import Foundation

/// Where `@question` is answered (`Config.questionBackend`): the dedicated Claude Code session on the user's Claude
/// subscription (`ClaudeSessionManager`), or the AI provider. Unset: the session when `claude` is installed and signed
/// in, else the provider. Every other request (writing, autocomplete, translating …) always goes to the provider.
public enum QuestionBackend: String, Codable, CaseIterable, Sendable {
    case claudeSession
    case provider
}

/// The input method's own long-running Claude Code session (`ClaudeSessionManager` keeps its process): one session id,
/// made once and kept in `directory`/id, in a working folder of its own whose CLAUDE.md says what it is for (so no home
/// or project CLAUDE.md is read). Every `@question` goes into it as one user message, so Claude remembers the earlier
/// ones, across days. This is what is sent and read: the arguments, the stream-json lines, the events.
///
/// The flags, checked with Claude Code 2.1.303 (`claude --help`, and by running them):
/// - `-p --input-format stream-json --output-format stream-json --verbose`: a process that stays up and takes one user
///   message per line on stdin; `--verbose` is required with stream-json output.
/// - `--include-partial-messages`: the answer's text deltas as they come (`stream_event` lines).
/// - `--session-id <id>` the first time, `--resume <id>` once it has a conversation (the first fails on an id in use,
///   the second on one that has none).
/// - `--tools WebSearch,WebFetch`: the only tools it has; `--allowedTools WebSearch,WebFetch` with `--permission-mode
///   dontAsk`: those run without asking and anything else is denied (without `--allowedTools`, dontAsk denies them too).
/// - `--setting-sources project`: the session folder's settings and CLAUDE.md only (not ~/.claude/CLAUDE.md or the
///   user's settings and hooks); `--strict-mcp-config`: no MCP servers.
public enum ClaudeSession {
    /// The session's folder: ~/Library/Application Support/AllInOneIME/claude-session on the Mac.
    public static var directory: URL { CorePaths.dataDir.appendingPathComponent("claude-session", isDirectory: true) }

    /// The CLAUDE.md written into the session's folder when it has none (the user may edit it).
    public static let instructions = """
        You are the assistant inside an input method. Answer short, ready to paste, in the language of the question.
        Earlier messages in this session are earlier questions from the same user.
        Write plain text: your answer is inserted at the user's cursor as it is, so no Markdown (no headings, bold, tables \
        or code fences) and no preamble. When a question needs current facts, you may search the web (WebSearch, WebFetch).

        """

    /// The tools the session has: reading the web, nothing else.
    public static let tools = "WebSearch,WebFetch"

    /// The arguments after `claude` that start (or resume) the session's process.
    public static func arguments(sessionID: String, resume: Bool) -> [String] {
        ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            + (resume ? ["--resume", sessionID] : ["--session-id", sessionID])
            + ["--tools", tools, "--allowedTools", tools, "--permission-mode", "dontAsk",
               "--setting-sources", "project", "--strict-mcp-config"]
    }

    /// What Terminal runs to go on in the session (the hand-off): Claude Code, interactive, on the same session, with all
    /// of its history (`--session-id` while it has none yet).
    public static func terminalArguments(claude: String, sessionID: String, resume: Bool) -> [String] {
        [claude] + (resume ? ["--resume", sessionID] : ["--session-id", sessionID])
    }

    // MARK: - Lines sent

    /// One user message, as a stream-json line.
    public static func userMessage(_ text: String) -> Data {
        line(["type": "user", "message": ["role": "user", "content": text]])
    }

    /// Stops the turn being answered; the process stays (`control_request` "interrupt").
    public static func interrupt(requestID: String) -> Data {
        line(["type": "control_request", "request_id": requestID, "request": ["subtype": "interrupt"]])
    }

    /// The answer to a permission request (there should be none with dontAsk): denied.
    public static func deny(requestID: String) -> Data {
        line(["type": "control_response",
              "response": ["subtype": "success", "request_id": requestID,
                           "response": ["behavior": "deny", "message": "Not allowed in the input method's session"]]])
    }

    static func line(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    // MARK: - Lines read

    /// What one line of the process's output says, as far as the input method cares.
    public enum Event: Equatable, Sendable {
        /// The turn started (`system` "init").
        case started
        /// A new model message began in the turn (after a tool's result, the answer starts again).
        case messageStarted
        /// Some of the answer's text.
        case text(String)
        /// The model call failed (signed out, the usage limit …): `assistant` with an `error`.
        case apiError(code: String, message: String)
        /// The turn ended (`result`): `error` false with its text, or how it failed; `interrupted`: stopped by an interrupt.
        case result(error: Bool, interrupted: Bool, text: String, status: Int?)
        /// Claude Code asks whether a tool may run: answered with `deny`.
        case permissionRequest(id: String)
        case other
    }

    /// The event in one line of output (`other` for anything else, a line that isn't JSON too).
    public static func event(_ line: Data) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return .other }
        switch object["type"] as? String {
        case "system":
            return object["subtype"] as? String == "init" ? .started : .other
        case "stream_event":
            // A subagent's text (`parent_tool_use_id`) isn't the answer.
            guard object["parent_tool_use_id"] is NSNull || object["parent_tool_use_id"] == nil,
                  let event = object["event"] as? [String: Any] else { return .other }
            switch event["type"] as? String {
            case "message_start": return .messageStarted
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String else { return .other }
                return .text(text)
            default: return .other
            }
        case "assistant":
            guard let code = object["error"] as? String else { return .other }
            let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
            return .apiError(code: code, message: text)
        case "result":
            let error = object["is_error"] as? Bool ?? (object["subtype"] as? String != "success")
            let interrupted = object["terminal_reason"] as? String == "aborted_streaming"
                || object["terminal_reason"] as? String == "aborted_tools"
            return .result(error: error, interrupted: interrupted, text: object["result"] as? String ?? "",
                           status: object["api_error_status"] as? Int)
        case "control_request":
            guard let request = object["request"] as? [String: Any], request["subtype"] as? String == "can_use_tool",
                  let id = object["request_id"] as? String else { return .other }
            return .permissionRequest(id: id)
        default:
            return .other
        }
    }

    /// Whether `claude auth status` (JSON) says it is signed in; nil when it can't be read.
    public static func signedIn(authStatus: Data) -> Bool? {
        (try? JSONSerialization.jsonObject(with: authStatus) as? [String: Any])?["loggedIn"] as? Bool
    }

    /// Whether `claude` can answer questions here, as last looked at (`ClaudeSessionManager.availability`).
    public enum Availability: Equatable, Sendable {
        /// Not looked at yet.
        case unknown
        case ready
        case notInstalled
        case signedOut
    }
}

/// Why the session didn't answer. `fallsBack`: before any of the answer came, the provider answers instead (with
/// `message` said in the panel).
public enum ClaudeSessionError: Error, LocalizedError, Equatable, Sendable {
    /// No `claude` command on this Mac.
    case notInstalled
    /// Claude Code isn't signed in.
    case signedOut
    /// The subscription's usage limit is reached (Claude Code's own message, which says until when).
    case limitReached(String)
    /// The session is open in Terminal (handed off): never two processes on one session.
    case openInTerminal
    /// The process ended while it answered (status, what it last said on stderr).
    case exited(Int32, String)
    /// The turn failed some other way (Claude Code's message).
    case failed(String)

    public var fallsBack: Bool {
        switch self {
        case .notInstalled, .signedOut, .limitReached, .openInTerminal: return true
        case .exited, .failed: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return tr("没找到 claude 命令（Claude Code）", "The claude command (Claude Code) isn't installed")
        case .signedOut:
            return tr("Claude Code 没有登录：在终端运行 claude 并 /login", "Claude Code isn't signed in: run claude in Terminal and /login")
        case let .limitReached(message):
            return tr("Claude 订阅的用量到了上限", "The Claude subscription's usage limit is reached") + (message.isEmpty ? "" : ": \(message)")
        case .openInTerminal:
            return tr("输入法的 Claude 会话正在终端里打开着", "The input method's Claude session is open in Terminal")
        case let .exited(status, message):
            return tr("Claude 会话意外退出", "The Claude session quit unexpectedly") + " (\(status))" + (message.isEmpty ? "" : ": \(message)")
        case let .failed(message):
            return tr("Claude 会话出错", "The Claude session failed") + (message.isEmpty ? "" : ": \(message)")
        }
    }

    /// What the panel says when the provider answered instead.
    public var fallbackNote: String {
        (errorDescription ?? "") + tr("，这次由 AI 服务回答", "; the AI provider answered this time")
    }

    /// The error for an `assistant` line's `error` code and text, or a failed `result` (`status`: its HTTP status).
    static func from(code: String?, status: Int?, message: String) -> ClaudeSessionError {
        switch (code, status) {
        case ("authentication_failed", _), (_, 401?), (_, 403?): return .signedOut
        case ("rate_limit", _), ("billing_error", _), (_, 429?): return .limitReached(message)
        default: return .failed(message)
        }
    }
}

/// The session's id and folder on disk: `id` holds the id, made once; `resumable` is there once the session has a
/// conversation (Claude Code started it on a question), so the process starts with `--resume`. "Start over" (Settings → AI) makes a
/// new id. The folder gets its CLAUDE.md (`ClaudeSession.instructions`) when it has none.
public struct ClaudeSessionStore: Sendable {
    public let directory: URL

    public init(directory: URL = ClaudeSession.directory) {
        self.directory = directory
    }

    var idFile: URL { directory.appendingPathComponent("id") }
    var resumableFile: URL { directory.appendingPathComponent("resumable") }
    /// The process id of the Claude Code a hand-off started in Terminal, written by the script that starts it.
    public var terminalPIDFile: URL { directory.appendingPathComponent("terminal.pid") }

    /// The folder and its CLAUDE.md, made when missing.
    public func prepare() throws {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let instructions = directory.appendingPathComponent("CLAUDE.md")
        if !files.fileExists(atPath: instructions.path) {
            try Data(ClaudeSession.instructions.utf8).write(to: instructions, options: .atomic)
        }
    }

    /// The session's id, made (and kept) the first time.
    public func sessionID() throws -> String {
        if let saved = try? String(contentsOf: idFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           UUID(uuidString: saved) != nil {
            return saved
        }
        try prepare()
        let id = UUID().uuidString.lowercased()
        try Data((id + "\n").utf8).write(to: idFile, options: .atomic)
        try? FileManager.default.removeItem(at: resumableFile)
        return id
    }

    /// Whether the session has a conversation to resume.
    public var resumable: Bool { FileManager.default.fileExists(atPath: resumableFile.path) }

    public func markResumable() { setResumable(true) }

    public func setResumable(_ resumable: Bool) {
        guard resumable != self.resumable else { return }
        if resumable { try? Data().write(to: resumableFile) } else { try? FileManager.default.removeItem(at: resumableFile) }
    }

    /// A new session from now on (the old one stays in Claude Code's history).
    @discardableResult
    public func startOver() throws -> String {
        try? FileManager.default.removeItem(at: idFile)
        try? FileManager.default.removeItem(at: resumableFile)
        return try sessionID()
    }

    /// The process id a hand-off's Terminal wrote, if any.
    public func terminalPID() -> Int32? {
        (try? String(contentsOf: terminalPIDFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    public func clearTerminalPID() {
        try? FileManager.default.removeItem(at: terminalPIDFile)
    }
}
