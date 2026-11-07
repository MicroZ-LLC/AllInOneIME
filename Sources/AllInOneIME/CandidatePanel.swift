import AllInOneIMECore
import AppKit
import QuartzCore

/// Borderless, non-activating floating panel shown under the insertion point (above it when there's no room below).
final class CandidatePanel: NSPanel {
    static let shared = CandidatePanel()

    /// Which side of the caret the panel is on.
    enum Side: Equatable {
        case below, above
    }

    /// The input controller currently showing the panel.
    weak var owner: AnyObject?
    let view = CandidateView()
    private var pendingHide: DispatchWorkItem?
    private var hiddenPresentation: (alpha: CGFloat, ignoresMouseEvents: Bool)?
    /// The side the panel is on while it shows, and the caret line it went there for: kept while typing on that line, as
    /// long as it fits there (`placement`), so a panel that grows and shrinks with the keys (the pinyin candidates' line
    /// coming and going) doesn't flip from one side of the caret to the other. Forgotten as it hides.
    private var placed: (side: Side, anchor: NSRect)?

    /// Hidden immediately between words, even while its window is kept ordered for the next word.
    var isShowing: Bool { isVisible && pendingHide == nil }

    var onSelect: ((Int) -> Void)? {
        get { view.onSelect }
        set { view.onSelect = newValue }
    }

    /// A row right-clicked: its index in `model.rows` (`SessionEvent.delete`).
    var onDelete: ((Int) -> Void)? {
        get { view.onDelete }
        set { view.onDelete = newValue }
    }

    /// The scroll wheel or trackpad over the panel: rows to move (down is positive).
    var onScroll: ((Int) -> Void)? {
        get { view.onScroll }
        set { view.onScroll = newValue }
    }

    /// A part of Translate as You Type's chip clicked (`PanelModel.chip`).
    var onChip: ((CandidateView.ChipPart) -> Void)? {
        get { view.onChip }
        set { view.onChip = newValue }
    }

    /// Told after each `show` and as it hides: what shows beside it follows it (`ImagePreview`, clipboard history's larger
    /// picture of an image).
    var onPresent: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Just below the cursor level: stays above full-screen apps and popup menus.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 100)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The pointer over a row highlights it (`CandidateView.hovered`), the panel never being key.
        acceptsMouseMovedEvents = true
        view.drawsBackground = false
        contentView = Self.glass(around: view)
    }

    /// The system's own material behind the rows, so the panel looks like the system's menus and follows
    /// its settings: Liquid Glass on macOS 26 (Clear or Tinted, as set in Appearance), the menu material
    /// before; both turn solid with Reduce Transparency (Accessibility → Display).
    static func glass(around view: NSView) -> NSView {
        view.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = CandidateView.Metrics.cornerRadius
            glass.contentView = view
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active  // the panel is never key: keep it frosted
        let radius = CandidateView.Metrics.cornerRadius
        effect.maskImage = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }.with { $0.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius); $0.resizingMode = .stretch }
        effect.addSubview(view)
        return effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ model: PanelModel, anchor: NSRect) {
        // Coming up (not changing with a key while up): it fades in as it does.
        let appearing = !isShowing
        pendingHide?.cancel()
        pendingHide = nil
        // A conversation grows up to about half the screen it's on, then scrolls (`PanelModel.transcript`).
        view.maxHeight = (Self.screen(for: anchor)?.visibleFrame.height).map { floor($0 / 2) }
        // Up already: no narrower than it shows (`CandidateView.minimumWidth`); coming up, as wide as its rows need.
        view.minimumWidth = appearing ? 0 : frame.width
        view.model = model
        let (nextFrame, side) = placement(at: anchor)
        // The pinyin candidates' line on the side nearest the caret, laid out for that side before anything is drawn: the
        // rows are never seen where the other side would have them.
        view.side = side
        placed = (side, anchor)
        if frame != nextFrame {
            setFrame(nextFrame, display: true)
            invalidateShadow()
        }
        if !isVisible { orderFrontRegardless() }
        if let presentation = hiddenPresentation {
            alphaValue = presentation.alpha
            ignoresMouseEvents = presentation.ignoresMouseEvents
            hiddenPresentation = nil
        }
        if appearing, alphaValue > 0 { animateAppearance(from: side) }
        onPresent?()
    }

    /// As it comes up: a quick fade, growing to its size from 98% toward the caret, 120 ms, no bounce; none with Reduce
    /// Motion. Core Animation's, on the layers only: the rows are there from the start, the window (its alpha, its frame)
    /// as without it, and no key waits for it.
    private func animateAppearance(from side: Side) {
        guard !CandidateView.reducesMotion, let layer = contentView?.layer else { return }
        let size = layer.bounds.size
        // The caret's corner: the top left below it, the bottom left above it (a layer's y goes up unless flipped).
        let top = layer.contentsAreFlipped() ? 0 : size.height
        let pivot = CGPoint(x: min(view.textInset, size.width), y: side == .below ? top : size.height - top)
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

    /// Its window, the glass behind the rows and their first drawing made now, unseen (no alpha, no clicks), and put away a
    /// moment later as `hide` puts it away: the first panel a key shows after launch doesn't wait for them (a cold first
    /// show took 30 ms on an M4, 5.9 ms after this). Once, at launch (`LaunchWarmUp`); only while it has never shown (one
    /// shown and hidden since has what it would make, and keeps how it shows: `hiddenPresentation`).
    func prewarm() {
        guard !isVisible, hiddenPresentation == nil else { return }
        view.model = PanelModel(rows: [PanelModel.Row(label: "1", text: "你好 AllInOneIME", kind: .candidate)])
        setFrame(NSRect(origin: frame.origin, size: view.contentSize), display: false)
        hiddenPresentation = (alphaValue, ignoresMouseEvents)
        alphaValue = 0
        ignoresMouseEvents = true
        orderFrontRegardless()
        display()
        view.model = PanelModel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isShowing else { return }
            self.orderOut(nil)
            self.pendingHide = nil
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Our other windows on screen where the panel is: none while it shows rows (spec 0: one thing at the caret at a
    /// time; a notice is the panel's own, on its footer then), which the self-test checks.
    var overlapping: [NSWindow] {
        NSApp.windows.filter { $0 !== self && $0.isVisible && $0.frame.intersects(frame) }
    }

    /// Whether `show(model, anchor:)` would change nothing: up already, with this model, where `anchor` puts it.
    func shows(_ model: PanelModel, anchor: NSRect) -> Bool {
        guard isShowing, view.model == model else { return false }
        let (nextFrame, side) = placement(at: anchor)
        return frame == nextFrame && view.side == side
    }

    func hide() {
        guard isShowing else { return }
        placed = nil
        view.minimumWidth = 0
        contentView?.layer?.removeAnimation(forKey: "appear")
        // No stale candidates or invisible hit target. Reuse the ordered window during a burst of typing:
        // ordering it out on every commit can stall the IME on a WindowServer fence in the client app.
        hiddenPresentation = (alphaValue, ignoresMouseEvents)
        alphaValue = 0
        ignoresMouseEvents = true
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isShowing else { return }
            self.orderOut(nil)
            self.pendingHide = nil
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        onPresent?()
    }

    /// Where the panel goes for `anchor` as the view is laid out now, and on which side of the caret (the side it is on
    /// kept while `anchor` is on the same line: `placed`).
    private func placement(at anchor: NSRect) -> (frame: NSRect, side: Side) {
        let size = view.contentSize
        let kept = placed.flatMap { Self.onTheSameLine($0.anchor, anchor) ? $0.side : nil }
        let (origin, side) = Self.placement(for: size, anchor: anchor, textInset: view.textInset, keeping: kept)
        return (NSRect(origin: origin, size: size), side)
    }

    /// Places the panel's top-left just below the line rect, or its bottom-left just above it when there is no room
    /// below (`keeping` `.above`, the side it is on while typing on that line: above as long as it fits there), and keeps
    /// it on the anchor's screen; with room on neither side, on the side with more, moved onto the screen. The first
    /// candidate's text starts under the caret (`textInset` from the panel's left edge).
    static func placement(for size: NSSize, anchor rawAnchor: NSRect, textInset: CGFloat = CandidateView.Metrics.textInsetX,
                          keeping kept: Side? = nil) -> (origin: NSPoint, side: Side) {
        let anchor = usable(rawAnchor)
        let screen = screen(for: anchor)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 4
        let below = anchor.minY - gap - size.height, above = anchor.maxY + gap
        let roomBelow = below >= visible.minY, roomAbove = above + size.height <= visible.maxY
        let side: Side = kept == .above && roomAbove ? .above
            : roomBelow ? .below
            : roomAbove ? .above
            : anchor.minY - visible.minY >= visible.maxY - anchor.maxY ? .below : .above
        let x = min(max(anchor.minX - textInset, visible.minX), visible.maxX - size.width)
        let y = min(max(side == .below ? below : above, visible.minY), visible.maxY - size.height)
        return (NSPoint(x: x, y: y), side)
    }

    /// Whether two caret rects are on the same line: the middle of one within the other's height.
    static func onTheSameLine(_ a: NSRect, _ b: NSRect) -> Bool {
        let (a, b) = (usable(a), usable(b))
        return b.midY >= a.minY - 1 && b.midY <= a.maxY + 1
    }

    /// `anchor`, or where the mouse is when a client reports an empty rect at the origin.
    static func usable(_ anchor: NSRect) -> NSRect {
        guard anchor.origin == .zero || !anchor.origin.x.isFinite || !anchor.origin.y.isFinite else { return anchor }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y - 18, width: 0, height: 18)
    }

    /// The screen the panel goes on for `anchor`.
    static func screen(for anchor: NSRect) -> NSScreen? {
        let anchor = usable(anchor)
        return NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
    }
}

/// Draws the candidate list: the core's `PanelModel`, with the icons as the Mac draws them (`Icon`), its caret as "▏"
/// and the choices where a conversation can go on as lines of text (`PanelModel.inputText`). Layout is computed when the
/// model changes; drawing is appearance-aware. Every list looks one way: the highlighted row a soft wash of the system's
/// accent color, the numbers on keycaps, the footer a few keys on keycaps.
final class CandidateView: NSView {
    /// An SF Symbol, drawn in `color` on a square of it, lightly tinted.
    struct Icon: Equatable {
        var symbol: String
        var color: NSColor
        /// Drawn instead of the symbol on its square: a script extension's own emoji, or image file.
        var emoji: String? = nil
        var image: String? = nil
        /// Drawn instead of the square once its icon is in (`itemIcon`): the app, folder or file a row opens (its path).
        var item: String? = nil
    }

    /// Translate as You Type's chip (「中 → 英」): the language typed and the one it translates into, each a part to click.
    typealias Chip = PanelModel.Chip
    typealias ChipPart = PanelModel.ChipPart

    enum Metrics {
        static let padding: CGFloat = 6
        static let rowInsetX: CGFloat = 8
        static let rowInsetY: CGFloat = 5
        static let labelGap: CGFloat = 10
        static let maxTextWidth: CGFloat = 520
        static let minWidth: CGFloat = 280
        static let cornerRadius: CGFloat = 16
        /// The highlighted row's corners: the panel's, less the padding (the two curves run together).
        static let rowRadius: CGFloat = 10
        static let footerGap: CGFloat = 7
        /// A row's number on its keycap: a square this big (a wider key, "Enter", as wide as it needs).
        static let keycapSize: CGFloat = 20
        static let keycapRadius: CGFloat = 6
        static let labelWidth: CGFloat = keycapSize
        static let iconSize: CGFloat = 20
        static let iconGap: CGFloat = 8
        /// Distance from the panel's left edge to where candidate text starts.
        static let textInsetX: CGFloat = padding + rowInsetX + labelWidth + labelGap
        /// Candidates in a row (`PanelModel.horizontal`): the number closer to its word, the cells apart, the widest a
        /// line gets before the next candidates go on another, and the most of a long candidate shown.
        static let cellLabelGap: CGFloat = 6
        static let cellSpacing: CGFloat = 2
        static let maxRowWidth: CGFloat = 600
        static let maxCellTextWidth: CGFloat = 280
        /// Translate as You Type's chip: the space around each part's text, and below it.
        static let chipInsetX: CGFloat = 8
        static let chipInsetY: CGFloat = 3
        static let chipGap: CGFloat = 4
        /// What a row has on its right (a tag, what ⏎ does), apart from its text; a tag's pill.
        static let trailingGap: CGFloat = 14
        static let tagInsetX: CGFloat = 7
        static let tagHeight: CGFloat = 19
        /// The small keycaps of the footer and of a row's right side, and the room between the footer's keys.
        static let smallKeycapHeight: CGFloat = 17
        static let hintGap: CGFloat = 14
        /// The sentence as typed, above the results (row 0): the room its hairline takes under it.
        static let headerRowGap: CGFloat = 5
        /// The pinyin candidates' pills (`PanelModel.candidates`).
        static let pillHeight: CGFloat = 24
        static let pillInsetX: CGFloat = 8
        static let pillGap: CGFloat = 6
        /// Between the pills and the hairline that parts them from the rows.
        static let stripGap: CGFloat = 3
        /// Rows on their way (`PanelModel.pending`): their bars, as parts of the room for the text.
        static let skeletonBars: [CGFloat] = [0.82, 0.64, 0.74]
        static let skeletonBarHeight: CGFloat = 10
    }

    enum Fonts {
        static let candidate = NSFont.systemFont(ofSize: 16)
        static let english = NSFont.systemFont(ofSize: 15)
        static let chinese = NSFont.systemFont(ofSize: 14)
        static let selectedCandidate = NSFont.systemFont(ofSize: 16, weight: .medium)
        static let selectedEnglish = NSFont.systemFont(ofSize: 15, weight: .medium)
        static let selectedChinese = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let comment = NSFont.systemFont(ofSize: 12)
        static let label = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        static let status = NSFont.systemFont(ofSize: 13)
        static let footer = NSFont.systemFont(ofSize: 12)
        static let detail = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        /// A key on the footer's keycaps, and on a row's right.
        static let key = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let chip = NSFont.systemFont(ofSize: 13, weight: .medium)
        static let tag = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let action = NSFont.systemFont(ofSize: 12, weight: .medium)
        /// An arithmetic result, and the sum before it.
        static let value = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        static let lead = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        static let pill = NSFont.systemFont(ofSize: 14)
        static let pillLabel = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        /// The text's font; the highlighted row's a little heavier (rows are measured with it: as wide either way).
        static func text(for kind: PanelModel.Row.Kind, selected: Bool = false) -> NSFont {
            switch kind {
            case .candidate: return selected ? selectedCandidate : candidate
            case .original: return selected ? selectedChinese : chinese
            case .translation: return selected ? selectedEnglish : english
            }
        }
    }

    static let background = NSColor(name: "AllInOneIMEPanelBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.16, alpha: 0.98) : NSColor(white: 0.995, alpha: 0.98)
    }

    private struct RowLayout {
        var frame: NSRect
        var textFrame: NSRect
        /// Its number's keycap (or a mark's place); empty without one.
        var labelFrame: NSRect
        var iconFrame: NSRect?
        /// A candidate in a row too long for its cell, drawn cut short with "…" (`layoutCells`); one that fits is drawn
        /// as it is, without measuring it again.
        var cut = false
        /// The middle of its first line, from the top: what is on its right is centered on it.
        var lineMidY: CGFloat
        /// The sentence as typed, drawn as a quiet line above the results (`isHeader`).
        var header = false
    }

    /// Its own solid background: off in the panel, where the system's glass is behind it (`CandidatePanel`);
    /// on for an offscreen image, which has nothing behind it to blur.
    var drawsBackground = true

    var model = PanelModel() {
        didSet {
            guard model != oldValue else { return }
            icons = model.rows.map { $0.icon.map(Icon.init) }
            // The newest rows (or the highlighted one) come into view again, unless the wheel moved a conversation up
            // from its end and only what the rows say changed (an answer coming in): they stay where the user put them.
            if !keepsScroll(from: oldValue) { scrolled = nil }
            let from = slideStart(from: oldValue)
            relayout()
            if let from { slide(from: from) }
        }
    }

    /// Whether a conversation the wheel scrolled up stays put as the model goes from `old` to `model`: the same rows
    /// with the same one picked, only their text (or the line on top, the status, the footer) changed. Scrolled back
    /// to the bottom, it follows the end again.
    private func keepsScroll(from old: PanelModel) -> Bool {
        guard let scrolled, scrolled < overflow - 0.5, model.transcript, old.transcript else { return false }
        return model.rows.count == old.rows.count && model.highlighted == old.highlighted
    }

    /// The side of the caret the panel is on (`CandidatePanel.placement`): the pinyin candidates shown with the rows
    /// (`PanelModel.candidates`) go on the side nearest it, the rows on the far side, so the word is picked first, then
    /// what to do with it: at the top below the caret (under the input line; a selection's header stays just above the
    /// rows), just above the footer above it. The panel is as big either way.
    var side: CandidatePanel.Side = .below {
        didSet { if side != oldValue, model.candidates != nil { relayout() } }
    }

    /// The tallest a conversation's panel gets (`PanelModel.transcript`); nil: no limit.
    var maxHeight: CGFloat? {
        didSet { if maxHeight != oldValue, model.transcript { relayout() } }
    }

    /// The narrowest it is laid out: while the panel shows, as wide as it has been since it came up (`CandidatePanel.show`),
    /// so rows ranked again with each key don't move its right edge in and out; the rows' highlight, the footer and the
    /// pinyin candidates' line go across all of it. 0: as wide as what it shows needs.
    var minimumWidth: CGFloat = 0 {
        didSet { if minimumWidth != oldValue, ceil(max(naturalWidth, minimumWidth)) != contentSize.width { relayout() } }
    }
    /// As wide as what it shows needs (`relayout`), `minimumWidth` aside.
    private var naturalWidth: CGFloat = 0
    /// A conversation's rows taller than fit: how far they are moved up (`rowsShift`), where they're shown
    /// (`rowsClip`), and how far the wheel moved them from where they'd be (nil: not moved).
    private(set) var rowsShift: CGFloat = 0
    private var rowsClip: NSRect?
    private var scrolled: CGFloat?

    /// A row clicked: its index in `model.rows`.
    var onSelect: ((Int) -> Void)?
    /// A row right-clicked: its index in `model.rows`.
    var onDelete: ((Int) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onChip: ((ChipPart) -> Void)?
    /// The row under the pointer, drawn lightly highlighted: what a click would pick.
    private(set) var hovered: Int? {
        didSet {
            guard hovered != oldValue else { return }
            needsDisplay = true
            onHover?(hovered)
        }
    }
    /// The pointer onto another row, or off the rows (nil): for what shows beside the panel only (`ImagePreview`); the
    /// choice and the text stay as they are.
    var onHover: ((Int?) -> Void)?
    /// The part of the chip under the pointer, drawn highlighted.
    private(set) var hoveredChip: ChipPart? {
        didSet { if hoveredChip != oldValue { needsDisplay = true } }
    }
    /// Where the chip's parts are (its source, the arrow, its target), and the whole of it.
    private(set) var chipFrames: (source: NSRect, arrow: NSRect, target: NSRect, whole: NSRect)?
    /// Scrolling not yet a whole row (a trackpad's small steps add up).
    private var pendingScroll: CGFloat = 0
    private(set) var contentSize = NSSize(width: Metrics.minWidth, height: 40)
    /// Where the first candidate's text starts, from the left edge: under the caret (`CandidatePanel.origin`).
    private(set) var textInset = Metrics.textInsetX
    private var rowLayouts: [RowLayout] = []
    /// The rows' icons as the Mac draws them (`Icon(_:)`: a symbol looked up, an image file's date read), once per model,
    /// not on each draw.
    private var icons: [Icon?] = []
    private var statusFrame: NSRect?
    private(set) var headerFrame: NSRect?
    /// Where the pinyin candidates shown with the rows are (`PanelModel.candidates`): on the side nearest the caret
    /// (`side`). Their pills, and what Space does at the line's end.
    private(set) var candidatesFrame: NSRect?
    private var pills: [(frame: NSRect, label: String, text: String)] = []
    private var inputFrame: NSRect?
    /// The rows on their way (`PanelModel.pending`): each one's place, its keycap's and its bar's.
    private var skeletons: [(frame: NSRect, keycap: NSRect?, bar: NSRect)] = []
    /// A light passing over the bars while they wait (none with Reduce Motion).
    private var shimmer: ShimmerView?
    /// Where the footer's line is, from the top.
    private(set) var footerY: CGFloat = 0

    /// The icon of the app, folder or file a row opens (`Icon.item`), from memory; nil: not in yet (it is asked for, and
    /// `itemIconsCameIn` says when it is), or none. The input method's reads `ItemIcons`; without it, the symbol.
    static var itemIcon: (String) -> NSImage? = { _ in nil }
    static let itemIconsLoaded = Notification.Name("AllInOneIMEItemIconsLoaded")
    private var itemIconsLoaded: NSObjectProtocol?

    /// The icons of `paths` came in for rows drawn with the symbol: every panel showing one draws it again.
    static func itemIconsCameIn(_ paths: Set<String>) {
        NotificationCenter.default.post(name: itemIconsLoaded, object: nil, userInfo: ["paths": paths])
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        relayout()
        // An app's, a folder's or a file's icon that came in after its row was drawn with the symbol: drawn now.
        itemIconsLoaded = NotificationCenter.default.addObserver(forName: Self.itemIconsLoaded, object: nil, queue: .main) {
            [weak self] note in
            guard let self, let paths = note.userInfo?["paths"] as? Set<String>,
                  icons.contains(where: { $0?.item.map(paths.contains) == true }) else { return }
            needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let itemIconsLoaded { NotificationCenter.default.removeObserver(itemIconsLoaded) }
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Whether it is drawn dark (Dark Mode, or a dark appearance given to it).
    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    // MARK: - Layout

    /// Whether row `index` is the sentence as typed above the results (row 0 of @improve, @translate …: "0" picks it),
    /// drawn as a quiet line of its own.
    private func isHeader(_ index: Int) -> Bool {
        index == 0 && !model.horizontal && !model.transcript && model.rows.first.map { $0.kind == .original && $0.label == "0" } == true
    }

    private func relayout() {
        let p = Metrics.padding
        var y = p
        var widest: CGFloat = 0
        rowLayouts = []
        let horizontal = model.horizontal && !model.rows.isEmpty
        // Rows one under another: their text starts after the widest keycap ("Tab", autocomplete's line), a digit's at
        // least, so a label never runs into its text; a list without numbers (one @'s) has no room for them.
        let labels = horizontal ? [] : model.rows.map { $0.label.isEmpty ? 0 : Self.keycapWidth($0.label) }
        let labelColumn = (labels.max() ?? 0) > 0 ? max(labels.max() ?? 0, Metrics.keycapSize) + Metrics.labelGap : 0
        let inset = p + Metrics.rowInsetX + labelColumn
        chipFrames = nil
        if let chip = model.chip {
            let frames = layoutChip(chip, top: y)
            chipFrames = frames
            widest = max(widest, frames.whole.maxX - inset - Metrics.rowInsetX)
            let alone = model.rows.isEmpty && model.status == .none && model.footer.isEmpty && model.inputText == nil && model.header.isEmpty
                && model.candidates == nil
            y = frames.whole.maxY + (alone ? 0 : Metrics.chipGap)
        }
        inputFrame = nil
        if let input = inputString() {
            let size = Self.measure(input, minHeight: 0)
            widest = max(widest, size.width + p + Metrics.rowInsetX - inset)
            inputFrame = NSRect(x: p + Metrics.rowInsetX, y: y + Metrics.rowInsetY, width: Metrics.maxTextWidth, height: size.height)
            y += size.height + 2 * Metrics.rowInsetY
        }
        // The pinyin candidates shown with the rows, on the side nearest the caret (`side`): a strip of pills, the y under it.
        candidatesFrame = nil
        pills = []
        let strip = model.candidates.map(layoutPills)
        func layoutCandidates(_ strip: (pills: [(frame: NSRect, label: String, text: String)], width: CGFloat), top: CGFloat) -> CGFloat {
            widest = max(widest, strip.width + p + Metrics.rowInsetX - inset)
            let origin = NSPoint(x: p + Metrics.rowInsetX, y: top + Metrics.rowInsetY)
            candidatesFrame = NSRect(origin: origin, size: NSSize(width: strip.width, height: Metrics.pillHeight + Metrics.stripGap))
            // The room between them and the rows' hairline on the rows' side.
            let dy = origin.y + (side == .below ? 0 : Metrics.stripGap)
            pills = strip.pills.map { ($0.frame.offsetBy(dx: origin.x, dy: dy), $0.label, $0.text) }
            return top + Metrics.pillHeight + Metrics.stripGap + 2 * Metrics.rowInsetY
        }
        // Below the caret: at the top, under the input line.
        if side == .below, let strip { y = layoutCandidates(strip, top: y) }
        headerFrame = nil
        if let header = headerString() {
            let size = Self.measure(header, minHeight: 0)
            widest = max(widest, size.width + p + Metrics.rowInsetX - inset)
            headerFrame = NSRect(x: p + Metrics.rowInsetX, y: y + Metrics.rowInsetY, width: Metrics.maxTextWidth, height: size.height)
            y += size.height + 2 * Metrics.rowInsetY
        }
        var cellsWidth: CGFloat = 0
        if horizontal { (y, cellsWidth) = layoutCells(top: y) }
        let rowsTop = y
        textInset = horizontal ? rowLayouts.first?.textFrame.minX ?? Metrics.textInsetX : inset
        // A column for the icons when any row has one: the text moves right by it.
        let iconColumn = model.rows.contains { $0.icon != nil } ? Metrics.iconSize + Metrics.iconGap : 0
        for (index, row) in model.rows.enumerated() where !horizontal {
            let header = isHeader(index)
            let text = rowText(row, header: header, selected: true)
            let font = row.lead != nil ? Fonts.value : Fonts.text(for: row.kind)
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            // What is on its right (a tag, what ⏎ does) has its room beside the text: the panel is wider by it.
            let trailing = trailingWidth(row, header: header)
            let size = Self.measure(text, minHeight: max(lineHeight, iconColumn > 0 ? Metrics.iconSize : 0, labelColumn > 0 ? Metrics.keycapSize : 0))
            // An arithmetic result without an icon starts where the icons are: its sum under them.
            let indent = row.lead != nil && row.icon == nil ? 0 : iconColumn
            widest = max(widest, size.width + indent + (trailing > 0 ? Metrics.trailingGap + trailing : 0))
            // Drawn as wide as the highlighted one measured (the heavier text): it wraps there, and the lighter as soon
            // or later, never further right. (A point more: laid out exactly as wide as its longest line, the text can
            // wrap once more and lose its last line.)
            // One line next to an icon or a keycap is centered on it.
            let beside = max(iconColumn > 0 ? Metrics.iconSize : 0, labelColumn > 0 ? Metrics.keycapSize : 0)
            let textY = y + Metrics.rowInsetY + (beside > lineHeight && size.height <= beside ? (beside - lineHeight) / 2 : 0)
            let textFrame = NSRect(x: inset + indent, y: textY, width: size.width + 1, height: size.height)
            let midY = textY + lineHeight / 2
            let labelFrame = row.label.isEmpty ? NSRect.zero
                : NSRect(x: p + Metrics.rowInsetX, y: (midY - Metrics.keycapSize / 2).rounded(), width: labels[index], height: Metrics.keycapSize)
            let iconFrame = row.icon.map { _ in
                NSRect(x: inset, y: (midY - Metrics.iconSize / 2).rounded(), width: Metrics.iconSize, height: Metrics.iconSize)
            }
            rowLayouts.append(RowLayout(
                frame: NSRect(x: p, y: y, width: 0, height: size.height + 2 * Metrics.rowInsetY),
                textFrame: textFrame, labelFrame: labelFrame, iconFrame: iconFrame, lineMidY: midY, header: header))
            y += size.height + 2 * Metrics.rowInsetY + (header ? Metrics.headerRowGap : 0)
        }
        // The rows on their way, under those in: a row of the results' height each.
        skeletons = []
        if !horizontal, !model.transcript, model.pending > 0 {
            let font = Fonts.english
            let height = max(ceil(font.ascender - font.descender + font.leading), labelColumn > 0 ? Metrics.keycapSize : 0) + 2 * Metrics.rowInsetY
            for _ in 0..<min(model.pending, Metrics.skeletonBars.count) {
                skeletons.append((NSRect(x: p, y: y, width: 0, height: height), nil, .zero))
                y += height
            }
        }
        let rowsBottom = y

        statusFrame = nil
        let compact = (model.rows.isEmpty || model.chip != nil) && model.footer.isEmpty
        let statusX = model.rows.isEmpty ? p + Metrics.rowInsetX : inset
        if let status = statusString() {
            let size = Self.measure(status, minHeight: 0)
            widest = max(widest, size.width + statusX - inset)
            statusFrame = NSRect(x: statusX, y: y + Metrics.rowInsetY, width: Metrics.maxTextWidth, height: size.height)
            y += size.height + 2 * Metrics.rowInsetY
        }
        // Above the caret: under the rows and the status, just above the footer.
        if side == .above, let strip { y = layoutCandidates(strip, top: y) }

        // In a row, as wide as the candidates need (and the status, the footer); in a column, at least `minWidth`.
        var width = horizontal ? max(cellsWidth, widest > 0 ? inset + widest + Metrics.rowInsetX + p : 0)
            : max(compact ? 0 : Metrics.minWidth, inset + widest + Metrics.rowInsetX + p)
        if !model.footer.isEmpty || !model.hints.isEmpty || model.note != nil {
            let footer = footerWidth()
            width = max(width, ceil(footer) + 2 * (p + Metrics.rowInsetX))
            footerY = y + Metrics.footerGap
            y = footerY + 1 + Metrics.footerGap + Metrics.smallKeycapHeight
        }
        // No narrower than it has shown since it came up (`minimumWidth`): the rows and the bars across all of it.
        naturalWidth = width
        width = max(width, minimumWidth)
        for i in rowLayouts.indices where !horizontal {
            rowLayouts[i].frame.size.width = width - 2 * p
        }
        for i in skeletons.indices {
            let midY = skeletons[i].frame.midY
            let room = width - p - Metrics.rowInsetX - inset
            skeletons[i].frame.size.width = width - 2 * p
            skeletons[i].keycap = labelColumn > 0
                ? NSRect(x: p + Metrics.rowInsetX, y: (midY - Metrics.keycapSize / 2).rounded(), width: Metrics.keycapSize, height: Metrics.keycapSize) : nil
            skeletons[i].bar = NSRect(x: inset, y: (midY - Metrics.skeletonBarHeight / 2).rounded(),
                                      width: (room * Metrics.skeletonBars[i % Metrics.skeletonBars.count]).rounded(), height: Metrics.skeletonBarHeight)
        }
        fitTranscript(height: ceil(y + p), rowsTop: rowsTop, rowsBottom: rowsBottom, width: width)
        contentSize = NSSize(width: ceil(width), height: min(ceil(y + p), ceil(y + p) - overflow))
        updateShimmer()
        needsDisplay = true
        // Other rows under a pointer that stayed put: the one there now (the pointer asked once, for both).
        let pointer = window.flatMap { $0.isVisible ? convert($0.mouseLocationOutsideOfEventStream, from: nil) : nil }
        (hovered, hoveredChip) = (pointer.flatMap(row(at:)), pointer.flatMap(chipPart(at:)))
    }

    /// The chip at the top left: its source and target parts, the arrow between them, one line.
    private func layoutChip(_ chip: Chip, top: CGFloat) -> (source: NSRect, arrow: NSRect, target: NSRect, whole: NSRect) {
        let (source, arrow, target) = chipStrings(chip)
        let height = ceil(Fonts.chip.ascender - Fonts.chip.descender + Fonts.chip.leading) + 2 * Metrics.chipInsetY
        let x = Metrics.padding + Metrics.rowInsetX - Metrics.chipInsetX
        let sourceFrame = NSRect(x: x, y: top, width: ceil(source.size().width) + 2 * Metrics.chipInsetX, height: height)
        let arrowFrame = NSRect(x: sourceFrame.maxX, y: top, width: ceil(arrow.size().width), height: height)
        let targetFrame = NSRect(x: arrowFrame.maxX, y: top, width: ceil(target.size().width) + 2 * Metrics.chipInsetX, height: height)
        return (sourceFrame, arrowFrame, targetFrame, sourceFrame.union(targetFrame))
    }

    /// The pinyin candidates ("1 你好   2 拟好 …") as pills in one line, from its left, and how wide the line is with what
    /// Space does at its end (`PanelModel.candidatesHint`): as many as fit in a row's widest text.
    private func layoutPills(_ candidates: String) -> (pills: [(frame: NSRect, label: String, text: String)], width: CGFloat) {
        let hint = model.candidatesHint.map { Metrics.trailingGap + Self.hintWidth($0) } ?? 0
        var x: CGFloat = 0
        var out: [(frame: NSRect, label: String, text: String)] = []
        for item in candidates.components(separatedBy: "   ") where !item.isEmpty {
            let parts = item.split(separator: " ", maxSplits: 1)
            let (label, text) = parts.count == 2 ? (String(parts[0]), String(parts[1])) : ("", item)
            let width = Metrics.pillInsetX * 2 + ceil(Self.pillWidth(label: label, text: text))
            let start = out.isEmpty ? 0 : x + Metrics.pillGap
            guard out.isEmpty || start + width + hint <= Metrics.maxTextWidth else { break }
            out.append((NSRect(x: start, y: 0, width: width, height: Metrics.pillHeight), label, text))
            x = start + width
        }
        return (out, x + hint)
    }

    /// How much taller than `maxHeight` a conversation's panel would be (its rows scroll instead).
    private var overflow: CGFloat = 0

    /// A conversation taller than `maxHeight`: its rows are shown between `rowsTop` and what is left above the status
    /// and footer, moved up to show the bottom of the last one, or the highlighted one when it is above (an earlier
    /// answer picked with ↑), or as far as the wheel moved them; the status, the candidates' line under them (above the
    /// caret) and the footer move up with the bottom of the panel.
    private func fitTranscript(height: CGFloat, rowsTop: CGFloat, rowsBottom: CGFloat, width: CGFloat) {
        rowsShift = 0
        rowsClip = nil
        overflow = 0
        guard model.transcript, let maxHeight, height > maxHeight, rowsBottom > rowsTop else { return }
        overflow = min(height - maxHeight, rowsBottom - rowsTop - 40)  // a few rows always show
        guard overflow > 0 else { overflow = 0; return }
        // The newest row stays at the bottom even when it's taller than the panel (its start then scrolls into view);
        // an earlier one selected above the panel's top comes down to it.
        var shift = overflow
        if let highlighted = model.highlighted, rowLayouts.indices.contains(highlighted), highlighted < rowLayouts.count - 1 {
            shift = min(shift, max(rowLayouts[highlighted].frame.minY - rowsTop, 0))
        }
        if let scrolled { shift = min(max(scrolled, 0), overflow) }
        rowsShift = shift
        rowsClip = NSRect(x: 0, y: rowsTop, width: width, height: rowsBottom - rowsTop - overflow)
        for i in rowLayouts.indices {
            rowLayouts[i].frame.origin.y -= shift
            rowLayouts[i].textFrame.origin.y -= shift
            rowLayouts[i].labelFrame.origin.y -= shift
            rowLayouts[i].iconFrame?.origin.y -= shift
            rowLayouts[i].lineMidY -= shift
        }
        statusFrame?.origin.y -= overflow
        if side == .above {
            candidatesFrame?.origin.y -= overflow
            pills = pills.map { ($0.frame.offsetBy(dx: 0, dy: -overflow), $0.label, $0.text) }
        }
        footerY -= overflow
    }

    /// The candidates side by side (`PanelModel.horizontal`), as many to a line as fit in `maxRowWidth`
    /// (`CandidateLayout.flow`): each a cell with its number's keycap and its word, one line, a long one cut short with
    /// "…". The y below them, and the panel width they need.
    private func layoutCells(top: CGFloat) -> (bottom: CGFloat, width: CGFloat) {
        let p = Metrics.padding
        let font = Fonts.candidate
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let height = max(lineHeight, Metrics.keycapSize)
        var labelWidths: [CGFloat] = [], textWidths: [CGFloat] = [], cuts: [Bool] = []
        for row in model.rows {
            let text = rowText(row, header: false, selected: true)
            labelWidths.append(row.label.isEmpty ? 0 : Self.keycapWidth(row.label) + Metrics.cellLabelGap)
            // A long one cut to fit, its cell as wide as what's left of it (no gap after the "…"); one that fits measured
            // once, as the highlighted one is drawn (a little heavier: the others are as wide).
            let width = ceil(text.size().width)
            let cut = width > Metrics.maxCellTextWidth
            textWidths.append((cut ? ceil(Self.fitted(text, width: Metrics.maxCellTextWidth).size().width) : width) + 1)
            cuts.append(cut)
        }
        let sizes = zip(labelWidths, textWidths).map {
            CGSize(width: Metrics.rowInsetX * 2 + $0 + $1, height: height + 2 * Metrics.rowInsetY)
        }
        let frames = CandidateLayout.flow(sizes, spacing: Metrics.cellSpacing, lineSpacing: Metrics.cellSpacing,
                                          maxWidth: Metrics.maxRowWidth - 2 * p)
        for (index, cell) in frames.enumerated() {
            let frame = cell.offsetBy(dx: p, dy: top)
            let midY = frame.midY
            let textFrame = NSRect(x: frame.minX + Metrics.rowInsetX + labelWidths[index], y: (midY - lineHeight / 2).rounded(),
                                   width: textWidths[index], height: lineHeight)
            let labelFrame = labelWidths[index] == 0 ? NSRect.zero
                : NSRect(x: frame.minX + Metrics.rowInsetX, y: (midY - Metrics.keycapSize / 2).rounded(),
                         width: labelWidths[index] - Metrics.cellLabelGap, height: Metrics.keycapSize)
            rowLayouts.append(RowLayout(frame: frame, textFrame: textFrame, labelFrame: labelFrame, iconFrame: nil, cut: cuts[index],
                                        lineMidY: midY))
        }
        return (top + (frames.map(\.maxY).max() ?? 0), (frames.map(\.maxX).max() ?? 0) + 2 * p)
    }

    /// `text` on one line no wider than `width`: as it is, or its longest start that fits with "…" after it (whole
    /// characters, so an emoji or a Hangul syllable isn't split).
    static func fitted(_ text: NSAttributedString, width: CGFloat) -> NSAttributedString {
        guard text.length > 0, ceil(text.size().width) > width else { return text }
        let string = text.string as NSString
        var ends: [Int] = [0]  // where each character ends, in UTF-16
        string.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byComposedCharacterSequences) {
            _, range, _, _ in ends.append(range.upperBound)
        }
        func cut(_ end: Int) -> NSAttributedString {
            // Not "word …": the space before the "…" goes.
            var end = end
            while end > 0, let scalar = Unicode.Scalar(string.character(at: end - 1)), CharacterSet.whitespaces.contains(scalar) { end -= 1 }
            let out = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: end)))
            out.append(NSAttributedString(string: "…", attributes: text.attributes(at: max(end - 1, 0), effectiveRange: nil)))
            return out
        }
        // The most characters that fit with the "…" (none at least).
        var low = 0, high = ends.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if ceil(cut(ends[mid]).size().width) <= width { low = mid } else { high = mid - 1 }
        }
        return cut(ends[low])
    }

    private static func measure(_ text: NSAttributedString, minHeight: CGFloat) -> NSSize {
        let rect = text.boundingRect(
            with: NSSize(width: Metrics.maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSSize(width: ceil(rect.width), height: max(ceil(rect.height), minHeight))
    }

    /// How wide `text` is in `font` (one of `Fonts`): the small words measured again and again with each key (keys,
    /// numbers, what ⏎ does, tags, pills) kept, a few hundred at most.
    private static func width(_ text: String, _ font: NSFont) -> CGFloat {
        let key = MeasuredText(text: text, font: ObjectIdentifier(font))
        if let width = measured[key] { return width }
        if measured.count > 400 { measured.removeAll(keepingCapacity: true) }
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        measured[key] = width
        return width
    }

    private struct MeasuredText: Hashable {
        var text: String
        var font: ObjectIdentifier
    }
    private static var measured: [MeasuredText: CGFloat] = [:]

    /// A pinyin candidate's pill text: its number, small, and its word on one baseline, drawn as one.
    private static func pillText(label: String, text: String, labelColor: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if !label.isEmpty {
            out.append(NSAttributedString(string: label, attributes: [.font: Fonts.pillLabel, .foregroundColor: labelColor]))
            out.append(NSAttributedString(string: " ", attributes: [.font: Fonts.pillLabel, .kern: 1.5]))
        }
        out.append(NSAttributedString(string: text, attributes: [.font: Fonts.pill, .foregroundColor: NSColor.labelColor]))
        return out
    }

    /// How wide a pill's text is (`pillText`), kept as `width` keeps small words.
    private static func pillWidth(label: String, text: String) -> CGFloat {
        let key = MeasuredText(text: label + "\u{1}" + text, font: ObjectIdentifier(Fonts.pill))
        if let width = measured[key] { return width }
        let width = pillText(label: label, text: text, labelColor: .labelColor).size().width
        measured[key] = width
        return width
    }

    /// Whether a row's label is a key ("1", "0", "⏎", "Tab"), drawn on a keycap, rather than a mark ("✓", "›").
    private static func isKey(_ label: String) -> Bool {
        guard let first = label.first else { return false }
        return first.isNumber || first.isLetter || "⏎↩⌘⌥⇧⌃".contains(first)
    }

    /// The width a row's label takes: a keycap at least square, a mark as wide as it is.
    private static func keycapWidth(_ label: String) -> CGFloat {
        let text = ceil(width(label, Fonts.label))
        return isKey(label) ? max(Metrics.keycapSize, text + 10) : max(Metrics.keycapSize, text)
    }

    /// A small keycap's width for `key` (the footer's, a row's right side's).
    private static func smallKeycapWidth(_ key: String) -> CGFloat {
        max(Metrics.smallKeycapHeight, ceil(width(key, Fonts.key)) + 10)
    }

    /// A footer hint's width: its keycap, the room after it, its words.
    private static func hintWidth(_ hint: PanelModel.Hint) -> CGFloat {
        (hint.key.isEmpty ? 0 : smallKeycapWidth(hint.key) + (hint.text.isEmpty ? 0 : 5)) + ceil(width(hint.text, Fonts.footer))
    }

    /// What row `row` has on its right, and how wide: the sentence as typed its key and what it does ("0 保留原文"), a
    /// tag its pill, one @'s rows what ⏎ does ("打开 ⏎", drawn on the highlighted one; room for it on each).
    private func trailingWidth(_ row: PanelModel.Row, header: Bool) -> CGFloat {
        if header {
            return row.action.map { Self.smallKeycapWidth(row.label) + 5 + ceil(Self.width($0, Fonts.comment)) } ?? 0
        }
        if let tag = row.tag { return ceil(Self.width(tag.text, Fonts.tag)) + 2 * Metrics.tagInsetX }
        if let action = row.action { return ceil(Self.width(action, Fonts.action)) + 5 + Self.smallKeycapWidth("⏎") }
        return 0
    }

    // MARK: - Strings

    /// A row's text as drawn: the text (an arithmetic result large, after its sum), the caret while it's coming in, and
    /// the comment, small, after it (but what a tag, the header's look or ⏎'s word says already).
    private func rowText(_ row: PanelModel.Row, header: Bool, selected: Bool) -> NSAttributedString {
        let primary: NSColor = header || row.kind == .original ? .secondaryLabelColor : .labelColor
        let font = Fonts.text(for: row.kind, selected: selected)
        let text = NSMutableAttributedString()
        if let lead = row.lead {
            text.append(NSAttributedString(string: lead + " =  ", attributes: [.font: Fonts.lead, .foregroundColor: NSColor.secondaryLabelColor]))
            let value = row.text.hasPrefix("= ") ? String(row.text.dropFirst(2)) : row.text
            text.append(NSAttributedString(string: value, attributes: [.font: Fonts.value, .foregroundColor: NSColor.labelColor]))
        } else {
            text.append(NSAttributedString(string: row.text, attributes: [.font: font, .foregroundColor: primary]))
        }
        if !row.isComplete {
            text.append(NSAttributedString(string: row.text.isEmpty ? "▍" : " ▍", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        let comment = shownComment(row, header: header)
        if !comment.isEmpty {
            // No-break spaces and word joiners: when the line wraps, the comment ("黑话", jargon) moves as one
            // piece together with the last word instead of breaking between its characters.
            let glued = "\u{00A0}\u{00A0}" + comment.map(String.init).joined(separator: "\u{2060}")
            text.append(NSAttributedString(string: glued, attributes: [.font: Fonts.comment, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        return text
    }

    /// The part of a row's comment drawn after its text: none on the sentence as typed (its look says it), beside an
    /// arithmetic result (what ⏎ does is said), nor a built-in command's summary in the one @ list (its name says
    /// enough); what follows its tag ("黑话 · …").
    private func shownComment(_ row: PanelModel.Row, header: Bool) -> String {
        if header || row.lead != nil || row.commentDescribes { return "" }
        guard let tag = row.tag, row.comment.hasPrefix(tag.text) else { return row.comment }
        let rest = row.comment.dropFirst(tag.text.count)
        return String(rest.hasPrefix(" · ") ? rest.dropFirst(3) : rest)
    }

    private func chipStrings(_ chip: Chip) -> (source: NSAttributedString, arrow: NSAttributedString, target: NSAttributedString) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Fonts.chip, .foregroundColor: NSColor.labelColor]
        return (NSAttributedString(string: chip.source, attributes: attributes),
                NSAttributedString(string: "→", attributes: [.font: Fonts.chip, .foregroundColor: NSColor.secondaryLabelColor]),
                NSAttributedString(string: chip.target, attributes: attributes))
    }

    private func inputString() -> NSAttributedString? {
        model.inputText.map { NSAttributedString(string: $0, attributes: [.font: Fonts.candidate, .foregroundColor: NSColor.labelColor]) }
    }

    private func headerString() -> NSAttributedString? {
        model.headerText.map {
            NSAttributedString(string: $0, attributes: [.font: Fonts.comment, .foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    private func statusString() -> NSAttributedString? {
        switch model.status {
        case .none:
            return nil
        case let .loading(text):
            // Rows held for what is coming say it already (and the footer who writes them).
            guard model.pending == 0 || model.transcript else { return nil }
            return NSAttributedString(string: text, attributes: [
                .font: Fonts.status, .foregroundColor: NSColor.secondaryLabelColor,
            ])
        case let .hint(text):
            return NSAttributedString(string: text, attributes: [
                .font: Fonts.status, .foregroundColor: NSColor.labelColor,
            ])
        case .list:
            return NSAttributedString(string: model.statusText ?? "", attributes: [
                .font: Fonts.status, .foregroundColor: NSColor.labelColor,
            ])
        case let .error(message):
            return NSAttributedString(string: "⚠︎ \(message)", attributes: [
                .font: Fonts.status, .foregroundColor: NSColor.systemRed,
            ])
        }
    }

    /// The footer as drawn (`PanelModel.footerHints`): a note, a few keys on keycaps with their words, the detail on the
    /// right; or, when it names no key, its words as they are. Read from the model as it is laid out.
    private var footerParts: (note: String?, hints: [PanelModel.Hint], plain: String?) = (nil, [], nil)

    private func footerWidth() -> CGFloat {
        let (note, hints) = model.footerHints
        footerParts = hints.isEmpty && note == nil ? (nil, [], model.footer.isEmpty ? nil : model.footer) : (note, hints, nil)
        let parts = footerParts
        var width = parts.plain.map { ceil(Self.width($0, Fonts.footer)) } ?? 0
        width += parts.note.map { ceil(Self.width($0, Fonts.footer)) + Metrics.hintGap } ?? 0
        width += parts.hints.map(Self.hintWidth).reduce(0, +) + CGFloat(max(parts.hints.count - 1, 0)) * Metrics.hintGap
        width += model.detail.map { ceil(Self.width($0, Fonts.detail)) + 16 } ?? 0
        return width
    }

    // MARK: - Drawing

    /// The accent color as text (`accentInk`), for the drawing under way.
    private var ink = NSColor.controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        let dark = isDark
        let accent = NSColor.controlAccentColor
        ink = Self.accentInk(dark: dark)
        let shape = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: Metrics.cornerRadius - 0.25, yRadius: Metrics.cornerRadius - 0.25)
        if drawsBackground {
            Self.background.setFill()
            shape.fill()
        }

        if let chip = model.chip, let frames = chipFrames {
            // A pill, as the system's tokens; the part under the pointer a little stronger: each is a button.
            let radius = frames.whole.height / 2
            accent.withAlphaComponent(dark ? 0.24 : 0.12).setFill()
            NSBezierPath(roundedRect: frames.whole, xRadius: radius, yRadius: radius).fill()
            if let part = hoveredChip {
                accent.withAlphaComponent(dark ? 0.34 : 0.2).setFill()
                NSBezierPath(roundedRect: part == .source ? frames.source : frames.target, xRadius: radius, yRadius: radius).fill()
            }
            let (source, arrow, target) = chipStrings(chip)
            for (text, frame) in [(source, frames.source), (arrow, frames.arrow), (target, frames.target)] {
                let size = text.size()
                text.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            }
        }
        let lineInset = Metrics.padding + Metrics.rowInsetX
        if let inputFrame, let input = inputString() {
            input.draw(with: inputFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            // Under it, a line as under a text being typed.
            Self.hairline(y: inputFrame.maxY + Metrics.rowInsetY - 0.5, from: lineInset, to: bounds.width - lineInset)
        }
        if let headerFrame, let header = headerString() {
            header.draw(with: headerFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        NSGraphicsContext.saveGraphicsState()
        if let rowsClip { NSBezierPath(rect: rowsClip).addClip() }
        // In a row, the highlight is a pill around the candidate, as in macOS's own panel; in a column a rounded wash.
        func radius(_ frame: NSRect) -> CGFloat { model.horizontal ? frame.height / 2 : Metrics.rowRadius }
        if let index = hovered, index != model.highlighted, rowLayouts.indices.contains(index) {
            let frame = rowLayouts[index].frame
            accent.withAlphaComponent(dark ? 0.12 : 0.07).setFill()
            NSBezierPath(roundedRect: frame, xRadius: radius(frame), yRadius: radius(frame)).fill()
        }
        // Selected: what the key that picks takes. Moving, it slides there from the row it was on.
        if let index = model.highlighted, rowLayouts.indices.contains(index) {
            let frame = slidingFrame(to: rowLayouts[index].frame)
            accent.withAlphaComponent(dark ? 0.28 : 0.14).setFill()
            NSBezierPath(roundedRect: frame, xRadius: radius(frame), yRadius: radius(frame)).fill()
        }
        for (index, layout) in rowLayouts.enumerated() where index < model.rows.count {
            drawRow(model.rows[index], index: index, layout: layout, dark: dark)
        }
        for skeleton in skeletons {
            let fill = NSColor.labelColor.withAlphaComponent(dark ? 0.1 : 0.07)
            fill.setFill()
            if let keycap = skeleton.keycap {
                NSBezierPath(roundedRect: keycap, xRadius: Metrics.keycapRadius, yRadius: Metrics.keycapRadius).fill()
            }
            let bar = skeleton.bar
            NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if let statusFrame, let status = statusString() {
            status.draw(with: statusFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        if let candidatesFrame { drawPills(in: candidatesFrame, dark: dark) }

        if !model.footer.isEmpty || !model.hints.isEmpty || model.note != nil { drawFooter(dark: dark) }

        // Its edge: a hairline, over the glass's own.
        (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.1)).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }

    /// A row: its keycap (or mark), icon and text, and what it has on its right.
    private func drawRow(_ row: PanelModel.Row, index: Int, layout: RowLayout, dark: Bool) {
        let highlighted = index == model.highlighted
        let accent = NSColor.controlAccentColor
        if layout.header {
            // The sentence as typed: a return arrow in place of its number, a hairline under it.
            if layout.labelFrame.width > 0 { Self.drawSymbol("arrow.turn.down.left", in: layout.labelFrame, pointSize: 11, color: .secondaryLabelColor, dark: dark) }
            let lineY = layout.frame.maxY + Metrics.headerRowGap / 2
            Self.hairline(y: lineY - 0.25, from: layout.frame.minX + Metrics.rowInsetX, to: layout.frame.maxX - Metrics.rowInsetX)
        } else if !row.label.isEmpty {
            if Self.isKey(row.label) {
                let fill = highlighted ? accent : NSColor.labelColor.withAlphaComponent(dark ? 0.1 : 0.06)
                Self.drawKeycap(row.label, in: layout.labelFrame, font: Fonts.label, radius: Metrics.keycapRadius, fill: fill,
                                textColor: highlighted ? .white : .secondaryLabelColor)
            } else {
                let mark = NSAttributedString(string: row.label, attributes: [.font: Fonts.label, .foregroundColor: NSColor.secondaryLabelColor])
                let size = mark.size()
                mark.draw(at: NSPoint(x: layout.labelFrame.midX - size.width / 2, y: layout.labelFrame.midY - size.height / 2))
            }
        }
        if icons.indices.contains(index), let icon = icons[index], let frame = layout.iconFrame { Self.draw(icon, in: frame, dark: dark) }
        let text = rowText(row, header: layout.header, selected: highlighted)
        // A candidate in a row keeps to its one line, cut short with "…" where it was measured too long (`layoutCells`).
        if layout.cut {
            Self.fitted(text, width: Metrics.maxCellTextWidth).draw(with: layout.textFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
        } else {
            text.draw(with: layout.textFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        guard !model.horizontal else { return }
        let right = layout.frame.maxX - Metrics.rowInsetX
        if layout.header, let action = row.action {
            // Its key and what it does, quietly on the right: "0 保留原文".
            let word = NSAttributedString(string: action, attributes: [.font: Fonts.comment, .foregroundColor: NSColor.secondaryLabelColor])
            let size = word.size()
            word.draw(at: NSPoint(x: right - size.width, y: layout.lineMidY - size.height / 2))
            let keyWidth = Self.smallKeycapWidth(row.label)
            let key = NSRect(x: right - size.width - 5 - keyWidth, y: (layout.lineMidY - Metrics.smallKeycapHeight / 2).rounded(),
                             width: keyWidth, height: Metrics.smallKeycapHeight)
            Self.drawKeycap(row.label, in: key, font: Fonts.key, radius: 4.5,
                            fill: highlighted ? accent : NSColor.labelColor.withAlphaComponent(dark ? 0.1 : 0.06),
                            textColor: highlighted ? .white : .secondaryLabelColor)
        } else if let tag = row.tag {
            let (fill, ink) = Self.tagColors(tag.tint, dark: dark)
            let label = NSAttributedString(string: tag.text, attributes: [.font: Fonts.tag, .foregroundColor: ink])
            let size = label.size()
            let pill = NSRect(x: right - ceil(size.width) - 2 * Metrics.tagInsetX, y: (layout.lineMidY - Metrics.tagHeight / 2).rounded(),
                              width: ceil(size.width) + 2 * Metrics.tagInsetX, height: Metrics.tagHeight)
            fill.setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            label.draw(at: NSPoint(x: pill.minX + Metrics.tagInsetX, y: pill.midY - size.height / 2))
        } else if highlighted, let action = row.action {
            // What ⏎ does here, in the accent color: "打开 ⏎".
            let keyWidth = Self.smallKeycapWidth("⏎")
            let key = NSRect(x: right - keyWidth, y: (layout.lineMidY - Metrics.smallKeycapHeight / 2).rounded(),
                             width: keyWidth, height: Metrics.smallKeycapHeight)
            Self.drawKeycap("⏎", in: key, font: Fonts.key, radius: 4.5, fill: accent.withAlphaComponent(dark ? 0.22 : 0.12),
                            textColor: ink, stroke: accent.withAlphaComponent(0.45))
            let word = NSAttributedString(string: action, attributes: [.font: Fonts.action, .foregroundColor: ink])
            let size = word.size()
            word.draw(at: NSPoint(x: key.minX - 5 - size.width, y: layout.lineMidY - size.height / 2))
        }
    }

    /// The pinyin candidates' pills, the first (what Space picks) in the accent's tint, what Space does at the end of
    /// the line, and a hairline between them and the rows.
    private func drawPills(in frame: NSRect, dark: Bool) {
        let accent = NSColor.controlAccentColor
        let lineInset = Metrics.padding + Metrics.rowInsetX
        for (index, pill) in pills.enumerated() {
            let first = index == 0
            (first ? accent.withAlphaComponent(dark ? 0.28 : 0.14) : NSColor.labelColor.withAlphaComponent(dark ? 0.08 : 0.05)).setFill()
            NSBezierPath(roundedRect: pill.frame, xRadius: 8, yRadius: 8).fill()
            let text = Self.pillText(label: pill.label, text: pill.text, labelColor: first ? ink : .tertiaryLabelColor)
            let height = ceil(Fonts.pill.ascender - Fonts.pill.descender)
            text.draw(at: NSPoint(x: pill.frame.minX + Metrics.pillInsetX, y: pill.frame.midY - height / 2))
        }
        if let hint = model.candidatesHint, let first = pills.first {
            let width = Self.hintWidth(hint)
            drawHint(hint, at: NSPoint(x: bounds.width - lineInset - width, y: first.frame.midY), dark: dark)
        }
        // Halfway between the pills and the rows.
        let y = side == .below ? frame.maxY + (Metrics.rowInsetY - Metrics.stripGap) / 2 : frame.minY - (Metrics.rowInsetY - Metrics.stripGap) / 2
        Self.hairline(y: y - 0.25, from: lineInset, to: bounds.width - lineInset)
    }

    /// The footer: a hairline, then its keys on keycaps (after the note, when there is one, on the right) or its words,
    /// and the detail on the right.
    private func drawFooter(dark: Bool) {
        let inset = Metrics.padding + Metrics.rowInsetX
        Self.hairline(y: footerY, from: inset, to: bounds.width - inset)
        let midY = footerY + 1 + Metrics.footerGap + Metrics.smallKeycapHeight / 2
        var right = bounds.width - inset
        if let detail = model.detail {
            let text = NSAttributedString(string: detail, attributes: [.font: Fonts.detail, .foregroundColor: NSColor.secondaryLabelColor])
            let size = text.size()
            text.draw(at: NSPoint(x: right - size.width, y: midY - size.height / 2))
            right -= ceil(size.width) + 16
        }
        let parts = footerParts
        if let plain = parts.plain {
            let text = NSAttributedString(string: plain, attributes: [.font: Fonts.footer, .foregroundColor: NSColor.secondaryLabelColor])
            text.draw(at: NSPoint(x: inset, y: midY - text.size().height / 2))
            return
        }
        var x = inset
        if let note = parts.note {
            let text = NSAttributedString(string: note, attributes: [.font: Fonts.footer, .foregroundColor: NSColor.secondaryLabelColor])
            text.draw(at: NSPoint(x: x, y: midY - text.size().height / 2))
            // Its keys on the right.
            x = right - (parts.hints.map(Self.hintWidth).reduce(0, +) + CGFloat(max(parts.hints.count - 1, 0)) * Metrics.hintGap)
        }
        for hint in parts.hints {
            drawHint(hint, at: NSPoint(x: x, y: midY), dark: dark)
            x += Self.hintWidth(hint) + Metrics.hintGap
        }
    }

    /// A key on a small keycap with its words after it, from `origin.x`, centered on `origin.y`.
    private func drawHint(_ hint: PanelModel.Hint, at origin: NSPoint, dark: Bool) {
        var x = origin.x
        if !hint.key.isEmpty {
            let width = Self.smallKeycapWidth(hint.key)
            let key = NSRect(x: x, y: (origin.y - Metrics.smallKeycapHeight / 2).rounded(), width: width, height: Metrics.smallKeycapHeight)
            Self.drawKeycap(hint.key, in: key, font: Fonts.key, radius: 4.5, fill: NSColor.labelColor.withAlphaComponent(dark ? 0.06 : 0.03),
                            textColor: .secondaryLabelColor, stroke: NSColor.labelColor.withAlphaComponent(dark ? 0.28 : 0.2))
            x += width + 5
        }
        let text = NSAttributedString(string: hint.text, attributes: [.font: Fonts.footer, .foregroundColor: NSColor.secondaryLabelColor])
        text.draw(at: NSPoint(x: x, y: origin.y - text.size().height / 2))
    }

    /// `key` centered on a rounded square (`frame`), filled, and outlined with a hairline when `stroke` is given.
    private static func drawKeycap(_ key: String, in frame: NSRect, font: NSFont, radius: CGFloat, fill: NSColor, textColor: NSColor,
                                   stroke: NSColor? = nil) {
        let shape = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        fill.setFill()
        shape.fill()
        if let stroke {
            stroke.setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
        }
        let text = NSAttributedString(string: key, attributes: [.font: font, .foregroundColor: textColor])
        let size = text.size()
        text.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }

    /// A hairline across, at `y`.
    private static func hairline(y: CGFloat, from left: CGFloat, to right: CGFloat) {
        NSColor.separatorColor.setFill()
        NSRect(x: left, y: y, width: right - left, height: 0.5).fill()
    }

    /// The accent color as text: a little darker on light, lighter on dark, to read on its own tint.
    private static func accentInk(dark: Bool) -> NSColor {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        return dark ? accent.blended(withFraction: 0.25, of: .white) ?? accent : accent.blended(withFraction: 0.2, of: .black) ?? accent
    }

    /// A tag's pill and its text: a style's own hue (orange polish, green concise, indigo formal), lightly tinted, its
    /// words darker in it; any other in gray.
    private static func tagColors(_ tint: String, dark: Bool) -> (fill: NSColor, ink: NSColor) {
        if let colors = tagColorsMade[TagTint(tint: tint, dark: dark)] { return colors }
        let colors = makeTagColors(tint, dark: dark)
        tagColorsMade[TagTint(tint: tint, dark: dark)] = colors
        return colors
    }

    private struct TagTint: Hashable {
        var tint: String
        var dark: Bool
    }
    private static var tagColorsMade: [TagTint: (fill: NSColor, ink: NSColor)] = [:]

    private static func makeTagColors(_ tint: String, dark: Bool) -> (fill: NSColor, ink: NSColor) {
        let hue: NSColor? = switch tint {
        case "POLISH": .systemOrange
        case "CONCISE": .systemGreen
        case "FORMAL": .systemIndigo
        default: nil
        }
        guard let hue = hue?.usingColorSpace(.sRGB) else {
            return (NSColor.labelColor.withAlphaComponent(dark ? 0.1 : 0.06), .secondaryLabelColor)
        }
        let ink = dark ? hue.blended(withFraction: 0.3, of: .white) ?? hue : hue.blended(withFraction: 0.42, of: .black) ?? hue
        return (hue.withAlphaComponent(dark ? 0.24 : 0.14), ink)
    }

    /// An SF Symbol in `color`, centered in `frame`.
    private static func drawSymbol(_ name: String, in frame: NSRect, pointSize: CGFloat, color: NSColor, dark: Bool) {
        guard let image = symbol(name, pointSize: pointSize, color: color, dark: dark) else { return }
        let size = image.size
        image.draw(in: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// A symbol in its color on a lightly tinted rounded square of it (a missing symbol: a generic one), an emoji, an
    /// image, or the icon of the app, folder or file a row opens, from memory (`itemIcon`: until it is in, the symbol, and
    /// it is asked for).
    static func draw(_ icon: Icon, in frame: NSRect, dark: Bool = false) {
        if let path = icon.item, let image = itemIcon(path) {
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        if let path = icon.image, let image = CommandIcons.image(path) {
            // Kept as it is shaped (clipboard history's thumbnails: a screenshot is wide), centered in the square.
            let size = image.size
            let scale = size.width > 0 && size.height > 0 ? min(frame.width / size.width, frame.height / size.height) : 1
            let fitted = NSSize(width: size.width * scale, height: size.height * scale)
            let rect = NSRect(x: frame.midX - fitted.width / 2, y: frame.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        if let emoji = icon.emoji {
            let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: frame.height * 0.8)])
            let size = text.size()
            text.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            return
        }
        icon.color.withAlphaComponent(dark ? 0.26 : 0.15).setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.width * 0.28, yRadius: frame.height * 0.28).fill()
        guard let image = symbol(icon.symbol, pointSize: frame.height * 0.52, color: icon.color, dark: dark, inked: true)
                ?? symbol("command", pointSize: frame.height * 0.52, color: icon.color, dark: dark, inked: true) else { return }
        let size = image.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        image.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
    }

    private struct SymbolKey: Hashable {
        var name: String
        var pointSize: CGFloat
        var color: NSColor
        var dark: Bool
        var inked: Bool
    }
    private static var symbols: [SymbolKey: NSImage] = [:]

    /// An SF Symbol in `color` (`inked`: a little darker on light, lighter on dark, as on an icon's tinted square), made
    /// once for each appearance: drawn with each key, it isn't looked up and colored again. Nil: no such symbol.
    private static func symbol(_ name: String, pointSize: CGFloat, color: NSColor, dark: Bool, inked: Bool = false) -> NSImage? {
        let key = SymbolKey(name: name, pointSize: pointSize, color: color, dark: dark, inked: inked)
        if let image = symbols[key] { return image }
        var ink = color
        if inked, let rgb = color.usingColorSpace(.sRGB) {
            ink = (dark ? rgb.blended(withFraction: 0.15, of: .white) : rgb.blended(withFraction: 0.22, of: .black)) ?? rgb
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            return nil
        }
        if symbols.count > 200 { symbols.removeAll(keepingCapacity: true) }
        symbols[key] = image
        return image
    }

    // MARK: - Motion

    /// Whether motion is off (Accessibility → Display → Reduce motion).
    static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The highlight sliding from one row to another (↑↓, the wheel): where it was, and since when; nil: still.
    private var sliding: (from: NSRect, start: CFTimeInterval)?
    private var slideLink: CADisplayLink?
    static let slideDuration: CFTimeInterval = 0.08

    /// Where the highlight slides from as the model goes from `old` to `model`: the same rows on screen, another one
    /// highlighted. Nil: it is drawn where it is at once (a new list, a panel not on screen, Reduce Motion).
    private func slideStart(from old: PanelModel) -> NSRect? {
        guard let from = old.highlighted, let to = model.highlighted, from != to, rowLayouts.indices.contains(from),
              old.rows == model.rows, old.horizontal == model.horizontal, window?.isVisible == true, window?.alphaValue ?? 0 > 0,
              !Self.reducesMotion else { return nil }
        return sliding.map { slidingFrame(to: rowLayouts[from].frame, at: $0) } ?? rowLayouts[from].frame
    }

    /// The highlight, sliding toward `target` (eased, `slideDuration`), or there.
    private func slidingFrame(to target: NSRect, at state: (from: NSRect, start: CFTimeInterval)? = nil) -> NSRect {
        guard let (from, start) = state ?? sliding else { return target }
        let t = min(max((CACurrentMediaTime() - start) / Self.slideDuration, 0), 1)
        let eased = CGFloat(1 - pow(1 - t, 3))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * eased }
        return NSRect(x: mix(from.minX, target.minX), y: mix(from.minY, target.minY),
                      width: mix(from.width, target.width), height: mix(from.height, target.height))
    }

    /// Starts the highlight's slide from `frame`, drawn again with each frame of the display until it is there.
    private func slide(from frame: NSRect) {
        sliding = (frame, CACurrentMediaTime())
        guard slideLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(slideStep))
        link.add(to: .main, forMode: .common)
        slideLink = link
    }

    @objc private func slideStep(_ link: CADisplayLink) {
        needsDisplay = true
        guard let sliding, CACurrentMediaTime() - sliding.start >= Self.slideDuration else { return }
        self.sliding = nil
        link.invalidate()
        slideLink = nil
    }

    /// The light passing over the bars of rows on their way: on while there are some, the panel on screen, and motion on.
    private func updateShimmer() {
        let bars = skeletons.map(\.bar).filter { $0.width > 0 }
        guard !bars.isEmpty, !Self.reducesMotion else {
            shimmer?.removeFromSuperview()
            shimmer = nil
            return
        }
        let area = bars.reduce(bars[0]) { $0.union($1) }
        let view = shimmer ?? ShimmerView()
        if shimmer == nil {
            addSubview(view)
            shimmer = view
        }
        view.frame = area
        view.update(bars: bars.map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }, dark: isDark)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if shimmer != nil { updateShimmer() }
    }

    // MARK: - Mouse

    override func scrollWheel(with event: NSEvent) {
        // A conversation taller than the panel: its rows scroll here, by the points the wheel or trackpad moved.
        if rowsClip != nil {
            let points = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 24
            scrolled = min(max((scrolled ?? rowsShift) - points, 0), overflow)
            relayout()
            onScroll?(0)  // the pointer on the panel all the same, not in the field (`SessionEvent.scroll`)
            return
        }
        // A row per notch of a wheel; a trackpad adds up its small steps (about a row per 24 points). Every event is told,
        // one short of a row as 0 (a trackpad's small steps, its momentum after the last row): none of them is the pointer
        // used in the field.
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 24 : event.scrollingDeltaY
        pendingScroll -= delta  // content up = further down the list
        let rows = Int(pendingScroll.rounded(.towardZero))
        pendingScroll -= CGFloat(rows)
        onScroll?(rows)
    }

    /// Row `index`'s place, from the view's top left (the highlight's, not sliding); nil: no such row.
    func rowFrame(_ index: Int) -> NSRect? {
        rowLayouts.indices.contains(index) ? rowLayouts[index].frame : nil
    }

    /// The row a click at `point` picks (`CandidateLayout.row`).
    private func row(at point: NSPoint) -> Int? {
        guard bounds.contains(point), rowsClip?.contains(point) ?? true else { return nil }
        return CandidateLayout.row(at: point, frames: rowLayouts.map(\.frame), pickable: model.rows.map(\.pickable))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Always: the panel is never key, and the input method's app is never active.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// The part of the chip at `point`, if any (the arrow between them is neither).
    func chipPart(at point: NSPoint) -> ChipPart? {
        guard let frames = chipFrames else { return nil }
        return frames.source.contains(point) ? .source : frames.target.contains(point) ? .target : nil
    }

    private func hover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        (hovered, hoveredChip) = (row(at: point), chipPart(at: point))
    }

    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseExited(with event: NSEvent) { (hovered, hoveredChip) = (nil, nil) }

    /// A click picks the row as its digit would (`Composer.choose`), or a part of the chip (`onChip`); the text field
    /// keeps the focus, the panel being non-activating and never key.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let part = chipPart(at: point) {
            onChip?(part)
        } else if let index = row(at: point) {
            // A Control-click is a right-click.
            if event.modifierFlags.contains(.control) { onDelete?(index) } else { onSelect?(index) }
        }
    }

    /// A right-click deletes the row's candidate (`onDelete`), as ⌃⌦ deletes the highlighted one.
    override func rightMouseDown(with event: NSEvent) {
        guard let index = row(at: convert(event.locationInWindow, from: nil)) else { return }
        onDelete?(index)
    }
}

/// A light passing over the bars of rows on their way (`PanelModel.pending`), left to right, again and again: Core
/// Animation's, so the main thread (the keys) isn't asked for it. Drawn over the bars, which the panel draws; nothing to
/// click (clicks go to the panel), and nothing in an offscreen image.
private final class ShimmerView: NSView {
    private let gradient = CAGradientLayer()
    private let mask = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.mask = mask
        layer?.addSublayer(gradient)
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.6, -0.3, 0]
        sweep.toValue = [1, 1.3, 1.6]
        sweep.duration = 1.4
        sweep.repeatCount = .infinity
        gradient.add(sweep, forKey: "sweep")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The bars, in its own coordinates from its top left, and the light's color for the appearance.
    func update(bars: [NSRect], dark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let light = NSColor.white.withAlphaComponent(dark ? 0.1 : 0.55).cgColor, clear = NSColor.white.withAlphaComponent(0).cgColor
        gradient.colors = [clear, light, clear]
        let path = CGMutablePath()
        let flipped = gradient.contentsAreFlipped()
        for bar in bars {
            // Unless the layers are flipped, their y goes up: the bar's from the bottom.
            let rect = CGRect(x: bar.minX, y: flipped ? bar.minY : bounds.height - bar.maxY, width: bar.width, height: bar.height)
            path.addRoundedRect(in: rect, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2)
        }
        mask.path = path
        CATransaction.commit()
    }
}

extension PanelModel {
    /// What the Mac draws on top, in the input line's font: where a conversation can go on, its title and its choices as
    /// lines of text (up to 4 on a line, more 3 a line, so the panel stays as wide), then the line of input with "▏" at
    /// its caret. Nil: neither.
    var inputText: String? {
        var lines: [String] = []
        if let handoff {
            let labels = handoff.choices.map { $0.shortcut + " " + $0.name }
            let perLine = labels.count <= 4 ? 4 : 3
            lines.append(handoff.title)
            lines.append(stride(from: 0, to: labels.count, by: perLine)
                .map { labels[$0..<min($0 + perLine, labels.count)].joined(separator: "   ") }.joined(separator: "\n"))
        }
        if let input {
            let text = input.caret.map { String(input.text.prefix($0)) + "▏" + String(input.text.dropFirst($0)) } ?? input.text
            lines.append(input.prompt + text)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The header's lines as the Mac draws them, one under the other; nil without.
    var headerText: String? { header.isEmpty ? nil : header.joined(separator: "\n") }

    /// The status's text as the Mac draws it (a list's items under it, after "· "); nil without one. An error's, without
    /// its "⚠︎".
    var statusText: String? {
        switch status {
        case .none: return nil
        case let .loading(text), let .hint(text), let .error(text): return text
        case let .list(title, items): return title + "\n" + items.map { "· " + $0 }.joined(separator: "\n")
        }
    }
}

private extension NSImage {
    func with(_ change: (NSImage) -> Void) -> NSImage {
        change(self)
        return self
    }
}
