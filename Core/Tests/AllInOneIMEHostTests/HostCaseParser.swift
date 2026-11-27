import Foundation
import AllInOneIMECore
import AllInOneIMETestSupport

/// Reads a host scenario (`HostCase`), one step a line (the host scenario contract, v1):
///
///     NAME     what it checks
///     PROFILES all | nstextview chromium electron tellsnothing
///     LANG     chinese | english            the field's starting language, before the first step that does something
///     SET      switchKey capsLock           a config key set before the first step that does something (v1.1)
///     TEXT     "Hi Bob|"                    the field's text: | caret, [..] selection, {..} marked
///     TYPE     nihao                        plain keys, one a character (quoted for spaces or #)
///     KEY      space enter shift cmd+z …    keys by name, modifiers joined with +; one or more
///     CLICK    inside 2 | outside
///     FOCUS    away | back | other | otherfield | otherapp | closewindow
///     SWITCH   abc | back
///     APP      clears
///     WAIT     300ms | 1.5s
///     EXPECT   doc "…" | marked "…" | marked none | preedit "…" | preedit none | panel shown|hidden
///              | lang chinese|english
///              | context before "…" | context after "…" | context unreadable | fallback none | switches 1
///              | calls length<=1 | nolost
///
/// `#` starts a comment (not inside quotes). In quotes `\` makes the next character itself (`\"`, `\\`, `\|`, `\[` …);
/// `\n` is a line break, `\t` a tab. A step for some profiles only ends with `@profile name …`, and a comment on its line
/// or the one before gives the owner's OK for it: anything else is the same on every profile.
enum HostCaseParser {
    static func parse(_ source: String, fallbackName: String) throws -> HostCase {
        var scenario = HostCase(name: fallbackName, profiles: HostProfile.allCases, language: .chinese, steps: [])
        var commentAbove = false
        for (index, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = index + 1
            let (code, comment) = try splitComment(raw.replacingOccurrences(of: "\r", with: ""), line: number)
            let line = code.trimmingCharacters(in: .whitespaces)
            defer { commentAbove = line.isEmpty && comment }
            guard !line.isEmpty else { continue }
            do {
                try read(line, into: &scenario, line: number, commented: comment || commentAbove)
            } catch let error as HostCaseError {
                throw HostCaseError(error.message, line: number)
            }
        }
        return scenario
    }

    /// One line, without its comment.
    private static func read(_ line: String, into scenario: inout HostCase, line number: Int, commented: Bool) throws {
        let (word, rest) = firstWord(line)
        let (arguments, only) = try profileSuffix(rest)
        if only != nil, !commented { throw HostCaseError("@profile needs a comment giving the owner's OK") }
        // TEXT sets the field before it has the focus: LANG may follow it.
        let started = scenario.steps.contains { if case .text = $0.action { false } else { true } }
        switch word.uppercased() {
        case "NAME":
            scenario.name = try text(arguments)
        case "PROFILES":
            scenario.profiles = try profiles(arguments)
        case "LANG":
            guard !started else { throw HostCaseError("LANG is the field's starting language: before the steps") }
            scenario.language = try language(arguments)
        case "SET":
            guard !started else { throw HostCaseError("SET is a setting the field starts with: before the steps") }
            scenario.settings.append(try setting(arguments, after: scenario.settings))
        default:
            let action = try action(word.uppercased(), arguments)
            scenario.steps.append(HostStep(line: number, action: action, only: only))
            return
        }
        if only != nil { throw HostCaseError("@profile on \(word): only on a step") }
    }

    private static func action(_ word: String, _ arguments: String) throws -> HostAction {
        switch word {
        case "TEXT": return .text(try FieldMarkup(parsing: try quoted(arguments)))
        case "TYPE": return .type(try text(arguments))
        case "KEY": return .keys(try words(arguments).map(keySpec))
        case "CLICK": return .click(try click(arguments))
        case "FOCUS": return .focus(try oneOf(arguments, FocusChange.init(rawValue:), "away, back, other, otherfield, otherapp or closewindow"))
        case "SWITCH": return .switchSource(toABC: try oneOf(arguments, ["abc": true, "back": false], "abc or back"))
        case "APP": return try oneOf(arguments, ["clears": .appClears], "clears")
        case "WAIT": return .wait(try duration(arguments))
        case "EXPECT": return .expect(try expectation(arguments))
        default: throw HostCaseError("no step \(word)")
        }
    }

    private static func expectation(_ arguments: String) throws -> HostExpectation {
        let (what, rest) = firstWord(arguments)
        switch what.lowercased() {
        case "doc":
            let markup = try FieldMarkup(parsing: try quoted(rest))
            guard markup.marked == nil else { throw HostCaseError("EXPECT doc is the text without the marked part: no {..}") }
            return .doc(markup)
        case "marked":
            return .marked(rest.lowercased() == "none" ? nil : try text(rest))
        case "preedit":
            // v1.3: the panel's input line; a `|` in it (optional) says where its caret is.
            guard rest.lowercased() != "none" else { return .preedit(nil, caret: nil) }
            let markup = try FieldMarkup(parsing: try quoted(rest))
            guard markup.selection == nil, markup.marked == nil else {
                throw HostCaseError("EXPECT preedit is the panel's input line: a | for its caret at most, no [..] or {..}")
            }
            let caret = markup.caret.map { (markup.text as NSString).substring(to: $0).count }
            return .preedit(markup.text, caret: caret)
        case "panel":
            return .panel(shown: try oneOf(rest, ["shown": true, "hidden": false], "shown or hidden"))
        case "lang":
            return .language(try language(rest))
        case "context":
            let (kind, quote) = firstWord(rest)
            switch kind.lowercased() {
            case "unreadable" where quote.isEmpty: return .contextBefore(nil)
            case "before": return .contextBefore(try text(quote))
            case "after": return .contextAfter(try text(quote))
            default: throw HostCaseError("EXPECT context before \"…\", after \"…\", or unreadable")
            }
        case "fallback":
            guard rest.lowercased() == "none" else { throw HostCaseError("EXPECT fallback none") }
            return .fallbackNone
        case "switches":
            guard let count = Int(rest), count >= 0 else { throw HostCaseError("EXPECT switches takes a count") }
            return .switches(count)
        case "calls":
            return try calls(rest)
        case "nolost":
            guard rest.isEmpty else { throw HostCaseError("EXPECT nolost takes nothing") }
            return .nolost
        default:
            throw HostCaseError("no EXPECT \(what)")
        }
    }

    /// `switchKey capsLock`: a key of the config and its value (quoted for spaces), checked against the settings before it.
    private static func setting(_ written: String, after earlier: [(key: String, value: String)]) throws -> (key: String, value: String) {
        let (key, rest) = firstWord(written)
        guard !key.isEmpty, !rest.isEmpty else { throw HostCaseError("SET <configKey> <value>") }
        let value = rest.first == "\"" ? try quoted(rest) : rest
        do {
            _ = try HostScenarioSettings.config(startingIn: .english, set: earlier + [(key, value)])
        } catch let error as HostSettingError {
            throw HostCaseError("SET \(key): \(error.description)")
        }
        return (key, value)
    }

    /// `length<=1`, `substring <= 4`, `total==3`.
    private static func calls(_ written: String) throws -> HostExpectation {
        let compact = written.filter { !$0.isWhitespace }
        let name = String(compact.prefix { $0.isLetter })
        let rest = compact.dropFirst(name.count)
        guard let call = HostCall(scenarioName: name) else {
            throw HostCaseError("EXPECT calls names one of \(HostCall.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        // The longest operator first ("<=" before "<"); "=" is "==".
        let operators = HostCallBudget.Comparison.allCases.map { ($0.rawValue, $0) } + [("=", .exactly)]
        guard let (written, comparison) = operators.sorted(by: { $0.0.count > $1.0.count }).first(where: { rest.hasPrefix($0.0) }),
              let limit = Int(rest.dropFirst(written.count)), limit >= 0 else {
            throw HostCaseError("EXPECT calls \(name) needs a bound: <=, <, ==, >= or > and a count")
        }
        return .calls(call, HostCallBudget(comparison: comparison, limit: limit))
    }

    // MARK: Parts of a line

    /// The line without its comment (`#` outside quotes), and whether it had one.
    private static func splitComment(_ line: String, line number: Int) throws -> (code: String, comment: Bool) {
        var inQuotes = false, escaped = false
        for index in line.indices {
            let character = line[index]
            if escaped {
                escaped = false
            } else if character == "\\", inQuotes {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
            } else if character == "#", !inQuotes {
                return (String(line[..<index]), true)
            }
        }
        if inQuotes { throw HostCaseError("a quote not closed", line: number) }
        return (line, false)
    }

    /// The arguments, and the profiles of an `@profile …` suffix after them (one in quotes is the text's).
    private static func profileSuffix(_ rest: String) throws -> (arguments: String, only: Set<HostProfile>?) {
        var inQuotes = false, escaped = false
        for index in rest.indices {
            let character = rest[index]
            if escaped {
                escaped = false
            } else if character == "\\", inQuotes {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes, rest[index...].hasPrefix("@profile") {
                let named = rest[index...].dropFirst("@profile".count)
                guard !named.contains("@profile") else { throw HostCaseError("one @profile a line") }
                return (rest[..<index].trimmingCharacters(in: .whitespaces), Set(try profiles(String(named))))
            }
        }
        return (rest, nil)
    }

    private static func profiles(_ written: String) throws -> [HostProfile] {
        let names = words(written.replacingOccurrences(of: ",", with: " "))
        if names.map({ $0.lowercased() }) == ["all"] { return HostProfile.allCases }
        guard !names.isEmpty else { throw HostCaseError("no profile named") }
        return try names.map { name in
            guard let profile = HostProfile(rawValue: name.lowercased()) else {
                throw HostCaseError("no profile \(name): \(HostProfile.allCases.map(\.rawValue).joined(separator: ", ")) or all")
            }
            return profile
        }
    }

    private static func language(_ written: String) throws -> HostLanguage {
        try oneOf(written, HostLanguage.init(rawValue:), "chinese or english")
    }

    private static func click(_ written: String) throws -> Int? {
        let (where_, rest) = firstWord(written)
        switch where_.lowercased() {
        case "outside" where rest.isEmpty: return nil
        case "inside":
            guard let offset = Int(rest), offset >= 0 else { throw HostCaseError("CLICK inside takes a text offset") }
            return offset
        default: throw HostCaseError("CLICK inside N, or outside")
        }
    }

    /// `300ms`, `1.5s`, `300` (milliseconds).
    private static func duration(_ written: String) throws -> TimeInterval {
        let lowered = written.lowercased().filter { !$0.isWhitespace }
        let (number, perSecond) = lowered.hasSuffix("ms") ? (lowered.dropLast(2), 1000.0)
            : lowered.hasSuffix("s") ? (lowered.dropLast(), 1.0) : (Substring(lowered), 1000.0)
        guard let value = Double(number), value >= 0 else { throw HostCaseError("WAIT takes a time: 300ms, 1.5s") }
        return value / perSecond
    }

    /// A key as named: `space`, `cmd+z`, `opt+1`, `shift` (tapped alone), `capslock`, `a`, `A`.
    static func keySpec(_ written: String) throws -> KeySpec {
        let parts = written.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "+" itself: the last part empty after a "+" ("cmd++", "+").
        let base = parts.last == "" && parts.count > 1 ? "+" : parts.last ?? ""
        let held = parts.count > 1 ? Array(parts.dropLast(parts.last == "" ? 2 : 1)) : []
        let modifiers = try held.map { name in
            guard let kind = modifierKinds[name.lowercased()] else { throw HostCaseError("no modifier \(name) in \(written)") }
            return kind
        }
        if held.isEmpty, let kind = modifierKinds[base.lowercased()] { return .tap(kind) }
        if held.isEmpty, ["capslock", "caps"].contains(base.lowercased()) { return .capsLock }
        if let named = namedKeys[base.lowercased()] { return .key(named, modifiers: modifiers) }
        if base.lowercased().hasPrefix("f"), let number = Int(base.dropFirst()), (1...12).contains(number) {
            return .key(.function(number), modifiers: modifiers)
        }
        guard base.count == 1, let character = base.first else { throw HostCaseError("no key \(written)") }
        return .key(.character(character), modifiers: modifiers)
    }

    private static let modifierKinds: [String: Key.ModifierKind] = [
        "shift": .shift, "cmd": .command, "command": .command, "ctrl": .control, "control": .control,
        "opt": .option, "option": .option, "alt": .option,
    ]

    private static let namedKeys: [String: NamedKey] = [
        "space": .space, "enter": .enter, "return": .enter, "esc": .escape, "escape": .escape, "tab": .tab,
        "backspace": .backspace, "delete": .backspace, "forwarddelete": .forwardDelete, "left": .left, "right": .right,
        "up": .up, "down": .down, "home": .home, "end": .end, "pageup": .pageUp, "pagedown": .pageDown,
    ]

    // MARK: Words and strings

    private static func firstWord(_ line: String) -> (word: String, rest: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: \.isWhitespace) else { return (trimmed, "") }
        return (String(trimmed[..<space]), trimmed[space...].trimmingCharacters(in: .whitespaces))
    }

    private static func words(_ line: String) -> [String] { line.split(whereSeparator: \.isWhitespace).map(String.init) }

    private static func oneOf<T>(_ written: String, _ choices: [String: T], _ expected: String) throws -> T {
        try oneOf(written, { choices[$0] }, expected)
    }

    private static func oneOf<T>(_ written: String, _ choice: (String) -> T?, _ expected: String) throws -> T {
        guard let chosen = choice(written.lowercased()) else { throw HostCaseError("\(written.isEmpty ? "nothing" : written): \(expected)") }
        return chosen
    }

    /// The text in quotes, as written (its escapes left for `FieldMarkup`): the quotes are the first and last characters,
    /// and a quote between them is written `\"`.
    private static func quoted(_ written: String) throws -> String {
        guard written.first == "\"" else { throw HostCaseError("text in quotes: \"…\"") }
        var escaped = false
        let inside = written.dropFirst()
        for index in inside.indices {
            if escaped {
                escaped = false
            } else if inside[index] == "\\" {
                escaped = true
            } else if inside[index] == "\"" {
                guard inside.index(after: index) == inside.endIndex else { throw HostCaseError("nothing after the closing quote") }
                return String(inside[..<index])
            }
        }
        throw HostCaseError("a quote not closed")
    }

    /// Text quoted (its escapes read), or as written where it isn't.
    private static func text(_ written: String) throws -> String {
        guard written.first == "\"" else { return written }
        var result = "", escaped = false
        for character in try quoted(written) {
            if escaped {
                result.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
