import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, spec 1.3: the token (what was typed into this field since a boundary, in English mode and in pinyin
/// mode), its boundaries, `@` first, the full-width `＃`; whether a source applies (its prefix, `minChars`, `exact`; spec
/// 6.7: Latin letters in any case, the prefix's too; 6.8: without a prefix, only a token of digits). The rig:
/// SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsTokenAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: - The token

    /// English mode: the keys go to the app, and the session follows them: "#7" shows the issues starting with it (5 at
    /// most, in the list's order), each digit after it narrows them, a token nothing matches shows none.
    @Test func aPrefixAndDigitsTypedInEnglishModeShowTheSourcesRows() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(field.issuesShown)")
            #expect(field.document == "#7", "the keys went to the app (\(field.document))")
            #expect(field.footer.contains("GitHub issues"), "the footer names the source (\(field.footer))")
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "#70: \(field.issuesShown)")
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002"]), "#700: \(field.issuesShown)")
            field.type("9")
            #expect(field.waitForIssues([]), "#7009 matches nothing: \(field.issuesShown)")
            #expect(field.document == "#7009")
        }
    }

    /// Pinyin mode: "#" typed while pinyin is composed ends the composition as usual (the first candidate goes in) and
    /// starts a token; the digits after it extend it. Its rows take the panel: nothing is composed any more.
    @Test func aPrefixTypedWhilePinyinIsComposedStartsAToken() async throws {
        try await inEnglish {
            let world = SuggestionsWorld(input: .chinese)
            try world.github()
            let field = world.field()
            field.type("nihao")
            #expect(field.host.marked == "nihao", "pinyin is composed (\(field.host.marked))")
            field.type("#")
            #expect(field.document == "你好#" && field.host.marked.isEmpty, "the composition ended (\(field.document))")
            field.type("7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(field.issuesShown)")
            #expect(!field.host.composer.isComposing && field.host.marked.isEmpty)
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "#70: \(field.issuesShown)")
            #expect(field.document == "你好#70")
        }
    }

    /// "#" typed with nothing composed in pinyin mode starts a token too.
    @Test func aPrefixTypedInPinyinModeWithNothingComposedStartsAToken() async throws {
        try await inEnglish {
            let world = SuggestionsWorld(input: .chinese)
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(field.issuesShown)")
        }
    }

    /// The full-width "＃" (pinyin mode's, or a full-width layout's) counts as "#": the rows are the same, and what was
    /// typed stays as typed when a row goes in.
    @Test func aFullWidthHashCountsAsTheHash() async throws {
        try await inEnglish {
            let world = SuggestionsWorld(input: .chinese)
            try world.github()
            let pinyin = world.field(engine: PunctuatingEngine(fullWidth: true))
            pinyin.type("nihao")
            pinyin.type("#")
            #expect(pinyin.document == "你好＃", "\(pinyin.document)")
            pinyin.type("7")
            #expect(pinyin.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(pinyin.issuesShown)")
            pinyin.type("0")
            #expect(pinyin.waitForIssues(["#7001", "#7002", "#7090"]))
            #expect(pinyin.press(SuggestionKeys.tab), "Tab takes the first row")
            #expect(pinyin.document == "你好＃7001", "only what wasn't typed goes in (\(pinyin.document))")

            world.config.defaultInput = .english
            let english = world.field()
            english.type("＃7")
            #expect(english.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(english.issuesShown)")
        }
    }

    /// Text the input method didn't see (there before the field had the focus) is no token: a digit typed after "#7"
    /// already in the field shows nothing.
    @Test func textTheInputMethodDidntSeeIsNoToken() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let warm = world.field()
            warm.type("#7")
            #expect(warm.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "the list is there")

            let host = FakeHost(services: world.services(engine: PunctuatingEngine()))
            host.document = "see #7"
            host.focus()
            let field = SuggestionsField(host: host, world: world)
            field.type("0")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
        }
    }

    // MARK: - Boundaries

    enum Boundary: String, CaseIterable, Sendable {
        case space, comma, semicolon, slash, returnKey, click, anotherField, paste, left, right, home, end
    }

    /// Each boundary ends the token: the rows go, and a digit typed after it is a token of its own (none of the issues'
    /// rows). Space, other punctuation, Return, a click, another field, a paste, a caret moved by the arrows, Home or End.
    @Test(arguments: Boundary.allCases)
    func aBoundaryEndsTheToken(_ boundary: Boundary) async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(field.issuesShown)")
            switch boundary {
            case .space: field.type(" ")
            case .comma: field.type(",")
            case .semicolon: field.type(";")
            case .slash: field.type("/")
            case .returnKey: field.press(SuggestionKeys.enter)
            case .click:
                world.pointerUsed = true
                field.host.send(.commit)
            case .anotherField:
                field.host.send(.blur)
                field.host.focus()
            case .paste: field.press(SuggestionKeys.commandV)
            case .left: field.press(SuggestionKeys.left)
            case .right: field.press(SuggestionKeys.right)
            case .home: field.press(SuggestionKeys.home)
            case .end: field.press(SuggestionKeys.end)
            }
            if boundary != .click { #expect(field.issuesShown.isEmpty, "\(boundary): the rows go (\(field.issuesShown))") }
            field.type("0")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(boundary): \"0\" is a token of its own (\(field.issuesShown))")
        }
    }

    /// After a boundary, a new token starts: "#7 #8" shows the issues of "#8".
    @Test func aNewTokenStartsAfterABoundary() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            field.type(" #8")
            #expect(field.waitForIssues(["#8001"]), "\(field.issuesShown)")
        }
    }

    // MARK: - "@"

    /// "@" first is the command list's, never a token's start: the list opens as without suggestions, and what is typed
    /// after it shows no source's rows.
    @Test func atFirstIsTheCommandListsNeverAToken() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.press(SuggestionKeys.key("@"))
            #expect(field.host.composer.draft == "@", "the command list opened (\(field.host.composer.draft))")
            #expect(Command.builtins.map(\.name).contains(field.rows.first?.text ?? ""), "its rows are commands (\(field.rows.map(\.text)))")
            field.type("#7")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
            field.press(SuggestionKeys.escape)
            field.type(" #7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "the same after a space: \(field.issuesShown)")
        }
    }

    // MARK: - Which source applies

    /// A source applies once the token starts with its prefix and has `minChars` characters after it.
    @Test func minCharsCountsTheCharactersAfterThePrefix() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(manifest: SuggestionsPlugins.githubManifest(minChars: 2))
            let field = world.field()
            field.type("#")
            field.idle()
            #expect(field.issuesShown.isEmpty)
            field.type("7")
            field.idle()
            #expect(field.issuesShown.isEmpty, "one character after the prefix: none yet (\(field.issuesShown))")
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "\(field.issuesShown)")
        }
    }

    /// A token that doesn't start with the prefix isn't the source's, whatever follows.
    @Test func aTokenThatDoesntStartWithThePrefixIsntTheSources() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("fix#7")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
            field.type(" 7")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
            field.type(" #7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "with the prefix: \(field.issuesShown)")
        }
    }

    /// A source without a prefix compares the whole token (`exact`): no row for a partial AWS account id, its row once
    /// all 12 digits are typed.
    @Test func aSourceWithoutPrefixShowsOnlyAWholeMatch() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.aws()
            let field = world.field()
            let accounts = SuggestionsItems.accounts.map(\.match)
            field.type("12345678901")
            field.idle()
            #expect(field.shown(accounts).filter { $0 != "?" }.isEmpty, "a partial id: \(field.rows.map(\.text))")
            field.type("2")
            #expect(field.settle { field.shown(accounts) == ["123456789012"] }, "\(field.rows.map(\.text))")
            #expect(field.rows.contains { $0.text.contains("prod") || $0.comment.contains("prod") }, "its title")
            field.type("0")
            field.idle()
            #expect(field.shown(accounts).filter { $0 != "?" }.isEmpty, "13 digits match nothing")
        }
    }

    /// The part after the prefix is compared without case: "#docs" shows "#Docs-42".
    @Test func thePartAfterThePrefixIsComparedWithoutCase() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [CompletionItem(match: "#Docs-42", title: "Docs"), CompletionItem(match: "#dev-7", title: "Dev")])
            let field = world.field()
            field.type("#docs")
            #expect(field.settle { field.shown(["#Docs-42", "#dev-7"]) == ["#Docs-42"] }, "\(field.rows.map(\.text))")
        }
    }

    static let tickets = [CompletionItem(match: "PROJ-1201", title: "Login page"), CompletionItem(match: "PROJ-1234", title: "Export"),
                          CompletionItem(match: "PROJ-77", title: "Docs")]

    /// The prefix too is compared without case (spec 6.7): "proj-12" shows PROJ-1201 and PROJ-1234, "Proj-7" PROJ-77.
    @Test func thePrefixIsComparedWithoutCaseToo() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            let plugin = try #require(try SuggestionsPlugins.install(SuggestionsPlugins.trackerManifest, in: world.folder))
            world.plugins = [plugin]
            world.runtime.list("tickets", items: Self.tickets)
            world.enable(plugin, "tickets")
            let matches = Self.tickets.map(\.match)
            let field = world.field()
            field.type("proj-12")
            #expect(field.settle { field.shown(matches) == ["PROJ-1201", "PROJ-1234"] }, "\(field.rows.map(\.text))")
            field.type(" Proj-7")
            #expect(field.settle { field.shown(matches) == ["PROJ-77"] }, "\(field.rows.map(\.text))")
            field.type(" PROJ-12")
            #expect(field.settle { field.shown(matches) == ["PROJ-1201", "PROJ-1234"] }, "as declared: \(field.rows.map(\.text))")
        }
    }

    /// Without a prefix a source is only for tokens of digits (spec 6.8): an item whose `match` has letters never shows,
    /// typed in full or not; the account ids do.
    @Test func aSourceWithoutPrefixIsOnlyForTokensOfDigits() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.aws()
            world.runtime.list("accounts", items: SuggestionsItems.accounts + [CompletionItem(match: "dev456789012", title: "lettered"),
                                                                               CompletionItem(match: "4444-5555-6666", title: "dashed")])
            let candidates = ["dev456789012", "4444-5555-6666", "123456789012"]
            let field = world.field()
            field.type("dev456789012")
            field.idle()
            #expect(field.shown(candidates).filter { $0 != "?" }.isEmpty, "letters: \(field.rows.map(\.text))")
            field.type(" 4444-5555-6666")
            field.idle()
            #expect(field.shown(candidates).filter { $0 != "?" }.isEmpty, "a dash: \(field.rows.map(\.text))")
            field.type(" 123456789012")
            #expect(field.settle { field.shown(candidates) == ["123456789012"] }, "digits: \(field.rows.map(\.text))")
        }
    }
}
