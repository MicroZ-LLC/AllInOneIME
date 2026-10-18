import AllInOneIMECore
import Foundation
import Testing

/// What a String Catalog must be, the core's and each shell's (InterfaceTextTests, and the shell's own test).
public enum StringCatalogCheck {
    /// The interface languages the catalogs have besides English (Simplified Chinese comes from the code).
    public static let languages = ["de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hant"]

    /// The catalog at `url`'s entries, key → entry.
    static func entries(_ url: URL, sourceLocation: SourceLocation) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: url)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
        return try #require(catalog["strings"] as? [String: [String: Any]], sourceLocation: sourceLocation)
    }

    /// An entry's string for `language`, and its state.
    static func unit(_ entry: [String: Any], _ language: String) -> (value: String, state: String?)? {
        let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any]
        guard let unit = localization?["stringUnit"] as? [String: Any], let value = unit["value"] as? String else { return nil }
        return (value, unit["state"] as? String)
    }

    /// Every key in use (not stale) in the catalog at `url` has a translation in each of `languages`, not empty, and
    /// marked translated.
    public static func everyKeyTranslated(_ url: URL, languages: [String] = languages,
                                          sourceLocation: SourceLocation = #_sourceLocation) throws {
        let strings = try entries(url, sourceLocation: sourceLocation)
        let inUse = strings.filter { $0.value["extractionState"] as? String != "stale" }
        #expect(!inUse.isEmpty, sourceLocation: sourceLocation)
        for language in languages {
            let missing = inUse.filter { entry in
                guard let unit = unit(entry.value, language) else { return true }
                return unit.value.isEmpty || unit.state != "translated"
            }.keys.sorted()
            #expect(missing.isEmpty, "\(language): \(missing.count) keys without a translation: \(missing.prefix(5))",
                    sourceLocation: sourceLocation)
        }
    }

    /// The arguments `format` refers to, each with how often: "%@ of %@" and "%2$@ of %1$@" → [0: 1, 1: 1]; nil when it
    /// has a "%" that isn't "%%", "%@" or "%n$@" (`InterfaceText.fill` shows English for it then).
    public static func arguments(_ format: String) -> [Int: Int]? {
        var arguments: [Int: Int] = [:]
        var sequential = 0
        var rest = Substring(format)
        while let percent = rest.firstIndex(of: "%") {
            rest = rest[rest.index(after: percent)...]
            if rest.hasPrefix("%") { rest = rest.dropFirst(); continue }
            if rest.hasPrefix("@") {
                arguments[sequential, default: 0] += 1
                sequential += 1
                rest = rest.dropFirst()
                continue
            }
            let digits = rest.prefix(while: \.isASCII).prefix(while: \.isNumber)
            guard !digits.isEmpty, let position = Int(digits), position > 0,
                  rest.dropFirst(digits.count).hasPrefix("$@") else { return nil }
            arguments[position - 1, default: 0] += 1
            rest = rest.dropFirst(digits.count + 2)
        }
        return arguments
    }

    /// Every translation in the catalog at `url` refers to the same arguments as its English (the key, or a key of its
    /// own's English value), each as often, in any order: none dropped, none made up.
    public static func placeholdersMatch(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        for (key, entry) in try entries(url, sourceLocation: sourceLocation) {
            let english = unit(entry, "en")?.value ?? key
            let expected = arguments(english)
            #expect(expected != nil, "\(key)", sourceLocation: sourceLocation)
            for language in ((entry["localizations"] as? [String: Any]) ?? [:]).keys where language != "en" {
                guard let translation = unit(entry, language)?.value else { continue }
                #expect(arguments(translation) == expected, "\(language): \(key) → \(translation)", sourceLocation: sourceLocation)
            }
        }
    }

    /// The catalog at `url` is in English, and its translations fit their keys' arguments (else the app shows English
    /// for them).
    public static func translationsFit(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let data = try Data(contentsOf: url)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
        #expect(catalog["sourceLanguage"] as? String == "en", sourceLocation: sourceLocation)
        let strings = try #require(catalog["strings"] as? [String: [String: Any]], sourceLocation: sourceLocation)
        #expect(!strings.isEmpty, sourceLocation: sourceLocation)
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            func value(_ language: String) -> String? {
                (localizations[language]?["stringUnit"] as? [String: Any])?["value"] as? String
            }
            let english = value("en") ?? key
            let count = english.components(separatedBy: "%@").count - 1
            #expect(InterfaceText.fill(english, Array(repeating: "x", count: count)) != nil, "\(key)", sourceLocation: sourceLocation)
            for language in localizations.keys where language != "en" {
                guard let translation = value(language) else { continue }
                #expect(InterfaceText.fill(translation, Array(repeating: "x", count: count)) != nil, "\(language): \(key)",
                        sourceLocation: sourceLocation)
            }
        }
    }
}
