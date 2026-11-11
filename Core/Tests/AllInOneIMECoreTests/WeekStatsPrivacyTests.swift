import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// This week's stats as the review of 0.7.4 found them wanting: what is kept of the user's own commands and the apps'
/// salt, nothing counted where nothing may leave the device, Forget All with requests still waiting, the same name from
/// two sources, and `@stats`'s ⌘C saying it copied only once it did.
@Suite(.serialized)
struct WeekStatsPrivacyTests {
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
        func stats(salt: Data = Data(repeating: 0xA7, count: 32)) -> WeekStats {
            WeekStats(now: { self.now }, calendar: calendar, salt: salt)
        }

        private static func date(_ day: String, calendar: Calendar) -> Date {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
        }
    }

    /// A program's answer held back until the test lets it go (`open`).
    private final class Gate: @unchecked Sendable {
        private let opened = DispatchSemaphore(value: 0)

        func open() { opened.signal() }

        func printing(_ text: String) -> AsyncThrowingStream<ConversionUpdate, Error> {
            AsyncThrowingStream { continuation in
                DispatchQueue.global().async {
                    self.opened.wait()
                    continuation.yield(ConversionUpdate(result: ConversionResult(versions: [CandidateLine(text)]), rawText: text,
                                                        isFinal: true, elapsed: 0.1, firstTokenLatency: nil, fromCache: false))
                    continuation.finish()
                }
            }
        }
    }

    /// A field (English) counting into `stats`, with the user's own `custom` commands; secure input elsewhere is
    /// `secure`'s, a program's answer `gate`'s when given (else at once).
    private func field(_ stats: WeekStats, custom: [CustomCommand] = [], secure: Bool = false, gate: Gate? = nil) -> FakeHost {
        var config = Config.default
        config.uiLanguage = nil  // withInterfaceLanguage's
        config.customCommands = custom
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.weekStats = stats
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.secureInputActive = { secure }
        services.runProgram = { _, input in
            gate?.printing(input.uppercased()) ?? AsyncThrowingStream { continuation in
                continuation.yield(ConversionUpdate(result: ConversionResult(versions: [CandidateLine(input.uppercased())]),
                                                    rawText: input.uppercased(), isFinal: true, elapsed: 0.1,
                                                    firstTokenLatency: nil, fromCache: false))
                continuation.finish()
            }
        }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    private static let shout = CustomCommand(name: "shout", type: .run, argv: ["/usr/bin/tr", "a-z", "A-Z"])

    // MARK: 1. What is kept

    /// A command of the user's own deleted or renamed: its name leaves the file, its runs stay in every total.
    @Test func aDeletedOrRenamedOwnCommandKeepsItsRunsButNotItsName() throws {
        let clock = Clock("2026-11-09")
        let stats = clock.stats()
        for _ in 0..<3 { stats.recordCommand(id: "oncology_results", source: .own, bundleID: "com.example.a", usedAI: true) }
        stats.recordCommand(id: "oncology_results", source: .plugin, bundleID: nil, usedAI: false)
        clock.at("2026-11-10")
        stats.recordCommand(id: "oncology_results", source: .own, bundleID: nil, usedAI: false)
        stats.recordCommand(id: "sig", source: .own, bundleID: nil, usedAI: false)
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true)
        let before = stats.snapshot(for: .current)
        #expect(before.topCommands.contains { $0.id == "oncology_results" && $0.source == .own })

        stats.keepCommands(["sig"], from: .own)  // deleted (or renamed) in Settings → Commands
        let after = stats.snapshot(for: .current)
        #expect(after.commandCount == before.commandCount)
        #expect(after.aiCommandCount == before.aiCommandCount)
        #expect(after.sourceCounts == before.sourceCounts)
        #expect(after.days.map(\.commandCount) == before.days.map(\.commandCount))
        #expect(after.distinctAppCount == before.distinctAppCount)
        #expect(!after.topCommands.contains { $0.id == "oncology_results" && $0.source == .own })
        #expect(after.topCommands.contains { $0.id == "oncology_results" && $0.source == .plugin }, "a plugin's name stays")
        #expect(after.otherCommands.total == 4)
        let shown = after.topCommands.reduce(0) { $0 + $1.count } + after.otherCommands.total
        #expect(shown == after.commandCount)
        let json = String(decoding: try stats.serializedData(), as: UTF8.self)
        #expect(json.components(separatedBy: "oncology_results").count == 2, "only the plugin's, on Monday")

        // Read back, the same; told again, nothing changes.
        let restored = clock.stats()
        try restored.restore(from: stats.serializedData())
        restored.keepCommands(["sig"], from: .own)
        #expect(restored.snapshot(for: .current) == after)
    }

    /// The salt the apps are hashed with is never in the file, only which one it was: hashes of another (the salt lost)
    /// are dropped, the rest kept; Forget All gives a new one.
    @Test func theSaltIsNeverKeptWithTheCounts() throws {
        let salt = Data((0..<32).map { UInt8($0) })
        let clock = Clock()
        let stats = clock.stats(salt: salt)
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.editor", usedAI: true)
        stats.recordTypedCharacters(12)
        #expect(stats.salt == salt)
        let data = try stats.serializedData()
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains(salt.base64EncodedString()))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["salt"] == nil)
        #expect(object["saltCheck"] is String)

        let same = clock.stats(salt: salt)
        try same.restore(from: data)
        #expect(same.snapshot(for: .current).distinctAppCount == 1)
        let other = clock.stats(salt: Data(repeating: 1, count: 32))
        try other.restore(from: data)
        #expect(other.snapshot(for: .current).distinctAppCount == 0, "hashes of another salt start again")
        #expect(other.snapshot(for: .current).commandCount == 1)
        #expect(other.snapshot(for: .current).charactersTyped == 12)

        stats.clearHistory()
        #expect(stats.salt != salt)
        #expect(try stats.kept().data == nil, "nothing counted: no file")
    }

    // MARK: 2. Where nothing may leave the device

    /// In a field told to be a password field (secure input off), and during secure input, a command run counts nothing:
    /// not the command, not the app.
    @Test func aKnownPasswordFieldOrSecureInputCountsNoCommand() async {
        await withInterfaceLanguage("en") {
            let stats = Clock().stats()
            let password = field(stats)
            password.send(.passwordField(true, focus: password.session.fieldSession))
            #expect(password.session.nothingLeavesDevice())
            password.type("@settings")
            password.press(FakeHost.enter)
            #expect(password.settingsOpened.count == 1, "the command still runs")
            #expect(stats.snapshot(for: .current).commandCount == 0)
            #expect(stats.snapshot(for: .current).distinctAppCount == 0)

            let secure = field(stats, secure: true)
            secure.type("@settings")
            secure.press(FakeHost.enter)
            #expect(stats.snapshot(for: .current).commandCount == 0)

            let plain = field(stats)
            plain.type("@settings")
            plain.press(FakeHost.enter)
            #expect(stats.snapshot(for: .current).commandCount == 1)
            #expect(stats.snapshot(for: .current).distinctAppCount == 1)
        }
    }

    /// A run whose request is waiting when the field turns out to be a password field isn't counted when it answers.
    @Test func aRunAnsweredInAFieldNothingMayLeaveIsNotCounted() async {
        await withInterfaceLanguage("en") {
            let stats = Clock().stats()
            let gate = Gate()
            let host = field(stats, custom: [Self.shout], gate: gate)
            host.type("@shout hello")
            host.press(FakeHost.enter)
            #expect(!host.session.weekStatsRuns.pending.isEmpty)
            host.send(.passwordField(true, focus: host.session.fieldSession))
            gate.open()
            #expect(host.settle(timeout: 5) { host.session.weekStatsRuns.pending.isEmpty })
            #expect(stats.snapshot(for: .current).commandCount == 0)
        }
    }

    // MARK: 3. Forget All with a request waiting

    /// Forget All while a command's request hasn't answered: the late answer adds nothing to the counts forgotten.
    @Test func forgetAllDropsTheRunsStillWaiting() async {
        await withInterfaceLanguage("en") {
            for forget in [false, true] {
                let stats = Clock().stats()
                let gate = Gate()
                let host = field(stats, custom: [Self.shout], gate: gate)
                host.type("@shout hello")
                host.press(FakeHost.enter)
                #expect(stats.snapshot(for: .current).commandCount == 0, "counted once it answers")
                if forget { stats.clearHistory() }
                gate.open()
                #expect(host.settle(timeout: 5) { host.session.weekStatsRuns.pending.isEmpty })
                #expect(stats.snapshot(for: .current).commandCount == (forget ? 0 : 1))
                #expect((stats.snapshot(for: .current).firstRecordedDay == nil) == forget)
            }
        }
    }

    /// The same at the counts: a run that started before a clear isn't counted after it.
    @Test func aRunFromBeforeAClearIsNotCounted() {
        let stats = Clock().stats()
        let era = stats.era
        stats.clearHistory()
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.editor", usedAI: true, era: era)
        #expect(stats.snapshot(for: .current).commandCount == 0)
        #expect(!stats.hasCommands)
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true, era: stats.era)
        #expect(stats.snapshot(for: .current).commandCount == 1)
    }

    // MARK: 5. The same name from two sources

    /// A command of the user's own and a plugin's of the same name are counted apart, on one day and across days, and
    /// the week ranks each with its own source.
    @Test func theSameNameFromTwoSourcesIsCountedApart() {
        let clock = Clock("2026-11-09")
        let stats = clock.stats()
        for _ in 0..<3 { stats.recordCommand(id: "foo", source: .own, bundleID: nil, usedAI: false) }
        clock.at("2026-11-10")
        stats.recordCommand(id: "foo", source: .plugin, bundleID: nil, usedAI: false)
        let week = stats.snapshot(for: .current)
        #expect(week.sourceCounts.own == 3)
        #expect(week.sourceCounts.plugin == 1)
        #expect(week.topCommands.map { "\($0.id)/\($0.source)/\($0.count)" } == ["foo/own/3", "foo/plugin/1"])
        #expect(week.shareCommands(hideOwnCommandNames: true, language: "en").map(\.displayName) == ["My command 1", "@foo"])

        // Both on one day: still two.
        stats.recordCommand(id: "foo", source: .own, bundleID: nil, usedAI: false)
        #expect(stats.snapshot(for: .current).topCommands.map { "\($0.id)/\($0.source)/\($0.count)" } ==
                ["foo/own/4", "foo/plugin/1"])
    }

    // MARK: 6. @stats's ⌘C

    /// ⌘C on `@stats`'s row asks the shell for the picture and says nothing yet; the shell's answer says it's copied, or
    /// that it couldn't be.
    @Test func atStatsSaysCopiedOnlyOnceThePictureIsThere() async {
        await withInterfaceLanguage("zh-Hans") {
            let stats = Clock().stats()
            stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true)
            let host = field(stats)
            host.type("@stats")
            #expect(host.press(KeyEvent(keyCode: 0x08, characters: "c", charactersIgnoringModifiers: "c", modifiers: .command)))
            #expect(host.platformActions.contains(.copyWeekStatsImage))
            #expect(!host.outputs.contains { output in
                switch output {
                case let .notice(text): return text == "已复制图片"
                case let .panel(model): return model?.detail == "已复制图片"
                default: return false
                }
            }, "not before the shell says the picture is there")
            #expect(host.session.weekStatsImageCopied(false).contains(.notice("无法复制图片")))
            #expect(host.session.weekStatsImageCopied(true).contains(.notice("已复制图片")))
        }
    }
}
