import Foundation

/// Apple's on-device model (macOS 26's Foundation Models framework) as a provider (`Provider.apple`): no key, no cost,
/// nothing leaves the Mac. The requests are the same as the other providers' (`Prompt`): the system prompt becomes the
/// session's instructions, the few-shot examples earlier turns of its transcript, the user's text the prompt; the answer
/// streams into `CandidateParser` as any other. The model is small: its context is about 4K tokens (8K on macOS 27),
/// and it speaks fewer languages (`SystemLanguageModel.supportedLanguages`).
public enum AppleModel {
    /// What `Config.settings(for: .apple).model` says (the menu's "Model:", the cache keys).
    public static let modelName = "apple-on-device"
    /// System Settings → Apple Intelligence & Siri, where it is turned on.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!

    /// The model on this Mac (`Platform.onDeviceModel`), or a stand-in that is never available (macOS before 26, or
    /// built without the framework).
    public static var system: any AppleModelBackend { Platform.current.onDeviceModel }

    /// Room kept for the answer when the examples are fitted into the context (`request`), in tokens.
    static let answerRoom = 1000
    /// Whatever the user set, the answer stops here: the model's context holds the request too.
    static let minimumAnswer = 256

    /// A rough count of the tokens in `text`, on the high side: a CJK character is about one token and three bytes
    /// in UTF-8; English is about four characters a token. Only used to leave few-shot examples out (`request`).
    static func estimatedTokens(_ text: String) -> Int { text.utf8.count / 3 + 4 }

    /// `body` as the on-device model takes it. The system prompt is the instructions, the user and assistant turns
    /// before the last user message the examples, that message the prompt. When they don't all fit in the context
    /// with room for the answer, examples are left out from the first (the rules and the format are in the
    /// instructions); a refine's conversation (the user's text, each answer and the instructions after it,
    /// `Prompt.refineMessage`) is never left out, only the few-shot examples before it. The answer's limit is the user's `maxTokens`, lowered to what the context has left (but not
    /// below `minimumAnswer`, unless the user's is lower still): never raised.
    public static func request(from body: ConverseRequest, maxTokens: Int, contextSize: Int) -> AppleModelRequest {
        let instructions = body.system.map(\.text).joined(separator: "\n\n")
        var examples: [AppleModelRequest.Turn] = []
        var pending: [String] = []
        for message in body.messages.dropLast() {
            let text = message.content.map(\.text).joined()
            if message.role == "assistant" {
                examples.append(.init(prompt: pending.joined(separator: "\n\n"), response: text))
                pending = []
            } else {
                pending.append(text)
            }
        }
        let prompt = (pending + body.messages.suffix(1).map { $0.content.map(\.text).joined() }).joined(separator: "\n\n")
        func size() -> Int {
            estimatedTokens(instructions) + estimatedTokens(prompt)
                + examples.reduce(0) { $0 + estimatedTokens($1.prompt) + estimatedTokens($1.response) }
        }
        // A refine: the turns from the user's text on are the conversation the last instruction is about.
        let isRefine: (String) -> Bool = { $0.hasPrefix(refineTag) }
        let conversation = isRefine(prompt) ? examples.reversed().prefix { isRefine($0.prompt) }.count + 1 : 0
        let room = min(maxTokens, answerRoom, contextSize / 3)
        while examples.count > conversation, size() + room > contextSize { examples.removeFirst() }
        let answer = min(maxTokens, max(minimumAnswer, contextSize - size()))
        return AppleModelRequest(instructions: instructions, examples: examples, prompt: prompt,
                                 temperature: body.inferenceConfig.temperature, maximumResponseTokens: answer)
    }

    /// Without the count of tokens generated (macOS 26 doesn't say), an answer whose estimated size is 90% of its limit
    /// or more may have been cut off there: it's reported as "max_tokens" (an unfinished last line is dropped, nothing
    /// is cached).
    static func possiblyCut(_ text: String, limit: Int) -> Bool {
        Double(estimatedOutputTokens(text)) >= 0.9 * Double(limit)
    }

    /// The tokens in an answer, as near as can be told without the model: about four ASCII characters a token, and
    /// a token for each other scalar (CJK, Hangul, Devanagari, …).
    static func estimatedOutputTokens(_ text: String) -> Int {
        let ascii = text.unicodeScalars.filter(\.isASCII).count
        return (ascii + 3) / 4 + text.unicodeScalars.count - ascii
    }

    /// Whether most of the letters in `text` are Latin (with accents, Vietnamese's too).
    static func mostlyLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter(\.properties.isAlphabetic)
        let latin = letters.filter { scalar in
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF,
                 0xFF21...0xFF3A, 0xFF41...0xFF5A: return true
            default: return false
            }
        }
        return latin.count * 2 > letters.count
    }

    /// The start of a refine's instruction (`Prompt.refineMessage`).
    static let refineTag = Prompt.refineMessage("").replacingOccurrences(of: "</refine>", with: "")

    /// What the user wrote in `prompt`, without the app's own wrapping: a selection's text without the instruction
    /// (`Prompt.editRequest`), a question and its selection without the tags (`Prompt.question`), a refine's
    /// instruction without its tags, else all of it; never the placeholders of values hidden from the model
    /// (`Redaction`), whose Latin letters would make text in another script look like English.
    static func usersText(_ prompt: String) -> String {
        let text = wrappedText(prompt)
        return placeholder.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                                    withTemplate: "")
    }

    /// A placeholder `Redaction` puts in place of a value: "[EMAIL_1]".
    static let placeholder = try! NSRegularExpression(
        pattern: #"\[(?:"# + Redaction.Kind.allCases.map(\.rawValue).joined(separator: "|") + #")_\d{1,3}\]"#)

    /// `usersText` before the placeholders go.
    private static func wrappedText(_ prompt: String) -> String {
        if let open = prompt.range(of: "<instruction>"), let start = prompt.range(of: "<text>", range: open.upperBound..<prompt.endIndex),
           let end = prompt.range(of: "</text>", options: .backwards), start.upperBound <= end.lowerBound {
            return String(prompt[start.upperBound..<end.lowerBound])
        }
        if prompt.hasPrefix(refineTag), prompt.hasSuffix("</refine>") {
            return String(prompt.dropFirst(refineTag.count).dropLast("</refine>".count))
        }
        return prompt.replacingOccurrences(of: "<selected_text>", with: "").replacingOccurrences(of: "</selected_text>", with: "")
    }

    /// Text in a language the model doesn't speak (`AppleModelBackend.supportedLanguages`, by language code), told
    /// with confidence: its code, else nil. Short (under 10 letters) or mixed text isn't judged, nor is text mostly in
    /// Latin letters (pinyin reads as Indonesian or Vietnamese): it goes to the model.
    static func unsupportedLanguage(of text: String, supported: Set<String>) -> String? {
        guard !supported.isEmpty, text.filter(\.isLetter).count >= 10, !mostlyLatin(text) else { return nil }
        guard let (language, confidence) = Platform.current.languages.dominantLanguage(of: text, among: []), confidence >= 0.8
        else { return nil }
        let code = String(language.prefix { $0 != "-" && $0 != "_" })
        return supported.contains(code) ? nil : code
    }

    /// Streams `body` from `backend` as the events of the other providers: text deltas, then the stop reason
    /// ("max_tokens" when the answer reached its limit). Throws `AppleModelError.unavailable` when the model isn't
    /// ready, and `.timedOut` when nothing new arrives for `timeout` seconds on `clock` (a test's moves by hand).
    public static func stream(_ body: ConverseRequest, backend: any AppleModelBackend, maxTokens: Int,
                              timeout: TimeInterval, clock: some Clock<Duration> = ContinuousClock())
        -> AsyncThrowingStream<BedrockStreamEvent, Error> {
        let availability = backend.availability
        guard availability == .available else {
            return AsyncThrowingStream { $0.finish(throwing: AppleModelError.unavailable(availability)) }
        }
        let request = request(from: body, maxTokens: maxTokens, contextSize: backend.contextSize)
        if unsupportedLanguage(of: usersText(request.prompt), supported: backend.supportedLanguages) != nil {
            return AsyncThrowingStream { $0.finish(throwing: AppleModelError.unsupportedLanguage) }
        }
        return AsyncThrowingStream { continuation in
            let lastActivity = Locked(initialState: clock.now)
            let task = Task {
                do {
                    var sent = String.UnicodeScalarView()
                    var text = ""
                    var outputTokens: Int?
                    for try await snapshot in backend.respond(to: request) {
                        lastActivity.withLock { $0 = clock.now }
                        text = snapshot.text
                        outputTokens = snapshot.outputTokens ?? outputTokens
                        // Each snapshot is the whole answer so far. Compared by Unicode scalars, not Characters: a
                        // snapshot can end inside a character (👍, then 👍🏽), and the deltas add up to it exactly.
                        let scalars = snapshot.text.unicodeScalars
                        if scalars.count >= sent.count, scalars.starts(with: sent) {
                            let delta = String.UnicodeScalarView(scalars.dropFirst(sent.count))
                            if !delta.isEmpty { continuation.yield(.textDelta(String(delta))) }
                        } else {
                            // Not a continuation of what went out (the model revised it): the whole answer, in its place.
                            continuation.yield(.textReplaced(snapshot.text))
                        }
                        sent = scalars
                    }
                    let cut = outputTokens.map { $0 >= request.maximumResponseTokens }
                        ?? possiblyCut(text, limit: request.maximumResponseTokens)
                    continuation.yield(.messageStop(reason: cut ? "max_tokens" : "end_turn"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Asleep until the timeout would be reached, then again until the new one if a snapshot came meanwhile.
            let watchdog = Task {
                while !Task.isCancelled {
                    let deadline = lastActivity.withLock { $0 }.advanced(by: .seconds(timeout))
                    if clock.now >= deadline {
                        task.cancel()
                        continuation.finish(throwing: AppleModelError.timedOut(timeout))
                        return
                    }
                    try? await clock.sleep(until: deadline, tolerance: nil)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                watchdog.cancel()
            }
        }
    }
}

/// Whether the on-device model can be used (`SystemLanguageModel.availability`).
public enum AppleModelAvailability: String, Equatable, Sendable {
    case available
    /// macOS before 26: the provider isn't offered.
    case unsupportedSystem
    /// This Mac can't run Apple Intelligence (an Intel Mac, say).
    case deviceNotEligible
    /// Turned off in System Settings → Apple Intelligence & Siri.
    case appleIntelligenceNotEnabled
    /// Still downloading, or not ready for another reason the system knows.
    case modelNotReady

    /// The provider is listed (greyed out with the reason when not available).
    public var isOffered: Bool { self != .unsupportedSystem }
}

/// One request to the on-device model.
public struct AppleModelRequest: Equatable, Sendable {
    /// A few-shot example: the user's text and the answer to it.
    public struct Turn: Equatable, Sendable {
        public var prompt: String
        public var response: String

        public init(prompt: String, response: String) {
            self.prompt = prompt
            self.response = response
        }
    }

    public var instructions: String
    public var examples: [Turn]
    public var prompt: String
    /// `Config.temperature` (nil: the model's own).
    public var temperature: Double?
    public var maximumResponseTokens: Int
}

/// The answer so far, as the session streams it.
public struct AppleModelSnapshot: Equatable, Sendable {
    /// The whole answer up to now (not a delta).
    public var text: String
    /// Tokens generated so far, when the system says (macOS 27).
    public var outputTokens: Int?

    public init(text: String, outputTokens: Int? = nil) {
        self.text = text
        self.outputTokens = outputTokens
    }
}

/// The model behind `Provider.apple`: Foundation Models on a Mac that has it, a stand-in in the tests.
public protocol AppleModelBackend: Sendable {
    var availability: AppleModelAvailability { get }
    /// The context in tokens: the request and the answer together.
    var contextSize: Int { get }
    /// The languages the model speaks, by language code ("en", "zh", …).
    var supportedLanguages: Set<String> { get }
    /// Snapshots of the answer as it grows; errors are `AppleModelError`, or `ProviderError.refused(.apple)`.
    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error>
}

public enum AppleModelError: Error, LocalizedError, Equatable {
    case unavailable(AppleModelAvailability)
    /// The text and the instructions don't fit in the model's small context.
    case contextExceeded
    /// The model doesn't speak the language of the text (or of the answer asked for).
    case unsupportedLanguage
    /// Another request is running, or the system is limiting them.
    case busy
    case timedOut(TimeInterval)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            switch reason {
            case .available: return nil
            case .unsupportedSystem: return "Apple Intelligence on this Mac needs macOS 26 or later"
            case .deviceNotEligible: return "This Mac can't run Apple Intelligence: choose another AI provider in the settings"
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is off: turn it on in System Settings → Apple Intelligence & Siri"
            case .modelNotReady: return "Apple Intelligence isn't ready yet (the model may still be downloading): try again later"
            }
        case .contextExceeded:
            return "Too long for Apple Intelligence on this Mac (its context is small): shorten the text or use another provider"
        case .unsupportedLanguage:
            return "Apple Intelligence on this Mac doesn't support this language: use another provider for it"
        case .busy: return "Apple Intelligence is busy: try again in a moment"
        case let .timedOut(seconds): return "Apple Intelligence didn't answer within \(Int(seconds)) seconds"
        case let .failed(detail): return "Apple Intelligence: \(detail)"
        }
    }
}

/// macOS before 26: never available.
struct UnsupportedBackend: AppleModelBackend {
    var availability: AppleModelAvailability { .unsupportedSystem }
    var contextSize: Int { 4096 }
    var supportedLanguages: Set<String> { [] }
    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: AppleModelError.unavailable(.unsupportedSystem)) }
    }
}
