import AllInOneIMECore
import Foundation

/// A host scenario (`Core/Tests/HostScenarios/*.hostcase`, the host scenario contract v1): a field, the steps a user and
/// the host take in it, and what is expected after them, the same on every profile. One step per line; `#` outside
/// quotes starts a comment; a line ending in `@profile <names>` holds only on those profiles (with the owner's OK, said
/// in a comment).
struct HostCase: Sendable, CustomStringConvertible {
    var name = ""
    /// Where it was read from (a file, or a test's own text), for the failures' messages.
    var source = ""
    var profiles: [HostProfile] = HostProfile.allCases
    var language: Language = .chinese
    var field = HostText()
    var steps: [Step] = []

    var description: String { name.isEmpty ? source : name }

    struct Step: Sendable {
        var line: Int
        var action: Action
        /// The profiles it holds on (`@profile`); nil: every one.
        var only: Set<HostProfile>?

        func applies(to profile: HostProfile) -> Bool { only?.contains(profile) ?? true }
    }

    enum Action: Sendable {
        case type(String)
        case keys([HostKey])
        /// A click at a text offset; nil: outside the field.
        case click(Int?)
        case focus(Focus)
        /// The input source switched to ABC (true) and back (false).
        case switchToABC(Bool)
        case appClears
        case wait(TimeInterval)
        case expect(Expectation)
    }

    enum Focus: String, Sendable { case away, back, otherapp, closewindow }

    enum Expectation: Sendable {
        case doc(String)
        case marked(String?)
        case panel(shown: Bool)
        case language(Language)
        /// What autocomplete and the AI would read before the caret; nil: nothing (unreadable).
        case contextBefore(String?)
        case switches(Int)
        case calls([CallBudget])
        case noLost
    }

    /// At most (or exactly) `limit` calls of `method` through IMK for each key.
    struct CallBudget: Sendable, CustomStringConvertible {
        enum Comparison: String, Sendable { case atMost = "<=", below = "<", exactly = "==" }
        var method: String
        var comparison: Comparison
        var limit: Int

        func holds(_ count: Int) -> Bool {
            switch comparison {
            case .atMost: count <= limit
            case .below: count < limit
            case .exactly: count == limit
            }
        }

        var description: String { "\(method)\(comparison.rawValue)\(limit)" }
    }

    struct ParseError: Error, CustomStringConvertible {
        var source: String
        var line: Int
        var message: String
        var description: String { "\(source):\(line): \(message)" }
    }
}

/// A key a scenario presses: a named one or a character, with the modifiers held for it; or a modifier pressed alone
/// (`shift`, `capslock`).
struct HostKey: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case named(String)
        case character(Character)
        /// A modifier key pressed and released on its own (a tap of Shift).
        case modifierTap(String)
        case capsLock
    }

    var kind: Kind
    var modifiers: [String] = []

    static func parse(_ token: String) -> HostKey? {
        let lower = token.lowercased()
        if lower == "capslock" { return HostKey(kind: .capsLock) }
        if HostKeys.modifiers[lower] != nil { return HostKey(kind: .modifierTap(lower)) }
        var parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "cmd++": the key is "+".
        if token.hasSuffix("++") { parts = Array(parts.dropLast(2)) + ["+"] }
        guard let last = parts.last, !last.isEmpty else { return nil }
        let modifiers = parts.dropLast().map { $0.lowercased() }
        guard modifiers.allSatisfy({ HostKeys.modifiers[$0] != nil }) else { return nil }
        if HostKeys.named[last.lowercased()] != nil { return HostKey(kind: .named(last.lowercased()), modifiers: modifiers) }
        guard last.count == 1, let character = last.first else { return nil }
        return HostKey(kind: .character(character), modifiers: modifiers)
    }
}

/// A field's text as a scenario writes it (`TEXT`): `|` the caret, `[…]` a selection, `{…}` marked text; a backslash
/// keeps the next character as it is.
struct HostText: Sendable, Equatable {
    var text = ""
    /// UTF-16 offsets.
    var selection = NSRange(location: 0, length: 0)
    var marked: NSRange?

    init() {}

    init(markup: String) throws {
        var plain = "", caret: Int?, selectionStart: Int?, selected: NSRange?, markedStart: Int?, markedRange: NSRange?
        var escaped = false
        for character in markup {
            let length = (plain as NSString).length
            if escaped {
                plain.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\": escaped = true
            case "|": caret = length
            case "[": selectionStart = length
            case "]":
                guard let start = selectionStart else { throw HostCase.ParseError(source: "", line: 0, message: "] without [") }
                selected = NSRange(location: start, length: length - start)
            case "{": markedStart = length
            case "}":
                guard let start = markedStart else { throw HostCase.ParseError(source: "", line: 0, message: "} without {") }
                markedRange = NSRange(location: start, length: length - start)
            default: plain.append(character)
            }
        }
        text = plain
        selection = selected ?? NSRange(location: caret ?? (plain as NSString).length, length: 0)
        marked = markedRange
    }
}

extension HostCase {
    /// Reads a scenario from `text`; `source` names it in errors.
    static func parse(_ text: String, source: String) throws -> HostCase {
        var scenario = HostCase()
        scenario.source = source
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let number = index + 1
            func fail(_ message: String) -> ParseError { ParseError(source: source, line: number, message: message) }
            var line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var only: Set<HostProfile>?
            if let at = line.range(of: " @profile ") ?? line.range(of: "\t@profile ") {
                let names = line[at.upperBound...].split(whereSeparator: { $0 == " " || $0 == "," })
                only = Set(try names.map { name in
                    guard let profile = HostProfile(rawValue: String(name)) else { throw fail("no profile \(name)") }
                    return profile
                })
                line = String(line[..<at.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            let (directive, rest) = split(line)
            switch directive.uppercased() {
            case "NAME": scenario.name = rest
            case "PROFILES": scenario.profiles = try profiles(rest, fail: fail)
            case "LANG":
                guard let language = language(rest) else { throw fail("LANG is chinese or english, not \(rest)") }
                scenario.language = language
            case "TEXT":
                do {
                    scenario.field = try HostText(markup: try quoted(rest, markup: true, fail: fail))
                } catch let error as ParseError {
                    throw fail(error.message)
                }
            default:
                guard let action = try action(directive.uppercased(), rest, fail: fail) else { throw fail("unknown step \(directive)") }
                scenario.steps.append(Step(line: number, action: action, only: only))
            }
        }
        return scenario
    }

    private static func action(_ directive: String, _ rest: String, fail: (String) -> ParseError) throws -> Action? {
        switch directive {
        case "TYPE":
            return .type(rest.hasPrefix("\"") ? try quoted(rest, fail: fail) : rest)
        case "KEY":
            let keys = try rest.split(separator: " ").map { token in
                guard let key = HostKey.parse(String(token)) else { throw fail("no key \(token)") }
                return key
            }
            guard !keys.isEmpty else { throw fail("KEY without a key") }
            return .keys(keys)
        case "CLICK":
            let words = rest.split(separator: " ").map(String.init)
            if words == ["outside"] { return .click(nil) }
            guard words.count == 2, words[0] == "inside", let offset = Int(words[1]) else { throw fail("CLICK inside <offset> | outside") }
            return .click(offset)
        case "FOCUS":
            guard let focus = Focus(rawValue: rest) else { throw fail("FOCUS away | back | otherapp | closewindow") }
            return .focus(focus)
        case "SWITCH":
            guard rest == "abc" || rest == "back" else { throw fail("SWITCH abc | back") }
            return .switchToABC(rest == "abc")
        case "APP":
            guard rest == "clears" else { throw fail("APP clears") }
            return .appClears
        case "WAIT":
            guard let seconds = duration(rest) else { throw fail("WAIT <n>ms | <n>s") }
            return .wait(seconds)
        case "EXPECT":
            return .expect(try expectation(rest, fail: fail))
        default:
            return nil
        }
    }

    private static func expectation(_ text: String, fail: (String) -> ParseError) throws -> Expectation {
        let (what, rest) = split(text)
        switch what {
        case "doc": return .doc(try quoted(rest, fail: fail))
        case "marked": return .marked(rest == "none" ? nil : try quoted(rest, fail: fail))
        case "panel":
            guard rest == "shown" || rest == "hidden" else { throw fail("EXPECT panel shown | hidden") }
            return .panel(shown: rest == "shown")
        case "lang":
            guard let language = language(rest) else { throw fail("EXPECT lang chinese | english") }
            return .language(language)
        case "context":
            if rest == "unreadable" { return .contextBefore(nil) }
            let (before, quotedText) = split(rest)
            guard before == "before" else { throw fail("EXPECT context before \"…\" | unreadable") }
            return .contextBefore(try quoted(quotedText, fail: fail))
        case "switches":
            guard let count = Int(rest) else { throw fail("EXPECT switches <n>") }
            return .switches(count)
        case "calls":
            let budgets = try rest.split(separator: " ").map { try budget(String($0), fail: fail) }
            guard !budgets.isEmpty else { throw fail("EXPECT calls <method><=<n>") }
            return .calls(budgets)
        case "nolost": return .noLost
        default: throw fail("unknown expectation \(what)")
        }
    }

    private static func budget(_ token: String, fail: (String) -> ParseError) throws -> CallBudget {
        for comparison in [CallBudget.Comparison.atMost, .exactly, .below] {
            let parts = token.components(separatedBy: comparison.rawValue)
            if parts.count == 2, !parts[0].isEmpty, let limit = Int(parts[1]) {
                return CallBudget(method: parts[0], comparison: comparison, limit: limit)
            }
        }
        if let equal = token.firstIndex(of: "="), let limit = Int(token[token.index(after: equal)...]) {
            return CallBudget(method: String(token[..<equal]), comparison: .exactly, limit: limit)
        }
        throw fail("a call budget is <method><=<n>, <method><<n> or <method>==<n>, not \(token)")
    }

    private static func profiles(_ text: String, fail: (String) -> ParseError) throws -> [HostProfile] {
        if text == "all" { return HostProfile.allCases }
        return try text.split(whereSeparator: { $0 == " " || $0 == "," }).map { name in
            guard let profile = HostProfile(rawValue: String(name)) else { throw fail("no profile \(name)") }
            return profile
        }
    }

    private static func language(_ text: String) -> Language? {
        switch text {
        case "chinese": .chinese
        case "english": .english
        default: nil
        }
    }

    private static func duration(_ text: String) -> TimeInterval? {
        if text.hasSuffix("ms"), let value = Double(text.dropLast(2)) { return value / 1000 }
        if text.hasSuffix("s"), let value = Double(text.dropLast()) { return value }
        return nil
    }

    /// The first word and the rest, trimmed.
    private static func split(_ text: String) -> (String, String) {
        guard let space = text.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return (text, "") }
        return (String(text[..<space]), text[space...].trimmingCharacters(in: .whitespaces))
    }

    /// A quoted string's text: `\"` a quote, `\n` and `\t` a line break and a tab, `\` and any other character the
    /// character. With `markup` (`TEXT`'s) the backslash stays before any other character, for the markup to keep it.
    private static func quoted(_ text: String, markup: Bool = false, fail: (String) -> ParseError) throws -> String {
        guard text.count >= 2, text.first == "\"", text.last == "\"" else { throw fail("expected a quoted string, not \(text)") }
        var result = "", escaped = false
        for character in text.dropFirst().dropLast() {
            if escaped {
                switch character {
                case "\"": result.append("\"")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default:
                    if markup { result.append("\\") }
                    result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// `line` without its comment: from a `#` outside quotes.
    private static func stripComment(_ line: String) -> String {
        var inQuotes = false, escaped = false
        for index in line.indices {
            let character = line[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
            } else if character == "#", !inQuotes {
                return String(line[..<index])
            }
        }
        return line
    }
}
