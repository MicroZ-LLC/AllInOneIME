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
        let listed = files.results(root.path + "/Cal", history: OpenHistory())
        #expect(listed.map(\.name) == ["Calls", "Calculator", "Calendar", "calendar.ics"] && listed.first?.isFolder == true,
                "folders first, an app isn't one (\(listed.map(\.name)))")
        #expect(listed == FileSearch.complete(root.path + "/Cal", limit: 8))
        #expect(files.results("https://example.com/cal", history: OpenHistory()).map(\.path) == ["https://example.com/cal"])
        #expect(files.results("example.com", history: OpenHistory()).first?.path == SearchResult.web("example.com")?.path)
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
        #expect(InstantFiles.isLocal("/") && InstantFiles.isLocal(root.path) && InstantFiles.isLocal("/System/Applications"))
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
        // Naming them all took 0.3 s of CPU on a Mac mini.
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

    /// What `names` finds for `keyword` in /System/Applications (at most `limit`), on a thread of its own, or nil when
    /// Spotlight didn't answer by the time limit. It answers on dispatch's threads, which the tests that wait for a child
    /// process may all take for seconds (`SpotlightTests.inBackground`): then there is nothing to compare.
    func names(_ keyword: String, limit: Int) async -> [FileSearchRanking.Found]? {
        let seconds = 30.0, started = Date()
        let found = await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: Spotlight(until: .now() + seconds).names(keyword, in: ["/System/Applications"], limit: limit)) }
                .start()
        }
        return Date().timeIntervalSince(started) < seconds ? found : nil
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

    @Test func namesAreFoundAsMdfindFindsThemNewestFirst() async throws {
        for keyword in ["calc", "Ca", "system"] {
            guard let found = await names(keyword, limit: 1000) else { continue }
            #expect(Set(found.map(\.path)) == (try mdfind(keyword, in: "/System/Applications")), "\(keyword): \(found.map(\.path))")
            // The most recently used first, then the most recently changed.
            let keys = found.map { ($0.lastUsed ?? .distantPast, $0.modified ?? .distantPast) }
            #expect(zip(keys, keys.dropFirst()).allSatisfy { $0 >= $1 }, "\(keyword): \(keys)")
        }
    }

    @Test func aNameSearchStopsAtItsLimitAndOnceCancelled() async {
        if let all = await names("a", limit: 1000), let some = await names("a", limit: 2) {
            #expect(some.count == min(2, all.count), "\(some.count) of \(all.count)")
        }
        let cancelled = Spotlight(until: .now() + 10)
        cancelled.cancel()
        #expect(cancelled.names("a", in: ["/System/Applications"], limit: 10) == nil)
        #expect(cancelled.names(each: ["a", "b"], in: ["/System/Applications"], limit: { _ in 10 }) == nil)
    }

    @Test func shortKeywordsListFewerAndOnlyWhereOpenLooks() {
        #expect(FileSearch.nameLimit("s") == 500 && FileSearch.nameLimit("sa") == 500 && FileSearch.nameLimit("saf") == 1000)
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
