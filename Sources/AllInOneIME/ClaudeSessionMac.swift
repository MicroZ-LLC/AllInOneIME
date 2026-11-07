import AllInOneIMECore
import AllInOneIMEMac
import Foundation

/// The input method's own Claude Code session on the Mac (`ClaudeSessionManager`, `ClaudeSession`): one process for every
/// text field, `claude` where Terminal finds it (`TerminalLauncher.claudePath`) or on the login shell's PATH, run with the
/// login shell's environment. At launch `claude auth status` says whether it can answer (the default for `@question`).
/// Handing it to Terminal (⌘⏎ in an @question conversation) ends our process and runs `claude --resume <id>` in the
/// session's folder; that Claude Code's process id goes in `ClaudeSessionStore.terminalPIDFile`, so that no process of
/// ours starts on the session while it runs.
enum ClaudeSessionMac {
    static let manager = ClaudeSessionManager(
        launcher: ProcessClaudeSessionLauncher(executable: { claudeURL }, environment: { ShellEnvironment.current }),
        isAlive: { kill($0, 0) == 0 })

    /// Where `claude` is, nil when it isn't installed.
    static var claudeURL: URL? {
        TerminalLauncher.claudePath.map { URL(fileURLWithPath: $0) }
            ?? CommandRunner.resolve("claude", path: ShellEnvironment.current["PATH"])
    }

    /// Looks whether `claude` is installed and signed in (`ClaudeSessionManager.availability`), off the main thread;
    /// `done` on the main thread after.
    static func checkAvailability(done: (@MainActor @Sendable () -> Void)? = nil) {
        Task.detached {
            let availability: ClaudeSession.Availability
            if let claude = claudeURL {
                let status = await authStatus(claude)
                availability = status.flatMap { ClaudeSession.signedIn(authStatus: $0) } == true ? .ready : .signedOut
            } else {
                availability = .notInstalled
            }
            manager.availability = availability
            log.notice("Claude session: \(String(describing: availability), privacy: .public)")
            if let done { await done() }
        }
    }

    /// What `claude auth status` prints (JSON), signed in or not; nil when it can't run.
    private static func authStatus(_ claude: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = claude
                process.arguments = ["auth", "status", "--json"]
                process.environment = ShellEnvironment.current
                process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
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
                continuation.resume(returning: data)
            }
        }
    }

    /// Opens the session in a Terminal window: our process ends, Claude Code resumes it in the session's folder, the next
    /// question typed (if any) as its first message. The script writes its process id first (`exec` keeps it).
    static func handOff(followUp: String) throws {
        guard let claude = claudeURL else { throw ClaudeSessionError.notInstalled }
        let (arguments, directory) = try manager.handOff(claude: claude.path)
        let pidFile = manager.store.terminalPIDFile.path
        let argv = ["/bin/sh", "-c", "printf '%s' $$ > \"$1\"; shift; exec \"$@\"", "sh", pidFile] + arguments
        if followUp.isEmpty {
            try TerminalLauncher.launch(argv, name: "claude-session", directory: directory.path)
        } else {
            try TerminalLauncher.agent(argv, prompt: followUp, directory: directory.path)
        }
        log.notice("Claude session handed to Terminal")
    }
}
