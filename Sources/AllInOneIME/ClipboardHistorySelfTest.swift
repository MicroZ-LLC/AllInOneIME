import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import InputMethodKit

/// Clipboard history in the self-test (`--selftest DIR --clipboard-only`): its logic is the core's unit tests'
/// (ClipboardHistorySessionTests) and the recording's the Mac's (ClipboardHistoryRecordingTests); here the real panel
/// shows on ⌃V, and ⏎ puts a two-line row in through IMK, into an NSTextView and into Slack's composer in the Electron
/// harness (where `ALLINONEIME_ELECTRON_HARNESS` names it), nothing sent; over a selection there it takes the selection's
/// place, and with an emoji before the caret the keys the panel takes leave the text as it was; where the page tells no
/// caret, ⌃V is the app's. The history is the self-test's own, and so is what ⌃V reads of the clipboard: the user's
/// clipboard and history file are never read or written.
extension SelfTest {
    /// The run of `--clipboard-only`, from `run` once the controller is made: this step only, the user's config checked
    /// as it was (`userConfig`).
    static func clipboardOnly(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL,
                              userConfig: Data?) -> Int32 {
        (settings.typeOut, settings.typeOutMistakes) = (false, false)
        controller.services.loadSettings = { SelfTest.settings }
        CandidatePanel.shared.alphaValue = 0
        CandidatePanel.shared.ignoresMouseEvents = true
        controller.ensureEngine()
        controller.applySettings()
        testClipboardHistory(controller, client, snapshotDirectory: snapshotDirectory)
        controller.deactivateServer(client)
        check((try? Data(contentsOf: Config.userURL)) == userConfig, "the user's config was left unchanged")
        return summary()
    }

    /// ⌃V as macOS hands it over.
    static var controlV: NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: 0, context: nil, characters: "\u{16}", charactersIgnoringModifiers: "v", isARepeat: false,
                         keyCode: 0x09)!
    }

    static func testClipboardHistory(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("Clipboard history: ⌃V shows the panel, ⏎ puts a two-line row in (an NSTextView, Slack's composer: nothing sent)",
                needs: .composing)
        typealias Call = PageFieldClient.Call
        let saved = (history: controller.services.clipboardHistory, read: controller.readClipboard, chromium: controller.chromiumApp,
                     pass: controller.passPasteKey, override: controller.clientOverride, peek: controller.peekClipboard)
        defer {
            controller.services.clipboardHistory = saved.history
            (controller.readClipboard, controller.chromiumApp, controller.passPasteKey) = (saved.read, saved.chromium, saved.pass)
            controller.peekClipboard = saved.peek
            controller.clientOverride = saved.override
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
            if let notice = controller.notice { controller.endNotice(notice) }
        }
        let item = "First line of the copy\nand its second line"
        let now = Date()
        let history = [ClipboardHistoryItem(text: item, copiedAt: now - 120), ClipboardHistoryItem(text: "an older copy", copiedAt: now - 3600)]
        controller.services.clipboardHistory = ClipboardHistoryServices(state: { .recording }, items: { history }, canPassPasteKey: { false },
                                                                       firstShowing: { false }, now: { now })
        // What ⌃V reads: the self-test's, never the clipboard; for the panel, only what it has (`peekClipboard`).
        var (peeks, reads) = (0, 0)
        controller.peekClipboard = { peeks += 1; return .text(item) }
        controller.readClipboard = { reads += 1; return .text(item) }
        var pasteKeys = 0
        controller.passPasteKey = { pasteKeys += 1 }
        controller.passCommandV = { pasteKeys += 1 }
        let slack = "com.tinyspeck.slackmacgap"
        controller.chromiumApp = { $0 == slack }
        let panel = CandidatePanel.shared

        /// `field` focused in English, ⌃V, the panel waited for; then ⏎ during its key (`during`, before the run loop
        /// turns), and what came after: whether the panel showed the history, and whether ⏎ was taken.
        func controlVThenReturn(_ field: IMKTextInput, during: (Bool) -> Void = { _ in }) -> (shown: Bool, rows: [String], comment: String,
                                                                                                 detail: String, taken: Bool) {
            controller.activateServer(field)
            controller.composer.setInputMode(.english)
            controller.clientOverride = field  // the read of the clipboard answers after the key, into the field being typed in
            let took = controller.handle(controlV, client: field)
            let shown = pump(timeout: 3) { panel.isShowing && panel.view.model.rows.first?.text == "First line of the copy" }
            let model = panel.view.model
            during(true)
            let taken = controller.handle(event("\r", code: VirtualKey.returnKey), client: field)
            during(false)
            _ = pump(timeout: 0.3) { false }  // what goes in once the key is done
            controller.deactivateServer(field)
            return (took && shown, model.rows.map(\.text), model.rows.first?.comment ?? "", model.detail ?? "", taken)
        }

        // An NSTextView (Messages' and Notes' kind): the panel, then the row in as typed, its line break too, nothing marked.
        let view = TextViewClient()
        let inView = controlVThenReturn(view)
        snapshot("clipboard-history", in: snapshotDirectory)
        check(inView.shown && inView.rows == ["First line of the copy", "an older copy"] && inView.comment.hasPrefix("+1 ")
              && inView.detail.contains(tr("剪贴板", "Clipboard")),
              "⌃V: the real panel shows the history, newest first (\(inView.rows)), \"\(inView.comment)\", \"\(inView.detail)\"")
        check(inView.taken && view.text == item && !view.textView.hasMarkedText() && !panel.isShowing,
              "an NSTextView: ⏎ puts the two lines in (\(view.text.debugDescription)), nothing marked, the panel gone")
        view.close()
        check(peeks == 1 && reads == 0, "⌃V opening the panel: the clipboard looked at for it (\(peeks)), not read as a command reads it (\(reads))")

        // An image on the clipboard: the panel only looks at its types; its data is read for a command (a private
        // pasteboard, its PNG given only when asked).
        let board = NSPasteboard.withUniqueName()
        let image = PromisedImage(), boardItem = NSPasteboardItem()
        boardItem.setDataProvider(image, forTypes: [.png])
        board.clearContents()
        board.writeObjects([boardItem])
        let peeked = AllInOneIMEInputController.clipboardContent(board, imageData: false)
        let askedPeeking = image.asked
        let read = AllInOneIMEInputController.clipboardContent(board)
        board.releaseGlobally()
        check(peeked == .image(Data()) && askedPeeking == 0 && read == .image(Data([0x89, 0x50, 0x4E, 0x47])) && image.asked == 1,
              "an image on the clipboard: its data not read for the panel (asked \(askedPeeking) times), read for a command")

        // An NSTextView with a selection: ⌃V ↓ ⏎ puts the row chosen in its place, as a paste over a selection does.
        let selectedView = TextViewClient()
        selectedView.textView.string = "Hello world"
        selectedView.textView.setSelectedRange(NSRange(location: 6, length: 5))
        controller.activateServer(selectedView)
        controller.composer.setInputMode(.english)
        controller.clientOverride = selectedView
        _ = controller.handle(controlV, client: selectedView)
        let viewShown = pump(timeout: 3) { panel.isShowing && panel.view.model.rows.first?.text == "First line of the copy" }
        let viewTaken = controller.handle(event("", code: VirtualKey.down), client: selectedView)
            && controller.handle(event("\r", code: VirtualKey.returnKey), client: selectedView)
        _ = pump(timeout: 0.3) { false }
        controller.deactivateServer(selectedView)
        check(viewShown && viewTaken && selectedView.text == "Hello an older copy" && !selectedView.textView.hasMarkedText(),
              "an NSTextView with \"world\" selected: ⌃V ↓ ⏎ puts the row in its place (\(selectedView.text.debugDescription))")
        selectedView.close()

        // Slack's composer (a Chromium page): ⏎ puts the two lines in during the key, more than one character with no
        // range, so the page has the key as the input method's (229) and sends nothing.
        let page = PageFieldClient()
        page.bundleIDOverride = slack
        page.start("", caret: 0)
        page.typed("#1")
        var before = 0
        let inPage = controlVThenReturn(page) { during in
            page.duringKey = during
            if during { before = page.calls.count }
        }
        let calls = Array(page.calls.dropFirst(before))
        let expected = [Call(duringKey: true, marks: false, range: nil, text: item)]
        check(inPage.shown && inPage.taken && calls == expected && page.text == "#1" + item && !page.hasMarked && pasteKeys == 0,
              "Slack's composer: ⏎ inserts the two lines during the key (\(calls.map(PageFieldClient.recorded))): \(page.text.debugDescription)")

        // An empty composer: ↑ on the panel (Slack edits the last message on it) marks a space at the caret during the key
        // and takes it out after, so the page has the key as the input method's; the field as it was.
        let empty = PageFieldClient()
        empty.bundleIDOverride = slack
        empty.start("", caret: 0)
        controller.activateServer(empty)
        controller.composer.setInputMode(.english)
        controller.clientOverride = empty
        _ = controller.handle(controlV, client: empty)
        let emptyShown = pump(timeout: 3) { panel.isShowing && panel.view.model.rows.first?.text == "First line of the copy" }
        let start = empty.calls.count
        empty.duringKey = true
        let upTaken = controller.handle(event("", code: VirtualKey.up), client: empty)
        empty.duringKey = false
        _ = pump(timeout: 0.3) { false }
        let upCalls = Array(empty.calls.dropFirst(start))
        _ = escape(controller, empty)
        controller.deactivateServer(empty)
        let upExpected = [Call(duringKey: true, marks: true, range: nil, selection: 1, text: " "),
                          Call(duringKey: false, marks: true, range: nil, selection: 0, text: "")]
        check(emptyShown && upTaken && upCalls == upExpected && empty.text.isEmpty && !empty.hasMarked,
              "an empty Slack composer: ↑ on the panel marks a space during the key and takes it out after "
              + "(\(upCalls.map(PageFieldClient.recorded))): \(empty.text.debugDescription)")

        /// ⌃V in `field` (a page's, focused in English), the panel waited for, then `keys`: whether the panel showed, what
        /// went in during and after each key, ⌃V's first, and whether each was taken.
        func keysInPage(_ field: PageFieldClient, _ keys: [NSEvent]) -> (shown: Bool, calls: [[Call]], taken: [Bool]) {
            controller.activateServer(field)
            controller.composer.setInputMode(.english)
            controller.clientOverride = field
            var (calls, taken) = ([[Call]](), [Bool]())
            func press(_ key: NSEvent) {
                let start = field.calls.count
                field.duringKey = true
                taken.append(controller.handle(key, client: field))
                field.duringKey = false
                _ = pump(timeout: 0.3) { false }  // what goes in once the key is done; ⌃V's read of the clipboard
                calls.append(Array(field.calls.dropFirst(start)))
            }
            press(controlV)
            let shown = pump(timeout: 3) { panel.isShowing && panel.view.model.rows.first?.text == "First line of the copy" }
            keys.forEach(press)
            if panel.isShowing { _ = escape(controller, field) }
            controller.deactivateServer(field)
            return (shown, calls, taken)
        }
        func marked(_ range: Range<Int>, _ text: String) -> [Call] {
            [Call(duringKey: true, marks: true, range: range, selection: (text as NSString).length, text: text),
             Call(duringKey: false, marks: false, range: nil, text: text)]
        }

        // A selection in Slack's composer (a word selected, ⌃V to put an older copy in its place): ⌃V marks the selected
        // text itself in its place during the key and commits it back (the page has the key as the input method's, its
        // text as it was, the caret after it); ↓ marks the character before the caret; ⏎ marks the row chosen in the
        // selection's place, committed after: the selection replaced, nothing sent.
        let selected = PageFieldClient()
        selected.bundleIDOverride = slack
        selected.start("Hello world", caret: 6, selected: 5)
        let over = keysInPage(selected, [event("", code: VirtualKey.down), event("\r", code: VirtualKey.returnKey)])
        let overExpected = [marked(6..<11, "world"), marked(10..<11, "d"), marked(6..<11, "an older copy")]
        check(over.shown && over.taken == [true, true, true] && over.calls == overExpected && selected.text == "Hello an older copy"
              && !selected.hasMarked,
              "Slack's composer with \"world\" selected: ⌃V ↓ ⏎ (\(over.calls.map { $0.map(PageFieldClient.recorded) })): "
              + selected.text.debugDescription)

        // An emoji before the caret (a surrogate pair): ⌃V, ↑ and Esc each mark the whole emoji in its place during the key
        // and commit it back: the text as it was.
        let emoji = PageFieldClient()
        emoji.bundleIDOverride = slack
        emoji.start("ok 👍", caret: 5)
        let around = keysInPage(emoji, [event("", code: VirtualKey.up), event("\u{1B}", code: VirtualKey.escape)])
        let aroundExpected = Array(repeating: marked(3..<5, "👍"), count: 3)
        check(around.shown && around.taken == [true, true, true] && around.calls == aroundExpected && emoji.text == "ok 👍"
              && !emoji.hasMarked && !panel.isShowing,
              "Slack's composer with an emoji before the caret: ⌃V ↑ Esc mark it whole (\(around.calls.map { $0.map(PageFieldClient.recorded) })): "
              + emoji.text.debugDescription)

        // A page that tells no caret: nothing could keep the panel's keys from it, so ⌃V is the app's there, no panel.
        let noCaret = PageFieldClient()
        noCaret.bundleIDOverride = slack
        noCaret.start("text", caret: 4)
        noCaret.tellsNoCaret = true
        controller.activateServer(noCaret)
        controller.composer.setInputMode(.english)
        controller.clientOverride = noCaret
        let noCaretTook = controller.handle(controlV, client: noCaret)
        let noCaretShown = pump(timeout: 1) { panel.isShowing }
        controller.deactivateServer(noCaret)
        check(!noCaretTook && !noCaretShown && noCaret.calls.isEmpty,
              "Slack's composer telling no caret: ⌃V is the app's (\(noCaretTook ? "taken" : "not taken")), \(noCaretShown ? "a panel" : "no panel")")

        // A terminal (Ghostty here) sends a key the input method took to the shell itself unless text went in during it or
        // marked text is there after it (0.6.8: ↓ ↑ after ⌃V went to the shell's history). Every key the panel takes is
        // kept from it: ⌃V, ↓, Esc each mark a space during the key and take it out after; ⏎ on the two-line row goes in
        // as a paste after the key, with the space marked during it, so the shell never gets the Return.
        let terminal = FakeTextClient()
        terminal.bundleIDOverride = "com.mitchellh.ghostty"
        let savedPaste = (can: controller.canPasteInTerminal, paste: controller.pasteInTerminal)
        var pasted: [String] = []
        controller.canPasteInTerminal = { true }
        controller.pasteInTerminal = { pasted.append($0) }
        controller.activateServer(terminal)
        controller.composer.setInputMode(.english)
        controller.clientOverride = terminal
        /// `key` handled, then what is marked during it (before the run loop turns) and after it.
        func inTerminal(_ key: NSEvent) -> (taken: Bool, during: String, after: String) {
            let taken = controller.handle(key, client: terminal)
            let during = terminal.marked
            _ = pump(timeout: 0.3) { false }
            return (taken, during, terminal.marked)
        }
        let vKey = inTerminal(controlV)
        let terminalShown = pump(timeout: 3) { panel.isShowing && panel.view.model.rows.first?.text == "First line of the copy" }
        let down = inTerminal(event("", code: VirtualKey.down))
        let esc = inTerminal(event("\u{1b}", code: VirtualKey.escape))
        let hidden = !panel.isShowing
        _ = inTerminal(controlV)
        _ = pump(timeout: 3) { panel.isShowing }
        let enter = inTerminal(event("\r", code: VirtualKey.returnKey))
        _ = pump(timeout: 1) { !pasted.isEmpty }
        controller.deactivateServer(terminal)
        (controller.canPasteInTerminal, controller.pasteInTerminal) = (savedPaste.can, savedPaste.paste)
        let kept = [vKey, down, esc, enter].allSatisfy { $0.taken && $0.during == " " && $0.after.isEmpty }
        check(terminalShown && hidden && kept && pasted == [item] && terminal.inserted.isEmpty,
              "a terminal: ⌃V ↓ Esc and ⏎ each kept from the shell (a space marked during the key, gone after: "
              + "\([vKey, down, esc, enter].map { "\($0.taken) \($0.during.debugDescription)→\($0.after.debugDescription)" })), "
              + "the two lines pasted after ⏎ (\(pasted.count)), nothing typed")

        // A kept image (0.6.8.2): its row in the real panel with its thumbnail, ⏎ pasting it with the app's own paste key
        // (an NSTextView: ⌘V; a terminal: ⌃V), from a history of the self-test's own (never the user's files or clipboard).
        let keptImages = ClipboardHistoryStore(url: snapshotDirectory.appendingPathComponent("clipboard-history-selftest.json"))
        keptImages.clear()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<400 { for y in 0..<200 { bitmap.setColor(NSColor(deviceRed: Double(x) / 400, green: 0.5, blue: Double(y) / 200, alpha: 1), atX: x, y: y) } }
        let shot = ClipboardImage(png: bitmap.representation(using: .png, properties: [:])!, width: 400, height: 200)
        keptImages.record("a text copied before", at: now - 600, limit: 20)
        keptImages.recordImage(shot, at: now - 120, limit: 20)
        controller.services.clipboardHistory = ClipboardHistoryServices(
            state: { .recording }, items: { keptImages.items }, canPassPasteKey: { true }, firstShowing: { false }, now: { now },
            imageData: { keptImages.imageData($0) }, clipboardIsNewest: { true })
        // The image just copied is on the clipboard still: its kept row stands for it, first.
        controller.peekClipboard = { .image(Data([0x89, 0x50, 0x4E, 0x47])) }
        var imagesPasted: [(Data, Bool)] = []
        let savedImagePaste = controller.pasteImage
        controller.pasteImage = { imagesPasted.append(($0, $1)) }
        /// ⌃V, the image's row (the first), ⏎ in `field`: the row as shown.
        func pasteKeptImage(into field: IMKTextInput, snapshotting: Bool = false) -> PanelModel.Row? {
            controller.activateServer(field)
            controller.composer.setInputMode(.english)
            controller.clientOverride = field
            _ = controller.handle(controlV, client: field)
            _ = pump(timeout: 3) { panel.isShowing && panel.view.model.rows.first?.text.hasPrefix(tr("图片", "Image")) == true }
            let row = panel.view.model.rows.first
            if snapshotting { snapshot("clipboard-history-image", in: snapshotDirectory) }
            _ = controller.handle(event("\r", code: VirtualKey.returnKey), client: field)
            _ = pump(timeout: 1) { false }
            controller.deactivateServer(field)
            return row
        }
        let imageView = TextViewClient()
        let imageRow = pasteKeptImage(into: imageView, snapshotting: true)
        imageView.close()
        let imageTerminal = FakeTextClient()
        imageTerminal.bundleIDOverride = "com.mitchellh.ghostty"
        _ = pasteKeptImage(into: imageTerminal)
        controller.pasteImage = savedImagePaste
        keptImages.clear()
        let thumbnailShown = imageRow?.icon.flatMap { icon -> String? in if case let .image(path, _) = icon.glyph { path } else { nil } } != nil
        check(imageRow?.text == tr("图片 400 × 200", "Image 400 × 200") && thumbnailShown
              && imagesPasted.map(\.0) == [shot.png, shot.png] && imagesPasted.map(\.1) == [false, true],
              "a kept image: its row (\(imageRow?.text ?? "none"), thumbnail \(thumbnailShown)), ⏎ pastes it "
              + "(\(imagesPasted.map { $0.1 ? "terminal ⌃V" : "⌘V" }))")

        // In the Electron harness's composer, that answer to ⏎ (the input method's as above; as it answers where the keys
        // couldn't be composed here, a locked screen): the text in, the key the input method's, nothing sent. The harness
        // runs on a locked screen too: it needs nothing composed here.
        section("Clipboard history: the two lines into Slack's composer in the Electron harness, ⏎ not sent")
        guard let path = ProcessInfo.processInfo.environment["ALLINONEIME_ELECTRON_HARNESS"], !path.isEmpty else {
            return skip("clipboard history's keys in the Electron harness's composer (make electron-harness, then "
                        + "ELECTRON_HARNESS=build/electron-harness)", noElectronHarness)
        }
        let harness = URL(fileURLWithPath: path)
        guard FileManager.default.isExecutableFile(atPath: electronBinary(in: harness).path),
              FileManager.default.fileExists(atPath: harness.appendingPathComponent("libprobe.dylib").path) else {
            check(false, "the Electron harness in \(path) (Electron and libprobe.dylib: make electron-harness)")
            return
        }
        let userData = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-electron-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: userData) }
        let answer = calls.isEmpty ? expected : calls
        let recording = runElectronHarness(harness, script: "type-keys", field: "composer", userData: userData, typed: "#1", keys: "return",
                                           answer: PageFieldClient.answer(answer)) ?? ""
        let outcome = pageOutcome(in: recording)
        let text = outcome.text ?? ""
        check(outcome.answered == answer.map(PageFieldClient.recorded) && outcome.keys == ["229"] && outcome.sent.isEmpty
              && text.hasPrefix("#1First line of the copy") && text.hasSuffix("and its second line") && outcome.markedLeft == false,
              "Electron harness, Slack's composer: ⏎ reached the page as \(outcome.keys), it sent \(outcome.sent.isEmpty ? "nothing" : "\(outcome.sent)"), "
              + "its text \(text.debugDescription) (\(outcome.answered.joined(separator: "; ")))")
        let upAnswer = upCalls.isEmpty ? upExpected : upCalls
        let up = pageOutcome(in: runElectronHarness(harness, script: "type-keys", field: "composer", userData: userData, typed: "", keys: "up",
                                                    answer: PageFieldClient.answer(upAnswer)) ?? "")
        check(up.answered == upAnswer.map(PageFieldClient.recorded) && up.keys == ["229"] && up.acted.isEmpty && (up.text ?? "").isEmpty
              && up.markedLeft == false,
              "Electron harness, an empty composer: ↑ reached the page as \(up.keys), it acted on \(up.acted.isEmpty ? "nothing" : "\(up.acted)"), "
              + "its text \((up.text ?? "-").debugDescription) (\(up.answered.joined(separator: "; ")))")
        // A selection, then ⌃V ↓ ⏎; an emoji before the caret, then ⌃V ↑ Esc: each key the input method's, nothing sent or
        // acted on; the selection replaced by the row, the emoji's text as it was.
        for (what, start, keys, answers, result) in [
            ("\"world\" selected: ⌃V ↓ ⏎", "Hello |world|", "control-v,down,return", over.calls.isEmpty ? overExpected : over.calls,
             "Hello an older copy"),
            ("an emoji before the caret: ⌃V ↑ Esc", "ok 👍", "control-v,up,escape", around.calls.isEmpty ? aroundExpected : around.calls, "ok 👍"),
        ] {
            let page = pageOutcome(in: runElectronHarness(harness, script: "type-keys", field: "composer", userData: userData, typed: "",
                                                          keys: keys, answer: PageFieldClient.answer(eachOf: answers), start: start) ?? "")
            check(page.answered == answers.flatMap { $0.map(PageFieldClient.recorded) } && page.keys == ["229", "229", "229"]
                  && page.sent.isEmpty && page.acted.isEmpty && page.text == result && page.markedLeft == false,
                  "Electron harness, Slack's composer with \(what): the keys reached the page as \(page.keys), it sent "
                  + "\(page.sent.isEmpty ? "nothing" : "\(page.sent)") and acted on \(page.acted.isEmpty ? "nothing" : "\(page.acted)"), "
                  + "its text \((page.text ?? "-").debugDescription) (\(page.answered.joined(separator: "; ")))")
        }
    }
}

/// An image on a pasteboard, its data given only when asked, counted.
private final class PromisedImage: NSObject, NSPasteboardItemDataProvider {
    var asked = 0

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        asked += 1
        item.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: type)
    }
}
