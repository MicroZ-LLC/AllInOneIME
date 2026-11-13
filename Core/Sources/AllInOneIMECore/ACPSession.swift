import Foundation

/// A question session on an agent that speaks the Agent Client Protocol (ACP: JSON-RPC 2.0, a message per line on
/// stdin/stdout). Generic: each ACP agent (Kiro CLI, Antigravity) is one `ACPBackend` value, its launch command, folder,
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
/// Antigravity (`agy acp`): `AntigravityBackend`, AntigravitySession.swift (an `ACPBackend` and `ACPDriver` with its
/// fast model and web-only check).
public struct ACPBackend: SessionBackend {
    public var agent: SessionAgent
    /// The folder's name in the data folder.
    public var folderName: String
    /// The arguments after the program that start the agent on ACP; one starting with "./" is a file of the folder,
    /// given as its full path.
    public var launch: [String]
    /// The agent's mode (its agent config) the session is put in when offered; nil: its default.
    public var mode: String?
    /// The mode (`mode`'s place) and launch (`launch`'s) of a conversation whose web tools are off (`SessionWeb`):
    /// nil, the same.
    public var offlineMode: String?
    public var offlineLaunch: [String]?
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

    public init(agent: SessionAgent, folderName: String, launch: [String], mode: String? = nil, offlineMode: String? = nil,
                offlineLaunch: [String]? = nil, files: [SessionFile] = [],
                availability: [String], resume: [String], start: [String], followUp: [String] = ["--"], base: URL? = nil,
                environment: [String: String] = [:],
                signIn: (@Sendable (_ environment: [String: String], _ home: URL) -> Bool)? = nil) {
        self.agent = agent
        self.folderName = folderName
        self.launch = launch
        self.mode = mode
        self.offlineMode = offlineMode
        self.offlineLaunch = offlineLaunch
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

    /// The mode of Kiro's session with its web tools off (`kiroOfflineAgent`).
    public static let kiroOfflineMode = "allinoneime-offline"

    /// Kiro's agent config for a conversation whose web tools are off (`SessionWeb`): no tools, no MCP servers.
    public static let kiroOfflineAgent = """
        {
          "name": "allinoneime-offline",
          "description": "The input method's own session, for a question with text the user didn't type: no tools.",
          "tools": [],
          "allowedTools": [],
          "resources": ["file://.kiro/steering/**/*.md"],
          "mcpServers": {},
          "includeMcpJson": false
        }

        """

    /// Kiro CLI on ACP.
    public static let kiro = ACPBackend(
        agent: .kiro, folderName: "kiro-session", launch: ["acp"], mode: kiroMode, offlineMode: kiroOfflineMode,
        files: [SessionFile(path: ".kiro/steering/allinoneime.md", content: ClaudeSession.instructions),
                SessionFile(path: ".kiro/agents/allinoneime.json", content: kiroAgent),
                SessionFile(path: ".kiro/agents/allinoneime-offline.json", content: kiroOfflineAgent)],
        availability: ["whoami", "-f", "json"], resume: ["chat", "--resume-id"], start: ["chat"])

    public var directory: URL { (base ?? CorePaths.dataDir).appendingPathComponent(folderName, isDirectory: true) }
    public var usesProviderSettings: Bool { false }
    public var retryTogglesResume: Bool { false }

    public func arguments(sessionID: String, resume: Bool, settings: URL?, web: SessionWeb) -> [String] {
        let launch = web == .open ? launch : offlineLaunch ?? launch
        return launch.map { $0.hasPrefix("./") ? directory.appendingPathComponent(String($0.dropFirst(2))).path : $0 }
    }

    public func driver(sessionID: String, agentSessionID: String?, resume: Bool, directory: URL, web: SessionWeb) -> any SessionDriver {
        ACPDriver(directory: directory, agentSessionID: agentSessionID, mode: web == .open ? mode : offlineMode ?? mode)
    }

    /// Its web tools off (any `only`) in its offline mode or launch; one with neither can't have them off.
    public func effective(_ web: SessionWeb) -> SessionWeb? {
        guard case .only = web else { return .open }
        return offlineMode != nil || offlineLaunch != nil ? .only([]) : nil
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

    func newConversation() -> [Data]? {
        guard ready, !prompting, queued == nil else { return nil }
        (ready, agentSessionID) = (false, nil)
        return [newSession()]
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
            let ended = ClaudeSession.Event.result(error: false, interrupted: cancelled, text: "", status: nil)
            return ((Self.usage(result).map { [.usage($0)] } ?? []) + [ended], [])
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

    /// The tokens a prompt's response says it used (`usage`: `totalTokens`, else its input and output); nil: none said.
    static func usage(_ result: [String: Any]?) -> Int? {
        guard let usage = result?["usage"] as? [String: Any] else { return nil }
        if let total = (usage["totalTokens"] as? NSNumber)?.intValue { return total }
        let counts = ["inputTokens", "outputTokens"].compactMap { (usage[$0] as? NSNumber)?.intValue }
        return counts.isEmpty ? nil : counts.reduce(0, +)
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
