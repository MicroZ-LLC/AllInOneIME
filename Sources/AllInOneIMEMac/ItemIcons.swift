import AppKit
import Foundation

/// The own icons of the apps, folders and files the panel's rows open (`IconToken.Glyph.item`), as Finder shows them
/// (`finderIcon`), drawn once at the rows' size and kept in memory by path. Loaded only off the main thread: with the
/// results, where they are found (`prefetch`, `load`: the app index, what `@open` opened before, a folder's listing,
/// Spotlight's files), else for a row shown before its icon was in (`icon(requesting:)`), which has `@open`'s symbol until
/// then, once, and its own icon from then on, never back (`onLoaded` tells the panel to draw it). A path with no icon (one
/// on a server, never asked: `Mounts`) is kept as none: its row keeps the symbol. Past `limit` the least recently used go.
public final class ItemIcons: @unchecked Sendable {
    public static let shared = ItemIcons()

    /// The rows' icon size, in points (`CandidateView.Metrics.iconSize`); what is kept has two pixels a point (Retina).
    public static let size: CGFloat = 20
    static let scale: CGFloat = 2

    /// How many icons are kept at most.
    public let limit: Int
    private let loader: @Sendable (String) -> NSImage?
    /// Where `onLoaded` is told: the main queue.
    private let tells: DispatchQueue
    /// Where a row's icon is read (`icon(requesting:)`), and where what is kept is read ahead (`prefetch`), apart: a
    /// folder's listing read ahead never holds up a row's icon, nor results waiting for theirs (`load`).
    private let queue = DispatchQueue(label: "com.allinoneime.inputmethod.item-icons", qos: .userInitiated)
    private let ahead = DispatchQueue(label: "com.allinoneime.inputmethod.item-icons.ahead", qos: .utility)
    private let lock = NSLock()
    /// Each path's icon (nil: it has none) and when it was last used (`clock`).
    private var kept: [String: (image: NSImage?, used: UInt64)] = [:]
    private var clock: UInt64 = 0
    /// The paths rows asked for that are being loaded.
    private var asked: Set<String> = []
    private var loaded: (@Sendable (Set<String>) -> Void)?

    /// Told, on `tells` (the main queue), the paths whose icons came in after a row asked for them (`icon(requesting:)`):
    /// a panel showing one draws it again.
    public var onLoaded: (@Sendable (Set<String>) -> Void)? {
        get { lock.withLock { loaded } }
        set { lock.withLock { loaded = newValue } }
    }

    /// `loader` reads a path's icon (Finder's, `finderIcon`; a stand-in in the tests).
    public init(limit: Int = 512, loader: @escaping @Sendable (String) -> NSImage? = { ItemIcons.finderIcon($0) },
                tells: DispatchQueue = .main) {
        self.limit = max(limit, 1)
        self.loader = loader
        self.tells = tells
    }

    /// The icon kept for `path` (nil: none, or not yet), from memory: nothing is read.
    public func icon(_ path: String) -> NSImage? {
        lock.withLock { use(path)?.image }
    }

    /// `icon`; where nothing is kept for `path` yet, its icon is loaded off the main thread and `onLoaded` told once it is
    /// in. A path kept as having none isn't asked again.
    public func icon(requesting path: String) -> NSImage? {
        let (image, ask) = lock.withLock { () -> (NSImage?, Bool) in
            if let entry = use(path) { return (entry.image, false) }
            return (nil, asked.insert(path).inserted)
        }
        guard ask else { return image }
        queue.async { [self] in
            if lock.withLock({ kept[path] == nil }) { keep(path, loader(path)) }
            let told = lock.withLock { () -> (@Sendable (Set<String>) -> Void)? in
                asked.remove(path)
                return loaded
            }
            if let told { tells.async { told([path]) } }
        }
        return nil
    }

    /// The icons of `paths` not kept yet loaded off the caller's thread, soon, as they are found: at most half of `limit`,
    /// the first, so that what rows asked for stays.
    public func prefetch(_ paths: [String]) {
        let wanted = Array(paths.prefix(limit / 2))
        guard !wanted.isEmpty else { return }
        ahead.async { [self] in preload(wanted) }
    }

    /// The icons of `paths` not kept yet loaded off the main thread, done when they are in (results found off it, before
    /// they are shown).
    public func load(_ paths: [String]) async {
        guard lock.withLock({ paths.contains { kept[$0] == nil } }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                preload(paths)
                continuation.resume()
            }
        }
    }

    /// The icons of `paths` not kept yet loaded now, on the caller's thread: never the main thread (results found off it).
    public func preload(_ paths: [String]) {
        assert(!Thread.isMainThread, "item icons are read off the main thread")
        for path in paths where lock.withLock({ kept[path] == nil }) {
            keep(path, loader(path))
        }
    }

    /// What is kept for `path`, now used last (under `lock`).
    private func use(_ path: String) -> (image: NSImage?, used: UInt64)? {
        guard kept[path] != nil else { return nil }
        clock += 1
        kept[path]?.used = clock
        return kept[path]
    }

    /// `image` kept for `path`; past `limit`, the least recently used go.
    private func keep(_ path: String, _ image: NSImage?) {
        lock.withLock {
            clock += 1
            kept[path] = (image, clock)
            guard kept.count > limit else { return }
            for (old, _) in kept.sorted(by: { $0.value.used < $1.value.used }).prefix(kept.count - limit) { kept[old] = nil }
        }
    }

    /// The icon Finder shows for `path` (`NSWorkspace.icon(forFile:)`), drawn at `size` points, two pixels a point; nil
    /// for what isn't there, and for what is on a server or kept in the cloud (never asked: `Mounts.isLocal`). Off the
    /// main thread only.
    public static func finderIcon(_ path: String, size: CGFloat = size) -> NSImage? {
        guard Mounts().isLocal(path), FileManager.default.fileExists(atPath: path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        let pixels = Int(size * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: size, height: size)) }
    }
}
