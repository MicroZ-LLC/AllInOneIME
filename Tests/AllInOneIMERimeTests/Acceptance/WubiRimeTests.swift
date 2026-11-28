import AllInOneIMECore
@testable import AllInOneIMERime
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// Real librime acceptance for Wubi 86 (issue #187), independent of the implementation.
// Assumed API: PinyinScheme.wubi (schema "wubi86"); FuzzyPinyin.apply(_:characters:scheme:schema:userDir:) writes its
// patch, `wubi86.custom.yaml`, from rime-wubi's schema beside rime-ice's, as it writes Zhuyin's; and
// PinyinScheme.applySchemaList(.wubi, userDir:) lists the schema. `make deps` puts rime-wubi's wubi86.schema.yaml and
// wubi86.dict.yaml (pinned commit 152a0d3f3efe40cae216d1e3b338242446848d07) beside rime-ice's data in ThirdParty/rime-data,
// as it does Zhuyin's, or in ThirdParty/rime-wubi. Each scenario has its own process and temporary Rime folders, never
// the user's Rime data.
//
// Every code below was looked up in that commit's wubi86.dict.yaml (by weight) and typed into librime on rime-wubi's
// schema: g 一, gggg 王 (五一 second), wqvb 你好 (您好 second), trnt 我, lgyi 国 (its one candidate in the common
// characters), p 这 (Traditional 這, 國 for 国).

private enum WubiRime {
    static let workerKey = "ALLINONEIME_WUBI_ACCEPTANCE_WORKER"
    static let rootKey = "ALLINONEIME_WUBI_ACCEPTANCE_ROOT"
    static var worker: String? { ProcessInfo.processInfo.environment[workerKey] }
    static let wubiFiles = ["wubi86.schema.yaml", "wubi86.dict.yaml"]

    /// Where Wubi's data is: beside rime-ice's, or in a folder of its own.
    static var wubiData: URL? {
        [RimeFixture.sharedData, RimeFixture.thirdParty.appendingPathComponent("rime-wubi")].first { folder in
            wubiFiles.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        }
    }

    static var dataAvailable: Bool {
        wubiData != nil && ["rime_ice.schema.yaml", "build/rime_ice.table.bin"].allSatisfy {
            FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent($0).path)
        }
    }

    static func run(_ scenario: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wubi-rime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("worker-output.txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(CommandLine.arguments.first))
        if let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path"), index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            process.arguments = ["--test-bundle-path", path, "--filter", "WubiRimeAcceptanceWorker", path,
                                 "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "WubiRimeAcceptanceWorker"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment[workerKey] = scenario
        environment[rootKey] = root.path
        environment["ALLINONEIME_THIRDPARTY"] = RimeFixture.thirdParty.path
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(300)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        let report = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        try #require(process.terminationReason == .exit && process.terminationStatus == 0, "\(scenario):\n\(report)")
        try #require(report.contains("WUBI_WORKER_FINISHED:\(scenario)"), "\(scenario) didn't run:\n\(report)")
    }

    /// The shared folder as the app has it: rime-ice's data and Wubi's, linked, and in `lua/` rime-ice's scripts with the
    /// app's filter of the candidates removed beside them.
    static func shared(_ root: URL) throws -> URL {
        let fm = FileManager.default
        let shared = root.appendingPathComponent("shared")
        let lua = shared.appendingPathComponent("lua")
        try fm.createDirectory(at: lua, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(atPath: RimeFixture.sharedData.path) where item != "lua" {
            try fm.createSymbolicLink(at: shared.appendingPathComponent(item),
                                      withDestinationURL: RimeFixture.sharedData.appendingPathComponent(item))
        }
        let wubi = try #require(wubiData, "Wubi's data (make deps)")
        if wubi.path != RimeFixture.sharedData.path {
            // Its files (a folder in it holds a repository's licenses), unless rime-ice's data has one of the name.
            for item in try fm.contentsOfDirectory(atPath: wubi.path) where !fm.fileExists(atPath: shared.appendingPathComponent(item).path) {
                var folder: ObjCBool = false
                guard fm.fileExists(atPath: wubi.appendingPathComponent(item).path, isDirectory: &folder), !folder.boolValue else { continue }
                try fm.createSymbolicLink(at: shared.appendingPathComponent(item), withDestinationURL: wubi.appendingPathComponent(item))
            }
        }
        let iceLua = RimeFixture.sharedData.appendingPathComponent("lua")
        for item in (try? fm.contentsOfDirectory(atPath: iceLua.path)) ?? [] {
            try fm.createSymbolicLink(at: lua.appendingPathComponent(item), withDestinationURL: iceLua.appendingPathComponent(item))
        }
        let filter = RimeFixture.root.appendingPathComponent("Resources/rime/lua/\(RemovedCandidates.luaFilter).lua")
        try fm.createSymbolicLink(at: lua.appendingPathComponent(filter.lastPathComponent), withDestinationURL: filter)
        return shared
    }

    /// librime started as the app starts it with Wubi picked: its patch and the schema list written by the app, a full
    /// check, no error logged about Wubi's schema.
    static func start(_ root: URL, characters: ChineseCharacters = .simplified) throws {
        let fm = FileManager.default
        let shared = try shared(root)
        let user = root.appendingPathComponent("Rime")
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        _ = try FuzzyPinyin.apply([], characters: characters, scheme: .wubi,
                                  schema: shared.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
        #expect(fm.fileExists(atPath: user.appendingPathComponent("wubi86.custom.yaml").path), "Wubi's own patch")
        #expect(try PinyinScheme.applySchemaList(.wubi, userDir: user) == .written)
        let logs = root.appendingPathComponent("logs")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        try RimeService.shared.start(sharedDataDir: shared, userDataDir: user, logDir: logs, fullCheck: true,
                                     openCCDir: RimeFixture.thirdParty.appendingPathComponent("opencc"))
        try #require(RimeService.shared.waitUntilReady(timeout: 180), "librime didn't deploy")
        #expect(RimeService.shared.deploymentStatus == .succeeded)
        for name in try fm.contentsOfDirectory(atPath: logs.path) where name.contains(".INFO") {
            let text = try String(contentsOf: logs.appendingPathComponent(name), encoding: .utf8)
            let errors = text.split(separator: "\n").filter {
                $0.range(of: #"^E\d{8} "#, options: .regularExpression) != nil && $0.contains("wubi86")
            }
            #expect(errors.isEmpty, "\(errors.prefix(5))")
        }
    }

    static func session() throws -> RimeSession {
        let session = try #require(RimeService.shared.makeSession())
        try #require(session.selectSchema("wubi86"), "couldn't select wubi86")
        #expect(session.schema == "wubi86")
        return session
    }

    static func type(_ keys: String, in session: RimeSession) -> EngineSnapshot {
        session.clearComposition()
        for key in keys.utf8 { _ = session.processKey(Int32(key), mask: 0) }
        return session.snapshot()
    }

    /// `keys` typed: composed, nothing put in yet, `word` the first candidate.
    static func expectFirst(_ keys: String, in session: RimeSession, _ word: String) {
        let snapshot = type(keys, in: session)
        #expect(snapshot.isComposing, "\(keys)")
        #expect(session.rawInput == keys)
        #expect(session.takeCommit() == nil, "\(keys) put in by itself")
        #expect(snapshot.candidates.first?.text == word, "\(keys) → \(snapshot.candidates.prefix(5).map(\.text))")
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "codes": { root in
            try start(root)
            let session = try session()
            // The first candidates; lgyi has one candidate at four codes and still waits for a pick.
            for (keys, word) in [("g", "一"), ("gggg", "王"), ("wqvb", "你好"), ("trnt", "我"), ("lgyi", "国"), ("p", "这")] {
                expectFirst(keys, in: session, word)
            }
            #expect(type("wqvb", in: session).candidates.prefix(2).map(\.text) == ["你好", "您好"])
            // Space puts the first in; then a new code starts.
            _ = type("gggg", in: session)
            #expect(session.processKey(RimeKey.space, mask: 0))
            #expect(session.takeCommit() == "王")
            #expect(!session.snapshot().isComposing)
            _ = type("lgyi", in: session)
            #expect(session.processKey(RimeKey.space, mask: 0))
            #expect(session.takeCommit() == "国")
            // A digit picks its row.
            _ = type("wqvb", in: session)
            #expect(session.processKey(0x32, mask: 0))
            #expect(session.takeCommit() == "您好")
        },
        "switch": { root in
            try start(root)
            let session = try session()
            expectFirst("trnt", in: session, "我")
            session.clearComposition()
            #expect(session.selectSchema("rime_ice"))
            #expect(type("nihao", in: session).candidates.prefix(5).contains { $0.text == "你好" })
            session.clearComposition()
            #expect(session.selectSchema("wubi86"))
            expectFirst("wqvb", in: session, "你好")
        },
        "traditional": { root in
            try start(root, characters: .taiwan)
            let session = try session()
            expectFirst("lgyi", in: session, "國")
            expectFirst("p", in: session, "這")
            expectFirst("g", in: session, "一")
        },
        "removed": { root in
            try start(root)
            let session = try session()
            expectFirst("wqvb", in: session, "你好")
            session.clearComposition()
            session.setRemovedCandidates(["你好"])
            let filtered = type("wqvb", in: session)
            #expect(!filtered.candidates.contains { $0.text == "你好" }, "removed candidate returned: \(filtered.candidates.map(\.text))")
            #expect(filtered.candidates.first?.text == "您好")
        },
        "shift": { root in
            try start(root)
            let session = try session()
            // A tap of Shift puts in what is composed, converted (as Zhuyin's), not the code typed, and goes to Latin.
            expectFirst("wqvb", in: session, "你好")
            _ = session.processKey(RimeKey.shiftL, mask: 0)
            _ = session.processKey(RimeKey.shiftL, mask: RimeKey.releaseMask)
            #expect(session.takeCommit() == "你好")
            let after = session.snapshot()
            #expect(after.isAsciiMode && !after.isComposing && session.rawInput.isEmpty)
        },
    ]
}

@Suite(.serialized, .enabled(if: WubiRime.worker != nil))
struct WubiRimeAcceptanceWorker {
    @Test func runScenario() throws {
        let scenario = try #require(WubiRime.worker)
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[WubiRime.rootKey]))
        let run = try #require(WubiRime.scenarios[scenario], "unknown scenario \(scenario)")
        try run(root)
        print("WUBI_WORKER_FINISHED:\(scenario)")
    }
}

@Suite(.serialized, .enabled(if: WubiRime.worker == nil),
       .enabled(if: WubiRime.dataAvailable || RimeFixture.dataRequired, "needs rime-ice and rime-wubi's data (make deps)"))
struct WubiRimeTests {
    @Test func wubi86DeploysAndTypesItsCodes() throws { try WubiRime.run("codes") }
    @Test func switchesWithFullPinyin() throws { try WubiRime.run("switch") }
    @Test func taiwanCharacters() throws { try WubiRime.run("traditional") }
    @Test func removedCandidateStaysRemoved() throws { try WubiRime.run("removed") }
    @Test func shiftTapPutsInTheCandidate() throws { try WubiRime.run("shift") }
}
