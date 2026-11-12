import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Assumed API, written before implementation: WeekStats(now:calendar:salt:) records
// completed commands with recordCommand(id:source:bundleID:usedAI:) and clipboard
// history pastes with recordClipboardPaste(). CommandSource is .own/.builtIn/.plugin;
// script extensions are plugins. snapshot(for: .current/.previous) is a Monday–Sunday
// Snapshot with days, totals, sourceCounts, topCommands, otherCommands, comparison,
// and firstRecordedDay. WeekStatsText is the localized page/card/menu/@stats model;
// shareCommands(hideOwnCommandNames:) changes display names only. SessionServices
// reports FakeHost runs. SettingsPlace.weekStats and PlatformAction.copyWeekStatsImage
// bridge @stats to the Mac shell. Injectable salt makes privacy tests repeatable.
@Suite(.serialized)
struct WeekStatsTests {
    private static func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        result.firstWeekday = 2
        return result
    }

    private static func date(_ day: String, hour: Int = 12, zone: String = "America/Los_Angeles") -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return calendar(zone).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    private final class Clock: @unchecked Sendable {
        var now: Date
        let calendar: Calendar
        init(_ day: String = "2026-11-10", zone: String = "America/Los_Angeles") {
            now = WeekStatsTests.date(day, zone: zone)
            calendar = WeekStatsTests.calendar(zone)
        }
        func at(_ day: String) { now = WeekStatsTests.date(day, zone: calendar.timeZone.identifier) }
        func recorder() -> WeekStats {
            WeekStats(now: { self.now }, calendar: calendar, salt: Data(repeating: 0xA7, count: 32))
        }
    }

    private func host(_ stats: WeekStats, language: String = "zh-Hans", custom: [CustomCommand] = [],
                      plugins: [InstalledPlugin] = [], scripts: [ScriptCommand] = []) -> FakeHost {
        var config = Config.default
        config.uiLanguage = language
        config.provider = .apple
        config.customCommands = custom
        let fixed = config
        var services = SessionServices(
            converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: OneAtAcceptanceTests.Model()),
            loadSettings: { fixed })
        services.weekStats = stats
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.runProgram = { _, input in OneAtAcceptanceTests.printing(input.uppercased()) }
        services.plugins = { _ in plugins }
        services.runPlugin = { _, input, _ in OneAtAcceptanceTests.printing(input.uppercased()) }
        services.loadExtensions = { _, _ in ExtensionIndex(commands: scripts) }
        services.startScript = { _, _, _, event in
            event(.update(CommandRunner.ScriptUpdate(output: .text("done"), text: "done", isFinal: true)))
            return 1
        }
        let field = FakeHost(services: services)
        field.focus()
        field.composer.setInputMode(.english)
        return field
    }

    @Test func completedRunsKeepIdSourceAndAIPerCommand() {
        let stats = Clock().recorder()
        stats.recordCommand(id: "sig", source: .own, bundleID: "com.example.editor", usedAI: false)
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.editor", usedAI: true)
        stats.recordCommand(id: "wordcount", source: .plugin, bundleID: "com.example.chat", usedAI: false)
        stats.recordCommand(id: "tsconv", source: .plugin, bundleID: "com.example.chat", usedAI: false)
        let week = stats.snapshot(for: .current)
        #expect(week.commandCount == 4)
        #expect(week.aiCommandCount == 1)
        #expect(week.sourceCounts.own == 1)
        #expect(week.sourceCounts.builtIn == 1)
        #expect(week.sourceCounts.plugin == 2)
        #expect(week.distinctAppCount == 2)
        #expect(Set(week.topCommands.map(\.id)) == ["sig", "improve", "wordcount", "tsconv"])
    }

    @Test func fakeHostReportsOneAtAsTheCommandItActuallyRan() async {
        await withInterfaceLanguage("zh-Hans") {
            let stats = Clock().recorder()
            let own = CustomCommand(name: "shout", type: .run, argv: ["/usr/bin/tr", "a-z", "A-Z"])
            let plugin = OneAtCustomCommandsAcceptanceTests.wordcount
            let script = OneAtCustomCommandsAcceptanceTests.tsconv
            for (index, command) in ["@please improve this sentence", "@shout hello",
                                     "@wordcount hello", "@tsconv 1700000000"].enumerated() {
                let field = host(stats, custom: [own], plugins: [plugin], scripts: [script])
                field.type(command)
                field.press(FakeHost.enter)
                #expect(field.settle(timeout: 5) { stats.snapshot(for: .current).commandCount == index + 1 })
            }
            let week = stats.snapshot(for: .current)
            #expect(Dictionary(uniqueKeysWithValues: week.topCommands.map { ($0.id, $0.count) }) ==
                    ["improve": 1, "shout": 1, "wordcount": 1, "tsconv": 1])
            #expect(week.sourceCounts.own == 1)
            #expect(week.sourceCounts.builtIn == 1)
            #expect(week.sourceCounts.plugin == 2)
            #expect(week.aiCommandCount == 1)
        }
    }

    @Test func calendarWeekStartsMondayAndPreviousTabIsTheWholePreviousWeek() {
        let clock = Clock("2026-11-08")
        let stats = clock.recorder()
        stats.recordCommand(id: "prior", source: .builtIn, bundleID: nil, usedAI: false)
        clock.at("2026-11-09")
        stats.recordCommand(id: "monday", source: .builtIn, bundleID: nil, usedAI: false)
        clock.at("2026-11-10")
        let current = stats.snapshot(for: .current)
        let previous = stats.snapshot(for: .previous)
        #expect(current.days.map(\.date) == (9...15).map { Self.date("2026-11-\($0)", hour: 0) })
        #expect(current.days.map(\.commandCount) == [1, 0, 0, 0, 0, 0, 0])
        #expect(previous.days.map(\.date) == (2...8).map { Self.date("2026-11-0\($0)", hour: 0) })
        #expect(previous.commandCount == 1)
        #expect(current.daysUsed == 1)
        #expect(WeekStatsText(current, language: "zh-Hans").barLabels == ["1", "–", "–", "–", "–", "–", "–"])
    }

    @Test func comparisonUsesSameWeekdayAndHidesZeroDenominator() {
        let clock = Clock("2026-11-02")
        let stats = clock.recorder()
        for _ in 0..<10 { stats.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false) }
        clock.at("2026-11-03")
        for _ in 0..<10 { stats.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false) }
        clock.at("2026-11-08")
        for _ in 0..<80 { stats.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false) }
        clock.at("2026-11-09")
        for _ in 0..<15 { stats.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false) }
        clock.at("2026-11-10")
        #expect(stats.snapshot(for: .current).comparison?.lastWeekCount == 20)
        #expect(stats.snapshot(for: .current).comparison?.percent == -25)
        #expect(WeekStatsText(stats.snapshot(for: .current), language: "zh-Hans").comparison == "比上周同期少 25%")
        for _ in 0..<10 { stats.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false) }
        #expect(stats.snapshot(for: .current).comparison?.percent == 25)
        let up = WeekStatsText(stats.snapshot(for: .current), language: "zh-Hans")
        #expect(up.comparison == "比上周同期多 25%")
        #expect(up.menuBarRow.contains("本周 25 次指令"))
        #expect(up.menuBarRow.contains("↑25%"))
        #expect(up.atStatsComparison == "比上周同期多 25%")
        let first = Clock().recorder()
        first.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false)
        #expect(first.snapshot(for: .current).comparison == nil)
        #expect(WeekStatsText(first.snapshot(for: .current), language: "zh-Hans").comparison == "下周起会和上周比较")
    }

    @Test func firstWeekNamesFirstDayAndCountsOnlyDaysWithCommands() {
        let clock = Clock("2026-11-12")
        let stats = clock.recorder()
        for _ in 0..<4 { stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.a", usedAI: true) }
        clock.at("2026-11-13")
        for _ in 0..<3 { stats.recordCommand(id: "sig", source: .own, bundleID: "com.example.b", usedAI: false) }
        stats.recordClipboardPaste()
        let week = stats.snapshot(for: .current)
        let text = WeekStatsText(week, language: "zh-Hans")
        #expect(week.daysUsed == 2)
        #expect(week.distinctAppCount == 2)
        #expect(week.firstRecordedDay == Self.date("2026-11-12", hour: 0))
        #expect(text.dateSubtitle.contains("从周四开始统计"))
        #expect(text.activity == "2 天都用了 · 在 2 个 App 里")
        #expect(text.barLabels == ["–", "–", "–", "4", "3", "–", "–"])
        #expect(text.weekdayLabels(forShare: false) == ["一", "二", "三", "四", "今天", "六", "日"])
        #expect(text.weekdayLabels(forShare: true) == ["一", "二", "三", "四", "五", "六", "日"])
        #expect(text.commandHint == "在输入框开头打 @，可以看到全部指令")
        #expect(text.clipboardFooter.contains("只记次数，不记内容"))
        #expect(text.clipboardFooter.contains("1"))
    }

    @Test func theInjectedTimeZoneChoosesTheLocalDay() {
        let instant = ISO8601DateFormatter().date(from: "2026-11-09T00:30:00Z")!
        let la = WeekStats(now: { instant }, calendar: Self.calendar(), salt: Data(repeating: 1, count: 32))
        let utc = WeekStats(now: { instant }, calendar: Self.calendar("UTC"), salt: Data(repeating: 2, count: 32))
        la.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false)
        utc.recordCommand(id: "open", source: .builtIn, bundleID: nil, usedAI: false)
        #expect(la.snapshot(for: .current).days[6].commandCount == 1) // Sunday in Los Angeles
        #expect(utc.snapshot(for: .current).days[0].commandCount == 1) // Monday in UTC
    }

    @Test func topFiveOthersAndEmptyHintMatchTheCanvas() {
        let stats = Clock().recorder()
        for (id, count, source) in [("sig", 29, WeekStats.CommandSource.own),
                                    ("improve", 23, .builtIn), ("bm", 19, .plugin),
                                    ("translate", 15, .builtIn), ("addr", 14, .own),
                                    ("six", 12, .own), ("seven", 10, .builtIn),
                                    ("eight", 6, .own), ("nine", 4, .builtIn)] {
            for _ in 0..<count { stats.recordCommand(id: id, source: source, bundleID: nil, usedAI: false) }
        }
        let week = stats.snapshot(for: .current)
        #expect(week.topCommands.map(\.id) == ["sig", "improve", "bm", "translate", "addr"])
        #expect(week.otherCommands.count == 4)
        #expect(week.otherCommands.total == 32)
        #expect(week.sourceCounts.own == 61)
        #expect(week.sourceCounts.builtIn == 52)
        #expect(week.sourceCounts.plugin == 19)
        #expect(WeekStatsText(week, language: "zh-Hans").otherCommands == "另外 4 个指令共 32 次")
        #expect(WeekStatsText(Clock().recorder().snapshot(for: .current), language: "zh-Hans").commandHint ==
                "在输入框开头打 @，可以看到全部指令")
    }

    @Test func sharingHidesOnlyOwnNamesByRankAndKeepsThePageUnchanged() {
        let stats = Clock().recorder()
        for (id, source, count) in [("sig", WeekStats.CommandSource.own, 5),
                                    ("improve", .builtIn, 4), ("wordcount", .plugin, 3), ("addr", .own, 2)] {
            for _ in 0..<count { stats.recordCommand(id: id, source: source, bundleID: nil, usedAI: false) }
        }
        let week = stats.snapshot(for: .current)
        #expect(week.topCommands.map(\.id) == ["sig", "improve", "wordcount", "addr"])
        #expect(week.shareCommands(hideOwnCommandNames: true).map(\.displayName) ==
                ["我的命令 1", "@improve", "@wordcount", "我的命令 2"])
        #expect(week.shareCommands(hideOwnCommandNames: false).map(\.displayName) ==
                ["@sig", "@improve", "@wordcount", "@addr"])
        #expect(WeekStatsText(week, language: "zh-Hans").headline == "这周你用了")
        #expect(WeekStatsText(week, language: "zh-Hans").shareHeadline == "这周我用了")
    }

    @Test func eightCalendarWeeksAreRetainedWithNoSubdayOrPlainBundleId() throws {
        let clock = Clock("2026-09-20")
        let stats = clock.recorder()
        stats.recordCommand(id: "old", source: .own, bundleID: "com.private.old", usedAI: false)
        clock.at("2026-09-21")
        stats.recordCommand(id: "kept", source: .own, bundleID: "com.private.editor", usedAI: false)
        clock.at("2026-11-10")
        stats.recordCommand(id: "today", source: .builtIn, bundleID: "com.private.editor", usedAI: true)
        let json = String(decoding: try stats.serializedData(), as: UTF8.self)
        #expect(!json.contains("old"))
        #expect(json.contains("kept"))
        #expect(json.contains("today"))
        #expect(!json.contains("com.private"))
        #expect(!json.contains("2026-11-10T"))
        #expect(!json.contains("12:00"))
        #expect(json.contains("salt"))
    }

    @Test func appHashesSurviveRestoreAndDeduplicateAcrossDays() throws {
        let clock = Clock("2026-11-09")
        let stats = clock.recorder()
        stats.recordCommand(id: "open", source: .builtIn, bundleID: "com.private.editor", usedAI: false)
        clock.at("2026-11-10")
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.private.editor", usedAI: true)
        stats.recordCommand(id: "sig", source: .own, bundleID: "com.private.chat", usedAI: false)
        let data = try stats.serializedData()
        let restored = clock.recorder()
        try restored.restore(from: data)
        #expect(restored.snapshot(for: .current).distinctAppCount == 2)
        #expect(!String(decoding: data, as: UTF8.self).contains("com.private"))
    }

    @Test func typedTextArgumentsAndClipboardContentsAreNeverSerialized() async throws {
        try await withInterfaceLanguage("zh-Hans") {
            let stats = Clock().recorder()
            let field = host(stats)
            field.type("private typed sentence 92841")
            field.clipboard = .text("private clipboard contents 61027")
            field.keepClipboardHistory()
            field.press(FakeHost.controlV)
            field.press(FakeHost.enter)
            stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.secret.editor", usedAI: true)
            stats.recordClipboardPaste()
            let json = String(decoding: try stats.serializedData(), as: UTF8.self)
            for secret in ["private typed sentence", "92841", "private clipboard contents", "61027", "com.secret.editor"] {
                #expect(!json.contains(secret))
            }
            #expect(!json.contains("arguments"))
            #expect(json.contains("improve"))
            #expect(stats.snapshot(for: .current).clipboardPasteCount >= 1)
        }
    }

    @Test func privacyClearHistoryClearsCountsAndFirstWeekState() throws {
        let stats = Clock().recorder()
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.editor", usedAI: true)
        stats.recordClipboardPaste()
        stats.clearHistory()
        let week = stats.snapshot(for: .current)
        #expect(week.commandCount == 0)
        #expect(week.distinctAppCount == 0)
        #expect(week.clipboardPasteCount == 0)
        #expect(week.firstRecordedDay == nil)
        #expect(!String(decoding: try stats.serializedData(), as: UTF8.self).contains("improve"))
    }

    @Test func atStatsRowAndKeysBelongToTheIMEInChineseAndEnglish() async {
        let stats = Clock().recorder()
        for _ in 0..<5 { stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true) }
        for language in ["zh-Hans", "en"] {
            await withInterfaceLanguage(language) {
                let field = host(stats, language: language)
                field.type("@stats")
                let row = field.panel?.rows.first { $0.text.contains("5") && $0.text.contains(language == "en" ? "commands" : "次指令") }
                #expect(row != nil)
                #expect(row?.comment.contains(language == "en" ? "built-in" : "内置") == true)
                #expect(field.panel?.hints.contains { $0.key == "⌘C" } == true)
                #expect(field.panel?.hints.contains { $0.key == "Esc" } == true)
                #expect(field.press(FakeHost.enter))
                #expect(field.settingsOpened.last == .weekStats)
            }
        }
        await withInterfaceLanguage("zh-Hans") {
            let copy = host(stats)
            copy.type("@stats")
            #expect(copy.press(KeyEvent(keyCode: 0x08, characters: "c", charactersIgnoringModifiers: "c", modifiers: .command)))
            #expect(copy.platformActions.contains(.copyWeekStatsImage))
            let cancel = host(stats)
            cancel.type("@stats")
            #expect(cancel.press(FakeHost.escape))
            #expect(cancel.settingsOpened.isEmpty)
            #expect(cancel.document.isEmpty)
        }
    }

    @Test func statsWordsAreTranslatedForShippedInterfaces() {
        let stats = Clock().recorder()
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true)
        let chinese = WeekStatsText(stats.snapshot(for: .current), language: "zh-Hans")
        #expect(chinese.menuBarRow.contains("本周 1 次指令"))
        #expect(chinese.atStatsTitle == "本周 1 次指令")
        #expect(chinese.sourceSummary.contains("内置 1"))
        #expect(chinese.privacyNote == "统计只存在这台 Mac 上，不同步，也不上传。")
        #expect(chinese.pageTitle == "本周统计")
        #expect(chinese.tabTitles == ["本周", "上周"])
        #expect(chinese.hideNamesLabel == "复制时隐藏我的命令名")
        #expect(chinese.saveImageLabel == "存为图片…")
        #expect(chinese.copyImageLabel == "复制图片")
        let english = WeekStatsText(stats.snapshot(for: .current), language: "en")
        #expect(english.headline == "This week you used")
        #expect(english.shareHeadline == "This week I used")
        #expect(english.atStatsTitle.contains("1 command"))
        for language in ["de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hant"] {
            let text = WeekStatsText(stats.snapshot(for: .current), language: language)
            #expect(!text.headline.isEmpty)
            #expect(text.headline != chinese.headline)
            #expect(text.headline != english.headline)
            #expect(text.privacyNote != chinese.privacyNote)
        }
    }
}
