import AllInOneIMECore
import AllInOneIMEMac
import Foundation

/// The input method's own question sessions on the Mac (`ClaudeSessionManager`), one per agent that has one
/// (`SessionAgent`): Claude Code's (`ClaudeSession`, `claude` where Terminal finds it or on the login shell's PATH, with
/// the provider settings of the user's Claude Code settings, CLAUDE_CONFIG_DIR as that environment says), Codex's
/// (`CodexBackend`, `codex app-server`), Gemini CLI's (`ACPBackend.gemini`, `gemini --acp`) and Kiro CLI's
/// (`ACPBackend.kiro`, `kiro-cli acp`), each on the login shell's PATH and with its environment (and what the agent needs
/// in it: `SessionBackend.environment`). Whether each can answer (the default for `@question`) is looked at the first
/// time a question could go to it (`ClaudeSessionManager.checkAvailability`: `claude auth status` with the session's own
/// flags in its folder, Codex's `account/read`, Gemini CLI's settings and files, `kiro-cli whoami`), and when Settings
/// shows them; never at launch.
/// Handing one to Terminal (⌘⏎ in an @question conversation) ends our process and runs `claude --resume <id>`,
/// `codex resume <thread>`, `gemini --resume <id>` or `kiro-cli chat --resume-id <id>` in the session's folder; that
/// process's id goes in `ClaudeSessionStore.terminalPIDFile`, so that no process of ours starts on the session while it
/// runs.
enum ClaudeSessionMac {
    static let manager = ClaudeSessionManager(
        launcher: launcher(ClaudeCodeBackend(), executable: { claudeURL }),
        isAlive: { kill($0, 0) == 0 },
        userSettings: { ClaudeSession.userSettingsFile(environment: ShellEnvironment.current) })

    static let codex = session(CodexBackend())
    static let gemini = session(ACPBackend.gemini)
    static let kiro = session(ACPBackend.kiro)

    /// The sessions by agent, for the converter.
    static var managers: [SessionAgent: ClaudeSessionManager] { [.claude: manager, .codex: codex, .gemini: gemini, .kiro: kiro] }

    private static func session(_ backend: any SessionBackend) -> ClaudeSessionManager {
        ClaudeSessionManager(backend: backend, launcher: launcher(backend, executable: { program(backend.agent) }),
                             isAlive: { kill($0, 0) == 0 })
    }

    /// Starts the agent with the login shell's environment and what the agent needs in it.
    private static func launcher(_ backend: any SessionBackend, executable: @escaping @Sendable () -> URL?) -> ProcessClaudeSessionLauncher {
        let extra = backend.environment
        return ProcessClaudeSessionLauncher(executable: executable,
                                            environment: { ShellEnvironment.current.merging(extra) { $1 } })
    }

    /// Where `claude` is, nil when it isn't installed.
    static var claudeURL: URL? {
        TerminalLauncher.claudePath.map { URL(fileURLWithPath: $0) }
            ?? CommandRunner.resolve("claude", path: ShellEnvironment.current["PATH"])
    }

    /// Where `agent`'s program is, nil when it isn't installed.
    static func program(_ agent: SessionAgent) -> URL? {
        agent == .claude ? claudeURL : CommandRunner.resolve(agent.program, path: ShellEnvironment.current["PATH"])
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

    /// The agent whose session `@question` goes to with `config` (`Config.questionSessionAgent`, as the converter
    /// decides it), nil: the provider.
    static func sessionAgent(_ config: Config) -> SessionAgent? {
        config.questionSessionAgent(availability: { managers[$0]?.availability ?? .notInstalled })
    }

    /// Opens the session the questions go to in a Terminal window: our process ends, the agent resumes it in the
    /// session's folder, the next question typed (if any) as its first message. The script writes its process id first
    /// (`exec` keeps it).
    static func handOff(followUp: String) throws {
        let session = manager((try? Config.load()).flatMap(sessionAgent) ?? .claude)
        guard let program = program(session.backend.agent) else { throw ClaudeSessionError.notInstalled }
        let (arguments, directory) = try session.handOff(program: program.path)
        let pidFile = session.store.terminalPIDFile.path
        let argv = ["/bin/sh", "-c", "printf '%s' $$ > \"$1\"; shift; exec \"$@\"", "sh", pidFile] + arguments
        if followUp.isEmpty {
            try TerminalLauncher.launch(argv, name: "\(session.backend.agent.rawValue)-session", directory: directory.path)
        } else {
            try TerminalLauncher.agent(argv, prompt: followUp, directory: directory.path)
        }
        log.notice("\(session.backend.agent.rawValue, privacy: .public) session handed to Terminal")
    }
}
