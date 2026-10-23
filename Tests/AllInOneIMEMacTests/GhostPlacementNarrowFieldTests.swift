import AllInOneIMEMac
import CoreGraphics
import Testing

/// The self-test's narrow field (AutocompleteSelfTest): its harness window's field cut to 160 pt (to x 400), the caret
/// after "Hello wor" at x 319, the suggestion ("ld, how are you?" and its key cap) 144 pt wide: cut at the field's edge.
extension GhostPlacementTests {
    @Test func theSelfTestsNarrowFieldCutsItAtItsEdge() {
        let field = CGRect(x: 240, y: 360, width: 160, height: 72)
        let caret = CGRect(x: 319, y: 374, width: 0, height: 18)
        let frame = GhostPlacement.frame(size: CGSize(width: 144, height: 18), caret: caret, visible: screen, field: field)
        #expect(frame == CGRect(x: 320, y: 374, width: 80, height: 18), "\(frame)")
    }
}
