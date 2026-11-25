import AllInOneIMECore
import AllInOneIMEMac
import AppKit

/// `@agent`: the coding agent picked in Settings (`AgentKind`) in a Terminal window, with the typed text as its first
/// message. The agent asks before it changes files or runs commands, as it always does.
enum TerminalLauncher {
    /// Where Claude Code's installers put the `claude` command, the first place `ClaudeSessionMac.claudeURL` looks
    /// (absolute, so the window doesn't depend on PATH).
    static let claudePath: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Opens a new Terminal window in the home folder that runs `arguments` (`AgentKind.terminalArguments`) with
    /// `prompt`, however long, as the last argument. An agent's CLI by the path its question session finds it at
    /// (`ClaudeSessionMac.program`: a desktop app's copy too, which Terminal's PATH doesn't have). The text goes in a file
    /// only the user can read; the script reads it into one argument and deletes it, so it is never part of a shell
    /// command (the script deletes itself too). `directory`: where it runs (nil: the home folder).
    static func agent(_ arguments: [String], prompt: String, directory: String? = nil) throws {
        guard !arguments.isEmpty else { return }
        var argv = arguments
        if let agent = ClaudeSessionMac.agent(program: argv[0]), let found = ClaudeSessionMac.program(agent) {
            argv[0] = found.path
        }
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("AllInOneIME", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        // Prompts of earlier launches whose script never ran (Terminal closed first …): gone after an hour.
        let hourAgo = Date().addingTimeInterval(-3600)
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? [] where (name.hasPrefix("agent-prompt-") || name.hasPrefix("claude-prompt-")) && name.hasSuffix(".txt") {
            let url = folder.appendingPathComponent(name)
            if let modified = (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, modified < hourAgo {
                try? files.removeItem(at: url)
            }
        }
        let file = folder.appendingPathComponent("agent-prompt-\(UUID().uuidString).txt")
        guard files.createFile(atPath: file.path, contents: Data(prompt.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
        do {
            try launch(argv, name: "agent", directory: directory, promptFile: file)
        } catch {
            try? files.removeItem(at: file)  // nothing will read it
            throw error
        }
    }

    /// Opens a new Terminal window in `directory` (else the home folder) that runs `argv` (a custom
    /// `terminal` command), each argument quoted as one word, with the login shell's PATH. `promptFile`: its text is the
    /// last argument, read when the script runs (the file is deleted then). Before the login shell has answered, the
    /// script is written with the fallback PATH (the main thread never waits for the shell: `ShellEnvironment.path`),
    /// then again with the shell's, waited for in the background, before Terminal is asked to run it.
    ///
    /// Terminal is asked to open a window and then to run the script there, again until the script
    /// says it started: a login shell that starts a wrapper first (the Kiro CLI's `kiro-cli-term`)
    /// drops what is typed before it is ready, and a `.command` file is typed in exactly then.
    /// Without permission to control Terminal, the `.command` file is used as before.
    static func launch(_ argv: [String], name: String = "command", directory: String? = nil, promptFile: URL? = nil) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AllInOneIME", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = folder.appendingPathComponent("\(name)-\(UUID().uuidString)")
        let scriptURL = base.appendingPathExtension("command")
        let marker = base.appendingPathExtension("started")
        let changeDirectory = directory.map { "cd \(shellQuote($0)) 2>/dev/null || cd ~ || exit 1" } ?? "cd ~ || exit 1"
        // The file's text as it is, trailing line breaks too (the "x" keeps them from `$(…)`).
        let readPrompt = promptFile.map {
            "prompt=\"$(cat -- \(shellQuote($0.path)); printf x)\"; prompt=\"${prompt%x}\"; rm -f -- \(shellQuote($0.path))\n"
        } ?? ""
        func write(path: String) throws {
            let script = """
                #!/bin/zsh -f
                : > \(shellQuote(marker.path))
                rm -f -- "$0"
                export PATH=\(shellQuote(path))
                \(changeDirectory)
                \(readPrompt)exec \(argv.map(shellQuote).joined(separator: " "))\(promptFile == nil ? "" : " \"$prompt\"")

                """
            try Data(script.utf8).write(to: scriptURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        }
        let shellAnswered = ShellEnvironment.readiness.isReady
        try write(path: ShellEnvironment.path)
        DispatchQueue.global().async {
            defer { try? FileManager.default.removeItem(at: marker) }
            if !shellAnswered { try? write(path: ShellEnvironment.path) }  // the login shell's PATH, waited for here
            if runWhenReady(scriptURL, marker: marker) { return }
            DispatchQueue.main.async {
                let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                NSWorkspace.shared.open([scriptURL], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    /// Opens a Terminal window, waits until its shell shows a prompt (something besides the "Last
    /// login" line), and types `exec <script>` into it once. Typed again, a line could reach the
    /// program the first one started. False when Terminal can't be told (no permission): nothing opened.
    private static func runWhenReady(_ script: URL, marker: URL) -> Bool {
        // Terminal opens a window of its own when it starts: that one is used, not a second.
        let terminalRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty == false
        let open = terminalRunning
            ? ["tell application \"Terminal\"", "activate", "do script \"\"", "return id of front window", "end tell"]
            : ["tell application \"Terminal\"", "activate",
               "repeat 50 times", "if (count of windows) > 0 then exit repeat", "delay 0.1", "end repeat",
               "if (count of windows) = 0 then do script \"\"", "return id of front window", "end tell"]
        guard let window = osascript(open), let windowID = Int(window) else { return false }
        let tab = "selected tab of window id \(windowID)"
        let started = Date()
        while Date().timeIntervalSince(started) < 8 {
            Thread.sleep(forTimeInterval: 0.2)
            guard let contents = osascript(["tell application \"Terminal\" to get contents of \(tab)"]) else {
                return true  // the window was closed
            }
            let lines = contents.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.contains(where: { !$0.isEmpty && !$0.hasPrefix("Last login") }) {
                Thread.sleep(forTimeInterval: 0.3)
                break
            }
        }
        _ = osascript(["tell application \"Terminal\"",
                       "do script \"exec \" & quoted form of \"\(script.path)\" in \(tab)", "end tell"])
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: marker.path) { Thread.sleep(forTimeInterval: 0.1) }
        if !FileManager.default.fileExists(atPath: marker.path) { log.error("Terminal didn't run the command in time") }
        return true
    }

    /// Runs AppleScript lines with osascript; its output, or nil when it failed.
    private static func osascript(_ lines: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` as one single-quoted shell word.
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
