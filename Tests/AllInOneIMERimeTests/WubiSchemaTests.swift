import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Wubi 86 (`PinyinScheme.wubi`) on rime-wubi's schema and the real librime, set up as the app sets it up: the data the
/// app carries (`make deps`' rime-wubi) linked into the pack (`LanguagePackStore.linkData`), the patch the settings
/// write for its schema, the schema list; then typed, in a process of its own (`RimeWorker`). Beyond the acceptance file
/// (Acceptance/WubiRimeTests.swift): what the patch takes from rime-ice's data (punctuation, `z`'s lookup), learning off,
/// the app's tap of Shift, the links.
struct WubiSchemaTests {
    let root = TestScratch.temporary("rime-wubi-\(UUID().uuidString)")
    /// Where `make deps` puts the Wubi data the app carries (Contents/SharedSupport/rime-wubi).
    static let data = RimeFixture.thirdParty.appendingPathComponent("rime-wubi")
    static var runs: Bool {
        RimeWorker.scenario == nil && (RimeWorker.dataAvailable && FileManager.default.fileExists(atPath: data.path)
            && FileManager.default.fileExists(atPath: TraditionalChineseRimeTests.openCC.path) || RimeWorker.required)
    }

    /// The data the app links is what `make deps` fetched, rime-wubi's license beside it; the schema is as the patch
    /// expects it: no switch of characters, no filters, what it takes from repositories the app hasn't.
    @Test(.enabled(if: runs, "needs the Wubi data (make deps)"))
    func theDataIsRimeWubis() throws {
        for name in PinyinScheme.wubiData + ["LICENSE", "AUTHORS"] {
            #expect(FileManager.default.fileExists(atPath: Self.data.appendingPathComponent(name).path), "\(name)")
        }
        let license = try String(contentsOf: Self.data.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(license.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
        let schema = try String(contentsOf: Self.data.appendingPathComponent("wubi86.schema.yaml"), encoding: .utf8)
        #expect(ChineseCharacters.switchIndex(ChineseCharacters.switchName, inSchema: schema) == nil)
        #expect(ShapeCode.filters(ofSchema: schema).isEmpty && !schema.contains("auto_select: true"))
        #expect(schema.contains("import_preset: symbols") && schema.contains("dictionary: pinyin_simp"))
    }

    @Test(.enabled(if: runs, "needs rime-ice, the Wubi data and OpenCC's data (make deps)"))
    func deployedAndTypedAsTheAppSetsItUp() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("wubi-app", root: root)
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "wubi-app": { root in
            let fm = FileManager.default
            let pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua",
                                                                 script: String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8))
            // The pack has no Wubi data of its own: the app's linked in, as `RimeStartup` links it.
            for name in PinyinScheme.wubiData { try? fm.removeItem(at: pack.appendingPathComponent(name)) }
            let store = LanguagePackStore(directory: root.appendingPathComponent("LanguagePacks"))
            try store.linkData(.chinesePinyin, from: WubiSchemaTests.data, names: PinyinScheme.wubiData)
            for name in PinyinScheme.wubiData {
                #expect(try fm.destinationOfSymbolicLink(atPath: pack.appendingPathComponent(name).path)
                        == WubiSchemaTests.data.appendingPathComponent(name).path)
            }
            let user = root.appendingPathComponent("Rime")
            // As `RimeStartup` writes them: the patches (f ↔ h for full pinyin, Taiwan's characters), the schema list.
            #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .wubi,
                                          schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user) == .written)
            #expect(try PinyinScheme.applySchemaList(.wubi, userDir: user) == .written)
            let logs = root.appendingPathComponent("logs")
            try fm.createDirectory(at: logs, withIntermediateDirectories: true)
            try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: logs, fullCheck: true,
                                         openCCDir: TraditionalChineseRimeTests.openCC)
            try #require(RimeService.shared.waitUntilReady(timeout: 180))
            #expect(RimeService.shared.deploymentStatus == .succeeded)
            let session = try #require(RimeService.shared.makeSession())
            // Deployed without an error logged (what the Doctor would report): the punctuation and the dictionary rime-wubi
            // takes from rime-prelude and rime-pinyin-simp are rime-ice's.
            for name in try fm.contentsOfDirectory(atPath: logs.path) where name.contains(".INFO") {
                let text = try String(contentsOf: logs.appendingPathComponent(name), encoding: .utf8)
                let errors = text.split(separator: "\n").filter { $0.range(of: #"^E\d{8} "#, options: .regularExpression) != nil }
                #expect(errors.isEmpty, "\(errors.prefix(5))")
            }
            #expect(session.schema == "rime_ice", "a new session starts in full pinyin")
            #expect(session.selectSchema("wubi86") && session.schema == "wubi86")
            #expect(session.api.pointee.get_option(session.id, "traditionalization") != 0, "Taiwan's characters")
            func type(_ keys: String) -> EngineSnapshot {
                session.clearComposition()
                for byte in keys.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
                return session.snapshot()
            }
            func words(_ keys: String) -> [String] { type(keys).candidates.prefix(5).map(\.text) }
            // Taiwan's characters (国 made 國); a phrase's code.
            #expect(words("lgyi").first == "國" && words("wqvb").first == "你好")
            // "z" then pinyin: looked up in rime-ice's dictionary, its Wubi code beside it.
            let lookup = type("zwo").candidates
            #expect(lookup.contains { $0.text == "我" && $0.comment.contains("trnt") }, "\(lookup.prefix(5))")
            // Punctuation as pinyin's: ";" after a code puts the first candidate in, then the mark; Taiwan's quotation marks.
            _ = type("gggg")
            _ = session.processKey(0x3B, mask: 0)
            #expect(session.takeCommit() == "王；" && !session.snapshot().isComposing)
            _ = session.processKey(0x22, mask: RimeKey.shiftMask)
            #expect(session.takeCommit() == "「")
            // A tap of Shift commits what is composed, converted, and switches to Latin.
            func tapShift() -> String? {
                _ = session.processKey(RimeKey.shiftL, mask: 0)
                _ = session.processKey(RimeKey.shiftL, mask: RimeKey.releaseMask)
                return session.takeCommit()
            }
            _ = type("lgyi")
            #expect(tapShift() == "國" && session.snapshot().isAsciiMode && !session.snapshot().isComposing)
            session.setAsciiMode(false)
            // Nothing learned: Space, a digit and a tap of Shift put in the same, without librime's commit.
            session.learns = false
            _ = type("wqvb")
            #expect(session.processKey(RimeKey.space, mask: 0) && session.takeCommit() == "你好" && !session.snapshot().isComposing)
            _ = type("wqvb")
            #expect(session.selectCandidate(onPage: 1) && session.takeCommit() == "您好")
            _ = type("gggg")
            #expect(tapShift() == "王" && session.snapshot().isAsciiMode && !session.snapshot().isComposing)
            session.setAsciiMode(false)
            session.learns = true
            // The app's tap of Shift (`Composer`): what is composed goes in converted.
            let composer = Composer(engine: session, actionKey: .enter)
            composer.pinyinScheme = .wubi
            session.clearComposition()
            for character in "gggg" { _ = composer.handleKeyDown(key(character)) }
            #expect(composer.engineState.isComposing)
            _ = composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
            let tap = composer.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
            #expect(tap.contains(.commit("王")), "\(tap)")
            #expect(composer.engineState.isAsciiMode && !composer.engineState.isComposing)
            session.setAsciiMode(false)

            // Full pinyin again on the same session, its fuzzy pinyin kept; Wubi's patch goes with another way.
            #expect(session.selectSchema("rime_ice"))
            #expect(words("nihao").contains("你好"))
            #expect(words("fong").contains("红") || words("fong").contains("紅"), "f ↔ h in full pinyin")
            #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .full,
                                          schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user) == .written)
            #expect(!fm.fileExists(atPath: user.appendingPathComponent("wubi86.custom.yaml").path))
            // The app without the data: the links go.
            try store.linkData(.chinesePinyin, from: nil, names: PinyinScheme.wubiData)
            #expect(PinyinScheme.wubiData.allSatisfy { (try? fm.attributesOfItem(atPath: pack.appendingPathComponent($0).path)) == nil })
        },
    ]
}
