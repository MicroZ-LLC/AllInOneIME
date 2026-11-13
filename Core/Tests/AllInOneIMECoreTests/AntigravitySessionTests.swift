import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// The question session on Google Antigravity's CLI (`AntigravityBackend`, `agy acp`), which took Gemini CLI's place: the
/// handshake with the fast model set before the first prompt, a prompt streamed, what agy asks refused, a tool other
/// than the web search ending the process, the conversation loaded after a restart, signed out; the hook that keeps it
/// to the web (run here as agy runs it), its sign-in read without running it, the hand-off, and a config that chose
/// Gemini CLI's session moved. The fake agent (`FakeClaude`'s processes) answers as `agy acp` 1.5.8 does.
@Suite(.serialized)
struct AntigravitySessionTests {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("antigravity-\(UUID().uuidString)")
    var backend: AntigravityBackend { AntigravityBackend(base: base, signIn: { _, _ in true }) }
    var folder: URL { backend.directory }
    var store: ClaudeSessionStore { ClaudeSessionStore(backend) }

    @Test func prepareRepairsEveryPermissionFile() throws {
        try store.prepare()
        for file in backend.files {
            let url = folder.appendingPathComponent(file.path)
            try Data("name: \(file.path)\ntools: [shell]\n".utf8).write(to: url, options: .atomic)
        }
        try store.prepare()
        for file in backend.files {
            #expect(try Data(contentsOf: folder.appendingPathComponent(file.path)) == Data(file.content.utf8))
        }
    }

    @Test func changedAgentToolsAreRejectedBeforeAnyPrompt() throws {
        try store.prepare()
        let driver = backend.driver(sessionID: "x", agentSessionID: nil, resume: false, directory: folder, web: .open)
        try Data("name: allinoneime\ntools: [shell]\n".utf8)
            .write(to: folder.appendingPathComponent(".agents/agents/allinoneime.md"), options: .atomic)
        #expect(driver.received(Data("{}".utf8)).events == [.failed(.notWebOnly, endsProcess: true)])
    }

    func manager(_ fake: FakeClaude) -> ClaudeSessionManager { ClaudeSessionManager(backend: backend, launcher: fake) }

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

    func requests(_ process: FakeClaude.Process, _ method: String) -> [[String: Any]] {
        process.lines.filter { $0["method"] as? String == method }
    }

    func params(_ process: FakeClaude.Process, _ method: String) -> [String: Any] {
        requests(process, method).last?["params"] as? [String: Any] ?? [:]
    }

    func respond(_ process: FakeClaude.Process, _ method: String, result: [String: Any] = [:], error: [String: Any]? = nil) throws {
        let id = try #require(requests(process, method).last?["id"])
        var line: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let error { line["error"] = error } else { line["result"] = result }
        process.say(line)
    }

    /// agy's models, as `session/new` lists them (its default first).
    static var models: [String: Any] { ["currentModelId": "gemini-4-argon-medium", "availableModels": [
        ["modelId": "gemini-4-argon-medium"], ["modelId": "gemini-3.8-flash-high"], ["modelId": "gemini-3.8-flash-low"],
    ]] }

    func initialize(_ process: FakeClaude.Process) throws {
        try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": true],
                                                    "agentInfo": ["name": "Antigravity ACP Server", "version": "1.5.8"]])
    }

    /// The handshake as agy answers it: `initialize`, `session/new` giving `id` (or the `session/load` asked for), then
    /// `session/set_model`.
    func open(_ process: FakeClaude.Process, id: String = "d50c263c-uuid") throws {
        try initialize(process)
        if requests(process, "session/load").isEmpty {
            try respond(process, "session/new", result: ["sessionId": id, "models": Self.models,
                                                         "modes": ["currentModeId": "default"]])
        } else {
            try respond(process, "session/load", result: ["models": Self.models])
        }
        try respond(process, "session/set_model")
    }

    func update(_ process: FakeClaude.Process, _ update: [String: Any], session: String = "d50c263c-uuid") {
        process.say(["jsonrpc": "2.0", "method": "session/update", "params": ["sessionId": session, "update": update]])
    }

    func chunk(_ process: FakeClaude.Process, _ text: String, session: String = "d50c263c-uuid") {
        update(process, ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": text]], session: session)
    }

    func tool(_ process: FakeClaude.Process, _ name: String, status: String, kind: String = "other") {
        update(process, ["sessionUpdate": "tool_call_update", "toolCallId": "call_1", "name": name, "status": status,
                         "kind": kind, "title": name])
    }

    func prompts(_ process: FakeClaude.Process) -> [String] {
        requests(process, "session/prompt").compactMap {
            (($0["params"] as? [String: Any])?["prompt"] as? [[String: Any]])?.first?["text"] as? String
        }
    }

    // MARK: - The handshake, the model, a prompt

    @Test func aConversationIsOpenedOnItsAgentWithTheFastModelAndAPromptStreams() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("what is rust")
        let process = try #require(fake.last)
        #expect(process.arguments == ["acp", "--agent", "allinoneime", "--disable-telemetry"] && process.directory == folder)
        #expect(backend.environment == ["ALLINONEIME_SESSION": "antigravity"])
        try initialize(process)
        let new = params(process, "session/new")
        #expect(new["cwd"] as? String == folder.path && (new["mcpServers"] as? [Any])?.isEmpty == true)
        try respond(process, "session/new", result: ["sessionId": "d50c263c-uuid", "models": Self.models])
        // The model first: no prompt until agy has answered it.
        let model = params(process, "session/set_model")
        #expect(model["sessionId"] as? String == "d50c263c-uuid" && model["modelId"] as? String == "gemini-3.8-flash-low")
        #expect(prompts(process).isEmpty)
        try respond(process, "session/set_model")
        #expect(prompts(process) == ["what is rust"])
        update(process, ["sessionUpdate": "agent_thought_chunk", "content": ["type": "text", "text": "Thinking"]])
        update(process, ["sessionUpdate": "tool_call", "toolCallId": "c1", "name": "search_web", "status": "in_progress", "kind": "search"])
        tool(process, "search_web", status: "completed", kind: "search")
        chunk(process, "A systems")
        chunk(process, " language.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn", "usage": ["totalTokens": 8501]])
        let got = await collect(stream)
        #expect(got.answers.last == "A systems language." && got.error == nil)
        #expect(store.agentSessionID() == "d50c263c-uuid" && session.availability == .ready && !process.terminated)
        // The next question: a prompt, no model asked again.
        let next = session.ask("and go?")
        #expect(prompts(process) == ["what is rust", "and go?"] && requests(process, "session/set_model").count == 1)
        chunk(process, "Also one.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(next).answers == ["Also one."])

        // The folder: the agents (web search alone; none), the hook before every tool, the gate it runs.
        let agent = try String(contentsOf: folder.appendingPathComponent(".agents/agents/allinoneime.md"), encoding: .utf8)
        #expect(agent.contains("tools:\n  - search_web\n") && agent.contains("mcpServers: []") && agent.contains(ClaudeSession.instructions))
        let offline = try String(contentsOf: folder.appendingPathComponent(".agents/agents/allinoneime-offline.md"), encoding: .utf8)
        #expect(offline.contains("tools: []") && !offline.contains("search_web"))
        let hooks = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(".agents/hooks.json"))) as? [String: Any])
        let preToolUse = ((hooks["allinoneime-web-only"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.first
        #expect(preToolUse?["matcher"] as? String == "*")
        // The gate by its full path, whichever folder agy runs the hook in.
        #expect(((preToolUse?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
            == "/bin/sh '\(folder.path)/.agents/allinoneime-web-only.sh'")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".agents/allinoneime-web-only.sh").path))
    }

    @Test func theFastModelIsTheOneOfferedOrNone() {
        func models(_ ids: [String]) -> [String: Any] { ["models": ["availableModels": ids.map { ["modelId": $0] }]] }
        let pick = { AntigravityDriver.model("gemini-3.8-flash-low", in: $0) }
        #expect(pick(models(["gemini-4-argon-medium", "gemini-3.8-flash-low"])) == "gemini-3.8-flash-low")
        // Not offered: the first flash at low, else none (agy's default stays).
        #expect(pick(models(["gemini-4-argon-medium", "gemini-3.9-flash-high", "gemini-3.9-flash-low"])) == "gemini-3.9-flash-low")
        #expect(pick(models(["gemini-4-argon-medium", "claude-sonnet-5-5-low"])) == nil)
        // No list said: asked for (one agy refuses changes nothing).
        #expect(pick([:]) == "gemini-3.8-flash-low")
    }

    @Test func noFastModelOfferedThePromptGoesAtOnceAndARefusedModelChangesNothing() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try initialize(process)
        try respond(process, "session/new", result: ["sessionId": "s1", "models": ["availableModels": [["modelId": "gemini-4-argon-medium"]]]])
        #expect(requests(process, "session/set_model").isEmpty && prompts(process) == ["hi"])
        chunk(process, "Hello", session: "s1")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(stream).answers == ["Hello"])

        // A new conversation in the same process (`newConversation`): the model asked again; refused, the prompt goes.
        let fake2 = FakeClaude()
        let other = manager(fake2)
        let second = other.ask("again")
        let process2 = try #require(fake2.last)
        try initialize(process2)
        try respond(process2, "session/load", result: ["models": Self.models])  // the id kept by the first
        #expect(prompts(process2).isEmpty)
        try respond(process2, "session/set_model", error: ["code": -32602, "message": "unknown model"])
        #expect(prompts(process2) == ["again"])
        chunk(process2, "Yes", session: "s1")
        try respond(process2, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(second).answers == ["Yes"])
    }

    // MARK: - Web only

    @Test func whatAgyAsksIsRefusedAndAToolOtherThanTheWebEndsTheProcess() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("run date")
        let process = try #require(fake.last)
        try open(process)
        // A permission (the shell, a file outside the folder): refused, as agy's own options would ("cancelled").
        process.say(["jsonrpc": "2.0", "id": 7, "method": "session/request_permission",
                     "params": ["sessionId": "d50c263c-uuid",
                                "toolCall": ["toolCallId": "c1", "name": "run_command", "kind": "execute", "title": "date"],
                                "options": [["optionId": "allow", "kind": "allow_once"], ["optionId": "deny", "kind": "reject_once"]]]])
        let denied = try #require(process.lines.last)
        #expect(denied["id"] as? Int == 7)
        #expect(((denied["result"] as? [String: Any])?["outcome"] as? [String: Any])?["outcome"] as? String == "cancelled")
        // Denied by the hook: it failed; the model says so.
        tool(process, "run_command", status: "failed", kind: "execute")
        chunk(process, "I can't run commands here.")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(stream).answers.last == "I can't run commands here." && !process.terminated)

        // A tool other than the web search that completed (the hook wasn't there): the process ends, the provider answers.
        let next = session.ask("read /etc/hosts")
        tool(process, "read_file", status: "completed", kind: "read")
        let error = await collect(next).error as? ClaudeSessionError
        #expect(error == .notWebOnly && error?.fallsBack == true && process.terminated)
    }

    @Test func withItsWebOffItRunsTheAgentWithoutToolsAndEvenTheSearchEndsIt() async throws {
        try store.prepare()
        let typed = SessionWeb.only([])
        #expect(backend.effective(typed) == .only([]))
        #expect(backend.arguments(sessionID: "x", resume: false, settings: nil, web: typed)
            == ["acp", "--agent", "allinoneime-offline", "--disable-telemetry"])
        let driver = backend.driver(sessionID: "x", agentSessionID: "s1", resume: true, directory: folder, web: typed)
        let line = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "session/update", "params": [
            "sessionId": "s1", "update": ["sessionUpdate": "tool_call_update", "name": "search_web", "status": "completed"]]])
        let events = driver.received(line).events
        #expect(events == [.failed(.notWebOnly, endsProcess: true)])
        let open = backend.driver(sessionID: "x", agentSessionID: "s1", resume: true, directory: folder, web: .open)
        #expect(open.received(line).events != [.failed(.notWebOnly, endsProcess: true)])
    }

    /// The hook's gate, run as agy runs it (`/bin/sh`, the tool's call on stdin): in the session's process only the web
    /// search, whatever an argument says; in Terminal nothing decided ("allow": agy's own rules, never "ask").
    @Test func theGateAllowsTheWebSearchOnlyInTheSessionsProcess() throws {
        let script = base.appendingPathComponent("gate.sh")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data(AntigravityBackend.gate.utf8).write(to: script)
        func decision(_ call: String, session: Bool = true) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path]
            var environment = ProcessInfo.processInfo.environment
            environment["ALLINONEIME_SESSION"] = session ? "antigravity" : nil
            process.environment = environment
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            input.fileHandleForWriting.write(Data(call.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return object?["decision"] as? String ?? ""
        }
        func call(_ name: String, args: String = "{}") -> String {
            #"{"conversationId":"c","toolCall":{"args":\#(args),"id":"t1","name":"\#(name)"},"hookEventName":"PreToolUse"}"#
        }
        #expect(try decision(call("search_web", args: #"{"query":"swift"}"#)) == "allow")
        for name in ["run_command", "read_file", "write_file", "edit_file", "invoke_subagent", "define_subagent", "schedule",
                     "swarm", "manage_task", "send_message", "ask_question", "mcp_github_create_issue"] {
            #expect(try decision(call(name)) == "deny", "\(name)")
        }
        // The name is read as JSON: an argument named so doesn't let a command through.
        #expect(try decision(call("run_command", args: #"{"name":"search_web","CommandLine":"\"name\":\"search_web\""}"#)) == "deny")
        #expect(try decision("not json") == "deny")
        // Terminal (agy as the user set it up): agy's own rules.
        #expect(try decision(call("run_command"), session: false) == "allow")
        #expect(try decision(call("search_web"), session: false) == "allow")
    }

    /// hooks.json runs the gate by its full path, quoted for the shell (here a folder with a space and a quote in its
    /// path), so that it is found whichever folder agy runs it in; a folder still holding the earlier hooks.json (the
    /// gate by a path relative to .agents) gets the new one.
    @Test func theHookRunsTheGateByItsFullPathFromAnyFolder() throws {
        let backend = AntigravityBackend(base: base.appendingPathComponent("Application Support/it's here"),
                                         signIn: { _, _ in true })
        let hooks = backend.directory.appendingPathComponent(".agents/hooks.json")
        try FileManager.default.createDirectory(at: hooks.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(try #require(AntigravityBackend.earlierHooks.first).utf8).write(to: hooks)
        try ClaudeSessionStore(backend).prepare()
        #expect(try String(contentsOf: hooks, encoding: .utf8) == AntigravityBackend.hooks(in: backend.directory))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as? [String: Any])
        let group = try #require(((object["allinoneime-web-only"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.first)
        let command = try #require((group["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        #expect(command.hasPrefix("/bin/sh '/") && command.contains(backend.directory.path.replacingOccurrences(of: "'", with: #"'\''"#)))
        func decision(in directory: URL) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = directory
            process.environment = ["PATH": "/usr/bin:/bin", "ALLINONEIME_SESSION": "antigravity"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            input.fileHandleForWriting.write(Data(#"{"toolCall":{"name":"run_command","args":{"CommandLine":"date"}}}"#.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["decision"] as? String ?? ""
        }
        for directory in [URL(fileURLWithPath: "/"), backend.directory, backend.directory.appendingPathComponent(".agents")] {
            #expect(try decision(in: directory) == "deny", "run in \(directory.path)")
        }
    }

    /// A folder whose gate is an earlier one, or was changed, gets the trusted gate back.
    @Test func anEarlierOrChangedGateIsReplaced() throws {
        let gate = folder.appendingPathComponent(".agents/allinoneime-web-only.sh")
        try FileManager.default.createDirectory(at: gate.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(try #require(AntigravityBackend.earlierGates.first).utf8).write(to: gate)
        #expect(AntigravityBackend.earlierGates.allSatisfy { $0.contains(#"echo '{"decision":"ask"}'"#) })
        try store.prepare()
        #expect(try String(contentsOf: gate, encoding: .utf8) == AntigravityBackend.gate)
        try Data("#!/bin/sh\necho '{\"decision\":\"ask\"}'\n".utf8).write(to: gate)
        try store.prepare()
        #expect(try String(contentsOf: gate, encoding: .utf8) == AntigravityBackend.gate)
    }

    // MARK: - After a restart, signed out

    @Test func aRestartLoadsTheConversationAndAsksForTheModelAgain() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let first = session.ask("my favourite colour is teal")
        let process = try #require(fake.last)
        try open(process)
        chunk(process, "OK")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        _ = await collect(first)
        session.stop()

        let restarted = manager(fake)
        let next = restarted.ask("what is my favourite colour?")
        let second = try #require(fake.last)
        #expect(fake.processes.count == 2 && second !== process)
        try initialize(second)
        let load = params(second, "session/load")
        #expect(load["sessionId"] as? String == "d50c263c-uuid" && load["cwd"] as? String == folder.path)
        #expect(requests(second, "session/new").isEmpty)
        // The conversation replayed first (its tools too): none of it is an answer, nothing ends.
        update(second, ["sessionUpdate": "user_message_chunk", "content": ["type": "text", "text": "my favourite colour is teal"]])
        tool(second, "read_file", status: "completed")
        chunk(second, "OK")
        try respond(second, "session/load", result: ["models": Self.models])
        #expect(params(second, "session/set_model")["modelId"] as? String == "gemini-3.8-flash-low" && prompts(second).isEmpty)
        try respond(second, "session/set_model")
        #expect(prompts(second) == ["what is my favourite colour?"])
        chunk(second, "Teal.")
        try respond(second, "session/prompt", result: ["stopReason": "end_turn"])
        #expect(await collect(next).answers == ["Teal."] && !second.terminated)
    }

    @Test func signedOutFailsSoTheProviderAnswers() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try initialize(process)
        // As agy says it with no sign-in (checked with an empty HOME).
        try respond(process, "session/new", error: ["code": -32000, "message": "Authentication required"])
        let error = await collect(stream).error as? ClaudeSessionError
        #expect(error == .signedOut && error?.fallsBack == true && session.availability == .signedOut && process.terminated)
        #expect(requests(process, "session/set_model").isEmpty)
        #expect(error?.description(for: .antigravity) == "Antigravity isn't signed in: run agy in Terminal")
    }

    @Test func itsSignInIsReadWithoutRunningIt() async throws {
        let home = base.appendingPathComponent("home", isDirectory: true)
        let settings = home.appendingPathComponent(".gemini/antigravity-cli/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        func signedIn(_ environment: [String: String] = [:], keychain: Bool) -> Bool {
            AntigravityBackend.signedIn(environment: environment, home: home, keychain: { keychain })
        }
        // Its Google sign-in: the keychain's.
        #expect(signedIn(keychain: true) && !signedIn(keychain: false))
        try Data(#"{"trustedWorkspaces": ["/Users/x"]}"#.utf8).write(to: settings)
        #expect(!signedIn(keychain: false))
        // A Gemini API key it is set to use, with the key in the environment.
        try Data(#"{"modelProvider": "gemini"}"#.utf8).write(to: settings)
        #expect(signedIn(["GEMINI_API_KEY": "k"], keychain: false) && !signedIn(["GEMINI_API_KEY": ""], keychain: true))
        // A Google Cloud project.
        try Data(#"{"gcp": {"project": "p"}}"#.utf8).write(to: settings)
        #expect(signedIn(keychain: false))
        // The check runs nothing; no program: not installed.
        let fake = FakeClaude()
        let out = ClaudeSessionManager(backend: AntigravityBackend(base: base, signIn: { _, _ in false }), launcher: fake)
        #expect(await out.checkAvailability() == .signedOut && fake.processes.isEmpty)
        #expect(await manager(fake).checkAvailability() == .ready && fake.processes.isEmpty)
        let missing = ClaudeSessionManager(backend: backend, launcher: QuestionSessionBackendsTests.Missing())
        #expect(await missing.checkAvailability() == .notInstalled)
    }

    // MARK: - Terminal, the names, the config

    @Test func handingOffResumesTheConversationInTerminal() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        try open(process)
        chunk(process, "Hello")
        try respond(process, "session/prompt", result: ["stopReason": "end_turn"])
        _ = await collect(stream)
        // `agy --conversation <the ACP session's id>` in the folder (checked: it resumes it); a follow-up as -i's value.
        let (arguments, directory, _) = try session.handOff(program: "/u/agy")
        #expect(arguments == ["/u/agy", "--conversation", "d50c263c-uuid"] && directory == folder && process.terminated)
        #expect(backend.terminalArguments(program: "/u/agy", sessionID: "x", agentSessionID: "c1", resume: true)
            == ["/u/agy", "--conversation", "c1", "-i"])
        #expect(backend.terminalArguments(program: "/u/agy", sessionID: "x", agentSessionID: nil, resume: false, followUp: false)
            == ["/u/agy"])
    }

    @Test func itIsAChoiceOfItsOwnAndGeminiCLIIsNone() {
        #expect(SessionAgent.antigravity.displayName == "Antigravity" && SessionAgent.antigravity.program == "agy")
        #expect(SessionAgent.antigravity.signIn == "agy" && SessionAgent.antigravity.agentKind == nil)
        #expect(QuestionBackend(.antigravity) == .antigravitySession && QuestionBackend.antigravitySession.agent == .antigravity)
        #expect(AIChoice.all.compactMap(\.agent) == [.claude, .codex, .antigravity, .kiro])
        #expect(AIChoice(id: "antigravitySession") == .cli(.antigravity))
        #expect(backend.directory.lastPathComponent == "antigravity-session" && !backend.usesProviderSettings)
        #expect(SessionAgent.antigravity.environmentVariables.contains("GEMINI_API_KEY"))
        // @agent keeps Gemini CLI.
        #expect(AgentKind.gemini.displayName() == "Gemini CLI" && AgentKind.gemini.terminalArguments() == ["gemini", "-i"])
    }

    @Test func aConfigThatChoseGeminiCLIsSessionMovesWithNothingLost() throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("config.json")
        let file = #"""
            {
              "provider" : "anthropic",
              "anthropic" : {"model" : "claude-sonnet-5-5"},
              "questionBackend" : "geminiSession",
              "aLaterKey" : [1, 2]
            }
            """#
        func object() throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        // agy installed: Antigravity's session, every other key as it was.
        try Data(file.utf8).write(to: url)
        #expect(try Config.load(from: url).ai == .cli(.antigravity))
        #expect(try Config.migrateGeminiCLISession(at: url, antigravityInstalled: { true }))
        var moved = try object()
        #expect(moved["questionBackend"] as? String == "antigravitySession" && moved["provider"] as? String == "anthropic")
        #expect(moved["aLaterKey"] as? [Int] == [1, 2] && (moved["anthropic"] as? [String: Any])?["model"] as? String == "claude-sonnet-5-5")
        // Once: nothing to move after.
        #expect(try !Config.migrateGeminiCLISession(at: url, antigravityInstalled: { false }))
        #expect(try object()["questionBackend"] as? String == "antigravitySession")

        // No agy: the provider is the AI, its settings kept.
        try Data(file.utf8).write(to: url)
        #expect(try Config.migrateGeminiCLISession(at: url, antigravityInstalled: { false }))
        moved = try object()
        #expect(moved["questionBackend"] == nil && moved["provider"] as? String == "anthropic" && moved["aLaterKey"] as? [Int] == [1, 2])
        #expect(try Config.load(from: url).ai == .provider(.anthropic))
        // Another CLI chosen, or no file: nothing.
        try Data(#"{"questionBackend": "kiroSession"}"#.utf8).write(to: url)
        #expect(try !Config.migrateGeminiCLISession(at: url, antigravityInstalled: { false }))
        #expect(try !Config.migrateGeminiCLISession(at: base.appendingPathComponent("none.json"), antigravityInstalled: { true }))
    }
}
