import AllInOneIMECore
import AppKit
import InputMethodKit

/// Clipboard history in the self-test (`--selftest DIR --clipboard-only`): its logic is the core's unit tests'
/// (ClipboardHistorySessionTests) and the recording's the Mac's (ClipboardHistoryRecordingTests); here the real panel
/// shows on ⌃V, and ⏎ puts a two-line row in through IMK, into an NSTextView and into Slack's composer in the Electron
/// harness (where `ALLINONEIME_ELECTRON_HARNESS` names it), nothing sent. The history is the self-test's own, and so is
/// what ⌃V reads of the clipboard: the user's clipboard and history file are never read or written.
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
                     pass: controller.passPasteKey, override: controller.clientOverride)
        defer {
            controller.services.clipboardHistory = saved.history
            (controller.readClipboard, controller.chromiumApp, controller.passPasteKey) = (saved.read, saved.chromium, saved.pass)
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
        controller.readClipboard = { .text(item) }  // what ⌃V reads: the self-test's, never the clipboard
        var pasteKeys = 0
        controller.passPasteKey = { pasteKeys += 1 }
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

        // In the Electron harness's composer, that answer to ⏎ (the input method's as above; as it answers where the keys
        // couldn't be composed here, a locked screen): the text in, the key the input method's, nothing sent. The harness
        // runs on a locked screen too: it needs nothing composed here.
        section("Clipboard history: the two lines into Slack's composer in the Electron harness, ⏎ not sent")
        guard let path = ProcessInfo.processInfo.environment["ALLINONEIME_ELECTRON_HARNESS"], !path.isEmpty else {
            print("  the Electron harness: not run (make electron-harness, then ELECTRON_HARNESS=build/electron-harness)")
            return
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
    }
}
