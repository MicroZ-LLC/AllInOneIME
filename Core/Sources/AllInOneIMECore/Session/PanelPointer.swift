/// The pointer over a shell's candidate panel, and whose it is: what a click on a row, a right-click, the wheel and a
/// click on Translate as You Type's chip do. The Mac's panel is one for the process (`CandidatePanel.shared`), and every
/// text field's controller shows its things in it: its candidates and lists, a notice, autocomplete's line, the
/// chip. Whoever shows something there takes the pointer with every handler at once (`take`), nil for one it has none
/// of: none is left to whoever showed the panel before. What the image preview beside the panel follows (the panel shown,
/// the row under the pointer) is the preview's, whoever shows the panel, and none of this.
///
/// A text field's session has the wheel over whatever it shows (`Handlers.session`): a wheel over our panel is no pointer
/// use in the field (`SessionEvent.scroll`), so the keys the panel says are ours stay ours. GitHub #66: autocomplete's
/// line ("Tab accept · Esc dismiss") and the notices took the panel but left the wheel to the field that last showed rows
/// there; a wheel over the line then counted as the pointer used in its own field, and Tab and Esc went to the app.
/// One thread's: the Mac's main thread.
public final class PanelPointer<ChipPart> {
    /// What the pointer does over the panel, nil where it does nothing: `select` a click on a row, `delete` a right-click
    /// (or a Control-click) on one, each with the row's index in the panel's rows; `scroll` the wheel or the trackpad over
    /// the panel, rows to move (down positive; 0 short of a row); `chip` a click on a part of the chip.
    public struct Handlers {
        public var select: ((Int) -> Void)?
        public var delete: ((Int) -> Void)?
        public var scroll: ((Int) -> Void)?
        public var chip: ((ChipPart) -> Void)?

        /// Every one given, nil for none: none can be left out.
        public init(select: ((Int) -> Void)?, delete: ((Int) -> Void)?, scroll: ((Int) -> Void)?, chip: ((ChipPart) -> Void)?) {
            self.select = select
            self.delete = delete
            self.scroll = scroll
            self.chip = chip
        }

        /// None: what no text field shows (a notice near the pointer).
        public static var none: Handlers { Handlers(select: nil, delete: nil, scroll: nil, chip: nil) }

        /// What a text field's session shows, `send` handing the session an event: the wheel, always (`.scroll`); a click
        /// and a right-click on a row (`.pick`, `.delete`) only where it shows rows to pick (`rows`: its candidates and
        /// lists, not a notice or autocomplete's line); a click on the chip to `chip`.
        public static func session(_ send: @escaping (SessionEvent) -> Void, rows: Bool = false,
                                   chip: ((ChipPart) -> Void)? = nil) -> Handlers {
            Handlers(select: rows ? { send(.pick($0)) } : nil, delete: rows ? { send(.delete($0)) } : nil,
                     scroll: { send(.scroll($0)) }, chip: chip)
        }
    }

    /// Whoever showed what the panel shows (nil: nobody yet, or gone).
    public private(set) weak var owner: AnyObject?
    public private(set) var handlers = Handlers.none

    public init() {}

    /// Taken by `owner` for what it shows: every handler its own from now on (nil, nobody's: none).
    public func take(by owner: AnyObject?, _ handlers: Handlers) {
        self.owner = owner
        self.handlers = handlers
    }

    // What the panel's view tells.

    public func clicked(_ row: Int) { handlers.select?(row) }
    public func rightClicked(_ row: Int) { handlers.delete?(row) }
    public func scrolled(_ rows: Int) { handlers.scroll?(rows) }
    public func chipClicked(_ part: ChipPart) { handlers.chip?(part) }
}
