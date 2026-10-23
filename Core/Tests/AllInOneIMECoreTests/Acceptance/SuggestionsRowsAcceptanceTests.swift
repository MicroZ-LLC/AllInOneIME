import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, spec 1.4: up to 5 rows, in the list's order with the rows picked before first (the one picked last
/// first: spec 6.17); the keys while rows show, per app class (ordinary, chat, terminal and code editor, none: spec 6.11),
/// digits never picking a row (6.1), Esc hiding them for the token (6.12), Tab in terminals and code editors (6.10);
/// which rows are offered (6.13); what goes in: only what wasn't typed, the template of the app's class. The rig:
/// SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsRowsAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static let allRows = ["#7001", "#7002", "#7090", "#7100", "#789"]

    /// A field of `app` in a world with the GitHub plugin, "#7" typed and its rows shown.
    func typedHash7(app: String = SuggestionsApps.editor, terminal: Bool = false,
                    items: [CompletionItem] = SuggestionsItems.issues, manifest: String = SuggestionsPlugins.githubManifest())
        throws -> SuggestionsField {
        let world = SuggestionsWorld()
        try world.github(items: items, manifest: manifest)
        let field = world.field(app: app, terminal: terminal)
        field.type("#7")
        return field
    }

    // MARK: - Rows

    /// Five rows at most, in the list's order (its rank, not sorted).
    @Test func atMostFiveRowsInTheListsOrder() async throws {
        try await inEnglish {
            let items = [7090, 7001, 7080, 7002, 7070, 7060, 7008, 7009].map { SuggestionsItems.issue($0, "Issue \($0)") }
            let field = try typedHash7(items: items)
            field.type("0")
            #expect(field.settle { field.shown(items.map(\.match)) == ["#7090", "#7001", "#7080", "#7002", "#7070"] },
                    "\(field.rows.map(\.text))")
            #expect(field.rows.count == 5)
        }
    }

    /// Rows picked before (by source and match) come first, the one picked last first (spec 6.17); a row picked is kept,
    /// and is the last picked then.
    @Test func rowsPickedBeforeComeFirstTheLastPickedFirst() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.picks = [SuggestionPick(plugin: "github", source: "issues", match: "#7100"),
                           SuggestionPick(plugin: "elsewhere", source: "issues", match: "#7002"),
                           SuggestionPick(plugin: "github", source: "issues", match: "#7090")]
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7090", "#7100", "#7001", "#7002", "#789"]),
                    "#7090 picked last, first; #7002 picked from another source, in its place: \(field.issuesShown)")
            #expect(field.pick(at: 1))
            #expect(field.document == "#7100", "\(field.document)")
            #expect(world.recordedPicks == [SuggestionPick(plugin: "github", source: "issues", match: "#7100")],
                    "\(world.recordedPicks)")
            let next = world.field(app: "com.apple.TextEdit")
            next.type("#7")
            #expect(next.waitForIssues(["#7100", "#7090", "#7001", "#7002", "#789"]), "picked again, first: \(next.issuesShown)")
        }
    }

    // MARK: - Ordinary apps

    /// Tab inserts the highlighted row, the first; with no rows, Tab is the app's.
    @Test func tabInsertsTheFirstRow() async throws {
        try await inEnglish {
            let field = try typedHash7()
            #expect(field.waitForIssues(Self.allRows))
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]))
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#7001", "\(field.document)")
            #expect(field.issuesShown.isEmpty, "the rows go: \(field.issuesShown)")
            #expect(!field.press(SuggestionKeys.tab), "no rows: the app's Tab")
        }
    }

    /// With nothing to show (no source applies, or none of its items), Tab is the app's.
    @Test func tabIsTheAppsWithoutRows() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#")
            field.idle()
            #expect(!field.press(SuggestionKeys.tab))
            field.type(" #7")
            #expect(field.waitForIssues(Self.allRows))
            field.type("009")
            #expect(field.waitForIssues([]))
            #expect(!field.press(SuggestionKeys.tab), "no row matches #7009")
        }
    }

    /// Digits never pick a row (spec 6.1), in English mode or pinyin mode: they go in and extend the token ("#7" and 1 is
    /// "#71", whose row is #7100).
    @Test(arguments: [Language.english, .chinese])
    func digitsExtendTheTokenAndNeverPickARow(_ input: Language) async throws {
        try await inEnglish {
            let world = SuggestionsWorld(input: input)
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows), "\(input): \(field.issuesShown)")
            field.press(SuggestionKeys.digit(1))
            #expect(field.document == "#71", "\(input): typed, not a row (\(field.document))")
            #expect(field.waitForIssues(["#7100"]), "\(input): \(field.issuesShown)")
            for digit in 2...5 {
                let other = world.field(app: "com.apple.TextEdit")
                other.type("#7")
                #expect(other.waitForIssues(Self.allRows))
                other.press(SuggestionKeys.digit(digit))
                #expect(other.document == "#7\(digit)", "\(input): \(digit) typed (\(other.document))")
            }
        }
    }

    /// ↓ and ↑ move the highlight; Return then inserts the highlighted row.
    @Test func arrowsMoveTheHighlightAndReturnInsertsIt() async throws {
        try await inEnglish {
            let field = try typedHash7()
            #expect(field.waitForIssues(Self.allRows))
            #expect(field.press(SuggestionKeys.down))
            #expect(field.press(SuggestionKeys.down))
            #expect(field.press(SuggestionKeys.up))
            #expect(field.host.panel?.highlighted == 1, "the second row: \(String(describing: field.host.panel?.highlighted))")
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "#7002", "\(field.document)")
            #expect(field.issuesShown.isEmpty)
        }
    }

    /// Return before the highlight moved is the app's: nothing is inserted (the token ends there).
    @Test func returnIsTheAppsUntilTheHighlightMoved() async throws {
        try await inEnglish {
            let field = try typedHash7()
            #expect(field.waitForIssues(Self.allRows))
            #expect(!field.press(SuggestionKeys.enter))
            #expect(field.document == "#7", "\(field.document)")
            #expect(field.issuesShown.isEmpty)
        }
    }

    /// Esc hides the rows; nothing is inserted, Tab is the app's then.
    @Test func escHidesTheRows() async throws {
        try await inEnglish {
            let field = try typedHash7()
            #expect(field.waitForIssues(Self.allRows))
            #expect(field.press(SuggestionKeys.escape))
            #expect(field.issuesShown.isEmpty && field.document == "#7", "\(field.issuesShown) \(field.document)")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
            #expect(!field.press(SuggestionKeys.tab), "hidden: the app's Tab")
        }
    }

    /// Esc hides the rows for the token (spec 6.12): a query's answer for it coming later doesn't show them again; they
    /// come back when the token changes.
    @Test func escHidesTheRowsUntilTheTokenChanges() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.runtime.query("70", items: [SuggestionsItems.issue(7066, "Filed a minute ago")])
            world.runtime.holdQueries = true
            let field = world.field()
            field.type("#70")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "\(field.issuesShown)")
            #expect(field.settle { world.runtime.waiting == ["70"] }, "\(world.runtime.waiting)")
            #expect(field.press(SuggestionKeys.escape))
            #expect(field.issuesShown.isEmpty && field.document == "#70", "\(field.issuesShown) \(field.document)")
            world.runtime.holdQueries = false
            world.runtime.release("70")
            field.idle(0.5)
            #expect(field.issuesShown.isEmpty, "the same token: still hidden (\(field.issuesShown))")
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002"]), "another token: back (\(field.issuesShown))")
        }
    }

    /// A click on a row inserts it.
    @Test func aClickOnARowInsertsIt() async throws {
        try await inEnglish {
            let field = try typedHash7()
            #expect(field.waitForIssues(Self.allRows))
            field.host.send(.pick(2))
            #expect(field.document == "#7090", "\(field.document)")
            #expect(field.issuesShown.isEmpty)
        }
    }

    // MARK: - Chat apps

    static let chatApps = [SuggestionsApps.slack, SuggestionsApps.weChat, SuggestionsApps.chrome]

    /// Chat apps (Slack, WeChat, a Chromium app): Tab inserts the first row, with the `chat` template (its address).
    @Test(arguments: chatApps)
    func tabInsertsTheFirstRowWithTheChatTemplateInChatApps(_ app: String) async throws {
        try await inEnglish {
            let field = try typedHash7(app: app)
            #expect(field.waitForIssues(Self.allRows), "\(app)")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#7001 https://github.com/octo-org/octo-repo/issues/7001", "\(app): \(field.document)")
        }
    }

    /// In chat apps the digits, the arrows, Return and Esc stay the app's: Return never sends a row.
    @Test(arguments: chatApps)
    func digitsArrowsReturnAndEscAreTheAppsInChatApps(_ app: String) async throws {
        try await inEnglish {
            let digit = try typedHash7(app: app)
            #expect(digit.waitForIssues(Self.allRows))
            #expect(!digit.press(SuggestionKeys.digit(2)), "\(app): 2")
            #expect(digit.document == "#72", "\(app): typed, not a row (\(digit.document))")

            for key in [SuggestionKeys.down, SuggestionKeys.up, SuggestionKeys.enter, SuggestionKeys.escape] {
                let field = try typedHash7(app: app)
                #expect(field.waitForIssues(Self.allRows))
                #expect(!field.press(key), "\(app): \(key.key) is the app's")
                #expect(field.document == "#7", "\(app): nothing inserted (\(field.document))")
            }
        }
    }

    /// A template list is tried in turn: the first whose variables the item has (an item without `url`: `{arg}`).
    @Test func templatesAreTriedInTurn() async throws {
        try await inEnglish {
            let items = [CompletionItem(match: "#7001", title: "No address")] + SuggestionsItems.issues.dropFirst()
            let field = try typedHash7(app: SuggestionsApps.slack, items: Array(items))
            #expect(field.waitForIssues(Self.allRows))
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#7001", "\(field.document)")
        }
    }

    /// `null` for a class of apps: no rows from the source there, its rows elsewhere.
    @Test func aNullTemplateMeansNoRowsInThatClass() async throws {
        try await inEnglish {
            let manifest = SuggestionsPlugins.githubManifest(insert: #"{ "default": "{arg}", "chat": null }"#)
            let chat = try typedHash7(app: SuggestionsApps.slack, manifest: manifest)
            chat.idle()
            #expect(chat.issuesShown.isEmpty, "\(chat.issuesShown)")
            #expect(!chat.press(SuggestionKeys.tab))
            let editor = try typedHash7(manifest: manifest)
            #expect(editor.waitForIssues(Self.allRows))
        }
    }

    // MARK: - Terminals

    /// Terminals: Tab completes the rows' common prefix only; when that adds nothing to what was typed, Tab is the
    /// terminal's (spec 6.10); a single row's `match` (never a template's text).
    @Test func tabCompletesTheCommonPrefixInTerminals() async throws {
        try await inEnglish {
            let items = [SuggestionsItems.issue(7781, "One"), SuggestionsItems.issue(7782, "Two"), SuggestionsItems.issue(8001, "Other")]
            let field = try typedHash7(app: "com.apple.Terminal", terminal: true, items: items)
            #expect(field.settle { field.shown(items.map(\.match)) == ["#7781", "#7782"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#778", "the common prefix: \(field.document)")
            #expect(field.settle { field.shown(items.map(\.match)) == ["#7781", "#7782"] }, "\(field.rows.map(\.text))")
            #expect(!field.press(SuggestionKeys.tab), "nothing more in common: the terminal's Tab")
            #expect(field.document == "#778", "\(field.document)")

            let single = try typedHash7(app: "com.apple.Terminal", terminal: true,
                                        items: [CompletionItem(match: "#7781", title: "One", arg: "#7781 (one)",
                                                               variables: ["url": "https://github.com/octo-org/octo-repo/issues/7781"])],
                                        manifest: SuggestionsPlugins.githubManifest(insert: #"{ "default": "{arg} {url}" }"#))
            #expect(single.settle { single.shown(["#7781"]) == ["#7781"] }, "\(single.rows.map(\.text))")
            #expect(single.press(SuggestionKeys.tab))
            #expect(single.document == "#7781", "{match} only: \(single.document)")
        }
    }

    /// In terminals the digits, the arrows, Return and Esc stay the app's.
    @Test func digitsArrowsReturnAndEscAreTheAppsInTerminals() async throws {
        try await inEnglish {
            for key in [SuggestionKeys.digit(1), SuggestionKeys.down, SuggestionKeys.up, SuggestionKeys.enter, SuggestionKeys.escape] {
                let field = try typedHash7(app: "com.apple.Terminal", terminal: true)
                #expect(field.waitForIssues(Self.allRows))
                #expect(!field.press(key), "\(key.key) \(key.characters) is the terminal's")
                #expect(field.document.count <= 3, "no row inserted (\(field.document))")
            }
        }
    }

    /// `insert.terminal` null: no rows in terminals and code editors (spec 6.10); elsewhere the source's rows.
    @Test func aNullTerminalTemplateMeansNoRowsInTerminalsAndCodeEditors() async throws {
        try await inEnglish {
            let manifest = SuggestionsPlugins.githubManifest(insert: #"{ "default": "{arg}", "terminal": null }"#)
            for (app, terminal) in [("com.apple.Terminal", true), (SuggestionsApps.vsCode, false)] {
                let field = try typedHash7(app: app, terminal: terminal, manifest: manifest)
                field.idle()
                #expect(field.issuesShown.isEmpty, "\(app): \(field.issuesShown)")
                #expect(!field.press(SuggestionKeys.tab), "\(app): its Tab")
            }
            let editor = try typedHash7(manifest: manifest)
            #expect(editor.waitForIssues(Self.allRows), "\(editor.issuesShown)")
        }
    }

    /// In terminals and code editors whatever `insert.terminal` says (but null), `{match}` goes in (spec 6.10).
    @Test func aTerminalTemplateInsertsTheMatchOnly() async throws {
        try await inEnglish {
            let items = [SuggestionsItems.issue(7781, "One")]
            let manifest = SuggestionsPlugins.githubManifest(insert: #"{ "default": "{arg}", "terminal": "{arg} {url}" }"#)
            for (app, terminal) in [("com.apple.Terminal", true), (SuggestionsApps.vsCode, false)] {
                let field = try typedHash7(app: app, terminal: terminal, items: items, manifest: manifest)
                #expect(field.settle { field.shown(["#7781"]) == ["#7781"] }, "\(app): \(field.rows.map(\.text))")
                #expect(field.press(SuggestionKeys.tab))
                #expect(field.document == "#7781", "\(app): \(field.document)")
            }
        }
    }

    // MARK: - App classes

    enum AppClass: String, Sendable {
        case ordinary, chat, codeEditor, noRows
    }

    struct ClassedApp: Sendable, CustomTestStringConvertible {
        var app: String
        var terminal = false
        var kind: AppClass
        var testDescription: String { "\(app) (\(kind))" }
    }

    static let classedApps: [ClassedApp] =
        SuggestionsApps.ordinary.map { ClassedApp(app: $0, kind: .ordinary) }
        + SuggestionsApps.chat.map { ClassedApp(app: $0, kind: .chat) }
        + SuggestionsApps.codeEditors.map { ClassedApp(app: $0, kind: .codeEditor) }
        + ["com.apple.Terminal", "com.googlecode.iterm2"].map { ClassedApp(app: $0, terminal: true, kind: .codeEditor) }
        + SuggestionsApps.noRows.map { ClassedApp(app: $0, kind: .noRows) }

    /// The app classes of spec 6.11, by what the keys do with "#7"'s rows: ordinary, ↓ moves the highlight; chat, Tab
    /// inserts the first row with the chat template; terminal or code editor, Tab is the app's (the rows' common prefix
    /// adds nothing to "#7"); no rows, none.
    @Test(arguments: classedApps)
    func eachAppHasItsClass(_ classed: ClassedApp) async throws {
        try await inEnglish {
            let field = try typedHash7(app: classed.app, terminal: classed.terminal)
            switch classed.kind {
            case .noRows:
                field.idle()
                #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
                #expect(!field.press(SuggestionKeys.tab) && field.document == "#7", "\(field.document)")
                let ordinary = field.world.field()
                ordinary.type("#7")
                #expect(ordinary.waitForIssues(Self.allRows), "the same source in an ordinary app: \(ordinary.issuesShown)")
            case .ordinary:
                #expect(field.waitForIssues(Self.allRows), "\(field.issuesShown)")
                #expect(field.press(SuggestionKeys.down), "↓ moves the highlight")
                #expect(field.host.panel?.highlighted == 1, "\(String(describing: field.host.panel?.highlighted))")
            case .chat:
                #expect(field.waitForIssues(Self.allRows), "\(field.issuesShown)")
                #expect(field.press(SuggestionKeys.tab))
                #expect(field.document == "#7001 https://github.com/octo-org/octo-repo/issues/7001", "\(field.document)")
            case .codeEditor:
                #expect(field.waitForIssues(Self.allRows), "\(field.issuesShown)")
                #expect(!field.press(SuggestionKeys.tab), "the common prefix adds nothing: its Tab")
                #expect(field.document == "#7", "\(field.document)")
            }
        }
    }

    // MARK: - No rows

    /// Remote desktops, virtual machines and SSH clients: no rows, Tab theirs.
    @Test(arguments: [SuggestionsApps.remoteDesktop, SuggestionsApps.virtualMachine, SuggestionsApps.sshClient])
    func noRowsInRemoteDesktopsVirtualMachinesAndSSHClients(_ app: String) async throws {
        try await inEnglish {
            let field = try typedHash7(app: app)
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(app): \(field.issuesShown)")
            #expect(!field.press(SuggestionKeys.tab))
            #expect(field.document == "#7")
            let ordinary = field.world.field()
            ordinary.type("#7")
            #expect(ordinary.waitForIssues(Self.allRows), "an ordinary app, the same source: \(ordinary.issuesShown)")
        }
    }

    // MARK: - What is offered

    /// A row is offered only when what it inserts starts with what was typed, in any case (spec 6.13): an `arg` that puts
    /// something before the issue's number isn't offered for "#70" (it is in a terminal, where `{match}` goes in).
    @Test func aRowWhoseInsertionDoesntStartWithWhatWasTypedIsntOffered() async throws {
        try await inEnglish {
            let items = [CompletionItem(match: "#7001", title: "Crash", arg: "#7001: Crash at the edge"),
                         CompletionItem(match: "#7002", title: "Settings", arg: "Fixes #7002"),
                         SuggestionsItems.issue(7090, "Docs")]
            let matches = items.map(\.match)
            let field = try typedHash7(items: items)
            field.type("0")
            #expect(field.settle { field.shown(matches) == ["#7001", "#7090"] }, "\(field.rows.map(\.text))")
            field.idle()
            #expect(field.shown(matches) == ["#7001", "#7090"], "\(field.rows.map(\.text))")
            let terminal = try typedHash7(app: "com.apple.Terminal", terminal: true, items: items)
            terminal.type("0")
            #expect(terminal.settle { terminal.shown(matches) == ["#7001", "#7002", "#7090"] }, "\(terminal.rows.map(\.text))")
        }
    }

    // MARK: - What goes in

    /// Only what wasn't typed is added: "#12" and the row "#1234" put in "34".
    @Test func onlyWhatWasntTypedGoesIn() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [SuggestionsItems.issue(1234, "The spec's example")],
                             manifest: SuggestionsPlugins.githubManifest(minChars: 2))
            let field = world.field()
            field.type("#1")
            field.idle()
            #expect(field.rows.isEmpty, "one character: no rows yet")
            field.type("2")
            #expect(field.settle { field.shown(["#1234"]) == ["#1234"] }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#1234", "\(field.document)")
            let inserted = field.host.outputs.dropFirst(before).compactMap { output -> String? in
                switch output {
                case let .commit(text), let .commitAfterKey(text), let .typeOut(text): return text
                case let .replace(text, _): return text
                default: return nil
                }
            }
            #expect(inserted == ["34"], "\(inserted)")
        }
    }

    /// The typed part stays as typed, its case too: "#docs" and the row "#Docs-42" make "#docs-42".
    @Test func theTypedPartKeepsItsCase() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [CompletionItem(match: "#Docs-42", title: "Docs")])
            let field = world.field()
            field.type("#docs")
            #expect(field.settle { field.shown(["#Docs-42"]) == ["#Docs-42"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#docs-42", "\(field.document)")
        }
    }

    /// The prefix typed in another case stays so (spec 6.7): "proj-12" and the row PROJ-1201 make "proj-1201".
    @Test func thePrefixTypedInAnotherCaseStaysSo() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            let plugin = try #require(try SuggestionsPlugins.install(SuggestionsPlugins.trackerManifest, in: world.folder))
            world.plugins = [plugin]
            world.runtime.list("tickets", items: [CompletionItem(match: "PROJ-1201", title: "Login page")])
            world.enable(plugin, "tickets")
            let field = world.field()
            field.type("proj-12")
            #expect(field.settle { field.shown(["PROJ-1201"]) == ["PROJ-1201"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "proj-1201", "\(field.document)")
        }
    }

    /// `arg` (when the item has one) is what `{arg}` inserts.
    @Test func argIsWhatTheDefaultTemplateInserts() async throws {
        try await inEnglish {
            let items = [CompletionItem(match: "#7001", title: "Crash", arg: "#7001: Crash at the edge")]
            let field = try typedHash7(items: items)
            #expect(field.settle { field.shown(["#7001"]) == ["#7001"] })
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#7001: Crash at the edge", "\(field.document)")
        }
    }

    /// A row's own variables fill the template: an AWS account typed in full gets its name after it.
    @Test func variablesFillTheTemplate() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.aws()
            let field = world.field()
            field.type("123456789012")
            #expect(field.settle { field.shown(["123456789012"]) == ["123456789012"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "123456789012 (prod)", "\(field.document)")
        }
    }
}
