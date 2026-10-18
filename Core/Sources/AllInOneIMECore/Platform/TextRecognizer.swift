import Foundation

/// Reads the text in an image on the device (OCR), for a screenshot pasted into a draft (`ScreenText`): Vision on Apple
/// platforms (`VisionTextRecognizer`), Windows.Media.Ocr in the Windows shell later; elsewhere none
/// (`UnsupportedTextRecognizer`). The image never leaves the device: only the text read from it may be sent.
public protocol TextRecognizer: Sendable {
    /// Loads what recognizing needs (the first run of Vision takes seconds), so that the next `recognize` is quick. A
    /// draft calls it when the clipboard has an image (only its types are read for that).
    func prepare() async
    /// The lines of text in `image` (PNG or TIFF data), in any order; `languages`: the recognizer's language codes to
    /// read, the likeliest first ("zh-Hans", "en-US", "ja-JP"). Throws `ScreenText.Problem.unsupported` where images
    /// can't be read.
    func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine]
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
    public func prepare() async {}
    public func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] {
        throw ScreenText.Problem.unsupported
    }
}
