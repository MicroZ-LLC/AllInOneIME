import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Completion sources on by default (owner 2026-10-25, 0.6.7.2: "这样用户不需要设置太多"). A plugin's are approved as it is
/// installed, from the library or put in the plugins folder, and the first time this version finds one installed before
/// (`Config.approveNewPlugins`, `pluginsSeen`); a plugin update that changes what was approved turns it off as before, and
/// a source an update adds is off until turned on. A script extension of the user's own is on as it loads, and one from a
/// trusted extension source too, with no approval (`CompletionSourceApproval.byDefault`); one from any other source once
/// approved as the source is added (`Config.approveAddedSource`), a change turning it off and a source an update adds
/// waiting until turned on. Turning "Trust its updates" on turns on those off because of a change and those waiting. One
/// the user turned off stays off (`Config.completionSourcesOff`), through updates, restarts and a re-index, until turned
/// on again. The plugins are written to a temporary folder and read as the app reads them; the bundles are the trust
/// tests' (`ExtensionCompletionsTrustTests.Place`).
@Suite(.serialized, SuggestionsOneAtATime())
struct CompletionSourcesOnByDefaultTests {
    typealias Place = ExtensionCompletionsTrustTests.Place

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: - Plugins

    /// A folder of plugins of a test's own, removed after it.
    final class Plugins: @unchecked Sendable {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plugins-default-\(UUID().uuidString)", isDirectory: true)
        deinit { try? FileManager.default.removeItem(at: folder) }

        /// The plugin `manifest` declares (its script `script`) written, or written again (an update), and read back.
        func install(_ manifest: String, script: String = SuggestionsPlugins.script) throws -> InstalledPlugin {
            try #require(try SuggestionsPlugins.install(manifest, script: script, in: folder))
        }
    }

    /// GitHub's plugin with a second source, pull requests after "PR-" (a list).
    static let twoSources = SuggestionsPlugins.githubManifest(extra: #"""
        , { "name": "pulls", "title": "Pull requests", "prefix": "PR-", "list": true, "insert": { "default": "{arg}" } }
        """#)

    static func source(_ plugin: InstalledPlugin, _ name: String) throws -> CompletionSource {
        try #require(plugin.manifest.completions.first { $0.name == name })
    }

    /// A plugin installed (one this Mac hasn't found before) has each of its sources approved as it is now: its hosts,
    /// whether it queries, its script, its terms, as turning one on approves; the plugin is noted, and found again it
    /// approves nothing more. Kept in the config file (never synced), read back as it was written.
    @Test func aPluginIsOnOnceInstalled() throws {
        let plugins = Plugins()
        let plugin = try plugins.install(Self.twoSources)
        let (issues, pulls) = (try Self.source(plugin, "issues"), try Self.source(plugin, "pulls"))
        var config = Config.default
        #expect(config.hasNewPlugins([plugin]))
        let approved = config.approveNewPlugins([plugin])
        #expect(approved)
        #expect(config.completionSources == [SuggestionsPlugins.approval(plugin, "issues"), SuggestionsPlugins.approval(plugin, "pulls")],
                "\(config.completionSources)")
        #expect(config.approval(of: issues, in: plugin)?.holds(for: issues, of: plugin) == true
                && config.approval(of: pulls, in: plugin)?.holds(for: pulls, of: plugin) == true)
        #expect(config.pluginsSeen == ["github"] && !config.hasNewPlugins([plugin]))
        let foundAgain = config.approveNewPlugins([plugin])
        #expect(!foundAgain, "found again: nothing more")
        #expect(config.suggestionsSettings().enabled == config.completionSources)

        let file = plugins.folder.appendingPathComponent("config.json")
        try config.write(to: file)
        let read = try Config.load(from: file)
        #expect(read.pluginsSeen == ["github"] && read.completionSources == config.completionSources)
        #expect(ICloudSync.neverSynced.contains("pluginsSeen") && ICloudSync.category(of: "pluginsSeen") == nil)
    }

    /// A config of 0.6.7.1 (no `pluginsSeen`): a plugin installed then, its source never turned on, is approved as it is
    /// the first time this version finds it; one approved then is kept as it was, and one marked lapsed stays off.
    @Test func aPluginInstalledBeforeIsOnTheFirstTimeThisVersionFindsIt() throws {
        let plugins = Plugins()
        let github = try plugins.install(SuggestionsPlugins.githubManifest())
        let tracker = try plugins.install(SuggestionsPlugins.trackerManifest)
        let aws = try plugins.install(SuggestionsPlugins.awsManifest)
        let approved = SuggestionsPlugins.approval(tracker, "tickets")
        var lapsed = SuggestionsPlugins.approval(aws, "accounts")
        lapsed.lapsed = true
        let old = """
            {"completionSources": \(String(decoding: try JSONEncoder().encode([approved, lapsed]), as: UTF8.self))}
            """
        var config = try JSONDecoder().decode(Config.self, from: Data(old.utf8))
        #expect(config.pluginsSeen.isEmpty && config.completionSourcesOff.isEmpty)
        let approvedOld = config.approveNewPlugins([aws, github, tracker])
        #expect(approvedOld)
        #expect(config.completionSources == [approved, lapsed, SuggestionsPlugins.approval(github, "issues")], "\(config.completionSources)")
        #expect(config.pluginsSeen == ["aws", "github", "tracker"])
        let accounts = try Self.source(aws, "accounts")
        #expect(config.approval(of: accounts, in: aws)?.holds(for: accounts, of: aws) == false, "lapsed: still off")
    }

    /// What a plugin update changes.
    enum Update: String, CaseIterable, Sendable {
        case hosts, prefix, query, queryMinChars, compare, script, version
    }

    /// A plugin update that changes what was approved (its hosts, the source's prefix, query or when it starts, how it
    /// compares, its script) turns it off again, as before, once; found again, nothing approves it again: off until turned
    /// on. One that changes only its version keeps it on.
    @Test(arguments: Update.allCases)
    func aPluginUpdateThatChangesWhatWasApprovedTurnsItOff(_ update: Update) throws {
        let plugins = Plugins()
        let plugin = try plugins.install(SuggestionsPlugins.githubManifest())
        var config = Config.default
        config.approveNewPlugins([plugin])
        let approval = try #require(config.completionSources.first)

        var manifest = SuggestionsPlugins.githubManifest()
        var script = SuggestionsPlugins.script
        switch update {
        case .hosts: manifest = SuggestionsPlugins.githubManifest(hosts: ["api.github.com", "collector.example.com"])
        case .prefix: manifest = manifest.replacingOccurrences(of: ##""prefix": "#""##, with: #""prefix": "GH-""#)
        case .query: manifest = SuggestionsPlugins.githubManifest(query: false)
        case .queryMinChars: manifest = manifest.replacingOccurrences(of: #""queryMinChars": 2"#, with: #""queryMinChars": 3"#)
        case .compare: manifest = manifest.replacingOccurrences(of: #""compare": "prefix""#, with: #""compare": "exact""#)
        case .script: script += "\n// fixed upstream\n"
        case .version: break
        }
        manifest = manifest.replacingOccurrences(of: #""version": "1.0.0""#, with: #""version": "1.1.0""#)
        let updated = try plugins.install(manifest, script: script)
        let issues = try Self.source(updated, "issues")
        let lapsed = CompletionSourceApproval.lapsed(config.completionSources, plugins: [updated])
        let asNew = config.approveNewPlugins([updated])
        #expect(!asNew, "\(update): an update, not a new plugin")
        if update == .version {
            #expect(lapsed.isEmpty && config.approval(of: issues, in: updated)?.holds(for: issues, of: updated) == true, "version: still on")
            return
        }
        #expect(lapsed == [approval], "\(update): off (\(lapsed))")
        let marked = config.markLapsed(lapsed)
        #expect(marked && config.approval(of: issues, in: updated)?.lapsed == true)
        #expect(CompletionSourceApproval.lapsed(config.completionSources, plugins: [updated]).isEmpty, "\(update): said once")
        let approvedAgain = config.approveNewPlugins([updated])
        #expect(!approvedAgain && config.approval(of: issues, in: updated)?.holds(for: issues, of: updated) == false,
                "\(update): off until turned on")
        config.setCompletionSource(issues, of: updated, enabled: true)
        #expect(config.approval(of: issues, in: updated)?.holds(for: issues, of: updated) == true, "\(update): turned on again")
    }

    /// A source an update adds starts off until turned on (it is a change), the plugin's other sources still on; so does
    /// one an update adds to a plugin that had none.
    @Test func aSourceAPluginUpdateAddsStartsOff() throws {
        let plugins = Plugins()
        let plugin = try plugins.install(SuggestionsPlugins.githubManifest())
        var config = Config.default
        config.approveNewPlugins([plugin])
        let updated = try plugins.install(Self.twoSources.replacingOccurrences(of: #""version": "1.0.0""#, with: #""version": "1.1.0""#))
        let (issues, pulls) = (try Self.source(updated, "issues"), try Self.source(updated, "pulls"))
        let asNew = config.approveNewPlugins([updated])
        #expect(!asNew)
        #expect(config.approval(of: pulls, in: updated) == nil, "added by the update: off")
        #expect(config.approval(of: issues, in: updated)?.holds(for: issues, of: updated) == true, "the other one still on")
        config.setCompletionSource(pulls, of: updated, enabled: true)
        #expect(config.approval(of: pulls, in: updated)?.holds(for: pulls, of: updated) == true, "turned on")

        let none = try plugins.install(#"""
            { "name": "notes", "version": "1.0.0", "type": "script", "script": "main.js", "hosts": ["notes.example.com"] }
            """#)
        let noted = config.approveNewPlugins([none])
        #expect(noted && config.pluginsSeen.contains("notes"), "a plugin with no source, noted")
        let gained = try plugins.install(#"""
            { "name": "notes", "version": "1.1.0", "type": "script", "script": "main.js", "hosts": ["notes.example.com"],
              "completions": [ { "name": "pages", "title": "Pages", "prefix": "NB-", "list": true, "insert": { "default": "{arg}" } } ] }
            """#)
        let gainedAsNew = config.approveNewPlugins([gained])
        #expect(!gainedAsNew && !config.completionSources.contains { $0.plugin == "notes" },
                "its first source, added by an update: off")
    }

    /// A plugin's source turned off stays off: kept in `completionSourcesOff` (never synced), through a restart (the config
    /// file read again), a scan finding the plugin again and an update; the session doesn't run it. Turned on again, it is
    /// off the list. Removed in Settings (`forgetPlugin`), everything kept of it goes: installed again, it is on.
    @Test func aPluginSourceTurnedOffStaysOff() throws {
        let plugins = Plugins()
        let plugin = try plugins.install(SuggestionsPlugins.githubManifest())
        let issues = try Self.source(plugin, "issues")
        let key = CompletionSourceKey(plugin: "github", source: "issues")
        var config = Config.default
        config.approveNewPlugins([plugin])
        config.setCompletionSource(issues, of: plugin, enabled: false)
        #expect(config.approval(of: issues, in: plugin) == nil && config.completionSourcesOff == [key] && config.turnedOff(key))
        #expect(config.suggestionsSettings().off == [key])

        let file = plugins.folder.appendingPathComponent("config.json")
        try config.write(to: file)
        #expect(try String(contentsOf: file, encoding: .utf8).contains(#""plugin" : "github""#))
        var restarted = try Config.load(from: file)
        #expect(restarted.completionSourcesOff == [key], "after a restart")
        let updated = try plugins.install(SuggestionsPlugins.githubManifest().replacingOccurrences(of: #""version": "1.0.0""#,
                                                                                                    with: #""version": "1.1.0""#))
        let afterUpdate = restarted.approveNewPlugins([updated])
        #expect(!afterUpdate && restarted.approval(of: issues, in: updated) == nil, "an update: still off")
        restarted.pluginsSeen = []  // as if found for the first time: still the user's choice
        let foundAgain = restarted.approveNewPlugins([updated])
        #expect(foundAgain && restarted.approval(of: issues, in: updated) == nil, "found again: still off")
        #expect(ICloudSync.neverSynced.contains("completionSourcesOff") && ICloudSync.category(of: "completionSourcesOff") == nil)

        restarted.setCompletionSource(issues, of: updated, enabled: true)
        #expect(restarted.completionSourcesOff.isEmpty && restarted.approval(of: issues, in: updated)?.holds(for: issues, of: updated) == true,
                "turned on again: off the list")
        restarted.setCompletionSource(issues, of: updated, enabled: false)
        let forgot = restarted.forgetPlugin("github")
        #expect(forgot)
        #expect(restarted.completionSources.isEmpty && restarted.completionSourcesOff.isEmpty && restarted.pluginsSeen.isEmpty)
        let installedAgain = restarted.approveNewPlugins([updated])
        #expect(installedAgain && restarted.approval(of: issues, in: updated)?.holds(for: issues, of: updated) == true,
                "installed again: on")
    }

    /// The list the user turned off is read leniently: anything but a list of `{plugin, source}` reads as none.
    @Test func theOffListIsKeptAsKeys() throws {
        func read(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }
        #expect(try read(#"{"completionSourcesOff": [{"plugin": "script-extensions", "source": "desk/tickets"}]}"#).completionSourcesOff
                == [CompletionSourceKey(extensionCommand: "desk/tickets")])
        #expect(try read(#"{"completionSourcesOff": "github"}"#).completionSourcesOff.isEmpty)
        #expect(try read(#"{"pluginsSeen": 3}"#).pluginsSeen.isEmpty)
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) is [String: Any])
        let empty = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as? [String: Any])
        #expect(empty["completionSourcesOff"] == nil && empty["pluginsSeen"] == nil, "not written while empty")
    }

    // MARK: - Script extensions

    /// The user's own extension is on as it loads, with nothing approved (its changes keep it on: nothing of it read); a
    /// command added to it later is on too.
    @Test func theUsersOwnExtensionIsOnAsItLoads() throws {
        let place = try Place(.own)
        try place.desk()
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        #expect(place.config.completionSources.isEmpty)
        let state = place.config.completionState(of: source, in: command, root: place.sources, sha256: { _ in
            Issue.record("nothing read")
            return nil
        })
        #expect(state == ScriptCompletionState(on: true, changed: false, tooLarge: false), "\(state)")
        #expect(CompletionSourceApproval.byDefault(source, of: command, follows: place.follows(command))
                == CompletionSourceApproval(plugin: CompletionSourceKey.scriptExtensions, source: command.id, hosts: [], query: source.query,
                                            scriptSHA256: "", terms: CompletionSourceApproval.Terms(source)))

        try place.write("extension.json", Self.bundle(["tickets": ExtensionCompletionsTrustTests.tickets(), "notes": Self.notes]))
        try place.write("notes.sh", place.script(body: ""))
        let notes = try #require(place.index.commands.first { $0.name == "notes" })
        guard case let .success(declared)? = notes.completion else { Issue.record("no source"); return }
        #expect(place.config.completionState(of: declared, in: notes, root: place.sources).on, "added later: on too")
    }

    /// From a source whose updates aren't trusted: off (nothing approved it) until the source is added; adding it
    /// approves the sources its extensions declare as they are then, pinned by its repository (`approveAddedSource`), but
    /// one turned off before (a re-review). From a trusted source, approved with nothing read.
    @Test(arguments: [ExtensionCompletionsTrustTests.Origin.untrusted, .trusted])
    func aSourcesExtensionsAreOnOnceTheSourceIsAdded(_ origin: ExtensionCompletionsTrustTests.Origin) throws {
        let place = try Place(origin)
        try place.desk()
        try place.write("extension.json", Self.bundle(["tickets": ExtensionCompletionsTrustTests.tickets(), "notes": Self.notes]))
        try place.write("notes.sh", place.script(body: ""))
        let url = ExtensionCompletionsTrustTests.teamURL
        let source = try #require(place.config.extensionSources.first)
        let commands = ExtensionSources.extensions(of: source, root: place.sources)
        #expect(Set(commands.map(\.name)) == ["tickets", "notes"])
        let (tickets, notes) = (try #require(commands.first { $0.name == "tickets" }), try #require(commands.first { $0.name == "notes" }))
        guard case let .success(ticketsSource)? = tickets.completion, case let .success(notesSource)? = notes.completion else {
            Issue.record("no sources")
            return
        }
        if origin == .untrusted {
            #expect(!place.config.completionState(of: ticketsSource, in: tickets, root: place.sources).on, "before it is added: off")
        }
        place.config.setCompletionSource(notesSource, of: notes, enabled: false, digest: nil, root: place.sources)
        var reads = 0
        let added = place.config.approveAddedSource(url, extensions: commands, root: place.sources, digest: { command in
            reads += 1
            return place.digest(command)
        })
        #expect(added)
        let approval = try #require(place.config.approval(of: ticketsSource, in: tickets))
        #expect(approval.scriptSHA256 == (origin == .untrusted ? place.digest(tickets) : "") && !approval.lapsed)
        #expect(origin == .untrusted ? reads > 0 : reads == 0, "\(origin): \(reads) read")
        #expect(place.holds(ticketsSource, of: tickets) && place.config.completionState(of: ticketsSource, in: tickets, root: place.sources).on)
        #expect(place.config.approval(of: notesSource, in: notes) == nil && place.config.turnedOff(CompletionSourceKey(extension: notes))
                && !place.config.completionState(of: notesSource, in: notes, root: place.sources).on, "turned off before: still off")
        let again = place.config.approveAddedSource(url, extensions: commands, root: place.sources, digest: place.digest)
        #expect(!again, "again: as it was")
        let other = place.config.approveAddedSource("https://git.example.com/other.git", extensions: commands, root: place.sources,
                                                 digest: place.digest)
        #expect(!other, "another source's: none of these")
    }

    /// From a source marked "Trust its updates", a source an update adds is on, nothing approved and nothing read; from any
    /// other, it waits until turned on (nothing approved it), and the update, a change to the repository, turns off the one
    /// approved as the source was added, said once.
    @Test(arguments: [ExtensionCompletionsTrustTests.Origin.trusted, .untrusted])
    func aSourceAnUpdateAdds(_ origin: ExtensionCompletionsTrustTests.Origin) throws {
        let place = try Place(origin)
        try place.desk()
        let source = try #require(place.config.extensionSources.first)
        place.config.approveAddedSource(source.url, extensions: ExtensionSources.extensions(of: source, root: place.sources),
                                        root: place.sources, digest: place.digest)
        try place.write("extension.json", Self.bundle(["tickets": ExtensionCompletionsTrustTests.tickets(), "notes": Self.notes]))
        try place.write("notes.sh", place.script(body: ""))
        let (tickets, notes) = (try place.command(), try #require(place.index.commands.first { $0.name == "notes" }))
        guard case let .success(ticketsSource)? = tickets.completion, case let .success(notesSource)? = notes.completion else {
            Issue.record("no sources")
            return
        }
        let added = place.config.completionState(of: notesSource, in: notes, root: place.sources)
        let lapsed = place.lapsed(tickets)
        switch origin {
        case .trusted:
            #expect(added.on && place.config.approval(of: notesSource, in: notes) == nil, "trusted: the one added is on (\(added))")
            #expect(lapsed.isEmpty && place.holds(ticketsSource, of: tickets), "the other still on")
        default:
            #expect(added == ScriptCompletionState(on: false, changed: false, tooLarge: false), "not trusted: the one added waits (\(added))")
            let marked = place.config.markLapsed(lapsed)
            #expect(lapsed.count == 1 && marked, "the update turns the approved one off")
            #expect(place.lapsed(tickets).isEmpty && place.config.completionState(of: ticketsSource, in: tickets, root: place.sources).changed,
                    "said once")
            place.config.setCompletionSource(notesSource, of: notes, enabled: true, root: place.sources)
            #expect(place.config.completionState(of: notesSource, in: notes, root: place.sources).on, "turned on")
        }
    }

    /// Turning "Trust its updates" on turns on the sources of its extensions off because of a change (marked lapsed) and
    /// those waiting (added by an update), approved as they are then, nothing read; never one the user turned off.
    /// Turning it off again turns nothing off by itself: those on are pinned as they are then, the one turned off stays
    /// off.
    @Test func turningTrustOnTurnsOnTheChangedAndTheWaitingButNotOneTurnedOff() throws {
        let place = try Place(.untrusted)
        try place.desk()
        try place.write("extension.json", Self.bundle(["tickets": ExtensionCompletionsTrustTests.tickets(), "notes": Self.notes]))
        try place.write("notes.sh", place.script(body: ""))
        let source = try #require(place.config.extensionSources.first)
        place.config.approveAddedSource(source.url, extensions: ExtensionSources.extensions(of: source, root: place.sources),
                                        root: place.sources, digest: place.digest)
        let notes = try #require(place.index.commands.first { $0.name == "notes" })
        guard case let .success(notesSource)? = notes.completion else { Issue.record("no source"); return }
        place.config.setCompletionSource(notesSource, of: notes, enabled: false, root: place.sources)

        // An update: tickets changed (lapsed), docs added, a new command "links" (waiting).
        try place.write("extension.json", Self.bundle(["tickets": ExtensionCompletionsTrustTests.tickets(prefix: "TIX-"), "notes": Self.notes,
                                                       "links": Self.links]))
        try place.write("links.sh", place.script(body: ""))
        let commands = place.index.commands
        let (tickets, links) = (try place.command(), try #require(commands.first { $0.name == "links" }))
        guard case let .success(ticketsSource)? = tickets.completion, case let .success(linksSource)? = links.completion else {
            Issue.record("no sources")
            return
        }
        place.config.markLapsed(place.lapsed(tickets))
        func state(_ command: ScriptCommand) -> ScriptCompletionState {
            guard case let .success(declared)? = command.completion else { return ScriptCompletionState(on: false, changed: false, tooLarge: false) }
            return place.config.completionState(of: declared, in: command, root: place.sources)
        }
        #expect(state(tickets).changed && !state(links).on && state(notes).turnedOff, "before: changed, waiting, turned off")

        let trusted = place.config.setTrustUpdates(true, of: source.url, extensions: commands, root: place.sources, sha256: { _ in
            Issue.record("nothing read")
            return nil
        })
        #expect(trusted)
        let approval = try #require(place.config.approval(of: ticketsSource, in: tickets))
        #expect(!approval.lapsed && approval.scriptSHA256.isEmpty && approval.terms == CompletionSourceApproval.Terms(ticketsSource),
                "the changed one approved as it is now: \(approval)")
        #expect(state(tickets).on && state(links).on, "the changed and the waiting on")
        #expect(!state(notes).on && state(notes).turnedOff && place.config.approval(of: notesSource, in: notes) == nil,
                "the one turned off stays off")

        let untrusted = place.config.setTrustUpdates(false, of: source.url, extensions: commands, root: place.sources)
        #expect(untrusted)
        let pinned = place.digest(tickets)
        #expect(place.config.approval(of: ticketsSource, in: tickets)?.scriptSHA256 == pinned
                && place.config.approval(of: linksSource, in: links)?.scriptSHA256 == pinned, "pinned as they are then")
        #expect(state(tickets).on && state(links).on && state(notes).turnedOff, "nothing off by itself")
        #expect(place.lapsed(tickets).isEmpty && place.lapsed(links).isEmpty)
    }

    /// A source turned off stays off: kept in `completionSourcesOff`, through a re-index (the folder read again), a change
    /// to the extension, a restart (the config file read again) and the source added again; the session doesn't run it.
    /// Turned on again, it is off the list and on.
    @Test(arguments: ExtensionCompletionsTrustTests.Origin.allCases)
    func turnedOffStaysOffUntilTurnedOnAgain(_ origin: ExtensionCompletionsTrustTests.Origin) throws {
        let place = try Place(origin)
        try place.desk()
        if let source = place.config.extensionSources.first {
            place.config.approveAddedSource(source.url, extensions: ExtensionSources.extensions(of: source, root: place.sources),
                                            root: place.sources, digest: place.digest)
        }
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        #expect(place.config.completionState(of: source, in: command, root: place.sources).on, "\(origin): on")
        place.config.setCompletionSource(source, of: command, enabled: false, root: place.sources)
        let key = CompletionSourceKey(extension: command)
        #expect(place.config.completionSourcesOff == [key] && place.config.approval(of: source, in: command) == nil)

        try place.make(.lib)
        let again = try place.command()  // the folder read again, after a change
        #expect(CompletionSourceKey(extension: again) == key)
        #expect(!place.config.completionState(of: source, in: again, root: place.sources).on, "\(origin): re-indexed, changed: off")
        let file = place.root.appendingPathComponent("config.json")
        try place.config.write(to: file)
        var restarted = try Config.load(from: file)
        #expect(restarted.completionSourcesOff == [key], "\(origin): after a restart")
        #expect(!restarted.completionState(of: source, in: again, root: place.sources).on)
        if let added = restarted.extensionSources.first {
            restarted.approveAddedSource(added.url, extensions: [again], root: place.sources, digest: place.digest)
            #expect(restarted.approval(of: source, in: again) == nil, "\(origin): the source added again: still off")
        }
        #expect(restarted.suggestionsSettings().off == [key])

        restarted.setCompletionSource(source, of: again, enabled: true, root: place.sources)
        #expect(restarted.completionSourcesOff.isEmpty && restarted.completionState(of: source, in: again, root: place.sources).on,
                "\(origin): turned on again")
    }

    /// Where it can't be pinned (its repository too large, or not all of it readable) a source not trusted can't be on:
    /// adding the source approves nothing, and Settings says why.
    @Test func whatCantBePinnedStaysOff() throws {
        let large = try ExtensionCompletionsRepositoryTests.place(.untrusted, files: ExtensionDigest.maxFiles + 1)
        let command = try large.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        let url = ExtensionCompletionsTrustTests.teamURL
        let approvedLarge = large.config.approveAddedSource(url, extensions: [command], root: large.sources, digest: large.digest)
        #expect(!approvedLarge)
        let state = large.config.completionState(of: source, in: command, root: large.sources)
        #expect(!state.on && state.tooLarge && state.cantTurnOn == CompletionSource.repositoryTooLarge, "\(state)")

        let locked = try Place(.untrusted)
        try locked.desk()
        let folder = try #require(locked.clone).appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let unreadable = try locked.command()
        let approvedLocked = locked.config.approveAddedSource(url, extensions: [unreadable], root: locked.sources, digest: locked.digest)
        #expect(!approvedLocked)
        let said = locked.config.completionState(of: source, in: unreadable, root: locked.sources)
        #expect(!said.on && said.unreadable && said.cantTurnOn == CompletionSource.repositoryUnreadable, "\(said)")
    }

    /// Through a text field, nothing approved: the user's own extension and a trusted source's show their rows, their
    /// program run; one from a source not trusted shows none and runs nothing. Turned off, none shows and nothing runs
    /// again; its cached list is kept only while it may be on.
    @Test(arguments: ExtensionCompletionsTrustTests.Origin.allCases)
    func throughAFieldWithNothingApproved(_ origin: ExtensionCompletionsTrustTests.Origin) async throws {
        try await inEnglish {
            let place = try Place(origin)
            try place.desk()
            let command = try place.command()
            let world = SuggestionsWorld()
            world.config.extensionSources = place.config.extensionSources
            world.switches = world.config.suggestionsSettings()
            func field(_ app: String) -> SuggestionsField {
                world.field(app: app) { services in
                    services.loadExtensions = { _, _ in place.index }
                    services.suggestions.extensionSourcesFolder = place.sources
                }
            }
            let first = field(SuggestionsApps.editor)
            first.type("TCK-1")
            switch origin {
            case .own, .trusted:
                #expect(first.settle(timeout: 15) { first.rows.map(\.text) == ["TCK-12", "TCK-17"] }, "\(origin): \(first.rows.map(\.text))")
                #expect(place.calls == "load|\n", "\(origin): run (\(place.calls))")
            case .untrusted:
                first.idle()
                #expect(first.rows.isEmpty && place.calls.isEmpty, "not trusted, not approved: \(first.rows.map(\.text)), \(place.calls)")
            }
            #expect(world.switches.sourceKeys(extensions: [command]).contains(CompletionSourceKey(extension: command)), "its list kept")

            world.switches.off = [CompletionSourceKey(extension: command)]
            let calls = place.calls
            let off = field("com.apple.TextEdit")
            off.type("TCK-1")
            off.idle(0.5)
            #expect(off.rows.isEmpty && place.calls == calls, "\(origin): turned off, nothing run (\(off.rows.map(\.text)))")
            #expect(!world.switches.sourceKeys(extensions: [command]).contains(CompletionSourceKey(extension: command)), "its list forgotten")
        }
    }

    // MARK: - Bundles

    /// A bundle "desk" with a command for each of `commands` (name → its completion), each running `<name>.sh`.
    static func bundle(_ commands: [String: String]) -> String {
        let entries = commands.sorted { $0.key > $1.key }.map { name, completion in
            #"{"script": "\#(name).sh", "name": "\#(name)", "title": "\#(name.capitalized)", "completion": \#(completion)}"#
        }
        return #"{"schemaVersion": 1, "name": "desk", "title": "Help Desk", "commands": [\#(entries.joined(separator: ", "))]}"#
    }

    static let notes = #"{"prefix": "NOTE-", "list": true, "refresh": "1h"}"#
    static let links = #"{"prefix": "LNK-", "list": true, "refresh": "1h"}"#
}
