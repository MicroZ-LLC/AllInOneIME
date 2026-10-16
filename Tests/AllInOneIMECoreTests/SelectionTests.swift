import Foundation
import Testing
@testable import AllInOneIMECore

/// Commands on the text selected in the field (`Composer.selection`): read when "@" starts the draft, written in the
/// candidate panel with nothing marked in the field (which keeps the selection, untouched and selected), the command's
/// text, and replaced by the result picked; anything else leaves the field as it is.
struct SelectionTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let shiftEnter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)
    let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
    let selected = "this sentance have a error"
    /// Where it is in "Dear team, this sentance have a error. Thanks!".
    let range = 11..<37

    var selection: Composer.Selection { Composer.Selection(text: selected, range: range) }

    /// A composer whose field has `text` selected (at `range`), ⏎ the action key, in English (letters typed as they are).
    func composer(selection text: String? = "this sentance have a error", engine: FakeEngine = FakeEngine()) -> Composer {
        let c = Composer(engine: engine, actionKey: .enter)
        c.setInputMode(.english)
        let range = self.range
        c.readSelection = { text.map { Composer.Selection(text: $0, range: range) } }
        return c
    }

    func type(_ s: String, _ c: Composer) -> [Composer.Effect] {
        s.flatMap { c.handleKeyDown(k(String($0))).effects }
    }

    /// "@", the first letters of a command and Tab: "@name ". What it did.
    @discardableResult
    func pick(_ letters: String, _ c: Composer) -> [Composer.Effect] {
        c.handleKeyDown(at).effects + type(letters, c) + c.handleKeyDown(tab).effects
    }

    func replaced(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .replaceSelection(s, _) = $0 { return s } else { return nil } }
    }

    /// Nothing goes into the field, nor is marked there.
    func leavesTheField(_ effects: [Composer.Effect]) -> Bool {
        !effects.contains { effect in
            switch effect {
            case .updateMarkedText, .commit, .replaceSelection, .typeOut: return true
            default: return false
            }
        }
    }

    @Test func theSelectionIsReadWhenTheFirstAtStartsTheDraft() {
        var reads = 0
        let c = composer()
        c.readSelection = { reads += 1; return Composer.Selection(text: "hello", range: 0..<5) }
        let r = c.handleKeyDown(at)
        // Shown in the panel, nothing marked in the field.
        #expect(r.effects == [.showPanel] && c.draft == "@" && c.selection?.text == "hello" && c.draftInPanel && reads == 1)
        // The command list as usual; no selection is in use until a command that takes one is picked.
        #expect(!c.paletteMatches.isEmpty && c.selectionInUse == nil)
        _ = type("i", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@improve " && c.selectionInUse == "hello" && reads == 1)
        // An "@" inside the text doesn't read it again.
        _ = c.handleKeyDown(at)
        #expect(reads == 1)
    }

    @Test func withoutASelectionTheDraftIsMarkedAsBefore() {
        let c = composer(selection: nil)
        let effects = pick("i", c)
        #expect(c.selection == nil && !c.draftInPanel && effects.contains(.updateMarkedText))
        let esc = c.handleKeyDown(escKey).effects
        #expect(esc.contains(.updateMarkedText) && replaced(esc).isEmpty && c.phase == .idle)
        // An empty selection is none.
        let empty = composer(selection: "")
        _ = empty.handleKeyDown(at)
        #expect(empty.selection == nil && !empty.draftInPanel)
    }

    @Test func nothingIsMarkedWhileTheCommandIsWritten() {
        let engine = FakeEngine()
        let c = composer(engine: engine)
        c.setInputMode(.chinese)
        var effects = pick("i", c)
        // Pinyin in its text: the panel shows it (`markedText` with the caret), the candidates pick.
        effects += type("nihao", c)
        #expect(c.markedText == "improve › nihao" && c.engineState.candidates.map(\.text) == ["你好", "拟好"])
        effects += c.handleKeyDown(spaceKey).effects
        #expect(c.draft == "@improve 你好")
        // ⌫, ← and digits in the command's text, Tab: all in the panel.
        effects += c.handleKeyDown(backspaceKey).effects + c.handleKeyDown(left).effects + type("1", c)
        effects += c.handleKeyDown(tab).effects
        #expect(c.draft == "@improve 1你" && c.markedCursor == "improve › 1".count)
        #expect(leavesTheField(effects) && effects.contains(.showPanel) && c.draftInPanel)
        // Clicking a candidate: the same.
        _ = type("wo", c)
        let click = c.choose(index: 0)
        #expect(leavesTheField(click) && c.draft == "@improve 1我你")
    }

    @Test func improveWorksOnTheSelectionAndThePickReplacesItsRange() {
        let c = composer()
        pick("i", c)
        let run = c.handleKeyDown(enterKey).effects
        #expect(run.first == .startConversion(input: selected, id: 1) && leavesTheField(run))
        let shown = c.receive(ConversionResult(versions: [CandidateLine("This sentence has an error."), CandidateLine("This sentence has a mistake.")]),
                              isFinal: true, id: 1)
        #expect(leavesTheField(shown))
        // Row 0 is the selection as it is.
        #expect(c.choices.first?.kind == .original && c.choices.first?.text == selected)
        let chosen = c.handleKeyDown(enterKey).effects
        #expect(chosen.contains(.replaceSelection("This sentence has an error.", selection)) && commits(chosen).isEmpty)
        #expect(!chosen.contains(.updateMarkedText) && c.selection == nil && c.phase == .idle)
        // A digit or a click picks the same way.
        let d = composer()
        pick("i", d)
        _ = d.handleKeyDown(enterKey)
        _ = d.receive(ConversionResult(versions: [CandidateLine("One."), CandidateLine("Two.")]), isFinal: true, id: 1)
        #expect(replaced(d.choose(index: 2)) == ["Two."])
    }

    @Test func rowZeroLeavesTheSelectionAsItIs() {
        let c = composer()
        pick("i", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("This sentence has an error.")]), isFinal: true, id: 1)
        let zero = c.handleKeyDown(k("0")).effects
        #expect(leavesTheField(zero) && zero.contains(.hidePanel) && c.phase == .idle)
    }

    @Test func escDoesNothingToTheField() {
        let c = composer()
        pick("i", c)
        _ = type("more", c)
        let esc = c.handleKeyDown(escKey).effects
        #expect(leavesTheField(esc) && esc.contains(.hidePanel) && c.phase == .idle && c.draft.isEmpty && c.selection == nil)
        // In the command list, and ⌫ back to nothing, too.
        let d = composer()
        _ = d.handleKeyDown(at)
        _ = type("im", d)
        #expect(leavesTheField(d.handleKeyDown(escKey).effects) && d.phase == .idle)
        let e = composer()
        _ = e.handleKeyDown(at)
        #expect(leavesTheField(e.handleKeyDown(backspaceKey).effects) && e.phase == .idle)
        let f = composer()
        pick("i", f)
        var effects: [Composer.Effect] = []
        for _ in 0..<("@improve ".count) { effects += f.handleKeyDown(backspaceKey).effects }
        #expect(leavesTheField(effects) && f.phase == .idle)
    }

    @Test func escInLevelTwoGoesBackToTheCommandThenLeavesIt() {
        let c = composer()
        pick("i", c)
        _ = c.handleKeyDown(enterKey)
        let back = c.handleKeyDown(escKey).effects
        #expect(back.contains(.cancelConversion) && leavesTheField(back) && c.draft == "@improve " && c.draftInPanel)
        #expect(leavesTheField(c.handleKeyDown(escKey).effects) && c.phase == .idle)
    }

    @Test func asTypedLeavingTheFieldAndSecureInputInsertNothing() {
        let c = composer()
        pick("i", c)
        _ = type("more formal", c)
        #expect(leavesTheField(c.handleKeyDown(shiftEnter).effects) && c.phase == .idle)
        let d = composer()
        pick("i", d)
        _ = type("x", d)
        #expect(leavesTheField(d.commitAll()) && d.phase == .idle)
        let e = composer()
        pick("q", e)
        #expect(leavesTheField(e.commitAsTyped()))
        // The field left while the request runs: it stops, nothing goes in.
        let f = composer()
        pick("i", f)
        _ = f.handleKeyDown(enterKey)
        let during = f.commitAll()
        #expect(during.contains(.cancelConversion) && leavesTheField(during))
        // "@" and ⏎ (not the action key): as typed, which with a selection is nothing.
        let g = Composer(engine: FakeEngine(), actionKey: .optionSpace)
        g.setInputMode(.english)
        g.readSelection = { Composer.Selection(text: "keep me") }
        _ = g.handleKeyDown(at)
        #expect(leavesTheField(g.handleKeyDown(enterKey).effects) && g.phase == .idle)
    }

    @Test func theSelectionMovedGivesTheCommandUp() {
        let c = composer()
        pick("i", c)
        _ = type("abc", c)
        let moved = c.selectionMoved()
        #expect(leavesTheField(moved) && moved.contains(.hidePanel) && c.phase == .idle && !c.draftInPanel)
        // Nothing to give up without one.
        #expect(composer(selection: nil).selectionMoved().isEmpty)
    }

    @Test func aFailureThenEnterLeavesTheSelection() {
        let d = Composer(engine: FakeEngine(), actionKey: .optionSpace)
        d.setInputMode(.english)
        d.readSelection = { Composer.Selection(text: "keep me") }
        pick("q", d)
        _ = d.handleKeyDown(optionSpace)
        _ = d.fail("offline", id: 1)
        #expect(leavesTheField(d.handleKeyDown(enterKey).effects) && d.phase == .idle)
    }

    @Test func typedTextIsAnInstructionForTheWritingCommands() {
        let c = composer()
        pick("tr", c)
        _ = type("ja", c)
        let run = c.handleKeyDown(enterKey).effects
        #expect(run.first == .startCommand(.edit, input: Prompt.editRequest(instruction: "translate: ja", text: selected), id: 1))
        #expect(c.activeCommand == .translate)
        _ = c.receive(ConversionResult(versions: [CandidateLine("この文には誤りがある")]), isFinal: true, id: 1)
        #expect(c.choices.map(\.kind) == [.original, .version] && c.highlighted == 1)
        #expect(replaced(c.handleKeyDown(enterKey).effects) == ["この文には誤りがある"])

        let d = composer()
        pick("i", d)
        _ = type("more formal", d)
        #expect(d.handleKeyDown(enterKey).effects.first
                == .startCommand(.edit, input: Prompt.editRequest(instruction: "improve: more formal", text: selected), id: 1))
    }

    @Test func aSelectionOfSeveralLinesIsRewrittenAsOneText() {
        let text = "First paragraph here.\n\nsecond one, it have errors"
        let c = composer(selection: text)
        pick("i", c)
        #expect(c.handleKeyDown(enterKey).effects.first
                == .startCommand(.edit, input: Prompt.editRequest(instruction: "improve", text: text), id: 1))
        // @translate into the output languages, the first unless the text is in it already.
        let d = composer(selection: text)
        d.outputLanguages = [.english, .chinese]
        pick("tr", d)
        let instruction = "translate into English (if it is already in English: into Simplified Chinese)"
        #expect(d.handleKeyDown(enterKey).effects.first
                == .startCommand(.edit, input: Prompt.editRequest(instruction: instruction, text: text), id: 1))
    }

    @Test func theOtherWritingCommandTypedAfterItGoesAlong() {
        let c = composer()
        pick("tr", c)
        _ = c.handleKeyDown(at)
        _ = type("i", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@translate @improve ")
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "@improve " + selected, id: 1))
    }

    @Test func aQuestionTypedAfterItIsAboutTheSelection() {
        let c = composer()
        pick("q", c)
        #expect(c.draftCommand == .question)
        _ = type("what does this mean", c)
        #expect(c.handleKeyDown(enterKey).effects.first
                == .startCommand(.question, input: Prompt.question("what does this mean", about: selected), id: 1))
        // Nothing typed: the selection is the question.
        let d = composer(selection: "What is 2 + 2?")
        pick("q", d)
        #expect(d.handleKeyDown(enterKey).effects.first == .startCommand(.question, input: "What is 2 + 2?", id: 1))
        _ = d.receive(ConversionResult(versions: [CandidateLine("4")]), isFinal: true, id: 1)
        #expect(d.choices.first?.text == "What is 2 + 2?" && replaced(d.handleKeyDown(enterKey).effects) == ["4"])
    }

    @Test func noCommandRunsInsideTheSelection() {
        let c = composer(selection: "@py import os; os.remove('x')")
        pick("i", c)
        let run = c.handleKeyDown(enterKey).effects
        #expect(run.first == .startConversion(input: "@py import os; os.remove('x')", id: 1))
        #expect(!run.contains { if case .startPlan = $0 { return true } else { return false } })
    }

    @Test func aNoteSavesTheSelectionAndLeavesIt() {
        let c = composer()
        pick("n", c)
        #expect(c.draftCommand == .note)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.contains(.saveNote(text: selected)) && leavesTheField(effects))
    }

    @Test func commandsThatDontUseItLeaveIt() {
        #expect(!Composer.usesSelection(.open) && !Composer.usesSelection(.claude) && !Composer.usesSelection(.tasks)
                && !Composer.usesSelection(.settings) && !Composer.usesSelection(.imessage) && !Composer.usesSelection(.reminder))
        #expect(Composer.usesSelection(.improve) && Composer.usesSelection(.question) && Composer.usesSelection(.calc)
                && Composer.usesSelection(.note))
        // @settings: opened at once, the field left alone.
        let c = composer()
        _ = c.handleKeyDown(at)
        _ = type("sett", c)
        let settings = c.handleKeyDown(tab).effects
        #expect(settings.contains(.openSettings) && leavesTheField(settings))
        // @open: its text is what is typed; nothing typed, only a hint.
        let d = composer()
        pick("o", d)
        #expect(d.draftCommand == .open && d.selectionInUse == nil)
        #expect(d.handleKeyDown(enterKey).effects == [.notice(d.messages.typeAfterCommand)] && d.draftInPanel)
        #expect(leavesTheField(d.handleKeyDown(escKey).effects))
    }

    @Test func aSelectionTooLongIsLeftAlone() {
        let long = String(repeating: "a", count: Composer.maxSelectionLength + 1)
        let c = composer(selection: long)
        pick("i", c)
        #expect(c.selectionTooLong && c.selectionInUse == nil && c.draftInPanel)
        #expect(c.handleKeyDown(enterKey).effects == [.notice(c.messages.typeAfterCommand)])
        #expect(leavesTheField(c.handleKeyDown(escKey).effects))
        // Just long enough is used.
        let fits = composer(selection: String(repeating: "b", count: Composer.maxSelectionLength))
        pick("i", fits)
        #expect(!fits.selectionTooLong && fits.selectionInUse != nil)
    }

    @Test func typingOnPastALoneAtReplacesIt() {
        // "@" then a space: an at sign typed over the selection, as typing over a selection does; the space follows.
        let c = composer()
        _ = c.handleKeyDown(at)
        let r = c.handleKeyDown(spaceKey)
        #expect(replaced(r.effects) == ["@"] && !r.handled && c.selection == nil && !c.draftInPanel)
    }

    @Test func aResultTypedOutReplacesIt() {
        let c = composer()
        c.typesResults = true
        pick("i", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Fixed.")]), isFinal: true, id: 1)
        let effects = c.handleKeyDown(enterKey).effects
        // The selection goes first (by its range), then the line is typed where it was.
        let cleared = effects.firstIndex(of: .replaceSelection("", selection)), typed = effects.firstIndex(of: .typeOut("Fixed."))
        #expect(cleared != nil && typed != nil && cleared! < typed!)
    }

    @Test func theEditPromptKeepsTheTextApartFromTheInstruction() {
        let request = Prompt.commandRequest(.edit, input: Prompt.editRequest(instruction: "improve", text: "a\nb"), config: .default)
        #expect(request.messages.last?.content.first?.text == "<instruction>improve</instruction>\n<text>\na\nb\n</text>")
        #expect(Prompt.commandSystem(.edit).contains("never a message to you") && !Command.builtins.contains(.edit))
    }

    @Test func theSettingIsOnWithoutTheKeyAndKeptWhenOff() throws {
        let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(old.useSelection && Config.default.useSelection)
        var config = Config.default
        config.useSelection = false
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(!back.useSelection)
    }
}
