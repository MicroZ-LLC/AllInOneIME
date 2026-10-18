#if canImport(NaturalLanguage)
import Foundation
import NaturalLanguage

/// The system's language recognizer.
public struct NaturalLanguageIdentifier: LanguageIdentifier {
    public init() {}

    public func dominantLanguage(of text: String, among candidates: [String]) -> (code: String, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        if !candidates.isEmpty { recognizer.languageConstraints = candidates.map(NLLanguage.init(rawValue:)) }
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return (language.rawValue, recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0)
    }
}
#endif
