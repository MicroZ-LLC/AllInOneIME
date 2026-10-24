import AllInOneIMECore
import Foundation
import Testing
@testable import AllInOneIMERime

/// The symbols the command trigger can't be (`Config.typingSymbols`), checked against rime-ice as it is deployed: every
/// symbol it doesn't type as itself, and every one its pinyin uses as a key, is refused; every one left types as itself.
/// A rime-ice update that changes what a symbol does fails here.
extension RimeEngineTests {
    static let symbols = (33...126).compactMap(UnicodeScalar.init).map(Character.init).filter { !$0.isLetter && !$0.isNumber }

    /// Typed with nothing composed, in Chinese mode: what goes in.
    @Test func everySymbolChinesePunctuationTypesOtherwiseIsRefused() throws {
        let session = try RimeFixture.session()
        defer { session.clearComposition() }
        var typesAsItself: [Character] = []
        for symbol in Self.symbols {
            session.clearComposition()
            _ = session.takeCommit()
            let handled = session.processKey(Int32(symbol.asciiValue!), mask: 0)
            let committed = session.takeCommit()
            let composing = session.snapshot().isComposing
            if !composing, !handled || committed == String(symbol) {
                typesAsItself.append(symbol)
            } else {
                #expect(Config.commandTriggerProblem(String(symbol)) == .typingSymbol(String(symbol)),
                        "\(symbol) types \(committed.map { "\"\($0)\"" } ?? "nothing"), composing: \(composing)")
            }
        }
        // What is left, less pinyin's keys (below) and /, is what the trigger can be.
        #expect(Set(Config.commandTriggers).isSubset(of: Set(typesAsItself.map(String.init))), "\(typesAsItself)")
    }

    /// The keys rime-ice's deployed schema gives pinyin a meaning while composing: the spelling's letters and separator, the
    /// lookup key, the keys that turn pages or pick a word's character, and the punctuation held after a digit.
    @Test func everyKeyPinyinUsesIsRefused() throws {
        _ = try RimeFixture.startup.get()
        // The user folder's when a patch made one, else the prebuilt one in the shared data.
        let deployed = [RimeFixture.userData, RimeFixture.sharedData].map { $0.appendingPathComponent("build/rime_ice.schema.yaml") }
        let schema = try String(contentsOf: try #require(deployed.first { FileManager.default.fileExists(atPath: $0.path) }),
                                encoding: .utf8)
        let names: [String: Character] = [
            "minus": "-", "equal": "=", "comma": ",", "period": ".", "semicolon": ";", "apostrophe": "'", "grave": "`",
            "slash": "/", "backslash": "\\", "bracketleft": "[", "bracketright": "]",
        ]
        func value(_ key: String) -> String? {
            guard let line = schema.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + ":") })
            else { return nil }
            var text = line.split(separator: ":", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 { text = String(text.dropFirst().dropLast()) }
            return text
        }
        var keys: [Character] = []
        for setting in ["alphabet", "delimiter", "digit_separators", "search"] {
            let text = try #require(value(setting), "\(setting) in the deployed schema")
            keys += text.filter { $0.isASCII && !$0.isLetter && !$0.isNumber && $0 != " " }
        }
        for setting in ["select_first_character", "select_last_character"] {
            let name = try #require(value(setting), "\(setting) in the deployed schema")
            keys.append(try #require(names[name] ?? (name.count == 1 ? name.first : nil), "\(name)"))
        }
        // Bindings of a key alone (no modifier), while composing or with candidates shown.
        let accepted = try NSRegularExpression(pattern: #"\{accept: "?([A-Za-z_]+|[^A-Za-z0-9 "])"?, send: [^}]*when: (composing|has_menu)\}"#)
        for match in accepted.matches(in: schema, range: NSRange(schema.startIndex..., in: schema)) {
            let name = String(schema[Range(match.range(at: 1), in: schema)!])
            if let symbol = names[name] ?? (name.count == 1 ? name.first : nil) { keys.append(symbol) }
        }
        #expect(Set(keys).isSuperset(of: ["'", "`", "-", "=", "[", "]", ",", ".", ":"]), "\(keys)")
        for key in keys {
            #expect(Config.commandTriggerProblem(String(key)) == .typingSymbol(String(key)), "\(key) is a pinyin key")
        }
    }
}
