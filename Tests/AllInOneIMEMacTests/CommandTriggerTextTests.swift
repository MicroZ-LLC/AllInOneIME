import AllInOneIMECore
import Foundation
import Testing

/// The Mac's own interface text (the input method's Settings window, menus and menu bar panel, the installer) names
/// commands with the command trigger the settings have, not a fixed "@": each text that names one goes through
/// `UIText.triggered` (or the window's `SettingsModel.triggered`, or a swap of "@" for the trigger). Read from the
/// sources, as the views can't be drawn here. And the String Catalogs' translations keep the ASCII @ the swap looks for.
struct CommandTriggerTextTests {
    static let root = StringCatalogTests.root

    /// The folders whose text is the Mac's interface; their self-tests (which check that text) and the README's sample
    /// panels aren't.
    static let interfaceSources = ["Sources/AllInOneIME", "Sources/AllInOneIMEInstaller", "Sources/AllInOneIMESettings"]

    /// Texts that name the "@" itself, not a command: Settings' menu of triggers ("@ (default)" marks the default), and the
    /// core's field for it in the settings document ("such as @ or ~" is its example).
    static let aboutTheTriggerItself = ["@（默认）", "@ (default)", "例如 @ 或 ~", "such as @ or ~"]

    /// The commands a text names with "@": each "@" but a format's ("%@", "%1$@"), an address's ("git@host") and
    /// Raycast's metadata ("@raycast.title").
    static func commandAts(_ text: String) -> Int {
        let characters = Array(text)
        var count = 0
        for (index, character) in characters.enumerated() where character == "@" {
            let before = index > 0 ? characters[index - 1] : " "
            if before == "%" || before == "$" { continue }
            if String(characters[..<index]).hasSuffix("git") { continue }
            if String(characters[(index + 1)...]).hasPrefix("raycast") { continue }
            count += 1
        }
        return count
    }

    /// A `tr(...)` call in a source file: its line, its string literals' text (Chinese, English), and whether what it
    /// returns names commands with the trigger (inside `triggered(`, or followed by `.replacingOccurrences(of: "@"`).
    struct Call {
        var line: Int
        var literals: [String]
        var triggered: Bool
    }

    static func calls(in source: String) -> [Call] {
        let bytes = Array(source.utf8)
        var calls: [Call] = []
        var index = 0

        func at(_ position: Int, _ text: String) -> Bool {
            var position = position
            for byte in text.utf8 {
                guard position < bytes.count, bytes[position] == byte else { return false }
                position += 1
            }
            return true
        }
        /// Past the comment or string literal at `position` (nil: neither is there), with a string's text.
        func skipped(_ position: Int) -> (end: Int, text: String?)? {
            if at(position, "//") {
                var end = position
                while end < bytes.count, bytes[end] != UInt8(ascii: "\n") { end += 1 }
                return (end, nil)
            }
            if at(position, "/*") {
                var end = position + 2
                while end < bytes.count, !at(end, "*/") { end += 1 }
                return (min(end + 2, bytes.count), nil)
            }
            var hashes = 0
            while at(position + hashes, "#") { hashes += 1 }
            guard at(position + hashes, "\"") else { return nil }
            let multiline = at(position + hashes, "\"\"\"")
            let close = (multiline ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
            var end = position + hashes + (multiline ? 3 : 1)
            var text: [UInt8] = []
            while end < bytes.count {
                if at(end, close) { return (end + close.utf8.count, String(decoding: text, as: UTF8.self)) }
                if hashes == 0, bytes[end] == UInt8(ascii: "\\") {
                    if at(end + 1, "(") {
                        // An interpolation: its expression, to the parenthesis that closes it.
                        end = closing(end + 1)
                        text.append(contentsOf: Array("%@".utf8))
                        continue
                    }
                    end += 2
                    continue
                }
                text.append(bytes[end])
                end += 1
            }
            return (end, String(decoding: text, as: UTF8.self))
        }
        /// Past the parenthesis that closes the one at `open`.
        func closing(_ open: Int) -> Int {
            var depth = 0, position = open
            while position < bytes.count {
                if let (end, _) = skipped(position) {
                    position = end
                    continue
                }
                if bytes[position] == UInt8(ascii: "(") { depth += 1 }
                if bytes[position] == UInt8(ascii: ")") {
                    depth -= 1
                    if depth == 0 { return position + 1 }
                }
                position += 1
            }
            return position
        }
        func literals(_ range: Range<Int>) -> [String] {
            var found: [String] = [], position = range.lowerBound
            while position < range.upperBound {
                if let (end, text) = skipped(position) {
                    if let text { found.append(text) }
                    position = end
                } else {
                    position += 1
                }
            }
            return found
        }
        func isIdentifier(_ byte: UInt8) -> Bool {
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ".")
        }

        var lines = 1, counted = 0
        while index < bytes.count {
            if let (end, _) = skipped(index) {
                index = end
                continue
            }
            guard at(index, "tr("), index == 0 || !isIdentifier(bytes[index - 1]) else {
                index += 1
                continue
            }
            let end = closing(index + 2)
            var before = index
            while before > 0, [UInt8(ascii: " "), UInt8(ascii: "\n")].contains(bytes[before - 1]) { before -= 1 }
            var after = end
            while after < bytes.count, [UInt8(ascii: " "), UInt8(ascii: "\n")].contains(bytes[after]) { after += 1 }
            lines += bytes[counted..<index].filter { $0 == UInt8(ascii: "\n") }.count
            counted = index
            let line = lines
            let triggered = String(decoding: bytes[max(0, before - 10)..<before], as: UTF8.self).hasSuffix("triggered(")
                || at(after, ".replacingOccurrences(of: \"@\"")
            calls.append(Call(line: line, literals: literals(index + 2..<end), triggered: triggered))
            index = end
        }
        return calls
    }

    static func interfaceFiles() throws -> [URL] {
        try interfaceSources.flatMap { folder in
            try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" && !$0.lastPathComponent.contains("SelfTest") && $0.lastPathComponent != "PanelShowcase.swift" }
        }
    }

    /// Every text of the Mac's own that names a command goes through the trigger, its Chinese and English naming as many.
    @Test func theMacsTextNamesCommandsWithTheTrigger() throws {
        let files = try Self.interfaceFiles()
        #expect(files.count > 20)
        var fixed: [String] = [], uneven: [String] = [], named = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for call in Self.calls(in: source) {
                let text = call.literals.joined(separator: " | ")
                let counts = call.literals.map(Self.commandAts)
                guard counts.contains(where: { $0 > 0 }), !Self.aboutTheTriggerItself.contains(where: text.contains) else { continue }
                named += 1
                let place = "\(file.lastPathComponent):\(call.line): \(text.prefix(90))"
                if !call.triggered { fixed.append(place) }
                // The Chinese and the English (with "+" joining a long one's parts, the parts are summed in order).
                if call.literals.count == 2, counts[0] != counts[1] { uneven.append(place) }
            }
        }
        #expect(fixed.isEmpty, "named with a fixed @ (wrap in model.triggered or UIText.triggered):\n\(fixed.joined(separator: "\n"))")
        #expect(uneven.isEmpty, "the Chinese and the English name a different number of commands:\n\(uneven.joined(separator: "\n"))")
        #expect(named >= 30, "texts naming commands found: \(named)")  // 34 since Settings v2 (fewer pages, shorter rows)
    }

    /// The reading of the sources finds what it looks for: a text wrapped, a text swapped after, one left fixed.
    @Test func theSourcesAreReadAsWritten() {
        let source = #"""
            // tr("@ in a comment", "@ in a comment")
            let a = model.triggered(tr("@agent 交给", "@agent hands it to"))
            let b = tr("自定义 @ 命令", "Custom @ Commands")
                .replacingOccurrences(of: "@", with: trigger)
            let c = tr("安装 @\(name(of: plugin)) \(version)？", "Install @\(name(of: plugin)) \(version)?")
            let d = tr("%@语音模型", "the %@ model") + tr("git@主机", "git@host")
            """#
        let calls = Self.calls(in: source)
        #expect(calls.map(\.line) == [2, 3, 5, 6, 6])
        #expect(calls.map(\.triggered) == [true, true, false, false, false])
        #expect(calls[2].literals == ["安装 @%@ %@？", "Install @%@ %@?"])
        #expect(calls.map { $0.literals.map(Self.commandAts) } == [[1, 1], [1, 1], [1, 1], [0, 0], [0, 0]])
    }

    /// The trigger swapped in for each "@" that names a command, the text as it is with @.
    @Test func aTextNamesCommandsWithTheTriggerGiven() {
        #expect(UIText.triggered("Install @stock 1.0?", trigger: "~") == "Install ~stock 1.0?")
        #expect(UIText.triggered("Custom @ Commands", trigger: "#") == "Custom # Commands")
        #expect(UIText.triggered("@agent and @reply", trigger: "@") == "@agent and @reply")
    }

    /// Each translation of a text that names commands keeps their ASCII @ (not ＠, not left out), so that the swap works
    /// in every language: the app's catalog and the core's.
    @Test(arguments: ["Resources/Localizable.xcstrings", "Core/Resources/Localizable.xcstrings"])
    func translationsKeepTheAt(_ catalog: String) throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(catalog))
        let strings = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        var wrong: [String] = []
        for (key, entry) in strings where Self.commandAts(key) > 0 && !Self.aboutTheTriggerItself.contains(where: key.contains) {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, localization) in localizations {
                guard let value = ((localization as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String else { continue }
                if Self.commandAts(value) != Self.commandAts(key) { wrong.append("\(language): \(key.prefix(60)) → \(value.prefix(60))") }
            }
        }
        #expect(wrong.isEmpty, "\(wrong.count) translations name commands differently:\n\(wrong.sorted().joined(separator: "\n"))")
    }
}
