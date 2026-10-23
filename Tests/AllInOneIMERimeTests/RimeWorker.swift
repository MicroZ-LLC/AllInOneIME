import Foundation
import Testing
@testable import AllInOneIMERime
#if canImport(Darwin)
import Darwin
#endif

/// A scenario run in a copy of this test process (`RimeWorkerTests`), with a folder of its own: librime starts once per
/// process, so a test that starts it with its own user folder (or shared data) needs a process of its own. The
/// scenarios, by name: `LunarDatabaseTests.scenarios`, `PersonalDictionaryBuildTests.scenarios`.
enum RimeWorker {
    static let scenarioKey = "ALLINONEIME_RIME_WORKER"
    static let rootKey = "ALLINONEIME_RIME_WORKER_ROOT"
    static var scenario: String? { ProcessInfo.processInfo.environment[scenarioKey] }
    static var dataAvailable: Bool {
        FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent("build/rime_ice.table.bin").path)
    }
    static var required: Bool { RimeFixture.dataRequired }
    static let scenarios = LunarDatabaseTests.scenarios.merging(PersonalDictionaryBuildTests.scenarios) { first, _ in first }

    /// Runs `scenario` in `root` (made here) and waits for it: it must exit cleanly, having run.
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
            process.arguments = ["--test-bundle-path", path, "--filter", "RimeWorkerTests", path, "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "RimeWorkerTests"]
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
        try #require(text.contains("RIME_WORKER_FINISHED:\(scenario)"), "\(scenario) didn't run:\n\(text)")
    }
}

@Suite(.serialized, .enabled(if: RimeWorker.scenario != nil))
struct RimeWorkerTests {
    @Test func runScenario() throws {
        let scenario = try #require(RimeWorker.scenario)
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[RimeWorker.rootKey]))
        let run = try #require(RimeWorker.scenarios[scenario], "unknown scenario \(scenario)")
        try run(root)
        print("RIME_WORKER_FINISHED:\(scenario)")
    }
}
