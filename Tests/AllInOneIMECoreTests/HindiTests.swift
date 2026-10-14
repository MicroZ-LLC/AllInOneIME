import Testing
@testable import AllInOneIMECore

struct HindiTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    @Test func transliteratesByRule() {
        #expect(HindiTransliteration(tables: PackData.hindi).transliterate("namaste", clusters: true) == "नमस्ते")
        #expect(HindiTransliteration(tables: PackData.hindi).transliterate("bhaarat", clusters: true) == "भारत")
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("bharat").first == "भारत")  // from the word list
        #expect(HindiTransliteration(tables: PackData.hindi).transliterate("kamra", clusters: false) == "कमरा")
        #expect(HindiTransliteration(tables: PackData.hindi).transliterate("pyaar", clusters: true) == "प्यार")
        #expect(HindiTransliteration(tables: PackData.hindi).transliterate("aam", clusters: true) == "आम")
        #expect(HindiTransliteration(tables: PackData.hindi).transliterate("ghar", clusters: true) == "घर")
        // Capitals inside a word are the retroflex letters.
        #expect(HindiTransliteration(tables: PackData.hindi).transliterate("TamaaTar", clusters: true) == "टमाटर")
    }

    @Test func commonWordsComeFirstSpelledAsHindiWritesThem() {
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("karna").first == "करना")
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("nahi").first == "नहीं")
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("main").first == "मैं")
        // A capital starting a sentence is the word, not a retroflex letter.
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("Main").first == "मैं")
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("Kamal").first == "कमल")
        // Words with a cluster offer both spellings.
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("kamra").contains("कमरा"))
        #expect(HindiTransliteration(tables: PackData.hindi).candidates("kamra").contains("कम्रा"))
    }

    func hindi() -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hindiTables = PackData.hindi
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

    @Test func withoutThePackHindiIsNoInputMode() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.hindi)
        #expect(c.inputLanguage == .chinese)
        c.hindiTables = PackData.hindi
        c.setInputMode(.hindi)
        #expect(c.inputLanguage == .hindi)
        c.hindiTables = nil  // the pack deleted
        #expect(c.inputLanguage == .chinese)
    }

    /// Without the Chinese pack level one is `LatinEngine`; in Hindi `engine` is Hindi's. The controller asks
    /// `primaryEngine` whether it still has to put a `LatinEngine` in (and go back to the default language).
    @Test func hindiWithoutTheChinesePack() {
        let c = Composer(engine: LatinEngine(), actionKey: .enter)
        c.hindiTables = PackData.hindi
        c.inputLanguages = [.english, .hindi]
        c.setInputMode(.english)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        #expect(c.inputLanguage == .hindi)
        #expect(c.engine is HindiEngine)
        #expect(c.primaryEngine is LatinEngine)
        var resets = 0
        for letter in "namaste" {
            // `ensureEngine` before each key.
            if !(c.primaryEngine is LatinEngine) {
                c.engine = LatinEngine()
                c.setInputMode(.english)
                resets += 1
            }
            _ = c.handleKeyDown(k(String(letter)))
        }
        #expect(resets == 0)
        #expect(c.markedText == "नमस्ते")
    }

    @Test func removingThePackFallsBackToAnInputLanguage() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hindiTables = PackData.hindi
        c.inputLanguages = [.english, .korean, .hindi]
        c.setInputMode(.hindi)
        c.hindiTables = nil
        #expect(c.inputLanguage == .english)  // not Chinese, which isn't one of them
    }

    /// `@open` from Hindi types English letters, and Hindi comes back after it.
    @Test func aCommandsLettersAreEnglishInHindi() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hangulTables = PackData.hangul
        c.hindiTables = PackData.hindi
        c.inputLanguages = [.english, .korean, .hindi]
        c.setInputMode(.korean)  // the Latin language typed last
        c.setInputMode(.hindi)
        _ = c.handleKeyDown(at)
        _ = type("ope", c)
        _ = c.handleKeyDown(tab)
        #expect(c.inputLanguage == .english)
        _ = type("doc", c)
        #expect(c.draft == "@open doc")
        _ = c.handleKeyDown(escKey)
        #expect(c.inputLanguage == .hindi)
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
        c.hindiTables = PackData.hindi
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
