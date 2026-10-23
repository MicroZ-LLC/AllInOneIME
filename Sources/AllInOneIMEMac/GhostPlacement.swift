import CoreGraphics

/// Where autocomplete's suggestion goes on the screen (the input method's overlay, `GhostOverlay`): right after the
/// caret, on its line, as tall as it, cut at the screen's edge and, where the field's frame is known, at the field's: a
/// narrow field's suggestion never covers the window beside it.
public enum GhostPlacement {
    /// The overlay's frame for the suggestion's `size` after `caret` (a rect on the screen, as tall as its line), within
    /// `visible` (the screen's visible frame; nil: none known) and `field` (the field's frame; nil: not known; one that
    /// doesn't hold the caret is taken for none: what Accessibility calls focused isn't always the field). At least
    /// `minimumWidth` wide (the Tab key cap).
    public static func frame(size: CGSize, caret: CGRect, visible: CGRect?, field: CGRect?, minimumWidth: CGFloat = 24) -> CGRect {
        let x = caret.maxX + 1
        var right = visible?.maxX ?? x + size.width
        if let field, field.insetBy(dx: -2, dy: -2).contains(CGPoint(x: caret.midX, y: caret.midY)) { right = min(right, field.maxX) }
        let width = max(min(size.width, right - x), minimumWidth)
        let height = max(caret.height, size.height)
        return CGRect(x: x, y: caret.midY - height / 2, width: width, height: height)
    }
}
