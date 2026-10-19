import Foundation

/// Models offered in the settings (any Bedrock model / inference-profile ID, or another provider's model, can be typed
/// in). Measured on 10 everyday sentences with the default presets (2026-10).
public struct SuggestedModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let note: String

    public init(id: String, title: String, note: String) {
        self.id = id
        self.title = title
        self.note = note
    }

    /// The models offered for `provider` (any other ID can be typed in).
    public static func suggested(for provider: Provider) -> [SuggestedModel] {
        switch provider {
        case .bedrock: return all
        case .anthropic:
            return [
                SuggestedModel(id: "claude-haiku-5-5", title: "Claude Haiku 5.5", note: tr("默认：最快、最便宜", "Default: fastest, cheapest")),
                SuggestedModel(id: "claude-sonnet-5-5", title: "Claude Sonnet 5.5", note: tr("更用心，慢一些", "More careful, slower")),
                SuggestedModel(id: "claude-opus-5-5", title: "Claude Opus 5.5", note: tr("最强，最慢最贵", "Most capable, slowest, priciest")),
            ]
        case .gemini:
            return [SuggestedModel(id: "gemini-3.8-flash", title: "Gemini 3.8 Flash", note: tr("默认", "Default"))]
        case .hosted, .apple:
            return []  // the service (the system) picks the model
        case .openai:
            // OpenAI's own; for another service (DeepSeek, Qwen, Ollama, …), "Custom…" and its base URL.
            return [
                SuggestedModel(id: "gpt-6-luna", title: "GPT-6 Luna", note: tr("默认：最快、最省", "Default: fastest, cheapest", key: "models.openaiDefault")),
                SuggestedModel(id: "gpt-5.4-mini", title: "GPT-5.4 mini", note: tr("上一代 mini", "The previous mini")),
            ]
        }
    }

    /// Bedrock's.
    public static var all: [SuggestedModel] {
        [
            SuggestedModel(id: "us.anthropic.claude-haiku-4-5-20251001-v1:0", title: "Claude Haiku 4.5",
                           note: tr("推荐：约 1.3 秒，质量好", "Recommended: about 1.3 s, good quality")),
            SuggestedModel(id: "us.anthropic.claude-sonnet-4-6", title: "Claude Sonnet 4.6",
                           note: tr("约 2.2 秒，改写最用心", "About 2.2 s, the most careful rewrites")),
            SuggestedModel(id: "us.amazon.nova-2-lite-v1:0", title: "Amazon Nova 2 Lite",
                           note: tr("约 1 秒，最便宜，润色偏弱", "About 1 s, cheapest, weaker polish")),
        ]
    }
}
