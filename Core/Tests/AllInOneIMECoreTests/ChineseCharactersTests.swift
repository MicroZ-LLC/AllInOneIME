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
        #expect(Prompt.version == 8)
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

    /// The Doctor says what to do when librime can't find, or can't read, OpenCC's data.
    @Test func theDoctorNamesTheOpenCCData() {
        let lines = [
            "E20261102 10:00:00.000 1234 simplifier.cc:330] opencc config not found: s2twp.json",
            "E20261102 10:00:01.000 1234 simplifier.cc:340] Error initializing opencc: /Users/alice/Library/Application Support/AllInOneIME/Rime/opencc/STPhrases.ocd2 is not a valid dictionary",
        ]
        let summary = Doctor.summarizeLogLines(lines, home: "/Users/alice")
        #expect(summary == [Doctor.missingOpenCC, Doctor.unreadableOpenCC] && !summary.joined().contains("alice"))
        #expect(summary.allSatisfy { $0.count <= 120 })
        let english = Doctor.localizedLogEvent(summary[0], Doctor.Words(language: "en"))
        #expect(english.contains("reinstall AllInOneIME") && english.contains("Settings → Input → Chinese → Characters"))
        let chinese = Doctor.localizedLogEvent(summary[1] + ", 2 times", Doctor.Words(language: "zh-Hans"))
        #expect(chinese.hasPrefix("Rime：繁体字的转换数据（OpenCC）读不出来") && chinese.hasSuffix("，2 次"))
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
