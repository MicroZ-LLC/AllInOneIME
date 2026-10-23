import Foundation
import Testing
@testable import AllInOneIMECore

/// The Mac's settings document as it is, text and all, against a golden (Fixtures/settings-mac-document.txt): with each
/// of its action keys, so that what Windows' document says differently (its keys, places and paths) never changes the
/// Mac's. In `SettingsServiceTests`: keys in memory only. `SETTINGS_WRITE_GOLDENS=1` writes the golden again.
extension SettingsServiceTests {
    /// The languages the core writes its text in. The others are the String Catalog's translations of the English, by
    /// its key, which the core's tests have no lookup for (`InterfaceText.lookup`): they show English here.
    static let macGoldenLanguages = ["en", "zh-Hans"]

    /// A config with the fields whose text the platforms word differently: the action key, Chinese (the English words),
    /// a program among the custom commands (the editor's warning), no extension folder of the system's own.
    static func macGoldenConfig(_ language: String, actionKey: String) -> String {
        #"{"uiLanguage": "\#(language)", "provider": "anthropic", "inputLanguages": ["en", "zh"], "actionKey": "\#(actionKey)", "#
            + #""extensionFolders": [], "customCommands": [{"name": "py", "type": "run", "argv": ["python3", "-c", "{input}"]}]}"#
    }

    /// The Mac's documents as lines, one a value: the whole document with the action key Return, and the action key's
    /// field with each other key. What is the system's own is left out ("$any"): the config file's path, the interface
    /// languages (by the system's names), Apple's model (offered where the system has it).
    func macDocumentLines() throws -> [String] {
        typealias JSON = AIConfig.JSONValue
        var lines: [String] = []
        for language in Self.macGoldenLanguages {
            for key in ["enter", "space", "optionTap", "optionSpace"] {
                let (service, url) = try service(Self.macGoldenConfig(language, actionKey: key), platform: .mac)
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let document = try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(withInterfaceLanguage(language) { service.document() }))
                lines.append("== \(language), actionKey \(key)")
                if key == "enter" {
                    Self.flatten(Self.withoutTheSystemsOwn(document), "", into: &lines)
                } else {
                    Self.flatten(Self.withoutTheSystemsOwn(document)["sections"].flatMap { sections in
                        sections.members.flatMap { $0["fields"]?.members ?? [] }.first { $0["id"] == .string("actionKey") }
                    } ?? .null, "actionKey", into: &lines)
                }
            }
        }
        return lines
    }

    /// `document` with the system's own values as "$any" (`macDocumentLines`).
    static func withoutTheSystemsOwn(_ document: AIConfig.JSONValue) -> AIConfig.JSONValue {
        func masked(_ field: AIConfig.JSONValue) -> AIConfig.JSONValue {
            guard case var .object(members) = field else { return field }
            switch members["id"] {
            case .string("configFile"): members["value"] = .string("$any")
            case .string("uiLanguage"): members["choices"] = .string("$any")
            case .string("provider"): members["choices"] = members["choices"].map { .array($0.members.filter { $0["value"] != .string("apple") }) }
            default: break
            }
            if let items = members["items"] {
                members["items"] = .array(items.members.map { item in
                    guard case var .object(fields) = item, let own = fields["fields"] else { return item }
                    fields["fields"] = .array(own.members.map(masked))
                    return .object(fields)
                })
            }
            return .object(members)
        }
        guard case var .object(members) = document, let sections = members["sections"] else { return document }
        members["sections"] = .array(sections.members.map { section in
            guard case var .object(section) = section, let fields = section["fields"] else { return section }
            section["fields"] = .array(fields.members.map(masked))
            return .object(section)
        })
        return .object(members)
    }

    /// `value`'s leaves as "path = JSON" lines, in key order; a list's members by their id (or value) where they have one.
    static func flatten(_ value: AIConfig.JSONValue, _ path: String, into lines: inout [String]) {
        func joined(_ key: String) -> String { path.isEmpty ? key : path + "." + key }
        switch value {
        case let .object(members):
            for key in members.keys.sorted() { flatten(members[key]!, joined(key), into: &lines) }
        case let .array(members):
            if members.isEmpty { lines.append(path + " = []") }
            for (index, member) in members.enumerated() {
                let name: String
                if case let .string(id)? = member["id"] { name = id }
                else if case let .string(value)? = member["value"] { name = "=" + value }
                else { name = String(index) }
                flatten(member, path + "[" + name + "]", into: &lines)
            }
        case let .string(text):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            lines.append(path + " = " + String(decoding: (try? encoder.encode(text)) ?? Data(), as: UTF8.self))
        case let .number(number):
            lines.append(path + " = " + (number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)))
        case let .bool(on):
            lines.append(path + " = " + (on ? "true" : "false"))
        case .null:
            lines.append(path + " = null")
        }
    }

    @Test func theMacsDocumentIsItsGolden() throws {
        let lines = try macDocumentLines()
        let text = lines.joined(separator: "\n") + "\n"
        if ProcessInfo.processInfo.environment["SETTINGS_WRITE_GOLDENS"] == "1" {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/settings-mac-document.txt")
            try Data(text.utf8).write(to: source)
            return
        }
        let url = try #require(Bundle.module.url(forResource: "settings-mac-document", withExtension: "txt", subdirectory: "Fixtures"))
        let golden = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let now = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // The first lines that differ, each with the document it is in.
        var document = "", shown = 0
        for index in 0..<max(golden.count, now.count) where shown < 20 {
            let (was, is_) = (index < golden.count ? golden[index] : "(none)", index < now.count ? now[index] : "(none)")
            if is_.hasPrefix("== ") { document = is_ }
            guard was != is_ else { continue }
            Issue.record("\(document), line \(index + 1):\n  golden: \(was)\n  now:    \(is_)")
            shown += 1
        }
    }
}

private extension AIConfig.JSONValue {
    subscript(key: String) -> AIConfig.JSONValue? {
        guard case let .object(members) = self else { return nil }
        return members[key]
    }

    /// An array's members; none for anything else.
    var members: [AIConfig.JSONValue] {
        guard case let .array(members) = self else { return [] }
        return members
    }
}
