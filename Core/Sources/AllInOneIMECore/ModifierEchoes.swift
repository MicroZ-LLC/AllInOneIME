import Foundation

/// Tells a modifier change handed over a second time from a new one. Chromium and Electron apps (Slack, VS Code, Chrome)
/// hand the input method every modifier change twice: AppKit hands it over in `-[NSApplication sendEvent:]`, and Chromium
/// sends a key event the page let go by through it again (`-[CommandDispatcher redispatchKeyEvent:]`), the same event:
/// its key, its flags, its time. Mostly 5–20 ms later, before the next change; with the page busy (Slack's often is for
/// more than 100 ms, about as long as a tap of Shift) after it, and after as many more as came meanwhile (Shift's down
/// and up for each capital typed): down, up, down again, up again, which the composer takes for two taps (the input
/// language switched back) and the long press of Shift for another press. The shell asks first, before the composer and
/// the long press see a change (macOS: `AllInOneIMEInputController.handleFlagsChanged`), the same for every text field:
/// a copy may reach another one.
///
/// A copy is a change no later than the latest one of its key with the same flags, and no more than `window` before it:
/// the same change again, or one from before a later press of that key. Not only among the last few changes: however
/// many came between, a copy is one. This never takes a new change for a copy while each key's changes come in the order of
/// their times, each at a time of its own, as the keyboard's do (the clock ticks every few tens of nanoseconds).
/// Synthesized ones needn't: a tool that posts the same CGEvent again, gives its events one time
/// (`NSEvent.keyEvent(…timestamp:…)` with a constant) or an earlier one has the later change taken for a copy and
/// dropped; two taps of Shift sent at one time switch the input language once. A change at a time still to come (a
/// tool's, in another unit or from another clock) is neither a copy nor kept: kept, it would take every change of its
/// key and flags after it for a copy until its time came, and be the latest of them, never forgotten, till then.
public struct ModifierEchoes: Equatable, Sendable {
    /// How many keys with their flags it keeps the latest time of: far more than come between a change and its copy
    /// (Shift's down and up are two, however many capitals are typed); past that, the one seen longest ago is forgotten.
    public static let kept = 64

    /// How long before the latest change of its key and flags a copy may be, in seconds: Chromium's come within tens
    /// of milliseconds, a busy page's after hundreds (after nine capitals, the first press's copy about a second after
    /// the last press). A change from longer before is one of its own.
    public static let window: TimeInterval = 5

    private struct Change: Hashable, Sendable {
        var keyCode: UInt16
        var flags: UInt
    }

    /// The latest time of each key with its flags handed over.
    private var latest: [Change: TimeInterval] = [:]

    public init() {}

    /// A modifier changed: `keyCode` the key, `flags` the event's modifier flags with every bit it has (the Mac's
    /// `NSEvent.modifierFlags.rawValue`: the sides, Caps Lock, fn), `timestamp` its time, `now` the time on the same
    /// clock as it is handed over (the Mac's `ProcessInfo.systemUptime`). True when it is a copy: the same key and flags
    /// as a change handed over, its time the same or earlier, by `window` at most. A time of 0 is none, and one later
    /// than `now` is still to come: such a change is never taken for a copy, nor kept.
    public mutating func isEcho(keyCode: UInt16, flags: UInt, timestamp: TimeInterval, now: TimeInterval) -> Bool {
        guard timestamp > 0, timestamp <= now else { return false }
        let change = Change(keyCode: keyCode, flags: flags)
        if let last = latest[change], timestamp <= last { return last - timestamp <= Self.window }
        latest[change] = timestamp
        if latest.count > Self.kept, let oldest = latest.min(by: { $0.value < $1.value }) { latest[oldest.key] = nil }
        return false
    }
}
