import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import QuartzCore

/// Clipboard history's larger picture of an image (0.7.0, owner): beside the candidate panel, the image of the row under the
/// pointer, else of the chosen row (↑↓), when that row is a kept image's (its thumbnail stands for one the history keeps:
/// `keptImage`). "Image on the clipboard" has none: ⌃V's panel looks only at the clipboard's types, never reads its image,
/// and nothing more is read for this. Which, how large and where are `ImagePreviewLayout`'s: up to 360 pt on its longer
/// side and never larger than the image itself, on the panel's right 8 pt from it with its top at the row's, smaller
/// there where the room up to the screen's edge is less (160 pt at least on its longer side), on the panel's left only
/// where even that doesn't fit, none without room on either side; never over the panel. It follows the pointer and the
/// keys, moves with the panel and the row, and goes as the panel goes. Pointing at a row changes nothing (the choice, the
/// text).
/// Never in the way: its window takes no clicks and never becomes key, and no key waits for it: it follows the panel a
/// turn of the run loop later (`update`), the row's thumbnail drawn larger until the image is decoded off the main thread
/// at the size drawn (`ImagePreviewImages`; a few kept while the panel shows, dropped as it hides). It looks as the panel
/// does (the system's glass, its corners and hairline edge, its shadow) and comes up as it does. Mac only; main thread only.
@MainActor
final class ImagePreview {
    static let shared = ImagePreview()

    /// The kept image a row's thumbnail (the file its icon draws) stands for, and its PNG's file; nil: none. The history's
    /// (`ClipboardHistoryShared`); the self-test's own.
    var keptImage: @MainActor (String) -> (image: ClipboardHistoryImage, file: URL)? = { ClipboardHistoryShared.keptImage(thumbnail: $0) }

    let window = ImagePreviewWindow()
    var view: ImagePreviewView { window.preview }
    let images = ImagePreviewImages()
    private(set) weak var panel: CandidatePanel?
    /// What it shows (nil: nothing), and its image's file.
    private(set) var shown: (layout: ImagePreviewLayout.Shown, file: URL)?
    /// An update asked for and not made yet (`update`).
    private var updating = false

    /// Shows beside `panel` from now on.
    func attach(to panel: CandidatePanel) {
        guard self.panel !== panel else { return }
        self.panel = panel
        window.level = panel.level
        panel.onPresent = { [weak self] in self?.update() }
        panel.view.onHover = { [weak self] _ in self?.update() }
    }

    /// The panel shown or hidden, or the pointer onto another row: gone at once as the panel goes; else brought up to date
    /// a turn of the run loop later, so neither the key that changed the panel nor the panel waits for it, and what one
    /// key changes is one update.
    func update() {
        guard let panel, panel.isShowing else { return hide() }
        // Nothing shown and no image row (pinyin's candidates, a command's rows): nothing to do on the key.
        let model = panel.view.model
        guard shown != nil || model.rows.indices.contains(where: { Self.thumbnail(of: model, $0) != nil }) else { return }
        guard !updating else { return }
        updating = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updating = false
                self.apply()
            }
        }
    }

    /// What shows as the panel is now: which row's image, how large, where; the image as decoded, or the row's thumbnail
    /// until it is.
    func apply() {
        guard let panel, panel.isShowing, let screen = panel.screen ?? NSScreen.main else { return hide() }
        let model = panel.view.model
        // The row under the pointer while the pointer is on it (not one a panel kept as it came up elsewhere).
        let pointer = NSEvent.mouseLocation
        let hovered = panel.view.hovered.flatMap { index in rowFrame(index, in: panel).map { $0.contains(pointer) } == true ? index : nil }
        let state = ImagePreviewLayout.Panel(frame: panel.frame, hovered: hovered, chosen: model.highlighted, visible: screen.visibleFrame,
                                             scale: screen.backingScaleFactor)
        var files: [Int: (file: URL, thumbnail: String)] = [:]
        let next = ImagePreviewLayout.shown(state, inset: CandidateView.Metrics.padding) { index in
            guard let path = Self.thumbnail(of: model, index), let kept = keptImage(path), let row = rowFrame(index, in: panel) else { return nil }
            files[index] = (kept.file, path)
            return ImagePreviewLayout.ImageRow(pixels: CGSize(width: kept.image.width, height: kept.image.height), top: row.maxY)
        }
        guard let next, let found = files[next.row] else { return hide() }
        let (file, thumbnail) = found
        let appearing = shown == nil
        shown = (next, file)
        let side = max(next.imageSize.width, next.imageSize.height) * screen.backingScaleFactor
        let key = ImagePreviewImages.Key(file: file, pixels: Int(side.rounded(.up)))
        if view.decoded != key {
            // Drawn once decoded if it is still what shows (`images` hands over only the one asked for last).
            let decoded: @MainActor @Sendable (CGImage) -> Void = { [weak self] image in
                guard let self, self.shown?.file == key.file else { return }
                self.view.show(image, for: key)
            }
            if let image = images.image(key, done: decoded) {
                view.show(image, for: key)
            } else {
                view.show(thumbnail: CommandIcons.image(thumbnail))
            }
        }
        window.appearance = panel.appearance
        window.alphaValue = panel.alphaValue
        if window.frame != next.frame {
            window.setFrame(next.frame, display: true)
            window.invalidateShadow()
        }
        if !window.isVisible { window.orderFrontRegardless() }
        if appearing, window.alphaValue > 0 { animateAppearance(onTheRight: next.frame.minX >= panel.frame.maxX) }
    }

    /// Gone (the panel hidden, no image row pointed at or chosen, or no room): at once, unseen and drawing nothing; its
    /// window put away after the key (ordering a window out during one can hold the app up on the window server, as the
    /// panel's comment says). The images decoded are dropped once the panel is hidden.
    func hide() {
        if panel?.isShowing != true { images.clear() }
        guard shown != nil else { return }
        shown = nil
        window.contentView?.layer?.removeAnimation(forKey: "appear")
        window.alphaValue = 0
        view.clear()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shown == nil else { return }
                self.window.orderOut(nil)
            }
        }
    }

    /// The file row `index`'s icon draws (clipboard history's thumbnail of a kept image); nil: no such row, or another icon.
    static func thumbnail(of model: PanelModel, _ index: Int) -> String? {
        guard model.rows.indices.contains(index), case let .image(path, _)? = model.rows[index].icon?.glyph else { return nil }
        return path
    }

    /// Row `index`'s frame on screen; nil: no such row.
    private func rowFrame(_ index: Int, in panel: CandidatePanel) -> NSRect? {
        guard let frame = panel.view.rowFrame(index) else { return nil }
        return panel.convertToScreen(panel.view.convert(frame, to: nil))
    }

    /// As it comes up, as the panel does: a quick fade, growing to its size from 98% toward the row (its top corner on the
    /// panel's side), 120 ms, no bounce; none with Reduce Motion. On the layers only: the window is where it goes from the
    /// start, and nothing waits for it.
    private func animateAppearance(onTheRight: Bool) {
        guard !CandidateView.reducesMotion, let layer = window.contentView?.layer else { return }
        let size = layer.bounds.size
        let pivot = CGPoint(x: onTheRight ? 0 : size.width, y: layer.contentsAreFlipped() ? 0 : size.height)
        let d = CGPoint(x: pivot.x - layer.anchorPoint.x * size.width, y: pivot.y - layer.anchorPoint.y * size.height)
        let grown = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(d.x, d.y, 0), 0.98, 0.98, 1), -d.x, -d.y, 0)
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: grown)
        scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.12
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "appear")
    }

    /// The panel and the preview beside it as one offscreen image, where they are on screen, a margin around them (their
    /// own solid backgrounds and a drawn shadow: an offscreen image has nothing behind it to blur); nil: no preview.
    func snapshot(appearance name: NSAppearance.Name = .aqua) -> NSBitmapImageRep? {
        guard let panel, let shown else { return nil }
        let margin: CGFloat = 24, scale: CGFloat = 2
        let area = panel.frame.union(shown.layout.frame).insetBy(dx: -margin, dy: -margin)
        let parts = [(panel.view as NSView, panel.frame), (view as NSView, shown.layout.frame)].compactMap { part, frame in
            Self.render(part, appearance: NSAppearance(named: name)).map { ($0, frame.offsetBy(dx: -area.minX, dy: -area.minY)) }
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(area.width * scale), pixelsHigh: Int(area.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = area.size  // before its context is made: drawn in points, `scale` pixels to one
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        (name == .darkAqua ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSRect(origin: .zero, size: area.size).fill()
        for (image, frame) in parts {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 14
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.set()
            image.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// `view` drawn offscreen in `appearance`, on its own solid background.
    private static func render(_ view: NSView, appearance: NSAppearance?) -> NSImage? {
        let backgrounds = (view as? CandidateView)?.drawsBackground ?? (view as? ImagePreviewView)?.drawsBackground
        func drawsBackground(_ on: Bool) {
            (view as? CandidateView)?.drawsBackground = on
            (view as? ImagePreviewView)?.drawsBackground = on
        }
        view.appearance = appearance
        drawsBackground(true)
        defer {
            view.appearance = nil
            drawsBackground(backgrounds ?? false)
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

/// The preview's window: borderless, never key or main, taking no clicks (they go to what is under it), above other apps'
/// windows on every Space as the panel is; the system's glass behind the image, as behind the panel's rows
/// (`CandidatePanel.glass`).
final class ImagePreviewWindow: NSPanel {
    let preview = ImagePreviewView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        preview.drawsBackground = false
        contentView = CandidatePanel.glass(around: preview)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The image, inset from the edge as the panel's rows are (`CandidateView.Metrics.padding`), its corners as round as a
/// row's highlight, a faint line around it (a white image on light glass keeps its edge), and the panel's hairline edge
/// around the whole; its own solid background only for an offscreen image (`drawsBackground`), as the panel's.
final class ImagePreviewView: NSView {
    /// What it draws: the image decoded for `decoded`, or (`decoded` nil) the row's thumbnail until it is.
    private(set) var image: NSImage?
    private(set) var decoded: ImagePreviewImages.Key?
    var drawsBackground = true

    /// The image decoded for `key`.
    func show(_ image: CGImage, for key: ImagePreviewImages.Key) {
        self.image = NSImage(cgImage: image, size: .zero)
        decoded = key
        needsDisplay = true
    }

    /// The row's thumbnail, drawn larger until the image is decoded.
    func show(thumbnail: NSImage?) {
        (image, decoded) = (thumbnail, nil)
        needsDisplay = true
    }

    func clear() {
        (image, decoded) = (nil, nil)
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let radius = CandidateView.Metrics.cornerRadius
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: radius - 0.25, yRadius: radius - 0.25)
        if drawsBackground {
            CandidateView.background.setFill()
            shape.fill()
        }
        if let image {
            let frame = bounds.insetBy(dx: CandidateView.Metrics.padding, dy: CandidateView.Metrics.padding)
            let corners = NSBezierPath(roundedRect: frame, xRadius: CandidateView.Metrics.rowRadius, yRadius: CandidateView.Metrics.rowRadius)
            NSGraphicsContext.saveGraphicsState()
            corners.addClip()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(dark ? 0.16 : 0.1).setStroke()
            corners.lineWidth = 0.5
            corners.stroke()
        }
        // Its edge: a hairline, over the glass's own, as the panel's.
        (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.1)).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}
