import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions with the largest list a plugin may return (20,000 items, `CompletionList.maxItems`): each key is handled
/// on the session's thread (the main thread on the Mac), so its rows are made from what matches only, at most 5 of them
/// and the rows picked before, never by making a row of every item first. The rig: Acceptance/SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsPerformanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// The most a key may take, as the median of the keys timed: a few milliseconds in a release build; a debug build is
    /// many times slower, and a loaded machine too.
    #if DEBUG
    static let bound: Duration = .milliseconds(12)
    #else
    static let bound: Duration = .milliseconds(3)
    #endif

    static let items = (1...CompletionList.maxItems).map { number in
        CompletionItem(match: "#\(number)", title: "#\(number) Issue number \(number)", subtitle: "octo-org/octo-repo · open",
                       arg: "#\(number)", variables: ["url": "https://github.com/octo-org/octo-repo/issues/\(number)"])
    }

    /// How long each of `keys` takes to be handled (the rows made and shown), in order; ⌫ takes the last character
    /// back, as the app does.
    func timed(_ keys: [KeyEvent], in field: SuggestionsField) -> [Duration] {
        let clock = ContinuousClock()
        return keys.map { key in
            var handled = false
            let duration = clock.measure { handled = field.press(key) }
            if !handled, key == SuggestionKeys.backspace, !field.host.document.isEmpty { field.host.document.removeLast() }
            return duration
        }
    }

    static func median(_ durations: [Duration]) -> Duration { durations.sorted()[durations.count / 2] }

    /// Keys over a list of 20,000: many rows matching ("#1"), a few ("#1999"), one, none ("#199999"), and back; some rows
    /// picked before, one of them far down the list, which still comes first.
    @Test func keysStayQuickWithTheLargestList() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: Self.items, manifest: SuggestionsPlugins.githubManifest(query: false))
            world.picks = [SuggestionPick(plugin: "github", source: "issues", match: "#19998"),
                           SuggestionPick(plugin: "github", source: "issues", match: "#1500")]
            let field = world.field()
            field.type("#1")
            #expect(field.settle { field.rows.count == 5 }, "\(field.rows.map(\.text))")
            #expect(field.issuesShown == ["#1500", "#19998", "#1", "#10", "#11"], "picked first: \(field.issuesShown)")

            // Many matching ("#1": 11,111; "#10": 1,111), then none ("#199999"), each key timed.
            var keys: [KeyEvent] = []
            for digit in "0123456789" { keys += [SuggestionKeys.key(digit), SuggestionKeys.backspace] }
            let many = timed(keys, in: field)
            field.type("9999")
            let none = timed(Array(repeating: [SuggestionKeys.key("9"), SuggestionKeys.backspace], count: 5).flatMap { $0 }, in: field)
                .enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
            #expect(field.document == "#19999" && field.issuesShown == ["#19999"], "\(field.document): \(field.issuesShown)")
            func shown(_ durations: [Duration]) -> [String] { durations.map { $0.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))) } }
            #expect(Self.median(many) < Self.bound, "many matching: \(shown(many))")
            #expect(Self.median(none) < Self.bound, "none matching: \(shown(none))")
        }
    }

    /// A template whose insertion never starts with what was typed (`"default": "{url}"`, a plugin's mistake) has no rows,
    /// and costs a key over a list of 20,000 no more than a good one: only so many matching items are tried for a key.
    @Test func aTemplateThatNeverFitsCostsAKeyLittle() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: Self.items, manifest: SuggestionsPlugins.githubManifest(
                query: false, insert: #"{ "default": "{url}", "chat": "{url}", "terminal": "{match}" }"#))
            let field = world.field()
            field.type("#1")
            #expect(field.settle { world.lastStatus?.items == CompletionList.maxItems }, "loaded: \(String(describing: world.lastStatus))")
            var keys: [KeyEvent] = []
            for digit in "0123456789" { keys += [SuggestionKeys.key(digit), SuggestionKeys.backspace] }
            let durations = timed(keys, in: field)
            #expect(field.rows.isEmpty, "\(field.rows.map(\.text))")
            let shown = durations.map { $0.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))) }
            #expect(Self.median(durations) < Self.bound, "\(shown)")
        }
    }

    /// The rows over a list of 20,000 are those a list of all of them gives: the first 5 matching, in its order, after the
    /// picked ones.
    @Test func theRowsAreTheFirstFiveMatching() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: Self.items, manifest: SuggestionsPlugins.githubManifest(query: false))
            world.picks = [SuggestionPick(plugin: "github", source: "issues", match: "#1977")]
            let field = world.field()
            field.type("#19")
            #expect(field.settle { field.issuesShown == ["#1977", "#19", "#190", "#191", "#192"] }, "\(field.issuesShown)")
            field.type("7")
            #expect(field.settle { field.issuesShown == ["#1977", "#197", "#1970", "#1971", "#1972"] }, "\(field.issuesShown)")
        }
    }
}
