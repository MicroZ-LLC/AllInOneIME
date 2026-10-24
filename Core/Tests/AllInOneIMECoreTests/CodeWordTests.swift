import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Code holds the word being typed as marked text (decision 33), as the command list holds what is typed after its
/// trigger: Chromium's pages and Electron's apps (Google Docs, Slack, VS Code) hand a key the input method took to the page
/// too when nothing is marked before or after it, and ↑ on Code's rows moved their caret as well. The word's characters
/// are marked text and the rows follow it; ↑↓ move the chosen row with it still marked; Tab and Return put the chosen row
/// in its place; → and Esc put it in as typed and hide the rows; any other key puts it in as typed, then is the app's;
/// ⌫ takes its last character back; another field, a click, the app's commit and a tap of Shift put it in as typed.
/// Where Code's rows may not show (a terminal, secure input, a password field, an app with none, the switches off) its
/// letters go straight in as before. The rig: Acceptance/SuggestionsAcceptanceTests.swift (`addCode`, `codeField`).
@Suite(.serialized, SuggestionsOneAtATime())
struct CodeWordTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// A world with the Code input in Python, the tests' pack its only one (keywords, `print($0)`, `def`, `if`, `class`).
    static func coding() throws -> SuggestionsWorld {
        let world = SuggestionsWorld()
        world.addCode("python", packs: [try SuggestionsCodingAcceptanceTests.pack("python")])
        return world
    }

    /// The rows' texts.
    static func texts(_ field: SuggestionsField) -> [String] { field.rows.map(\.text) }

    /// What the session put in since output `start`.
    static func committed(_ field: SuggestionsField, since start: Int = 0) -> [String] {
        field.host.outputs.dropFirst(start).compactMap { if case let .commit(text) = $0 { text } else { nil } }
    }

    static let commandS = KeyEvent(keyCode: 0x01, characters: "s", charactersIgnoringModifiers: "s", modifiers: .command)

    // MARK: - Held

    /// Each character of the word is the input method's, marked as typed (not converted) with the caret at its end, and
    /// nothing goes into the field; the rows follow it. Capitals, digits and "_" go on with it.
    @Test func theWordIsHeldAsMarkedTextAndTheRowsFollowIt() async throws {
        try await inEnglish {
            let field = try Self.coding().codeField()
            for letter in "pri" { #expect(field.press(SuggestionKeys.key(letter)), "\(letter): the input method's") }
            #expect(field.host.marked == "pri" && field.document.isEmpty, "\(field)")
            #expect(field.settle { Self.texts(field) == ["print"] }, "\(field)")
            let marks = field.host.outputs.compactMap { output -> String? in
                if case let .marked(text, cursor, converted) = output { return "\(text) \(cursor) \(converted)" } else { return nil }
            }
            #expect(marks == ["p 1 false", "pr 2 false", "pri 3 false"], "\(marks)")
            #expect(Self.committed(field).isEmpty)
            field.type("nt_A2")
            #expect(field.host.marked == "print_A2" && field.document.isEmpty && field.rows.isEmpty, "\(field)")
        }
    }

    /// A word starts with a letter or "_", as an identifier does: a number, and a plugin's "#123", go straight in as before.
    @Test func aDigitGoesOnWithAWordButStartsNone() async throws {
        try await inEnglish {
            let field = try Self.coding().codeField()
            field.type("x1")
            #expect(field.host.marked == "x1" && field.document.isEmpty, "\(field)")
            #expect(!field.press(SuggestionKeys.space) && field.document == "x1 ")
            #expect(!field.press(SuggestionKeys.digit(4)) && !field.press(SuggestionKeys.space))
            for character in "#12" { #expect(!field.press(SuggestionKeys.key(character)), "\(character): the app's") }
            #expect(field.document == "x1 4 #12" && field.host.marked.isEmpty, "\(field)")
            field.type(" _x")
            #expect(field.host.marked == "_x", "\(field)")
        }
    }

    // MARK: - The rows' keys

    /// ↓ and ↑ move the chosen row (the first chosen from the start) and are the input method's, the word still marked:
    /// with marked text there, the page never has them too. Return then puts the row chosen in.
    @Test func upAndDownMoveTheChosenRowWithTheWordStillMarked() async throws {
        try await inEnglish {
            let field = try Self.coding().codeField()
            field.type("de")
            #expect(field.settle { field.rows.map(\.comment) == ["function", "keyword"] }, "\(field)")
            #expect(field.host.panel?.highlighted == 0, "the first row chosen from the start")
            #expect(field.press(SuggestionKeys.down) && field.host.panel?.highlighted == 1)
            #expect(field.host.marked == "de" && field.document.isEmpty, "\(field)")
            #expect(field.press(SuggestionKeys.up) && field.host.panel?.highlighted == 0 && field.host.marked == "de")
            #expect(field.press(SuggestionKeys.down) && field.press(SuggestionKeys.enter))
            #expect(field.document == "def" && field.host.marked.isEmpty && field.rows.isEmpty, "the keyword chosen: \(field)")
        }
    }

    /// Tab and Return put the chosen row in, in one piece in place of the word held, the snippet's caret where it goes
    /// (`print($0)`: between its parentheses); its later lines get the caret's line's indentation, the word on that line
    /// not in the field yet.
    @Test func tabAndReturnPutTheChosenRowInInPlaceOfTheWord() async throws {
        try await inEnglish {
            let field = try Self.coding().codeField()
            field.type("pr")
            #expect(field.settle { Self.texts(field) == ["print"] }, "\(field)")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "print()" && field.host.marked.isEmpty && field.rows.isEmpty, "\(field)")
            #expect(Self.committed(field, since: before) == ["print()"], "\(Self.committed(field, since: before))")
            let moves = field.host.outputs.dropFirst(before).compactMap { output -> String? in
                if case let .moveCaret(back, after) = output { return "\(back) \(after ?? "")" } else { return nil }
            }
            #expect(moves == ["1 print()"], "\(moves)")

            let indented = try Self.coding().codeField()
            indented.host.document = "class A:\n    "
            indented.type("de")
            #expect(indented.settle { indented.rows.first?.comment == "function" }, "\(indented)")
            #expect(indented.press(SuggestionKeys.enter))
            #expect(indented.document == "class A:\n    def ():\n        " && indented.host.marked.isEmpty,
                    "\(indented.document.debugDescription)")
        }
    }

    /// After a mark the token goes on (`x.`), and the word held is what comes after it: the row puts in what the word
    /// lacks, after what is in the field.
    @Test func afterAMarkTheWordIsWhatFollowsIt() async throws {
        try await inEnglish {
            let field = try Self.coding().codeField()
            field.type("x.con")
            #expect(field.document == "x." && field.host.marked == "con", "\(field)")
            #expect(field.settle { Self.texts(field) == ["continue"] }, "\(field)")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "x.continue", "\(field)")
        }
    }

    /// Code's words read from the field while a word is held: the field's own (the held word isn't in it yet, or, where
    /// the field tells its marked text with it, is the word at the caret, left out), its rows putting in what the word
    /// lacks.
    @Test func theFieldsWordsWhileAWordIsHeld() async throws {
        try await inEnglish {
            #expect(CodingRows.words(FieldText(before: "counter = 1\ncount", after: "")) == ["counter"])
            let field = try Self.coding().codeField()
            field.host.document = "counter = 1\n"
            field.type("cou")
            field.pause(1)
            #expect(field.host.fieldReads == 1 && field.host.marked == "cou", "\(field)")
            #expect(field.settle { Self.texts(field) == ["counter"] }, "\(field)")
            #expect(field.press(SuggestionKeys.tab) && field.document == "counter = 1\ncounter", "\(field)")
        }
    }

    /// → and Esc put the word in as typed and hide the rows; the next → or Esc is the app's. Typed on from there, the word
    /// held is what follows, and the rows for the token put in what it lacks.
    @Test func rightAndEscPutTheWordInAsTypedAndHideTheRows() async throws {
        try await inEnglish {
            for key in [SuggestionKeys.right, SuggestionKeys.escape] {
                let field = try Self.coding().codeField()
                field.type("pr")
                #expect(field.settle { !field.rows.isEmpty }, "\(field)")
                #expect(field.press(key), "\(key.key): the rows'")
                #expect(field.document == "pr" && field.host.marked.isEmpty && field.rows.isEmpty, "\(key.key): \(field)")
                #expect(!field.press(key), "\(key.key): the next is the app's")

                let on = try Self.coding().codeField()
                on.type("pr")
                #expect(on.settle { !on.rows.isEmpty } && on.press(key))
                on.type("i")
                #expect(on.document == "pr" && on.host.marked == "i", "\(key.key): \(on)")
                #expect(on.settle { Self.texts(on) == ["print"] }, "\(key.key): \(on)")
                #expect(on.press(SuggestionKeys.tab) && on.document == "print()", "\(key.key): \(on)")
            }
        }
    }

    /// The command trigger right after the word is text, as after a word typed straight in ("user@host"): the word goes
    /// in, then the trigger, no command list; after the word Esc put in from its rows too.
    @Test func theTriggerRightAfterTheWordIsText() async throws {
        try await inEnglish {
            let field = try Self.coding().codeField()
            field.type("user")
            #expect(!field.press(FakeHost.at) && field.document == "user@" && !field.host.composer.isComposing, "\(field)")

            let escaped = try Self.coding().codeField()
            escaped.type("pr")
            #expect(escaped.settle { !escaped.rows.isEmpty } && escaped.press(SuggestionKeys.escape))
            #expect(!escaped.press(FakeHost.at) && escaped.document == "pr@" && !escaped.host.composer.isComposing, "\(escaped)")
        }
    }

    // MARK: - Ending the word

    /// Any other key puts the word in as typed, then is the app's, exactly as with nothing held: a space, marks, brackets
    /// and quotes (the editor closes them), an arrow, Home, Return and Tab where no row is chosen (the editor indents), a
    /// shortcut. One insert each, before the key.
    @Test func aKeyThatEndsTheWordPutsItInThenIsTheApps() async throws {
        try await inEnglish {
            let keys: [(KeyEvent, String)] = [
                (SuggestionKeys.space, " "), (SuggestionKeys.key("."), "."), (SuggestionKeys.key("("), "("),
                (SuggestionKeys.key("\""), "\""), (SuggestionKeys.key(":"), ":"), (SuggestionKeys.key("-"), "-"),
                (SuggestionKeys.up, ""), (SuggestionKeys.down, ""), (SuggestionKeys.left, ""), (SuggestionKeys.home, ""),
                (SuggestionKeys.enter, ""), (SuggestionKeys.tab, ""), (SuggestionKeys.shiftTab, ""), (Self.commandS, ""),
            ]
            for (key, typed) in keys {
                let field = try Self.coding().codeField()
                field.type("xq")
                #expect(field.host.marked == "xq" && field.rows.isEmpty, "no rows for it: \(field)")
                let before = field.host.outputs.count
                #expect(!field.press(key), "\(key.key) \(key.characters.debugDescription): the app's")
                #expect(Self.committed(field, since: before) == ["xq"] && field.document == "xq" + typed && field.host.marked.isEmpty,
                        "\(key.key) \(key.characters.debugDescription): \(field)")
            }
            // With rows up: a mark ends the word and the token, the rows go.
            let field = try Self.coding().codeField()
            field.type("pr")
            #expect(field.settle { !field.rows.isEmpty })
            #expect(!field.press(SuggestionKeys.key("(")) && field.document == "pr(" && field.rows.isEmpty, "\(field)")
        }
    }

    /// ⌫ takes the word's last character back, the rows following; with none left nothing is held, and the next ⌫ is the
    /// app's. Nothing went into the field.
    @Test func backspaceTakesTheWordsLastCharacterBack() async throws {
        try await inEnglish {
            let field = try Self.coding().codeField()
            field.host.document = "a = "
            field.type("pri")
            #expect(field.settle { Self.texts(field) == ["print"] }, "\(field)")
            #expect(field.press(SuggestionKeys.backspace) && field.host.marked == "pr", "\(field)")
            #expect(field.settle { Self.texts(field) == ["print"] }, "the rows for what is held: \(field)")
            #expect(field.press(SuggestionKeys.backspace) && field.host.marked == "p" && field.rows.isEmpty, "\(field)")
            #expect(field.press(SuggestionKeys.backspace) && field.host.marked.isEmpty && !field.host.composer.isComposing, "\(field)")
            #expect(!field.press(SuggestionKeys.backspace), "the next ⌫ is the app's")
            #expect(Self.committed(field).isEmpty && field.document == "a = ", "\(field)")
        }
    }

    /// Another field (another app), a click in the field (the app's commit), a tap of Shift out of Code, Code removed:
    /// the word goes in as typed, nothing lost, and Code's rows go.
    @Test func theWordGoesInAsTypedWhenTheFieldIsLeft() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let left = world.codeField()
            left.type("pri")
            let before = left.host.outputs.count
            left.host.send(.blur)
            #expect(Self.committed(left, since: before) == ["pri"] && left.document == "pri" && left.host.marked.isEmpty, "\(left)")

            let clicked = world.codeField()
            clicked.type("pri")
            #expect(clicked.settle { !clicked.rows.isEmpty })
            clicked.host.send(.commit)
            #expect(clicked.document == "pri" && clicked.host.marked.isEmpty && clicked.rows.isEmpty, "\(clicked)")

            let shifted = world.codeField()
            shifted.type("pr")
            #expect(shifted.settle { !shifted.rows.isEmpty })
            shifted.tapShift()
            #expect(shifted.host.composer.input != .code, "\(shifted.host.composer.input)")
            #expect(shifted.document == "pr" && shifted.host.marked.isEmpty && shifted.rows.isEmpty, "\(shifted)")
            #expect(!shifted.press(SuggestionKeys.up), "no rows left behind: ↑ is the app's")

            let removed = world.codeField()
            removed.type("pri")
            world.config.codingLanguage = nil
            removed.host.send(.configChanged)
            #expect(removed.document == "pri" && removed.host.marked.isEmpty && !removed.host.composer.coding, "\(removed)")
        }
    }

    /// Secure input coming on (in the field's app, or anywhere) puts the word in as typed; nothing is held while it's on.
    @Test func secureInputPutsTheWordIn() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("pri")
            field.host.secure = true
            #expect(!field.press(SuggestionKeys.key("n")) && !field.press(SuggestionKeys.key("t")))
            #expect(field.document == "print" && field.host.marked.isEmpty, "\(field)")

            let anywhere = world.codeField()
            anywhere.type("pri")
            world.secureInputAnywhere = true
            #expect(!anywhere.press(SuggestionKeys.key("n")) && !anywhere.press(SuggestionKeys.key("t")))
            #expect(anywhere.document == "print" && anywhere.host.marked.isEmpty, "\(anywhere)")
        }
    }

    // MARK: - Where it holds none

    /// Where Code's rows may not show its letters go straight in, as before: a terminal, a password field (told by the
    /// field, secure input off), secure input, an app with no rows (a remote desktop), Suggestions off in the app.
    @Test func whereRowsMayNotShowTheLettersGoStraightIn() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let terminal = world.codeField(terminal: true)
            for letter in "pr" { #expect(!terminal.press(SuggestionKeys.key(letter)), "a terminal: \(letter)") }
            #expect(terminal.document == "pr" && terminal.host.marked.isEmpty, "\(terminal)")

            let password = world.codeField(app: "com.apple.TextEdit")
            var context = password.host.context
            context.field = FieldInfo(app: "com.apple.TextEdit", terminal: false, secure: true)
            password.host.send(.key(SuggestionKeys.key("p"), context))
            #expect(password.host.marked.isEmpty && !password.host.composer.isComposing, "a password field: \(password)")

            world.config.changeProfile(for: SuggestionsApps.weChat) { $0.startingInput = .code }
            let secure = world.field(app: SuggestionsApps.weChat, passwordField: true)
            #expect(secure.host.composer.input == .code)
            for letter in "pr" { #expect(!secure.press(SuggestionKeys.key(letter)), "secure input: \(letter)") }
            #expect(secure.document == "pr" && secure.host.marked.isEmpty, "\(secure)")

            let remote = world.codeField(app: SuggestionsApps.remoteDesktop)
            for letter in "pr" { #expect(!remote.press(SuggestionKeys.key(letter)), "a remote desktop: \(letter)") }
            #expect(remote.document == "pr" && remote.host.marked.isEmpty, "\(remote)")

            world.switches.apps[SuggestionsApps.editor] = false
            let off = world.codeField()
            for letter in "pr" { #expect(!off.press(SuggestionKeys.key(letter)), "Suggestions off: \(letter)") }
            #expect(off.document == "pr" && off.host.marked.isEmpty, "\(off)")
        }
    }

    /// The languages type as before: English's letters straight in, pinyin composed.
    @Test func theLanguagesTypeAsBefore() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let english = world.field()
            #expect(english.host.composer.input == .language(.english))
            for letter in "pr" { #expect(!english.press(SuggestionKeys.key(letter))) }
            #expect(english.document == "pr" && english.host.marked.isEmpty, "\(english)")
        }
    }

    /// A composer on its own holds no word (its session says where Code holds one): Code's letters go to the app; told it
    /// holds one, a letter starts it, marked.
    @Test func aComposerOnItsOwnHoldsNone() {
        let composer = Composer(engine: LatinEngine())
        composer.hasCode = true
        composer.setInput(.code)
        #expect(composer.coding)
        let p = KeyEvent(keyCode: 0x23, characters: "p")
        #expect(!composer.handleKeyDown(p).handled && composer.codeWord == nil && !composer.isComposing)
        composer.holdsCodeWord = { true }
        let held = composer.handleKeyDown(p)
        #expect(held == .consumed([.updateMarkedText]) && composer.codeWord == "p" && composer.markedText == "p")
        #expect(!composer.wantsPanel, "no panel of the composer's: the rows are the session's")
        #expect(composer.commitAll().contains(.commit("p")) && composer.codeWord == nil && !composer.isComposing)
    }
}
