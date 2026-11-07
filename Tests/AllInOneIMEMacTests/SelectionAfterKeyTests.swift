import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac

/// The selection read after the "@" key, as a key waits for it on its own thread (`SelectionAfterKey`): the wait ends when
/// the read lands, from the thread that read it, or at the deadline when it never answers; a late answer is dropped.
struct SelectionAfterKeyTests {
    static let selected = Composer.Selection(text: "hello there")

    /// A read that never answers: the key waits until the deadline, not longer, and then none counts.
    @Test func theWaitEndsAtTheDeadlineWhenTheReadNeverAnswers() {
        let reads = SelectionAfterKey()
        reads.started(1)
        let start = Date()
        #expect(reads.wait(for: 1, timeout: InputSession.selectionWait) == nil)
        let waited = Date().timeIntervalSince(start)
        #expect(waited >= InputSession.selectionWait - 0.01 && waited < InputSession.selectionWait + 1, "\(waited) s")
        // Its answer, later: dropped, and nothing waits for it any more.
        reads.landed(1, Self.selected)
        let again = Date()
        #expect(reads.wait(for: 1, timeout: InputSession.selectionWait) == nil && Date().timeIntervalSince(again) < 0.1)
    }

    /// A read that lands before the key or while it waits, on another thread (the main one isn't needed): its answer, as
    /// soon as it is in.
    @Test func theWaitEndsWhenTheReadLands() {
        let reads = SelectionAfterKey()
        reads.started(1)
        reads.landed(1, Self.selected)
        #expect(reads.wait(for: 1, timeout: InputSession.selectionWait) == Self.selected)

        reads.started(2)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { reads.landed(2, Self.selected) }
        let start = Date()
        #expect(reads.wait(for: 2, timeout: 5) == Self.selected)
        #expect(Date().timeIntervalSince(start) < 4, "not the deadline")

        reads.started(3)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { reads.landed(3, nil) }
        #expect(reads.wait(for: 3, timeout: 5) == nil, "nothing selected")
    }

    /// Another read started since: the one before is waited for no more, and what it answers is dropped.
    @Test func onlyTheReadInFlightCounts() {
        let reads = SelectionAfterKey()
        reads.started(1)
        reads.started(2)
        reads.landed(1, Self.selected)
        let start = Date()
        #expect(reads.wait(for: 1, timeout: 5) == nil && Date().timeIntervalSince(start) < 1, "not the read in flight")
        reads.landed(2, nil)
        #expect(reads.wait(for: 2, timeout: 5) == nil)
    }
}
