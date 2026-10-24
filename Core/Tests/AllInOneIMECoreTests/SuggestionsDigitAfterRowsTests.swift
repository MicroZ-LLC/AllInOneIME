import Foundation
import Testing
@testable import AllInOneIMECore

/// "#1" shows rows; "7" typed then makes "#17", whose rows show too (the owner saw none, 0.6.7): a digit typed while
/// rows show extends the token, never picks, and the rows are made again for it, from the list (it has #17) or, where
/// it hasn't, from the live query asked for "17". In English and in Code, in an ordinary app and a chat app, whether
/// the query comes back at once or later, and with the query asked from one character on (its answer for "1" then
/// leaves the query for "17" to the pause). GitHub-like: 23 items, #1 to #23, in their order of last update. The rig:
/// Acceptance/SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsDigitAfterRowsTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// The issues' numbers in the list's order: last updated first.
    static let order = [23, 22, 21, 17, 20, 15, 19, 18, 14, 16, 12, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]

    static func list(with17: Bool) -> [CompletionItem] {
        order.filter { with17 || $0 != 17 }.map { SuggestionsItems.issue($0, "Issue \($0)") }
    }

    struct Case: CustomStringConvertible, Sendable {
        var code: Bool
        var app: String
        var with17: Bool
        var heldQuery: Bool
        var queryFrom: Int
        var description: String {
            "\(code ? "Code" : "English") in \(app), #17 \(with17 ? "listed" : "not listed"), query from \(queryFrom)"
                + (heldQuery ? ", answered late" : "")
        }
    }

    static let cases: [Case] = [false, true].flatMap { code in
        ["com.apple.Notes", SuggestionsApps.chrome].flatMap { app in
            [false, true].flatMap { with17 in
                [false, true].flatMap { heldQuery in
                    [2, 1].map { Case(code: code, app: app, with17: with17, heldQuery: heldQuery, queryFrom: $0) }
                }
            }
        }
    }

    @Test(arguments: cases)
    func aDigitTypedWhileRowsShowExtendsTheToken(_ c: Case) async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            let manifest = SuggestionsPlugins.githubManifest().replacingOccurrences(of: "\"queryMinChars\": 2",
                                                                                     with: "\"queryMinChars\": \(c.queryFrom)")
            try world.github(items: Self.list(with17: c.with17), manifest: manifest)
            world.runtime.query("1", items: [SuggestionsItems.issue(1, "Issue 1")])
            world.runtime.query("17", items: [SuggestionsItems.issue(17, "Issue 17")])
            world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
            let field = c.code ? world.codeField(app: c.app) : world.field(app: c.app)
            field.host.readsWhatIsWanted = true
            field.type("#1")
            #expect(field.settle { field.issuesShown.count == 5 && field.issuesShown.allSatisfy { $0.hasPrefix("#1") } },
                    "\(c): \(field.issuesShown)")
            world.runtime.holdQueries = c.heldQuery
            defer { world.runtime.releaseAll() }
            field.type("7")
            #expect(field.document == "#17", "\(c): \(field.document.debugDescription)")
            if c.heldQuery {
                field.idle(0.2)
                world.runtime.release("17")
            }
            #expect(field.settle { field.issuesShown == ["#17"] }, "\(c): \(field.issuesShown), queries \(world.runtime.queries)")
            // Not listed, the row is the query's for "17".
            #expect(c.with17 || world.runtime.queries.last == "17", "\(c): \(world.runtime.queries)")
        }
    }
}

extension SuggestionsDigitAfterRowsTests {
    /// The owner's "#17" (0.6.7): "#1" typed, the "1" key down handed over to the input method a second time (the same
    /// event; the field got it once), then "7". Through the shell's guard (`KeyEchoes`, as `KeyFeed` hands keys over)
    /// the copy is answered as the first was (the app's) and the session never sees it: its token stays "#17", not
    /// "#117", and #17's row shows. In English and in Code, in Notes and in Chrome, the copy right after the key or after
    /// the rows came.
    @Test(arguments: [false, true].flatMap { code in
        ["com.apple.Notes", SuggestionsApps.chrome].flatMap { app in [false, true].map { (code, app, $0) } }
    })
    func aKeyDownHandedOverTwiceIsTypedOnce(_ code: Bool, _ app: String, _ late: Bool) async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: Self.list(with17: true))
            world.runtime.query("1", items: [SuggestionsItems.issue(1, "Issue 1")])
            world.runtime.query("17", items: [SuggestionsItems.issue(17, "Issue 17")])
            world.addCode("python", packs: [try SuggestionsCodingPacksTests.shipped("python")])
            let field = code ? world.codeField(app: app) : world.field(app: app)
            field.host.readsWhatIsWanted = true
            let keys = KeyFeed(field)
            let label = "\(code ? "Code" : "English") in \(app)\(late ? ", the copy after the rows" : "")"
            keys.type("#1")
            if !late { #expect(keys.again() == false, "\(label): the copy answered as the first (the app's)") }
            #expect(field.settle { field.issuesShown.count == 5 && field.issuesShown.allSatisfy { $0.hasPrefix("#1") } },
                    "\(label): \(field.issuesShown)")
            if late { #expect(keys.again(after: 0.3) == false, "\(label): the copy answered as the first (the app's)") }
            keys.type("7")
            #expect(field.document == "#17" && keys.reached == 3, "\(label): \(field.document.debugDescription), \(keys.reached) keys")
            #expect(field.settle { field.issuesShown == ["#17"] }, "\(label): \(field.issuesShown), queries \(world.runtime.queries)")
            #expect(!world.runtime.queries.contains { $0.hasPrefix("11") }, "\(label): queries \(world.runtime.queries)")
        }
    }
}
