import AllInOneIMECore
import AppKit
import CryptoKit
import Foundation

// Clipboard history's recording and keeping on this Mac (the core's Session/ClipboardHistory.swift is the behaviour of
// the panel ⌃V shows): the text of each copy, after it is made, kept in a file of the user's only. The input method's
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

/// An image read off the clipboard: its PNG and its size in pixels.
public struct ClipboardImage: Equatable, Sendable {
    public var png: Data
    public var width: Int
    public var height: Int

    public init(png: Data, width: Int, height: Int) {
        (self.png, self.width, self.height) = (png, width, height)
    }

    /// The image types a copy of an image puts first.
    public static let types: Set<String> = ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif"]

    /// `data` (any image type macOS reads) as PNG, with its size in pixels; nil where it isn't an image.
    public static func from(_ data: Data) -> ClipboardImage? {
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
        let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? data : bitmap.representation(using: .png, properties: [:])
        guard let png else { return nil }
        return ClipboardImage(png: png, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
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

    public func image() -> ClipboardImage? {
        let pasteboard = NSPasteboard.general
        guard let first = pasteboard.types?.first, ClipboardImage.types.contains(first.rawValue),
              let data = pasteboard.data(forType: first) else { return nil }
        return ClipboardImage.from(data)
    }
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
            guard image.png.count <= ClipboardHistoryImage.maxBytes else { return .tooLong }
            newestSeen = count
            return store.recordImage(image, at: now(), limit: limit) ? .recorded : .same
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
public final class ClipboardHistoryStore {
    /// ~/Library/Application Support/AllInOneIME/clipboard-history.json.
    public static var defaultURL: URL { CorePaths.dataDir.appendingPathComponent("clipboard-history.json") }
    /// The longest side of a thumbnail, in pixels (the panel draws it in a row's icon square).
    static let thumbnailSide = 96

    public let url: URL
    /// The kept images' folder: clipboard-history-images, beside the list.
    public var imagesURL: URL { url.deletingLastPathComponent().appendingPathComponent("clipboard-history-images", isDirectory: true) }
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

    /// An image copied at `date`: its PNG and thumbnail written (once: its id is its data's SHA-256), first in the list,
    /// once (the same image further down moves up), `limit` kept at most. False: it was the newest already, or it couldn't
    /// be written, and nothing changed.
    @discardableResult
    public func recordImage(_ image: ClipboardImage, at date: Date, limit: Int) -> Bool {
        let id = SHA256.hash(data: image.png).map { String(format: "%02x", $0) }.joined()
        guard items.first?.image?.id != id else { return false }
        guard write(image, id: id) else { return false }
        items.removeAll { $0.image?.id == id }
        let kept = kept(id, width: image.width, height: image.height, bytes: image.png.count)
        items.insert(ClipboardHistoryItem(image: kept, copiedAt: date), at: 0)
        keep(limit)
        return true
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

    /// The image's PNG and thumbnail in the images folder (0600, excluded from backups; the PNG kept as it is if there).
    private func write(_ image: ClipboardImage, id: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            excludeFromBackup(imagesURL)
            let file = imageURL(id)
            if !FileManager.default.fileExists(atPath: file.path) { try Platform.current.files.writePrivate(image.png, to: file) }
            if let thumbnail = Self.thumbnail(image) { try Platform.current.files.writePrivate(thumbnail, to: thumbnailURL(id)) }
            return true
        } catch {
            CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")
                .error("clipboard history: could not save an image: \(String(describing: type(of: error)))")
            return false
        }
    }

    /// A PNG at most `thumbnailSide` pixels on its longer side.
    static func thumbnail(_ image: ClipboardImage) -> Data? {
        guard let source = NSBitmapImageRep(data: image.png)?.cgImage else { return nil }
        let scale = min(1, Double(thumbnailSide) / Double(max(image.width, image.height)))
        let (width, height) = (max(1, Int(Double(image.width) * scale)), max(1, Int(Double(image.height) * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
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
