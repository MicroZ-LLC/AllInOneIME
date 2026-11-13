import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner's 2026-11-13 contract: Caps Lock taps change language inside AllInOneIME, using Shift's
/// existing language-switch path. A hold remains the system's ordinary capitals lock.
///
/// Assumed new API for implementers: `ModifierChange(..., pressed: Bool)` distinguishes physical
/// Caps Lock down/up even when its lock-state flag is unchanged on release. On a short tap Core
/// emits `.platform(.setCapsLock(false))`; the Mac shell handles that action through its lock-state
/// protocol. `FakeHost.platformActions` records it without accessing keyboard hardware.
private final class CapsLockTestClock {
    var now: TimeInterval = 100
    func advance(_ seconds: TimeInterval) { now += seconds }
}

private final class CapsLockRig {
    let clock = CapsLockTestClock()
    let host: FakeHost

    init(secureAnywhere: Bool = false) {
        var config = Config.default
        config.inputLanguages = [.chinese, .english]
        config.defaultInput = .chinese
        var services = SessionServices(loadSettings: { config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.secureInputActive = { secureAnywhere }
        host = FakeHost(services: services)
        host.appTypesKeys = true
        host.focus()
    }

    func caps(_ pressed: Bool, lockOn: Bool) {
        host.modifiers(ModifierChange(key: .capsLock, modifiers: lockOn ? .capsLock : [],
                                      timestamp: clock.now, pressed: pressed))
    }

    func capTap(held: TimeInterval = 0.1, lockOnAfterPress: Bool = true) {
        caps(true, lockOn: lockOnAfterPress)
        clock.advance(held)
        caps(false, lockOn: lockOnAfterPress)
    }

    func shiftTap() {
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift],
                                      timestamp: clock.now))
        clock.advance(0.1)
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: clock.now))
    }

    var clearedLock: Int { host.platformActions.filter { $0 == .setCapsLock(false) }.count }
}

@Suite("Caps Lock toggles Chinese and English")
struct CapsLockToggleTests {
    @Test func aShortPressMatchesShiftInBothDirectionsAndClearsThePhysicalLock() {
        let caps = CapsLockRig(), shift = CapsLockRig()
        #expect(caps.host.composer.inputLanguage == .chinese)

        caps.capTap()
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == .english)
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        #expect(caps.clearedLock == 1, "the Mac host must be asked to turn off the light and lowercase state")

        caps.clock.advance(1)
        shift.clock.advance(1)
        caps.capTap(lockOnAfterPress: true)
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == .chinese)
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        #expect(caps.clearedLock == 2)
    }

    @Test func aLongPressLeavesCapitalsOnAndLettersGoStraightToTheApp() {
        let rig = CapsLockRig()
        rig.capTap(held: 0.6)
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0)
        let handled = rig.host.press(KeyEvent(keyCode: 0, characters: "A", modifiers: .capsLock))
        #expect(!handled, "Caps Lock capitals belong to the application, not pinyin")
        #expect(rig.host.document == "A")
        #expect(rig.host.marked.isEmpty && !rig.host.composer.isComposing)
        rig.clock.advance(1)
        rig.capTap(held: 0.6, lockOnAfterPress: false)
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0, "a second long press turns the lock off in macOS")
    }

    @Test func aKeyBetweenPressAndReleaseCancelsTheLanguageTap() {
        let rig = CapsLockRig()
        rig.caps(true, lockOn: true)
        rig.clock.advance(0.05)
        _ = rig.host.press(KeyEvent(keyCode: 0, characters: "A", modifiers: .capsLock))
        rig.clock.advance(0.05)
        rig.caps(false, lockOn: true)
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0)
        #expect(rig.host.document == "A")
    }

    @Test func secureInputLeavesCapsLockToTheSystem() {
        let rig = CapsLockRig()
        rig.host.secure = true
        rig.capTap()
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0)
    }

    @Test func systemSecureInputLeavesCapsLockToTheSystem() {
        let rig = CapsLockRig(secureAnywhere: true)
        rig.capTap()
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0)
    }

    @Test func aKnownPasswordFieldLeavesCapsLockToTheSystem() {
        let rig = CapsLockRig()
        rig.host.send(.passwordField(true, focus: rig.host.session.fieldSession))
        rig.capTap()
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0)
    }

    @Test func aCompositionHasExactlyTheShiftTapResult() {
        let caps = CapsLockRig(), shift = CapsLockRig()
        caps.host.type("nihao")
        shift.host.type("nihao")
        #expect(caps.host.composer.isComposing && shift.host.composer.isComposing)
        let capStart = caps.host.outputs.count, shiftStart = shift.host.outputs.count

        caps.capTap()
        shift.shiftTap()
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.document == shift.host.document, "Caps Lock must commit exactly what Shift commits")
        #expect(caps.host.marked == shift.host.marked)
        #expect(caps.host.composer.isComposing == shift.host.composer.isComposing)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
        let capsCommits = caps.host.outputs[capStart...].compactMap { output -> String? in
            if case let .commit(text) = output { text } else { nil }
        }
        let shiftCommits = shift.host.outputs[shiftStart...].compactMap { output -> String? in
            if case let .commit(text) = output { text } else { nil }
        }
        #expect(capsCommits == shiftCommits, "the same composition commit as Shift")
        #expect(caps.clearedLock == 1)
    }

    @Test func aTapKeepsTheSamePerFieldLanguageMemoryAsShift() {
        let caps = CapsLockRig(), shift = CapsLockRig()
        caps.capTap()
        shift.shiftTap()
        caps.host.send(.blur)
        shift.host.send(.blur)
        caps.host.focus()
        shift.host.focus()
        #expect(caps.host.composer.inputLanguage == shift.host.composer.inputLanguage)
        #expect(caps.host.noticeAlone == shift.host.noticeAlone)
    }
}
