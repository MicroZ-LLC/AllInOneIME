import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import os

extension AllInOneIMEInputController {
    /// The latest time of each modifier change handed over, whatever the text field (a copy may reach another one).
    @MainActor static var modifierEchoes = ModifierEchoes()
    /// Caps Lock's changes handed over again with a time of their own (`CapsLockCopies`), whatever the text field.
    @MainActor static var capsLockCopies = CapsLockCopies()

    /// Whether `event`, a modifier change, is one handed over before: dropped, for the session's composer (a tap of Shift
    /// or ⌥, a press of Caps Lock) and its long press of Shift (Translate as You Type) alike. Chromium and Electron apps
    /// (Slack, VS Code, Chrome, Brave) hand every modifier change over twice, the same event, after the next change too
    /// when the page is busy (`ModifierEchoes`); a page's Caps Lock change comes again with a time of its own, told by the
    /// lock (`CapsLockCopies`: with Caps Lock the switch key it switched the input language back).
    @MainActor
    static func isModifierCopy(_ event: NSEvent) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        // Each copy dropped, how long after the event's time it came (`log stream --level debug --predicate
        // 'subsystem == "com.allinoneime.inputmethod.AllInOneIME" AND eventMessage BEGINSWITH "modifier copy"'`): what
        // shows a real app hands the copy over with the event's own time.
        switch MacKeyEvents.copy(event, now: now, echoes: &modifierEchoes, capsLock: &capsLockCopies, lockOn: { CapsLockKey.isOn() }) {
        case .echo?:
            logCopy(event, now: now, kind: "")
            return true
        case .capsLock?:
            logCopy(event, now: now, kind: " (Caps Lock, a time of its own)")
            return true
        case nil:
            return false
        }
    }

    private static func logCopy(_ event: NSEvent, now: TimeInterval, kind: String) {
        let late = (now - event.timestamp) * 1000
        log.debug("""
            modifier copy dropped\(kind, privacy: .public): key \(event.keyCode, privacy: .public), flags \
            \(event.modifierFlags.rawValue, format: .hex(includePrefix: true), privacy: .public), \
            \(late, format: .fixed(precision: 1), privacy: .public) ms after its time
            """)
    }
}
