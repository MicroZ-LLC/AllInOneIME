import AllInOneIMECore
@testable import AllInOneIMERime
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// Real librime acceptance for Zhuyin, independent of the implementation.
// Assumed API: RimeSession.selectSchema("bopomofo") -> Bool, as in the Shuangpin acceptance tests;
// the bundled bopomofo schema uses Daqian keys and terra_pinyin.dict.yaml. Each scenario has its own
// process and temporary Rime user folder, never the user's Rime data.

private enum ZhuyinRime {
    static let workerKey = "ALLINONEIME_ZHUYIN_ACCEPTANCE_WORKER"
    static let rootKey = "ALLINONEIME_ZHUYIN_ACCEPTANCE_ROOT"
    static var worker: String? { ProcessInfo.processInfo.environment[workerKey] }
    static var dataAvailable: Bool {
        ["rime_ice.schema.yaml", "bopomofo.schema.yaml", "terra_pinyin.dict.yaml", "zhuyin.yaml",
         "stroke.schema.yaml", "stroke.dict.yaml", "build/rime_ice.table.bin"].allSatisfy {
            FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent($0).path)
        }
    }

    static func run(_ scenario: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhuyin-rime-\(UUID().uuidString)")
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
            process.arguments = ["--test-bundle-path", path, "--filter", "ZhuyinRimeAcceptanceWorker", path,
                                 "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "ZhuyinRimeAcceptanceWorker"]
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
        try #require(report.contains("ZHUYIN_WORKER_FINISHED:\(scenario)"), "\(scenario) didn't run:\n\(report)")
    }

    static func start(_ root: URL, traditional: Bool = false) throws {
        let user = root.appendingPathComponent("Rime")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "patch:\n  schema_list:\n    - schema: rime_ice\n    - schema: bopomofo\n"
            .write(to: user.appendingPathComponent("default.custom.yaml"), atomically: true, encoding: .utf8)
        if traditional {
            let schema = try String(contentsOf: RimeFixture.sharedData.appendingPathComponent("bopomofo.schema.yaml"), encoding: .utf8)
            let characters = try #require(ChineseCharacters.taiwan.patch(schema: schema),
                                          "bopomofo needs a Traditional conversion switch")
            let filter = "  engine/filters/+:\n    - lua_filter@*\(RemovedCandidates.luaFilter)\n"
            try ("patch:\n" + characters + filter)
                .write(to: user.appendingPathComponent("bopomofo.custom.yaml"), atomically: true, encoding: .utf8)
            let lua = user.appendingPathComponent("lua")
            try FileManager.default.createDirectory(at: lua, withIntermediateDirectories: true)
            let script = RimeFixture.root.appendingPathComponent("Resources/rime/lua/\(RemovedCandidates.luaFilter).lua")
            try FileManager.default.copyItem(at: script, to: lua.appendingPathComponent(script.lastPathComponent))
        }
        try RimeService.shared.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil, fullCheck: true,
                                     openCCDir: RimeFixture.thirdParty.appendingPathComponent("opencc"))
        try #require(RimeService.shared.waitUntilReady(timeout: 180), "librime didn't deploy")
        #expect(RimeService.shared.deploymentStatus == .succeeded)
    }

    static func session(_ schema: String) throws -> RimeSession {
        let session = try #require(RimeService.shared.makeSession())
        try #require(session.selectSchema(schema), "couldn't select \(schema)")
        return session
    }

    static func type(_ keys: String, in session: RimeSession) -> EngineSnapshot {
        for key in keys.utf8 { _ = session.processKey(Int32(key), mask: 0) }
        return session.snapshot()
    }

    static func expect(_ keys: String, in session: RimeSession, word: String) {
        let snapshot = type(keys, in: session)
        #expect(snapshot.isComposing)
        #expect(!snapshot.preedit.isEmpty)
        #expect(snapshot.candidates.prefix(5).contains { $0.text == word },
                "\(keys) → \(snapshot.candidates.prefix(5).map(\.text))")
    }

    static let scenarios: [String: (URL) throws -> Void] = [
        "daqian": { root in
            try start(root, traditional: true)
            let session = try session("bopomofo")
            #expect(session.api.pointee.get_option(session.id, "zh_hant_tw") != 0)
            expect("su3cl3", in: session, word: "你好") // ㄋㄧˇ ㄏㄠˇ on Standard/Daqian
        },
        "tone-and-switch": { root in
            try start(root)
            let session = try session("bopomofo")
            let before = type("su", in: session)
            #expect(before.isComposing)
            let after = type("3", in: session) // ˇ is a syllable's tone, not candidate 3
            #expect(session.rawInput == "su3")
            #expect(after.isComposing && after.preedit != before.preedit)
            #expect(after.candidates.prefix(5).contains { $0.text == "你" })
            session.clearComposition()
            #expect(session.selectSchema("rime_ice"))
            expect("nihao", in: session, word: "你好")
            session.clearComposition()
            #expect(session.selectSchema("bopomofo"))
            expect("su3cl3", in: session, word: "你好")
        },
        "removed": { root in
            try start(root, traditional: true)
            let session = try session("bopomofo")
            expect("su3cl3", in: session, word: "你好")
            session.clearComposition()
            session.setRemovedCandidates(["你好"])
            let filtered = type("su3cl3", in: session)
            #expect(!filtered.candidates.contains { $0.text == "你好" },
                    "removed candidate returned: \(filtered.candidates.map(\.text))")
        },
    ]
}

@Suite(.serialized, .enabled(if: ZhuyinRime.worker != nil))
struct ZhuyinRimeAcceptanceWorker {
    @Test func runScenario() throws {
        let scenario = try #require(ZhuyinRime.worker)
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[ZhuyinRime.rootKey]))
        let run = try #require(ZhuyinRime.scenarios[scenario], "unknown scenario \(scenario)")
        try run(root)
        print("ZHUYIN_WORKER_FINISHED:\(scenario)")
    }
}

@Suite(.serialized, .enabled(if: ZhuyinRime.worker == nil),
       .enabled(if: ZhuyinRime.dataAvailable || RimeFixture.dataRequired,
                "needs bopomofo and terra_pinyin data (make deps)"))
struct ZhuyinRimeTests {
    @Test func daqianProducesTraditionalCandidates() throws { try ZhuyinRime.run("daqian") }
    @Test func toneKeyAndReturnToFullPinyin() throws { try ZhuyinRime.run("tone-and-switch") }
    @Test func removedCandidateStaysRemoved() throws { try ZhuyinRime.run("removed") }
}
