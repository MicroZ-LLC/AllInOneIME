import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Acceptance tests for pinyin in Traditional characters (spec-traditional-chinese.md, Part A, with the owner's decision
// that the setting is global: typed Chinese is the chosen variant everywhere the app reasons about language), written
// from the spec by an independent reviewer; the implementer may not edit them. Each test names the spec item it
// enforces ("s1" item 1 …, "s5" the global effects). The Rime tests with the real pack are in
// Tests/AllInOneIMERimeTests/Acceptance/TraditionalChineseRimeAcceptanceTests.swift.
//
//  1. Setting
//   s1_theConfigKeyHoldsOneOfThreeValues        `chineseCharacters`: "simplified" | "taiwan" | "hongkong", saved as written;
//                                                absent stays absent; an unknown value doesn't break the file
//   s1_absentFollowsThePreferredLanguages        zh-Hant / zh-TW / zh-MO → taiwan, zh-HK → hongkong, others → simplified
//   s1_absentIsWorkedOutEachTimeItIsRead         the same settings follow a Mac whose language changes, until one is picked
//   s1_theSettingsDocumentOffersIt               Settings → Input → Chinese: 「字形」/ "Characters", 简体 / 繁體（台灣）/
//                                                繁體（香港）, next to fuzzy pinyin, as the system says until picked, saved
//   s1_itSyncsThroughICloud                      another Mac gets it, both ways, and is told to redeploy (`configKeys`)
//   s1_iCloudRefusesAValueItDoesntKnow           a newer version's value is refused, the Mac's own kept
//  2. Conversion (rime_ice.custom.yaml)
//   s2_taiwanPatchesTheSwitchFoundByName         switches/@N/reset: 1 with N where `traditionalization` is; s2twp.json
//   s2_hongKongPatchUsesS2hk                     s2hk.json
//   s2_simplifiedHasNoPatchForIt                 no OpenCC config, no switch reset; the file goes when nothing else is in it
//   s2_thePatchExistsWhenOnlyTheCharactersAreSet written / unchanged / written / removed: what tells the caller to redeploy
//   s2_fuzzyPinyinAndDictionariesKeepTheCharacters  fuzzy pinyin and personal dictionaries in the same file keep it
//  3. OpenCC data, the Doctor
//   s3_doctorExplainsOpenCCConfigNotFound        librime's `opencc config not found`: what to do, in both languages
//   s3_doctorExplainsOpenCCThatCantInitialize    librime's `Error initializing opencc`: what to do, in both languages
//  4. Punctuation
//   s4_traditionalQuotesInThePatch               " 「」 and ' 『』 with Taiwan's and Hong Kong's characters, not Simplified
//  5. Everywhere else
//   s5_theLanguageTypedIsTheVariant              zh, zh-Hant-TW, zh-Hant-HK
//   s5_improveNamesTheVariantAndTeachesInIt      through a session: @improve's prompt names Traditional Chinese (Taiwan) /
//                                                (Hong Kong), its examples are Traditional; Simplified as before
//   s5_rewriteStylesStayInTheVariant             the styles rewrite in the variant, their examples in it
//   s5_translateSkipsTraditionalIntoTraditional  @translate: into zh-Hant from Traditional is skipped, from Simplified not
//   s5_translateASimplifiedSelectionForTaiwan    (a reading) a Simplified text selected by a Taiwan user is translated
//   s5_translateThroughTheSessionSkipsTheSameLanguage  through a session: @translate from Traditional into zh-Hant
//                                                sends nothing, from Simplified it translates; @improve says "Polishing…"
//   s5_translateAsYouTypeSkipsTheSameLanguage    through a session: typed Traditional goes in as typed into zh-Hant;
//                                                Simplified typed is translated; Traditional into zh is translated
//   s5_translateAsYouTypeComesOnIntoAnother      its target, and whether there's anything to translate into
//   s5_theChipSaysTraditional                    through a session: 「繁 → 英」 / "ZH-HANT → EN", 「中」 for Simplified
//   s5_replyIsInTheUsersVariant                  through a session: @reply's language is the user's variant for Chinese
//   s5_autocompleteExamplesFollowTheVariant      the on-device model's examples in the characters typed
//   s5_screenTextReadsTraditionalFirst           OCR languages: zh-Hant first (and through a session's ⌃V)
//   s5_remindReadsTraditionalForms               下個禮拜五下午三點, 這個禮拜五, 兩個小時以後; the title as typed
//   s5_theInputIsNamedWithItsVariant             「中文（繁體）」 in the menu's and Settings' name, 「中文」 otherwise
//
// The model is the Claude API stubbed at the HTTP level (`RAStubProtocol`, RefineAcceptanceTests.swift: one host per
// test), or Apple's on-device model stubbed (`StubAppleModel`). Sessions are `FakeHost`s whose pinyin engine is a
// `FakeEngine` standing in for Rime with the characters' patch applied: it gives Traditional candidates where Rime would.
// Interface language as `withInterfaceLanguage` holds it; the system's languages through `Platform.$override`.

// MARK: - Fixtures

enum TCA {
    struct Languages: UserLanguages { var preferred: [String] }

    /// `body` on a Mac whose preferred languages (System Settings → Language & Region) are `languages`.
    static func onMac<T>(preferring languages: [String], _ body: () throws -> T) rethrows -> T {
        var platform = Platform.current
        platform.userLanguages = Languages(preferred: languages)
        return try Platform.$override.withValue(platform) { try body() }
    }

    /// Characters only Simplified Chinese writes (each has a Traditional form of its own), and only Traditional writes.
    static let simplifiedOnly = Set("这个们说为会还过时实觉谢难费点样东见间让话请问题帮级没现车边软网络视频简体吗与应该气欢乐亲爱开关门书买卖读写听记认识务动员经济业产农两头无从众优伤价议约钥带别")
    static let traditionalOnly = Set("這個們說為會還過時實覺謝難費點樣東見間讓話請問題幫級沒現車邊軟網絡視頻簡體嗎與應該氣歡樂親愛開關門書買賣讀寫聽記認識務動員經濟業產農兩頭無從眾優傷價議約鑰帶別週")

    static func han(_ text: String) -> Bool { text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
    static func simplified(in text: String) -> String { String(text.filter(simplifiedOnly.contains)) }
    static func traditional(in text: String) -> String { String(text.filter(traditionalOnly.contains)) }

    /// A request as the Claude API got it.
    struct Sent {
        var system: String
        var messages: [(role: String, text: String)]

        init(_ data: Data) throws {
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            func text(_ any: Any?) -> String {
                if let text = any as? String { return text }
                return (any as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            system = text(json["system"])
            messages = (json["messages"] as? [[String: Any]] ?? []).map { ($0["role"] as? String ?? "", text($0["content"])) }
        }

        /// The few-shot examples: every message but the last.
        var examples: [String] { messages.dropLast().map(\.text) }
        var last: String { messages.last?.text ?? "" }
    }

    /// Settings with `characters` picked (nil: none, as the system says), typing pinyin and English, translating into
    /// `outputs`, the Claude API at a host of the test's own.
    static func config(_ characters: ChineseCharacters?, outputs: [OutputLanguage] = [.english], ui: String = "en",
                       host: String = "tca-\(UUID().uuidString.lowercased()).test") -> Config {
        var config = Config.default
        config.uiLanguage = ui
        config.setOrder([Language.chinese, .english])
        config.setOrder(outputs)
        config.chineseCharacters = characters
        config.provider = .anthropic
        config.anthropic.baseURL = "https://\(host)"
        config.anthropic.model = "claude-test"
        config.rewriteStyles = []
        return config
    }

    static let zhHant = OutputLanguage("zh-Hant")
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48])
}

/// Text fields typing with `config`: pinyin from a `FakeEngine` (Rime with the characters' patch: its dictionary is the
/// test's), the model the Claude API at the config's host (`RAStubProtocol`).
final class TCAWorld: @unchecked Sendable {
    var config: Config
    let engine = FakeEngine()
    var host: String { config.anthropic.baseURL.flatMap { URL(string: $0)?.host } ?? "" }

    init(_ characters: ChineseCharacters?, outputs: [OutputLanguage] = [.english], ui: String = "en") {
        config = TCA.config(characters, outputs: outputs, ui: ui)
    }

    func field(app: String = "com.example.editor", _ adjust: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        let fixed = config, engine = self.engine
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.converter = Converter(client: BedrockClient(session: RAStubProtocol.session()), loadConfig: { fixed },
                                       loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
        adjust(&services)
        let host = FakeHost(services: services)
        host.app = app
        host.focus()
        return host
    }

    /// "@", the command's name, Tab: "@name ".
    func pick(_ name: String, in field: FakeHost) {
        field.press(FakeHost.at)
        field.type(name)
        field.press(FakeHost.tab)
    }

    /// Pinyin, then Space for its first candidate.
    func pinyin(_ letters: String, as text: String, in field: FakeHost) {
        engine.dictionary[letters] = [text]
        field.type(letters)
        field.press(FakeHost.space)
    }

    func sent() throws -> [TCA.Sent] { try RAStubProtocol.bodies(host).map(TCA.Sent.init) }
}

/// The language of a text by its characters, as sure as can be: Traditional-only characters "zh-Hant", other Han
/// "zh-Hans", else English.
struct TCALanguages: LanguageIdentifier {
    func dominantLanguage(of text: String, among candidates: [String]) -> (code: String, confidence: Double)? {
        if !TCA.traditional(in: text).isEmpty { return ("zh-Hant", 0.95) }
        if TCA.han(text) { return ("zh-Hans", 0.95) }
        return ("en", 0.95)
    }
}

/// The field a shell's service asks about, set once it is made.
final class TCAFieldBox: @unchecked Sendable {
    var field: FakeHost?
}

/// A recognizer that keeps the languages it was asked to read in.
final class TCARecognizer: TextRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [[String]] = []
    var languages: [[String]] { lock.withLock { asked } }

    func prepare(languages: [String]) async {}

    func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] {
        lock.withLock { asked.append(languages) }
        return []
    }
}

// MARK: - The tests

@Suite(MemorySecrets())
struct TraditionalChineseAcceptanceTests {
    // MARK: 1. The setting

    @Test func s1_theConfigKeyHoldsOneOfThreeValues() throws {
        for characters in [ChineseCharacters.simplified, .taiwan, .hongkong] {
            let config = try JSONDecoder().decode(Config.self, from: Data(#"{"chineseCharacters": "\#(characters.rawValue)"}"#.utf8))
            #expect(config.chineseCharacters == characters)
            #expect(config.typedChinese == characters, "picked, it is what Chinese is typed in")
            let written = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
            #expect(written["chineseCharacters"] as? String == characters.rawValue, "saved as written: \(written["chineseCharacters"] ?? "nil")")
        }
        #expect(Set(ChineseCharacters.allCases.map(\.rawValue)) == ["simplified", "taiwan", "hongkong"])
        // Absent: stays absent when saved (so it goes on following the system).
        let absent = try JSONDecoder().decode(Config.self, from: Data(#"{"fuzzyPinyin": ["z-zh"]}"#.utf8))
        #expect(absent.chineseCharacters == nil)
        let saved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(absent)) as? [String: Any])
        #expect(saved["chineseCharacters"] == nil)
        // A value this version doesn't know (a newer one's) is no value: the rest of the file is read.
        let unknown = try JSONDecoder().decode(Config.self, from: Data(#"{"chineseCharacters": "singapore", "fuzzyPinyin": ["z-zh"]}"#.utf8))
        #expect(unknown.chineseCharacters == nil && unknown.fuzzyPinyin == ["z-zh"])
    }

    @Test func s1_absentFollowsThePreferredLanguages() {
        let cases: [([String], ChineseCharacters)] = [
            (["zh-Hant"], .taiwan), (["zh-TW"], .taiwan), (["zh-Hant-TW"], .taiwan), (["zh-MO"], .taiwan), (["zh-Hant-MO"], .taiwan),
            (["zh-HK"], .hongkong), (["zh-Hant-HK"], .hongkong),
            (["zh-Hans"], .simplified), (["zh-Hans-CN"], .simplified), (["zh-CN"], .simplified), (["zh-SG"], .simplified),
            (["en-US"], .simplified), (["ja-JP"], .simplified), (["fr-FR", "de-DE"], .simplified),
            // A Taiwan user whose Mac shows English first, Traditional Chinese next, types Traditional (the first Chinese
            // of their languages says which): what a Taiwan user expects, though the interface is in English.
            (["en-US", "zh-Hant-TW"], .taiwan), (["en-GB", "zh-HK"], .hongkong), (["en-US", "zh-Hans-CN", "zh-Hant-TW"], .simplified),
        ]
        let config = TCA.config(nil)
        for (languages, expected) in cases {
            TCA.onMac(preferring: languages) {
                #expect(config.typedChinese == expected, "\(languages)")
            }
        }
    }

    @Test func s1_absentIsWorkedOutEachTimeItIsRead() {
        let config = TCA.config(nil)
        TCA.onMac(preferring: ["zh-Hans-CN"]) { #expect(config.typedChinese == .simplified) }
        TCA.onMac(preferring: ["zh-Hant-TW"]) {
            #expect(config.typedChinese == .taiwan, "the same settings, the system's language changed")
            #expect(config.typedLanguage(.chinese).code == "zh-Hant-TW")
        }
        TCA.onMac(preferring: ["zh-HK"]) { #expect(config.typedChinese == .hongkong) }
        // Picked, it no longer follows the system.
        var picked = config
        picked.chineseCharacters = .simplified
        TCA.onMac(preferring: ["zh-Hant-TW"]) { #expect(picked.typedChinese == .simplified) }
        picked.chineseCharacters = .hongkong
        TCA.onMac(preferring: ["zh-Hans-CN"]) { #expect(picked.typedChinese == .hongkong) }
    }

    /// The settings as a settings window gets them (`SettingsService`: Windows' settings document; the Mac's window shows
    /// the same rows), in a config file of the test's own.
    func service(_ text: String) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tca-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library), url)
    }

    @Test func s1_theSettingsDocumentOffersIt() throws {
        // In Chinese: 「字形」, its choices in their own characters, next to fuzzy pinyin (Settings → Input → Chinese).
        let (zh, url) = try service(#"{"provider": "anthropic", "uiLanguage": "zh", "inputLanguages": ["zh", "en"]}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try TCA.onMac(preferring: ["zh-Hant-TW", "en-US"]) {
            let document = zh.document()
            let field = try #require(document.field("chineseCharacters"), "no Characters field")
            #expect(field.label == "字形")
            #expect(field.choices?.map(\.value) == [.string("simplified"), .string("taiwan"), .string("hongkong")])
            #expect(field.choices?.map(\.label) == ["简体", "繁體（台灣）", "繁體（香港）"])
            #expect(field.value == .string("taiwan"), "as the system's languages say until one is picked: \(String(describing: field.value))")
            let section = try #require(document.sections.first { $0.fields.contains { $0.id == "fuzzyPinyin" } })
            let ids = section.fields.map(\.id)
            let characters = try #require(ids.firstIndex(of: "chineseCharacters"), "not with fuzzy pinyin: \(ids)")
            let fuzzy = try #require(ids.firstIndex(of: "fuzzyPinyin"))
            #expect(abs(characters - fuzzy) == 1, "next to fuzzy pinyin: \(ids)")
            // Picked: saved, and kept whatever the system says from then on.
            #expect((try? zh.set("chineseCharacters", to: .string("hongkong")).get()) != nil)
            let saved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            #expect(saved["chineseCharacters"] as? String == "hongkong")
        }
        let reloaded = try Config.load(from: url)
        TCA.onMac(preferring: ["zh-Hans-CN"]) {
            #expect(zh.document().field("chineseCharacters")?.value == .string("hongkong"))
            #expect(reloaded.typedChinese == .hongkong)
        }
        // In English.
        let (en, enURL) = try service(#"{"provider": "anthropic", "uiLanguage": "en", "inputLanguages": ["zh", "en"], "chineseCharacters": "simplified"}"#)
        defer { try? FileManager.default.removeItem(at: enURL.deletingLastPathComponent()) }
        let field = try #require(en.document().field("chineseCharacters"))
        #expect(field.label == "Characters")
        #expect(field.choices?.map(\.label) == ["Simplified", "Traditional (Taiwan)", "Traditional (Hong Kong)"])
        #expect(field.value == .string("simplified"))
    }

    @Test func s1_itSyncsThroughICloud() {
        let world = ICAWorld()
        let a = world.mac("A") { $0.chineseCharacters = .taiwan }
        let b = world.mac("B")  // none picked yet
        #expect(a.sync(at: 10).outcome == .synced)
        let first = b.sync(at: 20)
        #expect(b.config.chineseCharacters == .taiwan, "B got A's characters")
        #expect(first.configKeys.contains("chineseCharacters"), "B is told it changed (Rime deploys again): \(first.configKeys)")
        b.edit(at: 30) { $0.chineseCharacters = .hongkong }
        b.sync(at: 40)
        let back = a.sync(at: 50)
        #expect(a.config.chineseCharacters == .hongkong, "A got B's change")
        #expect(back.configKeys.contains("chineseCharacters"))
    }

    @Test func s1_iCloudRefusesAValueItDoesntKnow() {
        let world = ICAWorld()
        world.put(["chineseCharacters": "singapore"], at: ICA.t(5))
        let b = world.mac("B") { $0.chineseCharacters = .taiwan }
        let report = b.sync(at: 10)
        #expect(b.config.chineseCharacters == .taiwan, "its own kept")
        #expect(report.refused["chineseCharacters"] != nil, "\(report.refused)")
    }

    // MARK: 2. The conversion: rime_ice.custom.yaml

    /// A Rime user folder and a schema like rime-ice's in a folder of their own: `switches` as `schemaText` has them.
    struct RimeFolder {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tca-rime-\(UUID().uuidString)", isDirectory: true)
        var user: URL { root.appendingPathComponent("Rime", isDirectory: true) }
        var shared: URL { root.appendingPathComponent("shared", isDirectory: true) }
        var schema: URL { shared.appendingPathComponent("rime_ice.schema.yaml") }
        var patch: URL { user.appendingPathComponent("rime_ice.custom.yaml") }
        var patchText: String? { try? String(contentsOf: patch, encoding: .utf8) }

        init(switches: String) throws {
            try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            let schemaText = """
                # Rime schema
                schema:
                  schema_id: rime_ice
                  name: 雾凇拼音
                switches:
                \(switches)
                speller:
                  alphabet: zyxwvutsrqponmlkjihgfedcba
                  algebra:
                    - erase/^xx$/
                    - derive/^([jqxy])u$/$1v/
                translator:
                  dictionary: rime_ice
                traditionalize:
                  option_name: traditionalization
                  opencc_config: s2t.json
                  tips: none
                punctuator:
                  __include: default:/punctuator

                """
            try schemaText.write(to: schema, atomically: true, encoding: .utf8)
            try "---\nname: rime_ice\nversion: \"1\"\nsort: by_weight\n...\n".write(
                to: shared.appendingPathComponent("rime_ice.dict.yaml"), atomically: true, encoding: .utf8)
        }

        func apply(_ characters: ChineseCharacters, fuzzy: [String] = []) throws -> FuzzyPinyin.Outcome {
            try FuzzyPinyin.apply(fuzzy, characters: characters, schema: schema, userDir: user)
        }

        /// The patch's lines, trimmed.
        var lines: [String] { (patchText ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) } }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// rime-ice's own list: the switch is the third (@2) …
    static let rimeIceSwitches = """
          - name: ascii_mode
            states: [ 中, Ａ ]
          - name: ascii_punct  # 中英标点
            states: [ ¥, $ ]
          - name: traditionalization
            states: [ 简, 繁 ]
          - name: emoji
            states: [ 💀, 😄 ]
            reset: 1
          - name: full_shape
            states: [ 半角, 全角 ]
        """
    /// … another order, items written in a flow: found by its name, wherever it is.
    static let movedSwitches = """
          - { name: ascii_mode, states: [ 中, Ａ ], reset: 0 }
          - { name: emoji, states: [ 💀, 😄 ], reset: 1 }
          - { name: full_shape, states: [ 半角, 全角 ] }
          - { name: search_single_char, states: [ 正常, 单字 ] }
          - { name: traditionalization, states: [ 简, 繁 ] }
        """

    @Test func s2_taiwanPatchesTheSwitchFoundByName() throws {
        for (switches, index) in [(Self.rimeIceSwitches, 2), (Self.movedSwitches, 4)] {
            let folder = try RimeFolder(switches: switches)
            defer { folder.remove() }
            #expect(try folder.apply(.taiwan) == .written)
            let lines = folder.lines
            #expect(lines.contains("switches/@\(index)/reset: 1"), "the switch on at every session, by its place: \(lines)")
            #expect(!lines.contains { $0.hasPrefix("switches/@") && $0 != "switches/@\(index)/reset: 1" }, "no other switch: \(lines)")
            #expect(lines.contains("traditionalize/opencc_config: s2twp.json"), "Taiwan's characters and words: \(lines)")
        }
    }

    @Test func s2_hongKongPatchUsesS2hk() throws {
        let folder = try RimeFolder(switches: Self.rimeIceSwitches)
        defer { folder.remove() }
        #expect(try folder.apply(.hongkong) == .written)
        #expect(folder.lines.contains("switches/@2/reset: 1"), "\(folder.lines)")
        #expect(folder.lines.contains("traditionalize/opencc_config: s2hk.json"), "\(folder.lines)")
        #expect(!(folder.patchText ?? "").contains("s2twp"))
    }

    @Test func s2_simplifiedHasNoPatchForIt() throws {
        let folder = try RimeFolder(switches: Self.rimeIceSwitches)
        defer { folder.remove() }
        // With fuzzy pinyin (something else in the file): nothing of the characters in it.
        #expect(try folder.apply(.simplified, fuzzy: ["z-zh"]) == .written)
        let text = try #require(folder.patchText)
        #expect(text.contains("speller/algebra"), "fuzzy pinyin still written: \(text)")
        #expect(!text.contains("traditionalize") && !text.contains("opencc") && !text.contains("switches/@"), "\(text)")
        #expect(!text.contains("「") && !text.contains("『"), "rime-ice's own quotation marks: \(text)")
        // Nothing else: no file at all.
        _ = try folder.apply(.simplified, fuzzy: [])
        #expect(folder.patchText == nil, "\(folder.patchText ?? "")")
    }

    @Test func s2_thePatchExistsWhenOnlyTheCharactersAreSet() throws {
        let folder = try RimeFolder(switches: Self.rimeIceSwitches)
        defer { folder.remove() }
        #expect(folder.patchText == nil)
        #expect(try folder.apply(.taiwan) == .written, "no fuzzy pinyin, no dictionaries: written all the same")
        #expect(folder.patchText != nil)
        #expect(try folder.apply(.taiwan) == .unchanged, "the same again: nothing to deploy")
        #expect(try folder.apply(.hongkong) == .written, "changed: deployed again")
        #expect(try folder.apply(.simplified) == .removed, "back to Simplified: the file goes")
        #expect(folder.patchText == nil)
    }

    @Test func s2_fuzzyPinyinAndDictionariesKeepTheCharacters() throws {
        let folder = try RimeFolder(switches: Self.rimeIceSwitches)
        defer { folder.remove() }
        #expect(try folder.apply(.taiwan, fuzzy: ["z-zh"]) == .written)
        var text = try #require(folder.patchText)
        #expect(text.contains("speller/algebra") && text.contains("traditionalize/opencc_config: s2twp.json"), "\(text)")
        // A personal dictionary imported (and removed) writes the same file: the characters stay in it.
        let store = PersonalDictionaryStore(userDirectory: folder.user, schema: folder.schema)
        let source = folder.root.appendingPathComponent("team.dict.yaml")
        try "---\nname: team_words\nversion: \"1\"\n...\n霁鸢星槎\tce shi ci ku\t900000\n".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importDictionary(from: source, fuzzyPinyin: ["z-zh"], characters: .taiwan)
        text = try #require(folder.patchText)
        #expect(text.contains("translator/dictionary") && text.contains("traditionalize/opencc_config: s2twp.json")
                    && text.contains("switches/@2/reset: 1"), "\(text)")
        try store.removeDictionary(named: imported.name, fuzzyPinyin: [], characters: .hongkong)
        text = try #require(folder.patchText, "only the characters left: the file stays")
        #expect(text.contains("traditionalize/opencc_config: s2hk.json") && !text.contains("translator/dictionary"), "\(text)")
    }

    // MARK: 3. The Doctor and OpenCC's data

    /// librime's log (glog) as the Doctor reads it, with the user's home in the path.
    static func doctor(_ line: String) -> (lines: [String], en: String, zh: String, report: String) {
        let lines = Doctor.summarizeLogLines([line], home: "/Users/tca-someone")
        var facts = Doc.healthy
        facts.recentErrors = lines
        let en = Doc.findings(facts, .recentErrors)
        let zh = Doc.findings(facts, .recentErrors, chinese: true)
        return (lines, en.map { $0.text(chinese: false) }.joined(separator: "\n"), zh.map { $0.text(chinese: true) }.joined(separator: "\n"),
                Doctor.report(Doctor.findings(facts, chinese: false), areas: [.recentErrors]))
    }

    @Test func s3_doctorExplainsOpenCCConfigNotFound() {
        let found = Self.doctor("E20261102 09:15:02.481516 31337 simplifier.cc:71] opencc config not found: /Users/tca-someone/Library/Rime/opencc/s2twp.json")
        #expect(found.lines.count == 1 && !found.lines.contains { $0.hasPrefix("error in Rime") || $0.contains("other log line") },
                "recognised as its own event: \(found.lines)")
        #expect(found.en.contains("OpenCC") && found.en.contains("Traditional"), "\(found.en)")
        #expect(found.en.lowercased().contains("reinstall"), "says what to do: \(found.en)")
        #expect(found.zh.contains("OpenCC") && found.zh.contains("繁") && found.zh.contains("重新安装"), "\(found.zh)")
        #expect(!found.en.contains("tca-someone") && !found.report.contains("tca-someone"), "no path of the user's")
        #expect(found.report.split(separator: "\n").count == 1 && found.report.contains("OpenCC"), "\(found.report)")
    }

    @Test func s3_doctorExplainsOpenCCThatCantInitialize() {
        let found = Self.doctor("E20261102 09:15:02.481516 31337 simplifier.cc:93] Error initializing opencc: s2hk.json: invalid format")
        #expect(found.lines.count == 1 && !found.lines.contains { $0.hasPrefix("error in Rime") || $0.contains("other log line") },
                "recognised as its own event: \(found.lines)")
        #expect(found.en.contains("OpenCC") && found.en.contains("Traditional"), "\(found.en)")
        #expect(found.en.lowercased().contains("reinstall"), "says what to do: \(found.en)")
        #expect(found.zh.contains("OpenCC") && found.zh.contains("繁") && found.zh.contains("重新安装"), "\(found.zh)")
    }

    // MARK: 4. Punctuation

    @Test func s4_traditionalQuotesInThePatch() throws {
        for characters in [ChineseCharacters.taiwan, .hongkong] {
            let folder = try RimeFolder(switches: Self.rimeIceSwitches)
            defer { folder.remove() }
            _ = try folder.apply(characters)
            let punctuation = folder.lines.filter { $0.contains("punctuator") }
            // `"` is the key of the line with 「」 (written \" in the quoted key), `'` of the one with 『』.
            #expect(punctuation.contains { $0.contains("「") && $0.contains("」") && $0.contains(#"\""#) }, "\(characters): \(punctuation)")
            #expect(punctuation.contains { $0.contains("『") && $0.contains("』") && $0.contains("'") }, "\(characters): \(punctuation)")
        }
    }

    // MARK: 5. Everywhere else

    @Test func s5_theLanguageTypedIsTheVariant() {
        #expect(TCA.config(.simplified).typedLanguage(.chinese).code == "zh")
        #expect(TCA.config(.taiwan).typedLanguage(.chinese).code == "zh-Hant-TW")
        #expect(TCA.config(.hongkong).typedLanguage(.chinese).code == "zh-Hant-HK")
        #expect(TCA.config(.taiwan).typedLanguage(.english) == .english)
        #expect(ChineseCharacters.taiwan.language.isChinese && ChineseCharacters.hongkong.language.isChinese)
    }

    /// @improve in a text field: pinyin, the candidate, ⏎; the request the model got.
    @Test(arguments: [
        (ChineseCharacters.taiwan, "這個功能太難用了", "Traditional Chinese (Taiwan)"),
        (ChineseCharacters.hongkong, "這個功能太難用了", "Traditional Chinese (Hong Kong)"),
        (ChineseCharacters.simplified, "这个功能太难用了", "Simplified Chinese"),
    ])
    func s5_improveNamesTheVariantAndTeachesInIt(characters: ChineseCharacters, typed: String, name: String) async throws {
        let world = TCAWorld(characters)
        world.config.rewriteStyles = ["润色", "口语"]
        RAStubProtocol.enqueue(world.host, .answer("OK"))
        try await withInterfaceLanguage("en") {
            let field = world.field()
            world.pick("i", in: field)
            #expect(field.composer.draft == "@improve ", "\(field.composer.draft)")
            world.pinyin("zhegegongnengtainanyongle", as: typed, in: field)
            #expect(field.composer.draft == "@improve " + typed, "\(field.composer.draft)")
            field.press(FakeHost.enter)
            #expect(field.settle { !RAStubProtocol.bodies(world.host).isEmpty }, "nothing was sent")
            let sent = try #require(try world.sent().first)
            #expect(sent.last == typed)
            #expect(sent.system.contains(name), "the prompt names \(name):\n\(sent.system)")
            for other in ["Simplified Chinese", "Traditional Chinese (Taiwan)", "Traditional Chinese (Hong Kong)"] where other != name {
                #expect(!sent.system.contains(other), "never \(other) for \(characters):\n\(sent.system)")
            }
            let chinese = sent.examples.filter(TCA.han)
            #expect(!chinese.isEmpty, "Chinese examples: \(sent.examples)")
            if characters.isTraditional {
                for text in chinese { #expect(TCA.simplified(in: text).isEmpty, "an example in Simplified characters: \(text)") }
                #expect(chinese.contains { !TCA.traditional(in: $0).isEmpty }, "the examples in Traditional characters: \(chinese)")
                #expect(sent.examples.contains("這個功能太難用了"), "the example sentence as typed in Traditional: \(sent.examples)")
            } else {
                for text in chinese { #expect(TCA.traditional(in: text).isEmpty, "an example in Traditional characters: \(text)") }
                #expect(sent.examples.contains("这个功能太难用了"))
            }
        }
    }

    @Test func s5_rewriteStylesStayInTheVariant() {
        for (characters, name) in [(ChineseCharacters.taiwan, "Traditional Chinese (Taiwan)"), (.hongkong, "Traditional Chinese (Hong Kong)")] {
            var config = TCA.config(characters, outputs: [.english])
            config.rewriteStyles = ["润色", "正式", "口语"]
            // Writing mode (translations and styles), and @improve.
            for mode in [WritingMode.both, .improve] {
                let request = Prompt.request(for: "明天的會我可能去不了", mode: mode, config: config)
                let system = request.system.map(\.text).joined(separator: "\n")
                #expect(system.contains(name), "\(characters) \(mode): the rewrites are in \(name):\n\(system)")
                #expect(!system.contains("Simplified Chinese"), "\(characters) \(mode):\n\(system)")
                let examples = request.messages.dropLast().map { (role: $0.role, text: $0.content.map(\.text).joined(separator: "\n")) }
                let answers = examples.filter { $0.role == "assistant" }.map(\.text)
                let styleLines = answers.flatMap { $0.split(separator: "\n").map(String.init) }.filter { $0.hasPrefix("STYLE_") && TCA.han($0) }
                #expect(!styleLines.isEmpty, "\(characters) \(mode): style examples in Chinese: \(answers)")
                for line in styleLines { #expect(TCA.simplified(in: line).isEmpty, "\(characters) \(mode): \(line)") }
                for example in examples where TCA.han(example.text) {
                    #expect(TCA.simplified(in: example.text).isEmpty, "\(characters) \(mode): an example in Simplified: \(example.text)")
                }
            }
        }
    }

    /// The system prompt of `mode` on `text` with `config`.
    static func system(_ text: String, _ mode: WritingMode, _ config: Config) -> String {
        Prompt.request(for: text, mode: mode, config: config).system.map(\.text).joined(separator: "\n")
    }

    @Test func s5_translateSkipsTraditionalIntoTraditional() {
        // Traditional typed, Traditional Chinese among the output languages: the same language, nothing to translate it into.
        for characters in [ChineseCharacters.taiwan, .hongkong] {
            let config = TCA.config(characters, outputs: [.english, TCA.zhHant])
            let plan = WritingPlan.make(.translate, text: "這個功能太難用了", config: config)
            let targets = ([plan.versions].compactMap { $0 } + plan.translations).map(\.code)
            #expect(targets == ["en"], "\(characters): \(targets)")
            let system = Self.system("這個功能太難用了", .translate, config)
            #expect(!system.contains("Traditional Chinese"), "\(characters): no Traditional Chinese line asked for:\n\(system)")
        }
        // Simplified typed: a translation into it.
        let simplified = TCA.config(.simplified, outputs: [.english, TCA.zhHant])
        let plan = WritingPlan.make(.translate, text: "这个功能太难用了", config: simplified)
        let targets = ([plan.versions].compactMap { $0 } + plan.translations).map(\.code)
        #expect(targets.contains("zh-Hant") && targets.contains("en"), "\(targets)")
        #expect(Self.system("这个功能太难用了", .translate, simplified).contains("Traditional Chinese"))
        // Traditional typed, into Simplified Chinese: a translation (the other way round).
        let intoSimplified = TCA.config(.taiwan, outputs: [.english, .chinese])
        let back = WritingPlan.make(.translate, text: "這個功能太難用了", config: intoSimplified)
        #expect(([back.versions].compactMap { $0 } + back.translations).map(\.code).contains("zh"))
    }

    /// A reading of "from Simplified it's a translation" (item 5): a Taiwan user who selects a text written in Simplified
    /// characters (a page from the mainland) and asks for it in Traditional Chinese expects it in Traditional characters.
    /// What is typed is the chosen variant; a selection says by its own characters which script it is in.
    @Test func s5_translateASimplifiedSelectionForTaiwan() {
        let config = TCA.config(.taiwan, outputs: [.english, TCA.zhHant])
        let plan = WritingPlan.make(.translate, text: "这个功能太难用了，下个版本再改吧", config: config)
        let targets = ([plan.versions].compactMap { $0 } + plan.translations).map(\.code)
        #expect(targets.contains("zh-Hant"), "a Simplified text asked into Traditional Chinese is translated into it: \(targets)")
    }

    /// @translate in a text field whose only output language is Traditional Chinese: Traditional typed is in it already
    /// (the same language: nothing to translate it into, nothing sent), Simplified typed is translated. @improve on
    /// Traditional with that output language is polishing, as the panel says while the model works.
    @Test func s5_translateThroughTheSessionSkipsTheSameLanguage() async throws {
        for (characters, typed) in [(ChineseCharacters.taiwan, "台灣很美"), (.hongkong, "香港很美")] {
            let world = TCAWorld(characters, outputs: [TCA.zhHant])
            await withInterfaceLanguage("en") {
                let field = world.field()
                world.pick("translate", in: field)
                world.pinyin("taiwanhenmei", as: typed, in: field)
                field.press(FakeHost.enter)
                if case .loading? = field.panel?.status { Issue.record("\(characters): translating Traditional into Traditional Chinese") }
                if case .translating = field.composer.phase { Issue.record("\(characters): a request for the same language") }
                field.settle(timeout: 0.5) { false }
                #expect(RAStubProtocol.bodies(world.host).isEmpty, "\(characters): nothing to translate into, nothing sent")
            }
        }
        let simplified = TCAWorld(.simplified, outputs: [TCA.zhHant])
        RAStubProtocol.enqueue(simplified.host, .answer("ZHHANT: 台灣很美"))
        await withInterfaceLanguage("en") {
            let field = simplified.field()
            simplified.pick("translate", in: field)
            simplified.pinyin("taiwanhenmei", as: "台湾很美", in: field)
            field.press(FakeHost.enter)
            #expect(field.panel?.status == .loading("Translating…"), "\(String(describing: field.panel?.status))")
            #expect(field.settle { !RAStubProtocol.bodies(simplified.host).isEmpty }, "Simplified into Traditional Chinese is translated")
        }
        for characters in [ChineseCharacters.taiwan, .hongkong] {
            let world = TCAWorld(characters, outputs: [TCA.zhHant])
            await withInterfaceLanguage("en") {
                let field = world.field()
                world.pick("i", in: field)
                world.pinyin("taiwanhenmei", as: "台灣很美", in: field)
                field.press(FakeHost.enter)
                #expect(field.panel?.status == .loading("Polishing…"), "\(characters): \(String(describing: field.panel?.status))")
            }
        }
    }

    @Test func s5_translateAsYouTypeSkipsTheSameLanguage() async throws {
        // Traditional typed, into Traditional Chinese: in as typed, nothing collected, nothing sent.
        for (characters, typed) in [(ChineseCharacters.taiwan, "台灣很美"), (.hongkong, "香港很美")] {
            let world = TCAWorld(characters, outputs: [TCA.zhHant, .english])
            await withInterfaceLanguage("en") {
                let field = world.field()
                _ = field.composer.setTranslateMode(TranslateMode.Session(target: TCA.zhHant))
                world.pinyin("henmei", as: typed, in: field)
                #expect(field.document == typed && field.composer.draft.isEmpty, "\(characters): \(field.document) / \(field.composer.draft)")
                #expect(RAStubProtocol.bodies(world.host).isEmpty)
            }
        }
        // Simplified typed, into Traditional Chinese: collected, ⏎ translates.
        let simplified = TCAWorld(.simplified, outputs: [TCA.zhHant, .english])
        RAStubProtocol.enqueue(simplified.host, .answer("ZHHANT: 台灣很美"))
        await withInterfaceLanguage("en") {
            let field = simplified.field()
            _ = field.composer.setTranslateMode(TranslateMode.Session(target: TCA.zhHant))
            simplified.pinyin("henmei", as: "台湾很美", in: field)
            #expect(field.document.isEmpty && field.composer.draft == "台湾很美", "collected: \(field.document) / \(field.composer.draft)")
            field.press(FakeHost.enter)
            #expect(field.settle { !RAStubProtocol.bodies(simplified.host).isEmpty }, "translated")
        }
        // Traditional typed, into Simplified Chinese: translated.
        let intoSimplified = TCAWorld(.taiwan, outputs: [.chinese, .english])
        RAStubProtocol.enqueue(intoSimplified.host, .answer("ZH: 台湾很美"))
        await withInterfaceLanguage("en") {
            let field = intoSimplified.field()
            _ = field.composer.setTranslateMode(TranslateMode.Session(target: .chinese))
            intoSimplified.pinyin("henmei", as: "台灣很美", in: field)
            #expect(field.document.isEmpty && field.composer.draft == "台灣很美", "collected: \(field.document) / \(field.composer.draft)")
            field.press(FakeHost.enter)
            #expect(field.settle { !RAStubProtocol.bodies(intoSimplified.host).isEmpty }, "translated")
        }
    }

    @Test func s5_translateAsYouTypeComesOnIntoAnother() {
        // Chinese typed alone, Traditional Chinese and English to translate into.
        var config = TCA.config(.taiwan, outputs: [TCA.zhHant, .english])
        config.setOrder([Language.chinese])
        var state = TranslateMode.State()
        #expect(state.enter(last: nil, config: config)?.target == .english, "Traditional typed: never into Traditional Chinese")
        config.chineseCharacters = .simplified
        state = TranslateMode.State()
        #expect(state.enter(last: nil, config: config)?.target == TCA.zhHant, "Simplified typed: into Traditional Chinese")
        // Traditional Chinese the only output language: nothing to translate into with Traditional characters.
        config.setOrder([TCA.zhHant])
        #expect(config.hasLanguageToTranslateInto)
        config.chineseCharacters = .hongkong
        #expect(!config.hasLanguageToTranslateInto)
        state = TranslateMode.State()
        #expect(state.enter(last: nil, config: config) == nil)
    }

    @Test func s5_theChipSaysTraditional() async throws {
        for (characters, ui, source, target) in [(ChineseCharacters.taiwan, "zh", "繁", "英"), (.hongkong, "zh", "繁", "英"),
                                                 (.simplified, "zh", "中", "英"), (.taiwan, "en", "ZH-HANT", "EN"),
                                                 (.simplified, "en", "ZH", "EN")] {
            let world = TCAWorld(characters, outputs: [.english], ui: ui)
            world.engine.dictionary["henmei"] = ["很美"]
            await withInterfaceLanguage(ui) {
                // The shell shows the composer's chip while the mode is on (`SessionServices.translateChip`).
                let shown = TCAFieldBox()
                let field = world.field { $0.translateChip = { shown.field?.composer.translateModeChip() } }
                shown.field = field
                _ = field.composer.setTranslateMode(TranslateMode.Session(target: .english))
                field.type("henmei")
                let chip = field.panel?.chip
                #expect(chip?.source == source && chip?.target == target, "\(characters) in \(ui): \(String(describing: chip))")
                let named = field.composer.translateModeChip()
                #expect(named?.sourceText == (characters.isTraditional ? "繁" : "中"), "\(String(describing: named))")
            }
        }
    }

    /// @reply to a selected message, ⏎: the language the reply is asked in.
    func replyLanguage(_ characters: ChineseCharacters, message: String) async throws -> String {
        let world = TCAWorld(characters)
        RAStubProtocol.enqueue(world.host, .answer("OK"))
        var platform = Platform.current
        platform.languages = TCALanguages()
        return try await withInterfaceLanguage("en") {
            try Platform.$override.withValue(platform) {
                let field = world.field()
                field.document = message
                field.selection = 0..<(message as NSString).length
                world.pick("reply", in: field)
                field.press(FakeHost.enter)
                #expect(field.settle { !RAStubProtocol.bodies(world.host).isEmpty }, "nothing was sent")
                let sent = try #require(try world.sent().first)
                // The user's message (the system prompt explains the tag).
                let message = sent.last
                guard let start = message.range(of: "<reply_language>"),
                      let end = message.range(of: "</reply_language>", range: start.upperBound..<message.endIndex)
                else { return "<none>: \(message)" }
                return String(message[start.upperBound..<end.lowerBound])
            }
        }
    }

    @Test func s5_replyIsInTheUsersVariant() async throws {
        // The other party writes Simplified (from the mainland): a Taiwan or Hong Kong user replies in their own.
        #expect(try await replyLanguage(.taiwan, message: "明天的会几点开始？") == "Traditional Chinese (Taiwan)")
        #expect(try await replyLanguage(.hongkong, message: "明天的会几点开始？") == "Traditional Chinese (Hong Kong)")
        #expect(try await replyLanguage(.taiwan, message: "明天的會幾點開始？") == "Traditional Chinese (Taiwan)")
        // A Simplified user replying to Traditional writes Simplified.
        #expect(try await replyLanguage(.simplified, message: "明天的會幾點開始？") == "Simplified Chinese")
        // Not Chinese: the other party's language, whatever the characters.
        #expect(try await replyLanguage(.taiwan, message: "What time does the meeting start tomorrow?") == "English")
    }

    @Test func s5_autocompleteExamplesFollowTheVariant() async throws {
        for characters in [ChineseCharacters.taiwan, .hongkong, .simplified] {
            var config = TCA.config(characters)
            config.provider = .apple  // the on-device model: the one autocomplete gives examples
            let fixed = config
            let model = StubAppleModel(answer: ["一起去吃飯吧"])
            let converter = Converter(loadConfig: { fixed }, appleModel: model)
            let before = characters.isTraditional ? "今天晚上我們" : "今天晚上我们"
            _ = try? await converter.autocomplete(Autocomplete.Context(before: before), app: "com.example.editor")
            let request = try #require(model.requests.last, "\(characters): the model wasn't asked")
            let examples = request.examples.flatMap { [$0.prompt, $0.response] }.filter(TCA.han)
            #expect(!examples.isEmpty, "\(characters): Chinese examples after Chinese: \(request.examples)")
            for text in examples {
                if characters.isTraditional {
                    #expect(TCA.simplified(in: text).isEmpty, "\(characters): an example in Simplified characters: \(text)")
                } else {
                    #expect(TCA.traditional(in: text).isEmpty, "simplified: an example in Traditional characters: \(text)")
                }
            }
            if characters.isTraditional { #expect(examples.contains { !TCA.traditional(in: $0).isEmpty }, "\(examples)") }
        }
    }

    @Test func s5_screenTextReadsTraditionalFirst() async throws {
        #expect(ScreenText.languages(TCA.config(.taiwan)).first == "zh-Hant")
        #expect(ScreenText.languages(TCA.config(.hongkong)).first == "zh-Hant")
        #expect(ScreenText.languages(TCA.config(.simplified)).first == "zh-Hans")
        TCA.onMac(preferring: ["zh-Hant-HK"]) { #expect(ScreenText.languages(TCA.config(nil)).first == "zh-Hant") }
        // A screenshot pasted into @reply with ⌃V is read in them.
        for (characters, first) in [(ChineseCharacters.taiwan, "zh-Hant"), (.simplified, "zh-Hans")] {
            let world = TCAWorld(characters)
            let recognizer = TCARecognizer()
            await withInterfaceLanguage("en") {
                let field = world.field { $0.recognizeText = recognizer }
                world.pick("reply", in: field)
                field.clipboard = .image(TCA.png)
                field.press(FakeHost.controlV)
                #expect(field.settle(timeout: 5) { !recognizer.languages.isEmpty }, "\(characters): the screenshot wasn't read")
                #expect(recognizer.languages.first?.first == first, "\(characters): \(recognizer.languages)")
            }
        }
    }

    @Test func s5_remindReadsTraditionalForms() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Taipei"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10)))  // a Monday
        let parser = ReminderParser(calendar: calendar) { _ in [] }  // its own rules only, as of `now`
        for (traditional, simplified, title) in [("下個禮拜五下午三點開會", "下个礼拜五下午三点开会", "開會"),
                                                 ("這個禮拜五下午三點交報告", "这个礼拜五下午三点交报告", "交報告")] {
            let read = parser.parse(traditional, now: now), reference = parser.parse(simplified, now: now)
            #expect(reference.due?.hour == 15, "the Simplified sentence is read: \(reference)")
            #expect(read.due == reference.due && read.hasTime, "\(traditional): \(read) (Simplified: \(reference))")
            // What to be reminded of stays as the user typed it.
            #expect(read.title == title, "\(traditional): \(read.title)")
        }
        let later = parser.parse("兩個小時以後喝水", now: now)
        #expect(later.date == now.addingTimeInterval(2 * 3600), "\(later)")
        #expect(later.title.contains("喝水") && !later.title.contains("小時"), "\(later.title)")
        let simplifiedLater = parser.parse("两个小时以后喝水", now: now)
        #expect(simplifiedLater.date == now.addingTimeInterval(2 * 3600), "\(simplifiedLater)")
    }

    @Test func s5_theInputIsNamedWithItsVariant() throws {
        let zh = InterfaceLanguage.code(chinese: true), en = InterfaceLanguage.code(chinese: false)
        #expect(SessionText.inputName(.chinese, language: zh, chinese: .simplified) == "中文")
        #expect(SessionText.inputName(.chinese, language: zh, chinese: .taiwan) == "中文（繁體）")
        #expect(SessionText.inputName(.chinese, language: zh, chinese: .hongkong).contains("繁體"))
        #expect(SessionText.inputName(.chinese, language: en, chinese: .taiwan).contains("Traditional"))
        #expect(!SessionText.inputName(.chinese, language: en, chinese: .simplified).contains("Traditional"))
        #expect(SessionText.inputName(.english, language: zh, chinese: .taiwan) == SessionText.inputName(.english, language: zh))
        // Settings: the input languages' row names it so.
        let (service, url) = try service(#"{"provider": "anthropic", "uiLanguage": "zh", "inputLanguages": ["zh", "en"], "chineseCharacters": "taiwan"}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let languages = try #require(service.document().field("inputLanguages"))
        #expect(languages.choices?.first { $0.value == .string("zh") }?.label == "中文（繁體）", "\(languages.choices ?? [])")
    }
}
