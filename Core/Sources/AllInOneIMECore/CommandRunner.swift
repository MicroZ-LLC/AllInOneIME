import Foundation

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

    /// `environment` nil: the platform's (`ProcessLauncher.environment`; on the Mac `ShellEnvironment.current`, asked
    /// for off the caller's thread: the first time, the user's shell is started to read its PATH).
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
    /// as Raycast adds it (not on Windows). What it prints arrives as it comes (a progress shown), then all of it; when it
    /// fails, its last line says why. `status`: its status line (`ScriptCommand.status`), stopped sooner.
    public static func run(_ command: ScriptCommand, arguments: [String], environment: [String: String]? = nil,
                           status: Bool = false) -> AsyncThrowingStream<ScriptUpdate, Error> {
        let argv = status ? command.status?.launch ?? command.launch : command.launch + arguments
        let timeout = status ? min(ScriptCommand.Status.timeout, command.timeout) : command.timeout
        let launch = Launch(argv: argv, stdin: nil, timeout: timeout, directory: command.directory,
                            failureOnStandardOutput: true, streams: !status)
        #if os(Windows)
        let raw = run(launch, environment: environment)
        #else
        let raw = run(launch, environment: environment, extraPath: "/usr/local/bin")
        #endif
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

    /// Runs a script extension's completion program (`ExtensionCompletionRunner`, 0.6.7.1 §2): its launch and
    /// `arguments` (none for its list, a query's text), in its folder (or its `currentDirectoryPath`) with `environment`
    /// (`ScriptCommand.completionEnvironment`), /usr/local/bin on the PATH, as its commands run; nothing on standard
    /// input. What it printed (cleaned), once it exited, `maxOutput` bytes at most (more stops it: a list's 4 MB, not a
    /// command's 64 KB) within `timeout`; when it fails, its last line says why. Cancelling the task stops it (SIGTERM,
    /// then SIGKILL after `stopGrace`), and returns once it has exited: what runs after it (its bundle's next program,
    /// which may share its cookie file or cache) never runs alongside it.
    static func completionOutput(_ command: ScriptCommand, arguments: [String], environment: [String: String],
                                 timeout: Double, maxOutput: Int) async throws -> String {
        let launch = Launch(argv: command.launch + arguments, stdin: nil, timeout: timeout, directory: command.directory,
                            failureOnStandardOutput: true, maxOutput: maxOutput)
        let exit = ProgramExit()
        #if os(Windows)
        let stream = run(launch, environment: environment, exit: exit)
        #else
        let stream = run(launch, environment: environment, extraPath: "/usr/local/bin", exit: exit)
        #endif
        do {
            for try await update in stream where update.isFinal { return update.rawText }
        } catch {
            await exit.wait()
            throw error
        }
        await exit.wait()
        try Task.checkCancellation()
        return ""
    }

    /// Whether a program started for a call is over: its process exited, or it never started (cancelled first, not
    /// found, not launched). What a cancelled call waits for (`completionOutput`).
    final class ProgramExit: @unchecked Sendable {
        private let state = Locked(initialState: (over: false, waiting: [CheckedContinuation<Void, Never>]()))

        /// It is over: what waits for it goes on.
        func signal() {
            let waiting = state.withLock { state in
                state.over = true
                defer { state.waiting = [] }
                return state.waiting
            }
            for continuation in waiting { continuation.resume() }
        }

        /// Returns once it is over (at once if it is), the task cancelled or not.
        func wait() async {
            await withCheckedContinuation { continuation in
                let over = state.withLock { state in
                    if !state.over { state.waiting.append(continuation) }
                    return state.over
                }
                if over { continuation.resume() }
            }
        }
    }

    private static func run(_ launch: Launch, environment: [String: String]?, extraPath: String? = nil,
                            exit: ProgramExit? = nil) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let run = Run(launch: launch, continuation: continuation, exit: exit)
            continuation.onTermination = { _ in run.cancel() }
            let processes = Platform.current.processes  // here: a task's `Platform.override` isn't on the queue
            DispatchQueue.global().async {
                var environment = environment ?? processes.environment
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
        /// The most it may print (more stops it).
        var maxOutput = CommandRunner.maxOutputBytes
    }

    /// Runs `argv` with `stdin` (nil: none, the program reads its end at once) for its output (`maxOutput` bytes at most,
    /// `timeout` seconds), as a `run` command runs: in the home folder, with `environment` (nil: the platform's, on the
    /// Mac the user's shell's PATH); what it printed (control characters taken out), once it exited; an error when it
    /// failed, printed too much or ran too long. Cancelling the task stops it (`PluginCompletionRuntime`,
    /// `CommandCompletionRunner`).
    static func output(_ argv: [String], stdin: String?, timeout: Double, maxOutput: Int,
                       environment: [String: String]? = nil) async throws -> String {
        let launch = Launch(argv: argv, stdin: stdin, timeout: timeout, maxOutput: maxOutput)
        for try await update in run(launch, environment: environment) where update.isFinal { return update.rawText }
        try Task.checkCancellation()
        return ""
    }

    /// How often what a program printed so far is passed on (`Launch.streams`).
    static let streamInterval: Double = 0.1
    /// How long a program stopped (Esc, its timeout) has to end before it and what it started are killed.
    public static let stopGrace: Double = 0.5

    /// The programs running now (each with what it started: its process group, where there are groups).
    private static let running = Locked(initialState: [ObjectIdentifier: any LaunchedProcess]())

    /// Stops every program still running, and what each started: the input method is quitting (an update,
    /// logging out). Returns once they're gone, or after `grace` seconds, when they're killed.
    public static func stopAll(grace: Double = stopGrace) {
        stop(runningPrograms, grace: grace)
    }

    /// The programs running now.
    static var runningPrograms: [any LaunchedProcess] { running.withLock { Array($0.values) } }
    /// Their process IDs, which are their process groups'.
    static var runningGroups: Set<Int32> { Set(runningPrograms.map(\.processIdentifier)) }

    /// Stops `programs` and what they started: asked to end (SIGTERM), then after `grace` seconds what's left is killed.
    static func stop(_ programs: [any LaunchedProcess], grace: Double) {
        guard !programs.isEmpty else { return }
        for program in programs { program.terminate() }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, programs.contains(where: { $0.treeIsRunning }) { Thread.sleep(forTimeInterval: 0.02) }
        for program in programs { program.kill() }
        running.withLock { for program in programs { $0[ObjectIdentifier(program)] = nil } }
    }

    /// The program as it will be started: an absolute path, or the first match on `path`. On Windows as Windows finds
    /// one (`WindowsPrograms.find`): `path` split on ";", PATHEXT's extensions added ("git" → git.exe), "\" a separator
    /// too, and a script found when its kind is known (.ps1, .py, .sh, a "#!" line).
    public static func resolve(_ program: String, path: String?) -> URL? {
        #if os(Windows)
        return WindowsPrograms.find(program, path: path, expandingTilde: true)
        #else
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
        #endif
    }

    /// The PATH in `environment`; on Windows, whose variables' names are in any case, "Path" too.
    public static func searchPath(_ environment: [String: String]) -> String? {
        #if os(Windows)
        return WindowsPrograms.variable("PATH", in: environment)
        #else
        return environment["PATH"]
        #endif
    }

    /// Whether `program` would run here: programs can be started at all (`ProcessLauncher.canLaunch`: not on iOS or
    /// Android, where the commands that need one aren't offered), it is found (`resolve`), and it really runs
    /// (`ProcessLauncher.isRunnable`: on the Mac, a stand-in macOS keeps in /usr/bin for the developer tools,
    /// `python3`, `git`, …, only with Xcode or the command line tools installed; without them it only offers to
    /// install them).
    public static func isInstalled(_ program: String, path: String?) -> Bool {
        let processes = Platform.current.processes
        guard processes.canLaunch, let url = resolve(program, path: path) else { return false }
        return processes.isRunnable(url)
    }

    /// A program found but not started, as reported: not found; on Windows, when the launcher says why
    /// (`WindowsLaunchError`: its interpreter isn't installed, an argument a batch file can't be given), that.
    static func launchFailure(_ error: Error, program: String) -> RunError {
        #if os(Windows)
        if let error = error as? WindowsLaunchError, let message = error.errorDescription { return .failed(status: -1, message: message) }
        #endif
        return .notFound(program)
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
        /// Told once its process exited, or once it's known it never starts.
        private let exit: ProgramExit?
        private let processes = Platform.current.processes
        /// Set once it started (under `lock`).
        private var process: (any LaunchedProcess)?
        private let lock = NSLock()
        private var output = Data()
        private var errors = Data()
        private var stopReason: RunError?
        /// A stop asked for after it started but before it was kept (`process`), applied once it is.
        private var pendingStop: RunError?
        private var cancelled = false
        private var finished = false
        private let started = ContinuousClock.now
        /// When what was printed so far was last passed on (`Launch.streams`), and whether more came since.
        private var lastStreamed = ContinuousClock.now
        private var streamPending = false
        /// Both output pipes closed.
        private let pipes = DispatchGroup()

        init(launch: Launch, continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation, exit: ProgramExit? = nil) {
            self.launch = launch
            self.continuation = continuation
            self.exit = exit
        }

        func start(environment: [String: String]) {
            lock.lock()
            let skip = cancelled
            lock.unlock()
            guard !skip else {
                exit?.signal()
                return
            }
            let argv = launch.argv
            guard let program = argv.first, let url = CommandRunner.resolve(program, path: CommandRunner.searchPath(environment)) else {
                exit?.signal()
                continuation.finish(throwing: RunError.notFound(argv.first ?? ""))
                return
            }
            let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
            capture(stdout) { run, chunk in
                run.output.append(chunk)
                run.streamPending = run.launch.streams
            }
            capture(stderr) { $0.errors.append($1) }
            let spec = LaunchSpec(executable: url, arguments: Array(argv.dropFirst()), environment: environment,
                                  directory: launch.directory ?? CorePaths.home, standardInput: .pipe(stdin),
                                  standardOutput: .pipe(stdout), standardError: .pipe(stderr)) { [self] process in
                exit?.signal()
                // A program it started in the background may keep the pipes open: don't wait for that.
                DispatchQueue.global().async { [self] in
                    _ = pipes.wait(timeout: .now() + 1)
                    finish(process)
                }
            }
            do {
                let process = try processes.launch(spec)
                // Stopping it reaches what it started (its process group). Kept while it runs: under `lock`, as
                // `finish` drops it, so one that's over already (a quick program) is never kept.
                lock.lock()
                self.process = process
                let stopped = cancelled, pending = pendingStop
                if !finished { CommandRunner.running.withLock { $0[ObjectIdentifier(process)] = process } }
                lock.unlock()
                if stopped {
                    stop(nil)  // cancelled while it was starting
                } else if let pending {
                    stop(pending)  // too much output before it was kept
                }
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                exit?.signal()
                continuation.finish(throwing: CommandRunner.launchFailure(error, program: program))
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

        /// Reads `pipe` until it closes, keeping at most `launch.maxOutput` in all.
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
                let tooMuch = output.count + errors.count > launch.maxOutput
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
            let process = process
            // Started but not kept yet (output can come before `start` keeps it): stopped once it is.
            if process == nil, !finished, let reason, pendingStop == nil { pendingStop = reason }
            let running = !finished && stopReason == nil && process?.isRunning == true
            if running, let reason { stopReason = reason }
            lock.unlock()
            guard running, let process else { return }
            // Its whole tree: a script that ignores SIGTERM, or something it started, doesn't outlive it.
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + CommandRunner.stopGrace) { process.kill() }
        }

        private func finish(_ process: any LaunchedProcess) {
            lock.lock()
            guard !finished else { return lock.unlock() }
            finished = true
            CommandRunner.running.withLock { $0[ObjectIdentifier(process)] = nil }
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
