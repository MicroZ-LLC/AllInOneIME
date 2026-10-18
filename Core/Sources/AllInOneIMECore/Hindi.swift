import Foundation

/// The Hindi pack's data (`hindi.json`): the Devanagari of the Latin letters as they sound (consonants; vowels as
/// a letter of their own and as a sign after a consonant), and common words as Hindi spells them. The rules that
/// use it are the app's (`HindiTransliteration`); the pack holds no code.
public struct HindiTables: Codable, Equatable, Sendable {
    public var consonants: [String: String]
    /// Latin → [letter on its own, sign after a consonant]: "aa": ["आ", "ा"], "a": ["अ", ""].
    public var vowels: [String: [String]]
    /// "M": "ं".
    public var anusvara: [String: String]
    public var virama: String
    public var danda: String
    /// The sign a word-final vowel takes after a consonant, as casual spelling means it: "a": "ा" (kya क्या).
    public var endings: [String: String]
    /// Casual spellings (lowercase) → the word.
    public var words: [String: String]

    public static let fileName = "hindi.json"

    public static func load(from folder: URL) throws -> HindiTables {
        try JSONDecoder().decode(HindiTables.self, from: Data(contentsOf: folder.appendingPathComponent(fileName)))
    }
}

/// Hindi typed in Latin letters, as most people write it in chats ("aap kaise ho"), turned into Devanagari
/// (आप कैसे हो). Common words come from the pack's list, spelled as Hindi writes them (करना, not कर्ना); any other
/// word is transliterated by rule, with and without the consonant clusters casual spelling leaves ambiguous.
public struct HindiTransliteration: Sendable {
    public let tables: HindiTables

    public init(tables: HindiTables) { self.tables = tables }

    /// What a word may be written as, the likeliest first (at most `limit`).
    public func candidates(_ latin: String, limit: Int = 5) -> [String] {
        guard let first = latin.first else { return [] }
        // A capital starting a sentence ("Main", "Theek") is no retroflex letter: only capitals inside a word are.
        let latin = first.isUppercase && latin.dropFirst().contains(where: \.isLowercase) ? first.lowercased() + latin.dropFirst() : latin
        var out: [String] = []
        if let word = tables.words[latin.lowercased()] { out.append(word) }
        for spelling in [transliterate(latin, clusters: true), transliterate(latin, clusters: false)] where !out.contains(spelling) {
            out.append(spelling)
        }
        return Array(out.prefix(limit))
    }

    /// Letter by letter. `clusters`: two consonants in a row are joined (क्या, प्यार); otherwise the first keeps its
    /// vowel (करना, समय), as Hindi often writes words whose "a" isn't said.
    public func transliterate(_ latin: String, clusters: Bool) -> String {
        let tokens = tokenize(latin)
        var out = ""
        var afterConsonant = false
        for (index, token) in tokens.enumerated() {
            let last = index == tokens.count - 1
            switch token {
            case let .consonant(letter):
                if afterConsonant && clusters { out += tables.virama }
                out += letter
                afterConsonant = true
            case let .vowel(latin):
                let forms = tables.vowels[latin] ?? [latin, latin]
                if afterConsonant {
                    out += last && index > 0 ? tables.endings[latin] ?? forms[1] : forms[1]
                } else {
                    out += forms[0]
                }
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
        case other(String)
    }

    /// The longest match first ("chh" before "ch" before "c"); capitals for the retroflex letters (T ट, D ड, N ण,
    /// Sh ष, R ड़), else a letter is read in lowercase.
    func tokenize(_ latin: String) -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(latin)
        while !rest.isEmpty {
            var matched = false
            for length in stride(from: min(3, rest.count), through: 1, by: -1) {
                let piece = String(rest.prefix(length))
                for key in [piece, piece.lowercased()] {
                    if let consonant = tables.consonants[key] {
                        tokens.append(.consonant(consonant))
                    } else if tables.vowels[key] != nil {
                        tokens.append(.vowel(key))
                    } else if let sign = tables.anusvara[key] {
                        tokens.append(.other(sign))
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
}

/// Level one in Hindi: the Latin letters of a word are composed, shown in Devanagari with the ways it may be
/// written (`HindiTransliteration.candidates`), from the Hindi pack's tables. Space inserts the first and a space, a digit another, Return the
/// letters as typed, "." the danda (।). In Latin mode (inside `@open`, code) letters go through as typed.
public final class HindiEngine: PinyinEngine {
    public let transliteration: HindiTransliteration
    private var letters = ""
    private var highlighted = 0
    private var ascii = false
    private var pendingCommit: String?

    public init(tables: HindiTables) { transliteration = HindiTransliteration(tables: tables) }

    public var language: Language { .hindi }

    private var options: [String] { transliteration.candidates(letters) }

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
            emit((composing ? pick(highlighted) : "") + transliteration.tables.danda)
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
