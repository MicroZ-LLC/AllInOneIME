import AllInOneIMECore
import AppKit
import CryptoKit
import Foundation
import ImageIO

// Clipboard history's recording and keeping on this Mac (the core's Session/ClipboardHistory.swift is the behaviour of
// the panel ⌃V shows): the text of each copy, or its image (0.6.8.2), after it is made, kept in files of the user's only. The input method's
// `ClipboardHistoryShared` runs it on a timer and gives the sessions what it keeps.

/// Whether this app may read the clipboard now without the system asking the user (macOS 15.4:
/// `NSPasteboard.accessBehavior`, Privacy & Security → Paste from Other Apps), as told without asking.
public enum ClipboardAccess: String, Equatable, Sendable {
    /// Allow (or a macOS before 15.4, which never asks).
    case allowed
    /// Ask: each read asks first.
    case asks
    /// Never asked yet: the app isn't in Paste from Other Apps' list until a read has asked once.
    case notListed
    /// Deny.
    case denied
}

/// What clipboard history reads of a pasteboard (the general one, `SystemClipboard`; a test's fake): the change count
/// and `access`, which never ask the user; the types on it and its text, read only once `access` is `.allowed`.
public protocol ClipboardSource: AnyObject {
    var changeCount: Int { get }
    var access: ClipboardAccess { get }
    var types: [String] { get }
    /// Its plain text (rich text's too); nil: no text (an image, a colour), or none read (`SystemClipboard`: a copy made
    /// on an iPhone or another Mac).
    func text() -> String?
    /// The image on it, as PNG, where an image is what was copied (its first type an image's: a screenshot, Copy Image);
    /// nil otherwise (0.6.8.2).
    func image() -> ClipboardImage?
}

/// The ids of images being made ready, read and changed from any thread.
private final class PreparingIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var set: Set<String> = []
    var ids: Set<String> { lock.withLock { set } }
    func insert(_ id: String) { _ = lock.withLock { set.insert(id) } }
    func remove(_ id: String) { _ = lock.withLock { set.remove(id) } }
}

/// An image being made ready off the main thread (`ClipboardRecorder.imageWork`): what that came to, told from any thread,
/// and its adding to the store, on the main thread once: at its turn there, or earlier, as ⌃V's look waits for it.
// Unchecked: `result` is behind the lock; `add` and `outcome` are used on the main thread only.
private final class PreparingImage: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var value: ClipboardHistoryStore.Prepared?
    /// Adds it to the store; nil once it has.
    var add: ((ClipboardHistoryStore.Prepared) -> ClipboardRecorder.Outcome)?
    /// What adding it came to (`imageQueued` until it has).
    private(set) var outcome = ClipboardRecorder.Outcome.imageQueued

    /// What making it ready came to; nil: not yet.
    var result: ClipboardHistoryStore.Prepared? { lock.withLock { value } }

    /// Made ready (on any thread): `prepared` kept, and handed on.
    func prepared(_ prepared: ClipboardHistoryStore.Prepared) -> ClipboardHistoryStore.Prepared {
        lock.withLock { value = prepared }
        ready.signal()
        return prepared
    }

    /// Whether it is ready, waiting `seconds` at most for it.
    func wait(_ seconds: TimeInterval) -> Bool {
        result != nil || ready.wait(timeout: .now() + seconds) == .success
    }

    /// Added to the store, once (main thread).
    func added(_ prepared: ClipboardHistoryStore.Prepared) {
        guard let add else { return }
        self.add = nil
        outcome = add(prepared)
    }
}

/// A value handed back to the main thread it came from (unchecked: it is only ever used there).
private struct MainThreadOnly<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Records each copy into `store` (`poll`, on a timer): an image where one was copied (`ClipboardSource.image`; one over
/// `ClipboardHistoryImage.maxBytes` isn't), else the text copied, as `ClipboardSource.text` reads it, unless
/// reading it would ask the user (`access` not `.allowed`: nothing is read then, only the change count and the access,
/// which never ask), it was copied during secure input (a password field had the keys when it changed, or at the look
/// before), it was copied in a password manager (`PasswordManagers`: its app frontmost when it changed, or at the look
/// before: Keychain Access's Copy Password marks nothing), it is marked never to be kept (`neverRecorded`: password managers and clipboard tools mark theirs, as
/// TerminalPaste marks its own writes), it is neither an image nor text (a file, a colour) or was copied on an iPhone or
/// another Mac (Universal Clipboard: never read, `SystemClipboard.remoteType`), it is blank, or it is longer than
/// `ClipboardHistoryItem.maxLength`; nor the clipboard TerminalPaste puts back after its paste (`putBack`). Used on one
/// thread (the input method's main one).
public final class ClipboardRecorder {
    /// Why a change wasn't recorded.
    public enum Outcome: Equatable, Sendable {
        case unchanged, recorded
        case notAllowed, secureInput, marked, notText, blank, tooLong
        /// Copied in a password manager (`PasswordManagers`): its app was the frontmost when it changed, or at the look before.
        case passwordManager
        /// An image being made ready off the main thread (`imageWork`): recorded once it is.
        case imageQueued
        /// It couldn't be written (a full disk): nothing kept.
        case notSaved
        /// The newest kept already (a copy of it again).
        case same
    }

    /// Never recorded (nspasteboard.org's markers, which password managers and clipboard tools set, and the older ones of
    /// 1Password, KeeWeb and others, as `@reply`'s ⌃V leaves them alone too), nor a file (Finder's copy has its name as
    /// text).
    public static let neverRecorded: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type",
        "net.antelle.keeweb", "public.file-url",
    ]

    public let store: ClipboardHistoryStore
    let source: ClipboardSource
    /// Where images are made ready, one at a time (a later copy never overtakes an earlier one); as soon as the system can,
    /// as ⌃V's look may be waiting for one (`quickImageWait`: a wait on the main thread lends the queue no priority).
    static let imageQueue = DispatchQueue(label: "com.allinoneime.inputmethod.clipboard-images", qos: .userInitiated)
    /// Runs an image's preparation (its PNG, id, thumbnail and files: `ClipboardHistoryStore.prepare`) and hands its result
    /// to the second closure on the main thread: off the main thread by default, so a large copy never holds typing up;
    /// a test's runs it at once.
    public var imageWork: (@escaping @Sendable () -> ClipboardHistoryStore.Prepared, @escaping (ClipboardHistoryStore.Prepared) -> Void) -> Void = { prepare, done in
        // `done` runs on the main thread only, where the recorder is used; one image after another, in the order copied.
        let main = MainThreadOnly(done)
        ClipboardRecorder.imageQueue.async {
            let prepared = prepare()
            DispatchQueue.main.async { main.value(prepared) }
        }
    }
    /// The longest ⌃V's look waits for an image to be made ready (`poll(limit:quick:)`): a screenshot's takes 15–35 ms on
    /// an M4 (2560 × 1664 pixels; a 6K one's 120 ms); one taking longer is kept as it is ready, after the panel.
    public static let quickImageWait: TimeInterval = 0.15
    /// The images being made ready, in the order copied, until each is added on the main thread.
    private var preparing: [PreparingImage] = []
    let secureInput: () -> Bool
    /// The frontmost app's bundle id (nil: none known).
    let frontmostApp: () -> String?
    let now: () -> Date
    /// The change count last looked at (nil: none yet: what's on the clipboard is recorded at the first look, at launch),
    /// and whether secure input was on then.
    private var seen: Int?
    private var wasSecure = false
    /// Whether a password manager was the frontmost app at the last look.
    private var wasInPasswordManager = false
    /// The access as told at the last change.
    public private(set) var access: ClipboardAccess
    /// The change count of the copy the store has as its newest (recorded, or the newest already); nil: none since launch.
    private var newestSeen: Int?

    /// Whether what's on the clipboard now is the store's newest copy, unchanged since (the change count only: never asks).
    public var clipboardIsNewest: Bool { newestSeen != nil && newestSeen == source.changeCount }

    public init(source: ClipboardSource, store: ClipboardHistoryStore, secureInput: @escaping () -> Bool,
                frontmostApp: @escaping () -> String?, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.store = store
        self.secureInput = secureInput
        self.frontmostApp = frontmostApp
        self.now = now
        access = source.access
    }

    /// A look at the clipboard: a change since the last recorded (`limit`: how many are kept). `quick`: the look of a
    /// panel about to show (⌃V), which waits for it: a text copied is kept in memory at once and its file written off the
    /// main thread (`ClipboardHistoryStore.record(_:at:limit:savingLater:)`); an image copied just before, made ready off
    /// the main thread as any is, is waited for (`quickImageWait` at most) and kept at once, as is one a look before
    /// found, still being made ready: the panel has its kept row (its thumbnail, its preview), not the image on the
    /// clipboard. ⌃V is the user asking for the history, the clipboard's image with it.
    @discardableResult
    public func poll(limit: Int, quick: Bool = false) -> Outcome {
        let secure = secureInput()
        let inPasswordManager = PasswordManagers.contains(frontmostApp())
        defer { (wasSecure, wasInPasswordManager) = (secure, inPasswordManager) }
        let count = source.changeCount
        guard count != seen else {
            if quick { waitForImages() }
            return .unchanged
        }
        seen = count
        access = source.access
        guard access == .allowed else { return .notAllowed }
        guard !secure, !wasSecure else { return .secureInput }
        guard !inPasswordManager, !wasInPasswordManager else { return .passwordManager }
        guard Set(source.types).isDisjoint(with: Self.neverRecorded) else { return .marked }
        if let image = source.image() {
            let (store, date, generation) = (store, now(), store.generation)
            let preparing = PreparingImage()
            preparing.add = { [weak self] prepared in
                guard let self else { return .imageQueued }
                self.preparing.removeAll { $0 === preparing }
                // Cleared or turned off meanwhile: not kept.
                if case let .ready(ready) = prepared, store.generation != generation {
                    store.discard(ready)
                    return .imageQueued
                }
                switch prepared {
                case let .ready(ready):
                    // The newest still on the clipboard only if nothing was copied since.
                    if source.changeCount == count { newestSeen = count }
                    return store.add(ready, at: date, limit: limit) ? .recorded : .same
                case .tooLarge:
                    return .tooLong
                case .notSaved:
                    return .notSaved
                }
            }
            self.preparing.append(preparing)
            imageWork({ preparing.prepared(store.prepare(image)) }) { preparing.added($0) }
            if quick { waitForImages() }
            return preparing.outcome
        }
        guard let text = source.text() else { return .notText }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .blank }
        guard text.utf16.count <= ClipboardHistoryItem.maxLength * 4, text.count <= ClipboardHistoryItem.maxLength else { return .tooLong }
        newestSeen = count
        return store.record(text, at: now(), limit: limit, savingLater: quick) ? .recorded : .same
    }

    /// The images being made ready waited for, `quickImageWait` at most (the last of them: they are made ready one after
    /// another), and those ready by then added now, in the order copied, not at their turn on the main thread.
    private func waitForImages() {
        guard let last = preparing.last, last.wait(Self.quickImageWait) else { return }
        for image in preparing {
            if let prepared = image.result { image.added(prepared) }
        }
    }

    /// What's on the clipboard now is never recorded, only a copy made after it (Clear History, the history turned off
    /// and on again): its change count is remembered as looked at, which never asks.
    public func forget() {
        seen = source.changeCount
        newestSeen = nil
    }

    /// The clipboard put back at change count `count` as it was at `was`, after a paste of ours (`TerminalPaste`): never
    /// recorded as a new copy, where `was` was looked at already (recorded, or skipped: copied during secure input, before
    /// Clear History); the store's newest still, if it was. Not looked at yet: the next look takes it as it would have.
    public func putBack(at count: Int, asAt was: Int) {
        guard let seen, seen >= was else { return }
        self.seen = count
        if newestSeen == was { newestSeen = count }
    }
}

/// Clipboard history's copies, newest first, as kept on this Mac: one file (`url`) for the list, and beside it a folder
/// (`imagesURL`) with each kept image's PNG and its thumbnail (0.6.8.2), all readable by the user only (0600), in
/// Application Support, excluded from backups, written whole (the list atomically) with each change; an image no longer
/// in the list is deleted with it; `clear` deletes them all (Clear History, the history turned off). Read once, as it is
/// made. Never synced, never sent anywhere. Its files are written one change after another (`writes`): at once, or, for
/// a copy recorded as ⌃V's panel is about to show, after it, off the main thread.
// Unchecked: `prepare` runs off the main thread and touches only the images folder (by `url`, which never changes); the
// list itself is read and changed on the main thread only, and written from a copy of it on `writes`.
public final class ClipboardHistoryStore: @unchecked Sendable {
    /// ~/Library/Application Support/AllInOneIME/clipboard-history.json.
    public static var defaultURL: URL { CorePaths.dataDir.appendingPathComponent("clipboard-history.json") }
    /// The longest side of a thumbnail, in pixels (the panel draws it in a row's icon square).
    static let thumbnailSide = 96

    public let url: URL
    /// Counts the clears: an image made ready before one isn't added after it (`ClipboardRecorder.poll`).
    public private(set) var generation = 0
    /// Where the list's file is written and the images no longer in it deleted, in the order the changes were made.
    private let writes = DispatchQueue(label: "com.allinoneime.inputmethod.clipboard-history", qos: .userInitiated)
    /// The ids of the images being made ready (`prepare` until `add` or `discard`): their files are never removed meanwhile.
    private let preparing = PreparingIDs()
    /// The kept images' folder, beside the list and named after it (clipboard-history-images for the user's): two stores
    /// never share one.
    public var imagesURL: URL {
        url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-images", isDirectory: true)
    }
    public private(set) var items: [ClipboardHistoryItem]
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

    public init(url: URL = ClipboardHistoryStore.defaultURL,
                moveFile: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) {
        self.url = url
        self.moveFile = moveFile
        items = []
        let (read, clean) = read()
        items = read.compactMap { item in
            guard let image = item.image else { return ClipboardHistoryItem(text: item.text, copiedAt: item.copiedAt) }
            // An image whose file is gone (deleted by hand) is gone from the list too.
            guard FileManager.default.fileExists(atPath: imageURL(image.id).path) else { return nil }
            return ClipboardHistoryItem(image: kept(image.id, width: image.width, height: image.height, bytes: image.bytes),
                                        copiedAt: item.copiedAt)
        }
        // Off the main thread, before any later write: a file it couldn't read in full moved aside and the items it could
        // written in its place; the images files moved aside have, found.
        let recovered = items
        writes.async { [self] in
            unarchived = !clean
            if !clean, archive() { save(recovered) }
            keptAsideIDs = keptAside()
        }
    }

    /// The items of the list's file it can read, and whether it read them all (no file: all). Where it didn't, the file is
    /// moved aside as it was (`archive`) before anything is written, never written over: the history is what it can read,
    /// and the images it kept stay until Clear History (`keptAside`).
    private func read() -> (items: [File.Item], clean: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], true) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let file = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ReadFile.self, from: $0) }
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

    /// `text` copied at `date`: first, once (the same text further down moves up), `limit` kept at most. False: it was
    /// the newest already, and nothing changed. `savingLater`: in the list at once, its file written off the main thread
    /// after (`waitForWrites` waits for it).
    @discardableResult
    public func record(_ text: String, at date: Date, limit: Int, savingLater: Bool = false) -> Bool {
        guard items.first.map({ $0.image != nil || $0.text != text }) ?? true else { return false }
        items.removeAll { $0.image == nil && $0.text == text }
        items.insert(ClipboardHistoryItem(text: text, copiedAt: date), at: 0)
        keep(limit, later: savingLater)
        return true
    }

    /// Once what was to be written is (`record(_:at:limit:savingLater:)`).
    public func waitForWrites() {
        writes.sync {}
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
        preparing.insert(id)
        do {
            try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            excludeFromBackup(imagesURL)
            let file = imageURL(id)
            if !FileManager.default.fileExists(atPath: file.path) { try Platform.current.files.writePrivate(png, to: file) }
            if let thumbnail = Self.thumbnail(png) { try Platform.current.files.writePrivate(thumbnail, to: thumbnailURL(id)) }
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
        // Being made ready until the list with it is written: a write left for later, of the list before it, keeps its files.
        defer { preparing.remove(image.id) }
        guard items.first?.image?.id != image.id else { return false }
        items.removeAll { $0.image?.id == image.id }
        let kept = kept(image.id, width: image.width, height: image.height, bytes: image.bytes)
        let place = items.firstIndex { $0.copiedAt < date } ?? items.count
        items.insert(ClipboardHistoryItem(image: kept, copiedAt: date), at: place)
        keep(limit)
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
        guard items.count > max(limit, 1) else { return }
        keep(limit)
    }

    /// Everything forgotten: the list's file and the images deleted (after what was to be written before).
    public func clear() {
        generation += 1
        items = []
        writes.sync {
            (keptAsideIDs, unarchived) = ([], false)
            for file in [url, imagesURL] + asideURLs { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// `limit` kept at most, saved; images no longer in the list deleted: before it returns, or (`later`) off the main
    /// thread after.
    private func keep(_ limit: Int, later: Bool = false) {
        items = Array(items.prefix(max(limit, 1)))
        guard !items.isEmpty else { return clear() }
        let items = self.items
        let write = { [self] in
            save(items)
            removeUnlisted(listing: items)
        }
        if later { writes.async(execute: write) } else { writes.sync(execute: write) }
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
        writes.sync { removeUnlisted(listing: items) }
    }

    /// Image files whose image isn't among `items`, nor being made ready, deleted.
    private func removeUnlisted(listing items: [ClipboardHistoryItem]) {
        guard archive() else { return }
        let listed = Set(items.compactMap { $0.image?.id }).union(preparing.ids).union(keptAsideIDs)
        for (name, id) in Self.files(in: imagesURL) where !listed.contains(id) {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
        }
        if listed.isEmpty { try? FileManager.default.removeItem(at: imagesURL) }
    }

    /// The files in an images folder, each with its image's id.
    private static func files(in folder: URL) -> [(name: String, id: String)] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).map { name in
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
