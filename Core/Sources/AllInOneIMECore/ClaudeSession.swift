import Crypto
import Foundation

/// The CLI chosen as the AI (`Config.questionBackend`, `Config.ai`): the input method's own session on an agent
/// (`SessionAgent`): Claude Code's (`claudeSession`, its name in the file from before the others), Codex's, Antigravity's
/// or Kiro CLI's, each a `ClaudeSessionManager`. `@question` goes to it; what has to be fast goes to the fast fallback
/// (`Config.fastProvider`). None: the AI is the provider; so is `provider` (a file's "provider", 0.7.4's builds' choice of
/// the provider for questions).
public enum QuestionBackend: String, Codable, CaseIterable, Sendable {
    case claudeSession
    case codexSession
    case antigravitySession
    case kiroSession
    /// The provider, as none is (`Config.ai`): what 0.7.4's builds wrote for questions answered by the provider.
    case provider

    /// The session of `agent`.
    public init(_ agent: SessionAgent) {
        switch agent {
        case .claude: self = .claudeSession
        case .codex: self = .codexSession
        case .antigravity: self = .antigravitySession
        case .kiro: self = .kiroSession
        }
    }

    /// The agent whose session it is; nil for the provider.
    public var agent: SessionAgent? {
        switch self {
        case .claudeSession: return .claude
        case .codexSession: return .codex
        case .antigravitySession: return .antigravity
        case .kiroSession: return .kiro
        case .provider: return nil
        }
    }

    /// The agents that have a question session, in the order Settings lists them.
    public static let sessionAgents: [SessionAgent] = [.claude, .codex, .antigravity, .kiro]

    /// Every CLI's, in that order; not `provider`, which names none (a file's reads as none: `Config`).
    public static var allCases: [QuestionBackend] { sessionAgents.map(QuestionBackend.init) }

    /// What a file's value names: its case, and Gemini CLI's session of 0.7.4's earlier builds ("geminiSession": Gemini
    /// CLI no longer serves personal Google accounts) as Antigravity's, Google's CLI that took its place (on a Mac
    /// without it, `Config.migrateGeminiCLISession` makes the provider the AI). Nil: one this version doesn't know.
    public init?(file value: String) {
        if value == Self.geminiCLISession { self = .antigravitySession } else { self.init(rawValue: value) }
    }

    /// Gemini CLI's session's value in 0.7.4's earlier builds.
    public static let geminiCLISession = "geminiSession"
}

extension SessionAgent {
    /// Its session's name in Settings: "Claude Code session".
    public var sessionTitle: String { tr("\(displayName) 会话", "\(displayName) session") }
}

extension Config {
    /// The agent whose session `@question` goes to, nil: the provider. The one place that decides it (the converter,
    /// the prewarm, the hand-off, the panel's and the settings' labels, Start Over all ask it): the CLI chosen as the AI
    /// (`ai`), whatever it can do now (it is tried; the fast fallback answers with why when it can't).
    public var questionSessionAgent: SessionAgent? { questionBackend?.agent }
}

/// An `@question` conversation in the panel (`Composer.questionConversation`), as the session it goes to sees it
/// (`ClaudeSessionManager.request`): a new one each time the panel starts one (a question asked, a saved one picked, asked
/// again), its follow-ups in it. Each goes into a new conversation of the session's agent, so that a question never
/// carries the ones before it (nor waits for them to be read again after the prompt cache lapsed).
public struct QuestionConversation: Hashable, Sendable {
    public var id: String
    /// What the session's web tools may reach in it (`SessionWeb`).
    public var web: SessionWeb

    public init(id: String = UUID().uuidString, web: SessionWeb = .open) {
        self.id = id
        self.web = web
    }

    /// A conversation of one request, a writing task (`Converter.sessionStream`): an id of its own, so it never goes into
    /// another's agent conversation nor another into its, and no web tools.
    public static var oneOff: QuestionConversation { QuestionConversation(web: .only([])) }
}

/// What a question session's web tools may reach in a conversation (`QuestionConversation.web`). Text the user didn't
/// type into the question (selected text from another app, a screenshot's text, a page or another command's output
/// inside it) could tell the agent to send what the conversation holds to an address of its own: with such text in the
/// conversation only the addresses the user typed may be fetched, and with none typed the web tools are off. Each CLI
/// keeps to it as far as it can (`SessionBackend.effective`): Claude Code fetches from those addresses' sites only
/// (`WebFetch(domain:…)`, no search); Codex, Antigravity and Kiro CLI can't be kept to addresses, so theirs are off.
public enum SessionWeb: Hashable, Sendable {
    /// The session's web tools as they are.
    case open
    /// Only these addresses, typed by the user; none: no web.
    case only([URL])

    /// Open, or with text the user didn't type in the question (`untrusted`), only the addresses in `typed`.
    public init(untrusted: Bool, typed: String) {
        self = untrusted ? .only(Self.addresses(in: typed)) : .open
    }

    /// The same, with the addresses in `typed` (a follow-up the user typed) too.
    public func allowing(_ typed: String) -> SessionWeb {
        guard case let .only(urls) = self else { return self }
        return .only(urls + Self.addresses(in: typed).filter { !urls.contains($0) })
    }

    /// The sites (lowercased hosts) of `only`'s addresses, each once, in order; none for `open`.
    public var hosts: [String] {
        guard case let .only(urls) = self else { return [] }
        var seen = Set<String>()
        return urls.compactMap { $0.host?.lowercased() }.filter { seen.insert($0).inserted }
    }

    /// The web addresses in `text`, in order, each once: http(s) ones, and www. ones (as https); the punctuation after
    /// one isn't part of it.
    public static func addresses(in text: String) -> [URL] {
        guard let pattern = try? NSRegularExpression(pattern: #"(?i)\b(?:https?://|www\.)[^\s<>"'`，。、；：！？（）「」『』【】《》]+"#)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var found: [URL] = []
        for match in pattern.matches(in: text, range: range) {
            guard let span = Range(match.range, in: text) else { continue }
            var address = String(text[span])
            while let last = address.last, ".,;:!?)]}'\"".contains(last) { address.removeLast() }
            if address.lowercased().hasPrefix("www.") { address = "https://" + address }
            guard let url = URL(string: address), url.host?.isEmpty == false, !found.contains(url) else { continue }
            found.append(url)
        }
        return found
    }
}

/// What a question session says of a question as it answers it (`ClaudeSessionManager.answer`): the answer so far, and
/// what the panel's footer tells of it.
public struct SessionReply: Equatable, Sendable {
    public var text: String
    /// The agent conversation it went into had no earlier question: the first of an `@question` conversation, or one
    /// whose conversation couldn't be resumed (the agent began it afresh, without the rounds before).
    public var newConversation: Bool
    /// The tokens the turn used so far, as the CLI reports them (nil: it doesn't).
    public var tokens: Int?

    public init(text: String, newConversation: Bool = false, tokens: Int? = nil) {
        self.text = text
        self.newConversation = newConversation
        self.tokens = tokens
    }
}

/// The input method's own long-running Claude Code session (`ClaudeSessionManager` keeps its process), in a working
/// folder of its own whose CLAUDE.md says what it is for (so no home or project CLAUDE.md is read). Each `@question`
/// conversation in the panel is a conversation of its own (a session id, kept in `directory`/id while it is the current
/// one), each question one user message in it: Claude remembers the conversation's earlier rounds, not other
/// conversations. This is what is sent and read: the arguments, the stream-json lines, the events.
///
/// The flags, checked with Claude Code 2.1.303 (`claude --help`, and by running them):
/// - `-p --input-format stream-json --output-format stream-json --verbose`: a process that stays up and takes one user
///   message per line on stdin; `--verbose` is required with stream-json output.
/// - `--include-partial-messages`: the answer's text deltas as they come (`stream_event` lines).
/// - `--session-id <id>` the first time, `--resume <id>` once it has a conversation (the first fails on an id in use,
///   the second on one that has none).
/// - `--name AllInOneIME` (`SessionAgent.sessionName`): the session's title in Claude Code's own list (`/resume`, the
///   picker); kept in its transcript as a "custom-title" line, so `claude --resume AllInOneIME` in the session's folder
///   opens it (by title Claude Code looks in the folder it runs in only).
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
    /// file (`providerSettings`), nil when there is none; `web`: what its web tools may reach (`toolArguments`).
    public static func arguments(sessionID: String, resume: Bool, settings: URL? = nil, web: SessionWeb = .open) -> [String] {
        ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            + (resume ? ["--resume", sessionID] : ["--session-id", sessionID]) + ["--name", SessionAgent.sessionName]
            + toolArguments(web) + ["--permission-mode", "dontAsk",
               "--setting-sources", "project"] + settingsArguments(settings) + ["--strict-mcp-config"]
    }

    /// The tools for `web` (checked with Claude Code 2.1.303: its `system` "init" line lists them): `tools`, allowed;
    /// kept to some addresses, WebFetch only, allowed for their sites only (`WebFetch(domain:…)`; with dontAsk any other
    /// is denied), no WebSearch; no address, no tools at all (`--tools ""`).
    static func toolArguments(_ web: SessionWeb) -> [String] {
        guard case .only = web else { return ["--tools", tools, "--allowedTools", tools] }
        let hosts = web.hosts
        guard !hosts.isEmpty else { return ["--tools", ""] }
        return ["--tools", "WebFetch", "--allowedTools", hosts.map { "WebFetch(domain:\($0))" }.joined(separator: ",")]
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
                                        home: URL = CorePaths.home) -> URL {
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

    /// `message` with the excerpts of AllInOneIME's user guide for a conversation about it (`UserGuide.excerpts`), as
    /// the provider gets them (`Prompt.userGuide`): after the question, since the session's instructions are its
    /// CLAUDE.md. Its tools read the web, not files: excerpts, not the guide's path (`ChatHandoff.guideNote`).
    public static func message(_ message: String, guide: String?) -> String {
        guide.map { message + "\n\n" + Prompt.userGuide($0) } ?? message
    }

    /// What stands for an answer the session gave or was told (`ClaudeSessionStore.Memory.answered`): a short hash of
    /// its text, trimmed.
    public static func fingerprint(_ answer: String) -> String {
        let digest = SHA256.hash(data: Data(answer.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// What Terminal runs to go on in the session (the hand-off): Claude Code, interactive, on the same session, with all
    /// of its history (`--session-id` while it has none yet). A follow-up goes after "--" (`ClaudeCodeBackend`).
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
        /// The agent compacts the conversation's context (summarizes it to fit) before it goes on: Claude Code's
        /// `system` "compact_boundary", or its status "compacting"; Codex's `thread/compacted`, or its
        /// `contextCompaction` item.
        case compacting
        /// The tokens the turn used so far, as the agent reports them (Claude Code's `result` `usage`, Codex's
        /// `thread/tokenUsage/updated`, an ACP agent's prompt response `usage`).
        case usage(Int)
        /// The session or its turn failed (an ACP agent's error response); `endsProcess`: the process is of no use now.
        case failed(ClaudeSessionError, endsProcess: Bool)
        case other
    }

    /// The event in one line of output (`other` for anything else, a line that isn't JSON too).
    public static func event(_ line: Data) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return .other }
        switch object["type"] as? String {
        case "system":
            switch object["subtype"] as? String {
            case "init": return .started
            case "compact_boundary": return .compacting
            case "status": return object["status"] as? String == "compacting" ? .compacting : .other
            default: return .other
            }
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

    /// The tokens a `result` line says its turn used (`usage`: the input, read from and written to the cache or not, and
    /// the output); nil for any other line, or one without.
    public static func usage(_ line: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["type"] as? String == "result",
              let usage = object["usage"] as? [String: Any] else { return nil }
        let counts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
            .compactMap { (usage[$0] as? NSNumber)?.intValue }
        return counts.isEmpty ? nil : counts.reduce(0, +)
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
        /// Its session couldn't be used when a question was asked: the process ended before the session started (an
        /// older version that doesn't know a flag), it couldn't be kept to the web (`ClaudeSessionError.notWebOnly`), or
        /// its program couldn't be launched (`ClaudeSessionError.cannotLaunch`).
        /// Settings → AI says so until its sign-in is looked at again.
        case cannotStart
    }
}

/// Why the session didn't answer: whichever it is, before any of the answer came the provider answers instead (the
/// panel says why, `fallbackNote`); after some of it came, the question fails so (`description(for:)`).
public enum ClaudeSessionError: Error, LocalizedError, Equatable, Sendable {
    /// No `claude` command on this Mac.
    case notInstalled
    /// Its program was found (`ClaudeSessionLauncher.installed`) but couldn't be launched: gone since (an uninstall or
    /// update meanwhile), not executable (why, `ProcessClaudeSessionLauncher.launchFailure`).
    case cannotLaunch(String)
    /// Claude Code isn't signed in.
    case signedOut
    /// The subscription's usage limit is reached (Claude Code's own message, which says until when).
    case limitReached(String)
    /// Claude Code is set up for Amazon Bedrock and the AWS sign-in (SSO) or its credentials have expired, or none
    /// were found (`isAWSCredentialError`).
    case awsSignInExpired
    /// No sign of an answer within `ClaudeSessionManager.firstAnswerTimeout` (Claude Code stuck starting, a sign-in
    /// waiting in a browser): the process is ended. Or no process to ask within it: the one before still ending.
    case noResponse
    /// The process ended before its session started, tried twice (status, what it last said on stderr): an older
    /// Claude Code that doesn't know `--name`, a broken install.
    case failedToStart(Int32, String)
    /// The agent couldn't be kept to reading the web, so it wasn't asked: Kiro CLI without the input method's agent
    /// (`ACPBackend.kiroMode`), Codex whose config couldn't be read (the MCP servers to turn off unknown).
    case notWebOnly
    /// A question waited `ClaudeSessionManager.firstAnswerTimeout` for an earlier one the session is still answering
    /// (or that it didn't stop when asked to).
    case busy
    /// The agent began compacting the conversation's context before any of the answer came (`ClaudeSession.Event
    /// .compacting`), which may take longer than `ClaudeSessionManager.firstAnswerTimeout`: not waited for.
    case compacting
    /// The process ended while it answered (status, what it last said on stderr).
    case exited(Int32, String)
    /// The turn failed some other way (Claude Code's message).
    case failed(String)

    public var errorDescription: String? { description(for: .claude) }

    /// What it says for the session on `agent`: the agent's names in the same words for each (Claude Code's own for
    /// signing in and its subscription's limit; the AWS sign-in is only ever Claude Code's).
    public func description(for agent: SessionAgent) -> String {
        let (name, program, short) = (agent.displayName, agent.program, agent.shortName)
        switch self {
        case .notInstalled:
            return tr("没找到 \(program) 命令（\(name)）", "The \(program) command (\(name)) isn't installed")
        case .signedOut where agent == .claude:
            return tr("Claude Code 没有登录：在终端运行 claude 并 /login", "Claude Code isn't signed in: run claude in Terminal and /login")
        case .signedOut:
            return tr("\(name) 没有登录：在终端运行 \(agent.signIn)", "\(name) isn't signed in: run \(agent.signIn) in Terminal")
        case let .limitReached(message) where agent == .claude:
            return tr("Claude 订阅的用量到了上限", "The Claude subscription's usage limit is reached") + (message.isEmpty ? "" : ": \(message)")
        case let .limitReached(message):
            return tr("\(short) 的用量到了上限", "The \(short) usage limit is reached") + (message.isEmpty ? "" : ": \(message)")
        case .awsSignInExpired:
            return tr("AWS 登录已过期：在终端运行 aws sso login", "The AWS sign-in has expired: run aws sso login in Terminal")
        case .noResponse:
            return tr("\(short) 会话没有回应", "The \(short) session didn't respond")
        case let .cannotLaunch(reason):
            return tr("\(short) 会话启动不了", "The \(short) session couldn't start") + (reason.isEmpty ? "" : ": \(reason)")
        case let .failedToStart(status, message):
            return tr("\(short) 会话启动不了", "The \(short) session couldn't start") + " (\(status))" + (message.isEmpty ? "" : ": \(message)")
        case .notWebOnly:
            return tr("没法让 \(name) 只读网页，所以没有问它", "\(name) couldn't be limited to reading the web, so it wasn't asked")
        case .busy:
            return tr("\(short) 会话还在回答之前的问题", "The \(short) session is still answering an earlier question")
        case .compacting:
            return tr("\(short) 会话正在压缩对话", "The \(short) session is compacting the conversation")
        case let .exited(status, message):
            return tr("\(short) 会话意外退出", "The \(short) session quit unexpectedly") + " (\(status))" + (message.isEmpty ? "" : ": \(message)")
        case let .failed(message):
            return tr("\(short) 会话出错", "The \(short) session failed") + (message.isEmpty ? "" : ": \(message)")
        }
    }

    /// What the panel says when the provider answered instead.
    public var fallbackNote: String { fallbackNote(for: .claude) }

    public func fallbackNote(for agent: SessionAgent) -> String {
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

/// A hand-off to Terminal (⌘⏎, `ClaudeSessionManager.handOffOnceEnded`) that didn't reach it: why, and whether the
/// conversation stayed the one questions here go into (`kept`; else they go into a new one, a question having gone there
/// meanwhile). What it says is in the interface language, as it is shown.
public struct SessionHandOffError: LocalizedError, Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// Our process still ran a moment after it was killed: Terminal wasn't opened.
        case stillRunning
        /// Terminal couldn't be opened on it (why, as said in the interface language).
        case terminal(String)
    }

    public var reason: Reason
    public var kept: Bool

    public init(reason: Reason, kept: Bool) {
        self.reason = reason
        self.kept = kept
    }

    public var errorDescription: String? {
        let why: String
        switch reason {
        case .stillRunning: why = tr("会话的进程没有结束", "the session's process didn't end")
        case let .terminal(message): why = message
        }
        return kept
            ? tr("没能在终端打开这个对话（\(why)），对话还在这里", "Couldn't open the conversation in Terminal (\(why)); it stays here")
            : tr("没能在终端打开这个对话（\(why)），这里的问题会进入新的对话",
                 "Couldn't open the conversation in Terminal (\(why)); questions here now go into a new conversation")
    }
}

/// The session's id and folder on disk: `id` holds the id of the conversation questions go into now, made when there is
/// none, a new one for each new conversation (`startOver`: a request sent into a new one, `prewarm`, Settings' "Start
/// over"); `resumable` is there once that conversation has begun (Claude Code started it on a question), so the process
/// starts with `--resume`. The folder gets its CLAUDE.md (`ClaudeSession.instructions`) when it has none; `provider-settings.json`, the
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
    /// Where the conversations' lock files are (`ConversationLock`).
    var locks: URL { directory.appendingPathComponent("locks", isDirectory: true) }

    /// The lock file of the conversation `id` (`ConversationLock`): held while a process is on it, ours or Terminal's.
    public func lockFile(_ id: String) -> URL { locks.appendingPathComponent(id + ".lock") }

    /// The folder and its `files`: an enforced one (`SessionFile.enforced`) put back before each process starts whenever
    /// it isn't as written; the others (CLAUDE.md, AGENTS.md) made when missing or still an earlier default.
    public func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            if file.enforced {
                guard (try? Data(contentsOf: url)) != Data(file.content.utf8) else { continue }
            } else {
                let written = try? String(contentsOf: url, encoding: .utf8)
                guard written == nil || file.earlier.contains(written!) else { continue }
            }
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

    /// The conversation `id` the one now again, as it was before `startOver` (a hand-off that didn't reach Terminal:
    /// `ClaudeSessionManager.handOffOnceEnded`): whether it resumes, the agent's id of it. Its memory is the caller's to
    /// save.
    func restore(_ id: String, resumable: Bool, agentSessionID: String?) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data((id + "\n").utf8).write(to: idFile, options: .atomic)
        setResumable(resumable)
        if let agentSessionID { setAgentSessionID(agentSessionID) } else { try? FileManager.default.removeItem(at: agentSessionFile) }
    }

    /// A new conversation from now on (the old one stays in the agent's history).
    @discardableResult
    public func startOver() throws -> String {
        try? FileManager.default.removeItem(at: agentSessionFile)
        try? FileManager.default.removeItem(at: idFile)
        try? FileManager.default.removeItem(at: resumableFile)
        try? FileManager.default.removeItem(at: memoryFile)
        return try sessionID()
    }
}
