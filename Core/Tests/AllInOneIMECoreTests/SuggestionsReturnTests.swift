import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Return on the rows, Code's (its pack's keywords and snippets, the field's own words) and plugins' alike: it picks the
/// chosen row at once, as an IDE does, in every app (decision 31): ordinary apps, code editors, chat apps, browsers and
/// terminals. The first row that puts something in is chosen and drawn selected from the start; where none does, Return
/// is the app's. The footer is the same everywhere. The rig: Acceptance/SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsReturnTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// A world with the Code input in Python, the shipped pack installed.
    static func coding() throws -> SuggestionsWorld {
        let world = SuggestionsWorld()
        world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
        return world
    }

    static let enter = Platform.current.terms.enter
    static let notes = "com.apple.Notes"
    static let terminal = "com.apple.Terminal"

    /// The caret moves back the session asked for since output `start`.
    static func moves(_ field: SuggestionsField, since start: Int) -> [Int] {
        field.host.outputs.dropFirst(start).compactMap { output -> Int? in
            if case let .moveCaret(back, _) = output { return back } else { return nil }
        }
    }

    // MARK: - Return

    /// Notes (an ordinary app): "ret" and Return put in "return", no ↓ first; a snippet goes in with its caret, and a word
    /// of the field the same way.
    @Test func returnPicksACodingRowAtOnceInOrdinaryApps() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField(app: Self.notes)
            field.type("ret")
            #expect(field.settle { field.rows.first?.text == "return" }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.enter), "Return picks the keyword")
            #expect(field.document == "return", "\(field.document.debugDescription)")
            #expect(field.rows.isEmpty, "\(field.rows.map(\.text))")

            let snippet = world.codeField(app: Self.notes)
            snippet.type("pr")
            #expect(snippet.settle { snippet.rows.first?.text == "print" }, "\(snippet.rows.map(\.text))")
            let before = snippet.host.outputs.count
            #expect(snippet.press(SuggestionKeys.enter), "Return picks the snippet")
            #expect(snippet.document == "print()", "\(snippet.document.debugDescription)")
            #expect(Self.moves(snippet, since: before) == [1], "the caret at its $0: \(Self.moves(snippet, since: before))")

            // A pack with nothing of its own: the field's words alone.
            let words = SuggestionsWorld()
            words.addCode("example", packs: [CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [],
                                                                snippets: [])])
            let word = words.codeField(app: Self.notes)
            word.host.document = "compute_total = 1\n"
            word.type("co")
            #expect(word.settle { word.rows.first?.text == "compute_total" }, "\(word.rows.map(\.text))")
            #expect(word.press(SuggestionKeys.enter), "Return picks the field's word")
            #expect(word.document == "compute_total = 1\ncompute_total", "\(word.document.debugDescription)")
        }
    }

    /// VS Code (a code editor): Return puts in the first row, a coding row. A snippet goes in as its trigger there: with
    /// the trigger typed in full it has nothing to add, no row is chosen, and Return is the editor's.
    @Test func returnPicksTheFirstCodingRowInCodeEditors() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField(app: SuggestionsApps.vsCode)
            field.type("ret")
            #expect(field.settle { field.rows.first?.text == "return" }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.enter), "Return picks the first row")
            #expect(field.document == "return", "\(field.document.debugDescription)")

            let typed = world.codeField(app: SuggestionsApps.vsCode)
            typed.type("def")
            #expect(typed.settle { typed.rows.first?.text == "def" }, "\(typed.rows.map(\.text))")
            #expect(!typed.press(SuggestionKeys.enter), "nothing to add: the editor's Return")
            #expect(typed.document == "def", "\(typed.document.debugDescription)")
        }
    }

    /// Chat apps, browsers and terminals: Return picks coding rows there too while they show (decision 31), as the class
    /// puts them in (a terminal: the keyword).
    @Test(arguments: [(SuggestionsApps.slack, false), (SuggestionsApps.chrome, false), ("com.apple.Terminal", true)])
    func returnPicksCodingRowsInChatAppsAndTerminalsToo(_ app: String, _ terminal: Bool) async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField(app: app, terminal: terminal)
            field.type("ret")
            #expect(field.settle { field.rows.first?.text == "return" }, "\(app): \(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.enter), "\(app): Return picks the first row")
            #expect(field.document == "return", "\(app): \(field.document.debugDescription)")
        }
    }

    /// A plugin's rows: Return takes the chosen row at once too, the first, no ↓ first (decision 31), with Code's rows
    /// about or not.
    @Test func aPluginsRowsAreTakenByReturnAtOnce() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
            for field in [world.codeField(app: Self.notes), world.field(app: SuggestionsApps.slack)] {
                field.type("#7")
                #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(field.issuesShown)")
                #expect(field.press(SuggestionKeys.enter), "Return takes the first row")
                #expect(field.document.hasPrefix("#7001"), "\(field.document)")
            }
        }
    }

    // MARK: - The footer

    /// The footer says the keys, the same in every app and for every kind of row (decision 31).
    @Test func theFooterIsTheSameEverywhere() async throws {
        try await inEnglish {
            let footer = "Tab or \(Self.enter) inserts · ↑↓ to pick · → or Esc hides"
            let world = try Self.coding()
            for (app, terminal) in [(Self.notes, false), (SuggestionsApps.slack, false), (SuggestionsApps.vsCode, false), (Self.terminal, true)] {
                let coding = world.codeField(app: app, terminal: terminal)
                coding.type("ret")
                #expect(coding.settle { !coding.rows.isEmpty })
                #expect(coding.host.panel?.footer == footer, "\(app): \(coding.footer)")
            }

            let plugins = SuggestionsWorld()
            try plugins.github()
            for (app, terminal) in [(Self.notes, false), (SuggestionsApps.chrome, false), (Self.terminal, true)] {
                let plugin = plugins.field(app: app, terminal: terminal)
                plugin.type("#7")
                #expect(plugin.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(app): \(plugin.issuesShown)")
                #expect(plugin.host.panel?.footer == footer, "\(app): \(plugin.footer)")
                #expect(plugin.press(SuggestionKeys.down))
                #expect(plugin.host.panel?.footer == footer, "\(app), moved: \(plugin.footer)")
            }
        }
    }

    // MARK: - The highlight

    /// The first row is chosen and drawn selected from the start (`PanelModel.highlighted`), plugins' rows and Code's, in
    /// every class of app (decision 31); ↓ and ↑ move it at once.
    @Test func theFirstRowIsChosenFromTheStartEverywhere() async throws {
        try await inEnglish {
            let all = ["#7001", "#7002", "#7090", "#7100", "#789"]
            let plugins = SuggestionsWorld()
            try plugins.github()
            for (app, terminal) in [(Self.notes, false), (SuggestionsApps.slack, false), (SuggestionsApps.vsCode, false), (Self.terminal, true)] {
                let plugin = plugins.field(app: app, terminal: terminal)
                plugin.type("#7")
                #expect(plugin.waitForIssues(all), "\(app): \(plugin.issuesShown)")
                #expect(plugin.host.panel?.highlighted == 0, "\(app): the first row chosen")
                #expect(plugin.press(SuggestionKeys.down))
                #expect(plugin.host.panel?.highlighted == 1, "\(app): ↓ moves at once")
                #expect(plugin.press(SuggestionKeys.up) && plugin.press(SuggestionKeys.up))
                #expect(plugin.host.panel?.highlighted == all.count - 1, "\(app): ↑ from the first goes round to the last")
            }

            let world = try Self.coding()
            for (app, terminal) in [(Self.notes, false), (SuggestionsApps.vsCode, false), (SuggestionsApps.slack, false), (Self.terminal, true)] {
                let coding = world.codeField(app: app, terminal: terminal)
                coding.type("ret")
                #expect(coding.settle { !coding.rows.isEmpty })
                #expect(coding.host.panel?.highlighted == 0, "\(app): a coding row, chosen")
            }
        }
    }
}
