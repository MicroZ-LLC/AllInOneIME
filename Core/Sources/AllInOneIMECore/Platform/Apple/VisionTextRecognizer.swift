#if canImport(Vision)
import Foundation
import Vision

/// Vision's text recognition (`VNRecognizeTextRequest`), accurate and with language correction. On the device: the image
/// goes nowhere. The first request loads its models (seconds); `prepare` does that ahead of time.
public struct VisionTextRecognizer: TextRecognizer {
    public init() {}

    public func prepare(languages: [String]) async {
        // A blank image read once in the same languages: Vision's models for them are loaded for the next request (the
        // CJK ones and the Latin ones are apart). Nothing is found in it.
        guard let png = Self.blankPNG else { return }
        _ = try? await recognize(image: png, languages: languages)
    }

    public func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            // Vision's request blocks: on a queue of its own, not the async pool.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.read(image, languages: languages))
                } catch {
                    // Right after its models were first compiled, a request may fail once (an inference error): again.
                    do { continuation.resume(returning: try Self.read(image, languages: languages)) } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    static func read(_ image: Data, languages: [String]) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Only the languages Vision reads (it has no Hindi, say), by its own codes; none of them: its default.
        let wanted = visionCodes(languages, supported: (try? request.supportedRecognitionLanguages()) ?? [])
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

    /// BCP-47 codes (`TextRecognizer.recognize`) as Vision names them, in order, once each: the same code, else one of
    /// the same language ("vi-VN" → Vision's "vi-VT"); those it doesn't read are left out.
    static func visionCodes(_ languages: [String], supported: [String]) -> [String] {
        func base(_ code: String) -> String { String(code.lowercased().prefix { $0 != "-" && $0 != "_" }) }
        var seen = Set<String>()
        return languages.compactMap { code -> String? in
            let lower = code.lowercased()
            // Chinese by its script: zh-Hans and zh-Hant are different models.
            let match = supported.first { $0.lowercased() == lower }
                ?? (base(code) == "zh" ? nil : supported.first { base($0) == base(code) })
            return match.flatMap { seen.insert($0).inserted ? $0 : nil }
        }
    }

    /// A 128×64 white PNG.
    static let blankPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAIAAAABACAIAAABdtOgoAAAAbUlEQVR42u3RMQEAAAyDsPo3zWTsCRLI0muzAAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQHUVXqWSTHRRKwAAAABJRU5ErkJggg==")
}
#endif
