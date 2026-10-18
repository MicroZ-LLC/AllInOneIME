import Foundation
import Testing
@testable import AllInOneIMECore

struct HangulTests {
    /// Types `jamo` one by one: what came out, then what is still being typed.
    private func type(_ jamo: String) -> (committed: String, preedit: String) {
        var hangul = HangulComposer(tables: PackData.hangul)
        var out = ""
        for j in jamo { out += hangul.feed(j) }
        return (out, hangul.preedit)
    }

    @Test func composesSyllables() {
        #expect(type("ㅎㅏㄴㄱㅡㄹ") == ("한", "글"))
        #expect(type("ㅇㅏㄴㄴㅕㅇ") == ("안", "녕"))
    }

    @Test func aFinalBeforeAVowelStartsTheNextSyllable() {
        #expect(type("ㅎㅏㄴㅏ") == ("하", "나"))
        // Of two finals, the second moves: 닭 + ㅏ → 달가.
        #expect(type("ㄷㅏㄹㄱㅏ") == ("달", "가"))
    }

    @Test func compoundVowelsAndFinals() {
        #expect(type("ㄱㅗㅏ") == ("", "과"))
        #expect(type("ㅇㅡㅣ") == ("", "의"))
        #expect(type("ㄷㅏㄹㄱ") == ("", "닭"))
        #expect(type("ㅇㅓㅂㅅ") == ("", "없"))
    }

    @Test func loneJamo() {
        #expect(type("ㄱㄴ") == ("ㄱ", "ㄴ"))
        #expect(type("ㅏ") == ("", "ㅏ"))
        #expect(type("ㅏㄱ") == ("ㅏ", "ㄱ"))
        // ㄸ can't end a syllable: it starts the next one.
        #expect(type("ㅏㄸ").preedit == "ㄸ")
        #expect(type("ㄱㅏㄸ") == ("가", "ㄸ"))
    }

    private func back(_ hangul: inout HangulComposer) -> Bool { hangul.backspace() }

    @Test func backspaceTakesBackOneKey() {
        var hangul = HangulComposer(tables: PackData.hangul)
        for j in "ㄷㅏㄹㄱ" { _ = hangul.feed(j) }
        #expect(hangul.preedit == "닭")
        #expect(back(&hangul))
        #expect(hangul.preedit == "달")
        #expect(back(&hangul))
        #expect(hangul.preedit == "다")
        #expect(back(&hangul))
        #expect(hangul.preedit == "ㄷ")
        #expect(back(&hangul))
        #expect(hangul.isEmpty)
        #expect(!back(&hangul))
    }

    @Test func flushFinishesWhatIsTyped() {
        var hangul = HangulComposer(tables: PackData.hangul)
        for j in "ㅎㅏㄴ" { _ = hangul.feed(j) }
        #expect(hangul.flush() == "한")
        #expect(hangul.isEmpty)
    }

    /// The pack as 1.0.0 was: no usage maps.
    static var withoutUsageMaps: HangulTables {
        var tables = PackData.hangul
        (tables.usageKeys, tables.usageShiftKeys) = (nil, nil)
        return tables
    }

    @Test func eitherMapGivesTheSameJamo() throws {
        #expect(PackData.hangul.usageKeys?.count == PackData.hangul.keys.count)  // this checkout's pack has them (1.1.0)
        #expect(PackData.hangul.usageShiftKeys?.count == PackData.hangul.shiftKeys.count)
        let old = Self.withoutUsageMaps
        for entry in MacKeyCodes.entries {
            for shift in [false, true] {
                let byCode = PackData.hangul.jamo(keyCode: entry.code, shift: shift)
                #expect(PackData.hangul.jamo(usage: entry.usage, shift: shift) == byCode, "kVK \(entry.code)")
                #expect(old.jamo(usage: entry.usage, shift: shift) == byCode, "kVK \(entry.code)")
            }
        }
        #expect(PackData.hangul.jamo(usage: 0x14, shift: false) == "ㅂ")  // Q
        #expect(PackData.hangul.jamo(usage: 0x14, shift: true) == "ㅃ")
        #expect(PackData.hangul.jamo(usage: 0, shift: false) == nil)

        // A 1.0.0 pack's file (no usage maps) still reads, and 1.1.0's reads as the same tables plus the maps.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: PackData.folder
            .appendingPathComponent("ko-hangul").appendingPathComponent(HangulTables.fileName))) as! [String: Any]
        json["usageKeys"] = nil
        json["usageShiftKeys"] = nil
        let decoded = try JSONDecoder().decode(HangulTables.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == old)
    }

    /// Typed through the composer: the same syllables from either map, and from another system's events.
    @Test func eitherMapTypesTheSameText() {
        let codes: [Character: UInt16] = ["d": 0x02, "k": 0x28, "s": 0x01, "u": 0x20, "g": 0x05, "t": 0x11, "p": 0x23,
                                          "y": 0x10, "r": 0x0F, "m": 0x2E, "f": 0x03, "e": 0x0E]
        func run(_ tables: HangulTables, mac: Bool) -> ([String], String) {
            let c = Composer(engine: FakeEngine(), actionKey: .enter)
            c.hangulTables = tables
            c.inputLanguages = [.english, .korean]
            c.setInputMode(.korean)
            var out: [String] = []
            // 안녕하세요 한글 닭 까
            for letter in "dkssudgktpdy gksrmf ekfr Rk" {
                guard letter != " " else {
                    out += commits(c.handleKeyDown(KeyEvent(keyCode: VirtualKey.space, characters: " ")))
                    continue
                }
                let lower = Character(letter.lowercased()), shift = letter.isUppercase
                let code = codes[lower]!
                let event = mac
                    ? KeyEvent(keyCode: code, characters: String(letter), charactersIgnoringModifiers: String(lower),
                               modifiers: shift ? .shift : [])
                    : KeyEvent(key: .character, usage: MacKeyCodes.usage(code), characters: String(letter),
                               charactersIgnoringModifiers: String(lower), modifiers: shift ? .shift : [])
                out += commits(c.handleKeyDown(event))
            }
            return (out, c.markedText)
        }
        let expected = run(PackData.hangul, mac: true)
        #expect((expected.0.joined() + expected.1).replacingOccurrences(of: " ", with: "") == "안녕하세요한글닭까")
        #expect(run(Self.withoutUsageMaps, mac: true) == expected)
        #expect(run(PackData.hangul, mac: false) == expected)
        #expect(run(Self.withoutUsageMaps, mac: false) == expected)
    }

    @Test func keysOfThe2SetLayout() {
        // g k s → ㅎ ㅏ ㄴ; Shift for the tense consonants and ㅒ ㅖ; other keys are no jamo.
        #expect(PackData.hangul.jamo(keyCode: 5, shift: false) == "ㅎ")
        #expect(PackData.hangul.jamo(keyCode: 40, shift: false) == "ㅏ")
        #expect(PackData.hangul.jamo(keyCode: 15, shift: true) == "ㄲ")
        #expect(PackData.hangul.jamo(keyCode: 35, shift: true) == "ㅖ")
        #expect(PackData.hangul.jamo(keyCode: 40, shift: true) == "ㅏ")
        #expect(PackData.hangul.jamo(keyCode: 18, shift: false) == nil)  // 1
    }
}
