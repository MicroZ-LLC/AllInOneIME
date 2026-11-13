import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// The question sessions added in 0.7.4 and what changed for all of them: Codex over its app server (`CodexBackend`, the
/// fake answering as `codex app-server` 0.163 does; Antigravity's, which took Gemini CLI's place, has
/// AntigravitySessionTests); the name "AllInOneIME" each session has where the agent can name one; the sign-in checks run when a
/// question could first go to a session, not at launch, kept for the launch when ready and looked at again after a
/// failure; and the process started ahead only for an `@question` about to be asked.
@Suite(.serialized)
struct QuestionSessionBackendsTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString)")

    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (answers: [String], error: Error?) {
        var answers: [String] = []
        do {
            for try await answer in stream { answers.append(answer) }
            return (answers, nil)
        } catch {
            return (answers, error)
        }
    }

    // MARK: - Codex: the fake app server

    func codex(_ fake: FakeClaude, answerClock: any Clock<Duration> = ContinuousClock(),
               uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> ClaudeSessionManager {
        ClaudeSessionManager(backend: CodexBackend(base: folder), launcher: fake, answerClock: answerClock, uptime: uptime)
    }

    func requests(_ process: FakeClaude.Process, _ method: String) -> [[String: Any]] {
        process.lines.filter { $0["method"] as? String == method }
    }

    func params(_ process: FakeClaude.Process, _ method: String) -> [String: Any] {
        requests(process, method).last?["params"] as? [String: Any] ?? [:]
    }

    /// Answers the last request with `method`, as the app server does (no "jsonrpc").
    func respond(_ process: FakeClaude.Process, _ method: String, result: [String: Any] = [:], error: [String: Any]? = nil) throws {
        let id = try #require(requests(process, method).last?["id"])
        process.say(error.map { ["id": id, "error": $0] } ?? ["id": id, "result": result])
    }

    /// `initialize` answered, then `config/read` (with the user's config's `mcpServers`).
    func initialize(_ process: FakeClaude.Process, mcpServers: [String: Any] = [:]) throws {
        try respond(process, "initialize", result: ["userAgent": "test", "codexHome": "/x", "platformFamily": "unix", "platformOs": "macos"])
        try respond(process, "config/read", result: ["config": ["model": "gpt", "mcp_servers": mcpServers], "origins": [:]])
    }

    /// The handshake: `initialize`, `config/read`, then the thread started (`thread/start` giving `id`) or resumed.
    func open(_ process: FakeClaude.Process, thread id: String = "019a-thread", named: Bool = false) throws {
        try initialize(process)
        let thread: [String: Any] = ["id": id, "name": named ? "AllInOneIME" : NSNull(), "turns": []]
        if requests(process, "thread/resume").isEmpty {
            try respond(process, "thread/start", result: ["thread": thread, "model": "gpt", "sandbox": ["type": "readOnly"]])
        } else {
            try respond(process, "thread/resume", result: ["thread": thread])
        }
    }

    func delta(_ process: FakeClaude.Process, _ text: String, item: String = "msg_1", thread: String = "019a-thread", turn: String = "turn_1") {
        process.say(["method": "item/agentMessage/delta",
                     "params": ["threadId": thread, "turnId": turn, "itemId": item, "delta": text]])
    }

    func completed(_ process: FakeClaude.Process, status: String = "completed", error: [String: Any]? = nil,
                   thread: String = "019a-thread", turn: String = "turn_1") {
        var turnObject: [String: Any] = ["id": turn, "items": [], "status": status]
        if let error { turnObject["error"] = error }
        process.say(["method": "turn/completed", "params": ["threadId": thread, "turn": turnObject]])
    }

    /// The questions sent, their text.
    func turns(_ process: FakeClaude.Process) -> [String] {
        requests(process, "turn/start").compactMap {
            (($0["params"] as? [String: Any])?["input"] as? [[String: Any]])?.first?["text"] as? String
        }
    }

    @Test func aThreadIsStartedReadOnlyNamedAndATurnStreams() async throws {
        let fake = FakeClaude()
        let session = codex(fake)
        let stream = session.ask("what is rust")
        let process = try #require(fake.last)
        #expect(process.arguments == CodexBackend(base: folder).arguments(sessionID: "x", resume: false, settings: nil)
            && process.directory == folder.appendingPathComponent("codex-session"))
        // No "jsonrpc": the app server's lines don't have it.
        #expect(process.lines.first?["jsonrpc"] == nil && process.lines.first?["method"] as? String == "initialize")
        #expect(turns(process).isEmpty)  // not before the thread is open
        try open(process)
        #expect(requests(process, "initialized").count == 1 && requests(process, "initialized").first?["id"] == nil)
        #expect(params(process, "config/read")["cwd"] as? String == folder.appendingPathComponent("codex-session").path)
        let start = params(process, "thread/start")
        #expect(start["cwd"] as? String == folder.appendingPathComponent("codex-session").path)
        #expect(start["sandbox"] as? String == "read-only" && start["approvalPolicy"] as? String == "never")
        // The instructions go with the thread (Codex reads no AGENTS.md without its environment); no MCP server: no config.
        #expect(start["developerInstructions"] as? String == ClaudeSession.instructions && start["config"] == nil)
        // Named so that the user finds it in Codex's list: `codex resume AllInOneIME`.
        #expect(params(process, "thread/name/set")["name"] as? String == "AllInOneIME")
        #expect(params(process, "thread/name/set")["threadId"] as? String == "019a-thread")
        #expect(turns(process) == ["what is rust"] && params(process, "turn/start")["threadId"] as? String == "019a-thread")
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1", "items": [], "status": "inProgress"]])
        process.say(["method": "item/started", "params": ["threadId": "019a-thread", "turnId": "turn_1",
                                                         "item": ["type": "reasoning", "id": "r1"]]])
        delta(process, "A systems")
        delta(process, " language.")
        delta(process, "ignored", thread: "another")  // another thread's
        completed(process)
        #expect(await collect(stream).answers == ["A systems", "A systems language."])
        // The thread is kept: the hand-off resumes it in Terminal.
        let store = ClaudeSessionStore(CodexBackend(base: folder))
        #expect(store.agentSessionID() == "019a-thread")
        let (arguments, directory, _) = try session.handOff(program: "/u/codex")
        #expect(arguments == ["/u/codex", "resume", "019a-thread"] && directory == store.directory)
        #expect(process.terminated)
        // The folder has the instructions as Codex reads them.
        #expect((try? String(contentsOf: store.directory.appendingPathComponent("AGENTS.md"), encoding: .utf8)) == ClaudeSession.instructions)
    }

    @Test func aRestartResumesTheKeptThreadAndAGoneOneIsStartedAgain() async throws {
        let fake = FakeClaude()
        let store = ClaudeSessionStore(CodexBackend(base: folder))
        _ = try store.sessionID()
        store.setAgentSessionID("019a-kept")
        let session = codex(fake)
        let first = session.ask("one")
        let process = try #require(fake.last)
        try initialize(process)
        #expect(params(process, "thread/resume")["threadId"] as? String == "019a-kept")
        #expect(params(process, "thread/resume")["sandbox"] as? String == "read-only")
        #expect(params(process, "thread/resume")["developerInstructions"] as? String == ClaudeSession.instructions)
        // Resumed, already named: not named again.
        try respond(process, "thread/resume", result: ["thread": ["id": "019a-kept", "name": "AllInOneIME", "turns": []]])
        #expect(requests(process, "thread/start").isEmpty && requests(process, "thread/name/set").isEmpty)
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1", "items": [], "status": "inProgress"]])
        delta(process, "1", thread: "019a-kept")
        completed(process, thread: "019a-kept")
        #expect(await collect(first).answers == ["1"])

        // The process gone, the thread too: a new one, named.
        process.exit(0)
        let second = session.ask("two")
        let restarted = try #require(fake.last)
        #expect(fake.processes.count == 2)
        try initialize(restarted)
        try respond(restarted, "thread/resume", error: ["code": -32600, "message": "no rollout found for thread id 019a-kept"])
        try respond(restarted, "thread/start", result: ["thread": ["id": "019a-new", "turns": []]])
        #expect(params(restarted, "thread/name/set")["threadId"] as? String == "019a-new")
        #expect(turns(restarted) == ["two"] && store.agentSessionID() == "019a-new")
        try respond(restarted, "turn/start", result: ["turn": ["id": "turn_2", "items": [], "status": "inProgress"]])
        delta(restarted, "2", thread: "019a-new", turn: "turn_2")
        completed(restarted, thread: "019a-new", turn: "turn_2")
        #expect(await collect(second).answers == ["2"])
    }

    @Test func escInterruptsTheTurnByItsId() async throws {
        let fake = FakeClaude()
        let session = codex(fake)
        let stream = session.ask("long")
        let process = try #require(fake.last)
        try open(process)
        // Stopped before `turn/start` answered: the interrupt goes once the turn has its id.
        session.interrupt()
        #expect(await collect(stream).error is CancellationError)
        #expect(requests(process, "turn/interrupt").isEmpty)
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1", "items": [], "status": "inProgress"]])
        #expect(params(process, "turn/interrupt")["turnId"] as? String == "turn_1")
        #expect(params(process, "turn/interrupt")["threadId"] as? String == "019a-thread")
        completed(process, status: "interrupted")
        // The process stays; the next question goes to it.
        let next = session.ask("short")
        #expect(turns(process) == ["long", "short"] && !process.terminated)
        try respond(process, "turn/start", result: ["turn": ["id": "turn_2", "items": [], "status": "inProgress"]])
        session.interrupt()
        #expect(params(process, "turn/interrupt")["turnId"] as? String == "turn_2")
        completed(process, status: "interrupted", turn: "turn_2")
        #expect(await collect(next).error is CancellationError)
    }

    @Test func whatTheServerAsksIsRefused() async throws {
        let fake = FakeClaude()
        let session = codex(fake)
        let stream = session.ask("delete my files")
        let process = try #require(fake.last)
        try open(process)
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1", "items": [], "status": "inProgress"]])
        let asked: [(String, [String: Any])] = [
            ("item/commandExecution/requestApproval", ["decision": "decline"]),
            ("item/fileChange/requestApproval", ["decision": "decline"]),
            ("applyPatchApproval", ["decision": "denied"]),
            ("execCommandApproval", ["decision": "denied"]),
        ]
        for (index, (method, _)) in asked.enumerated() {
            process.say(["id": 100 + index, "method": method, "params": ["threadId": "019a-thread", "turnId": "turn_1"]])
        }
        process.say(["id": 200, "method": "item/tool/requestUserInput", "params": [:] as [String: Any]])
        for (index, (_, answer)) in asked.enumerated() {
            let reply = process.lines.first { $0["id"] as? Int == 100 + index && $0["method"] == nil }
            #expect(reply?["result"] as? NSDictionary == answer as NSDictionary)
        }
        let other = process.lines.first { $0["id"] as? Int == 200 && $0["method"] == nil }
        #expect((other?["error"] as? [String: Any])?["code"] as? Int == -32601)
        delta(process, "I can't.")
        completed(process)
        #expect(await collect(stream).answers == ["I can't."])
    }

    @Test func aTurnThatFailsSignedOutOrAtTheLimitSaysSo() async throws {
        let fake = FakeClaude()
        let session = codex(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try open(process)
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1", "items": [], "status": "inProgress"]])
        completed(process, status: "failed", error: ["message": "401 Unauthorized", "codexErrorInfo": "unauthorized"])
        let error = await collect(stream).error as? ClaudeSessionError
        #expect(error == .signedOut && error?.fallsBack == true && session.availability == .signedOut)
        #expect(error?.description(for: .codex) == "Codex isn't signed in: run codex login in Terminal")
        let limited = session.ask("again")
        try respond(process, "turn/start", result: ["turn": ["id": "turn_2", "items": [], "status": "inProgress"]])
        completed(process, status: "failed", error: ["message": "You've hit your usage limit.", "codexErrorInfo": "usageLimitExceeded"],
                  turn: "turn_2")
        #expect(await collect(limited).error as? ClaudeSessionError == .limitReached("You've hit your usage limit."))
        #expect(ClaudeSessionError.limitReached("").description(for: .codex) == "The Codex usage limit is reached")
        #expect(ClaudeSessionError.notInstalled.description(for: .codex) == "The codex command (Codex) isn't installed")
        #expect(ClaudeSessionError.notInstalled.description(for: .antigravity) == "The agy command (Antigravity) isn't installed")
        #expect(ClaudeSessionError.signedOut.description(for: .antigravity) == "Antigravity isn't signed in: run agy in Terminal")
        // Claude Code's and Kiro CLI's words as they were.
        #expect(ClaudeSessionError.signedOut.description(for: .claude) == "Claude Code isn't signed in: run claude in Terminal and /login")
        #expect(ClaudeSessionError.signedOut.description(for: .kiro) == "Kiro CLI isn't signed in: run kiro-cli login in Terminal")
        #expect(ClaudeSessionError.noResponse.description(for: .kiro) == "The Kiro session didn't respond")
        #expect(ClaudeSessionError.notInstalled.description(for: .claude) == "The claude command (Claude Code) isn't installed")
    }

    // MARK: - Codex reads the web, nothing else

    @Test func codexStartsWithoutAnEnvironmentAppsOrOtherAgents() {
        let backend = CodexBackend(base: folder)
        // Each with -c: a setting this Codex doesn't know is left aside (--disable would stop the server).
        #expect(backend.arguments(sessionID: "x", resume: true, settings: nil) == [
            "app-server",
            "-c", "features.shell_tool=false", "-c", "features.view_image=false", "-c", "features.apps=false",
            "-c", "features.plugins=false", "-c", "features.tool_suggest=false", "-c", "features.multi_agent=false",
            "-c", "features.multi_agent_v2=false", "-c", "agents.enabled=false", "-c", "features.goals=false",
            "-c", "features.image_generation=false", "-c", "features.memories=false",
            "-c", "tools.experimental_request_user_input.enabled=false", "-c", "skills.include_instructions=false",
            "-c", "include_permissions_instructions=false", "-c", "web_search=\"live\"",
        ])
        #expect(backend.arguments(sessionID: "x", resume: false, settings: nil) == backend.arguments(sessionID: "x", resume: true, settings: nil))
        // No environment for commands and files: no shell, no apply_patch, no view_image, no MCP server on this Mac.
        #expect(backend.environment == ["CODEX_EXEC_SERVER_URL": "none"])
        // The sign-in check and Codex in Terminal (the hand-off: the user's own Codex) as they were.
        #expect(backend.availabilityArguments(settings: nil) == ["app-server"])
        #expect(backend.terminalArguments(program: "/u/codex", sessionID: "x", agentSessionID: "019a", resume: true, followUp: false)
            == ["/u/codex", "resume", "019a"])
        // A follow-up after "--": one starting with "-" is no option.
        #expect(backend.terminalArguments(program: "/u/codex", sessionID: "x", agentSessionID: "019a", resume: true)
            == ["/u/codex", "resume", "019a", "--"])
    }

    @Test func codexTurnsTheUsersMCPServersOffAndHasTheFoldersInstructions() async throws {
        let fake = FakeClaude()
        let store = ClaudeSessionStore(CodexBackend(base: folder))
        try store.prepare()
        // An AGENTS.md the user edited is what the thread is told.
        let edited = "Answer in French.\n"
        try Data(edited.utf8).write(to: store.directory.appendingPathComponent("AGENTS.md"))
        let session = codex(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try initialize(process, mcpServers: [
            "docs": ["url": "https://mcp.example.com/mcp", "bearer_token_env_var": "DOCS_TOKEN", "enabled": true,
                     "tool_timeout_sec": NSNull()],
            "files": ["command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/"], "env": ["A": "b"],
                      "enabled": true, "required": true],
        ])
        let start = params(process, "thread/start")
        #expect(start["developerInstructions"] as? String == edited)
        // Each turned off, with its url or command and nothing else (no nulls, no tokens or arguments).
        let servers = try #require((start["config"] as? [String: Any])?["mcp_servers"] as? [String: Any])
        #expect(servers.count == 2)
        #expect(servers["docs"] as? NSDictionary == ["url": "https://mcp.example.com/mcp", "enabled": false] as NSDictionary)
        #expect(servers["files"] as? NSDictionary == ["command": "npx", "enabled": false] as NSDictionary)
        try respond(process, "thread/start", result: ["thread": ["id": "019a-thread", "turns": []]])
        try respond(process, "turn/start", result: ["turn": ["id": "turn_1", "items": [], "status": "inProgress"]])
        delta(process, "Salut")
        completed(process)
        #expect(await collect(stream).answers == ["Salut"])
        // Started again, resumed: the same.
        process.exit(0)
        let next = session.ask("again")
        let restarted = try #require(fake.last)
        try initialize(restarted, mcpServers: ["docs": ["url": "https://mcp.example.com/mcp", "enabled": true]])
        let resume = params(restarted, "thread/resume")
        #expect(resume["threadId"] as? String == "019a-thread" && resume["developerInstructions"] as? String == edited)
        #expect(((resume["config"] as? [String: Any])?["mcp_servers"] as? [String: Any])?.keys.sorted() == ["docs"])
        try respond(restarted, "thread/resume", result: ["thread": ["id": "019a-thread", "name": "AllInOneIME", "turns": []]])
        try respond(restarted, "turn/start", result: ["turn": ["id": "turn_2", "items": [], "status": "inProgress"]])
        completed(restarted, turn: "turn_2")
        #expect(await collect(next).error == nil)
    }

    @Test func codexIsNotAskedWhenItsConfigCantBeRead() async throws {
        let fake = FakeClaude()
        let session = codex(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try respond(process, "initialize", result: ["userAgent": "test"])
        try respond(process, "config/read", error: ["code": -32603, "message": "failed to read config"])
        // Which MCP servers to turn off isn't known (one reached over the network would start): no thread; the provider
        // answers, saying why.
        let got = await collect(stream)
        #expect(got.error as? ClaudeSessionError == .notWebOnly && ClaudeSessionError.notWebOnly.fallsBack)
        #expect(requests(process, "thread/start").isEmpty && process.terminated)
        #expect(session.availability == .cannotStart)
    }

    // MARK: - The sign-in checks

    @Test func codexIsSignedInAsAccountReadSays() {
        let backend = CodexBackend()
        func line(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        let chatgpt: [String: Any] = ["type": "chatgpt", "email": "a@b.c", "planType": "team"]
        #expect(backend.signedIn(line: line(["id": 2, "result": ["account": chatgpt, "requiresOpenaiAuth": true]])) == true)
        #expect(backend.signedIn(line: line(["id": 2, "result": ["account": ["type": "apiKey"], "requiresOpenaiAuth": true]])) == true)
        #expect(backend.signedIn(line: line(["id": 2, "result": ["account": NSNull(), "requiresOpenaiAuth": true]])) == false)
        // A provider of the user's own needs no OpenAI sign-in.
        #expect(backend.signedIn(line: line(["id": 2, "result": ["account": NSNull(), "requiresOpenaiAuth": false]])) == true)
        #expect(backend.signedIn(line: line(["id": 2, "error": ["code": -32603, "message": "x"]])) == false)
        // Not the answer: the initialize's, a notification.
        #expect(backend.signedIn(line: line(["id": 1, "result": ["userAgent": "x"]])) == nil)
        #expect(backend.signedIn(line: line(["method": "account/updated", "params": ["authMode": "chatgpt"]])) == nil)
        let sent = backend.availabilityInput.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(sent.map { $0["method"] as? String } == ["initialize", "initialized", "account/read"])
        #expect(backend.availabilityArguments(settings: nil) == ["app-server"])
    }

    @Test func theCodexCheckReadsTheAnswerThenEndsTheServer() async throws {
        let fake = FakeClaude()
        let session = codex(fake)
        let check = Task { await session.checkAvailability() }
        #expect(await Timing.eventually { fake.last?.lines.count == 3 })
        let process = try #require(fake.last)
        #expect(process.arguments == ["app-server"] && !process.terminated)
        process.say(["id": 1, "result": ["userAgent": "x"]])
        process.say(["method": "account/updated", "params": ["authMode": "chatgpt", "planType": "team"]])
        process.say(["id": 2, "result": ["account": ["type": "chatgpt", "email": "a@b.c", "planType": "team"], "requiresOpenaiAuth": true]])
        #expect(await check.value == .ready && session.availability == .ready)
        #expect(process.terminated)
    }

    @Test func aCheckThatSaysReadyIsKeptForTheLaunch() async throws {
        let fake = FakeClaude()
        let session = ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder), userSettings: { nil })
        let check = Task { await session.checkAvailability() }
        #expect(await Timing.eventually { fake.last != nil })
        let process = try #require(fake.last)
        #expect(process.arguments == ["--setting-sources", "project", "auth", "status", "--json"])
        process.say(["loggedIn": true, "authMethod": "claude.ai"])
        process.exit(0)
        #expect(await check.value == .ready)
        #expect(await session.checkAvailability() == .ready && fake.processes.count == 1)
        // Asked to look again (Settings): looked at again.
        let again = Task { await session.checkAvailability(force: true) }
        #expect(await Timing.eventually { fake.processes.count == 2 })
        fake.last?.say(["loggedIn": false])
        fake.last?.exit(1)
        #expect(await again.value == .signedOut)
    }

    @Test func aCheckThatFailedIsLookedAtAgainAMinuteLater() async throws {
        let fake = FakeClaude()
        let now = Locked(initialState: 1000.0)
        let session = ClaudeSessionManager(backend: ACPBackend.kiro, launcher: fake, store: ClaudeSessionStore(directory: folder),
                                           uptime: { now.withLock { $0 } })
        let check = Task { await session.checkAvailability() }
        #expect(await Timing.eventually { fake.last != nil })
        #expect(fake.last?.arguments == ["whoami", "-f", "json"])
        fake.last?.exit(1)
        #expect(await check.value == .signedOut)
        // Not again within the minute: the result stands.
        now.withLock { $0 += 30 }
        #expect(await session.checkAvailability() == .signedOut && fake.processes.count == 1)
        now.withLock { $0 += 31 }
        let later = Task { await session.checkAvailability() }
        #expect(await Timing.eventually { fake.processes.count == 2 })
        fake.last?.exit(0)
        #expect(await later.value == .ready)
        // A question that fails signed out: looked at again a minute after.
        session.availability = .signedOut
        #expect(await session.checkAvailability() == .signedOut && fake.processes.count == 2)
        now.withLock { $0 += 61 }
        let after = Task { await session.checkAvailability() }
        #expect(await Timing.eventually { fake.processes.count == 3 })
        fake.last?.exit(0)
        #expect(await after.value == .ready)
        // No program: not installed, nothing started.
        let missing = FakeClaude()
        missing.missing = true
        let none = ClaudeSessionManager(backend: ACPBackend.kiro, launcher: missing,
                                        store: ClaudeSessionStore(directory: folder.appendingPathComponent("n")))
        #expect(await none.checkAvailability() == .notInstalled && missing.processes.isEmpty)
    }

    @Test func aCheckWithNoAnswerInTimeSaysSignedOut() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = codex(fake, answerClock: clock)
        let check = Task { await session.checkAvailability() }
        #expect(await clock.sleepers(1))
        let process = try #require(fake.last)
        clock.advance(by: ClaudeSessionManager.checkTimeout)
        #expect(await check.value == .signedOut && process.terminated)
    }

    /// A launcher with no program.
    struct Missing: ClaudeSessionLauncher {
        func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                   exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
            throw ClaudeSessionError.notInstalled
        }
        func installed() -> Bool { false }
    }

    // MARK: - Which sessions are looked at, and when

    /// A session whose sign-in check counts its runs and says `ready`.
    final class Counted: @unchecked Sendable {
        let count = Locked(initialState: 0)
        var runs: Int { count.withLock { $0 } }
    }

    func local(_ agent: SessionAgent, ready: Bool, _ counted: Counted, launcher: FakeClaude = FakeClaude(),
               uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> ClaudeSessionManager {
        let backend = ACPBackend(agent: agent, folderName: "\(agent.rawValue)-session", launch: ["acp"], availability: [],
                                 resume: [], start: [], base: folder, signIn: { _, _ in
                                     counted.count.withLock { $0 += 1 }
                                     return ready
                                 })
        return ClaudeSessionManager(backend: backend, launcher: launcher, uptime: uptime)
    }

    /// Since 0.7.4 there is no Automatic to look at sign-ins for: the CLI chosen as the AI is tried as it is, and with a
    /// provider chosen no session is; nothing is looked at either way (Settings → AI looks, as it shows the choices).
    @Test func aQuestionLooksAtNoSignIn() {
        let (claudeRuns, codexRuns, kiroRuns) = (Counted(), Counted(), Counted())
        let sessions: [SessionAgent: ClaudeSessionManager] = [
            .claude: local(.claude, ready: true, claudeRuns), .codex: local(.codex, ready: true, codexRuns),
            .kiro: local(.kiro, ready: false, kiroRuns),
        ]
        var config = Config.default
        config.agent = .claude
        let converter = Converter(questionSessions: sessions)
        #expect(converter.questionSession(config) == nil)
        config.questionBackend = .kiroSession
        #expect(converter.questionSession(config) === sessions[.kiro])
        #expect((claudeRuns.runs, codexRuns.runs, kiroRuns.runs) == (0, 0, 0))
    }

    // MARK: - Started ahead only for a question about to be asked

    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.english])
            config.provider = .apple
            config.agent = .kiro
            config.questionBackend = .kiroSession  // chosen as the AI (no Automatic since 0.7.4)
        }
    }

    func host(_ settings: Settings, session: ClaudeSessionManager, secure: Bool = false) -> FakeHost {
        let converter = Converter(loadConfig: { settings.config }, appleModel: StubAppleModel(answer: ["x"]),
                                  questionSessions: [.kiro: session])
        var services = SessionServices(converter: converter, loadSettings: { settings.config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.secureInputActive = { secure }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    func settled(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        return condition()
    }

    @Test func onlyAQuestionAboutToBeAskedStartsTheSession() async {
        await withInterfaceLanguage("en") {
            let settings = Settings()
            let (fake, runs) = (FakeClaude(), Counted())
            let session = local(.kiro, ready: true, runs, launcher: fake)
            let host = host(settings, session: session)
            // The magic key alone, another row highlighted: nothing looked at, nothing started.
            host.press(FakeHost.at)
            host.type("hello")
            #expect(host.composer.oneAtRows.first == .write(.improve))
            Thread.sleep(forTimeInterval: 0.1)
            #expect(runs.runs == 0 && fake.processes.isEmpty)
            // A question typed: Ask AI highlighted, the session chosen started, once (its sign-in not looked at: since 0.7.4
            // the CLI chosen is tried as it is).
            host.press(FakeHost.escape)
            host.press(FakeHost.at)
            host.type("what is rust?")
            #expect(host.composer.oneAtRows.first == .write(.question), "\(host.composer.oneAtRows.map(\.id))")
            #expect(settled { fake.processes.count == 1 } && runs.runs == 0)
            #expect(fake.last?.arguments == ["acp"])
            // The panel takes in where questions go now.
            #expect(host.settle(timeout: 5) { host.composer.questionSession && host.composer.questionSessionAgent == .kiro })
            host.type(" x")
            Thread.sleep(forTimeInterval: 0.1)
            #expect(fake.processes.count == 1 && runs.runs == 0)

            // @question typed out, in another field: started (it runs already: nothing more).
            session.stop()
            let typed = self.host(settings, session: session)
            typed.press(FakeHost.at)
            typed.type("question")
            typed.press(FakeHost.tab)
            #expect(typed.composer.draftCommand == .question)
            #expect(settled { fake.processes.count == 2 })
        }
    }

    /// The session ready already: the magic key, and a row that isn't the question's, still start nothing; ↓ to Ask AI
    /// does.
    @Test func theAskAIRowHighlightedStartsTheSession() async {
        await withInterfaceLanguage("en") {
            let (fake, runs) = (FakeClaude(), Counted())
            let session = local(.kiro, ready: true, runs, launcher: fake)
            session.availability = .ready
            let host = host(Settings(), session: session)
            host.press(FakeHost.at)
            Thread.sleep(forTimeInterval: 0.1)
            #expect(fake.processes.isEmpty, "the magic key alone")
            host.type("hello")
            Thread.sleep(forTimeInterval: 0.1)
            #expect(fake.processes.isEmpty, "Improve highlighted")
            let ask = host.composer.oneAtRows.firstIndex(of: .write(.question))
            #expect(ask != nil, "\(host.composer.oneAtRows.map(\.id))")
            while let ask, host.composer.oneAtHighlighted < ask { host.press(FakeHost.down) }
            #expect(host.settle(timeout: 5) { fake.processes.count == 1 })
            #expect(runs.runs == 0)  // ready already: not looked at again
        }
    }

    @Test func noSessionStartsWithTheProviderPickedNoAIOrSecureInput() async {
        await withInterfaceLanguage("en") {
            let provider = Settings()
            provider.config.questionBackend = nil
            let noAI = Settings()
            noAI.config.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            for (settings, secure) in [(provider, false), (noAI, false), (Settings(), true)] {
                let (fake, runs) = (FakeClaude(), Counted())
                let host = host(settings, session: local(.kiro, ready: true, runs, launcher: fake), secure: secure)
                host.press(FakeHost.at)
                host.type("question")
                host.press(FakeHost.tab)
                host.type("what is rust")
                Thread.sleep(forTimeInterval: 0.15)
                #expect(runs.runs == 0 && fake.processes.isEmpty, "provider \(settings.config.questionBackend == nil), secure \(secure)")
            }
        }
    }

    // MARK: - The names

    @Test func eachSessionHasItsNameAndPanelWords() {
        #expect(SessionAgent.sessionName == "AllInOneIME")
        #expect(SessionAgent.allCases.map(\.displayName) == ["Claude Code", "Codex", "Antigravity", "Kiro CLI"])
        #expect(SessionAgent.allCases.map(\.program) == ["claude", "codex", "agy", "kiro-cli"])
        // Gemini CLI is an @agent agent without a session; Codex and Antigravity have sessions and are no @agent agents.
        #expect(SessionAgent(.custom) == nil && SessionAgent(.gemini) == nil && SessionAgent(.kiro) == .kiro)
        #expect(SessionAgent.codex.agentKind == nil && SessionAgent.antigravity.agentKind == nil)
        // Codex is no @agent agent: nothing of the list is left out for it.
        #expect(ChatHandoff.withSession([.claudeCode, .geminiCLI, .copy], agent: .codex) == [.claudeSession, .claudeCode, .geminiCLI, .copy])
        #expect(ChatHandoff.withSession([.claudeCode, .geminiCLI, .copy], agent: .antigravity)
            == [.claudeSession, .claudeCode, .geminiCLI, .copy])
        #expect(ChatHandoff.withSession([.claudeCode, .kiroCLI, .copy], agent: .kiro) == [.claudeSession, .claudeCode, .copy])
        #expect(SessionText.shortName(.claudeSession, session: .codex, language: "en") == "Codex (this session)")
        #expect(SessionText.name(.claudeSession, session: .antigravity, language: "en") == "Continue in Antigravity (the same session)")
        #expect(Composer.ChatMessages.english.opened(.antigravity) == "Opened the input method's Antigravity session in Terminal")
        #expect(Composer.ChatMessages.english.opened(.codex) == "Opened the input method's Codex session in Terminal")
        #expect(Composer.ChatMessages.english.opened(.claude) == "Opened the input method's Claude session in Terminal")
        #expect(Composer.ChatMessages.chinese.opened(.kiro) == "已在终端打开输入法的 Kiro 会话")
    }
}
