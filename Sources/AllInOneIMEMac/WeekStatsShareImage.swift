import AllInOneIMECore
import AppKit

/// This week's card as a picture to share (Settings → This Week's Copy Image and Save as Image…, `@stats`'s ⌘C): the
/// card `WeekStatsCard` draws in its `.share` style, 640 × 540 points at twice the pixels (1280 × 1080), a PNG, in the
/// first person ("这周我用了"), the user's own command names hidden if they asked. Made on this Mac from the counts in
/// memory; it goes where the user puts it, nowhere else.
public enum WeekStatsShareImage {
    public enum Appearance: Sendable {
        case light, dark

        /// The system's appearance now.
        @MainActor public static var current: Appearance {
            NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        }

        var name: NSAppearance.Name { self == .dark ? .darkAqua : .aqua }
    }

    public enum Failure: Error {
        case drawing
        /// The clipboard didn't take it.
        case pasteboard
    }

    /// The picture, as PNG data (any thread).
    public static func render(week: WeekStats.Snapshot, language: String, hideOwnCommandNames: Bool, appearance: Appearance,
                              icon: @escaping (WeekStats.Snapshot.CommandCount) -> IconToken = WeekStatsCard.builtInIcon) throws -> Data {
        let card = WeekStatsCard(week: week, language: language, style: .share, hideOwnCommandNames: hideOwnCommandNames, icon: icon)
        let size = WeekStatsCard.shareSize
        let scale: CGFloat = 2
        // In sRGB, which the PNG says: the colors as drawn on any screen it's shown on.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                 bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.drawing }
        cg.translateBy(x: 0, y: size.height * scale)
        cg.scaleBy(x: scale, y: -scale)
        let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = flipped
        (NSAppearance(named: appearance.name) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            card.draw(in: CGRect(origin: .zero, size: size))
        }
        flipped.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let image = cg.makeImage() else { throw Failure.drawing }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = size  // 144 dpi: shown 640 × 540 points
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.drawing }
        return png
    }

    /// The picture on `pasteboard` (the general one by default), as PNG and as TIFF for the apps that only take that.
    public static func copy(week: WeekStats.Snapshot, language: String, hideOwnCommandNames: Bool, appearance: Appearance,
                            icon: @escaping (WeekStats.Snapshot.CommandCount) -> IconToken = WeekStatsCard.builtInIcon,
                            to pasteboard: NSPasteboard = .general) throws {
        let png = try render(week: week, language: language, hideOwnCommandNames: hideOwnCommandNames, appearance: appearance,
                             icon: icon)
        guard put(png, on: pasteboard) else { throw Failure.pasteboard }
    }

    /// A picture `render` made on `pasteboard`, as PNG and as TIFF: whether the PNG is there.
    @discardableResult
    public static func put(_ png: Data, on pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        guard pasteboard.setData(png, forType: .png) else { return false }
        if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }
}
