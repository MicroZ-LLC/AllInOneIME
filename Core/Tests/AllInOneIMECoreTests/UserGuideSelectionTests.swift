import Foundation
import Testing
@testable import AllInOneIMECore

/// AllInOneIME's user guide for @question (`UserGuide`): which questions are about the app, how sections are chosen and
/// cut, and where the excerpts go besides the first request (a follow-up, a coding agent). The guide the app ships is the
/// macOS shell's (its tests: UserGuideShippedTests); the acceptance contract is Acceptance/UserGuideTests.swift.
struct UserGuideSelectionTests {
    // MARK: - Which questions

    @Test(arguments: ["what is the capital of France", "帮我解释这句话", "帮我续写这个故事", "这个英文词什么意思",
                      "write to foo@note.com about the plan", "list three crime novels", "summarize this article",
                      "does the input method show tones?"])
    func ordinaryQuestionsAreNotAboutTheApp(question: String) {
        #expect(!UserGuide.isAbout(question))
        #expect(UserGuide(text: Self.guide).excerpts(for: question) == nil)
    }

    @Test(arguments: ["AllInOneIME 是什么", "这个输入法怎么设置", "how do I configure this input method", "什么是双拼",
                      "what does ⌘⏎ do", "how do I use @note", "＠reminder 怎么用", "where is the magic key",
                      "All-in-One IME settings", "how do I add an input source"])
    func questionsAboutTheAppAre(question: String) {
        #expect(UserGuide.isAbout(question))
    }

    @Test func onlyTheQuestionCountsNotTheTextItIsAbout() {
        #expect(!UserGuide.isAbout(Prompt.question("what does this mean", about: "Press ⌃V in AllInOneIME for clipboard history")))
        #expect(!UserGuide.isAbout(Prompt.withScreenshot("translate this", "AllInOneIME Settings → General → Magic key")))
        #expect(UserGuide.isAbout(Prompt.question("how do I change the magic key", about: "some text")))
    }

    @Test func termsKeepKeysAndCommandsAndPairWords() {
        let english = UserGuide.terms("Press ⌃V or ⌘C⌘V, then @translate the magic keys")
        #expect(english.isSuperset(of: ["press", "⌃v", "⌘c", "⌘v", "@translate", "magic", "key", "magic key"]))
        #expect(!english.contains("or") && !english.contains("the"))
        let chinese = UserGuide.terms("怎么打开双拼")
        #expect(chinese.isSuperset(of: ["打开", "双拼"]) && !chinese.contains("怎么"))
    }

    @Test func theBestSectionAloneTooLongIsCutAtALine() throws {
        let long = (1...200).map { "Line \($0) about Shuangpin." }.joined(separator: "\n")
        let excerpts = try #require(UserGuide(text: "## Shuangpin / 双拼\n\(long)\n## Other\nNothing.\n## More\n\(long)")
            .excerpts(for: "双拼"))
        let best = try #require(excerpts.components(separatedBy: "\n\n## ").first)
        #expect(best.hasPrefix("## Shuangpin / 双拼\nLine 1 ") && best.hasSuffix("Shuangpin.…"))
        // What still fits goes with it (here the next section, as two are sent); what doesn't, doesn't.
        #expect(excerpts.count <= UserGuide.budget && excerpts.hasSuffix("## Other\nNothing.") && !excerpts.contains("## More"))
    }

    // MARK: - Where it goes

    static let guide = """
        ## Shuangpin / 双拼
        Settings → Input → Chinese (pinyin) → Typing.
        ## Magic key / 魔法键
        Settings → General → Magic key.
        """

    func converter(_ model: StubAppleModel, reads: Locked<Int>) -> Converter {
        var config = Config.default
        config.provider = .apple
        let fixed = config
        return Converter(loadConfig: { fixed }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                         loadKey: { _, _ in nil }, loadJargon: { _ in [] },
                         loadUserGuide: { reads.withLock { $0 += 1 }; return Self.guide }, appleModel: model)
    }

    @Test func theGuideIsReadOnlyForAQuestionAboutTheApp() async throws {
        let reads = Locked(initialState: 0)
        let model = StubAppleModel(answer: ["OK."])
        let converter = converter(model, reads: reads)
        for try await _ in converter.generate(.question, input: "what is rust") {}
        #expect(reads.withLock { $0 } == 0 && model.requests.first?.instructions == Prompt.commandSystem(.question))
        for try await _ in converter.generate(.question, input: "how do I change the magic key") {}
        #expect(reads.withLock { $0 } == 1)
        let instructions = try #require(model.requests.last?.instructions)
        #expect(instructions.hasPrefix(Prompt.commandSystem(.question) + "\n\n"))
        #expect(instructions.contains(Prompt.userGuideTitle + ":\n\n## Magic key / 魔法键"))
        // Other commands never read it.
        for try await _ in converter.generate(.edit, input: Prompt.editRequest(instruction: "improve", text: "the magic key")) {}
        #expect(reads.withLock { $0 } == 1)
    }

    @Test func aConversationAboutTheAppKeepsTheExcerptsAnOrdinaryOneHasNone() async throws {
        func instructions(_ first: String, then next: String) async throws -> String {
            let model = StubAppleModel(answer: ["OK."])
            let turns = [Refinement.Turn(answer: ConversionResult(versions: [CandidateLine("An answer.")]), instruction: next)]
            for try await _ in converter(model, reads: Locked(initialState: 0)).generate(.question, input: first, turns: turns) {}
            return try #require(model.requests.first).instructions
        }
        // The first question was about the app: "and how do I turn it off?" still gets the guide.
        #expect(try await instructions("怎么打开双拼", then: "and how do I turn it off?").contains("## Shuangpin / 双拼"))
        #expect(try await instructions("what is rust", then: "who made it") == Prompt.commandSystem(.question))
    }

    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

    /// "@question <question>" ⏎, answered: a conversation that can be handed off.
    func conversation(_ question: String, guide path: String?) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.handoffChoices = [.claudeCode, .claudeWeb, .copy]
        c.remembersQuestions = false
        c.userGuidePath = path
        c.setInputMode(.english)
        func type(_ s: String) { for ch in s { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) } }
        _ = c.handleKeyDown(at)
        type("question")
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        type(question)
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("An answer.")]), isFinal: true, id: 1)
        return c
    }

    func agentPrompt(_ effects: [Composer.Effect]) -> String? {
        effects.lazy.compactMap { if case let .continueInClaudeCode(prompt) = $0 { return prompt } else { return nil } }.first
    }

    @Test func aCodingAgentIsToldWhereTheGuideIsTheWebIsNot() throws {
        let path = "/Users/me/Library/Input Methods/AllInOneIME Input.app/Contents/Resources/user-guide.md"
        let prompt = try #require(agentPrompt(conversation("how do I change the magic key", guide: path).handOff(to: .claudeCode)))
        #expect(prompt == "**Q:** how do I change the magic key\n\n**A:** An answer.\n\n" + ChatHandoff.guideNote(path)
                + "\n\n" + ChatHandoff.continuation)
        let web = conversation("how do I change the magic key", guide: path).handOff(to: .claudeWeb)
        #expect(!web.contains { if case let .openLink(url) = $0 { return url.absoluteString.contains("user-guide") } else { return false } })
        // An ordinary conversation, or no guide: as before.
        let ordinary = try #require(agentPrompt(conversation("what is rust", guide: path).handOff(to: .claudeCode)))
        #expect(ordinary == "**Q:** what is rust\n\n**A:** An answer.\n\n" + ChatHandoff.continuation)
        let none = try #require(agentPrompt(conversation("how do I change the magic key", guide: nil).handOff(to: .claudeCode)))
        #expect(!none.contains("user guide"))
    }
}
