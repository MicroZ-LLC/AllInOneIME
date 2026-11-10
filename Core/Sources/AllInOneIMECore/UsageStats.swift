import Foundation

/// What was used on each day, counted on this Mac only: commands run (and of them, those that send text to a model,
/// `Command.usesAI`) and what was put in from the clipboard history. Never what was typed, run or copied: only how many
/// times. The menu bar panel shows the last 7 days in one line (`summary`). Days are the local calendar's; only the last
/// `keptDays` are kept. Never synced.
public struct UsageStats: Codable, Equatable, Sendable {
    /// One use, as the session reports it (`SessionServices.recordUsage`).
    public enum Event: Equatable, Sendable {
        /// A command was run (`Composer.Effect.commandUsed`); `usesAI`: it sends text to a model.
        case command(usesAI: Bool)
        /// Something from the clipboard history was put in (one or more rows at once count once).
        case clipboard
    }

    /// The counts of one day, or of several added up (`total`).
    public struct Counts: Codable, Equatable, Sendable {
        /// Every command run, those with AI included.
        public var commands = 0
        /// The commands run that send text to a model (counted in `commands` too).
        public var aiCommands = 0
        /// Puts from the clipboard history.
        public var clipboard = 0

        public init(commands: Int = 0, aiCommands: Int = 0, clipboard: Int = 0) {
            (self.commands, self.aiCommands, self.clipboard) = (commands, aiCommands, clipboard)
        }

        private enum CodingKeys: String, CodingKey {
            case commands, aiCommands, clipboard
        }

        /// A count a later version doesn't keep reads as 0.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commands = try container.decodeIfPresent(Int.self, forKey: .commands) ?? 0
            aiCommands = try container.decodeIfPresent(Int.self, forKey: .aiCommands) ?? 0
            clipboard = try container.decodeIfPresent(Int.self, forKey: .clipboard) ?? 0
        }

        /// Nothing counted.
        public var isEmpty: Bool { commands == 0 && clipboard == 0 }

        static func + (a: Counts, b: Counts) -> Counts {
            Counts(commands: a.commands + b.commands, aiCommands: a.aiCommands + b.aiCommands, clipboard: a.clipboard + b.clipboard)
        }
    }

    /// How many days are kept (the oldest beyond are forgotten as a day is counted).
    public static let keptDays = 30

    /// The local day ("2026-11-10") → what was counted on it.
    var days: [String: Counts] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case days
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([String: Counts].self, forKey: .days) ?? [:]
    }

    /// `event` counted on the day of `now`; days older than `keptDays` forgotten.
    public mutating func record(_ event: Event, now: Date = Platform.current.clock.now, calendar: Calendar = .current) {
        let today = Self.day(now, calendar)
        var counts = days[today] ?? Counts()
        switch event {
        case let .command(usesAI):
            counts.commands += 1
            if usesAI { counts.aiCommands += 1 }
        case .clipboard:
            counts.clipboard += 1
        }
        days[today] = counts
        let kept = Set(Self.lastDays(Self.keptDays, now: now, calendar: calendar))
        days = days.filter { kept.contains($0.key) }
    }

    /// What was counted on the last `count` days, today included.
    public func total(days count: Int = 7, now: Date = Platform.current.clock.now, calendar: Calendar = .current) -> Counts {
        Self.lastDays(count, now: now, calendar: calendar).reduce(Counts()) { $0 + (days[$1] ?? Counts()) }
    }

    /// The menu bar panel's line for the last 7 days: 「近 7 天：命令 132 次（用 AI 21 次）· 剪贴板 48 次」 /
    /// "Last 7 days: commands 132 (AI 21) · clipboard 48"; nil while nothing was counted in them.
    public func summary(language: String, now: Date = Platform.current.clock.now, calendar: Calendar = .current) -> String? {
        let week = total(days: 7, now: now, calendar: calendar)
        guard !week.isEmpty else { return nil }
        let t = InterfaceWords(language: language)
        return t.tr("近 7 天：命令 \(week.commands) 次（用 AI \(week.aiCommands) 次）· 剪贴板 \(week.clipboard) 次",
                    "Last 7 days: commands \(week.commands) (AI \(week.aiCommands)) · clipboard \(week.clipboard)")
    }

    /// The local days of the last `count` days, newest first.
    static func lastDays(_ count: Int, now: Date, calendar: Calendar) -> [String] {
        (0..<max(count, 0)).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: now).map { day($0, calendar) }
        }
    }

    /// The local day of `date`: "2026-11-10".
    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
