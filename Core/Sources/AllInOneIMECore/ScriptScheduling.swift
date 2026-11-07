import Foundation

/// Which status lines (`ScriptCommand.status`) run now: those the command list shows whose value is older than
/// their refresh time, no more than `maxRunning` at once. One that finishes, failed or not, frees its place for
/// the next due one (`finished`). The caller runs them and keeps this up to date. Not thread-safe (main thread).
public struct StatusSchedule: Sendable {
    public static let maxRunning = 2

    private var values: [String: (text: String?, at: Date)] = [:]
    private var running: Set<String> = []

    public init() {}

    /// With the values `kept` from an earlier launch (`StatusFile`): shown until they're refreshed, due as their refresh
    /// time says.
    public init(kept: [String: Kept]) {
        values = kept.mapValues { ($0.text, $0.at) }
    }

    /// The values `kept` from an earlier launch, read after this one started (`StatusFile`, off the main thread): those of
    /// the commands this launch has no value of yet.
    public mutating func adopt(_ kept: [String: Kept]) {
        for (id, value) in kept where values[id] == nil { values[id] = (value.text, value.at) }
    }

    /// A status line's value and when it was had: what is kept for the next launch.
    public struct Kept: Codable, Equatable, Sendable {
        public var text: String
        public var at: Date

        public init(text: String, at: Date) {
            self.text = text
            self.at = at
        }
    }

    /// The values had so far, the newest `StatusFile.limit`, to keep for the next launch.
    public var kept: [String: Kept] {
        let had = values.compactMap { id, value in value.text.map { (id, Kept(text: $0, at: value.at)) } }
        return Dictionary(uniqueKeysWithValues: had.sorted { $0.1.at > $1.1.at }.prefix(StatusFile.limit).map { $0 })
    }

    /// The last status line of the command with `id`.
    public func text(for id: String) -> String? { values[id]?.text ?? nil }

    /// Of `shown`, those to run now (marked running): due, not running, as many as there's room for.
    public mutating func due(_ shown: [ScriptCommand], now: Date = Platform.current.clock.now) -> [ScriptCommand] {
        var start: [ScriptCommand] = []
        for command in shown {
            guard running.count < Self.maxRunning else { break }
            guard let status = command.status, !running.contains(command.id) else { continue }
            if let value = values[command.id], now.timeIntervalSince(value.at) < status.refresh { continue }
            running.insert(command.id)
            start.append(command)
        }
        return start
    }

    /// A status run ended with `line` (nil: it failed, and the value before stays until its next refresh).
    /// True when what's shown changed.
    @discardableResult
    public mutating func finished(_ id: String, line: String?, now: Date = Platform.current.clock.now) -> Bool {
        running.remove(id)
        let old = values[id]?.text ?? nil
        values[id] = (line ?? old, now)
        return (line ?? old) != old
    }
}

/// The status lines' last values kept across launches (`StatusSchedule.kept`), so the command list shows them at once
/// after a launch, as it does within one, until they're refreshed: one file among the caches (`CorePaths.cacheDir`),
/// readable by the user only, written whole after each run that changed a value. A file that can't be read is none.
public struct StatusFile: Sendable {
    /// The app's own.
    public static let shared = StatusFile(url: CorePaths.cacheDir.appendingPathComponent("script-statuses.json"))
    /// The most values kept: the newest.
    public static let limit = 200

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() -> [String: StatusSchedule.Kept] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: url), let kept = try? decoder.decode([String: StatusSchedule.Kept].self, from: data)
        else { return [:] }
        return kept
    }

    /// `kept` written in place of what the file had (none: the file deleted). A cache: nothing when it can't be written.
    public func write(_ kept: [String: StatusSchedule.Kept]) {
        guard !kept.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(kept) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Platform.current.files.writePrivate(data, to: url)
    }
}

/// The rule for runs in the background (`background`, or a `show` whose field was left): at most `limit` at
/// once, and one command not twice.
public enum BackgroundRuns {
    public static let limit = 4

    /// Whether the command with `id` may go to the background while `running` (the ids of those running there) are.
    public static func admits(_ id: String, running: [String], limit: Int = limit) -> Bool {
        running.count < limit && !running.contains(id)
    }
}

/// The command list for the settings, built again only when what it's made of changed (the custom commands,
/// the plugins, the extensions' index generation, what's turned off, what's taken out of the list), not on each key.
public struct CatalogCache: Sendable {
    struct Key: Equatable, Sendable {
        var custom: [CustomCommand]
        var plugins: [InstalledPlugin]
        var generation: Int
        var disabled: [String]
        var hidden: [String]
    }

    private var key: Key?
    private var commands: [Command] = []

    public init() {}

    /// The catalog (`Command.catalog`, less `hidden`: `Config.hiddenFromCommandList`), and whether it's another than last
    /// time.
    public mutating func catalog(_ custom: [CustomCommand], plugins: [InstalledPlugin], index: ExtensionIndex,
                                 disabled: [String], hidden: [String] = []) -> (commands: [Command], changed: Bool) {
        let new = Key(custom: custom, plugins: plugins, generation: index.generation, disabled: disabled, hidden: hidden)
        guard new != key else { return (commands, false) }
        key = new
        commands = Command.catalog(custom, plugins: plugins, scripts: index.enabled(disabled), snippets: index.enabledSnippets(disabled),
                                   hidden: hidden)
        return (commands, true)
    }
}
