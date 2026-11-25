import Foundation
import Testing
import AllInOneIMECore

/// Where the panel at the caret goes (`PanelPlacement.frame(caret:panel:screens:)`, `atCaret`): under the caret, above it
/// where it doesn't fit below, inside the visible part of the screen the caret's middle is on (the nearest one where it
/// is on none); a caret told as nothing goes by the pointer. The Mac's candidate panel placed it so before it moved here
/// (CandidatePanelLayoutTests checks it there too).
struct PanelPlacementCaretTests {
    /// A 1440×900 main screen, the menu bar 25 high and the Dock 70.
    let main = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
    /// A display to the main one's left, its x below 0, no Dock on it.
    let left = ScreenInfo(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                          visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055))
    let panel = CGSize(width: 300, height: 200)
    /// The caret at the end of a line: a line high, one point wide.
    let line = CGRect(x: 640, y: 420, width: 1, height: 18)

    @Test func underTheCaretWhereItFits() {
        let placed = PanelPlacement.atCaret(panel, caret: line, screens: [main])
        #expect(placed.side == .below)
        #expect(placed.frame == CGRect(x: 640, y: 420 - PanelPlacement.caretGap - 200, width: 300, height: 200))
        #expect(PanelPlacement.frame(caret: line, panel: panel, screens: [main]) == placed.frame)
    }

    @Test func aboveTheCaretWhereItDoesNotFitBelow() {
        let low = CGRect(x: 640, y: 120, width: 1, height: 18)
        let placed = PanelPlacement.atCaret(panel, caret: low, screens: [main])
        #expect(placed.side == .above)
        #expect(placed.frame.minY == low.maxY + PanelPlacement.caretGap)
    }

    /// Above as long as it fits there while typing on that line (`keeping`), else as anywhere.
    @Test func theSideItIsOnIsKeptWhereItFits() {
        #expect(PanelPlacement.atCaret(panel, caret: line, screens: [main], keeping: .above).side == .above)
        let high = CGRect(x: 640, y: 800, width: 1, height: 18)
        #expect(PanelPlacement.atCaret(panel, caret: high, screens: [main], keeping: .above).side == .below)
    }

    /// Too tall for either side: on the side with more room, moved onto the screen.
    @Test func tooTallGoesOnTheSideWithMoreRoom() {
        let huge = CGSize(width: 300, height: 900)
        let low = CGRect(x: 640, y: 200, width: 1, height: 18), high = CGRect(x: 640, y: 700, width: 1, height: 18)
        #expect(PanelPlacement.atCaret(huge, caret: low, screens: [main]).side == .above)
        #expect(PanelPlacement.atCaret(huge, caret: high, screens: [main]).side == .below)
        let frame = PanelPlacement.frame(caret: high, panel: huge, screens: [main])
        #expect(frame.minY == main.visibleFrame.maxY - huge.height, "its top kept on the screen: \(frame)")
    }

    /// The first candidate's text under the caret; never past the visible part's edges.
    @Test func keptInsideTheVisiblePart() {
        #expect(PanelPlacement.atCaret(panel, caret: line, screens: [main], textInset: 12).frame.minX == 628)
        let edge = CGRect(x: 1400, y: 420, width: 1, height: 18)
        #expect(PanelPlacement.frame(caret: edge, panel: panel, screens: [main]).maxX == main.visibleFrame.maxX)
        let start = CGRect(x: 2, y: 420, width: 1, height: 18)
        #expect(PanelPlacement.atCaret(panel, caret: start, screens: [main], textInset: 12).frame.minX == 0)
        // Above the Dock: a caret just over it has the panel above.
        let overDock = CGRect(x: 640, y: 80, width: 1, height: 18)
        #expect(PanelPlacement.frame(caret: overDock, panel: panel, screens: [main]).minY >= main.visibleFrame.minY)
    }

    /// On a display to the left (x below 0): inside its own visible part, not the main screen's.
    @Test func onADisplayToTheLeft() {
        let caret = CGRect(x: -800, y: 500, width: 1, height: 18)
        let frame = PanelPlacement.frame(caret: caret, panel: panel, screens: [main, left])
        #expect(frame == CGRect(x: -800, y: 500 - PanelPlacement.caretGap - 200, width: 300, height: 200))
        let edge = CGRect(x: -100, y: 500, width: 1, height: 18)
        #expect(PanelPlacement.frame(caret: edge, panel: panel, screens: [main, left]).maxX == 0, "kept on the left display")
    }

    /// The screen the caret's middle is on: a caret whose bottom is on the main screen and whose middle is on the one
    /// above it goes on the one above.
    @Test func theScreenIsTheOneTheCaretsMiddleIsOn() {
        let upper = ScreenInfo(frame: CGRect(x: 0, y: 900, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 900, width: 1440, height: 900))
        let straddling = CGRect(x: 100, y: 895, width: 1, height: 18)
        #expect(PanelPlacement.screen(for: straddling, among: [main, upper]) == upper)
        let frame = PanelPlacement.frame(caret: straddling, panel: panel, screens: [main, upper])
        #expect(frame.minY >= upper.visibleFrame.minY, "inside the upper screen: \(frame)")
    }

    /// A caret off every screen (a display gone): the nearest screen's visible part.
    @Test func offEveryScreenTheNearestOne() {
        let right = ScreenInfo(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
        let off = CGRect(x: 5000, y: 300, width: 1, height: 18)
        #expect(PanelPlacement.screen(for: off, among: [main, right]) == right)
        let frame = PanelPlacement.frame(caret: off, panel: panel, screens: [main, right])
        #expect(frame.maxX == right.visibleFrame.maxX && frame.minY == 300 - PanelPlacement.caretGap - 200)
        let farLeft = CGRect(x: -5000, y: 300, width: 1, height: 18)
        #expect(PanelPlacement.frame(caret: farLeft, panel: panel, screens: [main, right]).minX == 0)
        #expect(PanelPlacement.screen(for: off, among: []) == nil)
    }

    /// A caret told as nothing (an empty rect at the origin, not a number): a line under the pointer, else the middle of
    /// the main screen's visible part.
    @Test func aCaretToldAsNothingGoesByThePointer() {
        let pointer = CGPoint(x: 700, y: 600)
        let underPointer = CGRect(x: 700, y: 582, width: 0, height: 18)
        #expect(PanelPlacement.usable(.zero, screens: [main], pointer: pointer) == underPointer)
        #expect(PanelPlacement.usable(CGRect(x: CGFloat.nan, y: 10, width: 0, height: 18), screens: [main], pointer: pointer) == underPointer)
        #expect(PanelPlacement.atCaret(panel, caret: .zero, screens: [main], pointer: pointer).frame.maxY == 582 - PanelPlacement.caretGap)
        #expect(PanelPlacement.usable(.zero, screens: [main]) == CGRect(x: 720, y: 472.5 - 18, width: 0, height: 18))
        // An empty rect anywhere else is the field's: used as it is.
        let empty = CGRect(x: 100, y: 860, width: 0, height: 0)
        #expect(PanelPlacement.usable(empty, screens: [main], pointer: pointer) == empty)
    }

    @Test func noScreenKnown() {
        let frame = PanelPlacement.frame(caret: line, panel: panel, screens: [])
        #expect(frame == CGRect(x: 640, y: 216, width: 300, height: 200))
        #expect(PanelPlacement.assumedScreen.contains(frame))
    }

    @Test func onTheSameLine() {
        let further = line.offsetBy(dx: 30, dy: 0), next = line.offsetBy(dx: 0, dy: -22)
        #expect(PanelPlacement.onTheSameLine(line, further, screens: [main]))
        #expect(!PanelPlacement.onTheSameLine(line, next, screens: [main]))
    }
}
