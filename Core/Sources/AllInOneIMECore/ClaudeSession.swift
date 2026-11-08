import Crypto
import Foundation

/// Where `@question` is answered (`Config.questionBackend`): the dedicated session of the agent `@agent` hands to
/// (`Config.agent`: Claude Code on the user's Claude subscription, Kiro CLI on their Kiro account; `ClaudeSessionManager`),
/// or the AI provider. Unset: the session when that agent is installed and signed in, else the provider. An agent with
/// no session (Gemini CLI, a custom one): the provider. `claudeSession` is the value's name in the file for either agent.
/// Every other request (writing, autocomplete, translating …) always goes to the provider.
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
/// - `--settings <file>`: what of the user's own settings says how Claude Code reaches a model and signs in
///   (`providerSettingKeys`: Amazon Bedrock, Vertex, a gateway, an API key helper …), copied into the session's folder
///   before each start (`providerSettings`). Without it a Claude Code set up for Bedrock in ~/.claude/settings.json
///   says "Not logged in" here, while `claude auth status` (which reads the user's settings) says signed in. Nothing to
///   copy: no flag. Managed settings (/Library/Application Support/ClaudeCode/managed-settings.json, MDM) apply whatever
///   the flags say; ~/.claude/settings.local.json is no user setting (only a project's, when Claude Code runs in ~), so
///   it isn't read. Since the user settings are left out, the availability check runs with the same flags in the same
///   folder (`authStatusArguments`), so that it says what the session will find.
public enum ClaudeSession {
    /// The session's folder: ~/Library/Application Support/AllInOneIME/claude-session on the Mac.
    public static var directory: URL { CorePaths.dataDir.appendingPathComponent("claude-session", isDirectory: true) }

    /// The CLAUDE.md written into the session's folder when it has none (the user may edit it). Web search isn't
    /// promised: on Amazon Bedrock Claude Code offers WebFetch only.
    public static let instructions = """
        You are the assistant inside an input method. Answer short, ready to paste, in the language of the question.
        Earlier messages in this session are earlier questions from the same user.
        Write plain text: your answer is inserted at the user's cursor as it is, so no Markdown (no headings, bold, tables \
        or code fences) and no preamble. When a question needs current facts, you may read web pages, or search the web \
        when you have a tool for it; without one, answer from what you know and say it may be out of date.

        """

    /// Earlier CLAUDE.md texts written as `instructions`: a folder still holding one as written gets the new one.
    static let earlierInstructions = ["""
        You are the assistant inside an input method. Answer short, ready to paste, in the language of the question.
        Earlier messages in this session are earlier questions from the same user.
        Write plain text: your answer is inserted at the user's cursor as it is, so no Markdown (no headings, bold, tables \
        or code fences) and no preamble. When a question needs current facts, you may search the web (WebSearch, WebFetch).

        """]

    /// The files written into the session's folder: its CLAUDE.md.
    public static let files = [SessionFile(path: "CLAUDE.md", content: instructions, earlier: earlierInstructions)]

    /// The tools the session may have: reading the web, nothing else (Claude Code leaves out what its provider lacks:
    /// WebSearch on Bedrock).
    public static let tools = "WebSearch,WebFetch"

    /// The arguments after `claude` that start (or resume) the session's process; `settings`: the provider settings
    /// file (`providerSettings`), nil when there is none.
    public static func arguments(sessionID: String, resume: Bool, settings: URL? = nil) -> [String] {
        ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            + (resume ? ["--resume", sessionID] : ["--session-id", sessionID])
            + ["--tools", tools, "--allowedTools", tools, "--permission-mode", "dontAsk",
               "--setting-sources", "project"] + settingsArguments(settings) + ["--strict-mcp-config"]
    }

    /// `claude auth status` as the session would see it (run in the session's folder): the same settings.
    public static func authStatusArguments(settings: URL? = nil) -> [String] {
        ["--setting-sources", "project"] + settingsArguments(settings) + ["auth", "status", "--json"]
    }

    static func settingsArguments(_ settings: URL?) -> [String] {
        settings.map { ["--settings", $0.path] } ?? []
    }

    // MARK: - The provider's settings

    /// The keys of the user's Claude Code settings copied into the session (Claude Code 2.1.319's settings schema):
    /// how it reaches a model and signs in, nothing else (no hooks, permissions, MCP servers, status line, plugins).
    /// - `env`: CLAUDE_CODE_USE_BEDROCK / _VERTEX / _FOUNDRY, AWS_PROFILE, AWS_REGION, ANTHROPIC_BASE_URL, ANTHROPIC_MODEL …
    /// - `apiKeyHelper`: a script that prints the API key or token; `proxyAuthHelper`: a corporate proxy's header.
    /// - `awsCredentialExport`, `awsAuthRefresh`: a script that exports AWS credentials, or refreshes the login (SSO).
    /// - `gcpAuthRefresh`: the same for Vertex.
    /// - `model`, `modelOverrides`: which model, and its provider's id for it (a Bedrock inference profile ARN).
    /// - `forceLoginMethod`, `forceLoginOrgUUID`, `forceLoginGatewayUrl`: the sign-in a company requires.
    public static let providerSettingKeys = [
        "env", "apiKeyHelper", "proxyAuthHelper", "awsCredentialExport", "awsAuthRefresh", "gcpAuthRefresh",
        "model", "modelOverrides", "forceLoginMethod", "forceLoginOrgUUID", "forceLoginGatewayUrl",
    ]

    /// The user's Claude Code settings file: settings.json in `CLAUDE_CONFIG_DIR` when the environment the session runs
    /// with sets it, else in ~/.claude.
    public static func userSettingsFile(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let configured = environment["CLAUDE_CONFIG_DIR"].map { ($0 as NSString).expandingTildeInPath } ?? ""
        let directory = configured.isEmpty ? home.appendingPathComponent(".claude", isDirectory: true)
            : URL(fileURLWithPath: configured, isDirectory: true)
        return directory.appendingPathComponent("settings.json")
    }

    /// `settings` (a settings.json's content) with only `providerSettingKeys`, as JSON; nil when it isn't a JSON
    /// object or holds none of them (an empty `env` counts as none).
    public static func providerSettings(_ settings: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return nil }
        var kept: [String: Any] = [:]
        for key in providerSettingKeys {
            guard let value = object[key], !(value is NSNull) else { continue }
            if let env = value as? [String: Any], env.isEmpty { continue }
            kept[key] = value
        }
        guard !kept.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: kept, options: [.sortedKeys, .prettyPrinted])
    }

    // MARK: - Rounds the session didn't see

    /// The message for `question` when the conversation had rounds the session didn't answer (the provider did, or
    /// they came from the saved history): those rounds first, as context, then the question.
    public static func message(_ question: String, after missing: [QuestionChat.Round]) -> String {
        guard !missing.isEmpty else { return question }
        let rounds = missing.map { "Question: \($0.question)\nAnswer: \($0.answer)" }.joined(separator: "\n\n")
        return "Earlier in this conversation, answered outside this session (for context):\n\n" + rounds
            + "\n\nThe question now:\n" + question
    }

    /// What stands for an answer the session gave or was told (`ClaudeSessionStore.Memory.answered`): a short hash of
    /// its text, trimmed.
    public static func fingerprint(_ answer: String) -> String {
        let digest = SHA256.hash(data: Data(answer.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
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
        /// Claude Code asks whether a tool may run: answered with `deny` (by the driver, `SessionDriver`).
        case permissionRequest(id: String)
        /// The agent gave the session this id (an ACP agent's `session/new`): kept for loading it again.
        case sessionID(String)
        /// A sign that the answer is being worked on (thinking, a tool running) with nothing to show.
        case working
        /// The session or its turn failed (an ACP agent's error response); `endsProcess`: the process is of no use now.
        case failed(ClaudeSessionError, endsProcess: Bool)
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
    /// Claude Code is set up for Amazon Bedrock and the AWS sign-in (SSO) or its credentials have expired, or none
    /// were found (`isAWSCredentialError`).
    case awsSignInExpired
    /// No sign of an answer within `ClaudeSessionManager.firstAnswerTimeout` (Claude Code stuck starting, a sign-in
    /// waiting in a browser): the process is ended.
    case noResponse
    /// The session is open in Terminal (handed off): never two processes on one session.
    case openInTerminal
    /// The process ended while it answered (status, what it last said on stderr).
    case exited(Int32, String)
    /// The turn failed some other way (Claude Code's message).
    case failed(String)

    public var fallsBack: Bool {
        switch self {
        case .notInstalled, .signedOut, .limitReached, .awsSignInExpired, .noResponse, .openInTerminal: return true
        case .exited, .failed: return false
        }
    }

    public var errorDescription: String? { description(for: .claude) }

    /// What it says for the session on `agent` (Claude Code's words for any but Kiro's).
    public func description(for agent: AgentKind) -> String {
        if agent == .kiro, let kiro = kiroDescription { return kiro }
        switch self {
        case .notInstalled:
            return tr("没找到 claude 命令（Claude Code）", "The claude command (Claude Code) isn't installed")
        case .signedOut:
            return tr("Claude Code 没有登录：在终端运行 claude 并 /login", "Claude Code isn't signed in: run claude in Terminal and /login")
        case let .limitReached(message):
            return tr("Claude 订阅的用量到了上限", "The Claude subscription's usage limit is reached") + (message.isEmpty ? "" : ": \(message)")
        case .awsSignInExpired:
            return tr("AWS 登录已过期：在终端运行 aws sso login", "The AWS sign-in has expired: run aws sso login in Terminal")
        case .noResponse:
            return tr("Claude 会话没有回应", "The Claude session didn't respond")
        case .openInTerminal:
            return tr("输入法的 Claude 会话正在终端里打开着", "The input method's Claude session is open in Terminal")
        case let .exited(status, message):
            return tr("Claude 会话意外退出", "The Claude session quit unexpectedly") + " (\(status))" + (message.isEmpty ? "" : ": \(message)")
        case let .failed(message):
            return tr("Claude 会话出错", "The Claude session failed") + (message.isEmpty ? "" : ": \(message)")
        }
    }

    /// Kiro CLI's words, where they differ.
    private var kiroDescription: String? {
        switch self {
        case .notInstalled:
            return tr("没找到 kiro-cli 命令（Kiro CLI）", "The kiro-cli command (Kiro CLI) isn't installed")
        case .signedOut:
            return tr("Kiro CLI 没有登录：在终端运行 kiro-cli login", "Kiro CLI isn't signed in: run kiro-cli login in Terminal")
        case .noResponse:
            return tr("Kiro 会话没有回应", "The Kiro session didn't respond")
        case .openInTerminal:
            return tr("输入法的 Kiro 会话正在终端里打开着", "The input method's Kiro session is open in Terminal")
        case let .exited(status, message):
            return tr("Kiro 会话意外退出", "The Kiro session quit unexpectedly") + " (\(status))" + (message.isEmpty ? "" : ": \(message)")
        case let .failed(message):
            return tr("Kiro 会话出错", "The Kiro session failed") + (message.isEmpty ? "" : ": \(message)")
        case .limitReached, .awsSignInExpired:
            return nil
        }
    }

    /// What the panel says when the provider answered instead.
    public var fallbackNote: String { fallbackNote(for: .claude) }

    public func fallbackNote(for agent: AgentKind) -> String {
        description(for: agent) + tr("，这次由 AI 服务回答", "; the AI provider answered this time")
    }

    /// The error for an `assistant` line's `error` code and text, or a failed `result` (`status`: its HTTP status).
    /// AWS's own credential errors first: they may come as 400, 403 or `authentication_failed`, and /login wouldn't help.
    static func from(code: String?, status: Int?, message: String) -> ClaudeSessionError {
        if isAWSCredentialError(message) { return .awsSignInExpired }
        switch (code, status) {
        case ("authentication_failed", _), (_, 401?), (_, 403?): return .signedOut
        case ("rate_limit", _), ("billing_error", _), (_, 429?): return .limitReached(message)
        default: return .failed(message)
        }
    }

    /// What AWS (or the AWS SDK in Claude Code) says when the credentials have expired or can't be had: an SSO login
    /// to do again. Not "Access to Bedrock models is not allowed" (the account's, not the sign-in's).
    static let awsCredentialPhrases = [
        "expiredtoken", "security token included in the request is expired", "security token included in the request is invalid",
        "unrecognizedclientexception", "invalidclienttokenid", "the sso session", "sso session associated with this profile",
        "token has expired and refresh failed", "error loading sso token", "could not load credentials",
        "credentialsprovidererror", "credential provider", "unable to locate credentials", "aws sso login",
    ]

    static func isAWSCredentialError(_ message: String) -> Bool {
        let text = message.lowercased()
        return awsCredentialPhrases.contains { text.contains($0) }
    }
}

/// The session's id and folder on disk: `id` holds the id, made once; `resumable` is there once the session has a
/// conversation (Claude Code started it on a question), so the process starts with `--resume`. "Start over" (Settings → AI) makes a
/// new id. The folder gets its CLAUDE.md (`ClaudeSession.instructions`) when it has none; `provider-settings.json`, the
/// user's provider settings (`ClaudeSession.providerSettings`), before each start; `context.json`, what the input method
/// keeps of the session (`Memory`).
///
/// The same for every agent's session (`SessionBackend`): its folder and `files` (Kiro's steering and agent config in
/// place of CLAUDE.md), and `agent-session`, the id an ACP agent gave the session (`agentSessionID`).
public struct ClaudeSessionStore: Sendable {
    public let directory: URL
    /// What `prepare` writes into the folder.
    public let files: [SessionFile]

    public init(directory: URL = ClaudeSession.directory, files: [SessionFile] = ClaudeSession.files) {
        self.directory = directory
        self.files = files
    }

    /// The store of `backend`'s session, in its folder.
    public init(_ backend: any SessionBackend) {
        self.init(directory: backend.directory, files: backend.files)
    }

    var idFile: URL { directory.appendingPathComponent("id") }
    var resumableFile: URL { directory.appendingPathComponent("resumable") }
    var providerSettingsFile: URL { directory.appendingPathComponent("provider-settings.json") }
    var memoryFile: URL { directory.appendingPathComponent("context.json") }
    var agentSessionFile: URL { directory.appendingPathComponent("agent-session") }
    /// The process id of the Claude Code a hand-off started in Terminal, written by the script that starts it.
    public var terminalPIDFile: URL { directory.appendingPathComponent("terminal.pid") }

    /// The folder and its `files` (CLAUDE.md), each made when missing or still an earlier default.
    public func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            let written = try? String(contentsOf: url, encoding: .utf8)
            guard written == nil || file.earlier.contains(written!) else { continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.content.utf8).write(to: url, options: .atomic)
        }
    }

    /// The provider settings in `user` (the user's settings.json) written for `--settings`, readable by the user only
    /// (an `env` may hold a key); nil, and no file, when there are none or `user` can't be read.
    public func writeProviderSettings(from user: URL) -> URL? {
        guard let settings = (try? Data(contentsOf: user)).flatMap(ClaudeSession.providerSettings),
              (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            try? FileManager.default.removeItem(at: providerSettingsFile)
            return nil
        }
        if (try? Data(contentsOf: providerSettingsFile)) != settings {
            guard (try? settings.write(to: providerSettingsFile, options: .atomic)) != nil else { return nil }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: providerSettingsFile.path)
        return providerSettingsFile
    }

    /// What the input method keeps of a session besides its id: the highest placeholder number given out per kind
    /// (`Redaction.Kind`), so that a value hidden in a later question never gets a placeholder an earlier one had (the
    /// values themselves are kept in memory only, `ClaudeSessionManager`), and the answers the session gave or was told
    /// (`ClaudeSession.fingerprint`), so that the rounds it didn't see are told once (`ClaudeSession.message`).
    public struct Memory: Codable, Equatable, Sendable {
        public var session: String
        public var numbers: [String: Int] = [:]
        public var answered: [String] = []

        /// The answers kept, the latest.
        static let maxAnswered = 500
    }

    /// The memory of the session `id`; empty when the file is of another session (or none).
    public func memory(of id: String) -> Memory {
        guard let data = try? Data(contentsOf: memoryFile),
              let memory = try? JSONDecoder().decode(Memory.self, from: data), memory.session == id else { return Memory(session: id) }
        return memory
    }

    public func save(_ memory: Memory) {
        var memory = memory
        memory.answered = Array(memory.answered.suffix(Memory.maxAnswered))
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: memoryFile, options: .atomic)
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
        try? FileManager.default.removeItem(at: agentSessionFile)
        return id
    }

    /// Whether the session has a conversation to resume.
    public var resumable: Bool { FileManager.default.fileExists(atPath: resumableFile.path) }

    public func markResumable() { setResumable(true) }

    public func setResumable(_ resumable: Bool) {
        guard resumable != self.resumable else { return }
        if resumable { try? Data().write(to: resumableFile) } else { try? FileManager.default.removeItem(at: resumableFile) }
    }

    /// The id the agent gave the session (an ACP agent's), nil before it has one.
    public func agentSessionID() -> String? {
        let saved = (try? String(contentsOf: agentSessionFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return saved?.isEmpty == false ? saved : nil
    }

    public func setAgentSessionID(_ id: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data((id + "\n").utf8).write(to: agentSessionFile, options: .atomic)
    }

    /// A new session from now on (the old one stays in the agent's history).
    @discardableResult
    public func startOver() throws -> String {
        try? FileManager.default.removeItem(at: agentSessionFile)
        try? FileManager.default.removeItem(at: idFile)
        try? FileManager.default.removeItem(at: resumableFile)
        try? FileManager.default.removeItem(at: memoryFile)
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
