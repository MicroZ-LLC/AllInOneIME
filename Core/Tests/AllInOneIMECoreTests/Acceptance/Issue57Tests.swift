import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #57: with Characters set to Traditional (Hong Kong), what the user typed is taken for Simplified when its telling
/// characters are Hong Kong's forms that Simplified writes alike: s2hk (OpenCC's Hong Kong variants, HKVariants) gives
/// 温, 户, 税, 脱, 悦, 卧, 葱 where Taiwan writes 溫, 戶, 稅, 脫, 悅, 臥, 蔥. Made Traditional they change, made
/// Simplified they don't, so 今日温度好高 counted as Simplified: `@improve`, the rewrite styles and translation asked for
/// Simplified Chinese. The text is Hong Kong's for a Hong Kong user; Simplified text is still Simplified, and a
/// Simplified user's 温 is Simplified as before. Through `Config.writtenLanguage` (what every caller asks), the request
/// the model gets for `@improve` and a style, and through a field's session (`TCAWorld`, TraditionalChineseAcceptanceTests:
/// pinyin from a `FakeEngine` giving the Hong Kong candidate, the Claude API stubbed, `RAStubProtocol`): `@improve`,
/// `@translate` into Traditional Chinese, Translate as You Type into Simplified. The Rime side (the candidates the app's own
/// OpenCC data gives) is Tests/AllInOneIMERimeTests/Issue57RimeTests.swift.
@Suite(MemorySecrets())
struct Issue57Tests {
    /// Hong Kong sentences as s2hk writes them, whose telling characters are only (or mostly) the forms Hong Kong and
    /// Simplified write alike.
    static let hongKong = [
        "今日温度好高",  // the issue's: 温
        "我要交税",  // 税
        "脱咗件外套",  // 脱
        "户口",  // 户
        "我好喜悦",  // 悦
        "我嘅卧室",  // 卧
        "葱花",  // 葱
        "今日温度好高，記得脱咗件外套先",  // 温 and 脱, with 記 that only Traditional writes
    ]

    /// Simplified sentences, one with 温 in it.
    static let simplified = ["这个功能太难用了", "今天温度很高，记得多喝水"]

    @Test func hongKongFormsTypedAreHongKong() {
        let config = TCA.config(.hongkong)
        for text in Self.hongKong {
            #expect(config.writtenLanguage(of: text) == .traditionalHongKong, "\(text): \(config.writtenLanguage(of: text).code)")
        }
    }

    @Test func simplifiedIsStillSimplified() {
        let hongKong = TCA.config(.hongkong)
        for text in Self.simplified {
            #expect(hongKong.writtenLanguage(of: text) == .chinese, "\(text): \(hongKong.writtenLanguage(of: text).code)")
        }
        // A Simplified user's 温 is Simplified, as before.
        let simplified = TCA.config(.simplified)
        for text in Self.hongKong.dropLast() {
            #expect(simplified.writtenLanguage(of: text) == .chinese, "\(text): \(simplified.writtenLanguage(of: text).code)")
        }
    }

    /// `@improve` and a rewrite style on 今日温度好高 for a Hong Kong user: the prompt asks for Hong Kong's Traditional
    /// Chinese, never Simplified.
    @Test func improveAndStylesAskForHongKong() {
        var config = TCA.config(.hongkong, outputs: [.english])
        config.rewriteStyles = ["润色", "口语"]
        for mode in [WritingMode.improve, .both] {
            let system = Prompt.request(for: "今日温度好高", mode: mode, config: config).system.map(\.text).joined(separator: "\n")
            #expect(system.contains("Traditional Chinese (Hong Kong)"), "\(mode):\n\(system)")
            #expect(!system.contains("Simplified Chinese"), "\(mode):\n\(system)")
        }
    }

    /// `@translate` into English and Traditional Chinese: Hong Kong text is in Traditional Chinese already.
    @Test func translateSkipsTraditionalChinese() {
        let config = TCA.config(.hongkong, outputs: [.english, TCA.zhHant])
        let plan = WritingPlan.make(.translate, text: "今日温度好高", config: config)
        let targets = ([plan.versions].compactMap { $0 } + plan.translations).map(\.code)
        #expect(targets == ["en"], "\(targets)")
    }

    // MARK: - In a field

    /// The issue's trigger: Hong Kong's characters, 今日温度好高 typed (the Hong Kong candidate), `@improve`.
    @Test func improveInAFieldAsksForHongKong() async throws {
        let world = TCAWorld(.hongkong)
        world.config.rewriteStyles = ["润色", "口语"]
        RAStubProtocol.enqueue(world.host, .answer("今日温度好高"))
        try await withInterfaceLanguage("en") {
            let field = world.field()
            world.pick("i", in: field)
            #expect(field.composer.draft == "@improve ", "\(field.composer.draft)")
            world.pinyin("jinriwendouhaogao", as: "今日温度好高", in: field)
            #expect(field.composer.draft == "@improve 今日温度好高", "\(field.composer.draft)")
            field.press(FakeHost.enter)
            #expect(field.settle { !RAStubProtocol.bodies(world.host).isEmpty }, "nothing was sent")
            let sent = try #require(try world.sent().first)
            #expect(sent.last == "今日温度好高")
            #expect(sent.system.contains("Traditional Chinese (Hong Kong)"), "the prompt names Hong Kong's:\n\(sent.system)")
            #expect(!sent.system.contains("Simplified Chinese"), "never Simplified Chinese:\n\(sent.system)")
            for text in sent.examples.filter(TCA.han) {
                #expect(TCA.simplified(in: text).isEmpty, "an example in Simplified characters: \(text)")
            }
        }
    }

    /// `@translate` with Traditional Chinese the only output language: the text is in it already, nothing is sent.
    @Test func translateInAFieldSendsNothing() async throws {
        let world = TCAWorld(.hongkong, outputs: [TCA.zhHant])
        await withInterfaceLanguage("en") {
            let field = world.field()
            world.pick("translate", in: field)
            world.pinyin("jinriwendouhaogao", as: "今日温度好高", in: field)
            field.press(FakeHost.enter)
            if case .loading? = field.panel?.status { Issue.record("translating Hong Kong text into Traditional Chinese") }
            if case .translating = field.composer.phase { Issue.record("a request for the same language") }
            field.settle(timeout: 0.5) { false }
            #expect(RAStubProtocol.bodies(world.host).isEmpty, "nothing to translate into, nothing sent")
        }
    }

    /// Translate as You Type into Simplified Chinese: Hong Kong text typed is collected, and ⏎ translates it (as Taiwan's
    /// is), not put in as typed with its Traditional 記 because 温 and 脱 outnumber it.
    @Test func translateAsYouTypeIntoSimplifiedTranslatesIt() async throws {
        let typed = "今日温度好高，記得脱咗件外套先"
        let world = TCAWorld(.hongkong, outputs: [.chinese, .english])
        RAStubProtocol.enqueue(world.host, .answer("ZH: 今天温度很高，记得先把外套脱了"))
        await withInterfaceLanguage("en") {
            let field = world.field()
            _ = field.composer.setTranslateMode(TranslateMode.Session(target: .chinese))
            world.pinyin("jinriwendouhaogao", as: typed, in: field)
            #expect(field.document.isEmpty && field.composer.draft == typed, "collected: \(field.document) / \(field.composer.draft)")
            field.press(FakeHost.enter)
            #expect(field.document != typed, "put in as typed, not translated into Simplified Chinese")
            #expect(field.settle { !RAStubProtocol.bodies(world.host).isEmpty }, "translated")
        }
    }
}
