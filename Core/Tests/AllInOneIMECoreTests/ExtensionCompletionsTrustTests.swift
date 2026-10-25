import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What a change to a script extension does to its completion source, by where the extension comes from (0.6.7.1 §2,
/// owner 2026-10-24): turning the source on pins the whole extension and its terms (query, prefix, queryMinChars,
/// compare). The user's own extension (a folder of theirs) and one from an extension source marked "Trust its updates"
/// stay on whatever changes, the approval following it (said nowhere), nothing of them read; one from any other source,
/// pinned by a digest of every file of its source's repository, is turned off by any change, said once, until it's turned
/// on again. The switch is off by default and kept with the source in the config. The bundles are written to a temporary
/// folder: the user's own in a folder of theirs, a source's in its clone (`ExtensionSources.bundleFolder`: its bundle in
/// extensions/desk, in a sources folder of the test's own, a shared file elsewhere in the repository), and read as the
/// input method reads them; their program notes its runs outside the bundle.
@Suite(.serialized, SuggestionsOneAtATime())
struct ExtensionCompletionsTrustTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// Where the bundle comes from.
    enum Origin: String, CaseIterable, Sendable {
        /// A folder of the user's own (their extensions folder).
        case own
        /// An extension source marked "Trust its updates".
        case trusted
        /// An extension source not marked so.
        case untrusted
    }

    /// A change to the bundle after its source was turned on.
    enum Change: String, CaseIterable, Sendable {
        /// A file of `lib/` the script uses.
        case lib
        /// A file the script uses elsewhere in its repository, out of its bundle (`../../shared/common.sh`).
        case shared
        /// The script itself.
        case script
        /// A new file anywhere in the bundle.
        case added
        /// Its terms: the prefix, whether it queries, how it compares.
        case prefix, query, compare
        /// Only how often its list is refreshed (a change to extension.json that isn't one of the terms).
        case refresh
    }

    static let teamURL = "git@git.example.com:team/desk.git"

    /// A temporary folder with the user's extensions folder (`own`), the sources' clones (`sources`) and the program's
    /// notes (`logs`, outside every bundle); the bundle "desk" written where `origin` puts it, the config naming its
    /// source.
    final class Place: @unchecked Sendable {
        let root: URL
        let origin: Origin
        var config = Config.default

        init(_ origin: Origin) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("extension-trust-\(UUID().uuidString)", isDirectory: true)
            self.origin = origin
            for folder in [own, sources, logs] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            config.extensionFolders = [own.path]
            if origin != .own {
                let source = ExtensionSource(url: ExtensionCompletionsTrustTests.teamURL, path: "extensions/desk", trustUpdates: origin == .trusted)
                ExtensionSources.enable(source, in: &config, root: sources)
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var own: URL { root.appendingPathComponent("extensions", isDirectory: true) }
        var sources: URL { root.appendingPathComponent("Sources", isDirectory: true) }
        var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }

        /// The bundle's folder: in the user's folder, or the source's clone.
        var bundle: URL {
            guard let source = config.extensionSources.first else { return own.appendingPathComponent("desk", isDirectory: true) }
            return ExtensionSources.bundleFolder(for: source, root: sources)
        }

        /// The source's clone (nil: the user's own).
        var clone: URL? { config.extensionSources.first.map { ExtensionSources.cloneFolder(for: $0.url, root: sources) } }

        /// Writes `path` of the bundle (folders made as needed); a script executable.
        func write(_ path: String, _ text: String) throws {
            let file = bundle.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            if path.hasSuffix(".sh") { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        }

        /// The bundle "desk": its command "tickets" declaring `completion`, its script sourcing lib/common.sh and a file
        /// out of its bundle (in a source's repository, shared/common.sh), its list `ticketsList` (in `logs`).
        func desk(_ completion: String = ExtensionCompletionsTrustTests.tickets()) throws {
            try write("extension.json", ExtensionCompletionsTrustTests.manifest(completion))
            try write("lib/common.sh", "greeting=hello\n")
            try write("../../shared/common.sh", "farewell=bye\n")
            try write("tickets.sh", script(body: ""))
            try Data(ExtensionCompletionsTrustTests.ticketsList.utf8).write(to: logs.appendingPathComponent("list.json"))
        }

        /// Its script: notes each run in `logs` (what it was asked, its arguments), prints its list; `extra` after.
        func script(body extra: String) -> String {
            """
            #!/bin/sh
            . "$(dirname "$0")/lib/common.sh"
            . "$(dirname "$0")/../../shared/common.sh"
            printf '%s|%s\\n' "$ALLINONEIME_COMPLETION" "$*" >> '\(logs.path)/calls.log'
            cat '\(logs.path)/list.json'
            \(extra)
            """
        }

        /// What the folders hold, read as the input method reads them: the user's folder, then the source's bundle (only
        /// ever its bundle, `ExtensionSources.loadFolders`).
        var index: ExtensionIndex {
            ExtensionStore.load([ExtensionStore.Folder(path: own.path, found: false)] + config.extensionSources.map {
                ExtensionStore.Folder(path: ExtensionSources.bundleFolder(for: $0, root: sources).path, found: false, bundleOnly: true)
            })
        }

        func command() throws -> ScriptCommand {
            try #require(index.commands.first { $0.name == "tickets" }, "\(index.commands.map(\.name)), skipped \(index.skipped)")
        }

        var calls: String { (try? String(contentsOf: logs.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "" }

        /// `change` made to the bundle.
        func make(_ change: Change) throws {
            switch change {
            case .lib: try write("lib/common.sh", "greeting=bonjour\n")
            case .shared: try write("../../shared/common.sh", "farewell=adieu\n")
            case .script: try write("tickets.sh", script(body: "# fixed upstream"))
            case .added: try write("docs/README.md", "Tickets after TCK-.\n")
            case .prefix: try write("extension.json", ExtensionCompletionsTrustTests.manifest(ExtensionCompletionsTrustTests.tickets(prefix: "TIX-")))
            case .query: try write("extension.json", ExtensionCompletionsTrustTests.manifest(ExtensionCompletionsTrustTests.tickets(query: true)))
            case .compare: try write("extension.json", ExtensionCompletionsTrustTests.manifest(ExtensionCompletionsTrustTests.tickets(compare: "exact")))
            case .refresh: try write("extension.json", ExtensionCompletionsTrustTests.manifest(ExtensionCompletionsTrustTests.tickets(refresh: "2h")))
            }
        }

        /// Whether a change keeps its source on, as the session and Settings ask.
        func follows(_ command: ScriptCommand) -> Bool { config.followsChanges(of: command, root: sources) }

        /// `command`'s digest, as one pinned is read (its source's repository, in this sources folder).
        func digest(_ command: ScriptCommand) -> String? { ExtensionDigest.of(command, root: sources) }

        /// `source` of `command` turned on as Settings turns it on (this sources folder), `sha256` reading its files.
        func enable(_ source: CompletionSource, of command: ScriptCommand, sha256: (URL) -> String? = PluginStore.sha256(of:)) {
            config.setCompletionSource(source, of: command, enabled: true, root: sources, sha256: sha256)
        }

        /// The approvals that no longer hold for `command` as it is now, and those that follow it, as the session finds
        /// them (`digest` reading it).
        func lapsed(_ command: ScriptCommand, digest: ((ScriptCommand) -> String?)? = nil) -> [CompletionSourceApproval] {
            CompletionSourceApproval.lapsed(config.completionSources, extensions: [command], follows: follows, digest: digest ?? self.digest)
        }

        func followed(_ command: ScriptCommand) -> [CompletionSourceApproval] {
            CompletionSourceApproval.followed(config.completionSources, extensions: [command], follows: follows)
        }

        /// Whether its approval holds for `source` of `command` now, as Settings and the session ask.
        func holds(_ source: CompletionSource, of command: ScriptCommand) -> Bool {
            config.approval(of: source, in: command)?.holds(for: source, of: command, follows: follows(command), root: sources) == true
        }
    }

    /// A file's SHA-256 that counts the files it read.
    final class Reads: @unchecked Sendable {
        private let read = Locked(initialState: 0)
        var count: Int { read.withLock { $0 } }
        func sha256(_ url: URL) -> String? {
            read.withLock { $0 += 1 }
            return PluginStore.sha256(of: url)
        }
    }

    static func tickets(prefix: String = "TCK-", query: Bool = false, compare: String = "prefix", refresh: String = "1h") -> String {
        #"{"prefix": "\#(prefix)", "list": true, "refresh": "\#(refresh)", "query": \#(query), "compare": "\#(compare)"}"#
    }

    static func manifest(_ completion: String) -> String {
        #"{"schemaVersion": 1, "name": "desk", "title": "Help Desk", "commands": [{"script": "tickets.sh", "name": "tickets", "title": "Tickets", "completion": \#(completion)}]}"#
    }

    static let ticketsList = #"{"items": [{"match": "TCK-12", "title": "Fix login"}, {"match": "TCK-17", "title": "Dark mode"}]}"#

    // MARK: - What is pinned

    /// The user's own bundle's digest is of every file of the bundle: its extension.json, its script, lib/, a hidden file,
    /// one added anywhere, one renamed or removed; the same files, the same digest. The Finder's and Windows' own files and
    /// git's folder aren't the bundle's. A file the bundle links to is read as itself. A single script's is its file's
    /// SHA-256. (A source's is of its whole repository: ExtensionCompletionsRepositoryTests.)
    @Test func theDigestIsOfEveryFileOfTheBundle() throws {
        let place = try Place(.own)
        try place.desk()
        let folder = place.bundle
        func digest() -> String? { ExtensionDigest.folder(folder, sha256: PluginStore.sha256(of:)) }
        let start = try #require(digest())
        #expect(start.count == 64 && start.allSatisfy(\.isHexDigit))
        let command = try place.command()
        #expect(ExtensionDigest.of(command) == start, "a bundle's command: its bundle's")

        try place.write("lib/common.sh", "greeting=bonjour\n")
        let lib = digest()
        #expect(lib != start, "lib/")
        try place.write("lib/common.sh", "greeting=hello\n")
        #expect(digest() == start, "the same files: the same digest")
        try place.write(".env", "TOKEN_FILE=~/.desk\n")
        #expect(digest() != start, "a hidden file")
        try FileManager.default.moveItem(at: folder.appendingPathComponent(".env"), to: folder.appendingPathComponent("lib/.env"))
        #expect(digest() != start && digest() != lib, "moved")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("lib/.env"))
        #expect(digest() == start, "removed")

        for ignored in [".DS_Store", "lib/.DS_Store", "._tickets.sh", "Icon\r", "Thumbs.db", ".git/FETCH_HEAD", ".git/objects/ab/cdef"] {
            try place.write(ignored, "\(UUID())")
        }
        #expect(digest() == start, "not the bundle's: the Finder's, Windows', git's")

        // A link to a file outside: what it leads to.
        let outside = place.root.appendingPathComponent("shared.sh")
        try Data("shared=1\n".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("lib/shared.sh"), withDestinationURL: outside)
        let linked = digest()
        try Data("shared=2\n".utf8).write(to: outside)
        #expect(linked != start && digest() != linked, "a linked file is read as itself")

        #expect(ExtensionDigest.folder(place.root.appendingPathComponent("none"), sha256: PluginStore.sha256(of:)) == nil)
        let single = ScriptFolder()
        single.add("tickets.sh", script(["title Tickets", "completion \(Self.tickets())"]))
        let script = try #require(single.load().commands.first)
        #expect(ExtensionDigest.of(script) == PluginStore.sha256(of: script.file), "a single script: its file")
    }

    /// Where an extension comes from: a folder of the user's own; an extension source's bundle (its clone in the sources
    /// folder), trusted or not by its switch; in the sources folder as no source's bundle, as one not trusted.
    @Test func whereAnExtensionComesFrom() throws {
        let own = try Place(.own), trusted = try Place(.trusted), untrusted = try Place(.untrusted)
        for place in [own, trusted, untrusted] { try place.desk() }
        let (mine, team, other) = (try own.command(), try trusted.command(), try untrusted.command())
        #expect(own.config.extensionOrigin(of: mine, root: own.sources) == .own)
        let source = try #require(trusted.config.extensionSources.first)
        #expect(trusted.config.extensionOrigin(of: team, root: trusted.sources) == .source(source) && source.trustUpdates)
        #expect(untrusted.config.extensionOrigin(of: other, root: untrusted.sources) == .source(untrusted.config.extensionSources[0]))
        #expect(own.follows(mine) && trusted.follows(team) && !untrusted.follows(other))

        // The same folder, its source gone from the config (a config copied from another Mac): no source's.
        var copied = untrusted.config
        copied.extensionSources = []
        #expect(copied.extensionOrigin(of: other, root: untrusted.sources) == .unknownSource)
        #expect(!copied.followsChanges(of: other, root: untrusted.sources))
        // The sources folder elsewhere: this one is a folder like any other, the user's own.
        #expect(untrusted.config.extensionOrigin(of: other, root: untrusted.root.appendingPathComponent("Other")) == .own)
    }

    // MARK: - The three cases

    /// Every change, each of the three: the user's own and a trusted source's stay on (nothing lapsed), turned on with
    /// nothing of them read (no digest), the approval following only their query and terms (`Config.follow`: a change to
    /// a file has nothing to follow, one to the terms is kept in its place); an untrusted source's, pinned by its whole
    /// repository, lapses (the approval marked so: off, said once), a change out of its bundle as much as one to its
    /// script, and nothing follows. Before the change, all three hold.
    @Test(arguments: Origin.allCases)
    func whatAChangeDoes(_ origin: Origin) throws {
        for change in Change.allCases {
            let place = try Place(origin)
            try place.desk()
            let before = try place.command()
            guard case let .success(source)? = before.completion else { Issue.record("no source"); return }
            let reads = Reads()
            place.enable(source, of: before, sha256: reads.sha256)
            let approval = try #require(place.config.approval(of: source, in: before))
            let pinned = place.digest(before)
            #expect(place.holds(source, of: before), "\(origin): on")
            #expect(place.lapsed(before).isEmpty && place.followed(before).isEmpty)

            try place.make(change)
            let after = try place.command()
            guard case let .success(now)? = after.completion else { Issue.record("\(change): no source"); continue }
            // (The user's own is read as a bundle, the file out of it not its own.)
            if origin != .own || change != .shared { #expect(place.digest(after) != pinned, "\(change): the repository changed") }
            let lapsed = place.lapsed(after, digest: { _ in reads.sha256(place.bundle.appendingPathComponent("tickets.sh")) })
            let followed = place.followed(after)
            switch origin {
            case .own, .trusted:
                #expect(approval.scriptSHA256.isEmpty && reads.count == 0, "\(origin), \(change): nothing of it read (\(reads.count))")
                #expect(lapsed.isEmpty, "\(origin), \(change): stays on")
                #expect(place.holds(now, of: after), "\(origin), \(change)")
                let terms = [.prefix, .query, .compare].contains(change)
                let expected = CompletionSourceApproval(plugin: approval.plugin, source: approval.source, hosts: [], query: now.query,
                                                        scriptSHA256: "", terms: CompletionSourceApproval.Terms(now))
                #expect(followed == (terms ? [expected] : []), "\(origin), \(change): follows its terms only (\(followed))")
                let kept = place.config.follow(followed)
                #expect(kept == terms && place.config.approval(of: now, in: after) == (terms ? expected : approval),
                        "\(origin), \(change): kept in its place")
                let again = place.config.follow(followed)
                #expect(!again, "\(origin), \(change): once")
            case .untrusted:
                #expect(approval.scriptSHA256 == pinned && reads.count > 0, "\(change): its repository pinned")
                #expect(place.lapsed(after) == [approval], "\(origin), \(change): off (\(lapsed))")
                #expect(followed.isEmpty, "\(origin), \(change): nothing follows")
                #expect(!place.holds(now, of: after))
                let marked = place.config.markLapsed(place.lapsed(after))
                #expect(marked && place.config.approval(of: now, in: after)?.lapsed == true)
                #expect(place.lapsed(after).isEmpty, "\(change): said once")
                // Turned on again: what it is now, on.
                place.enable(now, of: after)
                #expect(place.holds(now, of: after), "\(change): on again")
            }
        }
    }

    /// Through a text field, the bundle changed in lib/, or the repository out of the bundle (not its script), since its
    /// source was turned on: the user's own and a trusted source's show their rows, their program run as it is now,
    /// nothing reported followed (nothing of them read: no terms changed) and none lapsed; an untrusted source's shows
    /// none and runs nothing, its approval reported lapsed once (as the field takes the focus, and not again with the next
    /// one).
    @Test(arguments: Origin.allCases, [Change.lib, .shared])
    func throughAField(_ origin: Origin, _ change: Change) async throws {
        try await inEnglish {
            let place = try Place(origin)
            try place.desk()
            let command = try place.command()
            guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
            let world = SuggestionsWorld()
            world.config.extensionSources = place.config.extensionSources
            world.config.setCompletionSource(source, of: command, enabled: true, root: place.sources)
            world.switches = world.config.suggestionsSettings()
            let approval = try #require(world.config.completionSources.first)
            try place.make(change)
            let (lapsed, followed) = (Locked<[CompletionSourceApproval]>(initialState: []), Locked<[CompletionSourceApproval]>(initialState: []))
            func field(_ app: String) -> SuggestionsField {
                world.field(app: app) { services in
                    services.loadExtensions = { _, _ in place.index }
                    services.suggestions.extensionSourcesFolder = place.sources
                    services.suggestions.approvalsLapsed = { found in
                        lapsed.withLock { $0 += found }
                        var config = Config.default
                        config.completionSources = world.switches.enabled
                        config.markLapsed(found)
                        world.switches.enabled = config.completionSources
                    }
                    services.suggestions.approvalsFollowed = { found in followed.withLock { $0 += found } }
                }
            }
            let first = field(SuggestionsApps.editor)
            first.type("TCK-1")
            switch origin {
            case .own, .trusted:
                #expect(first.settle(timeout: 15) { first.rows.map(\.text) == ["TCK-12", "TCK-17"] }, "\(origin): \(first.rows.map(\.text))")
                #expect(place.calls == "load|\n", "\(origin): run as it is now (\(place.calls))")
                #expect(lapsed.withLock { $0 }.isEmpty)
                #expect(approval.scriptSHA256.isEmpty && followed.withLock { $0 }.isEmpty, "\(origin): \(followed.withLock { $0 })")
            case .untrusted:
                first.idle()
                #expect(first.rows.isEmpty && place.calls.isEmpty, "off, nothing run: \(first.rows.map(\.text)), \(place.calls)")
                #expect(lapsed.withLock { $0 } == [approval] && followed.withLock { $0 }.isEmpty, "said: \(lapsed.withLock { $0 })")
                let again = field("com.apple.TextEdit")
                again.type("TCK-1")
                again.idle(0.5)
                #expect(again.rows.isEmpty && lapsed.withLock { $0 } == [approval], "still off, said once")
            }
        }
    }

    // MARK: - Running it

    /// The runner runs only the extension pinned, its source's repository read again as it starts: a change in lib/ since,
    /// or out of the bundle elsewhere in the repository, as one to the script, and nothing runs; one that follows its
    /// changes runs as it is now.
    @Test(arguments: [Change.lib, .shared])
    func theRunnerRunsOnlyWhatWasPinnedUnlessItFollows(_ change: Change) async throws {
        let place = try Place(.untrusted)
        try place.desk()
        let command = try place.command()
        let pinned = try #require(place.digest(command))
        let runner = ExtensionCompletionRunner()
        let store = SuggestionsStore()
        func call(follows: Bool) -> ExtensionCompletionCall {
            ExtensionCompletionCall(command: command, environment: ProcessInfo.processInfo.environment, timeout: 10, scriptSHA256: pinned,
                                    followsChanges: follows, sourcesFolder: place.sources, sha256: { store.sha256(of: $0) })
        }
        _ = try await runner.load(call(follows: false))
        #expect(place.calls == "|\n", "the one pinned runs (\(place.calls))")
        try place.make(change)
        await #expect(throws: ExtensionCompletionError.scriptChanged) { try await runner.load(call(follows: false)) }
        #expect(place.calls == "|\n", "\(change): not run")
        _ = try await runner.load(call(follows: true))
        #expect(place.calls == "|\n|\n", "one that follows runs as it is (\(place.calls))")
    }

    // MARK: - The switch

    /// "Trust its updates" is off by default, and kept with the source in the config as its other fields are: an
    /// optional key, absent for off, `true` when on; anything else read as off. Enabling a source again (a re-review)
    /// keeps it. It is never synced: the source list isn't.
    @Test func theTrustSwitchIsOffByDefaultAndKeptWithTheSource() throws {
        let source = ExtensionSource(url: Self.teamURL)
        #expect(!source.trustUpdates)
        let encoder = JSONEncoder()
        func object(_ source: ExtensionSource) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any])
        }
        #expect(try object(source)["trustUpdates"] == nil, "off: not written")
        var trusted = source
        trusted.trustUpdates = true
        #expect(try object(trusted)["trustUpdates"] as? Bool == true)
        func read(_ json: String) throws -> ExtensionSource { try JSONDecoder().decode(ExtensionSource.self, from: Data(json.utf8)) }
        #expect(try read(#"{"url": "\#(Self.teamURL)"}"#).trustUpdates == false)
        #expect(try read(#"{"url": "\#(Self.teamURL)", "trustUpdates": true}"#).trustUpdates == true)
        #expect(try read(#"{"url": "\#(Self.teamURL)", "trustUpdates": "yes"}"#).trustUpdates == false)
        #expect(try read(#"{"url": "\#(Self.teamURL)", "trustUpdates": null}"#).trustUpdates == false)

        // The config file: written with the source, read back.
        let place = try Place(.trusted)
        let file = place.root.appendingPathComponent("config.json")
        try place.config.write(to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains(#""trustUpdates" : true"#) || text.contains(#""trustUpdates": true"#), "\(text)")
        #expect(try Config.load(from: file).extensionSources.first?.trustUpdates == true)
        #expect(try Config.load(from: file).extensionSources == place.config.extensionSources)

        // Enabled again (reviewed again after a force push): kept; a new source starts off.
        var config = place.config
        ExtensionSources.enable(ExtensionSource(url: Self.teamURL), in: &config, root: place.sources)
        #expect(config.extensionSources.map(\.trustUpdates) == [true])
        ExtensionSources.enable(ExtensionSource(url: "https://git.example.com/other/tools.git"), in: &config, root: place.sources)
        #expect(config.extensionSources.map(\.trustUpdates) == [true, false])

        #expect(ICloudSync.category(of: "extensionSources") == nil && ICloudSync.neverSynced.contains("extensionSources"))
    }

    /// Turning the switch off turns nothing off by itself: what the repository is then (a change made while it was on, not
    /// yet seen; nothing of it was read while trusted) is read and kept as what is approved, and only the next change, out
    /// of the bundle too, turns the source off. Turning it on turns nothing back on: an approval marked lapsed stays off
    /// until turned on again.
    @Test func turningTrustOffTurnsNothingOffByItself() throws {
        let place = try Place(.trusted)
        try place.desk()
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        place.enable(source, of: command)
        #expect(place.config.approval(of: source, in: command)?.scriptSHA256 == "", "trusted: nothing of it read")
        try place.make(.lib)  // an update while trusted, not yet seen
        let updated = try place.command()

        let off = place.config.setTrustUpdates(false, of: Self.teamURL, extensions: [updated], root: place.sources)
        #expect(off && place.config.extensionSources.first?.trustUpdates == false && !place.follows(updated))
        #expect(place.config.approval(of: source, in: updated)?.scriptSHA256 == place.digest(updated), "its repository read then")
        let offAgain = place.config.setTrustUpdates(false, of: Self.teamURL, extensions: [updated], root: place.sources)
        #expect(!offAgain, "already off")
        #expect(place.lapsed(updated).isEmpty, "nothing off by itself")
        #expect(place.holds(source, of: updated))

        try place.make(.shared)  // the next update, out of the bundle
        let next = try place.command()
        let lapsed = place.lapsed(next)
        #expect(lapsed.count == 1, "the next change turns it off")
        place.config.markLapsed(lapsed)

        let on = place.config.setTrustUpdates(true, of: Self.teamURL, extensions: [next], root: place.sources)
        #expect(on)
        #expect(!place.holds(source, of: next), "trusted again: still off until turned on again")
        #expect(place.followed(next).isEmpty)
        let none = place.config.setTrustUpdates(true, of: "https://git.example.com/none.git", extensions: [next], root: place.sources)
        #expect(!none, "no such source")
    }
}
