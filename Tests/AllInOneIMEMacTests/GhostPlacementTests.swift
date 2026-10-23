import AllInOneIMEMac
import CoreGraphics
import Testing

/// Autocomplete's suggestion after the caret (`GhostPlacement`): on the caret's line, cut at the screen's edge and at the
/// field's, where its frame is known, so that a narrow field's suggestion never covers the window beside it.
struct GhostPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let caret = CGRect(x: 100, y: 500, width: 0, height: 18)
    let size = CGSize(width: 300, height: 16)

    @Test func rightAfterTheCaretOnItsLine() {
        let frame = GhostPlacement.frame(size: size, caret: caret, visible: screen, field: nil)
        #expect(frame == CGRect(x: 101, y: 500, width: 300, height: 18))
        // At the screen's edge: cut there.
        let edge = GhostPlacement.frame(size: size, caret: CGRect(x: 1300, y: 500, width: 0, height: 18), visible: screen, field: nil)
        #expect(edge.maxX == 1440)
    }

    @Test func aNarrowFieldCutsItAtTheFieldsEdge() {
        let field = CGRect(x: 40, y: 490, width: 200, height: 40)
        let frame = GhostPlacement.frame(size: size, caret: caret, visible: screen, field: field)
        #expect(frame.minX == 101 && frame.maxX == 240, "\(frame)")
        // A field wide enough: as wide as the text.
        let wide = GhostPlacement.frame(size: size, caret: caret, visible: screen, field: CGRect(x: 40, y: 490, width: 800, height: 40))
        #expect(wide.width == 300)
        // A frame that doesn't hold the caret isn't the field's (what Accessibility calls focused isn't always it).
        let elsewhere = GhostPlacement.frame(size: size, caret: caret, visible: screen, field: CGRect(x: 600, y: 0, width: 50, height: 50))
        #expect(elsewhere.width == 300)
        // No room at all: the key cap still shows.
        let full = GhostPlacement.frame(size: size, caret: CGRect(x: 239, y: 500, width: 0, height: 18), visible: screen, field: field)
        #expect(full.width == 24)
    }
}
