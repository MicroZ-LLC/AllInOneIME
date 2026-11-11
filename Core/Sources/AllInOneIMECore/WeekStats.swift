import Crypto
import Foundation

/// This week's stats (0.7.4): how much AllInOneIME was used on this device, per local day, for Settings → This Week, the
/// menu bar panel's row, `@stats` and the picture a user can share. Counts and command names are kept:
///   - each command run, by its id (its name in the command list) and where it comes from (`CommandSource`), and whether
///     it sent a request to an AI provider; one @'s rows count as the command they ran. A command of the user's own
///     deleted or renamed since loses its name (`keepCommands`): its runs stay, among the earlier commands of its source;
///   - the apps it was used in, as salted hashes of their bundle ids: the page shows how many, never which. The salt
///     (`salt`, random) isn't kept with the counts: the shell keeps it apart (the Mac: in the keychain), and hashes made
///     with another are dropped when the counts are read back;
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
    private let state: Locked<State>
    private let listener = Locked<Listener?>(initialState: nil)

    /// `now` and `calendar` say which day it is (a test's, the system's by default); `salt` is what the bundle ids are
    /// hashed with (nil: a random one), which the shell keeps apart from the counts.
    public init(now: @escaping () -> Date = { Platform.current.clock.now }, calendar: Calendar = WeekStats.defaultCalendar(),
                salt: Data? = nil) {
        self.now = now
        var calendar = calendar
        calendar.firstWeekday = 2
        self.calendar = calendar
        state = Locked(initialState: State(salt: salt ?? Self.randomSalt()))
    }

    /// What the bundle ids are hashed with now: the shell keeps it apart from the counts (`kept`). A new one after
    /// `clearHistory`.
    public var salt: Data { state.withLock { $0.salt } }

    /// How many times everything counted was forgotten (`clearHistory`): a run counted once its request answers is
    /// counted only in the era it started in (`recordCommand`'s `era`), so a late answer adds nothing to the counts
    /// forgotten meanwhile.
    public var era: Int { state.withLock { $0.era } }

    /// Told after each change (a record, a restore, a clear), on the thread that made it: the shell writes the file
    /// soon after, off the key's thread.
    public var changed: (@Sendable () -> Void)? {
        get { listener.withLock { $0?.changed } }
        set { listener.withLock { $0 = newValue.map(Listener.init) } }
    }

    // MARK: - Counting

    /// A command ran: `id` its name, `source` where it comes from (the same name from two sources is counted as two
    /// commands), `bundleID` the app it ran in (nil: unknown), `usedAI` whether it sent a request to an AI provider.
    /// `era`: the `era` it started in, for a run counted once its request answers (nil: now); not counted if everything
    /// was forgotten since.
    public func recordCommand(id: String, source: CommandSource, bundleID: String?, usedAI: Bool, era: Int? = nil) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let today = day(of: now())
        let counted = state.withLock { state -> Bool in
            guard era.map({ $0 == state.era }) ?? true else { return false }
            prune(&state.record, today: today)
            var day = state.record.days[today.key] ?? Day()
            day.commands[source.rawValue, default: [:]][id, default: Runs()].add(usedAI: usedAI)
            if let hash = appHash(bundleID, salt: state.salt), !day.apps.contains(hash) {
                day.apps.append(hash)
                day.apps.sort()
            }
            state.record.days[today.key] = day
            if state.record.since == nil { state.record.since = today.key }
            return true
        }
        if counted { tell() }
    }

    /// Something was pasted from clipboard history.
    public func recordClipboardPaste() {
        let today = day(of: now())
        state.withLock { state in
            prune(&state.record, today: today)
            state.record.days[today.key, default: Day()].clipboardPastes += 1
            if state.record.since == nil { state.record.since = today.key }
        }
        tell()
    }

    /// `count` characters the user typed went into a field through the input method (the session tells them as they go
    /// in: `InputSession.countTyped`), added to today's number. Only the number: never which, nor where.
    public func recordTypedCharacters(_ count: Int) {
        guard count > 0 else { return }
        let today = day(of: now())
        state.withLock { state in
            // A day's first count drops the days no longer kept; the others only add.
            if state.record.days[today.key] == nil { prune(&state.record, today: today) }
            state.record.days[today.key, default: Day()].charactersTyped += count
            if state.record.since == nil { state.record.since = today.key }
        }
        tell()
    }

    /// Everything counted forgotten (Settings → Privacy's Forget All): the next week shown is a first week again. The
    /// salt goes too (a new one hashes the apps from now on), and the runs whose requests haven't answered yet are never
    /// counted (`era`).
    public func clearHistory() {
        let salt = Self.randomSalt()
        state.withLock { state in
            state.record = Record()
            state.salt = salt
            state.era += 1
        }
        tell()
    }

    /// The user's own commands there are now (`names`, of `source`): any other of that source counted in the weeks kept
    /// (one since deleted or renamed) loses its name, its runs kept among the earlier commands of its source
    /// (`Snapshot.otherCommands`), so that every total stays as it was.
    public func keepCommands(_ names: Set<String>, from source: CommandSource) {
        let changed = state.withLock { state -> Bool in
            var changed = false
            for (key, day) in state.record.days {
                guard let commands = day.commands[source.rawValue] else { continue }
                let gone = commands.filter { !names.contains($0.key) }
                guard !gone.isEmpty else { continue }
                var day = day
                for runs in gone.values { day.earlier[source.rawValue, default: Runs()].add(runs) }
                let kept = commands.filter { names.contains($0.key) }
                day.commands[source.rawValue] = kept.isEmpty ? nil : kept
                state.record.days[key] = day
                changed = true
            }
            return changed
        }
        if changed { tell() }
    }

    /// Whether any command is counted in the weeks kept: the menu bar panel's row shows from the first.
    public var hasCommands: Bool {
        let today = day(of: now())
        return state.withLock { state in
            prune(&state.record, today: today)
            return state.record.days.values.contains { $0.runCount > 0 }
        }
    }

    // MARK: - Kept

    /// What is kept, as JSON: which salt the apps' hashes were made with (`saltCheck`, never the salt), the first day
    /// counted, and each day's counts by its date ("2026-11-10").
    public func serializedData() throws -> Data {
        let (record, salt) = pruned()
        return try encode(record, salt: salt)
    }

    /// What the shell keeps, as one moment has it: the file's JSON (`serializedData`; nil when nothing is counted, and
    /// no file is needed), and the salt its apps' hashes were made with, which it keeps apart.
    public func kept() throws -> (data: Data?, salt: Data) {
        let (record, salt) = pruned()
        return (record.days.isEmpty && record.since == nil ? nil : try encode(record, salt: salt), salt)
    }

    /// What is counted in the weeks kept, and the salt, together.
    private func pruned() -> (Record, Data) {
        let today = day(of: now())
        return state.withLock { state in
            prune(&state.record, today: today)
            return (state.record, state.salt)
        }
    }

    private func encode(_ record: Record, salt: Data) throws -> Data {
        var record = record
        record.saltCheck = Self.check(salt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    /// What `serializedData` gave, back in place of what is counted now (the days older than kept dropped). Apps hashed
    /// with another salt than this one's (the salt lost, a file from elsewhere) are dropped: the week's apps start again.
    public func restore(from data: Data) throws {
        var restored = try JSONDecoder().decode(Record.self, from: data)
        restored.days = restored.days.filter { Self.date($0.key, calendar: calendar) != nil }
        let today = day(of: now())
        state.withLock { state in
            if restored.saltCheck != Self.check(state.salt) {
                for key in restored.days.keys { restored.days[key]?.apps = [] }
            }
            restored.saltCheck = nil
            prune(&restored, today: today)
            state.record = restored
        }
        tell()
    }

    // MARK: - A week

    /// The week `week` as the page shows it: its days Monday to Sunday, what ran, where from, the apps, the pastes, and
    /// how it compares with the week before (this week: so far, against the same days of last week).
    public func snapshot(for week: Week) -> Snapshot {
        let today = day(of: now())
        let kept = state.withLock { state -> Record in
            prune(&state.record, today: today)
            return state.record
        }
        let thisMonday = monday(of: today.date)
        let monday = week == .current ? thisMonday : add(days: -7, to: thisMonday)
        let before = add(days: -7, to: monday)
        let dates = (0..<7).map { add(days: $0, to: monday) }
        let todayIndex = week == .current ? dates.firstIndex { calendar.isDate($0, inSameDayAs: today.date) } : nil
        let days = dates.map { kept.days[Self.key($0, calendar: calendar)] ?? Day() }

        // Each command by its name and source; the earlier commands (since deleted or renamed) by source.
        var commands: [CommandKey: Int] = [:]
        var renamed: [CommandSource: Int] = [:]
        var sources = Snapshot.SourceCounts()
        var ai = 0, pastes = 0, characters = 0
        var apps = Set<String>()
        for day in days {
            for (raw, runs) in day.commands {
                guard let source = CommandSource(rawValue: raw) else { continue }
                for (id, runs) in runs {
                    commands[CommandKey(id: id, source: source), default: 0] += runs.runs
                    sources.add(runs.runs, from: source)
                    ai += runs.ai
                }
            }
            for (raw, runs) in day.earlier {
                guard let source = CommandSource(rawValue: raw) else { continue }
                renamed[source, default: 0] += runs.runs
                sources.add(runs.runs, from: source)
                ai += runs.ai
            }
            apps.formUnion(day.apps)
            pastes += day.clipboardPastes
            characters += day.charactersTyped
        }
        let ranked = commands.map { Snapshot.CommandCount(id: $0.key.id, source: $0.key.source, count: $0.value) }
            .sorted { ($1.count, $0.id, $0.source.rawValue) < ($0.count, $1.id, $1.source.rawValue) }
        let top = Array(ranked.prefix(Snapshot.topLimit))
        // The rest: the commands after the top ones, and the earlier commands of each source as one each.
        let rest = ranked.dropFirst(Snapshot.topLimit).map(\.count) + renamed.values.filter { $0 > 0 }

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
            topCommands: top, otherCommands: Snapshot.OtherCommands(count: rest.count, total: rest.reduce(0, +)),
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

    /// Which salt `salt` is, for the file (`Record.saltCheck`): a hash of it that tells two apart, never the salt.
    private static func check(_ salt: Data) -> String {
        SHA256.hash(data: Data("AllInOneIME week stats salt".utf8) + salt).prefix(8).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }

    private func tell() { listener.withLock { $0 }?.changed() }

    /// `changed` in a struct (a function kept in `Locked` as it is would gain a thunk on each write: `InterfaceText`).
    private struct Listener {
        let changed: @Sendable () -> Void
    }

    /// What is counted, the salt the apps are hashed with, and how many times everything was forgotten (`era`).
    private struct State {
        var record = Record()
        var salt: Data
        var era = 0
    }

    /// A command as the week ranks it: the same name from two sources is two.
    private struct CommandKey: Hashable {
        var id: String
        var source: CommandSource
    }

    // MARK: - The file

    /// What is kept: which salt the apps were hashed with (`saltCheck`, written with the file), the first day counted
    /// (`since`), and the days.
    private struct Record: Codable {
        var version = 2
        var saltCheck: String?
        var since: String?
        var days: [String: Day] = [:]
    }

    /// One day's counts: each command's runs by its source (`CommandSource`'s raw value) and name, the runs of the
    /// earlier commands (since deleted or renamed: `keepCommands`) by their source, the apps (salted hashes), the
    /// clipboard history pastes, the characters typed.
    private struct Day: Codable {
        var commands: [String: [String: Runs]] = [:]
        var earlier: [String: Runs] = [:]
        var apps: [String] = []
        var clipboardPastes = 0
        var charactersTyped = 0

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commands = try container.decodeIfPresent([String: [String: Runs]].self, forKey: .commands) ?? [:]
            earlier = try container.decodeIfPresent([String: Runs].self, forKey: .earlier) ?? [:]
            apps = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
            clipboardPastes = max(try container.decodeIfPresent(Int.self, forKey: .clipboardPastes) ?? 0, 0)
            // A file from before 0.7.4's characters has none; one made by hand can't make a week's sum overflow.
            charactersTyped = min(max(try container.decodeIfPresent(Int.self, forKey: .charactersTyped) ?? 0, 0), Int(Int32.max))
        }

        var runCount: Int {
            let named = commands.values.reduce(0) { sum, runs in runs.values.reduce(sum) { $0 + $1.runs } }
            return earlier.values.reduce(named) { $0 + $1.runs }
        }
    }

    private struct Runs: Codable {
        var runs = 0
        /// Of them, those that sent a request to an AI provider.
        var ai = 0

        mutating func add(usedAI: Bool) {
            runs += 1
            if usedAI { ai += 1 }
        }

        mutating func add(_ other: Runs) {
            runs += other.runs
            ai += other.ai
        }
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

        /// The commands after the first `topLimit`: how many, and their runs together (the earlier commands of a source,
        /// since deleted or renamed, as one).
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
