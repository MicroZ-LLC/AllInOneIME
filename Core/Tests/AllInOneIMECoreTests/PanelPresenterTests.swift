import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The candidate panel as the core makes it (`PanelPresenter`, `PanelModel`), in Simplified Chinese and English: what
/// every shell draws. In the language each presenter is given, whatever the process's is (`UIText.language`).
@Suite(MacTerms())
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
        #expect(zh.status == .none && zh.input == nil && zh.header.isEmpty && zh.chip == nil && !zh.transcript)
        // A click on a row picks what its number would.
        #expect(zh.rows.map(\.choice) == [0, 1])
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
        #expect(model.rows.allSatisfy { !$0.text.hasPrefix("@") && $0.icon != nil })  // the name alone
        #expect(model.rows.map(\.label) == (1...model.rows.count).map(String.init))
        let improve = try #require(model.rows.first { $0.text == "improve" })
        #expect(improve.icon == IconToken(.improve, color: .purple))
        #expect(improve.comment == "Polish in the same language, plus rewrites")
        #expect(zh.model(for: c).rows.first { $0.text == "improve" }?.comment == "润色，再给几种改写（不翻译）")
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
    @Test func thePresentersLanguageWhateverTheProcesssIs() async {
        let c = composer()
        c.setInputMode(.english)
        improveDraft(c)
        type("hello", c)
        let (english, chinese) = await withInterfaceLanguage("zh") { (en.model(for: c), zh.model(for: c)) }
        let (englishInEnglish, chineseInEnglish) = await withInterfaceLanguage("en") { (en.model(for: c), zh.model(for: c)) }
        #expect(english == englishInEnglish)
        #expect(chinese == chineseInEnglish)
        #expect(english.footer == "⌃V paste · ⌫ delete · Esc clear" && chinese.footer == "⌃V 粘贴 · ⌫ 删字 · Esc 清除")
        #expect(english.status == .hint("Space twice → polish / rewrite"))
    }

    /// The panel on Windows: its terms, the composer acting on its keys (`Composer.modifierRoles`), as a shell there sets
    /// them.
    func windows(_ c: Composer, language: String = "en") -> PanelModel {
        let roles = c.modifierRoles
        c.modifierRoles = .windows
        defer { c.modifierRoles = roles }
        return PanelPresenter(config: .default, language: language, terms: .windows).model(for: c)
    }

    /// On Windows the keys have Windows' names (`PlatformTerms`); the Mac's text stays as it was.
    @Test func theKeysAsThePlatformNamesThem() throws {
        let c = composer()
        c.setInputMode(.english)
        improveDraft(c)
        #expect(windows(c).footer == "Ctrl+V paste · Backspace delete · Esc clear")
        #expect(windows(c).status == .hint("Write something, or Ctrl+V to paste"))
        #expect(windows(c, language: "zh-Hans").footer == "Ctrl+V 粘贴 · Backspace 删字 · Esc 清除")
        #expect(PanelPresenter(config: .default, language: "en", terms: .mac).model(for: c).footer == "⌃V paste · ⌫ delete · Esc clear")
        // Results: copied with Ctrl+C.
        let sent = translating()
        _ = sent.receive(result, isFinal: true, id: 1)
        try #require(sent.phase == .choosing)
        #expect(windows(sent).footer == "Type, Shift+Enter refine · Space / Enter insert · digits pick · 0 original · Ctrl+C copy · Esc back")
        #expect(en.model(for: sent).footer == "Type, ⇧⏎ refine · Space / ⏎ insert · digits pick · 0 original · ⌘C copy · Esc back")
        // The action key a tap of Ctrl, in the palette's footer and a draft's hint.
        let tap = composer(key: .optionTap)
        tap.setInputMode(.english)
        improveDraft(tap)
        type("hello", tap)
        #expect(windows(tap).status == .hint("Tap Ctrl → polish / rewrite"))
        #expect(en.model(for: tap).status == .hint("Tap ⌥ → polish / rewrite"))
        // A shortcut recorded on the Mac: pressed with Ctrl on Windows.
        let recorded = composer(key: .shortcut(KeyShortcut(keyCode: 0x26, modifiers: .command, name: "⌘J")))
        recorded.setInputMode(.english)
        improveDraft(recorded)
        type("hello", recorded)
        #expect(windows(recorded).status == .hint("Ctrl+J → polish / rewrite"))
        #expect(en.model(for: recorded).status == .hint("⌘J → polish / rewrite"))
    }

    /// Which key does what is the composer's (`Composer.modifierRoles`), whatever roles the terms came with: the panel
    /// names the keys the composer acts on, so a shell that sets only one of the two can't make them disagree.
    @Test func theKeysAreTheOnesTheComposerActsOn() throws {
        let sent = translating()
        _ = sent.receive(result, isFinal: true, id: 1)
        try #require(sent.phase == .choosing)
        var macRoles = PlatformTerms.windows
        macRoles.roles = .mac
        sent.modifierRoles = .windows
        #expect(PanelPresenter(config: .default, language: "en", terms: macRoles).model(for: sent).footer.contains("Ctrl+C copy"))
        // The composer left on the Mac's roles: ⌘, the Windows key there, copies.
        sent.modifierRoles = .mac
        #expect(PanelPresenter(config: .default, language: "en", terms: .windows).model(for: sent).footer.contains("Win+C copy"))
        // The voice key and the action key too.
        let tap = composer(key: .optionTap)
        tap.setInputMode(.english)
        improveDraft(tap)
        type("hello", tap)
        tap.modifierRoles = .windows
        #expect(PanelPresenter(config: .default, language: "en", terms: macRoles).model(for: tap).status == .hint("Tap Ctrl → polish / rewrite"))
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
                == ["Screenshot · 2 lines (read on this Mac)", "The image stays on this Mac; only its text is sent"])
        #expect(SessionText.attachmentHeader(c, language: "en", terms: .windows)
                == ["Screenshot · 2 lines (read on this PC)", "The image stays on this PC; only its text is sent"])
        #expect(SessionText.attachmentHeader(c, language: "zh-Hans", terms: .windows) == ["截图 · 2 行（本机识别）", "图片不会离开这台电脑，只发送认出的文字"])
        // In the panel, each a line of the header.
        #expect(PanelPresenter(config: .default, language: "en", terms: .windows).model(for: c).header
                == ["Screenshot · 2 lines (read on this PC)", "The image stays on this PC; only its text is sent"])
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

    // MARK: - An @question conversation

    let commandReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .command)

    /// "@question what is rust" ⏎ in English, answered (request 1); then `followUps`, each asked with ⇧⏎ and answered.
    func conversation(rounds: Int = 5, handoff: [ChatHandoff.Destination] = [.claudeCode, .claudeWeb, .chatgpt, .copy],
                      followUps: [(String, String)] = []) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.questionRounds = rounds
        c.handoffChoices = handoff
        c.remembersQuestions = false
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        for ch in "question" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(tab)
        for ch in "what is rust" { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("A systems language.")]), isFinal: true, id: 1)
        for (question, answer) in followUps {
            for ch in question { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
            let started = c.handleKeyDown(shiftEnterKey).effects.lazy.compactMap { effect -> Int? in
                if case let .startRefine(_, id) = effect { return id } else { return nil }
            }.first
            if let started { _ = c.receive(ConversionResult(versions: [CandidateLine(answer)]), isFinal: true, id: started) }
        }
        return c
    }

    /// Its rounds as question and answer rows, oldest first: a click on an answer picks its round, on a question nothing;
    /// the highlight is on the answer picked; the line on top is the next question, its caret after what is typed.
    @Test func aConversationIsItsRoundsWithTheNextQuestionOnTop() throws {
        let c = conversation(followUps: [("who made it", "Graydon Hoare.")])
        try #require(c.isQuestionChat && c.phase == .choosing && c.chatRounds.count == 2)
        let model = en.model(for: c)
        #expect(model.transcript)
        #expect(model.rows.map(\.text) == ["Q: what is rust", "A: A systems language.", "Q: who made it", "A: Graydon Hoare."])
        #expect(model.rows.map(\.label) == ["", "1", "", "2"] && model.rows.map(\.choice) == [nil, 0, nil, 1])
        #expect(model.rows.map(\.pickable) == [false, true, false, true])
        #expect(model.rows.map(\.kind) == [.original, .original, .original, .translation])
        #expect(model.highlighted == 2 * c.highlighted + 1 && model.highlighted == 3)
        _ = c.handleKeyDown(upKey)
        #expect(en.model(for: c).highlighted == 1, "↑: the first answer")
        #expect(model.input == PanelModel.Input(prompt: "question 3/5 › ", text: "", caret: 0))
        #expect(model.handoff == nil && model.header.isEmpty)
        #expect(model.footer == "⇧⏎ ask · ⏎ insert · 1–5 pick · ⌘C copy · Esc back")
        for ch in "when" { _ = c.handleKeyDown(k(String(ch))) }
        #expect(en.model(for: c).input == PanelModel.Input(prompt: "question 3/5 › ", text: "when", caret: 4))
        #expect(zh.model(for: c).input?.prompt == "追问 3/5 › ")
    }

    /// After the last round (or ⌘⏎), where it can go on: a title, and the destinations with the shortcuts that pick them.
    @Test func whereAConversationCanGoOn() throws {
        let c = conversation(rounds: 2, handoff: [.claudeCode, .claudeWeb, .chatgpt, .gemini, .copy],
                             followUps: [("who made it", "Graydon Hoare.")])
        try #require(c.showsHandoff)
        let model = en.model(for: c)
        let handoff = try #require(model.handoff)
        #expect(handoff.title == "2 rounds in: continue in Claude or another AI")
        #expect(handoff.choices.map(\.shortcut) == ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5"])
        #expect(handoff.choices.map(\.name) == ["Claude Code", "Claude", "ChatGPT", "Gemini", "Copy"])
        #expect(model.input == nil, "nothing typed to take along")
        #expect(model.footer == "⌘1–⌘5 continue · ⏎ insert · 1–2 pick · ⌘C copy · Esc back")
        // What is typed goes along: its line under the choices.
        for ch in "and" { _ = c.handleKeyDown(k(String(ch))) }
        let typed = en.model(for: c)
        #expect(typed.input == PanelModel.Input(prompt: "then › ", text: "and", caret: 3))
        #expect(typed.footer == "⌘1–⌘5 continue, with what you typed · ⏎ insert · 1–2 pick · ⌘C copy · Esc back")
        // On Windows, picked with Ctrl.
        let onWindows = windows(c)
        #expect(onWindows.handoff?.choices.map(\.shortcut) == ["Ctrl+1", "Ctrl+2", "Ctrl+3", "Ctrl+4", "Ctrl+5"])
        #expect(onWindows.footer == "Ctrl+1–5 continue, with what you typed · Enter insert · 1–2 pick · Ctrl+C copy · Esc back")
        // Before the last round, ⌘⏎ shows them.
        let early = conversation(handoff: [.copy])
        #expect(en.model(for: early).handoff == nil)
        _ = early.handleKeyDown(commandReturn)
        #expect(en.model(for: early).handoff == PanelModel.Handoff(title: "Continue in Claude or another AI",
                                                                   choices: [.init(shortcut: "⌘1", name: "Copy")]))
        #expect(en.model(for: early).footer.hasPrefix("⌘1 continue · "))
    }

    /// An answer whose placeholder the model changed past telling is marked on its row; the detail says what was hidden.
    @Test func aConversationsChangedPlaceholderIsMarked() throws {
        let c = conversation(followUps: [("and its email", "Write to EMAIL_1.")])
        try #require(c.chatRounds.count == 2)
        let model = PanelPresenter(config: .default, language: "en", elapsed: 1, hidden: 1).model(for: c)
        #expect(model.rows.map(\.comment) == ["", "", "", "⚠ placeholder changed"])
        #expect(model.detail == "1 item hidden from the AI · 1.0s")
        #expect(PanelPresenter(config: .default, language: "en", elapsed: 1).model(for: c).rows.allSatisfy { $0.comment.isEmpty })
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

    /// Each built-in command has a built-in icon of its own; none is the generic one.
    @Test func eachBuiltInCommandHasItsOwn() {
        let builtins = [Command.improve, .translate, .question, .reply, .agent, .open, .read, .note, .reminder, .py, .js,
                        .webSearch, .tasks, .settings, .imessage, .reportIssue]
        let glyphs = builtins.map { IconToken.command($0).glyph }
        #expect(Set(glyphs.map { "\($0)" }).count == builtins.count, "one each")
        #expect(glyphs.allSatisfy { if case let .builtin(builtin) = $0 { return builtin != .command } else { return false } })
        #expect(IconToken.command(Command(name: "made-up", kind: .convert)).glyph == .builtin(.command))
    }

    /// The list a shell maps (`Builtin`): its names are the ones documented, each with an Apple symbol.
    @Test func theBuiltInsAreTheListAShellMaps() {
        #expect(IconToken.Builtin.allCases.map(\.rawValue) == [
            "improve", "translate", "question", "reply", "agent", "open", "read", "note", "reminder", "python", "javascript",
            "webSearch", "tasks", "settings", "message", "reportIssue", "command", "plugin", "link", "prompt", "run",
            "terminal", "snippet", "scriptInsert", "scriptShow", "scriptList", "scriptSilent", "scriptBackground",
            "scriptStatus", "done", "working", "needsYou",
        ])
        #expect(IconToken.Builtin.allCases.allSatisfy { !$0.appleSymbol.isEmpty && IconToken.Builtin(rawValue: $0.rawValue) == $0 })
    }

    /// A script extension's own glyph, one of emoji, image or symbol, falls back to the icon for what it does.
    @Test func aScriptNamesItsOwnWithAFallback() {
        var script = ScriptCommand(file: URL(fileURLWithPath: "/tmp/s.sh"), name: "s")
        let plain = IconToken.script(script)
        #expect(plain == IconToken(.scriptInsert, color: .teal) && plain.fallback == .scriptInsert)
        script.icon = .symbol("airplane")
        #expect(IconToken.script(script).glyph == .symbol("airplane", fallback: .scriptInsert))
        script.icon = .emoji("🍅")
        #expect(IconToken.script(script).glyph == .emoji("🍅", fallback: .scriptInsert))
        script.icon = .image(URL(fileURLWithPath: "/tmp/icon.png"))
        #expect(IconToken.script(script).glyph == .image(path: "/tmp/icon.png", fallback: .scriptInsert))
        script.output = .list
        #expect(IconToken.script(script).fallback == .scriptList)
    }

    /// A plugin's and a custom command's own symbol falls back to the icon for what they are.
    @Test func pluginsAndCustomCommandsFallBackByWhatTheyAre() {
        var manifest = PluginManifest(name: "stock", version: "1", type: .prompt, prompt: "x")
        let directory = URL(fileURLWithPath: "/tmp/stock")
        #expect(IconToken.plugin(InstalledPlugin(manifest: manifest, directory: directory, isLocal: true)) == IconToken(.plugin, color: .pink))
        manifest.icon = "chart.line.uptrend.xyaxis"
        manifest.color = "green"
        #expect(IconToken.plugin(InstalledPlugin(manifest: manifest, directory: directory, isLocal: true))
                == IconToken(.symbol("chart.line.uptrend.xyaxis", fallback: .plugin), color: .green))
        manifest.type = .link
        #expect(IconToken.plugin(InstalledPlugin(manifest: manifest, directory: directory, isLocal: true)).fallback == .link)
        let top = CustomCommand(name: "top", type: .terminal, argv: ["/usr/bin/top"])
        #expect(IconToken.custom(top) == IconToken(.terminal, color: .grayscale(0.25)))
        let mine = CustomCommand(name: "mine", type: .prompt, prompt: "x", icon: "star.fill", color: "#FF0000")
        #expect(IconToken.custom(mine) == IconToken(.symbol("star.fill", fallback: .prompt), color: .rgb(red: 255, green: 0, blue: 0)))
    }

    @Test func aTasksStateIsItsOwn() {
        #expect([AgentSession.Progress.done, .working, .needsYou].map { IconToken.progress($0).glyph }
                == [.builtin(.done), .builtin(.working), .builtin(.needsYou)])
    }
}
