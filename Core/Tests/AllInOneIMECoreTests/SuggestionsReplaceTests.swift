import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A row may replace the token (0.6.7.1 §1): whether it shows is its `match`'s, never its template's; what it puts in is
/// the first of its templates the item fills that can go in here. One that starts with the token follows it (only the rest
/// goes in); one that doesn't takes the token's place where the field tells where its text is (the token, prefix and all,
/// out by its range, the text in, as one `replace`), and is skipped for the next elsewhere (a terminal, a field that
/// reports no ranges). The rig is the acceptance tests' (Acceptance/SuggestionsAcceptanceTests.swift).
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsReplaceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static let link = "https://github.com/octo-org/octo-repo/issues/1234"

    /// An issue as the GitHub plugin returns it: the row shows "#1234 Fix login"; `{title}` is the title alone, `{url}` its
    /// link.
    static func issue(_ number: Int, _ title: String) -> CompletionItem {
        CompletionItem(match: "#\(number)", title: "#\(number) \(title)", arg: "#\(number)",
                       variables: ["url": "https://github.com/octo-org/octo-repo/issues/\(number)", "title": title])
    }

    /// The GitHub-like plugin, its own templates `insert`, its issues #1234 (a title and a link), #1299 (a title, no link)
    /// and #1277 (an `arg` that doesn't start with its match).
    static func world(insert: String) throws -> SuggestionsWorld {
        let world = SuggestionsWorld()
        try world.github(items: [Self.issue(1234, "Fix login"),
                                 CompletionItem(match: "#1299", title: "#1299 Dark mode", arg: "#1299", variables: ["title": "Dark mode"]),
                                 CompletionItem(match: "#1277", title: "Crash", arg: "Fixes #1277")],
                         manifest: SuggestionsPlugins.githubManifest(query: false, insert: insert))
        return world
    }

    static let markdown = #"{ "default": ["[{title}]({url})", "{arg}"], "terminal": "{match}" }"#

    /// The outputs since `from` that put text in: commits as "+text", replacements as "range text".
    static func edits(_ field: SuggestionsField, since from: Int) -> [String] {
        field.host.outputs.dropFirst(from).compactMap { output -> String? in
            switch output {
            case let .commit(text): return "+" + text
            case let .replace(text, range): return (range.map { "\($0)" } ?? "selection") + " " + text
            default: return nil
            }
        }
    }

    /// Types `text` in `field` as the field of an app that tells nothing of where its text is: no selected range with any
    /// key.
    static func typeWithoutRanges(_ field: SuggestionsField, _ text: String) {
        for character in text { pressWithoutRanges(field, SuggestionKeys.key(character)) }
    }

    @discardableResult
    static func pressWithoutRanges(_ field: SuggestionsField, _ key: KeyEvent) -> Bool {
        var context = field.host.context
        context.read.subtract([.selectedRange, .selection])
        (context.selectedRange, context.selection) = (nil, nil)
        let handled = field.host.press(key, with: context)
        if !handled, let text = key.printableText, key.key == .character { field.host.document += text }
        field.noteTimers()
        return handled
    }

    // MARK: - Shown by match, put in in the token's place

    /// `[{title}]({url})` never starts with "#12": the row shows all the same (by its match), and Tab puts the link in the
    /// token's place, "#12" out by its range (what was before it kept), in one change.
    @Test func aLinkTakesTheTokensPlace() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            field.host.document = "See "
            field.type("#12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "See [Fix login](\(Self.link))", "\(field.document)")
            #expect(Self.edits(field, since: before) == ["4..<7 [Fix login](\(Self.link))"])
            #expect(field.rows.isEmpty, "the token ended with it")
        }
    }

    /// An item without a link falls through to `{arg}`, which starts with the token: only the rest goes in, as before.
    @Test func theListFallsThroughToATemplateThatFollowsTheToken() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            field.type("#129")
            #expect(field.settle { field.issuesShown == ["#1299"] }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "#1299" && Self.edits(field, since: before) == ["+9"], "\(Self.edits(field, since: before))")
        }
    }

    /// The prefix is part of what is taken out, typed in full-width form too ("＃12" goes, the link comes).
    @Test func thePrefixIsTakenOutWithTheRest() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            field.type("＃12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "[Fix login](\(Self.link))", "\(field.document)")
        }
    }

    /// A row put in with a click takes the token's place too, by the range the field told with the last key (the token
    /// then, and what that key added to it).
    @Test func aClickedRowTakesTheTokensPlaceToo() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            field.host.document = "a "
            field.type("#123")
            #expect(field.settle { field.issuesShown == ["#1234"] }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            field.host.send(.pick(0))
            #expect(field.document == "a [Fix login](\(Self.link))", "\(field.document)")
            #expect(Self.edits(field, since: before) == ["2..<6 [Fix login](\(Self.link))"])

            // After ⌫ too: the token where it was, one character shorter.
            let again = world.field()
            again.host.document = "b "
            again.type("#1234")
            again.press(SuggestionKeys.backspace)
            again.host.document.removeLast()
            #expect(again.settle { again.issuesShown == ["#1234"] }, "\(again.rows.map(\.text))")
            again.host.send(.pick(0))
            #expect(again.document == "b [Fix login](\(Self.link))", "\(again.document)")
        }
    }

    /// An `arg` that doesn't start with its match (a plugin's "Fixes #1277") was never offered (spec 6.13); now it shows,
    /// by its match, and takes the token's place where the field tells where it is.
    @Test func anArgThatDoesntStartWithTheMatchReplaces() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": "{arg}", "terminal": "{match}" }"#)
            let field = world.field()
            field.type("#127")
            #expect(field.settle { field.issuesShown == ["#1277"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "Fixes #1277", "\(field.document)")
        }
    }

    // MARK: - Where the field tells nothing

    /// A field that reports no ranges: a template that doesn't start with the token is skipped for the next (`{arg}`);
    /// a row with no other never shows.
    @Test func withoutRangesTheTemplateIsSkippedForTheNext() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            Self.typeWithoutRanges(field, "#12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            #expect(Self.pressWithoutRanges(field, SuggestionKeys.tab))
            #expect(field.document == "#1234" && Self.edits(field, since: before) == ["+34"], "\(Self.edits(field, since: before))")

            let only = try Self.world(insert: #"{ "default": "[{title}]({url})", "terminal": "{match}" }"#)
            let other = only.field()
            Self.typeWithoutRanges(other, "#12")
            other.idle()
            #expect(other.rows.isEmpty, "nothing of it can go in there: \(other.rows.map(\.text))")
            other.type("3")
            #expect(other.settle { other.issuesShown == ["#1234"] }, "a key that tells where the token is: \(other.rows.map(\.text))")
        }
    }

    /// A terminal never tells where its text is: Markdown link chosen, its `{arg}` goes in there, the rest of it.
    @Test func aTerminalGetsTheNextTemplate() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": "{arg}", "terminal": "{match}" }"#)
            world.switches.insert = .markdownLink
            let field = world.field(app: "com.apple.Terminal", terminal: true)
            field.type("#12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#1234" && Self.edits(field, since: before) == ["+34"], "\(Self.edits(field, since: before))")
        }
    }

    /// The field told ranges as the rows were made, but not with the key that puts one in: its next template that starts
    /// with the token goes in, never a replacement by a range it no longer tells.
    @Test func aKeyWithoutRangesPutsInTheNextTemplate() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            field.type("#12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            #expect(Self.pressWithoutRanges(field, SuggestionKeys.enter))
            #expect(field.document == "#1234", "\(field.document)")
        }
    }

    // MARK: - Markdown link, everywhere and per app

    /// Markdown link chosen everywhere, or for an app, over the plugin's own templates; another app keeps its own.
    @Test func markdownLinkEverywhereAndPerApp() async throws {
        try await inEnglish {
            let world = try Self.world(insert: #"{ "default": ["{arg} {title}", "{arg}"], "terminal": "{match}" }"#)
            world.switches.appInserts = [SuggestionsApps.slack: .markdownLink]
            for (app, expected) in [(SuggestionsApps.slack, "[Fix login](\(Self.link))"), (SuggestionsApps.editor, "#1234 Fix login")] {
                let field = world.field(app: app)
                field.type("#1234")
                #expect(field.settle { field.issuesShown == ["#1234"] }, "\(app): \(field.rows.map(\.text))")
                #expect(field.press(SuggestionKeys.tab))
                #expect(field.document == expected, "\(app)")
            }
            world.switches.insert = .markdownLink
            let field = world.field(app: SuggestionsApps.editor)
            field.type("#1234")
            #expect(field.settle { field.issuesShown == ["#1234"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "[Fix login](\(Self.link))")
        }
    }

    /// Markdown link is offered after With title and link, everywhere and per app (the input menu's This App ▸ Insert
    /// too), named in both languages; its templates are the link, else the ID.
    @Test func markdownLinkIsOfferedAfterWithTitleAndLink() async {
        #expect(SuggestionsInsert.offered == [.title, .titleAndLink, .markdownLink])
        #expect(AppInsertChoice.offered.last == .off && AppInsertChoice.offered.dropLast().last == .insert(.markdownLink))
        #expect(SuggestionsInsert.markdownLink.templates == ["[{title}]({url})", "{arg}"])
        #expect(SuggestionsInsert(rawValue: "markdownLink") == .markdownLink)
        await withInterfaceLanguage("en") { #expect(SuggestionsInsert.markdownLink.label == "Markdown link") }
        await withInterfaceLanguage("zh-Hans") { #expect(SuggestionsInsert.markdownLink.label == "Markdown 链接") }
    }

    // MARK: - After a click, or with the field changed

    /// A click elsewhere in the field after the token (the input method isn't told of it: nothing is marked, so the app
    /// asks nothing of it): Tab, Return, ↓ ↑, → and Esc are the app's then, and the token is over. No row goes in, and
    /// nothing before the caret is taken out (by Tab's selection less the token's length: "llo" for a link).
    @Test func aClickSinceTheTokenGivesTheRowsKeysToTheApp() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            for key in [SuggestionKeys.tab, SuggestionKeys.enter, SuggestionKeys.down, SuggestionKeys.up, SuggestionKeys.right,
                        SuggestionKeys.escape] {
                world.pointerUsed = false
                let field = world.field()
                field.host.document = "Hello\nsee "
                field.type("#12")
                #expect(field.settle { field.issuesShown.first == "#1234" }, "\(key.key): \(field.rows.map(\.text))")
                // A click right after "Hello".
                world.pointerUsed = true
                field.host.selection = 5..<5
                let before = field.host.outputs.count
                #expect(!field.press(key), "\(key.key): the app's")
                #expect(Self.edits(field, since: before).isEmpty, "\(key.key): \(Self.edits(field, since: before))")
                #expect(field.document == "Hello\nsee #12" && field.rows.isEmpty, "\(key.key): \(field.document)")
            }
            // A click at the end, then typing on: a token of its own, its row put in in its place.
            world.pointerUsed = false
            let field = world.field()
            field.host.document = "Hello\nsee "
            field.type("#12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            world.pointerUsed = true
            #expect(!field.press(SuggestionKeys.tab))
            world.pointerUsed = false
            field.type(" #12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "Hello\nsee #12 [Fix login](\(Self.link))", "\(field.document)")
        }
    }

    /// The caret elsewhere by Tab's time with no click seen (text dragged in, a menu's command): Tab's selection isn't
    /// right after where the token started by the keys before, so nothing is taken out by it; the row goes in as a plain
    /// insertion would (the rest of its `{arg}`).
    @Test func aCaretMovedUnseenTakesNoTokenOut() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            field.host.document = "Hello\nsee "
            field.type("#12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            field.host.selection = 5..<5
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(Self.edits(field, since: before) == ["+34"], "\(Self.edits(field, since: before))")
            #expect(field.document == "Hello34\nsee #12", "nothing taken out: \(field.document)")
        }
    }

    /// What the shell checks before it replaces (`SessionOutput.checkNextReplace`): the token as typed in the range, and
    /// what a plain insertion would put in instead (the rest of `{arg}`, the next template). The field holds it: replaced.
    @Test func aReplacementIsReadBackFirst() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            field.host.document = "See "
            field.type("#12")
            #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            let checks = field.host.outputs.dropFirst(before).compactMap { output -> ReplacementCheck? in
                if case let .checkNextReplace(check) = output { return check } else { return nil }
            }
            #expect(checks == [ReplacementCheck(expected: "#12", otherwise: "34")])
            #expect(field.host.replacementsChecked == 1 && field.document == "See [Fix login](\(Self.link))", "\(field.document)")
        }
    }

    /// A row a key puts in says so first (`SessionOutput.rowByKey`), before what puts it in: Tab's, Return's and keypad
    /// Enter's, in the token's place, as a plain insertion of one character, and for a row that adds nothing (nothing
    /// follows it then). A row clicked doesn't: there is no key to answer.
    @Test func aRowPutInByAKeySaysSoFirst() async throws {
        try await inEnglish {
            /// What `outputs` say of putting text in, the marker too.
            func said(_ outputs: ArraySlice<SessionOutput>) -> [SessionOutput] {
                outputs.filter { output in
                    switch output {
                    case .rowByKey, .checkNextReplace, .replace, .commit, .commitAfterKey, .typeOut: return true
                    default: return false
                    }
                }
            }
            let world = try Self.world(insert: Self.markdown)
            let keypadEnter = KeyEvent(keyCode: VirtualKey.keypadEnter, characters: "\u{3}")
            for key in [SuggestionKeys.tab, SuggestionKeys.enter, keypadEnter] {
                let field = world.field()
                field.type("#12")
                #expect(field.settle { field.issuesShown.first == "#1234" }, "\(field.rows.map(\.text))")
                let before = field.host.outputs.count
                #expect(field.press(key))
                #expect(said(field.host.outputs.dropFirst(before))
                        == [.rowByKey, .checkNextReplace(ReplacementCheck(expected: "#12", otherwise: "34")),
                            .replace("[Fix login](\(Self.link))", range: 0..<3)], "\(key.key)")
                #expect(field.document == "[Fix login](\(Self.link))", "\(key.key): \(field.document)")
            }
            // A plain insertion of one character: what wasn't typed of "#1299".
            let plain = world.field()
            plain.type("#129")
            #expect(plain.settle { plain.issuesShown == ["#1299"] }, "\(plain.rows.map(\.text))")
            var before = plain.host.outputs.count
            #expect(plain.press(SuggestionKeys.enter))
            #expect(said(plain.host.outputs.dropFirst(before)) == [.rowByKey, .commit("9")] && plain.document == "#1299")
            // A row that adds nothing ("#1299" typed in full, its own row moved to): the marker alone, the key taken.
            let whole = world.field()
            whole.type("#1299")
            #expect(whole.settle { whole.issuesShown == ["#1299"] }, "\(whole.rows.map(\.text))")
            before = whole.host.outputs.count
            #expect(whole.pick(at: 0))
            #expect(said(whole.host.outputs.dropFirst(before)) == [.rowByKey] && whole.document == "#1299",
                    "\(said(whole.host.outputs.dropFirst(before)))")
            // Clicked: in the token's place, no marker.
            let clicked = world.field()
            clicked.type("#12")
            #expect(clicked.settle { clicked.issuesShown.first == "#1234" }, "\(clicked.rows.map(\.text))")
            before = clicked.host.outputs.count
            clicked.host.send(.pick(0))
            #expect(said(clicked.host.outputs.dropFirst(before))
                    == [.checkNextReplace(ReplacementCheck(expected: "#12", otherwise: "34")), .replace("[Fix login](\(Self.link))", range: 0..<3)])
        }
    }

    /// A row clicked once the text moved since the last key (text put in before the token by something the input method
    /// doesn't see): the range that key told holds other text now, so nothing is taken out; what a plain insertion would
    /// put in goes in at the caret, and nothing where there is none (a source whose only template is a link).
    @Test func aClickedRowWhereTheTextMovedTakesNothingOut() async throws {
        try await inEnglish {
            for (insert, expected) in [(Self.markdown, "Hi, a #1234"), (#"{ "default": "[{title}]({url})", "terminal": "{match}" }"#, "Hi, a #123")] {
                let world = try Self.world(insert: insert)
                let field = world.field()
                field.host.document = "a "
                field.type("#123")
                #expect(field.settle { field.issuesShown == ["#1234"] }, "\(field.rows.map(\.text))")
                field.host.document = "Hi, a #123"
                field.host.send(.pick(0))
                #expect(field.host.replacementsChecked == 1, "\(insert)")
                #expect(field.document == expected, "\(insert): \(field.document)")
            }
        }
    }

    /// The check itself, as both shells make it (`ReplacementCheck.apply`): the text in place of the range only where the
    /// field reads back what is expected there; else what goes in instead, at the caret, unless that's nothing.
    @Test func aCheckReplacesOnlyWhatItExpects() {
        func run(_ check: ReplacementCheck, on start: String, range: Range<Int>) -> (String, Bool) {
            var text = start as NSString
            let replaced = check.apply("[Fix](u)", range: range,
                                       read: { range in
                                           range.upperBound <= text.length ? text.substring(with: NSRange(location: range.lowerBound, length: range.count)) : nil
                                       },
                                       replace: { new, range in
                                           text = text.replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: new) as NSString
                                       },
                                       insert: { text = text.appending($0) as NSString })
            return (text as String, replaced)
        }
        let check = ReplacementCheck(expected: "#12", otherwise: "34")
        #expect(run(check, on: "See #12", range: 4..<7) == ("See [Fix](u)", true))
        #expect(run(check, on: "Hello see #12", range: 2..<5) == ("Hello see #1234", false), "other text there")
        #expect(run(check, on: "See #12", range: 6..<9) == ("See #1234", false), "nothing read back")
        #expect(run(ReplacementCheck(expected: "#12", otherwise: ""), on: "Hello see #12", range: 2..<5) == ("Hello see #12", false))
    }

    /// The range of a token whose end is the word Code holds never ends before it starts, were the token ever shorter than
    /// the word (it isn't): empty at worst, where a Range that ends before it starts would stop the input method.
    @Test func theWordsRangeNeverEndsBeforeItStarts() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
            let field = world.codeField()
            field.host.document = "x = "
            field.type("abc")
            #expect(field.host.composer.codeWord == "abc")
            let session = field.host.session!
            (session.suggesting.token, session.suggesting.selectedToken) = ("c", "c")
            (session.suggesting.selected, session.suggesting.ranges, session.suggesting.tokenStart) = (7..<7, true, nil)
            let row = SuggestionRow(text: "#1234", comment: "", insertion: "[Fix](u)", replaces: true, plainInsertion: "c",
                                    completion: "#1234", typed: "c", pick: nil, source: "GitHub")
            let outputs = session.collect { session.suggestionsInsert(row, key: nil) }
            let ranges = outputs.compactMap { output -> Range<Int>? in if case let .replace(_, range) = output { return range } else { return nil } }
            #expect(ranges == [6..<6], "\(outputs)")
        }
    }

    // MARK: - Reading the field

    /// The field's selection is read with a key only where it may matter: while a token is typed, or by a key that types a
    /// token's character; not by a space, Return, an arrow or a shortcut with no token (each read is a call to the app),
    /// nor in a terminal.
    @Test func theSelectionIsReadOnlyWhereItMayMatter() async throws {
        try await inEnglish {
            let world = try Self.world(insert: Self.markdown)
            let field = world.field()
            func reads(_ key: KeyEvent, in field: SuggestionsField) -> Bool {
                field.host.context(wantedFor: key).read.contains(.selectedRange)
            }
            for key in [SuggestionKeys.space, SuggestionKeys.enter, SuggestionKeys.left, SuggestionKeys.commandV, SuggestionKeys.backspace] {
                #expect(!reads(key, in: field), "\(key.key) with no token")
            }
            for character in ["#", "a", "7", "＃"] as [Character] {
                #expect(reads(SuggestionKeys.key(character), in: field), "\(character)")
            }
            field.type("#1")
            for key in [SuggestionKeys.space, SuggestionKeys.enter, SuggestionKeys.left, SuggestionKeys.backspace] {
                #expect(reads(key, in: field), "\(key.key) while a token is typed")
            }
            field.type(" ")
            #expect(!reads(SuggestionKeys.enter, in: field), "the token over")
            let terminal = world.field(app: "com.apple.Terminal", terminal: true)
            #expect(!reads(SuggestionKeys.key("#"), in: terminal), "a terminal tells none")
        }
    }

    // MARK: - The rows' own

    /// What a row puts in (`SuggestionRow.put`): a replacing one all of it where the field reports ranges, its plain text's
    /// rest elsewhere (nothing where it has none).
    @Test func aReplacingRowsPut() {
        let row = SuggestionRow(text: "#1234", comment: "", insertion: "[Fix](u)", replaces: true, plainInsertion: "#1234",
                                completion: "#1234", typed: "#12", pick: nil, source: "GitHub")
        #expect(row.put(ranges: true).text == "[Fix](u)" && row.put(ranges: true).replacing)
        #expect(row.put(ranges: false).text == "34" && !row.put(ranges: false).replacing)
        var none = row
        none.plainInsertion = "#12"
        #expect(none.put(ranges: false).text == "" && !none.put(ranges: false).replacing)
        var follows = row
        (follows.replaces, follows.insertion, follows.plainInsertion) = (false, "#1234 Fix", nil)
        #expect(follows.put(ranges: true).text == "34 Fix" && !follows.put(ranges: true).replacing)
        #expect(follows.rest(ranges: false) == "34 Fix")
    }
}
