import Foundation
import Testing
@testable import AllInOneIMECore

/// "@" typed right after a word is text (an email address, `ssh user@host`), in every app, terminals too; elsewhere it opens
/// the command list, and a key that leaves the list leaves the "@…" as typed, also in a terminal, which doesn't act on a
/// key after text inserted during it (`Composer.appTakesKeysAfterInsert`).
struct AtSignTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
    let right = KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}")
    let home = KeyEvent(keyCode: VirtualKey.home, characters: "\u{F729}")
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    /// A composer in English (`english`) or Chinese, in a text view or a terminal (`terminal`), with what the field
    /// has before the caret (`before`).
    func composer(english: Bool = true, terminal: Bool = false, before: Character? = nil) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.commands = Command.catalog([])
        c.horizontalCandidates = true  // the default layout
        c.appTakesKeysAfterInsert = !terminal
        c.characterBeforeCaret = { before }
        if english { c.setInputMode(.english) }
        return (c, engine)
    }

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(k(String(ch))) }
    }

    /// A text field typed into as the input controller does: what the composer inserts and the keys it lets through
    /// reach it, what is inserted after a key too, and `LastTyped` keeps the last character typed for the next "@".
    final class Field {
        let composer: Composer
        var text = ""
        var typed = LastTyped()

        init(_ composer: Composer) {
            self.composer = composer
            composer.characterBeforeCaret = { [unowned self] in self.typed.character }
        }

        @discardableResult
        func press(_ key: KeyEvent) -> Composer.Response {
            let response = composer.handleKeyDown(key)
            let inserted = commits(response).last
            text += commits(response).joined()
            if !response.handled { text += key.printableText ?? "" }
            typed.answered(key, passedOn: !response.handled, inserted: inserted, at: 0)
            for case let .commitAfterKey(s) in response.effects {
                text += s
                typed.forget()
            }
            return response
        }

        /// The keys of `text`, as a US layout types them.
        func type(_ text: String) {
            for ch in text {
                switch ch {
                case "@": press(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
                case " ": press(spaceKey)
                default: press(k(String(ch)))
                }
            }
        }
    }

    // MARK: - "@" after a word

    @Test func anAtRightAfterAWordIsText() {
        for english in [true, false] {
            for before: Character in ["z", "Q", "7", ".", "_", "-"] {
                let (c, _) = composer(english: english, before: before)
                let r = c.handleKeyDown(at)
                #expect(r == .passThrough && c.draft.isEmpty && c.markedText.isEmpty && !c.isComposing,
                        "\(before)@ in \(english ? "English" : "Chinese")")
            }
        }
    }

    @Test func elsewhereAnAtOpensTheList() {
        for english in [true, false] {
            for before: Character? in [nil, " ", "\n", "好", "(", ":", "，"] {
                let (c, _) = composer(english: english, before: before)
                let r = c.handleKeyDown(at)
                #expect(r.handled && c.draft == "@" && !c.paletteMatches.isEmpty, "\(before.map(String.init) ?? "nothing")@")
            }
        }
    }

    @Test func anAddressTypesThroughInATerminal() {
        // `ssh xyz@123.1769` and an email, in English, in a terminal: every key reaches it as typed, nothing is marked.
        for text in ["ssh xyz@123.1769", "mail bob.smith@example.com", "scp a_b@host-1:/tmp", "git clone git@github.com"] {
            let field = Field(composer(terminal: true).0)
            field.type(text)
            #expect(field.text == text && !field.composer.isComposing && field.composer.markedText.isEmpty)
        }
        // After a space the list opens, as before.
        let field = Field(composer(terminal: true).0)
        field.type("echo @")
        #expect(field.text == "echo " && field.composer.draft == "@" && !field.composer.paletteMatches.isEmpty)
        // So does "@" right after text the input method inserted (a result, a command as typed with ⇧⏎): no word typed.
        let after = Field(composer().0)
        after.type("@im")
        after.press(tab)
        after.type("hi")
        after.press(KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift))
        after.type("@")
        #expect(after.text == "@improve hi" && after.composer.draft == "@")
    }

    @Test func onlyWhatIsTypedCounts() {
        var typed = LastTyped()
        typed.answered(k("z"), passedOn: true, inserted: nil, at: 1)
        #expect(typed.character == "z" && typed.time == 1)
        // Taken with nothing inserted (pinyin, a move in the list): the field is as it was.
        typed.answered(k("n"), passedOn: false, inserted: nil, at: 2)
        #expect(typed.character == "z" && typed.time == 1)
        // What the input method inserts for a key: typed when it ends with the key's character ("@x" leaving the list in
        // a terminal, "@ "), else a result or a conversion (Space picking 你好, ⏎ inserting "391" or "bob").
        typed.answered(k("x"), passedOn: false, inserted: "@x", at: 3)
        #expect(typed.character == "x")
        typed.answered(spaceKey, passedOn: false, inserted: "@ ", at: 3)
        #expect(typed.character == " ")
        for (key, inserted) in [(spaceKey, "你好"), (enterKey, "391"), (enterKey, "bob"), (k("2"), "拟好")] {
            typed.answered(k("z"), passedOn: true, inserted: nil, at: 4)
            typed.answered(key, passedOn: false, inserted: inserted, at: 4)
            #expect(typed.character == nil, "\(inserted)")
        }
        // A key that goes on without a character (it may move the caret, or edit): not known.
        for key in [right, left, home, tab, enterKey, backspaceKey, escKey, upKey, k("v", mods: .command), k("a", mods: .control)] {
            typed.answered(k("z"), passedOn: true, inserted: nil, at: 5)
            typed.answered(key, passedOn: true, inserted: nil, at: 6)
            #expect(typed.character == nil, "\(key.keyCode)")
        }
        // "@" then . in a text view: the "@" inserted, the "." typed by the app.
        typed.answered(k("."), passedOn: true, inserted: "@", at: 7)
        #expect(typed.character == ".")
        typed.forget()
        #expect(typed.character == nil)
        // Typing: an arrow after "xyz" (the cursor moved, maybe a shell's history) and the "@" opens the list again.
        let field = Field(composer(terminal: true).0)
        field.type("xyz")
        #expect(!field.press(left).handled && field.typed.character == nil)
        field.type("@")
        #expect(field.text == "xyz" && field.composer.draft == "@")
    }

    // MARK: - ← → on the "@"

    @Test func arrowsOnABareAtInATextView() {
        // The "@" goes in and the key acts in the app (the caret moves on), as before; the list is gone.
        for arrow in [right, left] {
            let (c, _) = composer()
            _ = c.handleKeyDown(at)
            let r = c.handleKeyDown(arrow)
            #expect(r == Composer.Response(effects: [.hidePanel, .commit("@")], handled: false) && c.draft.isEmpty && !c.isComposing)
        }
        // A command name being typed too: "@im" as typed.
        let (c, _) = composer()
        _ = c.handleKeyDown(at)
        type("im", c)
        #expect(c.paletteQuery == "im")
        let r = c.handleKeyDown(right)
        #expect(commits(r) == ["@im"] && !r.handled && c.draft.isEmpty)
    }

    @Test func arrowsOnABareAtInATerminal() {
        // The terminal gets nothing for the key (text was marked before it); the "@" goes in once the key is done.
        for english in [true, false] {
            for arrow in [right, left, home] {
                let (c, _) = composer(english: english, terminal: true)
                _ = c.handleKeyDown(at)
                #expect(c.markedText == "@")
                let r = c.handleKeyDown(arrow)
                #expect(r == .consumed([.hidePanel, .updateMarkedText, .commitAfterKey("@")]), "\(arrow.keyCode)")
                #expect(c.draft.isEmpty && c.markedText.isEmpty && !c.isComposing)
            }
        }
        let (c, _) = composer(terminal: true)
        _ = c.handleKeyDown(at)
        type("im", c)
        #expect(c.handleKeyDown(right) == .consumed([.hidePanel, .updateMarkedText, .commitAfterKey("@im")]))
        // Typed into a field: "@", → and on: the "@" stays, what's typed next follows it.
        let field = Field(composer(terminal: true).0)
        field.type("@")
        field.press(right)
        field.type("123.1769")
        #expect(field.text == "@123.1769" && !field.composer.isComposing)
    }

    @Test func sideBySideCandidatesStillTakeTheArrows() {
        // Pinyin in a command's text, candidates in a row: ← → choose there, in a terminal too.
        let (c, e) = composer(english: false, terminal: true)
        _ = c.handleKeyDown(at)
        type("im", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@improve ")
        type("nihao", c)
        let r = c.handleKeyDown(right)
        #expect(r == .consumed([.updateMarkedText, .showPanel]) && c.engineState.highlighted == 1 && c.draft == "@improve ")
        #expect(c.handleKeyDown(left).handled && e.keys.last?.keycode == RimeKey.up)  // the previous one
    }

    // MARK: - Other keys after "@"

    @Test func whatCantBeACommandNameLeavesTheListAsTyped() {
        // "." ":" "/" "-", Space, a digit that numbers no row shown: in a text view the "@" goes in, then the key types.
        for key in [".", ":", "/", "-", " ", "0", "6", "9"] {
            let (c, _) = composer()
            _ = c.handleKeyDown(at)
            let r = c.handleKeyDown(key == " " ? spaceKey : k(key))
            #expect(commits(r) == ["@"] && !r.handled && c.draft.isEmpty && !c.isComposing, "@\(key)")
        }
        // In a terminal the key's character goes in with it.
        for key in [".", ":", "/", "-", " ", "0", "6", "9"] {
            let (c, _) = composer(terminal: true)
            _ = c.handleKeyDown(at)
            let r = c.handleKeyDown(key == " " ? spaceKey : k(key))
            #expect(r == .consumed([.hidePanel, .commit("@" + key)]) && c.draft.isEmpty && !c.isComposing, "@\(key)")
        }
        // A letter no command has: the "@" and the letter, in a terminal too.
        let field = Field(composer(terminal: true).0)
        field.type("@x@123.1769")
        #expect(field.text == "@x@123.1769" && !field.composer.isComposing)
    }

    @Test func aDigitStillPicksARowShown() {
        // As the README says: "@" then 1–5 picks from the five rows shown (the most used first).
        let (c, _) = composer(terminal: true)
        _ = c.handleKeyDown(at)
        let shown = c.paletteVisible.map(\.name)
        #expect(shown.count == Composer.paletteRows)
        _ = c.handleKeyDown(k("2"))
        #expect(c.draft == "@\(shown[1]) ")
    }

    @Test func chinesePunctuationAfterTheAtIsTheEngines() {
        // In Chinese mode the engine types "," as "，", in the same key: the "@" and the comma both go in.
        let (c, _) = composer(english: false, terminal: true)
        _ = c.handleKeyDown(at)
        let r = c.handleKeyDown(k(","))
        #expect(commits(r) == ["@", "，"] && r.handled && !c.isComposing)
    }
}
