import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The owner's decision of 2026-11-15 on the @question conversation's keys, once an answer is shown (round 1 and later
/// rounds): with the follow-up line empty Space and ⏎ do nothing; ⇧⏎ inserts the selected answer; pinyin + Space, a
/// Space after text and ⏎ with text are unchanged; Esc closes the panel and leaves nothing in the field at any round,
/// whatever the line holds; the conversation stays in the recent questions. Written from the spec by a separate agent;
/// the implementer doesn't edit it (AGENTS.md rule 11).
///
/// Driven through the session's key path (`FakeHost`), the provider a Claude API endpoint stubbed at the HTTP level
/// (`QCStubProtocol`: "Answer: <question>", nothing leaves the Mac), the pinyin engine the tests' stand-in (`FakeEngine`),
/// the recent questions kept in memory as the shell keeps them (`SessionServices.recordQuestion`).
@Suite("Chat keys", .serialized)
struct ChatKeysAcceptanceTests {
    /// The recent questions as the shell keeps them: what the session records, read back before each key.
    final class Recent: @unchecked Sendable {
        var history = QuestionHistory()
    }

    /// A field with a conversation in its panel.
    struct Chat {
        let host: FakeHost
        let endpoint: String
        let recent: Recent

        var composer: Composer { host.composer }
        /// Requests sent to the provider so far.
        var requests: Int { QCStubProtocol.bodies(endpoint).count }
    }

    /// What the follow-up line holds when a key is pressed.
    enum Line: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case empty, text, pinyin
        var testDescription: String { rawValue }
    }

    /// The input language the follow-up line is typed in.
    enum Typing: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case english, chinese
        var testDescription: String { rawValue }
    }

    // MARK: - The field

    private func field() -> Chat {
        let endpoint = "chat-keys-\(UUID().uuidString.lowercased()).test"
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .anthropic
        config.anthropic = ProviderSettings(baseURL: "https://\(endpoint)")
        config.rememberQuestions = true
        config.outputLanguages = [.english]
        config.rewriteStyles = []
        config.setOrder([Language.chinese, .english])
        let fixed = config
        let converter = Converter(client: BedrockClient(session: QCStubProtocol.session()), loadConfig: { fixed },
                                  loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
        let engine = FakeEngine()
        let recent = Recent()
        var services = SessionServices(converter: converter, loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        services.loadQuestionHistory = { recent.history }
        services.recordQuestion = { recent.history.record($0) }
        let host = FakeHost(services: services)
        host.app = "com.example.editor"
        host.focus()
        host.composer.setInputMode(.english)
        return Chat(host: host, endpoint: endpoint, recent: recent)
    }

    /// "@question q1" ⏎, then "q2" ⏎ … until round `round`'s answer is shown, all in.
    private func answered(round: Int) throws -> Chat {
        let chat = field()
        let host = chat.host
        host.press(FakeHost.at)
        host.type("q")
        host.press(FakeHost.tab)
        try #require(chat.composer.draft == "@question ", "draft=\(chat.composer.draft)")
        host.type("q1")
        host.press(FakeHost.enter)
        try #require(settled(chat, round: 1), "phase=\(chat.composer.phase)")
        var next = 2
        while next <= round {
            host.type("q\(next)")
            host.press(FakeHost.enter)
            try #require(settled(chat, round: next), "round \(next): phase=\(chat.composer.phase)")
            next += 1
        }
        try #require(chat.composer.isQuestionChat && chat.composer.chatRound == round)
        try #require(chat.composer.chatRounds.map(\.question) == (1...round).map { "q\($0)" })
        try #require(chat.requests == round)
        try #require(chat.host.document.isEmpty && chat.host.panel != nil)
        return chat
    }

    private func settled(_ chat: Chat, round: Int) -> Bool {
        chat.host.settle(timeout: 10) {
            chat.composer.canRefine && chat.composer.chatRound == round
                && chat.composer.chatRounds.last.map { !$0.answer.isEmpty } == true
        }
    }

    /// A Shift tap: the input language goes to Chinese.
    private func switchToChinese(_ chat: Chat) throws {
        chat.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: 100))
        chat.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: 100.1))
        try #require(chat.composer.inputLanguage == .chinese)
    }

    /// Puts `line` in the follow-up line (pinyin typed in Chinese, text in English).
    private func fill(_ line: Line, _ chat: Chat) throws {
        switch line {
        case .empty:
            try #require(chat.composer.refineLine == nil && chat.composer.refineText.isEmpty)
        case .text:
            chat.host.type("half")
            try #require(chat.composer.refineLine == "half")
        case .pinyin:
            try switchToChinese(chat)
            chat.host.type("nihao")
            try #require(chat.composer.refineIsComposing && chat.composer.refineLine == "nihao")
        }
    }

    /// What went into the field (committed, replaced, typed out) since output `mark`.
    private func inserted(_ chat: Chat, since mark: Int) -> [String] {
        chat.host.outputs.dropFirst(mark).compactMap { output -> String? in
            switch output {
            case let .commit(text), let .commitAfterKey(text), let .typeOut(text): return text
            case let .replace(text, _): return text
            default: return nil
            }
        }
    }

    /// The conversation is still up on the same round, with nothing sent, nothing inserted, the line empty.
    private func expectUnchanged(_ chat: Chat, rounds: [QuestionChat.Round], requests: Int, mark: Int,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
        let composer = chat.composer
        #expect(composer.isQuestionChat && composer.phase == .choosing, "phase=\(composer.phase)",
                sourceLocation: sourceLocation)
        #expect(composer.chatRound == rounds.count && composer.chatRounds == rounds,
                "rounds=\(composer.chatRounds.map(\.question))", sourceLocation: sourceLocation)
        #expect(chat.host.panel != nil, "the panel stays up", sourceLocation: sourceLocation)
        #expect(composer.refineLine == nil && composer.refineText.isEmpty,
                "the line stays empty: \(String(describing: composer.refineLine))", sourceLocation: sourceLocation)
        #expect(chat.requests == requests, "nothing sent", sourceLocation: sourceLocation)
        #expect(chat.host.document.isEmpty && inserted(chat, since: mark).isEmpty,
                "nothing inserted: \(chat.host.document) \(inserted(chat, since: mark))", sourceLocation: sourceLocation)
    }

    // MARK: - 1. Space with the line empty does nothing

    @Test(arguments: [1, 3], Typing.allCases)
    func p1_spaceWithTheLineEmptyDoesNothing(round: Int, typing: Typing) throws {
        let chat = try answered(round: round)
        if typing == .chinese { try switchToChinese(chat) }
        try fill(.empty, chat)
        let (rounds, requests, mark) = (chat.composer.chatRounds, chat.requests, chat.host.outputs.count)
        let handled = chat.host.press(FakeHost.space)
        #expect(handled, "Space is consumed, not passed to the app")
        expectUnchanged(chat, rounds: rounds, requests: requests, mark: mark)
        // Nothing comes later either (an answer inserted, a request answered).
        _ = chat.host.settle(timeout: 0.3) { false }
        expectUnchanged(chat, rounds: rounds, requests: requests, mark: mark)
    }

    // MARK: - 2. ⏎ with the line empty does nothing

    @Test(arguments: [1, 3], Typing.allCases)
    func p2_returnWithTheLineEmptyDoesNothing(round: Int, typing: Typing) throws {
        let chat = try answered(round: round)
        if typing == .chinese { try switchToChinese(chat) }
        try fill(.empty, chat)
        let (rounds, requests, mark) = (chat.composer.chatRounds, chat.requests, chat.host.outputs.count)
        let handled = chat.host.press(FakeHost.enter)
        #expect(handled, "⏎ is consumed, not passed to the app")
        expectUnchanged(chat, rounds: rounds, requests: requests, mark: mark)
        _ = chat.host.settle(timeout: 0.3) { false }
        expectUnchanged(chat, rounds: rounds, requests: requests, mark: mark)
    }

    // MARK: - 3. ⇧⏎ with the line empty inserts the selected answer and ends the chat

    @Test(arguments: [1, 3])
    func p3_shiftReturnWithTheLineEmptyInsertsTheSelectedAnswer(round: Int) throws {
        let chat = try answered(round: round)
        try fill(.empty, chat)
        // The latest answer is the one selected.
        let latest = try #require(chat.composer.chatRounds.last?.answer)
        #expect(latest == "Answer: q\(round)")
        let requests = chat.requests
        chat.host.press(acceptanceShiftReturn)
        #expect(chat.host.document == latest)
        #expect(chat.host.panel == nil && chat.composer.phase == .idle && !chat.composer.isQuestionChat)
        #expect(chat.requests == requests)
    }

    // MARK: - 4. Unchanged: pinyin + Space, a Space after text, ⏎ with text

    @Test(arguments: [1, 3])
    func p4a_pinyinAndSpacePicksTheFirstCandidateIntoTheLine(round: Int) throws {
        let chat = try answered(round: round)
        try fill(.pinyin, chat)
        let (rounds, requests, mark) = (chat.composer.chatRounds, chat.requests, chat.host.outputs.count)
        let handled = chat.host.press(FakeHost.space)
        #expect(handled)
        #expect(chat.composer.refineText == "你好" && chat.composer.refineLine == "你好")
        #expect(!chat.composer.refineIsComposing)
        #expect(chat.composer.isQuestionChat && chat.composer.chatRounds == rounds && chat.host.panel != nil)
        #expect(chat.requests == requests, "nothing sent")
        #expect(chat.host.document.isEmpty && inserted(chat, since: mark).isEmpty, "nothing inserted")
    }

    @Test(arguments: [1, 3])
    func p4b_spaceAfterTextTypesASpaceIntoTheLine(round: Int) throws {
        let chat = try answered(round: round)
        try fill(.text, chat)
        let (rounds, requests, mark) = (chat.composer.chatRounds, chat.requests, chat.host.outputs.count)
        let handled = chat.host.press(FakeHost.space)
        #expect(handled)
        #expect(chat.composer.refineLine == "half ")
        chat.host.type("x")
        #expect(chat.composer.refineLine == "half x")
        #expect(chat.composer.isQuestionChat && chat.composer.chatRounds == rounds && chat.host.panel != nil)
        #expect(chat.requests == requests, "nothing sent")
        #expect(chat.host.document.isEmpty && inserted(chat, since: mark).isEmpty, "nothing inserted")
    }

    @Test(arguments: [1, 3])
    func p4c_returnWithTextAsksTheNextRound(round: Int) throws {
        let chat = try answered(round: round)
        let mark = chat.host.outputs.count
        chat.host.type("next one")
        let handled = chat.host.press(FakeHost.enter)
        #expect(handled)
        #expect(settled(chat, round: round + 1), "phase=\(chat.composer.phase)")
        #expect(chat.requests == round + 1)
        #expect(chat.composer.chatRounds.map(\.question) == (1...round).map { "q\($0)" } + ["next one"])
        #expect(chat.composer.chatRounds.last?.answer == "Answer: next one")
        #expect(chat.host.panel != nil && chat.host.document.isEmpty && inserted(chat, since: mark).isEmpty)
    }

    // MARK: - 5. Esc closes the panel and leaves nothing, at any round, whatever the line holds

    @Test(arguments: [1, 3], Line.allCases)
    func p5_escapeClosesThePanelAndLeavesNothing(round: Int, line: Line) throws {
        let chat = try answered(round: round)
        try fill(line, chat)
        let (requests, mark) = (chat.requests, chat.host.outputs.count)
        chat.host.press(FakeHost.escape)
        let composer = chat.composer
        #expect(chat.host.panel == nil, "the panel closes")
        #expect(composer.phase == .idle && !composer.isComposing, "idle, not a round back nor the draft: \(composer.phase)")
        #expect(!composer.isQuestionChat && composer.chatRounds.isEmpty)
        #expect(composer.draft.isEmpty, "not back to the draft: \(composer.draft)")
        #expect(chat.host.marked.isEmpty && composer.markedText.isEmpty, "no marked text: \(chat.host.marked)")
        #expect(chat.host.document.isEmpty && inserted(chat, since: mark).isEmpty,
                "nothing in the field: \(chat.host.document) \(inserted(chat, since: mark))")
        #expect(chat.requests == requests, "nothing sent")
        // Nothing comes later either.
        _ = chat.host.settle(timeout: 0.3) { false }
        #expect(chat.host.panel == nil && composer.phase == .idle && chat.host.document.isEmpty)
        #expect(inserted(chat, since: mark).isEmpty && chat.requests == requests)
    }

    // MARK: - 6. After Esc the conversation is in the recent questions, to pick up again

    @Test(arguments: [1, 3])
    func p6_afterEscapeTheConversationIsInTheRecentQuestions(round: Int) throws {
        let chat = try answered(round: round)
        let rounds = chat.composer.chatRounds
        try #require(rounds.count == round && rounds.allSatisfy { !$0.answer.isEmpty })
        chat.host.press(FakeHost.escape)

        // Kept as the shell keeps it, and in the composer's list: the conversation whole, all its answered rounds.
        #expect(chat.recent.history.entries.count == 1)
        #expect(chat.recent.history.entries.first?.thread == rounds,
                "kept: \(String(describing: chat.recent.history.entries.first?.thread))")
        #expect(chat.composer.questionHistory.entries.first?.thread == rounds)

        // Picked up again as today, once Esc has closed the chat (point 5): "@question " lists it; its digit shows it with
        // every round, nothing sent.
        try #require(chat.host.panel == nil && chat.composer.phase == .idle,
                     "Esc closes the chat (point 5): \(chat.composer.phase), draft=\(chat.composer.draft)")
        let requests = chat.requests
        chat.host.press(FakeHost.at)
        chat.host.type("q")
        chat.host.press(FakeHost.tab)
        #expect(chat.composer.draft == "@question ")
        #expect(chat.composer.questionMatches.first?.thread == rounds)
        chat.host.type("1")
        #expect(chat.composer.showsSavedAnswer && chat.composer.isQuestionChat)
        #expect(chat.composer.chatRounds == rounds)
        #expect(chat.requests == requests && chat.host.document.isEmpty)
    }
}
