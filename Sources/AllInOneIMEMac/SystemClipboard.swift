import AppKit
import Foundation
import ImageIO

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
        guard !(pasteboard.types ?? []).contains(where: { $0.rawValue == Self.remoteType }) else { return nil }
        if let text = pasteboard.string(forType: .string) { return text }
        // Rich text without its plain text alongside: its plain text.
        if let rtf = pasteboard.data(forType: .rtf) { return NSAttributedString(rtf: rtf, documentAttributes: nil)?.string }
        return nil
    }

    /// Universal Clipboard's marker: a copy made on an iPhone or another Mac, its data fetched from there when read (the
    /// main thread would wait on the network): never read for the history, its text nor its image.
    public static let remoteType = "com.apple.is-remote-clipboard"

    public func image() -> ClipboardImage? {
        let pasteboard = NSPasteboard.general
        guard let types = pasteboard.types, let first = types.first, ClipboardImage.types.contains(first.rawValue),
              !types.contains(where: { $0.rawValue == Self.remoteType }), let data = pasteboard.data(forType: first)
        else { return nil }
        return ClipboardImage.from(data)
    }
}
