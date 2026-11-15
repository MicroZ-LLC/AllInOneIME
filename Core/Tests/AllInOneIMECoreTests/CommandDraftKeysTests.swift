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

    /// At level two (the command has run) nothing changes: ⌘⏎ is the conversation's (`handleHandoffKey`).
    @Test func aCommandThatRanIsNoDraftToDrop() {
        let c = improve(english: true)
        _ = c.handleKeyDown(enterKey)
        #expect(c.isLevelTwo && !c.dropsCommandDraft)
    }

    /// A text field's session, in Chinese (pinyin) as it starts.
    static func host() -> FakeHost {
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
        host.focus()
        return host
    }
}
