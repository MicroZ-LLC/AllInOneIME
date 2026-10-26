import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestion rows scroll (0.6.7.3): the rows are every item that matches (picked first, then the source's order), up to
/// 100; the panel shows 5 at a time (a key makes those and counts the rest; going past them makes them all). ↓ on the
/// last row shown moves the choice to the next and the rows shown by one, ↑ on the first the same way back, around the
/// ends too (to the last rows, or the first); the scroll wheel moves the rows shown without choosing, until a row is
/// clicked (what a click puts in is the row clicked) or a key moves the choice; the footer's right says which rows are
/// shown ("6–10 / 23", as the command list says it). The same for every source: a
/// plugin's, a custom command's, Code's. A key the rows take that puts nothing in (↓ ↑ → Esc) says so
/// (`SessionOutput.rowsTookKey`), for a shell whose app would act on it as well. The rig is the acceptance tests'
/// (Acceptance/SuggestionsAcceptanceTests.swift).
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsScrollTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// Issues #7001 … #(7000 + `count`), in that order.
    static func issues(_ count: Int) -> [CompletionItem] {
        (1...count).map { SuggestionsItems.issue(7000 + $0, "Issue \(7000 + $0)") }
    }

    /// "#7001" … for `numbers` (7001 is 1).
    static func shown(_ numbers: ClosedRange<Int>) -> [String] { numbers.map { "#\(7000 + $0)" } }

    /// A field with the GitHub plugin's `count` issues (no query), "#7" typed and its rows shown.
    static func typedHash7(_ count: Int, world: SuggestionsWorld = SuggestionsWorld()) throws -> SuggestionsField {
        try world.github(items: issues(count), manifest: SuggestionsPlugins.githubManifest(query: false))
        let field = world.field()
        field.type("#7")
        return field
    }

    /// The panel's highlighted row (among those shown) and what its footer's right says of the rows shown.
    static func state(_ field: SuggestionsField) -> (highlighted: Int?, position: String?) {
        let detail = field.host.panel?.detail ?? ""
        return (field.host.panel?.highlighted, detail.components(separatedBy: " · ").last { $0.contains("/") })
    }

    // MARK: - The keys

    /// 5 rows shown of 23, the first chosen; ↓ moves the choice down the 5, then past the last one shown the rows move by
    /// one; to the last row, then around to the first (the rows shown back at the start); ↑ from there around to the last
    /// (the last 5 shown), ↑ down to the first shown, then past it the rows move back by one; Return puts in the row
    /// chosen.
    @Test func downPastTheLastRowShownScrollsByOne() async throws {
        try await inEnglish {
            let field = try Self.typedHash7(23)
            #expect(field.settle { field.issuesShown == Self.shown(1...5) }, "\(field.issuesShown)")
            #expect(Self.state(field) == (0, "1–5 / 23"), "\(Self.state(field))")
            for _ in 1...4 { #expect(field.press(SuggestionKeys.down)) }
            #expect(field.issuesShown == Self.shown(1...5) && Self.state(field) == (4, "1–5 / 23"), "\(field.issuesShown) \(Self.state(field))")
            #expect(field.press(SuggestionKeys.down))
            #expect(field.issuesShown == Self.shown(2...6) && Self.state(field) == (4, "2–6 / 23"),
                    "↓ past the last row shown: the next chosen, the rows moved by one (\(field.issuesShown), \(Self.state(field)))")
            for _ in 6..<23 { field.press(SuggestionKeys.down) }
            #expect(field.issuesShown == Self.shown(19...23) && Self.state(field) == (4, "19–23 / 23"), "\(field.issuesShown) \(Self.state(field))")
            #expect(field.press(SuggestionKeys.down))
            #expect(field.issuesShown == Self.shown(1...5) && Self.state(field) == (0, "1–5 / 23"),
                    "↓ on the last row: around to the first (\(field.issuesShown), \(Self.state(field)))")
            #expect(field.press(SuggestionKeys.up))
            #expect(field.issuesShown == Self.shown(19...23) && Self.state(field) == (4, "19–23 / 23"),
                    "↑ on the first row: around to the last (\(field.issuesShown), \(Self.state(field)))")
            for _ in 1...4 { field.press(SuggestionKeys.up) }
            #expect(field.issuesShown == Self.shown(19...23) && Self.state(field) == (0, "19–23 / 23"), "\(Self.state(field))")
            #expect(field.press(SuggestionKeys.up))
            #expect(field.issuesShown == Self.shown(18...22) && Self.state(field) == (0, "18–22 / 23"),
                    "↑ past the first row shown: the rows moved back by one (\(field.issuesShown), \(Self.state(field)))")
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "#7018", "\(field.document)")
        }
    }

    /// 5 rows or fewer: nothing scrolls, and nothing says which are shown.
    @Test func fiveRowsOrFewerShowNoPosition() async throws {
        try await inEnglish {
            let field = try Self.typedHash7(5)
            #expect(field.settle { field.issuesShown == Self.shown(1...5) }, "\(field.issuesShown)")
            #expect(Self.state(field) == (0, nil), "\(Self.state(field)), \(field.footer)")
            for _ in 1...5 { field.press(SuggestionKeys.down) }
            #expect(field.issuesShown == Self.shown(1...5) && Self.state(field) == (0, nil), "around: \(Self.state(field))")
        }
    }

    /// Every item that matches is a row, up to 100 (a list of 150 matching); ↑ from the first goes to the 100th.
    @Test func atMostAHundredRows() async throws {
        try await inEnglish {
            let field = try Self.typedHash7(150)
            #expect(field.settle { Self.state(field).position == "1–5 / 100" }, "\(field.footer)")
            #expect(field.press(SuggestionKeys.up))
            #expect(field.issuesShown == Self.shown(96...100) && Self.state(field) == (4, "96–100 / 100"),
                    "\(field.issuesShown) \(Self.state(field))")
        }
    }

    /// Rows picked before come first (the last picked first), wherever their items are, past the 100th too; the others in
    /// the list's order after them, 100 rows in all.
    @Test func rowsPickedBeforeComeFirst() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.picks = [SuggestionPick(plugin: "github", source: "issues", match: "#7140"),
                           SuggestionPick(plugin: "github", source: "issues", match: "#7003")]
            let field = try Self.typedHash7(150, world: world)
            #expect(field.settle { field.issuesShown == ["#7003", "#7140", "#7001", "#7002", "#7004"] }, "\(field.issuesShown)")
            #expect(Self.state(field).position == "1–5 / 100", "\(field.footer)")
            #expect(field.press(SuggestionKeys.up))
            #expect(field.issuesShown == ["#7095", "#7096", "#7097", "#7098", "#7099"], "the 98 others after them: \(field.issuesShown)")
        }
    }

    /// A key makes the rows shown and counts the rest by their items: one whose templates can't go in here is counted
    /// until ↓ goes past the rows made, which makes them all and counts them (a `{url}` template, 4 of 12 issues without
    /// one).
    @Test func theRestAreCountedByTheirItemsUntilMade() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            let items = Self.issues(12).enumerated().map { index, item in
                index % 3 == 2 ? CompletionItem(match: item.match, title: item.title, arg: item.arg) : item
            }
            try world.github(items: items, manifest: SuggestionsPlugins.githubManifest(
                query: false, insert: #"{ "default": "{url}", "chat": "{url}", "terminal": "{match}" }"#))
            let field = world.field()
            field.type("#7")
            #expect(field.settle { field.issuesShown == ["#7001", "#7002", "#7004", "#7005", "#7007"] }, "\(field.issuesShown)")
            #expect(Self.state(field) == (0, "1–5 / 12"), "counted by the items: \(Self.state(field))")
            for _ in 1...5 { field.press(SuggestionKeys.down) }
            #expect(field.issuesShown == ["#7002", "#7004", "#7005", "#7007", "#7008"] && Self.state(field) == (4, "2–6 / 8"),
                    "made, counted: \(field.issuesShown) \(Self.state(field))")
            for _ in 1...2 { field.press(SuggestionKeys.down) }
            #expect(Self.state(field) == (4, "4–8 / 8"), "the eighth: \(Self.state(field))")
            field.press(SuggestionKeys.down)
            #expect(Self.state(field) == (0, "1–5 / 8"), "around from the eighth: \(Self.state(field))")
        }
    }

    // MARK: - The wheel

    /// The wheel over the panel moves the rows shown, as far as the ends, the choice staying (not shown: nothing drawn
    /// selected); Return puts in the row chosen. A key then moves the choice and brings it into view.
    @Test func theWheelScrollsWithoutChoosing() async throws {
        try await inEnglish {
            let field = try Self.typedHash7(23)
            #expect(field.settle { field.issuesShown == Self.shown(1...5) }, "\(field.issuesShown)")
            field.host.send(.scroll(3))
            #expect(field.issuesShown == Self.shown(4...8) && Self.state(field) == (nil, "4–8 / 23"), "\(field.issuesShown) \(Self.state(field))")
            field.host.send(.scroll(100))
            #expect(field.issuesShown == Self.shown(19...23) && Self.state(field) == (nil, "19–23 / 23"), "\(Self.state(field))")
            field.host.send(.scroll(-100))
            #expect(field.issuesShown == Self.shown(1...5) && Self.state(field) == (0, "1–5 / 23"), "\(Self.state(field))")
            field.host.send(.scroll(2))
            #expect(field.press(SuggestionKeys.down))
            #expect(field.issuesShown == Self.shown(2...6) && Self.state(field) == (0, "2–6 / 23"),
                    "↓ after the wheel: #7002 chosen, brought into view (\(field.issuesShown), \(Self.state(field)))")
            field.host.send(.scroll(10))
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "#7002", "the row chosen, not one shown: \(field.document)")
        }
    }

    /// A row clicked once the wheel moved the rows is the one clicked.
    @Test func aClickAfterTheWheelPutsInTheRowClicked() async throws {
        try await inEnglish {
            let field = try Self.typedHash7(23)
            #expect(field.settle { field.issuesShown == Self.shown(1...5) }, "\(field.issuesShown)")
            field.host.send(.scroll(7))
            #expect(field.issuesShown == Self.shown(8...12))
            field.host.send(.pick(1))
            #expect(field.document == "#7009", "\(field.document)")
        }
    }

    /// The rows made again for the same token (a query's answer, the list come back) stay where the wheel put them; a new
    /// token starts at the first.
    @Test func aNewTokenStartsAtTheFirstRow() async throws {
        try await inEnglish {
            let field = try Self.typedHash7(23)
            #expect(field.settle { field.issuesShown == Self.shown(1...5) }, "\(field.issuesShown)")
            for _ in 1...7 { field.press(SuggestionKeys.down) }
            #expect(Self.state(field) == (4, "4–8 / 23"), "\(Self.state(field))")
            field.type("01")
            #expect(field.settle { field.issuesShown == Self.shown(10...14) } && Self.state(field) == (0, "1–5 / 10"),
                    "\"#701\": \(field.issuesShown) \(Self.state(field))")
        }
    }

    // MARK: - Every source

    /// A custom command's rows scroll the same way.
    @Test func aCustomCommandsRowsScroll() async throws {
        try await inEnglish {
            final class Tickets: CommandCompletionRuntime, @unchecked Sendable {
                func list(_ command: CustomCommand) async throws -> Data {
                    Data((100...111).map { "JIRA-\($0)\tTicket \($0)" }.joined(separator: "\n").utf8)
                }
                func query(_ text: String, _ command: CustomCommand) async throws -> Data { Data() }
            }
            let world = SuggestionsWorld()
            world.switches.commands = [CustomCommand(name: "jira", type: .suggestions, argv: ["/Users/me/bin/jira-list"], prefix: "JIRA-")]
            let field = world.field { $0.suggestions.commandRuntime = Tickets() }
            field.type("JIRA-1")
            #expect(field.settle { field.rows.map(\.text) == (100...104).map { "JIRA-\($0)" } }, "\(field.rows.map(\.text))")
            #expect(Self.state(field) == (0, "1–5 / 12"), "\(Self.state(field))")
            for _ in 1...5 { field.press(SuggestionKeys.down) }
            #expect(field.rows.map(\.text) == (101...105).map { "JIRA-\($0)" } && Self.state(field) == (4, "2–6 / 12"),
                    "\(field.rows.map(\.text)) \(Self.state(field))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "JIRA-105", "\(field.document)")
        }
    }

    /// Code's rows (its pack's keywords) scroll the same way.
    @Test func codesRowsScroll() async throws {
        try await inEnglish {
            let keywords = (1...12).map { String(format: "pa%02d", $0) }
            let world = SuggestionsWorld()
            world.addCode("example", packs: [CodingLanguagePack(language: "example", title: "Example", version: "1.0.0",
                                                                keywords: keywords, snippets: [])])
            let field = world.codeField()
            field.type("pa")
            #expect(field.settle { field.rows.map(\.text) == Array(keywords.prefix(5)) }, "\(field.rows.map(\.text))")
            #expect(Self.state(field) == (0, "1–5 / 12"), "\(Self.state(field))")
            for _ in 1...5 { field.press(SuggestionKeys.down) }
            #expect(field.rows.map(\.text) == Array(keywords[1...5]) && Self.state(field) == (4, "2–6 / 12"),
                    "\(field.rows.map(\.text)) \(Self.state(field))")
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "pa06", "\(field.document)")
        }
    }

    // MARK: - What the shell is told

    /// ↓ ↑ → and Esc on the rows say that the rows took the key and put nothing in (`rowsTookKey`), first; Tab and Return
    /// say a row goes in (`rowByKey`) instead; a key the rows don't take says nothing.
    @Test func theKeysTheRowsTakeSaySo() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: Self.issues(8), manifest: SuggestionsPlugins.githubManifest(query: false))
            for key in [SuggestionKeys.down, SuggestionKeys.up, SuggestionKeys.right, SuggestionKeys.escape, SuggestionKeys.tab, SuggestionKeys.enter] {
                let field = world.field()
                field.type("#7")
                #expect(field.settle { !field.rows.isEmpty })
                let before = field.host.outputs.count
                #expect(field.press(key))
                let after = Array(field.host.outputs.dropFirst(before))
                let took = after.filter { $0 == .rowsTookKey }.count, rowByKey = after.filter { $0 == .rowByKey }.count
                if key == SuggestionKeys.tab || key == SuggestionKeys.enter {
                    #expect(took == 0 && rowByKey == 1, "\(key.key): \(after)")
                } else {
                    #expect(took == 1 && after.first == .rowsTookKey && rowByKey == 0, "\(key.key): \(after)")
                }
            }
            let field = world.field()
            field.type("#7")
            #expect(field.settle { !field.rows.isEmpty })
            let before = field.host.outputs.count
            field.type("0")
            #expect(!field.host.outputs.dropFirst(before).contains(.rowsTookKey))
        }
    }
}
