import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import Testing

/// Clipboard history's recording on the Mac (`ClipboardRecorder`) with a pasteboard of the test's own: each copy's text
/// kept, newest first and once; nothing read while reading would ask; never what was copied during secure input, what a
/// password manager or clipboard tool marks, what isn't text, blank or too long. Its file (`ClipboardHistoryStore`): the
/// user's only (0600), excluded from backups, its limit, deleted by Clear and when the history is turned off.
struct ClipboardHistoryRecordingTests {
    /// A pasteboard: what was copied (its types and text), counted as the system counts changes; whether reading it would
    /// ask; how many times its types or text were read.
    final class FakePasteboard: ClipboardSource {
        var changeCount = 0
        var access = ClipboardAccess.allowed
        var copiedTypes: [String] = []
        var copiedText: String?
        var copiedImage: ClipboardImage?
        private(set) var reads = 0

        var types: [String] {
            reads += 1
            return copiedTypes
        }

        func text() -> String? {
            reads += 1
            return copiedText
        }

        func image() -> ClipboardImage? {
            reads += 1
            return copiedImage
        }

        /// An image copied (a screenshot: PNG first, no text).
        func copy(image: ClipboardImage, types: [String] = ["public.png"]) {
            (copiedImage, copiedText, copiedTypes) = (image, nil, types)
            changeCount += 1
        }

        /// `text` copied, with `types` (plain text's by default).
        func copy(_ text: String?, types: [String] = ["public.utf8-plain-text"]) {
            (copiedText, copiedTypes, copiedImage) = (text, types, nil)
            changeCount += 1
        }
    }

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A recorder over a fake pasteboard, keeping its file in `folder`; secure input as `secure` says.
    static func recorder(in folder: URL, secure: @escaping () -> Bool = { false }) -> (ClipboardRecorder, FakePasteboard) {
        let pasteboard = FakePasteboard()
        let store = ClipboardHistoryStore(url: folder.appendingPathComponent("clipboard-history.json"))
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let recorder = ClipboardRecorder(source: pasteboard, store: store, secureInput: secure, now: {
            clock += 1
            return clock
        })
        return (recorder, pasteboard)
    }

    static func texts(_ recorder: ClipboardRecorder) -> [String] { recorder.store.items.map(\.text) }

    @Test func eachCopyIsKeptNewestFirstAndOnce() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        #expect(recorder.poll(limit: 20) == .notText, "nothing on the clipboard at the first look")
        for text in ["one", "two", "three"] {
            pasteboard.copy(text)
            #expect(recorder.poll(limit: 20) == .recorded)
            #expect(recorder.poll(limit: 20) == .unchanged, "no change, nothing read again")
        }
        #expect(Self.texts(recorder) == ["three", "two", "one"])
        pasteboard.copy("one")
        #expect(recorder.poll(limit: 20) == .recorded)
        #expect(Self.texts(recorder) == ["one", "three", "two"], "copied again: to the top, once")
        let copiedAt = recorder.store.items[0].copiedAt
        pasteboard.copy("one")
        #expect(recorder.poll(limit: 20) == .same && recorder.store.items[0].copiedAt == copiedAt, "the newest again: as it was")
        // Kept across launches.
        let again = ClipboardHistoryStore(url: recorder.store.url)
        #expect(again.items == recorder.store.items)
    }

    @Test func theLimitDropsTheOldest() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        for index in 1...7 {
            pasteboard.copy("copy \(index)")
            recorder.poll(limit: 5)
        }
        #expect(Self.texts(recorder) == (3...7).reversed().map { "copy \($0)" })
        recorder.store.trim(to: 2)
        #expect(Self.texts(recorder) == ["copy 7", "copy 6"], "a lower limit: the oldest go at once")
        #expect(ClipboardHistoryStore(url: recorder.store.url).items.map(\.text) == ["copy 7", "copy 6"], "and from the file")
    }

    /// Reading would ask (Ask, never asked yet, Deny): nothing of the clipboard is read, only its change count; once
    /// allowed, the next change is recorded.
    @Test func nothingIsReadWhileReadingWouldAsk() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        for access in [ClipboardAccess.asks, .notListed, .denied] {
            pasteboard.access = access
            pasteboard.copy("secret \(access)")
            #expect(recorder.poll(limit: 20) == .notAllowed && recorder.access == access)
        }
        #expect(pasteboard.reads == 0 && recorder.store.items.isEmpty)
        pasteboard.access = .allowed
        pasteboard.copy("allowed now")
        #expect(recorder.poll(limit: 20) == .recorded && Self.texts(recorder) == ["allowed now"])
    }

    /// Copied during secure input (a password field had the keys then, or at the look before): not recorded.
    @Test func notDuringSecureInput() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var secure = false
        let (recorder, pasteboard) = Self.recorder(in: folder, secure: { secure })
        recorder.poll(limit: 20)
        secure = true
        pasteboard.copy("hunter2")
        #expect(recorder.poll(limit: 20) == .secureInput)
        recorder.poll(limit: 20)
        pasteboard.copy("hunter3")
        secure = false
        #expect(recorder.poll(limit: 20) == .secureInput, "secure input on at the look before the change")
        pasteboard.copy("fine")
        #expect(recorder.poll(limit: 20) == .recorded)
        #expect(Self.texts(recorder) == ["fine"])
    }

    /// What password managers and clipboard tools mark (concealed, transient, auto-generated), TerminalPaste's own writes
    /// (transient), a file, what has no text, blank or longer than 100,000 characters: never recorded.
    @Test func neverRecorded() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
                       "com.agilebits.onepassword"] {
            pasteboard.copy("password", types: ["public.utf8-plain-text", marker])
            #expect(recorder.poll(limit: 20) == .marked, "\(marker)")
        }
        pasteboard.copy("Report.pdf", types: ["public.file-url", "public.utf8-plain-text"])
        #expect(recorder.poll(limit: 20) == .marked, "a file")
        pasteboard.copy(nil, types: ["public.png"])
        #expect(recorder.poll(limit: 20) == .notText, "an image")
        pasteboard.copy(" \n\t ")
        #expect(recorder.poll(limit: 20) == .blank)
        pasteboard.copy(String(repeating: "a", count: ClipboardHistoryItem.maxLength + 1))
        #expect(recorder.poll(limit: 20) == .tooLong)
        pasteboard.copy(String(repeating: "a", count: ClipboardHistoryItem.maxLength))
        #expect(recorder.poll(limit: 20) == .recorded, "100,000 characters: kept")
        #expect(recorder.store.items.count == 1)
    }

    /// The file is the user's only (0600), excluded from backups; Clear deletes it, and the next copy makes it again; the
    /// history turned off is the same Clear (`ClipboardHistoryShared`).
    @Test func theFileIsTheUsersOnlyAndClearDeletesIt() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        pasteboard.copy("kept")
        recorder.poll(limit: 20)
        let url = recorder.store.url
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600, "mode \(String(mode ?? 0, radix: 8))")
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        pasteboard.copy("again")
        recorder.poll(limit: 20)
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600, "each write")
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        recorder.store.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path) && recorder.store.items.isEmpty)
        #expect(ClipboardHistoryStore(url: url).items.isEmpty)
        recorder.forget()
        pasteboard.copy("after")
        #expect(recorder.poll(limit: 20) == .recorded && Self.texts(recorder) == ["after"] && FileManager.default.fileExists(atPath: url.path))
    }

    /// Clear History (and the history turned off and on again: `ClipboardHistoryShared` forgets then too) doesn't record
    /// what is on the clipboard at the next look: its change count is remembered, nothing of it read; only a later copy.
    @Test func clearDoesntRecordWhatIsOnTheClipboardAgain() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        pasteboard.copy("cleared")
        #expect(recorder.poll(limit: 20) == .recorded)
        recorder.store.clear()
        recorder.forget()
        let reads = pasteboard.reads
        #expect(recorder.poll(limit: 20) == .unchanged && recorder.store.items.isEmpty && pasteboard.reads == reads,
                "the next look: what was copied before Clear stays out")
        #expect(recorder.poll(limit: 20) == .unchanged && recorder.store.items.isEmpty)
        // Copied while the history was off, then on again (forgotten as it comes on): not recorded either.
        pasteboard.copy("while off")
        recorder.forget()
        #expect(recorder.poll(limit: 20) == .unchanged && recorder.store.items.isEmpty)
        pasteboard.copy("later")
        #expect(recorder.poll(limit: 20) == .recorded && Self.texts(recorder) == ["later"])
    }

    /// A file that can't be read is an empty history, made anew by the next copy.
    @Test func anUnreadableFileIsEmpty() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clipboard-history.json")
        try Data("not json".utf8).write(to: url)
        let store = ClipboardHistoryStore(url: url)
        #expect(store.items.isEmpty)
        store.record("new", at: Date(), limit: 20)
        #expect(ClipboardHistoryStore(url: url).items.map(\.text) == ["new"])
    }

    // MARK: - Images (0.6.8.2)

    /// A PNG `width` × `height` pixels, of `shade`.
    static func png(_ width: Int, _ height: Int, shade: CGFloat = 0.5) -> ClipboardImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<width { for y in 0..<height { bitmap.setColor(NSColor(deviceRed: shade, green: shade, blue: 1 - shade, alpha: 1), atX: x, y: y) } }
        return ClipboardImage(png: bitmap.representation(using: .png, properties: [:])!, width: width, height: height)
    }

    @Test func anImageCopiedIsKeptWithAThumbnailInFilesOfTheUsersOnly() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        pasteboard.copy("a text")
        #expect(recorder.poll(limit: 20) == .recorded)
        let shot = Self.png(400, 200)
        pasteboard.copy(image: shot)
        #expect(recorder.poll(limit: 20) == .recorded)
        let image = try #require(recorder.store.items.first?.image)
        #expect(image.width == 400 && image.height == 200 && image.bytes == shot.png.count)
        #expect(recorder.store.items.map(\.text) == ["", "a text"])
        #expect(recorder.store.imageData(image.id) == shot.png)
        let thumbnail = try #require(image.thumbnail)
        let thumb = try #require(NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: thumbnail))))
        #expect(thumb.pixelsWide == 96 && thumb.pixelsHigh == 48, "\(thumb.pixelsWide)×\(thumb.pixelsHigh)")
        for file in [recorder.store.url.path, thumbnail, recorder.store.imagesURL.appendingPathComponent("\(image.id).png").path] {
            let mode = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int
            #expect(mode == 0o600, "\(file): \(String(mode ?? 0, radix: 8))")
        }
        #expect(try recorder.store.imagesURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(recorder.clipboardIsNewest, "the clipboard holds the newest copy still")
        // Read again from the file, as the next launch does.
        let again = ClipboardHistoryStore(url: recorder.store.url)
        #expect(again.items.first?.image == image && again.items.count == 2)
    }

    @Test func theSameImageAgainMovesUpAndAnImageDroppedIsDeleted() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (recorder, pasteboard) = Self.recorder(in: folder)
        let (first, second) = (Self.png(10, 10, shade: 0.2), Self.png(10, 10, shade: 0.8))
        pasteboard.copy(image: first)
        recorder.poll(limit: 2)
        pasteboard.copy(image: second)
        recorder.poll(limit: 2)
        pasteboard.copy(image: first)
        #expect(recorder.poll(limit: 2) == .recorded)
        #expect(recorder.store.items.count == 2, "each image once")
        let firstID = try #require(recorder.store.items.first?.image?.id)
        let secondID = try #require(recorder.store.items.last?.image?.id)
        pasteboard.copy("a text")
        recorder.poll(limit: 2)
        #expect(recorder.store.items.map(\.text) == ["a text", ""])
        #expect(recorder.store.imageData(secondID) == nil, "the oldest dropped beyond the limit")
        let files = try FileManager.default.contentsOfDirectory(atPath: recorder.store.imagesURL.path).sorted()
        #expect(files == ["\(firstID)-thumb.png", "\(firstID).png"].sorted(), "\(files)")
        recorder.store.clear()
        #expect(!FileManager.default.fileExists(atPath: recorder.store.imagesURL.path), "Clear deletes the images too")
    }

    @Test func anImageIsNeverRecordedWhereATextWouldntBe() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var secure = false
        let (recorder, pasteboard) = Self.recorder(in: folder, secure: { secure })
        pasteboard.copy(image: Self.png(8, 8), types: ["public.png", "org.nspasteboard.ConcealedType"])
        #expect(recorder.poll(limit: 20) == .marked)
        secure = true
        pasteboard.copy(image: Self.png(8, 8))
        #expect(recorder.poll(limit: 20) == .secureInput)
        secure = false
        recorder.poll(limit: 20)
        let huge = ClipboardImage(png: Data(count: ClipboardHistoryImage.maxBytes + 1), width: 1, height: 1)
        pasteboard.copy(image: huge)
        #expect(recorder.poll(limit: 20) == .tooLong)
        pasteboard.access = .asks
        pasteboard.copy(image: Self.png(8, 8))
        #expect(recorder.poll(limit: 20) == .notAllowed)
        #expect(recorder.store.items.isEmpty)
    }
}
