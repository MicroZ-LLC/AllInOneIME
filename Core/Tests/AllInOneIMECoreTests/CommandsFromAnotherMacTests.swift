import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A custom `suggestions` command that came from another Mac through iCloud runs nothing on this Mac until the user
/// confirms it here once (spec Suggestions v1, decision 26): sync marks it with its program (`argv`) as it comes
/// (`Config.unconfirmedCommands`, this Mac's own, never synced); Settings → Custom Commands says it's from another Mac
/// with the program it would run, and Allow confirms that program; an edit of its program on another Mac asks again; a
/// command made or edited on this Mac is confirmed by that. Two Macs share a temporary "iCloud Drive" (`SyncRig`); a
/// field of the second runs the command's program through a stand-in (`Programs`): no program runs.
@Suite(.serialized, SuggestionsOneAtATime())
struct CommandsFromAnotherMacTests {
    let t0 = SyncRig.t0
    func t(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// Stands in for running a command's program: each run noted (its argv, and the query's text), a list of two
    /// issues printed.
    final class Programs: CommandCompletionRuntime, @unchecked Sendable {
        struct Run: Equatable {
            var argv: [String]
            var query: String?
        }

        private let runs = Locked<[Run]>(initialState: [])
        var all: [Run] { runs.withLock { $0 } }

        func list(_ command: CustomCommand) async throws -> Data {
            runs.withLock { $0.append(Run(argv: command.argv ?? [], query: nil)) }
            return Data("JIRA-12\tFix login\nJIRA-17\tDark mode\n".utf8)
        }

        func query(_ text: String, _ command: CustomCommand) async throws -> Data {
            runs.withLock { $0.append(Run(argv: command.argv ?? [], query: text)) }
            return Data("JIRA-\(text)9\tFound\n".utf8)
        }
    }

    static let program = ["/Users/me/bin/jira-list"]

    static func jira(_ argv: [String] = program, summary: String = "Jira issues") -> CustomCommand {
        CustomCommand(name: "jira", type: .suggestions, summary: summary, argv: argv, prefix: "JIRA-")
    }

    /// A field of a Mac whose settings are `config` (as the input method reads them), its commands' programs run by
    /// `programs`.
    static func field(_ config: Config, _ programs: Programs, world: SuggestionsWorld? = nil) -> SuggestionsField {
        let world = world ?? SuggestionsWorld()
        world.switches = config.suggestionsSettings(refreshes: world.switches.refreshes)
        return world.field { $0.suggestions.commandRuntime = programs }
    }

    // MARK: - From another Mac

    /// Made on A, it comes to B marked with its program: nothing of it runs on B, at the focus, as its prefix is typed,
    /// after its refresh interval, or on Refresh Now. Settings says where it's from and what it would run.
    @Test func aCommandFromAnotherMacRunsNothingUntilAllowed() async throws {
        try await inEnglish {
            let rig = try SyncRig()
            let a = try rig.mac("A") { $0.customCommands = [Self.jira()] }
            let b = try rig.mac("B")
            a.sync(at: t(0))
            let arrived = b.sync(at: t(1))
            let config = try b.config()
            #expect(config.customCommands == [Self.jira()])
            #expect(config.awaitsConfirmation(Self.jira()))
            #expect(config.unconfirmedCommands == [CustomCommand.Unconfirmed(name: "jira", argv: Self.program)])
            #expect(config.suggestionsSettings().commands.isEmpty, "not a source on B")
            #expect(arrived.unconfirmedCommands == ["jira"], "the notice's: \(arrived.unconfirmedCommands)")
            // The notice is once: the next run brings nothing new to confirm.
            #expect(b.sync(at: t(2)).unconfirmedCommands.isEmpty)
            // On A, where it was made, it runs.
            #expect(!(try a.config()).awaitsConfirmation(Self.jira()))
            #expect(try a.config().suggestionsSettings().commands == [Self.jira()])

            let programs = Programs()
            let world = SuggestionsWorld()
            let field = Self.field(config, programs, world: world)
            field.idle()
            #expect(programs.all.isEmpty, "at the focus: \(programs.all)")
            field.type("JIRA-1")
            field.idle()
            #expect(field.rows.isEmpty && programs.all.isEmpty, "its prefix typed: \(programs.all)")
            field.pause(2 * 3600)
            field.type("2")
            field.idle()
            #expect(programs.all.isEmpty, "after its refresh interval: \(programs.all)")
            world.switches.refreshes = [CompletionSourceRefresh(plugin: CompletionSourceKey.customCommands, source: "jira",
                                                                requested: world.clock.now)]
            field.host.send(.configChanged)
            field.idle()
            #expect(programs.all.isEmpty, "Refresh Now: \(programs.all)")

            // Settings → Custom Commands: from another Mac, the program it would run.
            let state = try #require(Self.jira().suggestionsState(config, status: nil))
            #expect(state.problem && state.text.hasPrefix("From another Mac: runs /Users/me/bin/jira-list"), "\(state.text)")
        }
    }

    /// Allowed on B (the program shown), it runs there as one made there: at the focus, and its rows show. Its
    /// confirmation stays on B: it never goes to iCloud, nor to A.
    @Test func allowedItRuns() async throws {
        try await inEnglish {
            let rig = try SyncRig()
            let a = try rig.mac("A") { $0.customCommands = [Self.jira()] }
            let b = try rig.mac("B")
            a.sync(at: t(0))
            b.sync(at: t(1))
            let settings = SettingsStore(configURL: b.configURL)
            settings.allowCommand(Self.jira())
            let config = try b.config()
            #expect(!config.awaitsConfirmation(Self.jira()) && config.unconfirmedCommands.isEmpty)
            #expect(config.suggestionsSettings().commands == [Self.jira()])

            let programs = Programs()
            let field = Self.field(config, programs)
            #expect(field.settle { programs.all == [Programs.Run(argv: Self.program)] }, "\(programs.all)")
            field.type("JIRA-1")
            #expect(field.settle { field.rows.map(\.text) == ["JIRA-12", "JIRA-17"] }, "\(field.rows.map(\.text))")

            // Allowing changes nothing that syncs.
            #expect(b.sync(at: t(2)).uploaded.isEmpty)
            #expect(a.sync(at: t(3)).applied.isEmpty)
        }
    }

    /// Allow confirms the program it showed: one another Mac put in meanwhile (sync changed it under the window) still
    /// asks.
    @Test func allowConfirmsTheProgramShown() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.customCommands = [Self.jira()] }
        let b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        let shown = try #require(try b.config().customCommands.first)
        try a.edit(at: t(2)) { $0.customCommands = [Self.jira(["/Users/me/bin/other"])] }
        a.sync(at: t(3))
        b.sync(at: t(4))
        SettingsStore(configURL: b.configURL).allowCommand(shown)
        #expect(try b.config().awaitsConfirmation(Self.jira(["/Users/me/bin/other"])))
    }

    /// Its program changed on another Mac after it was allowed here: it asks again, and runs nothing meanwhile; its
    /// summary changed there, it doesn't.
    @Test func itsProgramChangedByAnotherMacAsksAgain() async throws {
        try await inEnglish {
            let rig = try SyncRig()
            let a = try rig.mac("A") { $0.customCommands = [Self.jira()] }
            let b = try rig.mac("B")
            a.sync(at: t(0))
            b.sync(at: t(1))
            SettingsStore(configURL: b.configURL).allowCommand(Self.jira())
            try a.edit(at: t(2)) { $0.customCommands = [Self.jira(summary: "Our Jira issues")] }
            a.sync(at: t(3))
            #expect(b.sync(at: t(4)).unconfirmedCommands.isEmpty, "only its summary changed")
            #expect(!(try b.config()).awaitsConfirmation(Self.jira(summary: "Our Jira issues")))

            let changed = Self.jira(["/Users/me/bin/jira-list", "--all"], summary: "Our Jira issues")
            try a.edit(at: t(5)) { $0.customCommands = [changed] }
            a.sync(at: t(6))
            #expect(b.sync(at: t(7)).unconfirmedCommands == ["jira"])
            let config = try b.config()
            #expect(config.customCommands == [changed] && config.awaitsConfirmation(changed))
            #expect(config.suggestionsSettings().commands.isEmpty)
            let programs = Programs()
            let field = Self.field(config, programs)
            field.type("JIRA-1")
            field.idle()
            #expect(programs.all.isEmpty && field.rows.isEmpty, "\(programs.all)")
            let state = try #require(changed.suggestionsState(config, status: nil))
            #expect(state.text.hasPrefix("From another Mac: runs /Users/me/bin/jira-list --all"), "\(state.text)")
        }
    }

    // MARK: - Made or edited on this Mac

    /// Edited on this Mac (Settings' editor), it's confirmed by that: it runs, and no question comes back with the next
    /// sync; on the Mac it came from, its program edited here asks. Deleted, its mark goes with it.
    @Test func editedHereItAsksNothing() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.customCommands = [Self.jira()] }
        let b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        let settings = SettingsStore(configURL: b.configURL)
        let edited = Self.jira(["/Users/me/bin/jira-list", "--mine"])
        #expect(settings.saveCommand(edited, editing: "jira"))
        var config = try b.config()
        #expect(!config.awaitsConfirmation(edited) && config.unconfirmedCommands.isEmpty)
        #expect(config.suggestionsSettings().commands == [edited])
        #expect(b.sync(at: t(2)).uploaded == [ICloudSync.commandsKey])
        #expect(a.sync(at: t(3)).unconfirmedCommands == ["jira"], "its program edited on B: A asks")
        #expect(b.sync(at: t(4)).unconfirmedCommands.isEmpty)
        #expect(!(try b.config()).awaitsConfirmation(edited))

        // Another one comes, and is deleted here: nothing of it is kept.
        try a.edit(at: t(5)) { $0.customCommands.append(Self.gh) }
        a.sync(at: t(6))
        b.sync(at: t(7))
        #expect(try b.config().unconfirmedCommands.map(\.name) == ["gh"])
        settings.deleteCommand(named: "gh")
        config = try b.config()
        #expect(config.unconfirmedCommands.isEmpty && config.customCommands == [edited])
    }

    static let gh = CustomCommand(name: "gh", type: .suggestions, argv: ["gh-issues"], prefix: "#")

    /// Made on this Mac, in Settings or by hand in config.json, a command never asks, also once it has been to iCloud and
    /// back.
    @Test func madeHereItNeverAsks() throws {
        let rig = try SyncRig()
        let b = try rig.mac("B")
        b.sync(at: t(0))
        let settings = SettingsStore(configURL: b.configURL)
        #expect(settings.saveCommand(Self.jira(), editing: nil))
        try b.edit(at: t(1)) { $0.customCommands.append(Self.gh) }
        let config = try b.config()
        #expect(config.unconfirmedCommands.isEmpty)
        #expect(config.suggestionsSettings().commands.map(\.name) == ["jira", "gh"])
        #expect(!(try String(contentsOf: b.configURL, encoding: .utf8)).contains("unconfirmedCommands"), "nothing written for them")
        #expect(b.sync(at: t(2)).uploaded == [ICloudSync.commandsKey])
        #expect(b.sync(at: t(3)).unconfirmedCommands.isEmpty)
        #expect(try b.config().unconfirmedCommands.isEmpty)
    }

    /// A confirmation is of the program: a command from another Mac whose program this Mac runs already (one made here,
    /// or allowed) doesn't ask, whatever its name.
    @Test func aProgramThisMacRunsAlreadyDoesntAsk() throws {
        let rig = try SyncRig()
        let tickets = CustomCommand(name: "tickets", type: .suggestions, argv: Self.program, prefix: "T-")
        let a = try rig.mac("A") { $0.customCommands = [tickets] }
        let b = try rig.mac("B") { $0.customCommands = [Self.jira(), Self.gh] }
        a.sync(at: t(0))
        // B joins: iCloud's tickets runs B's jira's program.
        #expect(b.sync(at: t(1)).unconfirmedCommands.isEmpty)
        #expect(try b.config().customCommands.map(\.name) == ["tickets", "jira", "gh"])
        // A gets B's: jira runs A's tickets' program, gh asks.
        #expect(a.sync(at: t(2)).unconfirmedCommands == ["gh"])
        #expect(try a.config().suggestionsSettings().commands.map(\.name) == ["tickets", "jira"])
        // Allowed on A, gh's program doesn't ask there again under another name.
        SettingsStore(configURL: a.configURL).allowCommand(Self.gh)
        try b.edit(at: t(3)) { $0.customCommands.append(CustomCommand(name: "bugs", type: .suggestions, argv: ["gh-issues", "--bugs"], prefix: "BUG-")) }
        try b.edit(at: t(4)) { $0.customCommands.append(CustomCommand(name: "prs", type: .suggestions, argv: ["gh-issues"], prefix: "PR-")) }
        b.sync(at: t(5))
        #expect(a.sync(at: t(6)).unconfirmedCommands == ["bugs"])
        #expect(try a.config().unconfirmedCommands.map(\.name) == ["bugs"])
    }

    /// `run` commands are as they were (they run only when the user runs them): never marked.
    @Test func runCommandsAreUnchanged() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.customCommands = [CustomCommand(name: "py", type: .run, argv: ["python3", "-c", "{input}"])] }
        let b = try rig.mac("B")
        a.sync(at: t(0))
        let report = b.sync(at: t(1))
        #expect(report.unconfirmedCommands.isEmpty)
        let config = try b.config()
        #expect(config.customCommands.map(\.name) == ["py"] && config.unconfirmedCommands.isEmpty)
    }

    // MARK: - Never synced

    /// The marks are this Mac's own: never a synced key, never in iCloud's settings.json nor on another Mac, whatever
    /// the categories synced.
    @Test func theConfirmationsAreNeverSynced() throws {
        #expect(ICloudSync.neverSynced.contains("unconfirmedCommands"))
        #expect(ICloudSync.category(of: "unconfirmedCommands") == nil)
        #expect(Config.allKeys.contains("unconfirmedCommands"))
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.customCommands = [Self.jira()] }
        let b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        #expect(try b.config().unconfirmedCommands.count == 1)
        #expect(b.sync(at: t(2)).uploaded.isEmpty)
        let settings = try rig.settingsJSON()
        #expect(settings["unconfirmedCommands"] == nil, "\(settings.keys.sorted())")
        let icloud = try String(contentsOf: rig.folder.url.appendingPathComponent(ICloudSync.settingsFile), encoding: .utf8)
        #expect(!icloud.contains("unconfirmed"))
        a.sync(at: t(3))
        #expect(!(try String(contentsOf: a.configURL, encoding: .utf8)).contains("unconfirmed"))
        // Values iCloud would carry are refused as any key it doesn't sync: a mark put there by hand doesn't come in.
        var stale = try rig.settingsJSON()
        stale["unconfirmedCommands"] = ["value": [], "modified": ICloudSync.dateText(t(4)), "by": "X"]
        try JSONSerialization.data(withJSONObject: stale).write(to: rig.folder.url.appendingPathComponent(ICloudSync.settingsFile))
        #expect(b.sync(at: t(5)).applied.isEmpty)
        #expect(try b.config().unconfirmedCommands.count == 1)
    }

    /// The marks are read leniently (a value of the wrong kind is none, and the rest of config.json loads) and written
    /// only when there are some.
    @Test func theMarksInTheConfigFile() throws {
        let json = #"{"customCommands": [{"name": "jira", "type": "suggestions", "argv": ["/Users/me/bin/jira-list"], "prefix": "JIRA-"}],"#
            + #" "unconfirmedCommands": [{"name": "jira", "argv": ["/Users/me/bin/jira-list"]}]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.awaitsConfirmation(Self.jira()))
        let wrong = try JSONDecoder().decode(Config.self, from: Data(#"{"typeOut": true, "unconfirmedCommands": "jira"}"#.utf8))
        #expect(wrong.typeOut && wrong.unconfirmedCommands.isEmpty)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as? [String: Any]
        #expect(encoded?["unconfirmedCommands"] == nil)
        // The name in another case is the same command's.
        var other = Self.jira()
        other.name = "JIRA"
        #expect(config.awaitsConfirmation(other))
    }

    /// One with a built-in command's name, renamed on this Mac (`Config.freeBuiltinNames`, written by
    /// `Config.writeRenames`), stays unconfirmed under its new name.
    @Test func renamedForABuiltInItStaysUnconfirmed() throws {
        let rig = try SyncRig()
        let reply = CustomCommand(name: "reply", type: .suggestions, argv: Self.program, prefix: "R-")
        let a = try rig.mac("A") { $0.customCommands = [reply] }
        let b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        var config = try b.config()
        #expect(config.awaitsConfirmation(reply))
        let renamed = config.freeBuiltinNames(taken: [])
        #expect(renamed.map(\.new) == ["myreply"])
        var mine = reply
        mine.name = "myreply"
        #expect(config.awaitsConfirmation(mine) && config.suggestionsSettings().commands.isEmpty)
        #expect(try Config.writeRenames(renamed, at: b.configURL).count == 1)
        config = try b.config()
        #expect(config.customCommands == [mine] && config.awaitsConfirmation(mine), "\(config.unconfirmedCommands)")
    }

    /// Settings' document (Windows' window too) says it is from another Mac in the command's item.
    @Test func settingsDocumentSaysItsFromAnotherMac() async throws {
        let rig = try SyncRig()
        let a = try rig.mac("A") { $0.customCommands = [Self.jira()] }
        let b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        let library = PluginLibrary(directory: rig.root.appendingPathComponent("plugins", isDirectory: true))
        for platform in [SettingsPlatform.windows, .mac] {
            let service = SettingsService(store: SettingsStore(configURL: b.configURL), platform: platform, library: library)
            let items = try await withInterfaceLanguage("en") { try #require(service.document().field("commands.custom")?.items) }
            #expect(items.first?.detail?.contains("From another Mac: runs /Users/me/bin/jira-list") == true, "\(items.first?.detail ?? "")")
        }
    }
}
