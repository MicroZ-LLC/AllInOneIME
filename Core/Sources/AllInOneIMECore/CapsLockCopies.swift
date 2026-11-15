import Foundation

/// Tells Caps Lock's change handed over a second time from a press. Chromium's pages (Brave's, Chrome's) hand the input
/// method a modifier change again; Shift's copy has the change's own time and `ModifierEchoes` drops it, but Caps Lock's
/// comes with a time of its own, tens of milliseconds later, sometimes after the lock's going off (Brave 1.99's page
/// fields, 2026-11-14: a copy 34 ms after the press; another 6 ms after the lock went off). With Caps Lock the switch key
/// each change that says the lock went on is a press, so the copy switched the input language back: a page field stayed
/// in English (the address bar, no page, was fine).
///
/// A time can't tell it (presses 60 ms apart each switch), the lock can: a press turns it on before its change is handed
/// over, and the input method turns it off again at once (`PlatformAction.setCapsLock(false)`); a copy says the lock is
/// on while it is off and hasn't been seen on since the copy's time. A press while the input method keeps the lock off
/// after the last one (the Mac's `CapsLockKey.keepOff`) may find the lock off already, but it was seen on after the
/// press's time (`lockSeenOn`): a press. The shell asks before the session sees the change, the same for every field.
public struct CapsLockCopies: Equatable, Sendable {
    /// The latest time the lock was seen on, on the uptime clock (the changes' times are on it too).
    private var seenOnAt: TimeInterval?

    public init() {}

    /// The lock was seen on at `time` (`now` of a change handed over, or a check while it is kept off).
    public mutating func lockSeenOn(at time: TimeInterval) {
        seenOnAt = max(seenOnAt ?? time, time)
    }

    /// A Caps Lock change: `saysOn` whether its flags have the lock on, `lockOn` whether the lock is on now, `timestamp`
    /// its time, `now` the time it is handed over. True when it is a copy: it says the lock is on, the lock is off, and
    /// it was last seen on before the change's time. Never one where the lock was never seen on (none to copy). A press
    /// finding the lock on was on from its own time, not from when it was handed over: one handed over late (the main
    /// thread busy for 34 ms or more) would otherwise be seen on after its copy's time, and the copy taken for a press.
    public mutating func isCopy(saysOn: Bool, lockOn: Bool, timestamp: TimeInterval, now: TimeInterval) -> Bool {
        if lockOn {
            lockSeenOn(at: min(now, timestamp))
            return false
        }
        guard saysOn, let seenOnAt else { return false }
        return seenOnAt < timestamp
    }
}
