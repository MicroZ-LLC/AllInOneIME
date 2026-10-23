import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Return on coding mode's rows (the packs' keywords and snippets, the field's own words): it picks the highlighted row
/// at once, as an IDE does, in ordinary apps and code editors (the first row there); in chat apps (Return sends) and
/// terminals (Return runs the command) it stays the app's. Plugins' rows keep spec 1.4's rule: Return once ↓ or ↑ moved,
/// in ordinary apps only. The footer says what Return does, and the highlight is drawn chosen only where Return takes
/// it. The rig: Acceptance/SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsReturnTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// A world in coding mode with the shipped Python pack installed.
    static func coding() throws -> SuggestionsWorld {
        let world = SuggestionsWorld()
        world.packs = [try SuggestionsCodingPacksTests.shipped("python")]
        world.codingMode = true
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
            let field = world.field(app: Self.notes)
            field.type("ret")
            #expect(field.settle { field.rows.first?.text == "return" }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.enter), "Return picks the keyword")
            #expect(field.document == "return", "\(field.document.debugDescription)")
            #expect(field.rows.isEmpty, "\(field.rows.map(\.text))")

            let snippet = world.field(app: Self.notes)
            snippet.type("pr")
            #expect(snippet.settle { snippet.rows.first?.text == "print" }, "\(snippet.rows.map(\.text))")
            let before = snippet.host.outputs.count
            #expect(snippet.press(SuggestionKeys.enter), "Return picks the snippet")
            #expect(snippet.document == "print()", "\(snippet.document.debugDescription)")
            #expect(Self.moves(snippet, since: before) == [1], "the caret at its $0: \(Self.moves(snippet, since: before))")

            let words = SuggestionsWorld()
            words.codingMode = true
            let word = words.field(app: Self.notes)
            word.host.document = "compute_total = 1\n"
            word.type("co")
            #expect(word.settle { word.rows.first?.text == "compute_total" }, "\(word.rows.map(\.text))")
            #expect(word.press(SuggestionKeys.enter), "Return picks the field's word")
            #expect(word.document == "compute_total = 1\ncompute_total", "\(word.document.debugDescription)")
        }
    }

    /// VS Code (a code editor): Return puts in the first row, a coding row. A snippet completes as its trigger there: with
    /// the trigger typed in full it has nothing to add, and Return is the editor's.
    @Test func returnPicksTheFirstCodingRowInCodeEditors() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.field(app: SuggestionsApps.vsCode)
            field.type("ret")
            #expect(field.settle { field.rows.first?.text == "return" }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.enter), "Return picks the first row")
            #expect(field.document == "return", "\(field.document.debugDescription)")

            let typed = world.field(app: SuggestionsApps.vsCode)
            typed.type("def")
            #expect(typed.settle { typed.rows.first?.text == "def" }, "\(typed.rows.map(\.text))")
            #expect(!typed.press(SuggestionKeys.enter), "nothing to add: the editor's Return")
            #expect(typed.document == "def", "\(typed.document.debugDescription)")
        }
    }

    /// Chat apps (Return sends) and terminals (Return runs the command): Return stays the app's on coding rows too.
    @Test(arguments: [(SuggestionsApps.slack, false), (SuggestionsApps.chrome, false), ("com.apple.Terminal", true)])
    func returnStaysTheAppsInChatAppsAndTerminals(_ app: String, _ terminal: Bool) async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.field(app: app, terminal: terminal)
            field.type("ret")
            #expect(field.settle { field.rows.first?.text == "return" }, "\(app): \(field.rows.map(\.text))")
            #expect(!field.press(SuggestionKeys.enter), "\(app): Return is the app's")
            #expect(field.document == "ret", "\(app): nothing inserted (\(field.document.debugDescription))")
        }
    }

    /// A plugin's rows in an ordinary app: Return is the app's until ↓ or ↑ moved, as before; coding rows don't change that.
    @Test func aPluginsRowsStillWaitForTheArrows() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.codingMode = true
            world.packs = [try SuggestionsCodingPacksTests.shipped("python")]
            let field = world.field(app: Self.notes)
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(field.issuesShown)")
            #expect(!field.press(SuggestionKeys.enter), "Return is the app's")
            #expect(field.document == "#7", "\(field.document)")
        }
    }

    // MARK: - The footer

    /// The footer says what Return does: it inserts (coding rows, or once ↓ or ↑ moved), only after ↓ or ↑ (a plugin's
    /// rows), or it goes to the app (chat apps, terminals; a code editor's row with nothing to add).
    @Test func theFooterSaysWhatReturnDoes() async throws {
        try await inEnglish {
            let enter = Self.enter
            let world = try Self.coding()
            let coding = world.field(app: Self.notes)
            coding.type("ret")
            #expect(coding.settle { !coding.rows.isEmpty })
            #expect(coding.host.panel?.footer == "Tab or \(enter) inserts · ↑↓ to pick · Esc hides", "\(coding.footer)")

            let plugins = SuggestionsWorld()
            try plugins.github()
            let plugin = plugins.field(app: Self.notes)
            plugin.type("#7")
            #expect(plugin.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(plugin.issuesShown)")
            #expect(plugin.host.panel?.footer == "Tab inserts · ↑↓ then \(enter) to pick · Esc hides", "\(plugin.footer)")
            #expect(plugin.press(SuggestionKeys.down))
            #expect(plugin.host.panel?.footer == "Tab or \(enter) inserts · ↑↓ to pick · Esc hides", "moved: \(plugin.footer)")

            let chat = world.field(app: SuggestionsApps.slack)
            chat.type("ret")
            #expect(chat.settle { !chat.rows.isEmpty })
            #expect(chat.host.panel?.footer == "Tab inserts the first row · \(enter) goes to the app", "\(chat.footer)")

            let editor = world.field(app: SuggestionsApps.vsCode)
            editor.type("ret")
            #expect(editor.settle { !editor.rows.isEmpty })
            #expect(editor.host.panel?.footer == "Tab completes what they share · \(enter) inserts the first row", "\(editor.footer)")
            #expect(editor.host.panel?.highlighted == 0, "the row Return puts in, highlighted")

            let terminal = world.field(app: Self.terminal, terminal: true)
            terminal.type("ret")
            #expect(terminal.settle { !terminal.rows.isEmpty })
            #expect(terminal.host.panel?.footer == "Tab completes what they share · \(enter) goes to the app", "\(terminal.footer)")
            #expect(terminal.host.panel?.highlighted == nil, "no row Return puts in")
        }
    }

    // MARK: - The highlight

    /// Where Return doesn't pick the highlighted row yet, it isn't drawn chosen (`PanelModel.highlightChosen`), only
    /// marked as the row Tab takes: a plugin's rows in an ordinary app until ↓ or ↑ moves it (chosen from then on), any
    /// rows in a chat app. A coding row Return picks is chosen at once, in a code editor too.
    @Test func theHighlightIsChosenOnlyWhereReturnTakesIt() async throws {
        try await inEnglish {
            let all = ["#7001", "#7002", "#7090", "#7100", "#789"]
            let plugins = SuggestionsWorld()
            try plugins.github()
            let plugin = plugins.field(app: Self.notes)
            plugin.type("#7")
            #expect(plugin.waitForIssues(all), "\(plugin.issuesShown)")
            #expect(plugin.host.panel?.highlighted == 0 && plugin.host.panel?.highlightChosen == false,
                    "the first row, nothing chosen yet: \(String(describing: plugin.host.panel?.highlighted))")
            #expect(plugin.press(SuggestionKeys.down))
            #expect(plugin.host.panel?.highlighted == 1 && plugin.host.panel?.highlightChosen == true, "moved: chosen")
            #expect(plugin.press(SuggestionKeys.up))
            #expect(plugin.host.panel?.highlighted == 0 && plugin.host.panel?.highlightChosen == true, "moved back: still chosen")

            let tab = plugins.field(app: Self.notes)
            tab.type("#7")
            #expect(tab.waitForIssues(all), "\(tab.issuesShown)")
            #expect(tab.press(SuggestionKeys.tab), "Tab still takes the first row")
            #expect(tab.document == "#7001", "\(tab.document)")

            let chat = plugins.field(app: SuggestionsApps.slack)
            chat.type("#7")
            #expect(chat.waitForIssues(all), "\(chat.issuesShown)")
            #expect(chat.host.panel?.highlighted == 0 && chat.host.panel?.highlightChosen == false, "a chat app: never chosen")

            let world = try Self.coding()
            for app in [Self.notes, SuggestionsApps.vsCode] {
                let coding = world.field(app: app)
                coding.type("ret")
                #expect(coding.settle { !coding.rows.isEmpty })
                #expect(coding.host.panel?.highlighted == 0 && coding.host.panel?.highlightChosen == true,
                        "\(app): a coding row Return takes, chosen")
            }
            let codingChat = world.field(app: SuggestionsApps.slack)
            codingChat.type("ret")
            #expect(codingChat.settle { !codingChat.rows.isEmpty })
            #expect(codingChat.host.panel?.highlighted == 0 && codingChat.host.panel?.highlightChosen == false,
                    "a chat app's coding row: not chosen")
        }
    }
}
