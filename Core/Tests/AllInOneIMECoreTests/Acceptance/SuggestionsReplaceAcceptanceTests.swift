import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/*
 The API these tests need that 0.6.7 doesn't have (ExtensionCompletions-API.md has all of it):

     public enum SuggestionsInsert {
         /// "Markdown link": `[{title}]({url})`, else `{arg}`. Written as "markdownLink"; Settings names it "Markdown link"
         /// and offers it after With title and link (`offered`, and so `AppInsertChoice.offered`).
         case markdownLink
     }

 A replacement itself needs none: the session puts it in as `SessionOutput.replace(text, range:)`, the token's range.
 */

/// Script extensions as completion sources; replacing inserts (0.6.7.1, owner, 2026-10-24), section 1: a row may replace
/// the token (plugins too). Written from the spec by the tests' author, not from the implementation (whose changes don't
/// edit them). A row shows by its `match`; it puts in the first of its templates whose variables the item all has and that
/// can go in here: one that starts with the token as today (the rest after it), one that doesn't in place of the token,
/// only where the field tells where its text is (`suggesting.ranges`: it reports the selected range), else skipped for
/// the next. And the Insert choice "Markdown link", everywhere and per app. Everything goes through a text field's
/// `InputSession` as a shell drives it (the rig: SuggestionsAcceptanceTests.swift); a field that reports no ranges is one
/// whose keys come without a selected range, as a terminal's.
///
/// Section 4's bullets: shows by match (`aRowShowsByItsMatchWhateverItsTemplateFills`); replaces with ranges
/// (`aReplacementTakesOutTheTokenAndPutsInTheWholeTextAsOneChange`); skipped without
/// (`withoutRangesAReplacementIsSkippedForTheNextTemplate`); the list falls through
/// (`theFirstTemplateThatCanGoInHereIsUsed`, `aTemplateThatStartsWithTheTokenGoesInAsToday`); prefix included in what's
/// taken out (`thePrefixIsTakenOutWithTheToken`); no snippet rules (`aReplacementHasNoCaretStops`); Markdown link global and
/// per app (`markdownLinkIsAChoiceAfterWithTitleAndLink`, `markdownLinkChosenEverywhere`, `markdownLinkChosenForOneApp`);
/// plugins too, and custom commands (`aCustomCommandsRowsReplaceToo`).
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsReplaceAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: - Items and sources

    static func url(_ number: Int) -> String { "https://github.com/octo-org/octo-repo/issues/\(number)" }

    /// An issue with its title and address as variables (`{title}`, `{url}`).
    static func issue(_ number: Int, _ title: String) -> CompletionItem {
        CompletionItem(match: "#\(number)", title: title, arg: "#\(number)", variables: ["title": title, "url": url(number)])
    }

    static let crash = issue(7001, "Crash at the screen's edge")
    static let settings = issue(7002, "Settings: a switch per app")
    static let docs = issue(7090, "Docs: how to write a plugin")
    /// One with a title and no address, one with neither.
    static let noLink = CompletionItem(match: "#7055", title: "No link yet", arg: "#7055", variables: ["title": "No link yet"])
    static let bare = CompletionItem(match: "#7066", arg: "#7066")

    /// The Markdown link of an issue.
    static func link(_ item: CompletionItem) -> String {
        "[\(item.variables?["title"] ?? "")](\(item.variables?["url"] ?? ""))"
    }

    /// A world with the GitHub plugin's issues `items` (its list, no query) and its `insert`.
    static func world(insert: String, items: [CompletionItem] = [crash, settings, docs]) throws -> SuggestionsWorld {
        let world = SuggestionsWorld()
        try world.github(items: items, manifest: SuggestionsPlugins.githubManifest(query: false, insert: insert))
        return world
    }

    // MARK: - What the field saw

    /// A change to the field's text as the session made it: text put in at the caret, or in place of a range (UTF-16).
    enum Change: Equatable {
        case inserted(String)
        case replaced(String, Range<Int>?)
    }

    /// The changes the session made to the field's text since output `start`.
    static func changes(_ field: SuggestionsField, since start: Int) -> [Change] {
        field.host.outputs.dropFirst(start).compactMap { output -> Change? in
            switch output {
            case let .commit(text), let .commitAfterKey(text), let .typeOut(text): return .inserted(text)
            case let .replace(text, range): return .replaced(text, range)
            default: return nil
            }
        }
    }

    /// Whether the session moved the caret since output `start` (a snippet's tab stop).
    static func movedTheCaret(_ field: SuggestionsField, since start: Int) -> Bool {
        field.host.outputs.dropFirst(start).contains { output in
            if case .moveCaret = output { return true } else { return false }
        }
    }

    // MARK: - A field that reports no ranges

    /// What the field says with a key where it tells nothing of where its text is: no selected range, no selection.
    static func withoutRanges(_ context: FieldContext) -> FieldContext {
        var context = context
        context.read.subtract([.selectedRange, .selection])
        context.selectedRange = nil
        context.selection = nil
        return context
    }

    /// `key` in `field` as such a field tells it; the app types what the session lets through, at the end. Whether the
    /// session took it.
    @discardableResult
    static func pressWithoutRanges(_ key: KeyEvent, in field: SuggestionsField) -> Bool {
        let handled = field.host.press(key, with: withoutRanges(field.host.context))
        if !handled, key.key == .character || key.key == .space, let text = key.printableText { field.host.document += text }
        field.noteTimers()
        return handled
    }

    static func typeWithoutRanges(_ text: String, in field: SuggestionsField) {
        for character in text { pressWithoutRanges(SuggestionKeys.key(character), in: field) }
    }

    /// Picks the row at `index` there as the keys do: ↓ until it is the one chosen, then Return.
    @discardableResult
    static func pickWithoutRanges(at index: Int, in field: SuggestionsField) -> Bool {
        var handled = true
        for _ in 0..<max(field.rows.count, 1) where field.host.panel?.highlighted != index {
            handled = pressWithoutRanges(SuggestionKeys.down, in: field) && handled
        }
        return pressWithoutRanges(SuggestionKeys.enter, in: field) && handled
    }

    // MARK: - Showing

    /// "Whether a row shows is decided by its `{match}` (which always starts with the token, compared as today: `compare`
    /// prefix or exact, full-width folded), never by the filled template." A source whose only template is a Markdown link,
    /// which never starts with what was typed, has its rows for "#70", in the list's order, as typing goes on.
    @Test func aRowShowsByItsMatchWhateverItsTemplateFills() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": "[{title}]({url})" }"#)
            let field = world.field()
            field.type("#70")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "\(field.issuesShown)")
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002"]), "\(field.issuesShown)")
            let fullWidth = world.field(app: "com.apple.TextEdit")
            fullWidth.type("＃709")
            #expect(fullWidth.waitForIssues(["#7090"]), "full-width folded, as today: \(fullWidth.issuesShown)")
        }
    }

    /// The rule that replaced "a row is offered only when what it inserts starts with what was typed": an `arg` that puts
    /// something before the issue's number ("Fixes #7002") shows for "#70" by its match, and goes in in place of the token;
    /// the one whose `arg` starts with it ("#7001: Crash at the edge") goes in as today, the rest after the token.
    @Test func anArgThatDoesntStartWithTheTokenShowsAndReplacesIt() async throws {
        try await inEnglish {
            let items = [CompletionItem(match: "#7001", title: "Crash", arg: "#7001: Crash at the edge"),
                         CompletionItem(match: "#7002", title: "Settings", arg: "Fixes #7002")]
            let world = try Self.world(insert: #"{ "default": "{arg}" }"#, items: items)
            let field = world.field()
            field.type("#70")
            #expect(field.waitForIssues(["#7001", "#7002"]), "both show, by their match: \(field.issuesShown)")
            let before = field.host.outputs.count
            #expect(field.pick(at: 1))
            #expect(field.document == "Fixes #7002", "\(field.document)")
            #expect(Self.changes(field, since: before) == [.replaced("Fixes #7002", 0..<3)], "\(Self.changes(field, since: before))")

            world.picks = []  // the order of the list, not of what was picked
            let today = world.field(app: "com.apple.TextEdit")
            today.type("#70")
            #expect(today.waitForIssues(["#7001", "#7002"]))
            let start = today.host.outputs.count
            #expect(today.pick(at: 0))
            #expect(today.document == "#7001: Crash at the edge", "\(today.document)")
            #expect(Self.changes(today, since: start) == [.inserted("01: Crash at the edge")], "\(Self.changes(today, since: start))")
        }
    }

    // MARK: - Replacing

    /// "One that doesn't [start with the token] is a replacement: the token is taken out and the whole text goes in", "by
    /// the field's range, then inserts the text, as one change the user can undo as one where the field allows." Return on
    /// the first row puts the Markdown link in place of "#70": one change, the token's range (UTF-16) in the field, the
    /// text before it as it was; Tab on another row does the same with its link, and so does a click on a row. The rows
    /// go.
    @Test func aReplacementTakesOutTheTokenAndPutsInTheWholeTextAsOneChange() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": "[{title}]({url})" }"#)
            let field = world.field()
            field.type("see #70")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "\(field.issuesShown)")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "see " + Self.link(Self.crash), "\(field.document)")
            #expect(Self.changes(field, since: before) == [.replaced(Self.link(Self.crash), 4..<7)],
                    "one change, the token's range: \(Self.changes(field, since: before))")
            #expect(field.rows.isEmpty, "the rows go: \(field.issuesShown)")

            world.picks = []  // the order of the list, not of what was picked
            let tab = world.field(app: "com.apple.TextEdit")
            tab.type("Fixed in #70")
            #expect(tab.waitForIssues(["#7001", "#7002", "#7090"]), "\(tab.issuesShown)")
            #expect(tab.press(SuggestionKeys.down))
            let start = tab.host.outputs.count
            #expect(tab.press(SuggestionKeys.tab))
            #expect(tab.document == "Fixed in " + Self.link(Self.settings), "\(tab.document)")
            #expect(Self.changes(tab, since: start) == [.replaced(Self.link(Self.settings), 9..<12)], "\(Self.changes(tab, since: start))")

            world.picks = []  // the order of the list, not of what was picked
            let click = world.field(app: "com.apple.mail")
            click.type("see #70")
            #expect(click.waitForIssues(["#7001", "#7002", "#7090"]), "\(click.issuesShown)")
            let clicked = click.host.outputs.count
            click.host.send(.pick(2))
            #expect(click.document == "see " + Self.link(Self.docs), "\(click.document)")
            #expect(Self.changes(click, since: clicked) == [.replaced(Self.link(Self.docs), 4..<7)], "\(Self.changes(click, since: clicked))")
        }
    }

    /// "Only where the field tells where its text is (`suggesting.ranges`: it reports the selected range); where it doesn't
    /// (terminals and others), such a template is skipped for the next in the list." With `["[{title}]({url})", "{arg}"]`, a
    /// field that reports no ranges gets the issue's number: only what wasn't typed of it goes in, nothing is replaced. The
    /// row shows there too (by its match).
    @Test func withoutRangesAReplacementIsSkippedForTheNextTemplate() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": ["[{title}]({url})", "{arg}"] }"#)
            let field = world.field()
            Self.typeWithoutRanges("see #70", in: field)
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "\(field.issuesShown)")
            let before = field.host.outputs.count
            #expect(Self.pressWithoutRanges(SuggestionKeys.enter, in: field))
            #expect(field.document == "see #7001", "\(field.document)")
            #expect(Self.changes(field, since: before) == [.inserted("01")], "\(Self.changes(field, since: before))")

            // The same list where the field reports ranges: the Markdown link, in place of the token.
            let ranges = world.field(app: "com.apple.TextEdit")
            ranges.type("see #70")
            #expect(ranges.waitForIssues(["#7001", "#7002", "#7090"]))
            #expect(ranges.press(SuggestionKeys.enter))
            #expect(ranges.document == "see " + Self.link(Self.crash), "\(ranges.document)")
        }
    }

    /// "The first template in its list whose variables the item all has and that can go in here." With
    /// `["[{title}]({url})", "{arg} {title}", "{arg}"]` and ranges: an issue with a title and an address puts in its link,
    /// one without an address its number and title, one with neither its number. Without ranges the link is skipped: the
    /// number and title.
    @Test func theFirstTemplateThatCanGoInHereIsUsed() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": ["[{title}]({url})", "{arg} {title}", "{arg}"] }"#,
                                       items: [Self.crash, Self.noLink, Self.bare])
            let expected: [(row: Int, document: String, change: Change)] = [
                (0, Self.link(Self.crash), .replaced(Self.link(Self.crash), 0..<3)),
                (1, "#7055 No link yet", .inserted("55 No link yet")),
                (2, "#7066", .inserted("66")),
            ]
            for (row, document, change) in expected {
                world.picks = []  // the order of the list, not of what was picked
                let field = world.field()
                field.type("#70")
                #expect(field.waitForIssues(["#7001", "#7055", "#7066"]), "\(field.issuesShown)")
                let before = field.host.outputs.count
                #expect(field.pick(at: row))
                #expect(field.document == document, "row \(row): \(field.document)")
                #expect(Self.changes(field, since: before) == [change], "row \(row): \(Self.changes(field, since: before))")
            }

            world.picks = []
            let field = world.field(app: "com.apple.TextEdit")
            Self.typeWithoutRanges("#70", in: field)
            #expect(field.waitForIssues(["#7001", "#7055", "#7066"]), "\(field.issuesShown)")
            #expect(Self.pickWithoutRanges(at: 0, in: field))
            #expect(field.document == "#7001 Crash at the screen's edge", "no ranges: the next template (\(field.document))")
        }
    }

    /// "A filled template that starts with the token (as normalized today) goes in as today: the rest after the token" (its
    /// case as typed), with ranges or without: "PROJ-123 Fix login" for "proj-12" adds "3 Fix login".
    @Test func aTemplateThatStartsWithTheTokenGoesInAsToday() async throws {
        try await inEnglish {
            let world = try Self.tracker(insert: #"{ "default": "{match} {title}" }"#)
            for reportsRanges in [true, false] {
                let field = world.field(app: reportsRanges ? SuggestionsApps.editor : "com.apple.TextEdit")
                if reportsRanges { field.type("proj-12") } else { Self.typeWithoutRanges("proj-12", in: field) }
                #expect(field.settle { field.shown(["PROJ-123", "PROJ-129"]) == ["PROJ-123", "PROJ-129"] }, "\(field.rows.map(\.text))")
                let before = field.host.outputs.count
                #expect(reportsRanges ? field.press(SuggestionKeys.tab) : Self.pressWithoutRanges(SuggestionKeys.tab, in: field))
                #expect(field.document == "proj-123 Fix login", "ranges \(reportsRanges): \(field.document)")
                #expect(Self.changes(field, since: before) == [.inserted("3 Fix login")],
                        "ranges \(reportsRanges): \(Self.changes(field, since: before))")
            }
        }
    }

    // MARK: - What is taken out

    /// A tracker's tickets after "PROJ-", with `insert` (its list, no query).
    static func tracker(insert: String) throws -> SuggestionsWorld {
        let world = SuggestionsWorld()
        let manifest = """
            { "name": "tracker", "version": "1.0.0", "type": "script", "script": "main.js", "hosts": ["tracker.example.com"],
              "completions": [ { "name": "tickets", "title": "Tickets", "prefix": "PROJ-", "list": true, "insert": \(insert) } ] }
            """
        let plugin = try #require(try SuggestionsPlugins.install(manifest, in: world.folder))
        world.plugins.append(plugin)
        world.runtime.list("tickets", items: [Self.ticket(123, "Fix login"), Self.ticket(129, "Dark mode")])
        world.enable(plugin, "tickets")
        return world
    }

    static func ticket(_ number: Int, _ title: String) -> CompletionItem {
        CompletionItem(match: "PROJ-\(number)", title: title,
                       variables: ["title": title, "url": "https://tracker.example.com/browse/PROJ-\(number)"])
    }

    /// "The replacement takes out exactly the token the user typed (prefix included), by the field's range": "＃70" typed
    /// in full width is taken out whole, "＃" too; "proj-12" after "(" (a boundary) is taken out in the case it was typed,
    /// the "(" left as it was.
    @Test func thePrefixIsTakenOutWithTheToken() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": "[{title}]({url})" }"#)
            let field = world.field()
            field.type("＃70")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "\(field.issuesShown)")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == Self.link(Self.crash), "nothing of the token left: \(field.document)")
            #expect(Self.changes(field, since: before) == [.replaced(Self.link(Self.crash), 0..<3)], "\(Self.changes(field, since: before))")

            let tracker = try Self.tracker(insert: #"{ "default": "[{title}]({url})" }"#)
            let ticket = tracker.field()
            ticket.type("(proj-12")
            #expect(ticket.settle { ticket.shown(["PROJ-123", "PROJ-129"]) == ["PROJ-123", "PROJ-129"] }, "\(ticket.rows.map(\.text))")
            let start = ticket.host.outputs.count
            #expect(ticket.press(SuggestionKeys.enter))
            let link = "[Fix login](https://tracker.example.com/browse/PROJ-123)"
            #expect(ticket.document == "(" + link, "\(ticket.document)")
            #expect(Self.changes(ticket, since: start) == [.replaced(link, 1..<8)], "\(Self.changes(ticket, since: start))")
        }
    }

    /// "Snippet rules (caret stops) don't apply": a title with `$1` and `${2:name}` goes in as it is written, and the caret
    /// stays after what went in (no move into it).
    @Test func aReplacementHasNoCaretStops() async throws {
        try await inEnglish {
            let stops = Self.issue(7077, "Use $1 or ${2:name} here")
            let world = try Self.world(insert: #"{ "default": "[{title}]({url})" }"#, items: [stops])
            let field = world.field()
            field.type("#707")
            #expect(field.waitForIssues(["#7077"]), "\(field.issuesShown)")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "[Use $1 or ${2:name} here](\(Self.url(7077)))", "as written: \(field.document)")
            #expect(!Self.movedTheCaret(field, since: before), "no caret stop: \(Array(field.host.outputs.dropFirst(before)))")
        }
    }

    // MARK: - Markdown link

    /// "Global Insert (and each app's own) gets one more choice: Markdown link: `[{title}]({url})`, else `{arg}`. It sits
    /// after With title and link." Its templates, its name, its place among the choices everywhere and per app (Off still
    /// last), and the config keeps it (everywhere and an app's own).
    @Test func markdownLinkIsAChoiceAfterWithTitleAndLink() async throws {
        try await inEnglish {
            #expect(SuggestionsInsert.markdownLink.templates == ["[{title}]({url})", "{arg}"])
            #expect(SuggestionsInsert.markdownLink.label == "Markdown link", "\(SuggestionsInsert.markdownLink.label)")
            #expect(SuggestionsInsert.offered == [.title, .titleAndLink, .markdownLink], "\(SuggestionsInsert.offered)")
            #expect(AppInsertChoice.offered == [.insert(.title), .insert(.titleAndLink), .insert(.markdownLink), .off],
                    "\(AppInsertChoice.offered.map(\.rawValue))")
            #expect(AppInsertChoice.insert(.markdownLink).label == "Markdown link")
            #expect(SuggestionsInsert(rawValue: "markdownLink") == .markdownLink)

            var config = Config.default
            config.suggestionsInsert = .markdownLink
            config.changeProfile(for: SuggestionsApps.slack) { $0.insertChoice = .insert(.markdownLink) }
            let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
            #expect(decoded.suggestionsSettings().insert == .markdownLink)
            #expect(decoded.suggestionsSettings().insert(for: SuggestionsApps.slack) == .markdownLink)
            #expect(decoded.profile(for: SuggestionsApps.slack)?.insertChoice == .insert(.markdownLink))
        }
    }

    /// Where a row goes in with Markdown link chosen everywhere.
    enum Place: String, CaseIterable, Sendable {
        /// An ordinary app's field that reports where its text is.
        case document
        /// A chat app's (Slack) that does too.
        case chat
        /// A terminal's, which doesn't.
        case terminal
        /// An ordinary app's that doesn't either.
        case documentWithoutRanges
    }

    /// "So `["[{title}]({url})", "{arg}"]` works everywhere: a Markdown link in a document, the number in a terminal." With
    /// Markdown link chosen everywhere (over the plugin's own, the Default), the issue's link goes in where the field reports
    /// ranges (a document, a chat app), its number where it doesn't (a terminal, a field that doesn't tell); an issue without
    /// an address puts in its number anywhere.
    @Test(arguments: Place.allCases)
    func markdownLinkChosenEverywhere(_ place: Place) async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": "{arg}", "chat": ["{arg} {url}", "{arg}"], "terminal": "{match}" }"#,
                                       items: [Self.crash, Self.noLink])
            world.switches.insert = .markdownLink
            let ranges = place == .document || place == .chat
            for item in [Self.crash, Self.noLink] {
                let field: SuggestionsField
                switch place {
                case .document, .documentWithoutRanges: field = world.field()
                case .chat: field = world.field(app: SuggestionsApps.slack)
                case .terminal: field = world.field(app: "com.apple.Terminal", terminal: true)
                }
                // "#700", "#705": that issue's row alone.
                let typed = String(item.match.prefix(4))
                if ranges { field.type(typed) } else { Self.typeWithoutRanges(typed, in: field) }
                #expect(field.waitForIssues([item.match]), "\(place), \(item.match): \(field.issuesShown)")
                #expect(ranges ? field.press(SuggestionKeys.enter) : Self.pressWithoutRanges(SuggestionKeys.enter, in: field))
                let expected = ranges && item.variables?["url"] != nil ? Self.link(item) : item.match
                #expect(field.document == expected, "\(place), \(item.match): \(field.document)")
            }
        }
    }

    /// "Global Insert (and each app's own)": Markdown link chosen for one app (Settings → General → "In these apps", as
    /// its profile keeps it) puts links in there, while the others follow the choice everywhere, or the plugin's own;
    /// an app's own With title wins there over Markdown link everywhere.
    @Test func markdownLinkChosenForOneApp() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": "{arg}" }"#)
            world.config.changeProfile(for: SuggestionsApps.editor) { $0.insertChoice = .insert(.markdownLink) }
            world.switches.appInserts = world.config.suggestionsSettings().appInserts

            /// What the first row for "#70" puts in, in `app`.
            func put(in app: String) -> String {
                let field = world.field(app: app)
                field.type("#70")
                #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "\(app): \(field.issuesShown)")
                #expect(field.press(SuggestionKeys.enter))
                return field.document
            }
            #expect(put(in: SuggestionsApps.editor) == Self.link(Self.crash), "its own: Markdown link")
            #expect(put(in: "com.apple.TextEdit") == "#7001", "elsewhere: the plugin's own")
            world.switches.insert = .title
            #expect(put(in: SuggestionsApps.editor) == Self.link(Self.crash), "its own over the one everywhere")
            #expect(put(in: "com.apple.TextEdit") == "#7001 Crash at the screen's edge", "elsewhere: With title")

            world.switches.insert = .markdownLink
            world.config.changeProfile(for: "com.apple.mail") { $0.insertChoice = .insert(.title) }
            world.switches.appInserts = world.config.suggestionsSettings().appInserts
            #expect(put(in: "com.apple.mail") == "#7001 Crash at the screen's edge", "an app's own With title")
            #expect(put(in: "com.apple.TextEdit") == Self.link(Self.crash), "Markdown link everywhere")
        }
    }

    // MARK: - Custom commands too

    /// A custom suggestions command's program, as these tests run it: tickets as lines "match⇥title⇥url", the second
    /// without an address.
    final class TicketLines: CommandCompletionRuntime, @unchecked Sendable {
        func list(_ command: CustomCommand) async throws -> Data {
            Data("JIRA-12\tFix login\thttps://jira.example.com/browse/JIRA-12\nJIRA-17\tDark mode\n".utf8)
        }

        func query(_ text: String, _ command: CustomCommand) async throws -> Data { Data() }
    }

    /// The rule is every source's: a custom command's rows with Markdown link chosen put in "[Fix login](…)" in place of
    /// "JIRA-1", and "JIRA-17" (no address) as today.
    @Test func aCustomCommandsRowsReplaceToo() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.switches.commands = [CustomCommand(name: "jira", type: .suggestions, summary: "Jira issues",
                                                     argv: ["/Users/me/bin/jira-list"], prefix: "JIRA-")]
            world.switches.insert = .markdownLink
            for (row, expected) in [(0, "see [Fix login](https://jira.example.com/browse/JIRA-12)"), (1, "see JIRA-17")] {
                world.picks = []
                let field = world.field { $0.suggestions.commandRuntime = TicketLines() }
                field.type("see JIRA-1")
                #expect(field.settle { field.rows.map(\.text) == ["JIRA-12", "JIRA-17"] }, "\(field.rows.map(\.text))")
                #expect(field.pick(at: row))
                #expect(field.document == expected, "\(field.document)")
            }
        }
    }
}
