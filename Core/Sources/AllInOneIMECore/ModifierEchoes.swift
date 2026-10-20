import Foundation

/// Tells a modifier change handed over a second time from a new one. Chromium and Electron apps (Slack, VS Code, Chrome)
/// hand the input method every modifier change twice: AppKit hands it over in `-[NSApplication sendEvent:]`, and Chromium
/// sends a key event the page let go by through it again (`-[CommandDispatcher redispatchKeyEvent:]`), the same event:
/// its key, its flags, its time. Mostly 5–20 ms later, before the next change; with the page busy (Slack's often is for
/// more than 100 ms, about as long as a tap of Shift) after it: down, up, down again, up again, which the composer takes
/// for two taps (the input language switched back) and the long press of Shift for another press. The shell asks first,
/// before the composer and the long press see a change (macOS: `AllInOneIMEInputController.handleFlagsChanged`), the
/// same for every text field: a copy may reach another one.
public struct ModifierEchoes: Equatable, Sendable {
    /// How many changes it keeps: a busy page's copies may come after a few more (Shift for each capital, the modifiers
    /// of a shortcut).
    public static let kept = 16

    private struct Change: Equatable, Sendable {
        var keyCode: UInt16
        var flags: UInt
        var timestamp: TimeInterval
    }

    /// The last changes handed over, the latest last.
    private var seen: [Change] = []

    public init() {}

    /// A modifier changed: `keyCode` the key, `flags` the event's modifier flags with every bit it has (the Mac's
    /// `NSEvent.modifierFlags.rawValue`: the sides, Caps Lock, fn), `timestamp` its time. True when it is one of the last
    /// `kept` handed over again: the same key, flags and time (two changes never have all three alike: each has its own
    /// time). A time of 0 is none: such a change is never taken for a copy.
    public mutating func isEcho(keyCode: UInt16, flags: UInt, timestamp: TimeInterval) -> Bool {
        guard timestamp > 0 else { return false }
        let change = Change(keyCode: keyCode, flags: flags, timestamp: timestamp)
        if seen.contains(change) { return true }
        seen.append(change)
        if seen.count > Self.kept { seen.removeFirst(seen.count - Self.kept) }
        return false
    }
}
