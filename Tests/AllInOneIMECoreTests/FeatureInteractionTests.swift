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
