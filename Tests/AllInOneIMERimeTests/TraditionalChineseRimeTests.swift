import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Pinyin in Traditional characters (`ChineseCharacters`) on the real librime and rime-ice, with OpenCC's data as `make
/// deps` takes it from librime's own build (ThirdParty/opencc) and the app copies it into the Rime user folder: Taiwan's
/// characters and words, Hong Kong's, and Simplified as before, each through the patch the settings write and a redeploy
/// as a change makes. In a process of its own each (`RimeWorker`): librime starts once per process, and these start it
/// with a user folder of their own.
struct TraditionalChineseRimeTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-traditional-\(UUID().uuidString)")
    static let openCC = RimeFixture.thirdParty.appendingPathComponent("opencc", isDirectory: true)
    static let schema = RimeFixture.sharedData.appendingPathComponent("rime_ice.schema.yaml")
    static var runs: Bool {
        RimeWorker.scenario == nil && (RimeWorker.dataAvailable && FileManager.default.fileExists(atPath: openCC.path) || RimeWorker.required)
    }

    @Test(.enabled(if: runs, "no OpenCC data in ThirdParty/opencc (make deps)"))
    func taiwanThenHongKongThenSimplified() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("traditional-switching", root: root)
    }

    @Test(.enabled(if: runs, "no OpenCC data in ThirdParty/opencc (make deps)"))
    func withoutTheDataPinyinStaysSimplifiedAndTheLogSaysSo() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("traditional-without-data", root: root)
    }

    // MARK: The copy into the user folder

    var shared: URL { root.appendingPathComponent("opencc-shared") }
    var user: URL { root.appendingPathComponent("user") }

    func bundled(_ text: String) throws {
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        for name in ChineseCharacters.openCCFiles { try Data((text + " " + name).utf8).write(to: shared.appendingPathComponent(name)) }
    }

    func copied(_ name: String) throws -> String {
        try String(contentsOf: user.appendingPathComponent("opencc/" + name), encoding: .utf8)
    }

    /// Every file copied, copied again when the app's change (an update), and the user's own left alone; provided (what
    /// the Doctor reads, `providedOpenCC`) for the characters typed while each of theirs is the copy made, since the
    /// newest copy's time.
    @Test func theAppsDataIsCopiedAsTheLunarDatabaseIs() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        func provided(_ characters: ChineseCharacters) -> Date? { RimeService.providedOpenCC(userDataDir: user, for: characters) }
        try bundled("v1")
        #expect(provided(.taiwan) == nil)
        let before = Date().addingTimeInterval(-1)
        try RimeService.prepareOpenCC(from: shared, userDataDir: user)
        for name in ChineseCharacters.openCCFiles { #expect(try copied(name) == "v1 " + name) }
        let since = try #require(provided(.taiwan))
        #expect(since > before && since <= Date() && provided(.hongkong) != nil && provided(.simplified) == nil, "\(since)")
        try RimeService.prepareOpenCC(from: shared, userDataDir: user)
        #expect(try copied("s2twp.json") == "v1 s2twp.json" && provided(.taiwan) == since, "not copied again")
        // The user's own s2hk.json; then the app is updated.
        try Data("mine".utf8).write(to: user.appendingPathComponent("opencc/s2hk.json"))
        try bundled("v2, an update")
        try RimeService.prepareOpenCC(from: shared, userDataDir: user)
        #expect(try copied("s2twp.json") == "v2, an update s2twp.json" && copied("STPhrases.ocd2") == "v2, an update STPhrases.ocd2")
        #expect(try copied("s2hk.json") == "mine")
        #expect(provided(.hongkong) == nil, "the user's own s2hk.json isn't the app's")
        #expect(try #require(provided(.taiwan)) >= since, "a Taiwan user doesn't use it")
        // `opencc` a file: nothing copied, only logged; pinyin starts all the same (librime's own run, in the scenarios).
        try FileManager.default.removeItem(at: user)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: user.appendingPathComponent("opencc"))
        let heard = Locked<[String]>(initialState: [])
        let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
        defer { stop() }
        RimeService.supplyOpenCC(from: shared, userDataDir: user)
        #expect(heard.withLock { $0 }.contains { $0.contains("OpenCC data not copied") })
    }

    /// The bundle's files are exactly what the conversions name: each config's dictionaries are there.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: openCC.path) || RimeFixture.dataRequired))
    func theDataHasEveryFileItsConfigsName() throws {
        /// Every "file" a config names, however deep.
        func files(_ value: Any) -> [String] {
            if let object = value as? [String: Any] {
                if let file = object["file"] as? String { return [file] }
                return object.values.flatMap(files)
            }
            return (value as? [Any])?.flatMap(files) ?? []
        }
        for config in ChineseCharacters.openCCFiles where config.hasSuffix(".json") {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.openCC.appendingPathComponent(config)))
            let names = files(json)
            #expect(!names.isEmpty && names.allSatisfy(ChineseCharacters.openCCFiles.contains), "\(config): \(names)")
            // The files the Doctor checks for the characters that use it (`openCCData`): exactly these.
            for characters in ChineseCharacters.allCases where characters.openCCConfig == config {
                #expect(Set(characters.openCCData) == Set([config] + names), "\(characters): \(characters.openCCData)")
            }
        }
        let present = try FileManager.default.contentsOfDirectory(atPath: Self.openCC.path)
        #expect(Set(present) == Set(ChineseCharacters.openCCFiles))
    }

    // MARK: Scenarios

    /// The first candidate for `pinyin`, the composition cleared after.
    static func first(_ pinyin: String, in session: RimeSession) -> String? {
        session.clearComposition()
        type(pinyin, into: session)
        defer { session.clearComposition() }
        return session.snapshot().candidates.first?.text
    }

    /// What `"` and `'` put in, outside a composition.
    static func quotes(in session: RimeSession) -> String {
        var text = ""
        for byte in [0x22, 0x22, 0x27, 0x27] as [Int32] {
            _ = session.processKey(byte, mask: 0)
            text += session.takeCommit() ?? ""
        }
        return text
    }

    /// The patch the settings write (`RimeFuzzy`, `FuzzyPinyin.apply`), and a redeploy if it changed, as a change makes.
    static func pick(_ characters: ChineseCharacters, user: URL, deployed: Bool = true) throws -> FuzzyPinyin.Outcome {
        let outcome = try FuzzyPinyin.apply([], characters: characters, schema: schema, userDir: user)
        if deployed, outcome == .written || outcome == .removed {
            RimeService.shared.redeploy()
            try #require(RimeService.shared.waitUntilReady(timeout: 120))
        }
        return outcome
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "traditional-switching": { root in
            let user = root.appendingPathComponent("Rime")
            let service = RimeService.shared
            #expect(try pick(.taiwan, user: user, deployed: false) == .written)
            try service.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil, fullCheck: true, openCCDir: openCC)
            try #require(service.waitUntilReady(timeout: 120))
            #expect(FileManager.default.fileExists(atPath: user.appendingPathComponent("opencc/STPhrases.ocd2").path))
            var session = try #require(service.makeSession())
            // Taiwan's characters and words.
            #expect(first("ruanjian", in: session) == "軟體")
            #expect(first("wangluo", in: session) == "網路")
            #expect(first("xinxi", in: session) == "資訊")
            #expect(quotes(in: session) == "「」『』")
            // Each session starts Traditional (the switch reset on), whatever the last one left.
            _ = service.api.pointee.set_option(session.id, "traditionalization", 0)
            #expect(first("ruanjian", in: session) == "软件")
            session = try #require(service.makeSession())
            #expect(first("ruanjian", in: session) == "軟體")
            // Hong Kong's.
            #expect(try pick(.hongkong, user: user) == .written)
            session = try #require(service.makeSession())
            #expect(first("ruanjian", in: session) == "軟件")
            #expect(first("wangluo", in: session) == "網絡")
            #expect(quotes(in: session) == "「」『』")
            // Simplified again: as before, the patch gone.
            #expect(try pick(.simplified, user: user) == .removed)
            session = try #require(service.makeSession())
            #expect(first("ruanjian", in: session) == "软件")
            #expect(first("wangluo", in: session) == "网络")
            #expect(quotes(in: session) == "“”‘’")
        },
        "traditional-without-data": { root in
            // Taiwan's picked, but no OpenCC data for librime: Simplified candidates, and its log says why.
            let user = root.appendingPathComponent("Rime"), logs = root.appendingPathComponent("logs")
            let service = RimeService.shared
            #expect(try pick(.taiwan, user: user, deployed: false) == .written)
            try service.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: logs, fullCheck: true)
            try #require(service.waitUntilReady(timeout: 120))
            let session = try #require(service.makeSession())
            #expect(first("ruanjian", in: session) == "软件")
            let lines = try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.contains(".ERROR.") }
                .flatMap { ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
            #expect(Doctor.summarizeLogLines(lines).contains { $0.hasPrefix(Doctor.failedOpenCC) }, "\(lines)")
        },
    ]
}

extension RimeEngineTests {
    /// This process's librime, as the other engine tests have it (no patch): Simplified, as before
    /// (`TraditionalChineseRimeTests`).
    @Test func pinyinIsSimplifiedWithoutTheCharactersPatch() throws {
        let session = try RimeFixture.session()
        defer { session.clearComposition() }
        #expect(TraditionalChineseRimeTests.first("ruanjian", in: session) == "软件")
        #expect(TraditionalChineseRimeTests.first("wangluo", in: session) == "网络")
    }
}
