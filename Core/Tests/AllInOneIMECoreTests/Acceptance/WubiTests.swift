import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Independent acceptance contract for Wubi 86 (issue #187, 2026-11-27). Implementers do not edit Acceptance tests.
// Assumed API: PinyinScheme gains `case wubi = "wubi86"` (rime-wubi's schema id), so PinyinScheme(setting: "wubi86")
// is `.wubi`, Config.pinyinScheme stores "wubi86" and `Config.typedPinyin.schema` is "wubi86"; PinyinScheme.allCases and
// `others` list it, it is no Shuangpin scheme; PinyinEngine.selectSchema("wubi86") is called before the next key.
// Its name is tr("五笔 86", "Wubi 86") (`PinyinScheme.name(in:)`) in the existing "pinyinScheme" settings field. Its Rime
// patch is `wubi86.custom.yaml` in the Rime user folder, written by the existing writers (FuzzyPinyin.apply,
// PersonalDictionaryStore.importDictionary, given `scheme: .wubi`) the way Zhuyin's `bopomofo.custom.yaml` is, and
// PinyinScheme.applySchemaList(.wubi, userDir:) lists the schema. EnglishWordsEngine.scheme is `.wubi` after
// selectSchema("wubi86"). No new settings field, command or shortcut.

/// A stand-in for librime: Wubi codes (as verified in rime-wubi's wubi86.dict.yaml) while "wubi86" is selected, full
/// pinyin otherwise.
private final class WubiEngine: PinyinEngine {
    let base = FakeEngine()
    private(set) var selected: [String] = []

    static let wubi = [
        "g": ["一", "不", "到"], "gggg": ["王", "五一", "琵琶"], "wqvb": ["你好", "您好"],
        "trnt": ["我", "特性"], "lgyi": ["国"],
    ]

    init() { base.dictionary = ["nihao": ["你好", "拟好"]] }

    func selectSchema(_ id: String) -> Bool {
        selected.append(id)
        base.dictionary = id == "wubi86" ? Self.wubi : ["nihao": ["你好", "拟好"]]
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

@Suite("Wubi 86", .serialized)
struct WubiTests {
    /// rime-wubi's wubi86.schema.yaml at the commit the Makefile pins (152a0d3f3efe40cae216d1e3b338242446848d07), as
    /// the Rime shared folder has it beside rime-ice's.
    static let wubiSchema = """
        # Rime schema settings
        # encoding: utf-8

        schema:
          schema_id: wubi86
          name: "五笔86"
          version: "0.21"
          author:
            - 發明人 王永民先生
          description: |
            五筆字型86版
            碼表源自 ibus-table
            敲 z 鍵進入拼音反查
          dependencies:
            - pinyin_simp

        switches:
          - name: ascii_mode
            reset: 0
            states: [ 中文, 西文 ]
          - name: full_shape
            states: [ 半角, 全角 ]
          - name: extended_charset
            states: [ 常用, 增廣 ]
          - name: ascii_punct
            states: [ 。，, ．， ]

        engine:
          processors:
            - ascii_composer
            - recognizer
            - key_binder
            - speller
            - punctuator
            - selector
            - navigator
            - express_editor
          segmentors:
            - ascii_segmentor
            - matcher
            - abc_segmentor
            - punct_segmentor
            - fallback_segmentor
          translators:
            - punct_translator
            - reverse_lookup_translator
            - table_translator

        speller:
          delimiter: " ;'"
          #max_code_length: 4

        translator:
          dictionary: wubi86
          enable_charset_filter: true
          enable_sentence: true
          enable_encoder: true
          encode_commit_history: true
          max_phrase_length: 4
          disable_user_dict_for_patterns:
            - "^z.*$"

        reverse_lookup:
          dictionary: pinyin_simp
          prefix: "z"
          suffix: "'"
          tips: 〔拼音〕
          preedit_format:
            - xform/([nl])v/$1ü/
            - xform/([nl])ue/$1üe/
            - xform/([jqxy])v/$1u/

        punctuator:
          import_preset: symbols

        key_binder:
          import_preset: default

        recognizer:
          import_preset: default
          patterns:
            punct: '^/([0-9]0?|[A-Za-z]+)$'
            reverse_lookup: "^z[a-z]*'?$"

        """

    /// A small rime-ice schema: its Traditional switch, spelling rules (fuzzy pinyin's patch needs some), its dictionary.
    static let iceSchema = """
        schema:
          schema_id: rime_ice
        switches:
          - name: ascii_mode
            states: [ 中, Ａ ]
          - name: traditionalization
            states: [ 简, 繁 ]
        speller:
          alphabet: abcdefghijklmnopqrstuvwxyz
          algebra:
            - derive/^([nl])ue$/$1ve/
        translator:
          dictionary: rime_ice
        traditionalize:
          option_name: traditionalization
          opencc_config: s2t.json

        """

    private func service(language: String = "en", characters: String? = nil,
                         scheme: String? = nil) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wubi-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        var json: [String: Any] = ["inputLanguages": ["zh", "en"], "uiLanguage": language]
        if let characters { json["chineseCharacters"] = characters }
        if let scheme { json["pinyinScheme"] = scheme }
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins"))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: library), url)
    }

    /// The Rime folders as the Mac has them: the shared one (rime-ice's schema and dictionary, Wubi's schema, the app's
    /// filter of the candidates removed in its `lua/`) and the user's.
    private func rimeFolders() throws -> (root: URL, schema: URL, user: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wubi-rime-\(UUID().uuidString)")
        let shared = root.appendingPathComponent("shared")
        let user = root.appendingPathComponent("user")
        try fm.createDirectory(at: shared.appendingPathComponent("lua"), withIntermediateDirectories: true)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        let schema = shared.appendingPathComponent("rime_ice.schema.yaml")
        try Self.iceSchema.write(to: schema, atomically: true, encoding: .utf8)
        try "---\nname: rime_ice\nversion: \"1\"\nsort: by_weight\n...\n你好\tni hao\t1000\n"
            .write(to: shared.appendingPathComponent("rime_ice.dict.yaml"), atomically: true, encoding: .utf8)
        try Self.wubiSchema.write(to: shared.appendingPathComponent("wubi86.schema.yaml"), atomically: true, encoding: .utf8)
        try "-- the app's filter of the candidates removed\n"
            .write(to: shared.appendingPathComponent("lua/\(RemovedCandidates.luaFilter).lua"), atomically: true, encoding: .utf8)
        return (root, schema, user)
    }

    private func level(_ config: @escaping () -> Config, engine: WubiEngine) -> FakeHost {
        var services = SessionServices(loadSettings: config)
        services.levelOne = { .engine(engine) }
        services.englishDictionary = { EnglishDictionary([]) }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    // MARK: The choice

    @Test func wubi86IsAWayOfItsOwnNeitherShuangpinNorZhuyin() throws {
        let scheme = PinyinScheme(setting: "wubi86")
        #expect(scheme == .wubi)
        #expect(scheme.rawValue == "wubi86")
        #expect(scheme.schema == "wubi86")
        #expect(scheme.setting == "wubi86")
        #expect(PinyinScheme.allCases.contains(.wubi))
        #expect(PinyinScheme.others.contains(.wubi))
        #expect(!scheme.isShuangpin)
        #expect(!PinyinScheme.shuangpin.contains(.wubi))
        #expect(scheme != .zhuyin && scheme != .full)
        #expect(scheme.schemaList.contains("wubi86"))
        // The ones before it still mean what they did.
        #expect(PinyinScheme(setting: "bopomofo") == .zhuyin)
        #expect(PinyinScheme(setting: nil) == .full && PinyinScheme(setting: "full") == .full)
        #expect(PinyinScheme(setting: "wubi98") == .full, "an unknown way stays full pinyin")
    }

    @Test func theChoiceIsSavedAsWubi86() throws {
        var config = Config.default
        config.pinyinScheme = "wubi86"
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect(saved["pinyinScheme"] as? String == "wubi86")
        let loaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(loaded.pinyinScheme == "wubi86")
        #expect(loaded.typedPinyin == .wubi)
        #expect(loaded.typedPinyin.schema == "wubi86")
        let file = try JSONDecoder().decode(Config.self, from: Data(#"{"inputLanguages":["zh","en"],"pinyinScheme":"wubi86"}"#.utf8))
        #expect(file.typedPinyin == .wubi)
    }

    @Test func itsNameInChineseAndEnglish() {
        #expect(PinyinScheme.wubi.name(in: "zh") == "五笔 86")
        #expect(PinyinScheme.wubi.name(in: "en") == "Wubi 86")
    }

    @Test func settingsOffersWubiInTheTypingPickerInEveryLanguage() throws {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Localizable.xcstrings")
        let tables = try StringCatalog.tables(from: Data(contentsOf: catalog))
        for language in ["zh", "en", "fr", "de", "es", "ja", "ko"] {
            let (service, url) = try service(language: language)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let field = try #require(service.document().field("pinyinScheme"), "\(language)")
            let choice = try #require(field.choices?.first { $0.value == .string("wubi86") }, "\(language)")
            #expect(!choice.label.isEmpty, "\(language)")
            if language == "zh" { #expect(choice.label == "五笔 86") }
            if language == "en" { #expect(choice.label == "Wubi 86") }
        }
        // Every language the catalog translates the other ways into has Wubi's name too (`make strings`).
        let languages = tables.filter { $0.value["Full pinyin"]?.isEmpty == false }.map(\.key)
        #expect(!languages.isEmpty)
        for language in languages {
            #expect(tables[language]?["Wubi 86"]?.isEmpty == false, "\(language): Wubi 86")
        }
    }

    @Test func pickingWubiSavesItAndAddsNoSettingOfItsOwn() throws {
        let (service, url) = try service()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = Set(service.document().sections.flatMap(\.fields).map(\.id))
        _ = try service.set("pinyinScheme", to: .string("wubi86")).get()
        #expect(try Config.load(from: url).pinyinScheme == "wubi86")
        #expect(service.document().field("pinyinScheme")?.value == .string("wubi86"))
        let (wubi, wubiURL) = try self.service(scheme: "wubi86")
        defer { try? FileManager.default.removeItem(at: wubiURL.deletingLastPathComponent()) }
        let after = Set(wubi.document().sections.flatMap(\.fields).map(\.id))
        #expect(after.isSubset(of: before), "new fields with Wubi: \(after.subtracting(before))")
        // Shape codes are for pinyin: not shown with Wubi, as with Zhuyin.
        #expect(before.contains("shapeCode"))
        #expect(wubi.document().field("shapeCode") == nil)
    }

    @Test func pickingWubiLeavesTheCharactersAsTheyWere() throws {
        // Zhuyin's Taiwan default is Zhuyin's own; the spec gives Wubi none.
        let (service, url) = try service()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try service.set("pinyinScheme", to: .string("wubi86")).get()
        #expect(try Config.load(from: url).chineseCharacters == nil)
        let (prior, priorURL) = try self.service(characters: "taiwan")
        defer { try? FileManager.default.removeItem(at: priorURL.deletingLastPathComponent()) }
        _ = try prior.set("pinyinScheme", to: .string("wubi86")).get()
        #expect(try Config.load(from: priorURL).chineseCharacters == .taiwan)
    }

    // MARK: Typing

    @Test func nextKeyTypesWubiInThePanelAsEveryWayDoes() throws {
        final class Box { var config = Config.default }
        let box = Box()
        box.config.setOrder([Language.chinese, .english])
        let engine = WubiEngine()
        let host = level({ box.config }, engine: engine)
        host.type("nihao")
        host.press(FakeHost.space)
        #expect(host.document == "你好")

        // Picked in Settings: the next key types Wubi, without leaving the field.
        box.config.pinyinScheme = "wubi86"
        host.type("wqvb")
        #expect(engine.selected.last == "wubi86")
        #expect(engine.rawInput == "wqvb")
        // Only in the panel (its input line), the first row chosen; nothing in the field before a pick, nor marked there.
        #expect(host.document == "你好")
        #expect(host.marked.isEmpty)
        #expect(host.preedit.contains("wqvb"), "\(host.preedit)")
        let panel = try #require(host.panel)
        #expect(panel.rows.map(\.text).prefix(2) == ["你好", "您好"])
        #expect(panel.highlighted == 0)
        host.press(FakeHost.space)
        #expect(host.document == "你好你好")

        // Four codes and one candidate left: nothing goes in by itself.
        host.type("lgyi")
        #expect(engine.rawInput == "lgyi" && host.document == "你好你好")
        host.press(FakeHost.space)
        #expect(host.document == "你好你好国")

        // A digit picks its row; the next row is chosen with pinyin's keys in each layout (side by side, the default:
        // → moves, ↑↓ turn the page; in a column: ↓ moves), and Space picks the row chosen.
        host.type("wqvb")
        host.type("2")
        #expect(host.document == "你好你好国您好")
        host.type("trnt")
        host.press(FakeHost.right)
        #expect(host.panel?.highlighted == 1)
        host.press(FakeHost.space)
        #expect(host.document == "你好你好国您好特性")
        box.config.candidateLayout = .vertical
        _ = host.session.applySettings()  // as the shell does when the settings change
        host.type("trnt")
        host.press(FakeHost.down)
        #expect(host.panel?.highlighted == 1)
        host.press(FakeHost.space)
        #expect(host.document == "你好你好国您好特性特性")

        // Esc drops what is typed.
        host.type("g")
        host.press(FakeHost.escape)
        #expect(engine.rawInput.isEmpty && host.document == "你好你好国您好特性特性")
        #expect(host.panel?.rows.contains { $0.text == "一" } != true)

        // Back to full pinyin: the next key types it again.
        box.config.pinyinScheme = "full"
        host.type("nihao")
        #expect(engine.selected.last == "rime_ice")
        host.press(FakeHost.space)
        #expect(host.document == "你好你好国您好特性特性你好")
    }

    @Test func atCommandsAreStillFoundByLatinLetters() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.pinyinScheme = "wubi86"
        let fixed = config
        let host = level({ fixed }, engine: WubiEngine())
        host.type("@im")
        #expect(host.composer.paletteMatches.contains { $0.name == "improve" })
        #expect(host.composer.oneAt?.letters == "im")
        #expect(host.document.isEmpty)
    }

    // MARK: What goes with pinyin and what doesn't

    @Test func englishWordsDoNotJoinWubiCandidates() {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.pinyinScheme = "wubi86"
        config.englishWords = ["Bedrock"]
        let fixed = config
        let engine = WubiEngine()
        let host = level({ fixed }, engine: engine)
        host.type("bedrock")
        #expect(engine.selected.last == "wubi86")
        #expect(host.composer.engine?.snapshot().candidates.contains { $0.text == "Bedrock" } != true)
        #expect(host.panel?.rows.contains { $0.text == "Bedrock" } != true)
    }

    @Test func lettersPutInAsTypedAreNotLearnedAsEnglishWords() {
        let engine = EnglishWordsEngine(base: WubiEngine(), dictionary: EnglishDictionary([]), words: ["Bedrock"])
        var learned: [String] = []
        engine.rawCommitted = { learned.append($0) }
        #expect(engine.selectSchema("wubi86"))
        #expect(engine.scheme == .wubi)
        for letter in "bed".utf8 { _ = engine.processKey(Int32(letter), mask: 0) }
        #expect(!engine.snapshot().candidates.map(\.text).contains("Bedrock"))
        _ = engine.processKey(RimeKey.returnKey, mask: 0)
        _ = engine.takeCommit()
        #expect(learned.isEmpty, "Wubi codes are no English words: \(learned)")
    }

    @Test func wubisPatchHasTheRemovedCandidatesButNoFuzzyPinyinPersonalDictionariesOrShapeCodes() throws {
        let (root, schema, user) = try rimeFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("team.dict.yaml")
        try "---\nname: team\nversion: \"1\"\n...\n霁鸢星槎\tji yuan xing cha\n".write(to: source, atomically: true, encoding: .utf8)
        let store = PersonalDictionaryStore(userDirectory: user, schema: schema)
        _ = try store.importDictionary(from: source, fuzzyPinyin: ["n-l"], characters: .simplified, scheme: .wubi)
        let ice = try String(contentsOf: user.appendingPathComponent(FuzzyPinyin.fileName), encoding: .utf8)
        #expect(ice.contains("derive/^n/l/") && ice.contains("allinoneime_personal"), "full pinyin keeps them")
        let patch = user.appendingPathComponent("wubi86.custom.yaml")
        func text() throws -> String { try String(contentsOf: patch, encoding: .utf8) }
        let wubi = try text()
        #expect(wubi.contains("lua_filter@*\(RemovedCandidates.luaFilter)"), "\(wubi)")
        #expect(!wubi.contains("derive/"), "no fuzzy pinyin: \(wubi)")
        #expect(!wubi.contains("allinoneime_personal"), "no pinyin personal dictionaries: \(wubi)")
        // Words learned stay in Wubi's own user dictionary.
        #expect(!wubi.contains("user_dict: rime_ice"), "\(wubi)")

        _ = try FuzzyPinyin.apply(["n-l"], characters: .simplified, scheme: .wubi, shapeCode: .moqi, schema: schema, userDir: user)
        #expect(try !text().contains(ShapeCode.luaFilter), "no shape codes in Wubi")
        #expect(try !text().contains("derive/"))
    }

    @Test func wubisPatchCarriesTheCharacters() throws {
        let (root, schema, user) = try rimeFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let patch = user.appendingPathComponent("wubi86.custom.yaml")
        func text() throws -> String { try String(contentsOf: patch, encoding: .utf8) }
        // rime-wubi's dictionary is in Simplified characters: Traditional ones are converted as rime-ice's are.
        #expect(try FuzzyPinyin.apply([], characters: .taiwan, scheme: .wubi, schema: schema, userDir: user) == .written)
        #expect(try text().contains("s2twp.json"))
        #expect(try FuzzyPinyin.apply([], characters: .hongkong, scheme: .wubi, schema: schema, userDir: user) == .written)
        #expect(try text().contains("s2hk.json") && !text().contains("s2twp.json"))
        _ = try FuzzyPinyin.apply([], characters: .simplified, scheme: .wubi, schema: schema, userDir: user)
        let simplified = try text()
        #expect(!simplified.contains("s2twp.json") && !simplified.contains("s2hk.json"), "\(simplified)")
    }

    @Test func wubisPatchAndSchemaListNeverReplaceTheUsersOwn() throws {
        let (root, schema, user) = try rimeFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let patch = user.appendingPathComponent("wubi86.custom.yaml")
        #expect(try FuzzyPinyin.apply([], characters: .taiwan, scheme: .wubi, schema: schema, userDir: user) == .written)
        #expect(FileManager.default.fileExists(atPath: patch.path))
        // Another way picked: the app's Wubi patch goes (only what is used is deployed).
        _ = try FuzzyPinyin.apply([], characters: .taiwan, scheme: .full, schema: schema, userDir: user)
        #expect(!FileManager.default.fileExists(atPath: patch.path))
        // The user's own is left as it is.
        let mine = "patch:\n  menu/page_size: 9\n"
        try mine.write(to: patch, atomically: true, encoding: .utf8)
        _ = try FuzzyPinyin.apply([], characters: .taiwan, scheme: .wubi, schema: schema, userDir: user)
        #expect(try String(contentsOf: patch, encoding: .utf8) == mine)

        // The schema list names Wubi's schema; a user's own list is left alone.
        let list = user.appendingPathComponent("default.custom.yaml")
        #expect(try PinyinScheme.applySchemaList(.wubi, userDir: user) == .written)
        let listed = try #require(PinyinScheme.listedSchemas(String(contentsOf: list, encoding: .utf8)))
        #expect(listed.contains("wubi86"))
        #expect(try PinyinScheme.applySchemaList(.wubi, userDir: user) == .unchanged)
        let theirs = "patch:\n  schema_list:\n    - schema: luna_pinyin\n"
        try theirs.write(to: list, atomically: true, encoding: .utf8)
        #expect(try PinyinScheme.applySchemaList(.wubi, userDir: user) == .userFile)
        #expect(try String(contentsOf: list, encoding: .utf8) == theirs)
    }
}
