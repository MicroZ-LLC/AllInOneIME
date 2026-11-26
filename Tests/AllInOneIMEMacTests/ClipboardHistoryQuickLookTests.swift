import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import AppKit
import Foundation
import Testing

/// ⌃V's look at the clipboard (`ClipboardRecorder.poll(limit:quick:)`), which never waits (0.7.6): a text copied just
/// before is in the history at once and its file written after, off the main thread; an image is made ready off the main
/// thread and kept once it is.
struct ClipboardHistoryQuickLookTests {
    typealias Recording = ClipboardHistoryRecordingTests

    @Test func aTextCopiedJustBeforeIsListedAtOnceAndWrittenAfter() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Recording.recorder(in: folder)
        pasteboard.copy("older")
        recorder.poll(limit: 20)
        pasteboard.copy("just copied")
        #expect(recorder.poll(limit: 20, quick: true) == .recorded)
        #expect(Recording.texts(recorder) == ["just copied", "older"], "in the panel's list at once")
        recorder.store.waitForWrites()
        #expect(ClipboardHistoryStore.loaded(url: recorder.store.url).items.map(\.text) == ["just copied", "older"], "then in the file")
        let attributes = try FileManager.default.attributesOfItem(atPath: recorder.store.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    /// Clear History right after: nothing written before it comes back after it.
    @Test func aClearAfterAWriteLeftForLaterLeavesNoFile() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Recording.recorder(in: folder)
        for index in 0..<20 {
            pasteboard.copy("copy \(index) " + String(repeating: "x", count: 50_000))
            recorder.poll(limit: 100, quick: true)
        }
        recorder.store.clear()
        recorder.store.waitForWrites()
        #expect(!FileManager.default.fileExists(atPath: recorder.store.url.path) && recorder.store.items.isEmpty)
        #expect(ClipboardHistoryStore.loaded(url: recorder.store.url).items.isEmpty)
    }

    /// A recorder making its images ready as the input method's does: off the main thread, handed back to it after.
    static func recorderOffTheMainThread(in folder: URL) -> (ClipboardRecorder, Recording.FakePasteboard) {
        let (recorder, pasteboard) = Recording.recorder(in: folder)
        recorder.imageWork = ClipboardRecorder(source: pasteboard, store: recorder.store, secureInput: { false }, frontmostApp: { nil }).imageWork
        return (recorder, pasteboard)
    }

    /// An image copied just before (a screenshot): ⌃V's look never waits for it (0.7.6), made ready off the main thread as
    /// any is, and kept once it is, told then (`keptLater`): the panel shows its kept row anew.
    @MainActor @Test func anImageCopiedJustBeforeIsKeptOnceReadNeverWaitedFor() async throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorderOffTheMainThread(in: folder)
        var told = 0
        recorder.keptLater = { told += 1 }
        pasteboard.copy("a text")
        recorder.poll(limit: 20)
        try await ImagePreviewTests.wait { recorder.store.items.count == 1 }
        let shot = Recording.png(400, 200)
        pasteboard.copy(image: shot)
        // Not waited for: kept within the look only where it was ready by its end (a small image, at times).
        let outcome = recorder.poll(limit: 20, quick: true)
        #expect(outcome == .imageQueued || outcome == .recorded, "\(outcome)")
        try await ImagePreviewTests.wait { recorder.store.items.first?.image != nil }
        let image = try #require(recorder.store.items.first?.image, "kept once ready: \(Recording.texts(recorder))")
        #expect(image.width == 400 && image.thumbnail != nil && recorder.store.imageData(image.id) == shot.data)
        #expect(recorder.clipboardIsNewest, "the clipboard's image is the newest: its kept row stands for it")
        #expect(told == (outcome == .imageQueued ? 1 : 0), "only what is kept after its look is told: \(told)")
        #expect(recorder.store.items.count == 2 && recorder.poll(limit: 20) == .unchanged)
    }

    /// An image made ready already as ⌃V comes, its turn on the main thread not come yet: ⌃V's look keeps it at once.
    @MainActor @Test func anImageReadyBeforeItsTurnIsKeptByControlVsLook() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Recording.recorder(in: folder)
        var turn: (() -> Void)?
        recorder.imageWork = { prepare, done in
            let result = prepare()
            turn = { done(result) }
        }
        pasteboard.copy(image: Recording.png(300, 300))
        #expect(recorder.poll(limit: 20) == .imageQueued)
        recorder.poll(limit: 20, quick: true)
        #expect(recorder.store.items.first?.image?.width == 300 && recorder.clipboardIsNewest, "\(recorder.store.items)")
        turn?()
        #expect(recorder.store.items.count == 1, "its turn after: nothing more")
    }

    /// One still being made ready as ⌃V comes: the look doesn't wait for it (the panel offers the image on the clipboard
    /// meanwhile); it is kept once it is ready.
    @Test func anImageBeingMadeReadyIsNotWaitedFor() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Recording.recorder(in: folder)
        var held: (() -> Void)?
        recorder.imageWork = { prepare, done in held = { done(prepare()) } }
        pasteboard.copy(image: Recording.png(8, 8))
        let start = Date()
        #expect(recorder.poll(limit: 20, quick: true) == .imageQueued)
        let waited = Date().timeIntervalSince(start)
        #expect(waited < 0.06, "\(waited) s")
        #expect(recorder.store.items.isEmpty && !recorder.clipboardIsNewest)
        held?()
        #expect(recorder.store.items.first?.image != nil && recorder.clipboardIsNewest)
    }

    /// The owner's report: two screenshots one after the other, ⌃V right after the second. The panel's rows, as the
    /// session builds them from what ⌃V's look gives it (the input method's `ClipboardHistoryShared.services`): the second
    /// screenshot's kept row first, chosen, its thumbnail standing for the second (what its preview shows), then the
    /// first's. Before, the second was "Image on the clipboard", which has no preview. Since 0.7.6 ⌃V doesn't wait for
    /// it: the panel opens with "Image on the clipboard" first, and shows the kept row once it is in (`keptLater`, as
    /// `ClipboardHistoryShared` tells the field's session).
    @MainActor @Test func twoScreenshotsThenControlV() async throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorderOffTheMainThread(in: folder)
        let (first, second) = (Recording.png(640, 400, shade: 0.2), Recording.png(500, 300, shade: 0.8))
        pasteboard.copy(image: first)
        recorder.poll(limit: 20)  // the look each second
        try await ImagePreviewTests.wait { recorder.store.items.count == 1 }
        pasteboard.copy(image: second)
        let host = FakeHost(services: SessionServices())
        host.keepClipboardHistory()
        host.session.services.clipboardHistory = ClipboardHistoryServices(
            state: { .recording },
            items: { MainActor.assumeIsolated { recorder.poll(limit: 20, quick: true); return recorder.store.items } },
            canPassPasteKey: { true }, imageData: { recorder.store.imageData($0) },
            clipboardIsNewest: { MainActor.assumeIsolated { recorder.clipboardIsNewest } })
        recorder.keptLater = { host.send(.clipboardHistoryChanged) }
        host.clipboard = .image(Data())  // ⌃V's panel looks at the types only
        _ = host.press(FakeHost.controlV)
        _ = host.settle { host.panel != nil }
        // "Image on the clipboard" first unless the second was ready by then (a small image is, at times).
        try await ImagePreviewTests.wait { recorder.store.items.count == 2 && host.panel?.rows.first?.text != "Image on the clipboard" }
        let rows = host.panel?.rows ?? []
        #expect(rows.map(\.text) == ["Image 500 × 300", "Image 640 × 400"] && host.panel?.highlighted == 0, "\(rows.map(\.text))")
        let kept = rows.map { row -> ClipboardHistoryImage? in
            guard case let .image(path, _)? = row.icon?.glyph else { return nil }
            return recorder.store.image(thumbnail: path)?.image
        }
        #expect(kept.map { $0?.width } == [500, 640], "each row's thumbnail stands for its own image")
    }
}
