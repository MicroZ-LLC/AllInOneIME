import AllInOneIMECore
@testable import AllInOneIMERime
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// Real rime-ice + librime acceptance for Shuangpin, independent of the implementation.
// Expected API: RimeSession.selectSchema(_ id: String) -> Bool, as PinyinEngine in the Core acceptance file.
// Each scenario runs in its own process and temporary Rime user folder; no test uses the user's Rime data.

private enum ShuangpinRime {
    static let workerKey = "ALLINONEIME_SHUANGPIN_ACCEPTANCE_WORKER"
    static let rootKey = "ALLINONEIME_SHUANGPIN_ACCEPTANCE_ROOT"
    static var worker: String? { ProcessInfo.processInfo.environment[workerKey] }
    static var dataAvailable: Bool {
        ["rime_ice", "double_pinyin_flypy", "double_pinyin", "double_pinyin_mspy"].allSatisfy {
            FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent("\($0).schema.yaml").path)
        } && FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent("build/rime_ice.table.bin").path)
    }

    static var openCCAvailable: Bool {
        FileManager.default.fileExists(atPath: RimeFixture.thirdParty.appendingPathComponent("opencc/s2twp.json").path)
    }

    static func run(_ scenario: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shuangpin-rime-\(UUID().uuidString)")
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
            process.arguments = ["--test-bundle-path", path, "--filter", "ShuangpinRimeAcceptanceWorker", path,
                                 "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "ShuangpinRimeAcceptanceWorker"]
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
        try #require(report.contains("SHUANGPIN_WORKER_FINISHED:\(scenario)"), "\(scenario) didn't run:\n\(report)")
    }

    static func start(_ root: URL, traditional: Bool = false) throws {
        let user = root.appendingPathComponent("Rime")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        // The app's full-pinyin-only default.custom.yaml is replaced in this isolated folder with the
        // schema list the feature must enable. No pack is downloaded or process restarted to switch.
        let schemas = ["rime_ice", "double_pinyin_flypy", "double_pinyin", "double_pinyin_mspy",
                       "double_pinyin_sogou", "double_pinyin_abc", "double_pinyin_jiajia", "double_pinyin_ziguang"]
        let patch = "patch:\n  schema_list:\n" + schemas.map { "    - schema: \($0)\n" }.joined()
        try patch.write(to: user.appendingPathComponent("default.custom.yaml"), atomically: true, encoding: .utf8)
        if traditional {
            try #require(openCCAvailable, "no OpenCC data in ThirdParty/opencc (make deps): Traditional candidates can't be made")
            let schema = try String(contentsOf: RimeFixture.sharedData.appendingPathComponent("double_pinyin_flypy.schema.yaml"), encoding: .utf8)
            let characters = try #require(ChineseCharacters.taiwan.patch(schema: schema))
            let filter = "  engine/filters/+:\n    - lua_filter@*\(RemovedCandidates.luaFilter)\n"
            try ("patch:\n" + characters + filter)
                .write(to: user.appendingPathComponent("double_pinyin_flypy.custom.yaml"), atomically: true, encoding: .utf8)
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

    static func type(_ letters: String, in session: RimeSession) -> EngineSnapshot {
        for byte in letters.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
        return session.snapshot()
    }

    static func expect(_ letters: String, schema: String, word: String) throws {
        let session = try session(schema)
        let snapshot = type(letters, in: session)
        #expect(snapshot.candidates.prefix(5).contains { $0.text == word },
                "\(schema): \(letters) → \(snapshot.candidates.prefix(5).map(\.text))")
        #expect(snapshot.isComposing)
        #expect(!snapshot.preedit.isEmpty, "Rime supplies the scheme's preedit")
    }

    static let scenarios: [String: (URL) throws -> Void] = [
        "schemes": { root in
            try start(root)
            try expect("nihc", schema: "double_pinyin_flypy", word: "你好")
            try expect("nihk", schema: "double_pinyin", word: "你好")
            try expect("nihk", schema: "double_pinyin_mspy", word: "你好")
            try expect("nihao", schema: "rime_ice", word: "你好")
            let markedSession = try session("double_pinyin_flypy")
            let composer = Composer(engine: markedSession)
            for character in "nihc" { _ = composer.handleKeyDown(KeyEvent(keyCode: 0, characters: String(character))) }
            #expect(composer.markedText == markedSession.snapshot().preedit,
                    "marked text follows Rime's Shuangpin preedit")
        },
        "switch-without-restart": { root in
            try start(root)
            let session = try session("rime_ice")
            #expect(type("nihao", in: session).candidates.prefix(5).contains { $0.text == "你好" })
            session.clearComposition()
            #expect(session.selectSchema("double_pinyin_flypy"))
            let shuangpin = type("nihc", in: session)
            #expect(shuangpin.candidates.prefix(5).contains { $0.text == "你好" })
            #expect(!shuangpin.preedit.isEmpty)
            session.clearComposition()
            #expect(session.selectSchema("rime_ice"))
            #expect(type("nihao", in: session).candidates.prefix(5).contains { $0.text == "你好" })
        },
        "traditional-and-removal": { root in
            try start(root, traditional: true)
            let session = try session("double_pinyin_flypy")
            #expect(session.api.pointee.get_option(session.id, "traditionalization") != 0)
            let traditional = type("nihc", in: session)
            #expect(traditional.candidates.prefix(5).contains { $0.text == "你好" })
            session.clearComposition()
            let distinct = type("whlo", in: session) // wangluo → 網路 (distinct from 简体 网络)
            #expect(distinct.candidates.prefix(5).contains { $0.text == "網路" }, "\(distinct.candidates.prefix(5).map(\.text))")
            session.clearComposition()
            session.setRemovedCandidates(["你好"])
            let filtered = type("nihc", in: session)
            #expect(!filtered.candidates.contains { $0.text == "你好" }, "removed candidate returned: \(filtered.candidates.map(\.text))")
        },
    ]
}

@Suite(.serialized, .enabled(if: ShuangpinRime.worker != nil))
struct ShuangpinRimeAcceptanceWorker {
    @Test func runScenario() throws {
        let scenario = try #require(ShuangpinRime.worker)
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[ShuangpinRime.rootKey]))
        let run = try #require(ShuangpinRime.scenarios[scenario], "unknown scenario \(scenario)")
        try run(root)
        print("SHUANGPIN_WORKER_FINISHED:\(scenario)")
    }
}

@Suite(.serialized, .enabled(if: ShuangpinRime.worker == nil),
       .enabled(if: ShuangpinRime.dataAvailable || RimeFixture.dataRequired, "needs rime-ice Shuangpin data (make deps)"))
struct ShuangpinRimeTests {
    @Test func threeSchemesAndFullPinyin() throws { try ShuangpinRime.run("schemes") }
    @Test func switchesOnTheSameSessionWithoutRestart() throws { try ShuangpinRime.run("switch-without-restart") }
    /// Traditional characters need OpenCC's data (ThirdParty/opencc, `make deps`): without it librime keeps the
    /// Simplified candidates (whlo → 网络), so it is skipped as the other Traditional suites are, unless the data is required.
    @Test(.enabled(if: ShuangpinRime.openCCAvailable || RimeFixture.dataRequired, "no OpenCC data in ThirdParty/opencc (make deps)"))
    func traditionalAndRemovedCandidateStayInShuangpin() throws { try ShuangpinRime.run("traditional-and-removal") }
}
