import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import InputMethodKit
import os

extension AllInOneIMEInputController {
    /// The latest time of each modifier change handed over, whatever the text field (a copy may reach another one).
    @MainActor static var modifierEchoes = ModifierEchoes()
    /// Caps Lock's changes handed over again with a time of their own (`CapsLockCopies`), whatever the text field.
    @MainActor static var capsLockCopies = CapsLockCopies()

    /// The modifier changes the session took for itself (`handleFlagsChanged`), whatever the text field: their copies
    /// are taken too, however late they come.
    @MainActor static var modifiersTaken = TakenModifierChanges()

    /// A change of the modifiers. True: the input method's alone, kept from the app: the right ⌥'s press and release
    /// while pinyin is typed with shape codes on, its tap "`" (`SessionResponse.handled`, both or neither:
    /// `Composer.tookModifierChange`; the owner, 2026-11-26), and those events handed over again. False for every other
    /// one: the application sees modifier changes too.
    @MainActor
    func handleFlagsChanged(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        commitRow()  // a row the key before put in, if this change came first
        // Chromium's and Electron's second copy: dropped, and the app's or not as the first was (the same event, its time).
        guard !Self.isModifierCopy(event) else { return Self.modifiersTaken.took(at: event.timestamp) }
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        // The key was held up to the event; the pointer is asked later, so look back that much further. fn held with Shift
        // is no long press of it (only the session's long press minds fn).
        let change = MacKeyEvents.modifierChange(event, now: ProcessInfo.processInfo.systemUptime)
        let context = fieldReading.context(in: target) { session.fieldWants(forModifiers: change, given: $0) }
        // The session times a long press of Shift itself: Translate as You Type on or off (not in Code).
        let response = session.handle(.modifiers(change, context))
        apply(response.outputs, client: client)
        if response.handled { Self.modifiersTaken.take(at: event.timestamp) }
        return response.handled
    }

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
