import Foundation
import Testing
@testable import AllInOneIMECore

/// The settings as a settings window in another process sees them (`SettingsService`, Windows' Settings app over the
/// wire): a document of sections and fields made for one platform, one change at a time checked against its field, and
/// the actions. A config file of its own for each test; keys only in an in-memory store and no login environment
/// (`MemorySecrets`), so that the service is as an engine makes it (no secret store of its own, keys looked up as
/// `APIKeys.source` does) and still never reads the user's keychain or shell.
@Suite(.serialized, MemorySecrets())
struct SettingsServiceTests {
    func service(_ text: String = "{}", platform: SettingsPlatform = .windows) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        // The plugins in the test's own folder: the user's are never read.
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        return (SettingsService(store: SettingsStore(configURL: url), platform: platform, library: library), url)
    }

    /// A change elsewhere (the command line, an editor), dated later than the file was: what the service must read again.
    func writeElsewhere(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
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
        do {
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

    /// As an engine makes it (no secret store of its own, keys looked up with `APIKeys.source`): a key set in the user's
    /// environment says where it is from, never itself, and isn't removed here; one saved goes to the platform's store
    /// (in memory here) and shows its last 4.
    @Test(MemorySecrets(environment: ["GEMINI_API_KEY": "gemini-env-key-0000-wxyz"]))
    func theEnginesConfiguration() async throws {
        let (service, _) = try service(#"{"provider": "gemini"}"#)
        var key = try #require(service.document().field("gemini.key"))
        #expect(key.isSet == true && key.status == KeyState.shell("GEMINI_API_KEY").text(missing: "") && key.actions == ["setKey"])
        let saved = await service.perform(SettingsAction(field: "gemini.key", name: "setKey", key: "gemini-saved-key-0000-a1b2"))
        #expect((try? saved.get()) != nil && APIKeys.keyEnding(account: "gemini") == "a1b2")
        key = try #require(service.document().field("gemini.key"))
        #expect(key.status?.hasSuffix("a1b2") == true && key.actions == ["setKey", "removeKey"])
        let text = String(decoding: try JSONEncoder().encode(service.document()), as: UTF8.self)
        #expect(!text.contains("gemini-env-key") && !text.contains("gemini-saved-key"))
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

    /// A change whose save fails is refused (`failed`), and the document shows the file as it is, with why; the next
    /// change of something else doesn't write it; and a change that saves nothing after it isn't refused for it. A rule
    /// that saves on its own (the style order) and fails is refused too.
    @Test func aSaveThatFails() throws {
        let (service, url) = try service(#"{"maxTokens": 1000}"#)
        let folder = url.deletingLastPathComponent()
        var result: Result<Void, SettingsProblem> = .success(())
        guard try whileReadOnly(folder, { result = service.set("maxTokens", to: .number(1500)) }) else { return }
        guard case let .failure(problem) = result else { Issue.record("a change not saved was taken"); return }
        var document = service.document()
        #expect(problem.code == .failed && problem.message == document.saveError)
        #expect(document.field("maxTokens")?.value == .number(1000))
        // Writable again: another change, saved alone.
        #expect((try? service.set("typeOut", to: .bool(true)).get()) != nil)
        let config = try Config.load(from: url)
        #expect(config.typeOut && config.maxTokens == 1000 && service.document().saveError == nil)
        // Failed; then a change to what it is: taken, nothing left to show.
        _ = try whileReadOnly(folder) { _ = service.set("maxTokens", to: .number(2000)) }
        #expect(service.document().saveError != nil)
        #expect((try? service.set("maxTokens", to: .number(1000)).get()) != nil)
        #expect(service.document().saveError == nil)
        // The style order saves itself.
        let styles = try #require(service.document().field("rewriteStyles")?.value)
        let reordered = AIConfig.JSONValue.array((styles.strings ?? []).reversed().map(AIConfig.JSONValue.string))
        _ = try whileReadOnly(folder) { result = service.set("rewriteStyles", to: reordered) }
        if case let .failure(problem) = result { #expect(problem.code == .failed) } else { Issue.record("a failed save was taken") }
        document = service.document()
        #expect(document.field("rewriteStyles")?.value == styles && document.saveError != nil)
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

    /// A list changed in the file meanwhile (the command line added a word): a change made on the document of an older
    /// `revision` is `stale`, and nothing changes; one made as an edit of the list `shown` is merged with the list as it
    /// is now (what was added elsewhere stays, what was deleted elsewhere stays deleted); one with neither replaces the
    /// list, as before.
    @Test func staleLists() throws {
        let (service, url) = try service(#"{"redaction": {"enabled": true, "customWords": ["Acme"]}, "outputLanguages": ["en", "zh"]}"#)
        func strings(_ values: String...) -> AIConfig.JSONValue { .array(values.map(AIConfig.JSONValue.string)) }
        func problem(_ id: String, _ value: AIConfig.JSONValue, revision: UInt64? = nil,
                     shown: AIConfig.JSONValue? = nil) -> SettingsProblem.Code? {
            if case let .failure(problem) = service.set(id, to: value, revision: revision, shown: shown) { return problem.code }
            return nil
        }
        func words() throws -> [String] { try Config.load(from: url).redaction.customWords }
        let revision = service.revision
        #expect(service.document().field("redaction.customWords")?.value == strings("Acme"))
        try writeElsewhere(#"{"redaction": {"enabled": true, "customWords": ["Acme", "AddedByCLI"]}, "outputLanguages": ["en", "zh", "fr"]}"#, to: url)
        // On the revision the window had: stale, and the file as it is.
        #expect(problem("redaction.customWords", strings("Acme", "Mine"), revision: revision) == .stale)
        #expect(try words() == ["Acme", "AddedByCLI"] && service.revision > revision)
        // As an edit of what it showed: merged.
        #expect(problem("redaction.customWords", strings("Acme", "Mine"), shown: strings("Acme")) == nil)
        #expect(try words() == ["Acme", "AddedByCLI", "Mine"])
        // On the revision now: taken.
        #expect(problem("redaction.customWords", strings("Acme", "AddedByCLI", "Mine", "Zeta"), revision: service.revision) == nil)
        #expect(try words() == ["Acme", "AddedByCLI", "Mine", "Zeta"])
        // Deleted elsewhere, still shown: stays deleted; taken out in the window: goes.
        try writeElsewhere(#"{"redaction": {"enabled": true, "customWords": ["Acme", "AddedByCLI", "Zeta"]}, "outputLanguages": ["en", "zh", "fr"]}"#, to: url)
        #expect(problem("redaction.customWords", strings("AddedByCLI", "Mine", "Zeta", "Omega"),
                        shown: strings("Acme", "AddedByCLI", "Mine", "Zeta")) == nil)
        #expect(try words() == ["AddedByCLI", "Zeta", "Omega"])
        // A list of choices: the window's order of what it showed; the language added elsewhere after the one before it.
        #expect(problem("outputLanguages", strings("zh", "en"), shown: strings("en", "zh")) == nil)
        #expect(try Config.load(from: url).outputLanguages.map(\.code) == ["zh", "fr", "en"])
        // Neither: the window's list, as it is (what a client of before sends).
        #expect(problem("redaction.customWords", strings("Mine")) == nil)
        #expect(try words() == ["Mine"])
        // `shown` is for lists only.
        #expect(problem("maxTokens", .number(1500), shown: strings("1000")) == .badValue)
    }

    /// A command's arguments aren't merged: their order is their meaning. Changed since the window showed them: stale.
    @Test func aCommandsArgumentsAreNotMerged() throws {
        let (service, url) = try service(#"{"agent": "custom", "agentCommand": ["muse", "--"]}"#)
        func strings(_ values: String...) -> AIConfig.JSONValue { .array(values.map(AIConfig.JSONValue.string)) }
        #expect(service.document().field("agentCommand")?.ordered == true)
        #expect((try? service.set("agentCommand", to: strings("muse", "-q", "--"), shown: strings("muse", "--")).get()) != nil)
        try writeElsewhere(#"{"agent": "custom", "agentCommand": ["muse", "--verbose", "--"]}"#, to: url)
        if case let .failure(problem) = service.set("agentCommand", to: strings("muse", "--"), shown: strings("muse", "-q", "--")) {
            #expect(problem.code == .stale)
        } else {
            Issue.record("a command changed elsewhere was merged")
        }
        #expect(try Config.load(from: url).agentCommand == ["muse", "--verbose", "--"])
    }

    /// A value the choices don't have (a language only the file names, a later version's style, a thinking level of the
    /// file's own) is shown as a choice of its own, `disabled`: the field can still be changed, and it is kept as it is,
    /// never dropped, nor picked once it is gone.
    @Test func valuesOutsideTheChoices() throws {
        let (service, url) = try service(#"""
            {"provider": "anthropic", "anthropic": {"effort": "max"},
             "outputLanguages": ["en", "nl", "zh"], "rewriteStyles": ["简洁", "STYLE_OF_LATER", "POLISH"]}
            """#)
        func problem(_ id: String, _ value: AIConfig.JSONValue) -> SettingsProblem.Code? {
            if case let .failure(problem) = service.set(id, to: value) { return problem.code }
            return nil
        }
        func strings(_ values: String...) -> AIConfig.JSONValue { .array(values.map(AIConfig.JSONValue.string)) }
        let document = service.document()
        let nl = try #require(document.field("outputLanguages")?.choices?.first { $0.value == .string("nl") })
        #expect(nl.disabled == true && nl.label == UIText.name(OutputLanguage("nl")))
        // Reordered with it: taken. Left out: kept where it was. One nobody has: refused.
        #expect(problem("outputLanguages", strings("zh", "nl", "en")) == nil)
        #expect(try Config.load(from: url).outputLanguages.map(\.code) == ["zh", "nl", "en"])
        #expect(problem("outputLanguages", strings("en", "zh")) == nil)
        #expect(try Config.load(from: url).outputLanguages.map(\.code) == ["en", "nl", "zh"])
        #expect(problem("outputLanguages", strings("en", "nl", "zh", "xx")) == .badValue)
        // A later version's style: on, in its place, disabled; kept through a reorder and when left out.
        let styles = try #require(document.field("rewriteStyles"))
        #expect(styles.value == strings("简洁", "STYLE_OF_LATER", "润色"))
        #expect(styles.choices?.first { $0.value == .string("STYLE_OF_LATER") }?.disabled == true)
        #expect(problem("rewriteStyles", strings("润色", "STYLE_OF_LATER", "简洁")) == nil)
        #expect(try Config.load(from: url).rewriteStyles == ["润色", "STYLE_OF_LATER", "简洁"])
        #expect(problem("rewriteStyles", strings("正式")) == nil)
        #expect(try Config.load(from: url).rewriteStyles == ["正式", "STYLE_OF_LATER"])
        // A single choice: sent back as it is, taken; another picked; then it is gone, and not to be picked again.
        let effort = try #require(document.field("anthropic.effort"))
        #expect(effort.value == .string("max") && effort.choices?.last == SettingsDocument.Choice(value: .string("max"), label: "max", disabled: true))
        #expect(problem("anthropic.effort", .string("max")) == nil)
        #expect(problem("anthropic.effort", .string("low")) == nil && problem("anthropic.effort", .string("max")) == .badValue)
        #expect(try Config.load(from: url).anthropic.effort == "low")
    }

    /// A file that can't be read: shown read-only, saying why, and left as it is.
    @Test func aBrokenFile() throws {
        let (service, url) = try service("{ nope")
        let before = service.revision
        let document = service.document()
        #expect(document.loadError != nil && document.field("typeOut")?.readOnly == true)
        if case let .failure(problem) = service.set("typeOut", to: .bool(true)) {
            #expect(problem.code == .configBroken)
        } else {
            Issue.record("a change was taken over a broken file")
        }
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == "{ nope")
        // Fixed elsewhere: read again, and the clients told (the document's error is gone).
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        service.checkForChanges()
        #expect(service.revision > before && service.document().loadError == nil)
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

    /// What a generic client needs to draw what isn't a plain field: the command editor (`schema`: a field for each
    /// key of a command's `value`, some only for some types), the path fields' open panels (`picker`), and the button
    /// that takes a text (`textActions`: the Notion link). A command made from the schema's keys is saved as given.
    @Test func whatAnEditorIsTold() async throws {
        let (service, url) = try service(#"{"notes": {"destination": "notion"}}"#)
        var document = service.document()
        let schema = try #require(document.field("commands.custom")?.schema)
        #expect(schema.map(\.id) == ["name", "type", "summary", "prompt", "text", "url", "argv", "stdin", "timeoutSeconds", "ascii", "programs"])
        let byID = Dictionary(uniqueKeysWithValues: schema.map { ($0.id, $0) })
        #expect(byID["type"]?.choices?.map(\.value) == ["prompt", "run", "terminal", "link", "snippet"].map(AIConfig.JSONValue.string))
        #expect(byID["type"]?.value == .string("prompt") && byID["name"]?.when == nil)
        #expect(byID["argv"]?.kind == .words && byID["argv"]?.ordered == true
                && byID["argv"]?.when == ["type": [.string("run"), .string("terminal")]])
        #expect(byID["prompt"]?.multiline == true && byID["timeoutSeconds"]?.kind == .number && byID["timeoutSeconds"]?.max == 120)
        // Every key the schema names is a key of a command's definition.
        let definition: [String: AIConfig.JSONValue] = [
            "name": .string("shout"), "type": .string("run"), "summary": .string("Shout it"),
            "argv": .array([.string("tr"), .string("a-z"), .string("A-Z")]), "stdin": .string("{input}"),
            "timeoutSeconds": .number(5), "ascii": .bool(true),
        ]
        #expect(Set(definition.keys).isSubset(of: Set(schema.map(\.id))))
        let saved = await service.perform(SettingsAction(field: "commands.custom", name: "save", value: .object(definition)))
        #expect((try? saved.get()) != nil)
        #expect(try Config.load(from: url).customCommands == [CustomCommand(name: "shout", type: .run, summary: "Shout it",
                                                                            argv: ["tr", "a-z", "A-Z"], stdin: "{input}",
                                                                            ascii: true, timeoutSeconds: 5)])
        document = service.document()
        #expect(document.field("commands.custom")?.items?.first?.value == .object(definition))
        // Pickers, and the button that takes a text.
        #expect(document.field("notes.folder")?.picker == .folder && document.field("jargonFile")?.picker == .file)
        let notion = try #require(document.field("notes.notion"))
        #expect(notion.textActions == ["test"] && notion.placeholder != nil)
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

/// A test with a secret store in memory and the login environment given (none by default), through `Platform.override`:
/// the user's keychain is never read (no password prompt, no key of the developer's in a document), nor their shell's
/// variables. Each test case its own store.
struct MemorySecrets: SuiteTrait, TestTrait, TestScoping {
    var environment: [String: String] = [:]

    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> MemorySecrets? {
        testCase == nil ? nil : self
    }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        var platform = Platform.current
        platform.secrets = .inMemory()
        platform.processes = LoginEnvironment(variables: environment)
        try await Platform.$override.withValue(platform) { try await function() }
    }
}

/// No programs, and `variables` as the user's login environment (where `APIKeys.source` finds a key set in the shell).
struct LoginEnvironment: ProcessLauncher {
    var variables: [String: String]
    var canLaunch: Bool { false }
    var environment: [String: String] { variables }
    var loginEnvironment: [String: String] { variables }
    func isRunnable(_ program: URL) -> Bool { false }
    func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess { throw ProcessLaunchError.unsupported }
}
