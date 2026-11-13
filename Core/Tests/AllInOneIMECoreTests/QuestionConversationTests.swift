import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// Each `@question` conversation in the panel is a new conversation of the session's agent (`QuestionConversation`,
/// `ClaudeSessionManager.enter`), its follow-ups go on in that one, and `prewarm` gets the next one ready ahead of its
/// question: Claude Code's process started again on a new session id, Codex and an ACP agent opening a new thread or
/// session in the process they have.
struct QuestionConversationTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("question-conversation-\(UUID().uuidString)")

    func claude(_ fake: FakeClaude) -> ClaudeSessionManager {
        ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder), userSettings: { nil })
    }

    func converter(_ session: ClaudeSessionManager, agent: SessionAgent = .claude) -> Converter {
        var config = Config.default
        config.provider = .apple
        config.questionBackend = QuestionBackend(agent)
        let settings = config
        return Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["from the provider"]),
                         questionSessions: [agent: session])
    }

    func value(_ flag: String, _ arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).map { arguments[$0 + 1] }
    }

    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> [String] {
        var answers: [String] = []
        do { for try await answer in stream { answers.append(answer) } } catch {}
        return answers
    }

    /// Asks `question` of `conversation` through `converter`, Claude Code (the fake's latest process) answering `text`.
    func ask(_ converter: Converter, _ question: String, turns: [Refinement.Turn] = [], in conversation: QuestionConversation,
             _ fake: FakeClaude, answer text: String) async throws -> String? {
        let before = fake.processes.map(\.messages.count).reduce(0, +)
        let stream = converter.generate(.question, input: question, turns: turns, conversation: conversation)
        let task = Task {
            var last: ConversionUpdate?
            for try await update in stream { last = update }
            return last
        }
        #expect(await Timing.eventually(within: 10) { fake.processes.map(\.messages.count).reduce(0, +) == before + 1 })
        let process = try #require(fake.last)
        process.started()
        process.text(text)
        process.done(text)
        return try await task.value?.result.versions.first?.text
    }

    func turn(_ answer: String, _ question: String) -> Refinement.Turn {
        Refinement.Turn(answer: ConversionResult(versions: [CandidateLine(answer, isComplete: true)]), instruction: question)
    }

    // MARK: - Claude Code

    @Test func eachConversationIsANewClaudeSessionItsFollowUpsStayInIt() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let converter = converter(session)
        let (first, second) = (QuestionConversation(), QuestionConversation())
        #expect(try await ask(converter, "what is rust", in: first, fake, answer: "A language.") == "A language.")
        let one = try #require(fake.last)
        let firstID = try #require(value("--session-id", one.arguments))
        // A follow-up: the same process and conversation, the new question alone.
        #expect(try await ask(converter, "what is rust", turns: [turn("A language.", "shorter")], in: first, fake,
                              answer: "Rust.") == "Rust.")
        #expect(fake.processes.count == 1 && one.messages == ["what is rust", "shorter"])
        // Another conversation: a new Claude Code session, named as ever; the earlier one's process ended, nothing of it
        // sent.
        #expect(try await ask(converter, "what is go", in: second, fake, answer: "Another.") == "Another.")
        let two = try #require(fake.last)
        #expect(fake.processes.count == 2 && one.terminated && !two.terminated)
        let secondID = try #require(value("--session-id", two.arguments))
        #expect(secondID != firstID && two.messages == ["what is go"])
        #expect(value("--name", two.arguments) == "AllInOneIME")
        #expect(try ClaudeSessionStore(directory: folder).sessionID() == secondID)
    }

    @Test func prewarmGetsTheNextConversationReadyAndItsQuestionGoesIntoIt() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let converter = converter(session)
        // The first @question typed: a conversation made ready, which its question goes into (no second start).
        session.prewarm()
        let warm = try #require(fake.last)
        let firstID = try #require(value("--session-id", warm.arguments))
        _ = try await ask(converter, "one", in: QuestionConversation(), fake, answer: "1")
        #expect(fake.processes.count == 1 && warm.messages == ["one"])
        // The next one typed: a new conversation's process started at once, ahead of its question.
        session.prewarm()
        #expect(fake.processes.count == 2 && warm.terminated)
        let next = try #require(fake.last)
        let secondID = try #require(value("--session-id", next.arguments))
        #expect(secondID != firstID && next.messages.isEmpty)
        // Typed again before anything was asked: the one made ready stays.
        session.prewarm()
        #expect(fake.processes.count == 2 && !next.terminated)
        _ = try await ask(converter, "two", in: QuestionConversation(), fake, answer: "2")
        #expect(fake.processes.count == 2 && next.messages == ["two"])
    }

    @Test func aFollowUpAfterTheProcessEndedResumesItsConversation() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        let converter = converter(session)
        let conversation = QuestionConversation()
        _ = try await ask(converter, "what is rust", in: conversation, fake, answer: "A language.")
        let id = try #require(value("--session-id", fake.last?.arguments ?? []))
        session.stop()  // ended (idle, a crash)
        _ = try await ask(converter, "what is rust", turns: [turn("A language.", "shorter")], in: conversation, fake, answer: "R.")
        #expect(fake.processes.count == 2 && value("--resume", fake.last?.arguments ?? []) == id)
        #expect(fake.last?.messages == ["shorter"])
        session.stop()

        // The input method relaunched: a conversation it didn't keep starts a new one, its earlier rounds told with the
        // question, never the session on disk resumed.
        let relaunched = claude(fake)
        defer { relaunched.stop() }
        let picked = QuestionConversation()  // a saved conversation picked, going on
        _ = try await ask(self.converter(relaunched), "what is rust",
                          turns: [turn("A language.", "shorter"), turn("R.", "and go?")], in: picked, fake, answer: "G.")
        let last = try #require(fake.last)
        #expect(value("--session-id", last.arguments) != nil && value("--session-id", last.arguments) != id)
        let message = try #require(last.messages.first)
        #expect(message.contains("what is rust") && message.contains("A language.") && message.hasSuffix("and go?"), "\(message)")
    }

    @Test func withoutAConversationQuestionsGoOnInTheCurrentOne() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let enteredConversation1: QuestionConversation? = nil
        let first = session.ask("one", in: enteredConversation1)
        let process = try #require(fake.last)
        process.started()
        process.done("1")
        _ = await collect(first)
        let enteredConversation2: QuestionConversation? = nil
        _ = session.ask("two", in: enteredConversation2)
        #expect(fake.processes.count == 1 && process.messages == ["one", "two"])
    }

    // MARK: - Codex and ACP agents: a new conversation in the same process

    func requests(_ process: FakeClaude.Process, _ method: String) -> [[String: Any]] {
        process.lines.filter { $0["method"] as? String == method }
    }

    func respond(_ process: FakeClaude.Process, _ method: String, result: [String: Any] = [:], jsonrpc: Bool = false) throws {
        let id = try #require(requests(process, method).last?["id"])
        process.say((jsonrpc ? ["jsonrpc": "2.0"] : [:]).merging(["id": id, "result": result]) { $1 })
    }

    @Test func codexOpensEachConversationAsANewNamedThreadInItsProcess() async throws {
        let fake = FakeClaude()
        let backend = CodexBackend(base: folder)
        let session = ClaudeSessionManager(backend: backend, launcher: fake)
        defer { session.stop() }
        session.prewarm()
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["userAgent": "test"])
        try respond(process, "config/read", result: ["config": ["model": "gpt"]])
        try respond(process, "thread/start", result: ["thread": ["id": "t1", "name": NSNull()]])
        let enteredConversation3: QuestionConversation? = QuestionConversation()
        let first = session.ask("one", in: enteredConversation3)
        #expect(await Timing.eventually(within: 10) { requests(process, "turn/start").count == 1 })
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1"]])
        process.say(["method": "item/agentMessage/delta", "params": ["threadId": "t1", "itemId": "m", "delta": "1"]])
        process.say(["method": "turn/completed", "params": ["threadId": "t1", "turn": ["id": "turn_1", "status": "completed"]]])
        #expect(await collect(first) == ["1"])
        // The next @question typed: a new thread in the same process, named AllInOneIME too.
        session.prewarm()
        #expect(fake.processes.count == 1 && requests(process, "thread/start").count == 2)
        try respond(process, "thread/start", result: ["thread": ["id": "t2", "name": NSNull()]])
        let named = requests(process, "thread/name/set").compactMap { $0["params"] as? [String: Any] }
        #expect(named.map { $0["threadId"] as? String } == ["t1", "t2"])
        #expect(named.allSatisfy { $0["name"] as? String == "AllInOneIME" })
        #expect(ClaudeSessionStore(backend).agentSessionID() == "t2")
        let enteredConversation4: QuestionConversation? = QuestionConversation()
        _ = session.ask("two", in: enteredConversation4)
        #expect(await Timing.eventually(within: 10) { requests(process, "turn/start").count == 2 })
        #expect((requests(process, "turn/start").last?["params"] as? [String: Any])?["threadId"] as? String == "t2")
        #expect(fake.processes.count == 1)
    }

    @Test func aQuestionOfAnotherConversationOpensItsThreadFirst() async throws {
        let fake = FakeClaude()
        let session = ClaudeSessionManager(backend: CodexBackend(base: folder), launcher: fake)
        defer { session.stop() }
        let enteredConversation5: QuestionConversation? = QuestionConversation()
        let first = session.ask("one", in: enteredConversation5)
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["userAgent": "test"])
        try respond(process, "config/read", result: ["config": ["model": "gpt"]])
        try respond(process, "thread/start", result: ["thread": ["id": "t1", "name": NSNull()]])
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1"]])
        process.say(["method": "turn/completed", "params": ["threadId": "t1", "turn": ["id": "turn_1", "status": "completed"]]])
        _ = await collect(first)
        // No prewarm (asked at once): the thread opens, then the question goes.
        let enteredConversation6: QuestionConversation? = QuestionConversation()
        let second = session.ask("two", in: enteredConversation6)  // kept: a stream let go of is given up (Esc)
        #expect(requests(process, "thread/start").count == 2 && requests(process, "turn/start").count == 1)
        try respond(process, "thread/start", result: ["thread": ["id": "t2", "name": NSNull()]])
        #expect(await Timing.eventually(within: 10) { requests(process, "turn/start").count == 2 })
        #expect((requests(process, "turn/start").last?["params"] as? [String: Any])?["threadId"] as? String == "t2")
        withExtendedLifetime(second) {}
    }

    @Test func anACPAgentOpensEachConversationAsANewSessionInItsProcess() async throws {
        let fake = FakeClaude()
        var kiro = ACPBackend.kiro
        kiro.base = folder
        let session = ClaudeSessionManager(backend: kiro, launcher: fake)
        defer { session.stop() }
        let modes: [String: Any] = ["currentModeId": "vibe", "availableModes": [["id": "vibe"], ["id": ACPBackend.kiroMode]]]
        session.prewarm()
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]], jsonrpc: true)
        try respond(process, "session/new", result: ["sessionId": "sess_1", "modes": modes], jsonrpc: true)
        try respond(process, "session/set_mode", jsonrpc: true)
        let enteredConversation7: QuestionConversation? = QuestionConversation()
        let first = session.ask("one", in: enteredConversation7)
        #expect(await Timing.eventually(within: 10) { requests(process, "session/prompt").count == 1 })
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"], jsonrpc: true)
        _ = await collect(first)
        session.prewarm()
        #expect(fake.processes.count == 1 && requests(process, "session/new").count == 2)
        try respond(process, "session/new", result: ["sessionId": "sess_2", "modes": modes], jsonrpc: true)
        // In the web-only mode again before anything is asked in it.
        #expect(requests(process, "session/set_mode").count == 2)
        #expect((requests(process, "session/set_mode").last?["params"] as? [String: Any])?["sessionId"] as? String == "sess_2")
        try respond(process, "session/set_mode", jsonrpc: true)
        let enteredConversation8: QuestionConversation? = QuestionConversation()
        _ = session.ask("two", in: enteredConversation8)
        #expect(await Timing.eventually(within: 10) { requests(process, "session/prompt").count == 2 })
        #expect((requests(process, "session/prompt").last?["params"] as? [String: Any])?["sessionId"] as? String == "sess_2")
        #expect(ClaudeSessionStore(kiro).agentSessionID() == "sess_2" && fake.processes.count == 1)
    }

    // MARK: - The panel

    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.english])
            config.provider = .apple
            config.questionBackend = .claudeSession
        }
    }

    @Test func eachQuestionInThePanelIsAConversationItsFollowUpsKeepIt() async throws {
        try await withInterfaceLanguage("en") {
            let fake = FakeClaude()
            let session = claude(fake)
            defer { session.stop() }
            let settings = Settings()
            let converter = Converter(loadConfig: { settings.config }, appleModel: StubAppleModel(answer: ["x"]),
                                      questionSessions: [.claude: session])
            var services = SessionServices(converter: converter, loadSettings: { settings.config })
            let engine = FakeEngine()
            services.levelOne = { .engine(engine) }
            let host = FakeHost(services: services)
            host.focus()
            func answered(_ text: String, messages: Int) throws -> Bool {
                guard host.settle(timeout: 30, until: { fake.last?.messages.count == messages }) else { return false }
                let process = try #require(fake.last)
                process.started()
                process.text(text)
                process.done(text)
                // In, and the answer final: what is typed now is the next question.
                return host.settle(timeout: 30) {
                    host.composer.phase == .choosing && String(describing: host.panel).contains(text)
                }
            }
            host.press(FakeHost.at)
            host.type("question")
            host.press(FakeHost.tab)
            #expect(host.settle(timeout: 30) { fake.processes.count == 1 })
            host.type("what is rust")
            host.press(FakeHost.enter)
            #expect(try answered("Systems language.", messages: 1))
            let conversation = try #require(host.composer.questionConversation)
            host.type("shorter")
            host.press(FakeHost.enter)
            #expect(try answered("Rust.", messages: 2))
            #expect(host.composer.questionConversation == conversation)
            #expect(fake.processes.count == 1 && fake.last?.messages == ["what is rust", "shorter"])
            // A new @question: a new conversation, made ready as it is typed.
            host.press(FakeHost.escape)
            host.press(FakeHost.escape)
            host.press(FakeHost.escape)
            host.press(FakeHost.at)
            host.type("question")
            host.press(FakeHost.tab)
            #expect(host.settle(timeout: 30) { fake.processes.count == 2 })
            host.type("what is go")
            host.press(FakeHost.enter)
            #expect(try answered("Another language.", messages: 1))
            #expect(host.composer.questionConversation != conversation)
            #expect(fake.processes.count == 2 && fake.last?.messages == ["what is go"])
            let ids = fake.processes.map { value("--session-id", $0.arguments) }
            #expect(ids[0] != nil && ids[1] != nil && ids[0] != ids[1])
        }
    }
}
