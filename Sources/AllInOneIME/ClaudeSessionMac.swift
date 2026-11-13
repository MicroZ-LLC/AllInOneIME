import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation

/// The input method's own question sessions on the Mac (`ClaudeSessionManager`), one per agent that has one
/// (`SessionAgent`): Claude Code's (`ClaudeSession`, `claude` where Terminal finds it or on the login shell's PATH, with
/// the provider settings of the user's Claude Code settings, CLAUDE_CONFIG_DIR as that environment says), Codex's
/// (`CodexBackend`, `codex app-server`), Antigravity's (`AntigravityBackend`, `agy acp`) and Kiro CLI's
/// (`ACPBackend.kiro`, `kiro-cli acp`), each on the login shell's PATH and with its environment: the variables of the
/// login shell the agent needs (`SessionAgent.environmentVariables`: CLAUDE_CONFIG_DIR, CODEX_HOME, GEMINI_API_KEY …,
/// never logged) and what the agent needs in it (`SessionBackend.environment`). Whether each can answer is looked at
/// when Settings → AI shows the choices (`ClaudeSessionManager.checkAvailability`: `claude auth status` with the
/// session's own flags in its folder, Codex's `account/read`, Antigravity's sign-in in the keychain, `kiro-cli whoami`): as it
/// shows with a CLI chosen, as its choices are opened, and as a CLI is chosen there; never at launch, nor while a
/// provider is the AI and the choices stay closed. The one chosen as the AI (`Config.ai`) is tried as a question comes,
/// whatever was found.
/// Handing one to Terminal (⌘⏎ in an @question conversation) ends our process first (waited for), then runs `claude
/// --resume <id>`, `codex resume <thread>`, `agy --conversation <id>` or `kiro-cli chat --resume-id <id>` in the session's
/// folder under `lockf`, which holds the conversation's lock while it runs (`ClaudeSessionManager.terminalCommand`);
/// questions after it go into a new conversation, never the one handed off.
enum ClaudeSessionMac {
    static let manager = ClaudeSessionManager(
        launcher: launcher(ClaudeCodeBackend(), executable: { claudeURL }),
        userSettings: { ClaudeSession.userSettingsFile(environment: environment(.claude)) })

    static let codex = session(CodexBackend())
    static let antigravity = session(AntigravityBackend())
    static let kiro = session(ACPBackend.kiro)

    /// The sessions by agent, for the converter.
    static var managers: [SessionAgent: ClaudeSessionManager] { [.claude: manager, .codex: codex, .antigravity: antigravity, .kiro: kiro] }

    private static func session(_ backend: any SessionBackend) -> ClaudeSessionManager {
        ClaudeSessionManager(backend: backend, launcher: launcher(backend, executable: { program(backend.agent) }))
    }

    /// Starts the agent with the login shell's environment and what the agent needs in it.
    private static func launcher(_ backend: any SessionBackend, executable: @escaping @Sendable () -> URL?) -> ProcessClaudeSessionLauncher {
        let (agent, extra) = (backend.agent, backend.environment)
        return ProcessClaudeSessionLauncher(executable: executable,
                                            environment: { environment(agent).merging(extra) { $1 } })
    }

    /// The login shell's environment with what of it `agent` needs (`SessionAgent.environmentVariables`).
    private static func environment(_ agent: SessionAgent) -> [String: String] {
        ShellEnvironment.current(with: agent.environmentVariables)
    }

    /// Where `claude` is, nil when it isn't installed.
    static var claudeURL: URL? {
        TerminalLauncher.claudePath.map { URL(fileURLWithPath: $0) }
            ?? CommandRunner.resolve("claude", path: ShellEnvironment.current["PATH"])
            ?? desktopBundled(.claude)
    }

    /// Where `agent`'s program is, nil when it isn't installed.
    static func program(_ agent: SessionAgent) -> URL? {
        agent == .claude ? claudeURL
            : CommandRunner.resolve(agent.program, path: ShellEnvironment.current["PATH"]) ?? desktopBundled(agent)
    }

    /// The copy a desktop app brings along, for someone who has the app but never installed the CLI: the ChatGPT app
    /// (bundle com.openai.codex) carries `codex` in Resources/codex-cli/bin; the Claude app keeps Claude Code in
    /// ~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app (newest version taken). Both are
    /// those apps' own layout and may move with an update: not found is just "not installed".
    static func desktopBundled(_ agent: SessionAgent) -> URL? {
        let fm = FileManager.default
        func executable(_ url: URL) -> URL? { fm.isExecutableFile(atPath: url.path) ? url : nil }
        switch agent {
        case .codex:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { return nil }
            return executable(app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"))
        case .claude:
            let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code")
            let versions = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in versions {
                let folder = root.appendingPathComponent(version)
                for hash in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
                    if let url = executable(folder.appendingPathComponent("\(hash)/claude.app/Contents/MacOS/claude")) { return url }
                }
            }
            return nil
        case .antigravity:
            // Where agy's installer puts it, for a login shell whose PATH doesn't have it.
            return executable(fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy"))
        default:
            return nil
        }
    }

    /// A config that chose Gemini CLI's session (0.7.4's earlier builds) chooses Antigravity's when agy is on this Mac,
    /// else the provider (`Config.migrateGeminiCLISession`). Once a launch, off the main thread.
    static func migrateGeminiCLIChoice() {
        DispatchQueue.global(qos: .utility).async {
            do {
                if try Config.migrateGeminiCLISession(antigravityInstalled: { program(.antigravity) != nil }) {
                    log.notice("Gemini CLI's session chosen: moved to \((try? Config.load())?.questionBackend?.rawValue ?? "the provider", privacy: .public)")
                }
            } catch {
                log.error("Gemini CLI's session choice not moved: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The session of `agent`.
    static func manager(_ agent: SessionAgent) -> ClaudeSessionManager { managers[agent] ?? manager }

    /// Looks again whether each agent is installed and signed in (`ClaudeSessionManager.checkAvailability`, all at once,
    /// off the main thread), for Settings; `done` on the main thread after.
    static func checkAvailability(done: (@MainActor @Sendable () -> Void)? = nil) {
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for (agent, session) in managers {
                    group.addTask {
                        let availability = await session.checkAvailability(force: true)
                        log.notice("\(agent.rawValue, privacy: .public) session: \(String(describing: availability), privacy: .public)")
                    }
                }
            }
            if let done { await done() }
        }
    }

    /// The CLI `@question` goes to was changed in Settings' settings document (Settings → AI's choice does the same):
    /// every session's process ends (with a question it was answering), and the next question starts the one chosen.
    static func backendChanged() {
        for session in managers.values { session.stop() }
    }

    /// The sessions follow the config file as it is now (`Converter.questionSessionsFollow`): another CLI chosen in it
    /// (by hand), the old one's process ends at once. Main thread (`LiveConfig`).
    static func followConfig() {
        guard let config = LiveConfig.currentIfValid else { return }
        sharedConverter.questionSessionsFollow(config)
    }

    /// Opens the conversation the questions go to in a Terminal window: our process ends first, the agent resumes the
    /// conversation in the session's folder, holding its lock (`ClaudeSessionManager.terminalCommand`), the next question
    /// typed (if any) as its first message, interactive after it (after "--", or Antigravity's "-i":
    /// `SessionBackend.terminalArguments`). It is the CLI as the user set it up (their rules, tools and MCP servers).
    static func handOff(followUp: String) throws {
        let session = manager((try? Config.load())?.questionSessionAgent ?? .claude)
        guard let program = program(session.backend.agent) else { throw ClaudeSessionError.notInstalled }
        let (arguments, directory, lock) = try session.handOff(program: program.path, followUp: !followUp.isEmpty)
        let argv = ClaudeSessionManager.terminalCommand(arguments, lock: lock)
        if followUp.isEmpty {
            try TerminalLauncher.launch(argv, name: "\(session.backend.agent.rawValue)-session", directory: directory.path)
        } else {
            try TerminalLauncher.agent(argv, prompt: followUp, directory: directory.path)
        }
        log.notice("\(session.backend.agent.rawValue, privacy: .public) session handed to Terminal")
    }
}
