import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The candidate panel as the core makes it (`PanelPresenter`, `PanelModel`), in Simplified Chinese and English: what
/// every shell draws. In the language each presenter is given, whatever the process's is (`UIText.language`).
struct PanelPresenterTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    func composer(key: ActionKey = .space) -> Composer {
        let c = Composer(engine: FakeEngine(), voiceEnabled: false, actionKey: key)
        c.commands = Command.builtins
        return c
    }

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(k(String(ch))) }
    }

    /// "@improve " picked from the palette ("@i", Tab).
    func improveDraft(_ c: Composer) {
        _ = c.handleKeyDown(at)
        type("i", c)
        _ = c.handleKeyDown(tab)
    }

    let zh = PanelPresenter(config: .default, language: "zh-Hans")
    let en = PanelPresenter(config: .default, language: "en")

    // MARK: - Typing

    @Test func pinyinCandidatesAreRowsWithWhatSpaceDoes() {
        let c = composer()
        type("nihao", c)
        let (zh, en) = (zh.model(for: c), en.model(for: c))
        #expect(zh.rows.map(\.text) == ["你好", "拟好"])
        #expect(zh.rows.allSatisfy { $0.kind == .candidate && $0.pickable && $0.icon == nil })
        #expect(zh.highlighted == 0)
        #expect(zh.footer == "空格 选词 · 开头打 @ 用命令")
        #expect(en.footer == "Space picks · type @ first for commands")
        #expect(zh.status == .none && zh.input == nil && zh.header == nil && zh.chip == nil && !zh.transcript)
    }

    @Test func nothingTypedIsAnEmptyPanel() {
        #expect(zh.model(for: composer()) == PanelModel())
    }

    @Test func theCommandListHasIconsAndSummaries() throws {
        let c = composer()
        _ = c.handleKeyDown(at)
        let model = en.model(for: c)
        try #require(!model.rows.isEmpty)
        #expect(model.rows.count <= Composer.paletteRows)
        #expect(model.rows.allSatisfy { $0.text.hasPrefix("@") && $0.icon != nil })
        #expect(model.rows.map(\.label) == (1...model.rows.count).map(String.init))
        let improve = try #require(model.rows.first { $0.text == "@improve" })
        #expect(improve.icon == IconToken(symbol: "wand.and.stars", color: .purple))
        #expect(improve.comment == "Polish in the same language, plus rewrites")
        #expect(zh.model(for: c).rows.first { $0.text == "@improve" }?.comment == "润色，再给几种改写（不翻译）")
        #expect(model.footer == "⏎ / Tab / Space choose · Esc cancel")
        // More commands than rows: where the list is.
        try #require(c.paletteMatches.count > Composer.paletteRows)
        #expect(model.detail == "1–\(model.rows.count) / \(c.paletteMatches.count)")
    }

    @Test func aScriptStatusLineIsBesideItsName() {
        let script = ScriptCommand(id: "pomodoro", file: URL(fileURLWithPath: "/tmp/p.sh"), name: "pomodoro", title: "Pomodoro")
        let presenter = PanelPresenter(config: .default, language: "en", scriptStatus: { $0.id == "pomodoro" ? "12:04 left" : nil })
        let c = composer()
        c.commands = [Command(name: "pomodoro", kind: .run, script: script)]
        _ = c.handleKeyDown(at)
        #expect(presenter.model(for: c).rows.first?.comment == "Pomodoro · 12:04 left")
    }

    @Test func aDraftSaysWhatToDoNext() {
        let c = composer()
        improveDraft(c)
        let zh = zh.model(for: c)
        #expect(zh.rows.isEmpty)
        #expect(zh.status == .hint("写点内容，或按 ⌃V 粘贴"))
        #expect(zh.footer == "⌃V 粘贴 · ⌫ 删字 · Esc 清除")
        let en = en.model(for: c)
        #expect(en.status == .hint("Write something, or ⌃V to paste"))
        #expect(en.footer == "⌃V paste · ⌫ delete · Esc clear")
    }

    /// The panel is in the presenter's language, not the process's: two sessions can show two.
    @Test func thePresentersLanguageWhateverTheProcesssIs() {
        let c = composer()
        c.setInputMode(.english)
        improveDraft(c)
        type("hello", c)
        let (english, chinese) = withInterfaceLanguage("zh") { (en.model(for: c), zh.model(for: c)) }
        #expect(english == withInterfaceLanguage("en") { en.model(for: c) })
        #expect(chinese == withInterfaceLanguage("en") { zh.model(for: c) })
        #expect(english.footer == "⌃V paste · ⌫ delete · Esc clear" && chinese.footer == "⌃V 粘贴 · ⌫ 删字 · Esc 清除")
        #expect(english.status == .hint("Space twice → polish / rewrite"))
    }

    /// On Windows the keys have Windows' names (`PlatformTerms`); the Mac's text stays as it was.
    @Test func theKeysAsThePlatformNamesThem() throws {
        let c = composer()
        c.setInputMode(.english)
        improveDraft(c)
        let windows = PanelPresenter(config: .default, language: "en", terms: .windows)
        #expect(windows.model(for: c).footer == "Ctrl+V paste · ⌫ delete · Esc clear")
        #expect(windows.model(for: c).status == .hint("Write something, or Ctrl+V to paste"))
        #expect(PanelPresenter(config: .default, language: "zh-Hans", terms: .windows).model(for: c).footer == "Ctrl+V 粘贴 · ⌫ 删字 · Esc 清除")
        #expect(PanelPresenter(config: .default, language: "en", terms: .mac).model(for: c).footer == "⌃V paste · ⌫ delete · Esc clear")
        // Results: copied with Ctrl+C.
        let sent = translating()
        _ = sent.receive(result, isFinal: true, id: 1)
        try #require(sent.phase == .choosing)
        #expect(windows.model(for: sent).footer == "Type, ⇧⏎ refine · Space / ⏎ insert · digits pick · 0 original · Ctrl+C copy · Esc back")
        #expect(en.model(for: sent).footer == "Type, ⇧⏎ refine · Space / ⏎ insert · digits pick · 0 original · ⌘C copy · Esc back")
        // The action key a tap of Ctrl, in the palette's footer and a draft's hint.
        let tap = composer(key: .optionTap)
        tap.setInputMode(.english)
        improveDraft(tap)
        type("hello", tap)
        #expect(windows.model(for: tap).status == .hint("Tap Ctrl → polish / rewrite"))
        #expect(en.model(for: tap).status == .hint("Tap ⌥ → polish / rewrite"))
    }

    @Test func appsAndThisDeviceAsThePlatformCallsThem() {
        let word = SearchResult(name: "Word", path: #"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Word.lnk"#)
        #expect(SessionText.openRow(word, language: "en", terms: .windows).comment == "app")
        #expect(SessionText.openRow(word, language: "en", terms: .mac).comment != "app")
        let c = composer()
        c.attachment = .screenshot(.ready(ScreenText(transcript: ChatTranscript(messages: [.init(speaker: .them, text: "hi"),
                                                                                           .init(speaker: .me, text: "hey")],
                                                                                labelled: true))))
        #expect(SessionText.attachmentHeader(c, language: "en", terms: .mac)
                == "Screenshot · 2 lines (read on this Mac)\nThe image stays on this Mac; only its text is sent")
        #expect(SessionText.attachmentHeader(c, language: "en", terms: .windows)
                == "Screenshot · 2 lines (read on this PC)\nThe image stays on this PC; only its text is sent")
        #expect(SessionText.attachmentHeader(c, language: "zh-Hans", terms: .windows) == "截图 · 2 行（本机识别）\n图片不会离开这台电脑，只发送认出的文字")
    }

    // MARK: - Results

    /// "@improve 你好" sent (Space picks 你好, Space again sends it): request 1 in flight.
    func translating() -> Composer {
        let c = composer()
        improveDraft(c)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(spaceKey)
        return c
    }

    let result = ConversionResult(
        versions: [CandidateLine("Hi there."), CandidateLine("Hello.")],
        rewrites: [Rewrite(style: "简洁", line: CandidateLine("嗨！"))])

    @Test func whileTheAIWritesThePanelSaysSo() throws {
        let c = translating()
        guard case .translating = c.phase else {
            Issue.record("not translating: \(c.phase)")
            return
        }
        // Only the sentence as typed so far: the line under it says the AI is at work.
        try #require(c.choices.count == 1)
        let model = zh.model(for: c)
        #expect(model.footer == "生成中… · 0 原文 · Esc 返回")
        #expect(model.status == .loading("AI 翻译中…"))
        #expect(en.model(for: c).status == .loading("Translating…"))
    }

    @Test func resultsAreRowsByKindWithTheTimeTheyTook() throws {
        let c = translating()
        _ = c.receive(result, isFinal: true, id: 1)
        try #require(c.phase == .choosing)
        let timed = PanelPresenter(config: .default, language: "zh-Hans", elapsed: 1.24)
        let model = timed.model(for: c)
        try #require(model.rows.count == c.choices.count)
        #expect(model.rows.first?.kind == .original && model.rows.first?.comment == "原文")
        #expect(model.rows.dropFirst().allSatisfy { $0.kind == .translation })
        #expect(model.rows.contains { $0.text == "嗨！" && $0.comment == "简洁" })
        #expect(model.highlighted == c.highlighted)
        #expect(model.detail == "1.2s")
        // From the cache it says so; a notice is over either.
        #expect(PanelPresenter(config: .default, language: "en", elapsed: 1.24, fromCache: true).model(for: c).detail == "cached")
        #expect(PanelPresenter(config: .default, language: "en", notice: "已复制", elapsed: 1.24).model(for: c).detail == "已复制")
    }

    @Test func valuesHiddenFromTheAIAreSaidBesideTheTime() throws {
        let c = translating()
        _ = c.receive(result, isFinal: true, id: 1)
        try #require(c.phase == .choosing)
        let model = PanelPresenter(config: .default, language: "en", elapsed: 2, hidden: 2).model(for: c)
        #expect(model.detail == "2 items hidden from the AI · 2.0s")
        #expect(PanelRedaction.hiddenLine(1, language: "zh-Hans") == "已对 AI 隐藏 1 项")
        // Before any result there's nothing to say.
        var idle = PanelModel(detail: "x")
        PanelRedaction.annotate(&idle, choices: [], hidden: 2, phase: .idle, language: "en")
        #expect(idle.detail == "x")
    }

    /// A result whose placeholder the model changed past telling is marked, beside what its row says; the sentence as
    /// typed, a result with the value put back and a row still coming in aren't.
    @Test func aRowWhosePlaceholderChangedIsMarked() {
        let choices = [
            Composer.Choice(label: "0", kind: .original, text: "mail ada@example.com", isComplete: true),
            Composer.Choice(label: "1", kind: .version, text: "write to EMAIL_1 today", isComplete: true),
            Composer.Choice(label: "2", kind: .version, text: "write to ada@example.com", isComplete: true),
            Composer.Choice(label: "3", kind: .version, text: "EMAIL_1 again", isComplete: false),
            Composer.Choice(label: "4", kind: .translation("ja"), text: "[EMAIL_1] に書く", isComplete: true),
        ]
        var model = PanelModel(rows: choices.map { PanelModel.Row(label: $0.label, text: $0.text, kind: .translation) },
                               detail: "1.0s")
        model.rows[4].comment = "日语"
        PanelRedaction.annotate(&model, choices: choices, hidden: 1, phase: .choosing, language: "en")
        #expect(model.rows.map(\.comment) == ["", "⚠ placeholder changed", "", "", "日语 · ⚠ placeholder changed"])
        #expect(model.detail == "1 item hidden from the AI · 1.0s")
        #expect(PanelRedaction.changed(language: "zh-Hans") == "⚠ 占位符被改动")
    }

    // MARK: - Notices and the chip

    @Test func aNoticeOnItsOwnIsAHint() {
        #expect(PanelModel.notice("已复制") == PanelModel(status: .hint("已复制")))
    }

    @Test func theChipListsTheLanguagesWithTheTargetChecked() {
        let chip = TranslateMode.Chip(source: .chinese, target: .english, choices: [.english, OutputLanguage("ja")])
        let zh = PanelPresenter.chipModel(chip, notice: "英", language: "zh-Hans")
        #expect(zh.rows.map(\.label) == ["✓", ""])
        #expect(zh.rows.map(\.text) == ["英文", "日语"])
        #expect(zh.status == .hint("英"))
        #expect(zh.chip == PanelModel.Chip(source: "中", target: "英"))
        #expect(PanelPresenter.chipModel(chip, notice: nil, language: "zh-Hant").chip == PanelModel.Chip(source: "中", target: "英"))
        let en = PanelPresenter.chipModel(TranslateMode.Chip(source: .chinese, target: .english), notice: nil, language: "en")
        #expect(en.chip == PanelModel.Chip(source: "ZH", target: "EN") && en.rows.isEmpty && en.status == .none)
    }
}


/// The icons as data (`IconToken`): no interface language.
struct IconTokenTests {
    @Test func colorsByName() {
        #expect(IconToken.Color.named("#34C759") == .rgb(red: 0x34, green: 0xC7, blue: 0x59))
        #expect(IconToken.Color.named(" systemBlue ") == .blue && IconToken.Color.named("Grey") == .gray)
        #expect(IconToken.Color.named("black") == .grayscale(0.15))
        #expect(IconToken.Color.named("") == nil && IconToken.Color.named("chartreuse") == nil && IconToken.Color.named(nil) == nil)
        #expect(IconToken.Color.named("#12345") == nil)
    }

    @Test func eachBuiltInCommandHasItsOwn() {
        let builtins = [Command.improve, .translate, .question, .reply, .agent, .open, .read, .note, .reminder, .py, .js,
                        .webSearch, .tasks, .settings, .imessage, .reportIssue]
        let icons = builtins.map(IconToken.command)
        #expect(!icons.contains(IconToken(symbol: "command", color: .gray)))
        #expect(IconToken.command(.reminder) == IconToken(symbol: "bell.fill", color: .red))
        #expect(IconToken.progress(.done) == IconToken(symbol: "checkmark", color: .green))
    }

    @Test func aScriptNamesItsOwnWithAFallback() {
        var script = ScriptCommand(file: URL(fileURLWithPath: "/tmp/s.sh"), name: "s")
        let plain = IconToken.script(script)
        #expect(plain.color == .teal && plain.fallbackSymbol == nil && plain.emoji == nil && plain.image == nil)
        script.icon = .symbol("airplane")
        #expect(IconToken.script(script) == IconToken(symbol: "airplane", color: .teal, fallbackSymbol: plain.symbol))
        script.icon = .emoji("🍅")
        #expect(IconToken.script(script) == IconToken(symbol: plain.symbol, color: .teal, emoji: "🍅"))
        script.icon = .image(URL(fileURLWithPath: "/tmp/icon.png"))
        #expect(IconToken.script(script).image == "/tmp/icon.png")
    }
}
