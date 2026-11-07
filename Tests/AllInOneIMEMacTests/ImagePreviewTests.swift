import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import Testing

/// Clipboard history's larger picture of an image (`ImagePreviewLayout`, `ImagePreviewImages`; the input method's
/// ImagePreview.swift shows it beside the panel): the row under the pointer when it's an image's, else the chosen one,
/// else none, and none once the panel hides; up to 360 pt, never larger than the image, its shape kept; on the panel's
/// right 8 pt from it with its top at the row's, smaller there to fit (160 pt at least), on its left only where even
/// that doesn't fit, on the screen, never over the panel, none without room on either side. The image decoded off the
/// main thread at the size drawn, a result no longer wanted never shown, a few kept, none once cleared. The kept image
/// a row's thumbnail stands for (`ClipboardHistoryStore`).
struct ImagePreviewTests {
    typealias Layout = ImagePreviewLayout

    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    // MARK: - Which row's image

    @Test func theRowUnderThePointerWinsThenTheChosenRowThenNone() {
        let images: Set<Int> = [0, 2, 3]
        let isImage = { images.contains($0) }
        #expect(Layout.row(hovered: 2, chosen: 0, isImage: isImage) == 2, "pointing at an image row: its image, whatever is chosen")
        #expect(Layout.row(hovered: 1, chosen: 3, isImage: isImage) == 3, "pointing at a text row: the chosen row's image")
        #expect(Layout.row(hovered: nil, chosen: 0, isImage: isImage) == 0, "the pointer off the rows: the chosen row's image")
        #expect(Layout.row(hovered: nil, chosen: 1, isImage: isImage) == nil, "a text row chosen: none")
        #expect(Layout.row(hovered: 4, chosen: 1, isImage: isImage) == nil, "text rows pointed at and chosen: none")
        #expect(Layout.row(hovered: nil, chosen: nil, isImage: isImage) == nil)
    }

    /// The panel with two image rows (0 and 2) and a text row (1) between them, its rows 40 pt high from its top.
    static func shown(hovered: Int?, chosen: Int?, showing: Bool = true) -> Layout.Shown? {
        let panel = CGRect(x: 300, y: 400, width: 320, height: 160)
        let state = showing ? Layout.Panel(frame: panel, hovered: hovered, chosen: chosen, visible: screen, scale: 2) : nil
        return Layout.shown(state, inset: 6) { index in
            [0: CGSize(width: 800, height: 400), 2: CGSize(width: 300, height: 600)][index]
                .map { Layout.ImageRow(pixels: $0, top: panel.maxY - 6 - CGFloat(index) * 40) }
        }
    }

    @Test func whatShowsFollowsThePointerAndTheChoiceAndGoesWithThePanel() throws {
        let chosen = try #require(Self.shown(hovered: nil, chosen: 0))
        #expect(chosen.row == 0 && chosen.imageSize == CGSize(width: 360, height: 180))
        #expect(chosen.frame == CGRect(x: 628, y: 554 - 192, width: 372, height: 192), "\(chosen.frame)")
        let pointed = try #require(Self.shown(hovered: 2, chosen: 0))
        #expect(pointed.row == 2 && pointed.imageSize == CGSize(width: 150, height: 300), "the row pointed at wins")
        #expect(pointed.frame.maxY == CGFloat(554 - 80), "its top at the row's: it moves with the row (\(pointed.frame))")
        #expect(Self.shown(hovered: 1, chosen: 2)?.row == 2, "a text row pointed at: the chosen one's")
        #expect(Self.shown(hovered: 1, chosen: 1) == nil, "a text row pointed at and chosen: none")
        #expect(Self.shown(hovered: 2, chosen: 0, showing: false) == nil, "the panel hidden: none")
    }

    // MARK: - Size

    @Test func itsSizeIsAtMost360PointsNeverLargerThanTheImageItsShapeKept() {
        // A 6K screenshot on a Retina screen.
        let screenshot = Layout.size(pixels: CGSize(width: 6016, height: 3384), scale: 2)
        #expect(screenshot == CGSize(width: 360, height: 203), "\(screenshot)")
        // Small: its own size in points (a pixel to a screen pixel), never made larger.
        #expect(Layout.size(pixels: CGSize(width: 400, height: 200), scale: 2) == CGSize(width: 200, height: 100))
        #expect(Layout.size(pixels: CGSize(width: 120, height: 90), scale: 1) == CGSize(width: 120, height: 90))
        // The same image on a screen of a point to a pixel: capped.
        #expect(Layout.size(pixels: CGSize(width: 400, height: 200), scale: 1) == CGSize(width: 360, height: 180))
        // Tall: its height capped.
        #expect(Layout.size(pixels: CGSize(width: 900, height: 2400), scale: 2) == CGSize(width: 135, height: 360))
        // Very thin: a point at least.
        #expect(Layout.size(pixels: CGSize(width: 8000, height: 2), scale: 2) == CGSize(width: 360, height: 1))
        #expect(Layout.size(pixels: .zero, scale: 2) == .zero)
        for (width, height, scale) in [(6016.0, 3384.0, 2.0), (1000, 3000, 1), (720, 720, 2), (5, 1999, 2), (333, 777, 3)] {
            let size = Layout.size(pixels: CGSize(width: width, height: height), scale: scale)
            #expect(max(size.width, size.height) <= Layout.maxSide)
            #expect(size.width <= max((width / scale).rounded(), 1) && size.height <= max((height / scale).rounded(), 1), "never upscaled")
            // Its shape kept: each side the image's scaled by one factor, to the nearest point (a point at least).
            let factor = min(1, Layout.maxSide / max(width / scale, height / scale))
            #expect(abs(size.width - width / scale * factor) <= 0.5 || size.width == 1, "\(size) for \(width) × \(height)")
            #expect(abs(size.height - height / scale * factor) <= 0.5 || size.height == 1, "\(size) for \(width) × \(height)")
        }
    }

    // MARK: - Place

    @Test func itGoesOnThePanelsRightItsTopAtTheRows() throws {
        let panel = CGRect(x: 200, y: 300, width: 320, height: 200)
        let placed = try #require(Layout.frame(image: CGSize(width: 288, height: 148), inset: 6, panel: panel, rowTop: 480, visible: Self.screen))
        #expect(placed.image == CGSize(width: 288, height: 148), "at its size where it fits")
        #expect(placed.frame == CGRect(x: panel.maxX + 8, y: 480 - 160, width: 300, height: 160))
    }

    /// Less room on the right than it takes: smaller there, its shape kept, its height rounded, the width the room's.
    @Test func smallerOnTheRightWhereItDoesntFitThere() throws {
        let panel = CGRect(x: 900, y: 300, width: 320, height: 200)  // 212 pt from the gap to the screen's edge
        let placed = try #require(Layout.frame(image: CGSize(width: 360, height: 203), inset: 6, panel: panel, rowTop: 480, visible: Self.screen))
        #expect(placed.image == CGSize(width: 200, height: 113), "\(placed.image)")  // 212 - 12 wide; 203 × 200 / 360 = 112.8
        #expect(placed.frame == CGRect(x: 1228, y: 480 - 125, width: 212, height: 125), "\(placed.frame)")
        // Down to 160 pt on its longer side: on the right still.
        let narrow = try #require(Layout.frame(image: CGSize(width: 360, height: 203), inset: 6,
                                               panel: CGRect(x: 952, y: 300, width: 300, height: 200), rowTop: 480, visible: Self.screen))
        #expect(narrow.image == CGSize(width: 168, height: 95) && narrow.frame.minX == 1260, "\(narrow)")
        // A tall one: as wide as the room, its longer side the height.
        let tall = try #require(Layout.frame(image: CGSize(width: 135, height: 360), inset: 6,
                                             panel: CGRect(x: 1000, y: 300, width: 320, height: 200), rowTop: 480, visible: Self.screen))
        #expect(tall.image == CGSize(width: 100, height: 267) && tall.frame.minX == 1328, "\(tall)")
    }

    /// On the left only where it fits on the right at no size of 160 pt or more (the panel at the screen's right edge): at
    /// its size there, or smaller to fit the room there the same way.
    @Test func onTheLeftOnlyWhereEven160PointsDontFitOnTheRight() throws {
        let edge = CGRect(x: 1100, y: 300, width: 330, height: 200)  // 2 pt to the screen's edge
        let left = try #require(Layout.frame(image: CGSize(width: 288, height: 148), inset: 6, panel: edge, rowTop: 480, visible: Self.screen))
        #expect(left.image == CGSize(width: 288, height: 148) && left.frame == CGRect(x: 1100 - 8 - 300, y: 320, width: 300, height: 160))
        // 160 pt for the image on the right (1440 - 1260 - 8 - 2 × 6): there; 159: too small, so on the left.
        let square = CGSize(width: 360, height: 360)
        let at160 = try #require(Layout.frame(image: square, inset: 6, panel: CGRect(x: 1000, y: 300, width: 260, height: 200), rowTop: 480,
                                              visible: Self.screen))
        #expect(at160.image == CGSize(width: 160, height: 160) && at160.frame.minX == 1268, "\(at160)")
        let at159 = try #require(Layout.frame(image: square, inset: 6, panel: CGRect(x: 1000, y: 300, width: 261, height: 200), rowTop: 480,
                                              visible: Self.screen))
        #expect(at159.image == square && at159.frame.maxX == 1000 - 8, "\(at159)")
        // Little room on the left too: smaller there.
        let wide = CGRect(x: 250, y: 300, width: 1188, height: 200)
        let squeezed = try #require(Layout.frame(image: CGSize(width: 360, height: 203), inset: 6, panel: wide, rowTop: 480, visible: Self.screen))
        #expect(squeezed.image == CGSize(width: 230, height: 130), "\(squeezed.image)")
        #expect(squeezed.frame == CGRect(x: 0, y: 480 - 142, width: 242, height: 142), "\(squeezed.frame)")
    }

    @Test func noneWithoutRoomOnEitherSide() {
        let wide = CGRect(x: 100, y: 300, width: 1200, height: 200)  // 132 pt on the right, 92 on the left
        #expect(Layout.frame(image: CGSize(width: 288, height: 148), inset: 6, panel: wide, rowTop: 480, visible: Self.screen) == nil)
        // Small: never made larger, so it fits as it is or not at all (150 pt where 140 are free).
        #expect(Layout.frame(image: CGSize(width: 150, height: 100), panel: CGRect(x: 148, y: 0, width: 1144, height: 100), rowTop: 90,
                             visible: Self.screen) == nil)
        let small = CGRect(x: 0, y: 0, width: 600, height: 300)
        #expect(Layout.frame(image: CGSize(width: 188, height: 308), inset: 6, panel: CGRect(x: 100, y: 0, width: 100, height: 100), rowTop: 90,
                             visible: small) == nil, "taller than the screen")
    }

    @Test func movedOntoTheScreenUpOrDown() throws {
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 835)
        // A row near the bottom: up onto the screen.
        let low = try #require(Layout.frame(image: CGSize(width: 300, height: 200), panel: CGRect(x: 100, y: 40, width: 320, height: 120),
                                            rowTop: 150, visible: visible)).frame
        #expect(low.minY == visible.minY && low.minX == 428)
        // A row reported above the screen's top (a panel partly off it): down onto it.
        let high = try #require(Layout.frame(image: CGSize(width: 300, height: 200), panel: CGRect(x: 100, y: 700, width: 320, height: 200),
                                             rowTop: 900, visible: visible)).frame
        #expect(high.maxY == visible.maxY)
    }

    /// The owner's screen (1280 × 832 points, its menu bar 33) and a full-screen screenshot of it (2560 × 1664 pixels: 360 ×
    /// 234 points at most): wherever the panel is, the preview is on its right, smaller where the room there is less, its
    /// shape kept, its longer side 160 pt at least; on its left only where even that doesn't fit (the panel at the screen's
    /// right edge). The image is decoded at the size drawn (`imageSize`).
    @Test func onTheOwnersScreenItStaysOnTheRightSmallerWhereItMust() throws {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 799)
        var (right, smaller, left) = (0, 0, 0)
        for x in stride(from: 0.0, through: 1280 - 360, by: 10) {
            let panel = CGRect(x: x, y: 300, width: 360, height: 240)
            let state = Layout.Panel(frame: panel, hovered: nil, chosen: 0, visible: visible, scale: 2)
            let screenshot = Layout.ImageRow(pixels: CGSize(width: 2560, height: 1664), top: panel.maxY - 6)
            let shown = try #require(Layout.shown(state, inset: 6) { $0 == 0 ? screenshot : nil }, "none beside the panel at \(x)")
            let image = shown.imageSize
            #expect(shown.frame.size == CGSize(width: image.width + 12, height: image.height + 12))
            #expect(abs(image.height - image.width * 1664 / 2560) <= 0.5, "its shape kept: \(image)")
            #expect(!shown.frame.intersects(panel) && visible.contains(shown.frame), "\(shown.frame) by \(panel)")
            let room = visible.maxX - panel.maxX - Layout.gap - 12
            if room >= Layout.minSide {
                #expect(shown.frame.minX == panel.maxX + Layout.gap, "on the right while it fits there at 160 pt: \(shown.frame) by \(panel)")
                #expect(image.width == min(360, room.rounded(.down)), "as large as the room there allows, 360 pt at most: \(image)")
                if image.width < 360 { smaller += 1 } else { right += 1 }
            } else {
                #expect(shown.frame.maxX == panel.minX - Layout.gap && image.width == 360, "on the left at its size: \(shown.frame)")
                left += 1
            }
            #expect(shown.frame.maxY == panel.maxY - 6, "its top at the row's")
        }
        #expect(right > 0 && smaller > 0 && left > 0, "\(right) on the right, \(smaller) smaller there, \(left) on the left")
    }

    @Test func neverOverThePanelAndAlwaysOnTheScreen() {
        let visible = CGRect(x: -1280, y: 25, width: 1280, height: 775)  // a screen left of the main one, under a menu bar
        let (size, inset) = (CGSize(width: 360, height: 200), CGFloat(6))
        // The least the window takes beside the panel: the image at 160 pt on its longer side, its inset, the gap.
        let least = Layout.minSide + 2 * inset + Layout.gap
        var (placed, right, smaller) = (0, 0, 0)
        for x in stride(from: visible.minX, through: visible.maxX - 280, by: 37) {
            for y in stride(from: visible.minY, through: visible.maxY - 140, by: 53) {
                for width in [280.0, 520, 900] where x + width <= visible.maxX {
                    let panel = CGRect(x: x, y: y, width: width, height: 140)
                    let (roomRight, roomLeft) = (visible.maxX - panel.maxX, panel.minX - visible.minX)
                    guard let (image, frame) = Layout.frame(image: size, inset: inset, panel: panel, rowTop: panel.maxY - 6, visible: visible) else {
                        // None only where it fits on neither side.
                        #expect(roomRight < least && roomLeft < least, "\(panel)")
                        continue
                    }
                    placed += 1
                    #expect(!frame.intersects(panel), "over the panel: \(frame) \(panel)")
                    #expect(visible.contains(frame), "off the screen: \(frame)")
                    #expect(frame.size == CGSize(width: image.width + 2 * inset, height: image.height + 2 * inset))
                    // On the right wherever it fits there at 160 pt; on the left only where it doesn't.
                    if roomRight >= least {
                        #expect(frame.minX == panel.maxX + 8, "\(frame) by \(panel)")
                        right += 1
                    } else {
                        #expect(frame.maxX == panel.minX - 8, "\(frame) by \(panel)")
                    }
                    // Its size, or smaller to fit, its shape kept, 160 pt at least.
                    #expect(image == size || (max(image.width, image.height) >= Layout.minSide && abs(image.height - image.width * 200 / 360) <= 0.5),
                            "\(image)")
                    if image != size { smaller += 1 }
                    #expect(frame.maxY == panel.maxY - 6 || frame.minY == visible.minY)
                }
            }
        }
        #expect(placed > 100 && right > 50 && smaller > 10, "\(placed) placed, \(right) on the right, \(smaller) smaller")
    }

    // MARK: - Decoding

    /// A PNG of `width` × `height` pixels in `folder`.
    static func png(_ width: Int, _ height: Int, in folder: URL, name: String = UUID().uuidString) throws -> URL {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 0, bitsPerPixel: 0))
        for x in stride(from: 0, to: width, by: 7) { bitmap.setColor(.systemTeal, atX: x, y: x % height) }
        let url = folder.appendingPathComponent(name + ".png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("image-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Waits on the main actor (its queue running meanwhile) until `condition`, 5 s at most.
    @MainActor static func wait(until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
    }

    @MainActor @Test func theImageIsDecodedAtTheSizeDrawnOffTheMainThread() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try Self.png(1600, 800, in: folder)
        let images = ImagePreviewImages()
        let threads = Threads()
        images.decode = { key in
            threads.add(Thread.isMainThread)
            return ImagePreviewImages.thumbnail(key)
        }
        let key = ImagePreviewImages.Key(file: file, pixels: 720)
        let got = Handed()
        #expect(images.image(key) { got.images.append($0) } == nil, "not in yet: nothing at once, the key never waits")
        try await Self.wait { !got.images.isEmpty }
        let image = got.images.first
        #expect(got.images.count == 1 && image?.width == 720 && image?.height == 360,
                "decoded at the size drawn: \(image.map { "\($0.width) × \($0.height)" } ?? "none")")
        #expect(threads.onMain == [false], "off the main thread")
        #expect(images.image(key) { _ in Issue.record("in already: handed back at once") }?.width == 720, "kept while the panel shows")
        #expect(threads.onMain.count == 1, "not decoded again")
        // Never larger than the image itself.
        let smallFile = try Self.png(300, 200, in: folder)
        let small = ImagePreviewImages.thumbnail(ImagePreviewImages.Key(file: smallFile, pixels: 720))
        #expect(small?.width == 300 && small?.height == 200)
    }

    @MainActor @Test func aResultNoLongerWantedIsNeverShown() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (first, second) = (try Self.png(64, 32, in: folder), try Self.png(32, 64, in: folder))
        let images = ImagePreviewImages()
        let gate = DispatchSemaphore(value: 0)
        let threads = Threads()
        images.decode = { key in
            threads.add(Thread.isMainThread)
            if key.file == first { gate.wait() }  // the first still being decoded as the row changes
            return ImagePreviewImages.thumbnail(key)
        }
        let shown = Handed()
        _ = images.image(ImagePreviewImages.Key(file: first, pixels: 64)) { _ in shown.files.append(first) }
        try await Self.wait { threads.onMain.count == 1 }  // the first being decoded
        _ = images.image(ImagePreviewImages.Key(file: second, pixels: 64)) { _ in shown.files.append(second) }
        gate.signal()
        try await Self.wait { !shown.files.isEmpty }
        try await Task.sleep(for: .milliseconds(50))
        #expect(shown.files == [second], "only the row's image now: \(shown.files.map(\.lastPathComponent))")
        #expect(threads.onMain == [false, false], "each decoded once, off the main thread")

        // Pointed at again: what was decoded meanwhile, at once.
        let kept = images.image(ImagePreviewImages.Key(file: first, pixels: 64)) { _ in shown.files.append(first) }
        #expect(kept?.width == 64 && shown.files == [second])
    }

    @MainActor @Test func aFewAreKeptAndNoneOnceCleared() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let images = ImagePreviewImages()
        let files = try (0..<6).map { try Self.png(40 + $0, 30, in: folder) }
        for file in files {
            let done = Handed()
            _ = images.image(ImagePreviewImages.Key(file: file, pixels: 64)) { _ in done.files.append(file) }
            try await Self.wait { !done.files.isEmpty }
        }
        #expect(images.keys.map(\.file) == Array(files.suffix(ImagePreviewImages.kept)), "the last \(ImagePreviewImages.kept) used")

        // Cleared (the panel hidden) while one is being decoded: it's neither handed over nor kept.
        let gate = DispatchSemaphore(value: 0)
        images.decode = { key in
            gate.wait()
            return ImagePreviewImages.thumbnail(key)
        }
        let late = Handed()
        let lateFile = try Self.png(50, 50, in: folder)
        _ = images.image(ImagePreviewImages.Key(file: lateFile, pixels: 64)) { _ in late.files.append(lateFile) }
        images.clear()
        #expect(images.keys.isEmpty)
        gate.signal()
        try await Task.sleep(for: .milliseconds(100))
        #expect(late.files.isEmpty && images.keys.isEmpty, "a result from before the clear dropped")
    }

    // MARK: - The kept image a row stands for

    @Test func aRowsThumbnailFindsItsKeptImage() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardHistoryStore(url: folder.appendingPathComponent("clipboard-history.json"))
        let png = try Data(contentsOf: try Self.png(400, 200, in: folder, name: "copied"))
        store.record("a text", at: Date(timeIntervalSince1970: 1_800_000_000), limit: 20)
        #expect(store.recordImage(ClipboardImage(data: png, width: 400, height: 200), at: Date(timeIntervalSince1970: 1_800_000_100), limit: 20))
        let thumbnail = try #require(store.items.first?.image?.thumbnail)
        let found = try #require(store.image(thumbnail: thumbnail))
        #expect(found.image.width == 400 && found.image.height == 200)
        #expect(try Data(contentsOf: found.file) == png, "its PNG, not the thumbnail")
        #expect(store.image(thumbnail: folder.appendingPathComponent("elsewhere.png").path) == nil, "another file (a command's icon): none")
        store.clear()
        #expect(store.image(thumbnail: thumbnail) == nil, "no longer kept: none")
    }
}

/// What was handed over, on the main thread.
@MainActor private final class Handed {
    var images: [CGImage] = []
    var files: [URL] = []
}

/// Which threads decoded, told from any thread.
private final class Threads: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    var onMain: [Bool] { lock.withLock { values } }
    func add(_ main: Bool) { lock.withLock { values.append(main) } }
}
