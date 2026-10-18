import Foundation

/// Reads the interface text's String Catalog (Resources/Localizable.xcstrings, JSON) without Apple's tools: for the
/// shells that ship the catalog itself rather than the `.lproj` bundles the Makefile compiles from it (Windows,
/// Android, Linux). A language's table is catalog key → translated format, as `InterfaceText.translate(_:in:)` and
/// `InterfaceText.tableLookup` take it.
public enum StringCatalog {
    /// `language`'s translations in the catalog `data`: each entry's string for that language, when it has a non-empty
    /// one. Entries without one (not translated yet, or only plural or device variations, which `tr` doesn't use) are
    /// left out, so they show in English. Empty for a language the catalog doesn't have.
    public static func table(_ language: String, from data: Data) throws -> [String: String] {
        try tables(from: data)[language] ?? [:]
    }

    /// Every language's table in the catalog `data`, the source language's too (where a key of its own has its
    /// English).
    public static func tables(from data: Data) throws -> [String: [String: String]] {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        var tables: [String: [String: String]] = [:]
        for (key, entry) in catalog.strings {
            for (language, localization) in entry.localizations ?? [:] {
                guard let value = localization.stringUnit?.value, !value.isEmpty else { continue }
                tables[language, default: [:]][key] = value
            }
        }
        return tables
    }

    /// The languages with a translation in the catalog `data`, sorted.
    public static func languages(in data: Data) throws -> [String] {
        try tables(from: data).keys.sorted()
    }

    // As much of the catalog's format as the tables need; the rest (comments, states, variations) is skipped.
    private struct Catalog: Decodable {
        var strings: [String: Entry]
    }

    private struct Entry: Decodable {
        var localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        var stringUnit: StringUnit?
    }

    private struct StringUnit: Decodable {
        var value: String?
    }
}
