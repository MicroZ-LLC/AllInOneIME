import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Proposed API for the implementation:
// WeekStats(now:calendar:) is a local, thread-safe recorder. SessionServices.weekStats is an
// optional shared recorder; InputSession reports successful commands, sent AI requests, text
// actually inserted and clipboard-history pastes to it. The recorder exposes recordCommand(name:),
// recordAIRequest(), recordInsertedText(_:), recordClipboardPaste(), snapshot(), serializedData(),
// clearHistory() and cardText(language:). The snapshot exposes commandCount, aiRequestCount,
// characterCount, clipboardPasteCount, days (date and commandCount), topCommands (name and count),
// startDate and endDate. One recordCommand call represents one completed command, including a
// command selected through one @. Dates use the injected calendar's day boundaries.
@Suite(.serialized)
struct WeekStatsTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func day(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = utc.timeZone
        return formatter.date(from: text)!
    }

    private final class Clock: @unchecked Sendable {
        var now = WeekStatsTests.day("2026-11-10")
        func advance(_ days: Int) { now = WeekStatsTests.utc.date(byAdding: .day, value: days, to: now)! }
        func at(_ text: String) { now = WeekStatsTests.day(text) }
        func recorder() -> WeekStats { WeekStats(now: { self.now }, calendar: WeekStatsTests.utc) }
    }

    private func host(stats: WeekStats, custom: [CustomCommand] = [],
                      plugins: [InstalledPlugin] = [], scripts: [ScriptCommand] = [],
                      english: Bool = true) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .apple
        config.customCommands = custom
        let fixed = config
        let model = OneAtAcceptanceTests.Model()
        var services = SessionServices(
            converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
            loadSettings: { fixed })
        services.weekStats = stats
        let engine = FakeEngine()
        engine.dictionary["nihao"] = ["你好"]
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.runProgram = { _, input in OneAtAcceptanceTests.printing(input.uppercased()) }
        services.plugins = { _ in plugins }
        services.runPlugin = { _, input, _ in OneAtAcceptanceTests.printing(input.uppercased()) }
        services.loadExtensions = { _, _ in ExtensionIndex(commands: scripts) }
        services.startScript = { _, _, _, event in
            event(.update(CommandRunner.ScriptUpdate(output: .text("done"), text: "done", isFinal: true)))
            return 1
        }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(english ? .english : .chinese)
        return host
    }

    @Test func commandsAreCountedByNameWhenRunThroughTheSession() {
        let clock = Clock()
        let stats = clock.recorder()
        let own = CustomCommand(name: "shout", type: .run, argv: ["/usr/bin/tr", "a-z", "A-Z"])
        let plugin = OneAtCustomCommandsAcceptanceTests.wordcount
        let script = OneAtCustomCommandsAcceptanceTests.tsconv
        for (index, command) in ["@py 2+3", "@shout hello", "@wordcount hello", "@tsconv 1700000000"].enumerated() {
            let field = host(stats: stats, custom: [own], plugins: [plugin], scripts: [script])
            field.type(command)
            field.press(FakeHost.enter)
            #expect(field.settle(timeout: 5) { stats.snapshot().commandCount >= index + 1 })
        }
        let top = Dictionary(uniqueKeysWithValues: stats.snapshot().topCommands.map { ($0.name, $0.count) })
        #expect(top["py"] == 1)
        #expect(top["shout"] == 1)
        #expect(top["wordcount"] == 1)
        #expect(top["tsconv"] == 1)
    }

    @Test func oneAtActionCountsTheCommandItRunsOnce() {
        let stats = Clock().recorder()
        let field = host(stats: stats)
        field.type("@please improve this sentence")
        field.press(FakeHost.enter)
        #expect(field.settle(timeout: 5) { stats.snapshot().commandCount == 1 })
        #expect(stats.snapshot().topCommands.map(\.name) == ["improve"])
    }

    @Test func aiRequestsInsertedCharactersAndHistoryPastesAreCounted() {
        let stats = Clock().recorder()
        let ai = host(stats: stats)
        ai.type("@improve hello")
        ai.press(FakeHost.enter)
        #expect(ai.settle(timeout: 5) { stats.snapshot().aiRequestCount == 1 })

        let typing = host(stats: stats)
        typing.type("Hi")
        typing.press(FakeHost.space)
        #expect(typing.document == "Hi ")
        #expect(stats.snapshot().characterCount >= 3)

        let chinese = host(stats: stats, english: false)
        chinese.type("nihao")
        chinese.press(FakeHost.space)
        #expect(chinese.document == "你好")
        #expect(stats.snapshot().characterCount >= 5)

        let paste = host(stats: stats)
        paste.clipboard = .text("private paste body")
        paste.keepClipboardHistory()
        #expect(paste.press(FakeHost.controlV))
        #expect(paste.press(FakeHost.enter))
        #expect(paste.document == "private paste body")
        #expect(stats.snapshot().clipboardPasteCount == 1)
        #expect(stats.snapshot().characterCount >= 23)
    }

    @Test func sevenDayWindowAndEightWeekRetentionUseCalendarDays() throws {
        let clock = Clock()
        clock.at("2026-09-15")
        let stats = clock.recorder()
        stats.recordCommand(name: "old")
        clock.at("2026-09-16") // the first of 56 retained calendar days
        stats.recordCommand(name: "kept")
        clock.at("2026-11-03")
        stats.recordCommand(name: "outside-week")
        clock.at("2026-11-04")
        stats.recordCommand(name: "inside-week")
        clock.at("2026-11-10")
        stats.recordAIRequest()
        let week = stats.snapshot()
        #expect(week.startDate == Self.day("2026-11-04"))
        #expect(week.endDate == Self.day("2026-11-10"))
        #expect(week.days.count == 7)
        #expect(week.days.map(\.commandCount) == [1, 0, 0, 0, 0, 0, 0])
        #expect(week.commandCount == 1)
        #expect(week.aiRequestCount == 1)
        let serialized = String(decoding: try stats.serializedData(), as: UTF8.self)
        #expect(!serialized.contains("old"))
        #expect(serialized.contains("kept"))
        #expect(serialized.contains("outside-week"))
    }

    @Test func persistedDataContainsOnlyDayCountsAndCommandNames() throws {
        let stats = Clock().recorder()
        let typed = "private typed sentence 92841"
        let selected = "秘密选择内容 74193"
        let pasted = "private clipboard contents 61027"
        let field = host(stats: stats)
        field.type(typed)
        field.document = selected
        field.selection = 0..<(selected as NSString).length
        field.clipboard = .text(pasted)
        field.keepClipboardHistory()
        field.press(FakeHost.controlV)
        field.press(FakeHost.enter)
        stats.recordCommand(name: "improve")
        let data = try stats.serializedData()
        let json = String(decoding: data, as: UTF8.self)
        for forbidden in [typed, selected, pasted, "com.example.editor", "92841", "74193", "61027"] {
            #expect(!json.contains(forbidden), "usage.json retained sensitive content: \(forbidden)")
        }
        #expect(json.contains("improve"))
        #expect(!json.contains("2026-11-10T"), "Only calendar days may be serialized")
    }

    @Test func clearHistoryRemovesCountsAndTheCard() {
        let stats = Clock().recorder()
        #expect(stats.cardText(language: "en") == nil)
        stats.recordCommand(name: "improve")
        #expect(stats.snapshot().commandCount == 1)
        stats.clearHistory()
        #expect(stats.snapshot().commandCount == 0)
        #expect(stats.snapshot().aiRequestCount == 0)
        #expect(stats.cardText(language: "en") == nil)
    }

    @Test func aboutSummaryOffersFiveMostUsedCommands() {
        let stats = Clock().recorder()
        for (name, count) in [("one", 6), ("two", 5), ("three", 4),
                              ("four", 3), ("five", 2), ("six", 1)] {
            for _ in 0..<count { stats.recordCommand(name: name) }
        }
        #expect(stats.snapshot().topCommands.map { $0.name } ==
                ["one", "two", "three", "four", "five"])
    }

    @Test func cardTextInEnglishAndChineseShowsTheSameNumbers() {
        let stats = Clock().recorder()
        #expect(stats.cardText(language: "en") == nil)
        #expect(stats.cardText(language: "zh-Hans") == nil)
        for _ in 0..<41 { stats.recordCommand(name: "improve") }
        for _ in 0..<40 { stats.recordCommand(name: "translate") }
        for _ in 0..<30 { stats.recordCommand(name: "question") }
        for _ in 0..<21 { stats.recordCommand(name: "reply") }
        stats.recordInsertedText(String(repeating: "好", count: 2_300))
        #expect(stats.cardText(language: "en") ==
                "This week: 132 commands · @improve most (41) · 2,300 characters")
        #expect(stats.cardText(language: "zh-Hans") ==
                "本周：132 次指令 · 最常用 @improve（41 次）· 2,300 字")
    }
}
