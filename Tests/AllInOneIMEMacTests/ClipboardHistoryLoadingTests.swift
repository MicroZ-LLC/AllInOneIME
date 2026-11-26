import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import Foundation
import Testing

/// Clipboard history's file read off the main thread (`ClipboardHistoryStore`, 0.7.6), what the review of PR #162 found:
/// an image kept while it is read keeps its files through the writes queued before it; a lower limit applied while it
/// is read writes nothing unless it drops something; Clear History while it is read doesn't wait for it; and
/// `waitForLoad` returns for a store made off the main thread.
@Suite(.serialized)
struct ClipboardHistoryLoadingTests {
    static let twoItems = Data(#"{"items":[{"text":"older","copiedAt":1800000000},{"text":"oldest","copiedAt":1799999999}]}"#.utf8)

    /// A store over `url` whose read waits for `gate` (3 s at most), on the store's own queue.
    static func gated(_ url: URL, _ gate: DispatchSemaphore) -> ClipboardHistoryStore {
        ClipboardHistoryStore(url: url, readFile: { file in
            _ = gate.wait(timeout: .now() + 3)  // The store's queue only.
            return try? Data(contentsOf: file)
        })
    }

    static func file(_ contents: Data?) throws -> URL {
        let folder = try ClipboardHistoryRecordingTests.folder()
        let url = folder.appendingPathComponent("clipboard-history.json")
        if let contents { try contents.write(to: url) }
        return url
    }

    @Test func anImageKeptWhileTheFileIsReadKeepsItsFiles() throws {
        let url = try Self.file(Self.twoItems)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = DispatchSemaphore(value: 0)
        let store = Self.gated(url, gate)
        let date = Date(timeIntervalSince1970: 1_800_000_010)
        // A text first (its write queued, a list without the image), then the image.
        store.record("a text", at: date, limit: 20, savingLater: true)
        #expect(store.recordImage(ClipboardHistoryRecordingTests.png(8, 8), at: date + 1, limit: 20))
        let id = try #require(store.items.first?.image?.id)
        gate.signal()
        store.waitForWrites()
        #expect(store.items.map { $0.image != nil ? "<image>" : $0.text } == ["<image>", "a text", "older", "oldest"])
        #expect(FileManager.default.fileExists(atPath: store.imagesURL.appendingPathComponent("\(id).png").path),
                "the image's file is kept")
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains(id), "and listed in the file")
    }

    @Test func aLimitAppliedWhileTheFileIsReadWritesOnlyWhatItDrops() throws {
        // No file (a clean launch): none written.
        let none = try Self.file(nil)
        defer { try? FileManager.default.removeItem(at: none.deletingLastPathComponent()) }
        let gate = DispatchSemaphore(value: 0)
        let fresh = Self.gated(none, gate)
        fresh.trim(to: 20)
        gate.signal()
        fresh.waitForWrites()
        #expect(fresh.items.isEmpty)
        fresh.waitForWrites()
        #expect(!FileManager.default.fileExists(atPath: none.path), "nothing written for an empty history")

        // A history within the limit: left as it is.
        let url = try Self.file(Self.twoItems)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let again = DispatchSemaphore(value: 0)
        let kept = Self.gated(url, again)
        kept.trim(to: 20)
        again.signal()
        kept.waitForWrites()
        #expect(kept.items.count == 2)
        kept.waitForWrites()
        #expect(try Data(contentsOf: url) == Self.twoItems, "an unchanged history isn't written again")

        // A lower limit: the oldest dropped, in the file too.
        let lower = DispatchSemaphore(value: 0)
        let trimmed = Self.gated(url, lower)
        trimmed.trim(to: 1)
        lower.signal()
        trimmed.waitForWrites()
        #expect(trimmed.items.map(\.text) == ["older"])
        trimmed.waitForWrites()
        #expect(ClipboardHistoryStore.loaded(url: url).items.map(\.text) == ["older"])
    }

    @Test func clearWhileTheFileIsReadDoesntWaitForIt() throws {
        let url = try Self.file(Self.twoItems)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = DispatchSemaphore(value: 0)
        let store = Self.gated(url, gate)
        let start = Date()
        store.clear()
        let waited = Date().timeIntervalSince(start)
        gate.signal()
        store.waitForWrites()
        #expect(waited < 1, "Clear History waited \(waited) s for the file to be read")
        #expect(store.items.isEmpty && !FileManager.default.fileExists(atPath: url.path))
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func waitForLoadReturnsForAStoreMadeOffTheMainThread() async throws {
        let url = try Self.file(Self.twoItems)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = await Task.detached { ClipboardHistoryStore(url: url) }.value
        await store.waitForLoad()
        #expect(store.items.map(\.text) == ["older", "oldest"])
    }
}
