import CoreGraphics

/// Where autocomplete's suggestion goes on the screen (the input method's overlay, `GhostOverlay`): right after the
/// caret, on its line, as tall as it, cut at the screen's edge and, where the field's frame is known, at the field's: a
/// narrow field's suggestion never covers the window beside it. Where that leaves its text too little room, it doesn't go
/// anywhere.
public enum GhostPlacement {
    /// The overlay's frame for the suggestion's `size` after `caret` (a rect on the screen, as tall as its line), within
    /// `visible` (the screen's visible frame; nil: none known) and `field` (the field's frame; nil: not known; one that
    /// doesn't hold the caret is taken for none: what Accessibility calls focused isn't always the field). `chrome` of
    /// its width is the Tab key cap and the gaps beside it, the rest its text's. Nil where the text would get less than
    /// `minimumText` (the width of its first few characters, all of a shorter one): only the key cap, or a sliver of
    /// text, would show for a Tab that puts in all of it, so nothing shows (and Tab is the app's).
    public static func frame(size: CGSize, caret: CGRect, visible: CGRect?, field: CGRect?, chrome: CGFloat, minimumText: CGFloat) -> CGRect? {
        let x = caret.maxX + 1
        var right = visible?.maxX ?? x + size.width
        if let field, field.insetBy(dx: -2, dy: -2).contains(CGPoint(x: caret.midX, y: caret.midY)) { right = min(right, field.maxX) }
        let width = min(size.width, right - x)
        guard width - chrome >= minimumText else { return nil }
        let height = max(caret.height, size.height)
        return CGRect(x: x, y: caret.midY - height / 2, width: width, height: height)
    }
}
