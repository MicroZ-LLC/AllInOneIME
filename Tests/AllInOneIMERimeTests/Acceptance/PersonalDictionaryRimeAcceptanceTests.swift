import AllInOneIMECore
import AllInOneIMERime
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// Independent acceptance of the agreed personal-dictionary behavior, through real librime candidates and commits.
// The deliberately unrelated code/text mappings cannot be synthesized by ordinary pinyin. Cases first establish
// absence. Update/removal cases never commit their mappings, so the legitimate learned dictionary cannot mask a bug.
// Each case runs in a separate copy of this test executable with its own temporary Rime user folder. The normal
// RimeFixture singleton and maintenance threads in other suites are never used or reset by this suite.

private enum PersonalDictionaryRimeAcceptance {
    static let workerKey = "ALLINONEIME_PERSONAL_DICTIONARY_ACCEPTANCE_WORKER"
    static let rootKey = "ALLINONEIME_PERSONAL_DICTIONARY_ACCEPTANCE_ROOT"
    static var worker: String? { ProcessInfo.processInfo.environment[workerKey] }
    static let textA = "霁鸢星槎"
    static let codeA = "ceshiciku"
    static let textB = "鹭汀云笺"
    static let codeB = "yanshoucibiao"
    static let textC = "霁鸢雾港"
    static let codeC = "ceshigengxin"
    static let nativeText = "霁鸢旧语"
    static let nativeCode = "acceptancephrase"
    static let learnedText = "霁鸢"

    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let thirdParty: URL = {
        let given = ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
        return given.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? repository.appendingPathComponent("ThirdParty", isDirectory: true)
    }()
    static let shared = thirdParty.appendingPathComponent("rime-data", isDirectory: true)
    static var dataAvailable: Bool {
        FileManager.default.fileExists(atPath: shared.appendingPathComponent("build/rime_ice.table.bin").path)
    }
    static var required: Bool { ProcessInfo.processInfo.environment["ALLINONEIME_REQUIRE_RIME_DATA"] == "1" }

    static func dictionary(_ name: String, rows: [String], columns: String? = nil) -> String {
        "---\nname: \(name)\nversion: \"acceptance-1\"\nsort: by_weight\n"
            + (columns.map { "columns: \($0)\n" } ?? "")
            + "...\n" + rows.joined(separator: "\n") + "\n"
    }

    static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-dictionary-rime-acceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func runWorker(_ scenario: String, root: URL) throws {
        let executable = URL(fileURLWithPath: try #require(CommandLine.arguments.first))
        let stdout = root.appendingPathComponent("\(scenario).stdout")
        let stderr = root.appendingPathComponent("\(scenario).stderr")
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let out = try FileHandle(forWritingTo: stdout)
        let err = try FileHandle(forWritingTo: stderr)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = executable
        if let bundleArgument = CommandLine.arguments.firstIndex(of: "--test-bundle-path"),
           bundleArgument + 1 < CommandLine.arguments.count {
            // Swift 6.4's Swift Build runner dynamically loads a test bundle. Earlier SwiftPM versions execute
            // the generated package test binary directly. Preserve only the bundle argument, not the parent's
            // filters or its event-stream output file.
            let bundlePath = CommandLine.arguments[bundleArgument + 1]
            process.arguments = ["--test-bundle-path", bundlePath, "--filter", "PersonalDictionaryRimeWorkerTests",
                                 bundlePath, "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "PersonalDictionaryRimeWorkerTests"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment[workerKey] = scenario
        environment[rootKey] = root.path
        // Each worker uses explicit paths. It never opens the installed IME or launches an app.
        environment["ALLINONEIME_THIRDPARTY"] = thirdParty.path
        process.environment = environment
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let deadline = Date().addingTimeInterval(240)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            Issue.record("Rime acceptance worker \(scenario) timed out")
            return
        }
        process.waitUntilExit()
        let output = (try? String(contentsOf: stdout, encoding: .utf8)) ?? ""
        let errors = (try? String(contentsOf: stderr, encoding: .utf8)) ?? ""
        try #require(process.terminationReason == .exit && process.terminationStatus == 0,
                     "Worker \(scenario) failed:\n\(output)\n\(errors)")
        try #require(output.contains("PERSONAL_DICTIONARY_WORKER_FINISHED:\(scenario)"),
                     "The selected worker must actually execute, not pass with zero tests. Runner arguments: \(CommandLine.arguments)\n\(output)\n\(errors)")
    }
}

@Suite("Personal dictionaries: independent real-Rime acceptance", .serialized,
       .enabled(if: PersonalDictionaryRimeAcceptance.worker == nil),
       .enabled(if: PersonalDictionaryRimeAcceptance.dataAvailable || PersonalDictionaryRimeAcceptance.required,
                "requires the real Rime dictionaries in ThirdParty or ALLINONEIME_THIRDPARTY"))
struct PersonalDictionaryRimeAcceptanceTests {
    @Test("Imported words are real candidates and selecting one commits its exact text")
    func importsAndCommits() throws { try run("import-and-commit") }

    @Test("Imports coexist, source edits require reimport, and unlearned replacements/removals take effect")
    func coexistsUpdatesAndRemoves() throws { try run("coexist-update-remove") }

    @Test("Fuzzy pinyin enabled before import survives import, update and removal")
    func fuzzyBeforeImport() throws { try run("fuzzy-before-import") }

    @Test("Imported dictionaries survive enabling and disabling fuzzy pinyin")
    func importBeforeFuzzy() throws { try run("import-before-fuzzy") }

    @Test("Failed import and reimport leave the previous dictionary set usable after redeployment")
    func failedImportsPreserveWorkingCandidates() throws { try run("failed-imports") }

    @Test("Explicit column layouts either work by their named columns or fail without corrupting existing words")
    func honorsColumnsOrRefusesClearly() throws { try run("columns") }

    @Test("Learned words keep the rime_ice database; custom phrases and local-only imports are preserved")
    func preservesLearnedAndNativeData() throws { try run("learned-preservation") }

    @Test("A dictionary change queued during older maintenance activates the latest vocabulary and fuzzy pinyin")
    func dictionaryChangeDuringOlderMaintenance() throws { try run("queued-dictionary-change") }

    @Test("A fresh process uses the managed copy even after the original file is deleted")
    func persistsAcrossProcesses() throws {
        let root = try PersonalDictionaryRimeAcceptance.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try PersonalDictionaryRimeAcceptance.runWorker("persistence-prepare", root: root)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        if FileManager.default.fileExists(atPath: sources.path) { try FileManager.default.removeItem(at: sources) }
        try PersonalDictionaryRimeAcceptance.runWorker("persistence-reopen", root: root)
    }

    private func run(_ scenario: String) throws {
        let root = try PersonalDictionaryRimeAcceptance.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try PersonalDictionaryRimeAcceptance.runWorker(scenario, root: root)
    }
}

private final class PersonalDictionaryRimeWorld {
    let root: URL
    let user: URL
    let sources: URL
    let schema = PersonalDictionaryRimeAcceptance.shared.appendingPathComponent("rime_ice.schema.yaml")
    let service = RimeService.shared
    var store: PersonalDictionaryStore { PersonalDictionaryStore(userDirectory: user, schema: schema) }

    init(root: URL) throws {
        self.root = root
        user = root.appendingPathComponent("Rime", isDirectory: true)
        sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    func start() throws {
        try #require(PersonalDictionaryRimeAcceptance.dataAvailable, "Missing real Rime data")
        try #require(!service.isStarted, "This worker must be the only librime user in its process")
        try service.start(sharedDataDir: PersonalDictionaryRimeAcceptance.shared, userDataDir: user,
                          logDir: root.appendingPathComponent("Logs", isDirectory: true))
        try #require(service.waitUntilReady(timeout: 120), "Initial Rime deployment did not finish")
        try #require(service.makeSession() != nil, "Initial deployment did not produce a usable Rime session")
    }

    func redeploy() throws {
        service.redeploy()
        try #require(service.waitUntilReady(timeout: 120), "Rime redeployment did not finish")
        try #require(service.makeSession() != nil, "Redeployment did not produce a usable Rime session")
    }

    func source(_ name: String = "acceptance_alpha", rows: [String], columns: String? = nil,
                fileName: String = "Team vocabulary.dict.yaml") throws -> URL {
        let file = sources.appendingPathComponent(fileName)
        try PersonalDictionaryRimeAcceptance.dictionary(name, rows: rows, columns: columns)
            .write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Goes through normal keys and visible pages. It neither reads compiled tables nor uses private Rime APIs.
    func candidates(_ input: String) throws -> [String] {
        let session = try #require(service.makeSession())
        for byte in input.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
        defer { session.clearComposition() }
        var texts: [String] = []
        for _ in 0..<256 {
            let snapshot = session.snapshot()
            texts += snapshot.candidates.map(\.text)
            if snapshot.isLastPage || snapshot.candidates.isEmpty { return texts }
            _ = session.processKey(RimeKey.pageDown, mask: 0)
            if session.snapshot().pageNumber <= snapshot.pageNumber { return texts }
        }
        Issue.record("Candidate navigation exceeded 256 pages for \(input)")
        return texts
    }

    func contains(_ text: String, for input: String) throws {
        let shown = try candidates(input)
        let found = shown.contains(text)
        #expect(found, "\(input) should offer \(text); first candidates: \(Array(shown.prefix(15)))")
    }

    func excludes(_ text: String, for input: String) throws {
        let shown = try candidates(input)
        let found = shown.contains(text)
        #expect(!found, "\(input) unexpectedly still offers \(text); first candidates: \(Array(shown.prefix(15)))")
    }

    func commit(_ text: String, for input: String) throws {
        let session = try #require(service.makeSession())
        let composer = Composer(engine: session)
        for ch in input { _ = composer.handleKeyDown(KeyEvent(keyCode: 0, characters: String(ch))) }
        for _ in 0..<256 {
            let snapshot = composer.engineState
            if let index = snapshot.candidates.firstIndex(where: { $0.text == text }) {
                let effects = composer.choose(index: index)
                #expect(effects.contains(.commit(text)), "Selecting the imported candidate should insert its exact text: \(effects)")
                #expect(!composer.engineState.isComposing)
                #expect(composer.draft.isEmpty)
                return
            }
            if snapshot.isLastPage || snapshot.candidates.isEmpty { break }
            _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.pageDown, characters: ""))
            if composer.engineState.pageNumber <= snapshot.pageNumber { break }
        }
        Issue.record("No selectable candidate \(text) for \(input)")
    }

    func fuzzy(_ enabled: Bool) throws {
        let nan: Set<String> = ["难", "南", "男"]
        let shown = try candidates("lan")
        let hasNan = shown.contains { nan.contains($0) }
        #expect(hasNan == enabled,
                "n ↔ l should be \(enabled ? "enabled" : "disabled"); candidates: \(Array(shown.prefix(15)))")
    }

    func defaultsStillWork() throws {
        let session = try #require(service.makeSession())
        for byte in "nihao".utf8 { _ = session.processKey(Int32(byte), mask: 0) }
        let shown = session.snapshot().candidates.map(\.text)
        let hasNihao = shown.contains("你好")
        #expect(hasNihao, "The built-in nihao → 你好 must remain available: \(shown)")
        session.clearComposition()
        #expect(session.processKey(0x2c, mask: 0))
        #expect(session.takeCommit() == "，")
        session.setAsciiMode(true)
        #expect(!session.processKey(0x61, mask: 0))
        session.setAsciiMode(false)
    }

    func sync() throws -> URL {
        #expect(service.syncUserData())
        try #require(service.waitUntilReady(timeout: 90), "Learned-word sync did not finish")
        return try #require(service.userDataSyncDir).appendingPathComponent("rime_ice.userdb.txt")
    }

    func reject(_ operation: () throws -> Void) {
        do { try operation(); Issue.record("An invalid dictionary operation unexpectedly succeeded") }
        catch { #expect(!error.localizedDescription.isEmpty) }
    }
}

@Suite("Personal dictionaries: subprocess worker", .serialized,
       .enabled(if: PersonalDictionaryRimeAcceptance.worker != nil))
struct PersonalDictionaryRimeWorkerTests {
    @Test func runScenario() throws {
        let scenario = try #require(PersonalDictionaryRimeAcceptance.worker)
        let path = try #require(ProcessInfo.processInfo.environment[PersonalDictionaryRimeAcceptance.rootKey])
        let world = try PersonalDictionaryRimeWorld(root: URL(fileURLWithPath: path, isDirectory: true))
        switch scenario {
        case "import-and-commit": try importAndCommit(world)
        case "coexist-update-remove": try coexistUpdateRemove(world)
        case "fuzzy-before-import": try fuzzyBeforeImport(world)
        case "import-before-fuzzy": try importBeforeFuzzy(world)
        case "failed-imports": try failedImports(world)
        case "columns": try columns(world)
        case "learned-preservation": try learnedPreservation(world)
        case "queued-dictionary-change": try queuedDictionaryChange(world)
        case "persistence-prepare": try persistencePrepare(world)
        case "persistence-reopen": try persistenceReopen(world)
        default: Issue.record("Unknown personal-dictionary acceptance worker: \(scenario)")
        }
        print("PERSONAL_DICTIONARY_WORKER_FINISHED:\(scenario)")
    }

    private func importAndCommit(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        try world.defaultsStillWork()
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.excludes("我喜欢" + PersonalDictionaryRimeAcceptance.textA,
                           for: "woxihuan" + PersonalDictionaryRimeAcceptance.codeA)
        let file = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        let original = try Data(contentsOf: file)
        _ = try world.store.importDictionary(from: file, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.contains("我喜欢" + PersonalDictionaryRimeAcceptance.textA,
                           for: "woxihuan" + PersonalDictionaryRimeAcceptance.codeA)
        try world.defaultsStillWork()
        try world.commit(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        _ = try world.store.importDictionary(from: file, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        #expect(try world.store.list().count == 1)
        #expect(try Data(contentsOf: file) == original)
    }

    private func coexistUpdateRemove(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        for (text, code) in [(PersonalDictionaryRimeAcceptance.textA, PersonalDictionaryRimeAcceptance.codeA),
                             (PersonalDictionaryRimeAcceptance.textB, PersonalDictionaryRimeAcceptance.codeB),
                             (PersonalDictionaryRimeAcceptance.textC, PersonalDictionaryRimeAcceptance.codeC)] {
            try world.excludes(text, for: code)
        }
        let first = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        let second = try world.source("acceptance_beta", rows: ["\(PersonalDictionaryRimeAcceptance.textB)\tyan shou ci biao\t900000"],
                                      fileName: "Other vocabulary.dict.yaml")
        _ = try world.store.importDictionary(from: first, fuzzyPinyin: [])
        _ = try world.store.importDictionary(from: second, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.contains(PersonalDictionaryRimeAcceptance.textB, for: PersonalDictionaryRimeAcceptance.codeB)
        _ = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textC)\tce shi geng xin\t900000"])
        let editedOriginal = try Data(contentsOf: first)
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.excludes(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        _ = try world.store.importDictionary(from: first, fuzzyPinyin: [])
        try world.redeploy()
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.contains(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        try world.contains(PersonalDictionaryRimeAcceptance.textB, for: PersonalDictionaryRimeAcceptance.codeB)
        #expect(try world.store.list().count == 2)
        try world.store.removeDictionary(named: "acceptance_alpha", fuzzyPinyin: [])
        try world.redeploy()
        try world.excludes(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        try world.contains(PersonalDictionaryRimeAcceptance.textB, for: PersonalDictionaryRimeAcceptance.codeB)
        try world.store.removeDictionary(named: "acceptance_beta", fuzzyPinyin: [])
        try world.redeploy()
        try world.excludes(PersonalDictionaryRimeAcceptance.textB, for: PersonalDictionaryRimeAcceptance.codeB)
        try world.defaultsStillWork()
        #expect(try Data(contentsOf: first) == editedOriginal)
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    private func fuzzyBeforeImport(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        try world.fuzzy(false)
        _ = try FuzzyPinyin.apply(["n-l"], schema: world.schema, userDir: world.user)
        try world.redeploy()
        try world.fuzzy(true)
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        let file = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        _ = try world.store.importDictionary(from: file, fuzzyPinyin: ["n-l"])
        try world.redeploy()
        try world.fuzzy(true)
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        _ = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textC)\tce shi geng xin\t900000"])
        _ = try world.store.importDictionary(from: file, fuzzyPinyin: ["n-l"])
        try world.redeploy()
        try world.fuzzy(true)
        try world.contains(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        try world.store.removeDictionary(named: "acceptance_alpha", fuzzyPinyin: ["n-l"])
        try world.redeploy()
        try world.fuzzy(true)
        try world.excludes(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        _ = try FuzzyPinyin.apply([], schema: world.schema, userDir: world.user)
        try world.redeploy()
        try world.fuzzy(false)
    }

    private func importBeforeFuzzy(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        let file = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        _ = try world.store.importDictionary(from: file, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.fuzzy(false)
        for ids in [["n-l"], [], ["n-l"]] {
            _ = try FuzzyPinyin.apply(ids, schema: world.schema, userDir: world.user)
            try world.redeploy()
            try world.fuzzy(!ids.isEmpty)
            try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        }
        try world.store.removeDictionary(named: "acceptance_alpha", fuzzyPinyin: ["n-l"])
        try world.redeploy()
        try world.fuzzy(true)
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
    }

    private func queuedDictionaryChange(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        try world.defaultsStillWork()
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.excludes(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        let source = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        _ = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        // The first merged dictionary needs a full real compilation in this fresh user directory. Change both
        // vocabulary and spelling while that older deployment is still active; do not sleep through the race.
        world.service.redeploy(invalidateGeneratedSchema: true)
        try #require(!world.service.isReady, "The fixture must start older maintenance")
        _ = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textC)\tce shi geng xin\t900000"])
        _ = try world.store.importDictionary(from: source, fuzzyPinyin: ["n-l"])
        try #require(!world.service.isReady, "The second change must arrive during the older deployment")
        world.service.redeploy(invalidateGeneratedSchema: true)
        #expect(!world.service.isReady, "An older result cannot make the queued dictionary change ready")
        let premature = world.service.makeSession()
        #expect(premature == nil, "Do not expose a session before the queued deployment finishes")
        try #require(world.service.waitUntilReady(timeout: 180), "The queued dictionary deployment did not finish")
        if case .succeeded = world.service.deploymentStatus {} else {
            Issue.record("The latest queued deployment must report success")
        }
        #expect(world.service.deploymentError == nil)
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.contains(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        try world.fuzzy(true)
        try world.defaultsStillWork()
    }

    private func failedImports(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        let source = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        _ = try world.store.importDictionary(from: source, fuzzyPinyin: ["n-l"])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        _ = try world.source(rows: ["a replacement without an explicit code"])
        world.reject { _ = try world.store.importDictionary(from: source, fuzzyPinyin: ["n-l"]) }
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.fuzzy(true)
        let dependent = world.sources.appendingPathComponent("Dependent.dict.yaml")
        try "---\nname: acceptance_dependent\nversion: \"1\"\nimport_tables: [missing_dependency]\n...\n"
            .write(to: dependent, atomically: true, encoding: .utf8)
        world.reject { _ = try world.store.importDictionary(from: dependent, fuzzyPinyin: ["n-l"]) }
        world.reject {
            _ = try world.store.importDictionary(from: world.sources.appendingPathComponent("Missing.dict.yaml"), fuzzyPinyin: ["n-l"])
        }
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.fuzzy(true)
        try world.defaultsStillWork()
        #expect(try world.store.list().map(\.name) == ["acceptance_alpha"])
    }

    private func columns(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.excludes(PersonalDictionaryRimeAcceptance.textB, for: PersonalDictionaryRimeAcceptance.codeB)
        try world.excludes(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        let standard = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"],
                                        columns: "[text, code, weight]")
        _ = try world.store.importDictionary(from: standard, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        let unweighted = try world.source("acceptance_unweighted", rows: [
            "\(PersonalDictionaryRimeAcceptance.textC)\tce shi geng xin"
        ], columns: "[text, code]", fileName: "Unweighted.dict.yaml")
        _ = try world.store.importDictionary(from: unweighted, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
        let reordered = try world.source("acceptance_reordered", rows: ["yan shou ci biao\t900000\t\(PersonalDictionaryRimeAcceptance.textB)"],
                                         columns: "[code, weight, text]", fileName: "Reordered.dict.yaml")
        do {
            _ = try world.store.importDictionary(from: reordered, fuzzyPinyin: [])
            try world.redeploy()
            try world.contains(PersonalDictionaryRimeAcceptance.textB, for: PersonalDictionaryRimeAcceptance.codeB)
        } catch {
            let explanation = error.localizedDescription.lowercased()
            #expect(explanation.contains("column") || explanation.contains("layout") || explanation.contains("列"),
                    "Unsupported named columns need an actionable explanation: \(error)")
            try world.redeploy()
            try world.excludes(PersonalDictionaryRimeAcceptance.textB, for: PersonalDictionaryRimeAcceptance.codeB)
            #expect(try world.store.list().count == 2)
        }
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.contains(PersonalDictionaryRimeAcceptance.textC, for: PersonalDictionaryRimeAcceptance.codeC)
    }

    private func learnedPreservation(_ world: PersonalDictionaryRimeWorld) throws {
        let native = world.user.appendingPathComponent("custom_phrase.txt")
        let nativeBytes = Data("\(PersonalDictionaryRimeAcceptance.nativeText)\t\(PersonalDictionaryRimeAcceptance.nativeCode)\t1\n".utf8)
        try nativeBytes.write(to: native)
        let unrelated = world.user.appendingPathComponent("unrelated.custom.yaml")
        let unrelatedBytes = Data("# My unrelated schema\npatch:\n  menu/page_size: 7\n".utf8)
        try unrelatedBytes.write(to: unrelated)
        try world.start()
        try world.contains(PersonalDictionaryRimeAcceptance.nativeText, for: PersonalDictionaryRimeAcceptance.nativeCode)
        try world.excludes(PersonalDictionaryRimeAcceptance.learnedText, for: "nihao")
        try world.commit("你好", for: "nihao")
        let syncRoot = world.root.appendingPathComponent("Simulated local sync", isDirectory: true)
        _ = try RimeSync.setSyncDir(syncRoot, userDataDir: world.user)
        let beforeFile = try world.sync()
        let before = try String(contentsOf: beforeFile, encoding: .utf8)
        try #require(before.contains("你好"), "The fixture must first create an actual learned-word record")
        // Seed a word learned on another installation through librime's existing public sync mechanism.
        let installation = try String(contentsOf: world.user.appendingPathComponent("installation.yaml"), encoding: .utf8)
        let ownID = try #require(installation.components(separatedBy: "\n").first { $0.hasPrefix("installation_id:") })
            .dropFirst("installation_id:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        let other = syncRoot.appendingPathComponent("acceptance-other-device", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try before.replacingOccurrences(of: "你好", with: PersonalDictionaryRimeAcceptance.learnedText)
            .replacingOccurrences(of: ownID, with: "acceptance-other-device")
            .write(to: other.appendingPathComponent("rime_ice.userdb.txt"), atomically: true, encoding: .utf8)
        _ = try world.sync()
        try world.contains(PersonalDictionaryRimeAcceptance.learnedText, for: "nihao")
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        let source = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        _ = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.contains(PersonalDictionaryRimeAcceptance.learnedText, for: "nihao")
        let duringFile = try world.sync()
        let during = try String(contentsOf: duringFile, encoding: .utf8)
        #expect(duringFile == beforeFile, "Imports must retain the rime_ice learned-database identity")
        #expect(during.contains(PersonalDictionaryRimeAcceptance.learnedText))
        #expect(!during.contains(PersonalDictionaryRimeAcceptance.textA), "An unselected imported word is local vocabulary, not learned data")
        let copied = try FileManager.default.contentsOfDirectory(atPath: duringFile.deletingLastPathComponent().path)
        #expect(copied.allSatisfy { $0.hasSuffix(".userdb.txt") }, "Imported sources and customization are not synced: \(copied)")
        _ = try FuzzyPinyin.apply(["n-l"], schema: world.schema, userDir: world.user)
        try world.redeploy()
        _ = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textC)\tce shi geng xin\t900000"])
        _ = try world.store.importDictionary(from: source, fuzzyPinyin: ["n-l"])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.learnedText, for: "nihao")
        try world.store.removeDictionary(named: "acceptance_alpha", fuzzyPinyin: ["n-l"])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.learnedText, for: "nihao")
        try world.contains(PersonalDictionaryRimeAcceptance.nativeText, for: PersonalDictionaryRimeAcceptance.nativeCode)
        #expect(try Data(contentsOf: native) == nativeBytes)
        #expect(try Data(contentsOf: unrelated) == unrelatedBytes)
        let afterFile = try world.sync()
        #expect(afterFile == beforeFile)
        #expect(try String(contentsOf: afterFile, encoding: .utf8).contains(PersonalDictionaryRimeAcceptance.learnedText))
        let afterInstallation = try String(contentsOf: world.user.appendingPathComponent("installation.yaml"), encoding: .utf8)
        #expect(afterInstallation.contains(ownID), "The Rime installation identity survives dictionary changes")
    }

    private func persistencePrepare(_ world: PersonalDictionaryRimeWorld) throws {
        try world.start()
        try world.excludes(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        let source = try world.source(rows: ["\(PersonalDictionaryRimeAcceptance.textA)\tce shi ci ku\t900000"])
        _ = try world.store.importDictionary(from: source, fuzzyPinyin: [])
        try world.redeploy()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
    }

    private func persistenceReopen(_ world: PersonalDictionaryRimeWorld) throws {
        #expect(try world.store.list().map(\.name) == ["acceptance_alpha"])
        #expect(try world.store.list().first?.entryCount == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.sources.path).isEmpty)
        try world.start()
        try world.contains(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.commit(PersonalDictionaryRimeAcceptance.textA, for: PersonalDictionaryRimeAcceptance.codeA)
        try world.defaultsStillWork()
    }
}
