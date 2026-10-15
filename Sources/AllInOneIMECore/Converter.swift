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
        loadJargon: @escaping JargonLoader = { JargonLibrary.load(from: $0.jargonURL) }
    ) {
        self.client = ChatClient(bedrock: client)
        self.loadConfig = loadConfig
        self.loadCredentials = loadCredentials
        self.loadKey = loadKey
        self.loadJargon = loadJargon
    }

    /// `@improve`, `@translate` or both (`WritingMode`) on `input`; one request.
    public func convert(_ input: String, mode: WritingMode = .both) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(input, mode: mode, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ input: String, mode: WritingMode, continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        let started = ContinuousClock.now
        func elapsed() -> TimeInterval {
            let d = ContinuousClock.now - started
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }

        let config = try loadConfig()
        // Sensitive values hidden from the model (`Redaction`), put back in what it writes.
        var redaction = Redaction(config.redaction)
        let sent = redaction?.hide(input) ?? input
        let hidden = redaction?.count ?? 0
        let plan = WritingPlan.make(mode, text: input, config: config)
        let output = plan.versions
        let jargon = (plan.styles.contains { $0.tag == RewriteStyle.jargonTag } ? loadJargon(config) : [])
            .filter { redaction?.allows($0) ?? true }
        let jargonKey = jargon.isEmpty ? "" : "j\(JargonLibrary.fingerprint(jargon))|"
        let key = "\(config.activeModel)|\(Prompt.version)|\(plan.key)|\(jargonKey)\(input)"
        if let hit = cache.withLock({ $0.get(key) }) {
            continuation.yield(ConversionUpdate(
                result: hit, rawText: "", isFinal: true, elapsed: elapsed(),
                firstTokenLatency: nil, fromCache: true, hidden: hidden))
            return
        }

        let request = Prompt.request(for: input, mode: mode, config: config, jargon: jargon)
        let stream = client.stream(redaction?.protect(request, sent: sent) ?? request, config: config,
                                   loadCredentials: loadCredentials, loadKey: loadKey)

        var text = ""
        var firstToken: TimeInterval?
        var stopReason: String?
        var lastResult = ConversionResult.empty
        for try await event in stream {
            if case let .messageStop(reason) = event { stopReason = reason }
            guard case let .textDelta(delta) = event else { continue }
            if firstToken == nil { firstToken = elapsed() }
            text += delta
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

    /// Runs a `.generate` command: the answer streams in as the single version of the result.
    public func generate(_ command: Command, input: String) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runCommand(command, input: input, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runCommand(_ command: Command, input: String,
                            continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        let started = ContinuousClock.now
        func elapsed() -> TimeInterval {
            let d = ContinuousClock.now - started
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        let config = try loadConfig()
        // Hidden from the model (`Redaction`): what the text holds, then what a custom command's own prompt does.
        var redaction = Redaction(config.redaction)
        let sent = redaction?.hide([input] + [command.custom?.prompt].compactMap { $0 }).first ?? input
        let hidden = redaction?.count ?? 0
        // A custom command's instruction is part of the key: editing it asks again.
        let key = "@\(command.name)|\(command.custom?.prompt ?? "")|\(config.activeModel)|\(Prompt.commandVersion)|\(input)"
        if let hit = cache.withLock({ $0.get(key) }) {
            continuation.yield(ConversionUpdate(
                result: hit, rawText: "", isFinal: true, elapsed: elapsed(), firstTokenLatency: nil, fromCache: true, hidden: hidden))
            return
        }
        let request = Prompt.commandRequest(command, input: input, config: config)
        let stream = client.stream(redaction?.protect(request, sent: sent) ?? request, config: config,
                                   loadCredentials: loadCredentials, loadKey: loadKey)
        func answer(_ text: String, complete: Bool) -> ConversionResult {
            let lines = Self.lines(text)
            return ConversionResult(versions: [CandidateLine(redaction?.restore(lines, complete: complete) ?? lines, isComplete: complete)])
        }
        var text = ""
        var firstToken: TimeInterval?
        var stopReason: String?
        for try await event in stream {
            if case let .messageStop(reason) = event { stopReason = reason }
            guard case let .textDelta(delta) = event else { continue }
            if firstToken == nil { firstToken = elapsed() }
            text += delta
            if text.utf8.count > Self.maxOutputBytes { stopReason = "max_tokens"; break }
            continuation.yield(ConversionUpdate(
                result: answer(text, complete: false), rawText: text, isFinal: false, elapsed: elapsed(),
                firstTokenLatency: firstToken, fromCache: false, hidden: hidden))
        }
        try Task.checkCancellation()
        // Cut off at the token limit, the text still reads as an answer: keep it, but don't cache it.
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : answer(text, complete: true)
        if !final.isEmpty, stopReason != "max_tokens" { cache.withLock { $0.set(key, final) } }
        continuation.yield(ConversionUpdate(
            result: final, rawText: text, isFinal: true, elapsed: elapsed(), firstTokenLatency: firstToken, fromCache: false,
            hidden: hidden))
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
