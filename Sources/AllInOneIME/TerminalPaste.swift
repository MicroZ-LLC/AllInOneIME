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
    /// ⌃V to the app, marked as ours (`isOurs`), once no modifier is held: the app's own paste in a terminal or a code
    /// editor (clipboard history's image, ⌃V again).
    @MainActor
    static func postControlV() {
        Task { @MainActor in
            await modifiersUp()
            postV(.maskControl)
        }
    }

    /// ⌘V to the app, marked as ours, once no modifier is held: an app's own paste (clipboard history's image, ⌃V again
    /// elsewhere). Posted while ⌃ is still held from ⌃V, an app could read ⌃⌘V.
    @MainActor
    static func postCommandV() {
        Task { @MainActor in
            await modifiersUp()
            postV(.maskCommand)
        }
    }

    /// Until ⌘ ⌥ ⌃ ⇧ are all up on the keyboard (a second at most).
    @MainActor
    static func modifiersUp() async {
        let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<50 where !CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
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

    /// The clipboard's items as they are, each with its types in its own order (the first is what a reader takes first:
    /// clipboard history records an image only when it comes first).
    @MainActor
    private static func saved(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
    }

    /// `saved` put back on the clipboard, in its order.
    @MainActor
    private static func restore(_ saved: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        pasteboard.writeObjects(saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }

    /// Pastes `text` into the frontmost app, then puts the clipboard back once the app has read it.
    @MainActor
    static func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let before = saved(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Clipboard managers skip transient content (nspasteboard.org), clipboard history too.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ours = pasteboard.changeCount
        await modifiersUp()
        postV(.maskCommand)
        // The app reads the clipboard when the ⌘V reaches it: wait for that before typing on or putting it back.
        try? await Task.sleep(nanoseconds: 150_000_000)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard pasteboard.changeCount == ours else { return }  // something else was copied since
            restore(before, to: pasteboard)
        }
    }

    /// Hands a kept image to the app when it reads the clipboard (`NSPasteboardItemDataProvider`), so the clipboard is put
    /// back only once it has (and its TIFF made only if it is asked for).
    private final class ImageProvider: NSObject, NSPasteboardItemDataProvider {
        let png: Data
        private(set) var read = false

        init(png: Data) { self.png = png }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            if type == .png {
                item.setData(png, forType: .png)
            } else if type == .tiff, let tiff = NSImage(data: png)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            read = true
        }
    }

    /// The image being pasted (kept until the clipboard is put back).
    @MainActor private static var providing: ImageProvider?

    /// Pastes a kept image (PNG `png`) into the frontmost app with its own paste key (`controlV`: ⌃V in a terminal or a
    /// code editor, where Claude Code takes an image on it; else ⌘V), then puts the clipboard back a moment after the app
    /// has read it, or after 3 seconds if it never does (0.6.8.2, clipboard history). A reader slower than a fixed delay
    /// (Claude Code reads it with another program) still gets the image, never what was on the clipboard before.
    @MainActor
    static func pasteImage(_ png: Data, controlV: Bool) async {
        let pasteboard = NSPasteboard.general
        let before = saved(pasteboard)
        pasteboard.clearContents()
        let provider = ImageProvider(png: png)
        providing = provider
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png, .tiff])
        // Clipboard managers skip transient content (nspasteboard.org), clipboard history too (it reads types only then).
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount
        await modifiersUp()
        postV(controlV ? .maskControl : .maskCommand)
        for _ in 0..<60 where !provider.read { try? await Task.sleep(nanoseconds: 50_000_000) }
        try? await Task.sleep(nanoseconds: 300_000_000)  // the reader done with it
        if providing === provider { providing = nil }
        guard pasteboard.changeCount == ours else { return }  // something else was copied since
        restore(before, to: pasteboard)
    }
}
