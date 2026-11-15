import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner decisions 2026-11-14 (0.7.5), part 1: Japanese is its own language. A text with at least one hiragana or
/// katakana letter is Japanese ("ja"), with or without kanji, Latin letters or digits; the long-vowel mark ー and the
/// middle dot ・ alone don't make it so; kanji alone stays Chinese. `@translate` of it goes into every output language but
/// Japanese, `@improve` keeps it Japanese, one @ puts Translate first, the action line names what happens, Translate as You
/// Type translates it. `Language` (the input languages) gets no Japanese. Written from the spec by a separate agent; the
/// implementer doesn't edit it (AGENTS.md rule 11).
///
/// The AI is a stand-in for the on-device model that keeps each request (never a real call).
@Suite(.serialized)
struct OwnerDecisions075JapaneseTests {
    typealias Suite = OwnerDecisions075JapaneseTests

    static let ja = OutputLanguage("ja")

    /// Japanese: kana with kanji, kana alone, half-width katakana, kana with Latin letters or digits, a kana word in a
    /// Chinese sentence (at least one kana letter: the rule as written), and a letter from each end of each range the
    /// spec lists (U+3041–3096, U+309D–309F, U+30A1–30FA, U+30FD–30FF, U+31F0–31FF, U+FF66–FF9D).
    static let japanese = [
        "東京駅で待ってます", "ありがとう", "カタカナ", "ﾃｽﾄ", "iPhoneを買った", "3時に会いましょう", "日本語の勉強", "ラーメン",
        "コーヒーを飲みたい", "我想喝コーヒー",
        "ぁ", "ゖ", "ゝ", "ゟ", "ァ", "ヺ", "ヽ", "ヿ", "ㇰ", "ㇿ", "ｦ", "ﾝ",
    ]

    /// Not Japanese: the long-vowel mark and the middle dot alone (with or without kanji).
    static let marksOnly = ["ー", "・", "ー・ー", "東京・大阪", "東京ー"]

    /// Kanji only: Chinese, as before (it can't be told apart).
    static let kanjiOnly = ["東京", "東京大学", "日本語", "会社"]

    /// Chinese the main input language, then English; `outputs` the output languages; Chinese typed in Simplified
    /// characters; `@improve` alone doesn't translate.
    static func config(outputs: [OutputLanguage] = [.english, .chinese], inputs: [Language] = [.chinese, .english]) -> Config {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder(inputs)
        config.setOrder(outputs)
        config.rewriteStyles = ["润色", "简洁"]
        config.chineseCharacters = .simplified
        config.improveTranslates = false
        config.provider = .apple
        config.claudeInBackground = false
        return config
    }

    /// The tags of the lines a request's system prompt asks for, in order ("EN", "ZH", "STYLE_POLISH" …).
    static func formatLines(_ system: String) -> [String] {
        guard let start = system.range(of: "Reply in exactly this format and nothing else:\n"),
              let end = system.range(of: "\n\nRules:", range: start.upperBound..<system.endIndex) else { return [] }
        return system[start.upperBound..<end.lowerBound].components(separatedBy: "\n")
    }

    static func formatTags(_ system: String) -> [String] { formatLines(system).map { String($0.prefix { $0 != ":" }) } }

    static func system(_ request: ConverseRequest) -> String { request.system.map(\.text).joined(separator: "\n\n") }

    // MARK: - 1. What is Japanese; 2. the written language

    @Test func kanaMakesATextJapanese() {
        for chinese in [ChineseCharacters.simplified, .taiwan] {
            var config = Suite.config()
            config.chineseCharacters = chinese
            for text in Suite.japanese {
                #expect(config.writtenLanguage(of: text) == Suite.ja, "\(text) (\(chinese)): \(config.writtenLanguage(of: text).code)")
            }
        }
    }

    /// `OutputLanguage.of` says "ja" whatever `language:` and `chinese:` it is given.
    @Test func japaneseWhateverTheLanguageGiven() {
        for text in Suite.japanese {
            for language in Language.allCases {
                for chinese in ChineseCharacters.allCases {
                    let found = OutputLanguage.of(text, language: language, chinese: chinese)
                    #expect(found == Suite.ja, "\(text) as \(language) (\(chinese)): \(found.code)")
                }
            }
        }
    }

    @Test func theMarksAloneDontMakeATextJapanese() {
        let config = Suite.config()
        for text in Suite.marksOnly {
            #expect(config.writtenLanguage(of: text) != Suite.ja, "\(text): \(config.writtenLanguage(of: text).code)")
        }
    }

    @Test func kanjiAloneStaysChinese() {
        let config = Suite.config()
        for text in Suite.kanjiOnly {
            let found = config.writtenLanguage(of: text)
            #expect(found.isChinese && found != Suite.ja, "\(text): \(found.code)")
        }
    }

    /// Chinese, English, Korean, Hindi, French texts: as before.
    @Test func otherLanguagesAreUnchanged() {
        let config = Suite.config()
        let cases: [(String, OutputLanguage)] = [
            ("这家店的菜很好吃", .chinese), ("这个功能太难用了", .chinese), ("This feature is hard to use", .english),
            ("thank you for the gift", .english), ("오늘 몸이 좀 안 좋아요", OutputLanguage("ko")), ("ㅋㅋ", OutputLanguage("ko")),
            ("आज मेरी तबीयत ठीक नहीं है", OutputLanguage("hi")), ("這個功能太難用了", OutputLanguage("zh-Hant")),
        ]
        for (text, language) in cases {
            #expect(config.writtenLanguage(of: text) == language, "\(text): \(config.writtenLanguage(of: text).code)")
        }
        let french = Suite.config(inputs: [.english, .french])
        #expect(french.writtenLanguage(of: "on se voit demain ?") == OutputLanguage("fr"),
                "\(french.writtenLanguage(of: "on se voit demain ?").code)")
    }

    /// The input languages stay Chinese, English, French, Korean and Hindi: no Japanese among them.
    @Test func noJapaneseInputLanguage() {
        #expect(Language.allCases.map(\.rawValue) == ["zh", "en", "fr", "ko", "hi"], "\(Language.allCases)")
        #expect(Language(rawValue: "ja") == nil)
    }

    // MARK: - 3. @translate

    /// Into every output language but Japanese itself: `[en, zh]` a line each, `[en]` or `[ja, en]` three English versions.
    @Test func translatingJapaneseGoesIntoEveryOtherOutputLanguage() {
        for text in ["東京駅で待ってます", "ありがとう", "日本語の勉強"] {
            let both = WritingPlan.make(.translate, text: text, config: Suite.config(outputs: [.english, .chinese]))
            #expect(both.input == Suite.ja && both.versions == nil && both.translations == [.english, .chinese] && both.styles.isEmpty,
                    "\(text), [en, zh]: \(both)")
            let english = WritingPlan.make(.translate, text: text, config: Suite.config(outputs: [.english]))
            #expect(english.input == Suite.ja && english.versions == .english && english.translations.isEmpty, "\(text), [en]: \(english)")
            let fromJapanese = WritingPlan.make(.translate, text: text, config: Suite.config(outputs: [Suite.ja, .english]))
            #expect(fromJapanese.input == Suite.ja && fromJapanese.versions == .english && fromJapanese.translations.isEmpty,
                    "\(text), [ja, en]: \(fromJapanese)")
        }
    }

    /// What reaches the AI for `@translate` of a Japanese text with `[en, zh]`: an EN line and a ZH line.
    @Test func theTranslateRequestAsksForEnglishAndChinese() {
        for text in ["東京駅で待ってます", "ありがとう"] {
            let request = Prompt.request(for: text, mode: .translate, config: Suite.config(outputs: [.english, .chinese]))
            #expect(Suite.formatTags(Suite.system(request)) == ["EN", "ZH"], "\(text): \(Suite.formatTags(Suite.system(request)))")
        }
    }

    /// Whether there is a language to translate it into: Chinese is one for Japanese; Japanese alone is none.
    @Test func chineseIsALanguageToTranslateJapaneseInto() {
        let text = "東京駅で待ってます"
        #expect(SessionText.hasTranslationTarget(for: text, config: Suite.config(outputs: [.chinese])), "into Chinese")
        #expect(!SessionText.hasTranslationTarget(for: text, config: Suite.config(outputs: [Suite.ja])), "Japanese alone")
    }

    // MARK: - 4. @improve, and both

    @Test func improvingJapaneseKeepsItJapanese() {
        for text in ["東京駅で待ってます", "ありがとう"] {
            let config = Suite.config(outputs: [.english, .chinese])
            let plan = WritingPlan.make(.improve, text: text, config: config)
            #expect(plan.input == Suite.ja && plan.versions == Suite.ja && plan.translations.isEmpty && !plan.styles.isEmpty,
                    "\(text): \(plan)")
            let system = Suite.system(Prompt.request(for: text, mode: .improve, config: config))
            let tags = Suite.formatTags(system)
            #expect(Array(tags.prefix(3)) == ["JA", "JA", "JA"] && tags.dropFirst(3).allSatisfy { $0.hasPrefix("STYLE_") } && tags.count > 3,
                    "\(text): \(tags)")
            let styleLines = Suite.formatLines(system).filter { $0.hasPrefix("STYLE_") }
            #expect(!styleLines.isEmpty && styleLines.allSatisfy { $0.contains("Japanese") && !$0.contains("Chinese") }, "\(styleLines)")
            #expect(system.contains("Japanese") && !system.contains("Simplified Chinese"), "\(text): \(system)")
        }
    }

    /// The default action (`@improve` + `@translate`): the translations as `@translate`'s, then the rewrites in Japanese.
    @Test func improveAndTranslateTogetherOnJapanese() {
        let text = "東京駅で待ってます", config = Suite.config(outputs: [.english, .chinese])
        let plan = WritingPlan.make(.both, text: text, config: config)
        #expect(plan.input == Suite.ja && plan.versions == nil && plan.translations == [.english, .chinese] && !plan.styles.isEmpty,
                "\(plan)")
        let system = Suite.system(Prompt.request(for: text, mode: .both, config: config))
        let tags = Suite.formatTags(system)
        #expect(Array(tags.prefix(2)) == ["EN", "ZH"] && tags.dropFirst(2).allSatisfy { $0.hasPrefix("STYLE_") } && tags.count > 2,
                "\(tags)")
        let styleLines = Suite.formatLines(system).filter { $0.hasPrefix("STYLE_") }
        #expect(!styleLines.isEmpty && styleLines.allSatisfy { $0.contains("Japanese") && !$0.contains("Chinese") }, "\(styleLines)")
    }

    // MARK: - 5. One @ (the rule)

    @Test func japaneseIsAnotherLanguageForEveryInputLanguage() {
        for text in Suite.japanese {
            for main in Language.allCases {
                #expect(OneAt.isOtherLanguage(text, main: main), "\(text), main \(main)")
            }
        }
    }

    @Test func kanjiAloneIsChineseForOneAt() {
        for text in Suite.kanjiOnly {
            #expect(!OneAt.isOtherLanguage(text, main: .chinese), "\(text)")
        }
    }

    // MARK: - 6. Named as Japanese

    @Test func japaneseIsNamedInBothInterfaceLanguages() {
        #expect(Suite.ja.name(in: "zh-Hans") == "日语", "\(Suite.ja.name(in: "zh-Hans"))")
        #expect(Suite.ja.name(in: "en") == "Japanese", "\(Suite.ja.name(in: "en"))")
    }

    /// What the action key does with a Japanese text, as the line under a command says it (the selection's text given).
    @Test func theActionLineSaysWhatHappensToJapanese() {
        let config = Suite.config(outputs: [.english, .chinese])
        let (en, zh) = (InterfaceWords(language: "en"), InterfaceWords(language: "zh-Hans"))
        for text in ["東京駅で待ってます", "ありがとう"] {
            let input = config.language(of: text)
            #expect(en.action(.translate, input: input, config: config, text: text) == "translate to English, Chinese",
                    "\(text): \(en.action(.translate, input: input, config: config, text: text))")
            #expect(zh.action(.translate, input: input, config: config, text: text) == "翻译成英文、中文",
                    "\(text): \(zh.action(.translate, input: input, config: config, text: text))")
            #expect(en.action(Command.translate, input: input, config: config, text: text) == "translate to English, Chinese",
                    "\(text): \(en.action(Command.translate, input: input, config: config, text: text))")
            #expect(en.action(.improve, input: input, config: config, text: text) == "polish / rewrite",
                    "\(text): \(en.action(.improve, input: input, config: config, text: text))")
            #expect(zh.action(.improve, input: input, config: config, text: text) == "润色 / 改写",
                    "\(text): \(zh.action(.improve, input: input, config: config, text: text))")
            #expect(en.action(Command.improve, input: input, config: config, text: text) == "polish / rewrite",
                    "\(text): \(en.action(Command.improve, input: input, config: config, text: text))")
        }
    }

    // MARK: - 7. Translate as You Type

    /// A Japanese draft is translated into the mode's target like any text in another language; already in the target
    /// (Japanese), it goes in as typed, as any text in the target does. Typed with the input on English, which the mode
    /// collects when its target isn't English.
    @Test func translateAsYouTypeTranslatesAJapaneseDraft() {
        let cases: [(String, OutputLanguage, Bool)] = [
            ("東京駅で待ってます", .chinese, true), ("ありがとう", .chinese, true), ("日本語の勉強", .chinese, true),
            ("東京駅で待ってます", Suite.ja, false), ("ありがとう", Suite.ja, false),
        ]
        for (text, target, translated) in cases {
            let c = Composer(engine: FakeEngine(), actionKey: .enter)
            c.commands = Command.builtins
            c.chineseCharacters = .simplified
            _ = c.setTranslateMode(TranslateMode.Session(target: target))
            c.setInputMode(.english)
            for character in text { _ = c.handleKeyDown(k(String(character))) }
            #expect(c.draft == text, "\(text): the draft \(c.draft)")
            let effects = c.handleKeyDown(enterKey).effects
            let sent = effects.compactMap { effect -> String? in
                if case let .startTranslateMode(input, _, _) = effect { return input }
                return nil
            }
            if translated {
                #expect(sent == [text] && commits(effects).isEmpty, "\(text) into \(target.code): \(effects)")
            } else {
                #expect(sent.isEmpty && commits(effects) == [text], "\(text) into \(target.code): \(effects)")
            }
        }
    }

    // MARK: - Through a field's session

    /// The on-device model (`Provider.apple`): keeps each request, answers it with one line.
    final class Model: AppleModelBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["de", "en", "es", "fr", "ja", "ko", "zh"]
        private let asked = Locked<[AppleModelRequest]>(initialState: [])

        var requests: [AppleModelRequest] { asked.withLock { $0 } }

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            asked.withLock { $0.append(request) }
            return AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: "OK"))
                continuation.finish()
            }
        }
    }

    /// A field of an editor with the focus (`Suite.config`), its text `selected` and all of it selected, the input on
    /// English or Chinese.
    final class Field {
        let host: FakeHost
        let model = Model()

        init(english: Bool = false, selected: String? = nil, config: Config = Suite.config()) {
            let fixed = config
            let converter = Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model)
            var services = SessionServices(converter: converter, loadSettings: { fixed })
            services.levelOne = { .engine(FakeEngine()) }
            services.programInstalled = { _ in true }
            host = FakeHost(services: services)
            host.app = "com.example.editor"
            if let selected {
                host.document = selected
                host.selection = 0..<(selected as NSString).length
            }
            host.focus()
            if english { host.composer.setInputMode(.english) }
        }

        /// "@name" and Tab: the command picked.
        func pick(_ name: String) {
            host.type("@" + name)
            host.press(FakeHost.tab)
        }

        /// `text` pasted with ⌃V.
        func paste(_ text: String) {
            host.clipboard = .text(text)
            host.press(FakeHost.controlV)
        }

        /// ⏎, and what reached the AI for it (nil: nothing within five seconds).
        func returnSends() -> AppleModelRequest? {
            host.press(FakeHost.enter)
            host.settle(timeout: 5) { !model.requests.isEmpty }
            return model.requests.first
        }

        /// All the panel says: its rows, its status line (the line under a command: "⏎ → translate to …"), the rest.
        var panelText: String {
            guard let panel = host.panel else { return "" }
            let status: String
            switch panel.status {
            case .none: status = ""
            case let .loading(text), let .hint(text), let .error(text): status = text
            case let .list(text, items): status = ([text] + items).joined(separator: " ")
            }
            return (panel.rows.flatMap { [$0.text, $0.comment] } + panel.header
                    + [status, panel.input?.text ?? "", panel.candidates ?? "", panel.detail ?? "", panel.footer]).joined(separator: " ")
        }

        /// What each row is: the command whose name it shows ("@translate", in its text or its comment, or the name alone).
        var kinds: [String] {
            let names = Command.builtins.map(\.name) + [Command.edit.name]
            return (host.panel?.rows ?? []).map { row in
                for part in [row.text, row.comment] {
                    let bare = part.trimmingCharacters(in: .whitespaces)
                    if names.contains(bare) { return bare }
                    let characters = Array(part)
                    for (index, character) in characters.enumerated() where character == "@" {
                        let name = String(characters[(index + 1)...].prefix { $0.isASCII && $0.isLetter })
                        if names.contains(name) { return name }
                    }
                }
                return row.text
            }
        }
    }

    /// `@translate` on a Japanese selection: the line says English and Chinese, and the AI is asked for both.
    @Test func translateOnAJapaneseSelection() async {
        await withInterfaceLanguage("en") {
            let field = Field(selected: "東京駅で待ってます")
            field.pick("translate")
            #expect(field.panelText.contains("translate to English, Chinese"), "\(field.panelText)")
            let sent = field.returnSends()
            #expect(Suite.formatTags(sent?.instructions ?? "") == ["EN", "ZH"], "\(String(describing: sent?.instructions))")
        }
    }

    /// `@improve` on a Japanese selection: polished in Japanese, never "translate to Chinese".
    @Test func improveOnAJapaneseSelection() async {
        await withInterfaceLanguage("en") {
            let field = Field(selected: "東京駅で待ってます")
            field.pick("improve")
            #expect(field.panelText.contains("polish / rewrite") && !field.panelText.contains("translate to"), "\(field.panelText)")
            let sent = field.returnSends()
            let instructions = sent?.instructions ?? ""
            #expect(Array(Suite.formatTags(instructions).prefix(3)) == ["JA", "JA", "JA"] && !instructions.contains("Simplified Chinese"),
                    "\(instructions)")
        }
    }

    /// `@translate` with Japanese pasted as its text: into English and Chinese.
    @Test func translatePastedJapanese() async {
        await withInterfaceLanguage("en") {
            let field = Field(english: true)
            field.pick("translate")
            field.paste("東京駅で待ってます")
            #expect(field.host.composer.draft == "@translate 東京駅で待ってます", "\(field.host.composer.draft)")
            let sent = field.returnSends()
            #expect(Suite.formatTags(sent?.instructions ?? "") == ["EN", "ZH"], "\(String(describing: sent?.instructions))")
        }
    }

    /// One @ on a Japanese selection, Chinese the main input language: Translate first, and ⏎ asks for English and Chinese.
    @Test func oneAtOnAJapaneseSelectionPutsTranslateFirst() async {
        await withInterfaceLanguage("en") {
            for text in ["東京駅で待ってます", "日本語の勉強", "ありがとう"] {
                let field = Field(selected: text)
                field.host.type("@")
                #expect(field.kinds.first == "translate", "\(text): \(field.kinds) \(field.panelText)")
                let sent = field.returnSends()
                #expect(Suite.formatTags(sent?.instructions ?? "") == ["EN", "ZH"], "\(text): \(String(describing: sent?.instructions))")
            }
        }
    }

    /// One @ with Japanese typed as its text, or its start typed and the rest pasted (a paste right after the magic key
    /// alone is the app's, as before): Translate first.
    @Test func oneAtWithJapaneseTypedOrPastedPutsTranslateFirst() async {
        await withInterfaceLanguage("en") {
            for text in ["東京駅で待ってます", "日本語の勉強"] {
                let typed = Field(english: true)
                typed.host.type("@" + text)
                #expect(typed.host.composer.draft == "@" + text, "typed \(text): \(typed.host.composer.draft)")
                #expect(typed.kinds.first == "translate", "typed \(text): \(typed.kinds) \(typed.panelText)")

                let pasted = Field(english: true)
                pasted.host.type("@" + String(text.prefix(2)))
                pasted.paste(String(text.dropFirst(2)))
                #expect(pasted.host.composer.draft == "@" + text, "pasted \(text): \(pasted.host.composer.draft)")
                #expect(pasted.kinds.first == "translate", "pasted \(text): \(pasted.kinds) \(pasted.panelText)")
            }
        }
    }

    /// Kanji alone selected: Chinese as before, Improve first for a Chinese main language.
    @Test func oneAtOnAKanjiOnlySelectionImprovesFirst() async {
        await withInterfaceLanguage("en") {
            let field = Field(selected: "東京大学")
            field.host.type("@")
            #expect(field.kinds.first == "improve", "\(field.kinds) \(field.panelText)")
        }
    }
}
