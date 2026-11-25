import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// After "@", while the field's selection is still being read (`selectionPending`), ↓ moves the one @ highlight. When
/// the read comes back with nothing selected (or gives up, which is the same), the highlight stays on the row the user
/// moved to: it doesn't jump back to the first row, in the composer or in the panel built from it.
@Suite(.serialized)
struct OneAtHighlightDuringSelectionReadTests {
    /// A field with "hello there", nothing selected, that reads the selection after the key (`selectionFollows`); "@"
    /// typed, the read still in flight.
    func reading() -> FakeHost {
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        host.document = "hello there"
        host.selection = nil
        host.selectionReadsWait = true
        var told = host.context
        told.selection = nil
        told.selectionFollows = true
        host.press(FakeHost.at, with: told)
        return host
    }

    func check(downs: Int, land: (FakeHost) -> Void) throws {
        let host = reading()
        #expect(host.composer.selectionPending)
        #expect(host.composer.oneAtHighlighted == 0)
        for _ in 0..<downs { host.press(FakeHost.down) }
        #expect(host.composer.selectionPending, "↓ doesn't settle the read")
        let moved = host.composer.oneAtHighlighted
        #expect(moved == downs, "↓ moved the highlight: \(moved)")
        let row = try #require(host.composer.oneAtRows.indices.contains(moved) ? host.composer.oneAtRows[moved] : nil)

        land(host)
        let c = host.composer
        #expect(!c.selectionPending && c.selection == nil)
        #expect(c.oneAtHighlighted == moved, "kept on the row moved to, not back to the first: \(c.oneAtHighlighted)")
        #expect(c.oneAtRows.indices.contains(c.oneAtHighlighted) && c.oneAtRows[c.oneAtHighlighted].id == row.id,
                "the same row: \(c.oneAtRows.map(\.id))")

        _ = PanelPresenter(config: .default, language: "en").model(for: c)
        #expect(c.oneAtHighlighted == moved, "still there once the panel is built again: \(c.oneAtHighlighted)")
        #expect(c.oneAtRows.indices.contains(c.oneAtHighlighted) && c.oneAtRows[c.oneAtHighlighted].id == row.id)
    }

    @Test func theHighlightStaysWhenTheReadFindsNothingSelected() async throws {
        try await withInterfaceLanguage("en") {
            try check(downs: 1) { $0.answerFieldReads() }
            try check(downs: 2) { $0.answerFieldReads() }
        }
    }

    @Test func theHighlightStaysWhenTheReadGivesUp() async throws {
        try await withInterfaceLanguage("en") {
            try check(downs: 1) { $0.selectionReadsGiveUp() }
            try check(downs: 3) { $0.selectionReadsGiveUp() }
        }
    }

    /// Straight on the composer: `selectionRead(nil)` after ↓.
    @Test func selectionReadNilKeepsTheHighlight() async throws {
        try await withInterfaceLanguage("en") {
            try check(downs: 2) { _ = $0.composer.selectionRead(nil) }
        }
    }
}
