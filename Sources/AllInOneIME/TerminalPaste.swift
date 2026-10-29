import AppKit
import ApplicationServices

/// Pastes into the frontmost app by posting its paste key (Accessibility), the clipboard put back after: line breaks into
/// a terminal (text an input method inserts reaches a terminal as typed keys, so a line break there is Return: the shell
/// runs the line, Claude Code sends the message; a paste is different: shells and programs like Claude Code turn on
/// bracketed paste and take pasted line breaks as text), and clipboard history's kept images (0.6.8.2), with the app's
/// own paste key (⌘V; ⌃V in a terminal or a code editor). Without Accessibility an answer goes into a terminal on one
/// line as before, and an image is left on the clipboard.
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

    /// A paste of ours not put back yet: the clipboard's change count after our write, and what was there before it. A
    /// paste made meanwhile keeps that `before` (the user's, never our own write) and puts it back itself.
    @MainActor private static var pending: (ours: Int, before: [[(NSPasteboard.PasteboardType, Data)]])?

    /// What was on the clipboard before our paste: the user's, also while a paste of ours is still to be put back.
    @MainActor
    private static func userClipboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        if let pending, pending.ours == pasteboard.changeCount { return pending.before }
        return saved(pasteboard)
    }

    /// The clipboard put back after paste `ours`, unless something else was copied since or a later paste of ours took it
    /// over (that one puts it back).
    @MainActor
    private static func putBack(after ours: Int, to pasteboard: NSPasteboard) {
        guard let pending, pending.ours == ours else { return }
        self.pending = nil
        guard pasteboard.changeCount == ours else { return }  // something else was copied since
        restore(pending.before, to: pasteboard)
    }

    /// Pastes `text` into the frontmost app, then puts the clipboard back once the app has read it.
    @MainActor
    static func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let before = userClipboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Clipboard managers skip transient content (nspasteboard.org), clipboard history too.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ours = pasteboard.changeCount
        pending = (ours, before)
        await modifiersUp()
        postV(.maskCommand)
        // The app reads the clipboard when the ⌘V reaches it: wait for that before typing on or putting it back.
        try? await Task.sleep(nanoseconds: 150_000_000)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            putBack(after: ours, to: pasteboard)
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
    /// code editor, where Claude Code takes an image on it; else ⌘V), then puts the clipboard back 1.5 seconds after the
    /// app first read it (Claude Code reads it twice, with other programs: macOS asks the provider only the first time),
    /// or after 3 seconds if it never does (0.6.8.2, clipboard history): a slow reader still gets the image, never what
    /// was on the clipboard before.
    @MainActor
    static func pasteImage(_ png: Data, controlV: Bool) async {
        let pasteboard = NSPasteboard.general
        let before = userClipboard(pasteboard)
        pasteboard.clearContents()
        let provider = ImageProvider(png: png)
        providing = provider
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png, .tiff])
        // Clipboard managers skip transient content (nspasteboard.org), clipboard history too (it reads types only then).
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount
        pending = (ours, before)
        await modifiersUp()
        postV(controlV ? .maskControl : .maskCommand)
        for _ in 0..<60 where !provider.read { try? await Task.sleep(nanoseconds: 50_000_000) }
        if provider.read { try? await Task.sleep(nanoseconds: 1_500_000_000) }  // its reads after the first
        if providing === provider { providing = nil }
        putBack(after: ours, to: pasteboard)
    }
}
