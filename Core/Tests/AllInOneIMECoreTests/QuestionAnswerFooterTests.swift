import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// What an `@question`'s answer tells its footer (`ConversionUpdate.answeredBy`, `newConversation`, `tokens`): which
/// session's CLI answered, or the provider; whether the agent's conversation is new with it (the first question, or one
/// whose conversation couldn't be resumed: the agent doesn't have the rounds before); the tokens the CLI says it used.
struct QuestionAnswerFooterTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("answer-footer-\(UUID().uuidString)")

    func converter(_ sessions: [SessionAgent: ClaudeSessionManager], _ backend: QuestionBackend?) -> Converter {
        var config = Config.default
        config.provider = .apple
        config.questionBackend = backend
        let settings = config
        return Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["From the provider."]),
                         questionSessions: sessions)
    }

    /// The last update of `stream`, the fake's latest process answering with `answer` once the question is in.
    func last(_ stream: AsyncThrowingStream<ConversionUpdate, Error>, _ fake: FakeClaude,
              messages: Int, _ answer: (FakeClaude.Process) throws -> Void) async throws -> ConversionUpdate? {
        let task = Task {
            var last: ConversionUpdate?
            for try await update in stream { last = update }
            return last
        }
        #expect(await Timing.eventually(within: 10) { fake.last?.messages.count == messages })
        try answer(try #require(fake.last))
        return try await task.value
    }

    func result(_ text: String, usage: [String: Any]) -> [String: Any] {
        ["type": "result", "subtype": "success", "is_error": false, "result": text, "terminal_reason": "completed", "usage": usage]
    }

    @Test func claudeCodeSaysItsTokensAndANewConversation() async throws {
        let fake = FakeClaude()
        let session = ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder), userSettings: { nil })
        defer { session.stop() }
        let converter = converter([.claude: session], .claudeSession)
        let conversation = QuestionConversation()
        let first = try await last(converter.generate(.question, input: "one", conversation: conversation), fake, messages: 1) {
            $0.started()
            $0.text("1")
            $0.say(result("1", usage: ["input_tokens": 3, "cache_creation_input_tokens": 9000, "cache_read_input_tokens": 12000,
                                       "output_tokens": 40]))
        }
        #expect(first?.answeredBy == .claudeSession && first?.newConversation == true && first?.tokens == 21_043)
        let turns = [Refinement.Turn(answer: ConversionResult(versions: [CandidateLine("1", isComplete: true)]), instruction: "two")]
        let second = try await last(converter.generate(.question, input: "one", turns: turns, conversation: conversation), fake,
                                    messages: 2) {
            $0.started()
            $0.text("2")
            $0.done("2")
        }
        #expect(second?.answeredBy == .claudeSession && second?.newConversation == false && second?.tokens == nil)
    }

    @Test func aConversationClaudeCodeCouldNotResumeIsNew() async throws {
        let fake = FakeClaude()
        let session = ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder), userSettings: { nil })
        defer { session.stop() }
        let converter = converter([.claude: session], .claudeSession)
        let conversation = QuestionConversation()
        _ = try await last(converter.generate(.question, input: "one", conversation: conversation), fake, messages: 1) {
            $0.started()
            $0.done("1")
        }
        session.stop()
        // Its transcript gone: --resume ends before the session starts, the retry begins it afresh.
        let turns = [Refinement.Turn(answer: ConversionResult(versions: [CandidateLine("1", isComplete: true)]), instruction: "two")]
        let stream = converter.generate(.question, input: "one", turns: turns, conversation: conversation)
        let task = Task {
            var last: ConversionUpdate?
            for try await update in stream { last = update }
            return last
        }
        #expect(await Timing.eventually(within: 10) { fake.processes.count == 2 && fake.last?.messages.count == 1 })
        let resumed = try #require(fake.last)
        #expect(resumed.arguments.contains("--resume"))
        resumed.exit(1, "No conversation found with session ID")
        #expect(await Timing.eventually(within: 10) { fake.processes.count == 3 && fake.last?.messages.count == 1 })
        let again = try #require(fake.last)
        #expect(again.arguments.contains("--session-id"))
        again.started()
        again.done("2")
        let update = try await task.value
        #expect(update?.result.versions.first?.text == "2" && update?.newConversation == true)
    }

    @Test func codexSaysTheTurnsTokensAndAThreadItCouldNotResumeIsNew() async throws {
        let fake = FakeClaude()
        let backend = CodexBackend(base: folder)
        _ = try ClaudeSessionStore(backend).sessionID()
        ClaudeSessionStore(backend).setAgentSessionID("gone")
        let session = ClaudeSessionManager(backend: backend, launcher: fake)
        defer { session.stop() }
        let stream = session.answer("one")
        let process = try #require(fake.last)
        func respond(_ method: String, _ result: [String: Any]? = nil, error: [String: Any]? = nil) throws {
            let id = try #require(process.lines.last { $0["method"] as? String == method }?["id"])
            process.say(error.map { ["id": id, "error": $0] } ?? ["id": id, "result": result ?? [:]])
        }
        func usage(total: Int, last: Int) {
            process.say(["method": "thread/tokenUsage/updated",
                         "params": ["threadId": "t2", "turnId": "turn_1",
                                    "tokenUsage": ["total": ["totalTokens": total], "last": ["totalTokens": last]]]])
        }
        try respond("initialize", ["userAgent": "test"])
        try respond("config/read", ["config": ["model": "gpt"]])
        // The thread kept is gone: a new one.
        try respond("thread/resume", error: ["code": -32600, "message": "thread not found"])
        try respond("thread/start", ["thread": ["id": "t2", "name": NSNull()]])
        try respond("turn/start", ["turn": ["id": "turn_1"]])
        process.say(["method": "item/agentMessage/delta", "params": ["threadId": "t2", "itemId": "m", "delta": "1"]])
        // The thread had 5000 before the turn; its first response used 1200, its second 300 (said twice).
        usage(total: 6200, last: 1200)
        usage(total: 6500, last: 300)
        usage(total: 6500, last: 300)
        process.say(["method": "turn/completed", "params": ["threadId": "t2", "turn": ["id": "turn_1", "status": "completed"]]])
        var replies: [SessionReply] = []
        for try await reply in stream { replies.append(reply) }
        #expect(replies.last == SessionReply(text: "1", newConversation: true, tokens: 1500))
    }

    @Test func anACPAgentSaysItsTokens() async throws {
        let fake = FakeClaude()
        var kiro = ACPBackend.kiro
        kiro.base = folder
        let session = ClaudeSessionManager(backend: kiro, launcher: fake)
        defer { session.stop() }
        let stream = session.answer("one")
        let process = try #require(fake.last)
        func respond(_ method: String, _ result: [String: Any]) throws {
            let id = try #require(process.lines.last { $0["method"] as? String == method }?["id"])
            process.say(["jsonrpc": "2.0", "id": id, "result": result])
        }
        let modes: [String: Any] = ["currentModeId": ACPBackend.kiroMode, "availableModes": [["id": ACPBackend.kiroMode]]]
        try respond("initialize", ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]])
        try respond("session/new", ["sessionId": "sess_1", "modes": modes])
        #expect(await Timing.eventually(within: 10) { process.lines.contains { $0["method"] as? String == "session/prompt" } })
        process.say(["jsonrpc": "2.0", "method": "session/update",
                     "params": ["sessionId": "sess_1", "update": ["sessionUpdate": "agent_message_chunk",
                                                                  "content": ["type": "text", "text": "1"]]]])
        try respond("session/prompt", ["stopReason": "end_turn", "usage": ["inputTokens": 900, "outputTokens": 20,
                                                                           "totalTokens": 920]])
        var replies: [SessionReply] = []
        for try await reply in stream { replies.append(reply) }
        #expect(replies.last == SessionReply(text: "1", newConversation: true, tokens: 920))
    }

    @Test func theProviderSaysItAnsweredAQuestionOnly() async throws {
        let converter = converter([:], .provider)
        var last: ConversionUpdate?
        for try await update in converter.generate(.question, input: "what is rust") { last = update }
        #expect(last?.answeredBy == .provider && last?.newConversation == false && last?.tokens == nil)
        last = nil
        for try await update in converter.generate(Command(name: "summary", kind: .generate,
                                                           custom: CustomCommand(name: "summary", type: .prompt, prompt: "Summarize")),
                                                   input: "text") { last = update }
        #expect(last != nil && last?.answeredBy == nil)
    }
}
