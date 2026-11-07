import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What the panel model says only about how a shell draws it (`PanelModel.hints`, `note`, `candidatesHint`, `pending`;
/// a row's `action`, `tag`, `commentDescribes`, `lead`): the footer as a few keys, what ⏎ does on one @'s rows, a
/// result's style as a tag, the places of results on their way. The rest of the model (the footer's text, the comments)
/// stays as it was: these are beside it.
@Suite(MacTerms())
struct PanelLookTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let zh = PanelPresenter(config: .default, language: "zh-Hans")
    let en = PanelPresenter(config: .default, language: "en")

    func composer(key: ActionKey = .space) -> Composer {
        let c = Composer(engine: FakeEngine(), voiceEnabled: false, actionKey: key)
        c.commands = Command.builtins
        return c
    }

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(k(String(ch))) }
    }

    /// "@improve 你好" sent: request 1 in flight.
    func translating() -> Composer {
        let c = composer()
        _ = c.handleKeyDown(at)
        type("i", c)
        _ = c.handleKeyDown(tab)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(spaceKey)
        return c
    }

    func hints(_ pairs: [(String, String)]) -> [PanelModel.Hint] { pairs.map { PanelModel.Hint($0.0, $0.1) } }

    // MARK: - The footer as keys

    @Test func aFooterIsReadAsTheKeysItNames() {
        func read(_ footer: String) -> (note: String?, hints: [PanelModel.Hint]) { PanelModel(footer: footer).footerHints }
        // A key, its words; a part without one as words.
        #expect(read("空格 选词 · 开头打 @ 用命令").hints == hints([("空格", "选词"), ("", "开头打 @ 用命令")]))
        // Of several keys for one thing, the action key's (else the first); ↑↓ and Esc left out where another is said.
        #expect(read("Tab 或 ⏎ 插入 · ↑↓ 选择 · → 或 Esc 隐藏").hints == hints([("⏎", "插入"), ("→", "隐藏")]))
        #expect(read("⏎ / Tab / 空格 选择 · Esc 取消").hints == hints([("⏎", "选择")]))
        #expect(read("⌃V paste · ⌫ delete · Esc clear").hints == hints([("⌃V", "paste"), ("⌫", "delete")]))
        #expect(read("Ctrl+V paste · Backspace delete · Esc clear").hints == hints([("Ctrl+V", "paste"), ("Backspace", "delete")]))
        // Esc alone is said; something going on is the note.
        let running = read("运行中… · Esc 停止")
        #expect(running.note == "运行中…" && running.hints == hints([("Esc", "停止")]))
        // Digits and ↑↓ never, and three at most.
        #expect(read("Tab accept · Esc dismiss").hints == hints([("Tab", "accept")]))
        #expect(read("⏎ a · ⇧↓ b · 1–5 c · 0 d · ⌘C e · ⌘V f · ⌫ g").hints == hints([("⏎", "a"), ("⌘C", "e"), ("⌘V", "f")]))
        // Only words: none (the footer is drawn as it is).
        let words = read("只存在这台 Mac 上；在设置 →「通用」→「剪贴板历史」里可以关掉")
        #expect(words.note == nil && words.hints.isEmpty)
        // The presenter's own, when it gave them.
        let chosen = PanelModel(footer: "⏎ a · ⌘C b", hints: hints([("⏎", "上屏")]), note: "x")
        #expect(chosen.footerHints.note == "x" && chosen.footerHints.hints == hints([("⏎", "上屏")]))
    }

    // MARK: - Results

    @Test func resultsSayTheirTwoKeysTheSentenceAsTypedAndEachStyle() throws {
        let c = translating()
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi there."), CandidateLine("Hello.")],
                                       rewrites: [Rewrite(style: "简洁", line: CandidateLine("嗨！")),
                                                  Rewrite(style: "黑话", line: CandidateLine("拉通一下"))]),
                      isFinal: true, id: 1)
        try #require(c.phase == .choosing)
        let model = zh.model(for: c)
        #expect(model.hints == hints([("⏎", "上屏"), ("⌘C", "复制")]))
        #expect(en.model(for: c).hints == hints([("⏎", "insert"), ("⌘C", "copy")]))
        // On Windows, with its keys.
        c.modifierRoles = .windows
        #expect(PanelPresenter(config: .default, language: "en", terms: .windows).model(for: c).hints
                == hints([("Enter", "insert"), ("Ctrl+C", "copy")]))
        c.modifierRoles = .mac
        // The footer's text says it all, as before.
        #expect(model.footer.contains("数字选择") && model.footer.contains("0 原文"))
        // Row 0: what picking it does, said beside it.
        #expect(model.rows.first?.kind == .original && model.rows.first?.action == "保留原文" && model.rows.first?.comment == "原文")
        #expect(en.model(for: c).rows.first?.action == "Keep original")
        // Each style a tag, tinted by its own; the comment as it was.
        let concise = try #require(model.rows.first { $0.text == "嗨！" })
        #expect(concise.tag == PanelModel.Row.Tag(text: "简洁", tint: "CONCISE") && concise.comment == "简洁")
        let jargon = try #require(model.rows.first { $0.text == "拉通一下" })
        #expect(jargon.tag?.text == "黑话" && jargon.comment.hasPrefix("黑话"))
        // The versions have none; nothing is pending.
        #expect(model.rows.filter { $0.tag == nil && $0.kind == .translation }.map(\.text) == ["Hi there.", "Hello."])
        #expect(model.pending == 0 && model.note == nil)
    }

    @Test func whileTheAIWritesItsRowsHaveTheirPlacesAndTheFooterSaysWho() throws {
        let c = translating()
        guard case .translating = c.phase else {
            Issue.record("not translating: \(c.phase)")
            return
        }
        let model = zh.model(for: c)
        #expect(model.pending == 3)
        #expect(model.note?.hasSuffix(" 在写…") == true && model.hints == hints([("Esc", "取消")]))
        #expect(en.model(for: c).note?.hasSuffix(" is writing…") == true && en.model(for: c).hints == hints([("Esc", "cancel")]))
        // The model by the name the settings give it.
        var config = Config.default
        config.provider = .bedrock
        config.modelId = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
        #expect(PanelPresenter(config: config, language: "en").model(for: c).note == "Claude Haiku 4.5 is writing…")
        config.modelId = "something-of-my-own"
        #expect(PanelPresenter(config: config, language: "en").model(for: c).note == "AI is writing…")
        // The status and the footer's text as before.
        #expect(model.status == .loading("AI 翻译中…") && model.footer == "生成中… · 0 原文 · Esc 返回")
        // A version in: a place fewer.
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi", isComplete: false)]), isFinal: false, id: 1)
        #expect(zh.model(for: c).pending == 2 && zh.model(for: c).rows.count == 2)
    }

    // MARK: - One @

    @Test func oneAtsRowsSayWhatReturnDoesAndTheFooterHowToGiveTheKeysBack() throws {
        let c = composer(key: .enter)
        _ = c.handleKeyDown(at)
        type("nihao", c)
        try #require(c.engineState.isComposing)
        let composing = zh.model(for: c)
        // Composing, → is the engine's: Esc gives the keys back; Space picks a word, said at the candidates' end.
        #expect(composing.hints == hints([("Esc", "交还给 App")]))
        #expect(composing.candidatesHint == PanelModel.Hint("空格", "选词"))
        #expect(en.model(for: c).candidatesHint == PanelModel.Hint("Space", "picks a word"))
        #expect(composing.rows.allSatisfy { $0.action != nil }, "\(composing.rows.map(\.text))")
        _ = c.handleKeyDown(spaceKey)
        try #require(!c.engineState.isComposing)
        let picked = en.model(for: c)
        #expect(picked.hints == hints([("→", "back to the app")]) && picked.candidatesHint == nil)
        #expect(picked.rows.contains { $0.action == "do it" }, "\(picked.rows.map(\.text))")
    }

    @Test func aBuiltInCommandsSummaryIsMarkedAsOnlyDescribingIt() throws {
        let c = composer()
        _ = c.handleKeyDown(at)
        let model = en.model(for: c)
        let improve = try #require(model.rows.first { $0.text == "improve" })
        #expect(improve.commentDescribes && improve.comment == "Polish in the same language, plus rewrites")
        #expect(improve.action == "choose")
        #expect(model.hints == hints([("→", "back to the app")]))
    }

    @Test func aSumsResultHasItsSumBeforeIt() throws {
        let c = composer(key: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("3*7", c)
        try #require(c.oneAtRows.first == .value("21"))
        let row = try #require(en.model(for: c).rows.first)
        #expect(row.text == "= 21" && row.comment == "insert")
        #expect(row.lead == "3*7" && row.action == "insert")
    }
}
