import Foundation
import os

public struct ConversionUpdate: Equatable, Sendable {
    public var result: ConversionResult
    public var rawText: String
    public var isFinal: Bool
    /// Seconds since the conversion started.
    public var elapsed: TimeInterval
    /// Seconds until the first text delta arrived (nil until then, and for cache hits).
    public var firstTokenLatency: TimeInterval?
    public var fromCache: Bool
    /// How many values were hidden from the AI in the request (`Redaction`); 0 when none or hiding is off.
    public var hidden: Int = 0
    /// An `@question` conversation was too long for the model's context (the on-device model): earlier rounds were
    /// shortened to fit (`QuestionChat.fit`).
    public var shortened = false
}

/// Turns typed input into streamed `ConversionUpdate`s using the configured provider (`ChatClient`).
/// Config and credentials are re-read for every conversion, so edits apply without a restart.
public final class Converter: Sendable {
    public typealias ConfigLoader = @Sendable () throws -> Config
    public typealias CredentialLoader = @Sendable (_ profile: String) throws -> AWSSharedConfig.Resolved
    /// The user's jargon list for a config (only asked for when the jargon (黑话) style is on).
    public typealias JargonLoader = @Sendable (_ config: Config) -> [JargonEntry]

    private let client: ChatClient
    private let loadConfig: ConfigLoader
    private let loadCredentials: CredentialLoader
    private let loadKey: ChatClient.KeyLoader
    private let loadJargon: JargonLoader
    private let cache = OSAllocatedUnfairLock(initialState: LRUCache(capacity: 64))

    public init(
        client: BedrockClient = BedrockClient(),
        loadConfig: @escaping ConfigLoader = { try Config.load() },
        loadCredentials: @escaping CredentialLoader = { try AWSSharedConfig.load(profile: $0) },
        loadKey: @escaping ChatClient.KeyLoader = { try APIKeys.load($0, for: $1) },
        loadJargon: @escaping JargonLoader = { JargonLibrary.load(from: $0.jargonURL) },
        appleModel: any AppleModelBackend = AppleModel.system
    ) {
        self.client = ChatClient(bedrock: client, apple: appleModel)
        self.loadConfig = loadConfig
        self.loadCredentials = loadCredentials
        self.loadKey = loadKey
        self.loadJargon = loadJargon
    }

    /// `@improve`, `@translate` or both (`WritingMode`) on `input`; one request. `app`: the bundle id of the app it's
    /// typed in, whose profile may have its own rewrite styles, or no AI (`AppProfile`). With `turns`, a follow-up on
    /// results already shown (`Refinement`): the same lines again, revised as the last instruction asks.
    public func convert(_ input: String, mode: WritingMode = .both, app: String? = nil,
                        turns: [Refinement.Turn] = []) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(input, mode: mode, app: app, turns: turns, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ input: String, mode: WritingMode, app: String?, turns: [Refinement.Turn], continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        let started = ContinuousClock.now
        func elapsed() -> TimeInterval {
            let d = ContinuousClock.now - started
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }

        let config = try Self.settings(try loadConfig(), app: app)
        // Sensitive values hidden from the model (`Redaction`), put back in what it writes. A refine's turns (the
        // answers shown, the instructions) are hidden after the text, so its values keep the placeholders they had.
        var redaction = Redaction(config.redaction)
        let sent = redaction?.hide(input) ?? input
        let lastMessage = Self.hideTurns(turns, with: &redaction) ?? sent
        let hidden = redaction?.count ?? 0
        let plan = WritingPlan.make(mode, text: input, config: config)
        let output = plan.versions
        let jargon = (plan.styles.contains { $0.tag == RewriteStyle.jargonTag } ? loadJargon(config) : [])
            .filter { redaction?.allows($0) ?? true }
        let jargonKey = jargon.isEmpty ? "" : "j\(JargonLibrary.fingerprint(jargon))|"
        let key = "\(config.activeModel)|\(Prompt.version)|\(plan.key)|\(jargonKey)\(input)"
            + (turns.isEmpty ? "" : "|" + Prompt.turnsKey(turns))
        if let hit = cache.withLock({ $0.get(key) }) {
            continuation.yield(ConversionUpdate(
                result: hit, rawText: "", isFinal: true, elapsed: elapsed(),
                firstTokenLatency: nil, fromCache: true, hidden: hidden))
            return
        }

        let request = turns.isEmpty ? Prompt.request(for: input, mode: mode, config: config, jargon: jargon)
            : Prompt.refineRequest(for: input, mode: mode, config: config, jargon: jargon, turns: turns)
        let stream = client.stream(redaction?.protect(request, sent: lastMessage) ?? request, config: config,
                                   loadCredentials: loadCredentials, loadKey: loadKey)

        var text = ""
        var firstToken: TimeInterval?
        var stopReason: String?
        var lastResult = ConversionResult.empty
        for try await event in stream {
            if case let .messageStop(reason) = event { stopReason = reason }
            if case let .textDelta(delta) = event {
                text += delta
            } else if case let .textReplaced(whole) = event {
                text = whole
            } else {
                continue
            }
            if firstToken == nil { firstToken = elapsed() }
            // Far more than 3 sentences plus the rewrites; treat the rest as truncated.
            if text.utf8.count > Self.maxOutputBytes {
                stopReason = "max_tokens"
                break
            }
            let parsed = CandidateParser.parse(text, isFinal: false, output: output, translations: plan.translations)
            let result = redaction?.restore(parsed) ?? parsed
            // Most deltas only extend a line; skip updates that don't change what is shown.
            guard result != lastResult else { continue }
            lastResult = result
            continuation.yield(ConversionUpdate(
                result: result, rawText: text, isFinal: false, elapsed: elapsed(),
                firstTokenLatency: firstToken, fromCache: false, hidden: hidden))
        }
        try Task.checkCancellation()

        let parsed = Self.finalResult(text, stopReason: stopReason, output: output, translations: plan.translations)
        let final = redaction?.restore(parsed) ?? parsed
        if !final.isEmpty, stopReason != "max_tokens" {
            cache.withLock { $0.set(key, final) }
        }
        continuation.yield(ConversionUpdate(
            result: final, rawText: text, isFinal: true, elapsed: elapsed(),
            firstTokenLatency: firstToken, fromCache: false, hidden: hidden))
    }

    /// Runs a `.generate` command: the answer streams in as the single version of the result (`app` as for `convert`).
    /// `fresh`: asked again even if an answer is kept (a recent question asked again, `Composer.Effect.reask`); the new
    /// one is kept instead. With `turns`, a follow-up on the answer shown (`Refinement`): the whole answer again,
    /// revised as the last instruction asks.
    public func generate(_ command: Command, input: String, app: String? = nil, fresh: Bool = false,
                         turns: [Refinement.Turn] = []) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runCommand(command, input: input, app: app, fresh: fresh, turns: turns,
                                              continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runCommand(_ command: Command, input: String, app: String?, fresh: Bool = false, turns: [Refinement.Turn],
                            continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        let started = ContinuousClock.now
        func elapsed() -> TimeInterval {
            let d = ContinuousClock.now - started
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        let config = try Self.settings(try loadConfig(), app: app)
        // An @question conversation (`QuestionChat`): its turns are the answers and the questions after them, sent as
        // plain user and assistant turns, not as a refine.
        let chat = command == .question && !turns.isEmpty
        // Hidden from the model (`Redaction`): what the text holds, then what a custom command's own prompt does, then
        // a refine's turns (as for `convert`).
        var redaction = Redaction(config.redaction)
        let sent = redaction?.hide([input] + [command.custom?.prompt].compactMap { $0 }).first ?? input
        let lastMessage = Self.hideTurns(turns, with: &redaction, wrap: chat ? { $0 } : Prompt.refineMessage) ?? sent
        let hidden = redaction?.count ?? 0
        // A custom command's instruction is part of the key: editing it asks again.
        let key = "@\(command.name)|\(command.custom?.prompt ?? "")|\(config.activeModel)|\(Prompt.commandVersion)|\(input)"
            + (turns.isEmpty ? "" : "|" + (chat ? QuestionChat.turnsKey(turns) : Prompt.turnsKey(turns)))
        let request = chat ? QuestionChat.request(first: input, turns: turns, config: config)
            : turns.isEmpty ? Prompt.commandRequest(command, input: input, config: config)
            : Prompt.commandRefineRequest(command, input: input, config: config, turns: turns)
        var protected = redaction?.protect(request, sent: lastMessage) ?? request
        // The on-device model's context is small: a long conversation is fitted into it, older rounds shortened first
        // (said for an answer from the cache too).
        var shortened = false
        if chat, config.provider == .apple {
            (protected, shortened) = QuestionChat.fit(protected, contextSize: client.apple.contextSize,
                                                      maxTokens: protected.inferenceConfig.maxTokens ?? config.maxTokens)
        }
        if !fresh, let hit = cache.withLock({ $0.get(key) }) {
            continuation.yield(ConversionUpdate(
                result: hit, rawText: "", isFinal: true, elapsed: elapsed(), firstTokenLatency: nil, fromCache: true, hidden: hidden,
                shortened: shortened))
            return
        }
        let stream = client.stream(protected, config: config, loadCredentials: loadCredentials, loadKey: loadKey)
        func answer(_ text: String, complete: Bool) -> ConversionResult {
            let lines = Self.lines(text)
            return ConversionResult(versions: [CandidateLine(redaction?.restore(lines, complete: complete) ?? lines, isComplete: complete)])
        }
        var text = ""
        var firstToken: TimeInterval?
        var stopReason: String?
        for try await event in stream {
            if case let .messageStop(reason) = event { stopReason = reason }
            if case let .textDelta(delta) = event {
                text += delta
            } else if case let .textReplaced(whole) = event {
                text = whole
            } else {
                continue
            }
            if firstToken == nil { firstToken = elapsed() }
            if text.utf8.count > Self.maxOutputBytes { stopReason = "max_tokens"; break }
            continuation.yield(ConversionUpdate(
                result: answer(text, complete: false), rawText: text, isFinal: false, elapsed: elapsed(),
                firstTokenLatency: firstToken, fromCache: false, hidden: hidden, shortened: shortened))
        }
        try Task.checkCancellation()
        // Cut off at the token limit, the text still reads as an answer: keep it, but don't cache it.
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : answer(text, complete: true)
        if !final.isEmpty, stopReason != "max_tokens" { cache.withLock { $0.set(key, final) } }
        continuation.yield(ConversionUpdate(
            result: final, rawText: text, isFinal: true, elapsed: elapsed(), firstTokenLatency: firstToken, fromCache: false,
            hidden: hidden, shortened: shortened))
    }

    /// A refine's turns hidden (`Redaction.hide`) after the request's own texts, in the order sent: each answer's lines,
    /// then its instruction. A value already hidden keeps its placeholder; a new one (in an instruction) gets the next.
    /// The last message as it is sent (the last instruction, hidden, in `wrap`: a refine's tags, or as it is for an
    /// @question conversation's next question), or nil when there are no turns or hiding is off.
    static func hideTurns(_ turns: [Refinement.Turn], with redaction: inout Redaction?,
                          wrap: (String) -> String = Prompt.refineMessage) -> String? {
        guard !turns.isEmpty, redaction != nil else { return nil }
        let texts = turns.flatMap { Prompt.answerLines($0.answer) + [$0.instruction] }
        let sent = redaction!.hide(texts)
        return sent.last.map(wrap)
    }

    /// `config` as it applies in `app` (`Config.applying`); nothing is sent from an app with no AI.
    static func settings(_ config: Config, app: String?) throws -> Config {
        guard config.allowsAI(in: app) else { throw AppProfile.Refusal.noAI }
        return config.applying(app: app)
    }

    /// Model text as one line that is safe to insert anywhere, including a terminal: controls and
    /// line breaks become spaces (see `CandidateParser.stripControls`), runs of spaces collapse.
    static func oneLine(_ text: String) -> String {
        CandidateParser.stripControls(text).split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    /// A command's answer as text safe to insert, its line breaks kept (code, steps): controls go, tabs
    /// become 4 spaces, a Markdown code fence line the model wrote anyway goes, trailing spaces and runs
    /// of blank lines are trimmed; indentation stays. A terminal still gets it on one line (the controller).
    static func lines(_ text: String) -> String {
        let all = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .map { line -> String in
                let cleaned = CandidateParser.stripControls(line.replacingOccurrences(of: "\t", with: "    "))
                return String(cleaned.reversed().drop(while: { $0 == " " }).reversed())
            }
        var out: [String] = []
        for line in all where !(line.isEmpty && (out.last?.isEmpty ?? true)) { out.append(line) }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    /// When the model hit the token limit, its last line was cut off mid-sentence: drop it rather
    /// than offer a truncated sentence as a finished candidate.
    static let maxOutputBytes = 32 * 1024

    static func finalResult(_ text: String, stopReason: String?, output: OutputLanguage? = .english,
                            translations: [OutputLanguage] = []) -> ConversionResult {
        guard stopReason == "max_tokens" else {
            return CandidateParser.parse(text, isFinal: true, output: output, translations: translations)
        }
        var result = CandidateParser.parse(text, isFinal: false, output: output, translations: translations)
        result.versions = result.versions.filter { $0.isComplete }
        result.translations = result.translations.filter { $0.line.isComplete }
        result.rewrites = result.rewrites.filter { $0.line.isComplete }
        return result
    }
}

/// Tiny LRU keyed by string; recency tracked with an ordered array (capacity is small).
struct LRUCache: Sendable {
    let capacity: Int
    private var values: [String: ConversionResult] = [:]
    private var order: [String] = []

    init(capacity: Int) { self.capacity = capacity }

    mutating func get(_ key: String) -> ConversionResult? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    mutating func set(_ key: String, _ value: ConversionResult) {
        values[key] = value
        touch(key)
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
