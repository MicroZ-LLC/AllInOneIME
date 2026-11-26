import AllInOneIMEMac
import AppKit
import Foundation
import Testing

/// Clipboard history's image files while the list's writes (`ClipboardHistoryStore`'s queue) and an image being made
/// ready (`prepare`, on the recorder's image queue) run side by side (0.7.6 review): an image made ready while the folder's
/// unlisted files are deleted keeps its files; the same image made ready twice (copied before and after Clear History)
/// keeps its files until the last of them is added or discarded; the writes left are done before the input method ends,
/// half a second at most (`drain`).
@Suite(.serialized)
struct ClipboardHistoryImageRaceTests {
    typealias Recording = ClipboardHistoryRecordingTests

    /// The files an image made ready has in `store`'s folder: its PNG and its thumbnail.
    static func files(of id: String, in store: ClipboardHistoryStore) -> [String] {
        ["\(id).png", "\(id)-thumb.png"].filter {
            FileManager.default.fileExists(atPath: store.imagesURL.appendingPathComponent($0).path)
        }
    }

    /// Clear History deletes every unlisted file and then the folder (off the main thread); images copied meanwhile are
    /// made ready (their files written) while that runs, one after another until it is done. Each keeps its files, and
    /// is kept with them once added.
    @Test func imagesMadeReadyWhileAClearDeletesTheFolderKeepTheirFiles() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardHistoryStore.loaded(url: folder.appendingPathComponent("clipboard-history.json"))
        // Unlisted images' files enough for the clear to take a while deleting them (as a long history's would).
        try FileManager.default.createDirectory(at: store.imagesURL, withIntermediateDirectories: true)
        for index in 0..<5000 {
            let id = String(format: "%064x", index)
            FileManager.default.createFile(atPath: store.imagesURL.appendingPathComponent("\(id).png").path, contents: Data([1]))
        }
        let shots = (0..<60).map { Recording.png(4, 4, shade: CGFloat($0) / 60) }
        let cleared = DispatchSemaphore(value: 0)
        store.clear()
        DispatchQueue.global().async {
            store.waitForWrites()  // the clear done
            cleared.signal()
        }
        // Made ready one after another while it deletes (an image copied each moment), at least one, until it is done.
        var ready: [ClipboardHistoryStore.ReadyImage] = []
        repeat {
            let prepared = store.prepare(shots[ready.count % shots.count])
            guard case let .ready(image) = prepared else {
                Issue.record("an image copied while the clear ran wasn't kept (\(prepared)): its folder deleted as it was written")
                return
            }
            ready.append(image)
        } while cleared.wait(timeout: .now()) == .timedOut
        let date = Date()
        for (index, image) in ready.enumerated() { store.add(image, at: date.addingTimeInterval(Double(index)), limit: 1000) }
        store.waitForWrites()
        let kept = store.items.compactMap(\.image)
        #expect(!kept.isEmpty)
        let lost = kept.filter { Self.files(of: $0.id, in: store).count != 2 }
        #expect(lost.isEmpty, "\(lost.count) of \(kept.count) images made ready while the clear ran lost their files")
        #expect(ClipboardHistoryStore.loaded(url: store.url).items.count == kept.count, "the next launch hasn't them all")
    }

    /// The owner's order of things in the review: an image copied, Clear History, the same image copied again, both made
    /// ready before either is added. The first, made ready before the clear, is discarded; the second is kept, with its
    /// files.
    @Test func theSameImageMadeReadyTwiceKeepsItsFilesUntilTheLastIsDone() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardHistoryStore.loaded(url: folder.appendingPathComponent("clipboard-history.json"))
        let shot = Recording.png(40, 20)
        guard case let .ready(before) = store.prepare(shot) else {
            Issue.record("not made ready")
            return
        }
        store.clear()
        guard case let .ready(after) = store.prepare(shot) else {
            Issue.record("not made ready again")
            return
        }
        #expect(before.id == after.id)
        store.discard(before)  // copied before the clear: not kept
        store.waitForWrites()
        #expect(Self.files(of: after.id, in: store).count == 2, "the discarded copy's deletion took the kept one's files")
        #expect(store.add(after, at: Date(), limit: 20))
        store.waitForWrites()
        let image = try #require(store.items.first?.image)
        #expect(image.thumbnail != nil && store.imageData(image.id) == shot.data, "its row has no picture")
        #expect(Self.files(of: after.id, in: store).count == 2)
    }

    /// The same image made ready twice and added twice (copied twice quickly): the second add, the newest already, keeps
    /// the files the first wrote the list with.
    @Test func theSameImageAddedTwiceKeepsItsFiles() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardHistoryStore.loaded(url: folder.appendingPathComponent("clipboard-history.json"))
        let shot = Recording.png(30, 30)
        guard case let .ready(one) = store.prepare(shot), case let .ready(two) = store.prepare(shot) else {
            Issue.record("not made ready")
            return
        }
        #expect(store.add(one, at: Date(), limit: 20))
        #expect(!store.add(two, at: Date(), limit: 20), "the newest already")
        store.waitForWrites()
        #expect(Self.files(of: one.id, in: store).count == 2 && store.imageData(one.id) == shot.data)
    }

    /// What was asked of the history's files before the input method ends (Clear History just before an update) is done
    /// before it ends: `drain` waits for it, half a second at most, and says whether it was all done.
    @Test func drainWaitsForTheWritesLeftWithinItsBound() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clipboard-history.json")
        let written = ClipboardHistoryStore.loaded(url: url)
        written.record("kept before", at: Date(), limit: 20)
        written.waitForWrites()
        let file = try Data(contentsOf: url)
        // The next store's read of the file holds its writes up a while (a slow disk): Clear History queued behind it.
        let store = ClipboardHistoryStore(url: url, readFile: { url in
            usleep(150_000)
            return try? Data(contentsOf: url)
        })
        store.clear()
        let start = Date()
        #expect(ClipboardHistoryStore.drain(within: 0.5), "not all done within half a second")
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(!FileManager.default.fileExists(atPath: url.path), "the clear wasn't done when drain returned")

        // Held up longer than the bound: drain gives up at it, and says so.
        try file.write(to: url)
        let slow = ClipboardHistoryStore(url: url, readFile: { url in
            usleep(1_200_000)
            return try? Data(contentsOf: url)
        })
        slow.clear()
        let held = Date()
        #expect(!ClipboardHistoryStore.drain(within: 0.2))
        let waited = Date().timeIntervalSince(held)
        #expect(waited >= 0.19 && waited < 0.6, "\(waited) s")
        slow.waitForWrites()
    }
}
