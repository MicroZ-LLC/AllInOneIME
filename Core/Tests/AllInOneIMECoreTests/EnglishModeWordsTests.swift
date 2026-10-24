import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The words typed in English mode, key by key (`EnglishModeWords`): which stand, and which are none.
struct EnglishModeWordsTests {
    static let backspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")
    static let forwardDelete = KeyEvent(keyCode: VirtualKey.forwardDelete, characters: "\u{F728}")
    static let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
    static let undo = KeyEvent(keyCode: 0x06, characters: "z", modifiers: .command)

    /// Follows keys in English mode, a second apart; `clicked`: the times the pointer was used.
    struct Typist {
        var words = EnglishModeWords()
        var time: TimeInterval = 100
        var clicked: [TimeInterval] = []
        var english = true
        /// The words that stood, in order.
        var stood: [String] = []

        func pointerUsed(since time: TimeInterval) -> Bool { clicked.contains { $0 > time } }

        mutating func press(_ key: KeyEvent) {
            time += 1
            let clicked = clicked
            stood += words.typed(key, english: english, at: time, pointerUsedSince: { t in clicked.contains { $0 > t } })
        }

        /// `text`, a key a character (" " the space bar, "\r" Return, "\t" Tab, "⌫" Backspace).
        mutating func type(_ text: String) {
            for character in text {
                switch character {
                case " ": press(FakeHost.space)
                case "\r": press(FakeHost.enter)
                case "\t": press(FakeHost.tab)
                case "⌫": press(EnglishModeWordsTests.backspace)
                default: press(KeyEvent(keyCode: 0, characters: String(character)))
                }
            }
        }

        mutating func click() {
            time += 1
            clicked.append(time)
        }

        mutating func inputMethodTook(inserting text: String?) {
            time += 1
            let clicked = clicked
            stood += words.inputMethodTook(inserting: text, at: time, pointerUsedSince: { t in clicked.contains { $0 > t } })
        }

        mutating func leftEnglish() {
            time += 1
            let clicked = clicked
            stood += words.leftEnglish(at: time, pointerUsedSince: { t in clicked.contains { $0 > t } })
        }

        mutating func leftField() { stood += words.leftField() }
    }

    /// What stands of `text` typed in English mode, then a key that leaves the last word as it is.
    func stood(_ text: String) -> [String] {
        var typist = Typist()
        typist.type(text)
        typist.type("x")
        return typist.stood
    }

    @Test func aWordIsTheLettersBetweenSpacesLinesAndMarksThatEndIt() {
        #expect(stood("frobnicate ") == ["frobnicate"])
        #expect(stood("frobnicate\r") == ["frobnicate"], "Return")
        #expect(stood("we frobnicate it ") == ["we", "frobnicate", "it"], "each word, its spelling as typed")
        #expect(stood("Frobnicate, zorblax. (quuxify) \"wibble\"! ") == ["Frobnicate", "zorblax", "quuxify", "wibble"])
        #expect(stood("frobnicate") == [], "no space or mark after it yet")
        #expect(stood("frobnicate,") == [], "a mark, nothing after it yet")
    }

    @Test func lettersWithADigitOrAnotherMarkAreNone() {
        for token in ["example.com", "user@host", "don't", "e-mail", "abc123", "123abc", "#tag", "foo_bar", "path/to",
                      "zorb(lax", "a.b.c", "café", "naïve", "frob…nicate", "$HOME", "~user", ".bashrc", "-flag"] {
            #expect(stood(token + " ") == [], "\(token)")
        }
        // The next word after the space is one again.
        #expect(stood("user@host frobnicate ") == ["frobnicate"])
        #expect(stood(String(repeating: "abcdefgh", count: 3) + "x ") == [], "longer than any learned")
    }

    @Test func anEditWhileTypingItOrRightAfterItIsNone() {
        #expect(stood("frobx⌫nicate ") == [], "⌫ in the word")
        #expect(stood("frobnicate ⌫") == [], "⌫ right after it: back into it")
        #expect(stood("frobnicate ⌫zorblax ") == [], "…and what follows goes on that word")
        var typist = Typist()
        typist.type("frobnicate ")
        typist.press(Self.forwardDelete)
        typist.type("zorblax ")
        typist.press(Self.undo)
        typist.type("quuxify ")
        typist.press(Self.left)
        typist.type("wibble wobble ")
        typist.type("x")
        #expect(typist.stood == ["wobble"], "⌦, ⌘Z, an arrow: the word before goes, the one typed next too")
    }

    @Test func aTabOrEscapeLeavesTheWordBeforeButNotTheOneTyped() {
        // ⇥ may take an editor's completion of "frobn".
        #expect(stood("zorblax frobn\t") == ["zorblax"])
        #expect(stood("frobn\tzorblax ") == [], "the letters after the completion go on its word")
    }

    @Test func aClickWhileTypingAWordOrAfterItDropsIt() {
        var typist = Typist()
        typist.type("frob")
        typist.click()
        typist.type("nicate ")
        typist.type("zorblax ")
        typist.click()
        typist.type("quuxify wibble ")
        typist.type("x")
        // The first word was typed in two places; the second may have been clicked into; the third was typed where the
        // caret may have been inside a word; the fourth stands.
        #expect(typist.stood == ["wibble"])
        // A click before the first letter: the caret may be inside a word.
        var after = Typist()
        after.type("zorblax ")
        after.type("x")
        after.click()
        after.type("y frobnicate ")
        after.type("x")
        #expect(after.stood == ["zorblax", "frobnicate"])
    }

    @Test func theFieldsFirstWordStartsWhereTheCaretIs() {
        // The click that gave the field the focus came before the first key: it counts as where a word may start.
        var typist = Typist()
        typist.click()
        typist.type("frobnicate ")
        typist.type("x")
        #expect(typist.stood == ["frobnicate"])
    }

    @Test func aTapOfShiftOutOfEnglishEndsAWordTypedAmongChinese() {
        var typist = Typist()
        typist.inputMethodTook(inserting: "我们用")
        typist.type("kubectlx")
        typist.leftEnglish()
        typist.english = false
        typist.inputMethodTook(inserting: nil)  // pinyin
        typist.inputMethodTook(inserting: "部署")
        #expect(typist.stood == ["kubectlx"])
        // ⌫ right after the tap: an edit.
        var edited = Typist()
        edited.type("kubectlx")
        edited.leftEnglish()
        edited.english = false
        edited.press(Self.backspace)
        edited.inputMethodTook(inserting: "部署")
        #expect(edited.stood == [])
    }

    @Test func whatTheInputMethodPutInTellsWhetherAWordMayStart() {
        // After Chinese, a space, a full-width mark: yes; after letters (a word picked), digits or a mark: no.
        for (before, word) in [("你好", true), ("好 ", true), ("，", true), ("「", true), ("Bedrock", false), ("2026", false),
                               ("v1.", false)] {
            var typist = Typist()
            typist.inputMethodTook(inserting: before)
            typist.type("zorblax ")
            typist.type("x")
            #expect(typist.stood == (word ? ["zorblax"] : []), "after \(before)")
        }
        // A key the input method took with nothing put in (a command started), then one that went on: the word before
        // stands.
        var typist = Typist()
        typist.type("zorblax ")
        typist.inputMethodTook(inserting: nil)
        #expect(typist.stood == ["zorblax"])
    }

    @Test func lettersOutsideEnglishModeAreNoWord() {
        var typist = Typist()
        typist.english = false
        typist.type("bonjour ")
        typist.type("x")
        #expect(typist.stood == [])
    }

    @Test func whenTheFieldLosesTheFocus() {
        // The word that ended stands (a click took the focus elsewhere), and one followed by marks; letters alone don't.
        var typist = Typist()
        typist.type("frobnicate\r")
        typist.click()
        typist.leftField()
        #expect(typist.stood == ["frobnicate"])
        var marks = Typist()
        marks.type("it frobnicates.")
        marks.leftField()
        #expect(marks.stood == ["it", "frobnicates"])
        var letters = Typist()
        letters.type("frobn")
        letters.leftField()
        #expect(letters.stood == [])
        // Then all is forgotten.
        letters.type("icate ")
        letters.type("x")
        #expect(letters.stood == ["icate"])
    }
}

/// Words typed in English mode learned by the session (`InputSession`), as letters put in as typed while typing pinyin
/// are: the same guards, the same second time; nothing in English mode changes.
@Suite(.serialized)
struct EnglishModeLearningTests {
    final class Learned: @unchecked Sendable { var words: [String] = [] }

    func host(_ config: Config = Self.settings, learned: Learned = Learned(), dictionary: Bool = true,
              secure: @escaping () -> Bool = { false }, pointerUsed: @escaping () -> Bool = { false },
              app: String? = "com.example.editor", terminal: Bool = false, services shared: SessionServices? = nil) -> FakeHost {
        var services = shared ?? SessionServices(loadSettings: { config })
        if shared == nil {
            services.levelOne = { .engine(FakeEngine()) }
            if dictionary { services.englishDictionary = { EnglishDictionary(["hello", "world", "it"]) } }
            services.learnEnglishWord = { learned.words.append($0) }
            services.secureInputActive = secure
            services.pointerUsedWithin = { _ in pointerUsed() }
        }
        let host = FakeHost(services: services)
        host.app = app
        host.terminal = terminal
        host.focus()
        return host
    }

    static var settings: Config {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        return config
    }

    func tapShift(_ host: FakeHost) {
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: 100))
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: 100.1))
    }

    /// Into English mode with a tap of Shift (unless it's in it).
    func english(_ host: FakeHost) {
        if host.composer.inputLanguage != .english { tapShift(host) }
        #expect(host.composer.inputLanguage == .english)
    }

    /// `text` typed, a key a character: Space, Return ("\r"), ⌫ ("⌫"); whether each went straight to the app.
    @discardableResult
    func type(_ text: String, _ host: FakeHost) -> [Bool] {
        text.map { character in
            switch character {
            case "\r": return !host.press(FakeHost.enter)
            case "⌫": return !host.press(EnglishModeWordsTests.backspace)
            case " ": return !host.press(FakeHost.space)
            default: return !host.press(KeyEvent(keyCode: 0, characters: String(character)))
            }
        }
    }

    func candidates(_ host: FakeHost) -> [String] { host.composer.engineState.candidates.map(\.text) }

    @Test func wordsTypedInEnglishModeAreLearnedTheSecondTimeAndOfferedAmongPinyinsCandidates() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            let host = host(learned: learned)
            english(host)
            let before = host.outputs.count
            // Nothing in English mode changes: each key goes straight to the app, nothing is marked, put in or shown.
            #expect(type("we zorblax it. ", host).allSatisfy { $0 })
            #expect(learned.words.isEmpty, "the first time only remembered")
            #expect(type("zorblax\r", host).allSatisfy { $0 })
            #expect(learned.words.isEmpty, "it stands once the next key leaves it as it is")
            #expect(type("ok", host).allSatisfy { $0 })
            #expect(learned.words == ["zorblax"])
            let shown = host.outputs.dropFirst(before).filter { output in
                switch output {
                case let .marked(text, _, _): return !text.isEmpty
                case .commit, .commitAfterKey, .replace, .typeOut: return true
                case let .panel(model): return model.map { !$0.rows.isEmpty } ?? false
                default: return false
                }
            }
            #expect(shown.isEmpty, "\(shown)")
            #expect(!host.composer.isComposing)
            // Among pinyin's candidates, in this field at once.
            tapShift(host)
            type("zorb", host)
            #expect(candidates(host).contains("zorblax"), "\(candidates(host))")
            // Words rime-ice has, pinyin, words too short aren't learned.
            host.press(FakeHost.escape)
            english(host)
            type("hello hello nihao nihao ab ab ok", host)
            #expect(learned.words == ["zorblax"])
        }
    }

    @Test func theSecondTimeIsTheSameAsTypingPinyin() async {
        await withInterfaceLanguage("en") {
            // Once in English mode, once put in as typed while typing pinyin (⏎): learned, in either order, in any field.
            let learned = Learned()
            var services = SessionServices(loadSettings: { Self.settings })
            services.levelOne = { .engine(FakeEngine()) }
            services.englishDictionary = { EnglishDictionary(["hello"]) }
            services.learnEnglishWord = { learned.words.append($0) }
            let mail = host(services: services)
            english(mail)
            type("quuxify ok", mail)
            let notes = host(app: "com.example.notes", services: services)
            notes.type("quuxify")
            notes.press(FakeHost.enter)
            #expect(learned.words == ["quuxify"])
            notes.type("frobnicate")
            notes.press(FakeHost.enter)
            type(" frobnicate ok", mail)
            #expect(learned.words == ["quuxify", "frobnicate"])
        }
    }

    @Test func anEditedWordIsNone() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            let host = host(learned: learned)
            english(host)
            // ⌫ in the word, or right after it, each time.
            type("zorblxa⌫⌫ax zorblxa⌫⌫ax ok", host)
            type(" zorblax ⌫ zorblax ⌫ ok", host)
            #expect(learned.words.isEmpty)
            type(" zorblax zorblax ok", host)
            #expect(learned.words == ["zorblax"], "typed as it is")
        }
    }

    @Test func aWordTypedAmongChineseEndsWithATapOfShift() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            let host = host(learned: learned)
            for _ in 0..<2 {
                type("nihao ", host)  // 你好
                tapShift(host)
                type("zorblax", host)
                tapShift(host)
                type("wo ", host)
            }
            #expect(learned.words == ["zorblax"])
        }
    }

    @Test func aWordWithACapitalFirstIsNeverLearnedNorRemembered() async {
        await withInterfaceLanguage("en") {
            // A name in prose ("Zorblax said"), or a sentence's first word.
            let learned = Learned()
            let host = host(learned: learned)
            english(host)
            type("Zorblax Zorblax ZORBLAX ok", host)
            #expect(learned.words.isEmpty)
            type(" zorblax ok", host)
            #expect(learned.words.isEmpty, "the capitalized ones didn't count as the first time")
            type(" zorblax ok", host)
            #expect(learned.words == ["zorblax"])
        }
    }

    @Test func neverInAPasswordFieldDuringSecureInputInAnAppWithNoAIOrWithLearningOff() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            // A password field: secure input on, as the shell tells it with each key.
            let field = host(learned: learned)
            english(field)
            field.secure = true
            #expect(type("zorblax zorblax ok", field).allSatisfy { $0 })
            field.secure = false
            // Secure input on elsewhere (a password prompt) when the word would stand.
            var secure = false
            let anywhere = host(learned: learned, secure: { secure })
            english(anywhere)
            type("zorblax zorblax", anywhere)
            secure = true
            type(" ok", anywhere)
            secure = false
            // The word before secure input came on, typed in a password field: forgotten.
            let before = host(learned: learned)
            english(before)
            type("zorblax zorblax ", before)
            before.secure = true
            type("x", before)
            before.secure = false
            type("ok", before)
            var noAI = Self.settings
            noAI.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            var off = Self.settings
            off.learnsEnglishWords = false
            for config in [noAI, off] {
                let host = host(config, learned: learned)
                english(host)
                type("zorblax zorblax ok", host)
            }
            #expect(learned.words.isEmpty)
        }
    }

    @Test func neverInATerminalAnSSHClientARemoteDesktopOrAVirtualMachine() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            let terminal = host(learned: learned, app: "com.googlecode.iterm2", terminal: true)
            english(terminal)
            type("zorblax zorblax ok", terminal)
            for app in ["com.termius-dmg.mac", "com.microsoft.rdc.macos", "com.parallels.desktop.console", "com.vmware.fusion"] {
                let remote = host(learned: learned, app: app)
                english(remote)
                type("zorblax zorblax ok", remote)
            }
            #expect(learned.words.isEmpty)
            let editor = host(learned: learned)
            english(editor)
            type("zorblax zorblax ok", editor)
            #expect(learned.words == ["zorblax"], "anywhere else")
        }
    }

    /// A password manager: a password shown in a plain field there, or typed before secure input comes on, is no word,
    /// as autocomplete never runs there (`PasswordManagers`).
    @Test func neverInAPasswordManager() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            for app in ["com.1password.1password", "com.agilebits.onepassword7", "com.apple.Passwords", "com.bitwarden.desktop",
                        "org.keepassxc.keepassxc"] {
                let manager = host(learned: learned, app: app)
                english(manager)
                type("zorblax zorblax ok", manager)
            }
            #expect(learned.words.isEmpty)
            let editor = host(learned: learned)
            english(editor)
            type("zorblax zorblax ok", editor)
            #expect(learned.words == ["zorblax"], "anywhere else")
        }
    }

    @Test func neverWhatLooksLikeASecretOrHoldsAHiddenWord() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            var config = Self.settings
            config.redaction.customWords = ["phoenix"]
            let host = host(config, learned: learned)
            english(host)
            for secret in ["qwrtzpsdf", "aaargh", "phoenixapi", "xoBuKiVaZeNu", "hTqeWobAsuKelPimRaVo"] {
                type("\(secret) \(secret) ok ", host)
            }
            #expect(learned.words.isEmpty)
        }
    }

    @Test func aClickWhileTypingDropsTheWord() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            var clicked = false
            let host = host(learned: learned, pointerUsed: { clicked })
            english(host)
            type("zorbl", host)
            clicked = true
            type("ax ", host)
            clicked = false
            type("zorblax ok", host)
            #expect(learned.words.isEmpty, "the first one was typed where a click may have moved the caret")
        }
    }

    @Test func theLastWordStandsWhenTheFieldLosesTheFocus() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            let host = host(learned: learned)
            english(host)
            type("zorblax\r", host)
            host.send(.blur)
            host.focus()
            english(host)
            type("zorblax.", host)
            host.send(.blur)
            #expect(learned.words == ["zorblax"])
        }
    }

    @Test func noneWithoutRimeIcesDictionary() async {
        await withInterfaceLanguage("en") {
            let learned = Learned()
            let host = host(learned: learned, dictionary: false)
            english(host)
            type("zorblax zorblax ok", host)
            #expect(learned.words.isEmpty)
        }
    }
}
