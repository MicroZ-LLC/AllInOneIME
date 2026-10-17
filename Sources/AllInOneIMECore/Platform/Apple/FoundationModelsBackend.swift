#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// `SystemLanguageModel` with a fresh session per request: its transcript is the instructions and the examples.
@available(macOS 26, iOS 26, *)
struct FoundationModelsBackend: AppleModelBackend {
    var availability: AppleModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceNotEnabled
        case .unavailable: return .modelNotReady
        }
    }

    var contextSize: Int { SystemLanguageModel.default.contextSize }

    var supportedLanguages: Set<String> {
        Set(SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier })
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // The text is the user's own, to be rewritten or translated: the guardrails for transforming
                    // text, so a sentence that merely mentions something sensitive isn't refused.
                    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
                    func text(_ content: String) -> [Transcript.Segment] { [.text(Transcript.TextSegment(content: content))] }
                    var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: text(request.instructions),
                                                                                             toolDefinitions: []))]
                    for turn in request.examples {
                        entries.append(.prompt(Transcript.Prompt(segments: text(turn.prompt))))
                        entries.append(.response(Transcript.Response(assetIDs: [], segments: text(turn.response))))
                    }
                    let session = LanguageModelSession(model: model, tools: [], transcript: Transcript(entries: entries))
                    let options = GenerationOptions(temperature: request.temperature,
                                                    maximumResponseTokens: request.maximumResponseTokens)
                    for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                        var tokens: Int?
                        if #available(macOS 27, iOS 27, *) { tokens = snapshot.usage.output.totalTokenCount }
                        continuation.yield(AppleModelSnapshot(text: snapshot.content, outputTokens: tokens))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The framework's errors (macOS 26's `GenerationError`, macOS 27's `LanguageModelError`) as ours.
    static func mapped(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if #available(macOS 27, iOS 27, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: return AppleModelError.contextExceeded
                case .unsupportedLanguageOrLocale: return AppleModelError.unsupportedLanguage
                case .guardrailViolation, .refusal: return ProviderError.refused(.apple)
                case .rateLimited: return AppleModelError.busy
                default: return AppleModelError.failed(error.localizedDescription)
                }
            }
            if let error = error as? SystemLanguageModel.Error, case .assetsUnavailable = error {
                return AppleModelError.unavailable(.modelNotReady)
            }
            if error is LanguageModelSession.Error { return AppleModelError.busy }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return AppleModelError.contextExceeded
            case .unsupportedLanguageOrLocale: return AppleModelError.unsupportedLanguage
            case .guardrailViolation, .refusal: return ProviderError.refused(.apple)
            case .rateLimited, .concurrentRequests: return AppleModelError.busy
            case .assetsUnavailable: return AppleModelError.unavailable(.modelNotReady)
            default: return AppleModelError.failed(error.localizedDescription)
            }
        }
        return AppleModelError.failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
}

@available(macOS 26, iOS 26, *)
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
@available(macOS 26, iOS 26, *)
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
            if #available(macOS 26.4, iOS 26.4, *) {
                return DynamicGenerationSchema(name: unique("Optional"), anyOf: [dynamic(inner), .null])
            }
            return dynamic(inner)
        }
    }
}

/// A `GuidedTool` as a FoundationModels tool, its arguments an object of strings.
@available(macOS 26, iOS 26, *)
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
