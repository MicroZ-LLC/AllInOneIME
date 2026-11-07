import CoreGraphics
import Foundation
import ImageIO

// Clipboard history's larger picture of an image (0.7.0, owner): the input method's ImagePreview.swift shows it beside the
// candidate panel. Here is what it goes by, as AppKit's coordinates (points, y up): which row's image it shows, how large,
// where, and the image decoded for it (`ImagePreviewImages`).

/// Which row's image shows beside the panel, how large and where. One design for the mouse and the keys: the row under the
/// pointer when it is an image's, else the chosen row (↑↓) when it is, else none.
public enum ImagePreviewLayout {
    /// The longest side of the image, in points.
    public static let maxSide: CGFloat = 360
    /// The shortest its longer side is made to fit on the panel's right (`frame`): smaller, a screenshot's text can't be
    /// read; it goes on the panel's left then.
    public static let minSide: CGFloat = 160
    /// Between the panel and the preview.
    public static let gap: CGFloat = 8

    /// The panel as the preview goes by it: where it is, the row under the pointer and the chosen one, the visible frame of
    /// its screen and that screen's scale (pixels to a point).
    public struct Panel: Equatable, Sendable {
        public var frame: CGRect
        public var hovered: Int?
        public var chosen: Int?
        public var visible: CGRect
        public var scale: CGFloat

        public init(frame: CGRect, hovered: Int?, chosen: Int?, visible: CGRect, scale: CGFloat) {
            (self.frame, self.hovered, self.chosen, self.visible, self.scale) = (frame, hovered, chosen, visible, scale)
        }
    }

    /// An image row as the preview needs it: the image's size in pixels, and where the row's top is.
    public struct ImageRow: Equatable, Sendable {
        public var pixels: CGSize
        public var top: CGFloat

        public init(pixels: CGSize, top: CGFloat) {
            (self.pixels, self.top) = (pixels, top)
        }
    }

    /// What shows: the row's image, at `imageSize` (the size drawn, smaller than `size`'s where the room beside the panel
    /// is less), in a window at `frame` (the image with `inset` around it).
    public struct Shown: Equatable, Sendable {
        public var row: Int
        public var imageSize: CGSize
        public var frame: CGRect

        public init(row: Int, imageSize: CGSize, frame: CGRect) {
            (self.row, self.imageSize, self.frame) = (row, imageSize, frame)
        }
    }

    /// What shows beside `panel` (nil: the panel hidden, which clears it), an image row being what `image` tells of (nil
    /// for any other row); `inset` around the image. Nil: none (no image row pointed at or chosen, no room beside it).
    public static func shown(_ panel: Panel?, inset: CGFloat = 0, image: (Int) -> ImageRow?) -> Shown? {
        guard let panel, let index = row(hovered: panel.hovered, chosen: panel.chosen, isImage: { image($0) != nil }),
              let row = image(index) else { return nil }
        return frame(image: size(pixels: row.pixels, scale: panel.scale), inset: inset, panel: panel.frame, rowTop: row.top,
                     visible: panel.visible)
            .map { Shown(row: index, imageSize: $0.image, frame: $0.frame) }
    }

    /// The row whose image shows: the one under the pointer when it is an image's, else the chosen one when it is; nil:
    /// neither.
    public static func row(hovered: Int?, chosen: Int?, isImage: (Int) -> Bool) -> Int? {
        if let hovered, isImage(hovered) { return hovered }
        if let chosen, isImage(chosen) { return chosen }
        return nil
    }

    /// The image's size in points: its own on a screen of `scale` (a pixel of it to a pixel of the screen: never made
    /// larger), at most `maxSide` on its longer side, its shape kept (to the nearest point, a point at least). Zero for
    /// an image of no size.
    public static func size(pixels: CGSize, scale: CGFloat) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        let scale = max(scale, 1)
        let points = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        let factor = min(1, maxSide / max(points.width, points.height))
        return CGSize(width: max((points.width * factor).rounded(), 1), height: max((points.height * factor).rounded(), 1))
    }

    /// Where the preview of an image of `size` (`inset` around it in its window) goes beside `panel`, its top at `rowTop`
    /// (the row it shows), and the image's size there. On the panel's right, `gap` from it, every time it fits there:
    /// at `size`, or smaller, its shape kept, to fit the room up to `visible`'s right edge, as long as its longer side
    /// stays `minSide` at least. Only where even that doesn't fit (the panel at the screen's right edge), on the panel's
    /// left the same way. Moved up or down onto `visible`; never over the panel. Nil: no room on either side (or it is
    /// taller than `visible`).
    public static func frame(image size: CGSize, inset: CGFloat = 0, panel: CGRect, rowTop: CGFloat,
                             visible: CGRect) -> (image: CGSize, frame: CGRect)? {
        guard size.width > 0, size.height > 0, size.height + 2 * inset <= visible.height else { return nil }
        let right = panel.maxX + gap, left = panel.minX - gap
        let x: CGFloat, image: CGSize
        if right >= visible.minX, let fitted = fitted(size, width: visible.maxX - right - 2 * inset) {
            (x, image) = (right, fitted)
        } else if left <= visible.maxX, let fitted = fitted(size, width: left - visible.minX - 2 * inset) {
            (x, image) = (left - fitted.width - 2 * inset, fitted)
        } else {
            return nil
        }
        let outer = CGSize(width: image.width + 2 * inset, height: image.height + 2 * inset)
        let y = min(max(rowTop - outer.height, visible.minY), visible.maxY - outer.height)
        return (image, CGRect(x: x, y: y, width: outer.width, height: outer.height))
    }

    /// `size` in `width`: as it is where it fits, else narrowed to it, its shape kept (to whole points, the width rounded
    /// down), its longer side `minSide` at least. Nil: it doesn't fit.
    static func fitted(_ size: CGSize, width: CGFloat) -> CGSize? {
        if size.width <= width { return size }
        let narrowed = width.rounded(.down)
        guard narrowed > 0 else { return nil }
        let fitted = CGSize(width: narrowed, height: max((size.height * narrowed / size.width).rounded(), 1))
        return max(fitted.width, fitted.height) >= minSide ? fitted : nil
    }
}

/// The images the preview draws, decoded off the main thread at the size drawn (ImageIO's thumbnail of the file at that
/// many pixels, `decode`: a 6K screenshot is never decoded on the main thread, nor drawn from its full size), a few kept
/// (`kept`) while the panel shows; `clear` drops them as it hides. One is wanted at a time (the row pointed at or chosen):
/// a result for one no longer wanted is kept but never handed over. Main thread only, but for `decode`.
@MainActor
public final class ImagePreviewImages {
    /// An image file, to be decoded at `pixels` on its longer side at most.
    public struct Key: Hashable, Sendable {
        public var file: URL
        public var pixels: Int

        public init(file: URL, pixels: Int) {
            (self.file, self.pixels) = (file, pixels)
        }
    }

    /// The most kept at once.
    public static let kept = 4

    /// Decodes one (on `queue`, never the main thread): ImageIO's thumbnail by default (`thumbnail`); a test's own.
    public var decode: @Sendable (Key) -> CGImage? = { ImagePreviewImages.thumbnail($0) }
    private let queue = DispatchQueue(label: "com.aipinyin.inputmethod.image-preview", qos: .userInitiated)
    /// The images in, the one used last at the end.
    private var cache: [(key: Key, image: CGImage)] = []
    /// The one wanted, and what to hand it to once it is in.
    private var wanted: (key: Key, done: @MainActor (CGImage) -> Void)?
    /// The one wanted, told to the queue: one wanted no more by the time its turn comes isn't decoded.
    private let current = WantedKey()
    /// Those asked of the queue and not back yet.
    private var underway: Set<Key> = []
    /// Counts the clears: what was asked before one is dropped as it comes back.
    private var generation = 0

    public init() {}

    /// The keys of the images in, the one used last at the end.
    public var keys: [Key] { cache.map(\.key) }

    /// The image for `key` if it is in (it is the one wanted then); else nil, and it is decoded off the main thread and
    /// handed to `done` on the main thread once it is in, if it is still the one wanted then (no other asked for since,
    /// no `clear`).
    public func image(_ key: Key, done: @escaping @MainActor (CGImage) -> Void) -> CGImage? {
        current.key = key
        if let index = cache.firstIndex(where: { $0.key == key }) {
            let hit = cache.remove(at: index)
            cache.append(hit)
            wanted = nil
            return hit.image
        }
        wanted = (key, done)
        if !underway.contains(key) { ask(key) }
        return nil
    }

    /// None wanted any more, none kept (the panel hidden): what is under way is dropped as it comes back.
    public func clear() {
        generation += 1
        current.key = nil
        wanted = nil
        underway = []
        cache = []
    }

    /// `key` decoded on the queue, unless another is wanted by the time its turn comes.
    private func ask(_ key: Key) {
        underway.insert(key)
        let (decode, current, generation) = (decode, current, generation)
        queue.async { [weak self] in
            let skipped = current.key != key
            let decoded = Decoded(image: skipped ? nil : decode(key))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.came(decoded.image, for: key, skipped: skipped, generation: generation) }
            }
        }
    }

    private func came(_ image: CGImage?, for key: Key, skipped: Bool, generation: Int) {
        guard generation == self.generation else { return }
        underway.remove(key)
        // Left for another, and wanted again since: asked again.
        if skipped, wanted?.key == key { return ask(key) }
        guard let image else { return }
        cache.removeAll { $0.key == key }
        cache.append((key, image))
        if cache.count > Self.kept { cache.removeFirst(cache.count - Self.kept) }
        guard let wanted, wanted.key == key else { return }
        self.wanted = nil
        wanted.done(image)
    }

    /// `key`'s file as ImageIO's thumbnail of it, `key.pixels` on its longer side at most (never more than the image's
    /// own), turned as the file says, decoded now (not later, where it is drawn: on the main thread). Nil: not an image
    /// (any more).
    public nonisolated static func thumbnail(_ key: Key) -> CGImage? {
        guard key.pixels > 0,
              let source = CGImageSourceCreateWithURL(key.file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: key.pixels, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// The key wanted now, read and set from any thread.
private final class WantedKey: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ImagePreviewImages.Key?
    var key: ImagePreviewImages.Key? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// A decoded image handed back to the main thread (unchecked: a CGImage isn't changed once made).
private struct Decoded: @unchecked Sendable {
    let image: CGImage?
}
