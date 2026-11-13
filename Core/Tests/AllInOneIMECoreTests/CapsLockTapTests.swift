import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A tap of Caps Lock switches Chinese and English only pressed on its own, as Shift's tap: not with Shift, Control,
/// Option or Command held, and not with the mouse or trackpad used during the press (a Caps-Lock-click). The rest of
/// its contract is in Acceptance/CapsLockToggleTests.swift.
@Suite("A Caps Lock tap counts only on its own")
struct CapsLockTapTests {
    private final class Pointer {
        /// Whether the shell says the mouse or trackpad was used.
        var used = false
        /// The seconds each question about it looked back.
        var asked: [TimeInterval] = []
    }

    private final class Rig {
        var now: TimeInterval = 100
        let pointer: Pointer
        let host: FakeHost

        init() {
            var config = Config.default
            config.inputLanguages = [.chinese, .english]
            config.defaultInput = .chinese
            var services = SessionServices(loadSettings: { config })
            let engine = FakeEngine()
            services.levelOne = { .engine(engine) }
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

        /// Caps Lock pressed and released `held` seconds later with `modifiers` down throughout, the lock on.
        func capTap(with modifiers: Modifiers = [], held: TimeInterval = 0.1) {
            host.modifiers(ModifierChange(key: .capsLock, modifiers: modifiers.union(.capsLock), timestamp: now, pressed: true))
            now += held
            host.modifiers(ModifierChange(key: .capsLock, modifiers: modifiers.union(.capsLock), timestamp: now, pressed: false))
            now += 1
        }

        var clearedLock: Int { host.platformActions.filter { $0 == .setCapsLock(false) }.count }
    }

    @Test func aModifierHeldWithCapsLockIsNoTap() {
        let rig = Rig()
        let held: [Modifiers] = [[.shift, .leftShift], [.control, .leftControl], [.option, .rightOption], [.command, .leftCommand],
                                 [.shift], [.command]]
        for modifiers in held {
            rig.capTap(with: modifiers)
            #expect(rig.host.composer.inputLanguage == .chinese, "Caps Lock with \(modifiers.rawValue) held switched")
        }
        #expect(rig.clearedLock == 0, "the lock is the system's then")
        // On its own (fn doesn't count, as with Shift's tap) it still switches.
        rig.capTap(with: .function)
        #expect(rig.host.composer.inputLanguage == .english)
        #expect(rig.clearedLock == 1)
    }

    @Test func aModifierPressedOrReleasedOnlyAtOneEndIsNoTap() {
        let rig = Rig()
        // Shift held at the press only, or only at the release.
        rig.host.modifiers(ModifierChange(key: .capsLock, modifiers: [.capsLock, .shift], timestamp: rig.now, pressed: true))
        rig.now += 0.1
        rig.host.modifiers(ModifierChange(key: .capsLock, modifiers: .capsLock, timestamp: rig.now, pressed: false))
        rig.now += 1
        rig.host.modifiers(ModifierChange(key: .capsLock, modifiers: .capsLock, timestamp: rig.now, pressed: true))
        rig.now += 0.1
        rig.host.modifiers(ModifierChange(key: .capsLock, modifiers: [.capsLock, .option], timestamp: rig.now, pressed: false))
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0)
    }

    @Test func thePointerUsedDuringThePressIsNoTap() {
        let rig = Rig()
        rig.pointer.used = true
        rig.capTap(held: 0.2)
        #expect(rig.host.composer.inputLanguage == .chinese)
        #expect(rig.clearedLock == 0)
        #expect(rig.pointer.asked.contains { abs($0 - 0.2) < 0.001 }, "asked about the press's time, as Shift's tap is")
        rig.pointer.used = false
        rig.capTap()
        #expect(rig.host.composer.inputLanguage == .english)
        #expect(rig.clearedLock == 1)
    }
}
