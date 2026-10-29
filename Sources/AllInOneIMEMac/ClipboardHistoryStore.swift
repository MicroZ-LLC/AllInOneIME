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
    /// Its plain text (rich text's too); nil: no text (an image, a colour).
    func text() -> String?
    /// The image on it, as PNG, where an image is what was copied (its first type an image's: a screenshot, Copy Image);
    /// nil otherwise (0.6.8.2).
    func image() -> ClipboardImage?
}

/// An image read off the clipboard as it was there (PNG, TIFF, JPEG…) and its size in pixels, told without decoding it
/// (`ClipboardImage.from`); its PNG and thumbnail are made off the main thread (`ClipboardHistoryStore.prepare`).
public struct ClipboardImage: Equatable, Sendable {
    public var data: Data
    public var width: Int
    public var height: Int

    public init(data: Data, width: Int, height: Int) {
        (self.data, self.width, self.height) = (data, width, height)
    }

    /// The image types a copy of an image puts first.
    public static let types: Set<String> = ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif"]
    /// The most pixels an image kept may have (a photo's 48 MP is past it: its PNG would be over the limit anyway), and the
    /// most bytes it may come as: larger ones are never decoded.
    public static let maxPixels = 40_000_000
    public static let maxDataBytes = 60 * 1024 * 1024

    /// `data` with its size in pixels, as the image's header tells it (nothing decoded); nil where it isn't an image, or
    /// it is too large to keep (`maxPixels`, `maxDataBytes`).
    public static func from(_ data: Data) -> ClipboardImage? {
        guard data.count <= maxDataBytes, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width * height <= maxPixels
        else { return nil }
        return ClipboardImage(data: data, width: width, height: height)
    }

    /// As PNG (kept as it is when it is one).
    func pngData() -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// The general pasteboard, as clipboard history reads it.
public final class SystemClipboard: ClipboardSource {
    public init() {}

    public var changeCount: Int { NSPasteboard.general.changeCount }

    public var access: ClipboardAccess {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: return .allowed
        case .alwaysDeny: return .denied
        case .default: return .notListed
        case .ask: return .asks
        @unknown default: return .asks
        }
    }

    public var types: [String] { NSPasteboard.general.types?.map(\.rawValue) ?? [] }

    public func text() -> String? {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) { return text }
        // Rich text without its plain text alongside: its plain text.
        if let rtf = pasteboard.data(forType: .rtf) { return NSAttributedString(rtf: rtf, documentAttributes: nil)?.string }
        return nil
    }

    /// Universal Clipboard's marker: an image copied on an iPhone or another Mac, its data fetched from there when read
    /// (the main thread would wait on the network): never read for the history.
    public static let remoteType = "com.apple.is-remote-clipboard"

    public func image() -> ClipboardImage? {
        let pasteboard = NSPasteboard.general
        guard let types = pasteboard.types, let first = types.first, ClipboardImage.types.contains(first.rawValue),
              !types.contains(where: { $0.rawValue == Self.remoteType }), let data = pasteboard.data(forType: first)
        else { return nil }
        return ClipboardImage.from(data)
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
/// before), it is marked never to be kept (`neverRecorded`: password managers and clipboard tools mark theirs, as
/// TerminalPaste marks its own writes), it isn't text (an image, a file, a colour), it is blank, or it is longer than
/// `ClipboardHistoryItem.maxLength`. Used on one thread (the input method's main one).
public final class ClipboardRecorder {
    /// Why a change wasn't recorded.
    public enum Outcome: Equatable, Sendable {
        case unchanged, recorded
        case notAllowed, secureInput, marked, notText, blank, tooLong
        /// An image being made ready off the main thread (`imageWork`): recorded once it is.
        case imageQueued
        /// It couldn't be written (a full disk): nothing kept.
        case notSaved
        /// The newest kept already (a copy of it again, the clipboard put back after a paste of ours).
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
    /// Runs an image's preparation (its PNG, id, thumbnail and files: `ClipboardHistoryStore.prepare`) and hands its result
    /// to the second closure on the main thread: off the main thread by default, so a large copy never holds typing up;
    /// a test's runs it at once.
    public var imageWork: (@escaping @Sendable () -> ClipboardHistoryStore.Prepared, @escaping (ClipboardHistoryStore.Prepared) -> Void) -> Void = { prepare, done in
        // `done` runs on the main thread only, where the recorder is used.
        let main = MainThreadOnly(done)
        DispatchQueue.global(qos: .utility).async {
            let prepared = prepare()
            DispatchQueue.main.async { main.value(prepared) }
        }
    }
    let secureInput: () -> Bool
    let now: () -> Date
    /// The change count last looked at (nil: none yet: what's on the clipboard is recorded at the first look, at launch),
    /// and whether secure input was on then.
    private var seen: Int?
    private var wasSecure = false
    /// The access as told at the last change.
    public private(set) var access: ClipboardAccess
    /// The change count of the copy the store has as its newest (recorded, or the newest already); nil: none since launch.
    private var newestSeen: Int?

    /// Whether what's on the clipboard now is the store's newest copy, unchanged since (the change count only: never asks).
    public var clipboardIsNewest: Bool { newestSeen != nil && newestSeen == source.changeCount }

    public init(source: ClipboardSource, store: ClipboardHistoryStore, secureInput: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.store = store
        self.secureInput = secureInput
        self.now = now
        access = source.access
    }

    /// A look at the clipboard: a change since the last recorded (`limit`: how many are kept).
    @discardableResult
    public func poll(limit: Int) -> Outcome {
        let secure = secureInput()
        defer { wasSecure = secure }
        let count = source.changeCount
        guard count != seen else { return .unchanged }
        seen = count
        access = source.access
        guard access == .allowed else { return .notAllowed }
        guard !secure, !wasSecure else { return .secureInput }
        guard Set(source.types).isDisjoint(with: Self.neverRecorded) else { return .marked }
        if let image = source.image() {
            let (store, date) = (store, now())
            var outcome = Outcome.imageQueued
            imageWork({ store.prepare(image) }) { [weak self] prepared in
                guard let self else { return }
                switch prepared {
                case let .ready(ready):
                    outcome = store.add(ready, at: date, limit: limit) ? .recorded : .same
                    // The newest still on the clipboard only if nothing was copied since.
                    if source.changeCount == count { newestSeen = count }
                case .tooLarge:
                    outcome = .tooLong
                case .notSaved:
                    outcome = .notSaved
                }
            }
            return outcome
        }
        guard let text = source.text() else { return .notText }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .blank }
        guard text.utf16.count <= ClipboardHistoryItem.maxLength * 4, text.count <= ClipboardHistoryItem.maxLength else { return .tooLong }
        newestSeen = count
        return store.record(text, at: now(), limit: limit) ? .recorded : .same
    }

    /// What's on the clipboard now is never recorded, only a copy made after it (Clear History, the history turned off
    /// and on again): its change count is remembered as looked at, which never asks.
    public func forget() {
        seen = source.changeCount
        newestSeen = nil
    }
}

/// Clipboard history's copies, newest first, as kept on this Mac: one file (`url`) for the list, and beside it a folder
/// (`imagesURL`) with each kept image's PNG and its thumbnail (0.6.8.2), all readable by the user only (0600), in
/// Application Support, excluded from backups, written whole (the list atomically) with each change; an image no longer
/// in the list is deleted with it; `clear` deletes them all (Clear History, the history turned off). Read once, as it is
/// made. Never synced, never sent anywhere.
// Unchecked: `prepare` runs off the main thread and touches only the images folder (by `url`, which never changes); the
// list itself is read and changed on the main thread only.
public final class ClipboardHistoryStore: @unchecked Sendable {
    /// ~/Library/Application Support/AllInOneIME/clipboard-history.json.
    public static var defaultURL: URL { CorePaths.dataDir.appendingPathComponent("clipboard-history.json") }
    /// The longest side of a thumbnail, in pixels (the panel draws it in a row's icon square).
    static let thumbnailSide = 96

    public let url: URL
    /// The kept images' folder, beside the list and named after it (clipboard-history-images for the user's): two stores
    /// never share one.
    public var imagesURL: URL {
        url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-images", isDirectory: true)
    }
    public private(set) var items: [ClipboardHistoryItem]

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

    public init(url: URL = ClipboardHistoryStore.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let file = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(File.self, from: $0) }
        items = []
        items = file?.items.compactMap { item in
            guard let image = item.image else { return ClipboardHistoryItem(text: item.text, copiedAt: item.copiedAt) }
            // An image whose file is gone (deleted by hand) is gone from the list too.
            guard FileManager.default.fileExists(atPath: imageURL(image.id).path) else { return nil }
            return ClipboardHistoryItem(image: kept(image.id, width: image.width, height: image.height, bytes: image.bytes),
                                        copiedAt: item.copiedAt)
        } ?? []
    }

    /// `text` copied at `date`: first, once (the same text further down moves up), `limit` kept at most. False: it was
    /// the newest already, and nothing changed.
    @discardableResult
    public func record(_ text: String, at date: Date, limit: Int) -> Bool {
        guard items.first.map({ $0.image != nil || $0.text != text }) ?? true else { return false }
        items.removeAll { $0.image == nil && $0.text == text }
        items.insert(ClipboardHistoryItem(text: text, copiedAt: date), at: 0)
        keep(limit)
        return true
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
        do {
            try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            excludeFromBackup(imagesURL)
            let file = imageURL(id)
            if !FileManager.default.fileExists(atPath: file.path) { try Platform.current.files.writePrivate(png, to: file) }
            if let thumbnail = Self.thumbnail(png) { try Platform.current.files.writePrivate(thumbnail, to: thumbnailURL(id)) }
        } catch {
            CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")
                .error("clipboard history: could not save an image: \(String(describing: type(of: error)))")
            return .notSaved
        }
        return .ready(ReadyImage(id: id, width: image.width, height: image.height, bytes: png.count))
    }

    /// A ready image (`prepare`) copied at `date` in the list: where its date puts it (a text copied while it was made
    /// ready stays above it), once (the same image further down moves up), `limit` kept at most. False: it was the newest
    /// already, and nothing changed.
    @discardableResult
    public func add(_ image: ReadyImage, at date: Date, limit: Int) -> Bool {
        guard items.first?.image?.id != image.id else { return false }
        items.removeAll { $0.image?.id == image.id }
        let kept = kept(image.id, width: image.width, height: image.height, bytes: image.bytes)
        let place = items.firstIndex { $0.copiedAt < date } ?? items.count
        items.insert(ClipboardHistoryItem(image: kept, copiedAt: date), at: place)
        keep(limit)
        return true
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

    /// The oldest dropped beyond `limit` (a lower one set), at once.
    public func trim(to limit: Int) {
        guard items.count > max(limit, 1) else { return }
        keep(limit)
    }

    /// Everything forgotten: the list's file and the images deleted.
    public func clear() {
        items = []
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: imagesURL)
    }

    /// `limit` kept at most, saved; images no longer in the list deleted.
    private func keep(_ limit: Int) {
        items = Array(items.prefix(max(limit, 1)))
        save()
        removeUnlisted()
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
        let listed = Set(items.compactMap { $0.image?.id })
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: imagesURL.path) else { return }
        for name in files {
            let id = name.replacingOccurrences(of: "-thumb.png", with: "").replacingOccurrences(of: ".png", with: "")
            if !listed.contains(id) { try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name)) }
        }
        if listed.isEmpty { try? FileManager.default.removeItem(at: imagesURL) }
    }

    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    private func save() {
        guard !items.isEmpty else { return clear() }
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
            CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")
                .error("clipboard history: could not save it: \(String(describing: type(of: error)))")
        }
    }
}
