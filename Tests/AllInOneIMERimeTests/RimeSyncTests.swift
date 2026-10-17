import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

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
        let id = try #require(yaml.components(separatedBy: "\n").first { $0.hasPrefix("installation_id:") }?
            .dropFirst("installation_id:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"")))
        #expect(RimeService.shared.syncUserData())
        #expect(RimeService.shared.waitUntilReady(timeout: 60))
        #expect(!s.isValid, "sessions are dropped, as for a redeploy")
        #expect(RimeService.shared.userDataSyncDir?.standardizedFileURL.path == shared.appendingPathComponent(id).standardizedFileURL.path)
        let mine = shared.appendingPathComponent(id).appendingPathComponent("rime_ice.userdb.txt")
        let snapshot = try String(contentsOf: mine, encoding: .utf8)
        #expect(snapshot.contains("你好"))
        // The installation id is still this one's.
        let after = try String(contentsOf: RimeFixture.userData.appendingPathComponent("installation.yaml"), encoding: .utf8)
        #expect(after.contains(id) && RimeSync.syncDir(in: after) == shared.path)

        // Another Mac's snapshot, with a word this one never typed: merged in on the next sync.
        let line = try #require(snapshot.components(separatedBy: "\n").first { $0.contains("你好") && !$0.hasPrefix("#") })
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
        #expect(try String(contentsOf: otherFolder.appendingPathComponent("rime_ice.userdb.txt"), encoding: .utf8) == other,
                "another Mac's snapshot is only read")
        #expect(RimeService.shared.makeSession() != nil)
    }
}
