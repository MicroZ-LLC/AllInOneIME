import Foundation
import Testing
import AllInOneIMECore
@testable import AllInOneIMEMac

// Proposed Mac API: WeekStatsStore(applicationSupportDirectory:now:) owns a shared Core
// WeekStats recorder at `stats`, writes pending records off the key path with `flush()`, and
// clears them with `clearHistory()`. `fileURL` and `defaultURL` expose the local path for tests.
// The directory argument is ~/Library/Application Support in production; tests substitute a
// private temporary directory and never touch the user's usage or config files.
@Suite(.serialized)
struct WeekStatsStoreTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func storeIsPrivateInApplicationSupportAndClearHistoryDeletesIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("week-stats-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Date(timeIntervalSince1970: 1_794_314_400)
        let store = WeekStatsStore(applicationSupportDirectory: root, now: { clock })
        let file = root.appendingPathComponent("AllInOneIME/usage.json")
        #expect(store.fileURL == file)
        #expect(WeekStatsStore.defaultURL == FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME/usage.json"))

        store.stats.recordCommand(name: "improve")
        try await store.flush()
        #expect(FileManager.default.fileExists(atPath: file.path))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("improve"))
        #expect(!saved.contains("config.json"))
        #expect(!file.path.contains("Mobile Documents"))

        try await store.clearHistory()
        #expect(store.stats.snapshot().commandCount == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func statsCodeHasNoNetworkCallSite() throws {
        // A source-level guard complements the store test: recording and writing a local JSON
        // file must not gain a network path. Check the dedicated Core and Mac stats sources.
        let files = [
            Self.repository.appendingPathComponent("Core/Sources/AllInOneIMECore/WeekStats.swift"),
            Self.repository.appendingPathComponent("Sources/AllInOneIMEMac/WeekStatsStore.swift"),
        ]
        for file in files {
            #expect(FileManager.default.fileExists(atPath: file.path), "Missing stats source: \(file.path)")
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbidden in ["URLSession", "URLRequest", "NWConnection", "Network.framework",
                              "NSURLConnection", "CFHTTP", "http://", "https://"] {
                #expect(!source.contains(forbidden), "Stats source has a network call site: \(forbidden)")
            }
        }
    }
}
