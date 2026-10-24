import Foundation
import Testing
@testable import AllInOneIMECore

/// A source's prefix of letters and a dash ("PROJ-") typed in pinyin mode: librime holds the letters as pinyin and turns
/// a page on "-" (none on the first), and a digit after it picks a candidate, so the prefix never got into the field.
/// Now the "-" that finishes the prefix of a source that may show rows here ends the composition as typed (not
/// converted): the letters and the dash go in, the token starts, and digits after it go in as typed, the rows coming as
/// in English (spec 1.3, as "#" ends a composition). Otherwise pinyin is as it was. The rig:
/// Acceptance/SuggestionsAcceptanceTests.swift (`PunctuatingEngine`: "-" is taken while composing, digits pick).
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsPinyinPrefixTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static let tickets = [CompletionItem(match: "PROJ-1201", title: "Login page"), CompletionItem(match: "PROJ-1234", title: "Panel"),
                          CompletionItem(match: "PROJ-7", title: "Docs")]

    /// A world in pinyin mode with the tracker's tickets after "PROJ-" (`enable`: its source on).
    static func world(enable: Bool = true) throws -> SuggestionsWorld {
        let world = SuggestionsWorld(input: .chinese)
        let plugin = try #require(try SuggestionsPlugins.install(SuggestionsPlugins.trackerManifest, in: world.folder))
        world.plugins = [plugin]
        world.runtime.list("tickets", items: tickets)
        if enable { world.enable(plugin, "tickets") }
        return world
    }

    /// "proj" in pinyin, then "-": "proj-" goes in as typed, nothing is left marked; "12" after it is typed, the rows
    /// show, and Tab puts the first in, what was typed kept.
    @Test func theDashThatFinishesAPrefixEndsPinyinAsTyped() async throws {
        try await inEnglish {
            let field = try Self.world().field()
            field.type("proj")
            #expect(field.host.marked == "proj", "pinyin holds the letters (\(field.host.marked))")
            field.type("-")
            #expect(field.document == "proj-" && field.host.marked.isEmpty, "\(field.document.debugDescription), marked \(field.host.marked)")
            field.type("12")
            #expect(field.document == "proj-12", "the digits are typed, not picks: \(field.document.debugDescription)")
            #expect(field.settle { field.shown(Self.tickets.map(\.match)) == ["PROJ-1201", "PROJ-1234"] }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "proj-1201", "\(field.document.debugDescription)")
        }
    }

    /// After Chinese put in, a new token: "你好" then "proj-7".
    @Test func afterChineseItStartsANewToken() async throws {
        try await inEnglish {
            let field = try Self.world().field()
            field.type("nihao ")
            #expect(field.document == "你好", "\(field.document.debugDescription)")
            field.type("proj-7")
            #expect(field.document == "你好proj-7", "\(field.document.debugDescription)")
            #expect(field.settle { field.shown(Self.tickets.map(\.match)) == ["PROJ-7"] }, "\(field.rows.map(\.text))")
        }
    }

    /// Pinyin as it was where no source has that prefix: its own off, letters that aren't only the prefix's ("woproj"),
    /// another key (",").
    @Test func elsewhereThePinyinIsAsItWas() async throws {
        try await inEnglish {
            let off = try Self.world(enable: false).field()
            off.type("proj-")
            #expect(off.host.marked == "proj" && off.document.isEmpty, "no source: \(off.document.debugDescription), \(off.host.marked)")

            let world = try Self.world()
            let longer = world.field()
            longer.type("woproj-")
            #expect(longer.host.marked == "woproj" && longer.document.isEmpty, "\(longer.document.debugDescription), \(longer.host.marked)")

            let other = world.field()
            other.type("pro")
            other.type("-")
            #expect(other.host.marked == "pro" && other.document.isEmpty, "\"pro-\" starts no prefix: \(other.host.marked)")
        }
    }
}
