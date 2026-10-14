import Foundation
import Testing
@testable import AllInOneIMECore

/// French and Korean next to Chinese and English: Shift goes through them in order, Korean composes Hangul.
struct InputLanguageTests {
    /// Key codes of the letter keys (ANSI positions), as a Mac keyboard sends them.
    static let codes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    func key(_ letter: Character, shift: Bool = false) -> KeyEvent {
        let text = shift ? letter.uppercased() : String(letter)
        return KeyEvent(keyCode: Self.codes[letter]!, characters: text, charactersIgnoringModifiers: String(letter),
                        modifiers: shift ? .shift : [])
    }

    func type(_ letters: String, _ c: Composer) -> [Composer.Effect] {
        letters.flatMap { c.handleKeyDown(key($0)).effects }
    }

    func korean() -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hangulTables = PackData.hangul
        c.inputLanguages = [.english, .korean]
        c.setInputMode(.korean)
        return c
    }

    func shiftTap(_ c: Composer, at t: Double) -> [Composer.Effect] {
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: t)
        return c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: t + 0.1)
    }

    @Test func koreanComposesSyllablesIntoTheDocument() {
        let c = korean()
        // g k s r m f → 한글: 한 goes in once ㄱ starts the next syllable; 글 stays marked.
        let effects = type("gksrmf", c)
        #expect(commits(effects) == ["한"])
        #expect(c.markedText == "글")
        // Space finishes it, then is a space for the app.
        let space = c.handleKeyDown(spaceKey)
        #expect(commits(space) == ["글"])
        #expect(!space.handled)
        #expect(c.markedText.isEmpty)
    }

    @Test func backspaceTakesBackAJamoThenGoesToTheApp() {
        let c = korean()
        _ = type("ekfr", c)  // 닭
        #expect(c.markedText == "닭")
        #expect(c.handleKeyDown(backspaceKey).handled)
        #expect(c.markedText == "달")
        _ = c.handleKeyDown(backspaceKey)
        _ = c.handleKeyDown(backspaceKey)
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.markedText.isEmpty)
        #expect(c.handleKeyDown(backspaceKey) == .passThrough)
    }

    @Test func shiftGivesTenseConsonants() {
        let c = korean()
        _ = c.handleKeyDown(key("r", shift: true))
        _ = c.handleKeyDown(key("k"))
        #expect(c.markedText == "까")
    }

    @Test func koreanInACommandsText() {
        let c = korean()
        _ = c.handleKeyDown(at)
        // The command's name is typed in letters, not Hangul.
        _ = type("tr", c)
        #expect(c.draft == "@tr")
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@translate ")
        _ = type("dkssud", c)  // 안녕
        #expect(c.draft == "@translate 안")
        #expect(c.markedText.hasSuffix(" 안녕"))  // 녕 still being typed, at the cursor
        // ⏎ finishes the syllable and runs the command on the whole text.
        let run = c.handleKeyDown(enterKey)
        #expect(c.sentText == "안녕")
        #expect(run.effects.contains { if case .startConversion = $0 { return true } else { return false } })
    }

    @Test func shiftGoesThroughTheLanguagesInOrder() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hangulTables = PackData.hangul
        c.inputLanguages = [.english, .french, .korean, .chinese]
        c.setInputMode(.english)
        #expect(c.inputLanguage == .english)
        let toFrench = shiftTap(c, at: 10)
        #expect(c.inputLanguage == .french)
        #expect(toFrench.contains(.inputLanguageChanged(.french)))
        _ = shiftTap(c, at: 11)
        #expect(c.inputLanguage == .korean)
        _ = shiftTap(c, at: 12)
        #expect(c.inputLanguage == .chinese)
        _ = shiftTap(c, at: 13)
        #expect(c.inputLanguage == .english)
    }

    @Test func withoutThePackKeysAreLetters() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.korean)
        #expect(c.handleKeyDown(key("g")) == .passThrough)
    }

    @Test func switchingFinishesTheSyllable() {
        let c = korean()
        _ = type("gks", c)
        let effects = shiftTap(c, at: 20)
        #expect(commits(effects) == ["한"])
        #expect(c.inputLanguage == .english)
        #expect(c.markedText.isEmpty)
    }

    @Test func frenchTypesLettersAsTheAppGetsThem() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.inputLanguages = [.english, .french]
        c.setInputMode(.french)
        #expect(c.inputLanguage == .french)
        // Letters reach the app as its keyboard layout makes them (AZERTY: the A key types "q").
        #expect(c.handleKeyDown(KeyEvent(keyCode: 0, characters: "q")) == .passThrough)
    }

    @Test func dictationListensInTheInputLanguage() {
        let c = korean()
        _ = c.handleFlagsChanged(keyCode: VirtualKey.rightOption, modifiers: [.option, .rightOption], timestamp: 1)
        let effects = c.voiceHoldElapsed()
        #expect(effects.contains(.startVoice(id: 1, language: .korean)))
    }

    @Test func configKeepsUnknownLanguagesOutAndLayoutsByLanguage() throws {
        let json = #"{"inputLanguages": ["ko", "xx", "fr"], "keyboardLayouts": {"fr": "com.apple.keylayout.French-PC"}, "uiLanguage": "fr"}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.inputLanguages == [.korean, .french])
        #expect(config.uiLanguage == nil)  // the interface is Chinese or English
        #expect(config.keyboardLayout(for: .french) == "com.apple.keylayout.French-PC")
        #expect(Config.default.keyboardLayout(for: .french) == "com.apple.keylayout.French")
        #expect(Config.default.keyboardLayout(for: .english) == nil)
    }
}
