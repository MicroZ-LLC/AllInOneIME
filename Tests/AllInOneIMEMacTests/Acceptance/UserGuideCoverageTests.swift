import Foundation
import Testing
@testable import AllInOneIMECore

struct UserGuideCoverageTests {
    private var guideURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/user-guide.md")
    }

    @Test func shippedGuideCoversSettingsFieldsAndBuiltInCommands() throws {
        let url = guideURL
        #expect(FileManager.default.fileExists(atPath: url.path), "the app must ship Resources/user-guide.md")
        let guide = try String(contentsOf: url, encoding: .utf8)
        #expect(guide.contains("## ") && guide.contains("设置"), "the guide needs short English and Chinese sections")
        let searchable = guide.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        for topic in ["Input Sources", "English", "Accessibility", "Shuangpin", "magic key", "English words",
                      "clipboard history", "autocomplete", "Translate as You Type", "privacy", "updates"] {
            #expect(searchable.contains(topic.lowercased()), "guide omits \(topic)")
        }
        #expect(guide.contains("Settings → Input → Chinese → Typing"))

        // Read the same SettingsDocument fields the SettingsService tests do, from isolated config files.
        // Different providers and input modes expose conditional fields that the default document misses.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guide-fields-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fields: [String: SettingsDocument.Field] = [:]
        let samples = Provider.allCases.map { provider in
            "{\"provider\":\"\(provider.rawValue)\",\"inputLanguages\":[\"en\",\"zh\"]}"
        } + ["{\"inputLanguages\":[\"en\"]}", "{\"inputLanguages\":[\"zh\"]}"]
        for (index, json) in samples.enumerated() {
            let folder = directory.appendingPathComponent(String(index), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let configURL = folder.appendingPathComponent("config.json")
            try Data(json.utf8).write(to: configURL)
            let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
            let document = SettingsService(store: SettingsStore(configURL: configURL), platform: .mac, library: library).document()
            func collect(_ field: SettingsDocument.Field) {
                fields[field.id] = field
                for child in field.schema ?? [] { collect(child) }
                for item in field.items ?? [] {
                    for child in item.fields ?? [] { collect(child) }
                }
            }
            for section in document.sections {
                for field in section.fields { collect(field) }
            }
        }
        #expect(!fields.isEmpty, "the test must see the Settings document")
        for field in fields.values.sorted(by: { $0.id < $1.id }) {
            // Fields without a visible label give readers no Settings name to look up in the guide.
            guard !field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let label = field.label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            #expect(searchable.contains(label) || searchable.contains("`\(field.id)`"),
                    "guide omits Settings field \(field.id) (\(field.label))")
        }
        for command in Command.builtins {
            #expect(searchable.contains("@\(command.name)"), "guide omits built-in @\(command.name)")
        }
    }
}
