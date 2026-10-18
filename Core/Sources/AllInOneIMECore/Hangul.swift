import Foundation

/// The Korean pack's data (`hangul.json`): the jamo each key types in the 2-set (Dubeolsik) layout, and how jamo
/// make syllables. The rules that use it are the app's (`HangulComposer`); the pack holds no code.
public struct HangulTables: Codable, Equatable, Sendable {
    /// Jamo by the Mac's key code (as a string: "12": "ㅂ"), and with Shift where it differs (the tense consonants, ㅒ ㅖ).
    /// Other systems reach them by the key's usage (`jamo(usage:shift:)`).
    public var keys: [String: String]
    public var shiftKeys: [String: String]
    /// Initials, medials and finals in Unicode's order (a syllable is 0xAC00 + (initial × 21 + medial) × 28 + final,
    /// final 0 being none).
    public var initials: String
    public var medials: String
    public var finals: String
    /// Two jamo that make one: "ㅗㅏ": "ㅘ", "ㄹㄱ": "ㄺ".
    public var compoundVowels: [String: String]
    public var compoundFinals: [String: String]

    public static let fileName = "hangul.json"

    /// No tables (the Korean pack isn't installed): no key types a jamo.
    public static let none = HangulTables(keys: [:], shiftKeys: [:], initials: "", medials: "", finals: "", compoundVowels: [:], compoundFinals: [:])

    public static func load(from folder: URL) throws -> HangulTables {
        try JSONDecoder().decode(HangulTables.self, from: Data(contentsOf: folder.appendingPathComponent(fileName)))
    }

    /// The jamo of a key, by its position (the same on every Mac keyboard); nil for keys that aren't letters.
    public func jamo(keyCode: UInt16, shift: Bool) -> Character? {
        let key = String(keyCode)
        if shift, let tense = shiftKeys[key]?.first { return tense }
        return keys[key]?.first
    }

    /// The jamo of a key by its usage (the same key on every keyboard and system), through the Mac's code for that
    /// place (`MacKeyCodes`); nil for keys that aren't letters.
    public func jamo(usage: UInt16, shift: Bool) -> Character? {
        MacKeyCodes.code(usage: usage).flatMap { jamo(keyCode: $0, shift: shift) }
    }
}

/// Korean in the 2-set (Dubeolsik) layout: keys give jamo, which are composed into syllables as they are
/// typed (ㅎ ㅏ ㄴ → 한, then ㄱ ㅡ ㄹ → 글). The syllable being typed is shown marked (`preedit`); one that
/// is finished comes out of `feed`. The tables come from the Korean language pack.
public struct HangulComposer: Equatable, Sendable {
    public let tables: HangulTables
    /// The keys of each part of the syllable being typed, so ⌫ takes back one key at a time (ㄺ → ㄹ).
    private var initial: [Character] = []
    private var medial: [Character] = []
    private var final: [Character] = []
    private let initials: [Character], medials: [Character], finals: [Character]

    public init(tables: HangulTables) {
        self.tables = tables
        initials = Array(tables.initials)
        medials = Array(tables.medials)
        finals = Array(tables.finals)
    }

    public var isEmpty: Bool { initial.isEmpty && medial.isEmpty && final.isEmpty }

    /// The syllable (or lone jamo) being typed.
    public var preedit: String {
        guard let vowel = medialJamo(medial) else { return initial.first.map(String.init) ?? "" }
        guard let first = initial.first, let l = initials.firstIndex(of: first), let v = medials.firstIndex(of: vowel) else {
            return String(vowel)
        }
        let t = finalJamo(final).flatMap { finals.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        return String(UnicodeScalar(0xAC00 + (l * 21 + v) * 28 + t)!)
    }

    /// Takes one jamo (`HangulTables.jamo(usage:shift:)`); returns what is finished, if anything.
    public mutating func feed(_ jamo: Character) -> String {
        medials.contains(jamo) ? vowel(jamo) : consonant(jamo)
    }

    /// ⌫: the last key taken back. False when there is nothing to take back.
    public mutating func backspace() -> Bool {
        if !final.isEmpty { final.removeLast() } else if !medial.isEmpty { medial.removeLast() } else if !initial.isEmpty { initial.removeLast() } else { return false }
        return true
    }

    /// Everything typed so far, finished as it is.
    public mutating func flush() -> String {
        defer { (initial, medial, final) = ([], [], []) }
        return preedit
    }

    private mutating func consonant(_ c: Character) -> String {
        // No vowel yet (ㄱ then ㄴ), or a vowel on its own (ㅏ then ㄱ): what's there stays as it is.
        if medial.isEmpty || initial.isEmpty {
            let out = flush()
            initial = [c]
            return out
        }
        if final.isEmpty, finals.contains(c) {
            final = [c]
            return ""
        }
        if final.count == 1, finalJamo(final + [c]) != nil {
            final.append(c)
            return ""
        }
        let out = flush()
        initial = [c]
        return out
    }

    private mutating func vowel(_ v: Character) -> String {
        if final.isEmpty {
            if !medial.isEmpty {
                if medial.count == 1, medialJamo(medial + [v]) != nil {
                    medial.append(v)
                    return ""
                }
                let out = flush()
                medial = [v]
                return out
            }
            medial = [v]  // after a consonant (ㄱ ㅏ → 가), or on its own
            return ""
        }
        // A final consonant before a vowel starts the next syllable (한 ㅏ → 하나); of two, the second (닭 ㅏ → 달가).
        let moved = final.removeLast()
        let out = flush()
        initial = [moved]
        medial = [v]
        return out
    }

    private func medialJamo(_ keys: [Character]) -> Character? {
        keys.count == 1 ? keys[0] : keys.count == 2 ? tables.compoundVowels[String(keys)]?.first : nil
    }

    private func finalJamo(_ keys: [Character]) -> Character? {
        keys.count == 1 ? (finals.contains(keys[0]) ? keys[0] : nil) : keys.count == 2 ? tables.compoundFinals[String(keys)]?.first : nil
    }
}
