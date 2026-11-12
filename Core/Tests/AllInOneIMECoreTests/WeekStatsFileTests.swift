import Foundation
import Testing
@testable import AllInOneIMECore

/// This week's stats read back from files of other versions: 0.7.4's first builds' (version 1: each command's source with
/// its runs, the salt in the file) with every count, the apps too, the salt left in the file until the shell keeps it
/// apart; a later version's refused, so that this one never writes over it with less. And a file read while the shell
/// can't read the salt it keeps: its apps kept as they are.
struct WeekStatsFileTests {
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Tuesday, 10 November 2026, noon.
    private static let today = calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!

    private static func stats(salt: Data? = nil) -> WeekStats {
        WeekStats(now: { today }, calendar: calendar(), salt: salt)
    }

    /// The hash `salt` makes of `bundleID`, as a file has it.
    private static func appHash(_ bundleID: String, salt: Data) throws -> String {
        let stats = stats(salt: salt)
        stats.recordCommand(id: "x", source: .builtIn, bundleID: bundleID, usedAI: false)
        let object = try #require(JSONSerialization.jsonObject(with: stats.serializedData()) as? [String: Any])
        let days = try #require(object["days"] as? [String: [String: Any]])
        return try #require((days["2026-11-10"]?["apps"] as? [String])?.first)
    }

    /// A file of version 1, as 0.7.4's first builds wrote it, its apps hashed with `salt`: last week's Tuesday and this
    /// week's Monday.
    static func firstBuildsFile(salt: Data, app: String) -> Data {
        Data("""
        {"days":{"2026-11-03":{"apps":["\(app)"],"charactersTyped":15,"clipboardPastes":1,\
        "commands":{"improve":{"ai":2,"runs":2,"source":"builtIn"}}},\
        "2026-11-09":{"apps":["\(app)"],"charactersTyped":40,"clipboardPastes":2,\
        "commands":{"bar":{"ai":0,"runs":1,"source":"plugin"},"foo":{"ai":1,"runs":3,"source":"own"}}}},\
        "salt":"\(salt.base64EncodedString())","since":"2026-11-03","version":1}
        """.utf8)
    }

    /// Every count of a file of version 1 is read: the commands with their sources and AI runs, the pastes, the
    /// characters, the first day, and the apps, by the file's salt, which hashes them from then on. Written again, it is
    /// this version's, the salt in it until the shell keeps it apart, then without it; read back with that salt, the same.
    @Test func aFileOfTheFirstBuildsKeepsEveryCount() throws {
        let salt = Data((0..<32).map { UInt8(255 - $0) })
        let app = try Self.appHash("com.example.editor", salt: salt)
        let stats = Self.stats()
        #expect(try stats.restore(from: Self.firstBuildsFile(salt: salt, app: app)), "an earlier version: written again")
        #expect(stats.salt == salt)

        let week = stats.snapshot(for: .current)
        #expect(week.commandCount == 4)
        #expect(week.aiCommandCount == 1)
        #expect(week.sourceCounts == WeekStats.Snapshot.SourceCounts(own: 3, builtIn: 0, plugin: 1))
        #expect(week.topCommands.map { "\($0.id)/\($0.source)/\($0.count)" } == ["foo/own/3", "bar/plugin/1"])
        #expect(week.distinctAppCount == 1)
        #expect(week.clipboardPasteCount == 2)
        #expect(week.charactersTyped == 40)
        #expect(!week.isFirstWeek)
        let last = stats.snapshot(for: .previous)
        #expect(last.topCommands.map { "\($0.id)/\($0.source)/\($0.count)" } == ["improve/builtIn/2"])
        #expect(last.aiCommandCount == 2)
        #expect(last.charactersTyped == 15)
        #expect(stats.snapshot(for: .current).firstRecordedDay == Self.calendar().date(from: DateComponents(year: 2026, month: 11, day: 3)))

        stats.recordCommand(id: "foo", source: .own, bundleID: "com.example.editor", usedAI: false)
        #expect(stats.snapshot(for: .current).distinctAppCount == 1, "the same app, by the file's salt")

        let carrying = try #require(JSONSerialization.jsonObject(with: stats.serializedData()) as? [String: Any])
        #expect(carrying["version"] as? Int == 2)
        #expect(carrying["salt"] as? String == salt.base64EncodedString(), "until the shell keeps it apart")
        let lost = Self.stats()
        #expect(try lost.restore(from: stats.serializedData()), "carrying its salt: written again")
        #expect(lost.salt == salt && lost.snapshot(for: .current).distinctAppCount == 1)

        #expect(stats.keptApart(Self.stats().salt) == false, "another salt")
        #expect(stats.keptApart(salt), "written again, without it")
        #expect(stats.keptApart(salt) == false)
        let data = try stats.serializedData()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 2)
        #expect(object["salt"] == nil)
        #expect(!String(decoding: data, as: UTF8.self).contains(salt.base64EncodedString()))
        let again = Self.stats(salt: salt)
        #expect(try again.restore(from: data) == false)
        #expect(again.snapshot(for: .current) == stats.snapshot(for: .current))
        #expect(again.snapshot(for: .previous) == stats.snapshot(for: .previous))
    }

    /// The shell couldn't read the salt it keeps: the apps of the file read then are kept as they are (none dropped for
    /// this one's salt, none added), written back with the same hashes and the same `saltCheck`, and no salt is given to
    /// be kept; read back by the salt they were made with, every app is there. Forget All ends it: a new salt, kept.
    @Test func whileTheSaltIsUnreadTheFilesAppsAreKeptAsTheyAre() throws {
        let salt = Data((0..<32).map { UInt8($0) })
        let before = Self.stats(salt: salt)
        before.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.editor", usedAI: true)
        before.recordCommand(id: "sig", source: .own, bundleID: "com.example.mail", usedAI: false)
        let file = try before.serializedData()

        let unread = Self.stats()
        unread.saltUnread()
        #expect(!unread.countsApps)
        #expect(try unread.restore(from: file) == false)
        #expect(unread.snapshot(for: .current).distinctAppCount == 2, "none dropped")
        unread.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.notes", usedAI: true)
        #expect(unread.snapshot(for: .current).distinctAppCount == 2, "none added")
        #expect(unread.snapshot(for: .current).commandCount == 3)
        let (kept, given) = try unread.kept()
        #expect(given == nil, "no salt to keep")
        let data = try #require(kept)
        let written = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let read = try #require(JSONSerialization.jsonObject(with: file) as? [String: Any])
        #expect(written["saltCheck"] as? String == read["saltCheck"] as? String)
        #expect(written["salt"] == nil)
        let apps = { (object: [String: Any]) in (object["days"] as? [String: [String: Any]])?["2026-11-10"]?["apps"] as? [String] }
        #expect(apps(written) == apps(read) && apps(read)?.count == 2)

        let recovered = Self.stats(salt: salt)
        try recovered.restore(from: data)
        #expect(recovered.snapshot(for: .current).distinctAppCount == 2)
        #expect(recovered.snapshot(for: .current).commandCount == 3)

        unread.clearHistory()
        unread.recordCommand(id: "sig", source: .own, bundleID: nil, usedAI: false)
        #expect(try unread.kept().salt == unread.salt, "a new salt, to keep")
        #expect(!unread.countsApps, "still none this run")
    }

    /// A file of a later version isn't read (this one would write it again with less); nothing counted is changed.
    @Test func aFileOfALaterVersionIsNotRead() throws {
        let stats = Self.stats()
        stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true)
        let later = Data(#"{"version":3,"days":{"2026-11-10":{"commands":{"own":{"sig":{"runs":5,"ai":0}}}}}}"#.utf8)
        #expect(throws: WeekStats.LaterVersion.self) { try stats.restore(from: later) }
        #expect(stats.snapshot(for: .current).topCommands.map(\.id) == ["improve"])
        #expect(throws: (any Error).self) { try stats.restore(from: Data(#"{"version":2,"days":{"2026-11-10":{"commands":7}}}"#.utf8)) }
    }
}
