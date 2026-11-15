import AppKit
import InputMethodKit

/// Where a panel of ours goes in a field (`PanelAnchor`), from what the field tells through IMK: the rect for its
/// marked text's line, the selection's last character for a command on it, its marked text's own rect. What only the
/// input method's process can tell (Accessibility, the pointer, the screens) comes from it; the log and asking the field
/// again later (`PanelAnchor.reaskDelays`) are its too.
public enum FieldAnchor {
    /// Where `place` put the panel, and the rect it went by: the one the field tells (its marked text's own where the
    /// line's isn't one to trust and that is).
    public struct Placed: Equatable, Sendable {
        public var told: CGRect
        public var placement: PanelAnchor.Placement

        public init(told: CGRect, placement: PanelAnchor.Placement) {
            (self.told, self.placement) = (told, placement)
        }
    }

    /// Where a panel goes in `client`, the field of `app` (`memory` already entered for it, its window learned): the rect
    /// it tells (`told`) where it is one to trust; else the caret `accessibility` tells (given whether the page's frame
    /// is still to be read), the last rect to trust in this field, or the rect as told. Nothing better in this field yet
    /// (its first panel since the app came back, the field telling the page's corner): the app's last rect to trust, from
    /// another field or focus session of it, where it was typed in last (`lastByApp`, every field's); else, where nothing
    /// is known of the caret at all (Google Docs telling only its page's corner), by the `pointer`, where the field was
    /// clicked last, as a line under it. `selection`: a command's selection, which the panel goes under.
    @MainActor
    public static func place(in client: IMKTextInput, app: String?, selection: Range<Int>?, memory: inout PanelAnchor.Memory,
                             lastByApp: inout [String: CGRect], screens: [CGRect], pointer: () -> CGPoint,
                             accessibility: (_ page: Bool) -> PanelAnchor.Accessibility?) -> Placed {
        var told = Self.told(client, selection: selection)
        // The left edges distrust a rect only where the field tells nothing of its marked text (`PanelAnchor.trusted`).
        let marked = markedAnchor(client)
        let edges = marked == nil
        if !PanelAnchor.trusted(told, screens: screens, window: memory.window, page: memory.page, edges: edges),
           let marked,
           PanelAnchor.trusted(marked, screens: screens, window: memory.window, page: memory.page, edges: false) {
            told = marked  // the line's rect not one to trust, the marked text's own is
        }
        // Read before `place`, which has `memory` borrowed while it asks Accessibility (reading it in there crashed).
        let needsPage = memory.page == nil
        var placement = memory.place(told, screens: screens, edges: edges) { accessibility(needsPage) }
        if placement.source == .field {
            lastByApp[app ?? ""] = placement.rect
        } else if placement.source == .told, let previous = lastByApp[app ?? ""] {
            placement = PanelAnchor.Placement(rect: previous, source: .last)
        } else if placement.source == .told, let rect = pointerAnchor(pointer, in: memory.window, screens: screens) {
            // A pointer outside the window or over its toolbar isn't one.
            placement = PanelAnchor.Placement(rect: rect, source: .last)
        }
        return Placed(told: told, placement: placement)
    }

    /// The field asked again for the panel's rect (`PanelAnchor.reaskDelays`) after it told none to trust: the rect the
    /// panel moves to (nil: it stays), and the rect it went by. The marked text's rect, which the field is really asked
    /// for each time: InputMethodKit keeps the first `attributes(forCharacterIndex: 0, …)` answer for the whole
    /// composition (caretresearch, 0.6.7), so asking that again would only ever get the page's corner back.
    @MainActor
    public static func reasked(in client: IMKTextInput, selection: Range<Int>?, memory: inout PanelAnchor.Memory,
                               screens: [CGRect]) -> (rect: CGRect?, told: CGRect) {
        let marked = markedAnchor(client)
        let told = marked ?? Self.told(client, selection: selection)
        return (memory.reasked(told, screens: screens, edges: marked == nil), told)
    }

    /// The rect `client` tells for a panel: its marked text's line; for a command on the selection (`selection`), the
    /// selection's last character (nothing is marked to go by).
    @MainActor
    public static func told(_ client: IMKTextInput, selection: Range<Int>?) -> CGRect {
        if let range = selection, !range.isEmpty {
            let rect = client.firstRect(forCharacterRange: NSRange(location: range.upperBound - 1, length: 1), actualRange: nil)
            if rect != .zero { return rect }
        }
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        return lineRect
    }

    /// Where the panel goes by the marked text's own rect (`markedRect`): a line under it, as the line's rect
    /// (`attributes(forCharacterIndex:lineHeightRectangle:)`) is placed, the owner's log showing it one character's height
    /// under the character's rect. Asked of the field every time (`firstRect` isn't kept by InputMethodKit).
    @MainActor
    public static func markedAnchor(_ client: IMKTextInput) -> CGRect? {
        guard let marked = markedRect(client), marked.height > 1 else { return nil }
        return CGRect(x: marked.minX, y: marked.minY - marked.height, width: 1, height: marked.height)
    }

    /// The rect `client` tells for its marked text's first character: where its line's rect isn't one to trust, the field
    /// may still tell this one right (and the log says it, to see what else Chromium tells).
    @MainActor
    public static func markedRect(_ client: IMKTextInput) -> CGRect? {
        let marked = client.markedRange()
        guard marked.location != NSNotFound, marked.length > 0 else { return nil }
        let rect = client.firstRect(forCharacterRange: NSRange(location: marked.location, length: 1), actualRange: nil)
        return rect == .zero ? nil : rect
    }

    /// A line's rect at the pointer (`place`'s last resort), where it is inside `window` below its toolbar band and isn't
    /// itself a rect not to trust. Nil: no window known, the pointer outside it.
    public static func pointerAnchor(_ pointer: () -> CGPoint, in window: CGRect?, screens: [CGRect]) -> CGRect? {
        guard let window else { return nil }
        let pointer = pointer()
        let rect = CGRect(x: pointer.x, y: pointer.y - 9, width: 1, height: 18)
        guard window.insetBy(dx: 8, dy: 8).contains(pointer), pointer.y < window.maxY - 120,
              PanelAnchor.trusted(rect, screens: screens, window: window) else { return nil }
        return rect
    }
}
