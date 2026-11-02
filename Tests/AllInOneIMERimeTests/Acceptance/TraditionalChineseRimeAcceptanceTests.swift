import AllInOneIMECore
@testable import AllInOneIMERime
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// Acceptance tests for pinyin in Traditional characters with the real pack and librime (spec-traditional-chinese.md,
// Part A, items 2–4 and 8), written from the spec by an independent reviewer; the implementer may not edit them. The
// patch is written as the app writes it (`FuzzyPinyin.apply`, Settings → Input → Chinese → Characters), librime is
// given the OpenCC data as the app gives it (a copy of ThirdParty/opencc standing in for Contents/SharedSupport/opencc).
// librime starts once per process: each case runs in a copy of this test executable with a temporary Rime user folder
// of its own; the user's ~/Library/Rime is never used.
//
//   switchingCharacters          one librime, deployed again at each change (no restart): Taiwan 软件 → 軟體, 网络 → 網路,
//                                信息 → 資訊, 视频 → 影片, " 「」 and ' 『』, the switch on in every new session, the app's
//                                OpenCC data in the user folder's opencc/ (copied again when the app's changed); then Hong
//                                Kong 軟件, 網絡; then Simplified as before (软件, 网络, “)
//   hongKongFromTheStart         a fresh folder set to Hong Kong: 軟件, 網絡, 「」
//   withoutOpenCCData            Taiwan set but the app's OpenCC data missing: pinyin still types, and the Doctor reads
//                                librime's log as the OpenCC data missing, with what to do
//   theAppCarriesEveryFileItNeeds  every dictionary s2twp.json, s2hk.json and s2tw.json name is in the app's list and in
//                                ThirdParty/opencc

private enum TCRime {
    static let workerKey = "ALLINONEIME_TRADITIONAL_CHINESE_ACCEPTANCE_WORKER"
    static let rootKey = "ALLINONEIME_TRADITIONAL_CHINESE_ACCEPTANCE_ROOT"
    static var worker: String? { ProcessInfo.processInfo.environment[workerKey] }
    static var shared: URL { RimeFixture.sharedData }
    static var openCC: URL { RimeFixture.thirdParty.appendingPathComponent("opencc", isDirectory: true) }
    static var schema: URL { shared.appendingPathComponent("rime_ice.schema.yaml") }
    static var dataAvailable: Bool {
        FileManager.default.fileExists(atPath: shared.appendingPathComponent("build/rime_ice.table.bin").path)
            && FileManager.default.fileExists(atPath: openCC.appendingPathComponent("s2twp.json").path)
    }
    static var required: Bool { RimeFixture.dataRequired }

    /// Runs `scenario` in a copy of this process with a folder of its own, and waits for it.
    static func run(_ scenario: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tc-rime-acceptance-\(UUID().uuidString)", isDirectory: true)
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
            process.arguments = ["--test-bundle-path", path, "--filter", "TraditionalChineseRimeAcceptanceWorker", path,
                                 "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "TraditionalChineseRimeAcceptanceWorker"]
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
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        try #require(process.terminationReason == .exit && process.terminationStatus == 0, "\(scenario):\n\(text)")
        try #require(text.contains("TRADITIONAL_CHINESE_WORKER_FINISHED:\(scenario)"), "\(scenario) didn't run:\n\(text)")
    }

    // MARK: In the worker

    /// The user folder, and the app's OpenCC data (a copy the scenario may change, as an update would).
    static func folders(_ root: URL) throws -> (user: URL, bundled: URL) {
        let user = root.appendingPathComponent("Rime", isDirectory: true)
        let bundled = root.appendingPathComponent("App/Contents/SharedSupport/opencc", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundled.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: openCC, to: bundled)
        return (user, bundled)
    }

    static func start(user: URL, openCC: URL?, logs: URL? = nil) throws {
        let service = RimeService.shared
        try service.start(sharedDataDir: shared, userDataDir: user, logDir: logs, openCCDir: openCC)
        try #require(service.waitUntilReady(timeout: 180), "librime didn't deploy")
    }

    /// Settings → Input → Chinese → Characters changed: the patch written, Rime deployed again as the app does it.
    static func change(to characters: ChineseCharacters, user: URL, expect outcome: FuzzyPinyin.Outcome) throws {
        #expect(try FuzzyPinyin.apply([], characters: characters, schema: schema, userDir: user) == outcome, "\(characters)")
        RimeService.shared.redeploy()
        try #require(RimeService.shared.waitUntilReady(timeout: 180), "\(characters): no deployment")
        #expect(RimeService.shared.deploymentStatus == .succeeded, "\(characters): \(String(describing: RimeService.shared.deploymentError))")
    }

    static func session() throws -> RimeSession { try #require(RimeService.shared.makeSession()) }

    /// The candidates for `pinyin` in a new session.
    static func candidates(_ pinyin: String) throws -> [String] {
        let session = try session()
        defer { session.clearComposition() }
        for byte in pinyin.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
        return session.snapshot().candidates.map(\.text)
    }

    /// What `key` typed twice puts in, in a new session (nothing composed).
    static func punctuation(_ key: Character) throws -> [String] {
        let session = try session()
        let code = Int32(key.asciiValue ?? 0)
        return (0..<2).map { _ in
            _ = session.processKey(code, mask: 0)
            return session.takeCommit() ?? ""
        }
    }

    static func expectFirst(_ pinyin: String, _ expected: String, _ note: String) throws {
        let found = try candidates(pinyin)
        #expect(found.first == expected, "\(note): \(pinyin) → \(found.prefix(5))")
    }

    /// Whether the switch is on in a new session.
    static func traditionalizationOn() throws -> Bool {
        let session = try session()
        return session.api.pointee.get_option(session.id, "traditionalization") != 0
    }

    static let scenarios: [String: (URL) throws -> Void] = [
        "switching": { root in
            let (user, bundled) = try folders(root)
            #expect(try FuzzyPinyin.apply([], characters: .taiwan, schema: schema, userDir: user) == .written)
            try start(user: user, openCC: bundled)
            // The app's OpenCC data in the user folder's opencc/.
            for name in ChineseCharacters.openCCFiles {
                let copy = user.appendingPathComponent("opencc/\(name)")
                #expect(FileManager.default.contentsEqual(atPath: copy.path, andPath: bundled.appendingPathComponent(name).path),
                        "\(name) copied into the Rime folder's opencc")
            }
            // Taiwan's characters and words.
            #expect(try traditionalizationOn(), "the switch is on in a new session")
            try expectFirst("ruanjian", "軟體", "Taiwan")
            try expectFirst("wangluo", "網路", "Taiwan")
            try expectFirst("xinxi", "資訊", "Taiwan")
            try expectFirst("shipin", "影片", "Taiwan")
            try expectFirst("nihao", "你好", "Taiwan")
            #expect(try punctuation("\"") == ["「", "」"], "Taiwan's quotation marks")
            #expect(try punctuation("'") == ["『", "』"], "Taiwan's inner quotation marks")
            // An update brings other OpenCC data: copied at the next deployment.
            let changed = bundled.appendingPathComponent("s2tw.json")
            let text = try String(contentsOf: changed, encoding: .utf8)
            try (text + "\n").write(to: changed, atomically: true, encoding: .utf8)
            // Hong Kong: deployed again, no restart.
            try change(to: .hongkong, user: user, expect: .written)
            #expect(FileManager.default.contentsEqual(atPath: user.appendingPathComponent("opencc/s2tw.json").path, andPath: changed.path),
                    "the app's changed OpenCC file copied again")
            #expect(try traditionalizationOn())
            try expectFirst("ruanjian", "軟件", "Hong Kong")
            try expectFirst("wangluo", "網絡", "Hong Kong")
            #expect(try punctuation("\"") == ["「", "」"], "Hong Kong's quotation marks")
            #expect(try punctuation("'") == ["『", "』"], "Hong Kong's inner quotation marks")
            // Simplified: as before.
            try change(to: .simplified, user: user, expect: .removed)
            try expectFirst("ruanjian", "软件", "Simplified")
            try expectFirst("wangluo", "网络", "Simplified")
            try expectFirst("xinxi", "信息", "Simplified")
            #expect(try punctuation("\"") == ["“", "”"], "rime-ice's own quotation marks")
            // And back: Taiwan again.
            try change(to: .taiwan, user: user, expect: .written)
            try expectFirst("ruanjian", "軟體", "Taiwan again")
        },
        "hongkong-from-the-start": { root in
            let (user, bundled) = try folders(root)
            #expect(try FuzzyPinyin.apply([], characters: .hongkong, schema: schema, userDir: user) == .written)
            try start(user: user, openCC: bundled)
            try expectFirst("ruanjian", "軟件", "Hong Kong")
            try expectFirst("wangluo", "網絡", "Hong Kong")
            #expect(try punctuation("\"") == ["「", "」"])
        },
        "without-opencc-data": { root in
            let user = root.appendingPathComponent("Rime", isDirectory: true), logs = root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
            #expect(try FuzzyPinyin.apply([], characters: .taiwan, schema: schema, userDir: user) == .written)
            try start(user: user, openCC: nil, logs: logs)
            // Pinyin still types (in Simplified characters).
            let found = try candidates("ruanjian")
            #expect(!found.isEmpty && found.contains { $0.contains("软") || $0.contains("軟") }, "\(found)")
            _ = try candidates("wangluo")
            // What the Doctor reads of librime's error log (the app's: the files with .ERROR. in their name).
            Thread.sleep(forTimeInterval: 0.5)
            let files = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)) ?? []
            let lines = files.filter { $0.lastPathComponent.contains(".ERROR.") }
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .flatMap { $0.split(separator: "\n").map(String.init) }
            let summary = Doctor.summarizeLogLines(lines, home: NSHomeDirectory())
            #expect(summary.contains { $0.contains("OpenCC") }, "the Doctor names the missing OpenCC data: \(summary)\n\(lines.suffix(10))")
            var facts = Doctor.Facts()
            facts.recentErrors = summary
            let finding = Doctor.findings(facts, chinese: false).filter { $0.area == .recentErrors }.map { $0.text(chinese: false) }.joined()
            #expect(finding.lowercased().contains("reinstall"), "and what to do: \(finding)")
        },
    ]
}

@Suite(.serialized, .enabled(if: TCRime.worker != nil))
struct TraditionalChineseRimeAcceptanceWorker {
    @Test func runScenario() throws {
        let scenario = try #require(TCRime.worker)
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[TCRime.rootKey]))
        let run = try #require(TCRime.scenarios[scenario], "unknown scenario \(scenario)")
        try run(root)
        print("TRADITIONAL_CHINESE_WORKER_FINISHED:\(scenario)")
    }
}

@Suite(.serialized, .enabled(if: TCRime.worker == nil),
       .enabled(if: TCRime.dataAvailable || TCRime.required, "needs rime-ice and OpenCC's data in ThirdParty (make deps)"))
struct TraditionalChineseRimeAcceptanceTests {
    @Test func switchingCharacters() throws { try TCRime.run("switching") }

    @Test func hongKongFromTheStart() throws { try TCRime.run("hongkong-from-the-start") }

    @Test func withoutOpenCCData() throws { try TCRime.run("without-opencc-data") }

    @Test func theAppCarriesEveryFileItNeeds() throws {
        func files(in value: Any) -> [String] {
            if let object = value as? [String: Any] {
                var named = (object["file"] as? String).map { [$0] } ?? []
                named += object.values.flatMap(files)
                return named
            }
            if let array = value as? [Any] { return array.flatMap(files) }
            return []
        }
        for config in ["s2twp.json", "s2hk.json", "s2tw.json"] {
            #expect(ChineseCharacters.openCCFiles.contains(config), "\(config) carried")
            let data = try Data(contentsOf: TCRime.openCC.appendingPathComponent(config))
            let json = try JSONSerialization.jsonObject(with: data)
            var named = Set<String>()
            if let object = json as? [String: Any] { named = Set(object.values.flatMap(files)) }
            #expect(!named.isEmpty, "\(config) names its dictionaries")
            for file in named {
                #expect(ChineseCharacters.openCCFiles.contains(file), "\(config) needs \(file): carried by the app")
                #expect(FileManager.default.fileExists(atPath: TCRime.openCC.appendingPathComponent(file).path), "\(file) in ThirdParty/opencc")
            }
        }
    }
}
