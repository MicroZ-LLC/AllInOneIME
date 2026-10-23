import Foundation
import Testing
@testable import AllInOneIMECore

/// A custom command of type `suggestions` on its own (spec Suggestions v1, decision 24): read as a completion source by
/// a plugin entry's rules, refused with their reasons, its insert presets, its program's arguments, what its program may
/// print. The session's side, with real programs: CommandSuggestionsSessionTests.
struct CommandSuggestionsTests {
    static func jira(_ adjust: (inout CustomCommand) -> Void = { _ in }) -> CustomCommand {
        var command = CustomCommand(name: "Jira", type: .suggestions, summary: "Jira issues", argv: ["/usr/local/bin/jira-list"],
                                    prefix: "JIRA-")
        adjust(&command)
        return command
    }

    // MARK: - The source

    /// What it leaves out is what a plugin's entry leaves out: from 1 character after the prefix, compared by its start,
    /// refreshed every hour, no query (3 characters when it has one), `{arg}` inserted; its list always on, its name in
    /// small letters, its summary the title.
    @Test func aSuggestionsCommandIsASourceWithThePluginsDefaults() throws {
        let source = try #require(try Self.jira().suggestionSource?.get())
        #expect(source == CompletionSource(name: "jira", title: LocalizedText(en: "Jira issues"), prefix: "JIRA-", minChars: 1,
                                           compare: .prefix, list: true, refresh: 3600, query: false, queryMinChars: 3,
                                           insert: .standard))
        let declared = try #require(try Self.jira {
            $0.minChars = 2
            $0.compare = "exact"
            $0.refresh = "15m"
            $0.query = true
            $0.queryMinChars = 1
            $0.summary = nil
            $0.insert = CustomCommand.InsertPreset.title.insert
        }.suggestionSource?.get())
        #expect(declared.minChars == 2 && declared.compare == .exact && declared.refresh == 900 && declared.query
                && declared.queryMinChars == 1)
        #expect(declared.title.en == "jira", "no summary: its name")
        #expect(declared.insert == CompletionInsert(default: .templates(["{arg} {title}", "{arg}"])))
        #expect(CustomCommand(name: "x", type: .run, argv: ["echo"]).suggestionSource == nil, "only the suggestions type")
        // Full-width forms are typed as ASCII (`＃` is `#`).
        #expect(try Self.jira { $0.prefix = "＃" }.suggestionSource?.get().prefix == "#")
    }

    /// A value out of a plugin entry's range is refused with that entry's own reason (the rules are the same), and
    /// what a custom command adds: a prefix, and a list that loads within 20 s.
    @Test func whatBreaksTheRulesIsRefusedWithThePluginsReasons() throws {
        func reason(_ adjust: (inout CustomCommand) -> Void) -> String? {
            if case let .failure(refusal)? = Self.jira(adjust).suggestionSource { return refusal.reason }
            return nil
        }
        /// The reason a plugin's entry with `key` set so is refused with.
        func pluginReason(_ key: String, _ value: AIConfig.JSONValue) -> String? {
            var fields: [String: AIConfig.JSONValue] = ["name": .string("jira"), "title": .string("Jira"), "prefix": .string("JIRA-"),
                                                        "list": .bool(true)]
            fields[key] = value
            if case let .failure(refusal) = CompletionDeclaration.source(.object(fields)) { return refusal.reason }
            return nil
        }
        let cases: [(String, AIConfig.JSONValue, (inout CustomCommand) -> Void)] = [
            ("refresh", .string("1m"), { $0.refresh = "1m" }),
            ("refresh", .string("8d"), { $0.refresh = "8d" }),
            ("compare", .string("fuzzy"), { $0.compare = "fuzzy" }),
            ("minChars", .number(33), { $0.minChars = 33 }),
            ("queryMinChars", .number(0), { $0.queryMinChars = 0 }),
            ("insert", .object(["default": .string("{arg")]), { $0.insert = .object(["default": .string("{arg")]) }),
            ("prefix", .string("@j"), { $0.prefix = "@j" }),
            ("prefix", .string("JIRA "), { $0.prefix = "JIRA " }),
        ]
        for (key, value, adjust) in cases {
            let refused = reason(adjust)
            #expect(refused != nil && refused == pluginReason(key, value), "\(key) \(value): \(refused ?? "used")")
        }
        #expect(reason { $0.prefix = nil }?.contains("prefix") == true, "a prefix is required")
        #expect(reason { $0.prefix = " " }?.contains("prefix") == true)
        #expect(reason { $0.timeoutSeconds = 21 }?.contains("20") == true, "a list loads within 20 s")
        #expect(reason { $0.timeoutSeconds = 20 } == nil)
    }

    /// The editors' problems: the prefix (none, not one, the magic key at its start), the timeout, a template, then the
    /// rest of the rules; a refused command isn't offered (`isValid`).
    @Test func theEditorsSayWhatKeepsItFromBeingSaved() {
        #expect(Self.jira().problem(among: []) == nil && Self.jira().isValid)
        #expect(Self.jira { $0.argv = [] }.problem(among: []) == .emptyCommand)
        #expect(Self.jira { $0.prefix = nil }.problem(among: []) == .badPrefix)
        #expect(Self.jira { $0.prefix = "JIRA 1" }.problem(among: []) == .badPrefix)
        #expect(Self.jira { $0.prefix = "#" }.problem(among: [], trigger: "#") == .prefixIsMagicKey("#"))
        #expect(Self.jira { $0.prefix = "#" }.problem(among: [], trigger: "~") == nil)
        #expect(Self.jira { $0.timeoutSeconds = 30 }.problem(among: []) == .timeoutTooLong)
        #expect(Self.jira { $0.insert = .object(["chat": .string("{url")]) }.problem(among: []) == .badTemplate)
        let refresh = Self.jira { $0.refresh = "2m" }
        if case .suggestions? = refresh.problem(among: []) {} else { Issue.record("\(String(describing: refresh.problem(among: [])))") }
        #expect(!refresh.isValid)
        #expect(Self.jira().problem(among: [CustomCommand(name: "jira", type: .prompt, prompt: "x")]) == .nameTaken)
    }

    // MARK: - Insert presets

    @Test func theInsertPresetsAreTemplatesHoweverWritten() {
        #expect(CustomCommand.InsertPreset.match.insert == nil)
        for preset in CustomCommand.InsertPreset.allCases {
            #expect(CustomCommand.InsertPreset(preset.insert) == preset, "\(preset)")
        }
        #expect(CustomCommand.InsertPreset(.object(["default": .string("{arg}"), "terminal": .string("{match}")])) == .match)
        #expect(CustomCommand.InsertPreset(.object(["default": .array([.string("{arg} {title}"), .string("{arg}")]),
                                                    "chat": .array([.string("{arg} {title}"), .string("{arg}")])])) == .title)
        #expect(CustomCommand.InsertPreset(.object(["default": .string("{match} ({title})")])) == nil, "the user's own")
        #expect(CustomCommand.InsertPreset(.object(["default": .string("{arg")])) == nil)
    }

    // MARK: - The program's arguments

    /// The list runs with no input; a query's text is one argument, where `{input}` is written, else the last; the
    /// program as it is.
    @Test func theQueryIsOneArgumentInPlaceOfInputOrLast() {
        let plain = CustomCommand(name: "j", type: .suggestions, argv: ["jira-list", "--project", "WEB"], prefix: "J-")
        #expect(plain.suggestionArguments(query: nil) == ["jira-list", "--project", "WEB"])
        #expect(plain.suggestionArguments(query: "12; rm -rf /") == ["jira-list", "--project", "WEB", "12; rm -rf /"])
        let placed = CustomCommand(name: "j", type: .suggestions, argv: ["jira-list", "{input}", "--json", "--q={input}"], prefix: "J-")
        #expect(placed.suggestionArguments(query: nil) == ["jira-list", "--json", "--q="])
        #expect(placed.suggestionArguments(query: "a b") == ["jira-list", "a b", "--json", "--q=a b"])
        #expect(CustomCommand(name: "j", type: .suggestions, prefix: "J-").suggestionArguments(query: "1") == [])
        #expect(plain.queryTimeout == 3 && CustomCommand(name: "j", type: .suggestions, timeoutSeconds: 2).queryTimeout == 2)
    }

    // MARK: - What the program prints

    /// Lines "match<TAB>title<TAB>url": the match is the item's (its arg too), the title its title and `{title}`, the url
    /// its `{url}`; title and url may be left out; a bad line is dropped on its own, blank lines skipped, a match kept
    /// once; control and bidi characters taken out first.
    @Test func linesAreMatchTitleAndURL() throws {
        let printed = "JIRA-12\tFix login\thttps://jira.example.com/browse/JIRA-12\n"
            + "\n"
            + "JIRA-13\tSlow search\n"
            + "JIRA 14\tnot a match\n"
            + "JIRA-15\n"
            + "jira-12\tagain\n"
            + "JIRA-16\u{202E}\tRight\u{200B}-to-left\textra\tcolumns\n"
        let list = try CompletionOutput.readProgram(Data(printed.utf8)).get()
        #expect(list.items.map(\.match) == ["JIRA-12", "JIRA-13", "JIRA-15", "JIRA-16"], "\(list.items)")
        #expect(list.items[0] == CompletionItem(match: "JIRA-12", title: "Fix login",
                                                variables: ["title": "Fix login", "url": "https://jira.example.com/browse/JIRA-12"]))
        #expect(list.items[1].variables == ["title": "Slow search"] && list.items[2].title == nil && list.items[2].variables == nil)
        #expect(list.items[3].title == "Right-to-left" && list.items[3].variables?["url"] == "extra")
        #expect(try CompletionOutput.readProgram(Data()).get().items.isEmpty, "nothing printed: no items")
    }

    /// JSON first: the plugins' `{"items": [Item]}`, read as theirs (its title also its `{title}`); JSON that isn't an
    /// object with items is a failure, as a plugin's; the same limits.
    @Test func jsonIsThePluginsItems() throws {
        let json = #"""
              {"items": [{"match": "JIRA-1", "title": "One", "variables": {"url": "https://x.example/1"}},
                         {"match": "JIRA-2", "title": "Two", "variables": {"title": "Kept"}}, {"match": "bad match"}]}
            """#
        let list = try CompletionOutput.readProgram(Data(json.utf8)).get()
        #expect(list.items.map(\.match) == ["JIRA-1", "JIRA-2"])
        #expect(list.items[0].variables == ["url": "https://x.example/1", "title": "One"] && list.items[1].variables == ["title": "Kept"])
        #expect(CompletionOutput.readProgram(Data(#"{"rows": []}"#.utf8)) == .failure(.notAList))
        #expect(CompletionOutput.readProgram(Data(" {".utf8)) == .failure(.notAList))
        let many = (0...CompletionList.maxItems).map { "J-\($0)" }.joined(separator: "\n")
        #expect(CompletionOutput.readProgram(Data(many.utf8)) == .failure(.tooManyItems(CompletionList.maxItems + 1)))
        let large = Data(repeating: UInt8(ascii: "x"), count: CompletionList.maxBytes + 1)
        #expect(CompletionOutput.readProgram(large) == .failure(.tooLarge(bytes: large.count)))
        #expect(!CompletionOutput.Failure.notAList.programMessage.contains("plugin"))
    }

    // MARK: - In the config

    /// decision 24's command, as config.json has it: read, a source, written back as it was; the commands of other types
    /// are written as before (none of the new keys).
    @Test func theConfigKeepsItAsWritten() throws {
        let json = #"""
            { "name": "jira", "type": "suggestions", "summary": "Jira issues",
              "prefix": "JIRA-", "minChars": 1, "compare": "prefix",
              "argv": ["/Users/me/bin/jira-list"], "timeoutSeconds": 10, "refresh": "1h",
              "query": false, "queryMinChars": 3,
              "insert": { "default": ["{arg} {title}", "{arg}"], "chat": ["{arg} {title} {url}", "{arg}"], "terminal": "{match}" } }
            """#
        let command = try JSONDecoder().decode(CustomCommand.self, from: Data(json.utf8))
        #expect(command.type == .suggestions && command.prefix == "JIRA-" && command.refresh == "1h" && command.query == false)
        let source = try #require(try command.suggestionSource?.get())
        #expect(source.insert.chat == .templates(["{arg} {title} {url}", "{arg}"]))
        let again = try JSONDecoder().decode(CustomCommand.self, from: JSONEncoder().encode(command))
        #expect(again == command)
        let run = String(decoding: try JSONEncoder().encode(CustomCommand(name: "py", type: .run, argv: ["python3"])), as: UTF8.self)
        #expect(!run.contains("prefix") && !run.contains("insert") && !run.contains("query"), "\(run)")
        var config = Config.default
        config.customCommands = [command, CustomCommand(name: "py", type: .run, argv: ["python3"])]
        #expect(config.suggestionsSettings().commands == [command])
        #expect(config.suggestionsSettings().sourceKeys == [CompletionSourceKey(command: "jira")])
    }

    /// Its source is kept under a name no plugin can have, and its cached list's file is known as its own (pruned with
    /// the plugins').
    @Test func itsKeyIsNoPlugins() {
        let key = CompletionSourceKey(command: "Jira")
        #expect(key == CompletionSourceKey(plugin: "custom-commands", source: "jira") && key.isCustomCommand)
        #expect(!PluginLibrary.isValidName(key.plugin))
        #expect(CompletionSourceKey(fileName: key.fileName) == key)
        #expect(CompletionSourceKey(fileName: "github.issues.json") == CompletionSourceKey(plugin: "github", source: "issues"))
        #expect(CompletionSourceKey(fileName: "custom-command.jira.json") == nil)
    }

    /// What Settings says under it (the Mac's editor and command list, the settings document): how its source is doing,
    /// or why nothing of it shows.
    @Test func settingsSayHowItIsDoing() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            let now = Date()
            let jira = Self.jira()
            let fresh = jira.suggestionsState(config, status: nil, now: now)
            #expect(fresh?.text.hasPrefix("Not loaded yet") == true && fresh?.problem == false, "\(String(describing: fresh))")
            var status = CompletionSourceStatus(plugin: CompletionSourceKey.customCommands, source: "jira", items: 12,
                                                refreshed: now.addingTimeInterval(-120), error: nil, paused: false)
            let loaded = jira.suggestionsState(config, status: status, now: now)
            #expect(loaded?.text.contains("12 items") == true && loaded?.problem == false, "\(String(describing: loaded))")
            status.error = "jira: not logged in"
            let failed = jira.suggestionsState(config, status: status, now: now)
            #expect(failed?.text.contains("Last error: jira: not logged in") == true && failed?.problem == true)
            config.suggestions = false
            #expect(jira.suggestionsState(config, status: status, now: now)?.text.hasPrefix("Suggestions are off") == true)
            config.suggestions = nil
            config.commandTrigger = "#"
            let shadowed = Self.jira { $0.prefix = "#J" }.suggestionsState(config, status: nil, now: now)
            #expect(shadowed?.problem == true && shadowed?.text.contains("magic key") == true, "\(String(describing: shadowed))")
            let refused = Self.jira { $0.refresh = "1m" }.suggestionsState(config, status: nil, now: now)
            #expect(refused?.problem == true && refused?.text.hasPrefix("Can't be a suggestion source: ") == true)
            #expect(Self.jira { $0.prefix = "JIRA 1" }.suggestionsState(config, status: nil, now: now)?.text.hasPrefix("The prefix must be") == true)
            #expect(CustomCommand(name: "py", type: .run, argv: ["python3"]).suggestionsState(config, status: nil) == nil)
        }
    }

    /// In the command list it is a source: no program run from there, an icon of its own, what it is said.
    @Test func inTheCommandListItIsASource() {
        let catalog = Command.catalog([Self.jira()])
        let command = catalog.first { $0.name == "jira" }
        #expect(command?.kind == .suggestions && command?.needsChildProcess == true)
        #expect(command.map { !Composer.usesSelection($0) } == true)
        #expect(Command.catalog([Self.jira { $0.refresh = "1m" }]).contains { $0.name == "jira" } == false, "refused: not offered")
    }
}
