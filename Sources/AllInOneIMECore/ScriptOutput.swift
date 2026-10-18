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

    /// `open` for a web address or a path (not another computer's share, `namesShare`), else `insert`.
    static func defaultAction(for arg: String?) -> Action {
        guard let arg else { return .insert }
        let lower = arg.lowercased()
        let opens = lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://")
            || (CorePaths.isAbsolute(arg) && !namesShare(arg)) || arg.hasPrefix("~/")
        return opens ? .open : .insert
    }

    /// Whether `path` may be on another computer: on Windows one that starts with two separators, a share
    /// ("\\server\share\…", "//server/…"; the "\\?\…" and "\\.\…" forms with it). It is never opened, nor even looked
    /// at: reaching a share hands that computer the user's Windows sign-in (NTLM). Elsewhere "//x" is this computer's
    /// "/x", opened as before.
    static func namesShare(_ path: String) -> Bool {
        #if os(Windows)
        let start = Array(path.prefix(2))
        return start.count == 2 && start.allSatisfy(CorePaths.isSeparator)
        #else
        return false
        #endif
    }

    /// What `insert` puts in: its `arg`, else its title.
    public var insertText: String { arg ?? title }

    /// What `copy` and ⌘C take: `text.copy`, its `arg`, or its title.
    public var copyText: String { copy ?? arg ?? title }

    /// What `open` may open: an http(s) address; a folder (an app too); a file given by a `file://` address, an
    /// absolute path or a "~/" one, that's there and that opening wouldn't run: not an executable file (the
    /// system's programs, a `runme` with no extension) nor a kind of script (`runnableExtensions`). Nothing else:
    /// no other scheme, no relative path, no share on another computer (`namesShare`, not looked for).
    public var openURL: URL? {
        guard let target = openTarget else { return nil }
        let lower = target.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: target), url.host != nil else { return nil }
            return url
        }
        var folder: ObjCBool = false
        guard CorePaths.isAbsolute(target), !Self.namesShare(target), FileManager.default.fileExists(atPath: target, isDirectory: &folder)
        else { return nil }
        // A folder has the executable bit to be listed; a bundle like a .workflow is a folder too.
        if Self.runnableExtensions.contains((target as NSString).pathExtension.lowercased()) { return nil }
        #if os(Windows)
        // No executable bit: a program is a file Windows can run (an .exe, .com, …).
        if !folder.boolValue, FileManager.default.isExecutableFile(atPath: target) { return nil }
        #else
        if !folder.boolValue, access(target, X_OK) == 0 { return nil }
        #endif
        return URL(fileURLWithPath: target)
    }

    /// The kinds of file that opening runs: scripts and programs Terminal or an interpreter would run (on Windows,
    /// also what Explorer runs: programs, batch files, Windows Script Host's and PowerShell's scripts, installers,
    /// shortcuts).
    public static let runnableExtensions: Set<String> = {
        var kinds: Set<String> = [
            "sh", "bash", "zsh", "csh", "tcsh", "ksh", "fish", "command", "tool", "terminal",
            "py", "pyw", "rb", "pl", "php", "lua", "tcl", "js", "jar", "applescript", "scpt", "workflow", "action",
        ]
        #if os(Windows)
        kinds.formUnion(["exe", "com", "bat", "cmd", "scr", "cpl", "msc", "pif", "lnk", "url", "appref-ms", "ps1", "psm1",
                         "vbs", "vbe", "jse", "wsf", "wsh", "hta", "msi", "msp", "reg", "inf"])
        #endif
        return kinds
    }()

    /// What `open` opens: a web address as it is, a path with "~" expanded.
    public var openTarget: String? {
        guard let arg else { return nil }
        if arg.hasPrefix("~/") { return (arg as NSString).expandingTildeInPath }
        if arg.lowercased().hasPrefix("file://") { return URL(string: arg)?.path ?? arg }
        return arg
    }
}
