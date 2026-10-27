import AppKit
import ApplicationServices

/// Line breaks into a terminal. Text an input method inserts reaches a terminal as typed keys, so a line
/// break there is Return: the shell runs the line, Claude Code sends the message. A paste is different:
/// shells (zsh, bash 5) and programs like Claude Code turn on bracketed paste and take pasted line breaks
/// as text, and a terminal asks first when a paste with line breaks would run (Ghostty, iTerm2). So an
/// answer with line breaks goes into a terminal as a paste: the clipboard gets the text, ⌘V is posted,
/// and the clipboard is put back. Posting keys needs the Accessibility permission; without it the answer
/// goes in on one line as before.
enum TerminalPaste {
    /// Marks the ⌘V posted here, so the input method lets it through (`isOurs`).
    static let marker: Int64 = 0x4149_4F49  // "AIOI"

    /// Whether posting ⌘V is allowed. The first time it isn't, macOS is asked to show its permission prompt.
    @MainActor
    static func isAllowed() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !asked {
            asked = true
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        return false
    }

    @MainActor private static var asked = false

    /// Whether `event` is a ⌘V posted by `paste`, or a ⌃V by `postControlV`.
    static func isOurs(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// ⌃V to the frontmost app as it is, marked as ours so the input method lets it through: clipboard history's image
    /// row (a screenshot pasted the app's way: Claude Code's in a terminal). Needs Accessibility (asked without asking:
    /// `AXIsProcessTrusted`, before the row offers it).
    @MainActor
    static func postControlV() {
        postV(.maskControl)
    }

    /// V with `flags` down and up, marked as ours (`isOurs`).
    @MainActor
    private static func postV(_ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: down)  // V
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: marker)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Pastes `text` into the frontmost app, then puts the clipboard back once the app has read it.
    @MainActor
    static func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Clipboard managers skip transient content (nspasteboard.org).
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ours = pasteboard.changeCount

        postV(.maskCommand)
        // The app reads the clipboard when the ⌘V reaches it: wait for that before typing on or putting it back.
        try? await Task.sleep(nanoseconds: 150_000_000)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard pasteboard.changeCount == ours else { return }  // something else was copied since
            pasteboard.clearContents()
            if !saved.isEmpty {
                pasteboard.writeObjects(saved.map { types in
                    let item = NSPasteboardItem()
                    for (type, data) in types { item.setData(data, forType: type) }
                    return item
                })
            }
        }
    }
}
