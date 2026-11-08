import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac

/// What `@open` lists on the key that changed its text (`InstantFiles`), over an app index of stand-in bundles, and the
/// name search Spotlight answers in this process (`Spotlight.names`), checked against what mdfind finds.
struct InstantFilesTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("InstantFilesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func app(_ name: String, names: [String: String] = [:]) throws {
        let contents = root.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": name], format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        guard !names.isEmpty else { return }
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let table = names.mapValues { ["CFBundleDisplayName": $0] }
        try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Resources/InfoPlist.loctable"))
    }

    /// The stand-in apps, kept: Calculator (计算器), Calendar, WeChat (微信).
    func kept(history: OpenHistory = OpenHistory(), recheck: TimeInterval = 30) throws -> InstantFiles {
        try app("Calculator", names: ["zh_CN": "计算器"])
        try app("Calendar")
        try app("WeChat", names: ["zh_CN": "微信"])
        let files = InstantFiles(index: AppIndex(folders: [root.path], apps: [], home: nil, recheckInterval: 0), recheckInterval: recheck)
        files.make(history: history)
        return files
    }

    @Test func nothingIsListedBeforeWhatIsKeptIsMade() {
        defer { try? FileManager.default.removeItem(at: root) }
        let files = InstantFiles(index: AppIndex(folders: [root.path], apps: [], home: nil))
        #expect(files.results("cal", history: OpenHistory(), now: Date()).isEmpty)
    }

    @Test func theAppsOfTheIndexByEveryNameRankedAsTheFullSearchRanksThem() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try kept()
        #expect(files.results("cal", history: OpenHistory()).map(\.name) == ["Calendar", "Calculator"], "the shorter name first")
        #expect(files.results("计算", history: OpenHistory()).map(\.path) == [root.path + "/Calculator.app"])
        let wechat = files.results("微信", history: OpenHistory())
        #expect(wechat.map(\.name) == ["WeChat"] && wechat.first?.chineseName == "微信" && wechat.first?.isFolder == false)
        // The first letter: every app it is in.
        #expect(Set(files.results("c", history: OpenHistory()).map(\.name)) == ["Calendar", "Calculator", "WeChat"])
        #expect(files.results("cal", history: OpenHistory(), limit: 1).count == 1)
        #expect(files.results("zzz", history: OpenHistory()).isEmpty)
    }

    @Test func whatWasOpenedBeforeComesFirstWhenItsNameMatches() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // Outside the index, and a path `@open` lists from (`FileSearch.isCandidate`); one that is gone isn't listed.
        let opened = "/System/Applications/Calculator.app", gone = "/Applications/No Such Calculator.app"
        var history = OpenHistory()
        history.record(gone)
        history.record(opened)
        let files = try kept(history: history)
        let rows = files.results("calc", history: history)
        #expect(rows.map(\.path) == [opened, root.path + "/Calculator.app"], "\(rows.map(\.path))")
        #expect(rows.first?.name == FileManager.default.displayName(atPath: opened))
        #expect(!files.results("wechat", history: history).contains { $0.path == opened })
    }

    @Test func aPathListsItsFolderAndAWebAddressComesFirst() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try kept()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Calls"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("calendar.ics"))
        #expect(files.results(root.path + "/Cal", history: OpenHistory()).isEmpty, "nothing read on the key")
        let read = files.list(root.path + "/Cal", limit: 8)
        let listed = files.results(root.path + "/Cal", history: OpenHistory())
        #expect(listed.map(\.name) == ["Calls", "Calculator", "Calendar", "calendar.ics"] && listed.first?.isFolder == true,
                "folders first, an app isn't one (\(listed.map(\.name)))")
        #expect(listed == read && listed == FileSearch.complete(root.path + "/Cal", limit: 8))
        #expect(files.results("https://example.com/cal", history: OpenHistory()).map(\.path) == ["https://example.com/cal"])
        #expect(files.results("example.com", history: OpenHistory()).first?.path == SearchResult.web("example.com")?.path)
    }

    /// A path on the key (`instantResults`): nothing read from the disk then. Its folder is read off the key's thread, by
    /// the search (`list`, as `FileSearch.names` and `run` read it), and kept a moment: the keys after narrow it at once
    /// ("~/Doc" from "~/D"'s), without reading it again; another folder, or one listed too long ago, shows nothing.
    @Test func aPathTouchesNoDiskOnTheKeysThread() {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.path + "/home"
        let entries = ["Desktop", "Documents", "Downloads", "Library"].map { SearchResult(name: $0, path: folder + "/" + $0, isFolder: true) }
        let reads = Locked<[(query: String, onKeysThread: Bool)]>(initialState: [])
        let keysThread = pthread_mach_thread_np(pthread_self())
        let files = InstantFiles(index: AppIndex(folders: [], apps: [], home: nil)) { query, limit in
            reads.withLock { $0.append((query, pthread_mach_thread_np(pthread_self()) == keysThread)) }
            let prefix = query.hasSuffix("/") ? "" : (query as NSString).lastPathComponent.lowercased()
            return Array(entries.filter { $0.name.lowercased().hasPrefix(prefix) }.prefix(limit))
        }
        let now = Date()
        #expect(files.results(folder + "/", history: OpenHistory(), now: now).isEmpty)
        #expect(files.results(folder + "/D", history: OpenHistory(), now: now).isEmpty)
        #expect(reads.withLock { $0 }.isEmpty, "the key reads nothing")
        // The search reads it, off the key's thread.
        let listed = Locked<[SearchResult]>(initialState: [])
        let done = DispatchSemaphore(value: 0)
        Thread {
            listed.withLock { $0 = files.list(folder + "/", limit: 8, now: now) }
            done.signal()
        }.start()
        done.wait()
        #expect(listed.withLock { $0 } == entries)
        #expect(reads.withLock { $0.map(\.onKeysThread) } == [false])
        #expect(files.results(folder + "/", history: OpenHistory(), now: now.addingTimeInterval(1)) == entries)
        #expect(files.results(folder + "/do", history: OpenHistory(), now: now.addingTimeInterval(2)).map(\.name) == ["Documents", "Downloads"])
        #expect(files.results(folder + "/Doc", history: OpenHistory(), limit: 1, now: now.addingTimeInterval(2)).map(\.name) == ["Documents"])
        #expect(files.results(root.path + "/other/", history: OpenHistory(), now: now.addingTimeInterval(2)).isEmpty, "another folder")
        #expect(files.results(folder + "/D", history: OpenHistory(), now: now.addingTimeInterval(InstantFiles.listingKept + 1)).isEmpty,
                "listed too long ago")
        #expect(reads.withLock { $0.count } == 1, "read once, by the search")
        // "~/D" listed: "~/" isn't known from it (the other names weren't read).
        _ = files.list(folder + "/D", limit: 8, now: now)
        #expect(files.results(folder + "/", history: OpenHistory(), now: now).isEmpty)
        #expect(files.results(folder + "/Dow", history: OpenHistory(), now: now).map(\.name) == ["Downloads"])
    }

    /// One @'s search for a path (`FileSearch.names`, `SessionServices.searchFileNames`) lists its folder, off the key's
    /// thread, and the app's `instantResults` shows it at once on the next key.
    @Test func oneAtsSearchListsAPathsFolder() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.path + "/listed"
        for name in ["alpha", "beta"] { try FileManager.default.createDirectory(atPath: folder + "/" + name, withIntermediateDirectories: true) }
        try Data().write(to: URL(fileURLWithPath: folder + "/notes.txt"))
        #expect(InstantFiles.shared.results(folder + "/", history: OpenHistory()).isEmpty)
        // The next key as of when the search started: the folder is listed after that. (Under the load of the whole run
        // this test may go on seconds after the search was done, past the moment its listing is kept.)
        let started = Date()
        let found = await FileSearch.names(folder + "/", history: OpenHistory())
        #expect(found.map(\.name) == ["alpha", "beta", "notes.txt"], "\(found.map(\.name))")
        #expect(InstantFiles.shared.results(folder + "/b", history: OpenHistory(), now: started).map(\.name) == ["beta"])
    }

    @Test func whatIsKeptIsMadeAgainOnceOutOfDateOrForAPathOpenedSince() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try kept()
        let made = Date()
        try app("Calligraphy")
        // Within the interval nothing is made again: the new app isn't listed yet.
        #expect(!files.results("calli", history: OpenHistory(), now: made.addingTimeInterval(10)).contains { $0.name == "Calligraphy" })
        // Past it: made again off this thread, then listed.
        _ = files.results("calli", history: OpenHistory(), now: made.addingTimeInterval(31))
        #expect(await Timing.eventually { files.results("calli", history: OpenHistory()).map(\.name) == ["Calligraphy"] })
        // A path opened since: made again at once.
        var history = OpenHistory()
        history.record("/System/Applications/Calculator.app")
        _ = files.results("calc", history: history)
        #expect(await Timing.eventually { files.results("calc", history: history).first?.path == "/System/Applications/Calculator.app" })
    }

    /// `root` as the system's list of what is mounted would have it: without links (the temporary folder is in /var, a
    /// link to /private/var).
    var real: String {
        guard let real = realpath(root.path, nil) else { return root.path }
        defer { free(real) }
        return String(cString: real)
    }

    /// A server's volume (a stand-in: `root`/share, mounted from a server as `mounts` has it), and links to it and to
    /// a folder here, in `root`.
    func server() throws -> (share: String, mounts: Mounts) {
        let share = real + "/share"
        try FileManager.default.createDirectory(atPath: share + "/sub", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root.path + "/here", withIntermediateDirectories: true)
        for (link, target) in [("NAS", share), ("relative", "share/sub"), ("chain", root.path + "/NAS"), ("near", "here"), ("loop", "loop")] {
            try FileManager.default.createSymbolicLink(atPath: root.path + "/" + link, withDestinationPath: target)
        }
        return (share, Mounts(points: [("/", true), ("/System/Volumes/Data", true), (share, false)]))
    }

    @Test func onlyAFolderOfThisMacIsReadAtOnce() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(Mounts().isLocal("/") && Mounts().isLocal(root.path) && Mounts().isLocal("/System/Applications"))
        let (share, mounts) = try server()
        // On the server's volume however it is written, or through a link (`~/NAS` → `/Volumes/share`).
        for path in [share, share + "/sub", root.path + "/SHARE/sub", root.path + "/./share", root.path + "//share/sub",
                     root.path + "/here/../share", root.path + "/NAS", root.path + "/NAS/sub", root.path + "/relative",
                     root.path + "/chain/sub", root.path + "/loop"] {
            #expect(!mounts.isLocal(path), "\(path)")
        }
        for path in ["/", root.path, root.path + "/here", root.path + "/near", root.path + "/near/../here", root.path + "/no/such/folder"] {
            #expect(mounts.isLocal(path), "\(path)")
        }
        #expect(!mounts.isLocalVolume(share.uppercased()) && mounts.isLocalVolume(root.path + "/NAS"), "the path as written")
        // The system's own list: what it says of the server's volume as a stand-in is true of this Mac's.
        #expect(Mounts().isLocal(root.path + "/NAS/sub"))
    }

    @Test func aFolderIsListedByFileNameAndOnlyWhatIsShownIsNamed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (share, server) = try server()
        let list = root.path + "/list"
        // A folder; a server's volume mounted here (Finder would name it "Backup"); links to the server and to a folder
        // here; an app; files.
        let backup = real + "/list/Backup.localized"
        for folder in ["b-folder", "Backup.localized", "Tool.app"] {
            try FileManager.default.createDirectory(atPath: list + "/" + folder, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(atPath: list + "/NAS", withDestinationPath: share)
        try FileManager.default.createSymbolicLink(atPath: list + "/Near", withDestinationPath: "../here")
        for file in ["c.txt", "A.txt", ".hidden"] { try Data().write(to: URL(fileURLWithPath: list + "/" + file)) }
        let mounts = Mounts(points: server.points + [(backup, false)])
        let listed = FileSearch.complete(list + "/", limit: 8, mounts: mounts)
        #expect(listed.map(\.name) == ["b-folder", "Backup.localized", "Near", "A.txt", "c.txt", "NAS", "Tool"], "\(listed.map(\.name))")
        #expect(listed.map(\.isFolder) == [true, true, true, false, false, false, false], "a link to the server isn't followed")
        #expect(FileSearch.complete(list + "/", limit: 2, mounts: mounts).map(\.name) == ["b-folder", "Backup.localized"])
        #expect(FileSearch.complete(list + "/n", limit: 8, mounts: mounts).map(\.name) == ["Near", "NAS"])
        // On this Mac all of them: the volume is named as Finder names it, and the link is followed.
        let here = FileSearch.complete(list + "/", limit: 8)
        #expect(here.map(\.name) == ["b-folder", "Backup", "NAS", "Near", "A.txt", "c.txt", "Tool"], "\(here.map(\.name))")
        // A folder on the server is read only by the search, off the key's thread: as before, links followed.
        #expect(FileSearch.complete(root.path + "/", limit: 10, mounts: server).first { $0.name == "near" }?.isFolder == true)
        #expect(FileSearch.complete(share + "/", limit: 8, mounts: server).map(\.name) == ["sub"])
    }

    @Test func aLargeFolderIsListedAtOnce() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // A Downloads folder of 3,000 files and 100 folders: `complete` names only the 8 it lists.
        let big = root.path + "/big"
        for index in 0..<100 { try FileManager.default.createDirectory(atPath: big + "/folder \(index)", withIntermediateDirectories: true) }
        for index in 0..<3000 { FileManager.default.createFile(atPath: big + "/file \(index).pdf", contents: nil) }
        _ = FileManager.default.displayName(atPath: big)
        var listed: [SearchResult] = []
        let time = Timing.cpuSeconds { listed = FileSearch.complete(big + "/", limit: 8) }.seconds
        #expect(listed.map(\.name) == ["folder 0", "folder 1", "folder 10", "folder 11", "folder 12", "folder 13", "folder 14", "folder 15"],
                "\(listed.map(\.name))")
        // Naming them all took 0.15 s of CPU on a Mac mini (a debug build), this 2.3 ms.
        #expect(time < 0.05, "\(time) s")
        #expect(FileSearch.complete(big + "/file 29", limit: 8).map(\.name) == ["file 29.pdf", "file 290.pdf"] + (2900...2905).map { "file \($0).pdf" })
    }

    @Test func theFullSearchFindsWhatWasOpenedByItsName() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var history = OpenHistory()
        history.record("/System/Applications/Calculator.app")
        history.record("/Applications/No Such Calculator.app")
        let found = FileSearch.openedFiles(history, keywords: ["calc"], places: [], apps: [:])
        #expect(found.map(\.path) == ["/System/Applications/Calculator.app"], "only what is still there")
        #expect(FileSearch.openedFiles(history, keywords: ["applications"], places: [], apps: [:]).isEmpty, "a folder isn't its name")
        let indexed = ["/System/Applications/Calculator.app": AppIndex.App(path: "/System/Applications/Calculator.app", names: [])]
        #expect(FileSearch.openedFiles(history, keywords: ["calc"], places: [], apps: indexed).isEmpty, "an app of the index by its names only")
        // What is on a server isn't looked for: it counts as gone.
        let (share, mounts) = try server()
        try Data().write(to: URL(fileURLWithPath: share + "/sub/calculations.numbers"))
        history.record(share + "/sub/calculations.numbers")
        #expect(FileSearch.openedFiles(history, keywords: ["calc"], places: [], apps: [:]).count == 2)
        #expect(FileSearch.openedFiles(history, keywords: ["calc"], places: [], apps: [:], mounts: mounts).map(\.path)
            == ["/System/Applications/Calculator.app"])
        #expect(FileSearch.isThere(share + "/sub", mounts: Mounts()) && !FileSearch.isThere(share + "/sub", mounts: mounts))
    }

    // MARK: - Spotlight's names

    /// What `names` finds for `keyword` in `scopes` (`within` days), on a thread of its own. It answers on dispatch's
    /// threads, which the tests that wait for a child process may all take for seconds (`SpotlightTests.inBackground`):
    /// it is given a minute, and not answering by then is a failure.
    func names(_ keyword: String, in scopes: [String] = ["/System/Applications"], within days: Int? = nil) async -> [FileSearchRanking.Found] {
        let seconds = 60.0, started = Date()
        let found = await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: Spotlight(until: .now() + seconds).names(keyword, in: scopes, within: days)) }
                .start()
        }
        if Date().timeIntervalSince(started) >= seconds { Issue.record("Spotlight didn't answer \(keyword) in \(seconds) s") }
        return found ?? []
    }

    /// `body` on a thread of its own (it blocks), awaited.
    func inBackground<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in Thread { continuation.resume(returning: body()) }.start() }
    }

    /// What `mdfind -name keyword -onlyin folder` prints, the paths.
    func mdfind(_ keyword: String, in folder: String) throws -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", folder, "-name", keyword]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    @Test func namesAreFoundAsMdfindFindsThemWithTheirDates() async throws {
        for keyword in ["calc", "Ca", "system"] {
            let found = await names(keyword)
            #expect(Set(found.map(\.path)) == (try mdfind(keyword, in: "/System/Applications")), "\(keyword): \(found.map(\.path))")
        }
        // The dates Spotlight keeps.
        for found in await names("calc") {
            let item = try #require(NSMetadataItem(url: URL(fileURLWithPath: found.path)))
            #expect(found.lastUsed == item.value(forAttribute: "kMDItemLastUsedDate") as? Date, "\(found.path)")
            #expect(found.modified == item.value(forAttribute: "kMDItemContentModificationDate") as? Date, "\(found.path)")
        }
    }

    @Test func recentNamesAreTheAppsAndWhatWasUsedOrChangedLately() async {
        // Every app, however long ago it was used.
        let apps = Set(await names("a").map(\.path).filter { $0.hasSuffix(".app") })
        let today = Set(await names("a", within: 0).map(\.path))
        #expect(!apps.isEmpty && today.isSuperset(of: apps))
        // Each file of the home folder used or changed in the last 29 days, before the test started (what changes while
        // it runs may be found by one query and not the other).
        let home = FileManager.default.homeDirectoryForCurrentUser.path, started = Date()
        let recent = Set(await names("sa", in: [home], within: 30).map(\.path))
        let all = await names("sa", in: [home])
        let lately = all.filter { file in
            file.latest.map { $0 > started.addingTimeInterval(-29 * 86_400) && $0 < started.addingTimeInterval(-60) } ?? false
        }
        #expect(lately.allSatisfy { recent.contains($0.path) || !FileManager.default.fileExists(atPath: $0.path) },
                "\(lately.map(\.path).filter { !recent.contains($0) })")
        #expect(recent.count <= all.count + 10)
    }

    @Test func aNameSearchAsksForMoreOnlyWhileWhatItFoundIsntEnough() async {
        // In /System/Applications nothing changes while the test runs: what each query finds is known.
        let scopes = ["/System/Applications"]
        let (yesterday, month, all) = (await names("a", within: 1).count, await names("a", within: 30).count, await names("a").count)
        let b = await names("b").count
        /// The counts of what each keyword found ("a" asked up to `steps` times, from yesterday on), and what `enough` was told.
        func each(_ steps: Int, recent: [Int] = [1, 30]) async -> (found: [Int]?, told: [Int]) {
            let told = Locked(initialState: [Int]())
            let found = await inBackground {
                Spotlight(until: .now() + 60).names(each: ["a"], in: scopes, recentFirst: recent, enough: { found in
                    told.withLock { $0.append(found.count) }
                    return told.withLock { $0.count } >= steps
                })?.map(\.count)
            }
            return (found, told.withLock { $0 })
        }
        #expect(await each(1) == ([yesterday], [yesterday]), "what was used or changed since yesterday only")
        #expect(await each(2) == ([yesterday + month], [yesterday, yesterday + month]))
        #expect(await each(3) == ([yesterday + month + all], [yesterday, yesterday + month, yesterday + month + all]), "everything")
        #expect(await each(5) == ([yesterday + month + all], [yesterday, yesterday + month, yesterday + month + all]), "nothing more")
        #expect(await each(5, recent: []) == ([all], [all]), "all at once")
        let both = await inBackground { Spotlight(until: .now() + 60).names(each: ["a", "b"], in: scopes)?.map(\.count) }
        #expect(both == [all, b])
    }

    @Test func theRowsAreFilledWhenSoManyFilesAreListed() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let files = (0..<8).map { FileSearchRanking.Found(path: home + "/Documents/sales \($0).pdf") }
        #expect(FileSearch.fillsRows(files, limit: 8, keywords: ["sa"], places: []))
        #expect(!FileSearch.fillsRows(Array(files.dropLast()), limit: 8, keywords: ["sa"], places: []))
        // Only those `@open` would list: not in Library, not noise, named by every keyword.
        let unlisted = [home + "/Library/sales.pdf", home + "/Documents/build/sales.o", "/usr/share/sales.txt"].map { FileSearchRanking.Found(path: $0) }
        #expect(!FileSearch.fillsRows(Array(files.dropLast()) + unlisted, limit: 8, keywords: ["sa"], places: []))
        #expect(!FileSearch.fillsRows(files, limit: 8, keywords: ["sa", "xlsx"], places: []))
        #expect(FileSearch.fillsRows(files, limit: 8, keywords: ["sa", "pdf"], places: []))
    }

    /// `names` on a thread of its own, and when it returned there: what a test times, not when the task awaiting it is
    /// run again (in a loaded test run that waits for the concurrency pool, which tests waiting for a session hold).
    func timedNames(_ spotlight: Spotlight, _ keyword: String, in scopes: [String]) -> Task<(found: [FileSearchRanking.Found]?, at: Date), Never> {
        Task { await inBackground { (spotlight.names(keyword, in: scopes), Date()) } }
    }

    /// A query over for its waiter (cancelled, stopped, past its time) while a batch of its results is read reads
    /// nothing more of it, on its own queue: each result is read only while the query isn't over, and none of the batch
    /// is kept.
    @Test func aCancelledQueryReadsNothingMoreOfABatch() {
        let over = Locked(initialState: false)
        let asked = Locked<[CFIndex]>(initialState: [])
        let found = Spotlight.Query.results(0..<2000, isOver: { over.withLock { $0 } }) { index in
            asked.withLock { $0.append(index) }
            if index == 2 { over.withLock { $0 = true } }  // the cancel comes as the third is read
            return FileSearchRanking.Found(path: "/tmp/\(index)")
        }
        #expect(found == nil, "nothing of the batch kept")
        #expect(asked.withLock { $0 } == [0, 1, 2], "nothing read after the cancel")
        let all = Spotlight.Query.results(0..<3, isOver: { false }) { FileSearchRanking.Found(path: "/tmp/\($0)") }
        #expect(all?.map(\.path) == ["/tmp/0", "/tmp/1", "/tmp/2"])
        #expect(Spotlight.Query.results(0..<3, isOver: { true }) { _ in Issue.record("read"); return nil } == nil)
    }

    @Test func aNameSearchEndsAtOnceWhenCancelledWhileSpotlightLooks() async throws {
        // Everything on the startup disk: some 440,000 items, 12 s on a Mac mini.
        let spotlight = Spotlight(until: .now() + 60)
        let found = timedNames(spotlight, "", in: ["/"])
        #expect(await Timing.eventually { spotlight.isAsking })
        try await Task.sleep(for: .milliseconds(5))
        let cancelling = Date()
        spotlight.cancel()
        let (names, returned) = await found.value
        #expect(names == nil)
        #expect(returned.timeIntervalSince(cancelling) < 1, "\(returned.timeIntervalSince(cancelling)) s")
        #expect(!spotlight.isAsking)
        // Not started once cancelled.
        let cancelled = Spotlight(until: .now() + 10)
        cancelled.cancel()
        #expect(cancelled.names("a", in: ["/System/Applications"]) == nil)
        #expect(cancelled.names(each: ["a", "b"], in: ["/System/Applications"]) == nil)
    }

    /// Under load Spotlight's own deliveries back the query's queue up (a loaded test run took 12.8 s to return after a
    /// cancel): a cancel and the time limit don't wait behind them, the query is stopped once they are through, and
    /// nothing is read of a cancelled one. The queue held up here for 3 s once the query runs, as that backlog does (a
    /// small query: what is held up is the queue, whatever Spotlight finds).
    @Test func aCancelOrTheTimeLimitDoesntWaitForTheQueryToComeToIt() async throws {
        let held = 3.0, scopes = ["/System/Applications"]
        let asked = Locked<[Spotlight.Query]>(initialState: [])
        let hold: @Sendable (Spotlight.Query) -> Void = { query in
            asked.withLock { $0.append(query) }
            query.queue.async { Thread.sleep(forTimeInterval: held) }
        }
        let spotlight = Spotlight(until: .now() + 60)
        spotlight.queryRuns = hold
        let found = timedNames(spotlight, "", in: scopes)
        #expect(await Timing.eventually { !asked.withLock { $0 }.isEmpty })
        try await Task.sleep(for: .milliseconds(100))
        let cancelling = Date()
        spotlight.cancel()
        let (names, returned) = await found.value
        #expect(names == nil)
        #expect(returned.timeIntervalSince(cancelling) < 2, "\(returned.timeIntervalSince(cancelling)) s")
        let limited = Spotlight(until: .now() + 0.3)
        limited.queryRuns = hold
        let started = Date()
        let (some, ended) = await timedNames(limited, "", in: scopes).value
        #expect(some != nil && ended.timeIntervalSince(started) < 2, "\(ended.timeIntervalSince(started)) s")
        // Once the queue comes to them: nothing was read of the cancelled one.
        let cancelled = try #require(asked.withLock { $0 }.first)
        #expect(await inBackground { cancelled.queue.sync { cancelled.read } } == 0)
    }

    @Test func aNameSearchEndsAtTheTimeLimitWithWhatItFound() async {
        // What was found by then is kept, not dropped as when cancelled. All of it takes Spotlight some 12 s on a Mac mini
        // (alone, this returns after 0.5 s), and a loaded test run has held its answers for 25 s: the bound is for a
        // query that never ends.
        let started = Date()
        let found = await inBackground { Spotlight(until: .now() + 0.5).names("", in: ["/"]) }
        #expect(found != nil)
        #expect(Date().timeIntervalSince(started) < 50, "\(Date().timeIntervalSince(started)) s")
        #expect(await inBackground { Spotlight(until: .now()).names("calc", in: ["/System/Applications"]) } == [], "no time left")
    }

    @Test func namesAreLookedForInWhatIsRecentFirstAndOnlyWhereOpenLooks() {
        #expect(FileSearch.recentDays == [1, 30])
        let scopes = FileSearch.scopes()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Array(scopes.prefix(3)) == [home, "/Applications", "/System/Applications"])
        #expect(scopes.dropFirst(3).allSatisfy { $0.hasPrefix("/Volumes/") && !$0.hasPrefix("/Volumes/.") }, "\(scopes)")
        #expect(scopes.allSatisfy { FileSearch.isCandidate($0 + "/x") }, "only where `isCandidate` lists files from")
        // The startup disk's link in /Volumes leads to "/": Spotlight would look everywhere.
        #expect(!scopes.contains { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) != nil })
        // A server's volume isn't searched.
        let volumes = ((try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []).map { ("/Volumes/" + $0, false) }
        #expect(FileSearch.scopes(mounts: Mounts(points: [("/", true)] + volumes)) == Array(scopes.prefix(3)))
    }
}
