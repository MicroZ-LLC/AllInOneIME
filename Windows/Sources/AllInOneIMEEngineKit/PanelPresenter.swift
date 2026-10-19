import Foundation

/// A caret report (§6): the caret's (or the composition's first character's) rectangle in physical screen pixels, and
/// whether it is the caret's own or only the field's window (`exact: false`).
public struct CaretRect: Equatable, Sendable {
    public var x, y, width, height: Int
    public var exact: Bool

    public init(x: Int, y: Int, width: Int, height: Int, exact: Bool = true) {
        (self.x, self.y, self.width, self.height, self.exact) = (x, y, width, height, exact)
    }

    /// `[x, y, width, height]` as the wire has it.
    public init?(_ rect: [Int], exact: Bool) {
        guard rect.count == 4 else { return nil }
        self.init(x: rect[0], y: rect[1], width: rect[2], height: rect[3], exact: exact)
    }
}

/// Whose panel it is: a text field's session. One panel is up at a time, the last one shown; a session hides only its
/// own (the Mac's `hidePanelIfOwned`). A click on a row and the wheel go back to it.
public final class PanelOwner: @unchecked Sendable {
    /// The client's process: the panel hides when another process takes the foreground.
    public let pid: UInt32?
    /// A row clicked: `ComposerSession.choose(row:)`.
    public let choose: @Sendable (Int) -> Void
    /// The wheel over the panel, in rows (down is positive).
    public let scroll: @Sendable (Int) -> Void

    public init(pid: UInt32?, choose: @escaping @Sendable (Int) -> Void, scroll: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.pid = pid
        self.choose = choose
        self.scroll = scroll
    }
}

/// What draws the panel: the engine's candidate window on Windows (`CandidateWindow`), a recorder in the tests. Called
/// from the sessions' queues; an implementation does its drawing on its own thread. The small interface the window sits
/// behind, so that it can take the core's panel model later.
public protocol PanelPresenter: AnyObject, Sendable {
    /// Shows `model` for `owner` (or draws it again), at `caret` when there is one, else where the last report put it.
    func show(_ model: PanelModel, owner: PanelOwner, caret: CaretRect?)
    /// Hides the panel if `owner`'s is up.
    func hide(owner: PanelOwner)
    /// The caret moved: the panel follows, if it is `owner`'s.
    func move(owner: PanelOwner, caret: CaretRect)
    /// A short notice ("中", "Copied"): beside the footer while the panel is up, else on its own for a moment, at
    /// `caret` (the field's last one) when known.
    func notice(_ text: String, owner: PanelOwner, caret: CaretRect?)
    /// The owner's session is gone.
    func forget(owner: PanelOwner)
}

extension PanelPresenter {
    public func forget(owner: PanelOwner) {}
}

/// No panel: what a test without a window, or the engine without a desktop, uses.
public final class NoPanel: PanelPresenter {
    public init() {}
    public func show(_ model: PanelModel, owner: PanelOwner, caret: CaretRect?) {}
    public func hide(owner: PanelOwner) {}
    public func move(owner: PanelOwner, caret: CaretRect) {}
    public func notice(_ text: String, owner: PanelOwner, caret: CaretRect?) {}
}
