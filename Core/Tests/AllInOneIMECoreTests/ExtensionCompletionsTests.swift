import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Script extensions as completion sources (0.6.7.1 §2): a command's declaration (a script's `@allinoneime.completion`
/// line, a bundle entry's `"completion"` over it; refused on its own, with its reason, the command still loading), its
/// trust (off until turned on; a change to its script, prefix, query or compare turns it off again), its program run as
/// its commands run with `ALLINONEIME_COMPLETION` (its list with no arguments, a query with the text after the prefix as
/// its one argument; nothing of the field in its environment; 4 MB of output, not a command's 64 KB; one program of a
/// bundle at a time), and its rows through a text field's session as a plugin's. The programs are real sh scripts in a
/// temporary folder; the rig is the acceptance tests' (Acceptance/SuggestionsAcceptanceTests.swift).
@Suite(.serialized, SuggestionsOneAtATime())
struct ExtensionCompletionsTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// A folder of extensions the test writes (and removes): single scripts and bundles.
    final class Extensions: @unchecked Sendable {
        let folder: URL

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("extension-completions-\(UUID().uuidString)",
                                                                                 isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        /// An executable sh script at `path` (in the folder): its metadata lines, then `body`.
        @discardableResult
        func script(_ path: String, metadata: [String], body: String) throws -> URL {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = (["#!/bin/sh"] + metadata.map { "# @allinoneime." + $0 } + [body]).joined(separator: "\n") + "\n"
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }

        func write(_ path: String, _ text: String) throws {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func read(_ path: String) -> String? { try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8) }

        /// What the folder holds, read as the input method reads it.
        var index: ExtensionIndex { ExtensionStore.load([ExtensionStore.Folder(path: folder.path, found: false)]) }

        func command(_ name: String) -> ScriptCommand? { index.commands.first { $0.name == name } }
    }

    /// A ticket list's body: each call noted in calls.log (what it was asked, its arguments), the protocol's variables it
    /// was given in env-<function>.txt; its list from list.json, a query's answer for its argument.
    static let ticketsBody = #"""
        dir="$(cd "$(dirname "$0")" && pwd)"
        printf '%s|%s|%s\n' "$ALLINONEIME_COMPLETION" "$#" "$*" >> "$dir/calls.log"
        env | grep '^ALLINONEIME_' | sort > "$dir/env-$ALLINONEIME_COMPLETION.txt"
        if [ "$ALLINONEIME_COMPLETION" = query ]; then
          printf '{"items": [{"match": "TCK-%s9", "title": "Found", "variables": {"title": "Found %s", "url": "https://tickets.example.com/TCK-%s9"}}]}' "$1" "$1" "$1"
        else
          cat "$dir/list.json"
        fi
        """#

    static let listJSON = #"""
        {"items": [
          {"match": "TCK-12", "title": "Fix login", "variables": {"title": "Fix login", "url": "https://tickets.example.com/TCK-12"}},
          {"match": "TCK-17", "title": "Dark mode", "variables": {"title": "Dark mode"}},
          {"match": "TCK 99", "title": "A space in the match"}
        ]}
        """#

    static func declaration(_ fields: String = "") -> String {
        #"completion {"prefix": "TCK-", "list": true, "refresh": "1h", "insert": {"default": ["[{title}]({url})", "{arg}"]}"#
            + fields + "}"
    }

    /// A single script `tickets.sh` declaring the source (`declaration`), and its list.
    static func tickets(in extensions: Extensions, declaration: String = declaration()) throws -> ScriptCommand {
        try extensions.script("tickets.sh", metadata: ["schemaVersion 1", "title Tickets", declaration], body: ticketsBody)
        try extensions.write("list.json", listJSON)
        return try #require(extensions.command("tickets"))
    }

    /// A world whose fields see `extensions`' commands, those of `on` turned on as Settings turns them on.
    static func world(_ extensions: Extensions, on: [ScriptCommand]) -> (SuggestionsWorld, (inout SessionServices) -> Void) {
        world({ extensions.index }, on: on)
    }

    /// A world whose fields see the commands of `index`, those of `on` turned on.
    static func world(_ index: @escaping @Sendable () -> ExtensionIndex, on: [ScriptCommand])
        -> (SuggestionsWorld, (inout SessionServices) -> Void) {
        let world = SuggestionsWorld()
        for command in on {
            guard case let .success(source)? = command.completion else { continue }
            world.config.setCompletionSource(source, of: command, enabled: true)
        }
        world.switches = world.config.suggestionsSettings()
        let adjust: (inout SessionServices) -> Void = { services in
            services.loadExtensions = { _, _ in index() }
            services.extensionPreferences = { bundle, _ in bundle.values(["token": "s3cret"]) }
        }
        return (world, adjust)
    }

    // MARK: - The declaration

    /// A single script's line: the source with a plugin's keys and defaults, its name and title the command's.
    @Test func aScriptsLineDeclaresItsSource() throws {
        let extensions = try Extensions()
        let command = try Self.tickets(in: extensions, declaration: Self.declaration(#", "query": true, "queryMinChars": 2"#))
        guard case let .success(source)? = command.completion else { Issue.record("\(String(describing: command.completion))"); return }
        #expect(source.name == "tickets" && source.title.en == "Tickets")
        #expect(source.prefix == "TCK-" && source.minChars == 1 && source.compare == .prefix && source.list && source.refresh == 3600)
        #expect(source.query && source.queryMinChars == 2)
        #expect(source.insert.default == .templates(["[{title}]({url})", "{arg}"]))
        #expect(command.input == .required && command.output == .insert, "still a command as before")
    }

    /// A bundle entry's `"completion"` is used over its script's own line; a name or a title it gives is the command's.
    @Test func aBundleEntryIsUsedOverTheLine() throws {
        let extensions = try Extensions()
        try extensions.script("team/issues.sh", metadata: ["schemaVersion 1", ##"completion {"prefix": "#", "list": true}"##],
                              body: "echo")
        try extensions.write("team/extension.json", #"""
            { "schemaVersion": 1, "name": "team", "title": "Team",
              "commands": [{ "script": "issues.sh", "title": "Team issues",
                             "completion": { "name": "other", "title": "Other", "prefix": "ISS-", "list": true, "query": true } }] }
            """#)
        let command = try #require(extensions.command("issues"))
        guard case let .success(source)? = command.completion else { Issue.record("\(String(describing: command.completion))"); return }
        #expect(source.prefix == "ISS-" && source.query, "the entry's")
        #expect(source.name == "issues" && source.title.en == "Team issues", "the command's")
        #expect(command.completionTurn == "bundle:team" && CompletionSourceKey(extension: command).source == "team/issues")
    }

    /// A declaration that breaks a plugin's rules is refused on its own, with the reason a plugin's gets; the command loads.
    @Test(arguments: [
        (#"{"query": true, "list": false}"#, "a completion without a prefix can't query"),
        (#"{"compare": "prefix", "list": true}"#, "a completion without a prefix must compare exact"),
        (##"{"prefix": "#", "list": true, "insert": {"default": "{arg"}}"##, "insert.default isn't a template"),
        (#"{"prefix": "@x", "list": true}"#, "the prefix must be"),
        ("[1, 2]", "completion must be a JSON object"),
        ("{not json", "completion must be a JSON object"),
    ])
    func aBadDeclarationIsRefusedAndTheCommandLoads(_ json: String, _ reason: String) throws {
        let extensions = try Extensions()
        let command = try Self.tickets(in: extensions, declaration: "completion " + json)
        guard case let .failure(refused)? = command.completion else { Issue.record("not refused: \(json)"); return }
        #expect(refused.reason.hasPrefix(reason) && refused.name == "tickets", "\(refused.reason)")
        #expect(extensions.index.skipped.isEmpty)
    }

    /// No line, no source; a Raycast script's keys never declare one.
    @Test func noLineNoSource() throws {
        let extensions = try Extensions()
        try extensions.script("plain.sh", metadata: ["schemaVersion 1"], body: "echo")
        #expect(try #require(extensions.command("plain")).completion == nil)
    }

    /// The public example (Examples/extensions/bookmarks): its command `@bm` declares a source in its bundle's entry;
    /// turned on, `bm.sw` shows Swift's bookmark, and Tab puts in a Markdown link of it in the token's place.
    @Test func theBookmarksExampleCompletes() async throws {
        try await inEnglish {
            let index = ExtensionStore.load([.init(path: ExtensionExamplesTests.examples.path, found: false)])
            let bm = try #require(index.commands.first { $0.name == "bm" })
            guard case let .success(source)? = bm.completion else { Issue.record("\(String(describing: bm.completion))"); return }
            #expect(source.prefix == "bm." && source.list && !source.query && source.insert.terminal == .off)
            let (world, adjust) = Self.world({ index }, on: [bm])
            let field = world.field(adjust)
            field.host.document = "See "
            field.type("bm.sw")
            #expect(field.settle(timeout: 15) { field.rows.map(\.text) == ["bm.swift"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "See [Swift](https://www.swift.org)", "\(field.document)")
        }
    }

    // MARK: - Trust

    /// Off until turned on: a declared source runs nothing and shows no rows; turned on, its list's rows (a bad item
    /// dropped), a row put in as the source's templates say (here a Markdown link, in the token's place).
    @Test func offUntilTurnedOn() async throws {
        try await inEnglish {
            let extensions = try Extensions()
            let command = try Self.tickets(in: extensions)
            let (off, adjust) = Self.world(extensions, on: [])
            let field = off.field(adjust)
            field.type("TCK-1")
            field.idle()
            #expect(field.rows.isEmpty && extensions.read("calls.log") == nil, "nothing runs")

            let (world, adjustOn) = Self.world(extensions, on: [command])
            #expect(world.config.completionSources.first?.plugin == CompletionSourceKey.scriptExtensions)
            let on = world.field(adjustOn)
            on.type("TCK-1")
            #expect(on.settle(timeout: 15) { on.rows.map(\.text) == ["TCK-12", "TCK-17"] }, "\(on.rows.map(\.text))")
            #expect(on.footer.contains("Tickets"), "\(on.footer)")
            #expect(on.press(SuggestionKeys.tab))
            #expect(on.document == "[Fix login](https://tickets.example.com/TCK-12)", "\(on.document)")
            #expect(extensions.read("calls.log") == "load|0|\n", "its list, with no arguments")
        }
    }

    /// What its switch approved: its script, query, prefix and compare. A change to any of them turns it off (said once:
    /// the approval marked lapsed); its refresh, minChars, queryMinChars or insert don't (a bundle's entry: a single
    /// script's line is its script).
    @Test func aChangeToItsScriptPrefixQueryOrCompareTurnsItOff() throws {
        let extensions = try Extensions()
        try extensions.script("crm/contacts.sh", metadata: [], body: Self.ticketsBody)
        func bundle(_ completion: String) throws -> ScriptCommand {
            try extensions.write("crm/extension.json", #"{ "schemaVersion": 1, "name": "crm", "commands": [{ "script": "contacts.sh", "completion": "#
                                 + completion + " }] }")
            return try #require(extensions.command("contacts"))
        }
        let declared = #"{"prefix": "TCK-", "list": true"#
        let command = try bundle(declared + "}")
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        let approval = try #require(CompletionSourceApproval(enabling: source, of: command))
        #expect(approval.holds(for: source, of: command) && approval.hosts.isEmpty)

        for change in [#", "minChars": 3}"#, #", "queryMinChars": 5}"#, #", "refresh": "1d"}"#, #", "insert": {"default": "{match}"}}"#] {
            let other = try bundle(declared + change)
            guard case let .success(changed)? = other.completion else { Issue.record("\(change)"); continue }
            #expect(approval.holds(for: changed, of: other), "\(change)")
            #expect(CompletionSourceApproval.lapsed([approval], extensions: [other]).isEmpty, "\(change)")
        }
        for change in [#", "query": true}"#, #", "compare": "exact"}"#] {
            let other = try bundle(declared + change)
            guard case let .success(changed)? = other.completion else { Issue.record("\(change)"); continue }
            #expect(!approval.holds(for: changed, of: other), "\(change)")
            #expect(CompletionSourceApproval.lapsed([approval], extensions: [other]) == [approval], "\(change)")
        }
        let prefixed = try bundle(#"{"prefix": "TIX-", "list": true}"#)
        guard case let .success(newPrefix)? = prefixed.completion else { Issue.record("no source with another prefix"); return }
        #expect(!approval.holds(for: newPrefix, of: prefixed))
        // Its script itself.
        let same = try bundle(declared + "}")
        try extensions.script("crm/contacts.sh", metadata: [], body: Self.ticketsBody + "\n# 2")
        #expect(!approval.holds(for: source, of: same))
        #expect(CompletionSourceApproval.lapsed([approval], extensions: [same]) == [approval])
        var marked = approval
        marked.lapsed = true
        #expect(CompletionSourceApproval.lapsed([marked], extensions: [same]).isEmpty, "said once")
        #expect(CompletionSourceApproval.lapsed([approval], extensions: []).isEmpty, "a command not there doesn't lapse")
        // A single script's line is part of its script: any change to it is one.
        let single = try Self.tickets(in: extensions)
        guard case let .success(line)? = single.completion else { Issue.record("no line"); return }
        let lineApproval = try #require(CompletionSourceApproval(enabling: line, of: single))
        let edited = try Self.tickets(in: extensions, declaration: Self.declaration(#", "minChars": 2"#))
        guard case let .success(editedLine)? = edited.completion else { Issue.record("no edited line"); return }
        #expect(!lineApproval.holds(for: editedLine, of: edited))
    }

    /// Through a field: a script changed since its source was turned on shows no rows, runs nothing, and its approval is
    /// marked lapsed as the field takes the focus.
    @Test func aChangedScriptRunsNothing() async throws {
        try await inEnglish {
            let extensions = try Extensions()
            let command = try Self.tickets(in: extensions)
            let (world, adjust) = Self.world(extensions, on: [command])
            try extensions.script("tickets.sh", metadata: ["schemaVersion 1", "title Tickets", Self.declaration()],
                                  body: Self.ticketsBody + "\n# changed")
            let lapsed = Locked<[CompletionSourceApproval]>(initialState: [])
            let field = world.field { services in
                adjust(&services)
                services.suggestions.approvalsLapsed = { found in lapsed.withLock { $0 += found } }
            }
            field.type("TCK-1")
            field.idle()
            #expect(field.rows.isEmpty && extensions.read("calls.log") == nil)
            #expect(lapsed.withLock { $0 } == world.config.completionSources)
        }
    }

    // MARK: - The run protocol

    /// Its list: `ALLINONEIME_COMPLETION=load`, no arguments; its query: `query`, the text after the prefix its one
    /// argument. The environment: the interface language, its bundle's preferences; nothing of the field (no app, no
    /// query, no input language).
    @Test func theProgramsEnvironmentAndArguments() async throws {
        try await inEnglish {
            let extensions = try Extensions()
            try extensions.script("crm/contacts.sh", metadata: [], body: Self.ticketsBody)
            try extensions.write("crm/list.json", Self.listJSON)
            try extensions.write("crm/extension.json", #"""
                { "schemaVersion": 1, "name": "crm", "title": "CRM",
                  "preferences": [{ "name": "token", "type": "password", "title": "Token" }, { "name": "region", "type": "textfield", "default": "eu" }],
                  "commands": [{ "script": "contacts.sh", "title": "Contacts",
                                 "completion": { "prefix": "TCK-", "list": true, "query": true, "queryMinChars": 2 } }] }
                """#)
            let command = try #require(extensions.command("contacts"))
            let (world, adjust) = Self.world(extensions, on: [command])
            let field = world.field(app: SuggestionsApps.slack, adjust)
            field.type("TCK-34")
            #expect(field.settle(timeout: 15) { field.rows.map(\.text).contains("TCK-349") }, "\(field.rows.map(\.text))")
            let calls = (extensions.read("crm/calls.log") ?? "").split(separator: "\n").map(String.init)
            #expect(calls.contains("load|0|") && calls.contains("query|1|34"), "\(calls)")
            for function in ["load", "query"] {
                let env = extensions.read("crm/env-\(function).txt") ?? ""
                #expect(env.contains("ALLINONEIME_COMPLETION=\(function)\n") && env.contains("ALLINONEIME_LANGUAGE=en\n"), "\(env)")
                #expect(env.contains("ALLINONEIME_PREF_TOKEN=s3cret\n") && env.contains("ALLINONEIME_PREF_REGION=eu\n"), "\(env)")
                #expect(!env.contains("ALLINONEIME_APP") && !env.contains("ALLINONEIME_QUERY") && !env.contains("ALLINONEIME_INPUT_LANGUAGE"),
                        "\(env)")
                #expect(!env.contains("TCK-34") && !env.contains("slack"), "nothing of the field: \(env)")
            }
        }
    }

    /// A list larger than a command's 64 KB is read whole (its limit is a plugin's: 4 MB, 20,000 items).
    @Test func aListLargerThanACommandsOutputLoads() async throws {
        try await inEnglish {
            let extensions = try Extensions()
            let command = try Self.tickets(in: extensions)
            let items = (1...3000).map { #"{"match": "TCK-\#($0)", "title": "Ticket number \#($0) with a long enough title"}"# }
            try extensions.write("list.json", #"{"items": ["# + items.joined(separator: ",") + "]}")
            #expect((extensions.read("list.json")?.utf8.count ?? 0) > 64 * 1024)
            let (world, adjust) = Self.world(extensions, on: [command])
            let field = world.field(adjust)
            field.type("TCK-2999")
            #expect(field.settle(timeout: 15) { world.lastStatus?.items == 3000 }, "\(String(describing: world.lastStatus))")
            #expect(field.settle { field.rows.map(\.text) == ["TCK-2999"] }, "\(field.rows.map(\.text))")
        }
    }

    /// A required preference of its bundle not set: nothing runs, its status says what to set.
    @Test func aRequiredPreferenceNotSetRunsNothing() async throws {
        try await inEnglish {
            let extensions = try Extensions()
            try extensions.script("crm/contacts.sh", metadata: [], body: Self.ticketsBody)
            try extensions.write("crm/extension.json", #"""
                { "schemaVersion": 1, "name": "crm", "preferences": [{ "name": "account", "type": "textfield", "title": "Account", "required": true }],
                  "commands": [{ "script": "contacts.sh", "completion": { "prefix": "TCK-", "list": true } }] }
                """#)
            let command = try #require(extensions.command("contacts"))
            let (world, adjust) = Self.world(extensions, on: [command])
            let field = world.field(adjust)
            field.type("TCK-1")
            #expect(field.settle(timeout: 10) { world.lastStatus?.error != nil }, "\(String(describing: world.lastStatus))")
            #expect(world.lastStatus?.error == "Set “Account” in the settings first")
            #expect(extensions.read("crm/calls.log") == nil)
        }
    }

    /// The calls the session makes: a list within 20 seconds, a query within 3; the environment it is given; the script
    /// approved.
    @Test func theCallsLimits() async throws {
        try await inEnglish {
            let extensions = try Extensions()
            let command = try Self.tickets(in: extensions, declaration: Self.declaration(#", "query": true, "queryMinChars": 1"#))
            let runtime = RecordingRuntime()
            let (world, adjust) = Self.world(extensions, on: [command])
            let field = world.field { services in
                adjust(&services)
                services.suggestions.extensionRuntime = runtime
            }
            field.type("TCK-5")
            #expect(field.settle { runtime.calls.count >= 2 }, "\(runtime.calls.map(\.text))")
            let calls = runtime.calls
            let load = try #require(calls.first { $0.text == nil }), query = try #require(calls.first { $0.text != nil })
            #expect(load.call.timeout == 20 && query.call.timeout == 3 && query.text == "5")
            #expect(load.call.environment["ALLINONEIME_COMPLETION"] == "load" && query.call.environment["ALLINONEIME_COMPLETION"] == "query")
            #expect(load.call.scriptSHA256 == PluginStore.sha256(of: command.file))
        }
    }

    /// Records the calls, answers none.
    final class RecordingRuntime: ExtensionCompletionRuntime, @unchecked Sendable {
        private let recorded = Locked<[(call: ExtensionCompletionCall, text: String?)]>(initialState: [])
        var calls: [(call: ExtensionCompletionCall, text: String?)] { recorded.withLock { $0 } }

        func load(_ call: ExtensionCompletionCall) async throws -> Data {
            recorded.withLock { $0.append((call, nil)) }
            return Data(#"{"items": []}"#.utf8)
        }

        func query(_ text: String, _ call: ExtensionCompletionCall) async throws -> Data {
            recorded.withLock { $0.append((call, text)) }
            return Data(#"{"items": []}"#.utf8)
        }
    }

    // MARK: - The runner

    /// One program of a bundle at a time: a second waits until the first is done; another bundle's runs meanwhile.
    @Test func oneProgramOfABundleAtATime() async throws {
        let extensions = try Extensions()
        // Each notes when it starts and ends; the first takes a while.
        let body = #"""
            dir="$(cd "$(dirname "$0")" && pwd)"
            echo "start $(basename "$0")" >> "$dir/../order.log"
            [ "$(basename "$0")" = slow.sh ] && sleep 0.6
            echo "end $(basename "$0")" >> "$dir/../order.log"
            echo '{"items": []}'
            """#
        for path in ["a/slow.sh", "a/quick.sh", "b/other.sh"] { try extensions.script(path, metadata: [], body: body) }
        try extensions.write("a/extension.json", #"""
            { "schemaVersion": 1, "name": "a", "commands": [{ "script": "slow.sh", "completion": {"prefix": "A-", "list": true} },
                                                             { "script": "quick.sh", "completion": {"prefix": "B-", "list": true} }] }
            """#)
        try extensions.write("b/extension.json", #"""
            { "schemaVersion": 1, "name": "b", "commands": [{ "script": "other.sh", "completion": {"prefix": "C-", "list": true} }] }
            """#)
        let slow = try #require(extensions.command("slow")), quick = try #require(extensions.command("quick"))
        let other = try #require(extensions.command("other"))
        func call(_ command: ScriptCommand) -> ExtensionCompletionCall {
            ExtensionCompletionCall(command: command, environment: ProcessInfo.processInfo.environment, timeout: 10,
                                    scriptSHA256: PluginStore.sha256(of: command.file))
        }
        let runner = ExtensionCompletionRunner()
        async let first = runner.load(call(slow))
        try await Task.sleep(nanoseconds: 200_000_000)
        async let second = runner.load(call(quick))
        async let third = runner.load(call(other))
        _ = try await (first, second, third)
        let order = (extensions.read("order.log") ?? "").split(separator: "\n").map(String.init)
        let (endSlow, startQuick) = (order.firstIndex(of: "end slow.sh"), order.firstIndex(of: "start quick.sh"))
        #expect(endSlow != nil && startQuick != nil && endSlow! < startQuick!, "\(order)")
        #expect(order.firstIndex(of: "end other.sh")! < endSlow!, "another bundle's runs meanwhile: \(order)")
    }

    /// One waiting its turn that is cancelled (a newer query) never runs; the script approved only runs.
    @Test func aCancelledCallLeavesTheLineAndAChangedScriptNeverRuns() async throws {
        let extensions = try Extensions()
        let body = #"""
            dir="$(cd "$(dirname "$0")" && pwd)"
            echo "$(basename "$0")" >> "$dir/../ran.log"
            [ "$(basename "$0")" = slow.sh ] && sleep 0.6
            echo '{"items": []}'
            """#
        for path in ["a/slow.sh", "a/quick.sh"] { try extensions.script(path, metadata: [], body: body) }
        try extensions.write("a/extension.json", #"""
            { "schemaVersion": 1, "name": "a", "commands": [{ "script": "slow.sh", "completion": {"prefix": "A-", "list": true} },
                                                             { "script": "quick.sh", "completion": {"prefix": "B-", "list": true} }] }
            """#)
        let slow = try #require(extensions.command("slow")), quick = try #require(extensions.command("quick"))
        let runner = ExtensionCompletionRunner()
        func call(_ command: ScriptCommand, sha: String? = nil) -> ExtensionCompletionCall {
            ExtensionCompletionCall(command: command, environment: ProcessInfo.processInfo.environment, timeout: 10,
                                    scriptSHA256: sha ?? PluginStore.sha256(of: command.file))
        }
        let first = Task { try await runner.load(call(slow)) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let waiting = Task { try await runner.load(call(quick)) }
        try await Task.sleep(nanoseconds: 100_000_000)
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        _ = try await first.value
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(extensions.read("ran.log") == "slow.sh\n")
        await #expect(throws: ExtensionCompletionError.scriptChanged) { try await runner.load(call(quick, sha: String(repeating: "0", count: 64))) }
        #expect(extensions.read("ran.log") == "slow.sh\n")
    }

    // MARK: - What is kept

    /// Its list's file in the cache folder is named by its command's id's digest: kept while it is on, deleted once off.
    @Test func itsCacheFileGoesWithIt() throws {
        let key = CompletionSourceKey(extensionCommand: "~/.config/allinoneime/extensions/tickets.sh")
        #expect(key.isScriptExtension && key.fileName.hasPrefix("script-extensions.") && key.fileName.count == "script-extensions.".count + 16 + 5)
        #expect(CompletionSourceKey.isCacheFile(key.fileName) && CompletionSourceKey(fileName: key.fileName) == nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("extension-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = CompletionSourceKey(extensionCommand: "team/issues")
        for name in [key.fileName, other.fileName, "notes.txt"] { try Data("{}".utf8).write(to: folder.appendingPathComponent(name)) }
        let store = SuggestionsStore()
        store.prune(keeping: [key], folder: folder)
        let done = DispatchSemaphore(value: 0)
        SuggestionsStore.disk.async { done.signal() }
        done.wait()
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == [key.fileName, "notes.txt"])
    }

    // MARK: - Settings

    /// The settings document has its switch under the command (what it does, off until turned on), or why it is refused.
    @Test func theSettingsDocumentHasItsSwitch() async throws {
        let extensions = try Extensions()
        let command = try Self.tickets(in: extensions, declaration: Self.declaration(#", "query": true"#))
        try extensions.script("bad.sh", metadata: ["schemaVersion 1", #"completion {"query": true}"#], body: "echo")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("extension-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"extensionFolders": ["\#(extensions.folder.path)"]}"#.utf8).write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac,
                                      library: PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true)),
                                      secrets: .inMemory())
        try await withInterfaceLanguage("en") {
            let field = try #require(service.document().field("extensions.completion." + command.id))
            #expect(field.kind == .toggle && field.value == .bool(false) && field.label == "Suggestions", "\(field)")
            #expect(field.help?.contains("Runs this script in the background") == true && field.help?.contains("after TCK-") == true,
                    "\(field.help ?? "")")
            #expect((try? service.set(field.id, to: .bool(true)).get()) != nil)
            let saved = try Config.load(from: url)
            #expect(saved.completionSources.map(\.source) == [command.id] && saved.completionSources.first?.query == true)
            #expect(service.document().field(field.id)?.value == .bool(true))
            let bad = try #require(extensions.command("bad"))
            let refused = try #require(service.document().field("extensions.completion.refused." + bad.id))
            #expect(refused.help?.contains("can't query") == true, "\(refused.help ?? "")")
        }
    }
}
