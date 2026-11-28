import Foundation
import Testing

// 0.7.6 regress finding 2 (aio-notes/regress076.md): with a config file that cannot be read (`loadError != nil`,
// `canSave == false`) Settings → AI is disabled, so its choices must never open: pointing at them (the settings search,
// the start, the Doctor) would show cards whose Cancel, Esc and clicks are all disabled, with no way out on the page.
// Expected: `SettingsModel.point(at: .provider, …)` leaves the picker collapsed while `canSave` is false.
//
// The input method's code is an executable target, so (as Settings121MacTests does) all of Sources/AllInOneIME is
// compiled into a child with main.swift's dispatch replaced; the child's home is a folder of the test's and it reads a
// config of its own with a syntax error. Offline: no network, no keys, no CLI.

@Suite(.serialized)
struct Regress076UnreadableConfigPickerTests {
    private func report() throws -> [String: String] { try Regress076Child.report.get() }

    @Test func theChildReadsTheBrokenConfigAsUnreadable() throws {
        let report = try report()
        #expect(report["canSave"] == "false", "the config with a syntax error can be saved: \(report)")
        #expect(report["hasLoadError"] == "true", "no load error: \(report)")
    }

    @Test func searchingForAnAIDoesNotOpenTheChoicesWhileTheConfigIsUnreadable() throws {
        let report = try report()
        #expect(report["searchChoosing"] == "false",
                "searching \"kiro\" opened the choices of a disabled page (Cancel and Esc disabled): \(report)")
    }

    @Test func pointingAtACardDoesNotOpenTheChoicesWhileTheConfigIsUnreadable() throws {
        let report = try report()
        #expect(report["cardChoosing"] == "false",
                "the Doctor/start pointing at a card opened the choices of a disabled page: \(report)")
    }
}

enum Regress076Child {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let report: Result<[String: String], Error> = Result { try run() }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let harness = #"""

// MARK: - Regress076UnreadableConfigPickerTests' child (in place of main.swift's dispatch)

Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

MainActor.assumeIsolated {
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
        exit(3)
    }
    UIText.choice = "en"
    let url = URL(fileURLWithPath: home).appendingPathComponent("broken-config.json")
    try? "{ this is not json".write(to: url, atomically: true, encoding: .utf8)
    let model = SettingsModel(configURL: url, persists: true)
    print("canSave\t\(model.canSave)")
    print("hasLoadError\t\(model.loadError != nil)")
    model.point(at: .provider, search: "kiro")
    print("searchChoosing\t\(model.aiCards.choosing)")
    model.point(at: nil)
    model.changeAICards { $0.show(search: nil, target: nil) }
    model.point(at: nil, card: .cli(.kiro))
    print("cardChoosing\t\(model.aiCards.choosing)")
    fflush(stdout)
}
exit(0)
"""#

    static func run() throws -> [String: String] {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("regress076-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let home = fm.temporaryDirectory.appendingPathComponent("regress076-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch); try? fm.removeItem(at: home) }
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no dispatch line") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + harness).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("regress076")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path, "HOME": home.path]) { $1 }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw Failure(description: "the child failed (\(process.terminationStatus)):\n\(output.suffix(3000))") }
        var values: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.count == 2 { values[fields[0]] = fields[1] }
        }
        values["output"] = String(output.suffix(1500))
        return values
    }
}
