import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// New API assumed for this acceptance contract: WeekStats.recordTypedCharacters(_:) adds an
// already classified, nonnegative count without receiving text; Snapshot.charactersTyped is
// the week's sum; WeekStatsText.charactersTyped is the optional card/share line. The daily
// usage.json integer is named "charactersTyped". FakeHost exercises the actual commit path.
@Suite(.serialized)
struct WeekStatsCharactersTests {
    private final class Clock: @unchecked Sendable {
        var now: Date
        let calendar: Calendar

        init(_ day: String = "2026-11-10") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            calendar.firstWeekday = 2
            self.calendar = calendar
            now = Self.date(day, calendar: calendar)
        }

        func at(_ day: String) { now = Self.date(day, calendar: calendar) }
        func stats() -> WeekStats {
            WeekStats(now: { self.now }, calendar: calendar, salt: Data(repeating: 0xA7, count: 32))
        }

        private static func date(_ day: String, calendar: Calendar) -> Date {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
        }
    }

    private func host(_ stats: WeekStats, english: Bool = false, custom: [CustomCommand] = [],
                      autocomplete: Bool = false, model: AppleModelBackend? = nil,
                      uptime: @escaping () -> TimeInterval = { 1000 }) -> FakeHost {
        var config = Config.default
        config.uiLanguage = nil // withInterfaceLanguage owns the process-wide choice
        config.provider = .apple
        config.customCommands = custom
        config.autocomplete = autocomplete
        config.setOrder(english ? [Language.english] : [Language.chinese, .english])
        let fixed = config
        let engine = FakeEngine()
        var services = SessionServices(
            converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] },
                                 appleModel: model ?? OneAtAcceptanceTests.Model()),
            loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        services.weekStats = stats
        services.uptime = uptime
        let field = FakeHost(services: services)
        field.appTypesKeys = true
        field.focus()
        if english { field.composer.setInputMode(.english) }
        return field
    }

    @Test func chosenPinyinCountsCommittedHanziRatherThanKeysOrSelectionSpace() async {
        await withInterfaceLanguage("zh-Hans") {
            let stats = Clock().stats()
            let field = host(stats)
            field.type("nihao")
            #expect(stats.snapshot(for: .current).charactersTyped == 0, "uncommitted pinyin is not a typed character")
            field.press(FakeHost.space)
            #expect(field.document == "你好")
            #expect(stats.snapshot(for: .current).charactersTyped == 2)
            field.type("wo")
            field.press(FakeHost.space)
            #expect(field.document == "你好我")
            #expect(stats.snapshot(for: .current).charactersTyped == 3)
        }
    }

    @Test func englishLettersDigitsAndPunctuationCountButWhitespaceAndNewlinesDoNot() async {
        await withInterfaceLanguage("en") {
            let stats = Clock().stats()
            let field = host(stats, english: true)
            field.type("Ab3!?  ")
            field.press(FakeHost.enter)
            #expect(field.document.contains("Ab3!?"))
            #expect(stats.snapshot(for: .current).charactersTyped == 5)
        }
    }

    @Test func commandAndAIOutputSnippetAndClipboardPasteAddNoTypedCharacters() async throws {
        try await withInterfaceLanguage("en") {
            let stats = Clock().stats()
            let snippet = CustomCommand(name: "sig", type: .snippet, text: "Private signature 71382")
            let command = host(stats, english: true, custom: [snippet])
            command.type("@sig")
            command.press(FakeHost.enter)
            #expect(command.document.contains("Private signature 71382"))

            let ai = host(stats, english: true)
            ai.type("@please improve this sentence")
            ai.press(FakeHost.enter)
            #expect(ai.settle(timeout: 5) { stats.snapshot(for: .current).commandCount >= 2 })
            ai.press(FakeHost.enter)
            #expect(!ai.document.isEmpty)

            let paste = host(stats, english: true)
            paste.clipboard = .text("Private clipboard 52961")
            paste.keepClipboardHistory()
            paste.press(FakeHost.controlV)
            paste.press(FakeHost.enter)
            #expect(stats.snapshot(for: .current).charactersTyped == 0)
            let json = String(decoding: try stats.serializedData(), as: UTF8.self)
            #expect(!json.contains("Private signature 71382"))
            #expect(!json.contains("Private clipboard 52961"))
        }
    }

    @Test func acceptedAutocompleteAddsOnlyThePrefixActuallyTyped() async {
        await withInterfaceLanguage("en") {
            let stats = Clock().stats()
            let clock = Uptime()
            let field = host(stats, english: true, autocomplete: true,
                             model: ContinuingModel { _ in "ld, how are you? Fine." }, uptime: { clock.now })
            field.type("Hello wor")
            #expect(stats.snapshot(for: .current).charactersTyped == 8)
            clock.advance(0.2)
            field.fireTimers { if case .autocomplete = $0 { true } else { false } }
            #expect(field.settle(timeout: 5) { field.ghost == "ld, how are you?" })
            clock.advance(0.5)
            #expect(field.press(FakeHost.tab))
            #expect(field.document == "Hello world, how are you?")
            #expect(stats.snapshot(for: .current).charactersTyped == 8)
        }
    }

    @Test func secureInputDoesNotCountEvenWhenTheHostReceivesKeys() async {
        await withInterfaceLanguage("en") {
            let stats = Clock().stats()
            let field = host(stats, english: true)
            field.secure = true
            field.type("Secret123!")
            #expect(field.document.contains("Secret123!"))
            #expect(stats.snapshot(for: .current).charactersTyped == 0)
        }
    }

    @Test func keysPassedStraightToAnAppWithoutAnInputEngineAreNotCounted() async {
        await withInterfaceLanguage("en") {
            let stats = Clock().stats()
            var config = Config.default
            config.uiLanguage = nil
            let fixed = config
            var services = SessionServices(loadSettings: { fixed })
            services.levelOne = { .none }
            services.weekStats = stats
            let field = FakeHost(services: services)
            field.app = "com.example.passthrough"
            field.appTypesKeys = true
            field.focus()
            field.type("abc123!")
            #expect(field.document == "abc123!")
            #expect(stats.snapshot(for: .current).charactersTyped == 0)
        }
    }

    @Test func settingsTestRunProducesOutputWithoutAFieldCommitOrCharacterCount() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("week-stats-test-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configFile = root.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configFile)
        let service = SettingsService(store: SettingsStore(configURL: configFile), platform: .mac,
                                      library: PluginLibrary(directory: root.appendingPathComponent("plugins")))
        let definition: AIConfig.JSONValue = .object([
            "name": .string("shout"), "type": .string("run"),
            "argv": .array([.string("/usr/bin/tr"), .string("a-z"), .string("A-Z")]),
            "stdin": .string("{input}")
        ])
        try await service.perform(SettingsAction(field: "commands.custom", name: "save", value: definition)).get()
        let stats = Clock().stats()
        let result = try await service.perform(SettingsAction(field: "commands.custom", name: "test", item: "shout",
                                                              value: .string("private sample"))).get()
        #expect(result.message?.contains("PRIVATE SAMPLE") == true)
        #expect(stats.snapshot(for: .current).charactersTyped == 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("usage.json").path))
    }

    @Test func onlyOneIntegerPerLocalDayIsSerializedAndRestoredWithoutText() throws {
        let clock = Clock("2026-11-09")
        let stats = clock.stats()
        stats.recordTypedCharacters(7)
        clock.at("2026-11-10")
        stats.recordTypedCharacters(12)
        let data = try stats.serializedData()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let days = try #require(object["days"] as? [String: [String: Any]])
        #expect(days["2026-11-09"]?["charactersTyped"] as? Int == 7)
        #expect(days["2026-11-10"]?["charactersTyped"] as? Int == 12)
        #expect(!String(decoding: data, as: UTF8.self).contains("Secret123!"))
        #expect(!String(decoding: data, as: UTF8.self).contains("Private signature"))
        let restored = clock.stats()
        try restored.restore(from: data)
        #expect(restored.snapshot(for: .current).charactersTyped == 19)
    }

    @Test func localizedCardAndShareLineHasGroupingAndIsHiddenAtZeroOnBothTabs() {
        let clock = Clock("2026-11-08")
        let stats = clock.stats()
        #expect(WeekStatsText(stats.snapshot(for: .current), language: "zh-Hans").charactersTyped == nil)
        stats.recordTypedCharacters(12_340)
        clock.at("2026-11-10")
        #expect(WeekStatsText(stats.snapshot(for: .current), language: "en").charactersTyped == nil)
        let previous = stats.snapshot(for: .previous)
        #expect(previous.charactersTyped == 12_340)
        #expect(WeekStatsText(previous, language: "zh-Hans").charactersTyped == "打了 12,340 个字")
        #expect(WeekStatsText(previous, language: "en").charactersTyped == "12,340 characters typed")
        stats.recordTypedCharacters(12_340)
        let current = stats.snapshot(for: .current)
        #expect(WeekStatsText(current, language: "zh-Hans").charactersTyped == "打了 12,340 个字")
        #expect(WeekStatsText(current, language: "en").charactersTyped == "12,340 characters typed")
        #expect(!WeekStatsText(current, language: "en").menuBarRow.contains("12,340"))
        #expect(!WeekStatsText(current, language: "en").atStatsTitle.contains("12,340"))
        #expect(WeekStatsText(current, language: "zh-Hans").privacyNote == "统计只存在这台 Mac 上，不同步，也不上传。")
    }

    @Test func forgetClearsCharactersAndEightWeekRetentionPrunesTheirDays() throws {
        let clock = Clock("2026-09-20")
        let stats = clock.stats()
        stats.recordTypedCharacters(9)
        clock.at("2026-09-21")
        stats.recordTypedCharacters(11)
        clock.at("2026-11-10")
        stats.recordTypedCharacters(13)
        let json = String(decoding: try stats.serializedData(), as: UTF8.self)
        #expect(!json.contains("2026-09-20"))
        #expect(json.contains("2026-09-21"))
        #expect(json.contains("2026-11-10"))
        #expect(stats.snapshot(for: .current).charactersTyped == 13)
        stats.clearHistory()
        #expect(stats.snapshot(for: .current).charactersTyped == 0)
        #expect(stats.snapshot(for: .previous).charactersTyped == 0)
        #expect(WeekStatsText(stats.snapshot(for: .current), language: "en").charactersTyped == nil)
        let cleared = try #require(JSONSerialization.jsonObject(with: stats.serializedData()) as? [String: Any])
        #expect((cleared["days"] as? [String: Any])?.isEmpty == true)
    }
}
