import Foundation
import NaturalLanguage

/// The languages the input method types (`Config.inputLanguages`), and the two its interface and its own
/// sentences are in (Chinese, English; `Config.uiLanguage` is one of those).
public enum Language: String, Codable, CaseIterable, Sendable {
    case chinese = "zh"
    case english = "en"
    case french = "fr"
    case korean = "ko"
    case hindi = "hi"

    /// Name shown in the UI.
    public var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "英文"
        case .french: return "法语"
        case .korean: return "韩语"
        case .hindi: return "印地语"
        }
    }

    /// Its name in English.
    public var englishName: String {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        case .french: return "French"
        case .korean: return "Korean"
        case .hindi: return "Hindi"
        }
    }

    /// Tag of the level-two lines in this language ("EN: …", "ZH: …").
    var tag: String { rawValue.uppercased() }

    /// Name used in the prompt.
    var promptName: String { self == .chinese ? "Simplified Chinese" : englishName }

    /// Typed in Latin letters, as English is (French too, with its own keyboard layout); not pinyin or Hangul.
    public var isLatin: Bool { self == .english || self == .french }

    /// One the interface can be in.
    public var isInterfaceLanguage: Bool { self == .chinese || self == .english }

    /// The keyboard layout it types with by default (`Config.keyboardLayouts`), nil for the system's own.
    public var defaultKeyboardLayout: String? { self == .french ? "com.apple.keylayout.French" : nil }

    /// The language a typed sentence is written in, by its letters: Chinese as soon as it contains Chinese characters,
    /// Korean in Hangul, Hindi in Devanagari. Latin letters are English, or French when `french` (one of the user's
    /// input languages: `Config.language(of:)`) and the words read as French.
    public static func of(_ text: String, french: Bool = false) -> Language {
        if text.containsHan { return .chinese }
        let scalars = text.unicodeScalars
        // Syllables, and jamo on their own (ㅋㅋ).
        if scalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }) { return .korean }
        if scalars.contains(where: { (0x0900...0x097F).contains($0.value) }) { return .hindi }
        guard french else { return .english }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .french]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .french ? .french : .english
    }
}

/// A language the three main versions (1–3) can be written in: the user adds the ones they want
/// (`Config.outputLanguages`) and picks one (`Config.outputLanguage`). Stored as its code ("en",
/// "zh", "ja", …), so config files from before keep working.
public struct OutputLanguage: Hashable, Codable, Sendable, Identifiable {
    /// A BCP-47 code: "en", "zh", "zh-Hant", "ja".
    public let code: String

    public init(_ code: String) { self.code = code }

    public init(_ language: Language) { code = language.rawValue }

    public var id: String { code }

    public static let english = OutputLanguage("en")
    public static let chinese = OutputLanguage("zh")

    /// The languages that can be added, in the order the settings offer them.
    public static let catalog: [OutputLanguage] = [
        "en", "zh", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "vi", "th", "id", "ar",
        "hi", "bn", "te", "mr", "ta", "gu", "kn", "ml", "pa", "ur",
    ].map(OutputLanguage.init)

    /// The languages of India (and Urdu), named here rather than by `Locale`, which says "Bangla" and
    /// varies by macOS version; and the script each is written in (`script`).
    static let indian: [String: (english: String, chinese: String, script: String)] = [
        "hi": ("Hindi", "印地语", "Devanagari"),
        "bn": ("Bengali", "孟加拉语", "Bengali"),
        "te": ("Telugu", "泰卢固语", "Telugu"),
        "mr": ("Marathi", "马拉地语", "Devanagari"),
        "ta": ("Tamil", "泰米尔语", "Tamil"),
        "gu": ("Gujarati", "古吉拉特语", "Gujarati"),
        "kn": ("Kannada", "卡纳达语", "Kannada"),
        "ml": ("Malayalam", "马拉雅拉姆语", "Malayalam"),
        "pa": ("Punjabi", "旁遮普语", "Gurmukhi"),
        "ur": ("Urdu", "乌尔都语", "Urdu (Perso-Arabic)"),
    ]

    /// The script its lines are written in, for languages often typed in Latin letters instead
    /// (Hinglish "aap kaise ho"): the answer is in the script, not romanized. Nil for the others.
    var script: String? { Self.indian[code]?.script }

    /// The first of the system's preferred languages (`Locale.preferredLanguages`, "zh-Hans-CN", "ja-JP") that
    /// isn't English and can be translated into: a new user's translation language. Traditional Chinese
    /// for "zh-Hant…" and Taiwan, Hong Kong, Macau. Nil when there is none (English alone, or only ones
    /// not offered).
    public static func preferred(from identifiers: [String]) -> OutputLanguage? {
        for identifier in identifiers {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
            guard let code = parts.first?.lowercased(), code != "en" else { continue }
            var candidate = code
            if code == "zh" {
                let traditional = parts.dropFirst().contains { ["hant", "tw", "hk", "mo"].contains($0.lowercased()) }
                candidate = traditional ? "zh-Hant" : "zh"
            }
            if let language = catalog.first(where: { $0.code == candidate }) { return language }
        }
        return nil
    }

    /// The input language this is, when it is one ("zh" is Chinese; "zh-Hant" is not: Chinese typed in
    /// pinyin comes out simplified, so it is translated into traditional).
    public var input: Language? { Language(rawValue: code) }

    /// Tag of the level-two lines in this language ("EN: …", "ZH: …", "ZHHANT: …").
    var tag: String { code.uppercased().filter(\.isLetter) }

    /// Name used in the prompt ("English", "Simplified Chinese", "Traditional Chinese", "Japanese").
    var promptName: String {
        switch code {
        case "zh": return "Simplified Chinese"
        case "zh-Hant": return "Traditional Chinese"
        default:
            if let indian = Self.indian[code] { return "\(indian.english) (\(indian.script) script)" }
            return Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
        }
    }

    /// Its name in the interface language: "英文", "日语" / "English", "Japanese".
    public func name(chinese: Bool) -> String {
        switch (code, chinese) {
        case ("en", true): return "英文"
        case ("zh", true): return "中文"
        case ("zh", false): return "Chinese"
        case ("zh-Hant", true): return "繁体中文"
        case ("zh-Hant", false): return "Traditional Chinese"
        default:
            if let indian = Self.indian[code] { return chinese ? indian.chinese : indian.english }
            return Locale(identifier: chinese ? "zh-Hans" : "en").localizedString(forIdentifier: code) ?? code
        }
    }

    public init(from decoder: Decoder) throws {
        code = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(code)
    }
}

extension Language {
    /// Whether a sentence in this language is polished (not translated) for `output`.
    public func matches(_ output: OutputLanguage) -> Bool { output.input == self }
}
