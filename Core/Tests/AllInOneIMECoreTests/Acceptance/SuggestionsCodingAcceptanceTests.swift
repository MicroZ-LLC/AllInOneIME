import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, spec 2: coding mode (the chooser a long press of Shift opens, the session's: spec 6.2; on across
/// fields and apps, English first in each field, exclusive with Translate as You Type) and its sources: the coding
/// language packs' keywords and snippets (Fixtures/Suggestions/packs/; what is offered: spec 6.13), the words of the
/// field's own text (none where it tells none: 6.16); the keys and insertion of spec 1.4 (rows picked with Tab, or ↓ and
/// Return, never a digit: 6.1; code editors as terminals: 6.10, 6.11), a snippet's line breaks and its `$0`. The rig:
/// SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsCodingAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) rethrows { try withInterfaceLanguage("en", body) }

    static func pack(_ name: String) throws -> CodingLanguagePack {
        try JSONDecoder().decode(CodingLanguagePack.self, from: SuggestionsFixtures.data(name, in: "packs"))
    }

    /// A world in coding mode with the Python pack installed.
    static func coding(input: Language = .english) throws -> SuggestionsWorld {
        let world = SuggestionsWorld(input: input)
        world.packs = [try pack("python")]
        world.codingMode = true
        return world
    }

    /// The texts of the rows, each with its comment.
    static func texts(_ field: SuggestionsField) -> [String] { field.rows.map { $0.text + " " + $0.comment } }

    // MARK: - The chooser

    /// The two modes the chooser lists, as the panel's rows.
    static func chooser(_ field: SuggestionsField) -> Bool {
        let rows = field.rows.map(\.text)
        guard rows.count == 2 else { return false }
        return rows[0].contains("Translate as You Type") && rows[1].contains("Coding mode")
    }

    /// Holding Shift for a second opens the chooser at the caret: Translate as You Type, Coding mode. Esc closes it,
    /// nothing changed.
    @Test func holdingShiftOpensTheChooser() {
        inEnglish {
            let world = SuggestionsWorld()
            let field = world.field()
            field.holdShift()
            #expect(Self.chooser(field), "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.escape))
            #expect(!Self.chooser(field) && !world.codingMode && !world.translateAsYouType)
        }
    }

    /// A tap of Shift opens no chooser (it switches the input language, as before).
    @Test func aTapOfShiftOpensNoChooser() {
        inEnglish {
            let world = SuggestionsWorld()
            let field = world.field()
            field.tapShift()
            field.fireTimers()
            #expect(!Self.chooser(field), "\(field.rows.map(\.text))")
            #expect(field.host.composer.inputLanguage == .chinese, "switched to pinyin")
            field.holdShift()
            #expect(Self.chooser(field), "held, it opens: \(field.rows.map(\.text))")
        }
    }

    /// 2 (or ↓ and Return) picks Coding mode: on. The chooser goes.
    @Test func choosingCodingModeTurnsItOn() {
        inEnglish {
            let world = SuggestionsWorld()
            let field = world.field()
            field.holdShift()
            #expect(Self.chooser(field))
            #expect(field.press(SuggestionKeys.digit(2)))
            #expect(world.codingMode && !world.translateAsYouType)
            #expect(!Self.chooser(field))

            let other = SuggestionsWorld()
            let arrows = other.field()
            arrows.holdShift()
            #expect(arrows.press(SuggestionKeys.down))
            #expect(arrows.press(SuggestionKeys.enter))
            #expect(other.codingMode, "↓ and Return")
        }
    }

    /// Choosing the mode that is on turns it off.
    @Test func choosingTheModeThatIsOnTurnsItOff() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            let field = world.field()
            field.holdShift()
            #expect(Self.chooser(field))
            #expect(field.press(SuggestionKeys.digit(2)))
            #expect(!world.codingMode)

            world.translateAsYouType = true
            field.holdShift()
            #expect(field.press(SuggestionKeys.digit(1)))
            #expect(!world.translateAsYouType && !world.codingMode)
        }
    }

    /// A long press of Shift isn't a tap: in pinyin mode it opens the chooser, and closing it leaves the input language
    /// as it was.
    @Test func aLongPressOfShiftDoesntSwitchTheInputLanguage() {
        inEnglish {
            let world = SuggestionsWorld(input: .chinese)
            let field = world.field()
            #expect(field.host.composer.inputLanguage == .chinese)
            field.holdShift()
            #expect(Self.chooser(field), "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.escape))
            #expect(field.host.composer.inputLanguage == .chinese, "still pinyin")
            field.type("nihao")
            #expect(field.host.marked == "nihao", "\(field.host.marked)")
        }
    }

    /// Shift held to type capitals opens no chooser, however long.
    @Test func shiftHeldWhileTypingOpensNoChooser() {
        inEnglish {
            let world = SuggestionsWorld()
            let field = world.field()
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: world.clock.timestamp))
            field.noteTimers()
            world.clock.advance(0.2)
            field.press(SuggestionKeys.key("H"))
            world.clock.advance(1.5)
            field.fireTimers()
            #expect(!Self.chooser(field), "\(field.rows.map(\.text))")
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: world.clock.timestamp))
            #expect(!Self.chooser(field) && !world.codingMode && !world.translateAsYouType)
            field.holdShift()
            #expect(Self.chooser(field), "held on its own, it opens: \(field.rows.map(\.text))")
        }
    }

    /// Translate as You Type and coding mode are exclusive: choosing one turns the other off.
    @Test func translateAsYouTypeAndCodingModeAreExclusive() {
        inEnglish {
            let world = SuggestionsWorld()
            world.translateAsYouType = true
            let field = world.field()
            field.holdShift()
            #expect(field.press(SuggestionKeys.digit(2)))
            #expect(world.codingMode && !world.translateAsYouType, "coding on, Translate as You Type off")
            field.holdShift()
            #expect(field.press(SuggestionKeys.digit(1)))
            #expect(world.translateAsYouType && !world.codingMode, "Translate as You Type on, coding off")
        }
    }

    // MARK: - On across fields, English first

    /// Coding mode stays on across fields and apps; each field starts in English (where pinyin comes first otherwise);
    /// a tap of Shift still switches, and pinyin works as usual then.
    @Test func codingModeStartsEachFieldInEnglish() throws {
        try inEnglish {
            let world = try Self.coding(input: .chinese)
            for app in [SuggestionsApps.editor, "com.apple.TextEdit", SuggestionsApps.chrome] {
                let field = world.field(app: app)
                field.type("nihao")
                #expect(field.host.marked.isEmpty && field.document == "nihao", "\(app): English (\(field.host.marked))")
            }
            let field = world.field()
            field.tapShift()
            field.type(" nihao")
            #expect(field.host.marked == "nihao", "pinyin after a tap of Shift (\(field.host.marked))")
            world.codingMode = false
            let after = world.field()
            after.type("nihao")
            #expect(after.host.marked == "nihao", "off: the field starts in pinyin again (\(after.host.marked))")
        }
    }

    // MARK: - Packs

    /// The packs' keywords are rows from 2 characters on; what is typed exactly is not offered.
    @Test func keywordsAreRowsFromTwoCharactersOn() throws {
        try inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.type("r")
            field.idle()
            #expect(!Self.texts(field).contains { $0.contains("return") }, "one character: none (\(Self.texts(field)))")
            field.type("e")
            #expect(field.settle { field.shown(["return", "raise"]).contains("return") }, "\(Self.texts(field))")
            #expect(!field.shown(["return", "raise"]).contains("raise"), "\(Self.texts(field))")
            field.type("turn")
            field.idle()
            #expect(!field.shown(["return"]).contains("return"), "typed exactly: not offered (\(Self.texts(field)))")

            let all = try Self.coding()
            all.packs.append(try Self.pack("javascript"))
            let both = all.field()
            both.type("aw")
            #expect(both.settle { both.shown(["await"]) == ["await"] }, "a keyword of either pack, once: \(Self.texts(both))")
            both.type(" fun")
            #expect(both.settle { both.shown(["function"]).contains("function") }, "every installed pack applies: \(Self.texts(both))")
        }
    }

    /// Off: the packs give no rows.
    @Test func noCodingRowsWhileCodingModeIsOff() throws {
        try inEnglish {
            let world = try Self.coding()
            world.codingMode = false
            let field = world.field()
            field.type("re")
            field.idle()
            #expect(!field.shown(["return"]).contains("return"), "\(Self.texts(field))")
            #expect(!field.press(SuggestionKeys.tab))
            world.codingMode = true
            let on = world.field()
            on.type("re")
            #expect(on.settle { on.shown(["return"]).contains("return") }, "on: \(Self.texts(on))")
        }
    }

    /// A snippet goes in as text, its line breaks kept, its placeholders as their text; the caret at `$0`, where the
    /// field reports ranges.
    @Test func aSnippetGoesInWithItsLineBreaksAndTheCaretAtItsEnd() throws {
        try inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.type("cl")
            #expect(field.settle { field.rows.contains { ($0.text + $0.comment).contains("class with __init__") } },
                    "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { ($0.text + $0.comment).contains("class with __init__") })
            let before = field.host.outputs.count
            #expect(field.pick(at: index))
            #expect(field.document == "class Name:\n    def __init__(self):\n        \n", "\(field.document.debugDescription)")
            let moves = field.host.outputs.dropFirst(before).compactMap { output -> Int? in
                if case let .moveCaret(back, _) = output { return back } else { return nil }
            }
            #expect(moves == [1], "the caret before the last line break: \(moves)")
        }
    }

    /// `print($0)`: "pr" and Tab make "print()", the caret between the parentheses.
    @Test func theCaretGoesToTheSnippetsDollarZero() throws {
        try inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.type("pr")
            #expect(field.settle { field.shown(["print"]) == ["print"] }, "\(Self.texts(field))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "print()", "\(field.document)")
            #expect(field.host.outputs.dropFirst(before).contains { if case .moveCaret(back: 1, after: _) = $0 { true } else { false } },
                    "\(field.host.outputs.dropFirst(before))")
        }
    }

    /// Where the field reports no ranges, the snippet's caret stays at the end of what went in.
    @Test func withoutRangesTheCaretStaysAtTheEnd() throws {
        try inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.type("pr")
            #expect(field.settle { field.shown(["print"]) == ["print"] }, "\(Self.texts(field))")
            var context = field.host.context
            context.read.subtract([.selectedRange, .selection])
            context.selectedRange = nil
            context.selection = nil
            let before = field.host.outputs.count
            field.host.send(.key(SuggestionKeys.tab, context))
            let outputs = Array(field.host.outputs.dropFirst(before))
            #expect(outputs.contains { if case .commit("int()") = $0 { true } else if case .commitAfterKey("int()") = $0 { true } else { false } },
                    "\(outputs)")
            #expect(!outputs.contains { if case let .moveCaret(back, _) = $0 { back > 0 } else { false } }, "\(outputs)")
        }
    }

    /// The def snippet of the spec's example: its placeholders' text, nothing for `${2}`, the caret at the end.
    @Test func theSpecsDefSnippet() throws {
        try inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.type("de")
            #expect(field.settle { field.rows.contains { ($0.text + $0.comment).contains("function") } }, "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { ($0.text + $0.comment).contains("function") })
            #expect(field.pick(at: index))
            #expect(field.document == "def name():\n    ", "\(field.document.debugDescription)")
        }
    }

    /// A digit never picks a row (spec 6.1): "pr" and 1 is "pr1", typed.
    @Test func aDigitIsTypedNotAPick() throws {
        try inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.type("pr")
            #expect(field.settle { field.shown(["print"]) == ["print"] }, "\(Self.texts(field))")
            field.press(SuggestionKeys.digit(1))
            #expect(field.document == "pr1", "\(field.document)")
        }
    }

    // MARK: - What is offered

    /// A snippet is offered while what is typed starts its trigger, the whole trigger too (Tab then puts its body in); a
    /// keyword typed in full isn't (spec 6.13): "def" offers the def snippet, not the keyword "def".
    @Test func theWholeTriggerStillOffersTheSnippet() throws {
        try inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.type("def")
            #expect(field.settle { field.rows.contains { ($0.text + $0.comment).contains("function") } }, "\(Self.texts(field))")
            #expect(field.rows.count == 1, "the snippet only, not the keyword: \(Self.texts(field))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "def name():\n    ", "\(field.document.debugDescription)")
        }
    }

    /// A snippet whose body doesn't start with what was typed isn't offered (spec 6.13); one whose body does is.
    @Test func aSnippetWhoseBodyDoesntStartWithWhatWasTypedIsntOffered() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            world.packs = [CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [], snippets: [
                .init(trigger: "main", body: "if __name__ == \"__main__\":\n    $0", title: "main guard"),
                .init(trigger: "mainloop", body: "mainloop()$0", title: "the main loop"),
            ])]
            let field = world.field()
            field.type("ma")
            #expect(field.settle { Self.texts(field).contains { $0.contains("the main loop") } }, "\(Self.texts(field))")
            field.idle()
            #expect(!Self.texts(field).contains { $0.contains("main guard") }, "\(Self.texts(field))")
        }
    }

    // MARK: - The field's own words

    /// Types `text` where the field has `before` the caret and `after` it as the first key goes down (what it says with
    /// each key: its text, where the caret is); the app types each character.
    func type(_ text: String, into field: SuggestionsField, before: String, after: String) {
        var typed = ""
        for character in text {
            let left = before + typed
            let previous: FieldContext.BeforeCaret = left.last.map { FieldContext.BeforeCaret.text(String($0)) } ?? .nothing
            let context = FieldContext(read: .all, selectedRange: left.utf16.count..<left.utf16.count, beforeCaret: previous,
                                       text: FieldText(before: left, after: after))
            field.host.send(.key(SuggestionKeys.key(character), context))
            typed.append(character)
        }
    }

    /// Identifiers of 4 characters or more in the field's text, before the caret and after it, most frequent first; one
    /// shorter, or what is typed exactly, isn't offered.
    @Test func theFieldsOwnWordsAreRows() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            let field = world.field()
            let before = "result = compute_average(items)\ncox = 1\n"
            let after = "\nprint(compute_total(a), compute_total(b), compute_total(c))\n"
            type("c", into: field, before: before, after: after)
            field.idle()
            #expect(field.shown(["compute_total", "compute_average"]).filter { $0 != "?" }.isEmpty, "one character: none")
            type("o", into: field, before: before + "c", after: after)
            let words = ["compute_total", "compute_average", "cox"]
            #expect(field.settle { field.shown(words).prefix(2) == ["compute_total", "compute_average"] },
                    "the most frequent first (after the caret too): \(Self.texts(field))")
            #expect(!field.shown(words).contains("cox"), "3 characters: not offered")
        }
    }

    /// Among words as frequent, the nearest to the caret first.
    @Test func amongWordsAsFrequentTheNearestFirst() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            let field = world.field()
            type("ta", into: field, before: "table_far = 1\nother = 2\nstill = 3\ntable_near = 4\n", after: "")
            #expect(field.settle { field.shown(["table_near", "table_far"]) == ["table_near", "table_far"] }, "\(Self.texts(field))")
        }
    }

    /// The token is identifier characters: after "." a new one starts ("self.co" offers what "co" starts).
    @Test func aDotStartsANewToken() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            let field = world.field()
            type("self.co", into: field, before: "count_items(x)\n", after: "")
            #expect(field.settle { field.shown(["count_items"]) == ["count_items"] }, "\(Self.texts(field))")
        }
    }

    static let computePack = CodingLanguagePack(language: "example", title: "Example", version: "1.0.0",
                                                keywords: ["compute_total", "compute_average"],
                                                snippets: [.init(trigger: "compute_sum", body: "compute_sum($0)", title: "sum")])

    /// Terminals and code editors (VS Code, spec 6.11) are one class: Tab completes the rows' common prefix only (a
    /// snippet isn't expanded); once that adds nothing, Tab is the app's (spec 6.10).
    @Test(arguments: [("com.apple.Terminal", true), (SuggestionsApps.vsCode, false)])
    func inTerminalsAndCodeEditorsTabCompletesTheCommonPrefixOnly(_ app: String, _ terminal: Bool) {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            world.packs = [Self.computePack]
            let field = world.field(app: app, terminal: terminal)
            field.type("co")
            #expect(field.settle { field.shown(["compute_total", "compute_average", "compute_sum"]).filter { $0 != "?" }.count == 3 },
                    "\(app): \(Self.texts(field))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "compute_", "\(app): \(field.document)")
            #expect(field.settle { field.shown(["compute_total", "compute_average", "compute_sum"]).filter { $0 != "?" }.count == 3 },
                    "\(app): \(Self.texts(field))")
            #expect(!field.press(SuggestionKeys.tab), "\(app): nothing more in common, its Tab")
            #expect(field.document == "compute_", "\(app): \(field.document)")
        }
    }

    /// Where the field tells nothing of its text (a terminal), only the packs' keywords and snippets are rows (spec 6.16):
    /// a word in the field it doesn't tell of isn't one.
    @Test func whereTheFieldTellsNoTextOnlyPacksApply() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            world.packs = [Self.computePack]
            let field = world.field(app: "com.apple.Terminal", terminal: true)
            field.host.tellsNoText = true
            field.host.document = "compute_zebra = 1\n"
            for character in "co" {
                var context = field.host.context
                context.read.remove(.text)
                context.text = nil
                field.host.send(.key(SuggestionKeys.key(character), context))
                field.host.document.append(character)
            }
            let words = ["compute_total", "compute_average", "compute_sum", "compute_zebra"]
            #expect(field.settle { field.shown(words).filter { $0 != "?" }.count == 3 }, "\(Self.texts(field))")
            #expect(!field.shown(words).contains("compute_zebra"), "\(Self.texts(field))")
        }
    }
}
