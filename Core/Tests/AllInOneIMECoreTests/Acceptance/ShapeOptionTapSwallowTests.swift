import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The shape-code trigger is a grave key to the engine after pinyin has started.
private final class ShapeOptionSwallowEngine: PinyinEngine {
    let base = FakeEngine()

    init() {
        base.dictionary = ["yu": ["与", "于"], "yu`": ["与", "于"]]
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
    func selectSchema(_ id: String) -> Bool { true }
}

/// `SessionResponse.handled` is the portable pass-to-app result of a modifier event. The Mac controller currently
/// ignores that result and always returns false for `flagsChanged`; after the session takes the tap, it must use it.
@Suite("Shape-code right Option tap: pass to app", .serialized)
struct ShapeOptionTapSwallowTests {
    private func host(shapeCode: String? = "moqi", actionKey: ActionKey = .optionSpace,
                      scheme: PinyinScheme = .full) -> (FakeHost, ShapeOptionSwallowEngine) {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.shapeCode = shapeCode
        config.actionKey = actionKey
        config.pinyinScheme = scheme.setting
        let fixed = config
        let engine = ShapeOptionSwallowEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        return (host, engine)
    }

    private func change(_ side: Key.Side, down: Bool, at time: Double) -> ModifierChange {
        ModifierChange(key: .modifier(.option, side),
                       modifiers: down ? [.option, Modifiers.side(side, of: .option)] : [], timestamp: time)
    }

    private func tell(_ host: FakeHost, side: Key.Side = .right, down: Bool, at time: Double) -> SessionResponse {
        let event = change(side, down: down, at: time)
        return host.session.handle(.modifiers(event, host.context))
    }

    @Test func triggeringReleaseIsConsumed() {
        let (host, engine) = host()
        host.type("yu")
        #expect(engine.rawInput == "yu")
        let press = tell(host, down: true, at: 1)
        #expect(!press.handled)
        let release = tell(host, down: false, at: 1.1)
        #expect(engine.rawInput == "yu`", "the release must actually trigger shape codes")
        #expect(release.handled, "the app must not receive the modifier event that triggers shape codes")
    }

    @Test func noPinyinPassesToApp() {
        let (host, engine) = host()
        #expect(!tell(host, down: true, at: 2).handled)
        #expect(!tell(host, down: false, at: 2.1).handled)
        #expect(engine.rawInput.isEmpty)
    }

    @Test func shapeCodesOffPassesToApp() {
        let (host, engine) = host(shapeCode: nil)
        host.type("yu")
        #expect(!tell(host, down: true, at: 3).handled)
        #expect(!tell(host, down: false, at: 3.1).handled)
        #expect(engine.rawInput == "yu")
    }

    @Test func leftOptionPassesToApp() {
        let (host, engine) = host()
        host.type("yu")
        #expect(!tell(host, side: .left, down: true, at: 4).handled)
        #expect(!tell(host, side: .left, down: false, at: 4.1).handled)
        #expect(engine.rawInput == "yu")
    }

    @Test func longRightOptionHoldPassesToApp() {
        let (host, engine) = host()
        host.type("yu")
        #expect(!tell(host, down: true, at: 5).handled)
        #expect(!tell(host, down: false, at: 6).handled)
        #expect(engine.rawInput == "yu")
    }

    @Test func optionChordPassesToApp() {
        let (host, engine) = host()
        host.type("yu")
        #expect(!tell(host, down: true, at: 6).handled)
        _ = host.press(KeyEvent(keyCode: 0x12, characters: "¡", charactersIgnoringModifiers: "1", modifiers: .option))
        #expect(!tell(host, down: false, at: 6.1).handled)
        #expect(!engine.rawInput.contains("`"))
    }

    @Test func optionTapActionKeyPassesToApp() {
        let (host, engine) = host(actionKey: .optionTap)
        host.type("yu")
        #expect(!tell(host, down: true, at: 7).handled)
        #expect(!tell(host, down: false, at: 7.1).handled)
        #expect(!engine.rawInput.contains("`"))
    }

    @Test func zhuyinPassesToApp() {
        let (host, engine) = host(scheme: .zhuyin)
        host.type("yu")
        #expect(host.composer.pinyinScheme == .zhuyin && host.composer.engineState.isComposing)
        #expect(!tell(host, down: true, at: 8).handled)
        #expect(!tell(host, down: false, at: 8.1).handled)
        #expect(!engine.rawInput.contains("`"))
    }
}
