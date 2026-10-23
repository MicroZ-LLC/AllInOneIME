import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A custom command of type `suggestions` through a text field's session (spec Suggestions v1, decision 24), its program
/// a real sh script in a temporary folder, run as `run` commands run (`CommandCompletionRunner`): its list and its
/// queries, printed as lines or as the plugins' JSON; a bad line dropped; a timeout and the back-off and pause after
/// failures; what is typed after the prefix arriving as one argument, never through a shell nor in the environment; the
/// master and per-app switches; the insert presets; its cached list; the command itself only saying what it is. The rig
/// is the acceptance tests' (Acceptance/SuggestionsAcceptanceTests.swift): a world with its clock, fields that type.
@Suite(.serialized, SuggestionsOneAtATime())
struct CommandSuggestionsSessionTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// A program the tests run: an sh script in a temporary folder that notes each call's arguments (`calls`), then does
    /// what `body` says.
    final class Program: @unchecked Sendable {
        let folder: URL
        let script: URL
        let log: URL

        init(_ body: String) throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("command-suggestions-\(UUID().uuidString)",
                                                                                 isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            script = folder.appendingPathComponent("jira-list")
            log = folder.appendingPathComponent("calls.log")
            // Each call one line, written at once (calls may run side by side): how many arguments, then each after a
            // unit separator.
            let text = """
                #!/bin/sh
                line="$#"; for a in "$@"; do line="$line$(printf '\\037')$a"; done
                printf '%s\\n' "$line" >> '\(log.path)'
                \(body)
                """
            try Data(text.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        /// The calls so far, each its arguments.
        var calls: [[String]] {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            return text.split(separator: "\n").map { line in Array(line.split(separator: "\u{1F}", omittingEmptySubsequences: false).dropFirst().map(String.init)) }
        }

        /// A path in its folder.
        func path(_ name: String) -> String { folder.appendingPathComponent(name).path }
    }

    /// Jira issues: its list with no argument, as lines (one bad); a query's answer for its argument.
    static let tickets = #"""
        if [ $# -eq 0 ]; then
          printf 'JIRA-12\tFix login\thttps://jira.example.com/browse/JIRA-12\n'
          printf 'JIRA-123\tSlow search\thttps://jira.example.com/browse/JIRA-123\n'
          printf 'not a match\tA bad line\n'
          printf 'JIRA-17\tDark mode\n'
        else
          printf 'JIRA-%s9\tFound by query\n' "$1"
        fi
        """#

    static func jira(_ program: Program, _ adjust: (inout CustomCommand) -> Void = { _ in }) -> CustomCommand {
        var command = CustomCommand(name: "jira", type: .suggestions, summary: "Jira issues", argv: [program.script.path],
                                    prefix: "JIRA-")
        adjust(&command)
        return command
    }

    static let key = CompletionSourceKey(command: "jira")

    /// How long a test waits for what a program prints: a program started while a whole test run keeps the Mac busy may
    /// take seconds.
    static let wait: TimeInterval = 15

    // MARK: - List and query

    /// Typing the prefix shows the rows of the program's list (run once, with no argument), no approval asked: a line
    /// that isn't one dropped alone, each row its match and its title.
    @Test func itsListIsWhatTheProgramPrints() async throws {
        try await inEnglish {
            let program = try Program(Self.tickets)
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program)]
            let field = world.field()
            field.type("JIRA-1")
            #expect(field.settle(timeout: Self.wait) { field.rows.count == 3 }, "\(field.rows.map(\.text))")
            #expect(field.rows.map(\.text) == ["JIRA-12", "JIRA-123", "JIRA-17"])
            #expect(field.rows.map(\.comment) == ["Fix login", "Slow search", "Dark mode"])
            #expect(field.footer.contains("Jira issues"), "\(field.footer)")
            #expect(program.calls == [[]], "the list: no argument (\(program.calls))")
            let status = world.lastStatus
            #expect(status?.plugin == CompletionSourceKey.customCommands && status?.source == "jira" && status?.items == 3
                    && status?.error == nil, "Settings: its status (\(String(describing: status)))")
            field.press(SuggestionKeys.tab)
            #expect(field.document == "JIRA-12")
            #expect(world.picks.last == SuggestionPick(plugin: CompletionSourceKey.customCommands, source: "jira", match: "JIRA-12"))
        }
    }

    /// With `query`, the program is also run with what follows the prefix, from `queryMinChars` on; its answer joins the
    /// list's rows.
    @Test func aQueryRunsItWithTheTextAfterThePrefix() async throws {
        try await inEnglish {
            let program = try Program(Self.tickets)
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program) {
                $0.query = true
                $0.queryMinChars = 2
            }]
            let field = world.field()
            field.type("JIRA-1")
            #expect(field.settle(timeout: Self.wait) { field.rows.count == 3 }, "\(field.rows.map(\.text))")
            #expect(program.calls == [[]], "1 character: the list only (\(program.calls))")
            field.type("2")
            #expect(field.settle(timeout: Self.wait) { field.rows.map(\.text) == ["JIRA-12", "JIRA-123", "JIRA-129"] }, "\(field.rows.map(\.text))")
            #expect(program.calls == [[], ["12"]], "\(program.calls)")
        }
    }

    /// The plugins' JSON is read too: its items, their titles, a bad item dropped.
    @Test func itMayPrintThePluginsJSON() async throws {
        try await inEnglish {
            let program = try Program(#"""
                printf '{"items": [{"match": "JIRA-5", "title": "Five", "variables": {"url": "https://jira.example.com/browse/JIRA-5"}},'
                printf ' {"match": "JIRA 6"}, {"match": "JIRA-50", "title": "Fifty"}]}'
                """#)
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program) { $0.insert = CustomCommand.InsertPreset.titleAndLink.insert }]
            let field = world.field(app: SuggestionsApps.slack)
            field.type("JIRA-5")
            #expect(field.settle(timeout: Self.wait) { field.rows.map(\.text) == ["JIRA-5", "JIRA-50"] }, "\(field.rows.map(\.text))")
            field.press(SuggestionKeys.tab)
            #expect(field.document == "JIRA-5 Five https://jira.example.com/browse/JIRA-5", "\(field.document)")
        }
    }

    /// A key never waits for the program: the rows come once it has printed.
    @Test func aKeyNeverWaitsForTheProgram() async throws {
        try await inEnglish {
            let program = try Program("sleep 0.6\nprintf 'JIRA-12\\tFix login\\n'")
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program)]
            let field = world.field()
            let clock = ContinuousClock()
            let typed = clock.measure { field.type("JIRA-1") }
            #expect(typed < .milliseconds(400), "\(typed)")
            #expect(field.rows.isEmpty)
            #expect(field.settle(timeout: Self.wait) { field.rows.map(\.text) == ["JIRA-12"] }, "\(field.rows.map(\.text))")
        }
    }

    // MARK: - Arguments

    /// What is typed after the prefix goes to the program as one argument, in place of `{input}`: never through a shell
    /// (`;`, `$( )` and quotes are text), never in its environment; the list's `{input}` argument left out.
    @Test func theQueryIsOneArgumentNeverThroughAShell() async throws {
        let program = try Program("printf 'JIRA-1\\n'\nenv > \"$0.env.$#\"")
        let pwned = program.path("pwned")
        var command = Self.jira(program) { $0.argv = [program.script.path, "--query", "{input}", "--json"] }
        command.query = true
        let runner = CommandCompletionRunner()
        let token = "x; rm -rf / $(touch \(pwned)) `touch \(pwned)` \"'"
        _ = try await runner.query(token, command)
        _ = try await runner.list(command)
        #expect(program.calls == [["--query", token, "--json"], ["--query", "--json"]], "\(program.calls)")
        #expect(!FileManager.default.fileExists(atPath: pwned), "nothing ran in a shell")
        let environment = try String(contentsOfFile: program.script.path + ".env.3", encoding: .utf8)
        #expect(!environment.contains("rm -rf"), "not in the environment")
        // Without {input}: the last argument.
        command.argv = [program.script.path, "--project", "WEB"]
        _ = try await runner.query("12", command)
        #expect(program.calls.last == ["--project", "WEB", "12"])
    }

    /// Through a field: the token after the prefix, as typed, is the argument (nothing else of the field), and it isn't
    /// in the program's environment.
    @Test func aFieldSendsOnlyTheTokenAfterThePrefix() async throws {
        try await inEnglish {
            let program = try Program(Self.tickets + "\nenv > \"$0.env.$#\"")
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program) {
                $0.query = true
                $0.queryMinChars = 3
            }]
            let field = world.field()
            field.type("see JIRA-q7x")
            let written = program.script.path + ".env.1"
            #expect(field.settle(timeout: Self.wait) { FileManager.default.fileExists(atPath: written) }, "\(program.calls)")
            // The list (at the focus) and the query run side by side: in either order.
            #expect(Set(program.calls) == [[], ["q7x"]] && program.calls.count == 2, "\(program.calls)")
            #expect(field.settle(timeout: Self.wait) { field.rows.map(\.text) == ["JIRA-q7x9"] }, "\(field.rows.map(\.text))")
            let environment = try String(contentsOfFile: written, encoding: .utf8)
            #expect(!environment.contains("q7x") && !environment.contains("see"), "not in the environment")
        }
    }

    // MARK: - Failures

    /// A program that runs too long is stopped at its `timeoutSeconds`: the source says so, and backs off as a plugin's
    /// (no run again within a minute; then again).
    @Test func aTimeoutFailsTheListAndBacksOff() async throws {
        try await inEnglish {
            let program = try Program("sleep 5\nprintf 'JIRA-1\\n'")
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program) { $0.timeoutSeconds = 1 }]
            let field = world.field()
            field.type("JIRA-1")
            #expect(field.settle(timeout: Self.wait) { world.lastStatus?.error != nil }, "\(world.statuses.withLock { $0 })")
            #expect(world.lastStatus?.error?.contains("Stopped after 1") == true, "\(String(describing: world.lastStatus))")
            #expect(world.lastStatus?.paused == false && field.rows.isEmpty)
            #expect(program.calls.count == 1)
            field.type(" JIRA-1")
            field.idle(0.5)
            #expect(program.calls.count == 1, "backing off: not run again (\(program.calls.count))")
            field.pause(61)
            #expect(field.settle(timeout: Self.wait) { program.calls.count == 2 }, "a minute later: again (\(program.calls.count))")
        }
    }

    /// Failures in a row back off (1 min, 5 min, 30 min, 2 h) and the fifth pauses the source, its error kept (the last
    /// line the program wrote to standard error); "Refresh now" runs it again at once, and so does an edit of it.
    @Test func failuresBackOffThenPause() async throws {
        try await inEnglish {
            let program = try Program("echo 'jira: not logged in' >&2\nexit 3")
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program)]
            let field = world.field()
            field.type("JIRA-1")
            #expect(field.settle(timeout: Self.wait) { program.calls.count == 1 && world.lastStatus?.error != nil }, "\(program.calls.count)")
            #expect(world.lastStatus?.error == "jira: not logged in", "\(String(describing: world.lastStatus))")
            for (failure, wait) in [60.0, 300, 1800, 7200].enumerated() {
                field.pause(wait - 5)
                field.idle(0.2)
                #expect(program.calls.count == failure + 1, "before the back-off ends: not run (\(program.calls.count))")
                field.pause(10)
                #expect(field.settle(timeout: Self.wait) { program.calls.count == failure + 2 && (world.statuses.withLock { $0 }.count >= failure + 2) },
                        "after \(wait) s: run again (\(program.calls.count))")
            }
            #expect(field.settle(timeout: Self.wait) { world.lastStatus?.paused == true }, "the fifth failure pauses it (\(String(describing: world.lastStatus)))")
            #expect(world.store.status(Self.key)?.error == "jira: not logged in")
            field.pause(7300)
            #expect(program.calls.count == 5, "paused: not run (\(program.calls.count))")

            world.switches.refreshes = [CompletionSourceRefresh(plugin: CompletionSourceKey.customCommands, source: "jira",
                                                                requested: world.clock.now)]
            field.host.send(.configChanged)
            #expect(field.settle(timeout: Self.wait) { program.calls.count == 6 }, "Refresh now: run at once (\(program.calls.count))")
        }
    }

    // MARK: - Switches

    enum Switch: String, CaseIterable, Sendable { case master, app }

    /// Suggestions' master switch and the app's Suggestions apply as to plugins: off, no rows and nothing typed goes to
    /// the program (no query); the master switch off, it never runs.
    @Test(arguments: Switch.allCases)
    func theSwitchesApply(_ off: Switch) async throws {
        try await inEnglish {
            let program = try Program(Self.tickets)
            let world = SuggestionsWorld()
            world.switches.commands = [Self.jira(program) {
                $0.query = true
                $0.queryMinChars = 1
            }]
            switch off {
            case .master: world.switches.master = false
            case .app: world.switches.apps[SuggestionsApps.editor] = false
            }
            let field = world.field()
            field.type("JIRA-1")
            field.idle(0.5)
            #expect(field.rows.isEmpty && program.calls.allSatisfy(\.isEmpty), "\(off) off: \(field.rows.map(\.text)), \(program.calls)")
            if off == .master { #expect(program.calls.isEmpty, "\(program.calls)") }
            // Another app, its switch on: rows.
            if off == .app {
                let other = world.field(app: "com.apple.TextEdit")
                other.type("JIRA-1")
                #expect(other.settle(timeout: Self.wait) { other.rows.count == 3 }, "\(other.rows.map(\.text))")
            }
        }
    }

    /// Its prefix starting with the magic key: the key opens the command list, the source is inactive (Settings says
    /// why), its program never runs.
    @Test func theMagicKeyWins() async throws {
        try await inEnglish {
            let program = try Program(Self.tickets)
            let world = SuggestionsWorld()
            world.config.commandTrigger = "#"
            let command = Self.jira(program) { $0.prefix = "#J" }
            world.switches.commands = [command]
            #expect(try command.suggestionSource?.get().inactiveReason(world.config) != nil)
            let field = world.field()
            field.type("x #J1")
            field.idle(0.5)
            #expect(field.rows.isEmpty && program.calls.isEmpty, "\(program.calls)")
        }
    }

    // MARK: - Insertion

    enum Preset: String, CaseIterable, Sendable { case match, title, titleAndLink }

    /// The insert presets, per class of app: the match alone; with its title; in chat apps with its link too. Only what
    /// wasn't typed goes in; a terminal completes what the rows share.
    @Test(arguments: Preset.allCases)
    func theInsertPresets(_ preset: Preset) async throws {
        try await inEnglish {
            let program = try Program(Self.tickets)
            let world = SuggestionsWorld()
            let insert = CustomCommand.InsertPreset(rawValue: preset.rawValue)!.insert
            world.switches.commands = [Self.jira(program) {
                $0.insert = insert
                $0.minChars = 0
            }]
            let expected: [String: String] = [
                SuggestionsApps.editor: preset == .match ? "JIRA-12" : "JIRA-12 Fix login",
                SuggestionsApps.slack: preset == .match ? "JIRA-12" : preset == .title ? "JIRA-12 Fix login"
                    : "JIRA-12 Fix login https://jira.example.com/browse/JIRA-12",
            ]
            for (app, inserted) in expected {
                let field = world.field(app: app)
                field.type("JIRA-1")
                #expect(field.settle(timeout: Self.wait) { field.rows.count == 3 }, "\(app): \(field.rows.map(\.text))")
                field.press(SuggestionKeys.tab)
                #expect(field.document == inserted, "\(preset) in \(app)")
            }
            // A row without a title: the match alone.
            let untitled = world.field()
            untitled.type("JIRA-17")
            #expect(untitled.settle(timeout: Self.wait) { untitled.rows.map(\.text) == ["JIRA-17"] } || preset != .match, "\(untitled.rows.map(\.text))")
            // A terminal: Tab completes what the rows' matches share (from the prefix on, `minChars` 0), whatever the
            // preset; nothing more when they share only what was typed.
            let terminal = world.field(app: "com.apple.Terminal", terminal: true)
            terminal.type("JIRA-")
            #expect(terminal.settle(timeout: Self.wait) { terminal.rows.count == 3 }, "\(terminal.rows.map(\.text))")
            #expect(terminal.press(SuggestionKeys.tab))
            #expect(terminal.document == "JIRA-1", "\(preset) in a terminal: what they share (\(terminal.document))")
            #expect(!terminal.press(SuggestionKeys.tab), "nothing more shared: Tab is the terminal's")
        }
    }

    // MARK: - Kept

    /// Its list is cached on disk (readable by the user only) and read at the next launch; the command deleted, its file
    /// goes.
    @Test func itsListIsCachedUntilTheCommandGoes() async throws {
        try await inEnglish {
            let program = try Program(Self.tickets)
            let world = SuggestionsWorld()
            let cache = program.folder.appendingPathComponent("cache", isDirectory: true)
            world.cacheFolder = cache
            world.switches.commands = [Self.jira(program)]
            let field = world.field()
            field.type("JIRA-1")
            #expect(field.settle(timeout: Self.wait) { field.rows.count == 3 })
            let file = cache.appendingPathComponent("custom-commands.jira.json")
            #expect(field.settle(timeout: Self.wait) { FileManager.default.fileExists(atPath: file.path) }, "cached")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)

            world.switches.commands = []
            field.host.send(.configChanged)
            SuggestionsStore.disk.sync {}
            #expect(field.settle(timeout: Self.wait) { !FileManager.default.fileExists(atPath: file.path) }, "deleted with the command")
        }
    }

    // MARK: - The command itself

    /// `@jira` is a source, not an action: picked or run, it says what it is; nothing runs, nothing goes in.
    @Test func theCommandItselfOnlySaysWhatItIs() async throws {
        try await inEnglish {
            let program = try Program(Self.tickets)
            let world = SuggestionsWorld()
            let command = Self.jira(program)
            world.config.customCommands = [command]
            world.switches.commands = [command]
            let field = world.field()
            field.type("@jira")
            field.press(SuggestionKeys.enter)
            field.press(SuggestionKeys.enter)
            field.idle(0.3)
            let said = field.host.noticeAlone ?? field.host.panel?.detail ?? ""
            #expect(said.contains("suggestion source") && said.contains("JIRA-"), "\(said)")
            // Its list may load (a field took the focus), as a plugin's; nothing typed goes to it.
            #expect(field.document.isEmpty && program.calls.allSatisfy(\.isEmpty), "\(field.document), \(program.calls)")
        }
    }
}
