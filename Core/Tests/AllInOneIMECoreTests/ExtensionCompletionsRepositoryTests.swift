import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A script extension from an extension source, as its completion source pins it (0.6.7.1 §2): by every file of its
/// source's repository (a script may use `../shared/common.sh`, or a link to a folder elsewhere in the clone), all but
/// git's `.git` and the Finder's `.DS_Store`, a link as where it points; never one of more than 2,000 files or 20 MB,
/// which can't be turned on, and one that grows past it is turned off as a change would; read only for one whose changes
/// turn it off, and never with a key. Two sources never share a clone's folder. The places are those of
/// ExtensionCompletionsTrustTests (a temporary folder with the user's folder, the sources' clones, the program's notes).
@Suite(.serialized, SuggestionsOneAtATime())
struct ExtensionCompletionsRepositoryTests {
    typealias Place = ExtensionCompletionsTrustTests.Place
    typealias Reads = ExtensionCompletionsTrustTests.Reads

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// A place from `origin` with the bundle "desk" written and `count` more files of `size` bytes in its repository
    /// (data/, out of the bundle; the user's own: beside the bundle in their folder).
    static func place(_ origin: ExtensionCompletionsTrustTests.Origin, files count: Int = 0, size: Int = 16) throws -> Place {
        let place = try Place(origin)
        try place.desk()
        try fill(place, count, size: size)
        return place
    }

    /// `count` files of `size` bytes in data/ of `place`'s repository (the user's own: their folder), from `start` on.
    static func fill(_ place: Place, _ count: Int, size: Int = 16, from start: Int = 0) throws {
        guard count > 0 else { return }
        let data = (place.clone ?? place.own).appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let bytes = Data(repeating: UInt8(ascii: "x"), count: size)
        for index in start..<(start + count) { try bytes.write(to: data.appendingPathComponent("file-\(index).txt")) }
    }

    /// How many files `place`'s repository holds (links too), but .git's and .DS_Store.
    static func files(in folder: URL) -> Int {
        let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        var count = 0
        while let url = walk?.nextObject() as? URL {
            if url.lastPathComponent == ".git" { walk?.skipDescendants(); continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if url.lastPathComponent != ".DS_Store", values?.isRegularFile == true || values?.isSymbolicLink == true { count += 1 }
        }
        return count
    }

    // MARK: - What is pinned

    /// A source's extension is pinned by its whole repository (its clone): a file its script uses out of its bundle
    /// (shared/common.sh), a file of a folder elsewhere in the clone its bundle links to (lib/), the link itself as where
    /// it points (never followed: a file it leads to out of the clone isn't the source's); every name but .git and
    /// .DS_Store, wherever they are (the Finder's `._` files, `Icon\r`, Windows' files are files of the repository). The
    /// user's own keeps its bundle's rule.
    @Test func aSourcesDigestIsOfItsWholeRepository() throws {
        let place = try Self.place(.untrusted)
        let clone = try #require(place.clone)
        let command = try place.command()
        #expect(ExtensionDigest.repositoryFolder(of: command, root: place.sources)?.standardizedFileURL.path
                == clone.standardizedFileURL.path, "its source's clone")
        let fm = FileManager.default
        func write(_ path: String, _ text: String) throws {
            let file = clone.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        func digest() -> String? { place.digest(command) }
        let start = try #require(digest())
        #expect(start.count == 64 && start.allSatisfy(\.isHexDigit) && start != ExtensionDigest.folder(place.bundle, sha256: PluginStore.sha256(of:)))

        try write("shared/common.sh", "farewell=adieu\n")
        let shared = digest()
        #expect(shared != start, "a file out of the bundle, elsewhere in the repository")
        try write("shared/common.sh", "farewell=bye\n")
        #expect(digest() == start, "the same files: the same digest")

        // lib/ a link to a folder elsewhere in the clone: what is in it changes the digest, as does where it points.
        try fm.removeItem(at: place.bundle.appendingPathComponent("lib"))
        try write("tools/lib/common.sh", "greeting=hello\n")
        try write("tools/other/common.sh", "greeting=hello\n")
        try fm.createSymbolicLink(atPath: place.bundle.appendingPathComponent("lib").path, withDestinationPath: "../../tools/lib")
        let linked = try #require(digest())
        try write("tools/lib/common.sh", "greeting=bonjour\n")
        let changedThere = digest()
        #expect(changedThere != linked, "a file of the folder the link leads to, in the clone")
        try write("tools/lib/common.sh", "greeting=hello\n")
        try fm.removeItem(at: place.bundle.appendingPathComponent("lib"))
        try fm.createSymbolicLink(atPath: place.bundle.appendingPathComponent("lib").path, withDestinationPath: "../../tools/other")
        #expect(digest() != linked, "pointed elsewhere (the same files there): the link is where it points")

        // A link out of the clone: what it leads to isn't the source's, only where it points is.
        let outside = place.root.appendingPathComponent("outside.sh")
        try Data("outside=1\n".utf8).write(to: outside)
        try fm.createSymbolicLink(atPath: clone.appendingPathComponent("outside.sh").path, withDestinationPath: outside.path)
        let out = digest()
        try Data("outside=2, longer\n".utf8).write(to: outside)
        #expect(digest() == out, "never followed out of the clone")

        // Only git's folder and the Finder's .DS_Store are left out of a repository, wherever they are.
        for ignored in [".DS_Store", "extensions/desk/.DS_Store", ".git/FETCH_HEAD", ".git/objects/ab/cdef", "tools/.git/HEAD"] {
            try write(ignored, "\(UUID())")
        }
        #expect(digest() == out, "git's and the Finder's .DS_Store aren't the repository's")
        var last = out
        for name in ["._tickets.sh", "Icon\r", "Thumbs.db", "desktop.ini", ".env"] {
            try write("extensions/desk/" + name, "\(UUID())")
            let now = digest()
            #expect(now != last, "\(name.debugDescription) is a file of the repository")
            last = now
        }
        #expect(ExtensionDigest.repository(place.root.appendingPathComponent("none"), sha256: PluginStore.sha256(of:)) == nil)

        // The user's own: its bundle, as before (a file beside it isn't of it).
        let own = try Self.place(.own)
        let mine = try own.command()
        #expect(ExtensionDigest.repositoryFolder(of: mine, root: own.sources) == nil)
        #expect(ExtensionDigest.of(mine, root: own.sources) == ExtensionDigest.folder(own.bundle, sha256: PluginStore.sha256(of:)))
    }

    // MARK: - Only what can turn off is read

    /// The user's own and a trusted source's are never read for their approval: turned on, shown in Settings and checked
    /// for changes without one file read, so a trusted source's turns on whatever its repository's size (here past the
    /// limits: there is nothing to pin). An untrusted source's is read.
    @Test(arguments: ExtensionCompletionsTrustTests.Origin.allCases)
    func onlyWhatCanTurnOffIsRead(_ origin: ExtensionCompletionsTrustTests.Origin) throws {
        let place = try Self.place(origin, files: origin == .trusted ? ExtensionDigest.maxFiles + 1 : 0)
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        let reads = Reads()
        place.enable(source, of: command, sha256: reads.sha256)
        let state = place.config.completionState(of: source, in: command, root: place.sources, sha256: reads.sha256)
        let lapsed = place.lapsed(command, digest: { ExtensionDigest.of($0, root: place.sources, sha256: reads.sha256) })
        #expect(state == ScriptCompletionState(on: true, changed: false, tooLarge: false) && lapsed.isEmpty, "\(origin): \(state)")
        if origin == .untrusted {
            #expect(reads.count > 0 && place.config.completionSources.first?.scriptSHA256 == place.digest(command))
        } else {
            #expect(reads.count == 0 && place.config.completionSources.first?.scriptSHA256 == "", "\(origin): \(reads.count) read")
        }
    }

    // MARK: - The size limits

    /// A repository of more than 2,000 files (links count) or 20 MB in all can't be pinned: counted while walking, it
    /// stops past the limit, nothing read; its source can't be turned on, and Settings says why. At the limits it can.
    @Test func aRepositoryPastTheLimitsCantBeTurnedOn() async throws {
        try await inEnglish {
            let place = try Self.place(.untrusted)
            let clone = try #require(place.clone)
            let command = try place.command()
            guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
            try Self.fill(place, ExtensionDigest.maxFiles - Self.files(in: clone))
            #expect(Self.files(in: clone) == ExtensionDigest.maxFiles)
            let atLimit = try #require(place.digest(command))
            #expect(atLimit != ExtensionDigest.tooLarge, "2,000 files: pinned")

            try FileManager.default.createSymbolicLink(atPath: clone.appendingPathComponent("one-more").path, withDestinationPath: "README.md")
            let reads = Reads()
            #expect(ExtensionDigest.of(command, root: place.sources, sha256: reads.sha256) == ExtensionDigest.tooLarge)
            #expect(reads.count == 0, "nothing read past the limit (\(reads.count))")
            // The walk stops where it is told to, in the middle of a folder: no more of it listed.
            var listed = 0
            let all = ExtensionDigest.eachItem(in: clone.appendingPathComponent("data").path) { _ in
                listed += 1
                return listed < 3
            }
            #expect(all == false && listed == 3, "\(listed) listed")
            #expect(CompletionSourceApproval(enabling: source, of: command, root: place.sources) == nil)
            place.enable(source, of: command)
            #expect(place.config.completionSources.isEmpty, "it can't be turned on")
            #expect(place.config.completionState(of: source, in: command, root: place.sources)
                    == ScriptCompletionState(on: false, changed: false, tooLarge: true))
            #expect(CompletionSource.repositoryTooLarge == "Its repository is too large to check for changes (over 2,000 files or 20 MB).")

            // Its bytes: 20 MB in all at most (a file of its own, sparse: its size, nothing written).
            try FileManager.default.removeItem(at: clone.appendingPathComponent("data"))
            try FileManager.default.removeItem(at: clone.appendingPathComponent("one-more"))
            let big = clone.appendingPathComponent("data/big.bin")
            try FileManager.default.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
            #expect(FileManager.default.createFile(atPath: big.path, contents: nil))
            let handle = try FileHandle(forWritingTo: big)
            let others = try Self.bytes(in: clone)
            try handle.truncate(atOffset: UInt64(ExtensionDigest.maxBytes - others))
            #expect(place.digest(command) != ExtensionDigest.tooLarge, "20 MB: pinned")
            try handle.truncate(atOffset: UInt64(ExtensionDigest.maxBytes - others + 1))
            try handle.close()
            #expect(place.digest(command) == ExtensionDigest.tooLarge, "a byte more: too large")
        }
    }

    /// The bytes of the files in `folder` (but .git's and .DS_Store).
    static func bytes(in folder: URL) throws -> Int {
        let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        var bytes = 0
        while let url = walk?.nextObject() as? URL {
            if url.lastPathComponent == ".git" { walk?.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            if url.lastPathComponent != ".DS_Store", values.isSymbolicLink != true, values.isRegularFile == true { bytes += values.fileSize ?? 0 }
        }
        return bytes
    }

    /// One approved that grows past the limits is turned off as a change would: found lapsed (said once), its rows gone
    /// as the next field takes the focus, its program not run (read again as it starts), Settings saying why.
    @Test func anApprovedRepositoryThatGrowsPastTheLimitsIsTurnedOff() async throws {
        let place = try Self.place(.untrusted)
        let command = try place.command()
        guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
        let world = SuggestionsWorld()
        world.config.extensionSources = place.config.extensionSources
        world.config.setCompletionSource(source, of: command, enabled: true, root: place.sources)
        world.switches = world.config.suggestionsSettings()
        let approval = try #require(world.config.completionSources.first)
        let lapsed = Locked<[CompletionSourceApproval]>(initialState: [])
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
            }
        }
        await inEnglish {
            let first = field(SuggestionsApps.editor)
            first.type("TCK-1")
            #expect(first.settle(timeout: 15) { first.rows.map(\.text) == ["TCK-12", "TCK-17"] }, "on: \(first.rows.map(\.text))")
        }

        try Self.fill(place, ExtensionDigest.maxFiles)
        #expect(place.digest(command) == ExtensionDigest.tooLarge)
        let runner = ExtensionCompletionRunner()
        let call = ExtensionCompletionCall(command: command, environment: ProcessInfo.processInfo.environment, timeout: 10,
                                           scriptSHA256: approval.scriptSHA256, sourcesFolder: place.sources)
        let calls = place.calls
        await #expect(throws: ExtensionCompletionError.scriptChanged) { try await runner.load(call) }
        #expect(place.calls == calls, "not run")

        await inEnglish {
            let next = field("com.apple.TextEdit")
            next.type("TCK-1")
            next.idle(0.5)
            #expect(next.rows.isEmpty && place.calls == calls, "off, nothing run: \(next.rows.map(\.text)), \(place.calls)")
            #expect(lapsed.withLock { $0 } == [approval], "said: \(lapsed.withLock { $0 })")
            let again = field("com.apple.mail")
            again.type("TCK-1")
            again.idle(0.5)
            #expect(again.rows.isEmpty && lapsed.withLock { $0 } == [approval], "said once")
        }
        var config = place.config
        config.completionSources = world.switches.enabled
        #expect(config.completionState(of: source, in: command, root: place.sources)
                == ScriptCompletionState(on: false, changed: false, tooLarge: true), "Settings says it is too large")
    }

    /// The settings document says so under the command (its switch's status) and refuses to turn it on, with the reason;
    /// under the limits it turns on.
    @Test func theSettingsDocumentSaysARepositoryIsTooLarge() async throws {
        let place = try Self.place(.untrusted, files: ExtensionDigest.maxFiles + 1)
        let command = try place.command()
        let url = place.root.appendingPathComponent("config.json")
        try place.config.write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac,
                                      library: PluginLibrary(directory: place.root.appendingPathComponent("plugins", isDirectory: true)),
                                      secrets: .inMemory())
        service.extensionSourcesFolder = place.sources
        try await withInterfaceLanguage("en") {
            let id = "extensions.completion." + command.id
            let field = try #require(service.document().field(id), "\(service.document().sections.flatMap(\.fields).map(\.id).filter { $0.hasPrefix("extensions.") })")
            #expect(field.value == .bool(false) && field.status == CompletionSource.repositoryTooLarge, "\(field)")
            guard case let .failure(problem) = service.set(id, to: .bool(true)) else { Issue.record("turned on"); return }
            #expect(problem.message == CompletionSource.repositoryTooLarge, "\(problem)")
            let saved = try Config.load(from: url)
            #expect(saved.completionSources.isEmpty)
        }
        #expect((try? service.set("uiLanguage", to: .string("zh-Hans")).get()) != nil)
        #expect(service.document().field("extensions.completion." + command.id)?.status == "它的仓库太大，没法检查改动（超过 2,000 个文件或 20 MB）。")
        #expect((try? service.set("uiLanguage", to: .string("en")).get()) != nil)
        try FileManager.default.removeItem(at: try #require(place.clone).appendingPathComponent("data"))
        try await withInterfaceLanguage("en") {
            let id = "extensions.completion." + command.id
            #expect(service.document().field(id)?.status == nil)
            #expect((try? service.set(id, to: .bool(true)).get()) != nil)
            let saved = try Config.load(from: url)
            #expect(saved.completionSources.first?.scriptSHA256 == place.digest(command))
            #expect(service.document().field(id)?.value == .bool(true))
        }
    }

    // MARK: - Never with a key

    /// The pin is read as a field takes the focus, never with a key: a change to the repository while typing in the same
    /// field isn't seen by its keys (nothing reported), only by the next field (reported once); its program, read again as
    /// it starts, doesn't run meanwhile.
    @Test func aKeyReadsNoFile() async throws {
        try await inEnglish {
            let place = try Self.place(.untrusted)
            let command = try place.command()
            guard case let .success(source)? = command.completion else { Issue.record("no source"); return }
            let world = SuggestionsWorld()
            world.config.extensionSources = place.config.extensionSources
            world.config.setCompletionSource(source, of: command, enabled: true, root: place.sources)
            world.switches = world.config.suggestionsSettings()
            let lapsed = Locked<[CompletionSourceApproval]>(initialState: [])
            func field(_ app: String) -> SuggestionsField {
                world.field(app: app) { services in
                    services.loadExtensions = { _, _ in place.index }
                    services.suggestions.extensionSourcesFolder = place.sources
                    services.suggestions.approvalsLapsed = { found in lapsed.withLock { $0 += found } }
                }
            }
            let typing = field(SuggestionsApps.editor)
            typing.type("TCK-1")
            #expect(typing.settle(timeout: 15) { typing.rows.map(\.text) == ["TCK-12", "TCK-17"] }, "\(typing.rows.map(\.text))")
            try place.make(.shared)
            typing.type("2")
            typing.idle(0.3)
            #expect(lapsed.withLock { $0 }.isEmpty, "a key read nothing")
            let next = field("com.apple.TextEdit")
            next.idle(0.3)
            #expect(lapsed.withLock { $0 }.count == 1, "the next field's focus did")
            #expect(place.calls == "load|\n", "run once, before the change (\(place.calls))")
        }
    }

    // MARK: - Two sources, one folder

    /// Two addresses whose clones' folders would be one (the repository's name and a 4-byte hash of the address, the same
    /// for these two): the second is refused while the first is configured, with the reason; one already configured with
    /// the other (a config written by hand) is no source's (not trusted, whatever its switch).
    @Test func twoSourcesNeverShareAFolder() throws {
        let (first, second) = ("https://git.example.com/team47341/tools.git", "https://git.example.com/team67519/tools.git")
        #expect(ExtensionSources.folderName(for: first) == "tools-4317a211" && ExtensionSources.folderName(for: second) == "tools-4317a211")
        let place = try Place(.own)
        var config = place.config
        ExtensionSources.enable(ExtensionSource(url: first, trustUpdates: true), in: &config, root: place.sources)
        #expect(ExtensionSources.sharingFolder(with: second, in: config)?.url == first)
        #expect(throws: ExtensionSourceError.folderTaken(folder: "tools-4317a211", by: first)) {
            try ExtensionSources.checkFolder(for: second, in: config)
        }
        #expect(ExtensionSourceError.folderTaken(folder: "tools-4317a211", by: first).errorDescription
                == "Its folder, tools-4317a211, is already another source's (\(first)): remove that source first")
        #expect(throws: Never.self) { try ExtensionSources.checkFolder(for: first, in: config) }
        #expect(throws: Never.self) { try ExtensionSources.checkFolder(for: "https://git.example.com/team1/tools.git", in: config) }

        // Its extension: the first's while it is alone; no source's once both are configured.
        let bundle = ExtensionSources.bundleFolder(for: config.extensionSources[0], root: place.sources)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(ExtensionCompletionsTrustTests.manifest(ExtensionCompletionsTrustTests.tickets()).utf8)
            .write(to: bundle.appendingPathComponent("extension.json"))
        try Data("#!/bin/sh\n".utf8).write(to: bundle.appendingPathComponent("tickets.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundle.appendingPathComponent("tickets.sh").path)
        let command = try #require(ExtensionStore.load([ExtensionStore.Folder(path: bundle.path, found: false, bundleOnly: true)]).commands.first)
        #expect(config.extensionOrigin(of: command, root: place.sources) == .source(config.extensionSources[0]))
        #expect(config.followsChanges(of: command, root: place.sources))
        config.extensionSources.append(ExtensionSource(url: second, trustUpdates: true))
        #expect(config.extensionOrigin(of: command, root: place.sources) == .unknownSource)
        #expect(!config.followsChanges(of: command, root: place.sources), "not trusted")
    }

    // MARK: - What it costs

    /// What pinning costs for a repository at the file limit (2,000 files, 16 MB): the pin a field reads as it takes the
    /// focus and the check before each run, with no hash kept (cold) and with them kept (warm: nothing read again). The
    /// numbers are printed (`MEASURE`); the digests are the same.
    @Test func pinningA2000FileRepository() throws {
        let place = try Self.place(.untrusted)
        let clone = try #require(place.clone)
        try Self.fill(place, ExtensionDigest.maxFiles - Self.files(in: clone), size: 8_000)
        #expect(Self.files(in: clone) == ExtensionDigest.maxFiles)
        let command = try place.command()
        func time(_ body: () -> String?) -> (String?, Double) {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = body()
            return (result, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        // As the session reads it at the focus (its store's hashes), then as the runner reads it before a run (the call's).
        let store = SuggestionsStore()
        let (cold, focusCold) = time { ExtensionDigest.of(command, root: place.sources, sha256: store.sha256(of:)) }
        let (warm, focusWarm) = time { ExtensionDigest.of(command, root: place.sources, sha256: store.sha256(of:)) }
        let call = ExtensionCompletionCall(command: command, environment: [:], timeout: 10, scriptSHA256: cold,
                                           sourcesFolder: place.sources, sha256: { store.sha256(of: $0) })
        let (checked, runWarm) = time { ExtensionDigest.of(call.command, root: call.sourcesFolder, sha256: call.sha256) }
        let fresh = FileHashes()
        let (checkedCold, runCold) = time { ExtensionDigest.of(command, root: place.sources, sha256: fresh.sha256(of:)) }
        #expect(cold != nil && cold != ExtensionDigest.tooLarge && warm == cold && checked == cold && checkedCold == cold)
        print(String(format: "MEASURE 2,000-file clone (%.1f MB): focus pin cold %.1f ms, warm %.1f ms; pre-run check cold %.1f ms, warm %.1f ms",
                     Double(try Self.bytes(in: clone)) / 1_000_000, focusCold, focusWarm, runCold, runWarm))
    }
}
