import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime
#if canImport(Darwin)
import Darwin
#endif

/// rime-ice's lunar date database in the Rime user folder (`RimeService.prepareLunarDatabase`): copied from the shared
/// data, copied again when that changes (a language pack or app update), the user's own left alone, and never what keeps
/// pinyin from starting. The copying in folders of the test's own; starting librime in a process of its own each
/// (`LunarDatabaseWorker`), since it starts once per process.
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
    @Test(.enabled(if: LunarDatabaseWorker.scenario == nil && (LunarDatabaseWorker.dataAvailable || LunarDatabaseWorker.required)))
    func pinyinStartsWithoutItAndDeployingCopiesANewOne() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try LunarDatabaseWorker.run("unwritable", root: root.appendingPathComponent("unwritable"))
        try LunarDatabaseWorker.run("redeploy", root: root.appendingPathComponent("redeploy"))
    }
}

/// The scenarios run in a copy of the test process each (`LunarDatabaseWorkerTests`).
enum LunarDatabaseWorker {
    static let scenarioKey = "ALLINONEIME_LUNAR_WORKER"
    static let rootKey = "ALLINONEIME_LUNAR_WORKER_ROOT"
    static var scenario: String? { ProcessInfo.processInfo.environment[scenarioKey] }
    static var dataAvailable: Bool {
        FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent("build/rime_ice.table.bin").path)
    }
    static var required: Bool { RimeFixture.dataRequired }

    static func run(_ scenario: String, root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("output.txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(CommandLine.arguments.first))
        // As PersonalDictionaryRimeAcceptanceTests runs its workers: the test bundle's argument kept, if there is one.
        if let bundle = CommandLine.arguments.firstIndex(of: "--test-bundle-path"), bundle + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[bundle + 1]
            process.arguments = ["--test-bundle-path", path, "--filter", "LunarDatabaseWorkerTests", path, "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "LunarDatabaseWorkerTests"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment[scenarioKey] = scenario
        environment[rootKey] = root.path
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(240)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        try #require(process.terminationReason == .exit && process.terminationStatus == 0, "\(scenario):\n\(text)")
        try #require(text.contains("LUNAR_WORKER_FINISHED:\(scenario)"), "\(scenario) didn't run:\n\(text)")
    }
}

@Suite(.serialized, .enabled(if: LunarDatabaseWorker.scenario != nil))
struct LunarDatabaseWorkerTests {
    @Test func runScenario() throws {
        let scenario = try #require(LunarDatabaseWorker.scenario)
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[LunarDatabaseWorker.rootKey]))
        let user = root.appendingPathComponent("Rime")
        let service = RimeService.shared
        switch scenario {
        case "unwritable":
            // `lua` in the user folder a file: no database can go there.
            try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
            try Data("not a folder".utf8).write(to: user.appendingPathComponent("lua"))
            try service.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil)
            try #require(service.waitUntilReady(timeout: 120))
            let session = try #require(service.makeSession())
            for byte in "nihao".utf8 { _ = session.processKey(Int32(byte), mask: 0) }
            #expect(session.snapshot().candidates.contains { $0.text == "你好" })
        case "redeploy":
            // The shared data as rime-ice's, but with a lunar database of the test's own to change.
            let shared = root.appendingPathComponent("shared")
            try FileManager.default.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
            let fm = FileManager.default
            for name in try fm.contentsOfDirectory(atPath: RimeFixture.sharedData.path) where name != "lua" {
                try fm.createSymbolicLink(at: shared.appendingPathComponent(name), withDestinationURL: RimeFixture.sharedData.appendingPathComponent(name))
            }
            let lua = RimeFixture.sharedData.appendingPathComponent("lua")
            for name in try fm.contentsOfDirectory(atPath: lua.path) where name != "lunar.db" {
                try fm.createSymbolicLink(at: shared.appendingPathComponent("lua/" + name), withDestinationURL: lua.appendingPathComponent(name))
            }
            let original = try Data(contentsOf: lua.appendingPathComponent("lunar.db"))
            try original.write(to: shared.appendingPathComponent("lua/lunar.db"))
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
        default:
            Issue.record("unknown scenario \(scenario)")
        }
        print("LUNAR_WORKER_FINISHED:\(scenario)")
    }
}
