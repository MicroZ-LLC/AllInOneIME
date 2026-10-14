import Testing
@testable import AllInOneIMECore

struct HangulTests {
    /// Types `jamo` one by one: what came out, then what is still being typed.
    private func type(_ jamo: String) -> (committed: String, preedit: String) {
        var hangul = HangulComposer()
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
        var hangul = HangulComposer()
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
        var hangul = HangulComposer()
        for j in "ㅎㅏㄴ" { _ = hangul.feed(j) }
        #expect(hangul.flush() == "한")
        #expect(hangul.isEmpty)
    }

    @Test func keysOfThe2SetLayout() {
        // g k s → ㅎ ㅏ ㄴ; Shift for the tense consonants and ㅒ ㅖ; other keys are no jamo.
        #expect(HangulComposer.jamo(keyCode: 5, shift: false) == "ㅎ")
        #expect(HangulComposer.jamo(keyCode: 40, shift: false) == "ㅏ")
        #expect(HangulComposer.jamo(keyCode: 15, shift: true) == "ㄲ")
        #expect(HangulComposer.jamo(keyCode: 35, shift: true) == "ㅖ")
        #expect(HangulComposer.jamo(keyCode: 40, shift: true) == "ㅏ")
        #expect(HangulComposer.jamo(keyCode: 18, shift: false) == nil)  // 1
    }
}
