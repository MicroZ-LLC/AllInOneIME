import Foundation
import Testing

/// The input menu's changes (a rewrite style, the output language, @improve's translating, the default input, Code's
/// language, Autocomplete and Suggestions, This App's settings) write the config file as Settings saves it, through the
/// core's `Config.change`: only the keys they changed, so a key this version doesn't know and a custom command it refused
/// stay (ConfigChangeTests). None loads the config and writes it whole (`config.write()`). Read from the sources, as the
/// menu can't be drawn here.
struct InputMenuWritesTests {
    static func source(_ name: String) throws -> String {
        try String(contentsOf: StringCatalogTests.root.appendingPathComponent("Sources/AllInOneIME/\(name)"), encoding: .utf8)
    }

    /// The body of `func name(` in `source`: to the next line that closes a declaration at its indentation.
    static func body(of name: String, in source: String) -> Substring? {
        guard let start = source.range(of: "func \(name)(") else { return nil }
        let lineStart = source[..<start.lowerBound].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
        let indent = source[lineStart..<start.lowerBound].prefix { $0 == " " }
        guard let end = source.range(of: "\n\(indent)}\n", range: start.upperBound..<source.endIndex) else { return nil }
        return source[start.lowerBound..<end.upperBound]
    }

    /// Each place the menu changes the settings: the file and the function.
    static let writers = [
        ("InputMenu.swift", "toggleStyle"), ("InputMenu.swift", "setOutputLanguage"), ("InputMenu.swift", "toggleImproveTranslates"),
        ("InputMenu.swift", "setDefaultInput"), ("InputMenu.swift", "setCodingLanguage"),
        ("AppProfiles.swift", "changeAppProfile"), ("AutocompleteOverlay.swift", "set"), ("Suggestions.swift", "toggleSuggestions"),
        ("Suggestions.swift", "markLapsed"), ("Suggestions.swift", "markFollowed"),
    ]

    @Test(arguments: writers)
    func itWritesOnlyWhatItChanged(_ file: String, _ function: String) throws {
        let body = try #require(Self.body(of: function, in: try Self.source(file)), "\(file): \(function)")
        #expect(body.contains("try Config.change"), "\(file): \(function)")
        #expect(!body.contains(".write()"), "\(file): \(function)")
    }

    /// Nowhere in these files is the config written whole.
    @Test func noneWritesTheWholeConfig() throws {
        for file in Set(Self.writers.map(\.0)) {
            #expect(!(try Self.source(file)).contains("config.write()"), "\(file)")
        }
    }
}
