import Foundation
import Testing

/// Autocomplete set to Always for one app sends what is typed there whatever the main switch says: where an app's choice
/// is made, it says where the text goes, as the main switch does (`AutocompleteSwitch.destination`, the core's
/// `Autocomplete.Words.destination`): Settings → Apps' Autocomplete, and the input menu's This App. Read from the sources,
/// as the views and menus can't be drawn here.
struct AppAutocompleteDestinationTests {
    static let source = StringCatalogTests.root.appendingPathComponent("Sources/AllInOneIME/AppProfiles.swift")

    /// The text of `source` from `start` to the first `end` after it.
    static func part(_ source: String, from start: String, to end: String) -> Substring? {
        guard let from = source.range(of: start), let to = source.range(of: end, range: from.upperBound..<source.endIndex) else {
            return nil
        }
        return source[from.lowerBound..<to.lowerBound]
    }

    /// Settings → Apps: the Autocomplete choice of an app (as everywhere, Always, Never) says where the text goes.
    @Test func settingsAppsSaysWhereTheTextGoes() throws {
        let text = try String(contentsOf: Self.source, encoding: .utf8)
        let picker = try #require(Self.part(text, from: "get: { profile.autocomplete }", to: "// Suggestions as everywhere"))
        #expect(picker.contains("AutocompleteSwitch.destination"), "\(picker)")
    }

    /// The input menu's This App: under its Autocomplete choices, the line that says where the text goes, as under the
    /// main switch.
    @Test func thisAppMenuSaysWhereTheTextGoes() throws {
        let text = try String(contentsOf: Self.source, encoding: .utf8)
        let menu = try #require(Self.part(text, from: "func appMenuItem(", to: "func changeAppProfile("))
        let choices = try #require(Self.part(String(menu), from: "#selector(setAppAutocomplete(_:)), value: \"off\"",
                                             to: "menu.addItem(.separator())"))
        #expect(choices.contains("AutocompleteSwitch.destination"), "\(choices)")
    }
}
