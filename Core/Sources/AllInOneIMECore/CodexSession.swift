import Foundation

/// A question session on Codex, over its app server (`codex app-server`: JSON-RPC on stdin/stdout, a message per line,
/// without a "jsonrpc" field). What is sent: `initialize` and `initialized`; `thread/resume` with the thread kept (the
/// agent's id of the session, `ClaudeSessionStore.agentSessionID`), else, or when that fails, `thread/start` in the
/// session's folder, read-only and never asking for approval, then `thread/name/set` to "AllInOneIME"
/// (`SessionAgent.sessionName`); one `turn/start` per question, `turn/interrupt` to stop one. What the server asks
/// (an approval for a command, a file change, a patch; anything else) is refused.
///
/// Codex 0.163 (checked with `codex app-server generate-json-schema` and by running it):
/// - The answer comes as `item/agentMessage/delta` notifications (`delta`, per `itemId`: a new item after a tool starts
///   the answer again); the turn ends with `turn/completed`, its `turn.status` "completed", "interrupted" or "failed"
///   (`turn.error`: `message`, `codexErrorInfo`). `turn/start`'s response has the turn's id, which `turn/interrupt` takes.
/// - The thread's name is its title in Codex's own list; `codex resume AllInOneIME` opens it by that name.
/// - The folder's AGENTS.md is read as the session's instructions (and the user's ~/.codex/AGENTS.md too: there is no
///   way to leave that out).
/// - Signed in or not: `account/read` (`account`: an API key, a ChatGPT login or Amazon Bedrock; null when signed out,
///   unless `requiresOpenaiAuth` is false: a provider of the user's own). The server exits when its input closes, before
///   it answers: the check writes its requests and is ended once the answer is read.
public struct CodexBackend: SessionBackend {
    /// The data folder, the session's parent (tests: their own).
    public var base: URL?

    public init(base: URL? = nil) {
        self.base = base
    }

    public var agent: SessionAgent { .codex }
    public var directory: URL { (base ?? CorePaths.dataDir).appendingPathComponent("codex-session", isDirectory: true) }
    public var files: [SessionFile] { [SessionFile(path: "AGENTS.md", content: ClaudeSession.instructions)] }
    public var usesProviderSettings: Bool { false }
    public var retryTogglesResume: Bool { false }

    public func arguments(sessionID: String, resume: Bool, settings: URL?) -> [String] { ["app-server"] }

    public func driver(sessionID: String, agentSessionID: String?, resume: Bool, directory: URL) -> any SessionDriver {
        CodexDriver(directory: directory, threadID: agentSessionID)
    }

    public func availabilityArguments(settings: URL?) -> [String] { ["app-server"] }

    /// The id of `account/read` in the sign-in check.
    static let accountRequest = 2

    public var availabilityInput: [Data] {
        [CodexDriver.line(["id": 1, "method": "initialize", "params": CodexDriver.initializeParams]),
         CodexDriver.line(["method": "initialized"]),
         CodexDriver.line(["id": Self.accountRequest, "method": "account/read", "params": [:] as [String: Any]])]
    }

    public func signedIn(line: Data) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["method"] == nil, object["id"] as? Int == Self.accountRequest else { return nil }
        guard let result = object["result"] as? [String: Any] else { return false }
        return result["account"] is [String: Any] || result["requiresOpenaiAuth"] as? Bool == false
    }

    public func signedIn(status: Int32, output: Data) -> Bool? { nil }

    public func terminalArguments(program: String, sessionID: String, agentSessionID: String?, resume: Bool) -> [String] {
        [program] + (agentSessionID.map { ["resume", $0] } ?? [])
    }
}

/// One `codex app-server` process: the handshake, the thread, then a turn per question, as `CodexBackend` says.
final class CodexDriver: SessionDriver {
    private enum Request {
        case initialize, resume, start, name, turn, interrupt
    }

    private let directory: URL
    /// The thread: the one to resume, then the one open.
    private var threadID: String?
    /// The thread is open: turns go.
    private var ready = false
    private var serial = 0
    private var requests: [Int: Request] = [:]
    /// A message waiting for the thread to open, and whether it was stopped meanwhile.
    private var queued: String?
    private var queuedCancelled = false
    /// The turn being answered: started (its id, once `turn/start` answered), stopped before it had one.
    private var turnStarted = false
    private var turnID: String?
    private var interruptPending = false
    /// The agent message the answer's text comes from now.
    private var messageItem: String?

    init(directory: URL, threadID: String?) {
        self.directory = directory
        self.threadID = threadID
    }

    static var initializeParams: [String: Any] { ["clientInfo": ["name": "allinoneime", "title": "AllInOneIME", "version": "1"]] }

    /// What every thread is opened with: the session's folder, read-only, nothing asked.
    private var threadParams: [String: Any] { ["cwd": directory.path, "sandbox": "read-only", "approvalPolicy": "never"] }

    func opening() -> [Data] {
        [request(.initialize, "initialize", Self.initializeParams)]
    }

    func message(_ text: String) -> [Data] {
        guard ready else {
            (queued, queuedCancelled) = (text, false)
            return []
        }
        return [turn(text)]
    }

    func interrupt() -> [Data] {
        if turnStarted {
            guard let turnID, let threadID else {
                interruptPending = true
                return []
            }
            return [request(.interrupt, "turn/interrupt", ["threadId": threadID, "turnId": turnID])]
        }
        if queued != nil { queuedCancelled = true }
        return []
    }

    func received(_ line: Data) -> (events: [ClaudeSession.Event], replies: [Data]) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return ([], []) }
        let method = object["method"] as? String
        if let method, let id = object["id"] {
            return ([.permissionRequest(id: "\(id)")], [Self.line(["id": id].merging(Self.refusal(method)) { $1 })])
        }
        if let method {
            return (notification(method, object["params"] as? [String: Any] ?? [:]), [])
        }
        guard let id = object["id"] as? Int, let request = requests.removeValue(forKey: id) else { return ([], []) }
        return response(request, result: object["result"] as? [String: Any], error: object["error"] as? [String: Any])
    }

    /// The answer to what the server asks: an approval declined (a command, a file change, a patch); anything else, no
    /// such method.
    static func refusal(_ method: String) -> [String: Any] {
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            return ["result": ["decision": "decline"]]
        case "execCommandApproval", "applyPatchApproval":
            return ["result": ["decision": "denied"]]
        case "mcpServer/elicitation/request":
            return ["result": ["action": "decline"]]
        default:
            return ["error": ["code": -32601, "message": "Not supported by the input method"]]
        }
    }

    private func notification(_ method: String, _ params: [String: Any]) -> [ClaudeSession.Event] {
        guard turnStarted, params["threadId"] as? String == threadID else { return [] }
        switch method {
        case "item/agentMessage/delta":
            guard let delta = params["delta"] as? String else { return [] }
            let item = params["itemId"] as? String
            defer { messageItem = item }
            // Another message of the turn (after a tool): the answer starts again.
            return (messageItem != nil && item != messageItem ? [.messageStarted] : []) + [.text(delta)]
        case "item/started":
            let type = (params["item"] as? [String: Any])?["type"] as? String
            return type == "userMessage" ? [] : [.working]
        case "item/reasoning/summaryTextDelta", "item/reasoning/textDelta", "item/reasoning/summaryPartAdded":
            return [.working]
        case "turn/completed":
            let turn = params["turn"] as? [String: Any] ?? [:]
            (turnStarted, turnID, interruptPending, messageItem) = (false, nil, false, nil)
            switch turn["status"] as? String {
            case "interrupted":
                return [.result(error: false, interrupted: true, text: "", status: nil)]
            case "failed":
                return [.failed(Self.error(turn["error"] as? [String: Any] ?? [:]), endsProcess: false)]
            default:
                return [.result(error: false, interrupted: false, text: "", status: nil)]
            }
        default:
            return []
        }
    }

    private func response(_ kind: Request, result: [String: Any]?,
                          error: [String: Any]?) -> (events: [ClaudeSession.Event], replies: [Data]) {
        let failure = error.map(Self.error)
        switch kind {
        case .initialize:
            if let failure { return ([.failed(failure, endsProcess: true)], []) }
            let initialized = Self.line(["method": "initialized"])
            if let threadID {
                return ([], [initialized, request(.resume, "thread/resume", threadParams.merging(["threadId": threadID]) { $1 })])
            }
            return ([], [initialized, startThread()])
        case .resume:
            if let failure {
                // Signed out says so; any other failure: a new thread (the old one is gone).
                if failure == .signedOut { return ([.failed(failure, endsProcess: true)], []) }
                return ([], [startThread()])
            }
            let thread = result?["thread"] as? [String: Any]
            let named = thread?["name"] as? String == SessionAgent.sessionName
            return becameReady(naming: !named)
        case .start:
            if let failure { return ([.failed(failure, endsProcess: true)], []) }
            guard let id = (result?["thread"] as? [String: Any])?["id"] as? String, !id.isEmpty else {
                return ([.failed(.failed("No thread id"), endsProcess: true)], [])
            }
            threadID = id
            let (events, replies) = becameReady(naming: true)
            return ([.sessionID(id)] + events, replies)
        case .name, .interrupt:
            return ([], [])
        case .turn:
            if let failure {
                (turnStarted, interruptPending) = (false, false)
                return ([.failed(failure, endsProcess: false)], [])
            }
            guard turnStarted, let id = (result?["turn"] as? [String: Any])?["id"] as? String else { return ([], []) }
            turnID = id
            // Stopped before it had an id: stopped now.
            if interruptPending {
                interruptPending = false
                return ([], interrupt())
            }
            return ([], [])
        }
    }

    /// The thread is open (named "AllInOneIME" first when it isn't): the message waiting goes.
    private func becameReady(naming: Bool) -> (events: [ClaudeSession.Event], replies: [Data]) {
        ready = true
        let name = naming && threadID != nil
            ? [request(.name, "thread/name/set", ["threadId": threadID ?? "", "name": SessionAgent.sessionName])] : []
        guard let text = queued else { return ([.started], name) }
        queued = nil
        if queuedCancelled { return ([.started, .result(error: false, interrupted: true, text: "", status: nil)], name) }
        return ([.started], name + [turn(text)])
    }

    private func startThread() -> Data {
        request(.start, "thread/start", threadParams)
    }

    private func turn(_ text: String) -> Data {
        (turnStarted, turnID, interruptPending, messageItem) = (true, nil, false, nil)
        return request(.turn, "turn/start", ["threadId": threadID ?? "", "input": [["type": "text", "text": text]]])
    }

    private func request(_ kind: Request, _ method: String, _ params: [String: Any]) -> Data {
        serial += 1
        requests[serial] = kind
        return Self.line(["id": serial, "method": method, "params": params])
    }

    static func line(_ object: [String: Any]) -> Data { ClaudeSession.line(object) }

    /// A JSON-RPC error or a failed turn's error as the session's: not signed in (`codexErrorInfo` "unauthorized", or its
    /// words), the usage limit, else its message.
    static func error(_ error: [String: Any]) -> ClaudeSessionError {
        let message = error["message"] as? String ?? ""
        let info = error["codexErrorInfo"] as? String
        let text = message.lowercased()
        if info == "unauthorized" || text.contains("not logged in") || text.contains("unauthorized") || text.contains("codex login") {
            return .signedOut
        }
        if info == "usageLimitExceeded" || info == "sessionBudgetExceeded" { return .limitReached(message) }
        return .failed(message)
    }
}
