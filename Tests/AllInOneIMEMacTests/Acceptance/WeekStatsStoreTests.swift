import AppKit
import Foundation
import ImageIO
import Testing
import AllInOneIMECore
@testable import AllInOneIMEMac

// Assumed Mac API: WeekStatsStore(applicationSupportDirectory:now:calendar:)
// owns stats, fileURL and defaultURL, flushes writes off the key path, and removes
// usage.json on clearHistory(). WeekStatsShareImage.render/copy produces PNG at
// 640×540 points, 2×. WeekStatsMenuBar.row(stats:language:) is hidden until a
// command runs and navigates to SettingsPlace.weekStats. The page's hideOwnCommandNames
// flag lives in WeekStatsPagePreferences(defaults:), outside config.json.
@Suite(.serialized)
struct WeekStatsStoreTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static func calendar() -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        result.firstWeekday = 2
        return result
    }

    private static func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("week-stats-acceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func usageFileIsPrivateLocalAndClearHistoryDeletesIt() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let instant = Self.calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let store = WeekStatsStore(applicationSupportDirectory: root, now: { instant }, calendar: Self.calendar())
        let file = root.appendingPathComponent("AllInOneIME/usage.json")
        #expect(store.fileURL == file)
        #expect(WeekStatsStore.defaultURL == FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME/usage.json"))

        store.stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.private.editor", usedAI: true)
        try await store.flush()
        #expect(FileManager.default.fileExists(atPath: file.path))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("improve"))
        #expect(!saved.contains("com.private.editor"))
        #expect(!file.path.contains("Mobile Documents"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("AllInOneIME/config.json").path))

        try await store.clearHistory()
        #expect(store.stats.snapshot(for: .current).commandCount == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func shareCardAndClipboardArePNGAtTwoTimesCanvasSize() throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let instant = Self.calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let store = WeekStatsStore(applicationSupportDirectory: root, now: { instant }, calendar: Self.calendar())
        store.stats.recordCommand(id: "sig", source: .own, bundleID: nil, usedAI: false)
        let week = store.stats.snapshot(for: .current)

        for appearance in [WeekStatsShareImage.Appearance.light, .dark] {
            let png = try WeekStatsShareImage.render(
                week: week, language: "zh-Hans", hideOwnCommandNames: true, appearance: appearance)
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(CGImageSourceGetType(source) as String? == "public.png")
            #expect(image.width == 1280)
            #expect(image.height == 1080)
            let destination = root.appendingPathComponent("shared-\(appearance).png")
            try png.write(to: destination)
            #expect(try Data(contentsOf: destination) == png)
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("week-stats-acceptance-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try WeekStatsShareImage.copy(week: week, language: "zh-Hans",
                                     hideOwnCommandNames: true, appearance: .light, to: pasteboard)
        let copied = try #require(pasteboard.data(forType: .png))
        let copiedSource = try #require(CGImageSourceCreateWithData(copied as CFData, nil))
        let copiedImage = try #require(CGImageSourceCreateImageAtIndex(copiedSource, 0, nil))
        #expect(copiedImage.width == 1280)
        #expect(copiedImage.height == 1080)
    }

    @Test func menuBarRowAppearsOnlyAfterFirstCommandAndOpensTheWeekPage() throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let instant = Self.calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let store = WeekStatsStore(applicationSupportDirectory: root, now: { instant }, calendar: Self.calendar())
        #expect(WeekStatsMenuBar.row(stats: store.stats, language: "zh-Hans") == nil)
        store.stats.recordClipboardPaste()
        #expect(WeekStatsMenuBar.row(stats: store.stats, language: "zh-Hans") == nil)
        store.stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true)
        let row = try #require(WeekStatsMenuBar.row(stats: store.stats, language: "zh-Hans"))
        #expect(row.title.contains("本周 1 次指令"))
        #expect(row.destination == .weekStats)
        store.stats.clearHistory()
        #expect(WeekStatsMenuBar.row(stats: store.stats, language: "zh-Hans") == nil)
    }

    @Test func hideOwnNamesPreferenceSurvivesPageReopenOutsideConfig() throws {
        let suite = "week-stats-acceptance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = WeekStatsPagePreferences(defaults: defaults)
        #expect(first.hideOwnCommandNames == false)
        first.hideOwnCommandNames = true
        #expect(WeekStatsPagePreferences(defaults: defaults).hideOwnCommandNames == true)
        #expect(defaults.dictionaryRepresentation()["customCommands"] == nil)
    }

    @Test func statsSourcesHaveNoNetworkOrCloudSyncCallSite() throws {
        let files = [
            Self.repository.appendingPathComponent("Core/Sources/AllInOneIMECore/WeekStats.swift"),
            Self.repository.appendingPathComponent("Sources/AllInOneIMEMac/WeekStatsStore.swift"),
            Self.repository.appendingPathComponent("Sources/AllInOneIMEMac/WeekStatsShareImage.swift"),
        ]
        for file in files {
            #expect(FileManager.default.fileExists(atPath: file.path), "Missing stats source: \(file.path)")
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbidden in ["URLSession", "URLRequest", "NWConnection", "NSURLConnection",
                              "CFHTTP", "CKContainer", "NSUbiquitousKeyValueStore",
                              "Mobile Documents", "config.json"] {
                #expect(!source.contains(forbidden), "Stats source contains network, sync or config access: \(forbidden)")
            }
        }
    }
}
