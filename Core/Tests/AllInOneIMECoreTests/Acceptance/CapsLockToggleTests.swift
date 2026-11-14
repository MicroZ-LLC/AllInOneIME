import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner's 2026-11-13 contract (0.7.4): a double press of Caps Lock switches Chinese and English, as a tap of Shift does.
/// The first press turns the lock on, the second, within `Composer.shiftTapWindow` of it (measured between the two lock
/// changes), turns it off and switches. One press is Caps Lock as always. The input method never changes the lock itself.
///
/// macOS tells an input method only when the lock changes, never the key's release, so the Mac shell hands each lock
/// change to the session as `ModifierChange(key: .capsLock, modifiers: <.capsLock when the lock is now on>, timestamp:)`,
/// `pressed` left to its default; these tests drive it the same way, nothing else.
private final class Pointer {
    /// Whether the shell says the mouse or trackpad was used.
    var used = false
    /// The seconds each question about it looked back.
    var asked: [TimeInterval] = []
}

private final class CapsLockRig {
    /// The rig's clock: the events' timestamps.
    var now: TimeInterval = 100
    /// The mouse or trackpad as the shell tells it (`SessionServices.pointerUsedWithin`).
    let pointer: Pointer
    /// The lock as the rig last told it, and the other modifiers held (their kind and left side bits).
    private(set) var lockOn = false
    private(set) var held: Modifiers = []
    let host: FakeHost

    init(secureAnywhere: Bool = false) {
        var config = Config.default
        config.inputLanguages = [.chinese, .english]
        config.defaultInput = .chinese
        var services = SessionServices(loadSettings: { config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.secureInputActive = { secureAnywhere }
        let pointer = Pointer()
        self.pointer = pointer
        services.pointerUsedWithin = { seconds in
            pointer.asked.append(seconds)
            return pointer.used
        }
        host = FakeHost(services: services)
        host.appTypesKeys = true
        host.focus()
    }

    func advance(_ seconds: TimeInterval) { now += seconds }

    /// Caps Lock's lock changed (on or off), as the Mac shell tells it: no `pressed`, the lock in `modifiers`.
    func lock(_ on: Bool) {
        lockOn = on
        host.modifiers(ModifierChange(key: .capsLock, modifiers: held.union(on ? .capsLock : []), timestamp: now))
    }

    /// Two presses of Caps Lock `gap` seconds apart: the lock on, then off.
    func doublePress(gap: TimeInterval = 0.2) {
        lock(true)
        advance(gap)
        lock(false)
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

    /// Shift pressed and released on its own, 0.1 s apart: the tap the double press must equal.
    func shiftTap() {
        modifier(.shift, down: true)
        advance(0.1)
        modifier(.shift, down: false)
    }

    /// A letter key ("a") typed, a capital with the lock on: whether the session took it.
    @discardableResult
    func letter() -> Bool {
        host.press(KeyEvent(keyCode: 0, characters: lockOn ? "A" : "a", modifiers: lockOn ? .capsLock : []))
    }

    /// The commits since `start` (an index into `host.outputs`).
    func commits(since start: Int) -> [String] {
        host.outputs[start...].compactMap { output -> String? in
            if case let .commit(text) = output { text } else { nil }
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

/// The input method never changes the lock itself: no `PlatformAction` at all (nothing else in these rigs asks one; this
/// leaves out the old `.setCapsLock` case by name, which may be gone).
private func expectLockLeftAlone(_ rig: CapsLockRig, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(rig.host.platformActions.isEmpty,
            "the input method must never set Caps Lock's lock itself, asked: \(rig.host.platformActions)",
            sourceLocation: sourceLocation)
    #expect(!rig.host.platformActions.contains { "\($0)".contains("setCapsLock") }, sourceLocation: sourceLocation)
}

@Suite("A double press of Caps Lock switches Chinese and English")
struct CapsLockToggleTests {
    // MARK: A double press is Shift's tap

    @Test func aDoublePressSwitchesBothWaysAsShiftsTapDoes() {
        let caps = CapsLockRig(), shift = CapsLockRig()
        #expect(caps.host.composer.inputLanguage == .chinese)

        caps.doublePress()
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == .english, "on, then off within half a second: a switch")
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.noticeAlone != nil && caps.host.noticeAlone == shift.host.noticeAlone, "the same notice as Shift's tap")
        #expect(!caps.lockOn)

        caps.advance(1)
        shift.advance(1)
        caps.doublePress()
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == .chinese, "and back")
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        expectLockLeftAlone(caps)
        expectLockLeftAlone(shift)
    }

    @Test func theSecondPressJustWithinTheWindowStillSwitches() {
        let rig = CapsLockRig()
        rig.doublePress(gap: Composer.shiftTapWindow - 0.05)
        #expect(rig.host.composer.inputLanguage == .english)
        expectLockLeftAlone(rig)
    }

    @Test func aDoublePressKeepsTheSamePerFieldLanguageMemoryAsShift() {
        let caps = CapsLockRig(), shift = CapsLockRig()
        caps.doublePress()
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == .english)

        caps.host.send(.blur)
        shift.host.send(.blur)
        caps.host.focus()
        shift.host.focus()
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage, "the same field again")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)

        for rig in [caps, shift] {
            rig.host.send(.blur)
            rig.host.app = "com.example.other"
            rig.host.focus()
        }
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage, "another app's field")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)

        for rig in [caps, shift] {
            rig.host.send(.blur)
            rig.host.app = "com.example.editor"
            rig.host.focus()
        }
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage, "back in the first app")
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        expectLockLeftAlone(caps)
    }

    @Test func aCompositionHasExactlyTheShiftTapResult() {
        let caps = CapsLockRig(), shift = CapsLockRig()
        caps.host.type("nihao")
        shift.host.type("nihao")
        #expect(caps.host.composer.isComposing && shift.host.composer.isComposing)
        let capsStart = caps.host.outputs.count, shiftStart = shift.host.outputs.count

        caps.doublePress()
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == .english)
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.document == shift.host.document, "Caps Lock must commit exactly what Shift commits")
        #expect(caps.host.marked == shift.host.marked)
        #expect(caps.host.composer.isComposing == shift.host.composer.isComposing)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        #expect(caps.commits(since: capsStart) == shift.commits(since: shiftStart), "the same composition commit as Shift")
        expectLockLeftAlone(caps)
    }

    // MARK: One press is Caps Lock as always

    @Test func onePressIsCapitalsForTheAppAndALaterOffDoesNotSwitch() {
        let rig = CapsLockRig()
        rig.lock(true)
        #expect(rig.host.composer.inputLanguage == .chinese)
        rig.advance(0.1)
        let handled = rig.letter()
        #expect(!handled, "Caps Lock capitals belong to the application, not pinyin")
        #expect(rig.host.document == "A")
        #expect(rig.host.marked.isEmpty && !rig.host.composer.isComposing)

        rig.advance(Composer.shiftTapWindow + 0.5)
        rig.lock(false)
        #expect(rig.host.composer.inputLanguage == .chinese, "turned off later: just off, no switch")
        rig.letter()
        #expect(rig.host.composer.isComposing, "Chinese as before the lock")
        expectLockLeftAlone(rig)
    }

    @Test func theSecondPressLaterThanHalfASecondDoesNotSwitch() {
        let rig = CapsLockRig()
        rig.doublePress(gap: Composer.shiftTapWindow + 0.1)
        #expect(rig.host.composer.inputLanguage == .chinese)
        rig.doublePress(gap: 2)
        #expect(rig.host.composer.inputLanguage == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func aKeyTypedBetweenThePressesIsNoSwitch() {
        let rig = CapsLockRig()
        rig.lock(true)
        rig.advance(0.1)
        let handled = rig.letter()
        #expect(!handled)
        rig.advance(0.1)
        rig.lock(false)
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.host.document == "A", "the capital went to the app")
        expectLockLeftAlone(rig)
    }

    // MARK: Other modifiers

    @Test func anotherModifierHeldAtBothPressesIsNoSwitch() {
        let rig = CapsLockRig()
        for kind in Key.ModifierKind.allCases {
            // Held longer than a tap of it, so its own release is no tap either.
            rig.modifier(kind, down: true)
            rig.advance(0.4)
            rig.doublePress()
            rig.advance(0.4)
            rig.modifier(kind, down: false)
            #expect(rig.host.composer.inputLanguage == .chinese, "Caps Lock twice with \(kind) held switched")
            rig.advance(1)
        }
        expectLockLeftAlone(rig)
    }

    @Test func shiftHeldAtTheFirstPressOnlyIsNoSwitch() {
        let rig = CapsLockRig()
        rig.modifier(.shift, down: true)
        rig.advance(0.6)
        rig.lock(true)
        rig.advance(0.1)
        rig.modifier(.shift, down: false)
        rig.advance(0.1)
        rig.lock(false)
        #expect(rig.host.composer.inputLanguage == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func commandHeldAtTheSecondPressOnlyIsNoSwitch() {
        let rig = CapsLockRig()
        rig.lock(true)
        rig.advance(0.1)
        rig.modifier(.command, down: true)
        rig.advance(0.1)
        rig.lock(false)
        rig.advance(0.6)
        rig.modifier(.command, down: false)
        #expect(rig.host.composer.inputLanguage == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func aModifierPressedAndReleasedBetweenThePressesIsNoSwitch() {
        let rig = CapsLockRig()
        rig.lock(true)
        rig.advance(0.05)
        rig.modifier(.control, down: true)
        rig.advance(0.05)
        rig.modifier(.control, down: false)
        rig.advance(0.05)
        rig.lock(false)
        #expect(rig.host.composer.inputLanguage == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func fnHeldStillSwitches() {
        let rig = CapsLockRig()
        rig.fn(down: true)
        rig.advance(0.1)
        rig.doublePress()
        rig.advance(0.1)
        rig.fn(down: false)
        #expect(rig.host.composer.inputLanguage == .english, "fn doesn't count, as with Shift's tap")
        expectLockLeftAlone(rig)
    }

    // MARK: The mouse or trackpad

    @Test func thePointerUsedBetweenThePressesIsNoSwitch() {
        let rig = CapsLockRig()
        let gap = 0.3
        rig.lock(true)
        rig.advance(gap)
        rig.pointer.used = true
        rig.lock(false)
        rig.pointer.used = false
        #expect(rig.host.composer.inputLanguage == .chinese, "a Caps-Lock-click is no double press")
        #expect(rig.pointer.asked.contains { abs($0 - gap) < 0.05 },
                "asked about the time between the two lock changes, asked: \(rig.pointer.asked)")

        // The same without the pointer switches.
        rig.advance(1)
        rig.doublePress(gap: gap)
        #expect(rig.host.composer.inputLanguage == .english)
        expectLockLeftAlone(rig)
    }

    // MARK: Caps Lock is the system's where nothing may leave the device

    @Test func secureInputInTheFieldLeavesCapsLockToTheSystem() {
        let rig = CapsLockRig()
        rig.host.secure = true
        rig.doublePress()
        #expect(rig.host.composer.inputLanguage == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func secureInputAnywhereLeavesCapsLockToTheSystem() {
        let rig = CapsLockRig(secureAnywhere: true)
        rig.doublePress()
        #expect(rig.host.composer.inputLanguage == .chinese)
        expectLockLeftAlone(rig)
    }

    @Test func aKnownPasswordFieldLeavesCapsLockToTheSystem() {
        let rig = CapsLockRig()
        rig.host.send(.passwordField(true, focus: rig.host.session.fieldSession))
        rig.doublePress()
        #expect(rig.host.composer.inputLanguage == .chinese)
        expectLockLeftAlone(rig)
    }

    // MARK: Presses in a row

    @Test func onOffOnOffQuicklyIsTwoDoublePresses() {
        let caps = CapsLockRig(), shift = CapsLockRig()
        caps.lock(true)
        caps.advance(0.2)
        caps.lock(false)
        #expect(caps.host.composer.inputLanguage == .english)
        caps.advance(0.2)
        caps.lock(true)
        #expect(caps.host.composer.inputLanguage == .english, "an off then an on is no double press")
        caps.advance(0.2)
        caps.lock(false)
        #expect(caps.host.composer.inputLanguage == .chinese, "two switches: back where it started")

        shift.shiftTap()
        shift.advance(0.2)
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        expectLockLeftAlone(caps)
    }

    @Test func onOffThenOnLeavesTheLockOnWithNoExtraSwitch() {
        let rig = CapsLockRig()
        rig.doublePress()
        #expect(rig.host.composer.inputLanguage == .english)
        rig.advance(0.2)
        rig.lock(true)
        #expect(rig.host.composer.inputLanguage == .english, "the lock on again: no switch")
        rig.advance(0.1)
        #expect(!rig.letter(), "capitals go to the app")
        #expect(rig.host.document == "A")

        rig.advance(Composer.shiftTapWindow + 0.5)
        rig.lock(false)
        #expect(rig.host.composer.inputLanguage == .english, "its own off came too late: no switch")
        expectLockLeftAlone(rig)
    }

    @Test func anOffThenAQuickOnPairsOnlyWithItsOwnOff() {
        let rig = CapsLockRig()
        rig.lock(true)
        rig.advance(1)
        rig.lock(false)
        #expect(rig.host.composer.inputLanguage == .chinese, "the lock was on a while: just off")
        rig.advance(0.2)
        rig.lock(true)
        #expect(rig.host.composer.inputLanguage == .chinese, "off then on is no double press")
        rig.advance(0.2)
        rig.lock(false)
        #expect(rig.host.composer.inputLanguage == .english, "that on and its own quick off are")
        expectLockLeftAlone(rig)
    }
}
