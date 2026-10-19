import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// A file's lines: librime writes its files on Windows with "\r\n", one Character to Swift, which
/// `components(separatedBy: "\n")` doesn't split there.
func lines(_ text: String) -> [String] {
    text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
}

/// The learned words through iCloud are librime's own user-data sync (`RimeService.syncUserData`, `RimeSync`): here
/// against a temporary "iCloud" folder and the test process's own Rime folder, never the user's. In the serialized suite:
/// a sync drops every session, as a redeploy does.
extension RimeEngineTests {
    @Test func learnedWordsSyncThroughASharedFolder() throws {
        _ = try RimeFixture.startup.get()
        let shared = FileManager.default.temporaryDirectory
            .appendingPathComponent("allinoneime-rime-sync-tests-\(ProcessInfo.processInfo.processIdentifier)/rime")
        try? FileManager.default.removeItem(at: shared.deletingLastPathComponent())
        defer {
            _ = try? RimeSync.setSyncDir(nil, userDataDir: RimeFixture.userData)
            try? FileManager.default.removeItem(at: shared.deletingLastPathComponent())
        }
        // Something learned: a word picked.
        let s = try RimeFixture.session()
        type("nihao", into: s)
        _ = s.processKey(RimeKey.space, mask: 0)
        #expect(s.takeCommit() == "你好")

        try RimeSync.setSyncDir(shared, userDataDir: RimeFixture.userData)
        let yaml = try String(contentsOf: RimeFixture.userData.appendingPathComponent("installation.yaml"), encoding: .utf8)
        let id = try #require(lines(yaml).first { $0.hasPrefix("installation_id:") }?
            .dropFirst("installation_id:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"")))
        #expect(RimeService.shared.syncUserData())
        #expect(RimeService.shared.waitUntilReady(timeout: 60))
        #expect(!s.isValid, "sessions are dropped, as for a redeploy")
        #expect(RimeService.shared.userDataSyncDir?.standardizedFileURL.path == shared.appendingPathComponent(id).standardizedFileURL.path)
        let mine = shared.appendingPathComponent(id).appendingPathComponent("rime_ice.userdb.txt")
        let snapshot = try String(contentsOf: mine, encoding: .utf8)
        #expect(snapshot.contains("你好"))
        // Only the learned words: none of the user's own .yaml or .txt files (custom phrases, settings) is copied there.
        try Data("你好\tnh\n".utf8).write(to: RimeFixture.userData.appendingPathComponent("custom_phrase.txt"))
        defer { try? FileManager.default.removeItem(at: RimeFixture.userData.appendingPathComponent("custom_phrase.txt")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: shared.appendingPathComponent(id).path).allSatisfy { $0.hasSuffix(".userdb.txt") })
        // The installation id is still this one's.
        let after = try String(contentsOf: RimeFixture.userData.appendingPathComponent("installation.yaml"), encoding: .utf8)
        #expect(after.contains(id) && RimeSync.syncDir(in: after) == shared.path)

        // Another Mac's snapshot, with a word this one never typed: merged in on the next sync.
        let line = try #require(lines(snapshot).first { $0.contains("你好") && !$0.hasPrefix("#") })
        let other = snapshot.replacingOccurrences(of: line, with: line.replacingOccurrences(of: "你好", with: "拟好"))
            .replacingOccurrences(of: id, with: "other-mac")
        let otherFolder = shared.appendingPathComponent("other-mac")
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        try Data(other.utf8).write(to: otherFolder.appendingPathComponent("rime_ice.userdb.txt"))
        // A placeholder of a third Mac's (not downloaded yet) is passed over, not read as empty.
        let third = shared.appendingPathComponent("third-mac")
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
        try Data().write(to: third.appendingPathComponent(".rime_ice.userdb.txt.icloud"))
        #expect(RimeService.shared.syncUserData())
        #expect(RimeService.shared.waitUntilReady(timeout: 60))
        let merged = try String(contentsOf: mine, encoding: .utf8)
        #expect(merged.contains("拟好") && merged.contains("你好"), "\(merged.prefix(600))")
        let copied = try FileManager.default.contentsOfDirectory(atPath: shared.appendingPathComponent(id).path)
        #expect(copied == ["rime_ice.userdb.txt"], "only the learned words are in the sync folder: \(copied)")
        #expect(try String(contentsOf: otherFolder.appendingPathComponent("rime_ice.userdb.txt"), encoding: .utf8) == other,
                "another Mac's snapshot is only read")
        #expect(RimeService.shared.makeSession() != nil)
    }

    /// librime writes installation.yaml with "\r\n" on Windows: RimeSync reads and edits it all the same (its sync_dir,
    /// its installation_id), and again once librime has written it back so.
    @Test func installationFileAsLibrimeWritesIt() throws {
        _ = try RimeFixture.startup.get()
        let deployed = try #require(RimeFixture.deployedInstallation)
        #expect(deployed.contains("\r\n"), "librime's own line ends on Windows")
        let folder = "C:/Users/someone/OneDrive/AllInOneIME/rime"
        let set = RimeSync.installation(deployed, syncDir: folder)
        #expect(RimeSync.syncDir(in: set) == folder && set.contains("installation_id:"))
        let rewritten = set.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(RimeSync.syncDir(in: rewritten) == folder)
        let again = RimeSync.installation(rewritten, syncDir: folder)
        #expect(lines(again).filter { $0.hasPrefix("sync_dir:") }.count == 1, "one sync_dir: \(again)")
        let off = RimeSync.installation(rewritten, syncDir: nil)
        #expect(RimeSync.syncDir(in: off) == nil && off.contains("installation_id:"))

        let user = FileManager.default.temporaryDirectory
            .appendingPathComponent("allinoneime-rime-installation-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: user) }
        let file = user.appendingPathComponent("installation.yaml")
        try Data(rewritten.utf8).write(to: file)
        #expect(try RimeSync.removeSyncDir(ifItIs: URL(fileURLWithPath: folder), userDataDir: user))
        #expect(RimeSync.syncDir(in: try String(contentsOf: file, encoding: .utf8)) == nil)
        try Data(deployed.utf8).write(to: file)
        #expect(try RimeSync.resetInstallationID(userDataDir: user))
        #expect(try !String(contentsOf: file, encoding: .utf8).contains("installation_id:"))
    }

    /// A redeploy asked for while the learned words sync (fuzzy pinyin changed meanwhile) waits for the sync, then runs.
    @Test func aRedeployWaitsForTheLearnedWordsSync() throws {
        _ = try RimeFixture.startup.get()
        #expect(RimeService.shared.waitUntilReady(timeout: 60))
        var finished = false
        #expect(RimeService.shared.syncUserData { _ in finished = true })
        let generation = RimeService.shared.generation
        RimeService.shared.redeploy()
        #expect(RimeService.shared.generation == generation, "not while syncing")
        let deadline = Date().addingTimeInterval(60)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        #expect(finished && RimeService.shared.generation == generation + 1, "run once the sync ended")
        #expect(RimeService.shared.waitUntilReady(timeout: 60))
    }
}
