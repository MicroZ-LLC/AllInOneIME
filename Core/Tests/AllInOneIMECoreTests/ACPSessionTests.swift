import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// The question session on an ACP agent (`ACPBackend`, Kiro CLI): the handshake (a new session, or the one it had
/// loaded), a prompt streamed, what the agent asks refused, a turn cancelled, a crash loaded again, signed out falling
/// back to the provider; and `@question` going to the session of @agent's agent. The fake agent (`FakeClaude`'s
/// processes: what is sent, what it says) answers as `kiro-cli acp` 3.1.0 does.
struct ACPSessionTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kiro-session-\(UUID().uuidString)")
    var store: ClaudeSessionStore { ClaudeSessionStore(directory: folder, files: ACPBackend.kiro.files) }

    func manager(_ fake: FakeClaude, alive: @escaping @Sendable (Int32) -> Bool = { _ in false }) -> ClaudeSessionManager {
        ClaudeSessionManager(backend: ACPBackend.kiro, launcher: fake, store: store, isAlive: alive)
    }

    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (answers: [String], error: Error?) {
        var answers: [String] = []
        do {
            for try await answer in stream { answers.append(answer) }
            return (answers, nil)
        } catch {
            return (answers, error)
        }
    }

    // MARK: - The fake agent

    /// The requests `process` was sent with `method`.
    func requests(_ process: FakeClaude.Process, _ method: String) -> [[String: Any]] {
        process.lines.filter { $0["method"] as? String == method }
    }

    /// Answers the last request with `method` with `result` (or `error`).
    func respond(_ process: FakeClaude.Process, _ method: String, result: [String: Any] = [:], error: [String: Any]? = nil) throws {
        let request = try #require(requests(process, method).last)
        let id = try #require(request["id"])
        var line: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let error { line["error"] = error } else { line["result"] = result }
        process.say(line)
    }

    /// The handshake as Kiro answers it: `initialize` (it can load sessions), then `session/new` giving `id` (or the
    /// `session/load` asked for) in the default mode, then `session/set_mode` to the input method's.
    func open(_ process: FakeClaude.Process, newID id: String = "sess_1") throws {
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]])
        let modes: [String: Any] = ["currentModeId": "vibe", "availableModes": [["id": "vibe"], ["id": ACPBackend.kiroMode]]]
        if !requests(process, "session/load").isEmpty {
            try respond(process, "session/load", result: ["modes": modes])
        } else {
            try respond(process, "session/new", result: ["sessionId": id, "modes": modes])
        }
        try respond(process, "session/set_mode")
    }

    func update(_ process: FakeClaude.Process, _ update: [String: Any], session: String = "sess_1") {
        process.say(["jsonrpc": "2.0", "method": "session/update", "params": ["sessionId": session, "update": update]])
    }

    func chunk(_ process: FakeClaude.Process, _ text: String, session: String = "sess_1") {
        update(process, ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": text]], session: session)
    }

    /// The prompts sent, their text.
    func prompts(_ process: FakeClaude.Process) -> [String] {
        requests(process, "session/prompt").compactMap {
            (($0["params"] as? [String: Any])?["prompt"] as? [[String: Any]])?.first?["text"] as? String
        }
    }

    // MARK: - The handshake and a prompt

    @Test func aNewSessionIsMadeInTheFolderInItsModeAndAPromptStreams() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("what is rust")
        let process = try #require(fake.last)
        #expect(process.arguments == ["acp"] && process.directory == folder)
        // Only the handshake until the session is open.
        let initialize = try #require(requests(process, "initialize").first)
        #expect((initialize["params"] as? [String: Any])?["protocolVersion"] as? Int == 1 && prompts(process).isEmpty)
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]])
        let new = try #require(requests(process, "session/new").first?["params"] as? [String: Any])
        #expect(new["cwd"] as? String == folder.path && (new["mcpServers"] as? [Any])?.isEmpty == true)
        #expect(requests(process, "session/load").isEmpty)
        try respond(process, "session/new", result: ["sessionId": "sess_1",
                                                     "modes": ["currentModeId": "vibe", "availableModes": [["id": "vibe"], ["id": "allinoneime"]]]])
        let mode = try #require(requests(process, "session/set_mode").first?["params"] as? [String: Any])
        #expect(mode["sessionId"] as? String == "sess_1" && mode["modeId"] as? String == "allinoneime" && prompts(process).isEmpty)
        try respond(process, "session/set_mode")
        #expect(prompts(process) == ["what is rust"])
        update(process, ["sessionUpdate": "agent_thought_chunk", "content": ["type": "text", "text": "Thinking"]])
        chunk(process, "A systems")
        chunk(process, "x", session: "sess_other")  // another session's
        chunk(process, " language.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        let got = await collect(stream)
        #expect(got.answers == ["A systems", "A systems language."] && got.error == nil)
        #expect(store.agentSessionID() == "sess_1" && store.resumable && session.availability == .ready)
        // The folder: Kiro's steering (the instructions) and the agent config (web tools only, no MCP).
        let steering = try String(contentsOf: folder.appendingPathComponent(".kiro/steering/allinoneime.md"), encoding: .utf8)
        #expect(steering == ClaudeSession.instructions)
        let agent = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(".kiro/agents/allinoneime.json"))) as? [String: Any])
        #expect(agent["name"] as? String == "allinoneime" && agent["tools"] as? [String] == ["web_search", "web_fetch"])
        #expect((agent["mcpServers"] as? [String: Any])?.isEmpty == true && agent["includeMcpJson"] as? Bool == false)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("CLAUDE.md").path))

        // The next question in the same process: just a prompt.
        let next = session.ask("and go?")
        #expect(prompts(process) == ["what is rust", "and go?"] && requests(process, "session/new").count == 1)
        chunk(process, "Also one.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(next).answers == ["Also one."])
        #expect(fake.processes.count == 1)
    }

    @Test func aPrewarmedProcessHasTheSessionOpenBeforeTheQuestion() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        session.prewarm()
        let process = try #require(fake.last)
        try open(process)
        #expect(prompts(process).isEmpty)
        let stream = session.ask("刚才那个问题")
        #expect(prompts(process) == ["刚才那个问题"])
        chunk(process, "你问的是 rust")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(stream).answers.last == "你问的是 rust")
    }

    @Test func aToolCallStartsTheAnswerAgain() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("weather in Paris now")
        let process = try #require(fake.last)
        try open(process)
        chunk(process, "Let me look.")
        update(process, ["sessionUpdate": "tool_call", "toolCallId": "t1", "title": "Fetch URL", "kind": "fetch", "status": "pending"])
        update(process, ["sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed"])
        chunk(process, "Sunny, 18 °C.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(stream).answers == ["Let me look.", "Sunny, 18 °C."])
    }

    // MARK: - Loading it again

    @Test func aCrashFailsThatQuestionAndTheNextLoadsTheSession() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let first = session.ask("remember 7341")
        let process = try #require(fake.last)
        try open(process)
        chunk(process, "OK")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        _ = await collect(first)
        let stream = session.ask("count to 200")
        chunk(process, "1 2")
        process.exit(134, "panicked")
        let got = await collect(stream)
        #expect(got.answers == ["1 2"] && got.error as? ClaudeSessionError == .exited(134, "panicked"))

        let next = session.ask("which number?")
        let restarted = try #require(fake.last)
        #expect(fake.processes.count == 2 && restarted.arguments == ["acp"])
        try respond(restarted, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]])
        let load = try #require(requests(restarted, "session/load").first?["params"] as? [String: Any])
        #expect(load["sessionId"] as? String == "sess_1" && load["cwd"] as? String == folder.path && requests(restarted, "session/new").isEmpty)
        // The conversation replayed before the load's response: none of it is an answer.
        update(restarted, ["sessionUpdate": "user_message_chunk", "content": ["type": "text", "text": "remember 7341"]])
        chunk(restarted, "OK")
        try respond(restarted, "session/load", result: ["modes": ["currentModeId": "allinoneime", "availableModes": [["id": "allinoneime"]]]])
        #expect(requests(restarted, "session/set_mode").isEmpty)  // in its mode already
        #expect(prompts(restarted) == ["which number?"])
        chunk(restarted, "7341")
        try respond(restarted, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(next).answers == ["7341"])
    }

    @Test func aSessionThatWontLoadIsMadeAnewAndForgetsWhatItWasTold() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        _ = try store.sessionID()
        store.setAgentSessionID("sess_gone")
        session.remember(answers: ["An earlier answer."])
        #expect(session.missing([QuestionChat.Round(question: "q", answer: "An earlier answer.")]).isEmpty)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]])
        try respond(process, "session/load", error: ["code": -32603, "message": "Session not found"])
        try respond(process, "session/new", result: ["sessionId": "sess_2", "modes": ["currentModeId": ACPBackend.kiroMode]])
        #expect(prompts(process) == ["hi"] && store.agentSessionID() == "sess_2")
        chunk(process, "Hello", session: "sess_2")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(stream).answers == ["Hello"])
        // The new session wasn't told the earlier answer: it is told again with the next question.
        #expect(session.missing([QuestionChat.Round(question: "q", answer: "An earlier answer.")]).count == 1)
    }

    @Test func anAgentThatCantLoadSessionsGetsANewOne() throws {
        let fake = FakeClaude()
        let session = manager(fake)
        _ = try store.sessionID()
        store.setAgentSessionID("sess_1")
        _ = session.ask("hi")
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": false]])
        #expect(requests(process, "session/load").isEmpty && requests(process, "session/new").count == 1)
    }

    // MARK: - What the agent asks, stopping a turn

    @Test func whatTheAgentAsksIsRefused() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("create hello.txt")
        let process = try #require(fake.last)
        try open(process)
        process.say(["jsonrpc": "2.0", "id": 0, "method": "session/request_permission",
                     "params": ["sessionId": "sess_1", "toolCall": ["toolCallId": "t1", "title": "Write File"],
                                "options": [["optionId": "accept", "kind": "allow_once"], ["optionId": "reject", "kind": "reject_once"]]]])
        let denied = try #require(process.lines.last)
        #expect(denied["id"] as? Int == 0 && denied["method"] == nil)
        #expect(((denied["result"] as? [String: Any])?["outcome"] as? [String: Any])?["outcome"] as? String == "cancelled")
        process.say(["jsonrpc": "2.0", "id": "fs-1", "method": "fs/read_text_file", "params": ["sessionId": "sess_1", "path": "/etc/hosts"]])
        let refused = try #require(process.lines.last)
        #expect(refused["id"] as? String == "fs-1" && (refused["error"] as? [String: Any])?["code"] as? Int == -32601)
        chunk(process, "I didn't create it.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(stream).answers == ["I didn't create it."])
    }

    @Test func givingUpTheAnswerCancelsTheTurnAndTheProcessStays() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("count to 200")
        let process = try #require(fake.last)
        try open(process)
        chunk(process, "1 2 3")
        let reading = Task { await collect(stream) }
        try await Task.sleep(for: .milliseconds(50))
        reading.cancel()
        #expect(await Timing.eventually { !requests(process, "session/cancel").isEmpty })
        let cancel = try #require(requests(process, "session/cancel").first)
        #expect(cancel["id"] == nil && (cancel["params"] as? [String: Any])?["sessionId"] as? String == "sess_1")
        #expect(!process.terminated && session.isRunning)
        // A question asked meanwhile waits for the cancelled turn to end.
        let next = session.ask("still there?")
        #expect(prompts(process) == ["count to 200"])
        chunk(process, " 4")  // late: dropped
        try respond(process, "session/prompt", result: ["stopReason": "cancelled"])
        #expect(prompts(process) == ["count to 200", "still there?"])
        chunk(process, "yes")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(next).answers == ["yes"])
        #expect(fake.processes.count == 1)
    }

    @Test func interruptBeforeTheSessionOpensSendsNoPrompt() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("long")
        let process = try #require(fake.last)
        session.interrupt()
        #expect(await collect(stream).error is CancellationError)
        try open(process)
        #expect(prompts(process).isEmpty && requests(process, "session/cancel").isEmpty)
        let next = session.ask("short")
        #expect(prompts(process) == ["short"])
        chunk(process, "ok")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(next).answers == ["ok"])
    }

    // MARK: - Signed out, the hand-off

    @Test func signedOutFailsSoTheProviderAnswers() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": false],
                                                    "authMethods": [["id": "kiro-login", "name": "Kiro Login"]]])
        try respond(process, "session/new", error: ["code": -32000, "message": "Authentication required. Not logged in. Set the KIRO_API_KEY environment variable or run `kiro-cli login` first."])
        let error = await collect(stream).error as? ClaudeSessionError
        #expect(error == .signedOut && error?.fallsBack == true && session.availability == .signedOut)
        #expect(process.terminated && !session.isRunning && store.agentSessionID() == nil)
        #expect(error?.description(for: .kiro).contains("kiro-cli login") == true)
        // The sign-in check: `kiro-cli whoami`, signed in when it exits 0.
        #expect(session.authStatusArguments() == ["whoami", "-f", "json"])
        #expect(ACPBackend.kiro.signedIn(status: 0, output: Data()) == true && ACPBackend.kiro.signedIn(status: 1, output: Data()) == false)
    }

    @Test func signedOutThroughTheConverterTheProviderAnswersAndSaysWhy() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        var settings = Config.default
        settings.provider = .apple
        settings.agent = .kiro
        settings.questionBackend = .kiroSession
        let config = settings
        let apple = StubAppleModel(answer: ["From the provider."])
        let converter = Converter(loadConfig: { config }, appleModel: apple, questionSessions: [.kiro: session])
        let stream = converter.generate(.question, input: "what is rust")
        #expect(await Timing.eventually { !(fake.last.map { requests($0, "initialize") } ?? []).isEmpty })
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": [:] as [String: Any]])
        try respond(process, "session/new", error: ["code": -32000, "message": "Authentication required."])
        var last: ConversionUpdate?
        for try await update in stream { last = update }
        #expect(last?.result.versions.first?.text == "From the provider." && apple.requests.count == 1)
        #expect(last?.note == ClaudeSessionError.signedOut.fallbackNote(for: .kiro))
        #expect(last?.note?.contains("kiro-cli login") == true)
    }

    @Test func handingOffResumesTheAgentsSessionInTerminal() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        // No session yet: a new chat in the folder.
        #expect(try session.handOff(program: "/u/kiro-cli").arguments == ["/u/kiro-cli", "chat"])
        let stream = session.ask("one")
        let process = try #require(fake.last)
        try open(process, newID: "sess_abc")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        _ = await collect(stream)
        let (arguments, directory) = try session.handOff(program: "/u/kiro-cli")
        #expect(arguments == ["/u/kiro-cli", "chat", "--resume-id", "sess_abc"] && directory == folder)
        #expect(process.terminated && !session.isRunning)
        // Start over: a new session (the agent's id forgotten).
        try session.startOver()
        #expect(store.agentSessionID() == nil)
    }

    // MARK: - Which session answers

    @Test func theSessionPickedOrAutomaticallyTheOneOfAtAgentsAgent() {
        typealias A = ClaudeSession.Availability
        /// Where questions go with `backend` picked and `@agent` handing to `at`, the sessions in `ready` ready and every
        /// other one `other`.
        func agent(_ backend: QuestionBackend?, at: AgentKind, ready: Set<SessionAgent>, other: A = .signedOut) -> SessionAgent? {
            var config = Config.default
            config.agent = at
            config.questionBackend = backend
            return config.questionSessionAgent(availability: { ready.contains($0) ? .ready : other })
        }
        // Claude Code first, then the two added in 0.7.4, then Kiro CLI.
        let order = QuestionBackend.sessionAgents
        #expect(order == [.claude, .codex, .gemini, .kiro])
        for mask in 0..<(1 << order.count) {
            let ready = Set(order.indices.filter { mask & (1 << $0) != 0 }.map { order[$0] })
            for at in AgentKind.allCases {
                for other in [A.unknown, .notInstalled, .signedOut] {
                    // Picked: that one, whatever it can do now (tried; the provider answers with why).
                    for picked in order { #expect(agent(QuestionBackend(picked), at: at, ready: ready, other: other) == picked) }
                    #expect(agent(.provider, at: at, ready: ready, other: other) == nil)
                    // Automatic: @agent's agent's session when it has one and it's ready, else the first ready one in the
                    // order, else the provider.
                    let own = SessionAgent(at).flatMap { ready.contains($0) ? $0 : nil }
                    #expect(agent(nil, at: at, ready: ready, other: other) == own ?? order.first { ready.contains($0) },
                            "@agent \(at), ready \(ready), others \(other)")
                }
            }
        }
        // Spelled out: Kiro for @agent's Kiro even with Claude Code ready; Codex and Gemini CLI after Claude Code, before
        // Kiro; @agent's Gemini CLI: its own session; a custom agent has none.
        #expect(agent(nil, at: .kiro, ready: [.claude, .kiro]) == .kiro)
        #expect(agent(nil, at: .kiro, ready: [.claude]) == .claude)
        #expect(agent(nil, at: .claude, ready: [.codex, .gemini, .kiro]) == .codex)
        #expect(agent(nil, at: .claude, ready: [.gemini, .kiro]) == .gemini)
        #expect(agent(nil, at: .claude, ready: [.claude, .codex]) == .claude)
        #expect(agent(nil, at: .gemini, ready: [.claude, .gemini]) == .gemini)
        #expect(agent(nil, at: .custom, ready: [.codex, .kiro]) == .codex)
        #expect(agent(nil, at: .claude, ready: []) == nil)
        // What Automatic looks at, in that order; nothing when a session or the provider is picked.
        var config = Config.default
        config.agent = .kiro
        #expect(config.questionSessionCandidates == [.kiro, .claude, .codex, .gemini])
        config.agent = .custom
        #expect(config.questionSessionCandidates == order)
        config.questionBackend = .codexSession
        #expect(config.questionSessionCandidates.isEmpty)
        config.questionBackend = .provider
        #expect(config.questionSessionCandidates.isEmpty)
        // The file: Claude Code's keeps its name from before the others.
        #expect(QuestionBackend.allCases.map(\.rawValue) == ["claudeSession", "codexSession", "geminiSession", "kiroSession", "provider"])
        for backend in QuestionBackend.allCases {
            let decoded = try? JSONDecoder().decode(Config.self, from: Data(#"{"questionBackend":"\#(backend.rawValue)"}"#.utf8))
            #expect(decoded?.questionBackend == backend)
        }
    }

    @Test func questionsGoToTheSessionTheSettingsSay() async throws {
        let claudeFake = FakeClaude(), kiroFake = FakeClaude()
        let claude = ClaudeSessionManager(launcher: claudeFake, store: ClaudeSessionStore(directory: folder.appendingPathComponent("c")),
                                          userSettings: { nil })
        let kiro = manager(kiroFake)
        let sessions = [SessionAgent.claude: claude, .kiro: kiro]
        var settings = Config.default
        settings.provider = .apple
        let current = Locked(initialState: settings)
        let apple = StubAppleModel(answer: ["From the provider."])
        let converter = Converter(loadConfig: { current.withLock { $0 } }, appleModel: apple, questionSessions: sessions)
        func config(_ agent: AgentKind, _ backend: QuestionBackend?) -> Config {
            current.withLock { $0.agent = agent; $0.questionBackend = backend }
            return current.withLock { $0 }
        }

        // Picked: that session, whatever @agent hands to.
        #expect(converter.questionSession(config(.claude, .kiroSession)) === kiro)
        #expect(converter.questionSession(config(.kiro, .claudeSession)) === claude)
        #expect(converter.questionSession(config(.kiro, .provider)) == nil)
        #expect(kiro.answersQuestions(config(.claude, .kiroSession)) && !claude.answersQuestions(config(.claude, .kiroSession)))
        // Automatic: nothing known yet, the provider; then @agent's agent's, else the other ready one.
        #expect(converter.questionSession(config(.kiro, nil)) == nil)
        claude.availability = .ready
        #expect(converter.questionSession(config(.kiro, nil)) === claude)
        kiro.availability = .ready
        #expect(converter.questionSession(config(.kiro, nil)) === kiro && converter.questionSession(config(.gemini, nil)) === claude)

        // Kiro picked: the question goes to its process, none to Claude's.
        _ = config(.claude, .kiroSession)
        let stream = converter.generate(.question, input: "what is rust")
        #expect(await Timing.eventually { kiroFake.last != nil })
        let process = try #require(kiroFake.last)
        try open(process)
        chunk(process, "A systems language.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        var last: ConversionUpdate?
        for try await update in stream { last = update }
        #expect(last?.result.versions.first?.text == "A systems language." && last?.note == nil)
        #expect(claudeFake.processes.isEmpty && apple.requests.isEmpty)

        // The provider picked: the provider.
        _ = config(.kiro, .provider)
        last = nil
        for try await update in converter.generate(.question, input: "what is go") { last = update }
        #expect(last?.result.versions.first?.text == "From the provider." && apple.requests.count == 1)
        #expect(kiroFake.processes.count == 1 && claudeFake.processes.isEmpty)
    }

    @Test func theHandOffChoiceNamesTheSessionsAgent() {
        #expect(ChatHandoff.withSession([.kiroCLI, .claudeCode, .copy], agent: .kiro) == [.claudeSession, .claudeCode, .copy])
        #expect(SessionText.shortName(.claudeSession, picked: .claude, session: .kiro, language: "en") == "Kiro CLI (this session)")
        #expect(SessionText.shortName(.claudeSession, picked: .kiro, session: .claude, language: "en") == "Claude Code (this session)")
        #expect(ClaudeSessionError.noResponse.description(for: .kiro).contains("Kiro"))
        #expect(ClaudeSessionError.noResponse.description(for: .claude) == ClaudeSessionError.noResponse.errorDescription)
    }
}
