import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Reproduction (AGENTS.md rule 20) of a suspicion from a code read: a command draft that hasn't run ("@question …")
/// goes into the text field as typed when a ⌘ shortcut is pressed over it (⌘⏎, ⌘←) or the field loses the focus. Each
/// test says what should happen; one that fails shows the draft went in.
struct CommandDraftAsTypedTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let commandReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .command)
    let commandLeft = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}", modifiers: .command)

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
    }

    /// "@question" picked with Tab and `question` typed after it, not asked yet (⏎ the action key, as by default).
    func questionDraft(english: Bool, _ question: String) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.remembersQuestions = false
        if english { c.setInputMode(.english) }
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type(question, c)
        return c
    }

    /// Whether `effects` put the command's own text into the field.
    func insertsTheCommand(_ effects: [Composer.Effect]) -> Bool {
        commits(effects).contains { $0.contains("@question") }
    }

    // MARK: - ⌘⏎

    /// ⌘⏎ is "send" in Slack, Teams, Discord, Messages' fields and many more: on "@question what is rust" not asked yet,
    /// the draft must not be typed into the field (the app's send would then post "@question what is rust").
    @Test func commandReturnOnAQuestionNotAskedYetPutsNothingInTheField() {
        let c = questionDraft(english: true, "what is rust")
        #expect(c.draft == "@question what is rust" && c.phase == .drafting && !c.isLevelTwo)
        let response = c.handleKeyDown(commandReturn)
        #expect(!insertsTheCommand(response.effects),
                "⌘⏎ typed the draft into the field: \(commits(response)), the key the app's too: \(!response.handled)")
    }

    // MARK: - ⌘←

    /// ⌘← in a command's text moves to the start of that text (DraftCursorTests): with English text, nothing goes in.
    @Test func commandLeftInAnEnglishQuestionMovesTheCursorOnly() {
        let c = questionDraft(english: true, "what is rust")
        let response = c.handleKeyDown(commandLeft)
        #expect(!insertsTheCommand(response.effects), "⌘← typed the draft into the field: \(commits(response))")
        #expect(c.draft == "@question what is rust" && c.markedCursor == "question › ".count)
    }

    /// The same key with the question's pinyin still being typed ("@question " then "nihao", not picked): it must not
    /// end the draft by typing "@question 你好" into the field either.
    @Test func commandLeftWhilePinyinIsTypedInAQuestionPutsNothingInTheField() {
        let c = questionDraft(english: false, "")
        type("nihao", c)
        #expect(c.draft == "@question " && c.engineState.isComposing)
        let response = c.handleKeyDown(commandLeft)
        #expect(!insertsTheCommand(response.effects),
                "⌘← typed the draft into the field: \(commits(response)), the key the app's too: \(!response.handled)")
    }

    // MARK: - The focus lost

    /// "@question what is rust" typed in a field, then the field loses the focus (another field or app clicked): what the
    /// session does then (`SessionEvent.blur`, the Mac's `deactivateServer`).
    @Test func leavingTheFieldWithAQuestionNotAskedYetPutsNothingInIt() {
        let host = Self.host()
        Self.typeQuestion("what is rust", in: host)
        #expect(host.composer.draft == "@question what is rust" && host.document.isEmpty)
        host.send(.blur)
        #expect(!host.document.contains("@question"), "the field left: \"\(host.document)\" typed into it")
    }

    /// The same when the app ends the composition itself (a click elsewhere in the field: `SessionEvent.commit`, the Mac's
    /// `commitComposition`).
    @Test func theAppEndingTheCompositionOverAQuestionNotAskedYetPutsNothingInTheField() {
        let host = Self.host()
        Self.typeQuestion("what is rust", in: host)
        host.send(.commit)
        #expect(!host.document.contains("@question"), "the composition ended: \"\(host.document)\" typed into the field")
    }

    /// A text field's session in English mode, the defaults otherwise (⏎ the action key).
    static func host() -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.rememberQuestions = false
        config.claudeInBackground = false
        let fixed = config
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    /// "@question" picked with Tab, then `question`.
    static func typeQuestion(_ question: String, in host: FakeHost) {
        host.press(FakeHost.at)
        host.type("question")
        host.press(FakeHost.tab)
        host.type(question)
    }
}
