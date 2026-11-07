import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import Testing

/// ⌃V's look at the clipboard (`ClipboardRecorder.poll(limit:quick:)`), which its panel waits for: a text copied just
/// before is in the history at once and its file written after, off the main thread; an image isn't read then (all of
/// its data would be), but by the next look.
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
        #expect(ClipboardHistoryStore(url: recorder.store.url).items.map(\.text) == ["just copied", "older"], "then in the file")
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
        #expect(ClipboardHistoryStore(url: recorder.store.url).items.isEmpty)
    }

    /// An image: not read by ⌃V's look (the clipboard not looked at yet: `clipboardIsNewest` false, so the panel offers
    /// what is on it), read and kept by the next look.
    @Test func anImageIsLeftForTheNextLook() throws {
        let folder = try Recording.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Recording.recorder(in: folder)
        pasteboard.copy("a text")
        recorder.poll(limit: 20)
        pasteboard.copy(image: Recording.png(8, 8))
        let reads = pasteboard.reads
        #expect(recorder.poll(limit: 20, quick: true) == .imageLater)
        #expect(Recording.texts(recorder) == ["a text"] && !recorder.clipboardIsNewest)
        #expect(pasteboard.reads - reads <= 2, "its types only, not its data")
        #expect(recorder.poll(limit: 20) == .recorded, "made ready at once here")
        #expect(recorder.store.items.first?.image != nil && recorder.clipboardIsNewest)
        // Universal Clipboard's image (fetched from the other device when read): as a look always took it.
        pasteboard.copy(image: Recording.png(4, 4), types: ["public.png", SystemClipboard.remoteType])
        #expect(recorder.poll(limit: 20, quick: true) != .imageLater)
    }
}
