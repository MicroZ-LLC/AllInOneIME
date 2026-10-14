import Foundation
import Testing
@testable import AllInOneIMECore

struct WritingModeTests {
    func config(_ outputs: [OutputLanguage], styles: [String] = ["润色", "简洁"]) -> Config {
        var config = Config.default
        config.setOrder(outputs)
        config.rewriteStyles = styles
        return config
    }

    @Test func theCommandsAndBothTogether() {
        #expect(WritingMode.parse(.improve, "你好") == (.improve, "你好"))
        #expect(WritingMode.parse(nil, "你好") == (.improve, "你好"))
        #expect(WritingMode.parse(.translate, "你好") == (.translate, "你好"))
        // Written together, either way round: one request with both.
        #expect(WritingMode.parse(.translate, "@improve 牛的啊") == (.both, "牛的啊"))
        #expect(WritingMode.parse(.improve, "@translate 牛的啊") == (.both, "牛的啊"))
        #expect(WritingMode.parse(.improve, "牛的啊 @translate") == (.both, "牛的啊"))
        // The setting: @improve alone does both; @translate stays as it is.
        #expect(WritingMode.parse(.improve, "你好", improveTranslates: true) == (.both, "你好"))
        #expect(WritingMode.parse(.translate, "你好", improveTranslates: true) == (.translate, "你好"))
        #expect(try! JSONDecoder().decode(Config.self, from: Data("{}".utf8)).improveTranslates == false)
        // An address or a word that only contains the name isn't the command.
        #expect(WritingMode.parse(.improve, "mail a@translate.com") == (.improve, "mail a@translate.com"))
    }

    @Test func whatEachModeAsksFor() {
        let three = config([OutputLanguage("ja"), .english, .chinese])
        // @improve: polished in the sentence's own language, plus the styles; nothing translated.
        let improve = WritingPlan.make(.improve, text: "牛的啊", config: three)
        #expect(improve.versions == .chinese && improve.translations.isEmpty && improve.styles.map(\.name) == ["润色", "简洁"])
        // @translate: a line in each added language but the sentence's own, in the user's order; no styles.
        let translate = WritingPlan.make(.translate, text: "牛的啊", config: three)
        #expect(translate.versions == nil && translate.translations == [OutputLanguage("ja"), .english] && translate.styles.isEmpty)
        // One language to translate into: three versions in it.
        let one = WritingPlan.make(.translate, text: "牛的啊", config: config([.english, .chinese]))
        #expect(one.versions == .english && one.translations.isEmpty)
        // Both: the translations and the styles.
        let both = WritingPlan.make(.both, text: "牛的啊", config: three)
        #expect(both.translations == [OutputLanguage("ja"), .english] && both.styles.count == 2)
        // Nothing else to translate into: polished instead.
        let only = WritingPlan.make(.translate, text: "牛的啊", config: config([.chinese]))
        #expect(only.versions == .chinese && only.translations.isEmpty)
    }

    @Test func oneRequestForSeveralLanguages() {
        let three = config([OutputLanguage("ja"), .english, .chinese])
        let request = Prompt.request(for: "牛的啊", mode: .both, config: three)
        let system = request.system.first?.text ?? ""
        #expect(system.contains("\nJA: <the sentence in Japanese") && system.contains("\nEN: <the sentence in English")
                && !system.contains("\nZH: ") && system.contains("\nSTYLE_POLISH: ") && system.contains("\nSTYLE_CONCISE: "))
        // Examples need Japanese, which they aren't written in: the sentence goes alone.
        #expect(request.messages.count == 1)
        // English and Chinese only: the examples are answered the same way (a line per language).
        let two = Prompt.request(for: "牛的啊", mode: .translate, config: config([.english, OutputLanguage("zh-Hant"), .chinese]))
        #expect(two.messages.count == 1)
        let polish = Prompt.request(for: "牛的啊", mode: .improve, config: three)
        #expect((polish.system.first?.text ?? "").contains("\nZH: <how a native Simplified Chinese speaker") && polish.messages.count > 1)

        let answer = "EN: That's awesome\nJA: すごいね\nSTYLE_POLISH: 太厉害了\nZH: 牛\nSTYLE_CONCISE: 牛"
        let parsed = CandidateParser.parse(answer, isFinal: true, output: nil, translations: [OutputLanguage("ja"), .english])
        // In the user's order, whatever order the model answered in; a line in another language is ignored.
        #expect(parsed.translations.map(\.language.code) == ["ja", "en"] && parsed.translations.map(\.line.text) == ["すごいね", "That's awesome"])
        #expect(parsed.versions.isEmpty && parsed.rewrites.map(\.style) == ["润色", "简洁"])
    }

    @Test func indianLanguages() {
        let codes = ["hi", "bn", "te", "mr", "ta", "gu", "kn", "ml", "pa", "ur"]
        let languages = codes.map(OutputLanguage.init)
        #expect(languages.allSatisfy(OutputLanguage.catalog.contains))
        #expect(languages.map { $0.name(chinese: true) }
                == ["印地语", "孟加拉语", "泰卢固语", "马拉地语", "泰米尔语", "古吉拉特语", "卡纳达语", "马拉雅拉姆语", "旁遮普语", "乌尔都语"])
        #expect(languages.map { $0.name(chinese: false) }
                == ["Hindi", "Bengali", "Telugu", "Marathi", "Tamil", "Gujarati", "Kannada", "Malayalam", "Punjabi", "Urdu"])
        #expect(OutputLanguage("hi").promptName == "Hindi (Devanagari script)" && OutputLanguage("pa").promptName == "Punjabi (Gurmukhi script)")
        // Every tag in the catalog is its own, and none is read as a rewrite style.
        let tags = OutputLanguage.catalog.map(\.tag)
        #expect(Set(tags).count == tags.count && tags.allSatisfy { RewriteStyle.forTag($0) == nil })
        let answer = codes.map { "\($0.uppercased()): line \($0)" }.joined(separator: "\n") + "\nSTYLE_CONCISE: short"
        let parsed = CandidateParser.parse(answer, isFinal: true, output: nil, translations: languages)
        #expect(parsed.translations.map(\.language) == languages && parsed.translations.map(\.line.text) == codes.map { "line \($0)" })
        // A new user's system language.
        #expect(OutputLanguage.preferred(from: ["en-IN", "hi-IN"])?.code == "hi")
        #expect(OutputLanguage.preferred(from: ["bn-BD"])?.code == "bn" && OutputLanguage.preferred(from: ["pa-Guru-IN"])?.code == "pa")
        #expect(OutputLanguage.preferred(from: ["ur_PK"])?.code == "ur" && OutputLanguage.preferred(from: ["ta-LK", "en"])?.code == "ta")
    }

    /// Hinglish typed in Latin letters reads as English, so Hindi is a target, not "already in that
    /// language": the lines ask for Devanagari.
    @Test func romanizedHindiIsTranslatedIntoDevanagari() {
        let hindi = config([.english, OutputLanguage("hi")])
        let plan = WritingPlan.make(.translate, text: "aap kaise ho", config: hindi)
        #expect(plan.input == .english && plan.versions == OutputLanguage("hi") && plan.translations.isEmpty)
        let system = Prompt.request(for: "aap kaise ho", mode: .translate, config: hindi).system.first?.text ?? ""
        #expect(system.contains("HI: <how a native Hindi (Devanagari script) speaker"))
        #expect(system.contains("Write HI lines in the language's own script, never romanized"))
        // Several targets: each line names its script.
        let several = Prompt.request(for: "aap kaise ho", mode: .translate,
                                     config: config([OutputLanguage("hi"), OutputLanguage("ta"), .chinese]))
        let text = several.system.first?.text ?? ""
        #expect(text.contains("\nHI: <the sentence in Hindi (Devanagari script)") && text.contains("\nTA: <the sentence in Tamil (Tamil script)")
                && text.contains("Write HI, TA lines"))
        // Without them the rule isn't there.
        let japanese = Prompt.request(for: "aap kaise ho", mode: .translate, config: config([OutputLanguage("ja")]))
        let japaneseText = japanese.system.first?.text ?? ""
        #expect(!japaneseText.isEmpty && !japaneseText.contains("own script"))
    }
}
