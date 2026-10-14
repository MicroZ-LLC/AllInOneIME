import Testing
@testable import AllInOneIMECore

struct HindiTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    @Test func transliteratesByRule() {
        #expect(HindiTransliteration.transliterate("namaste", clusters: true) == "नमस्ते")
        #expect(HindiTransliteration.transliterate("bhaarat", clusters: true) == "भारत")
        #expect(HindiTransliteration.candidates("bharat").first == "भारत")  // from the word list
        #expect(HindiTransliteration.transliterate("kamra", clusters: false) == "कमरा")
        #expect(HindiTransliteration.transliterate("pyaar", clusters: true) == "प्यार")
        #expect(HindiTransliteration.transliterate("aam", clusters: true) == "आम")
        #expect(HindiTransliteration.transliterate("ghar", clusters: true) == "घर")
        // Capitals inside a word are the retroflex letters.
        #expect(HindiTransliteration.transliterate("TamaaTar", clusters: true) == "टमाटर")
    }

    @Test func commonWordsComeFirstSpelledAsHindiWritesThem() {
        #expect(HindiTransliteration.candidates("karna").first == "करना")
        #expect(HindiTransliteration.candidates("nahi").first == "नहीं")
        #expect(HindiTransliteration.candidates("main").first == "मैं")
        // A capital starting a sentence is the word, not a retroflex letter.
        #expect(HindiTransliteration.candidates("Main").first == "मैं")
        #expect(HindiTransliteration.candidates("Kamal").first == "कमल")
        // Words with a cluster offer both spellings.
        #expect(HindiTransliteration.candidates("kamra").contains("कमरा"))
        #expect(HindiTransliteration.candidates("kamra").contains("कम्रा"))
    }

    func hindi() -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.inputLanguages = [.english, .hindi]
        c.setInputMode(.hindi)
        return c
    }

    func type(_ s: String, _ c: Composer) -> [Composer.Effect] {
        s.flatMap { c.handleKeyDown(k(String($0))).effects }
    }

    @Test func typesAWordInDevanagari() {
        let c = hindi()
        #expect(c.inputLanguage == .hindi)
        _ = type("namaste", c)
        #expect(c.markedText == "नमस्ते")
        #expect(c.engineState.candidates.first?.text == "नमस्ते")
        let space = c.handleKeyDown(spaceKey)
        #expect(commits(space) == ["नमस्ते "])
        #expect(c.markedText.isEmpty)
    }

    @Test func digitsPickReturnTypesTheLettersDotIsTheDanda() {
        let c = hindi()
        _ = type("kamra", c)
        let picked = c.handleKeyDown(k("2"))
        #expect(commits(picked).count == 1)
        _ = type("ok", c)
        #expect(commits(c.handleKeyDown(enterKey)) == ["ok"])
        _ = type("hai", c)
        #expect(commits(c.handleKeyDown(k("."))) == ["है।"])
    }

    @Test func hindiInACommandsText() {
        let c = hindi()
        _ = c.handleKeyDown(at)
        _ = type("tr", c)  // the command's name in letters
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@translate ")
        _ = type("aap", c)
        _ = c.handleKeyDown(spaceKey)
        _ = type("kaise", c)
        _ = c.handleKeyDown(spaceKey)
        _ = type("ho", c)
        _ = c.handleKeyDown(enterKey)  // ⏎ runs it, the word being typed included
        #expect(c.sentText == "आप कैसे हो")
    }

    @Test func shiftLeavesHindiWithTheWordTyped() {
        let c = hindi()
        _ = type("namaste", c)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        let effects = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        #expect(commits(effects) == ["नमस्ते"])
        #expect(c.inputLanguage == .english)
        #expect(c.handleKeyDown(k("a")) == .passThrough)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 2)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 2.1)
        #expect(c.inputLanguage == .hindi)
    }

    @Test func chineseAndHindiTakeTurnsWithLibrime() {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.inputLanguages = [.chinese, .hindi, .english]
        c.setInputMode(.chinese)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        #expect(c.inputLanguage == .hindi)
        _ = type("ghar", c)
        #expect(c.markedText == "घर")
        #expect(engine.input.isEmpty)  // librime didn't get the letters
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 2)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 2.1)
        #expect(c.inputLanguage == .english)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 3)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 3.1)
        #expect(c.inputLanguage == .chinese)
        _ = type("nihao", c)
        #expect(engine.input == "nihao")
    }
}
