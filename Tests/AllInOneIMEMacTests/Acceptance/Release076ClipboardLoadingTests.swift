import AllInOneIMEMac
import AllInOneIMETestSupport
import Foundation
import Testing

/// Required test seam: `ClipboardHistoryStore.init(url:readFile:)` accepts a `@Sendable (URL) -> Data?` reader,
/// used for the history JSON instead of `Data(contentsOf:)`. The store exposes `isLoading` while that reader runs
/// and `waitForLoad() async` to await the merged, usable list. The reader must run off the caller's main thread.
/// These seams make the start-up race deterministic without a large file, timing threshold, or on-screen run.
@Suite(.serialized)
struct Release076ClipboardLoadingTests {
    static let oldFile = Data(#"{"items":[{"text":"older","copiedAt":1800000000},{"text":"oldest","copiedAt":1799999999}]}"#.utf8)

    static func historyFile() throws -> URL {
        let folder = TestScratch.temporary("clipboard-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("clipboard-history.json")
        try oldFile.write(to: url)
        return url
    }

    @Test @MainActor func initDoesNotReadTheFileOnTheCallingThread() async throws {
        let url = try Self.historyFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let readOnMain = Locked(initialState: false)
        let store = ClipboardHistoryStore(url: url, readFile: { file in
            readOnMain.withLock { $0 = Thread.isMainThread }
            return try? Data(contentsOf: file)
        })
        await store.waitForLoad()
        #expect(!readOnMain.withLock { $0 }, "initialization must never read the history file on the main thread")
    }

    @Test @MainActor func savedItemsAppearInOrderAfterLoading() async throws {
        let url = try Self.historyFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = DispatchSemaphore(value: 0)
        let store = ClipboardHistoryStore(url: url, readFile: { file in
            _ = gate.wait(timeout: .now() + 3) // Test worker thread only; bounded if loading regresses.
            return try? Data(contentsOf: file)
        })
        #expect(store.isLoading, "the store reports its loading state before the read finishes")
        gate.signal()
        await store.waitForLoad()
        #expect(!store.isLoading)
        #expect(store.items.map(\.text) == ["older", "oldest"])
    }

    @Test @MainActor func itemRecordedDuringLoadingIsSavedOnceWithOlderItems() async throws {
        let url = try Self.historyFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = DispatchSemaphore(value: 0)
        let store = ClipboardHistoryStore(url: url, readFile: { file in
            _ = gate.wait(timeout: .now() + 3) // Test worker thread only; bounded if loading regresses.
            return try? Data(contentsOf: file)
        })
        #expect(store.isLoading)
        #expect(store.record("new", at: Date(timeIntervalSince1970: 1_800_000_001), limit: 20, savingLater: true))
        #expect(store.items.map(\.text) == ["new"])
        #expect(try Data(contentsOf: url) == Self.oldFile, "a save during loading must not replace the full old file")
        gate.signal()
        await store.waitForLoad()
        store.waitForWrites()
        #expect(store.items.map(\.text) == ["new", "older", "oldest"])
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let entries = saved?["items"] as? [[String: Any]]
        #expect(entries?.compactMap { $0["text"] as? String } == ["new", "older", "oldest"])
    }
}
