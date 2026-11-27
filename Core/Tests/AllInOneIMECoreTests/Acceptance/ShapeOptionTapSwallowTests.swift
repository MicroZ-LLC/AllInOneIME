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

/// `SessionResponse.handled` is the portable pass-to-app result of a modifier event: true, the event is the input
/// method's alone; false, the app gets it as well.
///
/// The refined spec (the owner's #171 decision under InputMethodKit's limits: each event is answered as it comes, and a
/// press can't be handed to the app later): while pinyin is typed with shape codes on, the right Option's press and its
/// release are both the input method's, whether it turns out a tap (the shape-code marker) or not (a hold, Option with
/// another key: that key carries Option among its own modifiers). Only where another modifier changed while the right
/// Option was down (the app learned of Option from that event's flags) does its release reach the app. With no pinyin,
/// shape codes off, Zhuyin, the left Option, or the Option tap as the action key, the app gets the events as before.
/// With fn held, a tap of the right Option is no shape-code tap.
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

    /// A modifier changed: `key`, with `modifiers` down after it.
    private func tell(_ host: FakeHost, _ key: Key, _ modifiers: Modifiers, at time: Double) -> SessionResponse {
        host.session.handle(.modifiers(ModifierChange(key: key, modifiers: modifiers, timestamp: time), host.context))
    }

    /// An Option key pressed or released, nothing else down (but `with`).
    private func tell(_ host: FakeHost, side: Key.Side = .right, down: Bool, with others: Modifiers = [],
                      at time: Double) -> SessionResponse {
        let option: Modifiers = down ? [.option, Modifiers.side(side, of: .option)] : []
        return tell(host, .modifier(.option, side), option.union(others), at: time)
    }

    private static let digitWithOption = KeyEvent(keyCode: 0x12, characters: "¡", charactersIgnoringModifiers: "1",
                                                  modifiers: .option)

    // MARK: The right Option while pinyin is typed with shape codes on: the input method's

    @Test func tapIsConsumedPressAndReleaseAndTypesTheMarker() {
        let (host, engine) = host()
        host.type("yu")
        #expect(engine.rawInput == "yu")
        let document = host.document
        let press = tell(host, down: true, at: 1)
        #expect(press.handled, "the app must not get the press of what may be the shape-code tap")
        #expect(engine.rawInput == "yu", "nothing is typed at the press")
        let release = tell(host, down: false, at: 1.1)
        #expect(release.handled, "the app must not get the release of the tap that types the shape-code marker")
        #expect(engine.rawInput == "yu`", "the tap must type the shape-code marker")
        #expect(host.document == document, "the tap puts nothing into the field itself")
    }

    @Test func holdIsConsumedPressAndReleaseAndTypesNothing() {
        let (host, engine) = host()
        host.type("yu")
        let document = host.document
        #expect(tell(host, down: true, at: 5).handled, "the press is kept before it is known to be a hold")
        #expect(tell(host, down: false, at: 6).handled, "the app never got the press: it must not get the release alone")
        #expect(engine.rawInput == "yu", "a hold is no shape-code tap")
        #expect(host.document == document)
    }

    @Test func chordConsumesThePressAndHandlesTheKeyAsWithoutIt() {
        // The same key with Option among its modifiers, the Option key's own events never told: how the key is handled.
        let (plain, plainEngine) = host()
        plain.type("yu")
        let plainHandled = plain.press(Self.digitWithOption)

        let (host, engine) = host()
        host.type("yu")
        #expect(tell(host, down: true, at: 6).handled, "the press is kept before it is known to be a chord")
        let handled = host.press(Self.digitWithOption)
        #expect(handled == plainHandled, "the key typed with Option is handled as it always was")
        #expect(engine.rawInput == plainEngine.rawInput)
        #expect(host.document == plain.document)
        #expect(host.composer.engineState == plain.composer.engineState)
        let input = engine.rawInput
        #expect(tell(host, down: false, at: 6.1).handled, "the app never got the press: it must not get the release alone")
        #expect(engine.rawInput == input, "the release after a chord types nothing")
        #expect(!engine.rawInput.contains("`"), "Option with another key is no shape-code tap")
    }

    /// Another modifier down and up while the right Option is held: the app got both of its changes, the first with
    /// Option among its flags, so it knows Option is down and gets its release.
    @Test(arguments: [Key.ModifierKind.shift, .command, .control])
    func anotherModifierDuringTheHoldPassesTheRelease(_ kind: Key.ModifierKind) {
        let (host, engine) = host()
        host.type("yu")
        #expect(tell(host, down: true, at: 4).handled)
        let held: Modifiers = [.option, .rightOption]
        let other: Modifiers = [Modifiers.kind(kind), Modifiers.side(.left, of: kind)]
        #expect(!tell(host, .modifier(kind, .left), held.union(other), at: 4.02).handled, "the other modifier's press is the app's")
        #expect(!tell(host, .modifier(kind, .left), held, at: 4.05).handled, "the other modifier's release is the app's")
        #expect(!tell(host, down: false, at: 4.1).handled, "the app learned Option is down: it must get its release")
        #expect(engine.rawInput == "yu", "Option with another modifier is no shape-code tap")
    }

    @Test func anotherModifierStillDownAtTheReleasePassesIt() {
        let (host, engine) = host()
        host.type("yu")
        #expect(tell(host, down: true, at: 4).handled)
        #expect(!tell(host, .modifier(.shift, .left), [.option, .rightOption, .shift, .leftShift], at: 4.02).handled)
        #expect(!tell(host, down: false, with: [.shift, .leftShift], at: 4.1).handled,
                "the app learned Option is down: it must get its release")
        #expect(engine.rawInput == "yu")
    }

    @Test func leftOptionDuringTheHoldPassesTheRelease() {
        let (host, engine) = host()
        host.type("yu")
        #expect(tell(host, down: true, at: 4).handled)
        #expect(!tell(host, .modifier(.option, .left), [.option, .rightOption, .leftOption], at: 4.02).handled,
                "the left Option's press is the app's")
        #expect(!tell(host, .modifier(.option, .left), [.option, .rightOption], at: 4.05).handled,
                "the left Option's release is the app's")
        #expect(!tell(host, down: false, at: 4.1).handled, "the app learned Option is down: it must get its release")
        #expect(engine.rawInput == "yu")
    }

    /// Once the app was told of a release, the next tap is a new one: both of its events the input method's again.
    @Test func tapAfterAPassedReleaseIsConsumedAgain() {
        let (host, engine) = host()
        host.type("yu")
        _ = tell(host, down: true, at: 4)
        _ = tell(host, .modifier(.shift, .left), [.option, .rightOption, .shift, .leftShift], at: 4.02)
        _ = tell(host, .modifier(.shift, .left), [.option, .rightOption], at: 4.05)
        #expect(!tell(host, down: false, at: 4.1).handled)
        #expect(tell(host, down: true, at: 9).handled)
        #expect(tell(host, down: false, at: 9.1).handled)
        #expect(engine.rawInput == "yu`")
    }

    @Test func tapWithFnHeldTypesNoMarker() {
        let (host, engine) = host()
        host.type("yu")
        _ = tell(host, down: true, with: .function, at: 7.02)
        _ = tell(host, down: false, with: .function, at: 7.1)
        #expect(engine.rawInput == "yu", "a tap of the right Option with fn held is no shape-code tap")
    }

    // MARK: Unchanged: the app gets the events

    @Test func noPinyinPassesToApp() {
        let (host, engine) = host()
        #expect(!tell(host, down: true, at: 2).handled)
        #expect(!tell(host, down: false, at: 2.1).handled)
        #expect(engine.rawInput.isEmpty)
        // A hold too.
        #expect(!tell(host, down: true, at: 3).handled)
        #expect(!tell(host, down: false, at: 4).handled)
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
