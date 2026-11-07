import AllInOneIMECore
@testable import AllInOneIMERime
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

/// #57 on the real librime and rime-ice with the app's own OpenCC data (ThirdParty/opencc, as `make deps` takes it):
/// Characters set to Traditional (Hong Kong), the candidates pinyin gives carry Hong Kong's forms that Simplified writes
/// alike (s2hk's HKVariants: 温, 户, 悦), and what the user typed so is Traditional (Hong Kong) by `Config.writtenLanguage`,
/// what `@improve`, the rewrite styles and translation go by. The rest is Core's Issue57Tests. librime starts once per
/// process: the scenario runs in a copy of this test executable with a Rime user folder of its own.
private enum Issue57Rime {
    static let workerKey = "ALLINONEIME_ISSUE57_RIME_WORKER"
    static let rootKey = "ALLINONEIME_ISSUE57_RIME_ROOT"
    static var worker: String? { ProcessInfo.processInfo.environment[workerKey] }
    static var openCC: URL { RimeFixture.thirdParty.appendingPathComponent("opencc", isDirectory: true) }
    static var schema: URL { RimeFixture.sharedData.appendingPathComponent("rime_ice.schema.yaml") }
    static var dataAvailable: Bool {
        FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent("build/rime_ice.table.bin").path)
            && FileManager.default.fileExists(atPath: openCC.appendingPathComponent("s2hk.json").path)
    }

    /// Runs the scenario in a copy of this process with a folder of its own, and waits for it.
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("issue57-rime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("worker-output.txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(CommandLine.arguments.first))
        if let bundle = CommandLine.arguments.firstIndex(of: "--test-bundle-path"), bundle + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[bundle + 1]
            process.arguments = ["--test-bundle-path", path, "--filter", "Issue57RimeWorker", path, "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "Issue57RimeWorker"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment[workerKey] = "hongkong"
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
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        try #require(process.terminationReason == .exit && process.terminationStatus == 0, "\(text)")
        try #require(text.contains("ISSUE57_RIME_WORKER_FINISHED"), "the scenario didn't run:\n\(text)")
    }

    /// The candidates for `pinyin` in a new session.
    static func candidates(_ pinyin: String) throws -> [String] {
        let session = try #require(RimeService.shared.makeSession())
        defer { session.clearComposition() }
        for byte in pinyin.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
        return session.snapshot().candidates.map(\.text)
    }

    /// Hong Kong's characters picked (the patch as Settings writes it), librime given the app's OpenCC data; pinyin
    /// typed, the candidate with Hong Kong's form taken.
    static func hongKong(_ root: URL) throws {
        let user = root.appendingPathComponent("Rime", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        #expect(try FuzzyPinyin.apply([], characters: .hongkong, schema: schema, userDir: user) == .written)
        try RimeService.shared.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil, openCCDir: openCC)
        try #require(RimeService.shared.waitUntilReady(timeout: 180), "librime didn't deploy")
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.chineseCharacters = .hongkong
        for (pinyin, form, taiwan) in [("wendu", "温", "溫"), ("hukou", "户", "戶"), ("xiyue", "悦", "悅")] {
            let found = try candidates(pinyin)
            // The app's OpenCC data gives Hong Kong's form, the one Simplified writes too.
            let typed = try #require(found.first { $0.contains(form) }, "\(pinyin): no candidate with \(form): \(found.prefix(8))")
            #expect(!found.prefix(3).contains { $0.contains(taiwan) }, "\(pinyin): \(found.prefix(8))")
            #expect(config.writtenLanguage(of: typed) == .traditionalHongKong,
                    "\(pinyin) → \(typed): read as \(config.writtenLanguage(of: typed).code)")
        }
    }
}

@Suite(.serialized, .enabled(if: Issue57Rime.worker != nil))
struct Issue57RimeWorker {
    @Test func runScenario() throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[Issue57Rime.rootKey]))
        try Issue57Rime.hongKong(root)
        print("ISSUE57_RIME_WORKER_FINISHED")
    }
}

@Suite(.serialized, .enabled(if: Issue57Rime.worker == nil),
       .enabled(if: Issue57Rime.dataAvailable || RimeFixture.dataRequired, "needs rime-ice and OpenCC's data in ThirdParty (make deps)"))
struct Issue57RimeTests {
    @Test func hongKongCandidatesAreReadAsHongKong() throws { try Issue57Rime.run() }
}
