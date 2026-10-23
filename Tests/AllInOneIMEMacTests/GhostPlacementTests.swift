import AllInOneIMEMac
import CoreGraphics
import Testing

/// Autocomplete's suggestion after the caret (`GhostPlacement`): on the caret's line, cut at the screen's edge and at the
/// field's, where its frame is known, so that a narrow field's suggestion never covers the window beside it; not shown at
/// all where its text would get less room than a few of its characters.
struct GhostPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let caret = CGRect(x: 100, y: 500, width: 0, height: 18)
    /// The text and the key cap (`chrome` of it: the cap and the gaps beside it), and its first few characters' width.
    let size = CGSize(width: 300, height: 16)
    let chrome: CGFloat = 30
    let few: CGFloat = 26

    func frame(_ size: CGSize? = nil, caret: CGRect? = nil, visible: CGRect? = nil, field: CGRect? = nil, few: CGFloat? = nil) -> CGRect? {
        GhostPlacement.frame(size: size ?? self.size, caret: caret ?? self.caret, visible: visible ?? screen, field: field,
                             chrome: chrome, minimumText: few ?? self.few)
    }

    @Test func rightAfterTheCaretOnItsLine() {
        #expect(frame() == CGRect(x: 101, y: 500, width: 300, height: 18))
        // At the screen's edge: cut there.
        let edge = frame(caret: CGRect(x: 1300, y: 500, width: 0, height: 18))
        #expect(edge?.maxX == 1440)
    }

    @Test func aNarrowFieldCutsItAtTheFieldsEdge() {
        let field = CGRect(x: 40, y: 490, width: 200, height: 40)
        let cut = frame(field: field)
        #expect(cut?.minX == 101 && cut?.maxX == 240, "\(String(describing: cut))")
        // A field wide enough: as wide as the text.
        #expect(frame(field: CGRect(x: 40, y: 490, width: 800, height: 40))?.width == 300)
        // A frame that doesn't hold the caret isn't the field's (what Accessibility calls focused isn't always it).
        #expect(frame(field: CGRect(x: 600, y: 0, width: 50, height: 50))?.width == 300)
    }

    /// Where the text would get less than its first few characters (the key cap alone, or a sliver of text), nothing
    /// shows: Tab then is the app's (the shell tells the session, `SessionEvent.ghostNotShown`).
    @Test func tooLittleRoomForItsTextShowsNothing() {
        let field = CGRect(x: 40, y: 490, width: 200, height: 40)
        func at(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 500, width: 0, height: 18) }
        // No room at all, or room for the key cap only: none.
        #expect(frame(caret: at(239), field: field) == nil)
        #expect(frame(caret: at(240 - 1 - chrome), field: field) == nil)
        // Room for its first few characters: shown, cut; a point less: none.
        let least = frame(caret: at(240 - 1 - chrome - few), field: field)
        #expect(least?.width == chrome + few && least?.maxX == 240, "\(String(describing: least))")
        #expect(frame(caret: at(240 - chrome - few), field: field) == nil)
        // At the screen's edge alike.
        #expect(frame(caret: at(1440 - 1 - chrome))?.width == nil)
        #expect(frame(caret: at(1440 - 1 - chrome - few))?.width == chrome + few)
        // A suggestion shorter than a few characters shows only whole.
        let short = CGSize(width: chrome + 10, height: 16)
        #expect(frame(short, caret: at(240 - 1 - chrome - 10), field: field, few: 10)?.width == chrome + 10)
        #expect(frame(short, caret: at(240 - chrome - 10), field: field, few: 10) == nil)
    }

    /// The line and the x the suggestion goes at: Notes's numbers (its caret and the character before it a line above the
    /// panel's line, which is as narrow as a caret) put it on the panel's line at its x; a wide line takes the caret's x
    /// where the caret is on it, the end of the character before where only that is.
    @Test func theLineAsNarrowAsACaretIsTheCaret() {
        let notesLine = CGRect(x: 883.7, y: 426, width: 1, height: 16)
        let notesCaret = CGRect(x: 883.7, y: 442, width: 0, height: 16)
        let notesPrevious = CGRect(x: 870.8, y: 442, width: 12.9, height: 16)
        let placed = GhostPlacement.line(notesLine, caret: notesCaret, previous: notesPrevious)
        #expect(placed?.line == notesLine && placed?.x == 883.7, "\(String(describing: placed))")
        let wide = CGRect(x: 40, y: 500, width: 400, height: 18)
        #expect(GhostPlacement.line(wide, caret: CGRect(x: 120, y: 500, width: 0, height: 18), previous: nil)?.x == 120)
        #expect(GhostPlacement.line(wide, caret: CGRect(x: 120, y: 511, width: 0, height: 18),
                                    previous: CGRect(x: 100, y: 501, width: 12, height: 18))?.x == 112)
        // A caret more than a line from a wide line, or no line told at all: the candidate panel's line.
        #expect(GhostPlacement.line(wide, caret: CGRect(x: 120, y: 540, width: 0, height: 18), previous: nil) == nil)
        #expect(GhostPlacement.line(nil, caret: nil, previous: nil) == nil)
        // No line told: the caret's own rect is the line.
        #expect(GhostPlacement.line(nil, caret: CGRect(x: 120, y: 500, width: 0, height: 18), previous: nil)?.x == 120)
    }
}
