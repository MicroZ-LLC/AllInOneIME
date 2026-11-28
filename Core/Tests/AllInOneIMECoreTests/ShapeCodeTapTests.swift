import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A tap of the right ⌥ as "`" for shape codes (`Composer.shapeCodeTap`), beyond the acceptance file
/// (Acceptance/Issue168ShapeOptionTests.swift): what the tap leaves of a hold (dictation armed, its notice), and pinyin
/// without shape codes (Zhuyin, Wubi).
struct ShapeCodeTapTests {
    /// "ni" typed with shape codes on (Moqi), ⌥Space the action key.
    private func composing(voice: Bool) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, voiceEnabled: voice, actionKey: .optionSpace)
        c.shapeCode = .moqi
        for letter in "ni" { _ = c.handleKeyDown(k(String(letter))) }
        return (c, engine)
    }

    private func tapRightOption(_ c: Composer, at time: Double = 1) -> [Composer.Effect] {
        _ = c.handleFlagsChanged(keyCode: VirtualKey.rightOption, modifiers: [.option, .rightOption], timestamp: time)
        return c.handleFlagsChanged(keyCode: VirtualKey.rightOption, modifiers: [], timestamp: time + 0.1)
    }

    /// How many "`" the engine was given.
    private func graves(_ engine: FakeEngine) -> Int { engine.keys.filter { $0.keycode == 0x60 }.count }

    /// With dictation on, the press arms it; the tap is "`", not "hold right ⌥ to talk", and dictation doesn't start
    /// when the arming's time is up.
    @Test func aTapWithVoiceOnIsTheGraveAndLeavesDictationUnarmed() {
        let (c, engine) = composing(voice: true)
        let tap = tapRightOption(c)
        #expect(graves(engine) == 1)
        #expect(!tap.contains(.notice(c.messages.holdToTalk)))
        #expect(c.voiceHoldElapsed().isEmpty)
        #expect(c.voice == .off)
    }

    /// Zhuyin has no shape codes (its patch has none): the tap is as before, nothing given to the engine.
    @Test func zhuyinKeepsTheTapAsBefore() {
        let (c, engine) = composing(voice: false)
        c.pinyinScheme = .zhuyin
        #expect(tapRightOption(c).isEmpty)
        #expect(graves(engine) == 0)
        #expect(engine.input == "ni")
    }

    /// Nor has Wubi (its letters are codes, not pinyin): the tap is as before there too.
    @Test func wubiKeepsTheTapAsBefore() {
        let (c, engine) = composing(voice: false)
        c.pinyinScheme = .wubi
        #expect(tapRightOption(c).isEmpty)
        #expect(graves(engine) == 0)
        #expect(engine.input == "ni")
    }
}
