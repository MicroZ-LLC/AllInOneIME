import Foundation
import Testing
@testable import AllInOneIMECore

/// ⇧⏎: sends a follow-up (an @question conversation's next question, or a refine) once one is typed.
let shiftEnterKey = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)

/// An @question conversation in the panel (`QuestionChat`, `Composer+QuestionChat.swift`): the request of each round, the
/// fitting into the on-device model's context, the keys, the hand-off (`ChatHandoff`) and the saved threads.
struct QuestionChatTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    let commandReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .command)
    func command(_ digit: Int) -> KeyEvent {
        KeyEvent(keyCode: 0, characters: String(digit), charactersIgnoringModifiers: String(digit), modifiers: .command)
    }

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
    }

    func started(_ effects: [Composer.Effect]) -> (Refinement, Int)? {
        effects.lazy.compactMap { if case let .startRefine(r, id) = $0 { return (r, id) } else { return nil } }.first
    }

    func answer(_ text: String) -> ConversionResult { ConversionResult(versions: [CandidateLine(text)]) }

    /// "@question <question>" ⏎ in English, answered with `first` (request 1).
    func asked(_ question: String = "what is rust", first: String = "A systems language.", rounds: Int = 5,
               handoff: [ChatHandoff.Destination] = [.claudeCode, .claudeWeb, .chatgpt, .copy]) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.questionRounds = rounds
        c.handoffChoices = handoff
        c.remembersQuestions = false
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type(question, c)
        #expect(c.handleKeyDown(enterKey).effects.first == .startCommand(.question, input: question, id: 1))
        _ = c.receive(answer(first), isFinal: true, id: 1)
        #expect(c.isQuestionChat && c.phase == .choosing)
        return c
    }

    /// Types `question` and asks it with ⇧⏎; answered with `reply`.
    @discardableResult
    func followUp(_ c: Composer, _ question: String, reply: String) -> Refinement? {
        type(question, c)
        let run = started(c.handleKeyDown(shiftEnterKey).effects)
        if let run { _ = c.receive(answer(reply), isFinal: true, id: run.1) }
        return run?.0
    }

    // MARK: - The request

    @Test func theFirstRoundIsTheNormalQuestionRequest() {
        var config = Config.default
        for question in ["what is rust", "量子计算是什么", Prompt.question("what is this", about: "Lorem")] {
            #expect(QuestionChat.request([], question: question, config: config) == Prompt.commandRequest(.question, input: question, config: config))
        }
        config.provider = .apple
        #expect(QuestionChat.request(first: "q", turns: [], config: config) == Prompt.commandRequest(.question, input: "q", config: config))
    }

    @Test func aFollowUpIsTheRoundsAsTurnsThenTheQuestion() {
        let config = Config.default
        let rounds = [QuestionChat.Round(question: "what is rust", answer: "A language."),
                      QuestionChat.Round(question: "who made it", answer: "Graydon Hoare.")]
        let request = QuestionChat.request(rounds, question: "when?", config: config)
        let normal = Prompt.commandRequest(.question, input: "when?", config: config)
        #expect(request.system == normal.system && request.inferenceConfig == normal.inferenceConfig)
        #expect(request.messages.map(\.role) == ["user", "assistant", "user", "assistant", "user"])
        #expect(request.messages.map { $0.content.map(\.text).joined() } == ["what is rust", "A language.", "who made it", "Graydon Hoare.", "when?"])
        // Plain messages: not the refine wording.
        #expect(!request.messages.contains { $0.content.contains { $0.text.contains("<refine>") } })
        #expect(!request.system.contains { $0.text.contains("Follow-up instructions") })
        // The same from the refine plumbing the composer keeps the rounds in.
        let (first, turns, latest) = QuestionChat.turns(rounds + [QuestionChat.Round(question: "when?", answer: "")])
        #expect(first == "what is rust" && latest.isEmpty && turns.map(\.instruction) == ["who made it", "when?"])
        #expect(QuestionChat.request(first: first, turns: turns, config: config) == request)
        #expect(QuestionChat.rounds(first: first, turns: turns, latest: "In 2006.").map(\.answer) == ["A language.", "Graydon Hoare.", "In 2006."])
    }

    @Test func theRoundLimitIsKeptWithinTwoToTen() {
        #expect(QuestionChat.defaultRounds == 5 && QuestionChat.roundRange == 2...10)
        #expect([0, 1, 2, 5, 10, 11, 99].map(QuestionChat.rounds) == [2, 2, 2, 5, 10, 10, 10])
    }

    // MARK: - Fitting the on-device model's context

    func size(_ request: ConverseRequest) -> Int {
        AppleModel.estimatedTokens(request.system.map(\.text).joined(separator: "\n\n"))
            + request.messages.reduce(0) { $0 + AppleModel.estimatedTokens($1.content.map(\.text).joined()) }
    }

    @Test func aShortConversationIsSentWhole() {
        let rounds = (1...4).map { QuestionChat.Round(question: "question \($0)", answer: "answer \($0)") }
        let request = QuestionChat.request(rounds, question: "and then?", config: .default)
        let (fitted, shortened) = QuestionChat.fit(request, contextSize: 4096, maxTokens: 1000)
        #expect(fitted == request && !shortened)
    }

    @Test func theOldestAnswersLoseTheirMiddlesFirstThenTheOldestRoundsGo() {
        let long = String(repeating: "word ", count: 600)  // ~1000 tokens by the estimate
        let rounds = (1...4).map { QuestionChat.Round(question: "question \($0)", answer: "start \($0) " + long + " end \($0)") }
        let request = QuestionChat.request(rounds, question: "the last question", config: .default)
        // 4K: the middles of the oldest answers go, as many as needed, oldest first.
        let (fitted, shortened) = QuestionChat.fit(request, contextSize: 4096, maxTokens: 1000)
        #expect(shortened && size(fitted) + min(1000, AppleModel.answerRoom, 4096 / 3) <= 4096)
        #expect(fitted.messages.count == request.messages.count)
        let answers = fitted.messages.filter { $0.role == "assistant" }.map { $0.content.map(\.text).joined() }
        #expect(answers[0].hasPrefix("start 1 ") && answers[0].hasSuffix(" end 1") && answers[0].contains(QuestionChat.cut))
        #expect(answers[0].count < 200)
        #expect(answers.last == rounds.last?.answer)  // the newest only when it must
        // The last question whole, the questions as they were.
        #expect(fitted.messages.last?.content.first?.text == "the last question")
        #expect(fitted.messages.filter { $0.role == "user" }.map { $0.content.map(\.text).joined() }
                == request.messages.filter { $0.role == "user" }.map { $0.content.map(\.text).joined() })
        // A context so small that shortened answers aren't enough: the oldest rounds go too.
        let (tiny, cut) = QuestionChat.fit(request, contextSize: 800, maxTokens: 1000)
        #expect(cut && tiny.messages.count < request.messages.count && tiny.messages.count % 2 == 1)
        #expect(tiny.messages.last?.content.first?.text == "the last question" && tiny.messages.first?.role == "user")
        #expect(size(tiny) + min(1000, AppleModel.answerRoom, 800 / 3) <= 800)
        // 8K (macOS 27) keeps more than 4K.
        let (wide, _) = QuestionChat.fit(request, contextSize: 8192, maxTokens: 1000)
        let kept = { (r: ConverseRequest) in r.messages.filter { !$0.content.map(\.text).joined().contains(QuestionChat.cut) }.count }
        #expect(kept(wide) > kept(fitted))
    }

    @Test func theConverterFitsAConversationForTheOnDeviceModelAndSaysSo() async throws {
        var config = Config.default
        config.provider = .apple
        let fixed = config
        let long = String(repeating: "很长的回答。", count: 400)
        let turns = (1...3).map { Refinement.Turn(answer: answer("答\($0)" + long), instruction: "问题 \($0 + 1)") }
        // The model's context: 4K; the conversation doesn't fit whole.
        let stub = StubAppleModel(contextSize: 4096, answer: ["好的。"])
        let converter = Converter(loadConfig: { fixed }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                                  loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: stub)
        var last: ConversionUpdate?
        for try await update in converter.generate(.question, input: "问题 1", turns: turns) { last = update }
        #expect(last?.isFinal == true && last?.shortened == true && last?.result.versions.first?.text == "好的。")
        let request = try #require(stub.requests.first)
        #expect(request.prompt == "问题 4" && request.instructions == Prompt.commandSystem(.question))
        #expect(request.examples.allSatisfy { !$0.prompt.contains("<refine>") })
        // A short one is sent whole, and isn't said to be shortened.
        let short = StubAppleModel(contextSize: 4096, answer: ["OK."])
        let whole = Converter(loadConfig: { fixed }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                              loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: short)
        var final: ConversionUpdate?
        for try await update in whole.generate(.question, input: "what is rust",
                                               turns: [Refinement.Turn(answer: answer("A language."), instruction: "who made it")]) {
            final = update
        }
        #expect(final?.shortened == false)
        // The same long conversation again, from the cache: still said to be shortened.
        var again: ConversionUpdate?
        for try await update in converter.generate(.question, input: "问题 1", turns: turns) { again = update }
        #expect(again?.fromCache == true && again?.shortened == true && stub.requests.count == 1)
        let sent = try #require(short.requests.first)
        #expect(sent.examples.map(\.prompt) == ["what is rust"] && sent.examples.map(\.response) == ["A language."] && sent.prompt == "who made it")
    }

    @Test func otherProvidersGetTheWholeConversationAndItIsCached() async throws {
        let rig = RARig()
        RAStubProtocol.enqueue(rig.host, .answer("In 2006."))
        let long = String(repeating: "word ", count: 3000)
        let turns = [Refinement.Turn(answer: answer("A language. " + long), instruction: "when was it made?")]
        var finals: [ConversionUpdate] = []
        for _ in 0..<2 {
            for try await update in rig.converter.generate(.question, input: "what is rust", turns: turns) where update.isFinal {
                finals.append(update)
            }
        }
        let sent = try rig.sent()
        try #require(sent.count == 1)  // the second time from the cache
        #expect(finals.map(\.fromCache) == [false, true] && finals.allSatisfy { !$0.shortened })
        #expect(sent[0].messages.map(\.role) == ["user", "assistant", "user"])
        #expect(sent[0].messages.map(\.text) == ["what is rust", "A language. " + long, "when was it made?"])
        #expect(sent[0].system == Prompt.commandSystem(.question))
    }

    @Test func valuesHiddenFromTheAIAreHiddenInEveryRound() async throws {
        var config = Config.default
        config.provider = .apple
        config.redaction = RedactionSettings(enabled: true)
        let fixed = config
        let stub = StubAppleModel(answer: ["Write to [EMAIL_1] and [EMAIL_2]."])
        let converter = Converter(loadConfig: { fixed }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                                  loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: stub)
        let turns = [Refinement.Turn(answer: answer("Email bob@example.com."), instruction: "and alice@corp.example?")]
        var last: ConversionUpdate?
        for try await update in converter.generate(.question, input: "how do I reach bob@example.com", turns: turns) { last = update }
        let request = try #require(stub.requests.first)
        let all = ([request.instructions, request.prompt] + request.examples.flatMap { [$0.prompt, $0.response] }).joined(separator: "\n")
        #expect(!all.contains("bob@example.com") && !all.contains("alice@corp.example"))
        #expect(request.prompt == "and [EMAIL_2]?" && request.examples.map(\.response) == ["Email [EMAIL_1]."])
        #expect(last?.result.versions.first?.text == "Write to bob@example.com and alice@corp.example." && last?.hidden == 2)
    }

    // MARK: - Keys

    @Test func typingAfterTheAnswerIsTheNextQuestionAndShiftReturnAsksIt() {
        let c = asked()
        #expect(c.chatRounds == [QuestionChat.Round(question: "what is rust", answer: "A systems language.")] && c.chatRound == 1)
        #expect(c.choices.map(\.label) == ["1"] && c.choices.map(\.kind) == [.answer] && c.highlighted == 0)
        type("who made it", c)
        #expect(c.refineLine == "who made it" && c.phase == .choosing && c.typesRefine)
        let run = c.handleKeyDown(shiftEnterKey).effects
        let refinement = Refinement(request: .command(.question, input: "what is rust"),
                                    turns: [Refinement.Turn(answer: answer("A systems language."), instruction: "who made it")])
        #expect(run == [.startRefine(refinement, id: 2), .showPanel])
        #expect(c.isQuestionChat && c.chatRound == 2 && c.refineText.isEmpty)
        // While it comes in: the earlier answer and the one coming, which can't be picked yet (and is selected).
        _ = c.receive(ConversionResult(versions: [CandidateLine("Graydon", isComplete: false)]), isFinal: false, id: 2)
        #expect(c.choices.map(\.isComplete) == [true, false] && c.highlighted == 1)
        #expect(commits(c.handleKeyDown(enterKey)).isEmpty)
        _ = c.receive(answer("Graydon Hoare."), isFinal: true, id: 2)
        #expect(c.chatRounds.map(\.question) == ["what is rust", "who made it"])
        #expect(c.choices.map(\.text) == ["A systems language.", "Graydon Hoare."] && c.choices.map(\.label) == ["1", "2"])
        #expect(c.highlighted == 1 && c.copyableText == "Graydon Hoare.")
    }

    @Test func returnInsertsTheSelectedAnswerAndDropsWhatIsTyped() {
        let c = asked()
        followUp(c, "who made it", reply: "Graydon Hoare.")
        type("and when", c)
        #expect(commits(c.handleKeyDown(enterKey)) == ["Graydon Hoare."] && c.phase == .idle && c.refineText.isEmpty)
        // Space with nothing typed inserts too; with something typed it's a space in the question.
        let d = asked()
        type("why", d)
        _ = d.handleKeyDown(spaceKey)
        #expect(d.refineText == "why " && d.isLevelTwo)
        let e = asked()
        #expect(commits(e.handleKeyDown(spaceKey)) == ["A systems language."])
    }

    @Test func everyRoundsAnswerCanBePicked() {
        let c = asked()
        followUp(c, "who made it", reply: "Graydon Hoare.")
        followUp(c, "when", reply: "In 2006.")
        #expect(c.choices.map(\.label) == ["1", "2", "3"] && c.highlighted == 2)
        // ↑ moves the selection to an earlier answer; ⌘C copies it; ⏎ inserts it.
        _ = c.handleKeyDown(upKey)
        #expect(c.highlighted == 1 && c.copyableText == "Graydon Hoare.")
        #expect(c.handleKeyDown(k("c", mods: .command)).effects.first == .copy("Graydon Hoare."))
        #expect(commits(c.handleKeyDown(enterKey)) == ["Graydon Hoare."])
        // A digit inserts its round's answer at once; a click too.
        let d = asked()
        followUp(d, "who made it", reply: "Graydon Hoare.")
        #expect(commits(d.handleKeyDown(k("1"))) == ["A systems language."])
        let e = asked()
        followUp(e, "who made it", reply: "Graydon Hoare.")
        #expect(commits(e.choose(index: 0)) == ["A systems language."])
        // With a question typed, digits are part of it.
        let f = asked()
        type("in 2", f)
        #expect(f.refineText == "in 2" && f.isLevelTwo)
    }

    @Test func shiftReturnWithNothingTypedInsertsAsTyped() {
        let c = asked()
        #expect(commits(c.handleKeyDown(shiftEnterKey)) == ["@question what is rust"] && c.phase == .idle)
        // After a round too: as typed is the draft (the first question).
        let d = asked()
        followUp(d, "who made it", reply: "Graydon Hoare.")
        #expect(commits(d.handleKeyDown(shiftEnterKey)) == ["@question what is rust"])
    }

    @Test func escClearsTheQuestionThenGoesBackARoundThenLeaves() {
        let c = asked()
        followUp(c, "who made it", reply: "Graydon Hoare.")
        followUp(c, "when", reply: "In 2006.")
        type("where", c)
        _ = c.handleKeyDown(escKey)
        #expect(c.refineText.isEmpty && c.chatRound == 3)
        _ = c.handleKeyDown(escKey)
        #expect(c.chatRound == 2 && c.chatRounds.last == QuestionChat.Round(question: "who made it", answer: "Graydon Hoare."))
        _ = c.handleKeyDown(escKey)
        #expect(c.chatRound == 1 && c.choices.map(\.text) == ["A systems language."] && c.isLevelTwo)
        _ = c.handleKeyDown(escKey)
        #expect(!c.isLevelTwo && c.draft == "@question what is rust")
    }

    @Test func aFailedFollowUpKeepsTheRoundsAndPutsTheQuestionBack() {
        let c = asked()
        type("who made it", c)
        _ = c.handleKeyDown(shiftEnterKey)
        _ = c.fail("timeout", id: 2)
        #expect(c.phase == .choosing && c.chatRound == 1 && c.refineText == "who made it" && c.refineError == "timeout")
        // In an app with no AI nothing is asked.
        c.aiRefusal = { "No AI in this app" }
        #expect(c.handleKeyDown(shiftEnterKey).effects == [.showPanel] && c.refineError == "No AI in this app")
    }

    @Test func aFollowUpCanBeLongerThanARefineInstruction() {
        let c = asked()
        type("x", c)
        for _ in 0..<500 { _ = c.handleKeyDown(k("abcde")) }
        #expect(c.refineText.count == QuestionChat.maxFollowUpLength && QuestionChat.maxFollowUpLength > Refinement.maxInstructionLength)
    }

    @Test func pinyinInTheQuestionGoesThroughTheEngine() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.remembersQuestions = false
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type("rust", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(answer("A language."), isFinal: true, id: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        type("nihao", c)
        #expect(c.refineIsComposing && c.refineLine == "nihao")
        // ⇧⏎ converts the pinyin and asks.
        let run = started(c.handleKeyDown(shiftEnterKey).effects)
        #expect(run?.0.turns.last?.instruction == "你好")
    }

    // MARK: - After the last round: going on elsewhere

    @Test func afterTheLastRoundTheHandoffIsShownAndTypingIsItsFirstMessage() {
        let c = asked(rounds: 2)
        #expect(!c.showsHandoff && !c.chatAtLimit)
        followUp(c, "who made it", reply: "Graydon Hoare.")
        #expect(c.chatAtLimit && c.showsHandoff && c.chatRound == 2)
        // Typing doesn't ask a third question, nor does ⇧⏎ launch anything: the choices stay up, the text kept for them.
        type("go deeper", c)
        #expect(c.handleKeyDown(shiftEnterKey).effects == [.showPanel] && c.showsHandoff && c.refineText == "go deeper")
        #expect(c.isLevelTwo && c.chatRound == 2)
        // ⌘1 (Claude Code here) goes on there with it.
        let effects = c.handleKeyDown(command(1)).effects
        #expect(started(effects) == nil && c.phase == .idle)
        let prompt = effects.compactMap { if case let .continueInClaudeCode(p) = $0 { return p } else { return nil } }.first
        #expect(prompt == "**Q:** what is rust\n\n**A:** A systems language.\n\n**Q:** who made it\n\n**A:** Graydon Hoare.\n\n"
                + "Let's continue this discussion.\n\ngo deeper")
        #expect(effects.contains(.hidePanel) && commits(effects).isEmpty && effects.contains(.notice(c.messages.openedTerminal)))
    }

    /// Another agent than Claude Code: its own effect, and the notice names it (a custom one by its program).
    @Test func anotherAgentIsHandedTheConversationByItsOwnEffect() {
        let c = asked(rounds: 2, handoff: [.kiroCLI, .customAgent, .copy])
        c.messages = .english
        c.messages.agentNames = [.custom: "muse"]
        followUp(c, "who made it", reply: "Graydon Hoare.")
        let kiro = c.handleKeyDown(command(1)).effects
        #expect(kiro.contains { if case .continueInAgent(.kiro, _) = $0 { return true } else { return false } })
        #expect(!kiro.contains { if case .continueInClaudeCode = $0 { return true } else { return false } })
        #expect(kiro.contains(.notice("Opened Kiro CLI in Terminal")))
        let again = asked(rounds: 2, handoff: [.kiroCLI, .customAgent, .copy])
        again.messages.agentNames = [.custom: "muse"]
        followUp(again, "who made it", reply: "Graydon Hoare.")
        let custom = again.handleKeyDown(command(2)).effects
        #expect(custom.contains { if case .continueInAgent(.custom, _) = $0 { return true } else { return false } })
        #expect(custom.contains(.notice("已在终端打开 muse")))
    }

    @Test func commandDigitsPickWhereToGoOnOnceShown() {
        let c = asked(rounds: 2)
        followUp(c, "who made it", reply: "Graydon Hoare.")
        // ⌘2: Claude on the web, the conversation in the address.
        let web = c.handleKeyDown(command(2))
        let url = web.effects.compactMap { if case let .openLink(u) = $0 { return u } else { return nil } }.first
        #expect(web.handled && url?.absoluteString.hasPrefix("https://claude.ai/new?q=%2A%2AQ%3A%2A%2A%20what%20is%20rust") == true)
        #expect(!web.effects.contains { if case .copy = $0 { true } else { false } })
        // ⌘4: copy, in Markdown.
        let d = asked(rounds: 2)
        followUp(d, "who made it", reply: "Graydon Hoare.")
        let copy = d.handleKeyDown(command(4)).effects
        #expect(copy.contains(.copy("**Q:** what is rust\n\n**A:** A systems language.\n\n**Q:** who made it\n\n**A:** Graydon Hoare.")))
        #expect(copy.contains(.notice(d.chatMessages.copiedConversation)) && d.phase == .idle)
        // A ⌘-digit past the choices does nothing.
        let e = asked(rounds: 2)
        followUp(e, "who made it", reply: "Graydon Hoare.")
        #expect(e.handleKeyDown(command(9)) == .consumed() && e.isLevelTwo)
    }

    @Test func commandReturnShowsTheChoicesAtAnyRoundAndEscHidesThem() {
        let c = asked()
        // Not shown: ⌘1 is the app's.
        #expect(!c.handleKeyDown(command(1)).handled)
        #expect(c.handleKeyDown(commandReturn).effects == [.showPanel] && c.showsHandoff && !c.chatAtLimit)
        _ = c.handleKeyDown(escKey)
        #expect(!c.showsHandoff && c.isLevelTwo && c.chatRound == 1)
        // Shown, a follow-up typed goes with the hand-off; ⇧⏎ asks nothing and launches nothing then.
        _ = c.handleKeyDown(commandReturn)
        type("more", c)
        #expect(c.handleKeyDown(shiftEnterKey).effects == [.showPanel] && c.showsHandoff && c.chatRound == 1 && c.refineText == "more")
        let effects = c.handleKeyDown(command(3)).effects
        let url = effects.compactMap { if case let .openLink(u) = $0 { return u } else { return nil } }.first
        #expect(url?.host == "chatgpt.com" && url?.absoluteString.hasSuffix("discussion.%0A%0Amore") == true)
    }

    @Test func everyEscAtTheLastRoundDoesSomething() {
        // ⇧⏎ with a follow-up at the limit, then Esc: the follow-up goes; the next Esc goes back a round.
        let c = asked(rounds: 2)
        followUp(c, "who made it", reply: "Graydon Hoare.")
        type("more", c)
        _ = c.handleKeyDown(shiftEnterKey)
        _ = c.handleKeyDown(escKey)
        #expect(c.refineText.isEmpty && c.showsHandoff && c.chatRound == 2)
        _ = c.handleKeyDown(escKey)
        #expect(!c.showsHandoff && c.chatRound == 1)
        // ⌘⏎ at the limit (the choices are up already), then Esc: back a round at once.
        let d = asked(rounds: 2)
        followUp(d, "who made it", reply: "Graydon Hoare.")
        _ = d.handleKeyDown(commandReturn)
        _ = d.handleKeyDown(escKey)
        #expect(!d.showsHandoff && d.chatRound == 1)
        // ⌘⏎ before the limit, a round asked meanwhile up to it: Esc goes back a round there too.
        let e = asked(rounds: 2)
        _ = e.handleKeyDown(commandReturn)
        _ = e.handleKeyDown(escKey)
        followUp(e, "who made it", reply: "Graydon Hoare.")
        _ = e.handleKeyDown(escKey)
        #expect(e.chatRound == 1 && !e.showsHandoff)
    }

    @Test func theRoundsGoBackFromTheHandoffWithEsc() {
        let c = asked(rounds: 2)
        followUp(c, "who made it", reply: "Graydon Hoare.")
        #expect(c.showsHandoff)
        _ = c.handleKeyDown(escKey)
        #expect(!c.showsHandoff && c.chatRound == 1)
        // A question can be asked again from there.
        #expect(followUp(c, "who designed it", reply: "Graydon.") != nil && c.chatAtLimit)
    }

    @Test func noHandoffDuringSecureInputButCopying() {
        let c = asked(rounds: 2)
        followUp(c, "who made it", reply: "Graydon Hoare.")
        c.secureInputActive = { true }
        #expect(c.handleKeyDown(command(1)).effects == [.notice(c.chatMessages.secureInput), .showPanel] && c.isLevelTwo)
        #expect(c.handleKeyDown(command(4)).effects.contains { if case .copy = $0 { true } else { false } })
    }

    @Test func aHandoffOnASelectionLeavesItAndCarriesIt() {
        let selection = Composer.Selection(text: "Error 404 at /api", range: 3..<20)
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.handoffChoices = [.copy]
        c.readSelection = { selection }
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type("what does it mean", c)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(answer("Not found."), isFinal: true, id: 1)
        #expect(c.chatRounds.first?.question == "what does it mean")
        _ = c.handleKeyDown(commandReturn)
        let effects = c.handleKeyDown(command(1)).effects
        // The selected text as a quoted block of its own, the question as typed: no tags of ours.
        #expect(effects.contains(.copy("**Selected text:**\n\n> Error 404 at /api\n\n**Q:** what does it mean\n\n**A:** Not found.")))
        #expect(!effects.contains { if case let .copy(text) = $0 { text.contains("selected_text") } else { false } })
        #expect(!effects.contains { if case .replaceSelection = $0 { true } else { false } } && commits(effects).isEmpty)
    }

    @Test func commandReturnIsNeverTheAppsWhileAnAnswerComesIn() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.remembersQuestions = false
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        type("what is rust", c)
        _ = c.handleKeyDown(enterKey)
        // Round 1 coming in: consumed, nothing happens.
        #expect(c.handleKeyDown(commandReturn) == .consumed() && !c.showsHandoff)
        _ = c.receive(ConversionResult(versions: [CandidateLine("A sys", isComplete: false)]), isFinal: false, id: 1)
        #expect(c.handleKeyDown(commandReturn) == .consumed())
        _ = c.receive(answer("A systems language."), isFinal: true, id: 1)
        // A follow-up coming in: the same.
        type("who", c)
        _ = c.handleKeyDown(shiftEnterKey)
        #expect(c.isRefining && c.handleKeyDown(commandReturn) == .consumed() && !c.showsHandoff)
        _ = c.receive(answer("Graydon."), isFinal: true, id: 2)
        // In: the choices.
        #expect(c.handleKeyDown(commandReturn).effects == [.showPanel] && c.showsHandoff)
        // After a failure too (nothing to show), and elsewhere ⌘⏎ is still the app's.
        let d = asked()
        _ = d.handleKeyDown(escKey)
        _ = d.handleKeyDown(enterKey)
        _ = d.fail("timeout", id: 2)
        #expect(d.handleKeyDown(commandReturn) == .consumed())
        #expect(!Composer(engine: FakeEngine(), actionKey: .enter).handleKeyDown(commandReturn).handled)
    }

    @Test func theHandoffTextQuotesTheSelectionWithoutTags() {
        let rounds = [QuestionChat.Round(question: "what is this", answer: "A greeting.")]
        #expect(ChatHandoff.prompt(rounds, selection: "Hello,\n\nworld") ==
                "**Selected text:**\n\n> Hello,\n>\n> world\n\n**Q:** what is this\n\n**A:** A greeting.\n\nLet's continue this discussion.")
        #expect(ChatHandoff.copied(rounds, selection: "  ") == ChatHandoff.copied(rounds))
    }

    // MARK: - Other commands keep refining; @translate doesn't

    @Test func improveRefinesWithShiftReturnAndReturnInserts() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("improve", c)
        _ = c.handleKeyDown(tab)
        type("hello", c)
        _ = c.handleKeyDown(enterKey)
        let first = ConversionResult(versions: [CandidateLine("Hello there."), CandidateLine("Hi.")])
        _ = c.receive(first, isFinal: true, id: 1)
        #expect(c.canRefine && !c.isQuestionChat)
        type("shorter", c)
        #expect(commits(c.handleKeyDown(enterKey)) == ["Hello there."] && c.phase == .idle)
        let d = Composer(engine: FakeEngine(), actionKey: .enter)
        d.setInputMode(.english)
        _ = d.handleKeyDown(at)
        type("improve", d)
        _ = d.handleKeyDown(tab)
        type("hello", d)
        _ = d.handleKeyDown(enterKey)
        _ = d.receive(first, isFinal: true, id: 1)
        #expect(commits(d.handleKeyDown(shiftEnterKey)) == ["@improve hello"])  // nothing typed: as typed
    }

    @Test func translateHasNoRefineTypingGoesBackToItsText() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("translate", c)
        _ = c.handleKeyDown(tab)
        type("hello", c)
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "hello", id: 1))
        _ = c.receive(ConversionResult(versions: [CandidateLine("你好")]), isFinal: true, id: 1)
        #expect(!c.canRefine && !c.typesRefine)
        type("x", c)
        #expect(!c.isLevelTwo && c.draft == "@translate hellox")
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "hellox", id: 2))
        // ⇧⏎ on its results: as typed.
        _ = c.receive(ConversionResult(versions: [CandidateLine("你好")]), isFinal: true, id: 2)
        #expect(commits(c.handleKeyDown(shiftEnterKey)) == ["@translate hellox"])
    }

    // MARK: - Saved conversations

    @Test func aConversationIsSavedWholeByItsFirstQuestion() {
        let c = asked()
        c.remembersQuestions = true
        c.now = { Date(timeIntervalSince1970: 5) }
        type("who made it", c)
        _ = c.handleKeyDown(shiftEnterKey)
        let effects = c.receive(answer("Graydon Hoare."), isFinal: true, id: 2)
        let thread = [QuestionChat.Round(question: "what is rust", answer: "A systems language."),
                      QuestionChat.Round(question: "who made it", answer: "Graydon Hoare.")]
        let entry = QuestionHistory.Entry(rounds: thread, date: Date(timeIntervalSince1970: 5))
        #expect(effects.contains(.rememberQuestion(entry)))
        #expect(c.questionHistory.entries == [entry])
        #expect(entry.question == "what is rust" && entry.answer == "Graydon Hoare." && entry.thread == thread)
    }

    @Test func aSavedConversationShowsItsRoundsAndGoesOn() {
        let thread = [QuestionChat.Round(question: "what is rust", answer: "A systems language."),
                      QuestionChat.Round(question: "who made it", answer: "Graydon Hoare.")]
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.questionRounds = 3
        c.questionHistory = QuestionHistory(entries: [QuestionHistory.Entry(rounds: thread, date: Date(timeIntervalSince1970: 1))])
        c.now = { Date(timeIntervalSince1970: 9) }
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        _ = c.handleKeyDown(k("1"))
        #expect(c.showsSavedAnswer && c.isQuestionChat && c.chatRounds == thread && c.highlighted == 1)
        // R starts the next question, as any letter (⌘R asks again).
        type("rationale", c)
        let run = started(c.handleKeyDown(shiftEnterKey).effects)
        #expect(run?.0.request == .command(.question, input: "what is rust") && run?.0.turns.map(\.instruction) == ["who made it", "rationale"])
        let effects = c.receive(answer("Safety."), isFinal: true, id: run?.1 ?? 0)
        #expect(!c.showsSavedAnswer && c.chatAtLimit)
        let saved = effects.compactMap { if case let .rememberQuestion(e) = $0 { return e } else { return nil } }.first
        #expect(saved?.thread.map(\.question) == ["what is rust", "who made it", "rationale"] && c.questionHistory.entries.count == 1)
    }

    @Test func commandRAsksASavedAnswerAgain() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.questionHistory = QuestionHistory(entries: [QuestionHistory.Entry(question: "what is rust", answer: "A language.", date: .distantPast)])
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        _ = c.handleKeyDown(k("1"))
        #expect(c.showsSavedAnswer && c.chatRounds.count == 1)
        // R is the start of a follow-up; ⌘R asks it again (what was typed goes).
        _ = c.handleKeyDown(k("r"))
        #expect(c.refineLine == "r" && c.showsSavedAnswer)
        #expect(c.handleKeyDown(k("r", mods: .command)).effects.contains { if case .reask(.question, "what is rust", _) = $0 { true } else { false } })
    }

    @Test func commandRAsksASavedConversationsLatestQuestionAgainPastTheCache() {
        let thread = [QuestionChat.Round(question: "what is rust", answer: "A language."),
                      QuestionChat.Round(question: "who made it", answer: "Graydon.")]
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.questionRounds = 2
        c.questionHistory = QuestionHistory(entries: [QuestionHistory.Entry(rounds: thread, date: Date(timeIntervalSince1970: 1))])
        c.now = { Date(timeIntervalSince1970: 9) }
        c.setInputMode(.english)
        _ = c.handleKeyDown(at)
        type("question", c)
        _ = c.handleKeyDown(tab)
        _ = c.handleKeyDown(k("1"))
        #expect(c.showsSavedAnswer && c.chatAtLimit)
        // At the last round too: asked again, not handed over.
        let run = started(c.handleKeyDown(KeyEvent(keyCode: 0x0F, characters: "r", modifiers: .command)).effects)
        #expect(run?.0 == Refinement(request: .command(.question, input: "what is rust"),
                                     turns: [Refinement.Turn(answer: answer("A language."), instruction: "who made it")], fresh: true))
        #expect(!c.showsSavedAnswer && c.chatRound == 2 && c.refineText.isEmpty)
        let effects = c.receive(answer("Graydon Hoare."), isFinal: true, id: run?.1 ?? 0)
        let saved = effects.compactMap { if case let .rememberQuestion(e) = $0 { return e } else { return nil } }.first
        #expect(saved?.thread.map(\.answer) == ["A language.", "Graydon Hoare."] && c.questionHistory.entries.count == 1)
        // In an app with no AI: nothing asked.
        let d = Composer(engine: FakeEngine(), actionKey: .enter)
        d.questionHistory = c.questionHistory
        d.aiRefusal = { "No AI in this app" }
        d.setInputMode(.english)
        _ = d.handleKeyDown(at)
        type("question", d)
        _ = d.handleKeyDown(tab)
        _ = d.handleKeyDown(k("1"))
        #expect(d.handleKeyDown(k("r", mods: .command)).effects == [.notice("No AI in this app"), .showPanel] && d.showsSavedAnswer)
    }

    @Test func aFreshFollowUpGetsPastTheCache() async throws {
        let rig = RARig()
        RAStubProtocol.enqueue(rig.host, .answer("In 2006."), .answer("Back in 2006."))
        let turns = [Refinement.Turn(answer: answer("A language."), instruction: "when?")]
        var answers: [String] = []
        for fresh in [false, true] {
            for try await update in rig.converter.generate(.question, input: "what is rust", fresh: fresh, turns: turns) where update.isFinal {
                answers.append(update.result.versions.first?.text ?? "")
            }
        }
        let sent = try rig.sent().count
        #expect(answers == ["In 2006.", "Back in 2006."] && sent == 2)
    }

    @Test func oldFilesLoadAsOneRoundAndOneRoundIsWrittenAsBefore() throws {
        let old = #"{"entries":[{"question":"q","answer":"a","date":"2026-10-01T10:00:00Z"}]}"#
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qchat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("recent-questions.json")
        try Data(old.utf8).write(to: url)
        let loaded = QuestionHistory.load(from: url)
        #expect(loaded.entries.first?.rounds == nil && loaded.entries.first?.thread == [QuestionChat.Round(question: "q", answer: "a")])
        // One round: no "rounds" in the file; a conversation: all of them, read back as they were.
        var history = QuestionHistory()
        history.record(QuestionHistory.Entry(rounds: [QuestionChat.Round(question: "one", answer: "1")], date: Date(timeIntervalSince1970: 1)))
        try history.write(to: url)
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("rounds"))
        let thread = [QuestionChat.Round(question: " two ", answer: "2"), QuestionChat.Round(question: "and?", answer: "3")]
        history.record(QuestionHistory.Entry(rounds: thread, date: Date(timeIntervalSince1970: 2)))
        try history.write(to: url)
        let back = QuestionHistory.load(from: url)
        #expect(back.entries.first?.thread.map(\.question) == ["two", "and?"] && back.entries.first?.question == "two")
        #expect(back.entries.count == 2)
        // The same first question again: the thread is replaced, not added.
        history.record(QuestionHistory.Entry(rounds: [QuestionChat.Round(question: "two", answer: "new")], date: Date(timeIntervalSince1970: 3)))
        #expect(history.entries.count == 2 && history.entries.first?.thread == [QuestionChat.Round(question: "two", answer: "new")])
    }

    // MARK: - The hand-off

    /// The default choices: the agent `@agent` hands to first (⌘1), then the other agents installed, then Claude on the web,
    /// ChatGPT and Copy; an agent that isn't installed isn't there.
    @Test func theDefaultChoicesAreTheAgentsInstalledThePickedOneFirst() {
        let all: (AgentKind) -> Bool = { _ in true }
        #expect(ChatHandoff.defaultChoices(picked: .claude, installed: all)
                == [.claudeCode, .geminiCLI, .kiroCLI, .customAgent, .claudeWeb, .chatgpt, .copy])
        #expect(ChatHandoff.defaultChoices(picked: .kiro, installed: all)
                == [.kiroCLI, .claudeCode, .geminiCLI, .customAgent, .claudeWeb, .chatgpt, .copy])
        // Only those installed; the one picked isn't there when it isn't, and Claude Code doesn't stand in for it.
        #expect(ChatHandoff.defaultChoices(picked: .gemini, installed: { $0 == .claude || $0 == .kiro })
                == [.claudeCode, .kiroCLI, .claudeWeb, .chatgpt, .copy])
        #expect(ChatHandoff.choices(nil, picked: .claude, installed: { _ in false }) == [.claudeWeb, .chatgpt, .copy])
        // Configured: its order, each once, without the agents that aren't installed; never empty.
        let gemini: (AgentKind) -> Bool = { $0 == .gemini }
        #expect(ChatHandoff.choices([.gemini, .claudeCode, .geminiCLI, .gemini, .copy], picked: .claude, installed: gemini)
                == [.gemini, .geminiCLI, .copy])
        #expect(ChatHandoff.choices([.claudeCode, .kiroCLI], picked: .claude, installed: gemini) == [.copy])
        #expect(ChatHandoff.choices([.chatgpt, .claudeCode], picked: .gemini, installed: all) == [.chatgpt, .claudeCode])
        // Claude Code the only agent (the first 0.6.4 builds): as they had it.
        #expect(ChatHandoff.choices(nil, picked: .claude, installed: { $0 == .claude }) == [.claudeCode, .claudeWeb, .chatgpt, .copy])
    }

    /// Whether an agent can be offered: its program found; a custom one's as typed (trimmed), never without a command.
    @Test func anAgentIsOfferedWhenItsProgramIsFound() {
        var config = Config.default
        #expect(ChatHandoff.installed(.claude, in: config, program: { $0 == "claude" }))
        #expect(!ChatHandoff.installed(.gemini, in: config, program: { $0 == "claude" }))
        #expect(ChatHandoff.installed(.kiro, in: config, program: { $0 == "kiro-cli" }))
        #expect(!ChatHandoff.installed(.custom, in: config, program: { _ in true }))
        config.agentCommand = [" /opt/bin/muse ", "--"]
        var looked: [String] = []
        #expect(ChatHandoff.installed(.custom, in: config, program: { looked.append($0); return true }) && looked == ["/opt/bin/muse"])
        // Each agent's choice, and back.
        for kind in AgentKind.allCases { #expect(ChatHandoff.Destination(agent: kind).agent == kind) }
        #expect([ChatHandoff.Destination.claudeWeb, .chatgpt, .gemini, .copy].allSatisfy { $0.agent == nil })
    }

    @Test func theTextAndWhereItGoes() {
        let rounds = [QuestionChat.Round(question: "a & b?", answer: "c = d\n#1 + 2")]
        let prompt = ChatHandoff.prompt(rounds, followUp: "  more  ")
        #expect(prompt == "**Q:** a & b?\n\n**A:** c = d\n#1 + 2\n\nLet's continue this discussion.\n\nmore")
        #expect(ChatHandoff.copied(rounds) == "**Q:** a & b?\n\n**A:** c = d\n#1 + 2")
        #expect(ChatHandoff.copied(rounds, followUp: "next") == "**Q:** a & b?\n\n**A:** c = d\n#1 + 2\n\n**Q:** next")
        guard case let .open(url, nil) = ChatHandoff.action(.claudeWeb, prompt: prompt, copied: "") else { Issue.record("claude"); return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(url.host == "claude.ai" && url.path == "/new" && items?.count == 1 && items?.first?.value == prompt)
        #expect(!url.absoluteString.contains("&") && !url.absoluteString.contains("#") && !url.absoluteString.contains("+"))
        guard case let .open(gpt, nil) = ChatHandoff.action(.chatgpt, prompt: prompt, copied: "") else { Issue.record("chatgpt"); return }
        #expect(gpt.host == "chatgpt.com" && URLComponents(url: gpt, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == prompt)
        // Too long for an address: the plain page, the text on the clipboard.
        let long = String(repeating: "长", count: 2000)
        #expect(ChatHandoff.action(.claudeWeb, prompt: long, copied: "") == .open(URL(string: "https://claude.ai/new")!, clipboard: long))
        #expect(ChatHandoff.action(.chatgpt, prompt: long, copied: "") == .open(URL(string: "https://chatgpt.com/")!, clipboard: long))
        // Gemini: always the clipboard; copy; the agents.
        #expect(ChatHandoff.action(.gemini, prompt: "x", copied: "") == .open(URL(string: "https://gemini.google.com/app")!, clipboard: "x"))
        #expect(ChatHandoff.action(.copy, prompt: "x", copied: "md") == .copy("md"))
        #expect(ChatHandoff.action(.claudeCode, prompt: "x", copied: "md") == .agent(.claude, prompt: "x"))
        #expect(ChatHandoff.action(.geminiCLI, prompt: "x", copied: "md") == .agent(.gemini, prompt: "x"))
        #expect(ChatHandoff.action(.customAgent, prompt: "x", copied: "md") == .agent(.custom, prompt: "x"))
        // The longest address that still carries it.
        let fits = String(repeating: "a", count: ChatHandoff.maxURLLength - "https://claude.ai/new?q=".count)
        if case let .open(u, nil) = ChatHandoff.action(.claudeWeb, prompt: fits, copied: "") { #expect(u.absoluteString.count == ChatHandoff.maxURLLength) }
        else { Issue.record("fits") }
        #expect(ChatHandoff.action(.claudeWeb, prompt: fits + "a", copied: "") == .open(URL(string: "https://claude.ai/new")!, clipboard: fits + "a"))
    }

    // MARK: - Settings

    @Test func theConfigKeepsTheRoundsAndTheChoices() throws {
        #expect(Config.default.questionRounds == 5 && Config.default.questionContinueIn == nil)
        let decoded = try JSONDecoder().decode(Config.self, from: Data(#"{"questionRounds":30,"questionContinueIn":["gemini","martian","copy"]}"#.utf8))
        #expect(decoded.questionRounds == 10 && decoded.questionContinueIn == [.gemini, .copy])
        #expect(try JSONDecoder().decode(Config.self, from: Data(#"{"questionRounds":1}"#.utf8)).questionRounds == 2)
        // Not written while they're the defaults; written once set.
        let plain = String(decoding: try JSONEncoder().encode(Config.default), as: UTF8.self)
        #expect(!plain.contains("questionRounds") && !plain.contains("questionContinueIn"))
        var set = Config.default
        set.questionRounds = 3
        set.questionContinueIn = [.chatgpt, .claudeCode]
        let again = try JSONDecoder().decode(Config.self, from: try JSONEncoder().encode(set))
        #expect(again.questionRounds == 3 && again.questionContinueIn == [.chatgpt, .claudeCode])
    }
}
