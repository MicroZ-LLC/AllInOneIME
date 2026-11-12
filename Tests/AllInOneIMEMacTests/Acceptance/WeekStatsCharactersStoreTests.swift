import AppKit
import Foundation
import Testing
import AllInOneIMECore
@testable import AllInOneIMEMac

@Suite(.serialized)
struct WeekStatsCharactersStoreTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        value.firstWeekday = 2
        return value
    }

    @Test func countLivesInThePrivateUsageFileAndForgetRemovesIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("week-stats-characters-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instant = Self.calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let store = WeekStatsStore(applicationSupportDirectory: root, now: { instant }, calendar: Self.calendar())
        store.stats.recordTypedCharacters(12_340)
        try await store.flush()
        let file = root.appendingPathComponent("AllInOneIME/usage.json")
        let saved = try Data(contentsOf: file)
        let object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let days = try #require(object["days"] as? [String: [String: Any]])
        #expect(days["2026-11-10"]?["charactersTyped"] as? Int == 12_340)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("AllInOneIME/config.json").path))
        let reopened = WeekStatsStore(applicationSupportDirectory: root, now: { instant }, calendar: Self.calendar())
        #expect(reopened.stats.snapshot(for: .current).charactersTyped == 12_340)
        try await store.clearHistory()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func pageAndShareCardUseTheLocalizedCharacterLine() throws {
        let instant = Self.calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let stats = WeekStats(now: { instant }, calendar: Self.calendar())
        stats.recordTypedCharacters(12_340)
        let week = stats.snapshot(for: .current)
        let page = WeekStatsCard(week: week, language: "zh-Hans", style: .page)
        let share = WeekStatsCard(week: week, language: "en", style: .share)
        #expect(page.text.charactersTyped == "打了 12,340 个字")
        #expect(share.text.charactersTyped == "12,340 characters typed")
        let source = try String(contentsOf: Self.repository.appendingPathComponent("Sources/AllInOneIMEMac/WeekStatsCard.swift"),
                                encoding: .utf8)
        #expect(source.contains("text.charactersTyped"), "the rendered page and image both need the line")
        if let activity = source.range(of: "text.activity"), let characters = source.range(of: "text.charactersTyped"),
           let bars = source.range(of: "drawBars(", range: characters.upperBound..<source.endIndex) {
            #expect(activity.lowerBound < characters.lowerBound && characters.lowerBound < bars.lowerBound)
        }
        let png = try WeekStatsShareImage.render(week: week, language: "en", hideOwnCommandNames: false,
                                                 appearance: .light)
        #expect(!png.isEmpty)
    }

    @Test func readmeAndUserGuideExplainThatOnlyTheCharacterNumberIsKept() throws {
        let english = try String(contentsOf: Self.repository.appendingPathComponent("README.md"), encoding: .utf8)
        let chinese = try String(contentsOf: Self.repository.appendingPathComponent("README.zh-CN.md"), encoding: .utf8)
        let guide = try String(contentsOf: Self.repository.appendingPathComponent("Resources/user-guide.md"), encoding: .utf8)
        let englishStats = try #require(english.components(separatedBy: "## This week's stats").last?.components(separatedBy: "\n## ").first)
        let chinesePrivacy = try #require(chinese.components(separatedBy: "- 本周统计（设置").last?.components(separatedBy: "\n-").first)
        let guideStats = try #require(guide.components(separatedBy: "## This week's stats").last?.components(separatedBy: "\n## ").first)
        #expect(englishStats.localizedCaseInsensitiveContains("characters") && englishStats.localizedCaseInsensitiveContains("number"))
        #expect(chinesePrivacy.contains("字") && chinesePrivacy.contains("数字"))
        #expect(guideStats.localizedCaseInsensitiveContains("characters") && guideStats.localizedCaseInsensitiveContains("number"))
    }
}
