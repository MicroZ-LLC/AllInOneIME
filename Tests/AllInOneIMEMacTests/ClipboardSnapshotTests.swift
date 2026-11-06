import AllInOneIMEMac
import AppKit
import Foundation
import Testing

/// What a paste of the input method's keeps of the clipboard to put back after it (`ClipboardSnapshot`), on a pasteboard
/// of the test's own: nothing read where reading would ask (Ask, never asked yet) or come back empty (Deny); with Allow,
/// every item and type in its order, put back as it was.
@MainActor
struct ClipboardSnapshotTests {
    /// Hands out its data when a reader asks, counting each time.
    final class CountingProvider: NSObject, NSPasteboardItemDataProvider {
        private(set) var reads = 0

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            reads += 1
            item.setString("what the user copied", forType: type)
        }
    }

    /// A pasteboard of the test's own, with what the user copied on it (through `provider`).
    static func copied(through provider: CountingProvider) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.aipinyin.inputmethod.tests.snapshot.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.writeObjects([item])
        return pasteboard
    }

    @Test(arguments: [ClipboardAccess.denied, .asks, .notListed])
    func nothingIsReadWithoutAllow(_ access: ClipboardAccess) {
        let provider = CountingProvider()
        let pasteboard = Self.copied(through: provider)
        defer { pasteboard.releaseGlobally() }
        #expect(ClipboardSnapshot.take(pasteboard, access: access) == nil)
        #expect(provider.reads == 0)
        // The reads are counted: with Allow, what was copied is read.
        let snapshot = ClipboardSnapshot.take(pasteboard, access: .allowed)
        #expect(provider.reads > 0 && snapshot?.items.count == 1)
    }

    @Test func withAllowItIsKeptAndPutBack() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.aipinyin.inputmethod.tests.snapshot.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let html = NSPasteboard.PasteboardType.html, plain = NSPasteboard.PasteboardType.string
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        first.setString("<b>bold</b>", forType: html)
        first.setString("bold", forType: plain)
        second.setString("second", forType: plain)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let snapshot = try #require(ClipboardSnapshot.take(pasteboard, access: .allowed))
        #expect(snapshot.items.map { $0.map(\.type) } == [[html, plain], [plain]])
        pasteboard.clearContents()
        pasteboard.setString("ours", forType: plain)
        snapshot.restore(to: pasteboard)
        let items = pasteboard.pasteboardItems ?? []
        #expect(items.map(\.types) == [[html, plain], [plain]])
        #expect(items.map { $0.string(forType: plain) } == ["bold", "second"])
        #expect(items.first?.string(forType: html) == "<b>bold</b>")
    }
}
