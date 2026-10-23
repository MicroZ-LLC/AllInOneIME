import AppKit
import Carbon
import InputMethodKit

/// Secure event input is a session-wide flag: password fields, terminals' "Secure Keyboard Entry",
/// sudo prompts and the lock screen turn it on. macOS reports only one owner process and may
/// attribute it to loginwindow, so the owner can't always be trusted.
///
/// Policy: while it is on, nothing is ever sent to the model (InputController checks that before
/// every conversion). Local composing is also turned off in the app that reports owning it, in
/// terminals (their password prompts don't restrict input sources), and when the owner is unknown.
enum SecureInput {
    static var isOn: Bool { IsSecureEventInputEnabled() }

    /// Process that turned on secure event input: nil when off, -1 when on but the owner is unknown.
    static func ownerPID() -> pid_t? {
        guard isOn else { return nil }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard let pid = session?["kCGSSessionSecureInputPID"] as? NSNumber else { return -1 }
        return pid_t(truncating: pid)
    }

    /// Terminal apps, by bundle ID. A terminal runs every line it's given, so output goes in as one line there
    /// (InputController.isTerminal); ⌘V is left to it (`pastesIntoDraft`), and nothing is composed in it during
    /// secure input. A terminal inside an editor (VS Code, Cursor, JetBrains) has the editor's bundle ID, so it
    /// can't be told apart from the editor.
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "dev.warp.Warp-Preview", "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
        "co.zeit.hyper", "org.tabby", "com.raphaelamorim.rio", "dev.commandline.waveterm",
    ]

    /// True when nothing should be composed for `client` (keys then go to the app as typed).
    static func blocksComposing(_ client: IMKTextInput?) -> Bool {
        guard let pid = ownerPID() else { return false }
        let target = client?.bundleIdentifier()
        if let target, terminals.contains(target) { return true }
        guard pid > 0,
              let owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              let target
        else { return true }  // can't tell who owns it: be safe
        return owner == target
    }

    /// Whether the focused element is a password field as Accessibility tells it (`AXSecureTextField`): one whose app
    /// doesn't turn secure event input on for it, or not yet (a web page's, a field of the app's own drawing). Nil where it
    /// can't be told: Accessibility not allowed (never asked for here), nothing focused, no answer within a quarter of a
    /// second.
    static func focusedFieldIsSecure() -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement  // checked just above
        AXUIElementSetMessagingTimeout(element, 0.25)
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else { return false }
        return subrole as? String == kAXSecureTextFieldSubrole as String
    }

    static func ownerDescription() -> String {
        guard let pid = ownerPID() else { return "off" }
        let name = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)" : "unknown"
        return "held by \(name)"
    }
}
