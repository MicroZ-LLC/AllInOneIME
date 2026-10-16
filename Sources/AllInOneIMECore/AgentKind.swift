import Foundation

/// The coding agent `@agent` hands the text to (`Config.agent`): it starts in a Terminal window with the text as its
/// first message, which is always the last argument (`terminalArguments` + the prompt). Only Claude Code can also run
/// in the background (`claudeInBackground`).
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude, gemini, kiro, custom

    /// Its name in Settings and in the command list: a custom agent's is its program's file name.
    public func displayName(custom: [String] = []) -> String {
        switch self {
        case .claude: return "Claude Code"
        case .gemini: return "Gemini CLI"
        case .kiro: return "Kiro CLI"
        case .custom:
            guard let program = program(custom: custom) else { return "Custom" }
            return (program as NSString).lastPathComponent
        }
    }

    /// The program it needs on the Mac (nil: a custom agent without a command).
    public func program(custom: [String] = []) -> String? {
        switch self {
        case .claude: return "claude"
        case .gemini: return "gemini"
        case .kiro: return "kiro-cli"
        case .custom:
            let first = custom.first?.trimmingCharacters(in: .whitespaces) ?? ""
            return first.isEmpty ? nil : first
        }
    }

    /// What runs in Terminal, without the prompt (appended as the last argument). "--": the prompt is the prompt, even
    /// when it starts with "-" (Gemini CLI takes its first message as `-i`'s value instead). Nil when there's nothing to run.
    public func terminalArguments(custom: [String] = []) -> [String]? {
        switch self {
        case .claude: return ["claude", "--"]
        case .gemini: return ["gemini", "-i"]  // --prompt-interactive: its first message, then it goes on interactively
        case .kiro: return ["kiro-cli", "chat", "--"]
        case .custom: return program(custom: custom) == nil ? nil : custom
        }
    }

    /// Whether `@agent` can start it as a background task (`claude --bg`), listed by `@tasks`.
    public var supportsBackground: Bool { self == .claude }
}
