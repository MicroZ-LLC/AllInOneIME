import CoreGraphics

/// A click while pinyin is marked in a field (#116; the owner, 2026-11-15: leaving a field mid-composition leaves nothing
/// of it there, in every app). Hosts end the marked text themselves on a mouse down, before they tell the input method
/// anything: Chromium's view commits it (`finishComposingText`), NSTextField's field editor keeps it as text when another
/// field takes the focus. So the input method drops it on the mouse down itself, as early as it is told of one: the key
/// tap (`KeyGuard`, with Accessibility) before any app has the click, and IMK's mouse event, which AppKit's text views
/// hand over first.
public enum CompositionLeave {
    /// Whether a mouse down at `point` ends what this input method has marked: any click while something is marked, but
    /// one on a window of the input method's own (`ownWindows`, those that take clicks: a candidate row picks it).
    public static func mouseDownEnds(at point: CGPoint, marked: Bool, ownWindows: [CGRect]) -> Bool {
        marked && !ownWindows.contains { $0.contains(point) }
    }

    /// A Quartz event's location (from the top left of the primary screen, `primaryHeight` high) in AppKit's screen
    /// coordinates (from its bottom left).
    public static func appKitPoint(_ quartz: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: quartz.x, y: primaryHeight - quartz.y)
    }
}
