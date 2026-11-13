import Foundation

/// The agents the input method keeps a question session on (`ClaudeSessionManager`, `SessionBackend`): Claude Code,
/// Codex, Gemini CLI and Kiro CLI, in the order Automatic tries them (`QuestionBackend.sessionAgents`). Not `AgentKind`,
/// which is `@agent`'s list: Codex has a session and is no `@agent` agent. `init(_:)`: the session of `@agent`'s agent,
/// where it has one.
public enum SessionAgent: String, Codable, CaseIterable, Sendable {
    case claude, codex, gemini, kiro

    /// The name every agent's session has where the agent can name one (Claude Code's `--name`, Codex's thread name), so
    /// that the user finds it in the agent's own list of sessions; the others are found by their folder.
    public static let sessionName = "AllInOneIME"

    /// The session of `@agent`'s `agent`; nil for one without (a custom agent).
    public init?(_ agent: AgentKind) {
        switch agent {
        case .claude: self = .claude
        case .gemini: self = .gemini
        case .kiro: self = .kiro
        case .custom: return nil
        }
    }

    /// The `@agent` agent it is; nil for Codex.
    public var agentKind: AgentKind? {
        switch self {
        case .claude: return .claude
        case .codex: return nil
        case .gemini: return .gemini
        case .kiro: return .kiro
        }
    }

    /// Its name in Settings and the panel: "Claude Code", "Codex", "Gemini CLI", "Kiro CLI".
    public var displayName: String { agentKind?.displayName() ?? "Codex" }

    /// The short name its session goes by in what the panel says ("the Kiro session").
    public var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .kiro: return "Kiro"
        }
    }

    /// The program it runs: `claude`, `codex`, `gemini`, `kiro-cli`.
    public var program: String { agentKind?.program() ?? "codex" }

    /// What the user runs in Terminal to sign in (Claude Code's is its own words: `ClaudeSessionError`).
    var signIn: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex login"
        case .gemini: return "gemini"
        case .kiro: return "kiro-cli login"
        }
    }
}
