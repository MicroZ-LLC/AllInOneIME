import AllInOneIMECore
import AllInOneIMEMac
import Foundation

/// The input method's own question sessions on the Mac (`ClaudeSessionManager`), one per agent `@agent` can hand to that
/// has one (`Config.agent`): Claude Code's (`ClaudeSession`, `claude` where Terminal finds it or on the login shell's
/// PATH, with the provider settings of the user's Claude Code settings, CLAUDE_CONFIG_DIR as that environment says) and
/// Kiro CLI's (`ACPBackend.kiro`, `kiro-cli` on the login shell's PATH). Each runs with the login shell's environment. At
/// launch each one's sign-in check (`claude auth status` with the session's own flags in its folder; `kiro-cli whoami`)
/// says whether it can answer (the default for `@question`).
/// Handing one to Terminal (⌘⏎ in an @question conversation) ends our process and runs `claude --resume <id>` /
/// `kiro-cli chat --resume-id <id>` in the session's folder; that process's id goes in
/// `ClaudeSessionStore.terminalPIDFile`, so that no process of ours starts on the session while it runs.
enum ClaudeSessionMac {
    static let manager = ClaudeSessionManager(
        launcher: ProcessClaudeSessionLauncher(executable: { claudeURL }, environment: { ShellEnvironment.current }),
        isAlive: { kill($0, 0) == 0 },
        userSettings: { ClaudeSession.userSettingsFile(environment: ShellEnvironment.current) })

    static let kiro = ClaudeSessionManager(
        backend: ACPBackend.kiro,
        launcher: ProcessClaudeSessionLauncher(executable: { kiroURL }, environment: { ShellEnvironment.current }),
        isAlive: { kill($0, 0) == 0 })

    /// The sessions by agent, for the converter.
    static var managers: [AgentKind: ClaudeSessionManager] { [.claude: manager, .kiro: kiro] }

    /// Where `claude` is, nil when it isn't installed.
    static var claudeURL: URL? {
        TerminalLauncher.claudePath.map { URL(fileURLWithPath: $0) }
            ?? CommandRunner.resolve("claude", path: ShellEnvironment.current["PATH"])
    }

    /// Where `kiro-cli` is, nil when it isn't installed.
    static var kiroURL: URL? { CommandRunner.resolve("kiro-cli", path: ShellEnvironment.current["PATH"]) }

    static func program(_ agent: AgentKind) -> URL? { agent == .kiro ? kiroURL : claudeURL }

    /// The session of `agent` (Claude Code's for an agent without one: none of its questions go to it).
    static func manager(_ agent: AgentKind) -> ClaudeSessionManager { agent == .kiro ? kiro : manager }

    /// Looks whether each agent is installed and signed in (`ClaudeSessionManager.availability`), off the main thread;
    /// `done` on the main thread after.
    static func checkAvailability(done: (@MainActor @Sendable () -> Void)? = nil) {
        Task.detached {
            for agent in [AgentKind.claude, .kiro] {
                let session = manager(agent)
                let availability: ClaudeSession.Availability
                if let program = program(agent) {
                    let status = await signInStatus(program, session)
                    availability = status.flatMap { session.backend.signedIn(status: $0.status, output: $0.output) } == true ? .ready : .signedOut
                } else {
                    availability = .notInstalled
                }
                session.availability = availability
                log.notice("\(agent.rawValue, privacy: .public) session: \(String(describing: availability), privacy: .public)")
            }
            if let done { await done() }
        }
    }

    /// The sign-in check's exit status and output, signed in or not, as the session would see it (its settings, its
    /// folder); nil when it can't run.
    private static func signInStatus(_ program: URL, _ session: ClaudeSessionManager) async -> (status: Int32, output: Data)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = program
                process.arguments = session.authStatusArguments()
                process.environment = ShellEnvironment.current
                process.currentDirectoryURL = session.store.directory
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()
                continuation.resume(returning: (process.terminationStatus, data))
            }
        }
    }

    /// Opens the session of @agent's agent in a Terminal window: our process ends, the agent resumes it in the
    /// session's folder, the next question typed (if any) as its first message. The script writes its process id first
    /// (`exec` keeps it).
    static func handOff(followUp: String) throws {
        let agent = (try? Config.load())?.agent ?? .claude
        let session = manager(agent)
        guard let program = program(session.backend.agent) else { throw ClaudeSessionError.notInstalled }
        let (arguments, directory) = try session.handOff(program: program.path)
        let pidFile = session.store.terminalPIDFile.path
        let argv = ["/bin/sh", "-c", "printf '%s' $$ > \"$1\"; shift; exec \"$@\"", "sh", pidFile] + arguments
        let name = session.backend.agent == .kiro ? "kiro-session" : "claude-session"
        if followUp.isEmpty {
            try TerminalLauncher.launch(argv, name: name, directory: directory.path)
        } else {
            try TerminalLauncher.agent(argv, prompt: followUp, directory: directory.path)
        }
        log.notice("\(session.backend.agent.rawValue, privacy: .public) session handed to Terminal")
    }
}
