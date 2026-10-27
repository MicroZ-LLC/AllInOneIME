import Foundation

/// Which status lines (`ScriptCommand.status`) run now: those the command list shows whose value is older than
/// their refresh time, no more than `maxRunning` at once. One that finishes, failed or not, frees its place for
/// the next due one (`finished`). The caller runs them and keeps this up to date. Not thread-safe (main thread).
public struct StatusSchedule: Sendable {
    public static let maxRunning = 2

    private var values: [String: (text: String?, at: Date)] = [:]
    private var running: Set<String> = []

    public init() {}

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
