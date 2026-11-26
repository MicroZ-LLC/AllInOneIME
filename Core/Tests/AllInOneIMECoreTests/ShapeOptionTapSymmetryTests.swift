import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The shape-code trigger is a grave key to the engine after pinyin has started.
private final class SymmetryEngine: PinyinEngine {
    let base = FakeEngine()

    init() {
        base.dictionary = ["yu": ["与", "于"], "yu`": ["与", "于"]]
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        guard keycode == 0x60, mask == 0, !base.input.isEmpty else { return base.processKey(keycode, mask: mask) }
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

/// The right Option's press and release while pinyin is typed with shape codes on go to the app together or not at all
/// (the owner, 2026-11-26): an app that follows the modifiers from their changes never gets one without the other. And
/// what is no tap of the key on its own (fn held, a press told again after a chord, a key in secure input) types no "`".
@Suite("Shape-code right Option tap: the app gets both of its changes or neither", .serialized)
struct ShapeOptionTapSymmetryTests {
    private func host() -> (FakeHost, SymmetryEngine) {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.shapeCode = "moqi"
        config.actionKey = .optionSpace
        let fixed = config
        let engine = SymmetryEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        return (host, engine)
    }

    private static let rightDown: KeyModifiers = [.option, .rightOption]

    /// Whether the session took the change for itself (kept from the app).
    private func tell(_ host: FakeHost, _ key: Key, _ modifiers: KeyModifiers, at time: Double) -> Bool {
        host.session.handle(.modifiers(ModifierChange(key: key, modifiers: modifiers, timestamp: time), host.context)).handled
    }

    /// `tell` for the right Option.
    private func tell(_ host: FakeHost, _ modifiers: KeyModifiers, at time: Double) -> Bool {
        tell(host, .modifier(.option, .right), modifiers, at: time)
    }

    @Test func theTapsPressAndReleaseAreBothKeptFromTheApp() {
        let (host, engine) = host()
        host.type("yu")
        let press = tell(host, Self.rightDown, at: 1)
        let release = tell(host, [], at: 1.1)
        #expect(engine.rawInput == "yu`")
        #expect(press == release, "the app got the press (\(!press)) but the release (\(!release)) differently")
        #expect(release, "the tap that typed ` reached the app")
    }

    @Test func aPressToldAgainIsKeptAsTheFirstWas() {
        let (host, engine) = host()
        host.type("yu")
        let press = tell(host, Self.rightDown, at: 1)
        let again = tell(host, Self.rightDown, at: 1.02)
        let release = tell(host, [], at: 1.1)
        #expect(engine.rawInput == "yu`")
        #expect(press == again && again == release)
    }

    @Test func aLongHoldsPressAndReleaseGoTheSameWay() {
        let (host, engine) = host()
        host.type("yu")
        let press = tell(host, Self.rightDown, at: 5)
        let release = tell(host, [], at: 6)
        #expect(engine.rawInput == "yu")
        #expect(press == release)
    }

    @Test func aChordsPressAndReleaseGoTheSameWay() {
        let (host, engine) = host()
        host.type("yu")
        let press = tell(host, Self.rightDown, at: 6)
        _ = host.press(KeyEvent(keyCode: 0x12, characters: "¡", charactersIgnoringModifiers: "1", modifiers: .option))
        let release = tell(host, [], at: 6.1)
        #expect(!engine.rawInput.contains("`"))
        #expect(press == release)
    }

    /// Another modifier's change reaches the app with Option among its flags: the app knows the key is down from then, so
    /// it gets the release.
    @Test func theReleaseReachesAnAppToldOfTheKeyByAnotherModifiersChange() {
        let (host, engine) = host()
        host.type("yu")
        _ = tell(host, Self.rightDown, at: 7)
        let command = tell(host, .modifier(.command, .left), Self.rightDown.union([.command, .leftCommand]), at: 7.05)
        let commandUp = tell(host, .modifier(.command, .left), Self.rightDown, at: 7.1)
        let release = tell(host, [], at: 7.15)
        #expect(!command && !commandUp && !release)
        #expect(engine.rawInput == "yu")
    }

    @Test func withoutPinyinNothingIsKept() {
        let (host, _) = host()
        #expect(!tell(host, Self.rightDown, at: 8))
        #expect(!tell(host, [], at: 8.1))
    }

    // Item 5: fn held is no tap of the key on its own.
    @Test func aTapWithFnHeldTypesNothingAndIsTheApps() {
        let (host, engine) = host()
        host.type("yu")
        let press = tell(host, Self.rightDown.union(.function), at: 9)
        let release = tell(host, [.function], at: 9.1)
        #expect(engine.rawInput == "yu", "fn and right Option typed `")
        #expect(!press && !release)
    }

    // Item 6: the key told down again after a chord's other modifier went up is the same press, no new one.
    @Test func aPressToldAgainAfterAChordIsNoTap() {
        let (host, engine) = host()
        host.type("yu")
        let command: Key = .modifier(.command, .left)
        _ = tell(host, command, [.command, .leftCommand], at: 10)
        let press = tell(host, Self.rightDown.union([.command, .leftCommand]), at: 10.1)
        _ = tell(host, command, Self.rightDown, at: 10.2)
        let again = tell(host, Self.rightDown, at: 10.3)
        let release = tell(host, [], at: 10.4)
        #expect(engine.rawInput == "yu", "a press told again after ⌘ went up typed `")
        #expect(!press && !again && !release)
    }

    // Item 6: a key that secure input took ends the press before it as any key does (the action key's tap too).
    @Test func aKeyTakenBySecureInputEndsThePress() {
        let (host, _) = host()
        _ = tell(host, Self.rightDown, at: 11)
        #expect(host.composer.optionPressed != nil)
        host.secure = true
        _ = host.press(KeyEvent(keyCode: 0x12, characters: "¡", charactersIgnoringModifiers: "1", modifiers: .option))
        host.secure = false
        #expect(host.composer.optionPressed == nil, "a press with a key in secure input after it is still a tap's")
    }
}
