import Foundation
import Testing
@testable import AllInOneIMECore

/// The settings as a settings window in another process sees them (`SettingsService`, Windows' Settings app over the
/// wire): a document of sections and fields made for one platform, one change at a time checked against its field, and
/// the actions. A config file of its own for each test, keys only in an in-memory store.
@Suite(.serialized)
struct SettingsServiceTests {
    func service(_ text: String = "{}", platform: SettingsPlatform = .windows) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        // The plugins in the test's own folder: the user's are never read.
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        let service = SettingsService(store: SettingsStore(configURL: url), platform: platform, library: library)
        service.keySource = { APIKeys.hasKeychainKey(account: $0.rawValue) ? .keychain : .none }
        return (service, url)
    }

    func withMemorySecrets<T>(_ body: () async throws -> T) async rethrows -> T {
        var platform = Platform.current
        platform.secrets = .inMemory()
        return try await Platform.$override.withValue(platform) { try await body() }
    }

    func ids(_ document: SettingsDocument) -> Set<String> { Set(document.sections.flatMap { $0.fields.map(\.id) }) }

    // MARK: The document

    /// What only the Mac has is left out of Windows' document, and in the Mac's: iCloud sync, the menu bar icon, Chrome's
    /// page, voice; a choice only the Mac has (Apple Notes) too, unless it is the value now (then shown, not to be picked).
    @Test func macOnlyFieldsStayOnTheMac() throws {
        let windows = try service(#"{"provider": "anthropic"}"#).0.document()
        let mac = try service(#"{"provider": "anthropic"}"#, platform: .mac).0.document()
        let macOnly: Set = ["iCloudSync", "menuBarIcon", "agentPageContext", "voiceInput", "checkForUpdates"]
        #expect(ids(windows).isDisjoint(with: macOnly))
        #expect(macOnly.isSubset(of: ids(mac)))
        #expect(windows.platform == .windows && mac.platform == .mac)
        // Notes by default: Apple Notes is the value, shown on Windows but not to be picked.
        let destination = try #require(windows.field("notes.destination"))
        #expect(destination.choices?.first { $0.value == .string("notes") }?.disabled == true)
        #expect(mac.field("notes.destination")?.choices?.first { $0.value == .string("notes") }?.disabled == nil)
        // Options only the Mac has (⌥ as the action key) are left out on Windows.
        #expect(windows.field("actionKey")?.choices?.map(\.value) == [.string("enter"), .string("space")])
        #expect(mac.field("actionKey")?.choices?.count == 4)
    }

    /// A provider's own fields only while it is the one in use; the key as a secret: never its value.
    @Test func theProviderInUse() async throws {
        try await withMemorySecrets {
            let (service, _) = try service(#"{"provider": "openai", "openai": {"model": "deepseek-chat"}}"#)
            var document = service.document()
            #expect(document.field("openai.model")?.value == .string("deepseek-chat"))
            #expect(document.field("anthropic.model") == nil && document.field("bedrock.modelId") == nil)
            let key = try #require(document.field("openai.key"))
            #expect(key.kind == .secret && key.value == nil && key.isSet == false && key.actions == ["setKey"])
            // The key goes once, to the secret store; the document says it is saved and its last 4, never the key.
            let saved = await service.perform(SettingsAction(field: "openai.key", name: "setKey", key: "sk-test-wire-0123456789-a1b2"))
            #expect((try? saved.get()) != nil)
            document = service.document()
            let after = try #require(document.field("openai.key"))
            #expect(after.isSet == true && after.status?.contains("a1b2") == true && after.actions == ["setKey", "removeKey"])
            let text = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
            #expect(!text.contains("sk-test-wire"))
            let removed = await service.perform(SettingsAction(field: "openai.key", name: "removeKey"))
            #expect((try? removed.get()) != nil && !APIKeys.hasKeychainKey(account: "openai"))
            // An empty key saves nothing.
            if case let .failure(problem) = await service.perform(SettingsAction(field: "openai.key", name: "setKey", key: "  ")) {
                #expect(problem.code == .badValue)
            } else {
                Issue.record("an empty key was taken")
            }
        }
    }

    // MARK: Changes

    /// One change, checked against its field, saved key by key; the revision moves and `changed` hears it.
    @Test func aChangeIsCheckedAndSaved() throws {
        let (service, url) = try service(#"{"maxTokens": 1000, "aLaterKey": 1}"#)
        let heard = Locked<[UInt64]>(initialState: [])
        service.changed = { revision in heard.withLock { $0.append(revision) } }
        let before = service.revision
        #expect((try? service.set("maxTokens", to: .number(1500)).get()) != nil)
        #expect(try Config.load(from: url).maxTokens == 1500)
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("\"aLaterKey\": 1"))
        #expect(service.revision > before && heard.withLock { $0 } == [service.revision])
        func problem(_ id: String, _ value: AIConfig.JSONValue) -> SettingsProblem? {
            if case let .failure(problem) = service.set(id, to: value) { return problem }
            return nil
        }
        #expect(problem("maxTokens", .number(50))?.code == .badValue)  // out of 200…4000
        #expect(problem("maxTokens", .number(1550))?.code == .badValue)  // not in steps of 100
        #expect(problem("maxTokens", .string("2000"))?.code == .badValue)
        #expect(problem("typeOut", .number(1))?.code == .badValue)
        #expect(problem("noSuchSetting", .bool(true))?.code == .unknownField)
        #expect(problem("menuBarIcon", .bool(false))?.code == .unknownField)  // the Mac's
        #expect(problem("configFile", .string("/tmp/x"))?.code == .notChangeable)
        #expect(problem("inputLanguages", .array([]))?.code == .badValue)  // at least one
        #expect(problem("inputLanguages", .array([.string("klingon")]))?.code == .badValue)
        #expect(problem("inputLanguages", .array([.string("en"), .string("en")]))?.code == .badValue)
        #expect(try Config.load(from: url).maxTokens == 1500)
    }

    /// The rules each change follows are the store's: the first input language is the default, a style list is
    /// resolved, the interface language is applied at once.
    @Test func theStoresRules() throws {
        let (service, url) = try service()
        #expect((try? service.set("inputLanguages", to: .array([.string("zh"), .string("en")])).get()) != nil)
        var config = try Config.load(from: url)
        #expect(config.inputLanguages == [.chinese, .english] && config.defaultInput == .chinese)
        // Fuzzy pinyin shows with Chinese only.
        #expect(service.document().field("fuzzyPinyin") != nil)
        #expect((try? service.set("fuzzyPinyin", to: .array([.string("z-zh")])).get()) != nil)
        #expect(try Config.load(from: url).fuzzyPinyin == ["z-zh"])
        #expect((try? service.set("provider", to: .string("bedrock")).get()) != nil)
        #expect(service.document().field("bedrock.modelId") != nil && service.document().field("temperature") != nil)
        #expect((try? service.set("temperature", to: .null).get()) != nil)
        config = try Config.load(from: url)
        #expect(config.provider == .bedrock && config.temperature == nil)
        #expect((try? service.set("bedrock.region", to: .string("  ")).get()) != nil)
        #expect(try Config.load(from: url).region == nil)
        // The Cloud's sign-in and Apple's model aren't Windows' choices.
        let providers = service.document().field("provider")?.choices?.compactMap(\.value.string) ?? []
        #expect(!providers.contains("apple") && !providers.contains("hosted") && providers.contains("anthropic"))
    }

    /// A file that can't be read: shown read-only, saying why, and left as it is.
    @Test func aBrokenFile() throws {
        let (service, url) = try service("{ nope")
        let document = service.document()
        #expect(document.loadError != nil && document.field("typeOut")?.readOnly == true)
        if case let .failure(problem) = service.set("typeOut", to: .bool(true)) {
            #expect(problem.code == .configBroken)
        } else {
            Issue.record("a change was taken over a broken file")
        }
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == "{ nope")
    }

    /// The file changed by something else (the command line, an editor): read again, and the revision moves.
    @Test func changesMadeElsewhere() throws {
        let (service, url) = try service()
        let before = service.revision
        service.checkForChanges()
        #expect(service.revision == before)
        try Data(#"{"maxTokens": 2000}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        service.checkForChanges()
        #expect(service.revision > before && service.document().field("maxTokens")?.value == .number(2000))
    }

    // MARK: Commands

    /// Custom commands with the editor's rules: a name taken, an empty prompt, saved and deleted by name.
    @Test func customCommands() async throws {
        let (service, url) = try service()
        func save(_ definition: [String: AIConfig.JSONValue], as original: String? = nil) async -> SettingsProblem? {
            if case let .failure(problem) = await service.perform(SettingsAction(field: "commands.custom", name: "save", item: original,
                                                                                  value: .object(definition))) {
                return problem
            }
            return nil
        }
        #expect(await save(["name": .string("polite"), "type": .string("prompt"), "prompt": .string("Make it polite")]) == nil)
        #expect(await save(["name": .string("improve"), "type": .string("prompt"), "prompt": .string("x")])?.message
                == UIText.describe(.nameTaken))
        #expect(await save(["name": .string("terse"), "type": .string("prompt"), "prompt": .string(" ")])?.message
                == UIText.describe(.emptyPrompt))
        #expect(await save(["name": .string("polite2"), "type": .string("prompt"), "prompt": .string("y")])?.message
                == UIText.describe(.nameNotLetters))
        #expect(await save(["nonsense": .bool(true)])?.code == .badValue)
        // Renamed in place.
        #expect(await save(["name": .string("courteous"), "type": .string("prompt"), "prompt": .string("Make it polite")], as: "polite") == nil)
        let item = try #require(service.document().field("commands.custom")?.items?.first)
        #expect(item.id == "courteous" && item.actions == ["save", "delete"] && item.value != nil)
        let deleted = await service.perform(SettingsAction(field: "commands.custom", name: "delete", item: "courteous"))
        #expect((try? deleted.get()) != nil)
        #expect(try Config.load(from: url).customCommands.isEmpty)
        // An action a field doesn't have.
        if case let .failure(problem) = await service.perform(SettingsAction(field: "maxTokens", name: "test")) {
            #expect(problem.code == .notChangeable)
        } else {
            Issue.record("an action the field doesn't have was run")
        }
    }

    /// The document as JSON: what a client reads (keys sorted, nothing it doesn't have), and back.
    @Test func theDocumentAsJSON() throws {
        let (service, _) = try service(#"{"typeOut": true}"#)
        let document = service.document()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        #expect(try JSONDecoder().decode(SettingsDocument.self, from: data) == document)
        let rate = try #require(document.field("typeOutRate"))
        #expect(rate.kind == .number && rate.status != nil && rate.min == TypeOut.slowestRate)
        let text = String(decoding: try encoder.encode(document.field("typeOut")), as: UTF8.self)
        #expect(text.hasPrefix(#"{"help":"#) && text.contains(#""id":"typeOut","kind":"toggle","#) && !text.contains("null"))
    }
}
