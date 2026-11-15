import Foundation
import Testing
@testable import AllInOneIMECore

/// Acceptance cases for the platform-neutral panel frame in Cocoa coordinates.
struct PanelPlacementAcceptanceTests {
    let panel = CGSize(width: 180, height: 100)
    let main = ScreenInfo(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
    )

    @Test func usesTheDisplayToTheLeftOfTheMainDisplay() {
        let left = ScreenInfo(
            frame: CGRect(x: -800, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: -800, y: 0, width: 800, height: 600)
        )
        let caret = CGRect(x: -500, y: 300, width: 2, height: 20)
        let placed = PanelPlacement.frame(caret: caret, panel: panel, screens: [main, left])

        #expect(left.visibleFrame.contains(placed))
        #expect(placed.maxY <= caret.minY)
        #expect(placed.size == panel)
    }

    @Test func usesTheDisplayAboveTheMainDisplay() {
        let upper = ScreenInfo(
            frame: CGRect(x: 0, y: 800, width: 1000, height: 500),
            visibleFrame: CGRect(x: 0, y: 800, width: 1000, height: 500)
        )
        let caret = CGRect(x: 350, y: 1050, width: 2, height: 20)
        let placed = PanelPlacement.frame(caret: caret, panel: panel, screens: [main, upper])

        #expect(upper.visibleFrame.contains(placed))
        #expect(placed.maxY <= caret.minY)
    }

    @Test func screenChoiceUsesTheCaretsMidpointAcrossADisplayBoundary() {
        let left = ScreenInfo(
            frame: CGRect(x: -800, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: -800, y: 0, width: 800, height: 600)
        )
        let caret = CGRect(x: -20, y: 250, width: 60, height: 20)
        let placed = PanelPlacement.frame(caret: caret, panel: panel, screens: [left, main])

        #expect(main.visibleFrame.contains(placed))
    }

    @Test func staysVisibleAtEachEdgeOfTheScreen() {
        let left = CGRect(x: 2, y: 400, width: 2, height: 20)
        let right = CGRect(x: 995, y: 400, width: 2, height: 20)
        let bottom = CGRect(x: 400, y: 5, width: 2, height: 20)
        let top = CGRect(x: 400, y: 775, width: 2, height: 20)

        for caret in [left, right, bottom, top] {
            let placed = PanelPlacement.frame(caret: caret, panel: panel, screens: [main])
            #expect(main.visibleFrame.contains(placed), "caret: \(caret)")
        }
        #expect(PanelPlacement.frame(caret: bottom, panel: panel, screens: [main]).minY >= bottom.maxY)
        #expect(PanelPlacement.frame(caret: top, panel: panel, screens: [main]).maxY <= top.minY)
    }

    @Test func movesAboveWhenThePanelCannotFitBelowTheCaret() {
        let caret = CGRect(x: 400, y: 80, width: 2, height: 20)
        let placed = PanelPlacement.frame(caret: caret, panel: panel, screens: [main])

        #expect(placed.minY >= caret.maxY)
        #expect(main.visibleFrame.contains(placed))
    }

    @Test func aPanelTallerThanTheScreenKeepsItsTopVisible() {
        let tall = CGSize(width: 180, height: 900)
        let caret = CGRect(x: 400, y: 400, width: 2, height: 20)
        let placed = PanelPlacement.frame(caret: caret, panel: tall, screens: [main])

        // ASSUMPTION: When no position can fit the requested size, keep that size and show its top,
        // matching PanelPlacement.onScreen's existing behavior for an oversized panel.
        #expect(placed.size == tall)
        #expect(placed.maxY == main.visibleFrame.maxY)
        #expect(placed.minX >= main.visibleFrame.minX && placed.maxX <= main.visibleFrame.maxX)
    }

    @Test func aCaretBetweenDisplaysUsesTheNearestDisplay() {
        let far = ScreenInfo(
            frame: CGRect(x: 2000, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 2000, y: 0, width: 1000, height: 800)
        )
        let caret = CGRect(x: 1250, y: 300, width: 2, height: 20)
        let placed = PanelPlacement.frame(caret: caret, panel: panel, screens: [far, main])

        // ASSUMPTION: An off-screen caret with no other anchor available uses the nearest screen.
        #expect(main.visibleFrame.contains(placed))
    }

    @Test func aZeroCaretRectangleGetsASafeVisibleFallback() {
        let placed = PanelPlacement.frame(caret: .zero, panel: panel, screens: [main])

        // ASSUMPTION: This pure function has no pointer or previous-anchor input, so its fallback
        // is a finite frame on an available screen; the Mac adapter supplies richer anchor history.
        #expect(main.visibleFrame.contains(placed))
        #expect(placed.size == panel)
        #expect(placed.minX.isFinite && placed.minY.isFinite)
    }

    @Test func respectsTheDockAndMenuBarInsideTheScreenFrame() {
        let screen = ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 50, width: 900, height: 700)
        )
        let nearDock = CGRect(x: 990, y: 400, width: 2, height: 20)
        let nearMenuBar = CGRect(x: 400, y: 775, width: 2, height: 20)

        for caret in [nearDock, nearMenuBar] {
            let placed = PanelPlacement.frame(caret: caret, panel: panel, screens: [screen])
            #expect(screen.visibleFrame.contains(placed), "caret: \(caret)")
        }
        #expect(PanelPlacement.frame(caret: nearDock, panel: panel, screens: [screen]).maxX == screen.visibleFrame.maxX)
        #expect(PanelPlacement.frame(caret: nearMenuBar, panel: panel, screens: [screen]).maxY <= nearMenuBar.minY)
    }
}
