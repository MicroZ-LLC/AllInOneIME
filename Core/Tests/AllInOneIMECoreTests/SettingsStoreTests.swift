import Foundation
import Testing
@testable import AllInOneIMECore

/// The settings as a settings window changes them (`SettingsStore`): the Mac's window and Windows' Settings app (over the
/// wire) share it. Each test has a config file of its own in a temporary folder, and keys only in an in-memory store
/// (`Platform.override`): the user's are never touched.
struct SettingsStoreTests {
    /// A config file as a person might have left it: keys in their own order, spacing of their own, a key this version
    /// doesn't know. Its `maxTokens` is the default before 0.6.7, which reads as today's (2000).
    static let handWritten = """
        {
          "provider" : "anthropic",
          "maxTokens": 1000,
          "aLaterVersionsKey" : {"kept": [1, 2.50, "as is"]},
          "inputLanguages" : ["zh", "en"],
          "anthropic" : { "model" : "claude-haiku-5-5", "aFieldOfLater" : true }
        }

        """

    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(_ text: String) throws -> URL {
        let url = try folder().appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        return url
    }

    func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    /// A change elsewhere, dated later than the file was: what a store reading it again must see.
    func writeElsewhere(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
    }

    /// A platform whose secret store is in memory, for what `body` does.
    func withMemorySecrets<T>(_ body: () throws -> T) rethrows -> T {
        var platform = Platform.current
        platform.secrets = .inMemory()
        return try Platform.$override.withValue(platform, operation: body)
    }

    // MARK: The file

    /// A save writes only the keys that changed, in place: every other key keeps its text (spacing, numbers, a later
    /// version's key and field), and nothing is written when nothing changed.
    @Test func aSaveWritesOnlyWhatChanged() throws {
        let url = try file(Self.handWritten)
        let store = SettingsStore(configURL: url)
        #expect(store.canSave && store.config.provider == .anthropic && store.config.maxTokens == 2000)
        store.save()  // nothing changed: nothing written
        #expect(try text(url) == Self.handWritten)
        store.config.maxTokens = 1500
        store.save()
        #expect(try text(url) == Self.handWritten.replacingOccurrences(of: "\"maxTokens\": 1000", with: "\"maxTokens\": 1500"))
        #expect(store.saveError == nil)
        // A provider's field: only that field of the object.
        store.setProviderField(.anthropic, \.model, to: "  claude-sonnet-5-5 ")
        let written = try text(url)
        #expect(written.contains("\"claude-sonnet-5-5\"") && written.contains("\"aFieldOfLater\"")
                && written.contains("{\"kept\": [1, 2.50, \"as is\"]}"))
        #expect(try Config.load(from: url).anthropic.model == "claude-sonnet-5-5")
    }

    /// A provider's text field: trimmed, an empty one unset (the default then applies, never written as if typed), and
    /// nothing written when it doesn't change.
    @Test func aProviderFieldAsTyped() throws {
        let url = try file(Self.handWritten)
        let store = SettingsStore(configURL: url)
        store.setProviderField(.anthropic, \.model, to: "claude-haiku-5-5")  // as it is
        #expect(try text(url) == Self.handWritten)
        store.setProviderField(.openai, \.baseURL, to: "   ")
        #expect(store.config.openai.baseURL == nil && store.config.settings(for: .openai).baseURL != nil)
        store.setProviderField(.openai, \.effort, to: "", empty: "")
        #expect(store.config.openai.effort == "")
    }

    /// Without a file the settings are a new user's (`fresh`, when given), and the first save writes the whole file, as
    /// `Config.write` does.
    @Test func noFileYet() throws {
        let url = try folder().appendingPathComponent("config.json")
        var fresh = Config.default
        fresh.inputLanguages = [.english, .chinese]
        let store = SettingsStore(configURL: url, fresh: { fresh })
        #expect(store.canSave && store.config == fresh)
        store.save()  // nothing changed yet
        #expect(!FileManager.default.fileExists(atPath: url.path))
        store.config.typeOut = true
        store.save()
        var expected = fresh
        expected.typeOut = true
        let whole = try folder().appendingPathComponent("config.json")
        try expected.write(to: whole)
        #expect(try Data(contentsOf: url) == Data(contentsOf: whole))
    }

    /// A file that can't be read is left as it is: the error says why, and nothing is saved over it.
    @Test func aBrokenFileIsLeftAlone() throws {
        let broken = "{ \"maxTokens\": 1000,, }"
        let url = try file(broken)
        let store = SettingsStore(configURL: url)
        #expect(!store.canSave && store.loadError != nil && store.config == .default)
        store.setStyle(RewriteStyle.catalog[0], on: !store.isStyleOn(RewriteStyle.catalog[0]))
        store.save()
        #expect(try text(url) == broken)
        // Fixed elsewhere: read again, and saving works.
        try writeElsewhere("{\"maxTokens\": 900}", to: url)
        store.reloadIfChanged()
        #expect(store.canSave && store.loadError == nil && store.config.maxTokens == 900)
    }

    /// A preview (`persists` false) never writes, and never saves or removes a key.
    @Test func aPreviewWritesNothing() throws {
        let url = try file(Self.handWritten)
        try withMemorySecrets { () throws in
            let store = SettingsStore(configURL: url, persists: false)
            store.config.maxTokens = 3000
            store.save()
            #expect(store.saveKey("sk-test-preview-1234", for: .anthropic) == nil)
            #expect(!APIKeys.hasKeychainKey(account: "anthropic"))
            #expect(try text(url) == Self.handWritten)
        }
    }

    /// What changed elsewhere (an input method's menu, sync, an editor) is read again before it is shown, and a save
    /// doesn't put back what was there before; observers hear of it.
    @Test func readAgainWhenChangedElsewhere() throws {
        let url = try file(Self.handWritten)
        let store = SettingsStore(configURL: url)
        var heard: [SettingsStore.Change] = []
        let observation = store.observe { heard.append($0) }
        store.reloadIfChanged()  // not changed: not read
        #expect(heard.isEmpty)
        try writeElsewhere(Self.handWritten.replacingOccurrences(of: "\"maxTokens\": 1000", with: "\"maxTokens\": 700"), to: url)
        store.reloadIfChanged()
        #expect(store.config.maxTokens == 700 && heard == [.config])
        store.config.timeoutSeconds = 30
        store.save()
        #expect(try Config.load(from: url).maxTokens == 700)
        observation.cancel()
        store.config.timeoutSeconds = 45
        #expect(heard == [.config, .config])
    }

    /// A save reads the file back: what was written elsewhere meanwhile (another key) is kept, and then shown.
    @Test func aSaveKeepsWhatWasWrittenMeanwhile() throws {
        let url = try file(Self.handWritten)
        let store = SettingsStore(configURL: url)
        try writeElsewhere(Self.handWritten.replacingOccurrences(of: "\"maxTokens\": 1000", with: "\"maxTokens\": 800"), to: url)
        store.config.typeOut = true
        store.save()
        let now = try Config.load(from: url)
        #expect(now.maxTokens == 800 && now.typeOut)
        #expect(store.config.maxTokens == 800)
    }

    /// A save that fails (a folder that can't be written) says why and goes back to the file as it is: what wasn't saved
    /// isn't shown as saved, nor written by the next save of something else. A save with nothing to save after it
    /// clears the error: the file has what is shown.
    @Test func aFailedSaveGoesBack() throws {
        let url = try file(Self.handWritten)
        let store = SettingsStore(configURL: url)
        var heard: [SettingsStore.Change] = []
        let observation = store.observe { heard.append($0) }
        defer { observation.cancel() }
        let failed = try whileReadOnly(url.deletingLastPathComponent()) {
            store.config.maxTokens = 1500
            store.save()
        }
        guard failed else { return }  // a folder nothing keeps from being written (run as root)
        #expect(store.saveError != nil && store.failedSaves == 1)
        #expect(store.config.maxTokens == 2000 && heard == [.config, .status, .config])
        #expect(try text(url) == Self.handWritten)
        // Writable again: the next change is saved, and only it.
        store.config.typeOut = true
        store.save()
        #expect(store.saveError == nil)
        let now = try Config.load(from: url)
        #expect(now.typeOut && now.maxTokens == 2000)
        // Failed again; then nothing left to save: no error.
        _ = try whileReadOnly(url.deletingLastPathComponent()) {
            store.config.maxTokens = 3000
            store.save()
        }
        #expect(store.saveError != nil && store.failedSaves == 2)
        store.save()
        #expect(store.saveError == nil && store.config.maxTokens == 2000)
    }

    /// The interface language not saved: back to the one the file has, in the process too.
    @Test func anInterfaceLanguageNotSaved() async throws {
        let url = try file(#"{"uiLanguage": "en"}"#)
        let store = SettingsStore(configURL: url)
        try await withInterfaceLanguage("en") { () throws in
            let failed = try whileReadOnly(url.deletingLastPathComponent()) { store.setUILanguage("fr") }
            guard failed else { return }
            #expect(store.saveError != nil && store.config.uiLanguage == "en" && UIText.choice == "en")
        }
    }

    /// The file deleted while the store is in use (Windows' engine runs all along): read again as the store's new
    /// user's settings (`fresh`, Windows' with Chinese), not `Config.fresh`, and the next change is saved over those.
    @Test func aFileDeletedLater() throws {
        let url = try file(#"{"maxTokens": 1500}"#)
        var fresh = Config.default
        fresh.inputLanguages = [.english, .chinese]
        let store = SettingsStore(configURL: url, fresh: { fresh })
        #expect(store.config.maxTokens == 1500)
        try FileManager.default.removeItem(at: url)
        store.reloadIfChanged()
        #expect(store.config == fresh && store.loadError == nil)
        store.config.typeOut = true
        store.save()
        let written = try Config.load(from: url)
        #expect(written.inputLanguages == [.english, .chinese] && written.typeOut && written.maxTokens == fresh.maxTokens)
    }

    // MARK: Lists

    /// Commands are saved and deleted by name in the list as the file has it now (sync may have changed it); a name
    /// another command has by now isn't saved.
    @Test func commandsByName() throws {
        let url = try file("{}")
        let store = SettingsStore(configURL: url)
        #expect(store.saveCommand(CustomCommand(name: "polite", type: .prompt, prompt: "Make it polite"), editing: nil))
        #expect(store.saveCommand(CustomCommand(name: "terse", type: .prompt, prompt: "Make it short"), editing: nil))
        // Elsewhere, "brief" was added first in the list.
        var elsewhere = try Config.load(from: url)
        elsewhere.customCommands.insert(CustomCommand(name: "brief", type: .prompt, prompt: "Brief"), at: 0)
        try elsewhere.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        // Renaming "terse" to "brief" now takes another command's name: not saved.
        #expect(!store.saveCommand(CustomCommand(name: "brief", type: .prompt, prompt: "Short"), editing: "terse"))
        #expect(store.config.customCommands.map(\.name) == ["brief", "polite", "terse"])
        store.deleteCommand(named: "polite")
        #expect(try Config.load(from: url).customCommands.map(\.name) == ["brief", "terse"])
        #expect(store.otherCommands(than: "terse").map(\.name) == ["brief"])
    }

    /// The words hidden from the AI: the field's edit on the list as the file has it now.
    @Test func hiddenWords() throws {
        let url = try file("{}")
        let store = SettingsStore(configURL: url)
        #expect(store.saveWords(field: "Acme, Project X", shown: []) == ["Acme", "Project X"])
        #expect(try Config.load(from: url).redaction.customWords == ["Acme", "Project X"])
    }

    /// Input languages: one to five, the first the default; removing the only one leaves English.
    @Test func inputLanguages() throws {
        let store = SettingsStore(configURL: try file("{\"inputLanguages\": [\"en\"]}"))
        store.addInputLanguage(.chinese)
        store.addInputLanguage(.french)
        #expect(store.config.inputLanguages == [.english, .chinese, .french] && store.config.defaultInput == .english)
        store.moveInputLanguage(.chinese, by: -1)
        #expect(store.config.inputLanguages == [.chinese, .english, .french] && store.config.defaultInput == .chinese)
        store.moveInputLanguage(.chinese, by: -1)  // the first already
        #expect(store.config.inputLanguages.first == .chinese)
        store.makeDefaultInput(.french)
        #expect(store.config.inputLanguages == [.french, .chinese, .english] && store.config.defaultInput == .french)
        store.removeInputLanguage(.french)
        store.removePackLanguage(.chinese)
        #expect(store.config.inputLanguages == [.english])
        store.removeInputLanguage(.english)
        #expect(store.config.inputLanguages == [.english])
    }

    /// Output languages: one always stays, and the first is the one in use.
    @Test func outputLanguages() throws {
        let store = SettingsStore(configURL: try file("{\"outputLanguages\": [\"en\"]}"))
        let french = try #require(OutputLanguage.catalog.first { $0.code == "fr" })
        store.addOutputLanguage(french)
        store.removeOutputLanguage(store.config.outputLanguages[0])
        #expect(store.config.outputLanguages == [french] && store.config.outputLanguage == french)
        store.removeOutputLanguage(french)
        #expect(store.config.outputLanguages == [french])
    }

    /// Rewrite styles on and off, and in an order of one's own.
    @Test func rewriteStyles() throws {
        let url = try file("{}")
        let store = SettingsStore(configURL: url)
        let style = RewriteStyle.catalog[0]
        let on = store.isStyleOn(style)
        store.setStyle(style, on: !on)
        #expect(store.isStyleOn(style) == !on)
        #expect(try Config.load(from: url).rewriteStyles == store.config.rewriteStyles)
    }

    /// "Remember recent questions" off: the shell deletes the ones kept; on again, nothing is deleted.
    @Test func forgettingQuestions() throws {
        let store = SettingsStore(configURL: try file("{}"))
        var forgotten = 0
        store.questionsForgotten = { forgotten += 1 }
        store.setRememberQuestions(false)
        store.setRememberQuestions(true)
        #expect(forgotten == 1 && store.config.rememberQuestions)
    }

    /// The interface language, switched at once and saved (as "zh" and "en" for those two, as older versions read them).
    @Test func interfaceLanguage() async throws {
        let url = try file("{}")
        let store = SettingsStore(configURL: url)
        // The process's language: in turn with the other tests that set it.
        try await withInterfaceLanguage("en") { () throws in
            store.setUILanguage("fr")
            #expect(UIText.choice == "fr")
            #expect(try Config.load(from: url).uiLanguage == "fr")
        }
    }

    /// Notes: a folder destination without a folder asks for one first (cancelled: nothing changes).
    @Test func notesDestination() throws {
        let url = try file("{}")
        let store = SettingsStore(configURL: url)
        #expect(!store.setNotesDestination(.folder) { nil })
        #expect(store.config.notes.destination == NoteSettings().destination)
        #expect(store.setNotesDestination(.folder) { "~/Notes" })
        #expect(try Config.load(from: url).notes.folder == "~/Notes")
        store.setNotesFolder("~/Vault")
        #expect(store.config.notes.folder == "~/Vault" && store.config.notes.destination == .folder)
    }

    /// Extensions: switched off by id, folders added and found ones hidden.
    @Test func extensions() throws {
        let url = try file("{}")
        let store = SettingsStore(configURL: url)
        store.setEnabled("units/convert", false)
        #expect(!store.isEnabled("units/convert"))
        store.setEnabled("units/convert", true)
        #expect(store.isEnabled("units/convert"))
        store.addExtensionFolder("~/Scripts")
        store.addExtensionFolder("~/Scripts")
        #expect(store.config.extensionFolders.filter { $0 == "~/Scripts" }.count == 1)
    }

    // MARK: Keys

    /// Keys go to the secret store, never the config file; a blank one saves nothing and removes nothing; observers
    /// hear of each.
    @Test func keysInTheSecretStore() throws {
        let url = try file(Self.handWritten)
        try withMemorySecrets { () throws in
            let store = SettingsStore(configURL: url)
            var heard: [SettingsStore.Change] = []
            let observation = store.observe { heard.append($0) }
            defer { observation.cancel() }
            #expect(store.saveKey("   ", for: .anthropic) == nil && heard.isEmpty)
            #expect(store.saveKey("sk-test-settings-a1b2", for: .anthropic) == nil)
            #expect(heard == [.keys] && APIKeys.keyEnding(account: "anthropic") == "a1b2")
            #expect(try text(url) == Self.handWritten)
            let states = SettingsStore.keyStates([.anthropic, .openai], lookup: { APIKeys.hasKeychainKey(account: $0.rawValue) ? .keychain : .none })
            #expect(KeyState(states.sources[.anthropic], ending: states.endings[.anthropic]) == .saved(ending: "a1b2"))
            #expect(KeyState(states.sources[.openai], ending: states.endings[.openai]) == .missing)
            #expect(store.removeKey(.anthropic) == nil && !APIKeys.hasKeychainKey(account: "anthropic"))
            #expect(store.saveSearchKey("search-test-key-9999") == nil && APIKeys.keyEnding(account: WebSearch.backend.keyAccount) == "9999")
            #expect(store.removeSearchKey() == nil && !APIKeys.hasKeychainKey(account: WebSearch.backend.keyAccount))
            #expect(store.saveNotionToken("ntn_test_token_0000") == nil && APIKeys.hasKeychainKey(account: NotionAPI.keyAccount))
            #expect(store.removeNotionToken() == nil && !APIKeys.hasKeychainKey(account: NotionAPI.keyAccount))
        }
    }

    /// As a key row says it.
    @Test func keyStateText() {
        #expect(KeyState(.keychain, ending: "a1b2").text(missing: "none").hasPrefix("✓ "))
        #expect(KeyState(.environment("OPENAI_API_KEY"), ending: nil).isSet)
        #expect(KeyState(APIKeys.Source.none, ending: nil).text(missing: "none") == "none")
        #expect(KeyState(nil, ending: nil) == .loading)
    }
}

/// `body` with `folder` read-only (a save into it fails), then writable again. False, `body` not run, where that keeps
/// nothing from writing there (root). On Windows, where a folder's read-only attribute keeps nothing from being written
/// in it (nor a file's from being replaced by an atomic write), writing is denied to everyone on the folder and what is
/// in it (`denyWrites`), then allowed again; no one writes past that (an administrator neither), so a folder it can't
/// make read-only is the helper broken: an issue, not a test skipped quietly.
func whileReadOnly(_ folder: URL, _ body: () throws -> Void) throws -> Bool {
    #if os(Windows)
    guard let restore = denyWrites(in: folder) else {
        Issue.record("couldn't deny writes in \(folder.path)")
        return false
    }
    defer { restore() }
    let probe = folder.appendingPathComponent("probe.txt")
    if (try? Data().write(to: probe)) != nil {
        try? FileManager.default.removeItem(at: probe)
        Issue.record("\(folder.path) is still writable with writes denied")
        return false
    }
    #else
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
    guard !FileManager.default.isWritableFile(atPath: folder.path) else { return false }
    #endif
    try body()
    return true
}
