import Crypto
import Foundation

/// This week's stats (0.7.4): how much AllInOneIME was used on this device, per local day, for Settings → This Week, the
/// menu bar panel's row, `@stats` and the picture a user can share. Only counts are kept:
///   - each command run, by its id (its name in the command list), where it comes from (`CommandSource`) and whether it
///     sent a request to an AI provider; one @'s rows count as the command they ran;
///   - the apps it was used in, as salted hashes of their bundle ids (`salt`, random, kept with the counts): the page
///     shows how many, never which;
///   - the pastes from clipboard history;
///   - how many characters the user typed through the input method (`recordTypedCharacters`): one number a day.
/// Never what was typed, a command's text, what was pasted, or a time finer than the day. The last `weeksKept` calendar
/// weeks (Monday to Sunday, in the calendar's time zone) are kept; older days are dropped as new ones are counted. The
/// shell keeps it in a file of its own on the device (`serializedData`, `restore`), never synced or sent; a record
/// takes a lock and tells `changed`, nothing more, so no key waits for a file.
public final class WeekStats: @unchecked Sendable {
    /// Where a command comes from: the user's own (`Config.customCommands`), AllInOneIME's, or a plugin's (plugins,
    /// script extensions and the snippets of extension bundles).
    public enum CommandSource: String, Codable, Sendable, CaseIterable {
        case own, builtIn, plugin

        /// `command`'s: a plugin first (a prompt plugin has a definition too), an extension, the user's own, else built in.
        public init(_ command: Command) {
            if command.plugin != nil || command.script != nil || command.bundle != nil {
                self = .plugin
            } else if command.custom != nil {
                self = .own
            } else {
                self = .builtIn
            }
        }
    }

    /// The calendar week shown: this one, so far, or the one before it, whole.
    public enum Week: Sendable {
        case current, previous
    }

    /// The calendar weeks kept, this one included.
    public static let weeksKept = 8

    /// Monday to Sunday in the user's time zone, as it is when asked (a trip changes the days that follow).
    public static func defaultCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    private let now: () -> Date
    private let calendar: Calendar
    private let record: Locked<Record>
    private let listener = Locked<Listener?>(initialState: nil)

    /// `now` and `calendar` say which day it is (a test's, the system's by default); `salt` is what the bundle ids are
    /// hashed with (nil: a random one, kept with the counts; `restore` takes the kept one).
    public init(now: @escaping () -> Date = { Platform.current.clock.now }, calendar: Calendar = WeekStats.defaultCalendar(),
                salt: Data? = nil) {
        self.now = now
        var calendar = calendar
        calendar.firstWeekday = 2
        self.calendar = calendar
        record = Locked(initialState: Record(salt: salt ?? Self.randomSalt()))
    }

    /// Told after each change (a record, a restore, a clear), on the thread that made it: the shell writes the file
    /// soon after, off the key's thread.
    public var changed: (@Sendable () -> Void)? {
        get { listener.withLock { $0?.changed } }
        set { listener.withLock { $0 = newValue.map(Listener.init) } }
    }

    // MARK: - Counting

    /// A command ran: `id` its name, `bundleID` the app it ran in (nil: unknown), `usedAI` whether it sent a request
    /// to an AI provider.
    public func recordCommand(id: String, source: CommandSource, bundleID: String?, usedAI: Bool) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let today = day(of: now())
        record.withLock { record in
            prune(&record, today: today)
            var day = record.days[today.key] ?? Day()
            var runs = day.commands[id] ?? Runs(source: source)
            runs.source = source
            runs.runs += 1
            if usedAI { runs.ai += 1 }
            day.commands[id] = runs
            if let hash = appHash(bundleID, salt: record.salt), !day.apps.contains(hash) {
                day.apps.append(hash)
                day.apps.sort()
            }
            record.days[today.key] = day
            if record.since == nil { record.since = today.key }
        }
        tell()
    }

    /// Something was pasted from clipboard history.
    public func recordClipboardPaste() {
        let today = day(of: now())
        record.withLock { record in
            prune(&record, today: today)
            record.days[today.key, default: Day()].clipboardPastes += 1
            if record.since == nil { record.since = today.key }
        }
        tell()
    }

    /// `count` characters the user typed went into a field through the input method (the session tells them as they go
    /// in: `InputSession.countTyped`), added to today's number. Only the number: never which, nor where.
    public func recordTypedCharacters(_ count: Int) {
        guard count > 0 else { return }
        let today = day(of: now())
        record.withLock { record in
            // A day's first count drops the days no longer kept; the others only add.
            if record.days[today.key] == nil { prune(&record, today: today) }
            record.days[today.key, default: Day()].charactersTyped += count
            if record.since == nil { record.since = today.key }
        }
        tell()
    }

    /// Everything counted forgotten (Settings → Privacy's Forget All): the next week shown is a first week again. The
    /// salt stays (nothing it hashed is kept).
    public func clearHistory() {
        record.withLock { record in
            record.days = [:]
            record.since = nil
        }
        tell()
    }

    /// Whether any command is counted in the weeks kept: the menu bar panel's row shows from the first.
    public var hasCommands: Bool {
        let today = day(of: now())
        return record.withLock { record in
            prune(&record, today: today)
            return record.days.values.contains { !$0.commands.isEmpty }
        }
    }

    // MARK: - Kept

    /// What is kept, as JSON: the salt, the first day counted, and each day's counts by its date ("2026-11-10").
    public func serializedData() throws -> Data {
        let today = day(of: now())
        let kept = record.withLock { record -> Record in
            prune(&record, today: today)
            return record
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(kept)
    }

    /// What `serializedData` gave, back in place of what is counted now (the days older than kept dropped).
    public func restore(from data: Data) throws {
        var restored = try JSONDecoder().decode(Record.self, from: data)
        restored.days = restored.days.filter { Self.date($0.key, calendar: calendar) != nil }
        let today = day(of: now())
        record.withLock { record in
            prune(&restored, today: today)
            record = restored
        }
        tell()
    }

    // MARK: - A week

    /// The week `week` as the page shows it: its days Monday to Sunday, what ran, where from, the apps, the pastes, and
    /// how it compares with the week before (this week: so far, against the same days of last week).
    public func snapshot(for week: Week) -> Snapshot {
        let today = day(of: now())
        let kept = record.withLock { record -> Record in
            prune(&record, today: today)
            return record
        }
        let thisMonday = monday(of: today.date)
        let monday = week == .current ? thisMonday : add(days: -7, to: thisMonday)
        let before = add(days: -7, to: monday)
        let dates = (0..<7).map { add(days: $0, to: monday) }
        let todayIndex = week == .current ? dates.firstIndex { calendar.isDate($0, inSameDayAs: today.date) } : nil
        let days = dates.map { kept.days[Self.key($0, calendar: calendar)] ?? Day() }

        var commands: [String: (source: CommandSource, runs: Int)] = [:]
        var sources = Snapshot.SourceCounts()
        var ai = 0, pastes = 0, characters = 0
        var apps = Set<String>()
        for day in days {
            for (id, runs) in day.commands {
                commands[id] = (runs.source, (commands[id]?.runs ?? 0) + runs.runs)
                sources.add(runs.runs, from: runs.source)
                ai += runs.ai
            }
            apps.formUnion(day.apps)
            pastes += day.clipboardPastes
            characters += day.charactersTyped
        }
        let ranked = commands.map { Snapshot.CommandCount(id: $0.key, source: $0.value.source, count: $0.value.runs) }
            .sorted { ($1.count, $0.id) < ($0.count, $1.id) }
        let top = Array(ranked.prefix(Snapshot.topLimit))
        let rest = ranked.dropFirst(Snapshot.topLimit)

        // So far this week (through today), against last week through the same weekday; a past week whole.
        let through = todayIndex ?? 6
        let counted = days.prefix(through + 1).reduce(0) { $0 + $1.runCount }
        let earlier = (0...through).reduce(0) { sum, index in
            sum + (kept.days[Self.key(add(days: index, to: before), calendar: calendar)]?.runCount ?? 0)
        }
        let comparison = earlier > 0 ? Snapshot.Comparison(count: counted, lastWeekCount: earlier) : nil

        let first = kept.since.flatMap { Self.date($0, calendar: calendar) }
        return Snapshot(
            week: week,
            days: zip(dates, days).enumerated().map { index, pair in
                Snapshot.Day(date: pair.0, commandCount: pair.1.runCount, isToday: index == todayIndex,
                             isFuture: todayIndex.map { index > $0 } ?? false)
            },
            commandCount: sources.total, aiCommandCount: ai, sourceCounts: sources, distinctAppCount: apps.count,
            topCommands: top, otherCommands: Snapshot.OtherCommands(count: rest.count, total: rest.reduce(0) { $0 + $1.count }),
            comparison: comparison, firstRecordedDay: first, clipboardPasteCount: pastes, charactersTyped: characters,
            isFirstWeek: first.map { $0 >= monday } ?? true, calendar: calendar)
    }

    // MARK: - Days

    private struct Today {
        var date: Date
        var key: String
    }

    private func day(of date: Date) -> Today {
        let start = calendar.startOfDay(for: date)
        return Today(date: start, key: Self.key(start, calendar: calendar))
    }

    private func monday(of date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)  // 1 Sunday … 7 Saturday
        return add(days: -((weekday + 5) % 7), to: date)
    }

    /// `days` days after the start of `date`'s day, at the start of that day (a day of 23 or 25 hours is still one day).
    private func add(days: Int, to date: Date) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date)
    }

    /// "2026-11-10": a day, and nothing finer (the file's days, the name of a picture saved).
    public static func key(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func two(_ value: Int?) -> String { value.map { $0 < 10 ? "0\($0)" : "\($0)" } ?? "00" }
        return "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day))"
    }

    /// The start of the day `key` names, in `calendar`; nil for anything else.
    static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])).map(calendar.startOfDay)
    }

    private func prune(_ record: inout Record, today: Today) {
        let first = Self.key(add(days: -7 * (Self.weeksKept - 1), to: monday(of: today.date)), calendar: calendar)
        // The keys sort as their days do.
        if record.days.keys.contains(where: { $0 < first }) { record.days = record.days.filter { $0.key >= first } }
        // Nor the first day counted once it's older than they are: counting started before all the days kept (no week
        // shown is a first week then), and no older day stays in the file.
        if let since = record.since, since < first { record.since = first }
    }

    private func appHash(_ bundleID: String?, salt: Data) -> String? {
        guard let id = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !id.isEmpty else { return nil }
        let code = HMAC<SHA256>.authenticationCode(for: Data(id.utf8), using: SymmetricKey(data: salt))
        return code.prefix(8).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }

    private static func randomSalt() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private func tell() { listener.withLock { $0 }?.changed() }

    /// `changed` in a struct (a function kept in `Locked` as it is would gain a thunk on each write: `InterfaceText`).
    private struct Listener {
        let changed: @Sendable () -> Void
    }

    // MARK: - The file

    /// What is kept: the salt, the first day counted (`since`), and the days.
    private struct Record: Codable {
        var version = 1
        var salt: Data
        var since: String?
        var days: [String: Day] = [:]

        init(salt: Data) { self.salt = salt }
    }

    /// One day's counts: each command's runs, the apps (salted hashes), the clipboard history pastes, the characters
    /// typed.
    private struct Day: Codable {
        var commands: [String: Runs] = [:]
        var apps: [String] = []
        var clipboardPastes = 0
        var charactersTyped = 0

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commands = try container.decodeIfPresent([String: Runs].self, forKey: .commands) ?? [:]
            apps = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
            clipboardPastes = max(try container.decodeIfPresent(Int.self, forKey: .clipboardPastes) ?? 0, 0)
            // A file from before 0.7.4's characters has none; one made by hand can't make a week's sum overflow.
            charactersTyped = min(max(try container.decodeIfPresent(Int.self, forKey: .charactersTyped) ?? 0, 0), Int(Int32.max))
        }

        var runCount: Int { commands.values.reduce(0) { $0 + $1.runs } }
    }

    private struct Runs: Codable {
        var source: CommandSource
        var runs = 0
        /// Of them, those that sent a request to an AI provider.
        var ai = 0

        init(source: CommandSource) { self.source = source }
    }
}

// MARK: - A week, counted

extension WeekStats {
    /// A calendar week's counts, as `snapshot(for:)` makes them: what the page, the picture, the menu bar panel and
    /// `@stats` show.
    public struct Snapshot: Equatable, Sendable {
        /// The commands listed by name: the most run first.
        public static let topLimit = 5

        public struct Day: Equatable, Sendable {
            /// Its start, in the calendar's time zone.
            public var date: Date
            public var commandCount: Int
            /// Today (this week only), and a day after it: nothing counted yet, drawn as an empty one.
            public var isToday: Bool
            public var isFuture: Bool
        }

        public struct SourceCounts: Equatable, Sendable {
            public var own = 0
            public var builtIn = 0
            public var plugin = 0

            public var total: Int { own + builtIn + plugin }

            public subscript(source: CommandSource) -> Int {
                switch source {
                case .own: return own
                case .builtIn: return builtIn
                case .plugin: return plugin
                }
            }

            mutating func add(_ runs: Int, from source: CommandSource) {
                switch source {
                case .own: own += runs
                case .builtIn: builtIn += runs
                case .plugin: plugin += runs
                }
            }
        }

        public struct CommandCount: Equatable, Sendable {
            public var id: String
            public var source: CommandSource
            public var count: Int
        }

        /// The commands after the first `topLimit`: how many, and their runs together.
        public struct OtherCommands: Equatable, Sendable {
            public var count: Int
            public var total: Int
        }

        /// The week's runs against the week before's: this week through today against last week through the same
        /// weekday; a past week whole against the one before it.
        public struct Comparison: Equatable, Sendable {
            public var count: Int
            public var lastWeekCount: Int

            /// How much more (or less, below 0), in whole percent of the week before's.
            public var percent: Int {
                Int((Double(count - lastWeekCount) / Double(lastWeekCount) * 100).rounded())
            }
        }

        /// A command as the shared picture names it (`shareCommands`).
        public struct ShareCommand: Equatable, Sendable {
            public var id: String
            public var source: CommandSource
            public var count: Int
            /// "@sig", or "My command 1" for the user's own when their names are hidden.
            public var displayName: String
            /// Its name is hidden (one of the user's own).
            public var isHidden: Bool
        }

        public var week: Week
        /// Monday to Sunday.
        public var days: [Day]
        public var commandCount: Int
        /// Of them, those that sent a request to an AI provider.
        public var aiCommandCount: Int
        public var sourceCounts: SourceCounts
        /// How many apps it was used in (each counted once in the week).
        public var distinctAppCount: Int
        /// The most run, at most `topLimit`.
        public var topCommands: [CommandCount]
        public var otherCommands: OtherCommands
        /// Nil when the week before had none on those days.
        public var comparison: Comparison?
        /// The first day anything was counted (nil: nothing yet).
        public var firstRecordedDay: Date?
        public var clipboardPasteCount: Int
        /// The characters typed through the input method in the week (`recordTypedCharacters`).
        public var charactersTyped: Int
        /// Counting started in this week (or hasn't yet): there is no week before to compare it with.
        public var isFirstWeek: Bool
        /// The calendar its days are in (their time zone).
        public var calendar: Calendar

        /// The days with at least one command.
        public var daysUsed: Int { days.filter { $0.commandCount > 0 }.count }

        /// Today's place among `days` (this week only).
        public var todayIndex: Int? { days.firstIndex { $0.isToday } }

        /// `topCommands` as the picture names them: "@" and their names, the user's own as "My command 1", "My command
        /// 2" … in their order when `hideOwnCommandNames` (in `language`: the design's Simplified Chinese by default).
        /// The page always shows the names.
        public func shareCommands(hideOwnCommandNames: Bool, language: String = "zh-Hans") -> [ShareCommand] {
            var own = 0
            let words = WeekStatsWords(language: language)
            return topCommands.map { command in
                guard hideOwnCommandNames, command.source == .own else {
                    return ShareCommand(id: command.id, source: command.source, count: command.count,
                                        displayName: "@" + command.id, isHidden: false)
                }
                own += 1
                return ShareCommand(id: command.id, source: command.source, count: command.count,
                                    displayName: words.ownCommand(own), isHidden: true)
            }
        }
    }
}
