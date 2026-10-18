import AllInOneIMECore
import Foundation
import Testing

/// What a String Catalog must be, the core's and each shell's (InterfaceTextTests, and the shell's own test).
public enum StringCatalogCheck {
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
