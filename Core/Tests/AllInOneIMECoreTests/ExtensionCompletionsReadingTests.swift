import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// How a script extension from an extension source is told and read for its completion source's pin (0.6.7.1 §2, the
/// second review): where it comes from is where it was loaded from, never where links lead, and a source's bundle folder
/// that leads out of its clone loads nothing; a file's hash is kept by what can't be set back (its inode and status-change
/// time), not only its size and date; what can't be read all is never pinned; the walk stops past 10,000 items of any
/// kind, going down folders without recursion; and what Settings reads off the main thread, applied after, is what
/// reading at once would do. The places are those of ExtensionCompletionsTrustTests (a temporary folder with the user's
/// folder, the sources' clones, the program's notes).
@Suite(.serialized, SuggestionsOneAtATime())
struct ExtensionCompletionsReadingTests {
    typealias Place = ExtensionCompletionsTrustTests.Place
    typealias Reads = ExtensionCompletionsTrustTests.Reads
    typealias Origin = ExtensionCompletionsTrustTests.Origin

    /// `place`'s bundle folder moved out of the sources folder, a link to it left in its place (as an update could leave
    /// it): where it is now.
    @discardableResult
    static func leadOut(_ place: Place) throws -> URL {
        let fm = FileManager.default
        let elsewhere = place.root.appendingPathComponent("elsewhere/desk", isDirectory: true)
        try fm.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: place.bundle, to: elsewhere)
        try fm.createSymbolicLink(at: place.bundle, withDestinationURL: elsewhere)
        return elsewhere
    }

    /// The bundle "desk" written in `folder`.
    static func desk(in folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(ExtensionCompletionsTrustTests.manifest(ExtensionCompletionsTrustTests.tickets()).utf8)
            .write(to: folder.appendingPathComponent("extension.json"))
        try Data("#!/bin/sh\n".utf8).write(to: folder.appendingPathComponent("tickets.sh"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent("tickets.sh").path)
    }

    /// The command "tickets" of the bundle in `folder`, loaded as a source's bundle is (only ever that bundle).
    static func tickets(in folder: URL) throws -> ScriptCommand {
        let index = ExtensionStore.load([ExtensionStore.Folder(path: folder.path, found: false, bundleOnly: true)])
        return try #require(index.commands.first { $0.name == "tickets" }, "\(index.skipped)")
    }

    // MARK: - Where it was loaded from

    /// A source's bundle folder is that source's wherever it leads, asked before anything else: one that is (or becomes,
    /// after an update) a link out of the sources folder is still its source's, judged by its switch (before, the user's
    /// own: never read, always on), pinned by its source's clone; a folder of the user's that is a link to a source's
    /// bundle folder is that source's too. A folder written in the sources folder that is no source's bundle, its clone a
    /// link out of it, is no source's (not trusted). Only a folder of the user's elsewhere is theirs.
    @Test(arguments: [Origin.trusted, .untrusted])
    func aSourcesFolderIsItsSourcesWhereverItLeads(_ origin: Origin) throws {
        let place = try Place(origin)
        try place.desk()
        let source = try #require(place.config.extensionSources.first)
        let elsewhere = try Self.leadOut(place)
        let command = try place.command()
        #expect(ExtensionSources.comparable(command.extensionDirectory.path) == ExtensionSources.comparable(elsewhere.path),
                "it leads out of the sources folder")
        #expect(place.config.extensionOrigin(of: command, root: place.sources) == .source(source), "\(origin)")
        #expect(place.follows(command) == (origin == .trusted), "\(origin): as its switch says")
        #expect(ExtensionDigest.repositoryFolder(of: command, root: place.sources)?.standardizedFileURL.path
                == place.clone?.standardizedFileURL.path, "pinned by its clone")

        // A folder of the user's, a link to a source's bundle folder (in its clone): that source's.
        let other = try Place(origin)
        try other.desk()
        try FileManager.default.createSymbolicLink(at: other.own.appendingPathComponent("desk"), withDestinationURL: other.bundle)
        let index = ExtensionStore.load([ExtensionStore.Folder(path: other.own.path, found: false)])
        let mine = try #require(index.commands.first { $0.name == "tickets" }, "\(index.skipped)")
        #expect(mine.extensionDirectory.standardizedFileURL.path.hasPrefix(other.own.standardizedFileURL.path))
        #expect(other.config.extensionOrigin(of: mine, root: other.sources) == .source(try #require(other.config.extensionSources.first)))

        // Written in the sources folder, no source's, its clone a link out of it: no source's.
        let target = place.root.appendingPathComponent("stray-target", isDirectory: true)
        try Self.desk(in: target.appendingPathComponent("desk", isDirectory: true))
        let stray = place.sources.appendingPathComponent("stray-1a2b3c4d", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: stray, withDestinationURL: target)
        let strayCommand = try Self.tickets(in: stray.appendingPathComponent("desk", isDirectory: true))
        #expect(place.config.extensionOrigin(of: strayCommand, root: place.sources) == .unknownSource)
        #expect(!place.follows(strayCommand), "not trusted")
        #expect(ExtensionSources.untrustedFolders(in: place.config.with { $0.extensionFolders.append(stray.path + "/desk") },
                                                  statuses: [source.url: ExtensionSourceStatus(url: source.url, trusted: true)],
                                                  root: place.sources) == [stray.path + "/desk"], "kept out of the load list")

        // The same bundle in a folder of the user's own: theirs.
        let own = try Self.tickets(in: target.appendingPathComponent("desk", isDirectory: true))
        #expect(place.config.extensionOrigin(of: own, root: place.sources) == .own)
    }

    /// A source's bundle folder that leads out of its clone loads nothing, whatever it holds: one an update turned into a
    /// link out of the sources folder, one that leads into another source's clone, one whose path climbs out. One that
    /// links elsewhere in its own clone loads. Its source stays enabled and in the load list, not taken out (a Re-clone
    /// puts it right).
    @Test func aBundleThatLeadsOutOfItsCloneLoadsNothing() throws {
        let place = try Place(.trusted)
        try place.desk()
        let source = try #require(place.config.extensionSources.first)
        let clone = try #require(place.clone)
        let statuses = [source.url: ExtensionSourceStatus(url: source.url, trusted: true)]
        func loaded() -> [String] {
            ExtensionStore.load(ExtensionSources.loadFolders(place.config, found: [], statuses: statuses, root: place.sources)).commands.map(\.name)
        }
        func leaves() -> Bool { ExtensionSources.leavesClone(source, root: place.sources) }
        #expect(loaded() == ["tickets"] && !leaves())

        // Elsewhere in its own clone: loads.
        let fm = FileManager.default
        let inside = clone.appendingPathComponent("moved/desk", isDirectory: true)
        try fm.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: place.bundle, to: inside)
        try fm.createSymbolicLink(at: place.bundle, withDestinationURL: inside)
        #expect(loaded() == ["tickets"] && !leaves(), "a link in its clone")
        try fm.removeItem(at: place.bundle)
        try fm.moveItem(at: inside, to: place.bundle)

        // An update leaves a link out of the sources folder in its place: nothing loads.
        let elsewhere = try Self.leadOut(place)
        #expect(leaves() && loaded().isEmpty, "a link out: \(loaded())")
        #expect(ExtensionSources.isEnabled(source, in: place.config, root: place.sources), "still enabled")
        #expect(ExtensionSources.untrustedFolders(in: place.config, statuses: statuses, root: place.sources).isEmpty, "not taken out")
        // Into another source's clone: out of its own all the same.
        try fm.removeItem(at: place.bundle)
        let another = place.sources.appendingPathComponent("tools-0a1b2c3d/desk", isDirectory: true)
        try fm.createDirectory(at: another.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: elsewhere, to: another)
        try fm.createSymbolicLink(at: place.bundle, withDestinationURL: another)
        #expect(leaves() && loaded().isEmpty, "into another clone: \(loaded())")
        // Put back: loads again, nothing to undo.
        try fm.removeItem(at: place.bundle)
        try fm.moveItem(at: another, to: place.bundle)
        #expect(loaded() == ["tickets"] && !leaves())

        // A path that climbs out leads out as much.
        #expect(ExtensionSources.leavesClone(ExtensionSource(url: source.url, path: "extensions/../../elsewhere"), root: place.sources))
        // A clone that isn't there doesn't lead out (it says it is missing).
        #expect(!ExtensionSources.leavesClone(ExtensionSource(url: "https://git.example.com/none.git", path: "ext"), root: place.sources))
    }

    // MARK: - What a hash is kept by

    /// A file's hash is kept by more than its size and date, which a program can set back after changing it: by its inode
    /// (another file put in its place) and the time its status changed (set by every write, never back). Changed with its
    /// size and date set back, or replaced by another of the same size and date, it is read again, by the one store a
    /// plugin's script and an extension's files are hashed by (`SuggestionsStore.sha256`), and so its repository's digest
    /// changes. Unchanged, the same stamp: kept.
    @Test func aFileChangedWithItsSizeAndDateSetBackIsReadAgain() throws {
        let place = try Place(.untrusted)
        try place.desk()
        let command = try place.command()
        let file = try #require(place.clone).appendingPathComponent("shared/common.sh")
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        func dated(_ url: URL) throws { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        try dated(file)
        let store = SuggestionsStore()
        let before = try #require(FileHashes.stamp(file.path))
        let sha = try #require(store.sha256(of: file))
        let digest = try #require(ExtensionDigest.of(command, root: place.sources, sha256: store.sha256(of:)))
        #expect(FileHashes.stamp(file.path) == before, "unchanged: the same stamp")

        try Data("farewell=cya\n".utf8).write(to: file)  // as many bytes as "farewell=bye\n"
        try dated(file)
        let after = try #require(FileHashes.stamp(file.path))
        #expect(after.size == before.size && after.seconds == before.seconds && after.nanoseconds == before.nanoseconds,
                "its size and date set back: \(before) → \(after)")
        #expect(after != before, "its status changed")
        #expect(store.sha256(of: file) == PluginStore.sha256(of: file) && store.sha256(of: file) != sha, "read again")
        #expect(ExtensionDigest.of(command, root: place.sources, sha256: store.sha256(of:)) != digest, "the digest changed")

        // Another file of the same size and date put in its place.
        let now = try #require(store.sha256(of: file))
        let other = file.deletingLastPathComponent().appendingPathComponent("common.sh.new")
        try Data("farewell=bye\n".utf8).write(to: other)
        try dated(other)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: other, to: file)
        let replaced = try #require(FileHashes.stamp(file.path))
        #expect(replaced.size == after.size && replaced.seconds == after.seconds && replaced.inode != after.inode)
        #expect(store.sha256(of: file) == PluginStore.sha256(of: file) && store.sha256(of: file) != now, "another file: read again")
        #expect(ExtensionDigest.of(command, root: place.sources, sha256: store.sha256(of:)) == digest, "the files it was turned on with")
    }

    // MARK: - What can't be read

    /// What can't be read all is never pinned: a folder of the repository that can't be listed, an item whose kind can't
    /// be told (in a folder that can be listed but not searched), a file that can't be read; the user's own bundle's
    /// digest as much. Such an extension can't be turned on (Settings and the settings document say its files can't be
    /// read; the document refuses), and one approved is turned off as on a change (found lapsed, its program not run).
    /// Readable again, it is what it was.
    @Test func whatCantBeReadIsNeverPinned() async throws {
        let place = try Place(.untrusted)
        try place.desk()
        let clone = try #require(place.clone)
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        let fm = FileManager.default
        let locked = clone.appendingPathComponent("private", isDirectory: true)
        let notes = locked.appendingPathComponent("notes.txt")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("x\n".utf8).write(to: notes)
        func mode(_ url: URL, _ mode: Int) { try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }
        defer { mode(locked, 0o755); mode(notes, 0o644) }
        let readable = try #require(place.digest(command))
        let unreadable = ScriptCompletionState(on: false, changed: false, tooLarge: false, unreadable: true)

        for (what, url, bits) in [("a folder that can't be listed", locked, 0o000), ("an item whose kind can't be told", locked, 0o444),
                                  ("a file that can't be read", notes, 0o000)] {
            mode(url, bits)
            defer { mode(url, url == locked ? 0o755 : 0o644) }
            if url == locked, bits == 0o444 {
                var kinds: [ExtensionDigest.Item.Kind] = []
                #expect(ExtensionDigest.eachItem(in: locked.path) { kinds.append($0.kind); return true } == true)
                #expect(kinds == [.unreadable], "listed, its kind not told: \(kinds)")
            }
            #expect(place.digest(command) == nil, "\(what): no digest")
            #expect(ExtensionDigest.folder(clone, sha256: PluginStore.sha256(of:)) == nil, "\(what): the bundle walk's either")
            #expect(CompletionSourceApproval(enabling: source, of: command, root: place.sources) == nil, "\(what)")
            var config = place.config
            config.setCompletionSource(source, of: command, enabled: true, root: place.sources)
            #expect(config.completionSources.isEmpty, "\(what): it can't be turned on")
            let state = config.completionState(of: source, in: command, root: place.sources)
            #expect(state == unreadable && state.cantTurnOn == CompletionSource.repositoryUnreadable, "\(what): \(state)")
        }
        #expect(place.digest(command) == readable, "readable again: what it was")

        // One turned on, then not all of it readable: off, as on a change, and its program not run.
        place.enable(source, of: command)
        let approval = try #require(place.config.completionSources.first)
        #expect(approval.scriptSHA256 == readable && place.lapsed(command).isEmpty)
        mode(locked, 0o000)
        #expect(place.lapsed(command) == [approval], "turned off")
        #expect(place.config.completionState(of: source, in: command, root: place.sources) == unreadable)
        let call = ExtensionCompletionCall(command: command, environment: ProcessInfo.processInfo.environment, timeout: 10,
                                           scriptSHA256: approval.scriptSHA256, sourcesFolder: place.sources)
        await #expect(throws: ExtensionCompletionError.scriptChanged) { try await ExtensionCompletionRunner().load(call) }
        #expect(place.calls.isEmpty, "not run: \(place.calls)")

        // The settings document says so under the command, and won't turn it on.
        var config = place.config
        config.completionSources = []
        let url = place.root.appendingPathComponent("config.json")
        try config.write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac,
                                      library: PluginLibrary(directory: place.root.appendingPathComponent("plugins", isDirectory: true)),
                                      secrets: .inMemory())
        service.extensionSourcesFolder = place.sources
        try await withInterfaceLanguage("en") {
            let id = "extensions.completion." + command.id
            let field = try #require(service.document().field(id))
            #expect(field.value == .bool(false) && field.status == CompletionSource.repositoryUnreadable, "\(field)")
            guard case let .failure(problem) = service.set(id, to: .bool(true)) else { Issue.record("turned on"); return }
            #expect(problem.message == CompletionSource.repositoryUnreadable, "\(problem)")
            #expect(try Config.load(from: url).completionSources.isEmpty)
            #expect(CompletionSource.repositoryUnreadable == "Some of its files can't be read, so it can't be checked for changes.")
        }
        await withInterfaceLanguage("zh") { #expect(CompletionSource.repositoryUnreadable == "它有些文件读不了，没法检查改动。") }
    }

    // MARK: - How far the walk goes

    /// The items a walk of `folder` lists: every name in it and in its folders, `.git` once but nothing in it.
    static func items(in folder: URL) -> Int {
        var count = 0
        var folders = [folder.path]
        while let next = folders.popLast() {
            _ = ExtensionDigest.eachItem(in: next) { item in
                count += 1
                if item.kind == .folder, item.name != ".git" { folders.append(next + "/" + item.name) }
                return true
            }
        }
        return count
    }

    /// The walk counts every item it lists, whatever its kind: past 10,000 (empty folders, `.DS_Store`s, any name) it
    /// stops, nothing read, as past 2,000 files, and the repository is too large (the same message in Settings); what is
    /// in `.git` is never listed, however much. It goes down folders one after another, never by recursion: a file 300
    /// folders down is pinned like any other.
    @Test func theWalkStopsPastTenThousandItemsOfAnyKind() throws {
        let place = try Place(.untrusted)
        try place.desk()
        let clone = try #require(place.clone)
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        let fm = FileManager.default
        #expect(ExtensionDigest.maxEntries == 10_000)

        // In .git: more than 10,000 items, never listed.
        let objects = clone.appendingPathComponent(".git/objects", isDirectory: true)
        try fm.createDirectory(at: objects, withIntermediateDirectories: true)
        for index in 0...ExtensionDigest.maxEntries { #expect(fm.createFile(atPath: objects.appendingPathComponent("\(index)").path, contents: nil)) }
        let pinned = try #require(place.digest(command))
        #expect(pinned != ExtensionDigest.tooLarge, ".git isn't walked")

        // Empty folders and the Finder's files up to 10,000 items in all: pinned; one more: too large, nothing read.
        let many = clone.appendingPathComponent("many", isDirectory: true)
        try fm.createDirectory(at: many, withIntermediateDirectories: true)
        let room = ExtensionDigest.maxEntries - Self.items(in: clone)
        for index in 0..<(room - 1) { try fm.createDirectory(at: many.appendingPathComponent("folder-\(index)"), withIntermediateDirectories: false) }
        #expect(fm.createFile(atPath: many.appendingPathComponent(".DS_Store").path, contents: Data("x".utf8)))
        #expect(Self.items(in: clone) == ExtensionDigest.maxEntries)
        let atLimit = place.digest(command)
        #expect(atLimit != nil && atLimit != ExtensionDigest.tooLarge, "10,000 items: pinned")
        #expect(atLimit == pinned, "empty folders and .DS_Store aren't files of it")
        #expect(fm.createFile(atPath: many.appendingPathComponent("folder-0/.DS_Store").path, contents: Data("x".utf8)))
        let reads = Reads()
        #expect(ExtensionDigest.of(command, root: place.sources, sha256: reads.sha256) == ExtensionDigest.tooLarge)
        #expect(reads.count == 0, "nothing read past it (\(reads.count))")
        var config = place.config
        config.setCompletionSource(source, of: command, enabled: true, root: place.sources)
        let state = config.completionState(of: source, in: command, root: place.sources)
        #expect(config.completionSources.isEmpty && state.tooLarge && state.cantTurnOn == CompletionSource.repositoryTooLarge)
        try fm.removeItem(at: many)

        // 300 folders down.
        var deep = clone
        for _ in 0..<300 { deep.appendPathComponent("d", isDirectory: true) }
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        let bottom = deep.appendingPathComponent("bottom.txt")
        try Data("1\n".utf8).write(to: bottom)
        let one = try #require(place.digest(command))
        try Data("2\n".utf8).write(to: bottom)
        let two = try #require(place.digest(command))
        #expect(one != pinned && two != one && two != ExtensionDigest.tooLarge, "a file 300 folders down is pinned")
    }

    // MARK: - Read off the main thread, applied after

    /// What Settings reads off the main thread and applies after is what reading and applying at once does, and applying
    /// reads nothing: a switch's state from a digest read already, turning on with it (none for one that follows; nothing
    /// with no digest or one too large), "Trust its updates" off with what `pinsWithoutTrust` read.
    @Test(arguments: Origin.allCases)
    func readingThenApplyingIsReadingAtOnce(_ origin: Origin) throws {
        let place = try Place(origin)
        try place.desk()
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        let follows = place.follows(command)
        let read = follows ? nil : place.digest(command)
        var atOnce = place.config, after = place.config
        atOnce.setCompletionSource(source, of: command, enabled: true, root: place.sources)
        after.setCompletionSource(source, of: command, enabled: true, digest: read, root: place.sources)
        #expect(after == atOnce && !after.completionSources.isEmpty, "\(origin): turned on alike")
        #expect(after.completionState(of: source, in: command, follows: follows, digest: read)
                == atOnce.completionState(of: source, in: command, root: place.sources), "\(origin): the same state")
        if !follows {
            for digest in [nil, ExtensionDigest.tooLarge] {
                var none = place.config
                none.setCompletionSource(source, of: command, enabled: true, digest: digest, root: place.sources)
                #expect(none.completionSources.isEmpty, "\(origin): not with \(digest ?? "no digest")")
            }
        }
        guard origin == .trusted, let url = place.config.extensionSources.first?.url else { return }
        // "Trust its updates" off: what it pins read first, then applied.
        let reads = Reads()
        let pins = atOnce.pinsWithoutTrust(of: url, extensions: [command], root: place.sources, sha256: reads.sha256)
        #expect(reads.count > 0 && pins.first?.scriptSHA256 == ExtensionDigest.of(command, root: place.sources))
        var direct = atOnce, applied = atOnce
        direct.setTrustUpdates(false, of: url, extensions: [command], root: place.sources)
        let changed = applied.setTrustUpdates(false, of: url, pinning: pins)
        #expect(changed && applied == direct && applied.extensionSources.first?.trustUpdates == false, "the same, saved alike")
        let again = applied.setTrustUpdates(false, of: url, pinning: pins)
        #expect(!again, "once")
    }
}

private extension Config {
    func with(_ change: (inout Config) -> Void) -> Config {
        var config = self
        change(&config)
        return config
    }
}
