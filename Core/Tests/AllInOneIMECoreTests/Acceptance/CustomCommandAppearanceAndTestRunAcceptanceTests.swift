import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Contract for the existing custom-command editor, not a second settings page. Each fixture has its own config
/// and plugin directory; no test reads or writes the user's config, keychain, or input field.
@Suite(.serialized, MemorySecrets())
struct CustomCommandAppearanceAndTestRunAcceptanceTests {
    private func fixture(_ json: String = "{}") throws -> (SettingsService, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("command-icons-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")
        try Data(json.utf8).write(to: file)
        return (SettingsService(store: SettingsStore(configURL: file), platform: .mac,
                                library: PluginLibrary(directory: dir.appendingPathComponent("plugins"))), file)
    }

    private func definition(_ name: String, type: String = "run", icon: AIConfig.JSONValue? = nil,
                            color: AIConfig.JSONValue? = nil) -> AIConfig.JSONValue {
        var keys: [String: AIConfig.JSONValue] = ["name": .string(name), "type": .string(type)]
        if type == "prompt" { keys["prompt"] = .string("Rewrite the sample") }
        else { keys["argv"] = .array([.string("/usr/bin/tr"), .string("a-z"), .string("A-Z")]); keys["stdin"] = .string("{input}") }
        keys["icon"] = icon
        keys["color"] = color
        return .object(keys)
    }

    private func save(_ value: AIConfig.JSONValue, in service: SettingsService, editing name: String? = nil) async throws {
        try await service.perform(SettingsAction(field: "commands.custom", name: "save", item: name, value: value)).get()
    }

    @Test func macDocumentOffersTheIconAndNamedColorChoices() throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let list = try #require(service.document().field("commands.custom"))
        let icon = try #require(list.schema?.first { $0.id == "icon" })
        let color = try #require(list.schema?.first { $0.id == "color" })
        #expect(icon.kind == .text) // searchable symbol names and one typed emoji
        #expect(icon.optional == true)
        #expect(icon.choices?.first?.value == .null) // Default: omit the config key
        let symbols = Set(icon.choices?.compactMap(\.value.string) ?? [])
        #expect(Set(["terminal", "doc.text", "globe", "link", "bolt", "star", "envelope", "calendar",
                     "checklist", "magnifyingglass", "wand.and.stars", "text.bubble"]).isSubset(of: symbols))
        #expect(color.kind == .choice && color.optional == true)
        #expect(color.choices?.first?.value == .null)
        #expect(Set(color.choices?.compactMap(\.value.string) ?? []) ==
                Set(["red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown", "gray"]))
    }

    @Test func symbolEmojiAndDefaultRoundTripIntoConfigAndTheAtRow() async throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cases: [(String, String?, String?, IconToken.Glyph, IconToken.Color)] = [
            ("symbolic", "bolt", "purple", .symbol("bolt", fallback: .run), .purple),
            ("emojic", "🧮", "teal", .emoji("🧮", fallback: .run), .teal),
            ("plain", nil, nil, .builtin(.run), .brown),
        ]
        for (name, icon, color, _, _) in cases {
            try await save(definition(name, icon: icon.map(AIConfig.JSONValue.string),
                                      color: color.map(AIConfig.JSONValue.string)), in: service)
        }
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let entries = try #require(raw["customCommands"] as? [[String: Any]])
        for (name, icon, color, glyph, tint) in cases {
            let object = try #require(entries.first { $0["name"] as? String == name })
            #expect(object["icon"] as? String == icon)
            #expect(object["color"] as? String == color)
            if icon == nil { #expect(object["icon"] == nil && object["color"] == nil) }
            let item = try #require(service.document().field("commands.custom")?.items?.first { $0.id == name })
            #expect(item.value == definition(name, icon: icon.map(AIConfig.JSONValue.string),
                                             color: color.map(AIConfig.JSONValue.string)))
            let command = try #require(Config.load(from: file).customCommands.first { $0.name == name })
            let composer = Composer(engine: FakeEngine(), actionKey: .enter)
            composer.commands = Command.catalog([command])
            composer.setInputMode(.english)
            _ = composer.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
            for letter in name { _ = composer.handleKeyDown(k(String(letter))) }
            let row = try #require(PanelPresenter(config: Config.load(from: file), language: "en").model(for: composer)
                .rows.first { $0.text.contains(name) || $0.comment.contains(name) })
            #expect(row.icon?.glyph == glyph)
            #expect(row.icon?.color == tint)
        }
    }

    @Test func testRunUsesTheSampleAndShowsOutputWithoutAnInputField() async throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await save(definition("shout"), in: service)
        let list = try #require(service.document().field("commands.custom"))
        #expect(list.textActions?.contains("test") == true)
        #expect(list.items?.first { $0.id == "shout" }?.actions?.contains("test") == true)
        // The service owns only a settings store: no app client or insertion callback is supplied.
        let result = try await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "shout",
                                                              value: .string("a sample"))).get()
        #expect(result.message?.contains("A SAMPLE") == true)
        #expect(service.document().field("commands.custom")?.items?.first { $0.id == "shout" }?.detail?.contains("A SAMPLE") == true)
    }

    @Test func testRunIsAvailableForEveryExecutableCommandKind() async throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let definitions: [AIConfig.JSONValue] = [
            definition("shell"),
            .object(["name": .string("terminalcmd"), "type": .string("terminal"),
                     "argv": .array([.string("/bin/echo"), .string("{input}")])]),
            .object(["name": .string("webpage"), "type": .string("link"),
                     "url": .string("https://example.com/?q={input}")]),
            .object(["name": .string("insertion"), "type": .string("snippet"),
                     "text": .string("Hello, {input}")]),
            definition("rewrite", type: "prompt"),
        ]
        for definition in definitions { try await save(definition, in: service) }
        let items = try #require(service.document().field("commands.custom")?.items)
        for name in ["shell", "terminalcmd", "webpage", "insertion", "rewrite"] {
            #expect(items.first { $0.id == name }?.actions?.contains("test") == true, "\(name) can be tried in the editor")
        }
    }

    @Test func failedTestRunShowsTheProgramError() async throws {
        let (service, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await save(.object(["name": .string("broken"), "type": .string("run"),
                                "argv": .array([.string("/bin/sh"), .string("-c"), .string("echo sample-failure >&2; exit 7")])]), in: service)
        let result = await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "broken", value: .string("sample")))
        guard case let .failure(problem) = result else { Issue.record("failing program was reported as success"); return }
        #expect(problem.message.contains("sample-failure") || problem.message.contains("7"))
    }

    @Test func aiPromptRequiresConfirmationBeforeAnyProviderRequest() async throws {
        let (service, file) = try fixture(#"{"provider":"openai"}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await save(definition("polite", type: "prompt"), in: service)
        let requests = Locked<[String]>(initialState: [])
        // Assumed injectable seam: the production path uses its provider; this closure records requests in tests.
        service.commandTestAI = { (_: CustomCommand, sample: String) async throws -> String in
            requests.withLock { $0.append(sample) }
            return "polite answer"
        }
        let unconfirmed = await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "polite",
                                                               value: .string("private sample")))
        #expect(requests.withLock { $0 }.isEmpty)
        guard case let .failure(problem) = unconfirmed else { Issue.record("AI test ran without confirmation"); return }
        #expect(problem.message.contains("This sends the sample to") && problem.message.contains("OpenAI"))
        let confirmed = try await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "polite",
                                                                 value: .object(["sample": .string("private sample"),
                                                                                 "confirmed": .bool(true)]))).get()
        #expect(confirmed.message?.contains("polite answer") == true)
        #expect(requests.withLock { $0 } == ["private sample"])
    }
}
