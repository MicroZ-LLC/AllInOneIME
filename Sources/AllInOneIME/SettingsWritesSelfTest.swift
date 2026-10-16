import AllInOneIMECore
import AppKit
import SwiftUI

extension SelfTest {
    /// Settings writes the config file only when something in it was changed. Each page is opened (AI Provider for each
    /// provider), every text field is entered, ⏎ pressed on it as it is, and left; the window is closed: the file wasn't
    /// written at all. Then a letter is typed after each field's text and deleted: the file ends as it was, with no default
    /// put in where nothing was set (a default a field isn't set to is only its placeholder).
    static func testSettingsWritesNothingUnasked(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("untouched-config.json")
        let looksUp = SettingsModel.looksUpKeys
        defer {
            SettingsModel.looksUpKeys = looksUp
            try? FileManager.default.removeItem(at: url)
            _ = secureInputGoes()  // a key field's, if the focus went through one
        }
        SettingsModel.looksUpKeys = false
        func stamp() -> (Data?, Date?) {
            (try? Data(contentsOf: url), (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)
        }
        /// The page in a window of its own, on the file as it is, and its text fields (the sidebar's search aside).
        func open(_ page: SettingsPage) -> (NSWindow, [NSTextField]) {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: SettingsModel(configURL: url),
                                                                                                     page: page)))
            window.setContentSize(NSSize(width: 880, height: 900))
            window.makeKeyAndOrderFront(nil)
            _ = pump(timeout: 0.6) { false }
            func textFields(_ view: NSView) -> [NSTextField] {
                ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
            }
            let fields = window.contentView.map(textFields)?.filter {
                $0.isEditable && !($0 is NSSecureTextField) && $0.placeholderString != tr("搜索设置…", "Search settings…")
            } ?? []
            return (window, fields)
        }
        /// A key pressed in the field that has the focus.
        func key(_ characters: String, _ code: UInt16, in window: NSWindow) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, characters: characters,
                                                   charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { continue }
                window.sendEvent(event)
            }
            _ = pump(timeout: 0.05) { false }
        }
        func close(_ window: NSWindow) {
            window.close()
            _ = pump(timeout: 0.3) { false }
        }
        var written: [String] = []
        var entered = 0
        for provider in [Provider.bedrock, .anthropic, .gemini, .openai] {
            for page in provider == .bedrock ? SettingsPage.allCases : [.provider] {
                var config = Config.default
                config.provider = provider
                config.modelId = "us.example.custom-model-v1:0"  // Bedrock's Model ID field shown too
                config.redaction.enabled = true  // and the words to hide
                try? config.write(to: url)
                try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
                let before = stamp()
                let name = provider == .bedrock ? page.rawValue : "\(page.rawValue) (\(provider.rawValue))"

                // Each field entered, ⏎ on it as it is, left; the window closed: not written at all.
                let (window, fields) = open(page)
                for field in fields where window.makeFirstResponder(field) && window.firstResponder is NSText {
                    entered += 1
                    key("\r", 0x24, in: window)
                    window.makeFirstResponder(nil)
                    _ = pump(timeout: 0.1) { false }
                }
                close(window)
                let after = stamp()
                if after.0 != before.0 || after.1 != before.1 { written.append(name + (after.0 != before.0 ? ": changed" : ": rewritten")) }

                // A letter typed after each field's text and deleted, ⏎: written as it's edited, but as it was in the end.
                let (editing, again) = open(page)
                for field in again where editing.makeFirstResponder(field) {
                    guard let editor = editing.firstResponder as? NSTextView else { continue }
                    editor.moveToEndOfDocument(nil)
                    key("x", 0x07, in: editing)
                    key("\u{7f}", 0x33, in: editing)
                    key("\r", 0x24, in: editing)
                    editing.makeFirstResponder(nil)
                    _ = pump(timeout: 0.1) { false }
                }
                close(editing)
                if stamp().0 != before.0 { written.append(name + ": changed by a letter typed and deleted") }
            }
        }
        check(written.isEmpty && entered > 0, "Settings writes the config only when something is changed: each page opened, its "
              + "\(entered) text fields entered and ⏎ pressed, the window closed (\(written.isEmpty ? "not written" : written.joined(separator: ", ")))")
    }
}
