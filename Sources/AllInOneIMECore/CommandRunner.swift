import Foundation
import os

/// Runs a `run` command (`CustomCommand`): the program starts in the home folder, without a shell,
/// with the user's shell PATH; what it prints becomes the one result. It is stopped after its
/// timeout, when it prints too much, or when the request is cancelled (Esc). A script extension runs
/// the same way, in its own folder (`run(_:arguments:environment:)`).
public enum CommandRunner {
    /// Output kept from the program (more stops it).
    static let maxOutputBytes = 64 * 1024

    public enum RunError: Error, LocalizedError, Equatable {
        case notFound(String)
        case failed(status: Int32, message: String)
        case timedOut(Double)
        case tooMuchOutput

        public var errorDescription: String? {
            switch self {
            case let .notFound(program): return "Program not found: \(program)"
            case let .failed(status, message): return message.isEmpty ? "The program failed (exit status \(status))" : message
            case let .timedOut(seconds): return "Stopped after \(Int(seconds.rounded())) seconds"
            case .tooMuchOutput: return "Stopped: too much output"
            }
        }
    }

    /// `environment` nil: `ShellEnvironment.current` (asked for off the caller's thread: the first
    /// time, the user's shell is started to read its PATH).
    public static func run(_ command: CustomCommand, input: String,
                           environment: [String: String]? = nil) -> AsyncThrowingStream<ConversionUpdate, Error> {
        let launch = Launch(argv: command.arguments(for: input), stdin: command.standardInput(for: input), timeout: command.timeout)
        return run(launch, environment: environment)
    }

    /// What a script extension printed so far (`isFinal`: all of it, once it exited), read as its output.
    public struct ScriptUpdate: Equatable, Sendable {
        public var output: ScriptOutput
        /// The text it printed, cleaned (`cleanOutput`).
        public var text: String
        public var isFinal: Bool
    }

    /// Runs a script extension with `arguments` ($1 $2 $3, `ScriptCommand.arguments(from:)`) in its folder (or
    /// its `currentDirectoryPath`) with `environment` (`ScriptContext.environment`), /usr/local/bin on the PATH
    /// as Raycast adds it. What it prints arrives as it comes (a progress shown), then all of it; when it fails,
    /// its last line says why. `status`: its status line (`ScriptCommand.status`), stopped sooner.
    public static func run(_ command: ScriptCommand, arguments: [String], environment: [String: String]? = nil,
                           status: Bool = false) -> AsyncThrowingStream<ScriptUpdate, Error> {
        let argv = status ? command.status?.launch ?? command.launch : command.launch + arguments
        let timeout = status ? min(ScriptCommand.Status.timeout, command.timeout) : command.timeout
        let launch = Launch(argv: argv, stdin: nil, timeout: timeout, directory: command.directory,
                            failureOnStandardOutput: true, streams: !status)
        let raw = run(launch, environment: environment, extraPath: "/usr/local/bin")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await update in raw {
                        continuation.yield(ScriptUpdate(output: .parse(update.rawText), text: update.rawText, isFinal: update.isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(_ launch: Launch, environment: [String: String]?,
                            extraPath: String? = nil) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let run = Run(launch: launch, continuation: continuation)
            continuation.onTermination = { _ in run.cancel() }
            DispatchQueue.global().async {
                var environment = environment ?? ShellEnvironment.current
                if let extraPath, !(environment["PATH"] ?? "").split(separator: ":").contains(Substring(extraPath)) {
                    environment["PATH"] = (environment["PATH"].map { $0 + ":" } ?? "") + extraPath
                }
                run.start(environment: environment)
            }
        }
    }

    /// What is started, and how its output is read.
    struct Launch: Sendable {
        var argv: [String]
        var stdin: String?
        var timeout: Double
        /// Where it runs (nil: the home folder).
        var directory: URL? = nil
        /// What it printed (`cleanOutput`) as the result: by default, one line with all of it.
        var result: @Sendable (String) -> ConversionResult = { $0.isEmpty ? .empty : ConversionResult(versions: [CandidateLine($0)]) }
        /// A failure's message may be on standard output, when nothing on standard error says why.
        var failureOnStandardOutput = false
        /// What it printed so far arrives as it comes (`isFinal` false), a few times a second at most.
        var streams = false
    }

    /// How often what a program printed so far is passed on (`Launch.streams`).
    static let streamInterval: Double = 0.1
    /// How long a program stopped (Esc, its timeout) has to end before it and what it started are killed.
    public static let stopGrace: Double = 0.5

    /// The process groups of the programs running now (each runs in its own group: what it starts is in it too).
    private static let groups = OSAllocatedUnfairLock(initialState: Set<pid_t>())

    /// Stops every program still running, and what each started: the input method is quitting (an update,
    /// logging out). Returns once they're gone, or after `grace` seconds, when they're killed.
    public static func stopAll(grace: Double = stopGrace) {
        stop(groups: runningGroups, grace: grace)
    }

    /// The process groups of the programs running now.
    static var runningGroups: Set<pid_t> { groups.withLock { $0 } }

    /// Stops `running` (process groups): SIGTERM, then after `grace` seconds SIGKILL to what's left.
    static func stop(groups running: Set<pid_t>, grace: Double) {
        guard !running.isEmpty else { return }
        for group in running { kill(-group, SIGTERM) }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, running.contains(where: { kill(-$0, 0) == 0 }) { usleep(20_000) }
        for group in running { kill(-group, SIGKILL) }
        groups.withLock { $0.subtract(running) }
    }

    /// The program as it will be started: an absolute path, or the first match on `path`.
    public static func resolve(_ program: String, path: String?) -> URL? {
        let fm = FileManager.default
        if program.contains("/") {
            let expanded = (program as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        for dir in (path ?? "").split(separator: ":") where !dir.isEmpty {
            let candidate = (String(dir) as NSString).appendingPathComponent(program)
            if fm.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }

    /// Whether `program` would run here: it is found (`resolve`), and if it is one of the stand-ins macOS
    /// keeps in /usr/bin for the developer tools (`python3`, `git`, …), Xcode or the command line tools
    /// are installed (without them, the stand-in only offers to install them).
    public static func isInstalled(_ program: String, path: String?,
                                   developerFolders: [String] = DeveloperTools.folders) -> Bool {
        guard let url = resolve(program, path: path) else { return false }
        return !DeveloperTools.isStandIn(url) || DeveloperTools.installed(in: developerFolders)
    }

    /// What the program printed, as inserted: control characters (colors, bells, a terminal title)
    /// removed, line breaks and tabs kept, trailing blank lines dropped.
    static func cleanOutput(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)?", with: "", options: .regularExpression)
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\t" { out.append(scalar); continue }
            if scalar == "\r" { continue }
            if scalar.properties.generalCategory == .control { continue }
            out.append(scalar)
        }
        return String(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `result` as inserted into a terminal, which runs every line it is given: each text on one line
    /// (line breaks and tabs become spaces, none between Chinese characters; `Composer.oneLine`).
    public static func oneLine(_ result: ConversionResult) -> ConversionResult {
        var result = result
        for index in result.versions.indices {
            result.versions[index].text = Composer.oneLine(result.versions[index].text)
        }
        return result
    }

    /// One run of a program. Its callbacks arrive on several queues; `lock` guards the state.
    private final class Run: @unchecked Sendable {
        private let launch: Launch
        private let continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation
        private let process = Process()
        private let lock = NSLock()
        private var output = Data()
        private var errors = Data()
        private var stopReason: RunError?
        private var cancelled = false
        private var finished = false
        private let started = ContinuousClock.now
        /// When what was printed so far was last passed on (`Launch.streams`), and whether more came since.
        private var lastStreamed = ContinuousClock.now
        private var streamPending = false
        /// Both output pipes closed.
        private let pipes = DispatchGroup()

        init(launch: Launch, continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) {
            self.launch = launch
            self.continuation = continuation
        }

        func start(environment: [String: String]) {
            lock.lock()
            let skip = cancelled
            lock.unlock()
            guard !skip else { return }
            let argv = launch.argv
            guard let program = argv.first, let url = CommandRunner.resolve(program, path: environment["PATH"]) else {
                continuation.finish(throwing: RunError.notFound(argv.first ?? ""))
                return
            }
            process.executableURL = url
            process.arguments = Array(argv.dropFirst())
            process.environment = environment
            process.currentDirectoryURL = launch.directory ?? FileManager.default.homeDirectoryForCurrentUser
            let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = stdin
            capture(stdout) { run, chunk in
                run.output.append(chunk)
                run.streamPending = run.launch.streams
            }
            capture(stderr) { $0.errors.append($1) }
            process.terminationHandler = { [self] _ in
                // A program it started in the background may keep the pipes open: don't wait for that.
                DispatchQueue.global().async { [self] in
                    _ = pipes.wait(timeout: .now() + 1)
                    finish()
                }
            }
            do {
                try process.run()
                // Foundation starts it in a process group of its own (its id): stopping it reaches what it started.
                // Kept while it runs: under `lock`, as `finish` drops it, so one that's over already (a quick
                // program) is never kept.
                let group = process.processIdentifier
                lock.lock()
                if !finished { CommandRunner.groups.withLock { _ = $0.insert(group) } }
                lock.unlock()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: RunError.notFound(program))
                return
            }
            let text = launch.stdin
            DispatchQueue.global().async {
                // Written off the caller's queue: a program that doesn't read would block the write.
                if let text { try? stdin.fileHandleForWriting.write(contentsOf: Data(text.utf8)) }
                try? stdin.fileHandleForWriting.close()
            }
            let timeout = max(launch.timeout, 0.1)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in stop(.timedOut(timeout)) }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
            stop(nil)
        }

        /// Reads `pipe` until it closes, keeping at most `maxOutputBytes` in all.
        private func capture(_ pipe: Pipe, into append: @escaping @Sendable (Run, Data) -> Void) {
            pipes.enter()
            pipe.fileHandleForReading.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    pipes.leave()
                    return
                }
                lock.lock()
                append(self, chunk)
                let tooMuch = output.count + errors.count > CommandRunner.maxOutputBytes
                var sofar: Data?
                if streamPending, !finished, ContinuousClock.now - lastStreamed >= .seconds(CommandRunner.streamInterval) {
                    (sofar, streamPending, lastStreamed) = (output, false, ContinuousClock.now)
                }
                lock.unlock()
                if tooMuch { stop(.tooMuchOutput) }
                if let sofar {
                    let text = CommandRunner.cleanOutput(sofar)
                    continuation.yield(ConversionUpdate(result: .empty, rawText: text, isFinal: false, elapsed: 0,
                                                        firstTokenLatency: nil, fromCache: false))
                }
            }
        }

        /// Stops the program (once): `reason` is reported, nil when the request was cancelled.
        private func stop(_ reason: RunError?) {
            lock.lock()
            let running = !finished && stopReason == nil && process.isRunning
            if running, let reason { stopReason = reason }
            lock.unlock()
            guard running else { return }
            // Its whole group: a script that ignores SIGTERM, or something it started, doesn't outlive it.
            let group = process.processIdentifier
            kill(-group, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + CommandRunner.stopGrace) {
                kill(-group, SIGKILL)
            }
        }

        private func finish() {
            lock.lock()
            guard !finished else { return lock.unlock() }
            finished = true
            let group = process.processIdentifier
            CommandRunner.groups.withLock { _ = $0.remove(group) }
            let reason = stopReason, output = output, errors = errors, cancelled = cancelled
            lock.unlock()
            let status = process.terminationStatus
            if cancelled { return continuation.finish() }
            if let reason { return continuation.finish(throwing: reason) }
            guard status == 0 else {
                // The last line with words says what went wrong (Python's traceback ends with it; markers
                // like "~~^~~" above it are left out). A Raycast script may say it on standard output.
                func lastLine(_ data: Data) -> String? {
                    CommandRunner.cleanOutput(data).split(separator: "\n")
                        .last { $0.contains { $0.isLetter } }?.trimmingCharacters(in: .whitespaces)
                }
                let message = lastLine(errors) ?? (launch.failureOnStandardOutput ? lastLine(output) : nil) ?? ""
                return continuation.finish(throwing: RunError.failed(status: status, message: String(message.prefix(300))))
            }
            let d = ContinuousClock.now - started
            let elapsed = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
            let text = CommandRunner.cleanOutput(output)
            let result = launch.result(text)
            continuation.yield(ConversionUpdate(result: result, rawText: text, isFinal: true, elapsed: elapsed,
                                                firstTokenLatency: nil, fromCache: false))
            continuation.finish()
        }
    }
}

/// The environment a program started from the input method gets: the input method's own, with the
/// PATH of the user's login shell (an input method started by launchd only has the system folders,
/// so `python3` from Homebrew, pyenv or nvm wouldn't be found). The shell is asked once.
public enum ShellEnvironment {
    public static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    public static let current: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = login["PATH"] ?? fallbackPath
        return env
    }()

    /// The variables the input method reads from the user's shell: PATH, the providers' API keys
    /// (`Provider.keyVariables`) and the web search key (`WebSearch.backend`), for a key that is set
    /// there instead of in the keychain.
    public static let login: [String: String] = loginValues(["PATH"] + Provider.allCases.flatMap(\.keyVariables)
                                                                + WebSearch.backend.keyVariables)

    /// `names` as the user's interactive login shell sets them up (unset ones are left out); empty if
    /// the shell couldn't be read in 3 seconds.
    static func loginValues(_ names: [String]) -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = "__AllInOneIME_\(UUID().uuidString)__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Interactive too: pyenv, nvm and the like are usually set up in .zshrc. Each value is printed
        // between markers, so whatever the shell's startup files print is skipped.
        let script = names.map { "printf '\(marker)\($0)=%s' \"${\($0)}\"" }.joined(separator: "; ") + "; printf '\(marker)'"
        process.arguments = ["-ilc", script]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        guard (try? process.run()) != nil else { return [:] }
        if exited.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            return [:]
        }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var values: [String: String] = [:]
        for part in text.components(separatedBy: marker).dropFirst() {
            guard let eq = part.firstIndex(of: "="), names.contains(String(part[..<eq])) else { continue }
            let value = String(part[part.index(after: eq)...])
            if !value.isEmpty { values[String(part[..<eq])] = value }
        }
        return values
    }
}

/// The stand-ins macOS keeps in /usr/bin for the developer tools: `python3`, `git`, `make`, `swift` and
/// the others are one small program (hard links of one file) that runs the real tool from Xcode or the
/// command line tools, and without those only offers to install them.
public enum DeveloperTools {
    /// Where Xcode or the command line tools may be: the folder chosen with `xcode-select -s`, then the
    /// default places.
    public static var folders: [String] {
        let chosen = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")
        return (chosen.map { [$0] } ?? []) + ["/Applications/Xcode.app/Contents/Developer", "/Library/Developer/CommandLineTools"]
    }

    /// Whether one of `folders` has the tools.
    static func installed(in folders: [String]) -> Bool {
        folders.contains { folder in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: folder + "/usr/bin", isDirectory: &isFolder) && isFolder.boolValue
        }
    }

    /// Whether `url` (after symbolic links) is the same file as `standIn`: /usr/bin/python3 has been one
    /// of the stand-ins on every macOS since 10.15.
    static func isStandIn(_ url: URL, standIn: String = "/usr/bin/python3") -> Bool {
        var file = stat(), known = stat()
        guard stat(url.path, &file) == 0, stat(standIn, &known) == 0 else { return false }
        return file.st_dev == known.st_dev && file.st_ino == known.st_ino
    }
}
