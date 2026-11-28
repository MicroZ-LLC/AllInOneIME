import Foundation
import Testing

// PR #192's review (0.7.6 regress findings 1 and 2, follow-up). Settings' model is in the input method's executable
// target, so (as Regress076UnreadableConfigPickerTests does) all of Sources/AllInOneIME is compiled into a child with
// main.swift's dispatch replaced; its home is a folder of the test's and it reads config files of its own. Offline.
//
// 1. Two reads started at the same date arrive in order: the first is taken, the second (the newer file) is dropped as
//    the store moved on; it must then be read again, not leave Settings on the older file.
// 2. Settings → AI's choices open (Change ▾), then the config file can't be read any more: they collapse, as the page,
//    its Cancel and Esc are disabled.
@Suite(.serialized)
struct Regress076FollowUpTests {
    private func report() throws -> [String: String] { try Regress076FollowUpChild.report.get() }

    @Test func aDroppedReadIsReadAgainSoTheLatestFileIsShown() throws {
        let report = try report()
        #expect(report["afterFirst"] == "true", "the first read wasn't taken: \(report)")
        #expect(report["finished"] == "true", "the read again never finished: \(report)")
        #expect(report["latestShown"] == "true", "Settings stayed on the older file: \(report)")
    }

    @Test func theChoicesCollapseWhenTheConfigBecomesUnreadable() throws {
        let report = try report()
        #expect(report["openBefore"] == "true", "Change ▾ didn't open the choices: \(report)")
        #expect(report["canSaveAfter"] == "false", "the broken file was read as valid: \(report)")
        #expect(report["storedChoosing"] == "false", "the choices stayed open on a disabled page: \(report)")
        #expect(report["shownChoosing"] == "false", "the choices are shown on a disabled page: \(report)")
    }
}

enum Regress076FollowUpChild {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let report: Result<[String: String], Error> = Result { try run() }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let harness = #"""

// MARK: - Regress076FollowUpTests' child (in place of main.swift's dispatch)

Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

final class Flag { var on = false }

MainActor.assumeIsolated {
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
        exit(3)
    }
    UIText.choice = "en"
    func dated(_ url: URL, age: TimeInterval) {
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    // 1. Two reads from D1, taken in order: D2's, then D3's.
    let url = URL(fileURLWithPath: home).appendingPathComponent("order-config.json")
    var c1 = Config.default
    c1.voiceInput = false
    c1.rememberQuestions = false
    try? c1.write(to: url)
    dated(url, age: 300)
    let model = SettingsModel(configURL: url, persists: true)
    let d1 = model.store.fileDate
    var c2 = c1
    c2.voiceInput = true
    try? c2.write(to: url)
    dated(url, age: 200)
    let read1 = SettingsStore.FileRead(url, since: d1)
    var c3 = c2
    c3.rememberQuestions = true
    try? c3.write(to: url)
    dated(url, age: 100)
    let read2 = SettingsStore.FileRead(url, since: d1)
    model.take(read1, since: d1, attempts: 1) {}
    print("afterFirst\t\(model.config == c2)")
    let finished = Flag()
    model.take(read2, since: d1, attempts: 3) { finished.on = true }
    let deadline = Date().addingTimeInterval(20)
    while !finished.on, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    print("finished\t\(finished.on)")
    print("latestShown\t\(model.config == c3)")

    // 2. The choices open, then the file can't be read.
    let pickerURL = URL(fileURLWithPath: home).appendingPathComponent("picker-config.json")
    try? Config.default.write(to: pickerURL)
    dated(pickerURL, age: 300)
    let picker = SettingsModel(configURL: pickerURL, persists: true)
    picker.changeAICards { $0.change() }
    print("openBefore\t\(picker.aiCards.choosing)")
    try? "{ this is not json".write(to: pickerURL, atomically: true, encoding: .utf8)
    dated(pickerURL, age: 100)
    picker.reloadIfChanged()
    print("canSaveAfter\t\(picker.canSave)")
    print("storedChoosing\t\(picker.aiPicker.choosing)")
    print("shownChoosing\t\(picker.aiCards.choosing)")
    fflush(stdout)
}
exit(0)
"""#

    static func run() throws -> [String: String] {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("regress076b-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let home = fm.temporaryDirectory.appendingPathComponent("regress076b-home-\(UUID().uuidString)", isDirectory: true)
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
        let executable = scratch.appendingPathComponent("regress076b")
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
