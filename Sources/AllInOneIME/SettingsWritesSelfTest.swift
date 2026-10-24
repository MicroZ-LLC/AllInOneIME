import AllInOneIMECore
import AppKit
import SwiftUI

extension SelfTest {
    /// Settings writes the config file only when something in it was changed. Each page is opened (AI for each provider),
    /// every text field is entered, ⏎ pressed on it as it is, and left; the window is closed: the file wasn't
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
            for page in provider == .bedrock ? SettingsPage.allCases : [.ai] {
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

    /// A field copied from the config when its page shows follows the config while it isn't being edited, and is written
    /// back only when it was: with Privacy's words showing, the search's Change adds a word to the file; the page is left
    /// and the window closed: the word is still there. With a word typed into the field meanwhile, both are kept.
    static func testFieldsFollowOutsideWrites(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("outside-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        for typing in [false, true] {
            var config = Config.default
            config.provider = .bedrock
            config.redaction = RedactionSettings(enabled: true, customWords: ["Atlas"])
            try? config.write(to: url)
            let model = SettingsModel(configURL: url)
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, page: .privacy)))
            window.setContentSize(NSSize(width: 880, height: 900))
            window.makeKeyAndOrderFront(nil)
            _ = pump(timeout: 0.6) { false }
            if typing {
                func textFields(_ view: NSView) -> [NSTextField] {
                    ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
                }
                let field = window.contentView.map(textFields)?.first {
                    $0.placeholderString == tr("项目代号、名字…，用逗号分开", "A codename, a name…, separated by commas")
                }
                if let field, window.makeFirstResponder(field), let editor = window.firstResponder as? NSTextView {
                    editor.moveToEndOfDocument(nil)
                    for character in ", comet" {
                        for type in [NSEvent.EventType.keyDown, .keyUp] {
                            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                            windowNumber: window.windowNumber, context: nil, characters: String(character),
                                                            charactersIgnoringModifiers: String(character), isARepeat: false,
                                                            keyCode: keyCodes[character] ?? 0) { window.sendEvent(event) }
                        }
                    }
                    _ = pump(timeout: 0.2) { false }
                }
            }
            // The Assistant adds a word as it does: to the file, then the windows are told.
            _ = try? AIConfig.applying([.addWords(["Project Phoenix"])], at: url, now: Date())
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            _ = pump(timeout: 0.5) { false }
            // The page left, then the window closed.
            NotificationCenter.default.post(name: .allInOneIMEShowSettingsPage, object: nil, userInfo: ["page": SettingsPage.general.rawValue])
            _ = pump(timeout: 0.5) { false }
            window.close()
            model.save()  // as the settings window's close does
            _ = pump(timeout: 0.3) { false }
            let words = (try? Config.load(from: url))?.redaction.customWords ?? []
            let expected = typing ? ["Atlas", "Project Phoenix", "comet"] : ["Atlas", "Project Phoenix"]
            check(words == expected, typing
                  ? "a word typed into the field while the Assistant added one: both kept when the page is left (\(words))"
                  : "a word the Assistant adds while the Privacy words show is still there once the page is left and closed (\(words))")
        }
    }

    /// The custom agent's command (Settings → Commands → @agent) follows the config the same way: a command written into
    /// the file by hand while the field shows is read again and shown, and what's typed then goes on from it.
    static func testAgentCommandFollowsOutsideWrites(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("agent-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Config.default
        (config.agent, config.agentCommand) = (.custom, ["muse", "--"])
        try? config.write(to: url)
        let model = SettingsModel(configURL: url)
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, page: .commands)))
        window.setContentSize(NSSize(width: 880, height: 900))
        window.makeKeyAndOrderFront(nil)
        _ = pump(timeout: 0.6) { false }
        // By hand: another command, and the window told (as when it notices the file changed).
        config.agentCommand = ["kiro-cli", "chat", "--"]
        try? config.write(to: url)
        NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
        _ = pump(timeout: 0.5) { false }
        func textFields(_ view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
        }
        let field = window.contentView.map(textFields)?.first { $0.placeholderString == tr("例如 ", "e.g. ") + "muse --" }
        let shown = field?.stringValue ?? "-"
        // " x" typed at its end.
        if let field, window.makeFirstResponder(field), let editor = window.firstResponder as? NSTextView {
            editor.moveToEndOfDocument(nil)
            for character in " x" {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, characters: String(character),
                                                    charactersIgnoringModifiers: String(character), isARepeat: false,
                                                    keyCode: keyCodes[character] ?? 0) { window.sendEvent(event) }
                }
            }
            _ = pump(timeout: 0.2) { false }
        }
        window.close()
        model.save()  // as the settings window's close does
        _ = pump(timeout: 0.3) { false }
        let written = (try? Config.load(from: url))?.agentCommand ?? []
        check(shown == "kiro-cli chat --" && written == ["kiro-cli", "chat", "--", "x"],
              "the custom agent's command follows a hand edit, and typing goes on from it (shown \(shown), written \(written))")
    }

    /// A Settings save writes only what the window changed. With Settings open, the search's Change sets one app's profile
    /// and a switch of hiding sensitive information, and the window isn't told; the window then changes another app's
    /// Insert (General → Suggestions) and a category of hiding (one the config set off, shown with Restore Default), and
    /// saves: all four are in the file, and the window shows them.
    static func testSettingsSavesOnlyItsChanges(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("both-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (mail, weChat) = ("com.apple.mail", "com.tencent.xinWeChat")
        var config = Config.default
        config.appProfiles = [mail: AppProfile(inputLanguage: .english), weChat: AppProfile(inputLanguage: .chinese)]
        config.redaction = RedactionSettings(enabled: true, phones: false)
        try? config.write(to: url)
        let model = SettingsModel(configURL: url)
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, page: .general)))
        window.setContentSize(NSSize(width: 880, height: 900))
        window.makeKeyAndOrderFront(nil)
        _ = pump(timeout: 0.6) { false }
        // The search's Change: no AI in Mail, emails no longer hidden; the window not told.
        _ = try? AIConfig.applying([.app(mail, .noAI(true)), .flag(.redactionEmails, false)], at: url, now: Date())
        // The window: WeChat inserts with title (its list's picker), phone numbers hidden again (Restore Default), saved as
        // its controls save.
        model.changeProfile(weChat) { $0.suggestionsInsert = .title }
        model.config.redaction.phones = true
        model.save()
        window.close()
        model.save()  // as the settings window's close does
        _ = pump(timeout: 0.3) { false }
        let file = (try? Config.load(from: url)) ?? .default
        check(file.appProfiles[mail] == AppProfile(inputLanguage: .english, noAI: true)
              && file.appProfiles[weChat] == AppProfile(inputLanguage: .chinese, suggestionsInsert: .title)
              && !file.redaction.emails && file.redaction.phones && file.redaction.cards,
              "a Settings save over a Change it hadn't read keeps both: another app's profile, another switch (\(file.appProfiles), "
              + "emails \(file.redaction.emails), phones \(file.redaction.phones))")
        check(model.config.appProfiles[mail]?.noAI == true && !model.config.redaction.emails, "and the window then shows the Change's change")
    }

    /// General → Previous per-app settings → Remove clears what an app's profile still sets of the settings no longer
    /// offered (where it starts, Translate as You Type always on, autocomplete always, typing out, rewrite styles), its
    /// Insert (its Off among it: suggestions off, never listed here) and No AI kept; another app's are as they were; an
    /// app left with nothing goes from the file. The section is there only while an app has one.
    static func testPreviousAppSettings(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("previous-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (slack, mail, notes) = ("com.tinyspeck.slackmacgap", "com.apple.mail", "com.apple.Notes")
        var config = Config.default
        config.appProfiles = [slack: AppProfile(inputLanguage: .english, translateAlways: true, autocomplete: true, suggestions: false,
                                                suggestionsInsert: .titleAndLink),
                              mail: AppProfile(rewriteStyles: ["正式"], typeOut: true), notes: AppProfile(noAI: true, suggestions: false)]
        try? config.write(to: url)
        let model = SettingsModel(configURL: url)
        check(Set(model.previousAppSettings.map(\.app)) == [mail, slack],
              "the previous per-app settings list Slack and Mail, not Notes (No AI and Off only): \(model.previousAppSettings.map(\.app))")
        let row = model.previousAppSettings.first { $0.app == slack }?.text ?? ""
        let name = AppNames.name(for: slack)
        check(row == tr("\(name)：用英文开始、总是边打边译、总是续写", "\(name): starts in English, Always Translate as You Type, Autocomplete always on"),
              "Slack's row says what it sets: \(row)")
        model.removePreviousSettings(slack)
        var file = (try? Config.load(from: url)) ?? .default
        check(file.appProfiles[slack] == AppProfile(suggestions: false, suggestionsInsert: .titleAndLink)
              && file.appProfiles[mail] == config.appProfiles[mail] && file.appProfiles[notes] == AppProfile(noAI: true, suggestions: false),
              "Remove clears Slack's, its Insert and Off kept, Mail's and Notes' as they were (\(file.appProfiles))")
        model.removePreviousSettings(mail)
        file = (try? Config.load(from: url)) ?? .default
        check(file.appProfiles[mail] == nil && model.previousAppSettings.isEmpty,
              "Mail, left with nothing, goes from the file; the section is gone (\(file.appProfiles))")
    }

    /// General → Suggestions → "In these apps" with Off (the owner's decision of 2026-10-24), as its picker and Remove
    /// write it (`SettingsModel.setInsertChoice`): an app with only its suggestions off is listed, at Off; Off chosen for
    /// an app that inserts with title and link turns its suggestions off and keeps that; With title turns them back on
    /// with it; Remove clears both, its No AI kept; an app with neither isn't listed, its settings untouched. The page is
    /// drawn with an app at Off, in both languages.
    static func testAppInsertOff(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("insert-off-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (mail, terminal, notes) = ("com.apple.mail", "com.apple.Terminal", "com.apple.Notes")
        var config = Config.default
        config.appProfiles = [mail: AppProfile(noAI: true, suggestionsInsert: .titleAndLink), terminal: AppProfile(suggestions: false),
                              notes: AppProfile(inputLanguage: .english)]
        try? config.write(to: url)
        let model = SettingsModel(configURL: url)
        func own(_ app: String) -> AppProfile? { ((try? Config.load(from: url)) ?? .default).appProfiles[app] }
        check(Set(model.appInsertApps) == [mail, terminal] && model.config.profile(for: terminal)?.insertChoice == .off,
              "In these apps lists Mail and Terminal (Off, nothing to insert of its own), not Notes: \(model.appInsertApps)")
        model.setInsertChoice(.off, for: mail)
        check(own(mail) == AppProfile(noAI: true, suggestions: false, suggestionsInsert: .titleAndLink)
              && model.config.profile(for: mail)?.insertChoice == .off,
              "Off for Mail: its suggestions off, With title and link kept for when they're back (\(own(mail).map { "\($0)" } ?? "none"))")
        model.setInsertChoice(.insert(.title), for: mail)
        check(own(mail) == AppProfile(noAI: true, suggestionsInsert: .title),
              "With title for Mail: its suggestions back on, with title (\(own(mail).map { "\($0)" } ?? "none"))")
        model.setInsertChoice(.off, for: mail)
        model.setInsertChoice(nil, for: mail)
        model.setInsertChoice(nil, for: terminal)
        check(own(mail) == AppProfile(noAI: true) && own(terminal) == nil && own(notes) == config.appProfiles[notes] && model.appInsertApps.isEmpty,
              "Remove clears both, Mail's No AI kept, Terminal gone, Notes as it was (\(((try? Config.load(from: url)) ?? .default).appProfiles))")

        let chosen = UIText.choice
        defer { UIText.choice = chosen }
        for (name, language) in [("settings-insert-off", "zh"), ("settings-insert-off-en", "en")] {
            UIText.choice = language
            let preview = SettingsModel(configURL: url, persists: false)
            preview.config.appProfiles = [mail: AppProfile(suggestionsInsert: .titleAndLink), terminal: AppProfile(suggestions: false)]
            let image = snapshotDirectory.appendingPathComponent("\(name).png")
            SettingsImage.render(preview, page: .general, to: image) { seconds in _ = pump(timeout: seconds) { false } }
            check(FileManager.default.fileExists(atPath: image.path) && AppInsertChoice.off.label == tr("关闭", "Off"),
                  "General drawn with Terminal at Off in these apps (\(language))")
        }
    }
}
