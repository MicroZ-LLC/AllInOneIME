import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Zhuyin (`PinyinScheme.zhuyin`) on rime-bopomofo's schema and the real librime, set up as the app sets it up: the data
/// the app carries (`make deps`' rime-zhuyin) linked into the pack (`LanguagePackStore.linkData`), the patch the settings
/// write for its schema, the schema list; then typed on the Standard (Daqian) keys, in a process of its own (`RimeWorker`).
struct ZhuyinSchemaTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-zhuyin-\(UUID().uuidString)")
    /// Where `make deps` puts the Zhuyin data the app carries (Contents/SharedSupport/rime-zhuyin).
    static let data = RimeFixture.thirdParty.appendingPathComponent("rime-zhuyin")
    static var runs: Bool {
        RimeWorker.scenario == nil && (RimeWorker.dataAvailable && FileManager.default.fileExists(atPath: data.path)
            && FileManager.default.fileExists(atPath: TraditionalChineseRimeTests.openCC.path) || RimeWorker.required)
    }

    /// The data the app links is what `make deps` fetched, each repository's license beside it; the schema has what the
    /// patch needs: its characters' switch, the translators the patch keeps.
    @Test(.enabled(if: runs, "needs the Zhuyin data (make deps)"))
    func theDataIsRimeBopomofos() throws {
        for name in PinyinScheme.zhuyinData {
            #expect(FileManager.default.fileExists(atPath: Self.data.appendingPathComponent(name).path), "\(name)")
        }
        for repository in ["rime-bopomofo", "rime-terra-pinyin", "rime-stroke", "rime-essay"] {
            let license = try String(contentsOf: Self.data.appendingPathComponent("\(repository)/LICENSE"), encoding: .utf8)
            #expect(license.contains("GNU LESSER GENERAL PUBLIC LICENSE"), "\(repository)")
        }
        let schema = try String(contentsOf: Self.data.appendingPathComponent("bopomofo.schema.yaml"), encoding: .utf8)
        #expect(ChineseCharacters.optionSwitch(with: "zh_hant_tw", inSchema: schema)?.index == 2)
        #expect(ChineseCharacters.allCases.allSatisfy { $0.patch(schema: schema) != nil })
        // The patch's translators are the schema's own but rime-ice's custom phrases.
        let translators = ["punct_translator", "table_translator@custom_phrase", "reverse_lookup_translator", "script_translator"]
        #expect(schema.contains("  translators:\n" + translators.map { "    - \($0)\n" }.joined()))
        #expect(schema.contains("dictionary: terra_pinyin") && schema.contains("- stroke"))
    }

    @Test(.enabled(if: runs, "needs rime-ice, the Zhuyin data and OpenCC's data (make deps)"))
    func deployedAndTypedAsTheAppSetsItUp() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("zhuyin-app", root: root)
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "zhuyin-app": { root in
            let fm = FileManager.default
            let pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua",
                                                                 script: String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8))
            // The pack has no Zhuyin data of its own: the app's linked in, as `RimeStartup` links it.
            for name in PinyinScheme.zhuyinData { try? fm.removeItem(at: pack.appendingPathComponent(name)) }
            let store = LanguagePackStore(directory: root.appendingPathComponent("LanguagePacks"))
            try store.linkData(.chinesePinyin, from: ZhuyinSchemaTests.data, names: PinyinScheme.zhuyinData)
            for name in PinyinScheme.zhuyinData {
                #expect(try fm.destinationOfSymbolicLink(atPath: pack.appendingPathComponent(name).path)
                        == ZhuyinSchemaTests.data.appendingPathComponent(name).path)
            }
            try store.linkData(.chinesePinyin, from: ZhuyinSchemaTests.data, names: PinyinScheme.zhuyinData)  // as it is: kept
            let user = root.appendingPathComponent("Rime")
            // As `RimeStartup` writes them: the patches (f ↔ h for full pinyin, Taiwan's characters), the schema list.
            let outcome = try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .zhuyin,
                                                schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
            #expect(outcome == .written)
            #expect(try PinyinScheme.applySchemaList(.zhuyin, userDir: user) == .written)
            let patch = try String(contentsOf: user.appendingPathComponent("bopomofo.custom.yaml"), encoding: .utf8)
            #expect(patch.contains("lua_filter@*allinoneime_removed") && patch.contains("zh_hant_tw/opencc_config: t2tw.json"))
            #expect(!patch.contains("derive/"), "no fuzzy pinyin in Zhuyin")
            let logs = root.appendingPathComponent("logs")
            try fm.createDirectory(at: logs, withIntermediateDirectories: true)
            try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: logs, fullCheck: true,
                                         openCCDir: TraditionalChineseRimeTests.openCC)
            try #require(RimeService.shared.waitUntilReady(timeout: 180))
            #expect(RimeService.shared.deploymentStatus == .succeeded)
            let session = try #require(RimeService.shared.makeSession())
            // Deployed without an error logged (what the Doctor would report): stroke's own dependency (luna_pinyin, for
            // its reverse lookup, which Zhuyin's doesn't use) and the language model it may have (grammar) aren't needed.
            for name in try fm.contentsOfDirectory(atPath: logs.path) where name.contains(".INFO") {
                let text = try String(contentsOf: logs.appendingPathComponent(name), encoding: .utf8)
                let errors = text.split(separator: "\n").filter { $0.range(of: #"^E\d{8} "#, options: .regularExpression) != nil }
                #expect(errors.isEmpty, "\(errors.prefix(5))")
            }
            #expect(session.schema == "rime_ice", "a new session starts in full pinyin")
            #expect(session.selectSchema("bopomofo") && session.schema == "bopomofo")
            #expect(session.api.pointee.get_option(session.id, "zh_hant_tw") != 0, "Taiwan's characters")
            func type(_ keys: String) -> EngineSnapshot {
                session.clearComposition()
                for byte in keys.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
                return session.snapshot()
            }
            func words(_ keys: String) -> [String] { type(keys).candidates.prefix(5).map(\.text) }
            // ㄋㄧˇ ㄏㄠˇ, ㄨㄛˇ; Space the first tone (ㄅㄚ: 八); Taiwan's forms (爲 made 為).
            #expect(words("su3cl3").contains("你好"))
            #expect(words("ji3").contains("我"))
            #expect(words("18 ").contains("八"))
            let wei = words("jo4")
            #expect(wei.contains("為") && !wei.contains("爲"), "\(wei)")
            // A tone is a key, not a pick; so is ㄅ (1) after it; the preedit is Zhuyin.
            let tone = type("su3")
            #expect(session.rawInput == "su3" && tone.preedit.contains("ㄋㄧˇ"), "\(tone.preedit)")
            _ = session.processKey(0x31, mask: 0)
            #expect(session.rawInput == "su31")
            // No rime-ice custom phrases (its "u" 有, "ig" 一个): ㄧ is ㄧ's.
            #expect(!words("u").contains("有") || words("u").first != "有")
            #expect(!words("ig").contains("一个"))
            // Space after a syllable picks the highlighted candidate and takes it back; so do ⇧1 and a digit after a tone,
            // its picks: nothing goes in before Return (rime-bopomofo's own, its fluency editor).
            _ = type("su3cl3")
            #expect(session.processKey(RimeKey.space, mask: 0))
            #expect(session.snapshot().preedit == "你好" && session.takeCommit() == nil)
            _ = session.processKey(RimeKey.space, mask: 0)
            #expect(session.snapshot().preedit.contains("ㄋㄧˇ"))
            _ = type("su3")
            _ = session.processKey(0x21, mask: RimeKey.shiftMask)
            #expect(session.snapshot().isComposing && session.takeCommit() == nil)
            // Return commits what is composed, converted.
            let first = try #require(type("su3cl3").candidates.first?.text)
            #expect(session.processKey(RimeKey.returnKey, mask: 0))
            #expect(session.takeCommit() == first)
            // The candidates removed are left out.
            session.setRemovedCandidates(["你好"])
            #expect(!words("su3cl3").contains("你好"))
            session.setRemovedCandidates([])
            // Nothing learned: Space and the picks still put nothing in; Return puts in the same, without librime's commit.
            session.learns = false
            let unlearned = try #require(type("su3cl3").candidates.first?.text)
            #expect(session.processKey(RimeKey.space, mask: 0))
            #expect(session.snapshot().preedit == unlearned && session.takeCommit() == nil)
            #expect(session.processKey(RimeKey.returnKey, mask: 0))
            #expect(session.takeCommit() == unlearned && !session.snapshot().isComposing)
            _ = type("su3")
            #expect(session.selectCandidate(onPage: 0) && session.takeCommit() == nil && session.snapshot().isComposing)
            session.learns = true

            // Full pinyin again on the same session (its patch kept), and the list back to it alone (Zhuyin's removed).
            #expect(session.selectSchema("rime_ice"))
            #expect(words("nihao").contains("你好"))
            #expect(words("fong").contains("红") || words("fong").contains("紅"), "f ↔ h in full pinyin")
            #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .full,
                                          schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user) == .written)
            #expect(!fm.fileExists(atPath: user.appendingPathComponent("bopomofo.custom.yaml").path))
            #expect(try PinyinScheme.applySchemaList(.full, userDir: user) == .written)
            // The app without the data: the links go.
            try store.linkData(.chinesePinyin, from: nil, names: PinyinScheme.zhuyinData)
            #expect(PinyinScheme.zhuyinData.allSatisfy { (try? fm.attributesOfItem(atPath: pack.appendingPathComponent($0).path)) == nil })
        },
    ]
}
