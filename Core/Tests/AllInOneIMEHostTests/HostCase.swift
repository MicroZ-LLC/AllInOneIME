import Foundation
import AllInOneIMECore

/// A host scenario (`Tests/HostScenarios/*.hostcase`, in the host scenario contract's format: `HostCaseParser`): a text
/// field in a host that behaves as each of its profiles does, the steps a user and the app take in it, and what must
/// hold after. The same file is replayed here, through the core alone (`HostRun`), and on the Mac through its own reading
/// and anchoring code (Tests/AllInOneIMEMacTests/HostScenarios).
struct HostCase: Sendable {
    /// What it checks (`NAME`); the file's name where it has none.
    var name: String
    /// The profiles it runs against (`PROFILES`; all where it names none).
    var profiles: [HostProfile]
    /// The field's starting language (`LANG`; Chinese where it names none).
    var language: HostLanguage
    /// The config keys set before it starts (`SET <configKey> <value>`, in order: `HostScenarioSettings.applying`).
    var settings: [(key: String, value: String)] = []
    var steps: [HostStep]
}

/// The input languages a scenario's field starts in and is checked for (`LANG`, `EXPECT lang`).
enum HostLanguage: String, Sendable {
    case chinese, english
}

/// One line of a scenario: what it does, on which line, and on which profiles only (`@profile …`: an exception the
/// owner allowed; nil, every one the scenario runs against).
struct HostStep: Sendable {
    var line: Int
    var action: HostAction
    var only: Set<HostProfile>?

    func applies(to profile: HostProfile) -> Bool { only?.contains(profile) ?? true }
}

enum HostAction: Sendable, Equatable {
    /// The field's text as the app sets it (`TEXT`): what it holds, the caret, a selection, marked text.
    case text(FieldMarkup)
    /// Plain keys, one a character (`TYPE`).
    case type(String)
    /// Keys by name, with modifiers (`KEY`), in order.
    case keys([KeySpec])
    /// A click at a text offset in the field (UTF-16), or outside it (`CLICK`).
    case click(Int?)
    case focus(FocusChange)
    /// The input source switched to ABC, and back (`SWITCH`).
    case switchSource(toABC: Bool)
    /// The app emptied the field on its own (`APP clears`: a chat app's send).
    case appClears
    case wait(TimeInterval)
    case expect(HostExpectation)
}

enum FocusChange: String, Sendable {
    /// Another field of the app takes the focus; this one takes it again; another field takes the focus instead (another
    /// app's: `other`; another of the same app, which the shell tells from this one: `otherfield`); another app is
    /// brought forward; the window closes.
    case away, back, other, otherfield, otherapp, closewindow
}

/// A key as a scenario names it (`KEY`): a modifier tapped alone (`shift`: down and up), a press of Caps Lock, or a key
/// with the modifiers held for it.
enum KeySpec: Sendable, Equatable {
    case tap(Key.ModifierKind)
    case capsLock
    case key(NamedKey, modifiers: [Key.ModifierKind])
}

/// A key that isn't a modifier: by name (Return, ⌫ …) or by the character it types on a U.S. keyboard.
enum NamedKey: Sendable, Equatable {
    case space, enter, escape, tab, backspace, forwardDelete, left, right, up, down, home, end, pageUp, pageDown
    case function(Int)
    case character(Character)
}

/// What a scenario checks (`EXPECT`).
enum HostExpectation: Sendable, Equatable {
    /// The field's text, no marked part (a caret or a selection in it checked too, where the markup has one).
    case doc(FieldMarkup)
    /// The marked text the field shows; nil: none.
    case marked(String?)
    /// The candidate panel's input line, the composition as the panel shows it (contract v1.3: pinyin, a command draft
    /// "improve › ok"); its prompt and text together. nil: none (`EXPECT preedit none`). `caret` (in characters), where
    /// the scenario wrote a `|`: where the line's caret must be.
    case preedit(String?, caret: Int?)
    case panel(shown: Bool)
    case language(HostLanguage)
    /// What autocomplete or a command would read before the caret; nil: nothing (`EXPECT context unreadable`).
    case contextBefore(String?)
    /// What autocomplete or a command would read after the caret (`EXPECT context after`).
    case contextAfter(String)
    /// What autocomplete would use in place of the field's text where the field tells none (what was typed since the
    /// focus) is nothing (`EXPECT fallback none`): forgotten, as after a click.
    case fallbackNone
    /// The input language changed this many times since the last `EXPECT switches` (or the start).
    case switches(Int)
    /// Each key since the last `EXPECT calls` (or the start) made at most / exactly … calls of the host's `call`.
    case calls(HostCall, HostCallBudget)
    /// Every character committed is in the document as many times as it was committed: none lost, none doubled.
    case nolost
}

/// A call a shell makes of the host's text-input API (NSTextInputClient's on the Mac), counted per key; `total` is all of
/// them.
enum HostCall: String, Sendable, CaseIterable {
    case length, selectedRange, markedRange, substring, total

    /// The call a scenario names (any case; `attributedSubstring` is `substring`, `all` is `total`).
    init?(scenarioName name: String) {
        let lowered = name.lowercased()
        let aliases = ["attributedsubstring": Self.substring, "all": .total, "calls": .total]
        guard let call = Self.allCases.first(where: { $0.rawValue.lowercased() == lowered }) ?? aliases[lowered] else { return nil }
        self = call
    }
}

/// A bound on a count: `<=`, `<`, `==` (`=`), `>=`, `>`.
struct HostCallBudget: Sendable, Equatable, CustomStringConvertible {
    enum Comparison: String, Sendable, CaseIterable {
        case atMost = "<=", atLeast = ">=", exactly = "==", less = "<", more = ">"
    }

    var comparison: Comparison
    var limit: Int

    func allows(_ count: Int) -> Bool {
        switch comparison {
        case .atMost: count <= limit
        case .atLeast: count >= limit
        case .exactly: count == limit
        case .less: count < limit
        case .more: count > limit
        }
    }

    var description: String { comparison.rawValue + String(limit) }
}

/// A field's text as a scenario writes it: `|` the caret, `[..]` a selection, `{..}` marked text; `\` before any of these
/// (or before `\` or `"`) is that character itself, `\n` a line break, `\t` a tab.
struct FieldMarkup: Sendable, Equatable {
    /// The text, without the marked part.
    var text: String
    /// Where the caret is (UTF-16; nil: not marked, the end where the field is set from it).
    var caret: Int?
    var selection: Range<Int>?
    /// The marked text and where it starts in `text` (UTF-16).
    var marked: (text: String, at: Int)?

    static func == (a: FieldMarkup, b: FieldMarkup) -> Bool {
        a.text == b.text && a.caret == b.caret && a.selection == b.selection && a.marked?.text == b.marked?.text
            && a.marked?.at == b.marked?.at
    }

    /// `written` read as markup.
    init(parsing written: String) throws {
        var scanner = MarkupScanner()
        var escaped = false
        for character in written {
            if escaped {
                scanner.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                escaped = false
                continue
            }
            switch character {
            case "\\": escaped = true
            case "|": try scanner.caret()
            case "[": try scanner.open(.selection)
            case "]": try scanner.close(.selection)
            case "{": try scanner.open(.marked)
            case "}": try scanner.close(.marked)
            default: scanner.append(character)
            }
        }
        guard !escaped else { throw HostCaseError("a \\ at the end of the text") }
        self = try scanner.finish()
    }

    init(text: String, caret: Int? = nil, selection: Range<Int>? = nil, marked: (text: String, at: Int)? = nil) {
        (self.text, self.caret, self.selection, self.marked) = (text, caret, selection, marked)
    }
}

/// Reads `FieldMarkup`'s marks as they come.
private struct MarkupScanner {
    enum Span { case selection, marked }

    var text = ""
    var markedText = ""
    var caretAt: Int?
    var open: (span: Span, at: Int)?
    var selection: Range<Int>?
    var marked: (text: String, at: Int)?
    var length: Int { (text as NSString).length }

    mutating func append(_ character: Character) {
        if open?.span == .marked { markedText.append(character) } else { text.append(character) }
    }

    mutating func caret() throws {
        guard caretAt == nil, open == nil else { throw HostCaseError("a second caret, or one inside [..] or {..}") }
        caretAt = length
    }

    mutating func open(_ span: Span) throws {
        let used = span == .selection ? selection != nil : marked != nil
        guard open == nil, !used else {
            throw HostCaseError("[..] and {..} once each, never one inside another")
        }
        open = (span, length)
    }

    mutating func close(_ span: Span) throws {
        guard let opened = open, opened.span == span else { throw HostCaseError("a \(span == .selection ? "]" : "}") with nothing open") }
        open = nil
        if span == .selection { selection = opened.at..<length } else { marked = (markedText, opened.at) }
    }

    func finish() throws -> FieldMarkup {
        guard open == nil else { throw HostCaseError("a [ or { not closed") }
        guard selection == nil || marked == nil else { throw HostCaseError("a selection and marked text at once") }
        guard caretAt == nil || (selection == nil && marked == nil) else {
            throw HostCaseError("a caret with a selection or marked text (they say where the caret is)")
        }
        return FieldMarkup(text: text, caret: caretAt, selection: selection, marked: marked)
    }
}

/// A scenario that can't be read, and why.
struct HostCaseError: Error, CustomStringConvertible, Equatable {
    var line: Int?
    var message: String

    init(_ message: String, line: Int? = nil) {
        (self.message, self.line) = (message, line)
    }

    var description: String { line.map { "line \($0): \(message)" } ?? message }
}
