import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A small pinyin engine with the same grave-separated candidate lists as the shape-code table.
private final class ShapeOptionEngine: PinyinEngine {
    let base = FakeEngine()

    init() {
        base.dictionary = [
            "yu": ["与", "于", "鱼"], "yu`": ["与", "于", "鱼"],
            "yu`d": ["鱼", "浴"], "yu`da": ["鱼"],
        ]
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        guard keycode == 0x60, mask == 0, !base.input.isEmpty else {
            return base.processKey(keycode, mask: mask)
        }
        base.keys.append((keycode, mask))
        base.input.append("`")
        base.highlighted = 0
        return true
    }

    func takeCommit() -> String? { base.takeCommit() }
    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() { base.clearComposition() }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}

@Suite("Issue 168: right Option for shape codes", .serialized)
struct Issue168ShapeOptionTests {
    private func host(shapeCode: String? = "moqi", actionKey: ActionKey = .optionSpace) -> (FakeHost, ShapeOptionEngine) {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.shapeCode = shapeCode
        config.actionKey = actionKey
        let fixed = config
        let engine = ShapeOptionEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        return (host, engine)
    }

    private func option(_ composer: Composer, side: Key.Side = .right, down: Bool, at time: Double) -> [Composer.Effect] {
        composer.handleFlagsChanged(key: .modifier(.option, side),
                                    modifiers: down ? [.option, Modifiers.side(side, of: .option)] : [], timestamp: time)
    }

    private func tap(_ composer: Composer, side: Key.Side = .right, from time: Double = 1,
                     until release: Double = 1.1) -> [Composer.Effect] {
        _ = option(composer, side: side, down: true, at: time)
        return option(composer, side: side, down: false, at: release)
    }

    @Test func rightTapMatchesGraveAndItsShapeLettersNarrowCandidates() {
        let (tapped, tapEngine) = host()
        let (typed, typeEngine) = host()
        tapped.type("yu")
        typed.type("yu")
        #expect(tapped.panel?.input?.text == "yu")
        #expect(typed.panel?.input?.text == "yu")

        let grave = typed.composer.handleKeyDown(k("`"))
        #expect(grave.handled)
        let release = tap(tapped.composer)
        #expect(release == grave.effects)
        #expect(tapEngine.rawInput == typeEngine.rawInput)
        #expect(tapEngine.rawInput == "yu`")
        #expect(tapped.composer.engineState == typed.composer.engineState)
        #expect(tapped.composer.markedText == typed.composer.markedText)
        #expect(tapped.composer.voice == .off)

        tapped.type("da")
        typed.type("da")
        #expect(tapEngine.rawInput == "yu`da")
        #expect(tapEngine.base.candidates() == ["鱼"])
        #expect(tapped.panel?.rows.first?.text == "鱼")
        #expect(tapped.composer.engineState == typed.composer.engineState)
    }

    @Test func optionChordWithDigitDoesNotStartShapeCode() {
        let (host, engine) = host()
        host.type("yu")
        _ = option(host.composer, down: true, at: 2)
        let digit = host.composer.handleKeyDown(KeyEvent(keyCode: 0x12, characters: "¡",
                                                           charactersIgnoringModifiers: "1", modifiers: .option))
        let release = option(host.composer, down: false, at: 2.1)
        #expect(digit.handled)
        #expect(release.isEmpty)
        #expect(!engine.rawInput.contains("`"))
    }

    @Test func leftOptionAndLongRightPressDoNotStartShapeCode() {
        let (left, leftEngine) = host()
        left.type("yu")
        #expect(tap(left.composer, side: .left).isEmpty)
        #expect(leftEngine.rawInput == "yu")

        let (long, longEngine) = host()
        long.type("yu")
        _ = tap(long.composer, from: 3, until: 4)
        #expect(longEngine.rawInput == "yu")
    }

    @Test func anotherModifierDuringRightOptionDoesNotStartShapeCode() {
        let (host, engine) = host()
        host.type("yu")
        _ = option(host.composer, down: true, at: 4)
        _ = host.composer.handleFlagsChanged(key: .modifier(.shift, .left),
                                              modifiers: [.option, .rightOption, .shift, .leftShift], timestamp: 4.02)
        _ = host.composer.handleFlagsChanged(key: .modifier(.shift, .left),
                                              modifiers: [.option, .rightOption], timestamp: 4.05)
        _ = option(host.composer, down: false, at: 4.1)
        #expect(engine.rawInput == "yu")
    }

    @Test func rightOptionClickAndDictationHoldDoNotStartShapeCode() {
        let (clicked, clickEngine) = host()
        clicked.type("yu")
        clicked.composer.pointerUsedWithin = { _ in true }
        _ = tap(clicked.composer)
        #expect(clickEngine.rawInput == "yu")

        let (held, holdEngine) = host()
        held.type("yu")
        held.composer.voiceEnabled = true
        _ = option(held.composer, down: true, at: 5)
        let dictation = held.composer.voiceHoldElapsed()
        #expect(dictation.contains { if case .startVoice = $0 { true } else { false } })
        _ = option(held.composer, down: false, at: 5.3)
        #expect(!holdEngine.rawInput.contains("`"))
    }

    @Test func idleAndShapeCodesOffLeaveTheTapAsBefore() {
        let (idle, idleEngine) = host()
        let idleEffects = tap(idle.composer)
        #expect(idleEngine.rawInput.isEmpty && !idle.composer.engineState.isComposing)
        #expect(!idleEffects.contains(.updateMarkedText))

        let (off, offEngine) = host(shapeCode: nil)
        off.type("yu")
        let offEffects = tap(off.composer)
        #expect(offEngine.rawInput == "yu")
        #expect(offEffects == idleEffects)
        #expect(!offEffects.contains(.updateMarkedText))
    }

    @Test func optionTapActionKeyKeepsItsActionAndGraveStillWorks() {
        let (host, engine) = host(actionKey: .optionTap)
        host.type("@improve yu")
        let action = tap(host.composer)
        #expect(action.contains { if case .startConversion = $0 { true } else { false } })
        #expect(!engine.rawInput.contains("`"))

        let (graveHost, graveEngine) = self.host(actionKey: .optionTap)
        graveHost.type("yu`")
        #expect(graveEngine.rawInput == "yu`")
        graveHost.type("da")
        #expect(graveEngine.base.candidates() == ["鱼"])
    }

    @Test func shapeCodeHelpNamesBothWaysInEnglishAndChinese() async {
        await withInterfaceLanguage("en") {
            let help = UIText.shapeCodeHelp
            #expect(help.contains("`"))
            #expect(help.lowercased().contains("right") && (help.contains("⌥") || help.lowercased().contains("option")))
        }
        await withInterfaceLanguage("zh") {
            let help = UIText.shapeCodeHelp
            #expect(help.contains("`"))
            #expect(help.contains("右") && (help.contains("⌥") || help.contains("Option")))
        }
    }
}
