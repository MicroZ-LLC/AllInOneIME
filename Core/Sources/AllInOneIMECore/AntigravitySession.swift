import Foundation

/// The question session on Google Antigravity's CLI, `agy` (1.5.8, checked by running it): an ACP agent (`ACPBackend`,
/// `ACPDriver`), with what is its own here: the agent definition and the hook that keep it to searching the web, the
/// fast model, and its sign-in check. Gemini CLI's place: Gemini CLI no longer serves personal Google accounts
/// ("IneligibleTierError … migrate to the Antigravity suite").
///
/// - `agy acp --agent allinoneime` in the folder (`antigravity-session`); `initialize` (≈0.05 s) says `loadSession:
///   true`. `session/new` (≈0.9 s) gives a UUID, the conversation's id, the one `agy --conversation` takes (the hand-off,
///   checked); `session/load` after a restart replays the conversation first (`user_message_chunk`s, not part of any
///   answer) and remembers it; an id it doesn't have loads as a new conversation.
/// - The model: its default is slow (first token 5.5–8 s); `session/set_model` to `model` (≈1.7 s), sent after each
///   `session/new` and `session/load` before any prompt (`AntigravityDriver`).
/// - Reading the web and nothing else, three ways, each enough alone for what it covers:
///   1. `--agent allinoneime`: the folder's `.agents/agents/allinoneime.md` (`agent`), whose `tools` are `search_web`
///      alone (agy adds `manage_task`) and `mcpServers` none; a conversation whose web tools are off runs
///      `allinoneime-offline` (`offlineAgent`, no tools; `SessionWeb`, decided per process from the conversation's
///      `web` by `arguments`, as the other ACP agents' modes are). agy has no tool that reads a page (it uses `curl`
///      through its shell for that, refused): its `search_web` is what it has of the web. An agent agy can't find is
///      its default one, with every tool, silently: so also
///   2. the folder's `.agents/hooks.json` (`hooks`, `gate`): before every tool, in the session's process
///      (`ALLINONEIME_SESSION`, its environment), anything but `search_web` is denied (the shell, reading and writing
///      files, subagents, schedules, tasks, MCP tools); in Terminal (the hand-off) it decides nothing (`allow`, which
///      agy's docs say hands the call on to the next hook or its default policy: its own permission rules, as the user
///      set them up; `ask` would make it prompt for every tool).
///   3. Every permission request is refused (`ACPDriver`), and a tool other than the web one that completes ends the
///      process (`AntigravityDriver`: `notWebOnly`, the provider answers).
///   Checked live: a shell command and reading /etc/hosts were refused by the hook (the model said so), the web search
///   answered, and no file was written.
/// - The folder's GEMINI.md and AGENTS.md would be read, and the user's ~/.gemini/GEMINI.md too (no way to leave that
///   out); the instructions are the agent's system prompt instead.
/// - Signed out: `session/new` fails with -32000 "Authentication required". Its Google sign-in is in the login keychain
///   (service "gemini", account "antigravity"); a Gemini API key (`modelProvider` "gemini" in its settings) or a Google
///   Cloud project (`gcp`) are the other ways (`signedIn`). No command says whether it is signed in.
/// - ACP has no way to name a conversation (agy titles each one itself, `session_info_update`; `/rename` is its
///   terminal's): the session is found by its folder (`agy --continue` there).
public struct AntigravityBackend: SessionBackend {
    /// What it shares with the other ACP agents: the launch, folder, files, hand-off.
    public var acp: ACPBackend
    /// The model asked for after each `session/new` and `session/load` (`AntigravityDriver.model(in:)`).
    public var model: String

    public init(base: URL? = nil, model: String = Self.fastModel,
                signIn: @escaping @Sendable (_ environment: [String: String], _ home: URL) -> Bool = Self.signedIn) {
        acp = ACPBackend(
            agent: .antigravity, folderName: "antigravity-session",
            launch: ["acp", "--agent", Self.agentName, "--disable-telemetry"],
            offlineLaunch: ["acp", "--agent", Self.offlineAgentName, "--disable-telemetry"],
            files: [SessionFile(path: ".agents/agents/\(Self.agentName).md", content: Self.agent),
                    SessionFile(path: ".agents/agents/\(Self.offlineAgentName).md", content: Self.offlineAgent),
                    SessionFile(path: ".agents/hooks.json", content: Self.hooks),
                    SessionFile(path: ".agents/\(Self.gateFile)", content: Self.gate, earlier: Self.earlierGates)],
            availability: [], resume: ["--conversation"], start: [], followUp: ["-i"], base: base,
            environment: [Self.sessionVariable: "antigravity"], signIn: signIn)
        self.model = model
    }

    /// The fast model (first token ≈1.7 s), when agy offers it (`AntigravityDriver.model(in:)`).
    public static let fastModel = "gemini-3.8-flash-low"
    public static let agentName = "allinoneime"
    public static let offlineAgentName = "allinoneime-offline"
    /// The tool the session may use: agy's web search.
    public static let webTools: Set<String> = ["search_web"]
    /// Set in the session's process environment: the hook (`gate`) keeps that process to the web.
    public static let sessionVariable = "ALLINONEIME_SESSION"
    static let gateFile = "allinoneime-web-only.sh"

    /// The session's agent: the web search alone, no MCP servers, the instructions as its system prompt.
    public static let agent = """
        ---
        name: \(agentName)
        description: The input method's own session. Answers questions; may search the web, nothing else.
        tools:
          - search_web
        mcpServers: []
        mainAgent: true
        subagent: false
        model: inherit
        ---
        # System Prompt

        \(ClaudeSession.instructions)
        """

    /// The agent of a conversation whose web tools are off (`SessionWeb`): no tools.
    public static let offlineAgent = """
        ---
        name: \(offlineAgentName)
        description: The input method's own session, for a question with text the user didn't type. No tools.
        tools: []
        mcpServers: []
        mainAgent: true
        subagent: false
        model: inherit
        ---
        # System Prompt

        \(ClaudeSession.instructions)
        """

    /// agy's hooks for the folder: `gate` before every tool.
    public static let hooks = """
        {
          "allinoneime-web-only": {
            "PreToolUse": [
              {"matcher": "*", "hooks": [{"type": "command", "command": "/bin/sh ./\(gateFile)", "timeout": 10}]}
            ]
          }
        }

        """

    /// Before each tool (its call as JSON on stdin; run in .agents): in the session's process, the web search allowed and
    /// anything else denied; elsewhere (Terminal) nothing decided here ("allow", which hands the call on to agy's own
    /// rules; "ask" would prompt). The tool's name is read as JSON (`plutil`), never matched in the text, where an
    /// argument could hold it.
    public static let gate = """
        #!/bin/sh
        # AllInOneIME's own Antigravity session may search the web, nothing else (agy acp in this folder, with
        # \(sessionVariable) set). In Terminal (agy as you set it up) this decides nothing: "allow" hands the call on to
        # agy's own rules.
        name=$(/usr/bin/plutil -extract toolCall.name raw -o - - 2>/dev/null)
        if [ -z "${\(sessionVariable):-}" ]; then
          echo '{"decision":"allow"}'
        elif [ "$name" = "search_web" ]; then
          echo '{"decision":"allow"}'
        else
          echo '{"decision":"deny","reason":"In this session only searching the web is allowed."}'
        fi

        """

    /// Earlier `gate` texts: a folder still holding one as written gets the new one. The first said "ask" outside the
    /// session, which made agy prompt for every tool in Terminal.
    static let earlierGates = ["""
        #!/bin/sh
        # AllInOneIME's own Antigravity session may search the web, nothing else (agy acp in this folder, with
        # \(sessionVariable) set). In Terminal (agy as you set it up) this says nothing.
        name=$(/usr/bin/plutil -extract toolCall.name raw -o - - 2>/dev/null)
        if [ -z "${\(sessionVariable):-}" ]; then
          echo '{"decision":"ask"}'
        elif [ "$name" = "search_web" ]; then
          echo '{"decision":"allow"}'
        else
          echo '{"decision":"deny","reason":"In this session only searching the web is allowed."}'
        fi

        """]

    /// Whether agy is signed in, without running it: its Google sign-in in the login keychain, or a Gemini API key it
    /// is set to use (`modelProvider` "gemini" in ~/.gemini/antigravity-cli/settings.json, with GEMINI_API_KEY set), or
    /// a Google Cloud project it signed in to (`gcp` there). `keychain`: whether the keychain has the sign-in.
    public static func signedIn(environment: [String: String], home: URL) -> Bool {
        signedIn(environment: environment, home: home, keychain: keychainSignIn)
    }

    static func signedIn(environment: [String: String], home: URL, keychain: () -> Bool) -> Bool {
        let settings = home.appendingPathComponent(".gemini/antigravity-cli/settings.json")
        let object = (try? Data(contentsOf: settings))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if object["gcp"] != nil { return true }
        if object["modelProvider"] as? String == "gemini" {
            return !(environment["GEMINI_API_KEY"] ?? "").isEmpty || !(environment["GOOGLE_API_KEY"] ?? "").isEmpty
        }
        return keychain()
    }

    /// Whether the login keychain has agy's Google sign-in (its attributes only: the token isn't read, nothing asks;
    /// Platform/Apple/AntigravityKeychain.swift). None where there is no keychain.
    static func keychainSignIn() -> Bool {
        #if canImport(Security)
        return loginKeychainHasSignIn()
        #else
        return false
        #endif
    }

    public var agent: SessionAgent { acp.agent }
    public var directory: URL { acp.directory }
    public var files: [SessionFile] { acp.files }
    public var usesProviderSettings: Bool { false }
    public var retryTogglesResume: Bool { false }
    public var environment: [String: String] { acp.environment }

    public func arguments(sessionID: String, resume: Bool, settings: URL?, web: SessionWeb) -> [String] {
        acp.arguments(sessionID: sessionID, resume: resume, settings: settings, web: web)
    }

    public func driver(sessionID: String, agentSessionID: String?, resume: Bool, directory: URL, web: SessionWeb) -> any SessionDriver {
        AntigravityDriver(ACPDriver(directory: directory, agentSessionID: agentSessionID, mode: nil), model: model,
                          tools: web == .open ? Self.webTools : [])
    }

    public func effective(_ web: SessionWeb) -> SessionWeb? { acp.effective(web) }
    public func availabilityArguments(settings: URL?) -> [String] { [] }
    public func signedIn(environment: [String: String], home: URL) -> Bool? { acp.signedIn(environment: environment, home: home) }
    public func signedIn(status: Int32, output: Data) -> Bool? { status == 0 }

    public func terminalArguments(program: String, sessionID: String, agentSessionID: String?, resume: Bool,
                                  followUp: Bool) -> [String] {
        acp.terminalArguments(program: program, sessionID: sessionID, agentSessionID: agentSessionID, resume: resume,
                              followUp: followUp)
    }
}

/// An `ACPDriver` with what agy needs besides: after the conversation opens (`session/new`, `session/load`), the model
/// is set (`session/set_model`) before anything else is sent (the questions wait for its answer; one it refuses leaves
/// agy's default); and a tool other than `tools` that completes ends the process (`notWebOnly`).
final class AntigravityDriver: SessionDriver {
    private let inner: ACPDriver
    private let model: String
    private let tools: Set<String>
    /// The requests the inner driver sent, by id (their method, and the session they name): whose responses open a
    /// conversation, and which.
    private var sent: [Int: (method: String, session: String?)] = [:]
    private var serial = 0
    /// The id of the `session/set_model` waited for; what came meanwhile, held.
    private var setting: String?
    private var heldEvents: [ClaudeSession.Event] = []
    private var heldLines: [Data] = []
    /// A `session/load` is answered: the conversation it replays first isn't checked (`strayTool`).
    private var loading = false

    init(_ inner: ACPDriver, model: String, tools: Set<String>) {
        self.inner = inner
        self.model = model
        self.tools = tools
    }

    func opening() -> [Data] { pass(inner.opening()) }
    func message(_ text: String) -> [Data] { pass(inner.message(text)) }
    func interrupt() -> [Data] { pass(inner.interrupt()) }
    func newConversation() -> [Data]? { inner.newConversation().map(pass) }

    func received(_ line: Data) -> (events: [ClaudeSession.Event], replies: [Data]) {
        let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
        if let setting, object["method"] == nil, object["id"] as? String == setting {
            self.setting = nil
            let (events, lines) = (heldEvents, heldLines)
            (heldEvents, heldLines) = ([], [])
            return (events, lines)
        }
        if !loading, strayTool(object) {
            return ([.failed(.notWebOnly, endsProcess: true)], [])
        }
        let request = object["method"] == nil ? (object["id"] as? Int).flatMap { sent.removeValue(forKey: $0) } : nil
        let opened = request.map { $0.method == "session/new" || $0.method == "session/load" } == true
        if request?.method == "session/load" { loading = false }
        let (events, replies) = inner.received(line)
        let lines = pass(replies)
        if setting != nil {
            heldEvents += events
            heldLines += lines
            return ([], [])
        }
        guard opened, let result = object["result"] as? [String: Any],
              let sessionID = result["sessionId"] as? String ?? request?.session,
              let model = Self.model(model, in: result) else { return (events, lines) }
        serial += 1
        let id = "agy-model-\(serial)"
        setting = id
        (heldEvents, heldLines) = (events, lines)
        return ([], [ClaudeSession.line(["jsonrpc": "2.0", "id": id, "method": "session/set_model",
                                         "params": ["sessionId": sessionID, "modelId": model]])])
    }

    /// The lines sent by the inner driver, their requests noted; held while the model is being set.
    private func pass(_ lines: [Data]) -> [Data] {
        for line in lines {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let id = object["id"] as? Int, let method = object["method"] as? String else { continue }
            sent[id] = (method, (object["params"] as? [String: Any])?["sessionId"] as? String)
            if method == "session/load" { loading = true }
        }
        guard setting == nil else {
            heldLines += lines
            return []
        }
        return lines
    }

    /// Whether a tool not in `tools` (by agy's `name`, else its `title`) completed: let through though it shouldn't
    /// have been.
    private func strayTool(_ object: [String: Any]) -> Bool {
        guard object["method"] as? String == "session/update",
              let update = (object["params"] as? [String: Any])?["update"] as? [String: Any],
              ["tool_call", "tool_call_update"].contains(update["sessionUpdate"] as? String ?? ""),
              update["status"] as? String == "completed" else { return false }
        return !tools.contains(update["name"] as? String ?? update["title"] as? String ?? "")
    }

    /// The model to ask for: `preferred` when the response's `models.availableModels` has it, else the first fast one
    /// offered (its id has "flash" and "low"), else none (agy's default stays); a response without the list: `preferred`
    /// (one agy refuses changes nothing).
    static func model(_ preferred: String, in result: [String: Any]) -> String? {
        guard let models = (result["models"] as? [String: Any])?["availableModels"] as? [[String: Any]] else {
            return preferred
        }
        let ids = models.compactMap { $0["modelId"] as? String }
        if ids.contains(preferred) { return preferred }
        return ids.first { $0.lowercased().contains("flash") && $0.lowercased().contains("low") }
    }
}

// MARK: - Gemini CLI's session, before Antigravity took its place

extension Config {
    /// A config file whose CLI is Gemini CLI's session (0.7.4's earlier builds: "geminiSession", which reads as
    /// Antigravity's, `QuestionBackend.init(file:)`) written as Antigravity's when `antigravityInstalled` says agy is on
    /// this Mac, else as none (the provider is the AI). Only that key changes; every other key and the provider's
    /// settings stay as they are. Whether the file was changed. Run once at launch (the Mac's `ClaudeSessionMac`).
    @discardableResult
    public static func migrateGeminiCLISession(at url: URL = defaultURL, antigravityInstalled: () -> Bool) throws -> Bool {
        AIConfig.fileLock.lock(); defer { AIConfig.fileLock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              file["questionBackend"] as? String == QuestionBackend.geminiCLISession else { return false }
        let old = try load(from: url)
        var new = old
        new.questionBackend = antigravityInstalled() ? .antigravitySession : nil
        try AIConfig.writing(new, from: old, keys: ["questionBackend"], at: url)
        return true
    }
}


/// Names of Gemini CLI's question session from 0.7.4's earlier builds, each now Antigravity's: kept only so that the
/// acceptance tests written for it (which this change may not edit) still compile; they say what of it no longer holds.
extension SessionAgent {
    @available(*, deprecated, message: "Gemini CLI's session is Antigravity's now")
    public static let gemini = SessionAgent.antigravity
}

extension QuestionBackend {
    @available(*, deprecated, message: "Gemini CLI's session is Antigravity's now")
    public static let geminiSession = QuestionBackend.antigravitySession
}

extension ACPBackend {
    @available(*, deprecated, message: "Gemini CLI's session is Antigravity's now (AntigravityBackend)")
    public static var gemini: ACPBackend { AntigravityBackend().acp }
}
