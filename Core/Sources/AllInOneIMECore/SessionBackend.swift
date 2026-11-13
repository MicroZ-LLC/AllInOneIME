import Foundation

/// The agent a question session runs on (`ClaudeSessionManager`): how its process is started and talked to. Claude Code
/// over stream-json (`ClaudeCodeBackend`), Codex over its app server (`CodexBackend`), or an agent that speaks the Agent
/// Client Protocol (`ACPBackend`: Gemini CLI, Kiro CLI). The manager keeps what is the same for every agent: one
/// process, prewarmed, reused, ended when idle, started again after a crash, the queue of questions, the first-answer
/// timeout, the hand-off guard, redaction and catch-up, and the sign-in check, run when it is first needed.
public protocol SessionBackend: Sendable {
    /// The agent whose session this is.
    var agent: SessionAgent { get }
    /// The session's folder (one per agent): ~/Library/Application Support/AllInOneIME/<agent>-session on the Mac.
    var directory: URL { get }
    /// The files written into the folder when missing (or still holding an earlier default): what the agent reads there.
    var files: [SessionFile] { get }
    /// Whether the user's provider settings are copied into the folder and passed (`ClaudeSession.providerSettings`).
    var usesProviderSettings: Bool { get }
    /// A process that ended before its session started is tried once more the other way round (new ↔ resumed): Claude
    /// Code's `--session-id` fails on an id in use, `--resume` on one with no conversation.
    var retryTogglesResume: Bool { get }
    /// The arguments after the program that start the process. `sessionID`: the input method's id of the session;
    /// `resume`: it has a conversation; `settings`: the provider settings file, if any; `web`: what its web tools may
    /// reach, as `effective` makes it.
    func arguments(sessionID: String, resume: Bool, settings: URL?, web: SessionWeb) -> [String]
    /// What talks to one process (one per start): the lines it is sent, what its lines say. `agentSessionID`: the id the
    /// agent gave the session (an ACP agent's), nil before it has one; `web` as for `arguments`.
    func driver(sessionID: String, agentSessionID: String?, resume: Bool, directory: URL, web: SessionWeb) -> any SessionDriver
    /// What of `web` the agent can keep to (`SessionWeb`), for the whole process: kept to some addresses, only Claude
    /// Code can be; the others' web tools are off then. Nil: it can't be kept to it (no way to turn its web tools off):
    /// not asked, the provider answers (`ClaudeSessionError.notWebOnly`).
    func effective(_ web: SessionWeb) -> SessionWeb?
    /// What the agent's process needs in its environment besides the user's (the shell adds it).
    var environment: [String: String] { get }
    /// Whether the agent is signed in, read from its settings and files and `environment` (`home`: the user's home
    /// folder) without running anything; nil: it has no such check, the command below says.
    func signedIn(environment: [String: String], home: URL) -> Bool?
    /// The arguments of the command that says whether the agent is signed in (run in the folder).
    func availabilityArguments(settings: URL?) -> [String]
    /// The lines written to that command as it starts (a request to the agent's server); none: its input is closed.
    var availabilityInput: [Data] { get }
    /// Whether one line of its output says it is signed in (the answer to that request), nil: not this line; the
    /// command is ended once one does.
    func signedIn(line: Data) -> Bool?
    /// Whether that command's exit `status` and `output` say it is signed in; nil: can't tell.
    func signedIn(status: Int32, output: Data) -> Bool?
    /// What Terminal runs to go on in the session (the hand-off), `program` being where the agent is. `followUp`: the
    /// next question, typed with ⌘⏎, goes after these as the last argument, its first message (`TerminalLauncher.agent`,
    /// as after `AgentKind.terminalArguments`): they end with what makes it that message, the agent interactive after it,
    /// whatever it starts with: "--" (Claude Code, Codex, Kiro CLI: no option after it), Gemini CLI's "-i" (a prompt
    /// alone it answers once and exits).
    func terminalArguments(program: String, sessionID: String, agentSessionID: String?, resume: Bool, followUp: Bool) -> [String]
}

extension SessionBackend {
    /// The arguments with the web tools as they are.
    public func arguments(sessionID: String, resume: Bool, settings: URL?) -> [String] {
        arguments(sessionID: sessionID, resume: resume, settings: settings, web: .open)
    }

    public func driver(sessionID: String, agentSessionID: String?, resume: Bool, directory: URL) -> any SessionDriver {
        driver(sessionID: sessionID, agentSessionID: agentSessionID, resume: resume, directory: directory, web: .open)
    }

    /// No address can be kept to: any `only` is no web.
    public func effective(_ web: SessionWeb) -> SessionWeb? {
        if case .only = web { return .only([]) }
        return .open
    }

    /// What Terminal runs to go on in the session with a follow-up (`terminalArguments(…followUp: true)`): the
    /// follow-up is appended as the last argument.
    public func terminalArguments(program: String, sessionID: String, agentSessionID: String?, resume: Bool) -> [String] {
        terminalArguments(program: program, sessionID: sessionID, agentSessionID: agentSessionID, resume: resume, followUp: true)
    }

    public var environment: [String: String] { [:] }
    public func signedIn(environment: [String: String], home: URL) -> Bool? { nil }
    public var availabilityInput: [Data] { [] }
    public func signedIn(line: Data) -> Bool? { nil }
}

/// A file of the session's folder: `path` in it, its `content`, and earlier defaults that are replaced by it.
public struct SessionFile: Equatable, Sendable {
    public var path: String
    public var content: String
    public var earlier: [String] = []

    public init(path: String, content: String, earlier: [String] = []) {
        self.path = path
        self.content = content
        self.earlier = earlier
    }
}

/// What talks to one running process of a session, for `ClaudeSessionManager` (called under its lock, one call at a
/// time): the lines to write, and what each line read says (`ClaudeSession.Event`) with the lines to answer it with.
public protocol SessionDriver: AnyObject {
    /// Written as soon as the process starts (an ACP handshake), before any message.
    func opening() -> [Data]
    /// The lines for one user message (none yet when the session isn't ready: sent when it is).
    func message(_ text: String) -> [Data]
    /// The lines that stop the turn being answered (the process stays).
    func interrupt() -> [Data]
    /// One line of the process's output: what it says, and the lines to write back (a permission request denied).
    func received(_ line: Data) -> (events: [ClaudeSession.Event], replies: [Data])
    /// The lines that open a new conversation in this process, the messages after them going into it (Codex's
    /// `thread/start`, an ACP agent's `session/new`), once the one it has is open and no turn is answered; nil: it can't
    /// (Claude Code's process has one conversation: a new one is a new process; one still opening).
    func newConversation() -> [Data]?
}

extension SessionDriver {
    public func newConversation() -> [Data]? { nil }
}

// MARK: - Claude Code

/// Claude Code over stream-json (`ClaudeSession`): the session id is the input method's own.
public struct ClaudeCodeBackend: SessionBackend {
    public init() {}

    public var agent: SessionAgent { .claude }
    public var directory: URL { ClaudeSession.directory }
    public var files: [SessionFile] { ClaudeSession.files }
    public var usesProviderSettings: Bool { true }
    public var retryTogglesResume: Bool { true }

    public func arguments(sessionID: String, resume: Bool, settings: URL?, web: SessionWeb) -> [String] {
        ClaudeSession.arguments(sessionID: sessionID, resume: resume, settings: settings, web: web)
    }

    public func driver(sessionID: String, agentSessionID: String?, resume: Bool, directory: URL, web: SessionWeb) -> any SessionDriver {
        ClaudeStreamDriver()
    }

    /// Its WebFetch can be kept to the addresses' sites.
    public func effective(_ web: SessionWeb) -> SessionWeb? { web }

    public func availabilityArguments(settings: URL?) -> [String] { ClaudeSession.authStatusArguments(settings: settings) }

    public func signedIn(status: Int32, output: Data) -> Bool? { ClaudeSession.signedIn(authStatus: output) }

    public func terminalArguments(program: String, sessionID: String, agentSessionID: String?, resume: Bool,
                                  followUp: Bool) -> [String] {
        ClaudeSession.terminalArguments(claude: program, sessionID: sessionID, resume: resume) + (followUp ? ["--"] : [])
    }
}

/// One `claude -p` process: a line per message, its lines read as they are (`ClaudeSession.event`).
final class ClaudeStreamDriver: SessionDriver {
    private var interrupts = 0

    func opening() -> [Data] { [] }

    func message(_ text: String) -> [Data] { [ClaudeSession.userMessage(text)] }

    func interrupt() -> [Data] {
        interrupts += 1
        return [ClaudeSession.interrupt(requestID: "interrupt-\(interrupts)")]
    }

    func received(_ line: Data) -> (events: [ClaudeSession.Event], replies: [Data]) {
        let event = ClaudeSession.event(line)
        if case let .permissionRequest(id) = event { return ([event], [ClaudeSession.deny(requestID: id)]) }
        // The turn's tokens before its end.
        if case .result = event, let tokens = ClaudeSession.usage(line) { return ([.usage(tokens), event], []) }
        return ([event], [])
    }
}
