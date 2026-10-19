import Foundation

/// How much each @ command is used, for the order of the command list: every run adds 1 to its
/// score, and scores halve every week, so both how often and how lately count ("frecency").
public struct CommandUsage: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var score: Double
        var last: Date
    }

    var entries: [String: Entry] = [:]
    public static let halfLife: TimeInterval = 7 * 86400

    public init() {}

    /// The command's score as of `now`.
    public func score(_ name: String, now: Date = Platform.current.clock.now) -> Double {
        guard let entry = entries[name] else { return 0 }
        return entry.score * pow(0.5, max(now.timeIntervalSince(entry.last), 0) / Self.halfLife)
    }

    /// A built-in command took a new name (`@claude` → `@agent`): its use counts under the new one, once (a score
    /// already kept under `to` stays as it is).
    public mutating func migrateRenamed(from old: String, to new: String) {
        guard let entry = entries.removeValue(forKey: old), entries[new] == nil else { return }
        entries[new] = entry
    }

    /// The command was run.
    public mutating func record(_ name: String, now: Date = Platform.current.clock.now) {
        entries[name] = Entry(score: score(name, now: now) + 1, last: now)
        // Forget the long unused (a score under 0.01: about 7 weeks after a single use).
        entries = entries.filter { score($0.key, now: now) >= 0.01 || $0.key == name }
    }
}

extension Command {
    /// The command list has room for this many: the digits 1–5 pick them.
    public static let paletteLimit = 5

    /// The commands the list shows for `query` (the letters after "@"), at most `limit`. Nothing
    /// typed: the most used, then the rest in catalog order. Letters: the command named exactly that first (`@rep`
    /// lists a command named "rep" before `@reportissue` and `@reply`), then names starting with them, then
    /// names containing them, then script extensions with a word of their title or a keyword starting with
    /// them (`ScriptCommand.searchTerms`), each by use. Every match counts for `matching`; only these are shown.
    public static func palette(_ query: String, in commands: [Command], usage: CommandUsage,
                               limit: Int = paletteLimit, now: Date = Platform.current.clock.now) -> [Command] {
        paletteIndices(query, in: commands, usage: usage, now: now).prefix(limit).map { commands[$0] }
    }

    /// `palette`, as positions in `commands`, looking only at `candidates` (positions, in catalog order) when
    /// given: what matched a shorter query this one goes on (a longer query matches no command it didn't).
    static func paletteIndices(_ query: String, in commands: [Command], candidates: [Int]? = nil, usage: CommandUsage,
                               now: Date = Platform.current.clock.now) -> [Int] {
        let query = Array(query.lowercased().utf8)
        func starts(_ text: String.UTF8View, _ prefix: [UInt8]) -> Bool { text.starts(with: prefix) }
        // Names and terms are ASCII: compared as bytes.
        func contains(_ text: String.UTF8View, _ part: [UInt8]) -> Bool {
            let bytes = Array(text)
            guard bytes.count >= part.count else { return false }
            return (0...(bytes.count - part.count)).contains { start in bytes[start..<start + part.count].elementsEqual(part) }
        }
        let ranked = (candidates ?? Array(commands.indices)).compactMap { index -> (group: Int, score: Double, index: Int)? in
            let command = commands[index]
            let group: Int
            if query.isEmpty || starts(command.name.utf8, query) {
                // The name typed in full first, whatever is used more.
                group = !query.isEmpty && command.name.utf8.count == query.count ? -1 : 0
            } else if contains(command.name.utf8, query) {
                group = 1
            } else if let script = command.script, script.searchTerms.contains(where: { starts($0.utf8, query) }) {
                group = 2
            } else {
                return nil
            }
            return (group, usage.score(command.name, now: now), index)
        }
        return ranked.sorted { ($0.group, -$0.score, $0.index) < ($1.group, -$1.score, $1.index) }.map(\.index)
    }
}
