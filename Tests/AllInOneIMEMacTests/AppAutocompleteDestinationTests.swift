import Foundation
import Testing

/// Autocomplete sends what is typed to the model it uses: where it is turned on, the switch says where the text goes
/// (`AutocompleteSwitch.destination`, the core's `Autocomplete.Words.destination`): Settings → General's Autocomplete, as
/// the input menu's switch. An app's own choice (always, never) is no longer offered (Settings v2): This App has none,
/// and one set before is listed under General → Previous per-app settings (`PreviousAppSettings`). Read from the sources,
/// as the views and menus can't be drawn here.
struct AppAutocompleteDestinationTests {
    static func source(_ name: String) throws -> String {
        try String(contentsOf: StringCatalogTests.root.appendingPathComponent("Sources/AllInOneIME/\(name)"), encoding: .utf8)
    }

    /// The text of `source` from `start` to the first `end` after it.
    static func part(_ source: String, from start: String, to end: String) -> Substring? {
        guard let from = source.range(of: start), let to = source.range(of: end, range: from.upperBound..<source.endIndex) else {
            return nil
        }
        return source[from.lowerBound..<to.lowerBound]
    }

    /// Settings → General: Autocomplete's switch says where the text goes, whether it's on or not.
    @Test func settingsGeneralSaysWhereTheTextGoes() throws {
        let text = try Self.source("SettingsWindow.swift")
        let row = try #require(Self.part(text, from: "private var autocompleteSection: some View {", to: ".settingsRow(.autocomplete"))
        #expect(row.contains("AutocompleteSwitch.destination(model.config)"), "\(row)")
    }

    /// The input menu's This App offers no autocomplete of its own: Insert and No AI only.
    @Test func thisAppMenuHasNoAutocompleteChoice() throws {
        let text = try Self.source("AppProfiles.swift")
        let menu = try #require(Self.part(text, from: "func appMenuItem(", to: "func changeAppProfile("))
        #expect(!menu.contains("autocomplete") && menu.contains("toggleAppNoAI") && menu.contains("setAppSuggestionsInsert"), "\(menu)")
    }
}
