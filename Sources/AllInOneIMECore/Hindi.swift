import Foundation

/// Hindi typed in Latin letters, as most people write it in chats ("aap kaise ho"), turned into Devanagari
/// (आप कैसे हो). Common words come from a list, spelled as Hindi writes them (करना, not कर्ना); any other word
/// is transliterated by rule, with and without the consonant clusters casual spelling leaves ambiguous.
public enum HindiTransliteration {
    /// What a word may be written as, the likeliest first (at most `limit`).
    public static func candidates(_ latin: String, limit: Int = 5) -> [String] {
        guard let first = latin.first else { return [] }
        // A capital starting a sentence ("Main", "Theek") is no retroflex letter: only capitals inside a word are.
        let latin = first.isUppercase && latin.dropFirst().contains(where: \.isLowercase) ? first.lowercased() + latin.dropFirst() : latin
        var out: [String] = []
        if let word = words[latin.lowercased()] { out.append(word) }
        for spelling in [transliterate(latin, clusters: true), transliterate(latin, clusters: false)] where !out.contains(spelling) {
            out.append(spelling)
        }
        return Array(out.prefix(limit))
    }

    /// Letter by letter. `clusters`: two consonants in a row are joined (क्या, प्यार); otherwise the first keeps its
    /// vowel (करना, समय), as Hindi often writes words whose "a" isn't said.
    public static func transliterate(_ latin: String, clusters: Bool) -> String {
        let tokens = tokenize(latin)
        var out = ""
        var afterConsonant = false
        for (index, token) in tokens.enumerated() {
            let last = index == tokens.count - 1
            switch token {
            case let .consonant(letter):
                if afterConsonant && clusters { out += virama }
                out += letter
                afterConsonant = true
            case let .vowel(latin):
                let forms = vowels[latin]!
                if afterConsonant {
                    // A word ends with the long vowel, as casual spelling means it: "kya" क्या, "nahi" नही.
                    if last, latin == "a", index > 0 { out += "ा" } else if last, latin == "i" { out += "ी" } else { out += forms.sign }
                } else {
                    out += forms.letter
                }
                afterConsonant = false
            case .anusvara:
                out += "ं"
                afterConsonant = false
            case let .other(text):
                out += text
                afterConsonant = false
            }
        }
        return out
    }

    enum Token: Equatable {
        case consonant(String)
        case vowel(String)
        case anusvara
        case other(String)
    }

    /// The longest match first ("chh" before "ch" before "c"); capitals for the retroflex letters (T ट, D ड, N ण,
    /// Sh ष, R ड़), else a letter is read in lowercase.
    static func tokenize(_ latin: String) -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(latin)
        while !rest.isEmpty {
            var matched = false
            for length in stride(from: min(3, rest.count), through: 1, by: -1) {
                let piece = String(rest.prefix(length))
                for key in [piece, piece.lowercased()] {
                    if let consonant = consonants[key] {
                        tokens.append(.consonant(consonant))
                    } else if vowels[key] != nil {
                        tokens.append(.vowel(key))
                    } else if key == "M" {
                        tokens.append(.anusvara)
                    } else {
                        continue
                    }
                    rest = rest.dropFirst(length)
                    matched = true
                    break
                }
                if matched { break }
            }
            if !matched {
                tokens.append(.other(String(rest.first!)))
                rest = rest.dropFirst()
            }
        }
        return tokens
    }

    static let virama = "्"

    static let consonants: [String: String] = [
        "kh": "ख", "k": "क", "gh": "घ", "g": "ग", "chh": "छ", "ch": "च", "c": "क", "jh": "झ", "j": "ज",
        "Th": "ठ", "T": "ट", "Dh": "ढ", "D": "ड", "N": "ण", "th": "थ", "t": "त", "dh": "ध", "d": "द", "n": "न",
        "ph": "फ", "f": "फ़", "p": "प", "bh": "भ", "b": "ब", "m": "म", "y": "य", "r": "र", "l": "ल", "v": "व",
        "w": "व", "sh": "श", "Sh": "ष", "s": "स", "h": "ह", "q": "क़", "z": "ज़", "R": "ड़", "x": "क्स",
    ]

    static let vowels: [String: (letter: String, sign: String)] = [
        "aa": ("आ", "ा"), "a": ("अ", ""), "ai": ("ऐ", "ै"), "au": ("औ", "ौ"), "ee": ("ई", "ी"), "ii": ("ई", "ी"),
        "i": ("इ", "ि"), "oo": ("ऊ", "ू"), "uu": ("ऊ", "ू"), "u": ("उ", "ु"), "e": ("ए", "े"), "o": ("ओ", "ो"),
        "A": ("आ", "ा"), "I": ("ई", "ी"), "U": ("ऊ", "ू"),
    ]

    /// Common words as they are spelled in Hindi (casual Latin spellings of each, lowercase).
    static let words: [String: String] = [
        "hai": "है", "hain": "हैं", "main": "मैं", "mai": "मैं", "nahi": "नहीं", "nahin": "नहीं", "kya": "क्या",
        "aap": "आप", "ap": "आप", "tum": "तुम", "tu": "तू", "hum": "हम", "kaise": "कैसे", "kaisa": "कैसा", "kaisi": "कैसी",
        "theek": "ठीक", "thik": "ठीक", "accha": "अच्छा", "achha": "अच्छा", "acha": "अच्छा", "acchi": "अच्छी", "achhi": "अच्छी",
        "bahut": "बहुत", "bohot": "बहुत", "kar": "कर", "karna": "करना", "karo": "करो", "karte": "करते", "karta": "करता",
        "karti": "करती", "kuch": "कुछ", "kuchh": "कुछ", "mera": "मेरा", "meri": "मेरी", "mere": "मेरे", "tera": "तेरा",
        "teri": "तेरी", "tumhara": "तुम्हारा", "tumhari": "तुम्हारी", "apna": "अपना", "apni": "अपनी", "apne": "अपने",
        "yeh": "यह", "ye": "ये", "woh": "वह", "wo": "वो", "vo": "वो", "ho": "हो", "hoon": "हूँ", "hun": "हूँ", "hu": "हूँ",
        "tha": "था", "thi": "थी", "the": "थे", "raha": "रहा", "rahi": "रही", "rahe": "रहे", "gaya": "गया", "gayi": "गई",
        "gaye": "गए", "ja": "जा", "jao": "जाओ", "jana": "जाना", "aao": "आओ", "aana": "आना", "kab": "कब", "kahan": "कहाँ",
        "kaha": "कहा", "kyun": "क्यों", "kyon": "क्यों", "kyu": "क्यों", "kaun": "कौन", "ab": "अब", "abhi": "अभी",
        "phir": "फिर", "fir": "फिर", "aur": "और", "or": "और", "ya": "या", "lekin": "लेकिन", "par": "पर", "se": "से",
        "ko": "को", "ka": "का", "ki": "की", "ke": "के", "mein": "में", "me": "में", "pe": "पे", "tak": "तक", "sab": "सब",
        "log": "लोग", "din": "दिन", "raat": "रात", "kal": "कल", "aaj": "आज", "ghar": "घर", "kaam": "काम", "pani": "पानी",
        "paani": "पानी", "khana": "खाना", "pyaar": "प्यार", "pyar": "प्यार", "dost": "दोस्त", "bhai": "भाई", "maa": "माँ",
        "ji": "जी", "haan": "हाँ", "ha": "हाँ", "na": "ना", "mat": "मत", "sakta": "सकता", "sakti": "सकती", "sakte": "सकते",
        "chahiye": "चाहिए", "dhanyavaad": "धन्यवाद", "dhanyawad": "धन्यवाद", "shukriya": "शुक्रिया", "namaste": "नमस्ते",
        "samajh": "समझ", "samay": "समय", "waqt": "वक़्त", "baat": "बात", "bura": "बुरा", "naya": "नया", "nayi": "नई",
        "purana": "पुराना", "bada": "बड़ा", "badi": "बड़ी", "chhota": "छोटा", "chota": "छोटा", "sahi": "सही", "galat": "ग़लत",
        "zyada": "ज़्यादा", "jyada": "ज़्यादा", "kam": "कम", "jaldi": "जल्दी", "dekh": "देख", "dekho": "देखो", "bol": "बोल",
        "bolo": "बोलो", "sun": "सुन", "suno": "सुनो", "padh": "पढ़", "likh": "लिख", "hindi": "हिंदी", "bharat": "भारत",
        "desh": "देश", "duniya": "दुनिया", "zindagi": "ज़िंदगी", "dil": "दिल", "khush": "ख़ुश", "sach": "सच", "paisa": "पैसा",
        "paise": "पैसे", "kitna": "कितना", "kitne": "कितने", "kitni": "कितनी", "ek": "एक", "do": "दो", "teen": "तीन",
        "char": "चार", "paanch": "पाँच", "bas": "बस", "chalo": "चलो", "chal": "चल", "de": "दे", "le": "ले", "lo": "लो",
        "diya": "दिया", "liya": "लिया", "kiya": "किया", "hua": "हुआ", "hui": "हुई", "hue": "हुए", "mujhe": "मुझे",
        "tumhe": "तुम्हें", "tumhein": "तुम्हें", "use": "उसे", "unhe": "उन्हें", "humein": "हमें", "hume": "हमें",
        "unka": "उनका", "uska": "उसका", "iska": "इसका", "kisi": "किसी", "koi": "कोई", "sabse": "सबसे", "bilkul": "बिलकुल",
        "zaroor": "ज़रूर", "jarur": "ज़रूर", "shayad": "शायद", "matlab": "मतलब", "bhi": "भी", "hi": "ही", "to": "तो",
        "aapka": "आपका", "aapki": "आपकी", "aapke": "आपके", "humara": "हमारा", "hamara": "हमारा", "sir": "सर",
    ]
}

/// Level one in Hindi: the Latin letters of a word are composed, shown in Devanagari with the ways it may be
/// written (`HindiTransliteration.candidates`). Space inserts the first and a space, a digit another, Return the
/// letters as typed, "." the danda (।). In Latin mode (inside `@open`, code) letters go through as typed.
public final class HindiEngine: PinyinEngine {
    private var letters = ""
    private var highlighted = 0
    private var ascii = false
    private var pendingCommit: String?

    public init() {}

    public var language: Language { .hindi }

    private var options: [String] { HindiTransliteration.candidates(letters) }

    public func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        if ascii || mask & RimeKey.releaseMask != 0 { return false }
        let composing = !letters.isEmpty
        switch keycode {
        case 0x41...0x5A, 0x61...0x7A:
            letters.append(Character(Unicode.Scalar(UInt8(keycode))))
            highlighted = 0
            return true
        case RimeKey.space where composing:
            emit(pick(highlighted) + " ")
            return true
        case 0x31...0x35 where composing:
            let index = Int(keycode - 0x31)
            guard options.indices.contains(index) else { return true }
            emit(pick(index))
            return true
        case RimeKey.returnKey where composing:
            emit(letters)
            letters = ""
            return true
        case RimeKey.backSpace where composing:
            letters.removeLast()
            highlighted = 0
            return true
        case RimeKey.escape where composing:
            letters = ""
            return true
        case RimeKey.down where composing, RimeKey.right where composing:
            highlighted = min(highlighted + 1, options.count - 1)
            return true
        case RimeKey.up where composing, RimeKey.left where composing:
            highlighted = max(highlighted - 1, 0)
            return true
        case 0x2E:  // "." is the danda
            emit((composing ? pick(highlighted) : "") + "।")
            return true
        default:
            // Any other key: the word goes in first, then the key does what it does.
            if composing { emit(pick(highlighted)) }
            return false
        }
    }

    private func pick(_ index: Int) -> String {
        let all = options
        let text = all.indices.contains(index) ? all[index] : letters
        letters = ""
        highlighted = 0
        return text
    }

    private func emit(_ text: String) { pendingCommit = (pendingCommit ?? "") + text }

    public func takeCommit() -> String? {
        defer { pendingCommit = nil }
        return pendingCommit
    }

    public func snapshot() -> EngineSnapshot {
        let all = options
        let shown = all.indices.contains(highlighted) ? all[highlighted] : letters
        return EngineSnapshot(
            isComposing: !letters.isEmpty, preedit: shown, cursor: shown.count,
            candidates: all.enumerated().map { EngineCandidate(label: "\($0.offset + 1)", text: $0.element) },
            highlighted: highlighted, isAsciiMode: ascii)
    }

    public func selectCandidate(onPage index: Int) -> Bool {
        guard !letters.isEmpty, options.indices.contains(index) else { return false }
        emit(pick(index))
        return true
    }

    public func commitComposition() -> String? {
        guard !letters.isEmpty else { return nil }
        return pick(highlighted)
    }

    public var rawInput: String { letters }
    public func clearComposition() { letters = ""; highlighted = 0 }
    public func setAsciiMode(_ on: Bool) { ascii = on }
}
