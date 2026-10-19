import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Runs `body` in the interface language `choice` ("zh", "en"), then puts the one before back. The language is the
/// process's (`UIText.choice`): the tests that set it take turns, whichever suite they are in.
func withInterfaceLanguage<T>(_ choice: String, _ body: () throws -> T) rethrows -> T {
    interfaceLanguageLock.lock()
    defer { interfaceLanguageLock.unlock() }
    let before = UIText.choice
    UIText.choice = choice
    defer { UIText.choice = before }
    return try body()
}

private let interfaceLanguageLock = NSRecursiveLock()

/// What a text field's session says around the composer (`SessionText`), in Simplified Chinese and English.
@Suite(.serialized)
struct SessionTextTests {
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

    @Test func longTextIsShortenedOnOneLine() {
        #expect(SessionText.preview(String(repeating: "a", count: 300)).count == 281)
        #expect(SessionText.preview("short") == "short")
        #expect(SessionText.selectionPreview("one\ntwo\n\nthree") == "one ↵ two ↵ three")
        #expect(SessionText.selectionPreview(String(repeating: "字", count: 70)) == String(repeating: "字", count: 60) + "…")
    }

    @Test func anOpenRowSaysWhereItIs() {
        let home = CorePaths.home.path
        inLanguage("zh") {
            #expect(SessionText.openRow(SearchResult(name: "Calculator", path: "/System/Applications/Calculator.app",
                                                     chineseName: "计算器")) == ("计算器", "应用"))
            #expect(SessionText.openRow(SearchResult(name: "Notes", path: home + "/Documents/Notes", isFolder: true)).comment
                    == "~/Documents/")
            #expect(SessionText.openRow(SearchResult(name: "a.txt", path: home + "/a.txt", matchedContent: true)).comment == "内容 · ~")
        }
        inLanguage("en") {
            #expect(SessionText.openRow(SearchResult(name: "Calculator", path: "/System/Applications/Calculator.app",
                                                     chineseName: "计算器")) == ("Calculator", "app"))
        }
    }

    @Test func whatGoesInAfterASelection() {
        let selection = Composer.Selection(text: "Lunch?", range: 10..<16)
        #expect(SessionText.afterSelection("Lunch? Sure!", selection).map { [$0.text, String($0.at)] } == [" Sure!", "16"])
        #expect(SessionText.afterSelection("Sure!", selection) == nil)
        #expect(SessionText.afterSelection("Lunch?", selection) == nil)
        #expect(SessionText.afterSelection("Lunch? Sure!", Composer.Selection(text: "Lunch?")) == nil)
    }

    @Test func theDraftHintNamesTheActionKey() {
        let c = composer(key: .optionTap)
        c.setInputMode(.english)
        improveDraft(c)
        type("hello", c)
        let hint = inLanguage("zh") { SessionText.draftHint(c, config: .default) }
        #expect(hint.hasPrefix("单按 ⌥ → "))
        #expect(inLanguage("en") { SessionText.draftHint(c, config: .default) }.hasPrefix("Tap ⌥ → "))
        #expect(SessionText.draftHint(composer(), config: .default) == "")
    }

    @Test func menuAndSettingsRules() {
        #expect(SessionText.toggled("口语", in: ["正式", "润色"]).last == "口语")
        #expect(!SessionText.toggled("润色", in: ["正式", "润色"]).contains("润色"))
        #expect(SessionText.toggled(Language.english, in: [.chinese]) == [.chinese, .english])
        #expect(SessionText.toggled(Language.chinese, in: [.chinese]) == [.chinese])
        #expect(inLanguage("zh") { SessionText.inputName(.chinese) } == "中文（拼音）")
        #expect(inLanguage("en") { SessionText.inputName(.chinese) } == "Chinese (pinyin)")
        #expect(SessionText.chatChoice(row: 0) == nil && SessionText.chatChoice(row: 3) == 1)
        #expect(SessionText.noticeDuration("x", long: true) == 12 && SessionText.noticeDuration("", long: false) == 1.2)
        #expect(SessionText.noticeDuration(String(repeating: "x", count: 200), long: false) == 5)
        #expect(inLanguage("en") { SessionText.shortName(.atAgent, picked: .claude) } == "@agent's agent (Claude Code)")
        #expect(inLanguage("zh") { SessionText.name(.copy) } == "复制对话")
    }
}
