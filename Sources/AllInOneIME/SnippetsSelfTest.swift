import AllInOneIMECore
import AppKit
import InputMethodKit
import SwiftUI

/// A text field that is a real NSTextView: what the input method does goes to the text view's own text input methods,
/// so its caret moves as an NSTextView moves it. Empty text with a replacement range never arrives, as through the
/// input method connection (`FakeTextClient.dropsEmptyReplacements`); with `dropsEmptyMarkedText`, empty marked text with
/// one doesn't either. Main thread only.
final class TextViewClient: NSObject, IMKTextInput {
    let textView: NSTextView
    private let window: NSWindow
    var dropsEmptyMarkedText = false

    @MainActor
    override init() {
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 200), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        window.contentView = textView
        window.makeFirstResponder(textView)
        super.init()
    }

    @MainActor func close() { window.close() }
    @MainActor var text: String { textView.string }
    @MainActor var caret: NSRange { textView.selectedRange() }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        if text.isEmpty, replacementRange.location != NSNotFound { return }
        MainActor.assumeIsolated { textView.insertText(text, replacementRange: replacementRange) }
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        let marked: Any = string ?? ""
        if dropsEmptyMarkedText, replacementRange.location != NSNotFound,
           ((marked as? NSAttributedString)?.string ?? marked as? String ?? "").isEmpty { return }
        MainActor.assumeIsolated { textView.setMarkedText(marked, selectedRange: selectionRange, replacementRange: replacementRange) }
    }

    func selectedRange() -> NSRange { MainActor.assumeIsolated { textView.selectedRange() } }
    func markedRange() -> NSRange { MainActor.assumeIsolated { textView.markedRange() } }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        let text: String? = MainActor.assumeIsolated {
            guard range.location != NSNotFound, NSMaxRange(range) <= (textView.string as NSString).length else { return nil }
            return (textView.string as NSString).substring(with: range)
        }
        return text.map { NSAttributedString(string: $0) }
    }
    func length() -> Int { MainActor.assumeIsolated { (textView.string as NSString).length } }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect?.pointee = NSRect(x: 420, y: 560, width: 1, height: 18)
        return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "com.apple.TextEdit" }
    func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "allinoneime-selftest-textview" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { NSRect(x: 420, y: 560, width: 1, height: 18) }
}

extension SelfTest {
    /// Snippets (`@name` inserts a saved text): in an NSTextView the caret goes to `{cursor}`; in a field that tells no
    /// caret it stays at the end; into a terminal a text of several lines goes in as a paste, the caret left alone.
    static func testSnippets(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("snippets (an NSTextView, a field without a caret, a terminal)", needs: .composing)
        let before = settings.customCommands
        let pasteAllowed = controller.canPasteInTerminal, paste = controller.pasteInTerminal
        defer {
            settings.customCommands = before
            controller.applySettings()
            controller.canPasteInTerminal = pasteAllowed
            controller.pasteInTerminal = paste
            controller.composer.setInputMode(settings.defaultInput)
            controller.activateServer(client)
        }
        func snippet(_ name: String, _ text: String) -> CustomCommand {
            CustomCommand(name: name, type: .snippet, text: text)
        }
        // In the settings: a field's activation builds the command list from them.
        settings.customCommands = before + [snippet("selftestthx", "Hi {cursor}, thanks 😀"),
                                            snippet("selftestaddr", "1 Main Street\nSpringfield{cursor}\nUSA")]
        controller.applySettings()
        controller.activateServer(client)
        check(pump(timeout: 10) { controller.composer.commands.contains { $0.name == "selftestaddr" } }, "the snippets are offered")
        func insert(_ name: String, into field: IMKTextInput) {
            controller.activateServer(field)
            controller.composer.setInputMode(.english)
            _ = controller.handle(event("@", code: 0x13, flags: .shift), client: field)
            for ch in name { _ = controller.handle(event(String(ch), code: keyCodes[ch] ?? 0), client: field) }
            _ = controller.handle(event("\r", code: VirtualKey.returnKey), client: field)
            _ = pump(timeout: 0.3) { false }
        }

        // An NSTextView: the text goes in, the caret back to {cursor} (before ", thanks 😀": 11 UTF-16 units), by empty
        // marked text there; where that doesn't arrive, the caret stays at the end (18) and the text is as inserted.
        for drops in [false, true] {
            let view = TextViewClient()
            view.dropsEmptyMarkedText = drops
            view.textView.string = "Re: "
            view.textView.setSelectedRange(NSRange(location: 4, length: 0))
            insert("selftestthx", into: view)
            check(view.text == "Re: Hi , thanks 😀" && view.caret == NSRange(location: drops ? 18 : 7, length: 0)
                  && !view.textView.hasMarkedText() && !controller.composer.isComposing,
                  "@selftestthx ⏎ in an NSTextView\(drops ? " that gets no empty marked text" : "") inserts the text, the caret "
                  + (drops ? "left at the end" : "at {cursor}") + " (\(view.text.debugDescription), caret \(view.caret.location))")
            view.close()
        }

        // A field that tells no caret: inserted, the caret left at the end (nothing replaced).
        let blind = FakeTextClient()
        blind.knowsRanges = false
        insert("selftestthx", into: blind)
        check(blind.inserted == ["Hi , thanks 😀"] && blind.replacements == 0,
              "in a field without a caret it goes in and the caret isn't moved (\(blind.inserted))")

        // A field that has other text before its caret than what went in (the app changed it): not moved.
        let other = FakeTextClient()
        other.ignoresRanges = true
        insert("selftestthx", into: other)
        check(other.document == "Hi , thanks 😀" && other.marked.isEmpty && other.replacements == 0,
              "…nor in one that ignores ranges, and its text stays as it is (\(other.document.debugDescription))")

        // A terminal: the lines go in as a paste, and the caret isn't moved there (keys go to the shell).
        var pasted: [String] = []
        controller.canPasteInTerminal = { true }
        controller.pasteInTerminal = { pasted.append($0) }
        let terminal = FakeTextClient()
        terminal.bundleIDOverride = "com.apple.Terminal"
        insert("selftestaddr", into: terminal)
        _ = pump(timeout: 1) { !pasted.isEmpty }
        check(pasted == ["1 Main Street\nSpringfield\nUSA"] && terminal.inserted.isEmpty && terminal.replacements == 0,
              "a snippet of several lines goes into a terminal as a paste, the caret left alone (\(pasted.map(\.debugDescription)))")
    }

    /// The editor's "Insert text": its preview (the core's renderer: the date of now, ▏ at `{cursor}`) and Save, which
    /// hands back the snippet; and an extension source's review lists the snippets its bundle ships.
    static func testSnippetEditorAndReview(snapshotDirectory: URL) {
        section("snippets in the editor and in an extension source's review")
        let now = Date()
        let today = { () -> String in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: now)
        }()
        let preview = CommandEditor.preview("Dear {name?},\n{cursor}\n{date} {{x}}", now: now)
        check(preview == "Dear ‹name›,\n▏\n\(today) {x}", "the editor's preview fills the blanks with samples, ▏ at {cursor} (\(preview.debugDescription))")

        // The editor in a window: Save (⏎) hands the snippet back as typed.
        var saved: CustomCommand?
        let start = CustomCommand(name: "selftestsig", type: .snippet, summary: "Signature", text: "Best,\n{cursor}")
        let editor = CommandEditor(edit: CommandEdit(index: nil, command: start), others: []) { saved = $0; return true }
        let window = NSWindow(contentViewController: NSHostingController(rootView: editor))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        _ = pump(timeout: 0.6) { false }
        /// ⏎ with nothing focused: Save, the default button.
        func pressReturn() {
            window.makeFirstResponder(nil)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let key = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                              isARepeat: false, keyCode: VirtualKey.returnKey) { window.sendEvent(key) }
            }
            if saved == nil, let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: VirtualKey.returnKey) {
                _ = window.performKeyEquivalent(with: key)  // the default button's key, where the window didn't take it as a key
            }
            _ = pump(timeout: 0.5) { saved != nil }
        }
        pressReturn()
        check(saved == start, "Save hands back the snippet (\(String(describing: saved)))")

        // Its text is an NSTextView that replaces nothing while typing (no smart quotes or dashes: JSON and code stay as
        // typed), and a placeholder goes in at its caret, into what is saved.
        func textViews(in view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        let textView = window.contentView.flatMap { textViews(in: $0).first { $0.string == "Best,\n{cursor}" } }
        check(textView.map { !$0.isAutomaticQuoteSubstitutionEnabled && !$0.isAutomaticDashSubstitutionEnabled
                             && !$0.isAutomaticTextReplacementEnabled && !$0.isRichText } == true,
              "the snippet's text is typed as it is: no smart quotes, dashes or replacements (\(textView == nil ? "no text view" : "set"))")
        if let textView {
            let target = PlainTextEditor.Inserter()
            target.textView = textView
            textView.setSelectedRange(NSRange(location: 6, length: 0))
            target.insert("{date} ", into: .constant(""))
            textView.insertText("\"a\" -- b", replacementRange: textView.selectedRange())
            _ = pump(timeout: 0.2) { false }
            saved = nil
            pressReturn()
            check(textView.string == "Best,\n{date} \"a\" -- b{cursor}" && saved?.text == textView.string,
                  "a placeholder goes in at the caret, and the text is saved as typed (\(textView.string.debugDescription), "
                  + "saved \(saved?.text.debugDescription ?? "nothing"))")
        }
        window.close()
        let image = snapshotDirectory.appendingPathComponent("command-editor-snippet.png")
        renderOffscreen(CommandEditor(edit: CommandEdit(index: nil, command: start), others: []) { _ in true }, size: NSSize(width: 520, height: 520),
                        to: image)
        check(FileManager.default.fileExists(atPath: image.path), "the editor with a snippet renders (\(image.lastPathComponent))")

        // A bundle with only snippets: the review lists them, and they run nothing.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-snippets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(#"""
            {"schemaVersion": 1, "name": "selftestteam", "title": "Team texts",
             "snippets": [{"name": "selftestoffice", "text": "1 Main Street\nSpringfield", "summary": "Office address"},
                          {"name": "selftestwifi", "text": "guest / hunter2"}]}
            """#.utf8).write(to: folder.appendingPathComponent(ExtensionBundle.manifestName))
        var config = Config.default
        config.extensionFolders = []
        config.findRaycastScripts = false
        let review = ExtensionSourceReview.make(bundleFolder: folder, path: "", url: "file:///selftest", commit: nil, commitDate: nil, config: config)
        check(review.bundle?.name == "selftestteam" && review.problem == nil && review.commands.isEmpty
              && review.snippets.map(\.name) == ["selftestoffice", "selftestwifi"] && review.snippets.first?.text == "Office address"
              && review.programs.isEmpty, "the review of a bundle with only snippets lists them (\(review.snippets.map(\.name)))")
        check(review.summary.contains { $0.hasPrefix("snippet:     @selftestwifi — guest / hunter2") },
              "…and so does the command line's (\(review.summary.filter { $0.hasPrefix("snippet") }))")
        let reviewImage = snapshotDirectory.appendingPathComponent("extension-source-review-snippets.png")
        renderOffscreen(ExtensionSourceReviewView(review: review).frame(width: 600, height: 500), size: NSSize(width: 600, height: 500), to: reviewImage)
        check(FileManager.default.fileExists(atPath: reviewImage.path), "the review with snippets renders (\(reviewImage.lastPathComponent))")
    }
}
