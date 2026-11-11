import Foundation
import Testing

/// Source-level contract for the Mac-only SwiftUI editor. The app's CommandEditor lives in the executable target,
/// which the Mac test target cannot import; no UI automation or application launch is needed here.
struct CustomCommandEditorAcceptanceTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func existingEditorExposesAppearanceAndAnInlineTestRun() throws {
        let source = try String(contentsOf: Self.root.appendingPathComponent("Sources/AllInOneIME/CommandEditor.swift"), encoding: .utf8)
        let checks: [(Bool, String)] = [
            (source.contains("@State private var icon"), "icon selection state"),
            (source.contains("@State private var color"), "color selection state"),
            (source.contains("c.icon =") && source.contains("c.color ="), "save the selected icon and color"),
            (source.contains("IconToken"), "show the chosen appearance"),
            (source.contains("searchable") || source.contains("SearchField") || source.contains("searchText"), "search symbols"),
            (source.contains("Emoji") && source.contains("Default"), "Emoji and Default choices"),
            (source.contains("Test run") && source.contains("TextField"), "sample input beside Test run"),
            (source.contains("confirmationDialog") || source.contains("alert("), "confirm an AI test run"),
        ]
        for (present, behavior) in checks { #expect(present, "Missing \(behavior)") }
    }

    @Test func newEditorWordsAreTranslatedInEveryShippedLanguage() throws {
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: Self.root.appendingPathComponent("Resources/Localizable.xcstrings")))
            as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        // The Chinese side is in tr(zh, en); the seven other shipped translations live in this catalog.
        for key in ["Icon", "Color", "Emoji…", "Default", "Test run", "Sample input", "This sends the sample to %@", "Run"] {
            let entry = try #require(strings[key] as? [String: Any], "Missing Mac editor string: \(key)")
            let translations = try #require(entry["localizations"] as? [String: Any])
            for language in ["de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hant"] {
                let localized = translations[language] as? [String: Any]
                let unit = localized?["stringUnit"] as? [String: String]
                #expect(unit?["state"] == "translated" && unit?["value"]?.isEmpty == false,
                        "\(key) needs a \(language) translation")
            }
        }
    }
}
