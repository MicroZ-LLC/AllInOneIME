import Foundation
import Testing
@testable import AllInOneIMECore

/// Refining AI results: while they are shown, a letter starts a follow-up instruction ("shorter"), ⇧⏎ asks again with
/// the results as context, and the new ones replace them; Esc clears the line, then goes back one step, then to the
/// draft. Digits, Space and ⏎ on an empty line pick as before; ⏎ with a line typed inserts too (0.6.4).
struct RefineTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let first = ConversionResult(
        versions: [CandidateLine("Hello there, nice to meet you."), CandidateLine("Hi, good to meet you."), CandidateLine("Hey, nice meeting you.")],
        rewrites: [Rewrite(style: "简洁", line: CandidateLine("Hi, nice to meet you."))])
    let shorter = ConversionResult(versions: [CandidateLine("Hi!"), CandidateLine("Hey you!"), CandidateLine("Hiya!")])
    let formal = ConversionResult(versions: [CandidateLine("Good day."), CandidateLine("Greetings."), CandidateLine("Pleased to meet you.")])

    func type(_ s: String, _ c: Composer) -> [Composer.Effect] {
        s.flatMap { c.handleKeyDown(k(String($0))).effects }
    }

    /// "@improve hello" in English, ⏎ the action key, run and answered with `first` (request 1).
    func results(english: Bool = true) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        if english { c.setInputMode(.english) }
        _ = c.handleKeyDown(at)
        _ = type("i", c)
        _ = c.handleKeyDown(tab)
        if english {
            _ = type("hello", c)
        } else {
            c.setInputMode(.english)
            _ = type("hello", c)
            c.setInputMode(.chinese)
        }
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "hello", id: 1))
        _ = c.receive(first, isFinal: true, id: 1)
        #expect(c.phase == .choosing && c.canRefine)
        return (c, engine)
    }

    func started(_ effects: [Composer.Effect]) -> (Refinement, Int)? {
        effects.lazy.compactMap { if case let .startRefine(r, id) = $0 { return (r, id) } else { return nil } }.first
    }

    // MARK: - Keys

    @Test func aLetterStartsTheRefineLineAndShiftEnterRunsIt() {
        let (c, _) = results()
        let typed = type("shorter", c)
        // Nothing goes back to the draft, nothing is cancelled: the results stay, the line is in the panel.
        #expect(typed.allSatisfy { $0 == .showPanel } && c.phase == .choosing && c.refineText == "shorter")
        #expect(c.refineLine == "shorter" && c.choices.count == 5 && c.draft == "@improve hello")
        let run = c.handleKeyDown(shiftEnterKey).effects
        let expected = Refinement(request: .writing(.improve, input: "hello"),
                                  turns: [Refinement.Turn(answer: first, instruction: "shorter")])
        #expect(run == [.startRefine(expected, id: 2), .showPanel])
        #expect(c.isRefining && c.refineHistory == ["shorter"] && c.refineText.isEmpty && c.refineLine == nil)
        // The new results stream in, in place of the old: row 0 is still the sentence as typed.
        #expect(c.choices.map(\.kind) == [.original])
        _ = c.receive(shorter, isFinal: true, id: 2)
        #expect(c.phase == .choosing && !c.isRefining && c.refineHistory == ["shorter"])
        #expect(c.choices.map(\.text) == ["hello", "Hi!", "Hey you!", "Hiya!"] && c.highlighted == 1)
        // ⏎ on an empty line inserts the highlighted row, as always.
        #expect(commits(c.handleKeyDown(enterKey)) == ["Hi!"] && c.phase == .idle && c.refineHistory.isEmpty)
    }

    @Test func digitsPickWhileTheLineIsEmptyAndAreTextOnceItIsnt() {
        let (c, _) = results()
        #expect(commits(c.handleKeyDown(k("2"))) == ["Hi, good to meet you."])
        let (d, _) = results()
        _ = type("in 3 words", d)
        #expect(d.refineText == "in 3 words" && d.phase == .choosing)
        // ↑↓ still move among the rows.
        _ = d.handleKeyDown(downKey)
        #expect(d.highlighted == 2 && d.refineText == "in 3 words")
        // Space on an empty line still inserts.
        let (e, _) = results()
        #expect(commits(e.handleKeyDown(spaceKey)) == ["Hello there, nice to meet you."])
    }

    @Test func otherKeysOnAnEmptyLineAreAsBefore() {
        // Punctuation goes back to the draft and continues it, as typing in level two did.
        let (c, _) = results()
        let r = c.handleKeyDown(k("!"))
        #expect(c.phase == .drafting && c.draft == "@improve hello!" && r.effects.contains(.updateMarkedText))
        // ⌫ on an empty line: back to the draft.
        let (d, _) = results()
        _ = d.handleKeyDown(backspaceKey)
        #expect(d.phase == .drafting && d.draft == "@improve hello")
    }

    @Test func escClearsTheLineThenGoesBackOneStepThenToTheDraft() {
        let (c, _) = results()
        _ = type("shorter", c)
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.refineText == "shorte")
        #expect(c.handleKeyDown(escKey).effects == [.showPanel] && c.refineText.isEmpty && c.phase == .choosing)
        #expect(c.result == first)
        _ = type("shorter", c)
        _ = c.handleKeyDown(shiftEnterKey)
        _ = c.receive(shorter, isFinal: true, id: 2)
        _ = type("more formal", c)
        _ = c.handleKeyDown(shiftEnterKey)
        _ = c.receive(formal, isFinal: true, id: 3)
        #expect(c.refineHistory == ["shorter", "more formal"] && c.result == formal)
        // Esc: one step back each time, the results as they were.
        #expect(c.handleKeyDown(escKey).effects == [.showPanel])
        #expect(c.result == shorter && c.refineHistory == ["shorter"] && c.phase == .choosing)
        _ = c.handleKeyDown(backspaceKey)  // ⌫ on an empty line, the same
        #expect(c.result == first && c.refineHistory.isEmpty && c.phase == .choosing)
        // Then back to the draft, as before.
        _ = c.handleKeyDown(escKey)
        #expect(c.phase == .drafting && c.draft == "@improve hello" && !c.canRefine)
    }

    @Test func escDuringARefineStopsItAndKeepsTheResultsBefore() {
        let (c, _) = results()
        _ = type("shorter", c)
        _ = c.handleKeyDown(shiftEnterKey)
        // A line typed meanwhile doesn't change what Esc does: it stops the refine (the line goes with it).
        _ = type("warmer", c)
        #expect(c.isRefining && c.refineText == "warmer")
        let esc = c.handleKeyDown(escKey).effects
        #expect(esc == [.cancelConversion, .showPanel] && c.phase == .choosing && c.result == first && c.refineHistory.isEmpty)
        #expect(c.refineText.isEmpty)
        #expect(c.receive(shorter, isFinal: true, id: 2).isEmpty && c.result == first)
    }

    @Test func keysTypedWhileARefineRunsWriteTheNextStep() {
        let (c, _) = results()
        _ = type("shorter", c)
        _ = c.handleKeyDown(shiftEnterKey)
        // Typed while it streams: the next step's line; nothing is cancelled, the request goes on.
        var effects = type("more formal", c)
        effects += c.handleKeyDown(backspaceKey).effects + type("l", c)
        #expect(!effects.contains(.cancelConversion) && effects.allSatisfy { $0 == .showPanel })
        #expect(c.isRefining && c.refineText == "more formal" && c.refineLine == "more formal" && c.refineHistory == ["shorter"])
        // ⇧⏎ while it runs starts nothing (the line waits); a digit with a line is text, Space too.
        #expect(started(c.handleKeyDown(shiftEnterKey).effects) == nil && c.isRefining && c.refineText == "more formal")
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi!", isComplete: false)]), isFinal: false, id: 2)
        #expect(c.refineText == "more formal")
        _ = c.receive(shorter, isFinal: true, id: 2)
        #expect(c.phase == .choosing && c.result == shorter && c.refineText == "more formal")
        // Once the results are in, ⇧⏎ runs it on them.
        let run = started(c.handleKeyDown(shiftEnterKey).effects)
        #expect(run?.1 == 3 && run?.0.turns == [Refinement.Turn(answer: first, instruction: "shorter"),
                                                 Refinement.Turn(answer: shorter, instruction: "more formal")])
    }

    @Test func pinyinTypedWhileARefineRunsAndAFailureKeepIt() {
        let (c, engine) = results(english: false)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        _ = type("shorter", c)
        _ = c.handleKeyDown(shiftEnterKey)
        // Shift back to Chinese while it runs, and pinyin for the next step: its candidates show.
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 2)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 2.1)
        _ = type("nihao", c)
        #expect(c.isRefining && c.refineIsComposing && c.refineLine == "nihao")
        _ = c.handleKeyDown(spaceKey)
        #expect(c.refineText == "你好" && c.isRefining)
        // A failure keeps the line typed meanwhile rather than putting the old instruction back.
        _ = c.fail("timeout", id: 2)
        #expect(c.phase == .choosing && c.result == first && c.refineText == "你好" && c.refineError == "timeout")
        // Esc on pinyin typed during a refine: back to the results before it, the pinyin gone with the line.
        _ = type("nihao", c)
        _ = c.handleKeyDown(shiftEnterKey)  // runs "你好你好"
        _ = type("wo", c)
        _ = c.handleKeyDown(escKey)
        #expect(c.phase == .choosing && c.result == first && c.refineText.isEmpty && !engine.snapshot().isComposing)
    }

    @Test func aFailedRefineLeavesTheResultsAndItsInstruction() {
        let (c, _) = results()
        _ = type("shorter", c)
        _ = c.handleKeyDown(shiftEnterKey)
        // Secure input (the controller refuses it like any request), the network …
        #expect(c.fail("Secure input is on", id: 2) == [.showPanel])
        #expect(c.phase == .choosing && c.result == first && c.refineText == "shorter" && c.refineError == "Secure input is on")
        #expect(c.refineHistory.isEmpty)
        // ⇧⏎ runs it again; an answer with nothing in it fails the same way.
        let again = started(c.handleKeyDown(shiftEnterKey).effects)
        #expect(again?.1 == 3 && again?.0.turns == [Refinement.Turn(answer: first, instruction: "shorter")] && c.refineError == nil)
        _ = c.receive(.empty, isFinal: true, id: 3)
        #expect(c.phase == .choosing && c.result == first && c.refineError == c.messages.noResult)
        // The next key clears the error.
        _ = c.handleKeyDown(k("s"))
        #expect(c.refineError == nil && c.refineText == "shorters")
    }

    @Test func refiningAgainSendsTheWholeConversation() {
        let (c, _) = results()
        _ = type("shorter", c)
        _ = c.handleKeyDown(shiftEnterKey)
        _ = c.receive(shorter, isFinal: true, id: 2)
        _ = type("more formal", c)
        let run = started(c.handleKeyDown(shiftEnterKey).effects)
        #expect(run?.1 == 3)
        #expect(run?.0 == Refinement(request: .writing(.improve, input: "hello"), turns: [
            Refinement.Turn(answer: first, instruction: "shorter"), Refinement.Turn(answer: shorter, instruction: "more formal"),
        ]))
    }

    @Test func theActionKeyRunsTheLineToo() {
        let (c, _) = results()
        c.actionKey = .optionSpace
        _ = type("warmer", c)
        #expect(started(c.handleKeyDown(optionSpace).effects)?.0.turns.last?.instruction == "warmer")
    }

    @Test func pinyinInTheLineGoesThroughTheEngine() {
        let (c, engine) = results(english: false)
        #expect(!c.engineState.isAsciiMode)
        _ = type("nihao", c)
        // The candidates are shown (`refineIsComposing`); the results stay.
        #expect(c.refineIsComposing && c.refineLine == "nihao" && c.engineState.candidates.map(\.text) == ["你好", "拟好"])
        #expect(c.phase == .choosing && c.refineText.isEmpty)
        _ = c.handleKeyDown(spaceKey)
        #expect(c.refineText == "你好" && !c.refineIsComposing)
        // A digit picks a candidate while composing; a click on one too.
        _ = type("wo", c)
        _ = c.handleKeyDown(k("2"))
        #expect(c.refineText == "你好窝")
        _ = type("wo", c)
        #expect(c.choose(index: 0).contains(.showPanel) && c.refineText == "你好窝我" && c.phase == .choosing)
        // Esc while composing clears only the pinyin.
        _ = type("ni", c)
        _ = c.handleKeyDown(escKey)
        #expect(c.refineText == "你好窝我" && !engine.snapshot().isComposing)
        // ⇧⏎ on pinyin converts it and runs.
        _ = type("nihao", c)
        let run = started(c.handleKeyDown(shiftEnterKey).effects)
        #expect(run?.0.turns.last?.instruction == "你好窝我你好" && !engine.snapshot().isComposing)
    }

    @Test func shiftSwitchesTheLanguageOfTheLine() {
        let (c, _) = results(english: false)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        let effects = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        #expect(effects.contains(.inputLanguageChanged(.english)) && c.engineState.isAsciiMode && c.phase == .choosing)
        _ = type("more casual", c)
        #expect(c.refineText == "more casual")
    }

    @Test func questionsAndPromptCommandsRefineTheirAnswer() {
        let respond = Command.catalog([CustomCommand(name: "respond", type: .prompt, prompt: "Reply politely.")]).last!
        for (command, letters) in [(Command.question, "question"), (respond, "respond")] {
            let c = Composer(engine: FakeEngine(), actionKey: .enter)
            c.commands = Command.catalog([CustomCommand(name: "respond", type: .prompt, prompt: "Reply politely.")])
            c.setInputMode(.english)
            _ = c.handleKeyDown(at)
            _ = type(letters, c)
            _ = c.handleKeyDown(tab)
            #expect(c.draftCommand == command)
            _ = type("what is rust", c)
            #expect(c.handleKeyDown(enterKey).effects.first == .startCommand(command, input: "what is rust", id: 1))
            let answer = ConversionResult(versions: [CandidateLine("Rust is a systems programming language.")])
            _ = c.receive(answer, isFinal: true, id: 1)
            _ = type("in Japanese", c)
            let run = started(c.handleKeyDown(shiftEnterKey).effects)
            #expect(run?.0 == Refinement(request: .command(command, input: "what is rust"),
                                         turns: [Refinement.Turn(answer: answer, instruction: "in Japanese")]))
            _ = c.receive(ConversionResult(versions: [CandidateLine("Rust はシステム言語です。")]), isFinal: true, id: 2)
            // An @question conversation numbers every round's answer (`QuestionChat`); a refine shows the new one as 1.
            #expect(commits(c.handleKeyDown(k(command == .question ? "2" : "1"))) == ["Rust はシステム言語です。"])
        }
    }

    @Test func resultsThatArentTheAIsKeepTheirKeys() {
        // @open's files: a letter goes back to the draft as before.
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        _ = type("open", c)
        _ = c.handleKeyDown(tab)
        _ = type("notes", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receiveSearch([SearchResult(name: "Notes", path: "/Applications/Notes.app")], id: 1)
        #expect(c.phase == .choosing && !c.canRefine)
        _ = c.handleKeyDown(k("x"))
        #expect(c.phase == .drafting && c.draft == "@open notesx")
        // Typing while the first results still come in continues the sentence, as before.
        let (d, _) = results()
        _ = d.handleKeyDown(escKey)
        _ = d.handleKeyDown(enterKey)
        #expect(d.isLevelTwo && !d.canRefine)
        _ = d.handleKeyDown(k("x"))
        #expect(d.phase == .drafting && d.draft == "@improve hellox")
    }

    // MARK: - Selection

    @Test func aRefinedResultStillReplacesExactlyTheSelection() {
        let selected = "this sentance have a error", range = 11..<37
        let selection = Composer.Selection(text: selected, range: range)
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.readSelection = { selection }
        _ = c.handleKeyDown(at)
        _ = type("i", c)
        _ = c.handleKeyDown(tab)
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: selected, id: 1))
        let answer = ConversionResult(versions: [CandidateLine("This sentence has an error.")])
        _ = c.receive(answer, isFinal: true, id: 1)
        // Typing and running the refine touch nothing in the field.
        var effects = type("shorter", c)
        effects += c.handleKeyDown(shiftEnterKey).effects
        #expect(started(effects)?.0 == Refinement(request: .writing(.improve, input: selected),
                                                  turns: [Refinement.Turn(answer: answer, instruction: "shorter")]))
        effects += c.receive(ConversionResult(versions: [CandidateLine("It has an error.")]), isFinal: true, id: 2)
        let untouched = !effects.contains { effect in
            switch effect {
            case .updateMarkedText, .commit, .replaceSelection, .typeOut: return true
            default: return false
            }
        }
        #expect(untouched && c.selection == selection && c.draftInPanel)
        // Esc goes back one step, still on the selection; the pick replaces exactly it.
        _ = c.handleKeyDown(escKey)
        #expect(c.result == answer && c.selection == selection)
        _ = type("shorter", c)
        _ = c.handleKeyDown(shiftEnterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("It has an error.")]), isFinal: true, id: 3)
        let picked = c.handleKeyDown(enterKey).effects
        #expect(picked.contains(.replaceSelection("It has an error.", selection)) && commits(picked).isEmpty && c.phase == .idle)
    }

    @Test func theEditModeOnASelectionRefinesItsText() {
        let text = "First paragraph here.\n\nsecond one, it have errors"
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.readSelection = { Composer.Selection(text: text, range: 0..<text.utf16.count) }
        _ = c.handleKeyDown(at)
        _ = type("i", c)
        _ = c.handleKeyDown(tab)
        let input = Prompt.editRequest(instruction: "improve", text: text)
        #expect(c.handleKeyDown(enterKey).effects.first == .startCommand(.edit, input: input, id: 1))
        let answer = ConversionResult(versions: [CandidateLine("First paragraph here.\n\nThe second one has errors.")])
        _ = c.receive(answer, isFinal: true, id: 1)
        _ = type("warmer", c)
        #expect(started(c.handleKeyDown(shiftEnterKey).effects)?.0.request == .command(.edit, input: input))
    }

    // MARK: - Prompts

    /// The requests @improve, @translate and prompt commands send are byte for byte those of 0.6.3: only a refine adds
    /// anything. @question's are too, but for the rule about live data 0.6.4 added at the end of its system prompt.
    @Test func normalRequestsAreUnchangedSinceRelease063() throws {
        let url = try #require(Bundle.module.url(forResource: "prompts-release-0.6.3", withExtension: "json", subdirectory: "Fixtures"))
        let golden = try Data(contentsOf: url)
        #expect(try PromptGolden.json(withoutLiveDataRule: true) == golden)
        #expect(try PromptGolden.json() != golden)
        #expect(Prompt.version == 7 && Prompt.commandVersion == 4)
    }

    /// @question says it can't check live data (the weather, news, prices, scores, "today's" anything) instead of
    /// making it up; no other command's prompt has the rule.
    @Test func questionRefusesToMakeUpLiveData() {
        let system = Prompt.commandSystem(.question)
        #expect(system.hasSuffix(" If you are not sure, say so briefly. " + Prompt.liveDataRule))
        for word in ["weather", "news", "prices", "scores", "today", "can't check live information", "general guidance"] {
            #expect(Prompt.liveDataRule.contains(word), "\(word)")
        }
        let respond = Command.catalog([CustomCommand(name: "respond", type: .prompt, prompt: "Reply politely.")]).last!
        for command in [Command.edit, .agent, respond] { #expect(!Prompt.commandSystem(command).contains(Prompt.liveDataRule)) }
        #expect(!Prompt.system(styles: RewriteStyle.resolve(RewriteStyle.defaultNames)).contains("live information"))
    }

    @Test func theRefineRequestIsTheNormalOneThenTheConversation() {
        var config = Config.default
        config.setOrder([OutputLanguage.english, .chinese])
        let normal = Prompt.request(for: "我今天有点不舒服", mode: .both, config: config)
        let answer = ConversionResult(
            versions: [CandidateLine("I'm not feeling well today."), CandidateLine("I feel a bit off today."), CandidateLine("I'm under the weather.")],
            rewrites: [Rewrite(style: "润色", line: CandidateLine("我今天身体有点不舒服。")), Rewrite(style: "简洁", line: CandidateLine("今天不太舒服。"))])
        let turns = [Refinement.Turn(answer: answer, instruction: "shorter"), Refinement.Turn(answer: shorter, instruction: "用更口语的说法")]
        let refine = Prompt.refineRequest(for: "我今天有点不舒服", mode: .both, config: config, turns: turns)
        // The same system prompt, the refine rules after it; the same examples and sentence, then the turns.
        let system = refine.system.first?.text ?? ""
        #expect(system == (normal.system.first?.text ?? "") + "\n\n" + Prompt.writingRefineRules)
        #expect(Array(refine.messages.prefix(normal.messages.count)) == normal.messages)
        let rest = refine.messages.dropFirst(normal.messages.count).map { ($0.role, $0.content.first?.text ?? "") }
        #expect(rest.map(\.0) == ["assistant", "user", "assistant", "user"])
        #expect(rest[1].1 == "<refine>shorter</refine>" && rest[3].1 == "<refine>用更口语的说法</refine>")
        // The answers are written in the line format: they read back as the results they were.
        #expect(rest[0].1 == "EN: I'm not feeling well today.\nEN: I feel a bit off today.\nEN: I'm under the weather.\n"
                + "STYLE_POLISH: 我今天身体有点不舒服。\nSTYLE_CONCISE: 今天不太舒服。")
        #expect(CandidateParser.parse(rest[0].1, isFinal: true) == answer)
        #expect(CandidateParser.parse(rest[2].1, isFinal: true) == shorter)
        #expect(refine.inferenceConfig.temperature == normal.inferenceConfig.temperature)
    }

    @Test func translationsIntoSeveralLanguagesKeepTheirTags() {
        var config = Config.default
        config.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja")])
        let answer = ConversionResult(translations: [
            Translation(language: .english, line: CandidateLine("Thanks for your hard work.")),
            Translation(language: OutputLanguage("ja"), line: CandidateLine("お疲れさまです。")),
        ])
        let refine = Prompt.refineRequest(for: "辛苦了", mode: .translate, config: config,
                                          turns: [Refinement.Turn(answer: answer, instruction: "warmer")])
        let written = refine.messages[refine.messages.count - 2].content.first?.text ?? ""
        #expect(written == "EN: Thanks for your hard work.\nJA: お疲れさまです。")
        #expect(CandidateParser.parse(written, isFinal: true, output: nil, translations: [.english, OutputLanguage("ja")]) == answer)
    }

    @Test func theCommandRefineRequestIsTheNormalOneThenTheConversation() {
        let config = Config.default
        let normal = Prompt.commandRequest(.question, input: "what is rust", config: config)
        let answer = ConversionResult(versions: [CandidateLine("Rust is a systems language.")])
        let refine = Prompt.commandRefineRequest(.question, input: "what is rust", config: config,
                                                 turns: [Refinement.Turn(answer: answer, instruction: "in Japanese")])
        #expect(refine.system.first?.text == Prompt.commandSystem(.question) + "\n\n" + Prompt.commandRefineRules)
        #expect(refine.messages.map(\.role) == ["user", "assistant", "user"] && refine.messages.first == normal.messages.first)
        #expect(refine.messages.map { $0.content.first?.text ?? "" }
                == ["what is rust", "Rust is a systems language.", "<refine>in Japanese</refine>"])
        #expect(refine.inferenceConfig == normal.inferenceConfig)
        // The edit mode keeps its own instructions.
        let edit = Prompt.commandRefineRequest(.edit, input: "x", config: config, turns: [Refinement.Turn(answer: answer, instruction: "y")])
        #expect(edit.system.first?.text.hasPrefix(Prompt.editSystem) == true)
    }

    @Test func eachConversationHasItsOwnCacheKey() {
        let a = Prompt.turnsKey([Refinement.Turn(answer: first, instruction: "shorter")])
        let b = Prompt.turnsKey([Refinement.Turn(answer: first, instruction: "longer")])
        let c = Prompt.turnsKey([Refinement.Turn(answer: shorter, instruction: "shorter")])
        #expect(Set([a, b, c]).count == 3 && a.hasPrefix("refine\(Prompt.refineVersion)|"))
    }

    // MARK: - Converter

    @Test func aRefineIsSentWithTheConversationAndCached() async throws {
        let region = "us-refine-1"
        let host = "bedrock-runtime.\(region).amazonaws.com"
        StubURLProtocol.register(host: host, .init(
            status: 200, headers: ["Content-Type": "application/vnd.amazon.eventstream"],
            chunks: [Data(try fixture("bedrock-converse-stream"))]))
        var config = Config.default
        config.region = region
        config.awsProfile = "test"
        let fixed = config
        let converter = Converter(
            client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed },
            loadCredentials: { _ in
                AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIDTEST", secretAccessKey: "secret"), region: nil)
            })
        func collect(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> ConversionUpdate? {
            var last: ConversionUpdate?
            for try await update in stream { last = update }
            return last
        }
        let turns = [Refinement.Turn(answer: first, instruction: "shorter")]
        let refined = try #require(try await collect(converter.convert("我今天有点不舒服", turns: turns)))
        #expect(refined.isFinal && !refined.fromCache && refined.result.versions.count == 3)
        let request = try #require(StubURLProtocol.lastRequest(host: host))
        // URLSession hands the body to a protocol as a stream.
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                guard n > 0 else { break }
                data.append(buffer, count: n)
            }
            stream.close()
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("<refine>shorter</refine>") && body.contains("Follow-up instructions"))
        // The same refine again: from the cache. The plain request isn't the refine's.
        #expect(try await collect(converter.convert("我今天有点不舒服", turns: turns))?.fromCache == true)
        #expect(try await collect(converter.convert("我今天有点不舒服"))?.fromCache == false)
        #expect(try await collect(converter.convert("我今天有点不舒服"))?.fromCache == true)
    }
}
