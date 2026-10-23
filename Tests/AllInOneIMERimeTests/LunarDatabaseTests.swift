import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// rime-ice's lunar date database in the Rime user folder (`RimeService.prepareLunarDatabase`): copied from the shared
/// data, copied again when that changes (a language pack or app update), the user's own left alone, and never what keeps
/// pinyin from starting. The copying in folders of the test's own; starting librime in a process of its own each
/// (`RimeWorker`), since it starts once per process.
struct LunarDatabaseTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-lunar-\(UUID().uuidString)")
    var shared: URL { root.appendingPathComponent("shared") }
    var user: URL { root.appendingPathComponent("user") }
    var database: URL { user.appendingPathComponent("lua/lunar.db") }

    func sharedDatabase(_ text: String) throws {
        try FileManager.default.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: shared.appendingPathComponent("lua/lunar.db"))
    }

    func prepare() throws { try RimeService.prepareLunarDatabase(sharedDataDir: shared, userDataDir: user) }
    func copied() throws -> String { try String(contentsOf: database, encoding: .utf8) }

    @Test func aNewSharedDatabaseIsCopiedAgain() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try sharedDatabase("lunar 1")
        try prepare()
        #expect(try copied() == "lunar 1")
        try prepare()
        #expect(try copied() == "lunar 1")
        // The language pack (or the app) updated: the shared one changed.
        try sharedDatabase("lunar 2, a larger one")
        try prepare()
        #expect(try copied() == "lunar 2, a larger one")
        try sharedDatabase("lunar 3, as large")
        try prepare()
        #expect(try copied() == "lunar 3, as large")
    }

    @Test func theUsersOwnIsKeptWhenTheSharedOneChanges() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try sharedDatabase("lunar 1")
        try prepare()
        try Data("the user's own".utf8).write(to: database)
        try sharedDatabase("lunar 2")
        try prepare()
        #expect(try copied() == "the user's own")
        // One there before any copy was made: kept too.
        try FileManager.default.removeItem(at: user)
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("older, the user's".utf8).write(to: database)
        try prepare()
        #expect(try copied() == "older, the user's")
    }

    /// A copy an earlier build made, with no record of it: the shared one's bytes, so it is this app's, and kept current.
    @Test func anEarlierBuildsCopyIsTakenOver() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try sharedDatabase("lunar 1")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("lunar 1".utf8).write(to: database)
        try prepare()
        try sharedDatabase("lunar 2")
        try prepare()
        #expect(try copied() == "lunar 2")
    }

    /// Where the copy can't be made, or a link is there (even one to nothing): nothing thrown, nothing replaced; what
    /// went wrong is logged.
    @Test func whatCantBeCopiedIsOnlyLogged() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try sharedDatabase("lunar 1")
        let heard = Locked<[String]>(initialState: [])
        let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
        defer { stop() }
        // `lua` a file, not a folder.
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: user.appendingPathComponent("lua"))
        RimeService.supplyLunarDatabase(sharedDataDir: shared, userDataDir: user)
        #expect(try String(contentsOf: user.appendingPathComponent("lua"), encoding: .utf8) == "not a folder")
        #expect(heard.withLock { $0 }.contains { $0.contains("lunar date database not copied") })
        // A dangling link.
        try FileManager.default.removeItem(at: user.appendingPathComponent("lua"))
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: database.path, withDestinationPath: root.appendingPathComponent("gone").path)
        RimeService.supplyLunarDatabase(sharedDataDir: shared, userDataDir: user)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: database.path) == root.appendingPathComponent("gone").path)
    }

    /// librime starts, and pinyin works, though the database can't be copied; and a shared one that changes while it runs
    /// is copied again when it deploys again.
    @Test(.enabled(if: RimeWorker.scenario == nil && (RimeWorker.dataAvailable || RimeWorker.required)))
    func pinyinStartsWithoutItAndDeployingCopiesANewOne() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("lunar-unwritable", root: root.appendingPathComponent("unwritable"))
        try RimeWorker.run("lunar-redeploy", root: root.appendingPathComponent("redeploy"))
    }

    /// In a process of its own each (`RimeWorker`).
    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "lunar-unwritable": { root in
            // `lua` in the user folder a file: no database can go there.
            let user = root.appendingPathComponent("Rime")
            try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
            try Data("not a folder".utf8).write(to: user.appendingPathComponent("lua"))
            let service = RimeService.shared
            try service.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil)
            try #require(service.waitUntilReady(timeout: 120))
            let session = try #require(service.makeSession())
            for byte in "nihao".utf8 { _ = session.processKey(Int32(byte), mask: 0) }
            #expect(session.snapshot().candidates.contains { $0.text == "你好" })
        },
        "lunar-redeploy": { root in
            // The shared data as rime-ice's, but with a lunar database of the test's own to change.
            let fm = FileManager.default
            let shared = root.appendingPathComponent("shared"), user = root.appendingPathComponent("Rime")
            try fm.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
            for name in try fm.contentsOfDirectory(atPath: RimeFixture.sharedData.path) where name != "lua" {
                try fm.createSymbolicLink(at: shared.appendingPathComponent(name), withDestinationURL: RimeFixture.sharedData.appendingPathComponent(name))
            }
            let lua = RimeFixture.sharedData.appendingPathComponent("lua")
            for name in try fm.contentsOfDirectory(atPath: lua.path) where name != "lunar.db" {
                try fm.createSymbolicLink(at: shared.appendingPathComponent("lua/" + name), withDestinationURL: lua.appendingPathComponent(name))
            }
            let original = try Data(contentsOf: lua.appendingPathComponent("lunar.db"))
            try original.write(to: shared.appendingPathComponent("lua/lunar.db"))
            let service = RimeService.shared
            try service.start(sharedDataDir: shared, userDataDir: user, logDir: nil)
            try #require(service.waitUntilReady(timeout: 120))
            let copy = user.appendingPathComponent("lua/lunar.db")
            #expect(try Data(contentsOf: copy) == original)
            // A language pack update: the shared database changes, and Rime deploys again.
            let updated = original + Data("update".utf8)
            try updated.write(to: shared.appendingPathComponent("lua/lunar.db"))
            service.redeploy()
            try #require(service.waitUntilReady(timeout: 120))
            #expect(try Data(contentsOf: copy) == updated)
        },
    ]
}

