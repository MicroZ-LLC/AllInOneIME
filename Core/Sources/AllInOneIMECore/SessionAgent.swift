import Foundation

/// The agents the input method keeps a question session on (`ClaudeSessionManager`, `SessionBackend`): Claude Code,
/// Codex, Google Antigravity's CLI (`agy`) and Kiro CLI, in the order Settings lists them (`QuestionBackend.sessionAgents`).
/// Not `AgentKind`, which is `@agent`'s list: Codex and Antigravity have a session and are no `@agent` agents (Gemini CLI
/// is an `@agent` agent without a session: it no longer serves personal Google accounts). `init(_:)`: the session of
/// `@agent`'s agent, where it has one.
public enum SessionAgent: String, Codable, CaseIterable, Sendable {
    case claude, codex, antigravity, kiro

    /// The name every agent's session has where the agent can name one (Claude Code's `--name`, Codex's thread name), so
    /// that the user finds it in the agent's own list of sessions; the others are found by their folder.
    public static let sessionName = "AllInOneIME"

    /// The session of `@agent`'s `agent`; nil for one without (a custom agent).
    public init?(_ agent: AgentKind) {
        switch agent {
        case .claude: self = .claude
        case .kiro: self = .kiro
        case .gemini, .custom: return nil
        }
    }

    /// The `@agent` agent it is; nil for Codex and Antigravity.
    public var agentKind: AgentKind? {
        switch self {
        case .claude: return .claude
        case .codex, .antigravity: return nil
        case .kiro: return .kiro
        }
    }

    /// Its name in Settings and the panel: "Claude Code", "Codex", "Antigravity", "Kiro CLI".
    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        default: return agentKind?.displayName() ?? rawValue
        }
    }

    /// The short name its session goes by in what the panel says ("the Kiro session").
    public var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .kiro: return "Kiro"
        }
    }

    /// The program it runs: `claude`, `codex`, `agy`, `kiro-cli`.
    public var program: String {
        switch self {
        case .codex: return "codex"
        case .antigravity: return "agy"
        default: return agentKind?.program() ?? rawValue
        }
    }

    /// The variables of the user's login shell its session's process needs besides PATH (an input method started by
    /// launchd has none of them): where its settings are, its API key or token, the provider and model it uses, a
    /// proxy. Passed on as they are (`ShellEnvironment.current(with:)` on the Mac), never logged.
    public var environmentVariables: [String] {
        let proxy = ["HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "all_proxy",
                     "no_proxy", "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE"]
        let aws = ["AWS_PROFILE"] + AWSEnvironment.variables
        switch self {
        case .claude:
            return ["CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL",
                    "ANTHROPIC_SMALL_FAST_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL",
                    "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_CUSTOM_HEADERS", "CLAUDE_CODE_OAUTH_TOKEN",
                    "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "ANTHROPIC_BEDROCK_BASE_URL",
                    "AWS_BEARER_TOKEN_BEDROCK", "ANTHROPIC_VERTEX_PROJECT_ID", "ANTHROPIC_VERTEX_BASE_URL", "CLOUD_ML_REGION",
                    "ANTHROPIC_FOUNDRY_API_KEY", "ANTHROPIC_FOUNDRY_RESOURCE", "ANTHROPIC_FOUNDRY_BASE_URL",
                    "GOOGLE_APPLICATION_CREDENTIALS"] + aws + proxy
        case .codex:
            return ["CODEX_HOME", "CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORGANIZATION", "OPENAI_PROJECT",
                    "AZURE_OPENAI_API_KEY"] + aws + proxy
        case .antigravity:
            // Its own sign-in is in the keychain; these are for a Gemini API key or Google Cloud (Agent Platform) set up.
            return ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT_ID", "GOOGLE_CLOUD_LOCATION",
                    "GOOGLE_APPLICATION_CREDENTIALS", "CLOUDSDK_CONFIG"] + proxy
        case .kiro:
            return ["KIRO_API_KEY"] + aws + proxy
        }
    }

    /// Every agent's `environmentVariables`, each once.
    public static var environmentVariables: [String] {
        var seen = Set<String>()
        return allCases.flatMap(\.environmentVariables).filter { seen.insert($0).inserted }
    }

    /// What the user runs in Terminal to sign in (Claude Code's error says it in its own words: `ClaudeSessionError`).
    public var signIn: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex login"
        case .antigravity: return "agy"
        case .kiro: return "kiro-cli login"
        }
    }
}
