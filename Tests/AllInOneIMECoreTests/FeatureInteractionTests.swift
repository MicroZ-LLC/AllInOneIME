import Foundation
import Testing
@testable import AllInOneIMECore

/// The 0.6.3 features together: refining the results in an app with its own settings (its rewrite styles, no AI),
/// refining with Apple's on-device model (its context, its language check, its revised answers), and the recent
/// @questions in an app with no AI.
struct FeatureInteractionTests {
    let quiet = "com.example.quiet", casual = "com.example.casual"
    let shown = ConversionResult(versions: [CandidateLine("Hello there, nice to meet you.")])

    var config: Config {
        var config = Config.default
        config.provider = .apple
        config.setOrder([OutputLanguage.english])
        config.rewriteStyles = ["润色", "简洁"]
        config.appProfiles = [quiet: AppProfile(noAI: true), casual: AppProfile(rewriteStyles: ["口语"])]
        return config
    }

    func converter(_ stub: StubAppleModel) -> Converter {
        let config = config
        return Converter(loadConfig: { config }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                         loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: stub)
    }

    func turns(_ instruction: String = "shorter") -> [Refinement.Turn] {
        [Refinement.Turn(answer: shown, instruction: instruction)]
    }

    func updates(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> [ConversionUpdate] {
        var all: [ConversionUpdate] = []
        for try await update in stream { all.append(update) }
        return all
    }

    // MARK: Refine × per-app settings

    @Test func aRefineInAnAppWithNoAISendsNothing() async throws {
        let stub = StubAppleModel(answer: ["EN: Hi."])
        await #expect(throws: AppProfile.Refusal.noAI) {
            _ = try await updates(converter(stub).convert("hello", mode: .improve, app: quiet, turns: turns()))
        }
        await #expect(throws: AppProfile.Refusal.noAI) {
            _ = try await updates(converter(stub).generate(.question, input: "why", app: quiet, turns: turns()))
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func aRefineHasTheAppsRewriteStyles() async throws {
        let casualTag = try #require(RewriteStyle.named("口语")).lineTag
        let polishTag = try #require(RewriteStyle.named("润色")).lineTag
        let inApp = StubAppleModel(answer: ["EN: Hi."])
        _ = try await updates(converter(inApp).convert("hello", mode: .improve, app: casual, turns: turns()))
        let instructions = try #require(inApp.requests.first?.instructions)
        #expect(instructions.contains(casualTag) && !instructions.contains(polishTag))
        let elsewhere = StubAppleModel(answer: ["EN: Hi."])
        _ = try await updates(converter(elsewhere).convert("hello", mode: .improve, turns: turns()))
        #expect(elsewhere.requests.first?.instructions.contains(polishTag) == true)
    }

    // MARK: Refine × Apple's on-device model

    @Test func aRefineIsAConversationOnTheOnDeviceModel() throws {
        let body = Prompt.refineRequest(for: "hello", mode: .improve, config: config, turns: turns())
        let request = AppleModel.request(from: body, maxTokens: 1000, contextSize: 4096)
        #expect(request.instructions.hasSuffix(Prompt.writingRefineRules))
        #expect(request.prompt == Prompt.refineMessage("shorter"))
        let last = try #require(request.examples.last)
        #expect(last.prompt == "hello" && last.response == "EN: Hello there, nice to meet you.")
    }

    @Test func aRefineKeepsItsConversationWhenTheContextIsTight() throws {
        let long = String(repeating: "This is a rather long sentence about the meeting. ", count: 120)
        let long2 = ConversionResult(versions: [CandidateLine(long)])
        let twice = [Refinement.Turn(answer: long2, instruction: "shorter"), Refinement.Turn(answer: shown, instruction: "warmer")]
        let body = Prompt.refineRequest(for: long, mode: .improve, config: config, turns: twice)
        let request = AppleModel.request(from: body, maxTokens: 1000, contextSize: 4096)
        // The few-shot examples go, the text, both answers and the first instruction stay: the last is the prompt.
        #expect(request.examples.map(\.prompt) == [long, Prompt.refineMessage("shorter")])
        #expect(request.prompt == Prompt.refineMessage("warmer"))
        // Too long even so: sent as it is (the model says it doesn't fit), never as an instruction with nothing to apply it to.
        let longer = String(repeating: long, count: 3)
        let tooLong = [Refinement.Turn(answer: ConversionResult(versions: [CandidateLine(longer)]), instruction: "shorter")]
        let whole = AppleModel.request(from: Prompt.refineRequest(for: longer, mode: .improve, config: config, turns: tooLong),
                                       maxTokens: 1000, contextSize: 4096)
        #expect(whole.examples.map(\.prompt) == [longer] && whole.prompt == Prompt.refineMessage("shorter"))
        // A request that isn't a refine drops all its examples then, as before.
        let plain = AppleModel.request(from: Prompt.request(for: longer, mode: .improve, config: config), maxTokens: 1000,
                                       contextSize: 4096)
        #expect(plain.examples.isEmpty)
    }

    @Test func aRefinesLanguageIsJudgedOnTheInstructionAlone() async throws {
        #expect(AppleModel.usersText(Prompt.refineMessage("用更口语的说法")) == "用更口语的说法")
        let russian = StubAppleModel(answer: ["EN: Hi."])
        await #expect(throws: AppleModelError.unsupportedLanguage) {
            _ = try await updates(converter(russian).convert("hello", mode: .improve,
                                                             turns: turns("сделай это покороче, пожалуйста")))
        }
        #expect(russian.requests.isEmpty)
        let chinese = StubAppleModel(answer: ["EN: Hi."])
        let done = try await updates(converter(chinese).convert("hello", mode: .improve, turns: turns("用更口语的说法再短一点")))
        #expect(done.last?.result.versions.map(\.text) == ["Hi."])
    }

    @Test func aRevisedAnswerReplacesWhatARefineShowed() async throws {
        let stub = StubAppleModel(answer: ["EN: Hello", "EN: Hi.", "EN: Hi!"])
        let all = try await updates(converter(stub).convert("hello", mode: .improve, turns: turns()))
        #expect(all.allSatisfy { ["EN: Hello", "EN: Hi.", "EN: Hi!"].contains($0.rawText) })
        #expect(all.last?.isFinal == true && all.last?.result.versions.map(\.text) == ["Hi!"])
        let answer = StubAppleModel(answer: ["It is a long answer", "Short."])
        let command = try await updates(converter(answer).generate(.question, input: "why", turns: turns()))
        #expect(command.last?.rawText == "Short." && command.last?.result.versions.map(\.text) == ["Short."])
    }
}

/// Refining in the composer when the app has no AI (turned on while the results are up): refused, the results and the
/// instruction stay.
extension RefineTests {
    @Test func aRefineIsRefusedInAnAppWithNoAI() {
        let (c, _) = results()
        c.aiRefusal = { "No AI in this app" }
        _ = type("shorter", c)
        #expect(c.handleKeyDown(enterKey).effects == [.showPanel])
        #expect(!c.isRefining && c.phase == .choosing && c.refineError == "No AI in this app" && c.refineText == "shorter")
        #expect(c.result == first && c.refineHistory.isEmpty)
    }
}

/// The recent @questions in an app with no AI: listed, and a saved answer shown (nothing is sent), but neither asked
/// again (R) nor a new question asked.
extension ComposerTests {
    @Test func savedAnswersShowButAreNotAskedAgainInAnAppWithNoAI() {
        let c = questionDraft()
        c.aiRefusal = { "No AI in this app" }
        #expect(c.questionMatches.count == 3)
        #expect(requests(c.handleKeyDown(k("3")).effects).isEmpty && c.showsSavedAnswer)
        let again = c.handleKeyDown(k("r")).effects
        #expect(requests(again).isEmpty && again.contains(.notice("No AI in this app")))
        #expect(c.showsSavedAnswer && c.choices.map(\.text) == ["what is rust", "A language."])
        let d = questionDraft()
        d.aiRefusal = { "No AI in this app" }
        type("why is the sky blue", d)
        let asked = d.handleKeyDown(enterKey).effects
        #expect(requests(asked).isEmpty && asked.contains(.notice("No AI in this app")))
    }
}

/// Hiding sensitive values (`Redaction`) with the other 0.6.3 features: refining, revised answers from the on-device
/// model, its language check, the recent @questions.
extension FeatureInteractionTests {
    var hiding: Config {
        var config = config
        config.redaction = RedactionSettings(enabled: true)
        return config
    }

    func hidingConverter(_ stub: StubAppleModel) -> Converter {
        let config = hiding
        return Converter(loadConfig: { config }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                         loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: stub)
    }

    /// Everything a request to the on-device model holds.
    func body(_ request: AppleModelRequest) -> String {
        ([request.instructions, request.prompt] + request.examples.flatMap { [$0.prompt, $0.response] }).joined(separator: "\n")
    }

    @Test func aRefineIsHiddenWithTheMappingOfItsRequest() async throws {
        let input = "please email bob@example.com and call me"
        let first = StubAppleModel(answer: ["EN: Please email [EMAIL_1] and call me."])
        let shown = try #require(try await updates(hidingConverter(first).convert(input, mode: .improve)).last)
        #expect(shown.result.versions.map(\.text) == ["Please email bob@example.com and call me."])
        #expect(first.requests.first?.prompt == "please email [EMAIL_1] and call me")

        // The answer shown, and an instruction with a value of its own: the first keeps [EMAIL_1], the new one is next.
        let turns = [Refinement.Turn(answer: shown.result, instruction: "also cc alice@corp.example")]
        let refine = StubAppleModel(answer: ["EN: Please email [EMAIL_1], cc [EMAIL_2]."])
        let refined = try #require(try await updates(hidingConverter(refine).convert(input, mode: .improve, turns: turns)).last)
        let request = try #require(refine.requests.first)
        let sent = body(request)
        #expect(!sent.contains("bob@example.com") && !sent.contains("alice@corp.example"))
        #expect(request.prompt == Prompt.refineMessage("also cc [EMAIL_2]"))
        let conversation = Array(request.examples.suffix(1))
        #expect(conversation.map(\.prompt) == ["please email [EMAIL_1] and call me"])
        #expect(conversation.map(\.response) == ["EN: Please email [EMAIL_1] and call me."])
        #expect(refined.result.versions.map(\.text) == ["Please email bob@example.com, cc alice@corp.example."])
        #expect(refined.hidden == 2)

        // A command's answer the same way.
        let answer = ConversionResult(versions: [CandidateLine("Write to bob@example.com.")])
        let command = StubAppleModel(answer: ["Write to [EMAIL_1] today."])
        let again = try #require(try await updates(hidingConverter(command).generate(
            .question, input: "how do I reach bob@example.com", turns: [Refinement.Turn(answer: answer, instruction: "add today")])).last)
        let commandRequest = try #require(command.requests.first)
        #expect(!body(commandRequest).contains("bob@example.com") && commandRequest.prompt == Prompt.refineMessage("add today"))
        #expect(commandRequest.examples.map(\.response) == ["Write to [EMAIL_1]."])
        #expect(again.result.versions.map(\.text) == ["Write to bob@example.com today."])
    }

    @Test func aRevisedAnswerIsRestoredAndHeldBackLikeAnyOther() async throws {
        let snapshots = ["EN: Mail [EMAIL_1] now", "EN: Write to [EM", "EN: Write to [EMAIL_1", "EN: Write to [EMAIL_1]."]
        let stub = StubAppleModel(answer: snapshots)
        let all = try await updates(hidingConverter(stub).convert("write to bob@example.com", mode: .improve))
        let shown = all.flatMap { $0.result.versions.map(\.text) }
        #expect(!shown.isEmpty && shown.allSatisfy { !$0.contains("[") && !$0.uppercased().contains("EMAIL") }, "\(shown)")
        #expect(shown.contains("Mail bob@example.com now"))
        #expect(all.last?.result.versions.map(\.text) == ["Write to bob@example.com."])
        let answer = StubAppleModel(answer: ["Mail [EMAIL_1] now", "Write [EMAIL", "Write [EMAIL_1] today."])
        let lines = try await updates(hidingConverter(answer).generate(.question, input: "how to reach bob@example.com"))
            .flatMap { $0.result.versions.map(\.text) }
        #expect(lines.allSatisfy { !$0.contains("[") }, "\(lines)")
        #expect(lines.last == "Write bob@example.com today.")
    }

    @Test func theOnDeviceModelGetsHiddenTextJudgedWithoutPlaceholders() async throws {
        let stub = StubAppleModel(answer: ["EN: ok"])
        _ = try await updates(hidingConverter(stub).convert("mail bob@example.com and alice@corp.example", mode: .improve))
        #expect(stub.requests.first?.prompt == "mail [EMAIL_1] and [EMAIL_2]")
        #expect(AppleModel.usersText("नमस्ते [EMAIL_1] [PHONE_12]") == "नमस्ते  ")
        #expect(AppleModel.usersText(Prompt.refineMessage("cc [EMAIL_2]")) == "cc ")
        // Text in a script the model doesn't speak is told up front, however many placeholders it holds.
        let hindi = "आज मेरी तबीयत ठीक नहीं है a@b.example c@d.example e@f.example g@h.example"
        let refused = StubAppleModel(answer: ["ok"])
        await #expect(throws: AppleModelError.unsupportedLanguage) {
            _ = try await updates(hidingConverter(refused).generate(.question, input: hindi))
        }
        #expect(refused.requests.isEmpty)
    }

    @Test func aRecentQuestionKeepsTheRealTextAndIsAskedAgainHidden() async throws {
        let question = "what is the domain of bob@example.com"
        let stub = StubAppleModel(answer: ["The domain of [EMAIL_1] is example.com."])
        let answered = try #require(try await updates(hidingConverter(stub).generate(.question, input: question)).last)
        #expect(stub.requests.first?.prompt == "what is the domain of [EMAIL_1]")
        // What the composer keeps is what it was given: the answer restored, the question as typed.
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.questionHistory = QuestionHistory()
        c.now = { Date(timeIntervalSince1970: 7) }
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        for ch in "q" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        for ch in question { _ = c.handleKeyDown(k(String(ch))) }
        #expect(c.handleKeyDown(enterKey).effects.first == .startCommand(.question, input: question, id: 1))
        let kept = c.receive(answered.result, isFinal: true, id: 1).compactMap {
            if case let .rememberQuestion(entry) = $0 { return entry } else { return nil }
        }
        #expect(kept == [QuestionHistory.Entry(question: question, answer: "The domain of bob@example.com is example.com.",
                                               date: Date(timeIntervalSince1970: 7))])
        // R: asked again past the cache, hidden as the first time.
        let again = StubAppleModel(answer: ["[EMAIL_1] is at example.com."])
        let fresh = try #require(try await updates(hidingConverter(again).generate(.question, input: question, fresh: true)).last)
        #expect(again.requests.first?.prompt == "what is the domain of [EMAIL_1]" && !body(again.requests[0]).contains("bob@"))
        #expect(fresh.result.versions.map(\.text) == ["bob@example.com is at example.com."])
    }
}

/// Refining × the recent @questions: a refined answer replaces the one saved for its question (the decided behaviour),
/// as asking the same question again does; the other questions stay.
extension RefineTests {
    @Test func aRefinedQuestionsAnswerReplacesItsSavedAnswer() {
        let older = QuestionHistory.Entry(question: "why is the sky blue", answer: "Rayleigh scattering.",
                                          date: Date(timeIntervalSince1970: 1))
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.questionHistory = QuestionHistory(entries: [older])
        c.now = { Date(timeIntervalSince1970: 7) }
        _ = c.handleKeyDown(at)
        _ = type("question", c)
        _ = c.handleKeyDown(tab)
        _ = type("what is rust", c)
        #expect(c.handleKeyDown(enterKey).effects.first == .startCommand(.question, input: "what is rust", id: 1))
        let answer = ConversionResult(versions: [CandidateLine("Rust is a systems programming language.")])
        let saved = QuestionHistory.Entry(question: "what is rust", answer: "Rust is a systems programming language.",
                                          date: Date(timeIntervalSince1970: 7))
        #expect(c.receive(answer, isFinal: true, id: 1).contains(.rememberQuestion(saved)))
        #expect(c.questionHistory.entries == [saved, older])

        c.now = { Date(timeIntervalSince1970: 9) }
        _ = type("shorter", c)
        #expect(started(c.handleKeyDown(enterKey).effects)?.1 == 2)
        // Nothing is kept while the refined answer streams in; once it's complete, it takes the saved one's place.
        let partial = ConversionResult(versions: [CandidateLine("A systems", isComplete: false)])
        #expect(!c.receive(partial, isFinal: false, id: 2).contains { if case .rememberQuestion = $0 { true } else { false } })
        let refined = QuestionHistory.Entry(question: "what is rust", answer: "A systems language.",
                                            date: Date(timeIntervalSince1970: 9))
        let effects = c.receive(ConversionResult(versions: [CandidateLine("A systems language.")]), isFinal: true, id: 2)
        #expect(effects.contains(.rememberQuestion(refined)))
        #expect(c.questionHistory.entries == [refined, older])
    }
}
