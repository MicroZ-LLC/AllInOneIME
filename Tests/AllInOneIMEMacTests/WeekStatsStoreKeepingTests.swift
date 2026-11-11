import Foundation
import Testing
import AllInOneIMECore
@testable import AllInOneIMEMac

/// What `WeekStatsStore` keeps where: the salt in the keychain (here one in memory), never in usage.json, and Forget All
/// ordered with the counts around it (none lost, none left unwritten).
@Suite(.serialized)
struct WeekStatsStoreKeepingTests {
    private static func calendar() -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        result.firstWeekday = 2
        return result
    }

    private static let instant = calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!

    private static func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("week-stats-keeping-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func store(_ root: URL, _ keychain: SecretStore) -> WeekStatsStore {
        WeekStatsStore(applicationSupportDirectory: root, now: { instant }, calendar: calendar(), keychain: keychain)
    }

    /// The salt goes to the keychain (its own item), the file has only the hashes; a store made again with the keychain
    /// counts the same apps as before, one whose salt is gone starts the apps again and keeps the rest. Forget All deletes
    /// the file and the salt.
    @Test func theSaltIsInTheKeychainNeverInTheFile() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = APIKeys.Keychain.inMemory()
        let store = Self.store(root, keychain)
        store.stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.private.editor", usedAI: true)
        try await store.flush()

        let kept = try #require(keychain.read(WeekStatsStore.saltAccount))
        #expect(Data(base64Encoded: kept) == store.stats.salt)
        let file = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!file.contains(kept))
        #expect(!file.contains("\"salt\""))
        #expect(!file.contains("com.private.editor"))

        let again = Self.store(root, keychain)
        #expect(again.stats.salt == store.stats.salt)
        #expect(again.stats.snapshot(for: .current).distinctAppCount == 1, "the apps' hashes read back, by the same salt")

        let lost = Self.store(root, .inMemory())
        #expect(lost.stats.snapshot(for: .current).distinctAppCount == 0, "the salt gone: the apps start again")
        #expect(lost.stats.snapshot(for: .current).commandCount == 1)

        try await store.clearHistory()
        #expect(keychain.read(WeekStatsStore.saltAccount) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    /// Forget All while the store's queue is busy: it forgets at once, so a count made just after it (another field) is
    /// kept, and written with the clearing's own write, without waiting for another count.
    @Test func aCountJustAfterForgetAllIsKeptAndWritten() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = APIKeys.Keychain.inMemory()
        let store = Self.store(root, keychain)
        store.stats.recordCommand(id: "before", source: .builtIn, bundleID: "com.example.a", usedAI: false)
        try await store.flush()

        store.writes.suspend()  // a write under way
        let clearing = Task { try await store.clearHistory() }
        let deadline = Date().addingTimeInterval(5)
        while store.stats.snapshot(for: .current).commandCount > 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(store.stats.snapshot(for: .current).commandCount == 0, "forgotten when asked, not when the queue gets to it")
        store.stats.recordCommand(id: "after", source: .builtIn, bundleID: "com.example.b", usedAI: false)
        store.writes.resume()
        try await clearing.value

        #expect(store.stats.snapshot(for: .current).topCommands.map(\.id) == ["after"])
        let file = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(file.contains("after") && !file.contains("before"), "written by the clearing, no other count needed")
        #expect(Self.store(root, keychain).stats.snapshot(for: .current).topCommands.map(\.id) == ["after"])
        #expect(Self.store(root, keychain).stats.snapshot(for: .current).distinctAppCount == 1)
    }
}
