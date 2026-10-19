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

/// What a text field's session says around the composer (`SessionText`), in Simplified Chinese and English: in the
/// language each call is given.
struct SessionTextTests {
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

    @Test func longTextIsShortenedOnOneLine() {
        #expect(SessionText.preview(String(repeating: "a", count: 300)).count == 281)
        #expect(SessionText.preview("short") == "short")
        #expect(SessionText.selectionPreview("one\ntwo\n\nthree") == "one ↵ two ↵ three")
        #expect(SessionText.selectionPreview(String(repeating: "字", count: 70)) == String(repeating: "字", count: 60) + "…")
    }

    @Test func anOpenRowSaysWhereItIs() {
        let home = CorePaths.home.path
        let calculator = SearchResult(name: "Calculator", path: "/System/Applications/Calculator.app", chineseName: "计算器")
        #expect(SessionText.openRow(calculator, language: "zh-Hans") == ("计算器", "应用"))
        #expect(SessionText.openRow(SearchResult(name: "Notes", path: home + "/Documents/Notes", isFolder: true),
                                    language: "zh-Hans").comment == "~/Documents/")
        #expect(SessionText.openRow(SearchResult(name: "a.txt", path: home + "/a.txt", matchedContent: true),
                                    language: "zh-Hans").comment == "内容 · ~")
        #expect(SessionText.openRow(calculator, language: "en") == ("Calculator", "app"))
        // Traditional Chinese has Finder's name, as the other languages.
        #expect(SessionText.openRow(calculator, language: "zh-Hant").text == "Calculator")
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
        #expect(SessionText.draftHint(c, config: .default, language: "zh-Hans").hasPrefix("单按 ⌥ → "))
        #expect(SessionText.draftHint(c, config: .default, language: "en").hasPrefix("Tap ⌥ → "))
        #expect(SessionText.draftHint(composer(), config: .default, language: "en") == "")
    }

    /// The text is in the language given, whatever the process's is.
    @Test func theLanguageGivenWhateverTheProcesssIs() {
        let c = composer(key: .optionTap)
        c.setInputMode(.english)
        improveDraft(c)
        type("hello", c)
        let (english, chinese) = withInterfaceLanguage("zh") {
            (SessionText.draftHint(c, config: .default, language: "en"), SessionText.inputName(.chinese, language: "en"))
        }
        #expect(english == withInterfaceLanguage("en") { SessionText.draftHint(c, config: .default, language: "en") })
        #expect(english.hasPrefix("Tap ⌥ → ") && chinese == "Chinese (pinyin)")
    }

    @Test func menuAndSettingsRules() {
        #expect(SessionText.toggled("口语", in: ["正式", "润色"]).last == "口语")
        #expect(!SessionText.toggled("润色", in: ["正式", "润色"]).contains("润色"))
        #expect(SessionText.toggled(Language.english, in: [.chinese]) == [.chinese, .english])
        #expect(SessionText.toggled(Language.chinese, in: [.chinese]) == [.chinese])
        #expect(SessionText.inputName(.chinese, language: "zh-Hans") == "中文（拼音）")
        #expect(SessionText.inputName(.chinese, language: "en") == "Chinese (pinyin)")
        #expect(SessionText.inputName(.english, language: "en") == "English")
        #expect(SessionText.chatChoice(row: 0) == nil && SessionText.chatChoice(row: 3) == 1)
        #expect(SessionText.noticeDuration("x", long: true) == 12 && SessionText.noticeDuration("", long: false) == 1.2)
        #expect(SessionText.noticeDuration(String(repeating: "x", count: 200), long: false) == 5)
        #expect(SessionText.shortName(.atAgent, picked: .claude, language: "en") == "@agent's agent (Claude Code)")
        #expect(SessionText.name(.copy, language: "zh-Hans") == "复制对话")
        #expect(SessionText.name(.claudeWeb, language: "en") == "Claude (web)")
    }
}
