import Foundation

// MARK: - Screenshots asked about (`QuestionConversation.attachments`)

/// A question's screenshots: each round's text goes with its question (`Prompt.withScreenshot`, the first question's put
/// there by the composer), and its image, made smaller (`PromptImage`), only to an AI that can see it: the provider's
/// model (`Provider.seesImages`), or a question session's CLI (`SessionDriver.message(_:images:)`). Never when the words to
/// hide took something out (`Redaction`): the image would show it.
extension Converter {
    /// `turns` with each follow-up's screenshot text (rounds 1 on; round 0's is in the first question already).
    static func withScreenshots(_ turns: [Refinement.Turn], _ conversation: QuestionConversation?) -> [Refinement.Turn] {
        guard let attachments = conversation?.attachments, !attachments.isEmpty else { return turns }
        return turns.enumerated().map { index, turn in
            guard let attachment = attachments[index + 1] else { return turn }
            var turn = turn
            turn.instruction = Prompt.withScreenshot(turn.instruction, attachment.text)
            return turn
        }
    }

    /// How many values were hidden (`Redaction`), and the images to send of `conversation` (`images`).
    static func hiddenAndImages(_ redaction: Redaction?, _ conversation: QuestionConversation?) -> (Int, [Int: PromptImage]) {
        let hidden = redaction?.count ?? 0
        return (hidden, images(conversation, hidden: hidden))
    }

    /// The images to send, by round: none when anything was hidden from the model.
    static func images(_ conversation: QuestionConversation?, hidden: Int) -> [Int: PromptImage] {
        guard hidden == 0 else { return [:] }
        return conversation?.attachments.compactMapValues(\.image) ?? [:]
    }

    /// `request` with `images` on the user messages of their rounds (the n-th user message is round n), for a provider
    /// whose model can see them; as it is for one that can't.
    static func attaching(_ images: [Int: PromptImage], to request: ConverseRequest, config: Config) -> ConverseRequest {
        let provider = config.provider, settings = config.settings(for: provider)
        guard !images.isEmpty, provider.seesImages(model: settings.model ?? "", baseURL: settings.baseURL) else { return request }
        var request = request
        var round = 0
        for index in request.messages.indices where request.messages[index].role == "user" {
            if let image = images[round] { request.messages[index].images = [image] }
            round += 1
        }
        return request
    }

    /// The part of the cache key the images sent are: another screenshot is asked again.
    static func imagesKey(_ images: [Int: PromptImage]) -> String {
        images.isEmpty ? "" : "|images:" + images.keys.sorted().compactMap { images[$0]?.fingerprint }.joined(separator: ",")
    }
}

// MARK: - A screenshot in each provider's request (`HTTPProviders.makeRequest`)

extension HTTPProviders {
    /// The Claude API's message: its images (`PromptImage`) as image blocks before the text; none: the text alone.
    static func anthropicMessage(_ message: ConverseRequest.Message) -> [String: Any] {
        let text = message.content.map(\.text).joined()
        guard !message.images.isEmpty else { return ["role": message.role, "content": text] }
        let images: [[String: Any]] = message.images.map {
            ["type": "image", "source": ["type": "base64", "media_type": $0.mediaType, "data": $0.base64]]
        }
        return ["role": message.role, "content": images + [["type": "text", "text": text]]]
    }

    /// Gemini's parts: its images as `inline_data` before the text.
    static func geminiParts(_ message: ConverseRequest.Message) -> [[String: Any]] {
        message.images.map { ["inline_data": ["mime_type": $0.mediaType, "data": $0.base64]] } + message.content.map { ["text": $0.text] }
    }

    /// An OpenAI-compatible message: its images as `image_url` data URLs before the text, only where the service takes
    /// them (`images`: OpenAI's own API, `Provider.seesImages`); else the text alone.
    static func openAIMessage(_ message: ConverseRequest.Message, images sendsImages: Bool) -> [String: Any] {
        let text = message.content.map(\.text).joined()
        guard sendsImages, !message.images.isEmpty else { return ["role": message.role, "content": text] }
        let images: [[String: Any]] = message.images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
        return ["role": message.role, "content": images + [["type": "text", "text": text]]]
    }
}
