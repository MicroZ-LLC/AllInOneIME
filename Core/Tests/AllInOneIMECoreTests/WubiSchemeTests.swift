import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Wubi 86 (`PinyinScheme.wubi`, rime-wubi's `wubi86` schema) beside the other ways, beyond the acceptance file
/// (Acceptance/WubiTests.swift): the choice, its patch line by line (what it takes from rime-ice's data instead of
/// rime-wubi's other repositories, rime-ice's switch of characters added), the settings, and its keys in a session as
/// pinyin's are. librime on rime-wubi's data: the shell's Rime tests (`WubiSchemaTests`).
struct WubiSchemeTests {
    // MARK: The choice

    @Test func wubiIsAWayOfItsOwnThatTypesNoPinyin() throws {
        #expect(PinyinScheme(setting: "wubi86") == .wubi && PinyinScheme.wubi.setting == "wubi86")
        #expect(PinyinScheme.wubi.schema == "wubi86" && PinyinScheme.wubi.schemaList == ["rime_ice", "wubi86"])
        #expect(PinyinScheme.allCases.last == .wubi && PinyinScheme.others.last == .wubi)
        #expect(!PinyinScheme.wubi.isShuangpin && !PinyinScheme.wubi.isPinyin && PinyinScheme.wubi.algebra.isEmpty)
        #expect(!PinyinScheme.zhuyin.isPinyin && PinyinScheme.full.isPinyin && PinyinScheme.shuangpin.allSatisfy(\.isPinyin))
        #expect(PinyinScheme.shuangpin.count == 7, "Wubi is no Shuangpin scheme")
        #expect(PinyinScheme.wubiData == ["wubi86.schema.yaml", "wubi86.dict.yaml"])
        // Its name: in Simplified Chinese by its code or the settings' "zh", in English, translated elsewhere.
        #expect(PinyinScheme.wubi.name(in: "zh-Hans") == "五笔 86" && PinyinScheme.wubi.name(in: "zh") == "五笔 86")
        #expect(PinyinScheme.wubi.name(in: "en") == "Wubi 86" && PinyinScheme.full.name(in: "zh") == "全拼")
        // Kept in the config file as picked; a file naming it reads it.
        var config = Config.default
        config.pinyinScheme = "wubi86"
        let saved = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(saved.pinyinScheme == "wubi86" && saved.typedPinyin == .wubi)
        // Picked through the store, the characters stay as they were (Zhuyin's Taiwan default is Zhuyin's own).
        let folder = TestScratch.temporary("wubi-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = SettingsStore(configURL: folder.appendingPathComponent("config.json"))
        store.setPinyinScheme(.wubi)
        #expect(store.config.pinyinScheme == "wubi86" && store.config.chineseCharacters == nil)
    }

    // MARK: Its patch

    /// rime-wubi's schema at the pinned commit, as much of it as the patch reads (no switch of characters, no filters).
    private static let wubi86 = """
        schema:
          schema_id: wubi86
          dependencies:
            - pinyin_simp
        switches:
          - name: ascii_mode
            reset: 0
          - name: full_shape
          - name: extended_charset
          - name: ascii_punct
        engine:
          translators:
            - punct_translator
            - reverse_lookup_translator
            - table_translator
        translator:
          dictionary: wubi86
        reverse_lookup:
          dictionary: pinyin_simp
        punctuator:
          import_preset: symbols

        """

    /// The Rime folders: the shared one with rime-ice's schema (a switch of characters, spelling rules), Wubi's and the
    /// app's filter of the candidates removed; and the user's.
    private func folders() throws -> (shared: URL, user: URL) {
        let root = TestScratch.temporary("wubi-scheme-\(UUID().uuidString)")
        let shared = root.appendingPathComponent("shared"), user = root.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
        try Data("-- filter".utf8).write(to: shared.appendingPathComponent("lua/\(RemovedCandidates.luaFilter).lua"))
        let ice = "schema:\n  schema_id: rime_ice\nswitches:\n  - name: ascii_mode\n  - name: traditionalization\n"
            + "speller:\n  algebra:\n    - erase/^hm$/\n"
        try Data(ice.utf8).write(to: shared.appendingPathComponent("rime_ice.schema.yaml"))
        try Data(Self.wubi86.utf8).write(to: shared.appendingPathComponent("wubi86.schema.yaml"))
        return (shared, user)
    }

    @Test func itsPatchIsItsOwnWithWhatRimeWubiTakesFromElsewhereTakenFromRimeIce() throws {
        let (shared, user) = try folders()
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        let patch = user.appendingPathComponent("wubi86.custom.yaml")
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .simplified, scheme: .wubi, shapeCode: .moqi, schema: schema,
                                      userDir: user) == .written)
        let text = try String(contentsOf: patch, encoding: .utf8)
        #expect(text.hasPrefix(FuzzyPinyin.marker + "\n"))
        for line in ["  punctuator/import_preset: default\n", "  reverse_lookup/dictionary: rime_ice\n",
                     "  speller/delimiter: \" '\"\n", "  speller/auto_select: false\n",
                     "  ascii_composer/switch_key: { Caps_Lock: clear, Shift_L: commit_text, Shift_R: commit_text, Control_L: noop, Control_R: noop }\n"] {
            #expect(text.contains(line), "\(line) in \(text)")
        }
        // The filter of the candidates removed last; nothing of pinyin's: fuzzy pinyin, shape codes, personal dictionaries,
        // rime-ice's user dictionary; Simplified: no switch of characters.
        #expect(text.hasSuffix("  engine/filters/+:\n    - lua_filter@*\(RemovedCandidates.luaFilter)\n"))
        #expect(!text.contains("derive/") && !text.contains(ShapeCode.luaFilter) && !text.contains("translator/"))
        #expect(!text.contains("traditionalize") && !text.contains("「"))
        // Full pinyin's patch keeps fuzzy pinyin, as before.
        let ice = try String(contentsOf: user.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8)
        #expect(ice.contains("\"derive/^f/h/\""))
        // The same again: nothing to deploy.
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .simplified, scheme: .wubi, shapeCode: .moqi, schema: schema,
                                      userDir: user) == .unchanged)
    }

    /// rime-wubi's dictionary is in Simplified characters, and its schema has no switch of them: rime-ice's is added,
    /// on from the start, its filter before the schema's (and so before the candidates removed), on what is typed alone.
    @Test func itsCharactersAreRimeIcesSwitchAdded() throws {
        #expect(ChineseCharacters.simplified.addedSwitchPatch == nil)
        let taiwan = try #require(ChineseCharacters.taiwan.addedSwitchPatch)
        #expect(taiwan.contains("  switches/@next: { name: traditionalization, reset: 1, states: [ 简, 繁 ] }\n"))
        #expect(taiwan.contains("  traditionalize: { option_name: traditionalization, opencc_config: s2twp.json, tips: none, tags: [ abc ] }\n"))
        #expect(taiwan.contains("  \"engine/filters/@before 0\": simplifier@traditionalize\n"))
        #expect(taiwan.contains("  \"punctuator/half_shape/\\\"\": { pair: [ \"「\", \"」\" ] }\n"))
        #expect(taiwan.contains("  \"punctuator/full_shape/'\": { pair: [ \"『\", \"』\" ] }\n"))
        #expect(ChineseCharacters.hongkong.addedSwitchPatch?.contains("opencc_config: s2hk.json,") == true)
        // The quotation marks are the same lines rime-ice's patch has.
        let ice = "switches:\n  - name: ascii_mode\n  - name: traditionalization\n"
        let quotes = { (text: String) in text.split(separator: "\n").filter { $0.contains("punctuator/") } }
        #expect(quotes(taiwan) == quotes(try #require(ChineseCharacters.taiwan.patch(schema: ice))))

        let (shared, user) = try folders()
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        #expect(try FuzzyPinyin.apply([], characters: .hongkong, scheme: .wubi, schema: schema, userDir: user) == .written)
        let text = try String(contentsOf: user.appendingPathComponent("wubi86.custom.yaml"), encoding: .utf8)
        #expect(text.contains("opencc_config: s2hk.json") && text.contains("simplifier@traditionalize"))
    }

    @Test func itsPatchGoesWithAnotherWayAndNeverOverTheUsersOwn() throws {
        let (shared, user) = try folders()
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        let patch = user.appendingPathComponent("wubi86.custom.yaml")
        #expect(try FuzzyPinyin.apply([], characters: .simplified, scheme: .wubi, schema: schema, userDir: user) == .written)
        // Zhuyin picked: Wubi's goes (only what is used is deployed).
        #expect(try FuzzyPinyin.apply([], characters: .simplified, scheme: .zhuyin, schema: schema, userDir: user) == .written)
        #expect(!FileManager.default.fileExists(atPath: patch.path))
        // The user's own stays, whatever is picked.
        let mine = "patch:\n  speller/auto_select: true\n"
        try Data(mine.utf8).write(to: patch)
        for scheme in [PinyinScheme.wubi, .full, .xiaohe] {
            _ = try FuzzyPinyin.apply([], characters: .taiwan, scheme: scheme, schema: schema, userDir: user)
            #expect(try String(contentsOf: patch, encoding: .utf8) == mine, "\(scheme)")
        }
        // Without Wubi's schema in the shared data (a pack without the app's link): nothing to patch.
        try FileManager.default.removeItem(at: patch)
        try FileManager.default.removeItem(at: shared.appendingPathComponent("wubi86.schema.yaml"))
        _ = try FuzzyPinyin.apply([], characters: .taiwan, scheme: .wubi, schema: schema, userDir: user)
        #expect(!FileManager.default.fileExists(atPath: patch.path))
        #expect(PinyinScheme.wubi.ownPatch(characters: .taiwan, schemaText: "") == nil)
        #expect(PinyinScheme.xiaohe.ownPatch(characters: .taiwan, schemaText: Self.wubi86) == nil, "Shuangpin: rime-ice's patch")
    }

    // MARK: Settings

    @Test func settingsListItLastAndHideTheShapeCodesWithIt() throws {
        let folder = TestScratch.temporary("wubi-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"inputLanguages":["zh","en"],"uiLanguage":"en"}"#.utf8).write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac,
                                      library: PluginLibrary(directory: folder.appendingPathComponent("plugins")))
        let field = try #require(service.document().field("pinyinScheme"))
        #expect(field.choices?.last?.value == .string("wubi86") && field.choices?.last?.label == "Wubi 86")
        #expect(field.help?.contains("Wubi 86") == true)
        #expect(service.document().field("shapeCode") != nil)
        _ = try service.set("pinyinScheme", to: .string("wubi86")).get()
        #expect(service.document().field("shapeCode") == nil)
        #expect(try Config.load(from: url).typedPinyin == .wubi)
        _ = try service.set("pinyinScheme", to: .string("double_pinyin_flypy")).get()
        #expect(service.document().field("shapeCode") != nil)
    }

    // MARK: Typing

    /// A stand-in for librime: Wubi's codes (as rime-wubi's dictionary has them) while "wubi86" is selected, full pinyin's
    /// otherwise, each schema taken recorded.
    private final class TwoSchemaEngine: PinyinEngine {
        let base = FakeEngine()
        private(set) var selected: [String] = []
        static let pinyin = ["nihao": ["你好", "拟好", "泥好"]]
        static let wubi = ["wqvb": ["你好", "您好", "你们好"], "g": ["一", "不", "到"]]

        init() { base.dictionary = Self.pinyin }

        func selectSchema(_ id: String) -> Bool {
            selected.append(id)
            base.dictionary = id == PinyinScheme.wubi.schema ? Self.wubi : Self.pinyin
            return true
        }

        func processKey(_ keycode: Int32, mask: Int32) -> Bool { base.processKey(keycode, mask: mask) }
        func takeCommit() -> String? { base.takeCommit() }
        func snapshot() -> EngineSnapshot { base.snapshot() }
        func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
        func deleteCandidate(onPage index: Int) -> Bool { base.deleteCandidate(onPage: index) }
        func setRemovedCandidates(_ texts: [String]) { base.setRemovedCandidates(texts) }
        func commitComposition() -> String? { base.commitComposition() }
        var rawInput: String { base.rawInput }
        func clearComposition() { base.clearComposition() }
        func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
    }

    private final class Box: @unchecked Sendable { var config = Config.default }

    private func session(_ box: Box, engine: TwoSchemaEngine) -> FakeHost {
        var services = SessionServices(loadSettings: { box.config })
        services.levelOne = { .engine(engine) }
        services.englishDictionary = { EnglishDictionary([]) }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    /// Picked, the next key types Wubi; its candidates' keys are pinyin's in either layout (in a row ← → move, ↑↓ turn
    /// the page; in a column ↑↓ move), a digit picks, Esc drops what is typed; nothing is marked in the field, as with
    /// every way.
    @Test func itTypesFromTheNextKeyWithPinyinsKeys() throws {
        for layout in CandidateArrangement.allCases {
            let box = Box()
            box.config.setOrder([Language.chinese, .english])
            box.config.candidateLayout = layout
            let engine = TwoSchemaEngine()
            let host = session(box, engine: engine)
            box.config.pinyinScheme = "wubi86"
            host.type("wqvb")
            #expect(engine.selected.last == "wubi86" && host.composer.pinyinScheme == .wubi, "\(layout)")
            #expect(host.panel?.rows.map(\.text).prefix(2) == ["你好", "您好"] && host.panel?.highlighted == 0, "\(layout)")
            // The composer keeps the composition (the panel's input line shows it); the field is never asked to mark it.
            #expect(host.document.isEmpty && host.marked.isEmpty && host.composer.markedText == "wqvb", "\(layout): only in the panel")
            #expect(host.press(layout == .horizontal ? FakeHost.right : FakeHost.down))
            #expect(host.panel?.highlighted == 1, "\(layout)")
            #expect(host.press(FakeHost.space))
            #expect(host.document == "您好", "\(layout)")
            host.type("wqvb3")
            #expect(host.document == "您好你们好", "\(layout)")
            host.type("g")
            #expect(host.press(FakeHost.escape))
            #expect(engine.rawInput.isEmpty && host.document == "您好你们好", "\(layout)")
            // Full pinyin again: the next key types it, with the same keys.
            box.config.pinyinScheme = nil
            host.type("nihao")
            #expect(engine.selected.last == "rime_ice" && host.composer.pinyinScheme == .full)
            #expect(host.marked.isEmpty && host.composer.markedText == "nihao", "as Wubi's")
            #expect(host.press(layout == .horizontal ? FakeHost.right : FakeHost.down))
            #expect(host.press(FakeHost.space))
            #expect(host.document == "您好你们好拟好", "\(layout)")
        }
    }

    /// Its letters are codes: no English words among its candidates, nothing put in as typed learned as one.
    @Test func noEnglishWordsAmongItsCandidates() {
        let base = TwoSchemaEngine()
        let engine = EnglishWordsEngine(base: base, dictionary: EnglishDictionary([]), words: ["Wqvbx", "Bedrock"])
        var learned: [String] = []
        engine.rawCommitted = { learned.append($0) }
        #expect(engine.selectSchema("wubi86") && engine.scheme == .wubi)
        for letter in "wqvb".utf8 { _ = engine.processKey(Int32(letter), mask: 0) }
        #expect(engine.snapshot().candidates.map(\.text) == ["你好", "您好", "你们好"])
        _ = engine.processKey(RimeKey.returnKey, mask: 0)
        _ = engine.takeCommit()
        #expect(learned.isEmpty)
        // Full pinyin again: the words come back.
        #expect(engine.selectSchema("rime_ice") && engine.scheme == .full)
        for letter in "wqvb".utf8 { _ = engine.processKey(Int32(letter), mask: 0) }
        #expect(engine.snapshot().candidates.map(\.text).contains("Wqvbx"))
    }
}
