import CoreGraphics

/// Where autocomplete's suggestion goes on the screen (the input method's overlay, `GhostOverlay`): right after the
/// caret, on its line, as tall as it, cut at the screen's edge and, where the field's frame is known, at the field's: a
/// narrow field's suggestion never covers the window beside it. Where that leaves its text too little room, it doesn't go
/// anywhere.
public enum GhostPlacement {
    /// Which line the suggestion goes on and where on it, from what a field tells of its caret, three ways: the line
    /// as the candidate panel goes by it (`line`, from `attributes(forCharacterIndex:lineHeightRectangle:)`), the empty
    /// range at the caret (`caret`) and the character before it (`previous`). The line first: where it is as narrow as a
    /// caret it is the caret itself, its x too (Notes tells the other two a line above it, the panel's line right).
    /// Else the empty range's x where it is on that line, else the end of the character before. Nil, the candidate
    /// panel's line instead: no line told; the empty range more than a line away from a wide line; no x on the line.
    public static func line(_ line: CGRect?, caret: CGRect?, previous: CGRect?) -> (line: CGRect, x: CGFloat)? {
        guard let line = line ?? caret else { return nil }
        if line.width <= 2 { return (line, line.minX) }
        func apart(_ rect: CGRect) -> CGFloat { abs(rect.midY - line.midY) }
        if let caret, apart(caret) > line.height { return nil }
        if let caret, apart(caret) <= line.height / 2 { return (line, caret.maxX) }
        if let previous, apart(previous) <= line.height / 2 { return (line, previous.maxX) }
        return caret == nil ? (line, line.minX) : nil
    }

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
