import AllInOneIMEMac
import AppKit
import ApplicationServices

/// Pastes into the frontmost app by posting its paste key (Accessibility), the clipboard put back after: line breaks into
/// a terminal (text an input method inserts reaches a terminal as typed keys, so a line break there is Return: the shell
/// runs the line, Claude Code sends the message; a paste is different: shells and programs like Claude Code turn on
/// bracketed paste and take pasted line breaks as text), and clipboard history's kept images (0.6.8.2), with the app's
/// own paste key (⌘V; ⌃V in a terminal or a code editor). Without Accessibility an answer goes into a terminal on one
/// line as before, and an image is left on the clipboard. Where what is on the clipboard can't be kept without macOS
/// asking or a wait (Paste from Other Apps not Allow, a copy from an iPhone or another Mac, an app's data slow to come:
/// `ClipboardSnapshot`), it couldn't be put back: an answer goes in on one line then too, and an image is pasted and left
/// on the clipboard.
enum TerminalPaste {
    /// Marks the ⌘V posted here, so the input method lets it through (`isOurs`).
    static let marker: Int64 = 0x4149_4F49  // "AIOI"

    /// Whether text can be pasted: the clipboard can be read without macOS asking, to be put back after (Paste from Other
    /// Apps: Allow, told without asking; not a copy from an iPhone or another Mac: `ClipboardSnapshot.canTake`), and
    /// posting ⌘V is allowed. The first time posting isn't, macOS is asked to show its permission prompt.
    @MainActor
    static func isAllowed() -> Bool {
        guard ClipboardSnapshot.canTake(.general, access: SystemClipboard().access) else { return false }
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
    static func postControlV() { postVWhenUp(.maskControl) }

    /// ⌘V to the app, marked as ours, once no modifier is held: an app's own paste (clipboard history's image, ⌃V again
    /// elsewhere). Posted while ⌃ is still held from ⌃V, an app could read ⌃⌘V.
    @MainActor
    static func postCommandV() { postVWhenUp(.maskCommand) }

    /// V with `flags`, posted once no modifier is held (`modifiersUp`).
    @MainActor
    private static func postVWhenUp(_ flags: CGEventFlags) {
        Task { @MainActor in
            await modifiersUp()
            postV(flags)
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

    /// Clipboard history, once it runs (`ClipboardHistoryShared.start`): it looks at the clipboard before each write of
    /// ours (`lookBeforeWrite`), so a copy made just before is recorded or skipped as it is, and is told of each put back
    /// (`didPutBack`: the change count now, and the one of what was put back), never to record it as a new copy.
    @MainActor static var lookBeforeWrite: (@MainActor () -> Void)?
    @MainActor static var didPutBack: (@MainActor (_ count: Int, _ was: Int) -> Void)?

    /// A paste of ours not put back yet: the clipboard's change count after our write, what was there before it and its
    /// change count then. A paste made meanwhile keeps that `before` (the user's, never our own write) and puts it back
    /// itself.
    @MainActor private static var pending: (ours: Int, before: ClipboardSnapshot, was: Int)?

    /// How long a paste waits for what is on the clipboard to be kept (read off the main thread, so typing never waits on
    /// it): an app's data handed over only when read that takes longer (a busy app) isn't waited for.
    static let keepTimeout: TimeInterval = 0.25

    /// What was on the clipboard before our paste, and its change count: the user's, also while a paste of ours is still
    /// to be put back; nil, where it can't be kept without macOS asking or a wait (`ClipboardSnapshot.take`: Paste from
    /// Other Apps not Allow, a copy from an iPhone or another Mac, not all read within `keepTimeout`).
    @MainActor
    private static func userClipboard(_ pasteboard: NSPasteboard) async -> (snapshot: ClipboardSnapshot, was: Int)? {
        if let pending, pending.ours == pasteboard.changeCount { return (pending.before, pending.was) }
        let was = pasteboard.changeCount
        let snapshot = await ClipboardSnapshot.take(pasteboard, access: SystemClipboard().access, within: keepTimeout)
        // A paste of ours written meanwhile keeps the user's.
        if let pending, pending.ours == pasteboard.changeCount { return (pending.before, pending.was) }
        return snapshot.map { ($0, was) }
    }

    /// The clipboard put back after paste `ours`, unless something else was copied since or a later paste of ours took it
    /// over (that one puts it back). Clipboard history is told (`didPutBack`), never to record it as a new copy: what it
    /// puts back was looked at before our write (recorded, or skipped: copied during secure input, before Clear History).
    @MainActor
    private static func putBack(after ours: Int, to pasteboard: NSPasteboard) {
        guard let pending, pending.ours == ours else { return }
        self.pending = nil
        guard pasteboard.changeCount == ours else { return }  // something else was copied since
        pending.before.restore(to: pasteboard)
        didPutBack?(pasteboard.changeCount, pending.was)
    }

    /// Hands the text being pasted to the app when it reads the clipboard (`NSPasteboardItemDataProvider`), so the
    /// clipboard is put back only once it has, as a kept image's is (`ImageProvider`).
    private final class TextProvider: NSObject, NSPasteboardItemDataProvider {
        let text: String
        private(set) var read = false

        init(text: String) { self.text = text }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            if type == .string { item.setString(text, forType: .string) }
            read = true
        }
    }

    /// How long a paste of text waits for the app to read the clipboard (a terminal busy with output takes the ⌘V late)
    /// before it is put back all the same (an app that never reads it), and how long after the app's first read it is.
    static let textReadTimeout: TimeInterval = 5, textPutBackAfterRead: TimeInterval = 0.5

    /// Pastes `text` into the frontmost app, then puts the clipboard back once the app has read it: shortly after its first
    /// read (`textPutBackAfterRead`), or after `textReadTimeout` if it never does; typing goes on once it has. Put back on
    /// a timer from the ⌘V instead (half a second), a busy terminal that took the ⌘V later pasted what was copied before
    /// (a password, a token). Where what is on the clipboard can't be kept (`userClipboard`: Paste from Other Apps set to
    /// Ask or Deny since `isAllowed`, a copy from an iPhone, an app's data slow to come), nothing, at once: the clipboard
    /// is left as it is, and false, for the caller to put the text in on one line. Typing stopped before the ⌘V (its
    /// task cancelled: `write`): no ⌘V, the clipboard put back, and false.
    @MainActor @discardableResult
    static func paste(_ text: String) async -> Bool {
        let provider = TextProvider(text: text)
        guard let ours = await write(provider, for: [.string], thenPost: .maskCommand) else { return false }
        // The app reads the clipboard when the ⌘V reaches it: wait for that before typing on or putting it back (not once
        // a later paste of ours took it over: that one puts it back). The provider stays until then. Waited for in a task
        // of its own, which typing stopped meanwhile doesn't cancel: cut short, the clipboard was put back before the app
        // read it, and it pasted what was copied before.
        let steps = Int(textReadTimeout / 0.02)
        await Task { @MainActor in
            for _ in 0..<steps where !provider.read && pending?.ours == ours { try? await Task.sleep(nanoseconds: 20_000_000) }
        }.value
        Task { @MainActor in
            if provider.read { try? await Task.sleep(nanoseconds: UInt64(textPutBackAfterRead * 1_000_000_000)) }
            putBack(after: ours, to: NSPasteboard.general)
        }
        return true
    }

    /// `provider`'s item on the clipboard for `types`, what was there kept to be put back (`pending`), then V with `flags`
    /// posted once no modifier is held: the change count of our write. Nil, the clipboard untouched, where what is on it
    /// can't be kept (`userClipboard`); nil, no V posted and the clipboard untouched or put back, where the task was
    /// cancelled first.
    @MainActor
    private static func write(_ provider: any NSPasteboardItemDataProvider, for types: [NSPasteboard.PasteboardType],
                              thenPost flags: CGEventFlags) async -> Int? {
        let pasteboard = NSPasteboard.general
        lookBeforeWrite?()
        guard let before = await userClipboard(pasteboard) else { return nil }
        // Typing stopped while it was being kept: the clipboard isn't touched. Written, it could take over a paste made
        // meanwhile (the rest of the answer, put in at once) and be put back before that one's ⌘V was read.
        guard !Task.isCancelled else { return nil }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: types)
        // Clipboard managers skip transient content (nspasteboard.org), clipboard history too (it reads types only then).
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount
        pending = (ours, before.snapshot, before.was)
        await modifiersUp()
        // Typing stopped meanwhile (Esc, the field left, another result: its task cancelled, which cuts every wait here
        // short): no V, into this app or the one that has the focus now. Posted, the app read the clipboard once it was
        // put back, and pasted what was copied before.
        guard !Task.isCancelled else {
            putBack(after: ours, to: pasteboard)
            return nil
        }
        postV(flags)
        return ours
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
    /// was on the clipboard before. Where what is on the clipboard can't be kept (`userClipboard`), it couldn't be put
    /// back: the image is put on it, as without Accessibility, and pasted.
    @MainActor
    static func pasteImage(_ png: Data, controlV: Bool) async {
        let flags: CGEventFlags = controlV ? .maskControl : .maskCommand
        let provider = ImageProvider(png: png)
        providing = provider
        guard let ours = await write(provider, for: [.png, .tiff], thenPost: flags) else {
            providing = nil
            guard !Task.isCancelled else { return }  // nothing pasted (`write`)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            await modifiersUp()
            postV(flags)
            return
        }
        for _ in 0..<60 where !provider.read { try? await Task.sleep(nanoseconds: 50_000_000) }
        if provider.read { try? await Task.sleep(nanoseconds: 1_500_000_000) }  // its reads after the first
        if providing === provider { providing = nil }
        putBack(after: ours, to: NSPasteboard.general)
    }
}
