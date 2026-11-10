import Foundation
import Testing
@testable import AllInOneIMECore

/// What is counted on this Mac for the menu bar panel (`UsageStats`): commands run (those with AI apart) and puts from the
/// clipboard history, per local day, the last 7 days in one line, 30 days kept.
struct UsageStatsTests {
    /// Noon on 2027-01-15 in Los Angeles.
    let noon = Date(timeIntervalSince1970: 1_800_000_000 + 12 * 3600)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }()

    func daysAgo(_ days: Int) -> Date { noon.addingTimeInterval(-Double(days) * 86400) }

    @Test func eachKindIsCountedAndAIIsAlsoACommand() {
        var stats = UsageStats()
        #expect(stats.summary(language: "zh-Hans", now: noon, calendar: calendar) == nil, "nothing yet: no line")
        stats.record(.command(usesAI: false), now: noon, calendar: calendar)
        stats.record(.command(usesAI: true), now: noon, calendar: calendar)
        stats.record(.clipboard, now: noon, calendar: calendar)
        stats.record(.clipboard, now: noon, calendar: calendar)
        #expect(stats.total(now: noon, calendar: calendar) == UsageStats.Counts(commands: 2, aiCommands: 1, clipboard: 2))
        #expect(stats.summary(language: "zh-Hans", now: noon, calendar: calendar) == "近 7 天：命令 2 次（用 AI 1 次）· 剪贴板 2 次")
        #expect(stats.summary(language: "en", now: noon, calendar: calendar) == "Last 7 days: commands 2 (AI 1) · clipboard 2")
    }

    @Test func theLastSevenDaysTodayIncluded() {
        var stats = UsageStats()
        stats.record(.command(usesAI: false), now: daysAgo(7), calendar: calendar)  // a day too old for the line
        stats.record(.command(usesAI: false), now: daysAgo(6), calendar: calendar)
        stats.record(.clipboard, now: noon, calendar: calendar)
        #expect(stats.total(now: noon, calendar: calendar) == UsageStats.Counts(commands: 1, clipboard: 1))
        #expect(stats.total(days: 8, now: noon, calendar: calendar).commands == 2)
        // A week on, only today's: nothing in the line.
        #expect(stats.summary(language: "en", now: daysAgo(-7), calendar: calendar) == nil)
    }

    @Test func daysAreLocalDays() {
        // 23:30 and 00:30 in Los Angeles are two days, though an hour apart.
        let lateEvening = noon.addingTimeInterval(11.5 * 3600)
        var stats = UsageStats()
        stats.record(.clipboard, now: lateEvening, calendar: calendar)
        stats.record(.clipboard, now: lateEvening.addingTimeInterval(3600), calendar: calendar)
        #expect(stats.days.keys.sorted() == ["2027-01-15", "2027-01-16"], "\(stats.days.keys.sorted())")
    }

    @Test func onlyThirtyDaysAreKept() {
        var stats = UsageStats()
        for back in stride(from: 40, through: 0, by: -1) { stats.record(.clipboard, now: daysAgo(back), calendar: calendar) }
        #expect(stats.days.count == UsageStats.keptDays, "\(stats.days.count)")
        #expect(stats.total(days: 60, now: noon, calendar: calendar).clipboard == UsageStats.keptDays)
    }

    @Test func keptAsJSONAndReadWithWhatIsMissing() throws {
        var stats = UsageStats()
        stats.record(.command(usesAI: true), now: noon, calendar: calendar)
        let decoded = try JSONDecoder().decode(UsageStats.self, from: JSONEncoder().encode(stats))
        #expect(decoded == stats)
        // A count not kept (an older or newer version's file) reads as 0; no days at all, as none.
        let partial = Data(#"{"days": {"2027-01-15": {"clipboard": 3}}}"#.utf8)
        #expect(try JSONDecoder().decode(UsageStats.self, from: partial).total(now: noon, calendar: calendar)
            == UsageStats.Counts(clipboard: 3))
        #expect(try JSONDecoder().decode(UsageStats.self, from: Data("{}".utf8)) == UsageStats())
    }
}
