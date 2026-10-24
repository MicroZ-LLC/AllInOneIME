import Foundation
import Testing
@testable import AllInOneIMECore

/// A custom command in config.json that can't be read, a field with a value of the wrong kind (spec Suggestions v1,
/// decision 25), in each type: refused alone with its reason, the rest of the file loaded; it never runs; its JSON is kept
/// and written back; its name is taken; Settings → Custom Commands says why and deletes it.
@Suite(.serialized, MemorySecrets())
struct RefusedCustomCommandTests {
    typealias Reason = CustomCommand.Refused.Reason

    /// A config.json of its own (in a temporary folder) with `commands` (JSON, an entry each) as its custom commands.
    static func file(_ commands: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("refused-commands-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        let text = #"{ "uiLanguage": "en", "maxTokens": 1234, "customCommands": [ "# + commands.joined(separator: ", ") + " ] }"
        try Data(text.utf8).write(to: url)
        return url
    }

    static func json(_ text: String) throws -> AIConfig.JSONValue {
        try JSONDecoder().decode(AIConfig.JSONValue.self, from: Data(text.utf8))
    }

    /// The custom commands in the file at `url`, as it has them.
    static func entries(_ url: URL) throws -> [AIConfig.JSONValue] {
        guard case let .object(file) = try JSONDecoder().decode(AIConfig.JSONValue.self, from: Data(contentsOf: url)),
              case let .array(commands)? = file["customCommands"] else { return [] }
        return commands
    }

    /// One command of each type that is fine.
    static let good = [
        #"{"name": "polite", "type": "prompt", "prompt": "Make it polite"}"#,
        #"{"name": "py", "type": "run", "argv": ["python3", "-c", "{input}"], "timeoutSeconds": 5}"#,
        #"{"name": "top", "type": "terminal", "argv": ["top"]}"#,
        #"{"name": "google", "type": "link", "url": "https://www.google.com/search?q={input}"}"#,
        #"{"name": "sig", "type": "snippet", "text": "Best,\nWei"}"#,
        #"{"name": "jira", "type": "suggestions", "prefix": "JIRA-", "argv": ["/bin/echo"], "minChars": 1}"#,
    ]
    static let goodNames = ["polite", "py", "top", "google", "sig", "jira"]

    // MARK: - Refused alone

    /// In each type, a field with a value of the wrong kind (one of its own, and one any type has): that command is
    /// refused with its reason, the others (one of each type) and the rest of the file load, and it never runs.
    @Test(arguments: [
        (#"{"name": "bad", "type": "prompt", "prompt": 5}"#, Reason.wrongKind(field: "prompt", .text)),
        (#"{"name": "bad", "type": "prompt", "prompt": "x", "ascii": "yes"}"#, .wrongKind(field: "ascii", .trueOrFalse)),
        (#"{"name": "bad", "type": "run", "argv": "ls"}"#, .wrongKind(field: "argv", .list)),
        (#"{"name": "bad", "type": "run", "argv": ["ls", 5]}"#, .wrongKind(field: "argv[1]", .text)),
        (#"{"name": "bad", "type": "run", "argv": ["cat"], "stdin": ["x"]}"#, .wrongKind(field: "stdin", .text)),
        (#"{"name": "bad", "type": "run", "argv": ["ls"], "timeoutSeconds": "10"}"#, .wrongKind(field: "timeoutSeconds", .number)),
        (#"{"name": "bad", "type": "terminal", "argv": [1]}"#, .wrongKind(field: "argv[0]", .text)),
        (#"{"name": "bad", "type": "terminal", "argv": ["top"], "icon": 3, "color": "blue"}"#, .wrongKind(field: "icon", .text)),
        (#"{"name": "bad", "type": "link", "url": {"href": "https://example.com"}}"#, .wrongKind(field: "url", .text)),
        (#"{"name": "bad", "type": "link", "url": "https://example.com/?q={input}", "color": false}"#, .wrongKind(field: "color", .text)),
        (#"{"name": "bad", "type": "snippet", "text": true}"#, .wrongKind(field: "text", .text)),
        (#"{"name": "bad", "type": "snippet", "text": "x", "summary": ["a"]}"#, .wrongKind(field: "summary", .text)),
        (#"{"name": "bad", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "minChars": "two"}"#,
         .wrongKind(field: "minChars", .wholeNumber)),
        (#"{"name": "bad", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "queryMinChars": 2.5}"#,
         .wrongKind(field: "queryMinChars", .wholeNumber)),
        (#"{"name": "bad", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "query": "yes"}"#,
         .wrongKind(field: "query", .trueOrFalse)),
        (#"{"name": "bad", "type": "suggestions", "prefix": 5, "argv": ["/bin/echo"]}"#, .wrongKind(field: "prefix", .text)),
        (#"{"name": "bad", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "compare": "prefix", "refresh": 60}"#,
         .wrongKind(field: "refresh", .text)),
    ])
    func aValueOfTheWrongKindIsRefusedAlone(entry: String, reason: Reason) throws {
        let config = try Config.load(from: Self.file(Self.good + [entry]))
        #expect(config.uiLanguage == "en" && config.maxTokens == 1234)
        #expect(config.customCommands.map(\.name) == Self.goodNames && config.customCommands.allSatisfy(\.isValid))
        let refused = try #require(config.refusedCustomCommands.first)
        #expect(config.refusedCustomCommands.count == 1 && refused.name == "bad" && refused.reason == reason, "\(refused.reason)")
        #expect(refused.json == (try Self.json(entry)))
        #expect(config.unreadCustomCommands.isEmpty)
        // Never run: not among the commands typed after @, nor a suggestion source.
        #expect(!Command.catalog(config.customCommands).contains { $0.name == "bad" })
        #expect(!config.customCommands.contains { $0.name == "bad" })
    }

    /// No name or type (or null), a type or name that isn't text, not an object: refused alone too. A later version's
    /// type with a name is still kept as one, not refused.
    @Test func withoutANameOrATypeOrNotAnObject() throws {
        let cases: [(String, Reason)] = [
            (#"{"type": "run", "argv": ["ls"]}"#, .missing(field: "name")),
            (#"{"name": null, "type": "prompt", "prompt": "x"}"#, .missing(field: "name")),
            (#"{"name": "x", "prompt": "x"}"#, .missing(field: "type")),
            (#"{"name": "x", "type": 7}"#, .wrongKind(field: "type", .text)),
            (#"{"name": 5, "type": "hologram"}"#, .wrongKind(field: "name", .text)),
            (#"{"type": "hologram"}"#, .missing(field: "name")),
            (#""just text""#, .unreadable),
            ("[1, 2]", .unreadable),
        ]
        for (entry, reason) in cases {
            let config = try Config.load(from: Self.file(Self.good + [entry]))
            #expect(config.customCommands.map(\.name) == Self.goodNames, "\(entry)")
            #expect(config.refusedCustomCommands.map(\.reason) == [reason], "\(entry)")
            #expect(config.refusedCustomCommands.map(\.json) == [try Self.json(entry)], "\(entry)")
        }
        let later = try Config.load(from: Self.file([#"{"name": "beam", "type": "hologram", "power": "max"}"#]))
        #expect(later.refusedCustomCommands.isEmpty && later.unreadCustomCommandNames == ["beam"])
    }

    /// Every field a command writes has the kind of value it takes (`Refused.fields`), and only `insert` (any JSON) is
    /// left out: a field added to `CustomCommand` without its kind is caught here.
    @Test func everyFieldOfACommandHasItsKind() throws {
        let full = CustomCommand(name: "a", type: .suggestions, summary: "", prompt: "", argv: [""], stdin: "", ascii: true,
                                 timeoutSeconds: 1.5, icon: "", color: "", url: "", text: "", prefix: "", minChars: 1, compare: "",
                                 refresh: "", query: true, queryMinChars: 1, insert: .object([:]))
        guard case let .object(fields) = try JSONDecoder().decode(AIConfig.JSONValue.self, from: JSONEncoder().encode(full)) else {
            Issue.record("a command isn't written as an object")
            return
        }
        #expect(Set(fields.keys) == Set(CustomCommand.Refused.fields.map(\.name) + ["insert"]))
        for (name, kind) in CustomCommand.Refused.fields {
            #expect(fields[name].map(kind.fits) == true, "\(name)")
        }
    }

    // MARK: - Kept

    /// Rewriting the config never loses it: as Settings saves (`SettingsStore`, a command added: the list written again)
    /// or written whole, its JSON is in the file as it was (a field this version doesn't know too), after the others; it
    /// reads back refused.
    @Test func itsJSONIsWrittenBackAsItWas() throws {
        let entry = #"{"name": "wrong", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "minChars": "two", "later": {"x": [1, true]}}"#
        let json = try Self.json(entry)
        let url = try Self.file([Self.good[0], entry, Self.good[1]])
        let store = SettingsStore(configURL: url)
        #expect(store.saveCommand(CustomCommand(name: "terse", type: .prompt, prompt: "Shorter"), editing: nil))
        #expect(try Self.entries(url).last == json)
        let saved = try Config.load(from: url)
        #expect(saved.customCommands.map(\.name) == ["polite", "py", "terse"])
        #expect(saved.refusedCustomCommands.map(\.json) == [json] && saved.maxTokens == 1234)

        // A later version's entry stays last.
        let later = #"{"name": "beam", "type": "hologram"}"#
        try Data(#"{"customCommands": [\#(later), \#(entry), \#(Self.good[4])]}"#.utf8).write(to: url)
        let config = try Config.load(from: url)
        try config.write(to: url)
        #expect(try Self.entries(url) == [Self.json(Self.good[4]), json, Self.json(later)])
        let read = try Config.load(from: url)
        #expect(read.customCommands == config.customCommands && read.refusedCustomCommands == config.refusedCustomCommands)
        #expect(read.unreadCustomCommands == config.unreadCustomCommands)
    }

    /// Its name is taken, as a later version's command's is: no command saved in Settings may have it, and a built-in's
    /// name given up (`freeBuiltinNames`) doesn't become it.
    @Test func itsNameIsTaken() throws {
        let config = try Config.load(from: Self.file([#"{"name": "jira", "type": "suggestions", "prefix": "J-", "argv": ["x"], "minChars": "two"}"#]))
        #expect(config.unreadCustomCommandNames == ["jira"])
        let mine = CustomCommand(name: "Jira", type: .prompt, prompt: "Hi")
        #expect(mine.problem(among: config.customCommands, unread: config.unreadCustomCommandNames) == .nameTaken)

        var renaming = try Config.load(from: Self.file([#"{"name": "reply", "type": "prompt", "prompt": "x"}"#,
                                                         #"{"name": "myreply", "type": "prompt", "prompt": 5}"#]))
        #expect(renaming.freeBuiltinNames(taken: []).map(\.new) == ["myownreply"])
    }

    // MARK: - Settings

    /// Settings → Custom Commands (the settings document, Windows' and the Mac's) lists it after the others, by its name,
    /// with why it isn't used, and only Delete; Delete takes it out of the file, nothing else.
    @Test func settingsSayWhyAndDeleteIt() async throws {
        let url = try Self.file([Self.good[0], #"{"name": "wrong", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "minChars": "two"}"#,
                                 #""just text""#])
        let library = PluginLibrary(directory: url.deletingLastPathComponent().appendingPathComponent("plugins", isDirectory: true))
        for platform in [SettingsPlatform.windows, .mac] {
            let service = SettingsService(store: SettingsStore(configURL: url), platform: platform, library: library)
            let items = try await withInterfaceLanguage("en") { try #require(service.document().field("commands.custom")?.items) }
            #expect(items.map(\.id) == ["polite", "refused:0", "refused:1"])
            #expect(items.dropFirst().map(\.title) == ["@wrong", "@?"])
            #expect(items.dropFirst().allSatisfy { $0.actions == ["delete"] && $0.value == nil })
            #expect(items[1].detail == "This command isn't used: “minChars” should be a whole number")
            #expect(items[2].detail == "This command isn't used: it can't be read as a command")
        }

        let service = SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library)
        let deleted = await service.perform(SettingsAction(field: "commands.custom", name: "delete", item: "refused:0"))
        #expect((try? deleted.get()) != nil)
        var config = try Config.load(from: url)
        #expect(config.customCommands.map(\.name) == ["polite"] && config.refusedCustomCommands.map(\.reason) == [.unreadable])
        #expect(config.maxTokens == 1234)
        // One that isn't there (deleted meanwhile): nothing deleted.
        let again = await service.perform(SettingsAction(field: "commands.custom", name: "delete", item: "refused:1"))
        #expect((try? again.get()) == nil)
        config = try Config.load(from: url)
        #expect(config.customCommands.map(\.name) == ["polite"] && config.refusedCustomCommands.count == 1)
    }

    /// What Settings says, for each kind of value and the other reasons, in English and Simplified Chinese.
    @Test func theReasonsAsSettingsSaysThem() async {
        // The JSON is the test's own.
        func said(_ entry: String) -> String { UIText.describe(CustomCommand.Refused(try! Self.json(entry))) }
        await withInterfaceLanguage("en") {
            #expect(said(#"{"name": "a", "type": "run", "argv": "ls"}"#) == "This command isn't used: “argv” should be a list, [ … ]")
            #expect(said(#"{"name": "a", "type": "run", "argv": ["ls"], "timeoutSeconds": "9"}"#)
                    == "This command isn't used: “timeoutSeconds” should be a number")
            #expect(said(#"{"name": "a", "type": "run", "argv": ["ls"], "ascii": 1}"#)
                    == "This command isn't used: “ascii” should be true or false")
            #expect(said(#"{"name": "a", "type": "prompt", "prompt": 1}"#) == "This command isn't used: “prompt” should be text")
            #expect(said(#"{"type": "prompt", "prompt": "x"}"#) == "This command isn't used: “name” is missing")
            #expect(said("3") == "This command isn't used: it can't be read as a command")
        }
        await withInterfaceLanguage("zh") {
            #expect(said(#"{"name": "a", "type": "suggestions", "prefix": "W-", "argv": ["x"], "minChars": "two"}"#)
                    == "这个命令没有用上：「minChars」应该是整数")
            #expect(said(#"{"name": "a"}"#) == "这个命令没有用上：缺少「type」")
        }
    }
}
