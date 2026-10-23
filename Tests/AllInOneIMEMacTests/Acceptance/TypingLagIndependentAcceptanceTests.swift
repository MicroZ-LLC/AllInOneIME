import Foundation
import Testing

/// Independent acceptance for https://github.com/MicroZ-LLC/AllInOneIME/issues/23.
/// These tests were derived from the issue without reading the implementation author's tests.
/// The child uses real AppKit windows and librime, with temporary config/user folders only.
@Suite(.serialized)
struct TypingLagIndependentAcceptanceTests {
    @Test func candidateNoticeAndChipReuseWindowsAcrossCommits() throws {
        try Issue23AcceptanceChild.run("windows")
    }

    @Test func unchangedGeometryDoesNotReachAppKitWindowMutators() throws {
        try Issue23AcceptanceChild.run("geometry")
    }

    @Test func inputMenuCachesConfigAndRecoversFromMalformedFiles() throws {
        try Issue23AcceptanceChild.run("menu")
    }

    @Test func lunarTranslatorWorksWithNoPreexistingUserDirectory() throws {
        try Issue23AcceptanceChild.run("lunar-fresh")
    }

    @Test func startingRimePreservesExistingUserFiles() throws {
        try Issue23AcceptanceChild.run("lunar-existing")
    }
}

private enum Issue23AcceptanceChild {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(_ scenario: String) throws {
        let executable = try compiled.get()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue23-independent-\(scenario)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let thirdParty = ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
        let result = try command(executable, [scenario, temporary.path, thirdParty.path], timeout: 90)
        #expect(result.status == 0, "Independent child \(scenario) failed:\n\(result.output)")
        #expect(result.output.contains("ACCEPTANCE PASS \(scenario)"), "\(result.output)")
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue23-independent-harness-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        // The executable target cannot be imported by this test target. Compile its production panel,
        // view, icon, live-config and menu builder into a separate process. Unrelated menu actions
        // are stand-ins; no product implementation is rewritten or copied into the test oracle.
        let menu = try String(contentsOf: repository.appendingPathComponent("Sources/AllInOneIME/InputMenu.swift"), encoding: .utf8)
        guard let end = menu.range(of: "    /// IMK hands menu actions") else {
            throw ChildError("Could not isolate the production makeMenu declaration")
        }
        let menuURL = scratch.appendingPathComponent("ProductionMenu.swift")
        try (String(menu[..<end.lowerBound]) + "}\n").write(to: menuURL, atomically: true, encoding: .utf8)
        let harness = scratch.appendingPathComponent("Harness.swift")
        try Issue23AcceptanceHarness.swift.write(to: harness, atomically: true, encoding: .utf8)
        let observer = scratch.appendingPathComponent("ConfigReads.c")
        try Issue23AcceptanceHarness.readObserver.write(to: observer, atomically: true, encoding: .utf8)
        let observerLibrary = scratch.appendingPathComponent("ConfigReads.dylib")
        let c = try command(URL(fileURLWithPath: "/usr/bin/xcrun"),
                            ["clang", "-dynamiclib", observer.path, "-o", observerLibrary.path], timeout: 30)
        guard c.status == 0 else { throw ChildError(c.output) }
        let products = repository.appendingPathComponent(".build/debug")
        let modules = fm.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        let thirdParty = ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
        let rimeLib = thirdParty.appendingPathComponent("librime/dist/lib")
        var objects: [String] = []
        for module in ["AllInOneIMECore", "AllInOneIMEText", "AllInOneIMEScriptEngine", "AllInOneIMERime", "Crypto"] {
            let aggregate = products.appendingPathComponent(module + ".o")
            if fm.fileExists(atPath: aggregate.path) {
                objects.append(aggregate.path)
            } else {
                let folder = products.appendingPathComponent(module + ".build")
                objects += try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "o" }.map(\.path)
            }
        }
        let executable = scratch.appendingPathComponent("acceptance")
        let sources = ["CandidatePanel.swift", "CommandIcons.swift", "LiveSettings.swift"]
            .map { repository.appendingPathComponent("Sources/AllInOneIME/" + $0).path }
        let arguments = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", modules.path,
                         "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                         "-L", rimeLib.path, "-lrime", "-Xlinker", "-rpath", "-Xlinker", rimeLib.path,
                         "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels",
                         "-framework", "AppKit", "-framework", "InputMethodKit"]
            + sources + [menuURL.path, harness.path, observerLibrary.path] + objects + ["-o", executable.path]
        let swift = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 90)
        guard swift.status == 0 else { throw ChildError(swift.output) }
        return executable
    }

    private struct CommandResult { var status: Int32; var output: String }
    private struct ChildError: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    private static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        // A file avoids pipe-buffer deadlocks on compiler diagnostics / librime deployment output.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue23-child-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        if executable.lastPathComponent == "acceptance" {
            var environment = ProcessInfo.processInfo.environment
            environment["DYLD_INSERT_LIBRARIES"] = executable.deletingLastPathComponent()
                .appendingPathComponent("ConfigReads.dylib").path
            process.environment = environment
        }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            throw ChildError("Timed out running isolated acceptance child \(arguments.first ?? "")")
        }
        return CommandResult(status: process.terminationStatus,
                             output: (try? String(contentsOf: log, encoding: .utf8)) ?? "(no output)")
    }
}
