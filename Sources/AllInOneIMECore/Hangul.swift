import Foundation

/// Korean in the 2-set (Dubeolsik) layout: keys give jamo, which are composed into syllables as they are
/// typed (ㅎ ㅏ ㄴ → 한, then ㄱ ㅡ ㄹ → 글). The syllable being typed is shown marked (`preedit`); one that
/// is finished comes out (`Feed.committed`). Built in, no language pack: the composition is rules, not a dictionary.
public struct HangulComposer: Equatable, Sendable {
    /// The keys of each part of the syllable being typed, so ⌫ takes back one key at a time (ㄺ → ㄹ).
    private var initial: [Character] = []
    private var medial: [Character] = []
    private var final: [Character] = []

    public init() {}

    public var isEmpty: Bool { initial.isEmpty && medial.isEmpty && final.isEmpty }

    /// The syllable (or lone jamo) being typed.
    public var preedit: String {
        guard let vowel = Self.medial(medial) else { return initial.first.map(String.init) ?? "" }
        guard let first = initial.first else { return String(vowel) }
        let l = Self.initials.firstIndex(of: first)!, v = Self.medials.firstIndex(of: vowel)!
        let t = Self.final(final).flatMap { Self.finals.firstIndex(of: $0) } ?? 0
        return String(UnicodeScalar(0xAC00 + (l * 21 + v) * 28 + t)!)
    }

    /// Takes one jamo (`jamo(keyCode:shift:)`); returns what is finished, if anything.
    public mutating func feed(_ jamo: Character) -> String {
        Self.medials.contains(jamo) ? vowel(jamo) : consonant(jamo)
    }

    /// ⌫: the last key taken back. False when there is nothing to take back.
    public mutating func backspace() -> Bool {
        if !final.isEmpty { final.removeLast() } else if !medial.isEmpty { medial.removeLast() } else if !initial.isEmpty { initial.removeLast() } else { return false }
        return true
    }

    /// Everything typed so far, finished as it is.
    public mutating func flush() -> String {
        defer { self = HangulComposer() }
        return preedit
    }

    private mutating func consonant(_ c: Character) -> String {
        if medial.isEmpty {
            // ㄱ then ㄴ: two lone consonants (no syllable without a vowel).
            let out = flush()
            initial = [c]
            return out
        }
        if initial.isEmpty {
            // A vowel on its own (ㅏ) then a consonant: the vowel stays as it is.
            let out = flush()
            initial = [c]
            return out
        }
        if final.isEmpty, Self.finals.contains(c) {
            final = [c]
            return ""
        }
        if final.count == 1, Self.final(final + [c]) != nil {
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
                if medial.count == 1, Self.medial(medial + [v]) != nil {
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

    // MARK: Tables

    static let initials: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let medials: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// Finals, after "none" (index 0).
    static let finals: [Character] = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

    private static let compoundVowels: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    private static let compoundFinals: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ",
        "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]

    private static func medial(_ keys: [Character]) -> Character? {
        keys.count == 1 ? keys[0] : keys.count == 2 ? compoundVowels[String(keys)] : nil
    }

    private static func final(_ keys: [Character]) -> Character? {
        keys.count == 1 ? (finals.contains(keys[0]) && keys[0] != " " ? keys[0] : nil) : keys.count == 2 ? compoundFinals[String(keys)] : nil
    }

    // MARK: Keys

    /// The jamo of a key in the 2-set layout, by its position (the same on every Mac keyboard), with Shift for
    /// the tense consonants and ㅒ ㅖ. Nil for keys that aren't letters.
    public static func jamo(keyCode: UInt16, shift: Bool) -> Character? {
        if shift, let tense = shifted[keyCode] { return tense }
        return plain[keyCode]
    }

    private static let plain: [UInt16: Character] = [
        12: "ㅂ", 13: "ㅈ", 14: "ㄷ", 15: "ㄱ", 17: "ㅅ", 16: "ㅛ", 32: "ㅕ", 34: "ㅑ", 31: "ㅐ", 35: "ㅔ",
        0: "ㅁ", 1: "ㄴ", 2: "ㅇ", 3: "ㄹ", 5: "ㅎ", 4: "ㅗ", 38: "ㅓ", 40: "ㅏ", 37: "ㅣ",
        6: "ㅋ", 7: "ㅌ", 8: "ㅊ", 9: "ㅍ", 11: "ㅠ", 45: "ㅜ", 46: "ㅡ",
    ]
    private static let shifted: [UInt16: Character] = [12: "ㅃ", 13: "ㅉ", 14: "ㄸ", 15: "ㄲ", 17: "ㅆ", 31: "ㅒ", 35: "ㅖ"]
}
