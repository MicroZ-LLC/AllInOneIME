import CoreGraphics
import Foundation
import Testing
@testable import AllInOneIMECore

/// A list taller than the panel can be (`CandidateLayout.scrollOffset`): its rows move up as little as brings the
/// highlighted one into view, never past either end.
struct CandidateScrollTests {
    /// Rows 30 points high from y 10, shown in 100 points from there: 10 rows, 200 points more than the room.
    let top: CGFloat = 10, visible: CGFloat = 100, overflow: CGFloat = 200
    func row(_ index: Int) -> CGRect { CGRect(x: 0, y: top + CGFloat(index) * 30, width: 300, height: 30) }
    func offset(from current: CGFloat, showing index: Int?) -> CGFloat {
        CandidateLayout.scrollOffset(from: current, showing: index.map(row), top: top, visible: visible, overflow: overflow)
    }

    @Test func aRowInViewMovesNothing() {
        #expect(offset(from: 0, showing: 0) == 0)
        #expect(offset(from: 0, showing: 2) == 0)
        #expect(offset(from: 60, showing: 3) == 60)
    }

    @Test func downPastTheBottomMovesTheRowsUpByAsLittleAsItTakes() {
        // Row 3 ends at 130 (relative 120): 20 more than the room.
        #expect(offset(from: 0, showing: 3) == 20)
        #expect(offset(from: 20, showing: 4) == 50)
        // The last row: as far as they go.
        #expect(offset(from: 50, showing: 9) == 200)
    }

    @Test func upPastTheTopBringsTheRowDownToIt() {
        #expect(offset(from: 200, showing: 5) == 150)
        #expect(offset(from: 150, showing: 0) == 0)
        // Up one from what shows: the rows move by a row, not back to the top.
        #expect(offset(from: 200, showing: 8) == 200 && offset(from: 200, showing: 6) == 180)
    }

    @Test func withoutAHighlightTheRowsStayWithinTheirEnds() {
        #expect(offset(from: 120, showing: nil) == 120)
        #expect(offset(from: 500, showing: nil) == 200 && offset(from: -5, showing: nil) == 0)
    }

    @Test func aRowTallerThanTheRoomShowsItsTop() {
        let tall = CGRect(x: 0, y: 70, width: 300, height: 180)
        #expect(CandidateLayout.scrollOffset(from: 0, showing: tall, top: top, visible: visible, overflow: overflow) == 60)
        #expect(CandidateLayout.scrollOffset(from: 190, showing: tall, top: top, visible: visible, overflow: overflow) == 60)
    }
}
