import AllInOneIMEMac
import CoreGraphics
import Testing

/// A mouse down while something is marked ends it, unless it is on one of the input method's own windows (#116).
struct CompositionLeaveTests {
    @Test func aClickWhileComposingEndsItButNotOnAWindowOfOurs() {
        let panel = CGRect(x: 100, y: 500, width: 300, height: 80)
        #expect(CompositionLeave.mouseDownEnds(at: CGPoint(x: 600, y: 300), marked: true, ownWindows: [panel]))
        #expect(!CompositionLeave.mouseDownEnds(at: CGPoint(x: 150, y: 520), marked: true, ownWindows: [panel]),
                "a candidate row picks it")
        #expect(!CompositionLeave.mouseDownEnds(at: CGPoint(x: 600, y: 300), marked: false, ownWindows: []),
                "nothing marked: nothing to end")
    }

    @Test func aQuartzPointIsFlippedIntoAppKitsCoordinates() {
        #expect(CompositionLeave.appKitPoint(CGPoint(x: 10, y: 100), primaryHeight: 900) == CGPoint(x: 10, y: 800))
    }
}
