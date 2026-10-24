import AllInOneIMEMac
import CoreGraphics
import Testing

/// Where a panel at the caret goes (`PanelAnchor`): under the rect the field tells, where it is one to trust; else the
/// caret Accessibility tells, else the last rect to trust in that field, else the rect as told; a rect to trust told
/// later (the field asked again) moves it there. Chrome's numbers: a web view whose page starts under the toolbar.
struct PanelAnchorTests {
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    let window = CGRect(x: 100, y: 80, width: 1200, height: 780)
    /// The page's web area: the window less its toolbar.
    let page = CGRect(x: 100, y: 80, width: 1200, height: 690)
    /// Pinyin's marked text at the end of a line, where the field tells it.
    let line = CGRect(x: 640, y: 420, width: 12, height: 18)

    final class Client {}
    let client = Client(), other = Client()

    func field(_ client: Client, app: String? = "com.google.Chrome", session: Int = 1) -> PanelAnchor.Field {
        PanelAnchor.Field(client: ObjectIdentifier(client), app: app, session: session)
    }

    /// Chromium's rect before the page's bounds came: none high, at the page's top-left corner.
    var pageCorner: CGRect { CGRect(x: page.minX, y: page.maxY, width: 0, height: 0) }

    @Test func aRectToTrustIsUsedAsItIs() {
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        var asked = 0
        let placed = memory.place(line, screens: screens) {
            asked += 1
            return nil
        }
        #expect(placed == PanelAnchor.Placement(rect: line, source: .field) && !placed.reasks)
        // Accessibility isn't asked: it costs time, and the field told its caret.
        #expect(asked == 0 && memory.last == line)
    }

    @Test func whatIsNotARectToTrust() {
        #expect(PanelAnchor.trusted(line, screens: screens))
        // A caret is as narrow as a line: trusted.
        #expect(PanelAnchor.trusted(CGRect(x: 640, y: 420, width: 0, height: 18), screens: screens))
        // Empty, no height, the screen's origin, not a number.
        #expect(!PanelAnchor.trusted(.zero, screens: screens))
        #expect(!PanelAnchor.trusted(CGRect(x: 640, y: 420, width: 12, height: 0), screens: screens))
        #expect(!PanelAnchor.trusted(CGRect(x: 0, y: 0, width: 1, height: 18), screens: screens))
        #expect(!PanelAnchor.trusted(CGRect(x: CGFloat.nan, y: 420, width: 0, height: 18), screens: screens))
        // At the window's or the page's top-left corner, high or not: where Chromium's rect goes without the page's bounds.
        #expect(!PanelAnchor.trusted(pageCorner, screens: screens, window: window, page: page))
        #expect(!PanelAnchor.trusted(CGRect(x: page.minX, y: page.maxY - 18, width: 1, height: 18), screens: screens, page: page))
        #expect(!PanelAnchor.trusted(CGRect(x: window.minX + 1, y: window.maxY - 17, width: 1, height: 18), screens: screens, window: window))
        // Anywhere else in them, trusted.
        #expect(PanelAnchor.trusted(line, screens: screens, window: window, page: page))
        // No screen known: not checked.
        #expect(PanelAnchor.trusted(CGRect(x: 5000, y: 420, width: 0, height: 18), screens: []))
    }

    /// Google Docs (owner's report, 0.6.7): the rect for marked text is a line high on the window's left edge, under
    /// Chrome's toolbar (its hidden element, not at the caret), the page's frame unknown: not trusted once the window's
    /// frame is known, asked once in the field before its first rect is judged.
    @Test func aLineHighOnTheWindowsLeftEdgeNearItsTopIsNotTrusted() {
        let docs = CGRect(x: window.minX, y: window.maxY - 110, width: 1, height: 18)
        #expect(PanelAnchor.trusted(docs, screens: screens), "no window known: as before")
        #expect(!PanelAnchor.trusted(docs, screens: screens, window: window))
        // The same edge lower down, or a caret a little in from it: trusted.
        #expect(PanelAnchor.trusted(CGRect(x: window.minX, y: window.maxY - 400, width: 1, height: 18), screens: screens, window: window))
        #expect(PanelAnchor.trusted(CGRect(x: window.minX + 24, y: window.maxY - 110, width: 1, height: 18), screens: screens, window: window))

        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        var asked = 0
        memory.learnWindow {
            asked += 1
            return (window, false)
        }
        memory.learnWindow {
            asked += 1
            return (window, false)
        }
        #expect(asked == 1 && memory.window == window, "once in a field")
        memory.place(line, screens: screens) { nil }
        let placed = memory.place(docs, screens: screens) { nil }
        #expect(placed == PanelAnchor.Placement(rect: line, source: .last) && placed.reasks)
        // Another field asks again.
        memory.enter(field(other))
        memory.learnWindow {
            asked += 1
            return (nil, true)
        }
        #expect(asked == 2 && memory.window == nil && memory.accessibilityGivenUp)
    }

    @Test func aRectOffEveryScreenIsNotTrusted() {
        let off = CGRect(x: 5000, y: 3000, width: 0, height: 18)
        #expect(!PanelAnchor.trusted(off, screens: screens))
        // A second screen on the left has it.
        #expect(PanelAnchor.trusted(CGRect(x: -800, y: 300, width: 0, height: 18), screens: screens + [CGRect(x: -1920, y: 0, width: 1920, height: 1080)]))
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        // Nothing better known: as told, as before; asked again.
        let placed = memory.place(off, screens: screens) { nil }
        #expect(placed == PanelAnchor.Placement(rect: off, source: .told) && placed.reasks)
        #expect(memory.last == nil)
    }

    @Test func aZeroRectAtTheWindowsTopLeftUsesAccessibilitysCaret() {
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        memory.place(line, screens: screens) { nil }  // a rect to trust before: the caret goes first all the same
        let caret = CGRect(x: 652, y: 420, width: 0, height: 18)
        let corner = CGRect(x: window.minX, y: window.maxY, width: 0, height: 0)
        let placed = memory.place(corner, screens: screens) {
            PanelAnchor.Accessibility(caret: caret, window: window, page: page)
        }
        #expect(placed == PanelAnchor.Placement(rect: caret, source: .accessibility) && placed.reasks)
        #expect(memory.window == window && memory.page == page)
        // Not a rect to trust itself: the last one's then.
        #expect(memory.place(pageCorner, screens: screens) { PanelAnchor.Accessibility(caret: pageCorner, window: window) }.source == .last)
        // Outside the focused window, or no window told: not the caret of this field.
        let elsewhere = CGRect(x: 1350, y: 420, width: 0, height: 18)
        #expect(memory.place(pageCorner, screens: screens) { PanelAnchor.Accessibility(caret: elsewhere, window: window) }.source == .last)
        var fresh = PanelAnchor.Memory()
        fresh.enter(field(client))
        #expect(fresh.place(pageCorner, screens: screens) { PanelAnchor.Accessibility(caret: caret) }.source == .told)
    }

    @Test func noCaretFromAccessibilityUsesTheLastRectToTrust() {
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        memory.place(line, screens: screens) { nil }
        // Accessibility not allowed, or no caret told (Chrome without its page's tree): the last rect, as it was.
        #expect(memory.place(pageCorner, screens: screens) { nil } == PanelAnchor.Placement(rect: line, source: .last))
        let placed = memory.place(pageCorner, screens: screens) { PanelAnchor.Accessibility(window: window, page: page) }
        #expect(placed == PanelAnchor.Placement(rect: line, source: .last) && placed.reasks)
        // The page's frame known now: its top-left corner, even with a height, isn't trusted any more.
        let high = CGRect(x: page.minX, y: page.maxY - 18, width: 0, height: 18)
        #expect(memory.place(high, screens: screens) { nil }.source == .last)
    }

    @Test func aRectToTrustToldWhenAskedAgainReplacesTheFallback() {
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        memory.place(line, screens: screens) { nil }
        let next = CGRect(x: 40, y: 380, width: 12, height: 18)  // the next line's start, the caret there now
        #expect(memory.place(pageCorner, screens: screens) { nil }.rect == line)
        // 40 ms later still none: the panel stays; then the page's bounds came.
        #expect(memory.reasked(pageCorner, screens: screens) == nil)
        #expect(memory.reasked(next, screens: screens) == next)
        // Remembered: the next fallback is it.
        #expect(memory.last == next)
        #expect(memory.place(.zero, screens: screens) { nil } == PanelAnchor.Placement(rect: next, source: .last))
    }

    @Test func anotherFieldForgetsTheLastRect() {
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        memory.place(line, screens: screens) { PanelAnchor.Accessibility(window: window, page: page) }
        memory.place(pageCorner, screens: screens) { PanelAnchor.Accessibility(window: window, page: page) }
        // The same field again: kept.
        memory.enter(field(client))
        #expect(memory.last == line && memory.page == page)
        // Another client, another app, another focus session of the same field: forgotten, the frames too.
        for next in [field(other), field(client, app: "com.apple.Notes"), field(client, session: 2)] {
            var copy = memory
            copy.enter(next)
            #expect(copy.last == nil && copy.window == nil && copy.page == nil)
            #expect(copy.place(pageCorner, screens: screens) { nil } == PanelAnchor.Placement(rect: pageCorner, source: .told))
        }
        // The field left.
        memory.forget()
        #expect(memory.last == nil && memory.field == nil)
    }

    /// An app whose Accessibility times out isn't asked again in that field: it would hold up every key.
    @Test func accessibilityTimedOutIsNotAskedAgainInTheField() {
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        var asked = 0
        func read() -> PanelAnchor.Accessibility? {
            asked += 1
            return PanelAnchor.Accessibility(timedOut: true)
        }
        #expect(memory.place(pageCorner, screens: screens, accessibility: read).source == .told)
        #expect(memory.place(pageCorner, screens: screens, accessibility: read).source == .told)
        #expect(asked == 1 && memory.accessibilityGivenUp)
        memory.enter(field(client, session: 2))
        #expect(!memory.accessibilityGivenUp)
    }

    /// The Electron harness's numbers, a hidden input of no size at the page's top-left (Chromium's answers to
    /// `firstRect(forCharacterRange:)` there): the web view at x 40, its top at y 648; the caret's rect empty at that
    /// corner, the marked text's a line high under it. Once Accessibility told the page's frame, neither is trusted.
    @Test func theHarnesssHiddenInputAtThePagesCorner() {
        let screen = [CGRect(x: 0, y: 0, width: 1280, height: 720)]
        let web = CGRect(x: 40, y: 440, width: 520, height: 208), window = CGRect(x: 40, y: 440, width: 520, height: 240)
        let caret = CGRect(x: 40, y: 648, width: 0, height: 0), marked = CGRect(x: 40, y: 633, width: 1, height: 15)
        var memory = PanelAnchor.Memory()
        memory.enter(field(client))
        #expect(memory.place(caret, screens: screen) { PanelAnchor.Accessibility(window: window, page: web) }.source == .told)
        #expect(memory.place(marked, screens: screen) { nil }.source == .told)
        #expect(memory.reasked(marked, screens: screen) == nil)
        // The page's bounds come: a rect inside it is trusted.
        let line = CGRect(x: 57, y: 607, width: 1, height: 16)
        #expect(memory.reasked(line, screens: screen) == line)
    }

    @Test func accessibilitysRectsInAppKitsCoordinates() {
        // 100 pt from the main screen's top, 18 high, on a screen 900 high.
        #expect(PanelAnchor.appKit(CGRect(x: 640, y: 100, width: 0, height: 18), top: 900) == CGRect(x: 640, y: 782, width: 0, height: 18))
    }
}
