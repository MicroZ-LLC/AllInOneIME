import Foundation
import Testing
@testable import AllInOneIMECore

/// Caps Lock's change handed over again by a Chromium page (`CapsLockCopies`), with the times seen in Brave 1.99's page
/// fields on the owner's iMac (2026-11-14): one press, its copy 34 ms later with a time of its own; or the lock's going
/// off first and the press's copy 6 ms after that.
struct CapsLockCopiesTests {
    /// `copies.isCopy`, its answer apart (`#expect` takes no mutating call).
    private func copy(_ copies: inout CapsLockCopies, saysOn: Bool, lockOn: Bool, at time: TimeInterval,
                      now: TimeInterval) -> Bool {
        copies.isCopy(saysOn: saysOn, lockOn: lockOn, timestamp: time, now: now)
    }

    /// One press: the lock on as it is handed over (it turned on with the press), turned off by the input method at once.
    private func press(_ copies: inout CapsLockCopies, at time: TimeInterval) -> Bool {
        copies.isCopy(saysOn: true, lockOn: true, timestamp: time, now: time + 0.0003)
    }

    @Test func aPressIsNoCopy() {
        var copies = CapsLockCopies()
        #expect(!press(&copies, at: 100))
    }

    @Test func theCopyWithATimeOfItsOwnIsOne() {
        var copies = CapsLockCopies()
        #expect(!press(&copies, at: 302272.159827))
        // The input method turned the lock off; Chromium's copy, a time of its own.
        #expect(copy(&copies, saysOn: true, lockOn: false, at: 302272.194094, now: 302272.199946))
        // The lock's going off, and that one's copy: no press either way.
        #expect(!copy(&copies, saysOn: false, lockOn: false, at: 302272.228360, now: 302272.228623))
        #expect(!copy(&copies, saysOn: false, lockOn: false, at: 302272.230650, now: 302272.230843))
    }

    @Test func theCopyAfterTheLockWentOffIsOne() {
        var copies = CapsLockCopies()
        #expect(!press(&copies, at: 302388.123896))
        #expect(!copy(&copies, saysOn: false, lockOn: false, at: 302388.196863, now: 302388.197))
        #expect(copy(&copies, saysOn: true, lockOn: false, at: 302388.203162, now: 302388.2035))
    }

    @Test func pressesInARowEachArePresses() {
        var copies = CapsLockCopies()
        var time: TimeInterval = 50
        for gap in [0.05, 0.05, 0.3, 1, 0.05, 2, 0.1] {
            time += gap
            #expect(!press(&copies, at: time), "a press \(gap) s after the last")
            #expect(!copy(&copies, saysOn: false, lockOn: false, at: time + 0.01, now: time + 0.0101))
        }
    }

    /// A press handled late (here 50 ms after its time, the main thread busy): its copy, stamped 34 ms after the press,
    /// is still one. The lock was on from the press's own time, not from when it was handled.
    @Test func aPressHandledLateStillHasItsCopyKnown() {
        var copies = CapsLockCopies()
        #expect(!copy(&copies, saysOn: true, lockOn: true, at: 100.000, now: 100.050))
        #expect(copy(&copies, saysOn: true, lockOn: false, at: 100.034, now: 100.060))
    }

    /// Two presses 60 ms apart, each handled late: both are presses.
    @Test func latePressesInARowEachArePresses() {
        var copies = CapsLockCopies()
        #expect(!copy(&copies, saysOn: true, lockOn: true, at: 200.000, now: 200.050))
        #expect(!copy(&copies, saysOn: true, lockOn: true, at: 200.060, now: 200.110))
    }

    /// A press while the input method keeps the lock off after the last one (`keepOff`, every 15 ms for a second): the
    /// lock may be off again before its change is handed over, but it was seen on after the press's time.
    @Test func aPressThatKeepingTheLockOffCaughtFirstIsNoCopy() {
        var copies = CapsLockCopies()
        #expect(!press(&copies, at: 10))
        copies.lockSeenOn(at: 10.208)  // the second press at 10.2 turned it on; caught and turned off at 10.208
        #expect(!copy(&copies, saysOn: true, lockOn: false, at: 10.2, now: 10.21))
    }

    /// A change that says the lock is on, with the lock off and never seen on: none to be a copy of (the self-test's
    /// changes, or a lock turned off by something else first). Taken as a press.
    @Test func withTheLockNeverSeenOnNothingIsACopy() {
        var copies = CapsLockCopies()
        #expect(!copy(&copies, saysOn: true, lockOn: false, at: 5, now: 5.001))
        #expect(!copy(&copies, saysOn: true, lockOn: false, at: 5.2, now: 5.201))
    }

    /// Caps Lock not the switch key: the lock stays on, and its copy finds it on: no copy (the session leaves the lock to
    /// the system then anyway).
    @Test func aCopyWhileTheLockStaysOnIsLetThrough() {
        var copies = CapsLockCopies()
        #expect(!press(&copies, at: 1))
        #expect(!copy(&copies, saysOn: true, lockOn: true, at: 1.034, now: 1.035))
    }
}
