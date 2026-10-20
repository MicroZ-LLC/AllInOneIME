import AllInOneIMECore
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

    /// This rectangle inside `bounds` (a negative width or height taken as none): what is outside is cut off, and one
    /// wholly outside becomes a line on the nearest edge.
    public func clamped(to bounds: CaretRect) -> CaretRect {
        func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { min(max(value, low), max(high, low)) }
        let (right, bottom) = (bounds.x + max(bounds.width, 0), bounds.y + max(bounds.height, 0))
        let left = clamp(x, bounds.x, right), top = clamp(y, bounds.y, bottom)
        return CaretRect(x: left, y: top, width: clamp(x + max(width, 0), bounds.x, right) - left,
                         height: clamp(y + max(height, 0), bounds.y, bottom) - top, exact: exact)
    }
}

/// Whose panel it is: a text field's session. One panel is up at a time, the last one shown; a session hides only its
/// own (the Mac's `hidePanelIfOwned`). A click on a row and the wheel go back to it.
public final class PanelOwner: @unchecked Sendable {
    /// The client's process: the panel hides when another process takes the foreground.
    public let pid: UInt32?
    /// A row clicked, by its index in the model shown: the session picks the row's `choice`.
    public let choose: @Sendable (Int) -> Void
    /// The wheel over the panel, in rows (down is positive).
    public let scroll: @Sendable (Int) -> Void

    public init(pid: UInt32?, choose: @escaping @Sendable (Int) -> Void, scroll: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.pid = pid
        self.choose = choose
        self.scroll = scroll
    }
}

/// What draws the panel, the core's `PanelModel` (made by the core's `PanelPresenter`): the engine's candidate window on
/// Windows (`CandidateWindow`), a recorder in the tests. Called from the sessions' queues; an implementation does its
/// drawing on its own thread.
public protocol PanelWindow: AnyObject, Sendable {
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

extension PanelWindow {
    public func forget(owner: PanelOwner) {}
}

/// The core's panel as a window draws it with a line each for the input, the header and the status (the candidate
/// window's flat copy, `AioPanelModel`).
extension PanelModel {
    /// The line of input: its prompt, then its text with "▏" at the caret (none: only shown).
    var inputLine: String? {
        guard let input else { return nil }
        var text = input.text
        if let caret = input.caret {
            text.insert("▏", at: text.index(text.startIndex, offsetBy: min(max(caret, 0), text.count)))
        }
        return input.prompt + text
    }

    /// The header's line: where a conversation can go on ("Continue in Claude or another AI · Ctrl+1 Claude Code ·
    /// Ctrl+2 Claude"), then the header's lines, one after the other.
    var headerLine: String? {
        let handoff = self.handoff.map { [$0.title] + $0.choices.map { $0.shortcut + " " + $0.name } } ?? []
        let parts = (handoff + header).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The status's text: a list's items after its hint.
    var statusLine: String? {
        switch status {
        case .none: return nil
        case let .hint(text), let .loading(text), let .error(text): return text
        case let .list(hint, items): return ([hint] + items).joined(separator: " · ")
        }
    }
}

/// No panel: what a test without a window, or the engine without a desktop, uses.
public final class NoPanel: PanelWindow {
    public init() {}
    public func show(_ model: PanelModel, owner: PanelOwner, caret: CaretRect?) {}
    public func hide(owner: PanelOwner) {}
    public func move(owner: PanelOwner, caret: CaretRect) {}
    public func notice(_ text: String, owner: PanelOwner, caret: CaretRect?) {}
}
