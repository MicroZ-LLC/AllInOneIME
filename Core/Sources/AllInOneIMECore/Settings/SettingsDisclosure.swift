/// A folded part of Settings (More…, "Folders and sources…"): until it is clicked it is open when it opens by itself
/// (something set in it, the search pointing into it); a click shows it open or folded, whatever opened it, so one with
/// something set in it can still be folded. A new window, or the search pointing into it again, starts over (`reset`).
public struct SettingsDisclosure: Equatable, Sendable {
    /// What the last click showed: open or folded; nil: not clicked since it started over.
    public private(set) var clicked: Bool?

    public init() {}

    /// Whether it is shown open, `opensByItself` saying whether it would open with no click.
    public func isExpanded(opensByItself: Bool) -> Bool { clicked ?? opensByItself }

    /// Clicked to show it open (`expanded`) or folded.
    public mutating func click(_ expanded: Bool) { clicked = expanded }

    public mutating func reset() { clicked = nil }
}
