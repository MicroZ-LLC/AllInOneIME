import Foundation

/// A snippet's text (`CustomCommand.text`, a bundle's `snippets`), read into what it inserts: plain text, and the
/// placeholders filled in when it goes in.
///
/// - `{input}`: the whole text typed after the name.
/// - `{label?}`: a blank, filled from what is typed after the name, split on "," or "，" (`ScriptCommand.split`), in the
///   order the blanks first appear; the same label twice is one blank.
/// - `{clipboard}`, `{selection}`: the clipboard's text, the text selected when the draft started ("" without one).
/// - `{date}`, `{time}`: `yyyy-MM-dd` and `HH:mm`; `{date:FMT}` and `{time:FMT}` with a Unicode date pattern, in the
///   interface language's locale.
/// - `{cursor}`: where the caret goes once it's in (at most one).
///
/// `{{` writes "{", and the `}}` that closes it writes "}" (`{{input}}` is "{input}"); any other `}}` and `{…}` stay as
/// they are, so JSON or code in a snippet doesn't break (`{"a":{"b":1}}`). Line breaks are kept (`\r\n` as `\n`); the
/// text is plain, the same on every platform.
public struct SnippetTemplate: Hashable, Sendable {
    public enum Part: Hashable, Sendable {
        case text(String)
        case input
        /// The blank `fieldLabels[index]`.
        case field(Int)
        case clipboard
        case selection
        /// A date or time with this pattern (nil: `yyyy-MM-dd` for a date, `HH:mm` for a time).
        case date(String?)
        case time(String?)
        case cursor
    }

    /// What it needs when it goes in.
    public enum Need: Hashable, Sendable {
        /// `{input}`: text typed after the name.
        case input
        /// Blanks to fill (`fieldLabels`).
        case fields
        case clipboard
        case selection
    }

    public var parts: [Part]
    public var needs: Set<Need>
    /// The blanks' labels, in the order they first appear, each once.
    public var fieldLabels: [String]

    /// How many `{cursor}` it has (a valid snippet has at most one).
    public var cursorCount: Int { parts.filter { $0 == .cursor }.count }

    /// It can go inside another command's text (`@question 总结一下 @zoom`): nothing from the clipboard or the selection,
    /// no blanks to fill.
    public var canBeInner: Bool { needs.isDisjoint(with: [.clipboard, .selection, .fields]) }

    /// Something has to be typed after its name: `{input}` or blanks. Without, the action key picking it in the
    /// command list inserts it at once.
    public var needsTyping: Bool { needs.contains(.input) || needs.contains(.fields) }

    public static let defaultDate = "yyyy-MM-dd"
    public static let defaultTime = "HH:mm"

    /// `text` read into its parts (never fails: what isn't a placeholder is text).
    public static func parse(_ text: String) -> SnippetTemplate {
        var parts: [Part] = []
        var needs = Set<Need>()
        var labels: [String] = []
        var literal = ""
        func flush() {
            if !literal.isEmpty { parts.append(.text(literal)) }
            literal = ""
        }
        func add(_ part: Part) {
            flush()
            parts.append(part)
        }
        let chars = Array(text)
        // The `{{` written so far that no `}}` has closed yet: only such a `}}` is an escape.
        var open = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "{", i + 1 < chars.count, chars[i + 1] == "{" {
                literal.append("{")
                open += 1
                i += 2
                continue
            }
            if c == "}", open > 0, i + 1 < chars.count, chars[i + 1] == "}" {
                literal.append("}")
                open -= 1
                i += 2
                continue
            }
            if c == "{", let close = chars[(i + 1)...].firstIndex(where: { $0 == "}" || $0 == "{" || $0.isNewline }),
               chars[close] == "}", let part = placeholder(String(chars[(i + 1)..<close]), labels: &labels) {
                add(part)
                switch part {
                case .input: needs.insert(.input)
                case .field: needs.insert(.fields)
                case .clipboard: needs.insert(.clipboard)
                case .selection: needs.insert(.selection)
                case .text, .date, .time, .cursor: break
                }
                i = close + 1
                continue
            }
            literal.append(c)
            i += 1
        }
        flush()
        return SnippetTemplate(parts: parts, needs: needs, fieldLabels: labels)
    }

    /// The placeholder written between braces, or nil when it is none (it stays as text).
    private static func placeholder(_ token: String, labels: inout [String]) -> Part? {
        switch token {
        case "input": return .input
        case "clipboard": return .clipboard
        case "selection": return .selection
        case "date": return .date(nil)
        case "time": return .time(nil)
        case "cursor": return .cursor
        default: break
        }
        for (prefix, make) in [("date:", Part.date), ("time:", Part.time)] where token.hasPrefix(prefix) {
            let pattern = String(token.dropFirst(prefix.count))
            return pattern.trimmingCharacters(in: .whitespaces).isEmpty ? nil : make(pattern)
        }
        guard token.hasSuffix("?") else { return nil }
        let label = token.dropLast().trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !label.contains("?") else { return nil }
        if let index = labels.firstIndex(of: label) { return .field(index) }
        labels.append(label)
        return .field(labels.count - 1)
    }

    /// The text to insert, and where `{cursor}` is in it: UTF-16 units back from its end (nil without one). Blanks
    /// without a value are empty.
    public func render(_ values: SnippetValues) -> SnippetRender {
        // The text before `{cursor}` and after it (all of it in `before` without one).
        var before = ""
        var after: String?
        // One formatter for each pattern (a long snippet may have many dates).
        var formatted: [String: String] = [:]
        func date(_ pattern: String?, fallback: String) -> String {
            let key = pattern.map { "+" + $0 } ?? fallback
            if let known = formatted[key] { return known }
            let text = Self.format(values, pattern: pattern ?? fallback, custom: pattern != nil)
            formatted[key] = text
            return text
        }
        func append(_ piece: String) {
            if after != nil { after! += piece } else { before += piece }
        }
        for part in parts {
            switch part {
            case let .text(literal): append(literal)
            case .input: append(values.input)
            case let .field(index): append(index < values.fields.count ? values.fields[index] : "")
            case .clipboard: append(values.clipboard)
            case .selection: append(values.selection)
            case let .date(pattern): append(date(pattern, fallback: Self.defaultDate))
            case let .time(pattern): append(date(pattern, fallback: Self.defaultTime))
            case .cursor: if after == nil { after = "" }
            }
        }
        // `\r\n` as `\n` over the whole text, a pair split between a placeholder's value and the text around it too.
        // A pair split by `{cursor}` becomes the "\n" after it: the caret goes where the "\r" was.
        func lines(_ text: String) -> String { text.replacingOccurrences(of: "\r\n", with: "\n") }
        let text = lines(before + (after ?? ""))
        return SnippetRender(text: text, caretBack: after.map { min(lines($0).utf16.count, text.utf16.count) })
    }

    /// `values.now` with `pattern`, in `values.timeZone`: the default patterns with fixed digits (POSIX, Gregorian), a
    /// pattern of the user's in `values.locale`.
    private static func format(_ values: SnippetValues, pattern: String, custom: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = custom ? values.locale : Locale(identifier: "en_US_POSIX")
        if !custom { formatter.calendar = Calendar(identifier: .gregorian) }
        formatter.timeZone = values.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: values.now)
    }

    /// The text with the blanks typed so far and the rest as written (`{day?}`), for the panel while it's typed: the
    /// clipboard isn't read for it (that may ask the user), so `{clipboard}` shows as written too.
    public func preview(_ values: SnippetValues) -> String {
        let shown = SnippetTemplate(parts: parts.map { part in
            switch part {
            case .clipboard: return .text("{clipboard}")
            case let .field(index) where index >= values.fields.count || values.fields[index].isEmpty:
                return .text("{" + fieldLabels[index] + "?}")
            default: return part
            }
        }, needs: needs, fieldLabels: fieldLabels)
        return shown.render(values).text
    }
}

/// What a snippet's placeholders are filled with (`SnippetTemplate.render`).
public struct SnippetValues: Equatable, Sendable {
    /// `{input}`: the text typed after the name.
    public var input: String
    /// The blanks, in the order they first appear (`SnippetTemplate.fieldLabels`).
    public var fields: [String]
    public var clipboard: String
    public var selection: String
    /// The clock `{date}` and `{time}` read, in `timeZone`; `locale` for a pattern of the user's (`{date:FMT}`).
    public var now: Date
    public var timeZone: TimeZone
    public var locale: Locale

    public init(input: String = "", fields: [String] = [], clipboard: String = "", selection: String = "", now: Date = Date(),
                timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = Locale(identifier: "en_US_POSIX")) {
        self.input = input
        self.fields = fields
        self.clipboard = clipboard
        self.selection = selection
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
    }
}

/// A snippet rendered: the text to insert, and how far back from its end the caret goes (`{cursor}`), in UTF-16 units.
public struct SnippetRender: Equatable, Sendable {
    public var text: String
    public var caretBack: Int?

    public init(text: String, caretBack: Int? = nil) {
        self.text = text
        self.caretBack = caretBack
    }
}

extension SnippetTemplate {
    /// `text` with the snippets written inside it (`@zoom`, `@meet「周五 3点」`) replaced by what they insert, before
    /// the text is sent anywhere: the ones that can be used there (`canBeInner`), as `CommandPlan` finds them; their
    /// `{cursor}` is dropped, and `values.input` is each one's argument. The composer plans a text once, with the other
    /// commands in it (`CommandPlan.fillingSnippets`).
    public static func expandInner(_ text: String, commands: [Command], values: SnippetValues) -> String {
        let snippets = commands.filter { $0.kind == .snippet }
        guard !snippets.isEmpty, text.contains("@") else { return text }
        return CommandPlan.make(text, commands: snippets).fillingSnippets(values).plan.input(outputs: [])
    }
}

extension CommandPlan {
    /// The plan with its snippets put in (`Command.Kind.snippet`; `values.input` is each one's argument, its `{cursor}`
    /// dropped), and the snippets used, in order. What a snippet inserts is text from then on: it is never read for
    /// commands again, so an "@" in it (an address in a signature) neither runs a command nor keeps one from running.
    public func fillingSnippets(_ values: SnippetValues) -> (plan: CommandPlan, used: [Command]) {
        var parts: [Part] = []
        var steps: [Inner] = []
        var used: [Command] = []
        func text(_ piece: String) {
            guard !piece.isEmpty else { return }
            if case let .text(last)? = parts.last { parts[parts.count - 1] = .text(last + piece) } else { parts.append(.text(piece)) }
        }
        for part in self.parts {
            switch part {
            case let .text(piece): text(piece)
            case let .inner(index):
                guard index < inner.count else { continue }
                let step = inner[index]
                if step.command.kind == .snippet {
                    var filled = values
                    filled.input = step.argument
                    text(step.command.snippet?.render(filled).text ?? "")
                    used.append(step.command)
                } else {
                    parts.append(.inner(steps.count))
                    steps.append(step)
                }
            }
        }
        return (CommandPlan(parts: parts, inner: steps), used)
    }
}
