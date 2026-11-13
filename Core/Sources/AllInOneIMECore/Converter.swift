import Foundation

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
    /// Said in the panel with the answer: why the dedicated Claude session didn't answer and the provider did
    /// (`ClaudeSessionError.fallbackNote`).
    public var note: String?
    /// Who answered an `@question`: a question session (`QuestionBackend.claudeSession` …) or the AI provider; nil for
    /// any other request.
    public var answeredBy: QuestionBackend?
    /// The session's agent conversation is new with this answer (`SessionReply.newConversation`).
    public var newConversation = false
    /// The tokens the session's turn used, as its CLI reports them (`SessionReply.tokens`).
    public var tokens: Int?
}

/// Turns typed input into streamed `ConversionUpdate`s using the configured provider (`ChatClient`).
/// Config and credentials are re-read for every conversion, so edits apply without a restart.
public final class Converter: Sendable {
    public typealias ConfigLoader = @Sendable () throws -> Config
    public typealias CredentialLoader = ChatClient.CredentialLoader
    /// The user's jargon list for a config (only asked for when the jargon (黑话) style is on).
    public typealias JargonLoader = @Sendable (_ config: Config) -> [JargonEntry]
    /// The text of AllInOneIME's user guide, as the shell ships it (`UserGuide`; nil: none). Only `@question` reads it,
    /// and only for a question about AllInOneIME.
    public typealias UserGuideLoader = @Sendable () -> String?

    // Internal, not private: Translate as You Type's request (TranslateMode.swift) goes through them too.
    let client: ChatClient
    let loadConfig: ConfigLoader
    let loadCredentials: CredentialLoader
    let loadKey: ChatClient.KeyLoader
    private let loadJargon: JargonLoader
    private let loadUserGuide: UserGuideLoader
    /// The user guide as a file (the shell's bundled copy; nil: none): what a coding agent an @question conversation goes
    /// on in is pointed to (`ChatHandoff.guideNote`), since it reads files itself.
    public let userGuideFile: URL?
    let cache = Locked(initialState: LRUCache(capacity: 64))
    /// The input method's own sessions (`ClaudeSessionManager`), one per agent (Claude Code, Codex, Antigravity, Kiro
    /// CLI): `@question` goes to the one `questionSession` says.
    public let questionSessions: [SessionAgent: ClaudeSessionManager]
    /// The Claude Code session, if any.
    public var claudeSession: ClaudeSessionManager? { questionSessions[.claude] }
    /// Whether this Mac has an AWS profile of that name: Bedrock is set up, for the fast fallback (`isReady`).
    let hasAWSProfile: @Sendable (String) -> Bool

    /// The session `@question` goes to with `config`: the CLI chosen as the AI (`Config.questionSessionAgent`), tried
    /// whatever it can do now; nil: the provider.
    public func questionSession(_ config: Config) -> ClaudeSessionManager? {
        config.questionSessionAgent.flatMap { questionSessions[$0] }
    }

    /// Where questions went when last looked at (`questionSessionsFollow`): the CLI chosen as the AI, or the provider.
    private let questionChoice = Locked<String?>(initialState: nil)

    /// Notes where `config` sends questions; whether that changed since the last note (false the first time).
    private func note(_ config: Config) -> Bool {
        let choice = config.questionSessionAgent?.rawValue ?? "provider"
        return questionChoice.withLock { last -> Bool in
            defer { last = choice }
            return last != nil && last != choice
        }
    }

    /// The sessions follow `config` (read anew: Settings, its settings document, the file edited by hand): when where
    /// questions go changed since it was last looked at (here, or as a question or its prewarm picked a session), every
    /// session's process but the one questions go to now ends at once, with what it was answering, rather than staying
    /// up for `ClaudeSessionManager.idleTimeout`. The first look only notes it (no session was started before).
    public func questionSessionsFollow(_ config: Config) {
        guard note(config) else { return }
        let current = config.questionSessionAgent
        for (agent, session) in questionSessions where agent != current { session.stop() }
    }

    /// Ends every question session's process and what it started, and a sign-in check running: the input method
    /// quits (an update, logging out). Asked to end, then killed after `grace` seconds
    /// (`ClaudeSessionManager.stop(_:grace:)`); returns once they're gone, or then.
    public func stopQuestionSessions(grace: TimeInterval = CommandRunner.stopGrace) {
        ClaudeSessionManager.stop(Array(questionSessions.values), grace: grace)
    }

    public init(
        client: BedrockClient = BedrockClient(),
        loadConfig: @escaping ConfigLoader = { try Config.load() },
        loadCredentials: @escaping CredentialLoader = { try await AWSCredentialResolver.shared.resolve(profile: $0) },
        loadKey: @escaping ChatClient.KeyLoader = { try APIKeys.load($0, for: $1) },
        loadJargon: @escaping JargonLoader = { JargonLibrary.load(from: $0.jargonURL) },
        loadUserGuide: @escaping UserGuideLoader = { nil },
        userGuideFile: URL? = nil,
        appleModel: any AppleModelBackend = AppleModel.system,
        appleClock: any Clock<Duration> = ContinuousClock(),
        claudeSession: ClaudeSessionManager? = nil,
        questionSessions: [SessionAgent: ClaudeSessionManager] = [:],
        hasAWSProfile: @escaping @Sendable (String) -> Bool = { AWSSharedConfig.profileNames().contains($0) }
    ) {
        self.client = ChatClient(bedrock: client, apple: appleModel, appleClock: appleClock)
        var sessions = questionSessions
        if let claudeSession { sessions[.claude] = claudeSession }
        self.questionSessions = sessions
        self.loadConfig = loadConfig
        self.loadCredentials = loadCredentials
        self.loadKey = loadKey
        self.loadJargon = loadJargon
        self.loadUserGuide = loadUserGuide
        self.userGuideFile = userGuideFile
        self.hasAWSProfile = hasAWSProfile
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
        func elapsed() -> TimeInterval { Self.seconds(since: started) }

        // The fast fallback with a CLI chosen as the AI (`FastRoute`).
        let route = try fastSettings(app: app)
        let config = route.config
        // Sensitive values hidden from the model (`Redaction`), put back in what it writes. A refine's turns (the
        // answers shown, the instructions) are hidden after the text, so its values keep the placeholders they had.
        let (redaction, (sent, lastMessage)) = redacting(route) { redaction -> (String, String) in
            let sent = redaction?.hide(input) ?? input
            return (sent, Self.hideTurns(turns, with: &redaction) ?? sent)
        }
        let hidden = redaction?.count ?? 0
        let plan = WritingPlan.make(mode, text: input, config: config)
        let output = plan.versions
        let jargon = (plan.styles.contains { $0.tag == RewriteStyle.jargonTag } ? loadJargon(config) : [])
            .filter { redaction?.allows($0) ?? true }
        let jargonKey = jargon.isEmpty ? "" : "j\(JargonLibrary.fingerprint(jargon))|"
        let key = "\(route.model)|\(Prompt.version)|\(plan.key)|\(jargonKey)\(input)"
            + (turns.isEmpty ? "" : "|" + Prompt.turnsKey(turns))
        if let hit = cache.withLock({ $0.get(key) }) {
            continuation.yield(ConversionUpdate(
                result: hit, rawText: "", isFinal: true, elapsed: elapsed(),
                firstTokenLatency: nil, fromCache: true, hidden: hidden))
            return
        }

        let request = turns.isEmpty ? Prompt.request(for: input, mode: mode, plan: plan, config: config, jargon: jargon)
            : Prompt.refineRequest(for: input, mode: mode, plan: plan, config: config, jargon: jargon, turns: turns)
        let stream = self.stream(redaction?.protect(request, sent: lastMessage) ?? request, route)

        var text = ""
        var firstToken: TimeInterval?
        var stopReason: String?
        var lastResult = ConversionResult.empty
        for try await event in stream {
            if case let .messageStop(reason) = event { stopReason = reason }
            guard event.apply(to: &text) else { continue }
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

    /// Runs a `.generate` command: the answer streams in as the single version of the result (`app` as for `convert`);
    /// `@reply`'s three replies as three versions (`runReply`, Reply.swift).
    /// `fresh`: asked again even if an answer is kept (a recent question asked again, `Composer.Effect.reask`); the new
    /// one is kept instead. With `turns`, a follow-up on the answer shown (`Refinement`): the whole answer again,
    /// revised as the last instruction asks. `conversation`: the `@question` conversation in the panel it is of, which a
    /// question session keeps in one conversation of its agent (`ClaudeSessionManager.request`); nil: the session's current
    /// one.
    public func generate(_ command: Command, input: String, app: String? = nil, fresh: Bool = false,
                         turns: [Refinement.Turn] = [],
                         conversation: QuestionConversation? = nil) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if command == .reply {
                        try await self.runReply(input: input, app: app, fresh: fresh, turns: turns, continuation: continuation)
                    } else {
                        try await self.runCommand(command, input: input, app: app, fresh: fresh, turns: turns,
                                                  conversation: conversation, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runCommand(_ command: Command, input: String, app: String?, fresh: Bool = false, turns: [Refinement.Turn],
                            conversation: QuestionConversation?,
                            continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        let started = ContinuousClock.now
        func elapsed() -> TimeInterval { Self.seconds(since: started) }
        // The fast fallback with a CLI chosen as the AI (`FastRoute`): what answers a question the CLI's session can't,
        // and any other command.
        let route = try fastSettings(app: app)
        let config = route.config
        // An @question conversation (`QuestionChat`): its turns are the answers and the questions after them, sent as
        // plain user and assistant turns, not as a refine.
        let chat = command == .question && !turns.isEmpty
        // The CLI chosen as the AI (`Config.questionSessionAgent`) answers a question, unless it can't (below); another one
        // chosen since the last look, the old one's process ends (`questionSessionsFollow`). No sign-in is looked at here.
        let session: ClaudeSessionManager?
        if command == .question {
            questionSessionsFollow(config)
            session = questionSession(config)
        } else {
            session = nil
        }
        // Given up (Esc) before it is asked: nothing goes to the agent (or the fast fallback).
        try Task.checkCancellation()
        // The panel's conversation in one conversation of the agent, a new one for each, with the web tools it may have:
        // the request's own from now on (`ClaudeSessionManager.Request`), whatever another field asks before it is sent;
        // in the queue now, so that what goes by its conversation (below) is of the one it goes into.
        let sessionRequest = session?.request(conversation)
        // The rounds of the conversation the session didn't see (the fast fallback answered them, they are from the saved
        // history, or the agent's conversation is new), told it with the question.
        let earlier = Array(QuestionChat.rounds(first: input, turns: turns, latest: nil).dropLast())
        let missing = sessionRequest.flatMap { session?.missing(earlier, for: $0) } ?? []
        // Hidden from the model (`Redaction`): what the text holds, then what a custom command's own prompt does, then
        // a refine's turns (as for `convert`). For the session, numbered on from its earlier questions (one long
        // conversation: a placeholder never stands for two values), and the rounds it didn't see too.
        func hide(_ redaction: inout Redaction?) -> (sent: String, last: String, missing: [QuestionChat.Round]) {
            let sent = redaction?.hide([input] + [command.custom?.prompt].compactMap { $0 }).first ?? input
            let last = Self.hideTurns(turns, with: &redaction, wrap: chat ? { $0 } : Prompt.refineMessage) ?? sent
            let rounds = missing.map { round in
                QuestionChat.Round(question: redaction?.hide(round.question) ?? round.question,
                                   answer: redaction?.hide(round.answer) ?? round.answer)
            }
            return (sent, last, rounds)
        }
        var redaction: Redaction?
        let texts: (sent: String, last: String, missing: [QuestionChat.Round])
        if let session, let sessionRequest {
            (redaction, texts) = session.redacting(config.redaction, for: sessionRequest, hide)
        } else {
            (redaction, texts) = redacting(route, hide)
        }
        let (sent, lastMessage) = (texts.sent, texts.last)
        let hidden = redaction?.count ?? 0
        // A custom command's instruction is part of the key: editing it asks again.
        let key = "@\(command.name)|\(command.custom?.prompt ?? "")|\(route.model)|\(Prompt.commandVersion)|\(input)"
            + (turns.isEmpty ? "" : "|" + (chat ? QuestionChat.turnsKey(turns) : Prompt.turnsKey(turns)))
        // A question about AllInOneIME: the parts of its user guide that answer it best go with it (`UserGuide`); the
        // request for any other question is as it always was.
        let questions = chat ? QuestionChat.rounds(first: input, turns: turns, latest: nil).map(\.question) : [input]
        let guide = command == .question ? guideExcerpts(questions) : nil
        // The dedicated session: only the question asked now goes in (its conversation has the rounds before), redacted
        // as it would be for the provider, the guide's excerpts after it as they would go to the provider; not cached (the
        // conversation's earlier rounds are part of the answer). Should it not answer at all (not installed, signed out, its
        // limit, open in Terminal), the fast fallback does, and the panel says why; with none, the question fails so.
        var note: String?
        if let session, let sessionRequest {
            // The question typed last (`lastMessage` is the first one when nothing is hidden).
            let question = ClaudeSession.message(turns.last.map { redaction == nil ? $0.instruction : lastMessage } ?? sent,
                                                 after: texts.missing)
            let message = ClaudeSession.message(hidden > 0 ? question + "\n\n(" + Redaction.note + ")" : question, guide: guide)
            do {
                try await runInSession(session, sessionRequest, message: message, redaction: redaction, hidden: hidden,
                                       started: started, told: missing.map(\.answer), continuation: continuation)
                return
            } catch let error as ClaudeSessionError where error.fallsBack {
                guard !route.slow else { throw ClaudeSessionError.failed(error.description(for: session.backend.agent)) }
                note = error.fallbackNote(for: session.backend.agent)
            }
        }
        let request = chat ? QuestionChat.request(first: input, turns: turns, config: config, guide: guide)
            : turns.isEmpty ? Prompt.commandRequest(command, input: input, config: config, guide: guide)
            : Prompt.commandRefineRequest(command, input: input, config: config, turns: turns)
        var protected = redaction?.protect(request, sent: lastMessage) ?? request
        // The on-device model's context is small: a long conversation is fitted into it, older rounds shortened first
        // (said for an answer from the cache too).
        var shortened = false
        if chat, config.provider == .apple {
            (protected, shortened) = QuestionChat.fit(protected, contextSize: client.apple.contextSize,
                                                      maxTokens: protected.inferenceConfig.maxTokens ?? config.maxTokens)
        }
        // An @question's answer says it's the provider's.
        let answeredBy: QuestionBackend? = command == .question ? .provider : nil
        if !fresh, let hit = cache.withLock({ $0.get(key) }) {
            continuation.yield(ConversionUpdate(
                result: hit, rawText: "", isFinal: true, elapsed: elapsed(), firstTokenLatency: nil, fromCache: true, hidden: hidden,
                shortened: shortened, note: note, answeredBy: answeredBy))
            return
        }
        let stream = self.stream(protected, route)
        func answer(_ text: String, complete: Bool) -> ConversionResult {
            let lines = Self.lines(text)
            return ConversionResult(versions: [CandidateLine(redaction?.restore(lines, complete: complete) ?? lines, isComplete: complete)])
        }
        var text = ""
        var firstToken: TimeInterval?
        var stopReason: String?
        for try await event in stream {
            if case let .messageStop(reason) = event { stopReason = reason }
            guard event.apply(to: &text) else { continue }
            if firstToken == nil { firstToken = elapsed() }
            if text.utf8.count > Self.maxOutputBytes { stopReason = "max_tokens"; break }
            continuation.yield(ConversionUpdate(
                result: answer(text, complete: false), rawText: text, isFinal: false, elapsed: elapsed(),
                firstTokenLatency: firstToken, fromCache: false, hidden: hidden, shortened: shortened, note: note,
                answeredBy: answeredBy))
        }
        try Task.checkCancellation()
        // Cut off at the token limit, the text still reads as an answer: keep it, but don't cache it.
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : answer(text, complete: true)
        if !final.isEmpty, stopReason != "max_tokens" { cache.withLock { $0.set(key, final) } }
        continuation.yield(ConversionUpdate(
            result: final, rawText: text, isFinal: true, elapsed: elapsed(), firstTokenLatency: firstToken, fromCache: false,
            hidden: hidden, shortened: shortened, note: note, answeredBy: answeredBy))
    }

    /// `@question` answered by the dedicated Claude session, as its `request` (`ClaudeSessionManager.Request.answer`):
    /// `message` is the question as sent (redacted); the answer streams in as the provider's does, its placeholders put
    /// back, with which session it is, whether its conversation is new and the tokens it used (the panel's footer).
    /// Throws what the session failed with: a `ClaudeSessionError` that `fallsBack` only before any of the answer came.
    /// Answered, the answer and `told` (the earlier rounds' answers sent with the question) are in the session
    /// (`ClaudeSessionManager.remember`).
    private func runInSession(_ session: ClaudeSessionManager, _ request: ClaudeSessionManager.Request, message: String,
                              redaction: Redaction?, hidden: Int, started: ContinuousClock.Instant, told: [String],
                              continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        func elapsed() -> TimeInterval { Self.seconds(since: started) }
        func answer(_ text: String, complete: Bool) -> ConversionResult {
            let lines = Self.lines(text)
            return ConversionResult(versions: [CandidateLine(redaction?.restore(lines, complete: complete) ?? lines, isComplete: complete)])
        }
        var text = ""
        var firstToken: TimeInterval?
        var latest = SessionReply(text: "")
        let answeredBy = QuestionBackend(session.backend.agent)
        try Task.checkCancellation()  // given up: not sent
        do {
            for try await reply in request.answer(message) {
                (text, latest) = (reply.text, reply)
                if firstToken == nil { firstToken = elapsed() }
                if text.utf8.count > Self.maxOutputBytes { break }
                continuation.yield(ConversionUpdate(
                    result: answer(text, complete: false), rawText: text, isFinal: false, elapsed: elapsed(),
                    firstTokenLatency: firstToken, fromCache: false, hidden: hidden, answeredBy: answeredBy,
                    newConversation: reply.newConversation, tokens: reply.tokens))
            }
        } catch let error as ClaudeSessionError where firstToken != nil && error.fallsBack {
            throw ClaudeSessionError.failed(error.description(for: session.backend.agent))  // part of the answer is in: no other answers now
        }
        try Task.checkCancellation()
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : answer(text, complete: true)
        session.remember(answers: told + [final.versions.first?.text ?? ""], for: request)
        continuation.yield(ConversionUpdate(
            result: final, rawText: text, isFinal: true, elapsed: elapsed(), firstTokenLatency: firstToken, fromCache: false,
            hidden: hidden, answeredBy: answeredBy, newConversation: latest.newConversation, tokens: latest.tokens))
    }

    /// The excerpts of the user guide for an @question conversation's `questions` (`UserGuide.excerpts`): nil when none
    /// is about AllInOneIME, or there is no guide (it's read only for one that is).
    private func guideExcerpts(_ questions: [String]) -> String? {
        let asked = questions.map(UserGuide.question(in:)).joined(separator: "\n")
        guard UserGuide.isAbout(asked), let text = loadUserGuide() else { return nil }
        return UserGuide(text: text).excerpts(for: asked)
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

    /// The seconds from `start` until now (a conversion's `elapsed`, `firstTokenLatency`).
    static func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
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
