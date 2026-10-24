import Foundation
import Testing
@testable import AllInOneIMECore

/// What Windows' Settings app needed of the settings document besides the Mac window's pages: the per-app settings
/// (an app added by its program, its own fields, removed), the script extensions' folders and what is in them (a
/// bundle's switch, preferences and password), the lists typed as one line, the command editor's form and the window's
/// own words. A config file of its own for each test, keys only in an in-memory store.
@Suite(.serialized)
struct SettingsAppsExtensionsTests {
    typealias JSON = AIConfig.JSONValue

    func service(_ text: String = #"{"extensionFolders": []}"#) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-more-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library, secrets: .inMemory())
        service.keySource = { _ in .none }
        return (service, url)
    }

    func succeeded(_ result: Result<SettingsActionOutcome, SettingsProblem>) -> Bool {
        if case .success = result { return true }
        return false
    }

    // MARK: Apps

    /// An app added by its program (as Windows names it), listed with its own fields while it sets nothing, its settings
    /// saved in its profile, and removed.
    @Test func perAppSettings() throws {
        let (service, url) = try service()
        service.recentApps = { ["win:slack.exe", "win:notepad.exe"] }
        var list = try #require(service.document().field("apps.profiles"))
        #expect(list.kind == .items && list.actions == ["add"] && list.items?.isEmpty == true)
        #expect(list.choices?.map(\.value) == [.string("win:slack.exe"), .string("win:notepad.exe")])

        let before = service.revision
        #expect(succeeded(service.performNow(SettingsAction(field: "apps.profiles", name: "add", value: .string(#"C:\Windows\Notepad.exe"#)))))
        #expect(service.revision > before)
        list = try #require(service.document().field("apps.profiles"))
        let item = try #require(list.items?.first)
        #expect(item.id == "win:notepad.exe" && item.title == "notepad.exe" && item.actions == ["remove"])
        #expect(list.choices?.map(\.value) == [.string("win:slack.exe")])
        // Windows' own fields: where it starts, its styles, AI off, suggestions and what their rows insert; the Mac's (typed
        // out, always translate) left out.
        let ids = item.fields?.map(\.id) ?? []
        #expect(ids == ["apps.win:notepad.exe.inputLanguage", "apps.win:notepad.exe.ownStyles", "apps.win:notepad.exe.noAI",
                        "apps.win:notepad.exe.suggestions", "apps.win:notepad.exe.suggestionsInsert"])

        #expect((try? service.set("apps.win:notepad.exe.noAI", to: .bool(true)).get()) != nil)
        #expect(try Config.load(from: url).appProfiles["win:notepad.exe"]?.noAI == true)
        #expect(service.document().field("apps.profiles")?.items?.first?.detail?.isEmpty == false)
        // Its own styles: on, from the ones everywhere; then its own list.
        #expect((try? service.set("apps.win:notepad.exe.ownStyles", to: .bool(true)).get()) != nil)
        let styles = try #require(service.document().field("apps.win:notepad.exe.rewriteStyles"))
        #expect(styles.kind == .choices && styles.choices?.isEmpty == false)
        let first = try #require(styles.choices?.first?.value)
        #expect((try? service.set(styles.id, to: .array([first])).get()) != nil)
        #expect(try Config.load(from: url).appProfiles["win:notepad.exe"]?.rewriteStyles == [first.string ?? ""])
        // Nothing set any more: not saved, still listed.
        _ = service.set("apps.win:notepad.exe.noAI", to: .bool(false))
        _ = service.set("apps.win:notepad.exe.ownStyles", to: .bool(false))
        #expect(try Config.load(from: url).appProfiles.isEmpty)
        #expect(service.document().field("apps.profiles")?.items?.map(\.id) == ["win:notepad.exe"])

        #expect(succeeded(service.performNow(SettingsAction(field: "apps.profiles", name: "remove", item: "win:notepad.exe"))))
        #expect(service.document().field("apps.profiles")?.items?.isEmpty == true)
        // An app's program has no spaces.
        if case let .failure(problem) = service.performNow(SettingsAction(field: "apps.profiles", name: "add", value: .string("my app"))) {
            #expect(problem.code == .badValue)
        } else {
            Issue.record("an app with a space was added")
        }
    }

    @Test func appIDs() {
        #expect(SettingsSchema.appID("Notepad.exe", platform: .windows) == "win:notepad.exe")
        #expect(SettingsSchema.appID("win:Code.exe", platform: .windows) == "win:code.exe")
        #expect(SettingsSchema.appID(#"C:\Program Files\App\App.exe"#, platform: .windows) == "win:app.exe")
        #expect(SettingsSchema.appID("Microsoft.WindowsNotepad_8wekyb3d8bbwe!App", platform: .windows)
                == "win:Microsoft.WindowsNotepad_8wekyb3d8bbwe!App")
        #expect(SettingsSchema.appID("com.apple.Safari", platform: .mac) == "com.apple.Safari")
        #expect(SettingsSchema.appID("  ", platform: .windows) == nil)
    }

    // MARK: Script extensions

    static let manifest = #"""
        {"schemaVersion": 1, "name": "tools", "title": "Team Tools", "version": "1.2.0", "author": "Someone",
         "preferences": [
           {"name": "apiToken", "type": "password", "title": "API token", "required": true},
           {"name": "region", "type": "dropdown", "title": "Region", "default": "eu",
            "data": [{"title": "Europe", "value": "eu"}, {"title": "Asia", "value": "asia"}]},
           {"name": "verbose", "type": "checkbox", "title": "Verbose", "default": false},
           {"name": "host", "title": "Host", "default": "example.com"}
         ],
         "commands": [{"script": "find.sh", "name": "find", "title": "Find someone"}]}
        """#

    /// The folders, a bundle with its switch, preferences and password (kept in the secret store, shown by its ending),
    /// and a loose script's switch.
    @Test func scriptExtensions() throws {
        let extensions = FileManager.default.temporaryDirectory.appendingPathComponent("settings-ext-\(UUID().uuidString)", isDirectory: true)
        let bundle = extensions.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extensions) }
        try Data(Self.manifest.utf8).write(to: bundle.appendingPathComponent("extension.json"))
        try Data("#!/bin/sh\necho found\n".utf8).write(to: bundle.appendingPathComponent("find.sh"))
        try Data("#!/bin/sh\n# @allinoneime.schemaVersion 1\n# @allinoneime.title Say hi\necho hi\n".utf8)
            .write(to: extensions.appendingPathComponent("hello.sh"))
        for script in [bundle.appendingPathComponent("find.sh"), extensions.appendingPathComponent("hello.sh")] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }

        let (service, url) = try service()
        #expect(service.document().field("extensions.folders")?.items?.isEmpty == true)
        #expect(succeeded(service.performNow(SettingsAction(field: "extensions.folders", name: "add", value: .string(extensions.path)))))
        let folders = try #require(service.document().field("extensions.folders"))
        #expect(folders.picker == .folder && folders.textActions == ["add"] && folders.items?.map(\.actions) == [["remove"]])

        let installed = try #require(service.document().field("extensions.installed"))
        let tools = try #require(installed.items?.first { $0.id == "bundle:tools" })
        let kinds = Dictionary(uniqueKeysWithValues: (tools.fields ?? []).map { ($0.id, $0.kind) })
        #expect(kinds["extensions.on.tools"] == .toggle)
        #expect(kinds["extensions.preference.tools.apiToken"] == .secret)
        #expect(kinds["extensions.preference.tools.region"] == .choice)
        #expect(kinds["extensions.preference.tools.verbose"] == .toggle)
        #expect(kinds["extensions.preference.tools.host"] == .text)
        #expect(kinds["extensions.on.tools/find"] == .toggle)
        #expect(installed.items?.contains { $0.title == "@hello" } == true)

        #expect((try? service.set("extensions.preference.tools.region", to: .string("asia")).get()) != nil)
        #expect((try? service.set("extensions.preference.tools.host", to: .string("example.org")).get()) != nil)
        #expect(try Config.load(from: url).extensionPreferences["tools"] == ["region": "asia", "host": "example.org"])

        // The password: once to the store, never in the file nor the document; shown by its ending.
        #expect(succeeded(service.performNow(SettingsAction(field: "extensions.preference.tools.apiToken", name: "setKey",
                                                            key: "token-secret-9z8y"))))
        let token = try #require(service.document().field("extensions.preference.tools.apiToken"))
        #expect(token.isSet == true && token.status?.hasSuffix("9z8y") == true && token.actions == ["setKey", "removeKey"])
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("token-secret"))
        #expect(succeeded(service.performNow(SettingsAction(field: "extensions.preference.tools.apiToken", name: "removeKey"))))
        #expect(service.document().field("extensions.preference.tools.apiToken")?.isSet == false)

        // The bundle off: its commands' switches go, and its name is in the disabled list.
        #expect((try? service.set("extensions.on.tools", to: .bool(false)).get()) != nil)
        #expect(try Config.load(from: url).disabledExtensions == ["tools"])
        #expect(service.document().field("extensions.on.tools/find") == nil)

        #expect(succeeded(service.performNow(SettingsAction(field: "extensions.folders", name: "remove", item: extensions.path))))
        #expect(try Config.load(from: url).extensionFolders.isEmpty)
    }

    // MARK: Lists as a line, the command editor, the window's words

    /// A list of words set as the line its field shows: the hidden words split at commas, a custom agent's command as a
    /// command line (a quote not closed refused).
    @Test func wordsAsALine() throws {
        let (service, url) = try service(#"{"redaction": {"enabled": true}, "agent": "custom", "extensionFolders": []}"#)
        #expect((try? service.set("redaction.customWords", to: .string("Project X, Jane，Doe")).get()) != nil)
        #expect(try Config.load(from: url).redaction.customWords == ["Project X", "Jane", "Doe"])
        #expect(service.document().field("redaction.customWords")?.text == "Project X, Jane, Doe")
        #expect((try? service.set("agentCommand", to: .string(#"muse --model "big one""#)).get()) != nil)
        #expect(try Config.load(from: url).agentCommand == ["muse", "--model", "big one"])
        if case let .failure(problem) = service.set("agentCommand", to: .string(#"muse "open"#)) {
            #expect(problem.code == .badValue)
        } else {
            Issue.record("a command line with a quote not closed was taken")
        }
    }

    /// The command editor's fields (`schema`), and a command saved from it with its command line typed.
    @Test func commandForm() throws {
        let (service, url) = try service()
        let field = try #require(service.document().field("commands.custom"))
        let schema = try #require(field.schema)
        #expect(schema.map(\.id).starts(with: ["name", "type", "summary", "prompt"]))
        #expect(schema.first { $0.id == "argv" }?.when == ["type": [.string("run"), .string("terminal"), .string("suggestions")]])
        let saved = service.performNow(SettingsAction(field: "commands.custom", name: "save", value: .object([
            "name": .string("upper"), "type": .string("run"), "argv": .string(#"python3 -c "print(input().upper())""#),
        ])))
        #expect(succeeded(saved))
        #expect(try Config.load(from: url).customCommands.first?.argv == ["python3", "-c", "print(input().upper())"])
    }

    @Test func theWindowsOwnWords() throws {
        let document = try service().0.document()
        let strings = try #require(document.strings)
        for name in ["window.title", "action.setKey", "action.removeKey", "action.save", "action.save.item", "action.delete",
                     "action.add", "confirm.removeKey", "save", "cancel", "moveUp", "moveDown"] {
            #expect(strings[name]?.isEmpty == false, "\(name)")
        }
        #expect(strings["confirm.delete"]?.contains("{name}") == true)
        // The confirmations by the names §12.3 gives them (a client looks an item's `remove` up as confirm.removeItem).
        for name in ["confirm.removeKey", "confirm.delete", "confirm.removeItem"] {
            #expect(strings[name]?.contains("{name}") == true, "\(name)")
        }
        let chinese = try service(#"{"uiLanguage": "zh-Hans", "extensionFolders": []}"#).0.document().strings
        #expect(chinese?["confirm.removeItem"] == "移除「{name}」？")
    }
}
