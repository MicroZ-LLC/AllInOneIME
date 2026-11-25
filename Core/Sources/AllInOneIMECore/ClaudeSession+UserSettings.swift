import Foundation

extension ClaudeSession {
    /// The user's Claude Code settings file: settings.json in `CLAUDE_CONFIG_DIR` when the environment the session runs
    /// with sets it, else in ~/.claude.
    public static func userSettingsFile(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        home: URL = CorePaths.home) -> URL {
        let configured = environment["CLAUDE_CONFIG_DIR"].map { ($0 as NSString).expandingTildeInPath } ?? ""
        let directory = configured.isEmpty ? home.appendingPathComponent(".claude", isDirectory: true)
            : URL(fileURLWithPath: configured, isDirectory: true)
        return directory.appendingPathComponent("settings.json")
    }
}
