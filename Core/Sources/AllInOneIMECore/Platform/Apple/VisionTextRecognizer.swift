#if canImport(Vision)
import Foundation
import Vision

/// Vision's text recognition (`VNRecognizeTextRequest`), accurate and with language correction. On the device: the image
/// goes nowhere. The first request loads its models (seconds); `prepare` does that ahead of time.
public struct VisionTextRecognizer: TextRecognizer {
    public init() {}

    public func prepare() async {
        // A tiny blank image read once: Vision's models are loaded for the next request. Nothing is found in it.
        guard let png = Self.blankPNG else { return }
        _ = try? await recognize(image: png, languages: ["zh-Hans", "en-US"])
    }

    public func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            // Vision's request blocks: on a queue of its own, not the async pool.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.read(image, languages: languages))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func read(_ image: Data, languages: [String]) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Only the languages Vision reads (it has no Hindi, say); none of them: its default.
        let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
        let wanted = languages.filter { supported.contains($0) }
        if !wanted.isEmpty { request.recognitionLanguages = wanted }
        let handler = VNImageRequestHandler(data: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            // Vision's boxes have their origin at the bottom left.
            let box = observation.boundingBox
            return RecognizedLine(text: best.string, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
                                  confidence: Double(best.confidence))
        }
    }

    /// A 128×64 white PNG.
    static let blankPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAIAAAABACAIAAABdtOgoAAAAbUlEQVR42u3RMQEAAAyDsPo3zWTsCRLI0muzAAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQHUVXqWSTHRRKwAAAABJRU5ErkJggg==")
}
#endif
