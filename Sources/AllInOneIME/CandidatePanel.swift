import AllInOneIMECore
import AppKit

/// Borderless, non-activating floating panel shown under the insertion point.
final class CandidatePanel: NSPanel {
    static let shared = CandidatePanel()

    /// The input controller currently showing the panel.
    weak var owner: AnyObject?
    let view = CandidateView()

    var onSelect: ((Int) -> Void)? {
        get { view.onSelect }
        set { view.onSelect = newValue }
    }

    /// The scroll wheel or trackpad over the panel: rows to move (down is positive).
    var onScroll: ((Int) -> Void)? {
        get { view.onScroll }
        set { view.onScroll = newValue }
    }

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
    private static func glass(around view: NSView) -> NSView {
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

    func show(_ model: CandidateView.Model, anchor: NSRect) {
        view.model = model
        let size = view.contentSize
        setFrame(NSRect(origin: Self.origin(for: size, anchor: anchor, textInset: view.textInset), size: size), display: true)
        if !isVisible { orderFrontRegardless() }
        invalidateShadow()
    }

    func hide() {
        if isVisible { orderOut(nil) }
    }

    /// Places the panel's top-left just below the line rect, flipping above when there is no room,
    /// and keeps it on the anchor's screen. The first candidate's text starts under the caret (`textInset` from the
    /// panel's left edge).
    static func origin(for size: NSSize, anchor rawAnchor: NSRect,
                       textInset: CGFloat = CandidateView.Metrics.textInsetX) -> NSPoint {
        var anchor = rawAnchor
        // Some clients report an empty rect at the origin; fall back to the mouse position.
        if anchor.origin == .zero || !anchor.origin.x.isFinite || !anchor.origin.y.isFinite {
            let mouse = NSEvent.mouseLocation
            anchor = NSRect(x: mouse.x, y: mouse.y - 18, width: 0, height: 18)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 4
        var x = anchor.minX - textInset
        var y = anchor.minY - gap - size.height
        if y < visible.minY { y = anchor.maxY + gap }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

/// Draws the candidate list. Layout is computed when the model changes; drawing is appearance-aware.
final class CandidateView: NSView {
    struct Row: Equatable {
        enum Style: Equatable {
            /// Level-one pinyin candidate.
            case candidate
            /// The sentence as typed (level two, row 0).
            case original
            /// A version or rewrite from the model (level two).
            case translation
        }

        var label: String
        var text: String
        var comment: String = ""
        var style: Style
        var isComplete: Bool = true
        /// A symbol in a colored rounded square before the text, like the icons of iOS Settings.
        var icon: Icon? = nil
        /// A click picks it and the pointer over it highlights it (`onSelect`); not a line a script printed or a
        /// list's information, which nothing picks.
        var pickable = true
    }

    /// An SF Symbol, drawn white on `color`.
    struct Icon: Equatable {
        var symbol: String
        var color: NSColor
        /// Drawn instead of the symbol on its square: a script extension's own emoji, or image file.
        var emoji: String? = nil
        var image: String? = nil
    }

    enum Status: Equatable {
        case none
        case loading(String)
        case hint(String)
        case error(String)
    }

    struct Model: Equatable {
        var rows: [Row] = []
        var highlighted: Int?
        var status: Status = .none
        /// The command being written, as a line of input with its caret (▏), first: it isn't marked in the field (a
        /// command on the selected text).
        var input: String?
        /// A line above the rows: what the panel works on (the text selected in the field).
        var header: String?
        var footer = ""
        var detail: String?
        /// The rows side by side, as macOS's own panel (`Config.candidateLayout`): the engine's candidates only.
        var horizontal = false
    }

    enum Metrics {
        static let padding: CGFloat = 6
        static let rowInsetX: CGFloat = 8
        static let rowInsetY: CGFloat = 4
        static let labelGap: CGFloat = 8
        static let maxTextWidth: CGFloat = 520
        static let minWidth: CGFloat = 280
        static let cornerRadius: CGFloat = 10
        static let rowRadius: CGFloat = 6
        static let footerGap: CGFloat = 6
        static let labelWidth: CGFloat = ceil(("0" as NSString).size(withAttributes: [.font: Fonts.label]).width)
        static let iconSize: CGFloat = 20
        static let iconGap: CGFloat = 8
        /// Distance from the panel's left edge to where candidate text starts.
        static let textInsetX: CGFloat = padding + rowInsetX + labelWidth + labelGap
        /// Candidates in a row (`Model.horizontal`): the number closer to its word, the cells apart, the widest a
        /// line gets before the next candidates go on another, and the most of a long candidate shown.
        static let cellLabelGap: CGFloat = 4
        static let cellSpacing: CGFloat = 2
        static let maxRowWidth: CGFloat = 600
        static let maxCellTextWidth: CGFloat = 280
    }

    enum Fonts {
        static let candidate = NSFont.systemFont(ofSize: 16)
        static let english = NSFont.systemFont(ofSize: 15)
        static let chinese = NSFont.systemFont(ofSize: 14)
        static let comment = NSFont.systemFont(ofSize: 12)
        static let label = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        static let status = NSFont.systemFont(ofSize: 13)
        static let footer = NSFont.systemFont(ofSize: 11)

        static func text(for style: Row.Style) -> NSFont {
            switch style {
            case .candidate: return candidate
            case .original: return chinese
            case .translation: return english
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
        var labelOrigin: NSPoint
        var iconFrame: NSRect?
    }

    /// Its own solid background: off in the panel, where the system's glass is behind it (`CandidatePanel`);
    /// on for an offscreen image, which has nothing behind it to blur.
    var drawsBackground = true

    var model = Model() {
        didSet { if model != oldValue { relayout() } }
    }

    /// A row clicked: its index in `model.rows`.
    var onSelect: ((Int) -> Void)?
    var onScroll: ((Int) -> Void)?
    /// The row under the pointer, drawn lightly highlighted: what a click would pick.
    private(set) var hovered: Int? {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }
    /// Scrolling not yet a whole row (a trackpad's small steps add up).
    private var pendingScroll: CGFloat = 0
    private(set) var contentSize = NSSize(width: Metrics.minWidth, height: 40)
    /// Where the first candidate's text starts, from the left edge: under the caret (`CandidatePanel.origin`).
    private(set) var textInset = Metrics.textInsetX
    private var rowLayouts: [RowLayout] = []
    private var statusFrame: NSRect?
    private var headerFrame: NSRect?
    private var inputFrame: NSRect?
    private var footerY: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        relayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Layout

    private func relayout() {
        let p = Metrics.padding
        var y = p
        var widest: CGFloat = 0
        rowLayouts = []
        let horizontal = model.horizontal && !model.rows.isEmpty
        inputFrame = nil
        if let input = inputString() {
            let size = Self.measure(input, minHeight: 0)
            widest = max(widest, size.width + p + Metrics.rowInsetX - Metrics.textInsetX)
            inputFrame = NSRect(x: p + Metrics.rowInsetX, y: y + Metrics.rowInsetY, width: Metrics.maxTextWidth, height: size.height)
            y += size.height + 2 * Metrics.rowInsetY
        }
        headerFrame = nil
        if let header = headerString() {
            let size = Self.measure(header, minHeight: 0)
            widest = max(widest, size.width + p + Metrics.rowInsetX - Metrics.textInsetX)
            headerFrame = NSRect(x: p + Metrics.rowInsetX, y: y + Metrics.rowInsetY, width: Metrics.maxTextWidth, height: size.height)
            y += size.height + 2 * Metrics.rowInsetY
        }
        var cellsWidth: CGFloat = 0
        if horizontal { (y, cellsWidth) = layoutCells(top: y) }
        textInset = horizontal ? rowLayouts.first?.textFrame.minX ?? Metrics.textInsetX : Metrics.textInsetX
        // A column for the icons when any row has one: the text moves right by it.
        let iconColumn = model.rows.contains { $0.icon != nil } ? Metrics.iconSize + Metrics.iconGap : 0
        for row in model.rows where !horizontal {
            let (_, text) = strings(for: row, highlighted: false)
            let font = Fonts.text(for: row.style)
            let size = Self.measure(text, minHeight: max(ceil(font.ascender - font.descender + font.leading),
                                                          iconColumn > 0 ? Metrics.iconSize : 0))
            widest = max(widest, size.width + iconColumn)
            // Drawn at the width it was measured at: laid out only as wide as its longest line, the
            // text can wrap once more and lose its last line.
            // One line next to an icon is centered on it.
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            let textY = y + Metrics.rowInsetY + (iconColumn > 0 && size.height <= Metrics.iconSize ? (Metrics.iconSize - lineHeight) / 2 : 0)
            let textFrame = NSRect(x: Metrics.textInsetX + iconColumn, y: textY, width: Metrics.maxTextWidth, height: size.height)
            let labelOrigin = NSPoint(
                x: p + Metrics.rowInsetX,
                y: textFrame.minY + (font.ascender - Fonts.label.ascender))
            let iconFrame = row.icon.map { _ in
                NSRect(x: Metrics.textInsetX, y: y + Metrics.rowInsetY, width: Metrics.iconSize, height: Metrics.iconSize)
            }
            rowLayouts.append(RowLayout(
                frame: NSRect(x: p, y: y, width: 0, height: size.height + 2 * Metrics.rowInsetY),
                textFrame: textFrame, labelOrigin: labelOrigin, iconFrame: iconFrame))
            y += size.height + 2 * Metrics.rowInsetY
        }

        statusFrame = nil
        let compact = model.rows.isEmpty && model.footer.isEmpty
        let statusX = model.rows.isEmpty ? p + Metrics.rowInsetX : Metrics.textInsetX
        if let status = statusString() {
            let size = Self.measure(status, minHeight: 0)
            widest = max(widest, size.width + statusX - Metrics.textInsetX)
            statusFrame = NSRect(x: statusX, y: y + Metrics.rowInsetY, width: Metrics.maxTextWidth, height: size.height)
            y += size.height + 2 * Metrics.rowInsetY
        }

        // In a row, as wide as the candidates need (and the status, the footer); in a column, at least `minWidth`.
        var width = horizontal ? max(cellsWidth, widest > 0 ? Metrics.textInsetX + widest + Metrics.rowInsetX + p : 0)
            : max(compact ? 0 : Metrics.minWidth, Metrics.textInsetX + widest + Metrics.rowInsetX + p)
        if !model.footer.isEmpty {
            let footer = footerStrings()
            let footerWidth = footer.left.size().width + (footer.right.map { $0.size().width + 16 } ?? 0)
            width = max(width, ceil(footerWidth) + 2 * (p + Metrics.rowInsetX))
            footerY = y + Metrics.footerGap
            y = footerY + 1 + Metrics.footerGap + ceil(footer.left.size().height)
        }
        for i in rowLayouts.indices where !horizontal {
            rowLayouts[i].frame.size.width = width - 2 * p
        }
        contentSize = NSSize(width: ceil(width), height: ceil(y + p))
        needsDisplay = true
        // Other rows under a pointer that stayed put: the one there now.
        hovered = window.flatMap { $0.isVisible ? row(at: convert($0.mouseLocationOutsideOfEventStream, from: nil)) : nil }
    }

    /// The candidates side by side (`Model.horizontal`), as many to a line as fit in `maxRowWidth`
    /// (`CandidateLayout.flow`): each a cell with its number and word, one line, a long one cut short with "…".
    /// The y below them, and the panel width they need.
    private func layoutCells(top: CGFloat) -> (bottom: CGFloat, width: CGFloat) {
        let p = Metrics.padding
        let font = Fonts.candidate
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        var labelWidths: [CGFloat] = [], textWidths: [CGFloat] = []
        for row in model.rows {
            let (label, text) = strings(for: row, highlighted: false)
            labelWidths.append(row.label.isEmpty ? 0 : max(ceil(label.size().width), Metrics.labelWidth) + Metrics.cellLabelGap)
            // A long one cut to fit, its cell as wide as what's left of it (no gap after the "…").
            textWidths.append(ceil(Self.fitted(text, width: Metrics.maxCellTextWidth).size().width) + 1)
        }
        let sizes = zip(labelWidths, textWidths).map {
            CGSize(width: Metrics.rowInsetX * 2 + $0 + $1, height: lineHeight + 2 * Metrics.rowInsetY)
        }
        let frames = CandidateLayout.flow(sizes, spacing: Metrics.cellSpacing, lineSpacing: Metrics.cellSpacing,
                                          maxWidth: Metrics.maxRowWidth - 2 * p)
        for (index, cell) in frames.enumerated() {
            let frame = cell.offsetBy(dx: p, dy: top)
            let textFrame = NSRect(x: frame.minX + Metrics.rowInsetX + labelWidths[index], y: frame.minY + Metrics.rowInsetY,
                                   width: textWidths[index], height: lineHeight)
            let labelOrigin = NSPoint(x: frame.minX + Metrics.rowInsetX, y: textFrame.minY + (font.ascender - Fonts.label.ascender))
            rowLayouts.append(RowLayout(frame: frame, textFrame: textFrame, labelOrigin: labelOrigin, iconFrame: nil))
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

    // MARK: - Strings

    private func strings(for row: Row, highlighted: Bool) -> (NSAttributedString, NSAttributedString) {
        let primary: NSColor = highlighted ? .white : (row.style == .original ? .secondaryLabelColor : .labelColor)
        let secondary: NSColor = highlighted ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
        let font = Fonts.text(for: row.style)
        let label = NSAttributedString(string: row.label, attributes: [.font: Fonts.label, .foregroundColor: secondary])
        let text = NSMutableAttributedString(string: row.text, attributes: [.font: font, .foregroundColor: primary])
        if !row.isComplete {
            let caret: NSColor = highlighted ? NSColor.white.withAlphaComponent(0.6) : .tertiaryLabelColor
            text.append(NSAttributedString(string: row.text.isEmpty ? "▍" : " ▍", attributes: [.font: font, .foregroundColor: caret]))
        }
        if !row.comment.isEmpty {
            let color: NSColor = highlighted ? NSColor.white.withAlphaComponent(0.7) : .tertiaryLabelColor
            // No-break spaces and word joiners: when the line wraps, the comment ("黑话", jargon) moves as one
            // piece together with the last word instead of breaking between its characters.
            let glued = "\u{00A0}\u{00A0}" + row.comment.map(String.init).joined(separator: "\u{2060}")
            text.append(NSAttributedString(string: glued, attributes: [.font: Fonts.comment, .foregroundColor: color]))
        }
        return (label, text)
    }

    private func inputString() -> NSAttributedString? {
        model.input.map { NSAttributedString(string: $0, attributes: [.font: Fonts.candidate, .foregroundColor: NSColor.labelColor]) }
    }

    private func headerString() -> NSAttributedString? {
        model.header.map {
            NSAttributedString(string: $0, attributes: [.font: Fonts.comment, .foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    private func statusString() -> NSAttributedString? {
        switch model.status {
        case .none:
            return nil
        case let .loading(text):
            return NSAttributedString(string: text, attributes: [
                .font: Fonts.status, .foregroundColor: NSColor.secondaryLabelColor,
            ])
        case let .hint(text):
            return NSAttributedString(string: text, attributes: [
                .font: Fonts.status, .foregroundColor: NSColor.labelColor,
            ])
        case let .error(message):
            return NSAttributedString(string: "⚠︎ \(message)", attributes: [
                .font: Fonts.status, .foregroundColor: NSColor.systemRed,
            ])
        }
    }

    private func footerStrings() -> (left: NSAttributedString, right: NSAttributedString?) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Fonts.footer, .foregroundColor: NSColor.tertiaryLabelColor]
        return (
            NSAttributedString(string: model.footer, attributes: attributes),
            model.detail.map { NSAttributedString(string: $0, attributes: attributes) })
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius)
        if drawsBackground {
            Self.background.setFill()
            shape.fill()
            NSColor.separatorColor.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }

        if let inputFrame, let input = inputString() {
            input.draw(with: inputFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            // Under it, a line as under a text being typed.
            NSColor.separatorColor.setFill()
            let inset = Metrics.padding + Metrics.rowInsetX
            NSRect(x: inset, y: inputFrame.maxY + Metrics.rowInsetY - 1, width: bounds.width - 2 * inset, height: 1).fill()
        }
        if let headerFrame, let header = headerString() {
            header.draw(with: headerFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        for (index, layout) in rowLayouts.enumerated() where index < model.rows.count {
            let highlighted = index == model.highlighted
            // In a row, the highlight is a pill around the candidate, as in macOS's own panel.
            let radius = model.horizontal ? layout.frame.height / 2 : Metrics.rowRadius
            if index == hovered, !highlighted {
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: layout.frame, xRadius: radius, yRadius: radius).fill()
            }
            if highlighted {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: layout.frame, xRadius: radius, yRadius: radius).fill()
            }
            let (label, text) = strings(for: model.rows[index], highlighted: highlighted)
            label.draw(at: layout.labelOrigin)
            if let icon = model.rows[index].icon, let frame = layout.iconFrame { Self.draw(icon, in: frame) }
            // A candidate in a row keeps to its one line, cut short with "…" (as measured: `layoutCells`).
            if model.horizontal {
                Self.fitted(text, width: Metrics.maxCellTextWidth).draw(with: layout.textFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            } else {
                text.draw(with: layout.textFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }

        if let statusFrame, let status = statusString() {
            status.draw(with: statusFrame, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        if !model.footer.isEmpty {
            let inset = Metrics.padding + Metrics.rowInsetX
            NSColor.separatorColor.setFill()
            NSRect(x: inset, y: footerY, width: bounds.width - 2 * inset, height: 1).fill()
            let footer = footerStrings()
            let textY = footerY + 1 + Metrics.footerGap
            footer.left.draw(at: NSPoint(x: inset, y: textY))
            if let right = footer.right {
                right.draw(at: NSPoint(x: bounds.width - inset - right.size().width, y: textY))
            }
        }
    }

    /// A white symbol on a colored rounded square (a missing symbol: a generic one), or an emoji.
    static func draw(_ icon: Icon, in frame: NSRect) {
        if let path = icon.image, let image = CommandIcons.image(path) {
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        if let emoji = icon.emoji {
            let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: frame.height * 0.8)])
            let size = text.size()
            text.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            return
        }
        icon.color.setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.width * 0.24, yRadius: frame.height * 0.24).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: frame.height * 0.55, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = (NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil)
                           ?? NSImage(systemSymbolName: "command", accessibilityDescription: nil))?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        image.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
    }

    // MARK: - Mouse

    override func scrollWheel(with event: NSEvent) {
        // A row per notch of a wheel; a trackpad adds up its small steps (about a row per 24 points).
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 24 : event.scrollingDeltaY
        pendingScroll -= delta  // content up = further down the list
        let rows = Int(pendingScroll.rounded(.towardZero))
        guard rows != 0 else { return }
        pendingScroll -= CGFloat(rows)
        onScroll?(rows)
    }

    /// The row a click at `point` picks (`CandidateLayout.row`).
    private func row(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        return CandidateLayout.row(at: point, frames: rowLayouts.map(\.frame), pickable: model.rows.map(\.pickable))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Always: the panel is never key, and the input method's app is never active.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { hovered = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { hovered = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    /// A click picks the row as its digit would (`Composer.choose`); the text field keeps the focus, the panel
    /// being non-activating and never key.
    override func mouseDown(with event: NSEvent) {
        if let index = row(at: convert(event.locationInWindow, from: nil)) { onSelect?(index) }
    }
}


private extension NSImage {
    func with(_ change: (NSImage) -> Void) -> NSImage {
        change(self)
        return self
    }
}
