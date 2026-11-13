import Foundation

/// A question session on an agent that speaks the Agent Client Protocol (ACP: JSON-RPC 2.0, a message per line on
/// stdin/stdout). Generic: each ACP agent (Kiro CLI, Gemini CLI) is one `ACPBackend` value, its launch command, folder,
/// files and sign-in check. What is sent: `initialize`, then `session/load` with the agent's id of the session when
/// there is one and the agent can load sessions (else `session/new`), then `session/set_mode` to `mode` when the agent
/// offers it, then one `session/prompt` per question; `session/cancel` stops a turn. What the agent asks (a permission,
/// a file) is refused.
///
/// Kiro CLI (3.1.0, checked by running it):
/// - `kiro-cli acp` in the folder; `initialize` says `loadSession: true`. `session/new` gives an id ("sess_…", the
///   one `kiro-cli chat --resume-id` takes); `session/load` after the process restarted has the whole conversation (it
///   replays it as `session/update`s first, before its response: not part of any answer). Unknown ids load as new ones.
/// - The folder's `.kiro/steering/*.md` are read (and the user's ~/.kiro/steering too: there is no way to leave those
///   out); its `.kiro/agents/allinoneime.json` (`kiroAgent`) is offered as the mode "allinoneime", which has only the
///   web tools, allowed without asking, and no MCP servers. A Kiro that doesn't offer it (or won't switch to it) isn't
///   asked: its default agent has the file tools (`ClaudeSessionError.notWebOnly`, the provider answers).
/// - Signed out: `session/new` fails with -32000 "Authentication required …"; `kiro-cli whoami` exits 1.
/// - ACP has no session title, and Kiro gives none: the session is found by its folder (`kiro-cli chat --resume` there
///   opens the latest session of the folder, the input method's).
///
/// Gemini CLI (0.68.0, checked by running it signed out, in its source, and signed in to a local model server that
/// records the tools it is offered):
/// - `gemini --acp`; `initialize` says `loadSession: true` (no `session/list`, no titles). `session/new` gives a UUID,
///   the one `gemini --resume` takes in the same folder (by name it can't: `--resume` takes a UUID, "latest" or a
///   number); `session/load` replays the conversation first (`user_message_chunk`s, not part of any answer), and fails
///   with -32603 for a session it no longer has (it deletes sessions idle for 30 days): a new one then.
/// - `--skip-trust`: the folder is trusted for the run; in a folder that isn't, Gemini CLI doesn't read its GEMINI.md
///   (and folder trust is on by default). `--extensions none`: none of the user's extensions (their MCP servers).
///   `GEMINI_CLI_NO_RELAUNCH`: one Node process, not a second it would start for more memory (about 250 MB more).
/// - Like Claude Code's and Kiro's sessions, it may read the web and nothing else: `--policy` with the folder's
///   allinoneime-policy.toml (`geminiPolicy`) allows `web_fetch` and `google_web_search` without asking and denies every
///   other tool, which leaves it out of what the model is offered (reading files, the shell, writing, its subagents, MCP
///   tools). `--policy` is read in place of the user's ~/.gemini/policies, as the user's tier, and at the top priority of
///   that tier, above every rule the user's settings make (`tools.allowed`, trusted MCP servers …): only an
///   administrator's policies come before it. `--allowed-mcp-server-names` with a name no server has: none of the
///   user's MCP servers starts. In Terminal (the hand-off) Gemini CLI has none of these: the file isn't where it looks.
///   A follow-up goes there as `-i`'s value: a prompt alone Gemini CLI answers once and exits.
/// - The folder's GEMINI.md is read (and the user's ~/.gemini/GEMINI.md too: there is no way to leave that out).
/// - Signed out: `session/new` and `session/load` fail with -32000 ("Gemini API key is missing or not configured.",
///   "Authentication required"). There is no command that says whether it is signed in, and starting it with a Google
///   login whose saved credentials are gone opens a browser and waits: the check reads its settings and files instead
///   (`geminiSignedIn`), and never starts it.
public struct ACPBackend: SessionBackend {
    public var agent: SessionAgent
    /// The folder's name in the data folder.
    public var folderName: String
    /// The arguments after the program that start the agent on ACP; one starting with "./" is a file of the folder,
    /// given as its full path.
    public var launch: [String]
    /// The agent's mode (its agent config) the session is put in when offered; nil: its default.
    public var mode: String?
    public var files: [SessionFile]
    /// The command that exits 0 when signed in.
    public var availability: [String]
    /// What Terminal runs after the program: `resume` + the agent's id of the session, `start` when there's none yet;
    /// then `followUp` before a follow-up (`SessionBackend.terminalArguments`).
    public var resume: [String]
    public var start: [String]
    public var followUp: [String]
    /// The data folder, the sessions' parent (tests: their own).
    public var base: URL?
    /// What the agent's process needs in its environment besides the user's.
    public var environment: [String: String]
    /// Whether it is signed in, read from its files without running it (`signedIn(environment:home:)`); nil: the
    /// `availability` command says.
    public var signIn: (@Sendable (_ environment: [String: String], _ home: URL) -> Bool)?

    public init(agent: SessionAgent, folderName: String, launch: [String], mode: String? = nil, files: [SessionFile] = [],
                availability: [String], resume: [String], start: [String], followUp: [String] = ["--"], base: URL? = nil,
                environment: [String: String] = [:],
                signIn: (@Sendable (_ environment: [String: String], _ home: URL) -> Bool)? = nil) {
        self.agent = agent
        self.folderName = folderName
        self.launch = launch
        self.mode = mode
        self.files = files
        self.availability = availability
        self.resume = resume
        self.start = start
        self.followUp = followUp
        self.base = base
        self.environment = environment
        self.signIn = signIn
    }

    /// The mode Kiro's session runs in (`kiroAgent`).
    public static let kiroMode = "allinoneime"

    /// Kiro's agent config for the session: the web tools only (allowed without asking: `permissions`, which Kiro's v3
    /// engine reads, `allowedTools` the v2 one), no MCP servers, the folder's steering.
    public static let kiroAgent = """
        {
          "name": "allinoneime",
          "description": "The input method's own session: answers questions, may read the web, nothing else.",
          "tools": ["web_search", "web_fetch"],
          "allowedTools": ["web_search", "web_fetch"],
          "resources": ["file://.kiro/steering/**/*.md"],
          "mcpServers": {},
          "includeMcpJson": false,
          "permissions": {
            "rules": [
              {"capability": "web_fetch", "effect": "allow"},
              {"capability": "web_search", "effect": "allow"}
            ]
          }
        }

        """

    /// Kiro CLI on ACP.
    public static let kiro = ACPBackend(
        agent: .kiro, folderName: "kiro-session", launch: ["acp"], mode: kiroMode,
        files: [SessionFile(path: ".kiro/steering/allinoneime.md", content: ClaudeSession.instructions),
                SessionFile(path: ".kiro/agents/allinoneime.json", content: kiroAgent)],
        availability: ["whoami", "-f", "json"], resume: ["chat", "--resume-id"], start: ["chat"])

    /// Gemini CLI's policy for the session (its policy engine's TOML, priorities 0–999 within a tier): the web tools
    /// allowed without asking, every other tool denied, so left out.
    public static let geminiPolicy = """
        # AllInOneIME's own Gemini CLI session (gemini --acp --policy this file): it may read the web, nothing else.
        [[rule]]
        toolName = ["web_fetch", "google_web_search"]
        decision = "allow"
        priority = 999

        [[rule]]
        toolName = "*"
        decision = "deny"
        priority = 998

        """

    /// The name `--allowed-mcp-server-names` is given: no MCP server has it, so none starts.
    public static let noMCPServer = "allinoneime-no-mcp-servers"

    /// Gemini CLI on ACP, in its own folder with the instructions as its GEMINI.md and its policy.
    public static let gemini = ACPBackend(
        agent: .gemini, folderName: "gemini-session",
        launch: ["--acp", "--skip-trust", "--extensions", "none", "--allowed-mcp-server-names", noMCPServer,
                 "--policy", "./allinoneime-policy.toml"],
        files: [SessionFile(path: "GEMINI.md", content: ClaudeSession.instructions),
                SessionFile(path: "allinoneime-policy.toml", content: geminiPolicy)],
        availability: [], resume: ["--resume"], start: [], followUp: ["-i"],
        environment: ["GEMINI_CLI_NO_RELAUNCH": "true"], signIn: geminiSignedIn)

    /// Whether Gemini CLI is signed in, as its settings and files say (in `home`, or the GEMINI_CLI_HOME of
    /// `environment`): the sign-in its settings pick (`security.auth.selectedType`; the system's enforced or picked one
    /// first, then the user's; `selectedAuthType` in settings from before 0.3). A Google login: its saved credentials (a
    /// refresh token) are there. An API key or Vertex AI picked: signed in (the key may be in the environment, a .env or
    /// the keychain, where Gemini CLI's own dialog keeps it). Another sign-in the user set up (a gateway …): signed in.
    /// None picked: Gemini CLI uses an API key, so signed in when GEMINI_API_KEY is set (in `environment` or
    /// ~/.gemini/.env, ~/.env) or a gateway is (GOOGLE_GEMINI_BASE_URL).
    public static func geminiSignedIn(environment: [String: String], home: URL) -> Bool {
        let configured = environment["GEMINI_CLI_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let folder = (configured ?? home).appendingPathComponent(".gemini", isDirectory: true)
        func object(_ url: URL) -> [String: Any]? {
            (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        func picked(_ settings: [String: Any]?, enforced: Bool) -> String? {
            let auth = (settings?["security"] as? [String: Any])?["auth"] as? [String: Any]
            let keys = (enforced ? [auth?["enforcedType"]] : []) + [auth?["selectedType"], settings?["selectedAuthType"]]
            return keys.lazy.compactMap { $0 as? String }.first { !$0.isEmpty }
        }
        let system = object(URL(fileURLWithPath: "/Library/Application Support/GeminiCli/settings.json"))
        let user = object(folder.appendingPathComponent("settings.json"))
        func set(_ name: String) -> Bool { environment[name].map { !$0.isEmpty } ?? false }
        switch picked(system, enforced: true) ?? picked(user, enforced: false) {
        case "oauth-personal":
            let saved = object(folder.appendingPathComponent("oauth_creds.json"))?["refresh_token"] as? String
            return saved?.isEmpty == false || set("GOOGLE_APPLICATION_CREDENTIALS")
                || FileManager.default.fileExists(atPath: folder.appendingPathComponent("gemini-credentials.json").path)
        case nil:
            let dotEnv = [folder.appendingPathComponent(".env"), (configured ?? home).appendingPathComponent(".env")]
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .contains { $0.split(whereSeparator: \.isNewline).contains { line in
                    let line = line.trimmingCharacters(in: .whitespaces)
                    return (line.hasPrefix("GEMINI_API_KEY=") || line.hasPrefix("export GEMINI_API_KEY="))
                        && !line.hasSuffix("=")
                } }
            return set("GEMINI_API_KEY") || set("GOOGLE_GEMINI_BASE_URL") || dotEnv
        default:
            return true
        }
    }

    public var directory: URL { (base ?? CorePaths.dataDir).appendingPathComponent(folderName, isDirectory: true) }
    public var usesProviderSettings: Bool { false }
    public var retryTogglesResume: Bool { false }

    public func arguments(sessionID: String, resume: Bool, settings: URL?) -> [String] {
        launch.map { $0.hasPrefix("./") ? directory.appendingPathComponent(String($0.dropFirst(2))).path : $0 }
    }

    public func driver(sessionID: String, agentSessionID: String?, resume: Bool, directory: URL) -> any SessionDriver {
        ACPDriver(directory: directory, agentSessionID: agentSessionID, mode: mode)
    }

    public func availabilityArguments(settings: URL?) -> [String] { availability }

    public func signedIn(environment: [String: String], home: URL) -> Bool? { signIn?(environment, home) }

    public func signedIn(status: Int32, output: Data) -> Bool? { status == 0 }

    public func terminalArguments(program: String, sessionID: String, agentSessionID: String?, resume: Bool,
                                  followUp: Bool) -> [String] {
        [program] + (agentSessionID.map { self.resume + [$0] } ?? start) + (followUp ? self.followUp : [])
    }
}

/// One ACP process: the handshake, then the prompts, as `ACPBackend` says.
final class ACPDriver: SessionDriver {
    private enum Request {
        case initialize, load, new, setMode, prompt
    }

    private let directory: URL
    private let mode: String?
    /// The agent's id of the session: the one to load, then the one open.
    private var agentSessionID: String?
    /// The session is open (loaded or new, in its mode): prompts go.
    private var ready = false
    private var serial = 0
    private var requests: [Int: Request] = [:]
    /// A message waiting for the session to open, and whether it was stopped meanwhile.
    private var queued: String?
    private var queuedCancelled = false
    /// The prompt being answered.
    private var prompting = false

    init(directory: URL, agentSessionID: String?, mode: String?) {
        self.directory = directory
        self.agentSessionID = agentSessionID
        self.mode = mode
    }

    func opening() -> [Data] {
        [request(.initialize, "initialize", ["protocolVersion": 1,
                                             "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false]]])]
    }

    func message(_ text: String) -> [Data] {
        guard ready else {
            (queued, queuedCancelled) = (text, false)
            return []
        }
        return [prompt(text)]
    }

    func interrupt() -> [Data] {
        if prompting, let agentSessionID {
            return [ClaudeSession.line(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": agentSessionID]])]
        }
        if queued != nil { queuedCancelled = true }
        return []
    }

    func received(_ line: Data) -> (events: [ClaudeSession.Event], replies: [Data]) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return ([], []) }
        let method = object["method"] as? String
        // What the agent asks: refused (a tool's permission: cancelled, i.e. denied; anything else: no such method).
        if let method, let id = object["id"] {
            let answer: [String: Any] = method == "session/request_permission"
                ? ["result": ["outcome": ["outcome": "cancelled"]]]
                : ["error": ["code": -32601, "message": "Not supported by the input method"]]
            return ([.permissionRequest(id: "\(id)")], [ClaudeSession.line(["jsonrpc": "2.0", "id": id].merging(answer) { $1 })])
        }
        if let method {
            guard method == "session/update", prompting, let params = object["params"] as? [String: Any],
                  params["sessionId"] as? String == agentSessionID,
                  let update = params["update"] as? [String: Any] else { return ([], []) }
            return ([Self.event(update)], [])
        }
        guard let id = object["id"] as? Int, let request = requests.removeValue(forKey: id) else { return ([], []) }
        let result = object["result"] as? [String: Any]
        let error = object["error"] as? [String: Any]
        return response(request, result: result, error: error)
    }

    /// What a `session/update` says.
    static func event(_ update: [String: Any]) -> ClaudeSession.Event {
        switch update["sessionUpdate"] as? String {
        case "agent_message_chunk":
            guard let content = update["content"] as? [String: Any], content["type"] as? String == "text",
                  let text = content["text"] as? String else { return .working }
            return .text(text)
        case "tool_call":
            return .messageStarted  // after a tool, the answer starts again
        case "agent_thought_chunk", "tool_call_update", "plan":
            return .working
        default:
            return .other
        }
    }

    private func response(_ kind: Request, result: [String: Any]?,
                          error: [String: Any]?) -> (events: [ClaudeSession.Event], replies: [Data]) {
        let failure = error.map(Self.error)
        switch kind {
        case .initialize:
            if let failure { return ([.failed(failure, endsProcess: true)], []) }
            let capabilities = result?["agentCapabilities"] as? [String: Any]
            if let agentSessionID, capabilities?["loadSession"] as? Bool == true {
                return ([], [request(.load, "session/load", ["sessionId": agentSessionID, "cwd": directory.path, "mcpServers": []])])
            }
            return ([], [newSession()])
        case .load:
            if let failure {
                // Signed out says so; any other failure: a new session (the old one is gone).
                if failure == .signedOut { return ([.failed(failure, endsProcess: true)], []) }
                return ([], [newSession()])
            }
            return opened(result)
        case .new:
            if let failure { return ([.failed(failure, endsProcess: true)], []) }
            guard let id = result?["sessionId"] as? String, !id.isEmpty else {
                return ([.failed(.failed("No session id"), endsProcess: true)], [])
            }
            agentSessionID = id
            let (events, replies) = opened(result)
            return ([.sessionID(id)] + events, replies)
        case .setMode:
            // Not in its mode: not asked in the agent's default one.
            if failure != nil { return ([.failed(.notWebOnly, endsProcess: true)], []) }
            return becameReady()
        case .prompt:
            prompting = false
            if let failure { return ([.failed(failure, endsProcess: false)], []) }
            let cancelled = result?["stopReason"] as? String == "cancelled"
            return ([.result(error: false, interrupted: cancelled, text: "", status: nil)], [])
        }
    }

    /// The session is open: into its mode first when it isn't in it. An agent that doesn't offer the mode (or says no
    /// modes at all) isn't asked: the session would run in its default one, with more tools than the web.
    private func opened(_ result: [String: Any]?) -> (events: [ClaudeSession.Event], replies: [Data]) {
        guard let mode else { return becameReady() }
        let modes = result?["modes"] as? [String: Any]
        if modes?["currentModeId"] as? String == mode { return becameReady() }
        let offered = (modes?["availableModes"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        guard offered.contains(mode), let agentSessionID else { return ([.failed(.notWebOnly, endsProcess: true)], []) }
        return ([], [request(.setMode, "session/set_mode", ["sessionId": agentSessionID, "modeId": mode])])
    }

    private func becameReady() -> (events: [ClaudeSession.Event], replies: [Data]) {
        ready = true
        guard let text = queued else { return ([.started], []) }
        queued = nil
        if queuedCancelled { return ([.started, .result(error: false, interrupted: true, text: "", status: nil)], []) }
        return ([.started], [prompt(text)])
    }

    private func newSession() -> Data {
        request(.new, "session/new", ["cwd": directory.path, "mcpServers": []])
    }

    private func prompt(_ text: String) -> Data {
        prompting = true
        return request(.prompt, "session/prompt", ["sessionId": agentSessionID ?? "", "prompt": [["type": "text", "text": text]]])
    }

    private func request(_ kind: Request, _ method: String, _ params: [String: Any]) -> Data {
        serial += 1
        requests[serial] = kind
        return ClaudeSession.line(["jsonrpc": "2.0", "id": serial, "method": method, "params": params])
    }

    /// A JSON-RPC error as the session's: not signed in (ACP's auth_required, -32000, or its words), else its message.
    static func error(_ error: [String: Any]) -> ClaudeSessionError {
        let message = error["message"] as? String ?? ""
        let text = message.lowercased()
        if error["code"] as? Int == -32000 || text.contains("authentication required") || text.contains("not logged in") {
            return .signedOut
        }
        return .failed(message)
    }
}
