import AllInOneIMECore
import AppKit
import CryptoKit
import Foundation
import ImageIO

// Clipboard history's recording and keeping on this Mac (the core's Session/ClipboardHistory.swift is the behaviour of
// the panel ⌃V shows): the text of each copy, or its image (0.6.8.2), after it is made, kept in files of the user's only. The input method's
// `ClipboardHistoryShared` runs it on a timer and gives the sessions what it keeps.

/// The list as read from its file off the main thread (`ClipboardHistoryStore.init`): set once on the store's `writes`
/// queue, read from any thread.
private final class LoadedList: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [ClipboardHistoryItem]?
    /// The items read; nil: not read yet.
    var items: [ClipboardHistoryItem]? { lock.withLock { value } }
    func set(_ items: [ClipboardHistoryItem]) { lock.withLock { value = items } }
}

/// The ids of images being made ready, read and changed from any thread: each counted as many times as it is being made
/// ready (the same image copied before and after Clear History), until each of those is added or discarded.
private final class PreparingIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    var ids: Set<String> { lock.withLock { Set(counts.keys) } }
    func insert(_ id: String) { lock.withLock { counts[id, default: 0] += 1 } }
    func remove(_ id: String) {
        lock.withLock {
            guard let count = counts[id] else { return }
            counts[id] = count > 1 ? count - 1 : nil
        }
    }
}

/// Clipboard history's copies, newest first, as kept on this Mac: one file (`url`) for the list, and beside it a folder
/// (`imagesURL`) with each kept image's PNG and its thumbnail (0.6.8.2), all readable by the user only (0600), in
/// Application Support, excluded from backups, written whole (the list atomically) with each change; an image no longer
/// in the list is deleted with it; `clear` deletes them all (Clear History, the history turned off). Read once, as it is
/// made, off the main thread (a long history's file never holds typing up): empty meanwhile (`isLoading`), a copy
/// recorded then kept above what is read, and no write leaves out what is still being read. Never synced, never sent
/// anywhere. Its files are written one change after another (`writes`), off the main thread, never waited for there.
// Unchecked: `prepare` runs off the main thread and touches only the images folder (by `url`, which never changes), never
// while `writes` deletes in it (`folderLock`); the list itself is read and changed on the thread that made the store only (the main thread), and written from a copy of
// it on `writes`; the list read from the file is handed over through `LoadedList`.
public final class ClipboardHistoryStore: @unchecked Sendable {
    /// ~/Library/Application Support/AllInOneIME/clipboard-history.json.
    public static var defaultURL: URL { CorePaths.dataDir.appendingPathComponent("clipboard-history.json") }
    /// The longest side of a thumbnail, in pixels (the panel draws it in a row's icon square).
    static let thumbnailSide = 96

    public let url: URL
    /// Counts the clears: an image made ready before one isn't added after it (`ClipboardRecorder.poll`).
    public private(set) var generation = 0
    /// Where the list's file is written and the images no longer in it deleted, in the order the changes were made, off
    /// the main thread: every store's (one made anew for the same file reads it after what the one before wrote).
    private static let writes = DispatchQueue(label: "com.allinoneime.inputmethod.clipboard-history", qos: .userInitiated)
    private var writes: DispatchQueue { Self.writes }
    /// The ids of the images being made ready (`prepare` until `add` or `discard`): their files are never removed meanwhile.
    private let preparing = PreparingIDs()
    /// Held while an image's files are written into the images folder (`prepare`, off the main thread) and while the
    /// folder's unlisted files are deleted (`removeUnlisted`, on `writes`): a deletion never takes files written after it
    /// looked at what is being made ready, nor the folder with them. Never taken on the main thread but by the tests' and
    /// the self-test's `recordImage`.
    private let folderLock = NSLock()
    /// The kept images' folder, beside the list and named after it (clipboard-history-images for the user's): two stores
    /// never share one.
    public var imagesURL: URL {
        url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-images", isDirectory: true)
    }
    /// The copies, newest first: empty until the file is read (`isLoading`), a copy recorded meanwhile above what it has.
    public var items: [ClipboardHistoryItem] {
        finishLoading()
        return current
    }
    private var current: [ClipboardHistoryItem] = []
    /// The list read from the file, once it is (on `writes`); and whether it is yet to be merged into `current`.
    private let loaded = LoadedList()
    private var loadPending = true
    /// The limit a change asked for while the file was being read: what is read is kept to it too.
    private var limitWhileLoading: Int?
    /// Who waits for the file to be read (`waitForLoad`, main thread).
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    /// The images a list's file moved aside has (`keptAside`): never deleted but by `clear` (read and changed on `writes`
    /// only, after `init`).
    private var keptAsideIDs: Set<String> = []
    /// Whether the list's file is one it couldn't read in full, not moved aside yet (`archive`): never written over, and
    /// no image deleted, meanwhile (on `writes` only, after `init`).
    private var unarchived = false

    private struct File: Codable {
        struct Item: Codable {
            struct Image: Codable {
                var id: String
                var width: Int
                var height: Int
                var bytes: Int
            }

            var text: String
            var image: Image?
            var copiedAt: Date
        }

        var items: [Item]
    }

    /// The list's file as read: each item on its own (nil: one that can't be read, skipped).
    private struct ReadFile: Decodable {
        struct Entry: Decodable {
            var item: File.Item?
            init(from decoder: Decoder) throws { item = try? File.Item(from: decoder) }
        }

        var items: [Entry]
    }

    /// Moves a file (`FileManager.moveItem`; a test's may fail).
    private let moveFile: (URL, URL) throws -> Void
    /// Reads the list's file (`Data(contentsOf:)`; a test's may hold it up), on `writes`.
    private let readFile: @Sendable (URL) -> Data?

    /// The file is read on `writes`, before any write; made on the main thread, what it read is in `items` as soon as it
    /// is (made on another, at its next use there).
    public init(url: URL = ClipboardHistoryStore.defaultURL,
                moveFile: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
                readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) }) {
        self.url = url
        self.moveFile = moveFile
        self.readFile = readFile
        let onMain = Thread.isMainThread
        writes.async { [self] in
            load()
            if onMain { DispatchQueue.main.async { self.finishLoading() } }
        }
    }

    /// The list's file read (on `writes`): the items it can (an image whose file is gone, deleted by hand, is gone from
    /// the list too); a file it couldn't read in full moved aside and those items written in its place; the images files
    /// moved aside have, found.
    private func load() {
        let (read, clean) = read()
        let items: [ClipboardHistoryItem] = read.compactMap { item in
            guard let image = item.image else { return ClipboardHistoryItem(text: item.text, copiedAt: item.copiedAt) }
            guard FileManager.default.fileExists(atPath: imageURL(image.id).path) else { return nil }
            return ClipboardHistoryItem(image: kept(image.id, width: image.width, height: image.height, bytes: image.bytes),
                                        copiedAt: item.copiedAt)
        }
        unarchived = !clean
        if !clean, archive() { save(items) }
        keptAsideIDs = keptAside()
        loaded.set(items)
    }

    /// Whether the file is still being read (`items` has only what was recorded since).
    public var isLoading: Bool {
        finishLoading()
        return loadPending
    }

    /// Once the file is read and its items are in `items` (on the main thread, wherever the store was made).
    @MainActor
    public func waitForLoad() async {
        while isLoading {
            await withCheckedContinuation { waiter in
                loadWaiters.append(waiter)
                writes.async { DispatchQueue.main.async { self.finishLoading() } }
            }
        }
    }

    /// What the file had, once read, in `items`: below what was recorded meanwhile (the same copy once), to the limit
    /// asked for meanwhile.
    private func finishLoading() {
        if loadPending, let read = loaded.items {
            loadPending = false
            let all = Self.merge(current, read, limit: nil)
            current = Self.merge(current, read, limit: limitWhileLoading)
            // A lower limit set while it was read (`trim`) drops the oldest from the file now; nothing changed, nothing written.
            if current.count < all.count, let limit = limitWhileLoading { keep(limit) }
        }
        guard !loadPending, !loadWaiters.isEmpty else { return }
        let waiters = loadWaiters
        loadWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// `newer` then each of `older` not among them, `limit` at most (nil: all).
    private static func merge(_ newer: [ClipboardHistoryItem], _ older: [ClipboardHistoryItem], limit: Int?) -> [ClipboardHistoryItem] {
        var out = newer
        for item in older where !out.contains(where: { same($0, item) }) { out.append(item) }
        return limit.map { Array(out.prefix(max($0, 1))) } ?? out
    }

    private static func same(_ a: ClipboardHistoryItem, _ b: ClipboardHistoryItem) -> Bool {
        if let one = a.image, let other = b.image { return one.id == other.id }
        return a.image == nil && b.image == nil && a.text == b.text
    }

    /// The whole list to write for `items` (on `writes`): with what the file had where it was still being read as they
    /// were taken (`loading`), so no write leaves it out.
    private func whole(_ items: [ClipboardHistoryItem], loading: Bool, limit: Int?) -> [ClipboardHistoryItem] {
        loading ? Self.merge(items, loaded.items ?? [], limit: limit) : items
    }

    /// The items of the list's file it can read, and whether it read them all (no file: all). Where it didn't, the file is
    /// moved aside as it was (`archive`) before anything is written, never written over: the history is what it can read,
    /// and the images it kept stay until Clear History (`keptAside`).
    private func read() -> (items: [File.Item], clean: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], true) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let file = readFile(url).flatMap { try? decoder.decode(ReadFile.self, from: $0) }
        let items = file?.items.compactMap(\.item) ?? []
        guard items.count != file?.items.count else { return (items, true) }
        CoreLog(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")
            .error("clipboard history: \(file.map { "\($0.items.count - items.count) items" } ?? "the file") unreadable")
        return (items, false)
    }

    /// The list's file it couldn't read in full moved aside (`asidePrefix`), if it wasn't yet (on `writes`): false while it
    /// can't be, and then nothing may write the list's file nor delete an image. Tried again at each write.
    private func archive() -> Bool {
        guard unarchived else { return true }
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("\(Self.asidePrefix(url))\(Int(Date().timeIntervalSince1970 * 1000)).json")
        do { try moveFile(url, aside) } catch {
            CoreLog(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")
                .error("clipboard history: could not move an unreadable file aside: \(String(describing: type(of: error)))")
            return false
        }
        unarchived = false
        keptAsideIDs = keptAside()
        return true
    }

    /// The beginning of a list's file moved aside's name (clipboard-history-unreadable-<ms>.json for the user's).
    private static func asidePrefix(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent + "-unreadable-" }

    /// The list's files moved aside, unreadable (`read`).
    private var asideURLs: [URL] {
        let folder = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(Self.asidePrefix(url)) }.map { folder.appendingPathComponent($0) }
    }

    /// The images a list's file moved aside has (every image id in it, read as text), never deleted but by Clear History;
    /// every image in the folder where one of them can't be read, or isn't JSON at all (cut short: it may have had any).
    private func keptAside() -> Set<String> {
        var ids: Set<String> = []
        for file in asideURLs {
            guard let data = try? Data(contentsOf: file), (try? JSONSerialization.jsonObject(with: data)) != nil else {
                return Set(Self.ids(in: imagesURL))
            }
            ids.formUnion(String(decoding: data, as: UTF8.self).matches(of: /[0-9a-f]{64}/).map { String($0.output) })
        }
        return ids
    }

    /// `text` copied at `date`: first, once (the same text further down moves up), `limit` kept at most: in the list at
    /// once, its file written off the main thread after (`waitForWrites` waits for it), as every change's is now
    /// (`savingLater`, from when only ⌃V's look left it for later, changes nothing). False: it was the newest already, and
    /// nothing changed.
    @discardableResult
    public func record(_ text: String, at date: Date, limit: Int, savingLater: Bool = true) -> Bool {
        finishLoading()
        guard current.first.map({ $0.image != nil || $0.text != text }) ?? true else { return false }
        current.removeAll { $0.image == nil && $0.text == text }
        current.insert(ClipboardHistoryItem(text: text, copiedAt: date), at: 0)
        keep(limit)
        return true
    }

    /// Once what was to be written is (every change's, off the main thread): tests, the self-test.
    public func waitForWrites() {
        writes.sync {}
    }

    /// What every store was asked to write or delete by now, done before the input method ends (Clear History just
    /// before an update or a logout), `seconds` at most: whether it all was. Never on the main thread (the input method's
    /// termination's own queue, or after the run loop is done).
    @discardableResult
    public static func drain(within seconds: TimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        writes.async { done.signal() }
        return done.wait(timeout: .now() + seconds) == .success
    }

    /// An image made ready to keep (`prepare`): its id (its PNG's SHA-256), size and PNG's length, its files written.
    public struct ReadyImage: Sendable {
        public var id: String
        public var width: Int
        public var height: Int
        public var bytes: Int
    }

    /// What preparing an image came to.
    public enum Prepared: Sendable {
        case ready(ReadyImage)
        /// Its PNG is over `ClipboardHistoryImage.maxBytes` (or it couldn't be read as an image).
        case tooLarge
        /// Its files couldn't be written.
        case notSaved
    }

    /// `image` made ready to keep, off the main thread: its PNG (≤ `ClipboardHistoryImage.maxBytes`), its id, its thumbnail,
    /// both written in the images folder (0600; the folder 0700, excluded from backups; the PNG kept as it is if there).
    /// Touches nothing of the list (`add` does, on the main thread).
    public func prepare(_ image: ClipboardImage) -> Prepared {
        guard let png = image.pngData(), png.count <= ClipboardHistoryImage.maxBytes else { return .tooLarge }
        let id = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let thumbnail = Self.thumbnail(png)
        // Being made ready before the folder is looked at again (`removeUnlisted`): one deleting it now is done first.
        folderLock.lock()
        defer { folderLock.unlock() }
        preparing.insert(id)
        do {
            try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            excludeFromBackup(imagesURL)
            let file = imageURL(id)
            if !FileManager.default.fileExists(atPath: file.path) { try Platform.current.files.writePrivate(png, to: file) }
            if let thumbnail { try Platform.current.files.writePrivate(thumbnail, to: thumbnailURL(id)) }
        } catch {
            CoreLog(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")
                .error("clipboard history: could not save an image: \(String(describing: type(of: error)))")
            preparing.remove(id)
            return .notSaved
        }
        return .ready(ReadyImage(id: id, width: image.width, height: image.height, bytes: png.count))
    }

    /// A ready image (`prepare`) copied at `date` in the list: where its date puts it (a text copied while it was made
    /// ready stays above it), once (the same image further down moves up), `limit` kept at most. False: it was the newest
    /// already, and nothing changed.
    @discardableResult
    public func add(_ image: ReadyImage, at date: Date, limit: Int) -> Bool {
        finishLoading()
        guard current.first?.image?.id != image.id else {
            preparing.remove(image.id)
            return false
        }
        current.removeAll { $0.image?.id == image.id }
        let kept = kept(image.id, width: image.width, height: image.height, bytes: image.bytes)
        let place = current.firstIndex { $0.copiedAt < date } ?? current.count
        current.insert(ClipboardHistoryItem(image: kept, copiedAt: date), at: place)
        // Being made ready until the list with it is written: a write queued before it, of the list before it (while the
        // file is read, all of them are), keeps its files.
        keep(limit, releasing: image.id)
        return true
    }

    /// A ready image not added after all (the history cleared or turned off while it was made ready): its files deleted.
    public func discard(_ image: ReadyImage) {
        preparing.remove(image.id)
        removeUnlisted()
    }

    /// An image copied at `date`, prepared and added at once (tests, the self-test). False: not kept.
    @discardableResult
    public func recordImage(_ image: ClipboardImage, at date: Date, limit: Int) -> Bool {
        guard case let .ready(ready) = prepare(image) else { return false }
        return add(ready, at: date, limit: limit)
    }

    /// A kept image's PNG; nil: not kept (any more).
    public func imageData(_ id: String) -> Data? {
        guard items.contains(where: { $0.image?.id == id }) else { return nil }
        return try? Data(contentsOf: imageURL(id))
    }

    /// The kept image whose thumbnail is the file at `path` (a panel row's icon: `ClipboardHistoryImage.thumbnail`), and its
    /// PNG's file: what the panel's larger picture of it shows (the input method's ImagePreview). Nil: none kept (any more).
    public func image(thumbnail path: String) -> (image: ClipboardHistoryImage, file: URL)? {
        guard let image = items.lazy.compactMap(\.image).first(where: { $0.thumbnail == path }) else { return nil }
        return (image, imageURL(image.id))
    }

    /// The oldest dropped beyond `limit` (a lower one set), at once.
    public func trim(to limit: Int) {
        // While the file is read: applied as it is merged (`finishLoading`), written only if that drops something.
        if isLoading {
            limitWhileLoading = limit
            return
        }
        guard current.count > max(limit, 1) else { return }
        keep(limit)
    }

    /// Everything forgotten: the list at once, its file and the images deleted off the main thread after what was to be
    /// written before (`waitForWrites` waits for it).
    public func clear() {
        generation += 1
        current = []
        // What is being read is forgotten too; the files deleted after it is (never waited for).
        loadPending = false
        finishLoading()
        writes.async { [self] in
            (keptAsideIDs, unarchived) = ([], false)
            for file in [url] + asideURLs { try? FileManager.default.removeItem(at: file) }
            // Every image but one being made ready meanwhile (copied after it: kept; before it: `discard`ed), and the
            // folder with them.
            removeUnlisted(listing: [])
        }
    }

    /// `limit` kept at most, saved, images no longer in the list deleted: off the main thread, after what was to be written
    /// before (a snapshot of the list now). `releasing`: an image being made ready (`preparing`), until this write.
    private func keep(_ limit: Int, releasing id: String? = nil) {
        current = Array(current.prefix(max(limit, 1)))
        let loading = isLoading
        if loading { limitWhileLoading = limit }
        guard !current.isEmpty || loading else {
            if let id { preparing.remove(id) }
            return clear()
        }
        let items = current
        writes.async { [self] in
            let whole = whole(items, loading: loading, limit: limit)
            save(whole)
            removeUnlisted(listing: whole)
            if let id { preparing.remove(id) }
        }
    }

    func imageURL(_ id: String) -> URL { imagesURL.appendingPathComponent("\(id).png") }
    func thumbnailURL(_ id: String) -> URL { imagesURL.appendingPathComponent("\(id)-thumb.png") }

    private func kept(_ id: String, width: Int, height: Int, bytes: Int) -> ClipboardHistoryImage {
        let thumbnail = thumbnailURL(id)
        return ClipboardHistoryImage(id: id, width: width, height: height, bytes: bytes,
                                     thumbnail: FileManager.default.fileExists(atPath: thumbnail.path) ? thumbnail.path : nil)
    }

    /// A PNG at most `thumbnailSide` pixels on its longer side (ImageIO's thumbnail: the image decoded at that size only).
    static func thumbnail(_ png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: thumbnailSide]
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: small).representation(using: .png, properties: [:])
    }

    /// Image files whose image is no longer in the list deleted.
    private func removeUnlisted() {
        let (items, loading, limit) = (current, isLoading, limitWhileLoading)
        writes.async { [self] in removeUnlisted(listing: whole(items, loading: loading, limit: limit)) }
    }

    /// Image files whose image isn't among `items`, nor being made ready, deleted: while no image's files are being
    /// written (`folderLock`), so one made ready meanwhile is either listed as being made ready, or written after.
    private func removeUnlisted(listing items: [ClipboardHistoryItem]) {
        guard archive() else { return }
        folderLock.lock()
        defer { folderLock.unlock() }
        let listed = Set(items.compactMap { $0.image?.id }).union(preparing.ids).union(keptAsideIDs)
        for (name, id) in Self.files(in: imagesURL) where !listed.contains(id) {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
        }
        if listed.isEmpty { try? FileManager.default.removeItem(at: imagesURL) }
    }

    /// The files in an images folder, each with its image's id; not a hidden one: an image's file being written there
    /// (`prepare`, off the main thread), staged under a hidden name until it is.
    private static func files(in folder: URL) -> [(name: String, id: String)] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.map { name in
            (name, name.replacingOccurrences(of: "-thumb.png", with: "").replacingOccurrences(of: ".png", with: ""))
        }
    }

    private static func ids(in folder: URL) -> [String] { files(in: folder).map(\.id) }

    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// `items` written as the list's file (on `writes`).
    private func save(_ items: [ClipboardHistoryItem]) {
        guard archive() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let file = File(items: items.map { item in
            File.Item(text: item.text, image: item.image.map { File.Item.Image(id: $0.id, width: $0.width, height: $0.height, bytes: $0.bytes) },
                      copiedAt: item.copiedAt)
        })
        guard let data = try? encoder.encode(file) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Platform.current.files.writePrivate(data, to: url)
            // Time Machine and other backups leave it out (a new file each write: marked each time).
            excludeFromBackup(url)
        } catch {
            CoreLog(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")
                .error("clipboard history: could not save it: \(String(describing: type(of: error)))")
        }
    }
}
