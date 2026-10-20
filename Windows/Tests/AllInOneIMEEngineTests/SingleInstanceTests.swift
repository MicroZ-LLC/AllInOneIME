#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

/// One engine per user and session, or per pipe (§2.5): a second one exits, saying why with its exit code
/// (`EngineExit.anotherEngineRuns`), so that what starts it (the end-to-end driver) ends another engine only then.
struct SingleInstanceTests {
    @Test(.timeLimit(.minutes(1))) func aSecondEngineOnThePipeExitsWithTheCodeThatSaysSo() throws {
        try #require(FileManager.default.fileExists(atPath: debugEngine.path), "build the engine first (swift build)")
        let folder = try temporaryFolder("single")
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: config)
        // A pipe of its own: its own mutex too, whatever engine runs for this user.
        let pipe = "aio-single-\(GetCurrentProcessId())-\(UInt32.random(in: 0...UInt32.max))"
        func engine(_ errors: Pipe? = nil) -> Process {
            let engine = Process()
            engine.executableURL = debugEngine
            engine.arguments = ["--test", "--no-panel", "--no-rime", "--config", config.path, "--pipe", pipe]
            engine.standardOutput = FileHandle.nullDevice
            engine.standardError = errors ?? FileHandle.nullDevice
            return engine
        }
        let errors = Pipe()
        let output = Locked(initialState: "")
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            output.withLock { $0 += String(decoding: data, as: UTF8.self) }
        }
        let first = engine(errors)
        try first.run()
        defer {
            first.terminate()
            first.waitUntilExit()
            errors.fileHandleForReading.readabilityHandler = nil
        }
        let deadline = Date().addingTimeInterval(20)
        while !output.withLock({ $0.contains("ready in") }), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        try #require(output.withLock { $0 }.contains("ready in"), "\(output.withLock { $0 })")
        let second = engine()
        try second.run()
        second.waitUntilExit()
        #expect(second.terminationStatus == EngineExit.anotherEngineRuns)
        #expect(first.isRunning)
    }
}
#endif
