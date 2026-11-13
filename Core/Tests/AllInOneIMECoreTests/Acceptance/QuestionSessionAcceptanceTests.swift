// The fakes are Python scripts run through Foundation's Process: the Mac's (and the input method's sessions are the Mac's).
#if os(macOS)
import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for 0.7.4's `@question` session (written from the spec, not from the implementation):
// 1. One long-running agent session owned by the input method; `questionBackend` auto / provider / Claude Code / Codex /
//    Gemini CLI / Kiro CLI; Automatic picks @agent's agent when signed in, else the first signed-in of Claude Code, Codex,
//    Gemini CLI, Kiro CLI, else the provider; a chosen CLI that can't start or isn't signed in falls back with why.
// 2. Sign-in is checked lazily, never at launch nor with the provider picked; ready is kept, anything else looked at
//    again in the background at most once a minute; Settings forces a look.
// 3. The process starts only for an @question row typed, picked or highlighted; never for the magic key alone, in an app
//    with No AI, or during secure input.
// 4. The session is named AllInOneIME (Claude's --name and fixed id, Codex's thread name; Gemini's and Kiro's folder).
// 5. Every backend may read the web only.
// 6. Esc interrupts the answer; what the agent asks is always denied.
//
// The agents are fake CLIs: small Python scripts named claude, codex, gemini and kiro-cli in a folder of the test's,
// started through the real launcher (`ProcessClaudeSessionLauncher` over `FoundationProcessLauncher`), which log their
// arguments, folder, environment and every line they read.

/// Fake `claude`, `codex`, `gemini` and `kiro-cli`, each a real program speaking its agent's protocol.
final class FakeAgentCLIs: @unchecked Sendable {
    let root: URL
    let bin: URL
    let logs: URL
    /// The fake user's home: GEMINI_CLI_HOME and CODEX_HOME point into it.
    let home: URL
    private let settings = Locked<[String: String]>(initialState: [:])
    private let removed = Locked<Set<String>>(initialState: [])

    static let programs = ["claude", "codex", "gemini", "kiro-cli"]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aio-accept-\(UUID().uuidString)", isDirectory: true)
        bin = root.appendingPathComponent("bin", isDirectory: true)
        logs = root.appendingPathComponent("logs", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        for folder in [bin, logs, home] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for program in Self.programs {
            let url = bin.appendingPathComponent(program)
            try Data(Self.script.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    /// A behavior of the fakes: FAKE_SIGNED_OUT, FAKE_HANG (an answer that stops after "Partial" until interrupted),
    /// FAKE_IGNORE_INTERRUPT, FAKE_PERMISSION, FAKE_FAIL_START, FAKE_AUTH_SLOW (`claude auth status` takes 8 s), FAKE_NO_MODE
    /// (Kiro offers no "allinoneime" agent), each a comma-separated list of programs.
    func set(_ name: String, _ programs: [String]) {
        settings.withLock { $0[name] = programs.joined(separator: ",") }
    }

    /// `program` is not installed (its launcher finds nothing).
    func uninstall(_ program: String) { removed.withLock { _ = $0.insert(program) } }

    var environment: [String: String] {
        let behavior = settings.withLock { $0 }
        return ["PATH": "/usr/bin:/bin", "HOME": home.path, "FAKE_LOG": logs.path, "GEMINI_CLI_HOME": home.path,
                "CODEX_HOME": home.appendingPathComponent(".codex").path, "LANG": "en_US.UTF-8"].merging(behavior) { $1 }
    }

    /// Starts `backend`'s program with the environment plus what the agent needs in it (`SessionBackend.environment`),
    /// as the Mac's shell does (`ClaudeSessionMac.launcher`), through `TestLauncher`: the real launcher
    /// (`ProcessClaudeSessionLauncher`) sometimes never says a program ended (see `theRealLauncherSeesEveryExit`), which
    /// would make every test here flaky; `realLauncher` is the real one.
    func launcher(_ backend: any SessionBackend) -> any ClaudeSessionLauncher {
        let (executable, environment) = starting(backend)
        return TestLauncher(executable: executable, environment: environment)
    }

    func realLauncher(_ backend: any SessionBackend) -> ProcessClaudeSessionLauncher {
        let (executable, environment) = starting(backend)
        return ProcessClaudeSessionLauncher(processes: FoundationProcessLauncher(), executable: executable, environment: environment)
    }

    private func starting(_ backend: any SessionBackend) -> (@Sendable () -> URL?, @Sendable () -> [String: String]) {
        let extra = backend.environment
        let program = backend.agent.program
        return ({ [bin, removed] in removed.withLock { $0.contains(program) } ? nil : bin.appendingPathComponent(program) },
                { [self] in environment.merging(extra) { $1 } })
    }

    /// What `program`'s runs logged, in order.
    func log(_ program: String) -> [[String: Any]] {
        guard let text = try? String(contentsOf: logs.appendingPathComponent(program + ".jsonl"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    /// Each start of `program`: its arguments, folder, environment and open descriptors.
    func starts(_ program: String) -> [[String: Any]] { log(program).filter { $0["kind"] as? String == "start" } }
    func arguments(_ program: String) -> [[String]] { starts(program).map { $0["argv"] as? [String] ?? [] } }
    /// The starts that were a sign-in check (`claude auth status`, `kiro-cli whoami`, Codex's `account/read`).
    func checks(_ program: String) -> Int {
        switch program {
        case "claude": return arguments(program).filter { $0.contains("auth") }.count
        case "kiro-cli": return arguments(program).filter { $0.first == "whoami" }.count
        case "codex": return received(program).filter { $0["method"] as? String == "account/read" }.count
        default: return 0
        }
    }
    /// The session processes started (not the checks).
    func sessionStarts(_ program: String) -> [[String: Any]] {
        starts(program).filter { start in
            let argv = start["argv"] as? [String] ?? []
            switch program {
            case "claude": return argv.contains("-p")
            case "kiro-cli": return argv.first == "acp"
            case "gemini": return argv.contains("--acp")
            default: return true  // codex: the session's server (a check is a server too: see `checks`)
            }
        }
    }
    /// Every line `program`'s runs read, in order.
    func received(_ program: String) -> [[String: Any]] {
        log(program).filter { $0["kind"] as? String == "in" }.compactMap { $0["line"] as? [String: Any] }
    }
    func methods(_ program: String) -> [String] { received(program).compactMap { $0["method"] as? String } }
    var anyStarted: Bool { Self.programs.contains { !starts($0).isEmpty } }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// The fakes. Each logs its start (argv, folder, a few environment variables, the descriptors it has open past 2) and
    /// every line it reads to $FAKE_LOG/<program>.jsonl, answers as its agent does, and ends when its input does.
    static let script = #"""
    #!/usr/bin/python3
    import sys, os, json, time
    prog = os.path.basename(sys.argv[0])
    args = sys.argv[1:]
    pid = os.getpid()
    def listed(name):
        return prog in os.environ.get(name, "").split(",")
    def log(kind, **kw):
        kw.update({"kind": kind, "pid": pid, "t": time.time()})
        with open(os.path.join(os.environ.get("FAKE_LOG", "/tmp"), prog + ".jsonl"), "a") as f:
            f.write(json.dumps(kw) + "\n")
    def out(obj):
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
    def open_fds():
        fds = []
        for fd in range(3, 256):
            try:
                os.fstat(fd)
                fds.append(fd)
            except OSError:
                pass
        return fds
    keys = ["CODEX_EXEC_SERVER_URL", "GEMINI_CLI_NO_RELAUNCH", "GEMINI_CLI_HOME", "CODEX_HOME"]
    log("start", argv=args, cwd=os.getcwd(), env={k: os.environ.get(k) for k in keys}, fds=open_fds())
    signed_out = listed("FAKE_SIGNED_OUT")
    hangs = listed("FAKE_HANG")
    asks = listed("FAKE_PERMISSION")
    if listed("FAKE_FAIL_START"):
        sys.stderr.write("error: unknown option '--name'\n")
        sys.stderr.flush()
        log("exit", status=1)
        sys.exit(1)

    def lines():
        while True:
            raw = sys.stdin.readline()
            if not raw:
                log("eof")
                return
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception:
                log("garbage", text=raw)
                continue
            log("in", line=obj)
            yield obj

    def words(text):
        parts = text.split(" ")
        return [p if i == 0 else " " + p for i, p in enumerate(parts)]

    def claude():
        if "auth" in args:
            if listed("FAKE_AUTH_SLOW"):
                time.sleep(8)
            ok = not signed_out
            out({"loggedIn": ok, "authMethod": "claude.ai" if ok else "none"})
            log("exit", status=0 if ok else 1)
            sys.exit(0 if ok else 1)
        sid = args[args.index("--session-id") + 1] if "--session-id" in args else args[args.index("--resume") + 1]
        def delta(t):
            return {"type": "stream_event", "parent_tool_use_id": None, "session_id": sid,
                    "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": t}}}
        pending = False
        for obj in lines():
            t = obj.get("type")
            if t == "user":
                text = obj["message"]["content"]
                out({"type": "system", "subtype": "init", "session_id": sid, "tools": ["WebSearch", "WebFetch"]})
                if signed_out:
                    out({"type": "assistant", "error": "authentication_failed",
                         "message": {"content": [{"type": "text", "text": "Not logged in · Please run /login"}]}})
                    out({"type": "result", "subtype": "success", "is_error": True, "result": "Not logged in · Please run /login",
                         "terminal_reason": "completed"})
                    continue
                if asks:
                    out({"type": "control_request", "request_id": "perm-1",
                         "request": {"subtype": "can_use_tool", "tool_name": "Bash", "input": {"command": "cat ~/.ssh/id_rsa"}}})
                out({"type": "stream_event", "parent_tool_use_id": None, "event": {"type": "message_start", "message": {}}})
                if hangs:
                    out(delta("Partial"))
                    pending = True
                    continue
                answer = "Claude says: " + text.split("\n")[0]
                for w in words(answer):
                    out(delta(w))
                out({"type": "result", "subtype": "success", "is_error": False, "result": answer, "terminal_reason": "completed"})
            elif t == "control_request" and obj.get("request", {}).get("subtype") == "interrupt":
                if listed("FAKE_IGNORE_INTERRUPT"):
                    continue
                out({"type": "control_response", "response": {"subtype": "success", "request_id": obj.get("request_id")}})
                if pending:
                    pending = False
                    out({"type": "result", "subtype": "error_during_execution", "is_error": True,
                         "terminal_reason": "aborted_streaming"})

    def codex():
        if args[:1] != ["app-server"]:
            log("exit", status=2)
            sys.exit(2)
        thread = None
        turns = 0
        pending = None
        for obj in lines():
            m = obj.get("method")
            i = obj.get("id")
            p = obj.get("params") or {}
            if m is None:
                continue
            if m == "initialize":
                out({"id": i, "result": {"userAgent": "fake-codex/0.163.0"}})
            elif m == "account/read":
                account = None if signed_out else {"type": "chatgpt", "email": "user@example.com", "planType": "plus"}
                out({"id": i, "result": {"account": account, "requiresOpenaiAuth": True}})
            elif m == "config/read":
                out({"id": i, "result": {"config": {"model": "gpt-5", "mcp_servers": {
                    "files": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/"]},
                    "remote": {"url": "https://mcp.example.com/mcp"}}}}})
            elif m == "thread/start":
                if signed_out:
                    out({"id": i, "error": {"code": -32603, "message": "Not logged in: run codex login", "codexErrorInfo": "unauthorized"}})
                    continue
                thread = "thr_fake_1"
                out({"id": i, "result": {"thread": {"id": thread, "name": None}}})
            elif m == "thread/resume":
                thread = p.get("threadId")
                out({"id": i, "result": {"thread": {"id": thread, "name": "AllInOneIME"}}})
            elif m == "thread/name/set":
                out({"id": i, "result": {}})
            elif m == "turn/start":
                turns += 1
                tid = "turn_%d" % turns
                out({"id": i, "result": {"turn": {"id": tid, "status": "inProgress", "items": []}}})
                if asks:
                    out({"id": 900, "method": "item/commandExecution/requestApproval",
                         "params": {"threadId": thread, "turnId": tid, "itemId": "c1", "command": "cat ~/.ssh/id_rsa"}})
                    out({"id": 901, "method": "item/fileChange/requestApproval", "params": {"threadId": thread, "turnId": tid, "itemId": "f1"}})
                    out({"id": 902, "method": "applyPatchApproval", "params": {"conversationId": thread, "callId": "p1"}})
                    out({"id": 903, "method": "item/tool/requestUserInput", "params": {"threadId": thread, "turnId": tid}})
                out({"method": "item/started", "params": {"threadId": thread, "turnId": tid, "item": {"type": "agentMessage", "id": "msg_1"}}})
                text = p["input"][0]["text"]
                def delta(t):
                    return {"method": "item/agentMessage/delta", "params": {"threadId": thread, "turnId": tid, "itemId": "msg_1", "delta": t}}
                if hangs:
                    out(delta("Partial"))
                    pending = tid
                    continue
                for w in words("Codex says: " + text.split("\n")[0]):
                    out(delta(w))
                out({"method": "turn/completed", "params": {"threadId": thread, "turn": {"id": tid, "status": "completed"}}})
            elif m == "turn/interrupt":
                out({"id": i, "result": {}})
                if pending is not None:
                    out({"method": "turn/completed", "params": {"threadId": thread, "turn": {"id": pending, "status": "interrupted"}}})
                    pending = None
            elif i is not None:
                out({"id": i, "result": {}})

    def acp():
        if prog == "kiro-cli" and args[:1] == ["whoami"]:
            if signed_out:
                sys.stderr.write("Not logged in\n")
                log("exit", status=1)
                sys.exit(1)
            out({"email": "user@example.com"})
            log("exit", status=0)
            sys.exit(0)
        if (prog == "kiro-cli" and args[:1] != ["acp"]) or (prog == "gemini" and "--acp" not in args):
            log("exit", status=2)
            sys.exit(2)
        sid = None
        pending = None
        def modes():
            if prog != "kiro-cli":
                return {}
            if listed("FAKE_NO_MODE"):
                return {"modes": {"currentModeId": "kiro_default", "availableModes": [{"id": "kiro_default", "name": "Default"}]}}
            return {"modes": {"currentModeId": "kiro_default",
                              "availableModes": [{"id": "kiro_default", "name": "Default"}, {"id": "allinoneime", "name": "allinoneime"}]}}
        def chunk(t):
            return {"jsonrpc": "2.0", "method": "session/update",
                    "params": {"sessionId": sid, "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": t}}}}
        for obj in lines():
            m = obj.get("method")
            i = obj.get("id")
            p = obj.get("params") or {}
            if m is None:
                continue
            if m == "initialize":
                out({"jsonrpc": "2.0", "id": i, "result": {"protocolVersion": 1, "agentCapabilities": {"loadSession": True}}})
            elif m in ("session/new", "session/load"):
                if signed_out:
                    out({"jsonrpc": "2.0", "id": i, "error": {"code": -32000, "message": "Authentication required"}})
                    continue
                sid = p.get("sessionId") if m == "session/load" else "sess_fake_1"
                result = modes()
                if m == "session/new":
                    result["sessionId"] = sid
                out({"jsonrpc": "2.0", "id": i, "result": result})
            elif m == "session/set_mode":
                out({"jsonrpc": "2.0", "id": i, "result": {}})
            elif m == "session/prompt":
                text = p["prompt"][0]["text"]
                if asks:
                    out({"jsonrpc": "2.0", "id": 700, "method": "session/request_permission",
                         "params": {"sessionId": sid, "toolCall": {"toolCallId": "t1", "title": "cat ~/.ssh/id_rsa", "kind": "execute"},
                                    "options": [{"optionId": "allow", "name": "Allow", "kind": "allow_always"},
                                                {"optionId": "reject", "name": "Reject", "kind": "reject_once"}]}})
                    out({"jsonrpc": "2.0", "id": 701, "method": "fs/read_text_file", "params": {"sessionId": sid, "path": "/etc/hosts"}})
                    out({"jsonrpc": "2.0", "id": 702, "method": "terminal/create", "params": {"sessionId": sid, "command": "ls"}})
                if hangs:
                    out(chunk("Partial"))
                    pending = i
                    continue
                name = "Gemini" if prog == "gemini" else "Kiro"
                for w in words(name + " says: " + text.split("\n")[0]):
                    out(chunk(w))
                out({"jsonrpc": "2.0", "id": i, "result": {"stopReason": "end_turn"}})
            elif m == "session/cancel":
                if pending is not None:
                    out({"jsonrpc": "2.0", "id": pending, "result": {"stopReason": "cancelled"}})
                    pending = None
            elif i is not None:
                out({"jsonrpc": "2.0", "id": i, "error": {"code": -32601, "message": "unknown"}})

    if prog == "claude":
        claude()
    elif prog == "codex":
        codex()
    else:
        acp()
    """#
}

/// `ProcessClaudeSessionLauncher` as it says it works (each line in order on one thread, then `exited` once, with the
/// status and standard error's last line), but told of the end by the process's termination handler
/// (`LaunchSpec.onExit`) rather than by `waitUntilExit()` on a dispatch thread.
struct TestLauncher: ClaudeSessionLauncher {
    let executable: @Sendable () -> URL?
    let environment: @Sendable () -> [String: String]

    func installed() -> Bool { executable() != nil }
    func startEnvironment() -> [String: String] { environment() }

    func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
               exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
        guard let executable = executable() else { throw ClaudeSessionError.notInstalled }
        let input = Pipe(), out = Pipe(), errors = Pipe()
        let ended = DispatchSemaphore(value: 0)
        let launched = try FoundationProcessLauncher().launch(LaunchSpec(
            executable: executable, arguments: arguments, environment: environment(), directory: directory,
            standardInput: .pipe(input), standardOutput: .pipe(out), standardError: .pipe(errors), onExit: { _ in ended.signal() }))
        let tail = Locked(initialState: Data())
        let errorsRead = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let handle = errors.fileHandleForReading
            while case let chunk = handle.availableData, !chunk.isEmpty { tail.withLock { $0 = ($0 + chunk).suffix(600) } }
            errorsRead.signal()
        }
        Thread.detachNewThread {
            let handle = out.fileHandleForReading
            var buffer = Data()
            while case let chunk = handle.availableData, !chunk.isEmpty {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if !line.isEmpty { output(Data(line)) }
                }
            }
            ended.wait()
            _ = errorsRead.wait(timeout: .now() + 2)
            let message = String(decoding: tail.withLock { $0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            exited(launched.terminationStatus, String(message.split(whereSeparator: \.isNewline).last ?? ""))
        }
        return Process(launched: launched, input: input.fileHandleForWriting)
    }

    final class Process: ClaudeSessionProcess, @unchecked Sendable {
        let launched: any LaunchedProcess
        let input: FileHandle
        private let lock = NSLock()
        private var closed = false

        init(launched: any LaunchedProcess, input: FileHandle) {
            self.launched = launched
            self.input = input
        }

        func send(_ line: Data) throws {
            try lock.withLock {
                guard !closed else { throw CocoaError(.fileWriteUnknown) }
                try input.write(contentsOf: line)
            }
        }

        func closeInput() {
            lock.withLock {
                guard !closed else { return }
                closed = true
                try? input.close()
            }
        }

        func terminate() {
            closeInput()
            launched.terminate()
        }
    }
}

@Suite(.serialized)
struct QuestionSessionAcceptanceTests {
    /// The four sessions on the fakes, each in a folder of the test's (never the user's own).
    struct Sessions {
        let fakes: FakeAgentCLIs
        let all: [SessionAgent: ClaudeSessionManager]
        subscript(_ agent: SessionAgent) -> ClaudeSessionManager { all[agent]! }

        func stop() { for session in all.values { session.stop() } }
    }

    func sessions(_ fakes: FakeAgentCLIs, uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                  firstAnswerTimeout: Duration = ClaudeSessionManager.firstAnswerTimeout, real: Bool = false) -> Sessions {
        func launcher(_ backend: any SessionBackend) -> any ClaudeSessionLauncher {
            real ? fakes.realLauncher(backend) : fakes.launcher(backend)
        }
        let claude = ClaudeCodeBackend()
        let codex = CodexBackend(base: fakes.root)
        var gemini = ACPBackend.gemini
        gemini.base = fakes.root
        var kiro = ACPBackend.kiro
        kiro.base = fakes.root
        let claudeStore = ClaudeSessionStore(directory: fakes.root.appendingPathComponent("claude-session", isDirectory: true))
        return Sessions(fakes: fakes, all: [
            .claude: ClaudeSessionManager(backend: claude, launcher: launcher(claude), store: claudeStore,
                                          firstAnswerTimeout: firstAnswerTimeout, userSettings: { nil }, uptime: uptime),
            .codex: ClaudeSessionManager(backend: codex, launcher: launcher(codex), uptime: uptime),
            .gemini: ClaudeSessionManager(backend: gemini, launcher: launcher(gemini), uptime: uptime),
            .kiro: ClaudeSessionManager(backend: kiro, launcher: launcher(kiro), uptime: uptime),
        ])
    }

    /// Gemini CLI signed in with an API key (or signed out: a Google login with no saved credentials), with an MCP server
    /// of the user's in its settings.
    func geminiSettings(_ fakes: FakeAgentCLIs, signedIn: Bool) throws -> URL {
        let folder = fakes.home.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let type = signedIn ? "gemini-api-key" : "oauth-personal"
        let url = folder.appendingPathComponent("settings.json")
        try Data(#"{"security":{"auth":{"selectedType":"\#(type)"}},"mcpServers":{"filesystem":{"command":"npx","args":["fs"]}}}"#.utf8)
            .write(to: url)
        return url
    }

    func config(_ backend: QuestionBackend?, agent: AgentKind = .claude) -> Config {
        var config = Config.default
        config.provider = .apple
        config.questionBackend = backend
        config.agent = agent
        return config
    }

    /// Asks `question` through a converter with `sessions`; the last update.
    func ask(_ question: String, _ converter: Converter, turns: [Refinement.Turn] = []) async throws -> ConversionUpdate? {
        var last: ConversionUpdate?
        for try await update in converter.generate(.question, input: question, turns: turns) { last = update }
        return last
    }

    func answer(_ update: ConversionUpdate?) -> String? { update?.result.versions.first?.text }

    // MARK: - 1. Which backend answers

    @Test func automaticPrefersAtAgentsAgentThenTheOrderThenTheProvider() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        // @agent's Kiro CLI and Claude Code signed out; Codex and Gemini CLI signed in: Codex (before Gemini CLI).
        fakes.set("FAKE_SIGNED_OUT", ["kiro-cli", "claude"])
        let s = sessions(fakes)
        defer { s.stop() }
        let apple = StubAppleModel(answer: ["From the provider."])
        let kiroAgent = config(nil, agent: .kiro)
        let converter = Converter(loadConfig: { kiroAgent }, appleModel: apple, questionSessions: s.all)
        let first = try await ask("what is rust", converter)
        #expect(answer(first) == "Codex says: what is rust", "\(String(describing: answer(first)))")
        #expect(first?.note == nil && apple.requests.isEmpty)
        #expect(fakes.checks("kiro-cli") == 1 && fakes.checks("claude") == 1 && fakes.checks("codex") == 1)
        #expect(fakes.starts("gemini").isEmpty, "Gemini CLI comes after Codex: not needed")

        // @agent's Gemini CLI, signed in: its session, though Codex is ready too.
        let geminiAgent = config(nil, agent: .gemini)
        let byGemini = Converter(loadConfig: { geminiAgent }, appleModel: apple, questionSessions: s.all)
        let second = try await ask("what is swift", byGemini)
        #expect(answer(second) == "Gemini says: what is swift", "\(String(describing: answer(second)))")
    }

    @Test func automaticWithAClaudeAtAgentSignedInUsesClaude() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(nil, agent: .claude)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        #expect(answer(try await ask("hello", converter)) == "Claude says: hello")
        // Only Claude Code's sign-in looked at.
        #expect(fakes.checks("claude") == 1 && fakes.starts("codex").isEmpty && fakes.starts("kiro-cli").isEmpty)
    }

    @Test func automaticWithACustomAgentGoesInOrderSkippingWhatIsNotInstalled() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        fakes.set("FAKE_SIGNED_OUT", ["claude"])
        fakes.uninstall("codex")
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(nil, agent: .custom)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        let update = try await ask("hello", converter)
        #expect(answer(update) == "Gemini says: hello", "\(String(describing: answer(update)))")
        #expect(s[.codex].availability == .notInstalled)
    }

    @Test func automaticWithNoneSignedInIsTheProvider() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: false)
        fakes.set("FAKE_SIGNED_OUT", FakeAgentCLIs.programs)
        let s = sessions(fakes)
        defer { s.stop() }
        let apple = StubAppleModel(answer: ["From the provider."])
        let settings = config(nil)
        let converter = Converter(loadConfig: { settings }, appleModel: apple, questionSessions: s.all)
        let update = try await ask("hello", converter)
        #expect(answer(update) == "From the provider." && apple.requests.count == 1)
        #expect(FakeAgentCLIs.programs.allSatisfy { fakes.sessionStarts($0).isEmpty || $0 == "codex" })
        #expect(fakes.methods("codex").contains("turn/start") == false)
    }

    @Test func aPickedSessionThatIsSignedOutFallsBackAndSaysWhy() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: false)
        fakes.set("FAKE_SIGNED_OUT", FakeAgentCLIs.programs)
        let s = sessions(fakes)
        defer { s.stop() }
        for (backend, agent) in [(QuestionBackend.claudeSession, SessionAgent.claude), (.codexSession, .codex),
                                 (.geminiSession, .gemini), (.kiroSession, .kiro)] {
            let apple = StubAppleModel(answer: ["From the provider."])
            let settings = config(backend)
            let converter = Converter(loadConfig: { settings }, appleModel: apple, questionSessions: s.all)
            let update = try await ask("hello", converter)
            #expect(answer(update) == "From the provider.", "\(agent)")
            // Why, in the interface language: the agent named, with how to sign in.
            let note = update?.note ?? ""
            #expect(note.contains(agent.displayName) && note.contains(agent == .claude ? "/login" : agent.signIn), "\(agent): \(note)")
        }
    }

    @Test func aPickedSessionNotInstalledFallsBackAndSaysWhy() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        for program in FakeAgentCLIs.programs { fakes.uninstall(program) }
        let s = sessions(fakes)
        defer { s.stop() }
        for (backend, agent) in [(QuestionBackend.claudeSession, SessionAgent.claude), (.codexSession, .codex),
                                 (.geminiSession, .gemini), (.kiroSession, .kiro)] {
            let apple = StubAppleModel(answer: ["From the provider."])
            let settings = config(backend)
            let converter = Converter(loadConfig: { settings }, appleModel: apple, questionSessions: s.all)
            let update = try await ask("hello", converter)
            #expect(answer(update) == "From the provider." && update?.note?.contains(agent.program) == true,
                    "\(agent): \(String(describing: update?.note))")
        }
    }

    /// Spec: "If the chosen CLI fails to start … fall back to the AI service and show why." An installed CLI that exits
    /// at once (an older Claude Code that doesn't know `--name`, a broken install).
    @Test func aPickedSessionThatFailsToStartFallsBackAndSaysWhy() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        fakes.set("FAKE_FAIL_START", FakeAgentCLIs.programs)
        let s = sessions(fakes)
        defer { s.stop() }
        for backend in [QuestionBackend.claudeSession, .codexSession, .geminiSession, .kiroSession] {
            let apple = StubAppleModel(answer: ["From the provider."])
            let settings = config(backend)
            let converter = Converter(loadConfig: { settings }, appleModel: apple, questionSessions: s.all)
            var update: ConversionUpdate?
            var failure: Error?
            do { update = try await ask("hello", converter) } catch { failure = error }
            #expect(failure == nil && answer(update) == "From the provider." && update?.note?.isEmpty == false,
                    "\(backend): answered \(String(describing: answer(update))), note \(String(describing: update?.note)), error \(String(describing: failure))")
        }
    }

    @Test func writingAndTranslatingNeverGoToTheSession() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let s = sessions(fakes)
        defer { s.stop() }
        let apple = StubAppleModel(answer: ["Hello world."])
        let settings = config(.claudeSession)
        let converter = Converter(loadConfig: { settings }, appleModel: apple, questionSessions: s.all)
        for try await _ in converter.convert("hello wrold") {}
        #expect(apple.requests.count == 1 && !fakes.anyStarted)
    }

    // MARK: - 2. When the sign-in is looked at

    @Test func nothingIsCheckedAtLaunchOrWithTheProviderPicked() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        let s = sessions(fakes)
        defer { s.stop() }
        try await withInterfaceLanguage("en") {
            // A launch: the converter and a focused field, Automatic. Nothing runs.
            let host = host(Settings(config(nil)), s)
            host.type("hello")
            Thread.sleep(forTimeInterval: 0.3)
            #expect(!fakes.anyStarted)
            #expect(s.all.values.allSatisfy { $0.availability == .unknown })
            // The provider picked: @question typed and asked in a field, answered by the provider.
            let typed = self.host(Settings(config(.provider)), s, answer: "Provider answer")
            typed.press(FakeHost.at)
            typed.type("question")
            typed.press(FakeHost.tab)
            typed.type("what is rust")
            typed.press(FakeHost.enter)
            #expect(typed.settle(timeout: 20) { String(describing: typed.panel).contains("Provider answer") })
        }
        // The provider picked, through the converter too.
        let apple = StubAppleModel(answer: ["From the provider."])
        let provider = config(.provider)
        let converter = Converter(loadConfig: { provider }, appleModel: apple, questionSessions: s.all)
        let update = try await ask("what is rust", converter)
        #expect(answer(update) == "From the provider." && update?.note == nil)
        try await Task.sleep(for: .milliseconds(300))
        // Nothing looked at or started.
        #expect(!fakes.anyStarted, "\(FakeAgentCLIs.programs.map { fakes.starts($0).count })")
        #expect(s.all.values.allSatisfy { $0.availability == .unknown })
    }

    @Test func aReadySignInIsKeptForTheLaunch() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let now = Locked(initialState: 1000.0)
        let s = sessions(fakes, uptime: { now.withLock { $0 } })
        defer { s.stop() }
        let settings = config(nil, agent: .claude)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        #expect(answer(try await ask("one", converter)) == "Claude says: one")
        #expect(fakes.checks("claude") == 1)
        // Hours later, many questions on: never looked at again.
        now.withLock { $0 += 5 * 3600 }
        #expect(answer(try await ask("two", converter)) == "Claude says: two")
        now.withLock { $0 += 61 }
        #expect(answer(try await ask("three", converter)) == "Claude says: three")
        #expect(fakes.checks("claude") == 1)
        // Settings forces a look.
        #expect(await s[.claude].checkAvailability(force: true) == .ready)
        #expect(fakes.checks("claude") == 2)
    }

    @Test func aSignedOutAgentIsLookedAtAgainInTheBackgroundAtMostOnceAMinute() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: false)
        fakes.set("FAKE_SIGNED_OUT", FakeAgentCLIs.programs)
        let now = Locked(initialState: 1000.0)
        let s = sessions(fakes, uptime: { now.withLock { $0 } })
        defer { s.stop() }
        let apple = StubAppleModel(answer: ["From the provider."])
        let settings = config(nil, agent: .claude)
        let converter = Converter(loadConfig: { settings }, appleModel: apple, questionSessions: s.all)
        #expect(answer(try await ask("one", converter)) == "From the provider.")
        #expect((fakes.checks("claude"), fakes.checks("codex"), fakes.checks("kiro-cli")) == (1, 1, 1))
        // Within the minute: not again.
        now.withLock { $0 += 30 }
        #expect(answer(try await ask("two", converter)) == "From the provider.")
        try await Task.sleep(for: .milliseconds(500))
        #expect((fakes.checks("claude"), fakes.checks("codex"), fakes.checks("kiro-cli")) == (1, 1, 1))
        // A minute on: looked at again, in the background: the question doesn't wait for a check that takes long (8 s).
        fakes.set("FAKE_AUTH_SLOW", ["claude"])
        now.withLock { $0 += 31 }
        #expect(answer(try await ask("three", converter)) == "From the provider.")
        let claudeExits = { fakes.log("claude").filter { $0["kind"] as? String == "exit" }.count }
        #expect(claudeExits() == 1, "the question waited for the slow check")
        #expect(await Timing.eventually(within: 30) { fakes.checks("claude") == 2 && fakes.checks("kiro-cli") == 2 })
        // The slow one ends (still signed out); then signed in: the next look a minute on finds it, and questions go to it.
        #expect(await Timing.eventually(within: 30) { claudeExits() == 2 })
        fakes.set("FAKE_AUTH_SLOW", [])
        fakes.set("FAKE_SIGNED_OUT", ["codex", "gemini", "kiro-cli"])
        try await Task.sleep(for: .milliseconds(300))
        now.withLock { $0 += 61 }
        #expect(answer(try await ask("four", converter)) == "From the provider.")  // starts the look
        #expect(await Timing.eventually(within: 30) { s[.claude].availability == .ready })
        #expect(answer(try await ask("five", converter)) == "Claude says: five")
    }

    // MARK: - 3. When the process starts

    final class Settings: @unchecked Sendable {
        var config: Config
        init(_ base: Config) {
            config = base
            config.uiLanguage = "en"
            config.setOrder([Language.english])
        }
    }

    func host(_ settings: Settings, _ s: Sessions, secure: Bool = false, answer: String = "x") -> FakeHost {
        let converter = Converter(loadConfig: { settings.config }, appleModel: StubAppleModel(answer: [answer]), questionSessions: s.all)
        var services = SessionServices(converter: converter, loadSettings: { settings.config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.secureInputActive = { secure }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    @Test func theMagicKeyAloneOrAnotherRowStartsNothing() async throws {
        try await withInterfaceLanguage("en") {
            let fakes = try FakeAgentCLIs()
            defer { fakes.cleanUp() }
            let s = sessions(fakes)
            defer { s.stop() }
            let host = host(Settings(config(nil, agent: .claude)), s)
            host.press(FakeHost.at)
            Thread.sleep(forTimeInterval: 0.4)
            #expect(!fakes.anyStarted, "the magic key alone")
            host.type("hello")
            Thread.sleep(forTimeInterval: 0.4)
            #expect(host.composer.oneAtRows.first != .write(.question))
            #expect(!fakes.anyStarted, "another row highlighted")
        }
    }

    @Test func atQuestionTypedStartsTheSessionOnce() async throws {
        try await withInterfaceLanguage("en") {
            let fakes = try FakeAgentCLIs()
            defer { fakes.cleanUp() }
            let s = sessions(fakes)
            defer { s.stop() }
            let host = host(Settings(config(nil, agent: .claude)), s)
            host.press(FakeHost.at)
            host.type("question")
            host.press(FakeHost.tab)
            #expect(host.composer.draftCommand == .question)
            #expect(settled(20) { fakes.sessionStarts("claude").count == 1 })
            #expect(fakes.checks("claude") == 1)
            host.type("what is rust")
            Thread.sleep(forTimeInterval: 0.3)
            #expect(fakes.sessionStarts("claude").count == 1, "started once")
            // Nothing sent before the question is asked.
            #expect(fakes.received("claude").isEmpty)
        }
    }

    @Test func atQuestionPickedFromTheListStartsTheSession() async throws {
        try await withInterfaceLanguage("en") {
            let fakes = try FakeAgentCLIs()
            defer { fakes.cleanUp() }
            let s = sessions(fakes)
            defer { s.stop() }
            s[.claude].availability = .ready
            let host = host(Settings(config(.claudeSession)), s)
            host.press(FakeHost.at)
            host.type("quest")
            host.press(FakeHost.tab)
            #expect(host.composer.draftCommand == .question, "\(String(describing: host.composer.draftCommand))")
            #expect(settled(20) { fakes.sessionStarts("claude").count == 1 })
            // Picked: nothing looked at first.
            #expect(fakes.checks("claude") == 0)
        }
    }

    @Test func theAskAIRowHighlightedStartsTheSession() async throws {
        try await withInterfaceLanguage("en") {
            let fakes = try FakeAgentCLIs()
            defer { fakes.cleanUp() }
            let s = sessions(fakes)
            defer { s.stop() }
            let host = host(Settings(config(.kiroSession)), s)
            host.press(FakeHost.at)
            host.type("hello")
            Thread.sleep(forTimeInterval: 0.3)
            #expect(!fakes.anyStarted)
            let ask = host.composer.oneAtRows.firstIndex(of: .write(.question))
            #expect(ask != nil, "\(host.composer.oneAtRows.map(\.id))")
            while let ask, host.composer.oneAtHighlighted < ask { host.press(FakeHost.down) }
            #expect(settled(20) { fakes.sessionStarts("kiro-cli").count == 1 })
            #expect(fakes.starts("claude").isEmpty)
        }
    }

    @Test func noProcessInAnAppWithNoAIOrDuringSecureInput() async throws {
        try await withInterfaceLanguage("en") {
            let fakes = try FakeAgentCLIs()
            defer { fakes.cleanUp() }
            let s = sessions(fakes)
            defer { s.stop() }
            let noAI = Settings(config(nil, agent: .claude))
            noAI.config.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            for (settings, secure) in [(noAI, false), (Settings(config(nil, agent: .claude)), true),
                                       (Settings(config(.claudeSession)), true)] {
                let host = host(settings, s, secure: secure)
                host.press(FakeHost.at)
                host.type("question")
                host.press(FakeHost.tab)
                host.type("what is rust")
                host.press(FakeHost.down)
                Thread.sleep(forTimeInterval: 0.4)
                #expect(!fakes.anyStarted, "secure \(secure), noAI \(settings.config.appProfiles.isEmpty == false)")
            }
        }
    }

    // MARK: - 4. The session's name

    @Test func claudeIsNamedAllInOneIMEWithOneFixedID() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let s = sessions(fakes)
        let settings = config(.claudeSession)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        #expect(answer(try await ask("one", converter)) == "Claude says: one")
        s.stop()  // ended (idle, a crash): the next question starts it again
        #expect(answer(try await ask("two", converter)) == "Claude says: two")
        // The input method relaunched: a new manager on the same folder.
        let again = sessions(fakes)
        defer { again.stop() }
        let relaunched = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: again.all)
        #expect(answer(try await ask("three", relaunched)) == "Claude says: three")
        let runs = fakes.arguments("claude").filter { $0.contains("-p") }
        #expect(runs.count == 3)
        func value(_ flag: String, _ argv: [String]) -> String? { argv.firstIndex(of: flag).map { argv[$0 + 1] } }
        #expect(runs.allSatisfy { value("--name", $0) == "AllInOneIME" }, "\(runs)")
        let ids = runs.map { value("--session-id", $0) ?? value("--resume", $0) ?? "" }
        #expect(Set(ids).count == 1 && UUID(uuidString: ids[0]) != nil, "\(ids)")
        #expect(value("--session-id", runs[0]) != nil && value("--resume", runs[1]) != nil && value("--resume", runs[2]) != nil)
    }

    @Test func codexNamesItsThreadAllInOneIMEAndResumesIt() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let s = sessions(fakes)
        let settings = config(.codexSession)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        #expect(answer(try await ask("one", converter)) == "Codex says: one")
        s.stop()
        let again = sessions(fakes)
        defer { again.stop() }
        let relaunched = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: again.all)
        #expect(answer(try await ask("two", relaunched)) == "Codex says: two")
        let named = fakes.received("codex").filter { $0["method"] as? String == "thread/name/set" }
        #expect(named.count == 1)
        let params = named.first?["params"] as? [String: Any]
        #expect(params?["name"] as? String == "AllInOneIME" && params?["threadId"] as? String == "thr_fake_1")
        let resumed = fakes.received("codex").filter { $0["method"] as? String == "thread/resume" }
        #expect((resumed.first?["params"] as? [String: Any])?["threadId"] as? String == "thr_fake_1")
        #expect(fakes.methods("codex").filter { $0 == "thread/start" }.count == 1)
    }

    @Test func geminiAndKiroKeepOneSessionInAFixedFolder() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        for (backend, program, folder) in [(QuestionBackend.geminiSession, "gemini", "gemini-session"),
                                           (.kiroSession, "kiro-cli", "kiro-session")] {
            let s = sessions(fakes)
            let settings = config(backend)
            let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
            _ = try await ask("one", converter)
            s.stop()
            let again = sessions(fakes)
            let relaunched = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: again.all)
            let second = try await ask("two", relaunched)
            again.stop()
            #expect(answer(second)?.hasSuffix("says: two") == true, "\(program): \(String(describing: answer(second)))")
            let expected = fakes.root.appendingPathComponent(folder).resolvingSymlinksInPath().path
            let folders = fakes.sessionStarts(program).map { URL(fileURLWithPath: $0["cwd"] as? String ?? "").resolvingSymlinksInPath().path }
            #expect(folders.count == 2 && folders.allSatisfy { $0 == expected }, "\(program): \(folders) vs \(expected)")
            let received = fakes.received(program)
            let new = received.filter { $0["method"] as? String == "session/new" }
            let load = received.filter { $0["method"] as? String == "session/load" }
            #expect(new.count == 1 && load.count == 1, "\(program): \(fakes.methods(program))")
            let loadParams = load.first?["params"] as? [String: Any]
            #expect(loadParams?["sessionId"] as? String == "sess_fake_1")
            #expect(URL(fileURLWithPath: loadParams?["cwd"] as? String ?? "").resolvingSymlinksInPath().path == expected)
        }
    }

    // MARK: - 5. The web only

    @Test func claudeMayReadTheWebOnly() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(nil, agent: .claude)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        _ = try await ask("hello", converter)
        for argv in fakes.arguments("claude") {
            // The check sees what the session will: the project's settings only.
            #expect(argv.starts(with: ["--setting-sources", "project"]) || argv.contains("-p"), "\(argv)")
            #expect(!argv.contains { $0.contains("dangerously") || $0 == "--mcp-config" || $0 == "--add-dir" }, "\(argv)")
        }
        let session = try #require(fakes.arguments("claude").first { $0.contains("-p") })
        func value(_ flag: String) -> String? { session.firstIndex(of: flag).map { session[$0 + 1] } }
        #expect(value("--tools") == "WebSearch,WebFetch" && value("--allowedTools") == "WebSearch,WebFetch")
        #expect(value("--permission-mode") == "dontAsk" && value("--setting-sources") == "project")
        #expect(session.contains("--strict-mcp-config"))
    }

    @Test func codexHasNoEnvironmentNoMCPServersAndReadsTheWebOnly() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let codexHome = fakes.home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let userConfig = codexHome.appendingPathComponent("config.toml")
        try Data("model = \"gpt-5\"\n[mcp_servers.files]\ncommand = \"npx\"\n".utf8).write(to: userConfig)
        let before = try FileManager.default.attributesOfItem(atPath: userConfig.path)[.modificationDate] as? Date
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(nil, agent: .custom)  // Automatic: Claude Code first
        fakes.set("FAKE_SIGNED_OUT", ["claude"])
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        #expect(answer(try await ask("hello", converter)) == "Codex says: hello")
        let starts = fakes.starts("codex")
        #expect(starts.count >= 2)  // the check, the session
        for start in starts {
            #expect((start["env"] as? [String: Any])?["CODEX_EXEC_SERVER_URL"] as? String == "none", "\(start)")
            let argv = start["argv"] as? [String] ?? []
            #expect(argv.first == "app-server")
        }
        let session = try #require(starts.last?["argv"] as? [String])
        let overrides = stride(from: 0, to: session.count, by: 1).compactMap { session[$0] == "-c" && $0 + 1 < session.count ? session[$0 + 1] : nil }
        for off in ["features.shell_tool=false", "features.apps=false", "features.plugins=false", "agents.enabled=false",
                    "features.multi_agent=false"] {
            #expect(overrides.contains(off), "\(off) in \(overrides)")
        }
        // The thread: read-only, never asking, every MCP server of the user's off.
        let start = try #require(fakes.received("codex").first { $0["method"] as? String == "thread/start" })
        let params = try #require(start["params"] as? [String: Any])
        #expect(params["sandbox"] as? String == "read-only" && params["approvalPolicy"] as? String == "never")
        let servers = ((params["config"] as? [String: Any])?["mcp_servers"] as? [String: Any]) ?? [:]
        #expect(Set(servers.keys) == ["files", "remote"], "\(servers)")
        #expect(servers.values.allSatisfy { ($0 as? [String: Any])?["enabled"] as? Bool == false }, "\(servers)")
        // The user's config isn't written.
        #expect(try String(contentsOf: userConfig, encoding: .utf8) == "model = \"gpt-5\"\n[mcp_servers.files]\ncommand = \"npx\"\n")
        #expect(try FileManager.default.attributesOfItem(atPath: userConfig.path)[.modificationDate] as? Date == before)
    }

    @Test func geminiHasAPolicyOfTheWebToolsOnlyAndNoMCPServer() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let userSettings = try geminiSettings(fakes, signedIn: true)
        let before = try Data(contentsOf: userSettings)
        let modified = try FileManager.default.attributesOfItem(atPath: userSettings.path)[.modificationDate] as? Date
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(nil, agent: .gemini)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        #expect(answer(try await ask("hello", converter)) == "Gemini says: hello")
        let start = try #require(fakes.sessionStarts("gemini").first)
        let argv = start["argv"] as? [String] ?? []
        func value(_ flag: String) -> String? { argv.firstIndex(of: flag).map { argv[$0 + 1] } }
        let folder = fakes.root.appendingPathComponent("gemini-session")
        let policy = try #require(value("--policy"))
        #expect(URL(fileURLWithPath: policy).resolvingSymlinksInPath().path
                == folder.appendingPathComponent("allinoneime-policy.toml").resolvingSymlinksInPath().path)
        // The policy allows the two web tools and nothing else.
        let text = try String(contentsOfFile: policy, encoding: .utf8)
        let rules = text.components(separatedBy: "[[rule]]").dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let allows = rules.filter { $0.contains(#"decision = "allow""#) }
        #expect(allows.count == 1 && allows[0].contains(#""web_fetch""#) && allows[0].contains(#""google_web_search""#), "\(rules)")
        #expect(allows.allSatisfy { !$0.contains("read_file") && !$0.contains("run_shell_command") && !$0.contains("\"*\"") })
        #expect(rules.contains { $0.contains(#"toolName = "*""#) && $0.contains(#"decision = "deny""#) }, "\(rules)")
        // A server name none of the user's has.
        let names = try #require(value("--allowed-mcp-server-names"))
        let userServers = ((try JSONSerialization.jsonObject(with: before) as? [String: Any])?["mcpServers"] as? [String: Any])?.keys
        #expect(!names.isEmpty && !(userServers.map(Array.init) ?? []).contains(names))
        #expect(value("--extensions") == "none")
        #expect((start["env"] as? [String: Any])?["GEMINI_CLI_NO_RELAUNCH"] as? String == "true")
        // The user's settings aren't written.
        #expect(try Data(contentsOf: userSettings) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: userSettings.path)[.modificationDate] as? Date == modified)
    }

    @Test func kiroRunsInAnAgentWithTheWebToolsOnly() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(nil, agent: .kiro)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        #expect(answer(try await ask("hello", converter)) == "Kiro says: hello")
        let received = fakes.received("kiro-cli")
        let mode = try #require(received.first { $0["method"] as? String == "session/set_mode" })
        let modeID = try #require((mode["params"] as? [String: Any])?["modeId"] as? String)
        let agentFile = fakes.root.appendingPathComponent("kiro-session/.kiro/agents/\(modeID).json")
        let agent = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: agentFile)) as? [String: Any])
        #expect(Set(agent["tools"] as? [String] ?? []) == ["web_search", "web_fetch"])
        #expect(Set(agent["allowedTools"] as? [String] ?? []).isSubset(of: ["web_search", "web_fetch"]))
        #expect((agent["mcpServers"] as? [String: Any])?.isEmpty == true && agent["includeMcpJson"] as? Bool == false)
        let new = try #require(received.first { $0["method"] as? String == "session/new" })
        #expect(((new["params"] as? [String: Any])?["mcpServers"] as? [Any])?.isEmpty == true)
        // No file system for the agent.
        let initialize = try #require(received.first { $0["method"] as? String == "initialize" })
        let fs = ((initialize["params"] as? [String: Any])?["clientCapabilities"] as? [String: Any])?["fs"] as? [String: Any]
        #expect(fs?["readTextFile"] as? Bool != true && fs?["writeTextFile"] as? Bool != true)
    }

    /// One session's program is started (by the real launcher) with none of another's pipes: on quit each one's input
    /// ends.
    @Test func aSessionsProcessHoldsNoOtherDescriptors() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        let s = sessions(fakes, real: true)
        defer { s.stop() }
        for backend in [QuestionBackend.claudeSession, .codexSession, .geminiSession, .kiroSession] {
            let settings = config(backend)
            let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
            _ = try await ask("hello", converter)
        }
        for program in FakeAgentCLIs.programs {
            for start in fakes.sessionStarts(program) {
                #expect((start["fds"] as? [Int] ?? [0]).isEmpty, "\(program) inherited \(String(describing: start["fds"]))")
            }
        }
    }

    // MARK: - 6. Esc, and what the agent asks

    @Test func escInterruptsTheAnswerInEveryBackendAndTheProcessStays() async throws {
        try await withInterfaceLanguage("en") {
            let fakes = try FakeAgentCLIs()
            defer { fakes.cleanUp() }
            _ = try geminiSettings(fakes, signedIn: true)
            fakes.set("FAKE_HANG", FakeAgentCLIs.programs)
            let s = sessions(fakes)
            defer { s.stop() }
            for (backend, program) in [(QuestionBackend.claudeSession, "claude"), (.codexSession, "codex"),
                                       (.geminiSession, "gemini"), (.kiroSession, "kiro-cli")] {
                let settings = Settings(config(backend))
                let host = host(settings, s)
                host.press(FakeHost.at)
                host.type("question")
                host.press(FakeHost.tab)
                host.type("what is rust")
                host.press(FakeHost.enter)
                #expect(host.settle(timeout: 30) { String(describing: host.panel).contains("Partial") }, "\(program): no partial answer")
                host.press(FakeHost.escape)
                let interrupted = settled(20) {
                    let lines = fakes.received(program)
                    switch program {
                    case "claude":
                        return lines.contains { ($0["request"] as? [String: Any])?["subtype"] as? String == "interrupt" }
                    case "codex":
                        return lines.contains { line in
                            guard line["method"] as? String == "turn/interrupt", let p = line["params"] as? [String: Any] else { return false }
                            return p["threadId"] as? String == "thr_fake_1" && p["turnId"] as? String == "turn_1"
                        }
                    default:
                        return lines.contains { line in
                            line["method"] as? String == "session/cancel" && line["id"] == nil
                                && (line["params"] as? [String: Any])?["sessionId"] as? String == "sess_fake_1"
                        }
                    }
                }
                #expect(interrupted, "\(program): \(fakes.received(program).suffix(3))")
                // The process stays: the next question goes to it.
                #expect(fakes.sessionStarts(program).count == 1, "\(program)")
                #expect(s[backend.agent!].isRunning, "\(program)")
            }
        }
    }

    @Test func whatAnAgentAsksIsAlwaysDenied() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        _ = try geminiSettings(fakes, signedIn: true)
        fakes.set("FAKE_PERMISSION", FakeAgentCLIs.programs)
        let s = sessions(fakes)
        defer { s.stop() }
        for backend in [QuestionBackend.claudeSession, .codexSession, .geminiSession, .kiroSession] {
            let settings = config(backend)
            let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
            _ = try await ask("hello", converter)
        }
        // Claude Code: the can_use_tool request denied.
        #expect(await Timing.eventually(within: 10) { fakes.received("claude").contains { $0["type"] as? String == "control_response" } })
        let claude = try #require(fakes.received("claude").first { $0["type"] as? String == "control_response" })
        let response = claude["response"] as? [String: Any]
        #expect(response?["request_id"] as? String == "perm-1")
        #expect((response?["response"] as? [String: Any])?["behavior"] as? String == "deny", "\(claude)")
        // Codex: every approval declined, anything else refused.
        #expect(await Timing.eventually(within: 10) { fakes.received("codex").filter { $0["method"] == nil && $0["id"] != nil }.count >= 4 })
        let codex = Dictionary(fakes.received("codex").filter { $0["method"] == nil }.compactMap { line in
            (line["id"] as? Int).map { ($0, line) }
        }) { first, _ in first }
        for id in [900, 901, 902, 903] {
            let reply = try #require(codex[id], "codex request \(id) unanswered")
            let decision = (reply["result"] as? [String: Any])?["decision"] as? String
            #expect(reply["error"] != nil || decision == "decline" || decision == "denied", "\(id): \(reply)")
            #expect(decision != "accept" && decision != "approved" && decision != "acceptForSession", "\(id): \(reply)")
        }
        // ACP: the permission never allowed, the file and the terminal refused.
        for program in ["gemini", "kiro-cli"] {
            #expect(await Timing.eventually(within: 10) { fakes.received(program).filter { $0["method"] == nil }.count >= 3 })
            let replies = Dictionary(fakes.received(program).filter { $0["method"] == nil }.compactMap { line in
                (line["id"] as? Int).map { ($0, line) }
            }) { first, _ in first }
            let permission = try #require(replies[700], "\(program): permission unanswered")
            let outcome = ((permission["result"] as? [String: Any])?["outcome"] as? [String: Any])
            #expect(outcome?["outcome"] as? String == "cancelled" || outcome?["optionId"] as? String == "reject", "\(program): \(permission)")
            #expect(outcome?["optionId"] as? String != "allow")
            #expect(replies[701]?["error"] != nil && replies[702]?["error"] != nil, "\(program): \(replies)")
        }
    }

    // MARK: - Found in review

    /// The real launcher (`ProcessClaudeSessionLauncher`) says each time that a program ended: a program that exits at
    /// once (a CLI that fails to start, `claude auth status`, `kiro-cli whoami`) is seen to end within seconds, every time.
    @Test func theRealLauncherSeesEveryExit() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        fakes.set("FAKE_FAIL_START", ["claude"])
        let launcher = fakes.realLauncher(ClaudeCodeBackend())
        var missed: [String] = []
        for run in 0..<60 {
            let seen = Locked(initialState: false)
            let process = try launcher.start(["-p", "--session-id", "x"], in: fakes.root, output: { _ in },
                                             exited: { _, _ in seen.withLock { $0 = true } })
            defer { process.terminate() }
            if !(await Timing.eventually(within: 10) { seen.withLock { $0 } }) {
                let exits = fakes.log("claude").filter { $0["kind"] as? String == "exit" }.count
                missed.append("run \(run): no exit seen in 10 s (the program logged \(exits) of \(run + 1) exits)")
                break
            }
        }
        #expect(missed.isEmpty, "\(missed)")
    }

    /// What that means for the user: Claude Code signed in is found signed in each time Settings looks (a sign-in check
    /// whose end isn't seen counts as signed out after `checkTimeout`, 15 s).
    @Test func aSignedInClaudeIsFoundSignedInEachTime() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        let s = sessions(fakes, real: true)
        defer { s.stop() }
        var found: [ClaudeSession.Availability] = []
        for _ in 0..<60 {
            found.append(await s[.claude].checkAvailability(force: true))
            if found.last != .ready { break }
        }
        #expect(found.allSatisfy { $0 == .ready }, "\(found) after \(fakes.checks("claude")) checks")
    }


    /// Esc while the sign-in is still being looked at (the first question, Automatic): the question given up is never
    /// sent to the agent.
    @Test func escWhileTheSignInIsLookedAtSendsNothing() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        fakes.set("FAKE_AUTH_SLOW", ["claude"])
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(nil, agent: .claude)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["P"]), questionSessions: s.all)
        let asking = Task { try await ask("my private question", converter) }
        #expect(await Timing.eventually(within: 20) { fakes.checks("claude") == 1 })
        asking.cancel()  // Esc
        _ = try? await asking.value
        #expect(await Timing.eventually(within: 30) { fakes.log("claude").contains { $0["kind"] as? String == "exit" } })
        try await Task.sleep(for: .seconds(1))
        let sent = fakes.received("claude").contains { line in
            ((line["message"] as? [String: Any])?["content"] as? String)?.contains("my private question") == true
        }
        #expect(!sent, "the question was sent after Esc: \(fakes.received("claude"))")
    }

    /// A turn the agent never ends (stuck after its first words, deaf to the interrupt) doesn't hold up every later
    /// question: the next one is answered (by the session or, saying why, the provider).
    @Test func aTurnThatNeverEndsDoesNotHoldUpTheNextQuestion() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        fakes.set("FAKE_HANG", ["claude"])
        fakes.set("FAKE_IGNORE_INTERRUPT", ["claude"])
        let s = sessions(fakes, firstAnswerTimeout: .seconds(2))
        defer { s.stop() }
        let settings = config(.claudeSession)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["From the provider."]),
                                  questionSessions: s.all)
        let first = Task { try await ask("one", converter) }
        #expect(await Timing.eventually(within: 20) { fakes.received("claude").contains { $0["type"] as? String == "user" } })
        try await Task.sleep(for: .milliseconds(500))
        first.cancel()  // Esc
        _ = try? await first.value
        let finished = Locked<String?>(initialState: nil)
        let second = Task {
            do {
                let update = try await ask("two", converter)
                finished.withLock { $0 = "answered: \(update?.result.versions.first?.text ?? "")" }
            } catch {
                finished.withLock { $0 = "failed: \(error)" }
            }
        }
        let done = await Timing.eventually(within: 20) { finished.withLock { $0 } != nil }
        #expect(done, "the second question is still waiting behind the first")
        second.cancel()
    }

    /// Kiro CLI without the input method's web-only agent (a Kiro that didn't take its agent file): the session isn't
    /// asked in Kiro's default agent, which has the file tools; the provider answers and says why.
    @Test func kiroWithoutItsWebOnlyAgentIsNotAsked() async throws {
        let fakes = try FakeAgentCLIs()
        defer { fakes.cleanUp() }
        fakes.set("FAKE_NO_MODE", ["kiro-cli"])
        let s = sessions(fakes)
        defer { s.stop() }
        let settings = config(.kiroSession)
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["From the provider."]),
                                  questionSessions: s.all)
        var update: ConversionUpdate?
        do { update = try await ask("hello", converter) } catch {}
        #expect(!fakes.methods("kiro-cli").contains("session/prompt"), "asked in Kiro's default agent: \(fakes.methods("kiro-cli"))")
        #expect(answer(update) == "From the provider.", "\(String(describing: answer(update)))")
    }

    /// ⌘⏎ with the next question typed: Terminal goes on in the same session with it as the first message, interactively
    /// (the Mac's hand-off appends the follow-up as the last argument: `TerminalLauncher.agent`). Gemini CLI takes a
    /// positional prompt as a one-shot run; `-i` (as `@agent`'s `AgentKind.terminalArguments`) keeps it interactive.
    @Test func theHandOffWithAFollowUpStaysInteractive() {
        let followUp = "and what about Go?"
        let gemini = ACPBackend.gemini.terminalArguments(program: "/u/gemini", sessionID: "x", agentSessionID: "4f1c", resume: true)
            + [followUp]
        #expect(gemini.contains("--resume") && gemini.contains("4f1c"))
        let before = gemini.dropLast().last
        #expect(before == "-i" || before == "--prompt-interactive", "\(gemini) runs once and exits")
    }

    /// Whether `condition` holds within `timeout` seconds (blocking: for a FakeHost test's synchronous turn).
    func settled(_ timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        return condition()
    }
}
#endif
