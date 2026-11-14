import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner's 2026-11-13 contract (0.7.4): the language switch key is Shift or Caps Lock, the user's choice
/// (`Config.switchKey`, `SwitchKey.shift` by default). Replaces "a short press switches" and "two quick presses switch".
///
/// - Shift chosen: exactly as before the setting. A tap of Shift switches; Caps Lock is Caps Lock (never a switch, the lock
///   never touched by the input method, letters with it go to the app as typed).
/// - Caps Lock chosen: each press of Caps Lock on its own (no Shift, Control, Option or Command held; fn doesn't count) does
///   everything a tap of Shift does with Shift chosen (`composer.shiftTapped()`), and the input method turns the lock off
///   again at once (`PlatformAction.setCapsLock(false)`). That lock-off, and any lock-off, is never a switch. A tap of Shift
///   switches nothing; Shift with letters and the long press of Shift are unchanged. With another modifier held, in a
///   password field or under secure input, Caps Lock is the system's: no switch, the lock left alone.
///
/// macOS tells an input method only when the lock changes, so the Mac shell hands each lock change to the session as
/// `ModifierChange(key: .capsLock, modifiers: <.capsLock when the lock is now on, plus the other modifiers held>,
/// timestamp:)`; these tests drive it the same way (`FakeHost.modifiers`), and read what the input method asked of the
/// lock in `FakeHost.platformActions`. Where it asked for the lock off, the rig plays the shell: the lock goes off, and
/// macOS tells that change too.

/// The settings as the session loads them (`SessionServices.loadSettings`): changed by the test as Settings changes them.
private final class LoadedSettings {
    var config: Config
    init(_ config: Config) { self.config = config }
}

/// The rig's clock: the events' timestamps, and the session's uptime (the long press of Shift goes by it).
private final class RigClock {
    var now: TimeInterval = 100
}

/// Translate as You Type, as the shell keeps it (`SuggestionsServices.translateAsYouType`).
private final class TranslateSwitch {
    var on = false
}

private final class SwitchRig {
    let settings: LoadedSettings
    let clock = RigClock()
    let translate = TranslateSwitch()
    /// The lock as the rig last told it, and the other modifiers held (their kind and left side bits, fn as `.function`).
    private(set) var lockOn = false
    private(set) var held: Modifiers = []
    /// The field with the focus: its own session, as each text field has one. Fields share the services (what is learned).
    private(set) var host: FakeHost
    private let services: SessionServices
    /// What the input method asked of the fields before this one.
    private var earlierActions: [PlatformAction] = []

    /// A field of "com.example.editor" with the focus, Chinese and English the input languages (Chinese first), `key` the
    /// language switch key; `lockOn` the lock as it already is (on since before: the session wasn't told).
    init(_ key: SwitchKey = .shift, secureAnywhere: Bool = false, lockOn: Bool = false) {
        var config = Config.default
        config.inputLanguages = [.chinese, .english]
        config.defaultInput = .chinese
        config.switchKey = key
        let settings = LoadedSettings(config)
        self.settings = settings
        var services = SessionServices(loadSettings: { settings.config })
        services.secureInputActive = { secureAnywhere }
        services.pointerUsedWithin = { _ in false }
        let (clock, translate) = (clock, translate)
        services.uptime = { clock.now }
        services.suggestions.translateAsYouType = { translate.on }
        services.suggestions.setTranslateAsYouType = { translate.on = $0 }
        self.services = services
        host = Self.field(services, app: "com.example.editor")
        self.lockOn = lockOn
    }

    /// A text field of `app` taking the focus, with an engine of its own.
    private static func field(_ services: SessionServices, app: String) -> FakeHost {
        var services = services
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.app = app
        host.appTypesKeys = true
        host.focus()
        return host
    }

    /// The field loses the focus, and a new text field of `app` takes it (a session of its own).
    func newField(app: String = "com.example.editor") {
        host.send(.blur)
        earlierActions += host.platformActions
        host = Self.field(services, app: app)
    }

    var now: TimeInterval { clock.now }
    func advance(_ seconds: TimeInterval) { clock.now += seconds }

    var language: Language { host.composer.inputLanguage }
    /// What the input method asked, in every field so far.
    var actions: [PlatformAction] { earlierActions + host.platformActions }

    /// Settings → Input → Switch input language set to `key`: saved, and the session told (`SessionEvent.configChanged`).
    func choose(_ key: SwitchKey) {
        settings.config.switchKey = key
        host.send(.configChanged)
    }

    /// Caps Lock's lock changed (on or off), as the Mac shell tells it: the lock in `modifiers`, with what else is held.
    func lock(_ on: Bool) {
        lockOn = on
        host.modifiers(ModifierChange(key: .capsLock, modifiers: held.union(on ? .capsLock : []), timestamp: now))
    }

    /// One press of Caps Lock: the lock flips. Where that turned it on and the input method asked for it off
    /// (`.setCapsLock(false)`), the shell turns it off and macOS tells that change too, `gap` later. What the input method
    /// asked at the press, and at the change that followed it (none: none followed).
    @discardableResult
    func pressCapsLock(gap: TimeInterval = 0.01) -> (atPress: [PlatformAction], atOff: [PlatformAction]?) {
        let before = actions.count
        lock(!lockOn)
        let atPress = Array(actions[before...])
        guard lockOn, atPress.contains(.setCapsLock(false)) else { return (atPress, nil) }
        advance(gap)
        let middle = actions.count
        lock(false)
        return (atPress, Array(actions[middle...]))
    }

    /// `kind`'s left key goes down or up, the lock as it is.
    func modifier(_ kind: Key.ModifierKind, down: Bool) {
        let bits = Self.left(kind)
        if down { held.formUnion(bits) } else { held.subtract(bits) }
        host.modifiers(ModifierChange(key: .modifier(kind, .left), modifiers: held.union(lockOn ? .capsLock : []),
                                      timestamp: now))
    }

    /// fn (🌐) goes down or up, the lock as it is.
    func fn(down: Bool) {
        if down { held.insert(.function) } else { held.remove(.function) }
        host.modifiers(ModifierChange(key: .function, modifiers: held.union(lockOn ? .capsLock : []), timestamp: now))
    }

    /// Shift pressed and released on its own, 0.1 s apart.
    func shiftTap() {
        modifier(.shift, down: true)
        advance(0.1)
        modifier(.shift, down: false)
    }

    /// Shift held on its own for `seconds`, the session's timers due meanwhile fired, then released.
    func holdShift(for seconds: TimeInterval = 1.2) {
        modifier(.shift, down: true)
        advance(seconds)
        host.fireTimers { if case .suggestions = $0 { true } else { false } }
        modifier(.shift, down: false)
    }

    /// A letter key ("a") typed, a capital with the lock on: whether the session took it.
    @discardableResult
    func letter() -> Bool {
        host.press(KeyEvent(keyCode: 0, characters: lockOn ? "A" : "a", charactersIgnoringModifiers: "a",
                            modifiers: lockOn ? .capsLock : []))
    }

    /// "A" typed with Shift held (Shift down, the key, Shift up): whether the session took the key.
    @discardableResult
    func shiftedLetter() -> Bool {
        modifier(.shift, down: true)
        advance(0.05)
        let handled = host.press(KeyEvent(keyCode: 0, characters: "A", charactersIgnoringModifiers: "a",
                                          modifiers: held.union(lockOn ? .capsLock : [])))
        advance(0.05)
        modifier(.shift, down: false)
        return handled
    }

    /// The field loses the focus, and takes it again as a field of `app`: the same session (a page's next field).
    func refocus(app: String = "com.example.editor") {
        host.send(.blur)
        host.app = app
        host.focus()
    }

    /// The commits since `start` (an index into `host.outputs`).
    func commits(since start: Int) -> [String] {
        host.outputs[start...].compactMap { output -> String? in
            if case let .commit(text) = output { text } else { nil }
        }
    }

    /// The notices since `start` (an index into `host.outputs`).
    func notices(since start: Int) -> [String] {
        host.outputs[start...].compactMap { output -> String? in
            if case let .notice(text) = output { text } else { nil }
        }
    }

    private static func left(_ kind: Key.ModifierKind) -> Modifiers {
        switch kind {
        case .shift: [.shift, .leftShift]
        case .control: [.control, .leftControl]
        case .option: [.option, .leftOption]
        case .command: [.command, .leftCommand]
        }
    }
}

/// The input method never touched the lock: no `.setCapsLock` asked (nothing else in these rigs asks a `PlatformAction`).
private func expectLockLeftAlone(_ rig: SwitchRig, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(rig.actions.isEmpty, "the input method must leave Caps Lock's lock alone here, asked: \(rig.actions)",
            sourceLocation: sourceLocation)
}

/// Every action asked is `.setCapsLock(false)`, `count` of them: one for each press that switched.
private func expectLockTurnedOff(_ rig: SwitchRig, times count: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(rig.actions == Array(repeating: PlatformAction.setCapsLock(false), count: count),
            "expected the lock turned off \(count) times, asked: \(rig.actions)", sourceLocation: sourceLocation)
}

@Suite("The language switch key: Shift or Caps Lock")
struct CapsLockToggleTests {
    // MARK: Shift chosen (the default): Caps Lock is Caps Lock

    @Test func shiftIsTheDefaultSwitchKey() {
        #expect(Config.default.switchKey == .shift)
        #expect(Config.fresh.switchKey == .shift)
        #expect(SwitchRig().settings.config.switchKey == .shift)
    }

    @Test func withShiftCapsLockNeverSwitchesAndCapitalsGoToTheApp() {
        let rig = SwitchRig()
        rig.lock(true)
        #expect(rig.language == .chinese)
        rig.advance(0.1)
        let handled = rig.letter()
        #expect(!handled, "Caps Lock capitals belong to the application, not pinyin")
        #expect(rig.host.document == "A")
        #expect(rig.host.marked.isEmpty && !rig.host.composer.isComposing)

        rig.advance(1)
        rig.lock(false)
        #expect(rig.language == .chinese, "turned off: just off, no switch")
        rig.letter()
        #expect(rig.host.composer.isComposing, "Chinese as before the lock")
        expectLockLeftAlone(rig)
    }

    @Test func withShiftQuickPressesOfCapsLockNeverSwitch() {
        let rig = SwitchRig()
        // The older designs' gestures: a short press, two quick presses, and more in a row.
        for gap in [0.05, 0.2, 0.4, 0.05, 0.2, 2] {
            rig.lock(!rig.lockOn)
            #expect(rig.language == .chinese, "a lock change with Shift chosen switched (gap \(gap))")
            rig.advance(gap)
        }
        expectLockLeftAlone(rig)
    }

    @Test func withShiftATapOfShiftSwitchesBothWays() {
        let rig = SwitchRig()
        #expect(rig.language == .chinese)
        rig.shiftTap()
        #expect(rig.language == .english)
        #expect(rig.host.noticeAlone != nil, "the switch is said")
        rig.advance(1)
        rig.shiftTap()
        #expect(rig.language == .chinese, "and back")
        expectLockLeftAlone(rig)
    }

    // MARK: Caps Lock chosen: a press is Shift's tap, and the lock goes off again

    @Test func aPressSwitchesAsShiftsTapAndTheLockGoesOffAgain() {
        let caps = SwitchRig(.capsLock), shift = SwitchRig()
        #expect(caps.language == .chinese)

        caps.lock(true)
        shift.shiftTap()
        #expect(caps.language == .english, "a press of Caps Lock switches")
        #expect(caps.language == shift.language)
        #expect(caps.host.noticeAlone != nil && caps.host.noticeAlone == shift.host.noticeAlone, "the same notice as Shift's tap")
        expectLockTurnedOff(caps, times: 1)

        // The shell turned it off: macOS tells that change too. It is no press.
        let (notice, document, outputs) = (caps.host.noticeAlone, caps.host.document, caps.host.outputs.count)
        caps.advance(0.01)
        caps.lock(false)
        #expect(caps.language == .english, "the lock turned off after the press is no second switch")
        #expect(caps.host.noticeAlone == notice && caps.host.document == document)
        #expect(caps.notices(since: outputs).isEmpty && caps.commits(since: outputs).isEmpty)
        expectLockTurnedOff(caps, times: 1)

        caps.advance(1)
        shift.advance(1)
        caps.pressCapsLock()
        shift.shiftTap()
        #expect(caps.language == .chinese, "and back")
        #expect(caps.language == shift.language)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        expectLockTurnedOff(caps, times: 2)
        expectLockLeftAlone(shift)
    }

    @Test func pressesInARowEachSwitch() {
        let caps = SwitchRig(.capsLock), shift = SwitchRig()
        var expected = Language.chinese
        // Quick and slow: each press is a press (on, off by the input method, on, off …).
        for (index, gap) in [0.05, 0.05, 0.3, 1, 0.05, 2, 0.1].enumerated() {
            caps.advance(gap)
            shift.advance(gap)
            let (atPress, atOff) = caps.pressCapsLock(gap: 0.01)
            shift.shiftTap()
            expected = expected == .chinese ? .english : .chinese
            #expect(atPress == [.setCapsLock(false)], "press \(index + 1): asked \(atPress)")
            #expect(atOff == [], "press \(index + 1): the lock's going off asked \(atOff ?? [])")
            #expect(caps.language == expected, "press \(index + 1) didn't switch")
            #expect(caps.language == shift.language && caps.host.noticeAlone == shift.host.noticeAlone, "press \(index + 1)")
        }
        expectLockTurnedOff(caps, times: 7)
    }

    @Test func theLockOffComingLateIsStillNoSwitch() {
        let rig = SwitchRig(.capsLock)
        rig.lock(true)
        #expect(rig.language == .english)
        // The shell's change came late (a busy Mac): still just the lock going off.
        rig.advance(1.5)
        rig.lock(false)
        #expect(rig.language == .english)
        expectLockTurnedOff(rig, times: 1)
    }

    @Test func aLockOffChangeAloneIsNoSwitch() {
        // The lock on since before the session was told (another input source had it on): its press turns it off.
        let rig = SwitchRig(.capsLock, lockOn: true)
        let start = rig.host.outputs.count
        rig.lock(false)
        #expect(rig.language == .chinese, "a lock-off change is never a switch")
        #expect(rig.notices(since: start).isEmpty)
        expectLockLeftAlone(rig)

        rig.advance(0.3)
        rig.pressCapsLock()
        #expect(rig.language == .english, "the next press turns it on: a switch")
        expectLockTurnedOff(rig, times: 1)
    }

    @Test func aPressKeepsTheSamePerFieldLanguageMemoryAsShift() {
        let caps = SwitchRig(.capsLock), shift = SwitchRig()
        caps.pressCapsLock()
        shift.shiftTap()
        #expect(caps.language == .english)

        caps.refocus()
        shift.refocus()
        #expect(caps.language == shift.language, "the same app's field again")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)

        caps.refocus(app: "com.example.other")
        shift.refocus(app: "com.example.other")
        #expect(caps.language == shift.language, "another app's field")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)

        caps.refocus()
        shift.refocus()
        #expect(caps.language == shift.language, "back in the first app")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)

        // New text fields, each a session of its own.
        caps.newField()
        shift.newField()
        #expect(caps.language == shift.language, "a new field of the app")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        caps.newField(app: "com.example.other")
        shift.newField(app: "com.example.other")
        #expect(caps.language == shift.language, "a new field of another app")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        expectLockTurnedOff(caps, times: 1)
    }

    @Test func aPressTeachesAnAppItsStartingInputAsShiftsTapDoes() {
        let caps = SwitchRig(.capsLock), shift = SwitchRig()
        // Switched before typing, in two new fields in a row: the app learns to start in English.
        for round in 1...2 {
            if round > 1 {
                caps.newField()
                shift.newField()
            }
            #expect(caps.language == .chinese && shift.language == .chinese, "field \(round) starts in Chinese")
            caps.pressCapsLock()
            shift.shiftTap()
            let (capsStart, shiftStart) = (caps.host.outputs.count, shift.host.outputs.count)
            caps.letter()
            shift.letter()
            #expect(caps.language == .english && caps.language == shift.language, "field \(round)")
            #expect(caps.notices(since: capsStart) == shift.notices(since: shiftStart), "field \(round): what is said of it")
            #expect(caps.host.document == shift.host.document)
        }
        caps.newField()
        shift.newField()
        #expect(shift.language == .english, "Shift's taps taught the app")
        #expect(caps.language == shift.language, "Caps Lock's presses teach it the same")
        expectLockTurnedOff(caps, times: 2)
    }

    @Test func aCompositionHasExactlyTheShiftTapResult() {
        let caps = SwitchRig(.capsLock), shift = SwitchRig()
        caps.host.type("nihao")
        shift.host.type("nihao")
        #expect(caps.host.composer.isComposing && shift.host.composer.isComposing)
        let capsStart = caps.host.outputs.count, shiftStart = shift.host.outputs.count

        caps.pressCapsLock()
        shift.shiftTap()
        #expect(caps.language == .english)
        #expect(caps.language == shift.language)
        #expect(caps.host.document == shift.host.document, "Caps Lock must commit exactly what Shift commits")
        #expect(caps.host.marked == shift.host.marked)
        #expect(caps.host.composer.isComposing == shift.host.composer.isComposing)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        #expect(caps.commits(since: capsStart) == shift.commits(since: shiftStart), "the same composition commit as Shift")
        expectLockTurnedOff(caps, times: 1)
    }

    // MARK: Caps Lock chosen: Shift is just Shift

    @Test func aTapOfShiftSwitchesNothing() {
        let rig = SwitchRig(.capsLock)
        let (notice, start) = (rig.host.noticeAlone, rig.host.outputs.count)
        rig.shiftTap()
        #expect(rig.language == .chinese, "Shift's tap switches nothing with Caps Lock chosen")
        #expect(rig.host.noticeAlone == notice && rig.notices(since: start).isEmpty, "nothing said")
        rig.advance(1)
        rig.shiftTap()
        #expect(rig.language == .chinese)

        // The fields' language memory untouched: the field again, and new fields, still in Chinese.
        rig.refocus()
        #expect(rig.language == .chinese)
        rig.refocus(app: "com.example.other")
        #expect(rig.language == .chinese)
        rig.newField()
        #expect(rig.language == .chinese)
        rig.newField(app: "com.example.other")
        #expect(rig.language == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func aTapOfShiftLeavesACompositionAlone() {
        let rig = SwitchRig(.capsLock)
        rig.host.type("nihao")
        #expect(rig.host.composer.isComposing)
        let (marked, document, start) = (rig.host.marked, rig.host.document, rig.host.outputs.count)
        rig.shiftTap()
        #expect(rig.language == .chinese)
        #expect(rig.host.composer.isComposing, "still composing")
        #expect(rig.host.marked == marked && rig.host.document == document)
        #expect(rig.commits(since: start).isEmpty)
        expectLockLeftAlone(rig)
    }

    @Test func aTapOfShiftTeachesAnAppNothing() {
        let rig = SwitchRig(.capsLock)
        for _ in 1...2 {
            rig.shiftTap()
            rig.letter()
            #expect(rig.language == .chinese)
            rig.newField()
        }
        #expect(rig.language == .chinese, "nothing switched, nothing learned")
        expectLockLeftAlone(rig)
    }

    @Test func shiftWithLettersTypesCapitalsAsAlways() {
        let caps = SwitchRig(.capsLock), shift = SwitchRig()
        let capsTook = caps.shiftedLetter()
        let shiftTook = shift.shiftedLetter()
        #expect(capsTook == shiftTook)
        #expect(caps.host.document == shift.host.document && caps.host.marked == shift.host.marked)
        #expect(caps.language == .chinese && shift.language == .chinese, "Shift with a letter is no tap")
        expectLockLeftAlone(caps)
    }

    @Test func theLongPressOfShiftIsUnchanged() {
        let caps = SwitchRig(.capsLock), shift = SwitchRig()
        caps.holdShift()
        shift.holdShift()
        #expect(shift.translate.on, "a long press of Shift turns Translate as You Type on")
        #expect(caps.translate.on, "with Caps Lock chosen too")
        #expect(caps.language == .chinese && shift.language == .chinese)
        caps.advance(1)
        shift.advance(1)
        caps.holdShift()
        shift.holdShift()
        #expect(!shift.translate.on && !caps.translate.on, "and off")
        expectLockLeftAlone(caps)
    }

    // MARK: Caps Lock with another modifier held is the system's

    @Test func capsLockWithAnotherModifierHeldIsNoSwitch() {
        let rig = SwitchRig(.capsLock)
        var expected = Language.chinese
        var turnedOff = 0
        for kind in Key.ModifierKind.allCases {
            // Held longer than a tap of it, so its own release is no tap either.
            rig.modifier(kind, down: true)
            rig.advance(0.6)
            rig.lock(true)
            #expect(rig.language == expected, "Caps Lock with \(kind) held switched")
            expectLockTurnedOff(rig, times: turnedOff)
            rig.advance(0.6)
            rig.modifier(kind, down: false)
            #expect(rig.language == expected)

            // The lock stays on, as macOS set it; the next press turns it off: a lock-off, no switch.
            rig.advance(0.5)
            rig.pressCapsLock()
            #expect(!rig.lockOn && rig.language == expected, "after \(kind): the press that turned the lock off switched")
            expectLockTurnedOff(rig, times: turnedOff)

            // And the press after that is a press again.
            rig.advance(0.5)
            rig.pressCapsLock()
            expected = expected == .chinese ? .english : .chinese
            turnedOff += 1
            #expect(rig.language == expected, "after \(kind): a plain press")
            expectLockTurnedOff(rig, times: turnedOff)
            rig.advance(1)
        }
    }

    @Test func fnHeldStillSwitches() {
        let rig = SwitchRig(.capsLock)
        rig.fn(down: true)
        rig.advance(0.1)
        let (atPress, atOff) = rig.pressCapsLock()
        #expect(rig.language == .english, "fn doesn't count, as with Shift's tap")
        #expect(atPress == [.setCapsLock(false)] && atOff == [])
        rig.advance(0.1)
        rig.fn(down: false)
        #expect(rig.language == .english)
        expectLockTurnedOff(rig, times: 1)
    }

    // MARK: Caps Lock is the system's where nothing may leave the device

    @Test func secureInputInTheFieldLeavesCapsLockToTheSystem() {
        let rig = SwitchRig(.capsLock)
        rig.host.secure = true
        rig.lock(true)
        #expect(rig.language == .chinese)
        rig.advance(0.5)
        rig.lock(false)
        #expect(rig.language == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func secureInputAnywhereLeavesCapsLockToTheSystem() {
        let rig = SwitchRig(.capsLock, secureAnywhere: true)
        rig.lock(true)
        #expect(rig.language == .chinese)
        rig.advance(0.5)
        rig.lock(false)
        #expect(rig.language == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func aKnownPasswordFieldLeavesCapsLockToTheSystem() {
        let rig = SwitchRig(.capsLock)
        rig.host.send(.passwordField(true, focus: rig.host.session.fieldSession))
        rig.lock(true)
        #expect(rig.language == .chinese)
        rig.advance(0.5)
        rig.lock(false)
        #expect(rig.language == .chinese)
        expectLockLeftAlone(rig)
    }

    // MARK: Changing the setting

    @Test func choosingCapsLockWhileTheLockIsOnChangesNothingUntilTheNextPress() {
        let rig = SwitchRig()
        rig.lock(true)
        rig.advance(0.5)
        rig.choose(.capsLock)
        #expect(rig.language == .chinese)
        expectLockLeftAlone(rig)
        rig.advance(0.1)
        #expect(!rig.letter(), "the lock still on: capitals go to the app")
        #expect(rig.host.document == "A")

        // The next press turns the lock off: never a switch.
        rig.advance(0.5)
        rig.pressCapsLock()
        #expect(rig.language == .chinese)
        expectLockLeftAlone(rig)

        // The one after it is a press.
        rig.advance(0.5)
        rig.pressCapsLock()
        #expect(rig.language == .english)
        expectLockTurnedOff(rig, times: 1)
    }

    @Test func theSettingIsTheOneChosenNow() {
        let rig = SwitchRig()
        rig.choose(.capsLock)
        rig.pressCapsLock()
        #expect(rig.language == .english, "Caps Lock chosen: its press switches")
        rig.advance(0.5)
        rig.shiftTap()
        #expect(rig.language == .english, "and Shift's tap doesn't")
        expectLockTurnedOff(rig, times: 1)

        rig.advance(0.5)
        rig.choose(.shift)
        rig.lock(true)
        #expect(rig.language == .english, "Shift chosen again: Caps Lock is Caps Lock")
        rig.advance(0.1)
        #expect(!rig.letter() && rig.host.document == "A", "capitals go to the app")
        rig.advance(0.5)
        rig.lock(false)
        #expect(rig.language == .english)
        rig.advance(0.5)
        rig.shiftTap()
        #expect(rig.language == .chinese, "Shift's tap switches again")
        expectLockTurnedOff(rig, times: 1)
    }

    // MARK: The setting in the config

    @Test func theConfigReadsAndWritesTheSwitchKey() throws {
        func decode(_ text: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(text.utf8)) }
        func encoded(_ config: Config) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        }
        #expect(SwitchKey.shift.rawValue == "shift" && SwitchKey.capsLock.rawValue == "capsLock")
        #expect(SwitchKey(rawValue: "capsLock") == .capsLock && SwitchKey(rawValue: "shift") == .shift)

        #expect(try decode(#"{"switchKey": "capsLock"}"#).switchKey == .capsLock)
        #expect(try decode(#"{"switchKey": "shift"}"#).switchKey == .shift)
        #expect(try decode(#"{"provider": "anthropic"}"#).switchKey == .shift, "missing: the default")
        for unknown in [#""fn""#, #""CapsLock""#, #""""#, "1", "true", "null"] {
            #expect(try decode(#"{"switchKey": \#(unknown)}"#).switchKey == .shift, "\(unknown): the default")
        }

        #expect(try encoded(.default)["switchKey"] == nil, "the default isn't written")
        let fromBefore = try decode(#"{"checkForUpdates": false, "provider": "anthropic"}"#)
        #expect(try encoded(fromBefore)["switchKey"] == nil, "a file from before the setting doesn't gain the key")
        var caps = Config.default
        caps.switchKey = .capsLock
        #expect(try encoded(caps)["switchKey"] as? String == "capsLock")
        let saved = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(caps))
        #expect(saved.switchKey == .capsLock && saved == caps)
        var back = caps
        back.switchKey = .shift
        #expect(try encoded(back)["switchKey"] == nil, "back to Shift: the key goes")
        #expect(Config.allKeys.contains("switchKey"))
    }

    @Test func theSwitchKeySyncsThroughICloudAsLearningEnglishWordsDoes() {
        #expect(ICloudSync.settingsKeys.contains("switchKey"))
        #expect(ICloudSync.category(of: "switchKey") != nil)
        #expect(ICloudSync.category(of: "switchKey") == ICloudSync.category(of: "learnsEnglishWords"))
        var caps = Config.default
        caps.switchKey = .capsLock
        #expect(ICloudSync.values(of: .default, in: [.settings])["switchKey"] == .string("shift"), "synced either way")
        #expect(ICloudSync.values(of: caps, in: [.settings])["switchKey"] == .string("capsLock"))
        let env = ICloudSync.Environment()
        #expect(ICloudSync.problem("switchKey", .string("capsLock"), environment: env) == nil)
        #expect(ICloudSync.problem("switchKey", .string("shift"), environment: env) == nil)
        #expect(ICloudSync.problem("switchKey", .bool(true), environment: env) != nil)
        #expect(ICloudSync.problem("switchKey", .string("fn"), environment: env) != nil)
    }

    // MARK: Settings

    private func settings(language: String, _ extra: String = "") throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("switch-key-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"inputLanguages":["zh","en"],"uiLanguage":"\#(language)"\#(extra)}"#.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins"))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: library, secrets: .inMemory()), url)
    }

    @Test func settingsOffersTheChoiceUnderTheInputLanguages() throws {
        for (language, label, shift, caps) in [("en", "Switch input language", "Tap Shift", "Caps Lock"),
                                               ("zh", "切换输入语言", "单按 Shift", "按大写锁定键")] {
            let (service, url) = try settings(language: language)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let document = service.document()
            let field = try #require(document.field("switchKey"), "\(language): no switchKey field")
            #expect(field.label == label, "\(language)")
            #expect(field.value == .string("shift"), "\(language): Shift by default")
            let choices = try #require(field.choices, "\(language)")
            #expect(choices.map(\.value) == [.string("shift"), .string("capsLock")], "\(language)")
            #expect(choices.map(\.label) == [shift, caps], "\(language)")
            let section = try #require(document.sections.first { $0.fields.contains { $0.id == "inputLanguages" } })
            let ids = section.fields.map(\.id)
            let languages = try #require(ids.firstIndex(of: "inputLanguages"))
            let key = try #require(ids.firstIndex(of: "switchKey"), "\(language): not with the input languages")
            #expect(key > languages, "\(language): under the input languages")

            _ = try service.set("switchKey", to: .string("capsLock")).get()
            #expect(try Config.load(from: url).switchKey == .capsLock, "\(language): saved")
            #expect(service.document().field("switchKey")?.value == .string("capsLock"))
            _ = try service.set("switchKey", to: .string("shift")).get()
            #expect(try Config.load(from: url).switchKey == .shift)
        }
    }

    @Test func theInputLanguagesNoteNamesTheChosenKey() throws {
        let (shift, shiftURL) = try settings(language: "en")
        defer { try? FileManager.default.removeItem(at: shiftURL.deletingLastPathComponent()) }
        #expect(shift.document().field("inputLanguages")?.help == "Tap Shift to switch; new text fields start in the first.")

        let (caps, capsURL) = try settings(language: "en", #","switchKey":"capsLock""#)
        defer { try? FileManager.default.removeItem(at: capsURL.deletingLastPathComponent()) }
        let help = try #require(caps.document().field("inputLanguages")?.help)
        #expect(help.contains("Caps Lock") && !help.contains("Tap Shift"), "\(help)")

        let (chinese, chineseURL) = try settings(language: "zh", #","switchKey":"capsLock""#)
        defer { try? FileManager.default.removeItem(at: chineseURL.deletingLastPathComponent()) }
        let zh = try #require(chinese.document().field("inputLanguages")?.help)
        #expect(zh.contains("大写锁定") && !zh.contains("单按 Shift"), "\(zh)")
    }

    @Test func theNewInterfaceTextIsTranslated() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: package.appendingPathComponent("Resources/Localizable.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        for key in ["Switch input language", "Tap Shift", "Caps Lock",
                    "Caps Lock no longer locks capitals; type them with Shift."] {
            let entry = try #require(strings[key], "\(key): not in the catalog")
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in StringCatalogCheck.languages {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                #expect(!value.isEmpty, "\(key): no \(language)")
            }
        }
    }
}
