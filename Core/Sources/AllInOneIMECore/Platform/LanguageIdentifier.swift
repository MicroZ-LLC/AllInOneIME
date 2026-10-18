import Foundation

/// Tells the language a text is written in: NaturalLanguage on Apple platforms (`NaturalLanguageIdentifier`),
/// elsewhere its letters, stop words and accents (`HeuristicLanguageIdentifier`).
public protocol LanguageIdentifier: Sendable {
    /// The language `text` is most likely in, as a language code ("en", "fr", "zh-Hans", …), and how sure that is
    /// (0…1); nil when it can't tell. `candidates`: the codes to choose from (empty: any).
    func dominantLanguage(of text: String, among candidates: [String]) -> (code: String, confidence: Double)?
}

/// A guess from the text alone, for where there is no system language model: the script its letters are in (Han,
/// Hangul, Devanagari, Cyrillic, …), and for Latin letters the common words and accents of English, French, German,
/// Spanish, Italian and Portuguese.
public struct HeuristicLanguageIdentifier: LanguageIdentifier {
    public init() {}

    public func dominantLanguage(of text: String, among candidates: [String]) -> (code: String, confidence: Double)? {
        let allowed = Set(candidates.map(Self.base))
        func isAllowed(_ code: String) -> Bool { allowed.isEmpty || allowed.contains(Self.base(code)) }
        var counts: [String: Int] = [:]
        var letters = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            counts[Self.script(of: scalar), default: 0] += 1
        }
        guard letters > 0, let (script, count) = counts.max(by: { $0.value < $1.value }) else { return nil }
        let share = Double(count) / Double(letters)
        if script != "latin" {
            // Kana with Han is Japanese. Latin letters among them (a command, a name) don't make it less sure.
            let code = script == "zh" && (counts["ja"] ?? 0) > 0 ? "ja" : script
            let others = letters - (counts["latin"] ?? 0)
            return isAllowed(code) ? (code, Double(count) / Double(max(others, 1))) : nil
        }
        let scores = Self.latinScores(text).filter { isAllowed($0.key) }
        guard let best = scores.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) else {
            return nil
        }
        let total = scores.values.reduce(0, +)
        // No common word or accent at all: English, unsure.
        guard total > 0 else { return isAllowed("en") ? ("en", 0.5 * share) : (best.key, 0.3 * share) }
        return (best.key, share * best.value / total)
    }

    /// "zh-Hans" → "zh".
    static func base(_ code: String) -> String { String(code.prefix { $0 != "-" && $0 != "_" }).lowercased() }

    /// The language code a letter's script stands for ("latin" for Latin letters).
    static func script(of scalar: Unicode.Scalar) -> String {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF: return "ja"
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return "zh"
        case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F: return "ko"
        case 0x0900...0x097F: return "hi"
        case 0x0400...0x04FF: return "ru"
        case 0x0600...0x06FF, 0x0750...0x077F: return "ar"
        case 0x0590...0x05FF: return "he"
        case 0x0370...0x03FF: return "el"
        case 0x0E00...0x0E7F: return "th"
        case 0x0980...0x09FF: return "bn"
        case 0x0B80...0x0BFF: return "ta"
        default: return "latin"
        }
    }

    /// Each Latin language's evidence in `text`: its common words, two points each, and its own accents, one each.
    static func latinScores(_ text: String) -> [String: Double] {
        let words = text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
        var scores: [String: Double] = [:]
        for (code, list) in stopWords {
            scores[code] = Double(words.filter { list.contains($0) }.count * 2)
        }
        for character in text.lowercased() {
            for (code, marks) in accents where marks.contains(character) { scores[code, default: 0] += 1 }
        }
        return scores
    }

    static let stopWords: [String: Set<String>] = [
        "en": ["the", "and", "is", "are", "this", "that", "it", "to", "of", "you", "your", "i", "my", "we", "with", "for",
               "not", "have", "be", "was", "what", "do", "don't", "can", "need", "in", "on"],
        "fr": ["le", "la", "les", "et", "est", "je", "tu", "il", "elle", "nous", "vous", "ne", "pas", "un", "une", "des",
               "du", "de", "que", "qui", "me", "mon", "ma", "très", "bien", "avec", "pour", "c'est", "suis", "sens", "on",
               "se", "ce", "ça", "au", "aux", "mais", "dans", "sur", "oui", "non", "merci", "bonjour", "demain", "soir",
               "voit", "aujourd'hui", "fait", "faire", "peux", "veux"],
        "de": ["der", "die", "das", "und", "ist", "ich", "nicht", "ein", "eine", "mit", "zu", "sie", "es", "wir", "auf",
               "für", "mir", "sehr", "gut", "heute"],
        "es": ["el", "la", "los", "las", "y", "es", "yo", "no", "un", "una", "de", "que", "con", "para", "muy", "bien",
               "estoy", "hoy", "mi", "por"],
        "it": ["il", "la", "e", "è", "io", "non", "un", "una", "di", "che", "con", "per", "molto", "bene", "sono", "oggi",
               "mi", "lo"],
        "pt": ["o", "a", "os", "as", "e", "é", "eu", "não", "um", "uma", "de", "que", "com", "para", "muito", "bem",
               "estou", "hoje", "meu"],
    ]

    static let accents: [String: Set<Character>] = [
        "fr": ["é", "è", "ê", "ë", "à", "â", "ç", "î", "ï", "ô", "û", "ù", "œ"],
        "de": ["ä", "ö", "ü", "ß"],
        "es": ["ñ", "á", "í", "ó", "ú", "¿", "¡"],
        "it": ["ì", "ò"],
        "pt": ["ã", "õ", "ç", "á", "ê", "ô"],
    ]
}
