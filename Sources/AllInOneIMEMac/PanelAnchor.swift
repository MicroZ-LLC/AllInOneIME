import CoreGraphics

/// Where a panel of ours at the caret goes (the candidate panel, a notice, Translate as You Type's chip): under the rect
/// the field tells for its marked text (`attributes(forCharacterIndex:lineHeightRectangle:)`; the selection's last
/// character for a command on it), where that is a rect to trust (`trusted`). Chromium answers from bounds the page sends
/// it later: before they come, or from a hidden input element the page hasn't moved to the caret yet (Google Docs types
/// into one), it tells a rect at the page's top-left corner, which put the panel there, far from the caret. (The Electron
/// harness, with a hidden input of no size at the page's top-left: the caret's rect empty at that corner, the marked
/// text's a line high under it.)
///
/// A rect not to trust, the panel goes by the caret Accessibility tells for the focused element (on a screen, in the
/// focused window), else by the last rect to trust the field told (`Memory`), else by the rect as told, where it always
/// went. Then the field is asked again a moment later (`reaskDelays`), and the panel moves once it tells a rect to trust.
/// Accessibility is asked only for a rect not to trust: never on every key in an app that tells its caret right.
public enum PanelAnchor {
    /// When the field is asked again, in seconds after a panel placed by anything but a rect it told to trust: Chromium's
    /// bounds come a frame or more after the marked text (asked at once, the first key of a composition gets the page's
    /// corner); Google Docs' came half a second later at times (the owner's log). Every frame at first, then less often.
    public static let reaskDelays: [Double] = [0.016, 0.033, 0.05, 0.1, 0.15, 0.3, 0.5, 0.8]

    /// The field a panel is for: its client object and app, in one focus session (an activation of it).
    public struct Field: Equatable, Sendable {
        public var client: ObjectIdentifier
        public var app: String?
        public var session: Int

        public init(client: ObjectIdentifier, app: String?, session: Int) {
            (self.client, self.app, self.session) = (client, app, session)
        }
    }

    /// What Accessibility told of the focused element, in AppKit's coordinates (nil: not told): the caret's bounds, the
    /// focused window's frame and the frame of the page it is on (the outermost web area); `timedOut`: a call got no
    /// answer in time.
    public struct Accessibility: Equatable, Sendable {
        public var caret: CGRect?
        public var window: CGRect?
        public var page: CGRect?
        public var timedOut = false

        public init(caret: CGRect? = nil, window: CGRect? = nil, page: CGRect? = nil, timedOut: Bool = false) {
            (self.caret, self.window, self.page, self.timedOut) = (caret, window, page, timedOut)
        }
    }

    /// What a panel's anchor went by (the log says which).
    public enum Source: String, Sendable {
        /// The rect the field told, one to trust.
        case field
        /// The caret Accessibility told.
        case accessibility
        /// The last rect to trust the field told.
        case last
        /// The rect the field told, not one to trust: as before, nothing better known.
        case told
    }

    /// Where the panel goes and what that went by; anything but the field's own rect to trust has the field asked again
    /// (`reaskDelays`).
    public struct Placement: Equatable, Sendable {
        public var rect: CGRect
        public var source: Source
        public var reasks: Bool { source != .field }

        public init(rect: CGRect, source: Source) {
            (self.rect, self.source) = (rect, source)
        }
    }

    /// Whether `rect`, on the screen in AppKit's coordinates, is one to trust: it has a height (more than a point: an
    /// empty rect, zero wide and high, has none), isn't at the screen's origin, is on one of `screens` (their frames; none
    /// known: not checked), isn't at the top-left corner of the focused window or its page (`window`, `page`, where
    /// Accessibility told them), where Chromium's rect goes before it has the page's bounds, and isn't on the window's
    /// left edge near its top (`atLeftEdgeNearTop`). The left edges (`edges`) count only where the field tells nothing
    /// of its marked text itself: a terminal with no padding, filling the screen, has its caret on the screen's edge and
    /// tells its marked text's rect there too, where Google Docs, telling its page's corner, tells none.
    public static func trusted(_ rect: CGRect, screens: [CGRect], window: CGRect? = nil, page: CGRect? = nil, edges: Bool = true) -> Bool {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.height > 1, rect.origin != .zero else { return false }
        if !screens.isEmpty, !screens.contains(where: { $0.intersects(rect.insetBy(dx: -2, dy: -2)) }) { return false }
        // On a screen's very left edge: the page's corner of a window that fills the screen (the owner's Google Docs told
        // x 0 y 817 h 18 on a screen 956 high), never a caret, whatever Accessibility told or not.
        if edges, screens.contains(where: { abs(rect.minX - $0.minX) <= 2 && $0.insetBy(dx: -2, dy: -2).contains(CGPoint(x: rect.minX, y: rect.midY)) }) {
            return false
        }
        if edges, let window, atLeftEdgeNearTop(rect, of: window) { return false }
        return ![window, page].contains { $0.map { atTopLeft(rect, of: $0) } == true }
    }

    /// Whether `rect`'s top-left corner is `frame`'s (two points either way).
    static func atTopLeft(_ rect: CGRect, of frame: CGRect) -> Bool {
        abs(rect.minX - frame.minX) <= 2 && abs(rect.maxY - frame.maxY) <= 2
    }

    /// How far under a window's top Chromium's page starts at most (its tabs and toolbar, a bookmarks bar, a banner):
    /// a rect on the window's left edge down to here is the page's corner, not a caret.
    static let pageTopBelowWindowTop: CGFloat = 220

    /// Whether `rect` starts on `window`'s left edge (two points either way) within `pageTopBelowWindowTop` of its top:
    /// where the page's top-left corner is, under Chromium's tabs and toolbar. Google Docs' rect for marked text is a line
    /// high there (the hidden element it types into, not moved to the caret), so its height doesn't make it one to trust;
    /// no app draws a caret on its window's very edge.
    static func atLeftEdgeNearTop(_ rect: CGRect, of window: CGRect) -> Bool {
        abs(rect.minX - window.minX) <= 2 && rect.maxY <= window.maxY + 2 && rect.maxY >= window.maxY - pageTopBelowWindowTop
    }

    /// `rect` as Accessibility tells it (from the main screen's top-left, y down) in AppKit's coordinates (from its
    /// bottom-left, y up); `top`: the main screen's height.
    public static func appKit(_ rect: CGRect, top: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: top - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    /// What a field's panel goes by, for one field at a time: the last rect to trust it told, the frames Accessibility
    /// told there (a rect at their top-left corner isn't one to trust either), and whether Accessibility is still asked
    /// there. Another field forgets all of it.
    public struct Memory: Sendable {
        public private(set) var field: Field?
        public private(set) var last: CGRect?
        public private(set) var window: CGRect?
        public private(set) var page: CGRect?
        /// Accessibility got no answer in time in this field: not asked there again (an app that hangs would hold up
        /// every key).
        public private(set) var accessibilityGivenUp = false
        /// The window's frame was asked in this field (`learnWindow`), told or not.
        public private(set) var windowAsked = false

        public init() {}

        /// The panel is for `field` now: another field than before (another client, app or focus session) forgets the
        /// last one's.
        public mutating func enter(_ field: Field) {
            guard field != self.field else { return }
            self = Memory()
            self.field = field
        }

        /// The field is left.
        public mutating func forget() { self = Memory() }

        /// The focused window's frame, asked (`read`) once in the field, before its first rect is judged: a rect on its
        /// left edge near its top isn't one to trust even where it has a height (`atLeftEdgeNearTop`). Not once
        /// Accessibility timed out in the field.
        public mutating func learnWindow(_ read: () -> (frame: CGRect?, timedOut: Bool)?) {
            guard window == nil, !windowAsked, !accessibilityGivenUp else { return }
            windowAsked = true
            guard let told = read() else { return }
            window = told.frame
            accessibilityGivenUp = told.timedOut
        }

        /// Where the panel goes for `told`, the rect the field tells now: there, if it is one to trust (remembered);
        /// else the caret `accessibility` tells (asked only then, and not once it timed out in this field) where it is
        /// one to trust inside the focused window; else the last rect to trust; else `told`, as before.
        @discardableResult
        public mutating func place(_ told: CGRect, screens: [CGRect], edges: Bool = true,
                                   accessibility: () -> Accessibility?) -> Placement {
            if trusted(told, screens: screens, window: window, page: page, edges: edges) {
                last = told
                return Placement(rect: told, source: .field)
            }
            if !accessibilityGivenUp, let read = accessibility() {
                window = read.window ?? window
                page = read.page ?? page
                // Timed out, or no caret told: not asked again in this field (it would cost every key up to 0.1 s).
                accessibilityGivenUp = read.timedOut || read.caret == nil
                if let caret = read.caret, let window, trusted(caret, screens: screens, window: window, page: page),
                   window.insetBy(dx: -2, dy: -2).contains(CGPoint(x: caret.midX, y: caret.midY)) {
                    return Placement(rect: caret, source: .accessibility)
                }
            }
            if let last { return Placement(rect: last, source: .last) }
            return Placement(rect: told, source: .told)
        }

        /// The field asked again (`reaskDelays`) and telling `told` now: the rect the panel moves to, if it is one to trust
        /// (remembered); nil, the panel stays where it is.
        public mutating func reasked(_ told: CGRect, screens: [CGRect], edges: Bool = true) -> CGRect? {
            guard trusted(told, screens: screens, window: window, page: page, edges: edges) else { return nil }
            last = told
            return told
        }
    }
}
