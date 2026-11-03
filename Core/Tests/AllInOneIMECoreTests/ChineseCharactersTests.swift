import Foundation
import Testing
@testable import AllInOneIMECore

/// The characters Chinese is typed in (`ChineseCharacters`, `Config.chineseCharacters`): the setting and the system's
/// languages when it isn't set, Rime's patch, and Chinese as the language typed everywhere else (the prompts, Translate as
/// You Type, `@reply`, screen text, web search, `@remind`).
@Suite(MemorySecrets())
struct ChineseCharactersTests {
    struct Languages: UserLanguages { var preferred: [String] }

    /// What the system's preferred languages are, for what reads them (`Config.typedChinese`).
    func preferring<T>(_ languages: [String], _ body: () throws -> T) rethrows -> T {
        try Platform.$override.withValue(Platform(userLanguages: Languages(preferred: languages)), operation: body)
    }

    func config(_ characters: ChineseCharacters?, outputs: [OutputLanguage] = [.english], styles: [String] = ["润色"]) -> Config {
        var config = Config.default
        config.inputLanguages = [.chinese, .english]
        config.setOrder(outputs)
        config.rewriteStyles = styles
        config.chineseCharacters = characters
        return config
    }

    // MARK: The setting

    @Test func theSystemsLanguagesDecideUntilOneIsPicked() {
        let cases: [([String], ChineseCharacters)] = [
            (["zh-Hans-CN"], .simplified), (["zh-CN"], .simplified), (["zh"], .simplified),
            (["zh-Hant-TW"], .taiwan), (["zh-TW"], .taiwan), (["zh_TW"], .taiwan), (["zh-Hant"], .taiwan),
            (["zh-MO"], .taiwan), (["zh-Hant-MO"], .taiwan),
            (["zh-HK"], .hongkong), (["zh-Hant-HK"], .hongkong), (["zh_HK"], .hongkong),
            // The script says it: Simplified written in Hong Kong is Simplified.
            (["zh-Hans-HK"], .simplified),
            // The first Chinese one decides, wherever it is.
            (["en-US", "zh-Hant-TW"], .taiwan), (["ja-JP", "zh-HK", "zh-Hans"], .hongkong),
            (["en-US", "fr-FR"], .simplified), ([], .simplified),
        ]
        for (languages, characters) in cases {
            #expect(ChineseCharacters.preferred(from: languages) == characters, "\(languages)")
        }
        // Absent: worked out each time it is read, so a Mac whose language changes follows it.
        let config = self.config(nil)
        #expect(preferring(["zh-Hant-TW", "en"]) { config.typedChinese } == .taiwan)
        #expect(preferring(["zh-HK"]) { config.typedChinese } == .hongkong)
        #expect(preferring(["en-US", "zh-Hans-CN"]) { config.typedChinese } == .simplified)
        // Picked: the same whatever the system says.
        #expect(preferring(["zh-Hant-TW"]) { self.config(.simplified).typedChinese } == .simplified)
        #expect(preferring(["en-US"]) { self.config(.hongkong).typedChinese } == .hongkong)
    }

    @Test func keptInTheConfigOnlyOncePicked() throws {
        func decode(_ text: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(text.utf8)) }
        #expect(try decode("{}").chineseCharacters == nil)
        #expect(try decode(#"{"chineseCharacters": "taiwan"}"#).chineseCharacters == .taiwan)
        #expect(try decode(#"{"chineseCharacters": "hongkong"}"#).chineseCharacters == .hongkong)
        #expect(try decode(#"{"chineseCharacters": "simplified"}"#).chineseCharacters == .simplified)
        // One this version doesn't know, or of the wrong type: the system's, not an error.
        #expect(try decode(#"{"chineseCharacters": "macau"}"#).chineseCharacters == nil)
        #expect(try decode(#"{"chineseCharacters": 2}"#).chineseCharacters == nil)
        // Written only once picked.
        let unset = String(decoding: try JSONEncoder().encode(Config.default), as: UTF8.self)
        #expect(!unset.contains("chineseCharacters"))
        var picked = Config.default
        picked.chineseCharacters = .hongkong
        let text = String(decoding: try JSONEncoder().encode(picked), as: UTF8.self)
        #expect(text.contains(#""chineseCharacters":"hongkong""#))
        #expect(Config.allKeys.contains("chineseCharacters"))
    }

    /// Synced through iCloud as fuzzy pinyin is: one of the three, and taken out (the system's again) too.
    @Test func syncedThroughICloud() {
        let env = ICloudSync.Environment()
        #expect(ICloudSync.category(of: "chineseCharacters") == .settings)
        #expect(ICloudSync.problem("chineseCharacters", .string("taiwan"), environment: env) == nil)
        #expect(ICloudSync.problem("chineseCharacters", .string("macau"), environment: env) == .unknownValue)
        #expect(ICloudSync.problem("chineseCharacters", .bool(true), environment: env) == .wrongType)
        #expect(ICloudSync.problem("chineseCharacters", nil, environment: env) == nil)
        let applied = ICloudSync.applying(["chineseCharacters": .string("taiwan")], to: config(nil), environment: env)
        #expect(applied.config.chineseCharacters == .taiwan && applied.applied == ["chineseCharacters"])
    }

    /// In the settings document, next to fuzzy pinyin while Chinese is typed: the three, the one in use chosen (the
    /// system's until one is picked), and picking one saves it.
    @Test func inTheSettingsDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("characters-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"inputLanguages": ["zh", "en"]}"#.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library)
        try preferring(["zh-Hant-HK"]) {
            let input = try #require(service.document().sections.first { $0.id == "input" })
            let ids = input.fields.map(\.id)
            let field = try #require(input.fields.first { $0.id == "chineseCharacters" })
            #expect(ids.firstIndex(of: "chineseCharacters").map { $0 + 1 } == ids.firstIndex(of: "fuzzyPinyin"))
            #expect(field.kind == .choice && field.value == .string("hongkong"))
            #expect(field.choices?.map(\.value) == [.string("simplified"), .string("taiwan"), .string("hongkong")])
            #expect(try service.set("chineseCharacters", to: .string("taiwan")).get() == ())
            #expect(try Config.load(from: url).chineseCharacters == .taiwan)
            #expect(service.set("chineseCharacters", to: .string("macau")).isSuccess == false)
            // Translating into "zh" from Traditional characters: Simplified Chinese by name.
            let writing = try #require(service.document().sections.first { $0.id == "writing" })
            let zh = writing.fields.first { $0.id == "outputLanguages" }?.choices?.first { $0.value == .string("zh") }
            #expect(zh?.label == OutputLanguage.chinese.name(in: UIText.language, typing: .taiwan)
                        && zh?.label != OutputLanguage.chinese.name(in: UIText.language), "\(String(describing: zh))")
        }
        // Without Chinese typed, there's nothing to set.
        try Data(#"{"inputLanguages": ["en"]}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        #expect(service.document().field("chineseCharacters") == nil)
    }

    // MARK: Rime's patch

    let schema = """
    schema:
      schema_id: rime_ice
    switches:
      - name: ascii_mode
        states: [ 中, Ａ ]
      - name: ascii_punct  # 中英标点
        states: [ ¥, $ ]
      - name: traditionalization
        states: [ 简, 繁 ]
      - name: emoji
        states: [ 💀, 😄 ]
        reset: 1
    speller:
      alphabet: abc
      algebra:
        - abbrev/^([a-z]).+$/$1/
    traditionalize:
      option_name: traditionalization
      opencc_config: s2t.json
    """

    @Test func theSwitchIsFoundByItsName() {
        #expect(ChineseCharacters.switchIndex("traditionalization", inSchema: schema) == 2)
        #expect(ChineseCharacters.switchIndex("ascii_mode", inSchema: schema) == 0)
        #expect(ChineseCharacters.switchIndex("emoji", inSchema: schema) == 3)
        #expect(ChineseCharacters.switchIndex("full_shape", inSchema: schema) == nil)
        // Written in braces, and the list not indented under its key.
        let braces = "switches:\n- { name: ascii_mode, states: [中, A] }\n- {name: traditionalization, reset: 0}\nengine:\n  - x\n"
        #expect(ChineseCharacters.switchIndex("traditionalization", inSchema: braces) == 1)
        #expect(ChineseCharacters.switchIndex("traditionalization", inSchema: "speller:\n  alphabet: abc\n") == nil)
    }

    @Test func thePatchLines() throws {
        #expect(ChineseCharacters.simplified.patch(schema: schema) == nil)
        let taiwan = try #require(ChineseCharacters.taiwan.patch(schema: schema))
        #expect(taiwan == """
              # Traditional (Taiwan) characters: Settings → Input → Chinese → Characters.
              switches/@2/reset: 1
              traditionalize/opencc_config: s2twp.json
              "punctuator/half_shape/\\"": { pair: [ "「", "」" ] }
              "punctuator/half_shape/'": { pair: [ "『", "』" ] }
              "punctuator/full_shape/\\"": { pair: [ "「", "」" ] }
              "punctuator/full_shape/'": { pair: [ "『", "』" ] }

            """)
        #expect(ChineseCharacters.hongkong.patch(schema: schema)?.contains("traditionalize/opencc_config: s2hk.json\n") == true)
        // A schema without the switch can't be patched.
        #expect(ChineseCharacters.taiwan.patch(schema: "speller:\n  alphabet: abc\n") == nil)
        #expect(ChineseCharacters.allCases.compactMap(\.openCCConfig).allSatisfy(ChineseCharacters.openCCFiles.contains))
    }

    /// The same file as fuzzy pinyin's (`rime_ice.custom.yaml`), this app's by its first line: there with Traditional
    /// characters alone, with fuzzy pinyin too, and gone again with neither; the user's own file never touched.
    @Test func writtenWithFuzzyPinyin() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("characters-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let schemaURL = dir.appendingPathComponent("rime_ice.schema.yaml")
        try schema.write(to: schemaURL, atomically: true, encoding: .utf8)
        let user = dir.appendingPathComponent("user")
        let file = user.appendingPathComponent(FuzzyPinyin.fileName)
        func text() throws -> String { try String(contentsOf: file, encoding: .utf8) }
        func apply(_ ids: [String], _ characters: ChineseCharacters) throws -> FuzzyPinyin.Outcome {
            try FuzzyPinyin.apply(ids, characters: characters, schema: schemaURL, userDir: user)
        }
        #expect(try apply([], .simplified) == .unchanged)
        #expect(try apply([], .taiwan) == .written)
        #expect(try text() == FuzzyPinyin.marker + "\npatch:\n" + ChineseCharacters.taiwan.patch(schema: schema)!)
        #expect(try apply([], .taiwan) == .unchanged)
        #expect(try apply(["n-l"], .taiwan) == .written)
        let both = try text()
        #expect(both.hasPrefix(FuzzyPinyin.marker + "\npatch:\n  speller/algebra:\n") && both.contains("\"derive/^n/l/\"")
                && both.hasSuffix(ChineseCharacters.taiwan.patch(schema: schema)!))
        #expect(try apply(["n-l"], .hongkong) == .written && text().contains("opencc_config: s2hk.json"))
        #expect(try apply(["n-l"], .simplified) == .written && !text().contains("opencc"))
        #expect(try apply([], .simplified) == .removed && !FileManager.default.fileExists(atPath: file.path))
        // The user's own file: left as it is, and said so.
        try "patch:\n  menu/page_size: 9\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try apply([], .taiwan) == .userFile)
        #expect(try apply([], .simplified) == .unchanged)
        #expect(try text() == "patch:\n  menu/page_size: 9\n")
    }

    /// With personal dictionaries the patch holds theirs and the characters' lines (the store's branch with them), and an
    /// import or a removal writes it with the characters it is given; the last one removed, the characters stay.
    @Test func keptWithThePersonalDictionaries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("characters-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let user = dir.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let schemaURL = dir.appendingPathComponent("rime_ice.schema.yaml")
        try (schema + "\ntranslator:\n  dictionary: rime_ice\n").write(to: schemaURL, atomically: true, encoding: .utf8)
        try "---\nname: rime_ice\nversion: \"1\"\nsort: by_weight\n...\n你好\tni hao\t1000\n"
            .write(to: dir.appendingPathComponent("rime_ice.dict.yaml"), atomically: true, encoding: .utf8)
        let source = dir.appendingPathComponent("team.dict.yaml")
        try "---\nname: team\nversion: \"1\"\n...\n霁鸢星槎\tji yuan xing cha\n".write(to: source, atomically: true, encoding: .utf8)
        let store = PersonalDictionaryStore(userDirectory: user, schema: schemaURL)
        let file = user.appendingPathComponent(FuzzyPinyin.fileName)
        func text() throws -> String { try String(contentsOf: file, encoding: .utf8) }
        let taiwan = try #require(ChineseCharacters.taiwan.patch(schema: String(contentsOf: schemaURL, encoding: .utf8)))

        _ = try store.importDictionary(from: source, fuzzyPinyin: ["n-l"], characters: .taiwan)
        var written = try text()
        #expect(written.hasPrefix(FuzzyPinyin.marker + "\n# And the personal dictionaries (Settings → Input → Chinese).\npatch:\n  speller/algebra:\n")
                && written.contains("\"derive/^n/l/\"")
                && written.contains("  translator/dictionary: allinoneime_personal\n") && written.hasSuffix(taiwan), "\(written)")
        // Fuzzy pinyin changed with a dictionary there: the characters kept.
        #expect(try store.applyFuzzyPinyin([], characters: .taiwan) == .written)
        written = try text()
        #expect(!written.contains("speller/algebra") && written.contains("translator/dictionary") && written.hasSuffix(taiwan), "\(written)")
        #expect(try store.applyFuzzyPinyin([], characters: .hongkong) == .written && text().contains("opencc_config: s2hk.json"))
        #expect(try store.applyFuzzyPinyin([], characters: .simplified) == .written && !text().contains("opencc"))
        // An import and a removal with the characters given.
        let second = dir.appendingPathComponent("more.dict.yaml")
        try "---\nname: more\nversion: \"1\"\n...\n星槎\txing cha\n".write(to: second, atomically: true, encoding: .utf8)
        _ = try store.importDictionary(from: second, fuzzyPinyin: [], characters: .hongkong)
        #expect(try text().contains("translator/dictionary") && text().contains("opencc_config: s2hk.json"))
        try store.removeDictionary(named: "more", fuzzyPinyin: [], characters: .taiwan)
        #expect(try text().contains("translator/dictionary") && text().hasSuffix(taiwan))
        try store.removeDictionary(named: "team", fuzzyPinyin: [], characters: .taiwan)
        #expect(try text() == FuzzyPinyin.marker + "\npatch:\n" + taiwan)
        try store.removeDictionary(named: "team", fuzzyPinyin: [], characters: .simplified)  // none left: nothing changes
        #expect(try text() == FuzzyPinyin.marker + "\npatch:\n" + taiwan)
    }

    /// No characters picked and the system's languages changed while Rime runs: the patch is to be written again for the
    /// characters they give now, once (`ChineseCharacters.Written`); not before Rime's start first wrote it, not while
    /// they stay, not when picked ones don't change.
    @Test func theCandidatesFollowTheSystemsLanguages() {
        let written = ChineseCharacters.Written()
        let absent = config(nil)
        #expect(preferring(["zh-Hant-TW"]) { written.changed(absent) } == nil, "not written yet: Rime's start writes it")
        written.wrote(.simplified)
        #expect(preferring(["zh-Hans-CN"]) { written.changed(absent) } == nil)
        #expect(preferring(["zh-Hant-TW", "en"]) { written.changed(absent) } == .taiwan)
        #expect(preferring(["zh-Hant-TW", "en"]) { written.changed(absent) } == nil, "asked once")
        #expect(preferring(["zh-HK"]) { written.changed(absent) } == .hongkong)
        #expect(preferring(["en-US"]) { written.changed(absent) } == .simplified)
        // Picked: the system's languages have no say.
        written.wrote(.taiwan)
        #expect(preferring(["en-US"]) { written.changed(self.config(.taiwan)) } == nil)
        #expect(preferring(["zh-Hant-TW"]) { written.changed(self.config(.simplified)) } == .simplified)
    }

    // MARK: The language typed

    @Test func chineseTypedInTraditionalCharactersIsTraditionalChinese() {
        #expect(OutputLanguage(.chinese, chinese: .simplified) == .chinese)
        #expect(OutputLanguage(.chinese, chinese: .taiwan).code == "zh-Hant-TW")
        #expect(OutputLanguage(.chinese, chinese: .hongkong).code == "zh-Hant-HK")
        #expect(OutputLanguage(.english, chinese: .taiwan) == .english)
        #expect(config(.taiwan).typedLanguage(.chinese) == .traditionalTaiwan)
        // Named in the prompts by region: their words differ.
        #expect(OutputLanguage.chinese.promptName == "Simplified Chinese")
        #expect(OutputLanguage.traditionalTaiwan.promptName == "Traditional Chinese (Taiwan)")
        #expect(OutputLanguage.traditionalHongKong.promptName == "Traditional Chinese (Hong Kong)")
        #expect(OutputLanguage.traditionalTaiwan.name(in: "zh-Hans") == "繁体中文（台湾）")
        #expect(OutputLanguage.traditionalHongKong.name(in: "en") == "Traditional Chinese (Hong Kong)")
        // The same language as "zh-Hant", never as "zh"; Simplified as before.
        let hant = OutputLanguage("zh-Hant")
        #expect(Language.chinese.matches(hant, chinese: .taiwan) && Language.chinese.matches(hant, chinese: .hongkong))
        #expect(!Language.chinese.matches(.chinese, chinese: .taiwan) && !Language.chinese.matches(hant))
        #expect(Language.chinese.matches(.chinese) && Language.english.matches(.english, chinese: .taiwan))
        #expect(OutputLanguage.traditionalTaiwan.isSame(as: hant) && !OutputLanguage.traditionalTaiwan.isSame(as: .chinese))
        #expect(!OutputLanguage.chinese.isTraditionalChinese && OutputLanguage.traditionalHongKong.isTraditionalChinese)
        #expect(!OutputLanguage("ja").isChinese)
        // Traditional typed with only Traditional Chinese out: nothing to translate into (English typed has).
        #expect(config(.taiwan, outputs: [hant]).hasLanguageToTranslateInto)
        var only = config(.taiwan, outputs: [hant])
        only.inputLanguages = [.chinese]
        #expect(!only.hasLanguageToTranslateInto)
        only.chineseCharacters = .simplified
        #expect(only.hasLanguageToTranslateInto)
    }

    /// The input menu and Settings say so where it matters: 中文（拼音·繁體）.
    @Test func theInputsName() {
        #expect(SessionText.inputName(.chinese, language: "zh-Hans") == "中文（拼音）")
        #expect(SessionText.inputName(.chinese, language: "zh-Hans", chinese: .taiwan) == "中文（拼音·繁體）")
        #expect(SessionText.inputName(.chinese, language: "en", chinese: .hongkong) == "Chinese (pinyin, Traditional)")
        #expect(SessionText.inputName(.english, language: "en", chinese: .taiwan) == "English")
        #expect(SessionText.inputName(.language(.chinese), language: "zh-Hans", coding: nil, chinese: .taiwan) == "中文（拼音·繁體）")
        #expect(ChineseCharacters.allCases.map { $0.name(in: "zh-Hans") } == ["简体", "繁體（台灣）", "繁體（香港）"])
        #expect(ChineseCharacters.allCases.map { $0.name(in: "en") } == ["Simplified", "Traditional (Taiwan)", "Traditional (Hong Kong)"])
    }

    // MARK: Writing

    /// @improve and polishing keep the characters typed: Traditional is never written in Simplified, and the examples are
    /// typed and answered in Traditional characters too.
    @Test func improveKeepsTraditional() {
        let request = Prompt.request(for: "這個方案還不夠好", mode: .improve, config: config(.taiwan))
        let system = request.system.first?.text ?? ""
        #expect(system.contains("\nZHHANTTW: <how a native Traditional Chinese (Taiwan) speaker"))
        #expect(system.contains("rewritten in Traditional Chinese (Taiwan)") && !system.contains("Simplified"))
        #expect(system.contains("typing a sentence: Chinese, English, or a mix of both."))
        let examples = request.messages.dropLast().compactMap(\.content.first?.text).joined(separator: "\n")
        #expect(request.messages.count > 1 && examples.contains("這個功能太難用了") && examples.contains("ZHHANTTW: 辛苦你了！"))
        #expect(examples.contains("STYLE_POLISH: 這個功能用起來太彆扭了。"))
        // Not one character only Simplified Chinese writes.
        #expect(!examples.contains { "这个说会们团么对时发" .contains($0) }, "\(examples)")
        #expect(Prompt.version == 9)
        // Hong Kong's, named so; Simplified as before.
        let hongKong = Prompt.request(for: "這個方案還不夠好", mode: .improve, config: config(.hongkong)).system.first?.text ?? ""
        #expect(hongKong.contains("\nZHHANTHK: <how a native Traditional Chinese (Hong Kong) speaker"))
        let simplified = Prompt.request(for: "这个方案还不够好", mode: .improve, config: config(.simplified))
        #expect((simplified.system.first?.text ?? "").contains("\nZH: <how a native Simplified Chinese speaker"))
        #expect(simplified.messages.compactMap(\.content.first?.text).contains("这个功能太难用了"))
    }

    /// Into Traditional Chinese from Traditional typed: the same language, polished; from Simplified typed, a translation.
    @Test func translatingIntoTraditionalChinese() {
        let hant = OutputLanguage("zh-Hant")
        let traditional = WritingPlan.make(.translate, text: "這個方案", config: config(.taiwan, outputs: [hant, .english]))
        #expect(traditional.input == .traditionalTaiwan && traditional.versions == .english && traditional.translations.isEmpty)
        let polished = WritingPlan.make(.translate, text: "這個方案", config: config(.taiwan, outputs: [hant]))
        #expect(polished.versions == .traditionalTaiwan)
        let simplified = WritingPlan.make(.translate, text: "这个方案", config: config(.simplified, outputs: [hant]))
        #expect(simplified.input == .chinese && simplified.versions == hant)
        // English typed into Traditional Chinese: the Chinese examples are typed in Traditional characters and polished in
        // them (the examples have no lines in "zh-Hant" itself, as before).
        let texts = Prompt.request(for: "this plan isn't good enough", mode: .translate, config: config(.taiwan, outputs: [hant]))
            .messages.compactMap(\.content.first?.text)
        #expect(texts.contains("這個功能太難用了") && texts.contains { $0.hasPrefix("ZHHANTTW: 這個功能") }
                && !texts.contains { $0.hasPrefix("ZHHANT: ") }, "\(texts)")
        // What the action key will do says so.
        let words = InterfaceWords(language: "en")
        let polish = words.action(.translate, input: .chinese, config: config(.taiwan, outputs: [hant]))
        let translate = words.action(.translate, input: .chinese, config: config(.simplified, outputs: [hant]))
        #expect(polish == "polish" && translate == "translate to Traditional Chinese", "\(polish) | \(translate)")
        #expect(SessionText.hasTranslationTarget(for: "這個", config: config(.taiwan, outputs: [hant])) == false)
        #expect(SessionText.hasTranslationTarget(for: "这个", config: config(.simplified, outputs: [hant])))
    }

    /// Text the user didn't just type says by its own characters which Chinese it is (`Config.writtenLanguage`): a
    /// Simplified selection is translated into Traditional Chinese for a Taiwan user, a Traditional one into Simplified
    /// Chinese for a Simplified user; text that can't tell is in the characters typed.
    @Test func theTextsOwnCharactersSayWhichChineseItIs() {
        #expect(ChineseCharacters.writtenTraditional("这个功能太难用了，下个版本再改吧") == false)
        #expect(ChineseCharacters.writtenTraditional("這個功能太難用了") == true)
        #expect(ChineseCharacters.writtenTraditional("台灣很美") == true && ChineseCharacters.writtenTraditional("台湾很美") == false)
        // What both write alike (皇后, 公里, ICU reads the words), or no Chinese: can't tell.
        #expect(ChineseCharacters.writtenTraditional("香港很美") == nil && ChineseCharacters.writtenTraditional("皇后很美") == nil)
        #expect(ChineseCharacters.writtenTraditional("hello") == nil && ChineseCharacters.writtenTraditional("") == nil)
        // A quote in the other: the side more of it is on.
        #expect(ChineseCharacters.writtenTraditional("他說「这个」這個版本還是太難用了") == true)
        let hant = OutputLanguage("zh-Hant")
        let taiwan = config(.taiwan, outputs: [.english, hant])
        #expect(taiwan.writtenLanguage(of: "这个功能太难用了") == .chinese)
        #expect(taiwan.writtenLanguage(of: "這個功能太難用了") == .traditionalTaiwan && taiwan.writtenLanguage(of: "香港很美") == .traditionalTaiwan)
        let simplified = config(.simplified, outputs: [.english, .chinese])
        #expect(simplified.writtenLanguage(of: "這個功能太難用了") == hant && simplified.writtenLanguage(of: "香港很美") == .chinese)
        #expect(simplified.writtenLanguage(of: "this is fine") == .english)
        // @translate: a Simplified selection into Traditional Chinese, a Traditional one into Simplified.
        #expect(WritingPlan.make(.translate, text: "这个功能太难用了", config: taiwan).translations == [.english, hant])
        #expect(WritingPlan.make(.translate, text: "這個功能太難用了", config: simplified).translations == [.english, .chinese])
        #expect(WritingPlan.make(.translate, text: "这个功能太难用了", config: simplified).versions == .english)
        // Its examples in the sentence's characters, Simplified here (into English: lines the examples have).
        let examples = Prompt.request(for: "这个功能太难用了", mode: .translate, config: config(.taiwan)).messages.dropLast()
            .compactMap(\.content.first?.text).joined(separator: "\n")
        #expect(examples.contains("这个功能太难用了") && !examples.contains("這個功能"), "\(examples)")
        // What the action key will do with such a selection; whether there's a language to translate into.
        #expect(InterfaceWords(language: "en").action(.translate, input: .chinese, config: taiwan, text: "这个功能太难用了")
                    == "translate to English, Traditional Chinese")
        #expect(SessionText.hasTranslationTarget(for: "这个", config: config(.taiwan, outputs: [hant])))
        #expect(!SessionText.hasTranslationTarget(for: "這個", config: config(.taiwan, outputs: [hant])))
        #expect(SessionText.hasTranslationTarget(for: "這個", config: config(.simplified, outputs: [.chinese])))
        // Translate as You Type's draft (pasted into it, say): by its characters too.
        #expect(TranslateMode.plan(for: "这个", target: hant, config: taiwan).input == .chinese)
    }

    /// "zh" is Simplified Chinese by name for someone typing Traditional characters, where into it is a translation: the
    /// output languages, the chip (「简」, "ZH-HANS") and its list, what the action key does. As before for Simplified.
    @Test func simplifiedChineseIsNamedSoForTraditionalTypers() {
        #expect(OutputLanguage.chinese.name(in: "zh-Hans", typing: .taiwan) == "简体中文")
        #expect(OutputLanguage.chinese.name(in: "en", typing: .hongkong) == "Simplified Chinese")
        #expect(OutputLanguage.chinese.name(in: "fr", typing: .taiwan) == "chinois simplifié")
        #expect(OutputLanguage.chinese.name(in: "zh-Hans", typing: .simplified) == "中文")
        #expect(OutputLanguage.chinese.name(in: "en", typing: .simplified) == "Chinese")
        #expect(OutputLanguage("ja").name(in: "en", typing: .taiwan) == "Japanese")
        let chip = TranslateMode.Chip(source: .chinese, target: .chinese, choices: [.english, .chinese], chinese: .taiwan)
        #expect(chip.text == "繁 → 简" && chip.sourceTag == "ZH-HANT" && chip.targetTag == "ZH-HANS")
        #expect(TranslateMode.Chip(source: .english, target: .chinese).text == "英 → 中")
        #expect(TranslateMode.Chip(source: .english, target: .chinese).targetTag == "ZH")
        #expect(PanelPresenter.chipModel(chip, notice: nil, language: "en").rows.map(\.text) == ["English", "Simplified Chinese"])
        #expect(InterfaceWords(language: "zh-Hans").action(.translate, input: .chinese, config: config(.taiwan, outputs: [.chinese]))
                    == "翻译成简体中文")
        #expect(InterfaceWords(language: "zh-Hans").action(.translate, input: .english, config: config(.simplified, outputs: [.chinese]))
                    == "翻译成中文")
    }

    /// Translate as You Type into Traditional Chinese while Simplified is typed, then Traditional picked: Chinese would go
    /// in as typed, the chip 「繁 → 繁」. The target gives way as a removed one does, to the next (none: off); picked
    /// again on the chip, it's the user's.
    @Test func translateAsYouTypeIntoWhatIsTypedNowGivesWay() {
        let hant = OutputLanguage("zh-Hant")
        var config = config(.simplified, outputs: [hant, .english])
        var state = TranslateMode.State()
        func follow(_ chinese: ChineseCharacters) -> Bool {
            state.follow(outputs: config.outputLanguages, inputs: config.inputLanguages, chinese: chinese)
        }
        #expect(state.enter(last: hant, config: config)?.target == hant)
        #expect(follow(.simplified) == false)
        #expect(follow(.taiwan) && state.session?.target == .english)
        state.retarget(hant)
        #expect(follow(.taiwan) == false && state.session?.target == hant)
        // Back to Simplified with Simplified Chinese the target: the same, the other way round.
        config.setOrder([OutputLanguage.chinese, .english])
        config.chineseCharacters = .hongkong
        state = TranslateMode.State()
        #expect(state.enter(last: .chinese, config: config)?.target == .chinese)
        #expect(follow(.simplified) && state.session?.target == .english)
        // Nothing else to translate into: off (the shell says where to add one).
        config.setOrder([hant])
        config.chineseCharacters = .simplified
        state = TranslateMode.State()
        #expect(state.enter(last: nil, config: config)?.target == hant)
        #expect(follow(.hongkong) && !state.isOn)
        // A Simplified typer translating English into Chinese keeps it: the characters didn't change.
        config.setOrder([OutputLanguage.chinese])
        state = TranslateMode.State()
        #expect(state.enter(last: nil, config: config)?.target == .chinese)
        #expect(follow(.simplified) == false && state.isOn)
    }

    /// The Taiwan examples are Taiwan's words where they differ from what ICU's transform gives (儘快, 主管, 使用者, 下週),
    /// Hong Kong's ICU's; Simplified as written.
    @Test func taiwanExamplesUseTaiwansWords() {
        let all = Prompt.examples.flatMap { [$0.input] + $0.chinese } + RewriteStyle.catalog.flatMap(\.exampleRewrites)
            + Prompt.autocompleteChineseExamples.flatMap { [$0.context.before, $0.context.after, $0.answer] }
        let taiwan = all.map(OutputLanguage.traditionalTaiwan.written).joined(separator: "\n")
        for mainland in ["盡快", "用戶", "領導", "下周", "回趟家", "差點意思", "不好意思哈"] { #expect(!taiwan.contains(mainland), "\(mainland)") }
        for word in ["儘快", "使用者體驗", "主管", "下週"] { #expect(taiwan.contains(word), "\(word)") }
        #expect(Prompt.taiwan.keys.allSatisfy(all.contains), "each written for an example there is")
        #expect(Prompt.taiwan.values.allSatisfy { ChineseCharacters.writtenTraditional($0) != false }, "none of it Simplified")
        #expect(OutputLanguage.traditionalHongKong.written("你们团队得尽快修复") == "你們團隊得盡快修復")
        #expect(OutputLanguage.chinese.written("你们团队得尽快修复") == "你们团队得尽快修复")
        let typed = Prompt.autocompleteExamples(for: "感謝大家的支持，", chinese: .taiwan).map(\.answer)
        #expect(typed.contains("我們下週會公布最終結果。"), "\(typed)")
    }

    /// Translate as You Type: Traditional typed isn't collected for Traditional Chinese, the chip's source says 繁, and the
    /// target is the first output language something typed is translated into.
    @Test func translateAsYouType() {
        let hant = OutputLanguage("zh-Hant")
        #expect(TranslateMode.first(of: [hant, .english], from: [.chinese], chinese: .taiwan) == .english)
        #expect(TranslateMode.first(of: [hant, .english], from: [.chinese]) == hant)
        #expect(TranslateMode.target(last: nil, outputs: [hant, .english], inputs: [.chinese], chinese: .hongkong) == .english)
        let chip = TranslateMode.Chip(source: .chinese, target: .english, chinese: .taiwan)
        #expect(chip.sourceText == "繁" && chip.text == "繁 → 英" && chip.sourceTag == "ZH-HANT")
        #expect(TranslateMode.Chip(source: .chinese, target: .english).sourceText == "中")
        #expect(TranslateMode.Chip(source: .chinese, target: .english, chinese: .hongkong).sourceTag == "ZH-HANT")
        let plan = TranslateMode.plan(for: "這個", target: .english, config: config(.taiwan))
        #expect(plan.input == .traditionalTaiwan)
        var state = TranslateMode.State(), typed = config(.taiwan, outputs: [hant, .english])
        typed.inputLanguages = [.chinese]
        #expect(state.enter(last: nil, config: typed)?.target == .english)
    }

    /// The composer's mode knows the characters typed: Traditional typed into Traditional Chinese goes in as typed.
    @Test func theComposersModeKnowsTheCharacters() {
        let composer = Composer(engine: nil)
        composer.inputLanguages = [.chinese]
        composer.chineseCharacters = .taiwan
        _ = composer.setTranslateMode(TranslateMode.Session(target: OutputLanguage("zh-Hant")))
        #expect(composer.translateModeChip()?.sourceText == "繁")
        #expect(!composer.modeCollects)
        composer.chineseCharacters = .simplified
        #expect(composer.translateModeChip()?.sourceText == "中")
    }

    /// The on-device model's autocomplete examples are in the characters typed.
    @Test func autocompleteExamples() {
        let traditional = Prompt.autocompleteExamples(for: "這週五晚上", chinese: .taiwan)
        #expect(traditional.first?.context.before == "這週五晚上我們" && traditional.first?.answer == "一起去吃火鍋吧？")
        #expect(traditional.contains { $0.context.after.contains("別忘了帶鑰匙") })
        #expect(Prompt.autocompleteExamples(for: "这周五晚上").first?.answer == "一起去吃火锅吧？")
        let request = Prompt.autocompleteRequest(.init(before: "這週五晚上"), app: nil, onDevice: true, chinese: .hongkong)
        #expect(request.messages.compactMap(\.content.first?.text).contains("一起去吃火鍋吧？"))
    }

    // MARK: Everywhere else

    @Test func replyInTheUsersCharacters() {
        #expect(ReplyContext.name(ofCode: "zh-Hant", chinese: .simplified) == "Simplified Chinese")
        #expect(ReplyContext.name(ofCode: "zh-Hans", chinese: .taiwan) == "Traditional Chinese (Taiwan)")
        #expect(ReplyContext.name(ofCode: "zh", chinese: .hongkong) == "Traditional Chinese (Hong Kong)")
        #expect(ReplyContext.name(ofCode: "ja", chinese: .taiwan) == "Japanese")
    }

    @Test func screenTextReadsTraditionalFirst() {
        #expect(ScreenText.languages(config(.taiwan)).prefix(2) == ["zh-Hant", "zh-Hans"])
        #expect(ScreenText.languages(config(.hongkong)).first == "zh-Hant")
        #expect(ScreenText.languages(config(.simplified)).first == "zh-Hans")
        #expect(!ScreenText.languages(config(.taiwan)).contains("zh-Hant-TW"))
    }

    @Test func webSearchAsksForTraditionalPages() throws {
        func items(_ backend: any SearchBackend, _ query: String) throws -> [String: String] {
            let request = try backend.request(for: query, count: 5, detailed: false, key: "k")
            let url = try #require(request.url)
            return Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") })
        }
        #expect(try items(WebSearch.backend(chinese: .taiwan), "蘋果發表會")["search_lang"] == "zh-hant")
        #expect(try items(WebSearch.backend(chinese: .hongkong), "蘋果")["search_lang"] == "zh-hant")
        #expect(try items(WebSearch.backend(chinese: .simplified), "苹果")["search_lang"] == "zh-hans")
        #expect(try items(WebSearch.backend(chinese: .taiwan), "apple event")["search_lang"] == nil)
        let place = SessionTasks.Place(app: nil, terminal: false, pastesInTerminal: false, improveTranslates: false,
                                       pluginLanguage: .chinese, chinese: .taiwan)
        #expect(place.chinese == .taiwan)
    }

    /// `@remind` reads Traditional characters as it reads Simplified ones; the title keeps them.
    @Test func remindersInTraditionalCharacters() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 16))!
        let parser = ReminderParser(calendar: calendar) { _ in [] }
        let later = parser.parse("兩個小時以後提醒我開會", now: now)
        #expect(later.title == "開會" && later.hasTime && later.date == now.addingTimeInterval(2 * 3600), "\(later)")
        let simplified = parser.parse("两个小时以后提醒我开会", now: now)
        #expect(simplified.date == later.date && simplified.title == "开会")
        let friday = parser.parse("下個禮拜五下午三點交報告", now: now)
        #expect(friday.title == "交報告" && friday.hasTime && friday.due == parser.parse("下个礼拜五下午三点交报告", now: now).due, "\(friday)")
        #expect(friday.due?.day == 16 && friday.due?.hour == 15, "\(friday)")
        #expect(ReminderParser.Written("這個禮拜五").text == "这个礼拜五")
    }

    /// The Doctor says what to do when librime can't use OpenCC's data. librime 1.16.1 logs a config that is missing and
    /// one it can't read alike, "opencc config not found" with the path quoted (its simplifier loads the config lazily and
    /// catches what OpenCC throws); an older librime's "Error initializing opencc" is the same event.
    @Test func theDoctorNamesTheOpenCCData() {
        let lines = [
            #"E20261102 10:00:00.000 1234 simplifier.cc:46] opencc config not found: "/Users/alice/Library/Application Support/AllInOneIME/Rime/opencc/s2twp.json""#,
            #"E20261102 10:05:00.000 1234 simplifier.cc:46] opencc config not found: "/Users/alice/Library/Application Support/AllInOneIME/Rime/opencc/s2hk.json""#,
        ]
        let summary = Doctor.summarizeLogLines(lines, home: "/Users/alice")
        #expect(summary == [Doctor.failedOpenCC + ", 2 times"] && !summary.joined().contains("alice"), "\(summary)")
        #expect(Doctor.summarizeLogLines(["E20261102 10:00:01.000 1234 simplifier.cc:93] Error initializing opencc: s2hk.json"])
                    == [Doctor.failedOpenCC])
        #expect(summary.allSatisfy { $0.count <= 120 })
        let english = Doctor.localizedLogEvent(summary[0], Doctor.Words(language: "en"))
        #expect(english.contains("missing or can't be read") && english.contains("reinstall AllInOneIME")
                    && english.contains("files of your own") && english.contains("Settings → Input → Chinese → Characters"), "\(english)")
        let chinese = Doctor.localizedLogEvent(summary[0], Doctor.Words(language: "zh-Hans"))
        #expect(chinese.hasPrefix("Rime：繁体字的转换数据（OpenCC）缺少或读不出来") && chinese.contains("重新安装")
                    && chinese.hasSuffix("，2 次"), "\(chinese)")
    }

    /// Earlier runs' errors about OpenCC's data don't keep the warning once the app's files are in the Rime folder, or
    /// Simplified is chosen, as lua/lunar.db's don't once it's there; not known, they are errors.
    @Test func earlierOpenCCErrorsAreResolvedAsTheLunarDatabasesAre() {
        let line = #"E20261102 10:00:00.000 1234 simplifier.cc:46] opencc config not found: "/Users/alice/Rime/opencc/s2twp.json""#
        func finding(_ openCC: Doctor.OpenCCNow) -> Doctor.Finding? {
            var facts = Doctor.Facts()
            facts.recentErrors = Doctor.summarizeLogLines([line], home: "/Users/alice", openCC: openCC)
            return Doctor.findings(facts, chinese: false).first { $0.area == .recentErrors }
        }
        #expect(finding(.unknown)?.status == .warning && finding(.unknown)?.title == "1 recent error in the logs")
        for (openCC, why) in [(Doctor.OpenCCNow.provided, "this version provides it"), (.unused, "Simplified is chosen now")] {
            let found = finding(openCC)
            #expect(found?.status == .ok && found?.title == "An earlier Rime error is resolved", "\(openCC): \(String(describing: found))")
            #expect(found?.detail?.hasSuffix(why) == true, "\(String(describing: found?.detail))")
        }
        let chinese = Doctor.localizedLogEvent(Doctor.unusedOpenCC, Doctor.Words(language: "zh-Hans"))
        #expect(chinese == "之前运行 Rime 时用不了繁体字的转换数据（OpenCC）；现在选的是简体")
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
