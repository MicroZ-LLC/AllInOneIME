import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, decision 24: a custom command of type "suggestions" (config.json's custom commands) as a suggestion
/// source. Written from the spec by the tests' author, not from the implementation: each command is read from config
/// JSON as the spec writes it, its program is a real sh script in a temporary folder of the test's own (the fixtures below
/// are written there), and everything is observed through a text field's `InputSession` as a shell drives it (the rig:
/// SuggestionsAcceptanceTests.swift). What it shares with plugin sources (spec 1–6) is checked as it applies to a
/// command: the rows, the keys per app class, what goes in, frecency, the cache on disk, the back-off and the pause, the
/// switches.
///
/// Decision 24, bullet by bullet:
/// - the config's shape, what is refused and why, the rest still loading: `theSpecsCommandIsReadFromConfigJSON`,
///   `refusedCommandsSayWhyAndTheRestOfTheConfigLoads`, `refusedCommandsNeverRun`, `aValueOfTheWrongKindIsRefusedAlone`
/// - the program run as a `run` command's, its list with no input, its query with the token after the prefix:
///   `linesAreMatchTitleAndURL` (the list), `aProgramWithoutASlashIsFoundOnThePath`,
///   `aQuerySendsTheTextAfterThePrefixAsOneArgument`, `shellCharactersInTheQueryAreTextNeverRun`,
///   `nothingElseOfTheFieldReachesTheProgram`
/// - its output, lines or the plugins' JSON: `linesAreMatchTitleAndURL`, `jsonIsThePluginsItems`
/// - the rows as plugin rows: `theInsertChoicesPerClassOfApp`, `onlyWhatWasntTypedGoesIn`, `rowsPickedOftenAndLateComeFirst`,
///   `theKeysAreAPluginSourcesInEachClassOfApp`
/// - no approval, on while it exists, the switches: `noApprovalAndOnWhileItExists`, `theMasterSwitchOffMeansItNeverRuns`,
///   `anAppsSuggestionsOffMeansNoRowsThere`, `aPrefixStartingWithTheMagicKeyIsNeverUsed`
/// - failures, back-off, pause and resume: `aFailedRunKeepsTheOldListAndBacksOff`, `theFifthFailureInARowPausesUntilAnEdit`
/// - the command itself: `typingTheCommandOnlySaysWhatItIs`
/// - the cache on disk: `itsListIsCachedForTheUserOnlyAndGoesWithTheCommand`
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsCustomCommandsAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// How long a test waits for what a real program prints (started while a whole test run keeps the Mac busy).
    static let wait: TimeInterval = 15

    // MARK: - The user's program

    /// The user's own program: an sh script in a temporary folder the test makes (and removes), which notes each call's
    /// arguments (`calls`), then does what its body says (`body.sh` in the folder, which a test may change: the user
    /// fixing or breaking it). The fixtures it prints are files the test writes next to it.
    final class UserProgram: @unchecked Sendable {
        let folder: URL
        let script: URL

        init(_ body: String, name: String = "jira-list") throws {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("custom-suggestions-acceptance-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            script = folder.appendingPathComponent(name)
            try writeScript(at: script)
            try setBody(body)
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        /// The script at `url`: each call one line in calls.log (how many arguments, each after a unit separator), written
        /// at once (a list and a query may run side by side); then the body, sourced (it has "$@" and `$dir`).
        func writeScript(at url: URL) throws {
            let text = """
                #!/bin/sh
                dir='\(folder.path)'
                line="$#"; for a in "$@"; do line="$line$(printf '\\037')$a"; done
                printf '%s\\n' "$line" >> "$dir/calls.log"
                . "$dir/body.sh"

                """
            try Data(text.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        /// What it does from now on.
        func setBody(_ body: String) throws {
            try Data((body + "\n").utf8).write(to: folder.appendingPathComponent("body.sh"), options: .atomic)
        }

        /// A file next to it (what it prints).
        func write(_ name: String, _ text: String) throws {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
        }

        func path(_ name: String) -> String { folder.appendingPathComponent(name).path }

        /// The calls so far, each its arguments (the program's name left out).
        var calls: [[String]] {
            let text = (try? String(contentsOf: folder.appendingPathComponent("calls.log"), encoding: .utf8)) ?? ""
            return text.split(separator: "\n").map { line in
                Array(line.split(separator: "\u{1F}", omittingEmptySubsequences: false).dropFirst().map(String.init))
            }
        }

        /// The files of the folder whose names start with `prefix` (what a body wrote per call).
        func files(startingWith prefix: String) -> [URL] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { $0.hasPrefix(prefix) }.sorted().map { folder.appendingPathComponent($0) }
        }
    }

    // MARK: - Fixtures

    /// What the user's program prints as lines, "match<TAB>title<TAB>url": good lines, lines that aren't one (a space or a
    /// semicolon in the match, no match, a match over 64 characters: each dropped alone), a blank line, a zero-width
    /// space in a match and a bidi control in a title (taken out first).
    static let listLines = [
        "JIRA-4011\tFix login\thttps://jira.example.com/browse/JIRA-4011",
        "JIRA-4012\tSlow search\thttps://jira.example.com/browse/JIRA-4012",
        "JIRA 4013\tA space in the match",
        "\tNo match at all",
        "JIRA-4014;rm\tA semicolon in the match",
        "JIRA-4077-and-a-match-far-too-long-for-a-row-of-sixty-four-characters\tToo long",
        "JIRA-433\tDark mode",
        "",
        "JIRA-\u{200B}58",
        "JIRA-5913\tCrash\u{202E} on start\thttps://jira.example.com/browse/JIRA-5913",
    ].joined(separator: "\n") + "\n"

    /// The matches a row may show, longest first where one starts another.
    static let matches = ["JIRA-4011", "JIRA-4012", "JIRA-4013", "JIRA-4014", "JIRA-433", "JIRA-58", "JIRA-5913", "JIRA-4099",
                          "JIRA-1239"]

    /// The plugins' JSON (`{"items": [Item]}`): an item with `arg`, `subtitle` and a `{url}` variable, bad items (a
    /// space in the match, none, not an object) dropped one by one; their order is their rank.
    static let listJSON = #"""
        {"items": [
          {"match": "JIRA-4011", "title": "Fix login", "subtitle": "In progress", "arg": "JIRA-4011 (login)",
           "variables": {"url": "https://jira.example.com/browse/JIRA-4011"}},
          {"match": "JIRA 4012", "title": "A space in the match"},
          {"title": "No match at all"},
          "not an item",
          {"match": "JIRA-433", "title": "Dark mode"}
        ]}
        """#

    /// The program's body that prints the lines written as list.tsv.
    static let printsTheList = #"cat "$dir/list.tsv""#

    /// The spec's command (decision 24) as config.json has it, its program `program`, with `fields` set over the spec's
    /// (JSON values, written as they are: `"query": "true"` puts in `true`) and those in `without` left out.
    static func jiraJSON(_ program: UserProgram?, _ fields: [String: String] = [:], without: Set<String> = []) -> String {
        var all: [(String, String)] = [
            ("name", #""jira""#), ("type", #""suggestions""#), ("summary", #""Jira issues""#),
            ("prefix", #""JIRA-""#), ("minChars", "1"), ("compare", #""prefix""#),
            ("argv", program.map { "[" + quoted($0.script.path) + "]" } ?? #"["/Users/me/bin/jira-list"]"#),
            ("timeoutSeconds", "10"), ("refresh", #""1h""#),
            ("query", "false"), ("queryMinChars", "3"),
            ("insert", #"{ "default": ["{arg} {title}", "{arg}"], "chat": ["{arg} {title} {url}", "{arg}"], "terminal": "{match}" }"#),
        ]
        for (key, value) in fields where !all.contains(where: { $0.0 == key }) { all.append((key, value)) }
        all = all.map { key, value in (key, fields[key] ?? value) }.filter { !without.contains($0.0) }
        return "{ " + all.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", ") + " }"
    }

    /// A custom command read from config JSON, as config.json's `customCommands` has it.
    static func command(_ json: String) throws -> CustomCommand {
        try JSONDecoder().decode(CustomCommand.self, from: Data(json.utf8))
    }

    /// The spec's command with `fields` over its own (`jiraJSON`).
    static func jira(_ program: UserProgram, _ fields: [String: String] = [:], without: Set<String> = []) throws -> CustomCommand {
        try command(jiraJSON(program, fields, without: without))
    }

    /// `text` as a JSON string.
    static func quoted(_ text: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes]), as: UTF8.self)
            .dropFirst().dropLast().description
    }

    /// A world whose config has `commands` as its custom commands, and the switches as the settings make them
    /// (`Config.suggestionsSettings`): no source of a plugin, nothing approved.
    static func world(_ commands: CustomCommand...) -> SuggestionsWorld {
        let world = SuggestionsWorld()
        world.config.customCommands = commands
        world.switches = world.config.suggestionsSettings()
        return world
    }

    /// The commands changed as Settings changes them: in the config, in the switches, the session told.
    static func setCommands(_ commands: [CustomCommand], in world: SuggestionsWorld, field: SuggestionsField) {
        world.config.customCommands = commands
        world.switches.commands = world.config.suggestionsSettings().commands
        field.host.send(.configChanged)
    }

    static let key = CompletionSourceKey(command: "jira")

    /// What went into the field since output `from`: the texts the session committed or replaced.
    static func inserted(_ field: SuggestionsField, since from: Int) -> [String] {
        field.host.outputs.dropFirst(from).compactMap { output -> String? in
            switch output {
            case let .commit(text), let .commitAfterKey(text), let .typeOut(text): return text
            case let .replace(text, _): return text
            default: return nil
            }
        }
    }

    // MARK: - The config

    /// The spec's command, as config.json writes it, is a source with what it says: its prefix, from 1 character after
    /// it, compared by its start, its list refreshed every hour, no query (3 characters when it has one), its program
    /// stopped after 10 s, its templates per class of app; its summary is its title. What it leaves out is what a plugin's
    /// entry leaves out (docs/plugins.md: minChars 1, compare prefix, refresh 1h, query false, queryMinChars 3,
    /// insert `{arg}`); its timeout a `run` command's (10 s).
    @Test func theSpecsCommandIsReadFromConfigJSON() throws {
        let command = try Self.command(Self.jiraJSON(nil))
        #expect(command.type == .suggestions && command.name == "jira" && command.argv == ["/Users/me/bin/jira-list"])
        let source = try #require(try command.suggestionSource?.get(), "\(String(describing: command.suggestionSource))")
        #expect(source.prefix == "JIRA-" && source.minChars == 1 && source.compare == .prefix && source.list
                && source.refresh == 3600 && !source.query && source.queryMinChars == 3, "\(source)")
        #expect(source.title.en == "Jira issues", "\(source.title)")
        #expect(source.insert == CompletionInsert(default: .templates(["{arg} {title}", "{arg}"]),
                                                  chat: .templates(["{arg} {title} {url}", "{arg}"]),
                                                  terminal: .templates(["{match}"])), "\(source.insert)")
        #expect(command.timeout == 10)

        let bare = try Self.command(#"{ "name": "jira", "type": "suggestions", "prefix": "JIRA-", "argv": ["jira-list"] }"#)
        let defaults = try #require(try bare.suggestionSource?.get(), "\(String(describing: bare.suggestionSource))")
        #expect(defaults.minChars == 1 && defaults.compare == .prefix && defaults.refresh == 3600 && !defaults.query
                && defaults.queryMinChars == 3 && defaults.insert == .standard, "\(defaults)")
        #expect(bare.timeout == CustomCommand.defaultTimeout)

        let queried = try Self.command(Self.jiraJSON(nil, ["query": "true", "queryMinChars": "2", "refresh": #""15m""#,
                                                            "minChars": "2", "compare": #""exact""#]))
        let read = try #require(try queried.suggestionSource?.get())
        #expect(read.query && read.queryMinChars == 2 && read.refresh == 900 && read.minChars == 2 && read.compare == .exact, "\(read)")
    }

    /// Each command a rule refuses (no prefix, the magic key as its prefix, a template that isn't one, `timeoutSeconds`
    /// over 20, a value out of a plugin entry's range) is refused on its own, with its own reason, which Settings shows
    /// under it; the rest of config.json still loads (the other commands, the settings), and the good source is one.
    @Test func refusedCommandsSayWhyAndTheRestOfTheConfigLoads() async throws {
        try await inEnglish {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-suggestions-config-\(UUID().uuidString)",
                                                                                     isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("config.json")
            let json = """
                { "uiLanguage": "en", "commandTrigger": "#", "suggestions": true,
                  "customCommands": [
                    \(Self.jiraJSON(nil)),
                    { "name": "noprefix", "type": "suggestions", "summary": "No prefix", "argv": ["/bin/echo"] },
                    { "name": "magic", "type": "suggestions", "summary": "The magic key", "prefix": "#J", "argv": ["/bin/echo"] },
                    { "name": "template", "type": "suggestions", "prefix": "TPL-", "argv": ["/bin/echo"],
                      "insert": { "default": "{arg", "chat": "{arg} {url}" } },
                    { "name": "slow", "type": "suggestions", "prefix": "SLOW-", "argv": ["/bin/echo"], "timeoutSeconds": 21 },
                    { "name": "often", "type": "suggestions", "prefix": "OFT-", "argv": ["/bin/echo"], "refresh": "1m" },
                    { "name": "python", "type": "run", "summary": "Python", "argv": ["python3", "-c", "{input}"] }
                  ] }
                """
            try Data(json.utf8).write(to: file)
            let config = try Config.load(from: file)
            #expect(config.commandTrigger == "#" && config.uiLanguage == "en" && config.suggestions == true)
            #expect(config.customCommands.map(\.name) == ["jira", "noprefix", "magic", "template", "slow", "often", "python"],
                    "every command kept: \(config.customCommands.map(\.name))")
            let named = Dictionary(config.customCommands.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            #expect(named["python"]?.type == .run && named["python"]?.isValid == true, "the run command loads")

            let jira = try #require(named["jira"])
            let source = try #require(try jira.suggestionSource?.get())
            #expect(source.inactiveReason(config) == nil)
            #expect(jira.suggestionsState(config, status: nil)?.problem == false)

            /// Why `name` isn't used, as the rules have it (a refusal, or the source inactive with the config).
            func reason(_ name: String) -> String? {
                guard let command = named[name] else { return nil }
                switch command.suggestionSource {
                case let .failure(refusal)?: return refusal.reason
                case let .success(source)?: return source.inactiveReason(config)
                case nil: return nil
                }
            }
            let refused = ["noprefix", "magic", "template", "slow", "often"]
            var reasons: [String] = []
            for name in refused {
                let why = reason(name)
                #expect(why?.isEmpty == false, "\(name): refused with a reason (\(why ?? "used"))")
                reasons.append(why ?? "")
                let shown = named[name]?.suggestionsState(config, status: nil)
                #expect(shown?.problem == true && shown?.text.isEmpty == false,
                        "\(name): Settings says why it isn't used (\(String(describing: shown)))")
            }
            #expect(Set(reasons).count == refused.count, "each its own reason: \(reasons)")
            #expect(reason("noprefix")?.localizedCaseInsensitiveContains("prefix") == true, "\(reason("noprefix") ?? "")")
            #expect(reason("slow")?.contains("20") == true, "\(reason("slow") ?? "")")
            #expect(reason("template")?.localizedCaseInsensitiveContains("insert") == true
                    || reason("template")?.localizedCaseInsensitiveContains("template") == true, "\(reason("template") ?? "")")
            #expect(reason("often")?.localizedCaseInsensitiveContains("refresh") == true, "\(reason("often") ?? "")")

            // 20 s is still within the limit.
            let twenty = try Self.command(Self.jiraJSON(nil, ["timeoutSeconds": "20"]))
            #expect((try? twenty.suggestionSource?.get()) != nil, "timeoutSeconds 20: used")
        }
    }

    /// The commands refused never run and show no rows; the good one next to them does.
    @Test func refusedCommandsNeverRun() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines + "TPL-1\tTemplate\nSLOW-1\tSlow\nOFT-1\tOften\n#J1\tMagic\n1234\tNo prefix\n")
            let path = Self.quoted(program.script.path)
            let commands = try [
                Self.jira(program, ["argv": "[\(path), \"--from=jira\"]"]),
                Self.command(#"{ "name": "noprefix", "type": "suggestions", "argv": [\#(path), "--from=noprefix"], "compare": "exact" }"#),
                Self.command(##"{ "name": "magic", "type": "suggestions", "prefix": "#J", "argv": [\##(path), "--from=magic"] }"##),
                Self.command(#"{ "name": "template", "type": "suggestions", "prefix": "TPL-", "argv": [\#(path), "--from=template"], "insert": { "default": "{arg" } }"#),
                Self.command(#"{ "name": "slow", "type": "suggestions", "prefix": "SLOW-", "argv": [\#(path), "--from=slow"], "timeoutSeconds": 21 }"#),
                Self.command(#"{ "name": "often", "type": "suggestions", "prefix": "OFT-", "argv": [\#(path), "--from=often"], "refresh": "1m" }"#),
            ]
            let world = SuggestionsWorld()
            world.config.commandTrigger = "#"
            defer { UIText.commandTrigger = "@" }  // the process's, which the session sets
            world.config.customCommands = commands
            world.switches = world.config.suggestionsSettings()
            let field = world.field()
            field.type("JIRA-4")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012", "JIRA-433"] },
                    "the good one: \(field.rows.map(\.text))")
            for typed in [" TPL-1", " SLOW-1", " OFT-1", " 1234"] {
                field.type(typed)
                field.idle(0.3)
                #expect(field.rows.isEmpty, "\(typed): \(field.rows.map(\.text))")
            }
            field.idle(0.5)
            #expect(program.calls.allSatisfy { $0 == ["--from=jira"] } && !program.calls.isEmpty,
                    "only the good one ran: \(program.calls)")
        }
    }

    /// A key of the wrong kind (`"minChars": "two"`) breaks a rule as an out-of-range one does (decision 24: the same
    /// limits as a plugin entry's, which spec 6.9 refuses alone): that command isn't a source, and the rest of config.json
    /// still loads.
    @Test func aValueOfTheWrongKindIsRefusedAlone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-suggestions-config-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.json")
        let json = """
            { "uiLanguage": "en",
              "customCommands": [
                \(Self.jiraJSON(nil)),
                { "name": "wrong", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "minChars": "two" },
                { "name": "python", "type": "run", "argv": ["python3", "-c", "{input}"] }
              ] }
            """
        try Data(json.utf8).write(to: file)
        let config = try #require(try? Config.load(from: file), "config.json with one wrong value still loads")
        #expect(config.uiLanguage == "en")
        #expect(config.customCommands.contains { $0.name == "jira" } && config.customCommands.contains { $0.name == "python" },
                "\(config.customCommands.map(\.name))")
        if let wrong = config.customCommands.first(where: { $0.name == "wrong" }) {
            #expect((try? wrong.suggestionSource?.get()) == nil, "not a source")
        }
    }

    // MARK: - The list

    /// The list is the program run with no input (no argument), once, its rows what it printed as lines: each its match
    /// and its title, a line that isn't one dropped alone; `{title}` and `{url}` are the line's title and url, a line
    /// without them fine (the templates tried in turn); hidden characters taken out of what shows and goes in. No
    /// approval asked.
    @Test func linesAreMatchTitleAndURL() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program, ["insert": #"{ "default": ["{arg} ({title}) <{url}>", "{arg} ({title})", "{arg}"] }"#]))
            #expect(world.switches.enabled.isEmpty)
            let field = world.field()
            field.type("JIRA-4")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012", "JIRA-433"] },
                    "in the order printed, bad lines dropped: \(field.rows.map { $0.text + " · " + $0.comment })")
            for (row, title) in zip(field.rows, ["Fix login", "Slow search", "Dark mode"]) {
                #expect((row.text + " " + row.comment).contains(title), "the row shows its title: \(row.text) · \(row.comment)")
            }
            #expect(field.footer.contains("Jira issues"), "its summary is the source's title: \(field.footer)")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "JIRA-4011 (Fix login) <https://jira.example.com/browse/JIRA-4011>", "\(field.document)")

            let expected = [("JIRA-43", "JIRA-433 (Dark mode)"), ("JIRA-5", "JIRA-58"),
                            ("JIRA-59", "JIRA-5913 (Crash on start) <https://jira.example.com/browse/JIRA-5913>")]
            for (typed, inserted) in expected {
                let other = world.field()
                other.type(typed)
                #expect(other.settle(timeout: Self.wait) { !other.rows.isEmpty }, "\(typed)")
                if typed == "JIRA-5" {
                    #expect(other.shown(Self.matches) == ["JIRA-58", "JIRA-5913"], "the zero-width space taken out: \(other.rows.map(\.text))")
                }
                if typed == "JIRA-59" {
                    #expect(other.rows.allSatisfy { !($0.text + $0.comment).contains("\u{202E}") }, "no bidi control shown")
                }
                #expect(other.press(SuggestionKeys.tab))
                #expect(other.document == inserted, "\(typed): \(other.document)")
            }
            #expect(program.calls == [[]], "its list: run once, with no input (\(program.calls))")
        }
    }

    /// Its output may be the plugins' JSON (`{"items": [Item]}`): an item's `arg` is what `{arg}` inserts, its `variables`
    /// fill the templates (`{url}`), its title shows; bad items are dropped one by one.
    @Test func jsonIsThePluginsItems() async throws {
        try await inEnglish {
            let program = try UserProgram(#"cat "$dir/list.json""#)
            try program.write("list.json", Self.listJSON)
            let world = Self.world(try Self.jira(program, ["insert": #"{ "default": "{arg}", "chat": ["{arg} {url}", "{arg}"] }"#]))
            let field = world.field()
            field.type("JIRA-4")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-433"] },
                    "\(field.rows.map { $0.text + " · " + $0.comment })")
            #expect(field.rows.first.map { ($0.text + " " + $0.comment).contains("Fix login") } == true)
            field.type("0")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011"] })
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "JIRA-4011 (login)", "its arg: \(field.document)")

            let chat = world.field(app: SuggestionsApps.slack)
            chat.type("JIRA-40")
            #expect(chat.settle(timeout: Self.wait) { chat.shown(Self.matches) == ["JIRA-4011"] })
            #expect(chat.press(SuggestionKeys.tab))
            #expect(chat.document == "JIRA-4011 (login) https://jira.example.com/browse/JIRA-4011", "\(chat.document)")
            let noURL = world.field(app: SuggestionsApps.slack)
            noURL.type("JIRA-43")
            #expect(noURL.settle(timeout: Self.wait) { noURL.shown(Self.matches) == ["JIRA-433"] })
            #expect(noURL.press(SuggestionKeys.tab))
            #expect(noURL.document == "JIRA-433", "no url: the next template (\(noURL.document))")
        }
    }

    /// A program without "/" is looked up on the PATH, as a `run` command's is; one found nowhere is the source's error
    /// (as on a Mac the command synced to without the program), no rows.
    @Test func aProgramWithoutASlashIsFoundOnThePath() async throws {
        try await inEnglish {
            let name = "jira-list-\(UUID().uuidString.prefix(8).lowercased())"
            let program = try UserProgram(Self.printsTheList, name: name)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program, ["argv": "[\(Self.quoted(name))]"]))
            let path = ["PATH": program.folder.path + ":/usr/bin:/bin"]
            let field = world.field { $0.suggestions.commandRuntime = CommandCompletionRunner(environment: path) }
            field.type("JIRA-4")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012", "JIRA-433"] },
                    "found on the PATH: \(field.rows.map(\.text))")

            let elsewhere = Self.world(try Self.jira(program, ["argv": #"["jira-list-not-on-this-mac"]"#]))
            let missing = elsewhere.field { $0.suggestions.commandRuntime = CommandCompletionRunner(environment: path) }
            missing.type("JIRA-4")
            #expect(missing.settle(timeout: Self.wait) { elsewhere.lastStatus?.error?.isEmpty == false },
                    "not found: its error (\(String(describing: elsewhere.lastStatus)))")
            #expect(missing.rows.isEmpty)
        }
    }

    // MARK: - The query

    enum ArgvStyle: String, CaseIterable, Sendable {
        /// `{input}` written in argv: the text goes there.
        case placed
        /// No `{input}`: the text is the last argument.
        case appended
    }

    /// With `query`, the program also runs with the text after the prefix as one argument, in place of `{input}` where
    /// argv writes it, else appended; not before `queryMinChars` characters; its answer shows. The list runs with no
    /// input (nothing typed in its arguments, no `{input}` left in them).
    @Test(arguments: ArgvStyle.allCases)
    func aQuerySendsTheTextAfterThePrefixAsOneArgument(_ style: ArgvStyle) async throws {
        try await inEnglish {
            // The list, then for each argument that isn't a flag a row found by the query.
            let program = try UserProgram(#"""
                cat "$dir/list.tsv"
                for a in "$@"; do case "$a" in --*) ;; *) printf 'JIRA-%s9\tFound by query\n' "$a" ;; esac; done
                """#)
            try program.write("list.tsv", Self.listLines)
            let path = Self.quoted(program.script.path)
            let argv = style == .placed ? "[\(path), \"--search\", \"{input}\", \"--json\"]" : "[\(path), \"--json\"]"
            let world = Self.world(try Self.jira(program, ["argv": argv, "query": "true", "queryMinChars": "3"]))
            let field = world.field()
            field.type("JIRA-12")
            field.idle(0.8)
            #expect(program.calls.allSatisfy { !$0.contains("1") && !$0.contains("12") }, "under 3 characters: no query (\(program.calls))")
            field.type("3")
            let expected = style == .placed ? ["--search", "123", "--json"] : ["--json", "123"]
            #expect(field.settle(timeout: Self.wait) { program.calls.contains(expected) }, "\(style): \(program.calls)")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches).contains("JIRA-1239") }, "its answer: \(field.rows.map(\.text))")
            let lists = program.calls.filter { $0 != expected }
            #expect(!lists.isEmpty && lists.allSatisfy { call in !call.contains { $0.contains("123") || $0.contains("{input}") } },
                    "the list: no input (\(lists))")
        }
    }

    /// The query's text is one argument as it is: `;`, `$( )`, backquotes, `&&` and `#` are text, nothing runs in a
    /// shell, in `{input}` alone or inside a longer argument. In a field, such characters end the token: only what is
    /// typed after the prefix up to them goes, never what follows.
    @Test func shellCharactersInTheQueryAreTextNeverRun() async throws {
        let program = try UserProgram(Self.printsTheList)
        try program.write("list.tsv", Self.listLines)
        let pwned = (1...4).map { program.path("pwned-\($0)") }
        let texts = ["12; touch \(pwned[0])", "$(touch \(pwned[1]))", "`touch \(pwned[2])`", "12 && touch \(pwned[3]) # x",
                     "$(id)", "a#b"]
        let path = Self.quoted(program.script.path)
        let runner = CommandCompletionRunner()
        for argv in ["[\(path)]", "[\(path), \"--q={input}\"]"] {
            let command = try Self.jira(program, ["argv": argv, "query": "true"])
            for text in texts {
                _ = try await runner.query(text, command)
                let expected = argv.contains("{input}") ? ["--q=" + text] : [text]
                #expect(program.calls.last == expected, "\(text): \(String(describing: program.calls.last))")
            }
        }
        for file in pwned { #expect(!FileManager.default.fileExists(atPath: file), "nothing ran: \(file)") }

        try await inEnglish {
            let world = Self.world(try Self.jira(program, ["query": "true", "queryMinChars": "2"]))
            let field = world.field()
            field.type("JIRA-12")
            #expect(field.settle(timeout: Self.wait) { program.calls.contains(["12"]) }, "\(program.calls)")
            field.type("; touch x")
            field.idle(0.5)
            field.type(" JIRA-34")
            #expect(field.settle(timeout: Self.wait) { program.calls.contains(["34"]) }, "\(program.calls)")
            field.type("$(id)")
            field.idle(0.5)
            field.type(" JIRA-a#b.c@d")
            #expect(field.settle(timeout: Self.wait) { program.calls.contains(["a#b.c@d"]) }, "\(program.calls)")
            field.idle(0.5)
            let queries = program.calls.suffix(from: 2 * texts.count).filter { !$0.isEmpty }
            // A query as the token grows ("a#" first, from `queryMinChars`), never what follows it.
            #expect(queries.allSatisfy { $0.count == 1 && (["12", "34"].contains($0[0]) || "a#b.c@d".hasPrefix($0[0])) },
                    "the token after the prefix only: \(queries)")
        }
    }

    /// Nothing of the field but the token after the prefix reaches the program: not the text before it (in its arguments,
    /// on its standard input, in its environment), nothing on standard input at all.
    @Test func nothingElseOfTheFieldReachesTheProgram() async throws {
        try await inEnglish {
            let program = try UserProgram(#"""
                cat > "$dir/stdin.$$"
                env > "$dir/env.$$"
                cat "$dir/list.tsv"
                """#)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program, ["query": "true", "queryMinChars": "4"]))
            let field = world.field()
            field.type("zebrafish ")
            field.type("JIRA-q7zx")
            #expect(field.settle(timeout: Self.wait) { program.calls.contains(["q7zx"]) }, "\(program.calls)")
            field.idle(0.5)
            #expect(Set(program.calls).isSubset(of: [[], ["q7zx"]]), "\(program.calls)")
            let inputs = program.files(startingWith: "stdin.")
            #expect(inputs.count == program.calls.count, "\(inputs.map(\.lastPathComponent))")
            for file in inputs {
                #expect((try? Data(contentsOf: file))?.isEmpty == true, "nothing on standard input: \(file.lastPathComponent)")
            }
            let environments = program.files(startingWith: "env.")
            #expect(!environments.isEmpty)
            for file in environments {
                let environment = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                #expect(!environment.contains("zebrafish") && !environment.contains("q7zx"),
                        "not in its environment: \(file.lastPathComponent)")
            }
        }
    }

    // MARK: - The rows

    enum Insert: String, CaseIterable, Sendable {
        /// "Just the match".
        case match
        /// "With its title".
        case title
        /// "With title and link": the link in chat apps, as the spec's own example has it.
        case titleAndLink
    }

    /// The editor's three choices of what goes in, per class of app: just the match; with its title; with its title, and
    /// in chat apps its link (decision 24's example). A row without title or url: the match alone. A terminal gets the
    /// match only, whatever the choice.
    @Test(arguments: Insert.allCases)
    func theInsertChoicesPerClassOfApp(_ choice: Insert) async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            var command = try Self.jira(program, without: ["insert"])
            command.insert = CustomCommand.InsertPreset(rawValue: choice.rawValue)?.insert
            #expect(CustomCommand.InsertPreset(rawValue: choice.rawValue) != nil)
            let world = Self.world(command)
            let link = "https://jira.example.com/browse/JIRA-5913"
            let expected: [(app: String, terminal: Bool, inserted: String)] = [
                (SuggestionsApps.editor, false, choice == .match ? "JIRA-5913" : "JIRA-5913 Crash on start"),
                (SuggestionsApps.slack, false, choice == .match ? "JIRA-5913"
                    : choice == .title ? "JIRA-5913 Crash on start" : "JIRA-5913 Crash on start \(link)"),
                ("com.apple.Terminal", true, "JIRA-5913"),
            ]
            for (app, terminal, inserted) in expected {
                let field = world.field(app: app, terminal: terminal)
                field.type("JIRA-59")
                #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-5913"] }, "\(app): \(field.rows.map(\.text))")
                #expect(field.press(SuggestionKeys.tab), "\(app)")
                #expect(field.document == inserted, "\(choice) in \(app): \(field.document)")
            }
            for app in [SuggestionsApps.editor, SuggestionsApps.slack] {
                let field = Self.world(command).field(app: app)  // a world of its own: no row picked before
                field.type("JIRA-5")
                #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-58", "JIRA-5913"] }, "\(app)")
                #expect(field.press(SuggestionKeys.tab))
                #expect(field.document == "JIRA-58", "\(choice) in \(app), no title, no url: \(field.document)")
            }
        }
    }

    /// Only what wasn't typed goes in, the typed part kept as typed (its case too): "jira-59" and the row JIRA-5913 with
    /// its title put in "13 Crash on start".
    @Test func onlyWhatWasntTypedGoesIn() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program))
            let field = world.field()
            field.type("jira-59")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-5913"] }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(Self.inserted(field, since: before) == ["13 Crash on start"], "\(Self.inserted(field, since: before))")
            #expect(field.document == "jira-5913 Crash on start", "\(field.document)")
        }
    }

    /// Rows picked before come first, by how often and how recently each was picked (frecency, decision 18), then the
    /// program's order; a pick is kept as the source's (the command's) and the row's match.
    @Test func rowsPickedOftenAndLateComeFirst() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program, without: ["insert"]))
            let order = ["JIRA-4011", "JIRA-4012", "JIRA-433"]

            /// A new field: "JIRA-4" typed, its rows `rows`, the row at `index` picked (↓ and Return; nil: none).
            func pick(_ index: Int?, expecting rows: [String], _ comment: String) {
                let field = world.field()
                field.type("JIRA-4")
                #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == rows }, "\(comment): \(field.rows.map(\.text))")
                guard let index, field.shown(Self.matches) == rows else { return }
                #expect(field.pick(at: index))
                #expect(field.document == rows[index], "\(field.document)")
            }
            pick(2, expecting: order, "nothing picked: the program's order")
            pick(2, expecting: ["JIRA-433", "JIRA-4011", "JIRA-4012"], "JIRA-433 picked")
            pick(1, expecting: ["JIRA-4012", "JIRA-433", "JIRA-4011"], "each picked once: the later first")
            pick(nil, expecting: ["JIRA-433", "JIRA-4012", "JIRA-4011"], "JIRA-433 twice, and last")
            #expect(world.recordedPicks.map(\.match) == ["JIRA-433", "JIRA-4012", "JIRA-433"], "\(world.recordedPicks)")
            #expect(world.recordedPicks.allSatisfy { $0.plugin == Self.key.plugin && $0.source == Self.key.source },
                    "\(world.recordedPicks)")
        }
    }

    enum AppClass: String, CaseIterable, Sendable {
        case ordinary, chat, terminal, noRows
    }

    /// The keys while its rows show are a plugin source's, per class of app (spec 1.4, 6.10–6.12): in ordinary apps Tab
    /// inserts the first row, ↓ moves the highlight and Return then inserts it, Return before it moved is the app's, Esc
    /// hides the rows; in chat apps Tab inserts the first row, the arrows, Return and Esc are the app's; in terminals Tab
    /// completes the rows' common part only, then is the terminal's, the other keys the terminal's; remote desktops: no
    /// rows.
    @Test(arguments: AppClass.allCases)
    func theKeysAreAPluginSourcesInEachClassOfApp(_ kind: AppClass) async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let command = try Self.jira(program, without: ["insert"])
            let all = ["JIRA-4011", "JIRA-4012", "JIRA-433"]

            /// A new field of the class, in a world of its own (no row picked before), `typed` typed and its rows shown.
            func typed(_ text: String = "JIRA-4", rows: [String] = all) -> SuggestionsField {
                let world = Self.world(command)
                let field: SuggestionsField
                switch kind {
                case .ordinary: field = world.field()
                case .chat: field = world.field(app: SuggestionsApps.slack)
                case .terminal: field = world.field(app: "com.apple.Terminal", terminal: true)
                case .noRows: field = world.field(app: SuggestionsApps.remoteDesktop)
                }
                field.type(text)
                if kind != .noRows {
                    #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == rows }, "\(kind): \(field.rows.map(\.text))")
                }
                return field
            }

            switch kind {
            case .ordinary:
                let tab = typed()
                #expect(tab.press(SuggestionKeys.tab))
                #expect(tab.document == "JIRA-4011" && tab.rows.isEmpty, "\(tab.document)")
                let early = typed()
                #expect(!early.press(SuggestionKeys.enter), "Return before ↓: the app's")
                #expect(early.document == "JIRA-4", "\(early.document)")
                let moved = typed()
                #expect(moved.press(SuggestionKeys.down) && moved.press(SuggestionKeys.down) && moved.press(SuggestionKeys.up))
                #expect(moved.host.panel?.highlighted == 1, "\(String(describing: moved.host.panel?.highlighted))")
                #expect(moved.press(SuggestionKeys.enter))
                #expect(moved.document == "JIRA-4012", "\(moved.document)")
                let escaped = typed()
                #expect(escaped.press(SuggestionKeys.escape))
                #expect(escaped.rows.isEmpty && escaped.document == "JIRA-4")
                #expect(!escaped.press(SuggestionKeys.tab), "hidden: the app's Tab")
            case .chat:
                let tab = typed()
                #expect(tab.press(SuggestionKeys.tab))
                #expect(tab.document == "JIRA-4011", "\(tab.document)")
                for key in [SuggestionKeys.down, SuggestionKeys.up, SuggestionKeys.enter, SuggestionKeys.escape] {
                    let field = typed()
                    #expect(!field.press(key), "\(key.characters.debugDescription) is the chat app's")
                    #expect(field.document == "JIRA-4", "nothing inserted: \(field.document)")
                }
            case .terminal:
                let field = typed("JIRA-40", rows: ["JIRA-4011", "JIRA-4012"])
                #expect(field.press(SuggestionKeys.tab))
                #expect(field.document == "JIRA-401", "the rows' common part: \(field.document)")
                #expect(!field.press(SuggestionKeys.tab), "nothing more in common: the terminal's Tab")
                for key in [SuggestionKeys.down, SuggestionKeys.enter, SuggestionKeys.escape] {
                    let other = typed()
                    #expect(!other.press(key), "\(key.characters.debugDescription) is the terminal's")
                    #expect(other.document == "JIRA-4", "\(other.document)")
                }
            case .noRows:
                let field = typed()
                field.idle(0.5)
                #expect(field.rows.isEmpty, "\(field.rows.map(\.text))")
                #expect(!field.press(SuggestionKeys.tab) && field.document == "JIRA-4")
            }
        }
    }

    // MARK: - Switches

    /// No approval: a command of type suggestions is a source as soon as it is in the config, and while it is; deleted, its
    /// rows go and its program isn't run again.
    @Test func noApprovalAndOnWhileItExists() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program))
            #expect(world.switches.enabled.isEmpty && world.switches.master == nil, "nothing approved, nothing switched on")
            let field = world.field()
            field.type("JIRA-4")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012", "JIRA-433"] },
                    "\(field.rows.map(\.text))")
            let calls = program.calls.count
            Self.setCommands([], in: world, field: field)
            field.type(" JIRA-4")
            field.idle(0.5)
            #expect(field.rows.isEmpty, "deleted: \(field.rows.map(\.text))")
            let next = world.field()
            next.type("JIRA-4")
            next.pause(2 * 3600)
            next.type(" JIRA-4")
            next.idle(0.5)
            #expect(next.rows.isEmpty && program.calls.count == calls, "never run again: \(program.calls.count) calls")
        }
    }

    /// Suggestions' master switch off: the program never runs (neither its list nor a query), no rows.
    @Test func theMasterSwitchOffMeansItNeverRuns() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program, ["query": "true", "queryMinChars": "1"]))
            world.switches.master = false
            for app in [SuggestionsApps.editor, "com.apple.TextEdit", SuggestionsApps.slack] {
                let field = world.field(app: app)
                field.type("JIRA-4")
                field.idle(0.5)
                field.pause(2 * 3600)
                field.type(" JIRA-40")
                field.idle(0.5)
                #expect(field.rows.isEmpty, "\(app): \(field.rows.map(\.text))")
            }
            #expect(program.calls.isEmpty, "never run: \(program.calls)")
        }
    }

    /// An app's Suggestions off: no rows there, and nothing typed there goes to the program; other apps as before.
    @Test func anAppsSuggestionsOffMeansNoRowsThere() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program, ["query": "true", "queryMinChars": "1"]))
            world.switches.apps[SuggestionsApps.editor] = false
            let off = world.field()
            off.type("JIRA-4")
            off.idle(0.8)
            #expect(off.rows.isEmpty, "\(off.rows.map(\.text))")
            #expect(program.calls.allSatisfy { $0.isEmpty }, "nothing typed there went to it: \(program.calls)")
            let on = world.field(app: "com.apple.TextEdit")
            on.type("JIRA-4")
            #expect(on.settle(timeout: Self.wait) { on.shown(Self.matches).starts(with: ["JIRA-4011", "JIRA-4012", "JIRA-433"]) },
                    "another app: \(on.rows.map(\.text))")
        }
    }

    enum MagicKey: String, CaseIterable, Sendable {
        case at = "@", hash = "#"
    }

    /// A prefix starting with the magic key is never used (decision 24; spec 6.14): typing it opens the command list, the
    /// program never runs, no rows; Settings says why under the command.
    @Test(arguments: MagicKey.allCases)
    func aPrefixStartingWithTheMagicKeyIsNeverUsed(_ magic: MagicKey) async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", "\(magic.rawValue)J12\tMagic\n" + Self.listLines)
            let command = try Self.jira(program, ["prefix": Self.quoted(magic.rawValue + "J")])
            let world = SuggestionsWorld()
            world.config.commandTrigger = magic.rawValue
            defer { UIText.commandTrigger = "@" }  // the process's, which the session sets
            world.config.customCommands = [command]
            world.switches = world.config.suggestionsSettings()
            let state = command.suggestionsState(world.config, status: nil)
            #expect(state?.problem == true && state?.text.isEmpty == false, "Settings says why: \(String(describing: state))")
            let field = world.field()
            field.type("x \(magic.rawValue)J1")
            #expect(field.host.composer.draft.hasPrefix(magic.rawValue), "the command list opened: \(field.host.composer.draft)")
            field.idle(0.8)
            #expect(!field.rows.contains { ($0.text + $0.comment).contains("J12") }, "\(field.rows.map(\.text))")
            #expect(program.calls.isEmpty, "never run: \(program.calls)")
        }
    }

    // MARK: - Failures

    enum Failure: String, CaseIterable, Sendable {
        /// The program isn't there (deleted, or never on this Mac).
        case missing
        /// It runs past `timeoutSeconds`.
        case timeout
        /// It exits non-zero (what it printed on standard output is no list).
        case exitsNonZero
        /// It prints what isn't a list: JSON cut short.
        case garbage
        /// It prints more than the 4 MiB a list may be (each line a good one).
        case tooMuch
    }

    /// The program broken as `failure` says, its new rows (JIRA-4099) never shown.
    static func breakProgram(_ program: UserProgram, _ failure: Failure) throws {
        switch failure {
        case .missing: try FileManager.default.removeItem(at: program.script)
        case .timeout: try program.setBody("sleep 30")
        case .exitsNonZero:
            try program.setBody(#"printf 'JIRA-4099\tNew one\n'; echo 'jira: not logged in' >&2; exit 3"#)
        case .garbage: try program.setBody(#"printf '{"items": [{"match": "JIRA-4099", "title": "New one"'"#)
        case .tooMuch: try program.setBody(#"yes "$(printf 'JIRA-4099\tNew one')" | head -c 6000000"#)
        }
    }

    /// Uses the source as the user would after a while: the timers due fire, " JIRA-4" is typed.
    static func use(_ field: SuggestionsField) {
        field.fireTimers()
        field.type(" JIRA-4")
    }

    /// A run that fails (the program missing, too slow, exiting non-zero, printing garbage or too much) keeps the old list
    /// (its rows, its count), the source's status says the error, and it backs off: not run again within a minute, run
    /// again after.
    @Test(arguments: Failure.allCases)
    func aFailedRunKeepsTheOldListAndBacksOff(_ failure: Failure) async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let world = Self.world(try Self.jira(program, ["refresh": #""5m""#, "timeoutSeconds": "4"]))
            let field = world.field()
            field.type("JIRA-40")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012"] }, "\(field.rows.map(\.text))")
            #expect(field.settle(timeout: Self.wait) { world.lastStatus?.items == 5 && world.lastStatus?.error == nil },
                    "\(String(describing: world.lastStatus))")

            try Self.breakProgram(program, failure)
            world.clock.advance(6 * 60)
            Self.use(field)
            #expect(field.settle(timeout: Self.wait) { world.lastStatus?.error?.isEmpty == false },
                    "\(failure): the error said (\(String(describing: world.lastStatus)))")
            let status = world.lastStatus
            #expect(status?.items == 5 && status?.paused == false, "\(failure): the old list's items, not paused (\(String(describing: status)))")
            field.type(" JIRA-40")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012"] },
                    "\(failure): the old list (\(field.rows.map(\.text)))")
            field.idle(0.3)
            #expect(field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012"], "\(failure): \(field.rows.map(\.text))")

            let failedRun = world.store.lastLoadStarted(Self.key)
            let calls = program.calls.count
            world.clock.advance(40)
            Self.use(field)
            field.idle(0.5)
            #expect(world.store.lastLoadStarted(Self.key) == failedRun && program.calls.count == calls,
                    "\(failure): not run again within a minute")
            world.clock.advance(30)
            Self.use(field)
            #expect(field.settle(timeout: Self.wait) { world.store.lastLoadStarted(Self.key) != failedRun },
                    "\(failure): run again after a minute")
            if failure != .missing {
                #expect(field.settle(timeout: Self.wait) { program.calls.count == calls + 1 }, "\(failure): \(program.calls.count)")
            }
        }
    }

    /// Failures in a row back off (1 min, 5 min, 30 min, 2 h) and the fifth pauses the source, Settings saying so and
    /// why; paused, the program isn't run, fixed or not; editing the command runs it again, and a good run unpauses it.
    @Test func theFifthFailureInARowPausesUntilAnEdit() async throws {
        try await inEnglish {
            let program = try UserProgram(#"echo 'jira: not logged in' >&2; exit 3"#)
            try program.write("list.tsv", Self.listLines)
            let command = try Self.jira(program)
            let world = Self.world(command)
            let field = world.field()
            field.type("JIRA-4")
            #expect(field.settle(timeout: Self.wait) { program.calls.count == 1 && world.lastStatus?.error != nil },
                    "\(program.calls.count), \(String(describing: world.lastStatus))")
            for (failure, backOff) in [60.0, 300, 1800, 7200].enumerated() {
                let told = world.statuses.withLock { $0.count }
                world.clock.advance(backOff - 15)
                Self.use(field)
                field.idle(0.3)
                #expect(program.calls.count == failure + 1, "failure \(failure + 1): not run within \(Int(backOff)) s")
                world.clock.advance(30)
                Self.use(field)
                #expect(field.settle(timeout: Self.wait) { program.calls.count == failure + 2 && world.statuses.withLock { $0.count } > told },
                        "after \(Int(backOff)) s: run again (\(program.calls.count))")
            }
            #expect(field.settle(timeout: Self.wait) { world.lastStatus?.paused == true }, "the fifth pauses it: \(String(describing: world.lastStatus))")
            #expect(world.lastStatus?.error?.isEmpty == false)
            #expect(command.suggestionsState(world.config, status: world.lastStatus)?.problem == true, "Settings says so")

            try program.setBody(Self.printsTheList)
            for _ in 1...3 {
                world.clock.advance(3 * 3600)
                Self.use(field)
                field.idle(0.3)
            }
            #expect(program.calls.count == 5 && field.rows.isEmpty, "paused, fixed or not: not run (\(program.calls.count))")

            var edited = command
            let fixed = program.folder.appendingPathComponent("jira-list-fixed")
            try program.writeScript(at: fixed)
            edited.argv = [fixed.path]
            Self.setCommands([edited], in: world, field: field)
            Self.use(field)
            #expect(field.settle(timeout: Self.wait) { program.calls.count == 6 }, "edited: run again (\(program.calls.count))")
            field.type(" JIRA-4")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012", "JIRA-433"] },
                    "\(field.rows.map(\.text))")
            #expect(field.settle(timeout: Self.wait) { world.lastStatus?.paused == false && world.lastStatus?.error == nil },
                    "\(String(describing: world.lastStatus))")
        }
    }

    // MARK: - The command itself

    /// Typed as a command (`~jira` with the magic key ~, `@jira` with @), it only says what it is, its summary: nothing
    /// runs, nothing goes in.
    @Test(arguments: ["~", "@"])
    func typingTheCommandOnlySaysWhatItIs(_ trigger: String) async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let command = try Self.jira(program)
            let world = SuggestionsWorld()
            world.config.commandTrigger = trigger
            defer { UIText.commandTrigger = "@" }  // the process's, which the session sets
            world.config.customCommands = [command]
            world.switches = world.config.suggestionsSettings()
            let field = world.field()
            field.idle(0.5)
            let calls = program.calls.count
            var said: [String] = []
            func look() {
                said += field.rows.map { $0.text + " " + $0.comment }
                said += [field.footer, field.host.noticeAlone ?? ""]
            }
            field.type("\(trigger)jira")
            look()
            field.press(SuggestionKeys.enter)
            field.idle(0.3)
            look()
            field.press(SuggestionKeys.enter)
            field.idle(0.5)
            look()
            #expect(said.contains { $0.contains("Jira issues") }, "its summary: \(said)")
            #expect(field.document.isEmpty, "nothing goes in: \(field.document)")
            #expect(field.host.opened.isEmpty && field.host.typedOut.isEmpty)
            #expect(program.calls.count == calls && program.calls.allSatisfy { $0.isEmpty }, "nothing runs: \(program.calls)")
        }
    }

    // MARK: - The cache on disk

    /// The regular files in `folder` and below.
    static func files(in folder: URL) -> [URL] {
        guard let all = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return all.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    /// Its list is cached on disk, readable by the user only (0600); the next launch shows it while the program runs again
    /// (failing now: the cached list kept); the command deleted, its file goes.
    @Test func itsListIsCachedForTheUserOnlyAndGoesWithTheCommand() async throws {
        try await inEnglish {
            let program = try UserProgram(Self.printsTheList)
            try program.write("list.tsv", Self.listLines)
            let cache = program.folder.appendingPathComponent("cache", isDirectory: true)
            let command = try Self.jira(program)
            let world = Self.world(command)
            world.cacheFolder = cache
            let field = world.field()
            field.type("JIRA-4")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.matches) == ["JIRA-4011", "JIRA-4012", "JIRA-433"] })
            #expect(field.settle(timeout: Self.wait) { !Self.files(in: cache).isEmpty }, "cached in \(cache.path)")
            for file in Self.files(in: cache) {
                let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
                #expect(permissions == 0o600, "\(file.lastPathComponent): \(String(permissions ?? 0, radix: 8))")
            }

            try program.setBody("exit 1")
            let next = Self.world(command)
            next.cacheFolder = cache
            let launched = next.field()
            launched.type("JIRA-4")
            #expect(launched.settle(timeout: Self.wait) { launched.shown(Self.matches) == ["JIRA-4011", "JIRA-4012", "JIRA-433"] },
                    "the next launch: the cached list (\(launched.rows.map(\.text)))")

            Self.setCommands([], in: next, field: launched)
            launched.type(" JIRA-4")
            #expect(launched.settle(timeout: Self.wait) { Self.files(in: cache).isEmpty },
                    "deleted with the command: \(Self.files(in: cache).map(\.lastPathComponent))")
        }
    }
}
