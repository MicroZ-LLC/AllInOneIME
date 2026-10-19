import Foundation

/// Sends Settings → Assistant's request (`AIConfigPrompt`): on Apple's on-device model whenever it is available, whatever provider
/// the user chose (or whether one is set up at all), held to the answer's schema (guided generation) with tools that look
/// up apps, AWS profiles and language packs on this Mac; otherwise to the configured provider, the JSON described in the
/// instructions. Either way the answer is the same JSON, read by the same strict reader (`AIConfig.parse`). Values the
/// user hides from the AI are hidden as in any request (`Redaction`), and answers are kept like other conversions.
///
/// The on-device model's context is small (4096 tokens before macOS 27, 8192 since) and holds the schema and the tools
/// too: the request is fitted to it (`AIConfigFit`), counted by the model where it can tell.
public final class AIConfigService: Sendable {
    public struct Answer: Equatable, Sendable {
        /// The JSON as written (an on-device answer with its apps put back into its keys, `AIConfigPrompt.canonical`).
        public var text: String
        public var fromCache: Bool
        /// Answered by the on-device model.
        public var onDevice: Bool
        /// How many values were hidden from the AI.
        public var hidden: Int
    }

    /// Lookups the on-device model may call (FoundationModels tools); each answers in a few short lines, nothing secret.
    public struct Tools: Sendable {
        public var findApps: @Sendable (String) -> String
        public var awsProfiles: @Sendable () -> String
        public var languagePacks: @Sendable () -> String

        public init(findApps: @escaping @Sendable (String) -> String, awsProfiles: @escaping @Sendable () -> String,
                    languagePacks: @escaping @Sendable () -> String) {
            self.findApps = findApps
            self.awsProfiles = awsProfiles
            self.languagePacks = languagePacks
        }

        /// The tools as the backend takes them.
        var guided: [GuidedTool] {
            [
                GuidedTool(name: "findApps", description: "Finds installed apps whose name contains the text; returns their names and bundle IDs.",
                           arguments: [("name", "the app's name, as the user wrote it")]) { self.findApps($0["name"] ?? "") },
                GuidedTool(name: "awsProfiles", description: "Lists the AWS profiles on this Mac and their regions (names only).",
                           arguments: []) { _ in self.awsProfiles() },
                GuidedTool(name: "languagePacks", description: "Lists the input languages and whether their language pack is installed.",
                           arguments: []) { _ in self.languagePacks() },
            ]
        }
    }

    private let client: ChatClient
    private let loadCredentials: ChatClient.CredentialLoader
    private let loadKey: ChatClient.KeyLoader
    private let cache = Locked(initialState: LRUCache(capacity: 32))

    public init(client: ChatClient = ChatClient(),
                loadCredentials: @escaping ChatClient.CredentialLoader = { try await AWSCredentialResolver.shared.resolve(profile: $0) },
                loadKey: @escaping ChatClient.KeyLoader = { try APIKeys.load($0, for: $1) }) {
        self.client = client
        self.loadCredentials = loadCredentials
        self.loadKey = loadKey
    }

    /// Whether the request would go to the on-device model now.
    public var onDevice: Bool { client.apple.availability == .available }

    /// Gets the on-device model ready (it loads in a few seconds the first time): called as Settings → Assistant
    /// shows, so the request that follows doesn't wait for it. Nothing is sent.
    public func prewarm() {
        guard onDevice, let guided = client.apple as? any AppleGuidedBackend else { return }
        guided.prewarm()
    }

    /// The answer for `sentence` (keys already dropped), or with `turns`, the revised one after them. Throws the
    /// provider's error (no key, the network …), `AppleModelError.unavailable` when the user's provider is the on-device
    /// model and it can't be used, or `AppleModelError.contextExceeded` when the request can't be fitted to its context.
    public func ask(_ sentence: String, turns: [Refinement.Turn] = [], context: AIConfigPrompt.Context,
                    tools: Tools? = nil) async throws -> Answer {
        let onDevice = self.onDevice
        let config = context.config
        if !onDevice, config.provider == .apple { throw AppleModelError.unavailable(client.apple.availability) }
        // Whatever the caller did: a key typed into the sentence or a refine's line never goes out.
        let sentence = AIConfig.droppingKeys(sentence).text
        var turns = turns
        for index in turns.indices { turns[index].instruction = AIConfig.droppingKeys(turns[index].instruction).text }
        var redaction = Redaction(config.redaction)
        let sent = redaction?.hide(sentence) ?? sentence
        let lastMessage = Converter.hideTurns(turns, with: &redaction) ?? sent
        let hiding = Hiding(redaction: redaction, lastMessage: lastMessage)
        guard onDevice else { return try await askProvider(sentence, turns: turns, context: context, hiding: hiding) }
        return try await askOnDevice(sentence, turns: turns, context: context, tools: tools?.guided ?? [], hiding: hiding)
    }

    /// What the request hides from the AI (`Redaction`), and the last message as it goes.
    private struct Hiding {
        var redaction: Redaction?
        var lastMessage: String

        var count: Int { redaction?.count ?? 0 }
        func protect(_ request: ConverseRequest) -> ConverseRequest { redaction?.protect(request, sent: lastMessage) ?? request }
        func restore(_ text: String) -> String { redaction?.restore(text) ?? text }
    }

    /// The configured provider's answer, with every setting in the instructions.
    private func askProvider(_ sentence: String, turns: [Refinement.Turn], context: AIConfigPrompt.Context, hiding: Hiding) async throws -> Answer {
        let config = context.config
        let request = AIConfigPrompt.request(sentence, context: context, turns: turns)
        let key = "@config|\(AIConfigPrompt.version)|\(config.activeModel)|\(request.system.map(\.text).joined())|\(sentence)"
            + (turns.isEmpty ? "" : "|" + Prompt.turnsKey(turns))
        if let hit = cache.withLock({ $0.get(key) }), let text = hit.versions.first?.text {
            return Answer(text: text, fromCache: true, onDevice: false, hidden: hiding.count)
        }
        let text = try await collect(client.stream(hiding.protect(request), config: config, loadCredentials: loadCredentials, loadKey: loadKey))
        return keep(hiding.restore(text), key: key, Answer(text: "", fromCache: false, onDevice: false, hidden: hiding.count))
    }

    /// `answer` with `text`, kept under `key` unless it is empty.
    private func keep(_ text: String, key: String, _ answer: Answer) -> Answer {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cache.withLock { $0.set(key, ConversionResult(versions: [CandidateLine(text)])) }
        }
        var answer = answer
        answer.text = text
        return answer
    }

    /// The on-device model held to the schema with `tools`, the request fitted to its context (`fitted`), where the
    /// backend can (`AppleGuidedBackend`); else the JSON in the instructions, as for any provider. Throws
    /// `AppleModelError.contextExceeded` when the request can't be fitted.
    private func askOnDevice(_ sentence: String, turns: [Refinement.Turn], context: AIConfigPrompt.Context, tools: [GuidedTool],
                             hiding: Hiding) async throws -> Answer {
        var config = context.config
        config.provider = .apple
        // Tools and the schema take longer than a sentence: at least half a minute.
        let timeout = max(config.timeoutSeconds, 30)
        let answer = Answer(text: "", fromCache: false, onDevice: true, hidden: hiding.count)
        guard let guided = client.apple as? any AppleGuidedBackend else {
            let request = AIConfigPrompt.request(sentence, context: context, turns: turns, compact: true)
            let key = Self.onDeviceKey(request, sentence: sentence, turns: turns)
            if let hit = cache.withLock({ $0.get(key) }), let text = hit.versions.first?.text {
                return Answer(text: text, fromCache: true, onDevice: true, hidden: hiding.count)
            }
            let body = hiding.protect(request)
            let text = try await collect(AppleModel.stream(body, backend: client.apple, maxTokens: body.inferenceConfig.maxTokens ?? config.maxTokens,
                                                           timeout: timeout))
            return keep(hiding.restore(text), key: key, answer)
        }
        guard let fit = await Self.fitted(sentence, turns: turns, context: context, tools: tools, protect: hiding.protect, backend: guided)
        else { throw AppleModelError.contextExceeded }
        let key = Self.onDeviceKey(AIConfigPrompt.request(sentence, context: context, turns: fit.turns, compact: true, scope: fit.scope),
                                   sentence: sentence, turns: turns)
        if let hit = cache.withLock({ $0.get(key) }), let text = hit.versions.first?.text {
            return Answer(text: text, fromCache: true, onDevice: true, hidden: hiding.count)
        }
        let contextSize = guided.contextSize
        var request = AppleModel.request(from: fit.body, maxTokens: fit.body.inferenceConfig.maxTokens ?? config.maxTokens, contextSize: contextSize)
        // The answer gets what the context has left (the tools' calls their room): never less than its own room, never more
        // than the user's limit.
        let left = contextSize - fit.tokens - (fit.tools.isEmpty ? 0 : AIConfigFit.toolRoom)
        request.maximumResponseTokens = min(fit.body.inferenceConfig.maxTokens ?? config.maxTokens, max(left, AIConfigFit.answerRoom))
        let (sent, schema, tools) = (request, fit.schema, fit.tools)
        let json = try await Self.withTimeout(timeout) { try await guided.respond(to: sent, schema: schema, tools: tools) }
        return keep(hiding.restore(AIConfigPrompt.canonical(json)), key: key, answer)
    }

    /// The cache key of an on-device request.
    private static func onDeviceKey(_ request: ConverseRequest, sentence: String, turns: [Refinement.Turn]) -> String {
        "@config|\(AIConfigPrompt.version)|apple-guided|\(request.system.map(\.text).joined())|\(sentence)"
            + (turns.isEmpty ? "" : "|" + Prompt.turnsKey(turns))
    }

    /// The request fitted to `backend`'s context (`AIConfigFit.plan`), its size counted by the model where it can tell
    /// (else the estimate, on the high side); nil when it can't be fitted. The estimate is scaled by the model's count:
    /// down once when it leaves room to spare (more of the settings fit), up when the request came out too large.
    static func fitted(_ sentence: String, turns: [Refinement.Turn], context: AIConfigPrompt.Context, tools: [GuidedTool],
                       protect: (ConverseRequest) -> ConverseRequest, backend: any AppleGuidedBackend) async -> AIConfigFit? {
        let contextSize = backend.contextSize
        func plan(_ scale: Double) -> AIConfigFit? {
            AIConfigFit.plan(sentence, turns: turns, context: context, tools: tools, protect: protect, budget: contextSize,
                             contextSize: contextSize) { request, schema, tools in
                Int((Double(AIConfigFit.estimatedTokens(request, schema: schema, tools: tools)) * scale).rounded(.up))
            }
        }
        var scale = 1.0
        var fitted: AIConfigFit?
        for _ in 0..<3 {
            guard var fit = plan(scale) else { break }
            let request = AppleModel.request(from: fit.body, maxTokens: fit.body.inferenceConfig.maxTokens ?? context.config.maxTokens,
                                             contextSize: contextSize)
            guard let counted = await backend.tokenCount(of: request, schema: fit.schema, tools: fit.tools) else { return fitted ?? fit }
            let ratio = Double(counted) / Double(max(fit.tokens, 1))
            guard counted <= contextSize - AIConfigFit.reserve(tools: !fit.tools.isEmpty) else {
                scale *= ratio * 1.05
                continue
            }
            fit.tokens = counted
            let whole = fit.scope == .everything && fit.turns.count == turns.count
            guard fitted == nil, !whole, ratio < 0.95 else { return fit }
            fitted = fit
            scale *= ratio
        }
        return fitted
    }

    /// The text of a stream of events (the whole answer).
    private func collect(_ stream: AsyncThrowingStream<BedrockStreamEvent, Error>) async throws -> String {
        var text = ""
        for try await event in stream {
            switch event {
            case let .textDelta(delta): text += delta
            case let .textReplaced(whole): text = whole
            default: break
            }
            if text.utf8.count > 64 * 1024 { break }
        }
        try Task.checkCancellation()
        return text
    }

    public static func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AppleModelError.timedOut(seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }
}

/// A lookup the on-device model may call: its arguments are strings.
public struct GuidedTool: Sendable {
    public var name: String
    public var description: String
    public var arguments: [(name: String, description: String)]
    public var call: @Sendable ([String: String]) async -> String

    public init(name: String, description: String, arguments: [(name: String, description: String)],
                call: @escaping @Sendable ([String: String]) async -> String) {
        self.name = name
        self.description = description
        self.arguments = arguments
        self.call = call
    }
}

/// An on-device model that can be held to a schema and given tools (guided generation): the answer is JSON.
public protocol AppleGuidedBackend: AppleModelBackend {
    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String
    /// Loads the model ahead of a request (nothing is sent).
    func prewarm()
    /// The tokens `request` takes of the context with `schema` and `tools` (the instructions, the conversation, the
    /// prompt, the schema and the tools' definitions; not the answer), as the model counts them; nil where it can't tell
    /// (before macOS 26.4). Nothing is sent.
    func tokenCount(of request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async -> Int?
}

extension AppleGuidedBackend {
    public func prewarm() {}
    public func tokenCount(of request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async -> Int? { nil }
}
