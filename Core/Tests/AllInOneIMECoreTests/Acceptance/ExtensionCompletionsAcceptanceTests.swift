import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/*
 The API these tests need that 0.6.7 doesn't have (ExtensionCompletions-API.md has all of it, and how a session gets
 the commands):

     extension ScriptCommand {
         /// The completion source the command declares (`@allinoneime.completion {…}`, or its bundle entry's
         /// `"completion": {…}`, the entry's over the line), read by a plugin `completions` entry's rules, its name the
         /// command's name and its title the command's title. `.failure`: refused, and why; nil: none declared.
         public var completion: Result<CompletionSource, CompletionRefusal>? { get }
     }

     extension CompletionSourceKey {
         /// What `command`'s source is kept under (its list, status, picks, approval): a `plugin` no plugin can have.
         public init(extension command: ScriptCommand)
     }

     extension CompletionSourceApproval {
         /// What turning `command`'s source on in Settings → Commands approves now: its key, its extension's digest (every
         /// file of its bundle, a single script's file: `ExtensionDigest`), whether it queries, its terms; no hosts. Nil: no
         /// source declared (or one refused), or nothing of it to read.
         public init?(enabling command: ScriptCommand)
     }

 (`SuggestionsInsert.markdownLink`, which the last test uses: SuggestionsReplaceAcceptanceTests.swift.)
 */

/// Script extensions as completion sources; replacing inserts (0.6.7.1, owner, 2026-10-24), section 2: a script
/// extension's command declares one completion source, as a plugin's `completions` entry declares one; its program runs
/// for the list (`ALLINONEIME_COMPLETION=load`) and the query (`=query`, the text after the prefix its one argument), on
/// by default until the user turns it off (owner 2026-10-25); the Insert choices apply to it. Written from the spec by the tests' author, not from the
/// implementation (whose changes don't edit them). The extensions are written to disk and read as the app reads them
/// (`ScriptFolder`, `ExtensionStore.load`), and handed to a text field's `InputSession` as the shell hands them
/// (`SessionServices.loadExtensions`); the field is driven as a shell drives it (the rig: SuggestionsAcceptanceTests.swift).
/// Their programs are real bash scripts of the tests' own in a temporary folder, which note each run (how it was called,
/// its environment, where it ran, its start and end) and print what the test wrote for them.
///
/// Section 4's bullets: an extension's declaration (single script line, bundle entry, entry over line, refused
/// declarations with reasons, command still loads): `aScriptDeclaresItsSourceOnOneMetadataLine`,
/// `aBundleEntryDeclaresItsSourceOverTheScriptsLine`, `aDeclarationThatBreaksTheRulesIsRefusedAloneWithItsReason`,
/// `aCommandWithASourceIsStillACommand`; the run protocol (env, argument, no app/token, limits, 64 KB lifted, one at a
/// time per bundle): `theListRunsWithLoadAndNoArguments`, `aQueryGetsTheTextAfterThePrefixAsItsOneArgument`,
/// `theEnvironmentHasTheLanguageAndThePreferencesButNotTheAppOrTheToken`, `outputsOver64KBAreRead`,
/// `aListOverTheItemsOrBytesLimitIsAFailure`, `aQueryIsStoppedAfterThreeSeconds`, `aListIsStoppedAfterTwentySecondsAtMost`,
/// `aBundleRunsOneCompletionProgramAtATime`, `aNewerQueryCancelsTheOlderOne`; trust (on by default until turned off,
/// owner 2026-10-25; from an extension source whose updates aren't trusted, turned off by a change to any file of the
/// bundle or to its prefix, query or compare; the user's own kept on, owner 2026-10-24): `aSourceIsOnUntilTurnedOff`,
/// `aChangeToItsScriptPrefixQueryOrCompareTurnsItOff`, `aChangeToAnythingElseKeepsItOn`,
/// `nothingRunsForSecureInputOrPasswordFields`; Insert choices apply:
/// `theInsertChoicesApplyToItsRows`.
@Suite(.serialized, SuggestionsOneAtATime())
struct ExtensionCompletionsAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// How long a test waits for what a real program does (started while a whole test run keeps the machine busy).
    static let wait: TimeInterval = 15

    // MARK: - The world

    /// A Suggestions world (the rig's) with script extensions: their folder on disk, read as the app reads it (again with
    /// `reload`, as a scan after a change), handed to every field's session as the shell hands it, with the values its
    /// bundles' commands get (`extensionPreferences`: what the user set, passwords from the keychain); an approval reported
    /// lapsed is marked so in the settings, as the shell marks it. The programs are bash scripts of the test's own
    /// (`body`), which note each run in a folder of their own (`logs`) and print what the test wrote there for them.
    /// With `source`, the extensions' folder is the extension sources' folder (as the shell has it, `Config.extensionSources`
    /// naming it), the bundle "desk" that source's clone (`deskFolder`); without, a folder of the user's own.
    final class World: @unchecked Sendable {
        let suggestions: SuggestionsWorld
        let extensions = ScriptFolder()
        let logs = ScriptFolder()
        private let index = Locked(initialState: ExtensionIndex.empty)
        /// What `extensionPreferences` gives each bundle's commands, by the bundle's name.
        let preferences = Locked<[String: [String: String]]>(initialState: [:])
        /// The approvals the session reported lapsed (`approvalsLapsed`), in order.
        let lapsed = Locked<[CompletionSourceApproval]>(initialState: [])

        /// The extension source "desk" is installed from (nil: the user's own folder).
        let source: ExtensionSource?

        init(source: ExtensionSource? = nil) {
            suggestions = SuggestionsWorld()
            self.source = source
            suggestions.config.extensionSources = source.map { [$0] } ?? []
        }

        /// The bundle "desk"'s folder in the extensions' folder: "desk", or its source's clone.
        var deskFolder: String { source.map { ExtensionSources.folderName(for: $0.url) } ?? "desk" }

        /// Writes `name` (folders made as needed) into the extensions' folder, executable.
        func add(_ name: String, _ text: String) { extensions.add(name, text) }

        /// The folder read again, as the app reads it.
        func reload() {
            let read = extensions.load()
            index.withLock { $0 = read }
        }

        var loaded: ExtensionIndex { index.withLock { $0 } }

        func command(_ name: String) throws -> ScriptCommand {
            try #require(loaded.commands.first { $0.name == name }, "\(name): \(loaded.commands.map(\.name)), skipped \(loaded.skipped)")
        }

        /// `name`'s source turned on in Settings → Commands, with what it is now (an approval of it before, replaced).
        @discardableResult
        func enable(_ name: String) throws -> CompletionSourceApproval {
            let command = try command(name)
            let approval = try #require(CompletionSourceApproval(enabling: command), "\(name): \(String(describing: command.completion))")
            suggestions.switches.enabled.removeAll { $0.plugin == approval.plugin && $0.source == approval.source }
            suggestions.switches.enabled.append(approval)
            return approval
        }

        /// A text field of `app` that has the focus, its session given the extensions as they are when it asks.
        func field(app: String = SuggestionsApps.editor, terminal: Bool = false, passwordField: Bool = false) -> SuggestionsField {
            suggestions.field(app: app, terminal: terminal, passwordField: passwordField) { services in
                services.loadExtensions = { _, _ in self.loaded }
                if self.source != nil { services.suggestions.extensionSourcesFolder = self.extensions.url }
                services.extensionPreferences = { bundle, _ in self.preferences.withLock { $0[bundle.name] ?? [:] } }
                services.suggestions.approvalsLapsed = { marked in
                    self.lapsed.withLock { $0 += marked }
                    var config = Config.default
                    config.completionSources = self.suggestions.switches.enabled
                    config.markLapsed(marked)
                    self.suggestions.switches.enabled = config.completionSources
                }
            }
        }

        var reportedLapsed: [CompletionSourceApproval] { lapsed.withLock { $0 } }

        /// The last status reported for `command`'s source.
        func status(_ command: ScriptCommand) -> CompletionSourceStatus? {
            let key = CompletionSourceKey(extension: command)
            return suggestions.statuses.withLock { $0 }.last { $0.plugin == key.plugin && $0.source == key.source }
        }

        // MARK: The programs

        /// What every program of these tests does, as `name`: notes the run in `logs` (how it was called: its
        /// ALLINONEIME_COMPLETION, "command" without one, then its arguments; its environment as `env` prints it; where it
        /// runs; its start, and its end once it gets there), waits first if the test says so (`delay`), then prints what the
        /// test wrote for it (`list`, `answer`; a query without an answer: no items), or as a command a line of its own.
        func body(_ name: String) -> String {
            #"""
            log='\#(logs.url.path)'; name='\#(name)'
            kind="${ALLINONEIME_COMPLETION:-command}"
            call="$kind"; for a in "$@"; do call="$call$(printf '\037')$a"; done
            printf '%s\n' "$call" >> "$log/$name.calls"
            env > "$log/$name.$kind.$$.env"
            pwd -P > "$log/$name.$$.pwd"
            printf 'start %s %s %s\n' "$name" "$kind" "$*" >> "$log/events"
            pause="$log/$name.$kind${1:+.$1}.sleep"
            if [ -f "$pause" ]; then sleep "$(cat "$pause")"; fi
            case "$kind" in
              load) cat "$log/$name.list.json" ;;
              query) if [ -f "$log/$name.query.$1.json" ]; then cat "$log/$name.query.$1.json"; else echo '{"items": []}'; fi ;;
              *) echo "ran as a command: $*" ;;
            esac
            printf 'end %s %s %s\n' "$name" "$kind" "$*" >> "$log/events"
            """#
        }

        /// A single script `name`: its title (the name, capitalized), `keys` (each "key value"), the completion it declares
        /// (`completion`, the JSON of its `@allinoneime.completion` line; nil: none), then `body`.
        func program(_ name: String, completion: String?, keys: [String] = []) -> String {
            script(["title \(name.capitalized)"] + keys + (completion.map { ["completion \($0)"] } ?? []), body(name))
        }

        /// What program `name` prints for its list: `items` (made at `fetchedAt`), or `json` as it is.
        func list(_ name: String, _ items: [CompletionItem], fetchedAt: Date? = nil) {
            write("\(name).list.json", SuggestionsJSON.list(items, fetchedAt: fetchedAt))
        }

        func list(_ name: String, json: String) { write("\(name).list.json", Data(json.utf8)) }

        /// What program `name` prints for the query `text`.
        func answer(_ name: String, query text: String, _ items: [CompletionItem]) {
            write("\(name).query.\(text).json", SuggestionsJSON.list(items))
        }

        /// How long program `name` waits before it prints, run for `kind` ("load", "query"; a query for `text` only).
        func delay(_ name: String, _ kind: String, query text: String? = nil, seconds: Double) {
            write("\(name).\(kind)\(text.map { "." + $0 } ?? "").sleep", Data("\(seconds)".utf8))
        }

        func write(_ file: String, _ data: Data) { try? data.write(to: logs.url.appendingPathComponent(file)) }

        /// The bytes of what program `name` prints for its list.
        func listSize(_ name: String) -> Int {
            ((try? FileManager.default.attributesOfItem(atPath: logs.url.appendingPathComponent("\(name).list.json").path))?[.size]
                as? Int) ?? 0
        }

        // MARK: What they noted

        private func text(_ file: String) -> String {
            (try? String(contentsOf: logs.url.appendingPathComponent(file), encoding: .utf8)) ?? ""
        }

        private func files(_ prefix: String, _ suffix: String) -> [String] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: logs.url.path)) ?? []
            return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.sorted().map(text)
        }

        /// The runs of program `name` so far, in order: each how it was called (its ALLINONEIME_COMPLETION, "command"
        /// without one), then its arguments.
        func calls(_ name: String) -> [[String]] {
            text("\(name).calls").split(separator: "\n").map { line in
                line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            }
        }

        /// The environments of `name`'s runs for `kind` ("load", "query"), each as `env` printed it.
        func environments(_ name: String, _ kind: String) -> [String] { files("\(name).\(kind).", ".env") }

        /// Where `name`'s runs ran.
        func directories(_ name: String) -> [String] {
            files("\(name).", ".pwd").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        /// The runs' starts and ends, in order: "start <name> <kind> <arguments>", "end …".
        var events: [String] {
            text("events").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    /// The value of the variable `name` in an environment as `env` printed it; nil: not there.
    static func variable(_ name: String, in environment: String) -> String? {
        environment.split(separator: "\n").first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
    }

    /// Whether no two runs of `events` overlapped: each start followed by its own end before the next start.
    static func oneAtATime(_ events: [String]) -> Bool {
        var running: String?
        for event in events {
            let parts = event.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return false }
            switch parts[0] {
            case "start":
                guard running == nil else { return false }
                running = parts[1]
            case "end":
                guard running == parts[1] else { return false }
                running = nil
            default: return false
            }
        }
        return true
    }

    // MARK: - Sources and items

    /// A source of tickets after "TKT-": a list refreshed every hour and, with `query`, a lookup from `queryMinChars`
    /// characters on, as `@allinoneime.completion` or a bundle entry writes it.
    static func tickets(prefix: String = "TKT-", compare: String = "prefix", query: Bool = true, queryMinChars: Int = 3,
                        refresh: String = "1h", insert: String = #"{"default": "{arg}"}"#) -> String {
        #"{"prefix": "\#(prefix)", "minChars": 1, "compare": "\#(compare)", "list": true, "refresh": "\#(refresh)", "query": \#(query), "queryMinChars": \#(queryMinChars), "insert": \#(insert)}"#
    }

    /// A ticket with its title and address as variables too (`{title}`, `{url}`).
    static func ticket(_ match: String, _ title: String) -> CompletionItem {
        CompletionItem(match: match, title: title, variables: ["title": title, "url": "https://tickets.example.com/\(match)"])
    }

    static let ticketList = [ticket("TKT-101", "Fix login"), ticket("TKT-102", "Slow search"), ticket("TKT-205", "Dark mode")]
    /// The matches a row may show, longest first where one starts another.
    static let ticketMatches = ["TKT-101", "TKT-102", "TKT-205", "TIX-101"]

    /// A bundle "desk" (Help Desk) whose command "tickets" declares `completion` in its entry, its script without one;
    /// with `preferences`, a region (a text, "eu" by default) and an API token (a password).
    static func desk(_ completion: String, preferences: Bool = false) -> String {
        let declared = preferences ? #""preferences": [{"name": "region", "type": "textfield", "title": "Region", "default": "eu"}, {"name": "apiToken", "type": "password", "title": "API token"}],"# : ""
        return #"""
            {"schemaVersion": 1, "name": "desk", "title": "Help Desk", \#(declared)
             "commands": [{"script": "tickets.sh", "name": "tickets", "title": "Tickets", "completion": \#(completion)}]}
            """#
    }

    /// The world with the bundle "desk" (`desk`) written and read, its program printing `ticketList`; installed from
    /// `source` (nil: a folder of the user's own).
    static func deskWorld(_ completion: String = tickets(), preferences: Bool = false, from source: ExtensionSource? = nil) -> World {
        let world = World(source: source)
        world.add(world.deskFolder + "/extension.json", desk(completion, preferences: preferences))
        world.add(world.deskFolder + "/tickets.sh", "#!/bin/bash\n" + world.body("tickets"))
        world.list("tickets", ticketList)
        world.reload()
        return world
    }

    /// The world with the single script "tickets.sh" declaring `completion` written and read, its program printing
    /// `ticketList`.
    static func ticketsWorld(_ completion: String = tickets()) -> World {
        let world = World()
        world.add("tickets.sh", world.program("tickets", completion: completion))
        world.list("tickets", ticketList)
        world.reload()
        return world
    }

    // MARK: - The declaration

    /// "A single script: one metadata line, `# @allinoneime.completion {…JSON…}` (any comment mark, as other keys)", "with
    /// the same fields and meaning as a plugin's `completions` entry", "`name` and `title` are not given: the source is the
    /// command's (its name, its title)". What a key leaves out is a plugin entry's default (minChars 1 with a prefix,
    /// compare prefix, refresh 1 h, queryMinChars 3, insert `{arg}`); a source without a prefix compares exact, from 3
    /// digits. A script without the line declares none.
    @Test func aScriptDeclaresItsSourceOnOneMetadataLine() throws {
        let world = World()
        let insert = #"{"default": ["{arg} {title}", "{arg}"], "chat": ["{arg} {url}", "{arg}"], "terminal": "{match}"}"#
        world.add("tickets.sh", world.program("tickets", completion: Self.tickets(queryMinChars: 2, insert: insert)))
        world.add("bare.sh", world.program("bare", completion: #"{"prefix": "BARE-", "list": true}"#))
        world.add("accounts.sh", world.program("accounts", completion: #"{"compare": "exact", "list": true, "refresh": "1d"}"#))
        world.add("plain.sh", world.program("plain", completion: nil))
        for (file, mark) in [("slashes.js", "//"), ("dashes.lua", "--"), ("semicolons.el", ";")] {
            world.add(file, "#!/bin/sh\n\(mark) @allinoneime.schemaVersion 1\n\(mark) @allinoneime.completion {\"prefix\": \"MARK-\", \"list\": true}\necho hi\n")
        }
        world.reload()

        let command = try world.command("tickets")
        let source = try #require(try command.completion?.get(), "\(String(describing: command.completion))")
        #expect(source.name == "tickets" && source.title.en == "Tickets" && command.title == "Tickets", "the command's: \(source.name), \(source.title)")
        #expect(source.prefix == "TKT-" && source.minChars == 1 && source.compare == .prefix && source.list && source.refresh == 3600
                && source.query && source.queryMinChars == 2, "\(source)")
        #expect(source.insert == CompletionInsert(default: .templates(["{arg} {title}", "{arg}"]), chat: .templates(["{arg} {url}", "{arg}"]),
                                                  terminal: .templates(["{match}"])), "\(source.insert)")

        let bare = try #require(try world.command("bare").completion?.get())
        #expect(bare.minChars == 1 && bare.compare == .prefix && bare.refresh == 3600 && !bare.query && bare.queryMinChars == 3
                && bare.insert == .standard, "a plugin entry's defaults: \(bare)")
        let accounts = try #require(try world.command("accounts").completion?.get())
        #expect(accounts.prefix == nil && accounts.compare == .exact && accounts.minChars == 3 && accounts.refresh == 86400
                && !accounts.query, "\(accounts)")
        let plain = try world.command("plain")
        #expect(plain.completion == nil, "no line: no source")
        for name in ["slashes", "dashes", "semicolons"] {
            let marked = try world.command(name)
            #expect((try? marked.completion?.get())?.prefix == "MARK-", "\(name): \(String(describing: marked.completion))")
        }
    }

    /// "A bundle (extension.json): the command's entry may have `"completion": {…}`; as with the other keys, the entry's
    /// value is used over the script's own line." An entry's declaration is the command's; one that has none leaves the
    /// script's line as it is; one over a script's line replaces it whole (its prefix, its query).
    @Test func aBundleEntryDeclaresItsSourceOverTheScriptsLine() throws {
        let world = World()
        world.add("desk/extension.json", #"""
            {"schemaVersion": 1, "name": "desk", "title": "Help Desk",
             "commands": [
               {"script": "tickets.sh", "name": "tickets", "title": "Tickets", "completion": {"prefix": "TKT-", "list": true, "refresh": "15m"}},
               {"script": "moved.sh", "name": "moved", "completion": {"prefix": "NEW-", "list": true, "query": true}},
               {"script": "kept.sh", "name": "kept"}
             ]}
            """#)
        world.add("desk/tickets.sh", "#!/bin/bash\n" + world.body("tickets"))
        world.add("desk/moved.sh", world.program("moved", completion: #"{"prefix": "OLD-", "list": true}"#))
        world.add("desk/kept.sh", world.program("kept", completion: #"{"prefix": "KEPT-", "list": true}"#))
        world.reload()

        let tickets = try world.command("tickets")
        #expect(tickets.source == .bundle("desk"))
        let source = try #require(try tickets.completion?.get(), "\(String(describing: tickets.completion))")
        #expect(source.name == "tickets" && source.title.en == "Tickets" && source.prefix == "TKT-" && source.refresh == 900, "\(source)")
        let movedCommand = try world.command("moved")
        let moved = try #require(try movedCommand.completion?.get())
        #expect(moved.prefix == "NEW-" && moved.query, "the entry's over the line: \(moved)")
        #expect(moved.title.en == movedCommand.title, "\(moved.title)")
        let kept = try #require(try world.command("kept").completion?.get())
        #expect(kept.prefix == "KEPT-", "no entry of its own: the line's (\(kept))")
    }

    /// "A declaration that breaks the rules (same as a plugin's: e.g. `query` without `prefix`, a no-prefix source other
    /// than `exact` over digits, a bad template) is refused on its own, with its reason shown under the command in
    /// Settings; the command still loads." "One source per command." Each refused declaration has its own reason (the
    /// rule it breaks); its command loads as it would without it (none is skipped), next to one whose declaration is good.
    @Test func aDeclarationThatBreaksTheRulesIsRefusedAloneWithItsReason() async throws {
        try await inEnglish {
            let world = World()
            let refused: [(name: String, completion: String)] = [
                ("queries", #"{"list": true, "query": true}"#),
                ("digits", #"{"list": true, "compare": "prefix"}"#),
                ("template", #"{"prefix": "TPL-", "list": true, "insert": {"default": "{arg"}}"#),
                ("often", #"{"prefix": "OFT-", "list": true, "refresh": "1m"}"#),
                ("broken", #"{"prefix": "BRK-", "list": tru"#),
                ("two", #"[{"prefix": "ONE-", "list": true}, {"prefix": "TWO-", "list": true}]"#),
            ]
            for (name, completion) in refused {
                world.add("\(name).sh", world.program(name, completion: completion, keys: ["output insert"]))
            }
            world.add("good.sh", world.program("good", completion: Self.tickets()))
            world.add("desk/extension.json", #"""
                {"schemaVersion": 1, "name": "desk", "commands": [
                   {"script": "entry.sh", "name": "entry", "completion": {"query": true, "list": true}},
                   {"script": "entry.sh", "name": "text", "completion": "TKT-"}]}
                """#)
            world.add("desk/entry.sh", "#!/bin/bash\n" + world.body("entry"))
            world.reload()

            #expect(world.loaded.skipped.isEmpty, "every command loads: \(world.loaded.skipped)")
            var reasons: [String: String] = [:]
            for name in refused.map(\.name) + ["entry", "text"] {
                let command = try world.command(name)
                guard case let .failure(refusal)? = command.completion else {
                    Issue.record("\(name): refused (\(String(describing: command.completion)))")
                    continue
                }
                #expect(!refusal.reason.isEmpty, "\(name): a reason to show")
                reasons[name] = refusal.reason
                #expect(command.title == name.capitalized || command.source == .bundle("desk"), "\(name): the command as it is: \(command.title)")
            }
            let queries = try world.command("queries")
            #expect(queries.output == .insert, "its other keys as they are")
            let rules = ["queries", "digits", "template", "often"].compactMap { reasons[$0] }
            #expect(Set(rules).count == 4, "each the rule it breaks: \(reasons)")
            #expect(reasons["queries"]?.localizedCaseInsensitiveContains("prefix") == true, "\(reasons["queries"] ?? "")")
            #expect(reasons["digits"]?.localizedCaseInsensitiveContains("exact") == true
                    || reasons["digits"]?.localizedCaseInsensitiveContains("compare") == true, "\(reasons["digits"] ?? "")")
            #expect(reasons["template"]?.localizedCaseInsensitiveContains("insert") == true
                    || reasons["template"]?.localizedCaseInsensitiveContains("template") == true, "\(reasons["template"] ?? "")")
            #expect(reasons["often"]?.localizedCaseInsensitiveContains("refresh") == true, "\(reasons["often"] ?? "")")
            #expect((try? world.command("good").completion?.get()) != nil, "the good one next to them is a source")
        }
    }

    /// "One source per command. A command may still be run as a command as before." The command read with its
    /// declaration is the one read without it (its name, title, input, arguments, output, timeout, how it starts), and it
    /// runs as a command does: its arguments as typed, no ALLINONEIME_COMPLETION.
    @Test func aCommandWithASourceIsStillACommand() async throws {
        let world = World()
        let keys = ["output insert", #"argument1 {"type": "text", "placeholder": "words"}"#]
        world.add("tickets.sh", world.program("tickets", completion: Self.tickets(), keys: keys))
        world.reload()
        let declared = try world.command("tickets")
        let plain = try #require(ScriptCommand.read(world.program("tickets", completion: nil, keys: keys),
                                                    file: declared.file, executable: true).flatMap { try? $0.get() })
        #expect(declared.completion != nil && plain.completion == nil)
        #expect(declared.name == plain.name && declared.title == plain.title && declared.input == plain.input
                && declared.arguments == plain.arguments && declared.output == plain.output && declared.timeout == plain.timeout
                && declared.launch == plain.launch && declared.directory == plain.directory, "\(declared) / \(plain)")

        var printed = ""
        for try await update in CommandRunner.run(declared, arguments: ["hello"], environment: ["PATH": "/usr/bin:/bin"]) where update.isFinal {
            printed = update.text
        }
        #expect(printed == "ran as a command: hello", "\(printed)")
        #expect(world.calls("tickets") == [["command", "hello"]], "\(world.calls("tickets"))")
    }

    // MARK: - Running it

    /// "`load`: the script runs with `ALLINONEIME_COMPLETION=load` and no arguments; it prints `{ "items": [Item],
    /// "fetchedAt"?: unixSeconds }` as JSON on standard output." "Working directory as for its commands." "`Item` as a
    /// plugin's: … the same limits and checks." Turned on, its list loads once, its rows are its items in their order
    /// (a bad one dropped alone), the footer says its title and how old the list is (`fetchedAt`), Settings is told its
    /// item count; Return puts the row in.
    @Test func theListRunsWithLoadAndNoArguments() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld(Self.tickets(query: false))
            let fetchedAt = Int(world.suggestions.clock.now.timeIntervalSince1970) - 3 * 3600
            world.list("tickets", json: #"""
                {"fetchedAt": \#(fetchedAt), "items": [
                  {"match": "TKT-101", "title": "Fix login", "variables": {"url": "https://tickets.example.com/TKT-101"}},
                  {"match": "TKT 103", "title": "A space in the match"},
                  "not an item",
                  {"match": "TKT-102", "title": "Slow search"},
                  {"match": "TKT-205", "title": "Dark mode"}
                ]}
                """#)
            let command = try world.command("tickets")
            try world.enable("tickets")
            let field = world.field()
            field.type("TKT-1")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.ticketMatches) == ["TKT-101", "TKT-102"] },
                    "\(field.rows.map { $0.text + " · " + $0.comment })")
            #expect(field.footer.contains("Tickets") && field.footer.contains("3 h ago"), "\(field.footer)")
            #expect(world.calls("tickets") == [["load"]], "once, with no arguments: \(world.calls("tickets"))")
            #expect(world.directories("tickets") == [command.directory.path], "\(world.directories("tickets"))")
            #expect(field.settle { world.status(command)?.items == 3 }, "the good items: \(String(describing: world.status(command)))")
            #expect(world.status(command)?.error == nil)
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "TKT-101", "\(field.document)")
        }
    }

    /// "`query`: `ALLINONEIME_COMPLETION=query`, and the text after the prefix as its one argument (not in the
    /// environment), as a Suggestions custom command gets it; it prints `{ "items": [Item] }`." "Called as a plugin's query
    /// is": not before `queryMinChars` characters after the prefix; its items show after the list's.
    @Test func aQueryGetsTheTextAfterThePrefixAsItsOneArgument() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld()
            world.answer("tickets", query: "qzx", [Self.ticket("TKT-qzx9", "Found by the query")])
            try world.enable("tickets")
            let field = world.field()
            field.type("TKT-qz")
            field.idle(0.8)
            #expect(!world.calls("tickets").contains { $0.first == "query" }, "2 characters: no query yet (\(world.calls("tickets")))")
            field.type("x")
            #expect(field.settle(timeout: Self.wait) { world.calls("tickets").contains(["query", "qzx"]) }, "\(world.calls("tickets"))")
            #expect(field.settle(timeout: Self.wait) { field.shown(["TKT-qzx9"]) == ["TKT-qzx9"] }, "its answer: \(field.rows.map(\.text))")
            let calls = world.calls("tickets")
            #expect(calls.filter { $0.first == "query" }.allSatisfy { $0.count == 2 }, "one argument each: \(calls)")
            #expect(calls.filter { $0.first == "load" }.allSatisfy { $0.count == 1 }, "the list: none (\(calls))")
        }
    }

    /// "Environment: `ALLINONEIME_LANGUAGE`, the bundle's `ALLINONEIME_PREF_*` (passwords from the keychain as for its
    /// commands); never the app in front or the token itself beyond the query argument. Working directory as for its
    /// commands." For the list and the query alike: the interface language (Chinese here), the bundle's values as the shell
    /// gives them (a password among them), nothing of the app (its id nowhere) and nothing of what was typed (the token
    /// nowhere, `ALLINONEIME_QUERY` empty if there at all); run where the command runs.
    @Test func theEnvironmentHasTheLanguageAndThePreferencesButNotTheAppOrTheToken() async throws {
        try await withInterfaceLanguage("zh") {
            let world = Self.deskWorld(preferences: true)
            world.suggestions.config.uiLanguage = "zh"
            world.preferences.withLock { $0["desk"] = ["region": "ap-test", "apiToken": "s3cret-token"] }
            let command = try world.command("tickets")
            try world.enable("tickets")
            let app = "com.example.notes"
            let field = world.field(app: app)
            field.type("TKT-qzx")
            #expect(field.settle(timeout: Self.wait) {
                world.calls("tickets").contains(["query", "qzx"]) && !world.environments("tickets", "query").isEmpty
                    && !world.environments("tickets", "load").isEmpty
            }, "\(world.calls("tickets"))")
            for kind in ["load", "query"] {
                for environment in world.environments("tickets", kind) {
                    #expect(Self.variable("ALLINONEIME_COMPLETION", in: environment) == kind)
                    #expect(Self.variable("ALLINONEIME_LANGUAGE", in: environment) == "zh", "\(kind)")
                    #expect(Self.variable("ALLINONEIME_PREF_REGION", in: environment) == "ap-test", "\(kind)")
                    #expect(Self.variable("ALLINONEIME_PREF_APITOKEN", in: environment) == "s3cret-token", "\(kind): the password too")
                    #expect((Self.variable("ALLINONEIME_APP", in: environment) ?? "").isEmpty, "\(kind): no app")
                    #expect((Self.variable("ALLINONEIME_QUERY", in: environment) ?? "").isEmpty, "\(kind): no token")
                    #expect(!environment.contains(app), "\(kind): the app's id nowhere")
                    #expect(!environment.contains("qzx") && !environment.contains("TKT-q"), "\(kind): what was typed nowhere")
                }
            }
            #expect(Set(world.directories("tickets")) == [command.directory.path], "\(world.directories("tickets"))")
        }
    }

    /// "Up to 20 s, 20,000 items, 4 MB (the 64 KB output limit of commands doesn't apply to completion runs)." A list of
    /// some 300 KB loads whole (its last item a row), and a query's answer of over 100 KB shows.
    @Test func outputsOver64KBAreRead() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld()
            let padding = String(repeating: "x", count: 80)
            world.list("tickets", (1...3000).map { CompletionItem(match: "TKT-\($0)", title: "Ticket \($0) \(padding)") })
            #expect(world.listSize("tickets") > 4 * 64 * 1024, "\(world.listSize("tickets")) bytes")
            let answer = (1...1000).map { CompletionItem(match: "TKT-zzz\($0)", title: String(repeating: "y", count: 100)) }
            #expect(SuggestionsJSON.list(answer).count > 64 * 1024)
            world.answer("tickets", query: "zzz", answer)
            let command = try world.command("tickets")
            try world.enable("tickets")
            let field = world.field()
            field.type("TKT-2999")
            #expect(field.settle(timeout: Self.wait) { field.shown(["TKT-2999"]) == ["TKT-2999"] }, "\(field.rows.map(\.text))")
            #expect(world.status(command)?.items == 3000, "\(String(describing: world.status(command)))")
            field.type(" TKT-zzz")
            #expect(field.settle(timeout: Self.wait) { field.rows.map(\.text) == (1...5).map { "TKT-zzz\($0)" } }, "\(field.rows.map(\.text))")
        }
    }

    /// What a list may be over.
    enum TooMuch: String, CaseIterable, Sendable {
        /// 20,001 items.
        case items
        /// 4,500 items, over 4 MB of them.
        case bytes
    }

    /// "Up to … 20,000 items, 4 MB": 20,000 items load; a list of more items, or of more bytes, is a failure, as a
    /// plugin's: Settings is told why, and no row shows.
    @Test(arguments: TooMuch.allCases)
    func aListOverTheItemsOrBytesLimitIsAFailure(_ tooMuch: TooMuch) async throws {
        try await inEnglish {
            let full = Self.ticketsWorld(Self.tickets(query: false))
            full.list("tickets", (1...CompletionList.maxItems).map { CompletionItem(match: "TKT-\($0)") })
            let command = try full.command("tickets")
            try full.enable("tickets")
            let fits = full.field()
            fits.type("TKT-19999")
            #expect(fits.settle(timeout: Self.wait) { fits.shown(["TKT-19999"]) == ["TKT-19999"] }, "20,000 items: \(fits.rows.map(\.text))")
            #expect(full.status(command)?.items == CompletionList.maxItems)

            let over = Self.ticketsWorld(Self.tickets(query: false))
            switch tooMuch {
            case .items: over.list("tickets", (1...CompletionList.maxItems + 1).map { CompletionItem(match: "TKT-\($0)") })
            case .bytes: over.list("tickets", (1...4500).map { CompletionItem(match: "TKT-\($0)", title: String(repeating: "x", count: 1000)) })
            }
            if tooMuch == .bytes { #expect(over.listSize("tickets") > CompletionList.maxBytes) }
            let tooLarge = try over.command("tickets")
            try over.enable("tickets")
            let field = over.field()
            field.type("TKT-1")
            #expect(field.settle(timeout: Self.wait) { over.status(tooLarge)?.error?.isEmpty == false },
                    "\(tooMuch): a failure (\(String(describing: over.status(tooLarge))))")
            field.idle(0.3)
            #expect(field.rows.isEmpty, "\(tooMuch): \(field.rows.map(\.text))")
        }
    }

    /// "`query`: … Up to 3 s." A query that takes longer is stopped: it never gets to its end, and what it would have
    /// printed never shows.
    @Test func aQueryIsStoppedAfterThreeSeconds() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld()
            world.answer("tickets", query: "slo", [Self.ticket("TKT-slo1", "Too late")])
            world.delay("tickets", "query", query: "slo", seconds: 4)
            try world.enable("tickets")
            let field = world.field()
            field.type("TKT-slo")
            #expect(field.settle(timeout: Self.wait) { world.events.contains("start tickets query slo") }, "\(world.events)")
            field.idle(5)
            #expect(!world.events.contains("end tickets query slo"), "stopped: \(world.events)")
            #expect(!field.rows.contains { $0.text == "TKT-slo1" }, "\(field.rows.map(\.text))")
        }
    }

    /// "`load`: … Up to 20 s." A list that takes longer is stopped by then at the latest: a failure Settings is told of,
    /// no rows.
    @Test func aListIsStoppedAfterTwentySecondsAtMost() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld(Self.tickets(query: false))
            world.delay("tickets", "load", seconds: 25)
            let command = try world.command("tickets")
            try world.enable("tickets")
            let field = world.field()
            field.type("TKT-1")
            #expect(field.settle(timeout: Self.wait) { world.events.contains("start tickets load") }, "\(world.events)")
            let started = Date()
            #expect(field.settle(timeout: 22) { world.status(command)?.error?.isEmpty == false },
                    "stopped, a failure: \(String(describing: world.status(command)))")
            #expect(Date().timeIntervalSince(started) < 21.5, "within 20 s (\(Date().timeIntervalSince(started)) s)")
            #expect(!world.events.contains("end tickets load"), "\(world.events)")
            field.idle(0.3)
            #expect(field.rows.isEmpty, "\(field.rows.map(\.text))")
        }
    }

    /// "Only one completion program of a bundle runs at a time (a bundle's programs may share state: a cookie file, a
    /// cache)." Two commands of one bundle, each a source whose list takes a while, both wanted at once: one runs to its end
    /// before the other starts, and both lists come.
    @Test func aBundleRunsOneCompletionProgramAtATime() async throws {
        try await inEnglish {
            let world = World()
            world.add("kit/extension.json", #"""
                {"schemaVersion": 1, "name": "kit", "commands": [
                   {"script": "aa.sh", "name": "aa", "completion": {"prefix": "AA-", "list": true}},
                   {"script": "bb.sh", "name": "bb", "completion": {"prefix": "BB-", "list": true}}]}
                """#)
            for name in ["aa", "bb"] {
                world.add("kit/\(name).sh", "#!/bin/bash\n" + world.body(name))
                world.list(name, [CompletionItem(match: name.uppercased() + "-11", title: "One of \(name)")])
                world.delay(name, "load", seconds: 0.8)
            }
            world.reload()
            try world.enable("aa")
            try world.enable("bb")
            let field = world.field()
            field.type("AA-1 BB-1")
            #expect(field.settle(timeout: Self.wait) { world.events.contains("end aa load") && world.events.contains("end bb load") },
                    "\(world.events)")
            #expect(Self.oneAtATime(world.events), "one at a time: \(world.events)")
            #expect(field.settle(timeout: Self.wait) { field.rows.map(\.text) == ["BB-11"] }, "\(field.rows.map(\.text))")
            field.type(" AA-1")
            #expect(field.settle(timeout: Self.wait) { field.rows.map(\.text) == ["AA-11"] }, "\(field.rows.map(\.text))")
        }
    }

    /// "A newer query for the same source cancels the older one, as for plugins." A query still running when the next
    /// token's is asked is stopped (it never gets to its end), and what it would have printed never shows; the newer
    /// one's answer does.
    @Test func aNewerQueryCancelsTheOlderOne() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld()
            world.answer("tickets", query: "abc", [Self.ticket("TKT-abc1", "Late")])
            world.answer("tickets", query: "def", [Self.ticket("TKT-def1", "Current")])
            world.delay("tickets", "query", query: "abc", seconds: 2.5)
            try world.enable("tickets")
            let field = world.field()
            field.type("TKT-abc")
            #expect(field.settle(timeout: Self.wait) { world.events.contains("start tickets query abc") }, "\(world.events)")
            field.type(" TKT-def")
            #expect(field.settle(timeout: Self.wait) { field.shown(["TKT-def1"]) == ["TKT-def1"] }, "\(field.rows.map(\.text))")
            field.idle(3)
            #expect(!world.events.contains("end tickets query abc"), "the older one stopped: \(world.events)")
            #expect(!field.rows.contains { $0.text.contains("TKT-abc1") }, "\(field.rows.map(\.text))")
        }
    }

    // MARK: - Trust

    /// "On by default" (owner 2026-10-25, 0.6.7.2; before, "off until the user turns the source on in Settings →
    /// Commands"): with suggestions running (another source on), the source of a command of the user's own shows its rows
    /// as it loads, nothing turned on; turned off in Settings (`SuggestionsSettings.off`), it shows no rows and its program
    /// doesn't run again (no lookup), the other source still on.
    @Test func aSourceIsOnUntilTurnedOff() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld()
            try world.suggestions.github()
            let field = world.field()
            field.type("TKT-10")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.ticketMatches) == ["TKT-101", "TKT-102"] },
                    "on as it loads: \(field.rows.map(\.text))")

            world.suggestions.switches.off.append(CompletionSourceKey(extension: try world.command("tickets")))
            field.host.send(.configChanged)
            let calls = world.calls("tickets").count
            field.type(" TKT-101")
            field.idle(1)
            #expect(field.rows.isEmpty, "turned off: \(field.rows.map(\.text))")
            #expect(world.calls("tickets").count == calls, "nothing run: \(world.calls("tickets"))")
            field.type(" #7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "the plugin's source is on: \(field.issuesShown)")
        }
    }

    /// What an update of the command changes.
    enum Change: String, CaseIterable, Sendable {
        case script, prefix, query, compare
        /// Another file of its bundle, one its script could use (lib/common.sh).
        case lib
    }

    /// The extension source "desk" is installed from in these tests, its updates not marked trusted.
    static let deskSource = ExtensionSource(url: "git@git.example.com:team/desk.git")

    /// "When an extension source updates the command, a change to its script file, `prefix`, `query` or `compare` turns the
    /// source off again (said once, as for plugins)"; since 2026-10-24 (owner): from an extension source whose updates
    /// aren't trusted, a change to any file of its bundle (lib/ too) or to those terms. The command as an update leaves it
    /// (its script file, its bundle entry's declaration, or a file in lib/ changed): the approval is reported lapsed once,
    /// the source shows no rows and runs nothing until it is turned on again; then its rows.
    @Test(arguments: Change.allCases)
    func aChangeToItsScriptPrefixQueryOrCompareTurnsItOff(_ change: Change) async throws {
        try await inEnglish {
            let world = Self.deskWorld(from: Self.deskSource)
            let desk = world.deskFolder
            world.list("tickets", Self.ticketList + [Self.ticket("TIX-101", "Under another prefix")])
            let approval = try world.enable("tickets")
            let warm = world.field()
            warm.type("TKT-10")
            #expect(warm.settle(timeout: Self.wait) { warm.shown(Self.ticketMatches) == ["TKT-101", "TKT-102"] }, "\(warm.rows.map(\.text))")
            #expect(world.reportedLapsed.isEmpty)

            switch change {
            case .script: world.add(desk + "/tickets.sh", "#!/bin/bash\n# fixed upstream\n" + world.body("tickets"))
            case .prefix: world.add(desk + "/extension.json", Self.desk(Self.tickets(prefix: "TIX-")))
            case .query: world.add(desk + "/extension.json", Self.desk(Self.tickets(query: false)))
            case .compare: world.add(desk + "/extension.json", Self.desk(Self.tickets(compare: "exact")))
            case .lib: world.add(desk + "/lib/common.sh", "# fixed upstream\n")
            }
            world.reload()
            let calls = world.calls("tickets").count
            let probe = change == .prefix ? "TIX-101" : "TKT-101"
            let field = world.field(app: "com.apple.TextEdit")
            field.type(probe)
            field.idle(1)
            #expect(field.rows.isEmpty, "\(change): off (\(field.rows.map(\.text)))")
            #expect(world.calls("tickets").count == calls, "\(change): nothing run (\(world.calls("tickets")))")
            #expect(world.reportedLapsed == [approval], "\(change): said (\(world.reportedLapsed))")
            let again = world.field(app: "com.apple.mail")
            again.type(probe)
            again.idle(0.5)
            #expect(again.rows.isEmpty, "\(change): still off")
            #expect(world.reportedLapsed == [approval], "\(change): said once (\(world.reportedLapsed))")

            try world.enable("tickets")
            field.host.send(.configChanged)
            field.type(" " + probe)
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.ticketMatches).contains(probe) },
                    "\(change): turned on again (\(field.rows.map(\.text)))")
        }
    }

    /// Before 2026-10-24 the four were what turned it off, wherever it came from; now (owner) an extension of the user's own
    /// (a folder of theirs, not an extension source's) is trusted: a change to it, here how often the list is refreshed,
    /// what a row puts in and a file in lib/, keeps the source on (nothing said), with what it says now.
    @Test func aChangeToAnythingElseKeepsItOn() async throws {
        try await inEnglish {
            let world = Self.deskWorld()
            try world.enable("tickets")
            let warm = world.field()
            warm.type("TKT-10")
            #expect(warm.settle(timeout: Self.wait) { warm.shown(Self.ticketMatches) == ["TKT-101", "TKT-102"] }, "\(warm.rows.map(\.text))")

            world.add("desk/extension.json", Self.desk(Self.tickets(refresh: "2h", insert: #"{"default": ["{arg} {title}", "{arg}"]}"#)))
            world.add("desk/lib/common.sh", "# shared\n")
            world.reload()
            let field = world.field(app: "com.apple.TextEdit")
            field.type("TKT-10")
            #expect(field.settle(timeout: Self.wait) { field.shown(Self.ticketMatches) == ["TKT-101", "TKT-102"] }, "still on: \(field.rows.map(\.text))")
            #expect(world.reportedLapsed.isEmpty, "\(world.reportedLapsed)")
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "TKT-101 Fix login", "its insert as it is now: \(field.document)")
        }
    }

    /// Where the field is secret.
    enum Secure: String, CaseIterable, Sendable {
        /// Secure input on in the field's app (the Mac tells it with each key).
        case secureInput
        /// A password field (Windows tells it with the focus).
        case passwordField
        /// Secure input on anywhere (a password prompt, the lock screen).
        case anywhere
    }

    /// "Secure input and password fields: no rows, nothing run for them, as for every source." Nothing typed there is
    /// looked up (no query run), no rows; with secure input on anywhere nothing runs at all. Elsewhere, the same source's
    /// rows.
    @Test(arguments: Secure.allCases)
    func nothingRunsForSecureInputOrPasswordFields(_ secure: Secure) async throws {
        try await inEnglish {
            let world = Self.ticketsWorld()
            try world.enable("tickets")
            world.suggestions.secureInputAnywhere = secure == .anywhere
            let field = world.field(passwordField: secure == .passwordField)
            field.host.secure = secure == .secureInput
            field.type("TKT-101")
            field.idle(1)
            #expect(field.rows.isEmpty, "\(secure): \(field.rows.map(\.text))")
            #expect(!world.calls("tickets").contains { $0.first == "query" }, "\(secure): nothing typed looked up (\(world.calls("tickets")))")
            if secure == .anywhere { #expect(world.calls("tickets").isEmpty, "nothing run: \(world.calls("tickets"))") }

            world.suggestions.secureInputAnywhere = false
            let open = world.field(app: "com.apple.TextEdit")
            open.type("TKT-10")
            #expect(open.settle(timeout: Self.wait) { open.shown(Self.ticketMatches) == ["TKT-101", "TKT-102"] }, "\(open.rows.map(\.text))")
        }
    }

    // MARK: - Insert

    /// "The same as a plugin's source: the global and per-app Insert choices apply to it; its own `insert` is the
    /// Default." Its own templates per class of app until a choice is made; With title everywhere; Markdown link in one
    /// app, a link in place of the token there.
    @Test func theInsertChoicesApplyToItsRows() async throws {
        try await inEnglish {
            let world = Self.ticketsWorld(Self.tickets(query: false, insert: #"{"default": "{arg}", "chat": ["{arg} {url}", "{arg}"], "terminal": "{match}"}"#))
            try world.enable("tickets")

            /// What the first row for "TKT-10" puts in, in `app`.
            func put(in app: String) -> String {
                let field = world.field(app: app)
                field.type("TKT-10")
                #expect(field.settle(timeout: Self.wait) { field.shown(Self.ticketMatches) == ["TKT-101", "TKT-102"] }, "\(app): \(field.rows.map(\.text))")
                #expect(field.press(SuggestionKeys.enter))
                return field.document
            }
            #expect(put(in: SuggestionsApps.editor) == "TKT-101", "its own Default")
            #expect(put(in: SuggestionsApps.slack) == "TKT-101 https://tickets.example.com/TKT-101", "its own, in a chat app")
            world.suggestions.switches.insert = .title
            #expect(put(in: SuggestionsApps.editor) == "TKT-101 Fix login", "With title everywhere")
            #expect(put(in: SuggestionsApps.slack) == "TKT-101 Fix login")
            world.suggestions.switches.appInserts = [SuggestionsApps.editor: .markdownLink]
            #expect(put(in: SuggestionsApps.editor) == "[Fix login](https://tickets.example.com/TKT-101)", "Markdown link in its app")
            #expect(put(in: "com.apple.TextEdit") == "TKT-101 Fix login", "With title elsewhere")
        }
    }
}
