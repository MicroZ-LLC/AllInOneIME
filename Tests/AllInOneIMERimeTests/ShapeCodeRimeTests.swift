import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Shape codes (`ShapeCode`) on the real librime and rime-ice, set up as the app sets them up: rime-lua-aux-code's filter
/// with the app's other scripts (the pack's `lua/`, `LanguagePackStore.linkCode`), its tables linked into the pack
/// (`LanguagePackStore.linkData`), the patch the settings write (`FuzzyPinyin.apply` with the shape codes) and a full
/// check. Each table puts a character it knows first, in full pinyin and in Microsoft Shuangpin; a pick commits the
/// character alone; Backspace takes back the letters, then "`"; off is as before (rime-ice's own filter on "`"); Zhuyin
/// isn't touched. In a process of its own each (`RimeWorker`).
struct ShapeCodeRimeTests {
    let root = TestScratch.temporary("rime-shape-code-\(UUID().uuidString)")
    static var runs: Bool {
        RimeWorker.scenario == nil && (RimeWorker.dataAvailable && FileManager.default.fileExists(atPath: tables.path)
            && FileManager.default.fileExists(atPath: TraditionalChineseRimeTests.openCC.path) || RimeWorker.required)
    }
    /// Where `make deps` puts the filter and the tables the app carries.
    static let auxCode = RimeFixture.thirdParty.appendingPathComponent("rime-aux-code")
    static let tables = auxCode.appendingPathComponent(ShapeCode.folder)

    /// 鱼 (yu) in each table, by the first two letters of its code: what puts it first among yu's candidates.
    static let fish: [ShapeCode: String] = [.moqi: "da", .flypy: "da", .wubi86: "qg", .cangjie: "nm"]

    @Test(.enabled(if: runs, "needs rime-ice, OpenCC's data and the shape codes' tables (make deps)"))
    func eachTablePutsItsCharacterFirstInFullPinyinAndShuangpin() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("shape-code-tables", root: root)
    }

    @Test(.enabled(if: runs, "needs rime-ice, OpenCC's data and the shape codes' tables (make deps)"))
    func offIsAsBeforeAndZhuyinIsUntouched() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("shape-code-off-zhuyin", root: root)
    }

    @Test(.enabled(if: runs, "needs rime-ice, OpenCC's data and the shape codes' tables (make deps)"))
    func traditionalOutputKeepsShapeCodeFiltering() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("shape-code-traditional", root: root)
    }

    /// The patch for each schema: the filter in the place of rime-ice's on "`" (its own index in each), the table, the
    /// trigger; nothing without the script or the table; Zhuyin's never.
    @Test(.enabled(if: RimeWorker.dataAvailable || RimeWorker.required, "needs rime-ice (make deps)"))
    func thePatchReplacesRimeIcesFilterInEachSchema() throws {
        let shared = RimeFixture.sharedData
        for scheme in [PinyinScheme.full] + PinyinScheme.shuangpin {
            let text = try String(contentsOf: shared.appendingPathComponent("\(scheme.schema).schema.yaml"), encoding: .utf8)
            let filters = ShapeCode.filters(ofSchema: text)
            let index = try #require(filters.firstIndex(of: "lua_filter@*search@radical_pinyin"), "\(scheme): \(filters)")
            #expect(filters.last == "uniquifier", "\(scheme): \(filters)")
            let pack = try Self.pack(root.appendingPathComponent(scheme.rawValue))
            let patch = try #require(ShapeCode.moqi.patch(schema: text, sharedData: pack), "\(scheme)")
            #expect(patch.contains("  engine/filters/@\(index): lua_filter@*aux_code\n"), "\(scheme): \(patch)")
            #expect(patch.contains("  aux_code/dictionary: moqi_aux_code\n  aux_code/learn_trigger: \"`\"\n"), "\(scheme): \(patch)")
            #expect(ShapeCode.moqi.patch(schema: text, sharedData: shared) == nil, "\(scheme): rime-ice's data alone has no filter")
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Set up as the app

    /// The Chinese pack in `root` as the app has it: rime-ice's data, its `lua/` the app's scripts (rime-ice's, the filter
    /// of the candidates removed, aux_code.lua), the tables linked in (`LanguagePackStore.linkData`).
    static func pack(_ root: URL) throws -> URL {
        let pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua",
                                                             script: String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8))
        try FileManager.default.copyItem(at: auxCode.appendingPathComponent("lua/aux_code.lua"),
                                         to: root.appendingPathComponent("rime-lua/aux_code.lua"))
        let store = LanguagePackStore(directory: root.appendingPathComponent("LanguagePacks"))
        try store.linkData(.chinesePinyin, from: auxCode, names: [ShapeCode.folder])
        return pack
    }

    /// The patch for `scheme` and `code` written, the schema list, and librime started (`start`) or deployed again.
    static func apply(_ code: ShapeCode?, scheme: PinyinScheme, characters: ChineseCharacters = .simplified,
                      pack: URL, user: URL, start: Bool) throws -> FuzzyPinyin.Outcome {
        let outcome = try FuzzyPinyin.apply([], characters: characters, scheme: scheme, shapeCode: code,
                                            schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
        let listed = try PinyinScheme.applySchemaList(scheme, userDir: user)
        if start {
            try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: nil, fullCheck: true,
                                         openCCDir: TraditionalChineseRimeTests.openCC)
        } else if outcome != .unchanged || listed == .written {
            RimeService.shared.redeploy()
        }
        try #require(RimeService.shared.waitUntilReady(timeout: 180))
        #expect(RimeService.shared.deploymentStatus == .succeeded)
        return outcome
    }

    /// The candidates on the first page after `keys`, typed afresh in `schema`.
    static func type(_ keys: String, in session: RimeSession) -> [String] {
        session.clearComposition()
        for byte in keys.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
        return session.snapshot().candidates.map(\.text)
    }

    /// Every candidate after `keys`, typed afresh, page after page.
    static func list(_ keys: String, in session: RimeSession) -> [String] {
        var texts = type(keys, in: session)
        for _ in 0..<40 {
            let snapshot = session.snapshot()
            if snapshot.isLastPage || snapshot.candidates.isEmpty { break }
            _ = session.processKey(RimeKey.pageDown, mask: 0)
            texts += session.snapshot().candidates.map(\.text)
        }
        session.clearComposition()
        return texts
    }

    /// yu's keys in each schema tested (Microsoft Shuangpin's: y u, its spelling unchanged), and jinyu's (金鱼).
    static let yu: [String: String] = ["rime_ice": "yu", "double_pinyin_mspy": "yu"]
    static let jinyu: [String: String] = ["rime_ice": "jinyu", "double_pinyin_mspy": "jnyu"]

    // MARK: Scenarios

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "shape-code-tables": { root in
            let pack = try pack(root), user = root.appendingPathComponent("Rime")
            var started = false
            for code in ShapeCode.allCases {
                let letters = try #require(fish[code], "\(code): no character to try")
                #expect(try apply(code, scheme: .microsoft, pack: pack, user: user, start: !started) == .written, "\(code)")
                started = true
                let session = try #require(RimeService.shared.makeSession())
                for schema in ["rime_ice", "double_pinyin_mspy"] {
                    #expect(session.selectSchema(schema), "\(schema)")
                    let yu = try #require(Self.yu[schema])
                    // Every page: 鱼 isn't on yu's first until it has been picked once (librime learns it).
                    let all = list(yu, in: session)
                    #expect(all.contains("鱼"), "\(code), \(schema): \(all.prefix(20))")
                    #expect(type(yu + "`", in: session) == type(yu, in: session), "\(code), \(schema): \"`\" alone leaves the list as it is")
                    let filtered = list(yu + "`" + letters, in: session)
                    #expect(filtered.first == "鱼", "\(code), \(schema): \(filtered.prefix(10))")
                    #expect(Set(filtered).isSubset(of: Set(all)) && filtered.count < all.count,
                            "\(code), \(schema): only yu's, the unmatched left out: \(filtered.prefix(10))")
                    #expect(type(yu + "`" + letters.prefix(1), in: session).contains("鱼"), "\(code), \(schema): one letter")
                    // A word with the character: listed (金鱼, its second character).
                    let words = type(try #require(jinyu[schema]) + "`" + letters, in: session)
                    #expect(words.contains("金鱼"), "\(code), \(schema): \(words)")
                    // Space picks it: the character alone goes in, none of the letters.
                    _ = type(yu + "`" + letters, in: session)
                    #expect(session.processKey(RimeKey.space, mask: 0))
                    #expect(session.takeCommit() == "鱼", "\(code), \(schema)")
                    #expect(!session.snapshot().isComposing, "\(code), \(schema): nothing left composed")
                    // A digit picks too.
                    _ = type(yu + "`" + letters, in: session)
                    #expect(session.processKey(Int32(UInt8(ascii: "1")), mask: 0))
                    #expect(session.takeCommit() == "鱼", "\(code), \(schema): a digit")
                }
                // Backspace: the letters, then "`", then the pinyin.
                #expect(session.selectSchema("rime_ice"))
                _ = type("yu`" + letters, in: session)
                for left in ["yu`" + letters.prefix(1), "yu`", "yu", "y"] {
                    _ = session.processKey(RimeKey.backSpace, mask: 0)
                    #expect(session.rawInput == left, "\(code): \(session.rawInput) for \(left)")
                }
                session.clearComposition()
            }
        },
        "shape-code-traditional": { root in
            let pack = try pack(root), user = root.appendingPathComponent("Rime")
            var start = true
            for characters in [ChineseCharacters.taiwan, .hongkong] {
                // Wubi and Xiaohe index 鱼. Moqi and Cangjie have separate codes for 魚.
                let cases: [(ShapeCode, String)] = [(.wubi86, "qgf"), (.flypy, "da"), (.moqi, "dh"), (.cangjie, "nf")]
                for (code, letters) in cases {
                    #expect(try apply(code, scheme: .microsoft, characters: characters, pack: pack, user: user, start: start) == .written)
                    start = false
                    let session = try #require(RimeService.shared.makeSession())
                    for schema in ["rime_ice", "double_pinyin_mspy"] {
                        try #require(session.selectSchema(schema))
                        let candidates = type("yu`" + letters, in: session)
                        let context = "\(code), \(characters), \(schema): \(candidates)"
                        #expect(candidates.first == "魚", "\(context)")
                        if candidates.first == "魚" {
                            #expect(session.processKey(RimeKey.space, mask: 0))
                            #expect(session.takeCommit() == "魚", "\(context)")
                        }
                    }
                }
            }
        },
        "shape-code-off-zhuyin": { root in
            let pack = try pack(root), user = root.appendingPathComponent("Rime")
            // Off: rime-ice's own patch and its filter on "`" (the radicals' pinyin: yu`yu, 鱼 by its parts).
            #expect(try apply(nil, scheme: .microsoft, pack: pack, user: user, start: true) == .written)
            for schema in ["rime_ice", "double_pinyin_mspy"] {
                let patch = try String(contentsOf: user.appendingPathComponent("\(schema).custom.yaml"), encoding: .utf8)
                #expect(!patch.contains("aux_code"), "\(schema): \(patch)")
            }
            var session = try #require(RimeService.shared.makeSession())
            #expect(session.selectSchema("rime_ice"))
            let before = ["yu", "yu`", "yu`da", "yu`nm", "nihao"].map { type($0, in: session) }
            // On, then off again: the same candidates as before.
            #expect(try apply(.moqi, scheme: .microsoft, pack: pack, user: user, start: false) == .written)
            session = try #require(RimeService.shared.makeSession())
            #expect(session.selectSchema("rime_ice"))
            #expect(type("yu`da", in: session).first == "鱼")
            #expect(try apply(nil, scheme: .microsoft, pack: pack, user: user, start: false) == .written)
            session = try #require(RimeService.shared.makeSession())
            #expect(session.selectSchema("rime_ice"))
            #expect(["yu", "yu`", "yu`da", "yu`nm", "nihao"].map { type($0, in: session) } == before)

            // Zhuyin with shape codes on: its patch has none of them, and it types as it did.
            #expect(try apply(.moqi, scheme: .zhuyin, pack: pack, user: user, start: false) == .written)
            let zhuyin = try String(contentsOf: user.appendingPathComponent("bopomofo.custom.yaml"), encoding: .utf8)
            #expect(!zhuyin.contains("aux_code") && !zhuyin.contains("engine/filters/@"), "\(zhuyin)")
            #expect(try String(contentsOf: user.appendingPathComponent("rime_ice.custom.yaml"), encoding: .utf8).contains("aux_code"))
            session = try #require(RimeService.shared.makeSession())
            #expect(session.selectSchema("bopomofo"))
            #expect(type("su3", in: session).contains("你"), "Zhuyin: ㄋㄧˇ")
        },
    ]
}
