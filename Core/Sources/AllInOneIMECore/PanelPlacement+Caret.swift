import Foundation

/// A screen as the platform tells it, in its screen coordinates (Cocoa's on the Mac: from the main screen's bottom-left,
/// y up; a display to the left of it has x below 0): all of it (`frame`) and the part a window may use (`visibleFrame`:
/// without the menu bar and the Dock).
public struct ScreenInfo: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        (self.frame, self.visibleFrame) = (frame, visibleFrame)
    }
}

/// The panel at the caret (the candidate panel, a notice, Translate as You Type's chip), placed by the caret's rect the
/// field told (the anchor its shell went by: on the Mac `PanelAnchor`, which turns a rect not to trust into the caret
/// Accessibility tells, the last rect to trust, or the rect as told). Every platform's, in the screens' coordinates (y up).
extension PanelPlacement {
    /// Which side of the caret the panel is on.
    public enum Side: Equatable, Sendable {
        case below, above
    }

    /// Between the caret's line and the panel.
    public static let caretGap: CGFloat = 4
    /// The screen assumed where none is known.
    public static let assumedScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    /// The line under the pointer that stands in for a caret the field told nothing of (`usable`).
    static let pointerLine: CGFloat = 18

    /// Where a panel of `panel`'s size goes for `caret`: under it, else above it where it doesn't fit below, inside the
    /// visible part of the caret's screen (`screen(for:among:)`). A caret told as nothing (an empty rect at the origin,
    /// or not a number) goes by the middle of the main screen (`usable`).
    public static func frame(caret: CGRect, panel: CGSize, screens: [ScreenInfo]) -> CGRect {
        atCaret(panel, caret: caret, screens: screens).frame
    }

    /// The panel's frame for `caret` and the side of the caret it is on. Its top-left just below the caret's line, or its
    /// bottom-left just above it where there is no room below (`keeping` `.above`, the side it is on while typing on that
    /// line: above as long as it fits there); with room on neither side, on the side with more, moved onto the screen.
    /// The first candidate's text starts under the caret (`textInset` from the panel's left edge). `pointer`: where the
    /// pointer is, for a caret told as nothing (`usable`).
    public static func atCaret(_ size: CGSize, caret: CGRect, screens: [ScreenInfo], textInset: CGFloat = 0,
                               keeping kept: Side? = nil, pointer: CGPoint? = nil) -> (frame: CGRect, side: Side) {
        let anchor = usable(caret, screens: screens, pointer: pointer)
        let visible = screen(for: anchor, among: screens)?.visibleFrame ?? assumedScreen
        let below = anchor.minY - caretGap - size.height, above = anchor.maxY + caretGap
        let roomBelow = below >= visible.minY, roomAbove = above + size.height <= visible.maxY
        let side: Side = kept == .above && roomAbove ? .above
            : roomBelow ? .below
            : roomAbove ? .above
            : anchor.minY - visible.minY >= visible.maxY - anchor.maxY ? .below : .above
        let x = min(max(anchor.minX - textInset, visible.minX), visible.maxX - size.width)
        let y = min(max(side == .below ? below : above, visible.minY), visible.maxY - size.height)
        return (CGRect(origin: CGPoint(x: x, y: y), size: size), side)
    }

    /// The screen the panel goes on for `caret` (its rect as `usable` makes it): the one its middle is on, else the one
    /// nearest to it (a caret told off every screen: a display gone, a rect from another one's coordinates); nil: none.
    public static func screen(for caret: CGRect, among screens: [ScreenInfo]) -> ScreenInfo? {
        let middle = CGPoint(x: caret.midX, y: caret.midY)
        if let on = screens.first(where: { $0.frame.contains(middle) }) { return on }
        return screens.min { distance(from: middle, to: $0.frame) < distance(from: middle, to: $1.frame) }
    }

    /// `caret`, or where a field that tells nothing of its caret has it: an empty rect at the origin, or one that isn't a
    /// number, is a line under the pointer (`pointer`), else in the middle of the main screen's visible part (the first
    /// of `screens`).
    public static func usable(_ caret: CGRect, screens: [ScreenInfo], pointer: CGPoint? = nil) -> CGRect {
        let finite = caret.origin.x.isFinite && caret.origin.y.isFinite && caret.width.isFinite && caret.height.isFinite
        guard !finite || caret.origin == .zero else { return caret }
        let main = screens.first?.visibleFrame ?? assumedScreen
        let point = pointer ?? CGPoint(x: main.midX, y: main.midY)
        return CGRect(x: point.x, y: point.y - pointerLine, width: 0, height: pointerLine)
    }

    /// Whether two carets are on the same line: the middle of one within the other's height (each as `usable` makes it).
    public static func onTheSameLine(_ a: CGRect, _ b: CGRect, screens: [ScreenInfo], pointer: CGPoint? = nil) -> Bool {
        let (a, b) = (usable(a, screens: screens, pointer: pointer), usable(b, screens: screens, pointer: pointer))
        return b.midY >= a.minY - 1 && b.midY <= a.maxY + 1
    }

    /// How far `point` is from `rect` (0: inside it).
    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX), dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
