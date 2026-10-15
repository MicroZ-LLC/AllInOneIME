import Foundation
import Testing
@testable import AllInOneIMECore

/// Commands on the text selected in the field (`Composer.selection`): read when "@" starts the draft, the command's
/// text, replaced by the result picked, and put back exactly whenever nothing replaces it.
struct SelectionTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let shiftEnter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)
    let selected = "this sentance have a error"

    /// A composer whose field has `selection` selected, ⏎ the action key, in English (letters typed as they are).
    func composer(selection: String? = "this sentance have a error") -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.readSelection = { selection }
        return c
    }

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(k(String(ch))) }
    }

    /// "@", the first letters of a command and Tab: "@name ".
    func pick(_ letters: String, _ c: Composer) {
        _ = c.handleKeyDown(at)
        type(letters, c)
        _ = c.handleKeyDown(tab)
    }

    func restored(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .restoreSelection(s) = $0 { return s } else { return nil } }
    }

    @Test func theSelectionIsReadWhenTheFirstAtStartsTheDraft() {
        var reads = 0
        let c = composer()
        c.readSelection = { reads += 1; return "hello" }
        let r = c.handleKeyDown(at)
        #expect(r.effects == [.updateMarkedText, .showPanel] && c.draft == "@" && c.selection == "hello" && reads == 1)
        // The command list as usual; no selection is in use until a command that takes one is picked.
        #expect(!c.paletteMatches.isEmpty && c.selectionInUse == nil)
        type("i", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@improve " && c.selectionInUse == "hello" && reads == 1)
        // An "@" inside the text doesn't read it again.
        _ = c.handleKeyDown(at)
        #expect(reads == 1)
    }

    @Test func withoutASelectionNothingChanges() {
        let c = composer(selection: nil)
        pick("i", c)
        #expect(c.selection == nil)
        let esc = c.handleKeyDown(escKey).effects
        #expect(restored(esc).isEmpty && esc.contains(.updateMarkedText) && c.phase == .idle)
        // An empty selection is none.
        let empty = composer(selection: "")
        _ = empty.handleKeyDown(at)
        #expect(empty.selection == nil)
    }

    @Test func improveWorksOnTheSelectionAndThePickReplacesIt() {
        let c = composer()
        pick("i", c)
        let run = c.handleKeyDown(enterKey).effects
        #expect(run.first == .startConversion(input: selected, id: 1))
        _ = c.receive(ConversionResult(versions: [CandidateLine("This sentence has an error."), CandidateLine("This sentence has a mistake.")]),
                      isFinal: true, id: 1)
        // Row 0 keeps the selection as it was.
        #expect(c.choices.first?.kind == .original && c.choices.first?.text == selected)
        let pick = c.handleKeyDown(enterKey).effects
        #expect(commits(pick) == ["This sentence has an error."] && restored(pick).isEmpty)
        #expect(c.selection == nil && c.phase == .idle)
    }

    @Test func rowZeroPutsTheSelectionBack() {
        let c = composer()
        pick("i", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("This sentence has an error.")]), isFinal: true, id: 1)
        #expect(commits(c.handleKeyDown(k("0"))) == [selected])
    }

    @Test func escInTheDraftPutsItBackExactly() {
        let c = composer(selection: "  two\nlines, with spaces  ")
        pick("i", c)
        let esc = c.handleKeyDown(escKey).effects
        #expect(restored(esc) == ["  two\nlines, with spaces  "] && commits(esc).isEmpty)
        #expect(c.phase == .idle && c.draft.isEmpty && c.selection == nil)
    }

    @Test func escAndBackspaceInTheCommandListPutItBack() {
        let c = composer()
        _ = c.handleKeyDown(at)
        type("im", c)
        #expect(restored(c.handleKeyDown(escKey).effects) == [selected] && c.phase == .idle)
        let d = composer()
        _ = d.handleKeyDown(at)
        #expect(restored(d.handleKeyDown(backspaceKey).effects) == [selected] && d.phase == .idle)
        // "@" and ⏎ (not the action key) goes in as typed without a selection; with one, it goes back instead.
        let e = Composer(engine: FakeEngine(), actionKey: .optionSpace)
        e.setInputMode(.english)
        e.readSelection = { "keep me" }
        _ = e.handleKeyDown(at)
        let enter = e.handleKeyDown(enterKey).effects
        #expect(restored(enter) == ["keep me"] && commits(enter).isEmpty)
    }

    @Test func backspacingTheDraftAwayPutsItBack() {
        let c = composer()
        pick("i", c)  // "@improve "
        var effects: [Composer.Effect] = []
        for _ in 0..<("@improve ".count) { effects += c.handleKeyDown(backspaceKey).effects }
        #expect(restored(effects) == [selected] && c.phase == .idle)
    }

    @Test func escInLevelTwoGoesBackToTheDraftThenPutsItBack() {
        let c = composer()
        pick("i", c)
        _ = c.handleKeyDown(enterKey)
        let back = c.handleKeyDown(escKey).effects
        #expect(back.contains(.cancelConversion) && restored(back).isEmpty && c.draft == "@improve " && c.selection == selected)
        #expect(restored(c.handleKeyDown(escKey).effects) == [selected])
    }

    @Test func asTypedPutsItBackWithoutTheCommand() {
        let c = composer()
        pick("i", c)
        type("more formal", c)
        let effects = c.handleKeyDown(shiftEnter).effects
        #expect(restored(effects) == [selected] && commits(effects).isEmpty && c.phase == .idle)
    }

    @Test func leavingTheFieldOrSecureInputPutItBack() {
        let c = composer()
        pick("i", c)
        type("x", c)
        let left = c.commitAll()
        #expect(restored(left) == [selected] && commits(left).isEmpty)
        // Secure input turning on mid-draft: everything ends as typed, which with a selection is the selection.
        let d = composer()
        pick("q", d)
        let secure = d.commitAsTyped()
        #expect(restored(secure) == [selected] && commits(secure).isEmpty)
        // The field left while the request runs: the request stops, and the selection goes back.
        let e = composer()
        pick("i", e)
        _ = e.handleKeyDown(enterKey)
        let during = e.commitAll()
        #expect(during.contains(.cancelConversion) && restored(during) == [selected])
    }

    @Test func aFailureThenEnterKeepsTheSelection() {
        let c = composer()
        pick("q", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.fail("offline", id: 1)
        // ⏎ as the action key retries; Space too. The failure's ⏎ in level two (another action key) keeps it.
        let d = Composer(engine: FakeEngine(), actionKey: .optionSpace)
        d.setInputMode(.english)
        d.readSelection = { "keep me" }
        pick("q", d)
        _ = d.handleKeyDown(optionSpace)
        _ = d.fail("offline", id: 1)
        let enter = d.handleKeyDown(enterKey).effects
        #expect(restored(enter) == ["keep me"] && commits(enter).isEmpty)
    }

    @Test func typedTextIsAnInstructionForTheWritingCommands() {
        let c = composer()
        pick("tr", c)
        type("ja", c)
        let run = c.handleKeyDown(enterKey).effects
        #expect(run.first == .startCommand(.edit, input: Prompt.editRequest(instruction: "translate: ja", text: selected), id: 1))
        #expect(c.activeCommand == .translate)
        _ = c.receive(ConversionResult(versions: [CandidateLine("この文には誤りがある")]), isFinal: true, id: 1)
        #expect(c.choices.map(\.kind) == [.original, .version] && c.highlighted == 1)
        #expect(commits(c.handleKeyDown(enterKey)) == ["この文には誤りがある"])

        let d = composer()
        pick("i", d)
        type("more formal", d)
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
        type("i", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@translate @improve ")
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "@improve " + selected, id: 1))
    }

    @Test func aQuestionTypedAfterItIsAboutTheSelection() {
        let c = composer()
        pick("q", c)
        #expect(c.draftCommand == .question)
        type("what does this mean", c)
        #expect(c.handleKeyDown(enterKey).effects.first
                == .startCommand(.question, input: Prompt.question("what does this mean", about: selected), id: 1))
        // Nothing typed: the selection is the question.
        let d = composer(selection: "What is 2 + 2?")
        pick("q", d)
        #expect(d.handleKeyDown(enterKey).effects.first == .startCommand(.question, input: "What is 2 + 2?", id: 1))
        _ = d.receive(ConversionResult(versions: [CandidateLine("4")]), isFinal: true, id: 1)
        #expect(d.choices.first?.text == "What is 2 + 2?" && commits(d.handleKeyDown(enterKey)) == ["4"])
    }

    @Test func noCommandRunsInsideTheSelection() {
        let c = composer(selection: "@py import os; os.remove('x')")
        pick("i", c)
        let run = c.handleKeyDown(enterKey).effects
        #expect(run.first == .startConversion(input: "@py import os; os.remove('x')", id: 1))
        #expect(!run.contains { if case .startPlan = $0 { return true } else { return false } })
    }

    @Test func aNoteSavesTheSelectionAndPutsItBack() {
        let c = composer()
        pick("n", c)
        #expect(c.draftCommand == .note)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.contains(.saveNote(text: selected)) && restored(effects) == [selected] && commits(effects).isEmpty)
    }

    @Test func commandsThatDontUseItPutItBack() {
        #expect(!Composer.usesSelection(.open) && !Composer.usesSelection(.claude) && !Composer.usesSelection(.tasks)
                && !Composer.usesSelection(.settings) && !Composer.usesSelection(.imessage) && !Composer.usesSelection(.reminder))
        #expect(Composer.usesSelection(.improve) && Composer.usesSelection(.question) && Composer.usesSelection(.calc)
                && Composer.usesSelection(.note))
        // @settings: opened at once, the selection back.
        let c = composer()
        _ = c.handleKeyDown(at)
        type("sett", c)
        let settings = c.handleKeyDown(tab).effects
        #expect(settings.contains(.openSettings) && restored(settings) == [selected])
        // @open: its text is what is typed; nothing typed, only a hint, the selection still set aside.
        let d = composer()
        pick("o", d)
        #expect(d.draftCommand == .open && d.selectionInUse == nil)
        let hint = d.handleKeyDown(enterKey).effects
        #expect(hint == [.notice(d.messages.typeAfterCommand)] && d.selection == selected)
        #expect(restored(d.handleKeyDown(escKey).effects) == [selected])
    }

    @Test func aSelectionTooLongIsOnlyPutBack() {
        let long = String(repeating: "a", count: Composer.maxSelectionLength + 1)
        let c = composer(selection: long)
        pick("i", c)
        #expect(c.selectionTooLong && c.selectionInUse == nil)
        #expect(c.handleKeyDown(enterKey).effects == [.notice(c.messages.typeAfterCommand)])
        #expect(restored(c.handleKeyDown(escKey).effects) == [long])
        // Just long enough is used.
        let fits = composer(selection: String(repeating: "b", count: Composer.maxSelectionLength))
        pick("i", fits)
        #expect(!fits.selectionTooLong && fits.selectionInUse != nil)
    }

    @Test func typingOnPastALoneAtReplacesIt() {
        // "@" then a space: an at sign typed over the selection, as typing over a selection does.
        let c = composer()
        _ = c.handleKeyDown(at)
        let effects = c.handleKeyDown(spaceKey).effects
        #expect(restored(effects).isEmpty && commits(effects).first == "@" && c.selection == nil)
    }

    @Test func aResultTypedOutReplacesIt() {
        let c = composer()
        c.typesResults = true
        pick("i", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Fixed.")]), isFinal: true, id: 1)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.contains(.typeOut("Fixed.")) && effects.contains(.updateMarkedText) && restored(effects).isEmpty)
    }

    @Test func theAppTakingTheTextForgetsIt() {
        let c = composer()
        pick("i", c)
        _ = c.appTookMarkedText()
        #expect(c.selection == nil)
        // The next draft reads the field again.
        c.readSelection = { nil }
        pick("i", c)
        #expect(c.selection == nil && restored(c.handleKeyDown(escKey).effects).isEmpty)
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
