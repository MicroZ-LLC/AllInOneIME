import CoreGraphics

/// The candidate panel's geometry that needs no drawing (the app's `CandidateView` measures and draws): where
/// candidates in a row go, and which row a point is on, for a click or the pointer over the panel.
public enum CandidateLayout {
    /// Cells of `sizes` side by side from the top left, `spacing` apart, a line holding as many as fit in
    /// `maxWidth` (one at least, however wide), the next line `lineSpacing` below: candidates in a row
    /// (`Config.candidateLayout`), which wrap rather than make the panel wider than `maxWidth`. A line is as tall
    /// as its tallest cell; the cells sit at its top.
    public static func flow(_ sizes: [CGSize], spacing: CGFloat, lineSpacing: CGFloat, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }

    /// The row under `point` (view coordinates, as `frames`), if it can be picked: a click picks it, the pointer
    /// over it highlights it. Nil over a row that can't (a line a script printed, a list's information), the gap
    /// between two, the footer and the status.
    public static func row(at point: CGPoint, frames: [CGRect], pickable: [Bool]) -> Int? {
        guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return nil }
        return pickable.indices.contains(index) && pickable[index] ? index : nil
    }
}
