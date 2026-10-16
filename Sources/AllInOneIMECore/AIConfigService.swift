import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Sends `@config`'s request (`AIConfigPrompt`): on Apple's on-device model whenever it is available, whatever provider
/// the user chose (or whether one is set up at all), held to the answer's schema (guided generation) with tools that look
/// up apps, AWS profiles and language packs on this Mac; otherwise to the configured provider, the JSON described in the
/// instructions. Either way the answer is the same JSON, read by the same strict reader (`AIConfig.parse`). Values the
/// user hides from the AI are hidden as in any request (`Redaction`), and answers are kept like other conversions.
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
    private let cache = OSAllocatedUnfairLock(initialState: LRUCache(capacity: 32))

    public init(client: ChatClient = ChatClient(),
                loadCredentials: @escaping ChatClient.CredentialLoader = { try await AWSCredentialResolver.shared.resolve(profile: $0) },
                loadKey: @escaping ChatClient.KeyLoader = { try APIKeys.load($0, for: $1) }) {
        self.client = client
        self.loadCredentials = loadCredentials
        self.loadKey = loadKey
    }

    /// Whether the request would go to the on-device model now.
    public var onDevice: Bool { client.apple.availability == .available }

    /// Gets the on-device model ready (it loads in a few seconds the first time): called as `@config` or `@doctor` is
    /// written, so the request that follows doesn't wait for it. Nothing is sent.
    public func prewarm() {
        guard onDevice, let guided = client.apple as? any AppleGuidedBackend else { return }
        guided.prewarm()
    }

    /// The answer for `sentence` (keys already dropped), or with `turns`, the revised one after them. Throws the
    /// provider's error (no key, the network …), or `AppleModelError.unavailable` when the user's provider is the
    /// on-device model and it can't be used.
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
        let hidden = redaction?.count ?? 0
        let request = AIConfigPrompt.request(sentence, context: context, turns: turns, compact: onDevice)
        let route = onDevice ? "apple-guided" : config.activeModel
        let key = "@config|\(AIConfigPrompt.version)|\(route)|\(request.system.map(\.text).joined())|\(sentence)"
            + (turns.isEmpty ? "" : "|" + Prompt.turnsKey(turns))
        if let hit = cache.withLock({ $0.get(key) }), let text = hit.versions.first?.text {
            return Answer(text: text, fromCache: true, onDevice: onDevice, hidden: hidden)
        }
        let body = redaction?.protect(request, sent: lastMessage) ?? request
        var text: String
        if onDevice {
            var apple = config
            apple.provider = .apple
            text = try await askOnDevice(body, schema: AIConfigPrompt.schema(context), tools: tools?.guided ?? [], config: apple)
        } else {
            text = try await collect(client.stream(body, config: config, loadCredentials: loadCredentials, loadKey: loadKey))
        }
        let answer = redaction?.restore(text) ?? text
        if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cache.withLock { $0.set(key, ConversionResult(versions: [CandidateLine(answer)])) }
        }
        return Answer(text: answer, fromCache: false, onDevice: onDevice, hidden: hidden)
    }

    /// The on-device model held to `schema` with `tools`, where the backend can (`AppleGuidedBackend`); else the JSON in
    /// the instructions, as for any provider.
    private func askOnDevice(_ body: ConverseRequest, schema: GuidedSchema, tools: [GuidedTool], config: Config) async throws -> String {
        let maxTokens = body.inferenceConfig.maxTokens ?? config.maxTokens
        // Tools and the schema take longer than a sentence: at least half a minute.
        let timeout = max(config.timeoutSeconds, 30)
        guard let guided = client.apple as? any AppleGuidedBackend else {
            return try await collect(AppleModel.stream(body, backend: client.apple, maxTokens: maxTokens, timeout: timeout))
        }
        let request = AppleModel.request(from: body, maxTokens: maxTokens, contextSize: client.apple.contextSize)
        let json = try await Self.withTimeout(timeout) { try await guided.respond(to: request, schema: schema, tools: tools) }
        return AIConfigPrompt.canonical(json)
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
}

extension AppleGuidedBackend {
    public func prewarm() {}
}

#if canImport(FoundationModels)
@available(macOS 26, *)
extension FoundationModelsBackend: AppleGuidedBackend {
    func prewarm() {
        LanguageModelSession(model: SystemLanguageModel.default).prewarm()
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        do {
            let generation = try GenerationSchema(root: GuidedSchemaBuilder().dynamic(schema), dependencies: [])
            // The instructions, then a refine's conversation so far (its earlier answers and instructions), as the
            // transcript; the last instruction (or the sentence) is the prompt.
            func text(_ content: String) -> [Transcript.Segment] { [.text(Transcript.TextSegment(content: content))] }
            var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: text(request.instructions), toolDefinitions: []))]
            for turn in request.examples {
                entries.append(.prompt(Transcript.Prompt(segments: text(turn.prompt))))
                entries.append(.response(Transcript.Response(assetIDs: [], segments: text(turn.response))))
            }
            let session = LanguageModelSession(model: SystemLanguageModel.default, tools: try tools.map(DynamicTool.init),
                                               transcript: Transcript(entries: entries))
            let options = GenerationOptions(temperature: request.temperature, maximumResponseTokens: request.maximumResponseTokens)
            let response = try await session.respond(to: request.prompt, schema: generation, options: options)
            return response.content.jsonString
        } catch {
            throw Self.mapped(error)
        }
    }
}

/// `GuidedSchema` as the framework's runtime schema. Names are made unique (one used twice gets a number).
@available(macOS 26, *)
private final class GuidedSchemaBuilder {
    private var names = Set<String>()

    private func unique(_ name: String) -> String {
        var candidate = name, n = 2
        while !names.insert(candidate).inserted {
            candidate = "\(name)\(n)"
            n += 1
        }
        return candidate
    }

    func dynamic(_ schema: GuidedSchema) -> DynamicGenerationSchema {
        switch schema {
        case let .object(name, properties):
            return DynamicGenerationSchema(name: unique(name), properties: properties.map {
                DynamicGenerationSchema.Property(name: $0.name, description: $0.description, schema: dynamic($0.schema),
                                                 isOptional: $0.optional)
            })
        case let .choice(name, choices):
            return DynamicGenerationSchema(name: unique(name), anyOf: choices.map(dynamic))
        case let .strings(name, values):
            return DynamicGenerationSchema(name: unique(name), anyOf: values)
        case let .array(item, min, max):
            return DynamicGenerationSchema(arrayOf: dynamic(item), minimumElements: min, maximumElements: max)
        case .string:
            return DynamicGenerationSchema(type: String.self)
        case .bool:
            return DynamicGenerationSchema(type: Bool.self)
        case let .number(min, max):
            return DynamicGenerationSchema(type: Double.self, guides: [.range(min...max)])
        case let .optional(inner):
            if #available(macOS 26.4, *) {
                return DynamicGenerationSchema(name: unique("Optional"), anyOf: [dynamic(inner), .null])
            }
            return dynamic(inner)
        }
    }
}

/// A `GuidedTool` as a FoundationModels tool, its arguments an object of strings.
@available(macOS 26, *)
private struct DynamicTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let tool: GuidedTool

    init(_ tool: GuidedTool) throws {
        self.tool = tool
        name = tool.name
        description = tool.description
        parameters = try GenerationSchema(root: DynamicGenerationSchema(name: tool.name + "Arguments", properties: tool.arguments.map {
            DynamicGenerationSchema.Property(name: $0.name, description: $0.description, schema: DynamicGenerationSchema(type: String.self))
        }), dependencies: [])
    }

    func call(arguments: GeneratedContent) async throws -> String {
        var values: [String: String] = [:]
        for argument in tool.arguments {
            values[argument.name] = try? arguments.value(String.self, forProperty: argument.name)
        }
        return await tool.call(values)
    }
}
#endif
