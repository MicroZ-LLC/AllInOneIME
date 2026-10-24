import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The row ↓ or ↑ moved to while the rows are made again for the same token: Code's field words read once typing pauses
/// (on the Mac only then: a key doesn't read the field's text), a list or a query coming back. It stays chosen, by what
/// it is (the same item, keyword, snippet or word) wherever it is now; only a new token starts again from the first row
/// that puts something in (decision 31). The rig: Acceptance/SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsHighlightTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// The row highlighted now, as its text and comment.
    static func highlighted(_ field: SuggestionsField) -> String? {
        guard let panel = field.host.panel, let index = panel.highlighted, panel.rows.indices.contains(index) else { return nil }
        return panel.rows[index].text + " · " + panel.rows[index].comment
    }

    /// Notes, as the Mac reads it: "for" typed, then ↓ twice before the pause's read of the field's words has come back.
    /// The read brings a word of the field; the row the arrows moved to stays highlighted (and chosen), and the next ↓
    /// goes on from it.
    @Test func theArrowsMovesStayWhenThePausesReadComesBack() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
            let field = world.codeField(app: "com.apple.Notes")
            field.host.readsWhatIsWanted = true
            field.host.fieldReadsWait = true
            field.host.document = "for_each = 1\n"
            field.type("for")
            #expect(field.rows.map(\.comment) == ["for … in", "for … in range", "for … in enumerate", "built-in"], "\(field)")
            // The pause: its read asked for, not back yet.
            field.pause(InputSession.wordsPause + 0.05)
            #expect(field.host.fieldReads == 1, "\(field.host.fieldReads)")
            #expect(field.press(SuggestionKeys.down) && field.press(SuggestionKeys.down))
            #expect(Self.highlighted(field) == "for · for … in enumerate", "\(field)")
            field.host.answerFieldReads()
            #expect(field.rows.contains { $0.text == "for_each" }, "the field's word came: \(field)")
            #expect(Self.highlighted(field) == "for · for … in enumerate", "\(field)")
            #expect(field.press(SuggestionKeys.down))
            #expect(Self.highlighted(field) == "format · built-in", "\(field)")
        }
    }

    /// "#70" with the list still loading: the query's answer are the rows, the first chosen (decision 31); ↓ to the
    /// second. The list comes back, its rows go first: the issue the arrow moved to stays chosen where it is now, and
    /// Return puts it in.
    @Test func aListComingBackKeepsTheRowTheArrowsMovedTo() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.runtime.holdLoads = true
            defer { world.runtime.releaseAll() }
            world.runtime.query("70", items: [SuggestionsItems.issue(7050, "Found by the query"), SuggestionsItems.issue(7000, "Zero")])
            let field = world.field(app: "com.apple.Notes")
            field.type("#70")
            #expect(field.settle { field.issuesShown == ["#7050", "#7000"] }, "\(field)")
            #expect(field.host.panel?.highlighted == 0, "the first chosen: \(field)")
            #expect(field.press(SuggestionKeys.down))
            #expect(field.issuesShown[field.host.panel?.highlighted ?? 0] == "#7000", "\(field)")
            world.runtime.release("load:issues")
            #expect(field.settle { field.issuesShown.count > 2 }, "\(field)")
            #expect(field.issuesShown.first == "#7001", "the list's rows first: \(field.issuesShown)")
            #expect(field.issuesShown[field.host.panel?.highlighted ?? 0] == "#7000",
                    "\(field.issuesShown), highlighted \(String(describing: field.host.panel?.highlighted))")
            #expect(field.press(SuggestionKeys.enter), "Return puts in the row the arrow moved to")
            #expect(field.document.hasSuffix("#7000"), "\(field.document.debugDescription)")
        }
    }

    /// A first row that puts nothing in (what was typed is all of it: "#70" typed, issue #70) isn't the one chosen from
    /// the start: the next that puts something in is (decision 31). The arrows move from it, and ↑ reaches the first row:
    /// chosen, Return takes it (nothing more goes in, the rows go).
    @Test func aFirstRowThatPutsNothingInIsntChosenFromTheStart() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [SuggestionsItems.issue(70, "Seventy"), SuggestionsItems.issue(7050, "Fifty"),
                                     SuggestionsItems.issue(7000, "Zero")])
            let field = world.field(app: "com.apple.Notes")
            field.type("#70")
            #expect(field.settle { field.issuesShown == ["#70", "#7050", "#7000"] }, "\(field)")
            #expect(field.host.panel?.highlighted == 1, "\(String(describing: field.host.panel?.highlighted))")
            #expect(field.press(SuggestionKeys.down))
            #expect(field.host.panel?.highlighted == 2, "\(String(describing: field.host.panel?.highlighted))")
            #expect(field.press(SuggestionKeys.up) && field.press(SuggestionKeys.up))
            #expect(field.host.panel?.highlighted == 0, "\(String(describing: field.host.panel?.highlighted))")
            #expect(field.press(SuggestionKeys.enter), "the row chosen: Return takes it")
            #expect(field.document == "#70" && field.rows.isEmpty, "\(field.document.debugDescription)")
        }
    }

    /// Where no row puts anything in ("#7050" typed, its one row), none is chosen: Return and Tab are the app's.
    @Test func whereNoRowPutsAnythingInReturnAndTabAreTheApps() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [SuggestionsItems.issue(7050, "Fifty")])
            let field = world.field(app: "com.apple.Notes")
            field.type("#7050")
            #expect(field.settle { field.issuesShown == ["#7050"] }, "\(field)")
            #expect(field.host.panel?.highlighted == nil, "\(String(describing: field.host.panel?.highlighted))")
            #expect(!field.press(SuggestionKeys.tab), "the app's Tab")
            let enter = world.field(app: "com.apple.Notes")
            enter.type("#7050")
            #expect(enter.settle { enter.issuesShown == ["#7050"] }, "\(enter)")
            #expect(!enter.press(SuggestionKeys.enter), "the app's Return")
            #expect(enter.document == "#7050", "\(enter.document.debugDescription)")
        }
    }

    /// A new token starts again from the first row.
    @Test func aNewTokenStartsFromTheFirstRow() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field(app: "com.apple.Notes")
            field.type("#7")
            #expect(field.settle { field.issuesShown.count > 2 }, "\(field)")
            #expect(field.press(SuggestionKeys.down) && field.host.panel?.highlighted == 1, "\(field)")
            field.type(" #7")
            #expect(field.settle { field.issuesShown.count > 2 }, "\(field)")
            #expect(field.host.panel?.highlighted == 0, "\(field)")
        }
    }
}
