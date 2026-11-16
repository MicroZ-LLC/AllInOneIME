import Foundation

/// A screenshot as it goes to an AI that can see images (`Provider.seesImages`, the question sessions' CLIs): pasted with
/// ⌃V into a question or a follow-up, made smaller on the device first (`TextRecognizer.downscaled`, its long side at
/// most `longSide` pixels). Its text, read on the device, always goes along too (`Prompt.withScreenshot`), so an AI that
/// can't see images still has it. Never kept: the recent questions only note that one was attached
/// (`QuestionHistory.Entry.hadScreenshot`).
public struct PromptImage: Hashable, Sendable {
    /// JPEG or PNG data.
    public var data: Data
    /// "image/jpeg" or "image/png".
    public var mediaType: String

    /// The longest side an image is sent with (Claude's own limit before it scales an image down).
    public static let longSide = 1568

    public init(data: Data, mediaType: String) {
        self.data = data
        self.mediaType = mediaType
    }

    public var base64: String { data.base64EncodedString() }

    /// "jpeg" or "png": Bedrock Converse's `format`.
    public var format: String { mediaType == "image/png" ? "png" : "jpeg" }

    /// A `data:` URL of it (OpenAI's `image_url`, Codex's `image` input).
    public var dataURL: String { "data:\(mediaType);base64,\(base64)" }

    /// A short, stable fingerprint of its bytes (FNV-1a), for a cache key: another screenshot is asked again.
    public var fingerprint: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

extension Provider {
    /// Whether this provider's model can be sent an image (`PromptImage`): the Claude API and Gemini, always; OpenAI's own
    /// API (another service behind an OpenAI-compatible URL may not take images, and fails the request if it doesn't);
    /// Bedrock's Claude and Nova models (not Nova Micro, text only); never AllInOneIME Cloud (its service takes text only)
    /// nor the on-device model.
    public func seesImages(model: String, baseURL: String?) -> Bool {
        switch self {
        case .anthropic, .gemini: return true
        case .openai:
            let host = baseURL.flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces))?.host?.lowercased() }
            return host == "api.openai.com"
        case .bedrock:
            let model = model.lowercased()
            return model.contains("anthropic.") || (model.contains("amazon.nova-") && !model.contains("nova-micro"))
        case .hosted, .apple: return false
        }
    }
}

extension QuestionConversation {
    /// A screenshot a round was asked with (`attachments`, by round: 0 the first question, 1 the first follow-up …).
    public struct Attachment: Hashable, Sendable {
        /// Its text, read on the device, which goes with the question ("" when it had none: then only the image goes,
        /// to an AI that can see it).
        public var text: String
        public var image: PromptImage?

        public init(text: String, image: PromptImage?) {
            self.text = text
            self.image = image
        }
    }

    /// A conversation asked with `attachments`.
    public init(web: SessionWeb, attachments: [Int: Attachment]) {
        self.init(web: web)
        self.attachments = attachments
    }
}

extension ClaudeSession {
    /// One user message with screenshots (`PromptImage`), as image blocks before the text (Claude Code's stream-json
    /// input passes them on to the model as they are, checked against a local server with 2.1.325); none: `userMessage(_:)`.
    public static func userMessage(_ text: String, images: [PromptImage]) -> Data {
        guard !images.isEmpty else { return userMessage(text) }
        let blocks: [[String: Any]] = images.map {
            ["type": "image", "source": ["type": "base64", "media_type": $0.mediaType, "data": $0.base64]]
        }
        return line(["type": "user", "message": ["role": "user", "content": blocks + [["type": "text", "text": text]]]])
    }
}

extension SessionDriver {
    /// A user message without a screenshot.
    func message(_ text: String) -> [Data] { message(text, images: []) }
}

extension Config {
    /// Whether the AI questions go to can see an image: a question session's CLI (Claude Code, Codex, Kiro CLI and
    /// Antigravity all take one), else the provider's model (`Provider.seesImages`).
    public var questionsSeeImages: Bool {
        if questionSessionAgent != nil { return true }
        let settings = settings(for: provider)
        return provider.seesImages(model: settings.model ?? "", baseURL: settings.baseURL)
    }
}

extension ScreenText {
    /// `recognize`, and the image made smaller for an AI that can see it (`PromptImage`; nil: none could be made). An
    /// image with no text in it (a chart, a photo) comes back without text, the image alone, where it could be made.
    static func recognizeWithImage(_ image: Data, with recognizer: any TextRecognizer,
                                   languages: [String]) async throws -> (ScreenText?, PromptImage?) {
        let small = recognizer.downscaled(image, longSide: PromptImage.longSide)
        do {
            return (try await recognize(image, with: recognizer, languages: languages), small)
        } catch Problem.noText where small != nil {
            return (nil, small)
        }
    }
}
