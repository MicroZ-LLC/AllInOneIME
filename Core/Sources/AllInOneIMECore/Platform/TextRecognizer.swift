import Foundation

/// Reads the text in an image on the device (OCR), for a screenshot pasted into a draft (`ScreenText`): Vision on Apple
/// platforms (`VisionTextRecognizer`), Windows.Media.Ocr in the Windows shell later; elsewhere none
/// (`UnsupportedTextRecognizer`). The image itself goes only to an AI that can see it, made smaller first (`downscaled`).
public protocol TextRecognizer: Sendable {
    /// Loads what recognizing in `languages` needs (the first run of Vision takes seconds, and loads the models of the
    /// languages asked for), so that the next `recognize` in them is quick. A draft calls it once a command is picked
    /// with an image on the clipboard (only its types are read for that), in `ScreenText.languages`.
    func prepare(languages: [String]) async
    /// The lines of text in `image` (PNG or TIFF data), in any order; `languages`: BCP-47 codes of the languages to read,
    /// the likeliest first ("zh-Hans", "en-US", "ja-JP", `ScreenText.languages`), which each recognizer maps to its own
    /// (Vision's, Windows.Media.Ocr's). Throws `ScreenText.Problem.unsupported` where images can't be read.
    func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine]
    /// `image` (PNG or TIFF data) made small enough to send to an AI that can see it (`PromptImage`): its long side at
    /// most `longSide` pixels, as JPEG. Nil where images can't be made smaller here: the image isn't sent, its text is.
    func downscaled(_ image: Data, longSide: Int) -> PromptImage?
}

extension TextRecognizer {
    /// Nothing to load ahead of time.
    public func prepare(languages: [String]) async {}
    /// No image to send from here.
    public func downscaled(_ image: Data, longSide: Int) -> PromptImage? { nil }
}

/// A line of text read from an image.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    /// Where it is in the image, as fractions of its width and height (0…1), with the origin at the top left.
    public var box: CGRect
    /// How sure the recognizer is of it (0…1).
    public var confidence: Double

    public init(text: String, box: CGRect, confidence: Double) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

/// No text recognition on this platform: every image is `ScreenText.Problem.unsupported`.
public struct UnsupportedTextRecognizer: TextRecognizer {
    public init() {}
    public func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] {
        throw ScreenText.Problem.unsupported
    }
}
