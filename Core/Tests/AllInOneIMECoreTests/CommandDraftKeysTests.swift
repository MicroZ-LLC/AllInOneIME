import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A command not run yet ("@improve …", "@question …") never goes into the field as typed (the owner, 2026-11-15): ⌘⏎
/// runs it as ⏎ does, any other ⌘ shortcut and the field left drop it, ⌘← ⌘→ convert its pinyin into it first. The same
/// whether its text is Chinese or English; plain text and `@note` go in as typed, as before.
struct CommandDraftKeysTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let commandReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .command)
    let commandA = KeyEvent(keyCode: 0x00, characters: "a", charactersIgnoringModifiers: "a", modifiers: .command)
    let commandS = KeyEvent(keyCode: 0x01, characters: "s", charactersIgnoringModifiers: "s", modifiers: .command)
    let commandRight = KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}", modifiers: .command)

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
    }

    /// `name` picked from the list with Tab ("@" and its first letters), ⏎ the action key (the default).
    func draft(_ name: String, english: Bool) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.remembersQuestions = false
        if english { c.setInputMode(.english) }
        _ = c.handleKeyDown(at)
        type(name, c)
        _ = c.handleKeyDown(tab)
        return c
    }

    /// "@improve hello world" in English mode, "@improve 你好" in Chinese (the pinyin picked with Space).
    func improve(english: Bool) -> Composer {
        let c = draft("improve", english: english)
        type(english ? "hello world" : "nihao ", c)
        #expect(c.draft == (english ? "@improve hello world" : "@improve 你好") && c.phase == .drafting)
        return c
    }

    func startsConversion(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { if case .startConversion = $0 { true } else { false } }
    }

    // MARK: - ⌘⏎

    @Test(arguments: [true, false])
    func commandReturnRunsTheCommandAsReturnDoes(english: Bool) {
        let byReturn = improve(english: english), byCommandReturn = improve(english: english)
        let expected = byReturn.handleKeyDown(enterKey)
        let response = byCommandReturn.handleKeyDown(commandReturn)
        #expect(response == expected && response.handled, "the key never reaches the app")
        #expect(startsConversion(response.effects) && commits(response).isEmpty && byCommandReturn.isLevelTwo)
    }

    /// Pinyin not picked yet is picked first, as ⏎ picks it.
    @Test func commandReturnPicksThePinyinAndRuns() {
        let c = draft("improve", english: false)
        type("nihao", c)
        #expect(c.engineState.isComposing)
        let response = c.handleKeyDown(commandReturn)
        #expect(response.handled && response.effects.contains(.startConversion(input: "你好", id: 1)))
        #expect(commits(response).isEmpty)
    }

    // MARK: - Any other ⌘ shortcut

    @Test(arguments: [true, false])
    func anotherShortcutDropsTheCommandAndGoesToTheApp(english: Bool) {
        for key in [commandA, commandS] {
            let c = improve(english: english)
            let response = c.handleKeyDown(key)
            #expect(!response.handled, "\(key.characters): the shortcut is the app's")
            #expect(commits(response).isEmpty && response.effects.contains(.hidePanel), "\(key.characters)")
            #expect(c.draft.isEmpty && c.phase == .idle && c.markedText.isEmpty, "\(key.characters)")
        }
    }

    @Test func aShortcutDropsPinyinBeingTypedInACommandToo() {
        let c = draft("question", english: false)
        type("nihao", c)
        let response = c.handleKeyDown(commandA)
        #expect(!response.handled && commits(response).isEmpty)
        #expect(c.draft.isEmpty && !c.engineState.isComposing && c.phase == .idle)
    }

    // MARK: - ⌘← ⌘→

    @Test func commandRightPicksThePinyinIntoTheCommandThenMoves() {
        let c = draft("question", english: false)
        type("hello ", c)  // Chinese mode: the FakeEngine has no word for it, so its letters are its candidate
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}", modifiers: .command))
        type("nihao", c)
        #expect(c.engineState.isComposing)
        let response = c.handleKeyDown(commandRight)
        #expect(response.handled && commits(response).isEmpty)
        #expect(c.draft == "@question 你好hello" && !c.engineState.isComposing && c.cursorTailCount == 0)
    }

    // MARK: - The field left

    @Test(arguments: [true, false])
    func leavingTheFieldDropsTheCommand(english: Bool) {
        let c = improve(english: english)
        #expect(c.commitAll() == [.hidePanel, .updateMarkedText])
        #expect(c.draft.isEmpty && c.phase == .idle)
    }

    @Test func leavingTheFieldDropsPinyinBeingTypedInACommand() {
        let pinyin = draft("improve", english: false)
        type("nihao", pinyin)
        #expect(commits(pinyin.commitAll()).isEmpty && !pinyin.engineState.isComposing && pinyin.phase == .idle)
    }

    /// The session's blur and the app's commit, with a Chinese command: nothing in the field. Plain text still goes in.
    @Test func aChineseCommandIsDroppedWhenTheFieldIsLeftAndPlainTextIsNot() {
        for event in [SessionEvent.blur, .commit] {
            let host = Self.host()
            host.press(FakeHost.at)
            host.type("question")
            host.press(FakeHost.tab)
            host.type("nihao")
            host.press(FakeHost.space)
            #expect(host.composer.draft == "@question 你好", "\(event)")
            host.send(event)
            #expect(host.document.isEmpty && host.composer.draft.isEmpty, "\(event): \"\(host.document)\"")
        }
        let host = Self.host()
        host.type("nihao")
        host.send(.blur)
        #expect(host.document == "你好")
    }

    // MARK: - As before

    /// Not a command: "@john" (one @'s text) goes in as typed with a shortcut, as before.
    @Test func plainTextStillGoesInAsTypedWithAShortcut() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("john", c)
        #expect(c.draft == "@john" && c.draftCommand == nil)
        let response = c.handleKeyDown(commandA)
        #expect(!response.handled && commits(response) == ["@john"])
    }

    /// `@note` of one line keeps going in as typed: a shortcut, the field left (the owner kept it as it was).
    @Test func aOneLineNoteStillGoesInAsTyped() {
        let shortcut = draft("note", english: true)
        type("buy milk", shortcut)
        #expect(shortcut.draft == "@note buy milk" && !shortcut.dropsCommandDraft)
        let response = shortcut.handleKeyDown(commandA)
        #expect(!response.handled && commits(response) == ["@note buy milk"])
        let left = draft("note", english: true)
        type("buy milk", left)
        #expect(commits(left.commitAll()) == ["@note buy milk"])
    }

    /// At level two (the command has run) ⌘⏎ is the conversation's (`handleHandoffKey`), not a draft's.
    @Test func aCommandThatRanIsNoDraftToRun() {
        let c = improve(english: true)
        _ = c.handleKeyDown(enterKey)
        #expect(c.isLevelTwo && !c.isCommandDraft && !c.dropsCommandDraft)
    }

    // MARK: - @note and ⌘⏎

    /// A one-line `@note`: ⌘⏎ saves it, exactly as ⏎ does, and never reaches the app; leaving still types it in.
    @Test(arguments: [true, false])
    func commandReturnSavesAOneLineNoteAsReturnDoes(english: Bool) {
        func note() -> Composer {
            let c = draft("note", english: english)
            type(english ? "buy milk" : "nihao ", c)
            #expect(c.draft == (english ? "@note buy milk" : "@note 你好") && c.isCommandDraft)
            return c
        }
        let byReturn = note(), byCommandReturn = note()
        let expected = byReturn.handleKeyDown(enterKey)
        let response = byCommandReturn.handleKeyDown(commandReturn)
        #expect(response == expected && response.handled, "the key never reaches the app")
        #expect(commits(response).isEmpty && byCommandReturn.draft.isEmpty)
        #expect(commits(note().commitAll()) == [english ? "@note buy milk" : "@note 你好"])
    }

    // MARK: - A command that ran, the field left

    /// Results streaming in (`translating`) or all shown (`choosing`): the field left or the composition ended puts nothing
    /// in; the run is cancelled and the panel hidden.
    @Test func leavingTheFieldAfterTheCommandRanPutsNothingIn() {
        let streaming = improve(english: true)
        _ = streaming.handleKeyDown(enterKey)
        _ = streaming.receive(ConversionResult(versions: [CandidateLine("Hello", isComplete: false)]), isFinal: false, id: 1)
        #expect(streaming.phase == .translating(id: 1))
        let left = streaming.commitAll()
        #expect(commits(left).isEmpty && left.contains(.cancelConversion) && left.contains(.hidePanel))
        #expect(streaming.draft.isEmpty && streaming.phase == .idle)

        let shown = improve(english: false)
        _ = shown.handleKeyDown(enterKey)
        _ = shown.receive(ConversionResult(versions: [CandidateLine("Hello world.")]), isFinal: true, id: 1)
        #expect(shown.phase == .choosing)
        let ended = shown.commitAll()
        #expect(commits(ended).isEmpty && ended.contains(.hidePanel) && shown.phase == .idle)
    }

    /// The session's blur and the app's commit while the command runs: nothing in the field.
    @Test func theSessionPutsNothingInWhenACommandThatRanIsLeft() {
        for event in [SessionEvent.blur, .commit] {
            let host = Self.host()
            host.composer.setInputMode(.english)
            host.press(FakeHost.at)
            host.type("improve")
            host.press(FakeHost.tab)
            host.type("hello")
            host.press(enterKey)
            #expect(host.composer.isLevelTwo, "\(event)")
            host.send(event)
            #expect(host.document.isEmpty && host.composer.draft.isEmpty && host.panel == nil, "\(event): \"\(host.document)\"")
        }
    }

    // MARK: - A password field

    /// A password field takes over (`passwordFieldTakesOver`) with a command not run yet, or one that ran: dropped, never
    /// typed into it. A one-line `@note` and plain text still go in as typed, as everywhere else.
    @Test(arguments: [true, false])
    func aPasswordFieldNeverGetsTheCommand(english: Bool) {
        let c = improve(english: english)
        let ended = c.passwordFieldTakesOver()
        #expect(commits(ended).isEmpty && ended.contains(.hidePanel) && c.draft.isEmpty && c.phase == .idle)
        let pinyin = draft("question", english: false)
        type("nihao", pinyin)
        #expect(commits(pinyin.passwordFieldTakesOver()).isEmpty && !pinyin.engineState.isComposing)
        let ran = improve(english: english)
        _ = ran.handleKeyDown(enterKey)
        #expect(commits(ran.passwordFieldTakesOver()).isEmpty && ran.phase == .idle)
        let note = draft("note", english: true)
        type("buy milk", note)
        #expect(commits(note.passwordFieldTakesOver()) == ["@note buy milk"])
        let plain = Composer(engine: FakeEngine(), actionKey: .enter)
        type("nihao", plain)
        #expect(commits(plain.passwordFieldTakesOver()) == ["nihao"])
    }

    /// The session: secure input comes on in the field with "@question 你好" pending; the next key finds it gone.
    @Test func secureInputDropsTheCommandInTheSession() {
        let host = Self.host()
        host.press(FakeHost.at)
        host.type("question")
        host.press(FakeHost.tab)
        host.type("nihao")
        host.press(FakeHost.space)
        #expect(host.composer.draft == "@question 你好")
        host.secure = true
        host.press(k("a"))
        #expect(!host.document.contains("@question") && host.composer.draft.isEmpty, "\"\(host.document)\"")
    }

    // MARK: - ⌘V

    let commandV = KeyEvent(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: .command)

    func readsClipboard(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { if case .readClipboard = $0 { true } else { false } }
    }

    /// ⌘V in a command not run yet takes the clipboard into it in every app: also where the app pastes on ⌘V itself
    /// (terminals, Notes: `pastesIntoDraft` off). `@note` too; never the draft dropped.
    @Test(arguments: [true, false])
    func commandVPastesIntoTheCommandInEveryApp(appPastes: Bool) {
        for name in ["improve", "note"] {
            for english in [true, false] {
                let c = draft(name, english: english)
                c.pastesIntoDraft = !appPastes
                type(english ? "fix " : "nihao", c)
                #expect(c.pastesIntoCommand, "\(name)")
                let response = c.handleKeyDown(commandV)
                #expect(response.handled && readsClipboard(response.effects) && commits(response).isEmpty, "\(name)")
                #expect(c.draft == (english ? "@\(name) fix " : "@\(name) 你好"), "\(name): pinyin picked first")
                _ = c.pasted(.text("this"), id: 1)
                #expect(c.draft.hasSuffix("this") && c.phase == .drafting, "\(name)")
            }
        }
    }

    /// The session in a terminal: ⌘V pastes into "@improve " as in any other app.
    @Test func commandVPastesIntoTheCommandInATerminal() {
        for terminal in [false, true] {
            let host = Self.host(terminal: terminal)
            host.clipboard = .text("hello")
            host.composer.setInputMode(.english)
            host.press(FakeHost.at)
            host.type("improve")
            host.press(FakeHost.tab)
            #expect(host.press(commandV), "terminal: \(terminal)")
            #expect(host.composer.draft == "@improve hello" && host.document.isEmpty, "terminal: \(terminal)")
        }
    }

    /// A text field's session (a terminal's), in Chinese (pinyin) as it starts.
    static func host(terminal: Bool = false) -> FakeHost {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.uiLanguage = "en"
        config.rememberQuestions = false
        config.claudeInBackground = false
        let fixed = config
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.terminal = terminal
        host.focus()
        return host
    }
}
