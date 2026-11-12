import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Shuangpin (`PinyinScheme`) on rime-ice's own Shuangpin schemas and the real librime: the spelling rules the core reads
/// the schemes' letters by are the schemas' own, and a scheme picked is deployed and typed with as the app sets it up
/// (the patch the settings write for its schema, the schema list), in a process of its own (`RimeWorker`).
struct ShuangpinSchemaTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-shuangpin-\(UUID().uuidString)")
    static var runs: Bool {
        RimeWorker.scenario == nil && (RimeWorker.dataAvailable && FileManager.default.fileExists(atPath: TraditionalChineseRimeTests.openCC.path)
            || RimeWorker.required)
    }

    static func schemaText(_ scheme: PinyinScheme) throws -> String {
        try String(contentsOf: RimeFixture.sharedData.appendingPathComponent("\(scheme.schema).schema.yaml"), encoding: .utf8)
    }

    /// Each scheme's spelling rules (`PinyinScheme.algebra`, which `Pinyin.Reading` reads the letters by) are its
    /// schema's, in order; and each schema has what the patch needs: its Traditional switch, its spelling rules.
    @Test(.enabled(if: RimeWorker.dataAvailable || RimeWorker.required, "needs rime-ice (make deps)"))
    func theSchemesRulesAreRimeIces() throws {
        for scheme in PinyinScheme.shuangpin {
            let text = try Self.schemaText(scheme)
            #expect(FuzzyPinyin.algebra(ofSchema: text) == scheme.algebra, "\(scheme)")
            #expect(ChineseCharacters.taiwan.patch(schema: text) != nil, "\(scheme): the Traditional switch")
            #expect(FuzzyPinyin.patch(["z-zh"], schema: text) != nil, "\(scheme): fuzzy pinyin's place")
            #expect(text.contains("schema_id: \(scheme.schema)\n"), "\(scheme)")
        }
        #expect(PinyinScheme.full.algebra.isEmpty)
    }

    @Test(.enabled(if: runs, "needs rime-ice and OpenCC's data (make deps)"))
    func deployedAndTypedAsTheAppSetsItUp() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("shuangpin-app", root: root)
    }

    /// What librime commits after the part picked on Return, when nothing is learned (`RimeSession.learns` off): the
    /// letters typed after it, not as many as the preedit spells out ("xiang" for "xl").
    @Test func lettersAfterThePickAreTheKeysTyped() {
        func composition(_ preedit: String, picked: String) -> RimeSession.Composition {
            let bytes = Array(preedit.utf8), start = picked.utf8.count
            return RimeSession.Composition(preedit: bytes, selection: start..<bytes.count, hasMenu: true, preview: "")
        }
        #expect(composition("你好xiang ma", picked: "你好").lettersAfterThePick(input: "nihcxlma", shuangpin: true) == "xlma")
        #expect(composition("你好xiang m", picked: "你好").lettersAfterThePick(input: "nihcxlm", shuangpin: true) == "xlm")
        #expect(composition("你好 e", picked: "你好").lettersAfterThePick(input: "nihcee", shuangpin: true) == "ee")
        #expect(composition("你好 ma", picked: "你好").lettersAfterThePick(input: "nihaoma") == "ma", "full pinyin as before")
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "shuangpin-app": { root in
            let pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua",
                                                                 script: String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8))
            let user = root.appendingPathComponent("Rime")
            // As `RimeStartup` writes them: the patch for both schemas (f ↔ h, Taiwan's characters), and the schema list.
            let outcome = try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .xiaohe,
                                                schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
            #expect(outcome == .written)
            #expect(try PinyinScheme.applySchemaList(.xiaohe, userDir: user) == .written)
            let patch = try String(contentsOf: user.appendingPathComponent("double_pinyin_flypy.custom.yaml"), encoding: .utf8)
            #expect(patch.contains("lua_filter@*allinoneime_removed") && patch.contains("\"derive/^h/f/\""))
            try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: nil, fullCheck: true,
                                         openCCDir: TraditionalChineseRimeTests.openCC)
            try #require(RimeService.shared.waitUntilReady(timeout: 180))
            #expect(RimeService.shared.deploymentStatus == .succeeded)
            let session = try #require(RimeService.shared.makeSession())
            #expect(session.schema == "rime_ice", "a new session starts in full pinyin")
            // Not deployed: refused, full pinyin's kept.
            #expect(!session.selectSchema("double_pinyin_mspy") && session.schema == "rime_ice")
            #expect(session.selectSchema("double_pinyin_flypy") && session.schema == "double_pinyin_flypy")
            func type(_ letters: String) -> [String] {
                session.clearComposition()
                for byte in letters.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
                return session.snapshot().candidates.prefix(5).map(\.text)
            }
            #expect(type("nihc").contains("你好"))
            // Every syllable's keys as the core reads Xiaohe (`Pinyin.Reading`, with f ↔ h) are librime's: each types a
            // character of its own, but for two syllables of the core's list (`Pinyin.syllables`) rime-ice has no
            // character of: nia and nun (full pinyin reads them as ni a, nu n).
            let rules = FuzzyPinyin.pairs.filter { $0.id == "f-h" }.flatMap(\.rules) + PinyinScheme.xiaohe.algebra
            let codes = Pinyin.reading(fuzzy: ["f-h"], scheme: .xiaohe).spellings
            #expect(codes.count > 400 && codes.allSatisfy { $0.count == 2 }, "\(codes.filter { $0.count != 2 })")
            let unread = codes.filter { code in !type(code).contains { $0.containsHan && $0.count == 1 } }
            let syllables = Pinyin.syllables.filter { !SpellingAlgebra.apply(rules, to: [$0]).isDisjoint(with: unread) }
            #expect(syllables.isSubset(of: ["nia", "nun"]), "\(unread.sorted()) from \(syllables.sorted())")
            #expect(type("whlo").contains("網路"), "Taiwan's words in Shuangpin")
            #expect(type("fsse").contains("紅色"), "f ↔ h: fong for hong")
            session.setRemovedCandidates(["你好"])
            #expect(!type("nihc").contains("你好"), "the candidates removed are left out")
            session.setRemovedCandidates([])

            // Nothing learned: Return after a part picked puts in the part and the keys typed after it.
            session.learns = false
            session.clearComposition()
            for byte in "nihcxlma".utf8 { _ = session.processKey(Int32(byte), mask: 0) }
            var picked = false
            for _ in 0..<6 where !picked {
                if let index = session.snapshot().candidates.firstIndex(where: { $0.text == "你好" }) {
                    picked = session.selectCandidate(onPage: index)
                } else {
                    _ = session.processKey(RimeKey.pageDown, mask: 0)
                }
            }
            try #require(picked, "你好 on the first pages of nihcxlma")
            #expect(session.processKey(RimeKey.returnKey, mask: 0))
            #expect(session.takeCommit() == "你好xlma")

            // Full pinyin again on the same session, and the list back to it alone (the scheme's patch removed).
            #expect(session.selectSchema("rime_ice"))
            session.learns = true
            #expect(type("nihao").contains("你好"))
            #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .full,
                                          schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user) == .written)
            #expect(!FileManager.default.fileExists(atPath: user.appendingPathComponent("double_pinyin_flypy.custom.yaml").path))
            #expect(try PinyinScheme.applySchemaList(.full, userDir: user) == .written)
        },
    ]
}
