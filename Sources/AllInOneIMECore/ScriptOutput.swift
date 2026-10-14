import Foundation

/// What a script extension printed, as the panel uses it (docs/extensions.md, "Output"): plain text, a result
/// with a summary and its detail (`{"summary": "…", "detail": "…"}`), or a list in Alfred's Script Filter JSON
/// (`{"items": […], "rerun": 2}`).
public enum ScriptOutput: Hashable, Sendable {
    case text(String)
    case summary(String, detail: String?)
    case list(ScriptList)

    /// `text` (cleaned, `CommandRunner.cleanOutput`) as output: a JSON object with `items` is a list, one with
    /// `summary` a result; anything else is text. A `list` command's text that isn't a list stays text (the
    /// panel says it's not one).
    public static func parse(_ text: String) -> ScriptOutput {
        guard text.hasPrefix("{"), let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .text(text) }
        if let items = object["items"] as? [[String: Any]] {
            return .list(ScriptList(items: items.compactMap(ScriptItem.init(json:)).prefix(ScriptList.maxItems).map { $0 },
                                    rerun: (object["rerun"] as? NSNumber)?.doubleValue))
        }
        if let summary = object["summary"].map({ "\($0)" }) {
            return .summary(summary, detail: object["detail"].map { "\($0)" })
        }
        return .text(text)
    }

    /// Its lines with words (blank ones left out).
    public var lines: [String] {
        switch self {
        case let .text(text):
            return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case let .summary(summary, detail): return [summary] + (detail.map { [$0] } ?? [])
        case let .list(list): return list.items.map(\.title)
        }
    }

    public var isEmpty: Bool {
        switch self {
        case let .text(text): return text.isEmpty
        case let .summary(summary, _): return summary.isEmpty
        case let .list(list): return list.items.isEmpty
        }
    }

    /// What a notice or a notification says about it: the summary, else the last line.
    public var headline: String? {
        if case let .summary(summary, _) = self { return summary.isEmpty ? nil : summary }
        if case .list = self { return nil }
        return lines.last
    }

    /// What a background command's notification says under its title: the summary and its detail, else the
    /// last line.
    public var notificationBody: String? {
        if case let .summary(summary, detail) = self, let detail, !detail.isEmpty { return summary + "\n" + detail }
        return headline
    }

    /// What ⌘C copies of it all: the text, or the summary and its detail.
    public var copyText: String {
        switch self {
        case let .text(text): return text
        case let .summary(summary, detail): return [summary, detail].compactMap { $0 }.joined(separator: "\n")
        case let .list(list): return list.items.map(\.title).joined(separator: "\n")
        }
    }
}

/// A Script Filter list: the rows to pick from, and when to run again while it's shown.
public struct ScriptList: Hashable, Sendable {
    public var items: [ScriptItem]
    /// Seconds after which it runs again while it's shown (Alfred's `rerun`, 0.1–5 there; here at least 0.5).
    public var rerun: Double?

    public init(items: [ScriptItem], rerun: Double? = nil) {
        self.items = items
        self.rerun = rerun.map { max($0, Self.minimumRerun) }
    }

    public static let maxItems = 50
    public static let minimumRerun: Double = 0.5
}

/// One row of a list: `{"title": …, "subtitle": …, "arg": …, "action": "open", "valid": true, "text": {"copy": …}}`.
public struct ScriptItem: Hashable, Sendable {
    /// What picking it does (our addition to Alfred's format).
    public enum Action: String, Hashable, Sendable {
        /// Inserts its `arg` (or title).
        case insert
        /// Opens its `arg`: a web address, or a file or folder.
        case open
        /// Copies `text.copy` (or its `arg`, or title).
        case copy
        /// Runs the command again with its `arg` as $1 (`ALLINONEIME_ACTION=run`): a second step.
        case run
    }

    public var title: String
    public var subtitle: String?
    public var arg: String?
    public var action: Action
    /// False: a row of information only.
    public var valid: Bool
    public var copy: String?
    /// What Tab puts after the command (Alfred's `autocomplete`).
    public var autocomplete: String?

    public init(title: String, subtitle: String? = nil, arg: String? = nil, action: Action? = nil, valid: Bool = true,
                copy: String? = nil, autocomplete: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.arg = arg
        self.action = action ?? Self.defaultAction(for: arg)
        self.valid = valid
        self.copy = copy
        self.autocomplete = autocomplete
    }

    /// An item of Alfred's JSON; nil without a title. `arg` may be a string or a list (its first).
    init?(json: [String: Any]) {
        guard let title = json["title"].map({ "\($0)" }), !title.isEmpty else { return nil }
        let arg = (json["arg"] as? [Any])?.first.map { "\($0)" } ?? json["arg"].map { "\($0)" }
        let text = json["text"] as? [String: Any]
        self.init(title: title, subtitle: json["subtitle"].map { "\($0)" }, arg: arg,
                  action: (json["action"] as? String).flatMap(Action.init(rawValue:)),
                  valid: (json["valid"] as? Bool) ?? true, copy: text?["copy"].map { "\($0)" },
                  autocomplete: json["autocomplete"].map { "\($0)" })
    }

    /// `open` for a web address or a path, else `insert`.
    static func defaultAction(for arg: String?) -> Action {
        guard let arg else { return .insert }
        let lower = arg.lowercased()
        let opens = lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://")
            || arg.hasPrefix("/") || arg.hasPrefix("~/")
        return opens ? .open : .insert
    }

    /// What `insert` puts in: its `arg`, else its title.
    public var insertText: String { arg ?? title }

    /// What `copy` and ⌘C take: `text.copy`, its `arg`, or its title.
    public var copyText: String { copy ?? arg ?? title }

    /// What `open` may open: an http(s) address; a `file://` address, an absolute path or a "~/" one that's there.
    /// Not a file Terminal would run (`.command`, `.tool`, `.terminal`), nor any other scheme or a relative path.
    public var openURL: URL? {
        guard let target = openTarget else { return nil }
        let lower = target.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: target), url.host != nil else { return nil }
            return url
        }
        guard target.hasPrefix("/"), FileManager.default.fileExists(atPath: target),
              !["command", "tool", "terminal"].contains((target as NSString).pathExtension.lowercased()) else { return nil }
        return URL(fileURLWithPath: target)
    }

    /// What `open` opens: a web address as it is, a path with "~" expanded.
    public var openTarget: String? {
        guard let arg else { return nil }
        if arg.hasPrefix("~/") { return (arg as NSString).expandingTildeInPath }
        if arg.lowercased().hasPrefix("file://") { return URL(string: arg)?.path ?? arg }
        return arg
    }
}
