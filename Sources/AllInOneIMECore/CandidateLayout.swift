import CoreGraphics

/// The candidate panel's geometry that needs no drawing (the app's `CandidateView` measures and draws): which
/// row a point is on, for a click or the pointer over the panel.
public enum CandidateLayout {
    /// The row under `point` (view coordinates, as `frames`), if it can be picked: a click picks it, the pointer
    /// over it highlights it. Nil over a row that can't (a line a script printed, a list's information), the gap
    /// between two, the footer and the status.
    public static func row(at point: CGPoint, frames: [CGRect], pickable: [Bool]) -> Int? {
        guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return nil }
        return pickable.indices.contains(index) && pickable[index] ? index : nil
    }
}
