import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Shuangpin and Zhuyin (`PinyinScheme`) beside full pinyin: the schemes, the letters read as each reads them (what isn't
/// learned as an English word, where one goes among the candidates), the files that deploy them (the schema list, the
/// patch made for the scheme's schema; Zhuyin's own) and the interface text in every language the catalog has. librime
/// on rime-ice's own schemas: `ShuangpinSchemaTests` in the shell's Rime tests; on rime-bopomofo's, `ZhuyinSchemaTests`.
struct PinyinSchemeTests {
    @Test func theSchemesAreRimeIcesSchemas() {
        #expect(PinyinScheme.allCases.map(\.schema) == ["rime_ice", "double_pinyin_flypy", "double_pinyin", "double_pinyin_mspy",
                                                         "double_pinyin_sogou", "double_pinyin_abc", "double_pinyin_jiajia",
                                                         "double_pinyin_ziguang", "bopomofo"])
        #expect(PinyinScheme(setting: nil) == .full && PinyinScheme(setting: "full") == .full && PinyinScheme(setting: "wubi86") == .full)
        #expect(PinyinScheme(setting: "double_pinyin_mspy") == .microsoft && PinyinScheme.microsoft.setting == "double_pinyin_mspy")
        #expect(PinyinScheme.full.setting == nil && !PinyinScheme.full.isShuangpin && PinyinScheme.shuangpin.count == 7)
        #expect(!PinyinScheme.zhuyin.isShuangpin && PinyinScheme.others == PinyinScheme.shuangpin + [.zhuyin])
        #expect(PinyinScheme.zhuyin.schemaList == ["rime_ice", "bopomofo"] && PinyinScheme.zhuyin.algebra.isEmpty)
        var config = Config.default
        config.pinyinScheme = "wubi86"  // a later version's: full pinyin here, and not kept
        let reread = try? JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(reread?.pinyinScheme == nil && reread?.typedPinyin == .full)
        #expect(PinyinScheme.xiaohe.schemaList == ["rime_ice", "double_pinyin_flypy"] && PinyinScheme.full.schemaList == ["rime_ice"])
    }

    // MARK: The letters

    @Test func shuangpinLettersAreReadAsTheSchemeReadsThem() {
        #expect(Pinyin.isPinyin("nihc", scheme: .xiaohe) && Pinyin.isPinyin("vsgo", scheme: .xiaohe))  // 你好, 中国
        #expect(Pinyin.isPinyin("nihk", scheme: .microsoft) && Pinyin.isPinyin("nihk", scheme: .ziranma))
        #expect(Pinyin.isPinyin("aaee", scheme: .xiaohe), "a syllable without an initial: its vowel twice")
        #expect(!Pinyin.isPinyin("bedrock", scheme: .xiaohe) && !Pinyin.isPinyinBeingTyped("bedrock", scheme: .xiaohe))
        #expect(Pinyin.isPinyinBeingTyped("nihcx", scheme: .xiaohe) && !Pinyin.isPinyin("nihcx", scheme: .xiaohe))
        #expect(!Pinyin.isPinyin("vsgo") && Pinyin.isPinyin("nihao"), "full pinyin as before")
        // Fuzzy pinyin's rules before the scheme's: f ↔ h makes fong (hong) Xiaohe's fs.
        #expect(!Pinyin.isPinyin("fs", scheme: .xiaohe) && Pinyin.isPinyin("fs", fuzzy: ["f-h"], scheme: .xiaohe))
    }

    @Test func shuangpinPutInAsTypedIsntLearnedAsAnEnglishWord() {
        let none = EnglishDictionary([])
        #expect(EnglishWords.learnable("vsgo", known: [], dictionary: none, hidden: []))
        #expect(!EnglishWords.learnable("vsgo", known: [], dictionary: none, hidden: [], scheme: .xiaohe))
        #expect(EnglishWords.learnable("bedrock", known: [], dictionary: none, hidden: [], scheme: .xiaohe))
    }

    /// librime typing a Shuangpin scheme spells the syllables out in its preedit ("ni hao" for "nihc"): the English words
    /// still go among the candidates, until a word is picked ("你好" before the letters).
    @Test func englishWordsAmongShuangpinCandidates() {
        let base = SpelledOutEngine()
        base.dictionary = ["bedr": ["被动"], "nihc": ["你好"]]
        let engine = EnglishWordsEngine(base: base, dictionary: EnglishDictionary([]), words: ["Bedrock"])
        #expect(engine.selectSchema("double_pinyin_flypy") && engine.scheme == .xiaohe && base.selected == ["double_pinyin_flypy"])
        for letter in "bedr".utf8 { _ = engine.processKey(Int32(letter), mask: 0) }
        #expect(engine.snapshot().candidates.map(\.text).contains("Bedrock"), "\(engine.snapshot())")
        base.picked = "你好"
        #expect(!engine.snapshot().candidates.map(\.text).contains("Bedrock"), "a word picked: the page is for the rest")
        engine.clearComposition()
        #expect(!engine.selectSchema("double_pinyin_mspy") && engine.scheme == .xiaohe, "one the engine can't take: as before")
    }

    // MARK: The files

    /// A temporary Rime data folder with two schemas, rime-ice's and Xiaohe's, as much of them as the patch reads; and a
    /// user folder.
    private func folders() throws -> (shared: URL, user: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pinyin-scheme-\(UUID().uuidString)")
        let shared = root.appendingPathComponent("shared"), user = root.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
        try Data("-- filter".utf8).write(to: shared.appendingPathComponent("lua/\(RemovedCandidates.luaFilter).lua"))
        let full = "schema:\n  schema_id: rime_ice\nswitches:\n  - name: ascii_mode\n  - name: traditionalization\n"
            + "speller:\n  algebra:\n    - erase/^hm$/\n"
        let xiaohe = "schema:\n  schema_id: double_pinyin_flypy\nswitches:\n  - name: ascii_mode\n  - name: ascii_punct\n"
            + "  - name: traditionalization\nspeller:\n  algebra:\n" + PinyinScheme.xiaohe.algebra.map { "    - \($0)\n" }.joined()
        try Data(full.utf8).write(to: shared.appendingPathComponent("rime_ice.schema.yaml"))
        try Data(xiaohe.utf8).write(to: shared.appendingPathComponent("double_pinyin_flypy.schema.yaml"))
        return (shared, user)
    }

    /// rime-bopomofo's schema, as much of it as the patch reads: its switches (the characters' a switch of four options).
    private static let bopomofo = """
        schema:
          schema_id: bopomofo
        switches:
          - name: ascii_mode
            reset: 0
            states: [ 中文, 西文 ]
          - name: full_shape
            states: [ 半角, 全角 ]
          - options:
              - zh_hant
              - zh_hans
              - zh_hant_hk
              - zh_hant_tw
            states:
              - 傳統漢字
              - 简化字
              - 香港字形
              - 臺灣字形
            abbrev: [ 漢, 简, 港, 臺 ]
          - name: ascii_punct
            states: [ 。，, ．， ]
        engine:
          processors:
            - ascii_composer

        """

    @Test func zhuyinsCharactersAreAnOptionOfItsSwitch() {
        #expect(ChineseCharacters.optionSwitch(with: "zh_hant_tw", inSchema: Self.bopomofo)?.index == 2)
        #expect(ChineseCharacters.optionSwitch(with: "zh_hans", inSchema: Self.bopomofo)?.options == ["zh_hant", "zh_hans", "zh_hant_hk", "zh_hant_tw"])
        #expect(ChineseCharacters.optionSwitch(with: "zh_hant_tw", inSchema: "switches:\n- name: ascii_mode\n- options: [zh_hant, zh_hant_tw]\n")?.index == 1)
        #expect(ChineseCharacters.optionSwitch(with: "zh_hant_tw", inSchema: "switches:\n  - name: traditionalization\n") == nil)
        // Taiwan's: the fourth option, t2tw, the quotation marks; Hong Kong's the third; Simplified the second, converted too.
        let taiwan = ChineseCharacters.taiwan.patch(schema: Self.bopomofo) ?? ""
        #expect(taiwan.contains("  switches/@2/reset: 3\n") && taiwan.contains("  zh_hant_tw/opencc_config: t2tw.json\n"))
        #expect(taiwan.contains("「") && !taiwan.contains("traditionalize"))
        #expect(ChineseCharacters.hongkong.patch(schema: Self.bopomofo)?.contains("  switches/@2/reset: 2\n  zh_hant_hk/opencc_config: t2hk.json\n") == true)
        let simplified = ChineseCharacters.simplified.patch(schema: Self.bopomofo) ?? ""
        #expect(simplified.contains("  switches/@2/reset: 1\n  zh_hans/opencc_config: t2s.json\n") && !simplified.contains("「"))
        #expect(["t2tw.json", "t2hk.json", "t2s.json"].allSatisfy(ChineseCharacters.openCCFiles.contains))
    }

    @Test func zhuyinHasAPatchOfItsOwn() throws {
        let (shared, user) = try folders()
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        try Data(Self.bopomofo.utf8).write(to: shared.appendingPathComponent("bopomofo.schema.yaml"))
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        let patch = user.appendingPathComponent("bopomofo.custom.yaml")
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .zhuyin, schema: schema, userDir: user) == .written)
        let text = try String(contentsOf: patch, encoding: .utf8)
        #expect(text.hasPrefix(FuzzyPinyin.marker + "\n"))
        // Its characters and the filter of the candidates removed, its translators without rime-ice's custom phrases; no
        // fuzzy pinyin (rime-ice's patch keeps it).
        #expect(text.contains("switches/@2/reset: 3") && text.contains("zh_hant_tw/opencc_config: t2tw.json"))
        #expect(text.contains("lua_filter@*\(RemovedCandidates.luaFilter)"))
        #expect(text.contains("engine/translators: [ punct_translator, reverse_lookup_translator, script_translator ]"))
        #expect(!text.contains("derive/") && !text.contains("custom_phrase\n"))
        #expect(try String(contentsOf: user.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8).contains("\"derive/^f/h/\""))
        // A tap of Shift commits what is composed, converted (rime-ice's: the keys typed); full pinyin's as rime-ice's.
        #expect(text.contains("  ascii_composer/switch_key: { Caps_Lock: clear, Shift_L: commit_text, Shift_R: commit_text, Control_L: noop, Control_R: noop }\n"))
        #expect(try !String(contentsOf: user.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8).contains("ascii_composer"))
        // Simplified: converted too. Another scheme: Zhuyin's gone; the user's own left as it is.
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .simplified, scheme: .zhuyin, schema: schema, userDir: user) == .written)
        #expect(try String(contentsOf: patch, encoding: .utf8).contains("zh_hans/opencc_config: t2s.json"))
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .simplified, scheme: .xiaohe, schema: schema, userDir: user) == .written)
        #expect(!FileManager.default.fileExists(atPath: patch.path))
        let mine = "patch:\n  menu/page_size: 9\n"
        try Data(mine.utf8).write(to: patch)
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .simplified, scheme: .zhuyin, schema: schema, userDir: user) == .written)
        #expect(!FileManager.default.fileExists(atPath: user.appendingPathComponent("double_pinyin_flypy.custom.yaml").path))
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .simplified, scheme: .zhuyin, schema: schema, userDir: user) == .unchanged)
        #expect(try String(contentsOf: patch, encoding: .utf8) == mine)
        // Listed beside full pinyin.
        #expect(try PinyinScheme.applySchemaList(.zhuyin, userDir: user) == .written)
        #expect(PinyinScheme.listedSchemas(try String(contentsOf: user.appendingPathComponent("default.custom.yaml"), encoding: .utf8))
                == ["rime_ice", "bopomofo"])
    }

    /// Zhuyin's keys are digits and punctuation too, and its letters no word: none among its candidates, nothing put in
    /// as typed learned, and its digits librime's whatever the page.
    @Test func noEnglishWordsAmongZhuyinsCandidates() {
        let base = SpelledOutEngine()
        base.dictionary = ["bed": ["貝德"]]
        let engine = EnglishWordsEngine(base: base, dictionary: EnglishDictionary([]), words: ["Bedrock"], removedCandidates: ["貝德"])
        var learned: [String] = []
        engine.rawCommitted = { learned.append($0) }
        #expect(engine.selectSchema("bopomofo") && engine.scheme == .zhuyin)
        for letter in "bed".utf8 { _ = engine.processKey(Int32(letter), mask: 0) }
        #expect(!engine.snapshot().candidates.map(\.text).contains("Bedrock"))
        _ = engine.processKey(RimeKey.returnKey, mask: 0)
        _ = engine.takeCommit()
        #expect(learned.isEmpty)
    }

    @Test func theSchemeIsListedBesideFullPinyin() throws {
        let (shared, user) = try folders()
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let list = user.appendingPathComponent("default.custom.yaml")
        func listed() throws -> [String]? { PinyinScheme.listedSchemas(try String(contentsOf: list, encoding: .utf8)) }
        // None there: full pinyin leaves it to librime's start (the pack's copy); Shuangpin writes it.
        #expect(try PinyinScheme.applySchemaList(.full, userDir: user) == .unchanged)
        #expect(!FileManager.default.fileExists(atPath: list.path))
        #expect(try PinyinScheme.applySchemaList(.xiaohe, userDir: user) == .written)
        #expect(try listed() == ["rime_ice", "double_pinyin_flypy"])
        #expect(try PinyinScheme.applySchemaList(.xiaohe, userDir: user) == .unchanged)
        #expect(try PinyinScheme.applySchemaList(.microsoft, userDir: user) == .written && listed() == ["rime_ice", "double_pinyin_mspy"])
        #expect(try PinyinScheme.applySchemaList(.full, userDir: user) == .written && listed() == ["rime_ice"])
        // The Chinese pack's copy (and an earlier version's, whatever its comment): full pinyin's alone, this app's.
        let pack = "# Written by AllInOneIME: only the full-pinyin schema is used (its dictionaries are prebuilt\n"
            + "# into the app bundle, so deployment on first use is quick).\npatch:\n  schema_list:\n    - schema: rime_ice\n"
        try Data(pack.utf8).write(to: list)
        #expect(try PinyinScheme.applySchemaList(.full, userDir: user) == .unchanged)
        try Data(("# Written by an earlier name of the app\n" + pack).utf8).write(to: list)
        #expect(try PinyinScheme.applySchemaList(.xiaohe, userDir: user) == .written && listed() == ["rime_ice", "double_pinyin_flypy"])
        // The user's own list: left as it is.
        let own = "patch:\n  schema_list:\n    - schema: luna_pinyin\n    - schema: rime_ice\n"
        try Data(own.utf8).write(to: list)
        #expect(try PinyinScheme.applySchemaList(.xiaohe, userDir: user) == .userFile)
        #expect(try String(contentsOf: list, encoding: .utf8) == own)
    }

    @Test func theSchemeHasThePatchOfItsOwnSchema() throws {
        let (shared, user) = try folders()
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        let patch = user.appendingPathComponent("double_pinyin_flypy.custom.yaml")
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .xiaohe, schema: schema, userDir: user) == .written)
        let text = try String(contentsOf: patch, encoding: .utf8)
        #expect(text.hasPrefix(FuzzyPinyin.marker + "\n"))
        // Fuzzy pinyin's rules first, then Xiaohe's own; its Traditional switch (third, not rime-ice's second); the filter.
        let rules = FuzzyPinyin.algebra(ofSchema: text.replacingOccurrences(of: "patch:\n  speller/algebra:", with: "speller:\n  algebra:"))
        #expect(rules == (["derive/^f/h/", "derive/^h/f/"] + PinyinScheme.xiaohe.algebra).map { "\"\($0)\"" })
        #expect(text.contains("switches/@2/reset: 1") && text.contains("traditionalize/opencc_config: s2twp.json"))
        #expect(text.contains("lua_filter@*\(RemovedCandidates.luaFilter)"))
        let own = try String(contentsOf: user.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8)
        #expect(own.contains("switches/@1/reset: 1") && own.contains("\"derive/^f/h/\""))
        // The same settings again: nothing to deploy. Another scheme: its patch, Xiaohe's gone.
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .xiaohe, schema: schema, userDir: user) == .unchanged)
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .microsoft, schema: schema, userDir: user) == .written)
        #expect(!FileManager.default.fileExists(atPath: patch.path))
        #expect(FileManager.default.fileExists(atPath: user.appendingPathComponent("double_pinyin_mspy.custom.yaml").path))
        // Full pinyin: none; the user's own left as it is.
        let mine = "patch:\n  menu/page_size: 9\n"
        try Data(mine.utf8).write(to: patch)
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .full, schema: schema, userDir: user) == .written)
        #expect(!FileManager.default.fileExists(atPath: user.appendingPathComponent("double_pinyin_mspy.custom.yaml").path))
        #expect(try String(contentsOf: patch, encoding: .utf8) == mine)
        #expect(try FuzzyPinyin.apply(["f-h"], characters: .taiwan, scheme: .xiaohe, schema: schema, userDir: user) == .unchanged)
        #expect(try String(contentsOf: patch, encoding: .utf8) == mine)
    }

    // MARK: The text

    /// The core's package (its catalog: Resources/Localizable.xcstrings).
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The field's label, what it says and every scheme's name are translated in every language of the core's catalog,
    /// and come out translated where a shell gives the core its catalog (`InterfaceText.tableLookup`, as Windows does).
    @Test func typingIsTranslatedInEveryLanguage() throws {
        let data = try Data(contentsOf: Self.package.appendingPathComponent("Resources/Localizable.xcstrings"))
        let lookup = InterfaceText.tableLookup(try StringCatalog.tables(from: data))
        let texts = [("输入方式", "Typing")] + PinyinScheme.allCases.map { ($0.name(in: "zh-Hans"), $0.name(in: "en")) }
        for language in StringCatalogCheck.languages {
            for (chinese, english) in texts {
                let shown = InterfaceText.text(UIString(chinese), UIString(english), language: language, lookup: lookup)
                #expect(lookup(english, language)?.isEmpty == false, "\(language): \(english)")
                if english == "Typing" || english == "Full pinyin" { #expect(shown != english, "\(language): \(english)") }
            }
            #expect(lookup(UIText.$scopedLanguage.withValue("en") { UIText.pinyinSchemeHelp }, language)?.isEmpty == false, "\(language)")
        }
        #expect(PinyinScheme.xiaohe.name(in: "zh-Hans") == "双拼 – 小鹤" && PinyinScheme.full.name(in: "en") == "Full pinyin")
    }
}

/// A stand-in for librime typing a Shuangpin scheme: its preedit spells out the syllables (Xiaohe's "nihc" as "ni hao"),
/// with what is picked before them.
private final class SpelledOutEngine: PinyinEngine {
    let base = FakeEngine()
    var dictionary: [String: [String]] {
        get { base.dictionary }
        set { base.dictionary = newValue }
    }
    private(set) var selected: [String] = []
    /// A word picked from the composition: shown first in the preedit.
    var picked = ""

    func selectSchema(_ id: String) -> Bool {
        selected.append(id)
        return ["double_pinyin_flypy", "rime_ice", "bopomofo"].contains(id)
    }

    func snapshot() -> EngineSnapshot {
        var snap = base.snapshot()
        if snap.isComposing { snap.preedit = picked + ["nihc": "ni hao", "bedr": "be duan"][base.input, default: base.input] }
        return snap
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool { base.processKey(keycode, mask: mask) }
    func takeCommit() -> String? { base.takeCommit() }
    func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() {
        picked = ""
        base.clearComposition()
    }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}
