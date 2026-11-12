import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A follow-up typed in Zhuyin (`PinyinScheme.zhuyin`) after an answer (an @question conversation's next question, a
/// refine instruction): its first key goes to the engine when it starts a syllable, a digit (1 ㄅ) or a mark (- ㄦ) as a
/// letter does, as in level one: never taken as an answer's number, nor sent back to the command's draft (which hid the
/// conversation). A tone's digit with nothing typed starts nothing (it is as before); in full pinyin digits still pick.
@Suite(MacTerms())
struct FollowUpZhuyinTests {
    /// `FakeEngine` with Zhuyin's other keys as rime-bopomofo has them: those of its initials that aren't letters (its
    /// `speller/initials`: 1 ㄅ, 2 ㄉ, 5 ㄓ, 8 ㄚ, 9 ㄞ, 0 ㄢ, , ㄝ, . ㄡ, / ㄥ, ; ㄤ, - ㄦ) start a syllable or go on with one;
    /// a tone (3 4 6 7) only goes on with one.
    final class ZhuyinKeysEngine: PinyinEngine {
        let base = FakeEngine()

        func processKey(_ keycode: Int32, mask: Int32) -> Bool {
            if !base.ascii, let scalar = Unicode.Scalar(UInt32(keycode)) {
                let c = Character(scalar)
                if "125890,./;-".contains(c) || !base.input.isEmpty && "3467".contains(c) {
                    base.keys.append((keycode, mask))
                    base.input.append(c)
                    return true
                }
            }
            return base.processKey(keycode, mask: mask)
        }

        func takeCommit() -> String? { base.takeCommit() }
        func snapshot() -> EngineSnapshot { base.snapshot() }
        func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
        func commitComposition() -> String? { base.commitComposition() }
        var rawInput: String { base.rawInput }
        func clearComposition() { base.clearComposition() }
        func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
    }

    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
    }

    /// "@question what is rust" ⏎, answered: a conversation, its answer the row numbered 1; Chinese input on, typed in
    /// `scheme`.
    func conversation(_ scheme: PinyinScheme = .zhuyin) throws -> (Composer, ZhuyinKeysEngine) {
        let engine = ZhuyinKeysEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.remembersQuestions = false
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type("what is rust", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("A language.")]), isFinal: true, id: 1)
        try #require(c.isQuestionChat && c.canRefine && c.choices.contains { $0.label == "1" })
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        try #require(c.inputLanguage == .chinese)
        c.pinyinScheme = scheme
        return (c, engine)
    }

    @Test func aDigitOrMarkThatStartsASyllableStartsTheNextQuestion() throws {
        for key in ["1", "-", "5", ",", ";"] {
            let (c, engine) = try conversation()
            let response = c.handleKeyDown(k(key))
            #expect(response.handled && commits(response).isEmpty, "\(key)")
            #expect(c.isQuestionChat && c.refineIsComposing && engine.rawInput == key, "\(key)")
            // The syllable goes on (a tone), and ⏎ asks it.
            _ = c.handleKeyDown(k("3"))
            #expect(engine.rawInput == key + "3" && c.isQuestionChat, "\(key)")
            let asked = c.handleKeyDown(enterKey).effects.contains { if case .startRefine = $0 { true } else { false } }
            #expect(asked && c.refinements.last?.instruction == key + "3", "\(key)")
        }
    }

    @Test func aToneWithNothingTypedAndFullPinyinsDigitsAreAsBefore() throws {
        // A tone starts no syllable: nothing is given to the engine, the conversation stays.
        let (tone, engine) = try conversation()
        _ = tone.handleKeyDown(k("3"))
        #expect(engine.rawInput.isEmpty && !tone.refineIsComposing && tone.isQuestionChat && tone.refineText.isEmpty)
        // Full pinyin: 1 picks the answer, - goes back to the draft.
        let (full, _) = try conversation(.full)
        #expect(commits(full.handleKeyDown(k("1"))) == ["A language."])
        let (mark, _) = try conversation(.full)
        _ = mark.handleKeyDown(k("-"))
        #expect(!mark.isQuestionChat && !mark.refineIsComposing)
    }

    /// The same in a refine line after other results (`@improve`'s): the line, not a version's number.
    @Test func aRefineLineStartsTheSameWay() throws {
        let engine = ZhuyinKeysEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("i", c)
        _ = c.handleKeyDown(tab)
        type("hello", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi."), CandidateLine("Howdy.")]), isFinal: true, id: 1)
        try #require(c.canRefine)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        c.pinyinScheme = .zhuyin
        let response = c.handleKeyDown(k("2"))
        #expect(commits(response).isEmpty && c.refineIsComposing && engine.rawInput == "2" && c.canRefine)
    }
}
