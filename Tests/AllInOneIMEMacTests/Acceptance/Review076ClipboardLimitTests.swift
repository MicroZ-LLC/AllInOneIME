import AllInOneIMEMac
import AllInOneIMECore
import AppKit
import Foundation
import Testing
import AllInOneIMETestSupport

@Suite("0.7.6 review: clipboard image limit", .serialized)
struct Review076ClipboardLimitTests {
    private func image(_ red: CGFloat) throws -> ClipboardImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: red, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        return ClipboardImage(data: try #require(bitmap.representation(using: .png, properties: [:])), width: 2, height: 2)
    }

    @Test func imagePushedPastTheLimitLosesBothFiles() async throws {
        let folder = TestScratch.temporary("review076-clipboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardHistoryStore(url: folder.appendingPathComponent("clipboard-history.json"))
        await store.waitForLoad()
        let first = try image(0.2), older = try image(0.8)
        #expect(store.recordImage(first, at: Date(timeIntervalSince1970: 101), limit: 1))
        let keptID = try #require(store.items.first?.image?.id)
        guard case let .ready(ready) = store.prepare(older) else {
            Issue.record("the second image was not prepared")
            return
        }
        #expect(FileManager.default.fileExists(atPath: store.imagesURL.appendingPathComponent("\(ready.id).png").path))
        #expect(store.add(ready, at: Date(timeIntervalSince1970: 100), limit: 1))
        store.waitForWrites()
        #expect(store.items.count == 1)
        #expect(store.items.first?.image?.id == keptID)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: store.imagesURL.path)) ?? []
        #expect(!files.contains("\(ready.id).png"), "an image pushed out of history is still on disk: \(files)")
        #expect(!files.contains("\(ready.id)-thumb.png"), "its thumbnail is still on disk: \(files)")
    }
}
