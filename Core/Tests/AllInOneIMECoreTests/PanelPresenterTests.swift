import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The candidate panel as the core makes it (`PanelPresenter`, `PanelModel`), in Simplified Chinese and English: what
/// every shell draws. In the interface language each test sets (`withInterfaceLanguage`).
@Suite(.serialized)
struct PanelPresenterTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    func inLanguage<T>(_ choice: String, _ body: () throws -> T) rethrows -> T { try withInterfaceLanguage(choice, body) }

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

    let presenter = PanelPresenter(config: .default)

    // MARK: - Typing

    @Test func pinyinCandidatesAreRowsWithWhatSpaceDoes() {
        let c = composer()
        type("nihao", c)
        let (zh, en) = (inLanguage("zh") { presenter.model(for: c) }, inLanguage("en") { presenter.model(for: c) })
        #expect(zh.rows.map(\.text) == ["你好", "拟好"])
        #expect(zh.rows.allSatisfy { $0.kind == .candidate && $0.pickable && $0.icon == nil })
        #expect(zh.highlighted == 0)
        #expect(zh.footer == "空格 选词 · 开头打 @ 用命令")
        #expect(en.footer == "Space picks · type @ first for commands")
        #expect(zh.status == .none && zh.input == nil && zh.header == nil && zh.chip == nil && !zh.transcript)
    }

    @Test func nothingTypedIsAnEmptyPanel() {
        #expect(presenter.model(for: composer()) == PanelModel())
    }

    @Test func theCommandListHasIconsAndSummaries() throws {
        let c = composer()
        _ = c.handleKeyDown(at)
        let model = inLanguage("en") { presenter.model(for: c) }
        try #require(!model.rows.isEmpty)
        #expect(model.rows.count <= Composer.paletteRows)
        #expect(model.rows.allSatisfy { $0.text.hasPrefix("@") && $0.icon != nil })
        #expect(model.rows.map(\.label) == (1...model.rows.count).map(String.init))
        let improve = try #require(model.rows.first { $0.text == "@improve" })
        #expect(improve.icon == IconToken(symbol: "wand.and.stars", color: .purple))
        #expect(improve.comment == UIText.summary(Command.improve))
        #expect(model.footer == "⏎ / Tab / Space choose · Esc cancel")
        // More commands than rows: where the list is.
        if c.paletteMatches.count > Composer.paletteRows {
            #expect(model.detail == "1–\(model.rows.count) / \(c.paletteMatches.count)")
        }
    }

    @Test func aScriptStatusLineIsBesideItsName() {
        let script = ScriptCommand(id: "pomodoro", file: URL(fileURLWithPath: "/tmp/p.sh"), name: "pomodoro", title: "Pomodoro")
        let presenter = PanelPresenter(config: .default, scriptStatus: { $0.id == "pomodoro" ? "12:04 left" : nil })
        let c = composer()
        c.commands = [Command(name: "pomodoro", kind: .run, script: script)]
        _ = c.handleKeyDown(at)
        let model = inLanguage("en") { presenter.model(for: c) }
        #expect(model.rows.first?.comment == "Pomodoro · 12:04 left")
    }

    @Test func aDraftSaysWhatToDoNext() {
        let c = composer()
        improveDraft(c)
        let zh = inLanguage("zh") { presenter.model(for: c) }
        #expect(zh.rows.isEmpty)
        #expect(zh.status == .hint("写点内容，或按 ⌃V 粘贴"))
        #expect(zh.footer == "⌃V 粘贴 · ⌫ 删字 · Esc 清除")
        let en = inLanguage("en") { presenter.model(for: c) }
        #expect(en.status == .hint("Write something, or ⌃V to paste"))
        #expect(en.footer == "⌃V paste · ⌫ delete · Esc clear")
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

    @Test func whileTheAIWritesThePanelSaysSo() {
        let c = translating()
        guard case .translating = c.phase else {
            Issue.record("not translating: \(c.phase)")
            return
        }
        let model = inLanguage("zh") { presenter.model(for: c) }
        #expect(model.footer == "生成中… · 0 原文 · Esc 返回")
        if c.choices.count <= 1 {
            guard case .loading = model.status else {
                Issue.record("no loading line: \(model.status)")
                return
            }
        }
    }

    @Test func resultsAreRowsByKindWithTheTimeTheyTook() throws {
        let c = translating()
        _ = c.receive(result, isFinal: true, id: 1)
        try #require(c.phase == .choosing)
        let timed = PanelPresenter(config: .default, elapsed: 1.24)
        let model = inLanguage("zh") { timed.model(for: c) }
        try #require(model.rows.count == c.choices.count)
        #expect(model.rows.first?.kind == .original && model.rows.first?.comment == "原文")
        #expect(model.rows.dropFirst().allSatisfy { $0.kind == .translation })
        #expect(model.rows.contains { $0.text == "嗨！" && $0.comment == "简洁" })
        #expect(model.highlighted == c.highlighted)
        #expect(model.detail == "1.2s")
        // From the cache it says so; a notice is over either.
        #expect(inLanguage("en") { PanelPresenter(config: .default, elapsed: 1.24, fromCache: true).model(for: c) }.detail == "cached")
        #expect(PanelPresenter(config: .default, notice: "已复制", elapsed: 1.24).model(for: c).detail == "已复制")
    }

    @Test func valuesHiddenFromTheAIAreSaidBesideTheTime() throws {
        let c = translating()
        _ = c.receive(result, isFinal: true, id: 1)
        try #require(c.phase == .choosing)
        let model = inLanguage("en") { PanelPresenter(config: .default, elapsed: 2, hidden: 2).model(for: c) }
        #expect(model.detail == "2 items hidden from the AI · 2.0s")
        #expect(inLanguage("zh") { PanelRedaction.hiddenLine(1) } == "已对 AI 隐藏 1 项")
        // Before any result there's nothing to say.
        var idle = PanelModel(detail: "x")
        PanelRedaction.annotate(&idle, choices: [], hidden: 2, phase: .idle)
        #expect(idle.detail == "x")
    }

    // MARK: - Notices and the chip

    @Test func aNoticeOnItsOwnIsAHint() {
        #expect(PanelModel.notice("已复制") == PanelModel(status: .hint("已复制")))
    }

    @Test func theChipListsTheLanguagesWithTheTargetChecked() {
        let chip = TranslateMode.Chip(source: .chinese, target: .english, choices: [.english, OutputLanguage("ja")])
        let zh = inLanguage("zh") { PanelPresenter.chipModel(chip, notice: "英") }
        #expect(zh.rows.map(\.label) == ["✓", ""])
        #expect(zh.rows.map(\.text) == inLanguage("zh") { [UIText.name(OutputLanguage.english), UIText.name(OutputLanguage("ja"))] })
        #expect(zh.status == .hint("英"))
        #expect(zh.chip == PanelModel.Chip(source: chip.sourceText, target: chip.targetText))
        let en = inLanguage("en") { PanelPresenter.chipModel(TranslateMode.Chip(source: .chinese, target: .english), notice: nil) }
        #expect(en.chip == PanelModel.Chip(source: chip.sourceTag, target: chip.targetTag) && en.rows.isEmpty && en.status == .none)
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
