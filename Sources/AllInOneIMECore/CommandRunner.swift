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
    }

    /// How often what a program printed so far is passed on (`Launch.streams`).
    static let streamInterval: Double = 0.1
    /// How long a program stopped (Esc, its timeout) has to end before it and what it started are killed.
    public static let stopGrace: Double = 0.5

    /// The process groups of the programs running now (each runs in its own group: what it starts is in it too).
    private static let groups = Locked(initialState: Set<Int32>())

    /// Stops every program still running, and what each started: the input method is quitting (an update,
    /// logging out). Returns once they're gone, or after `grace` seconds, when they're killed.
    public static func stopAll(grace: Double = stopGrace) {
        stop(groups: runningGroups, grace: grace)
    }

    /// The process groups of the programs running now.
    static var runningGroups: Set<Int32> { groups.withLock { $0 } }

    /// Stops `running` (process groups): SIGTERM, then after `grace` seconds SIGKILL to what's left.
    static func stop(groups running: Set<Int32>, grace: Double) {
        guard !running.isEmpty else { return }
        let processes = Platform.current.processes
        for group in running { processes.signal(.terminate, group: group) }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, running.contains(where: { processes.signal(.check, group: $0) }) { Thread.sleep(forTimeInterval: 0.02) }
        for group in running { processes.signal(.kill, group: group) }
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
        private let processes = Platform.current.processes
        /// Set once it started (under `lock`).
        private var process: (any LaunchedProcess)?
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
            let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
            capture(stdout) { run, chunk in
                run.output.append(chunk)
                run.streamPending = run.launch.streams
            }
            capture(stderr) { $0.errors.append($1) }
            let spec = LaunchSpec(executable: url, arguments: Array(argv.dropFirst()), environment: environment,
                                  directory: launch.directory ?? CorePaths.home, standardInput: .pipe(stdin),
                                  standardOutput: .pipe(stdout), standardError: .pipe(stderr)) { [self] process in
                // A program it started in the background may keep the pipes open: don't wait for that.
                DispatchQueue.global().async { [self] in
                    _ = pipes.wait(timeout: .now() + 1)
                    finish(process)
                }
            }
            do {
                let process = try processes.launch(spec)
                // It runs in a process group of its own (its id): stopping it reaches what it started.
                // Kept while it runs: under `lock`, as `finish` drops it, so one that's over already (a quick
                // program) is never kept.
                let group = process.processIdentifier
                lock.lock()
                self.process = process
                let stopped = cancelled
                if !finished { CommandRunner.groups.withLock { _ = $0.insert(group) } }
                lock.unlock()
                if stopped { stop(nil) }  // cancelled while it was starting
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
            let process = process
            let running = !finished && stopReason == nil && process?.isRunning == true
            if running, let reason { stopReason = reason }
            lock.unlock()
            guard running, let group = process?.processIdentifier else { return }
            // Its whole group: a script that ignores SIGTERM, or something it started, doesn't outlive it.
            let processes = processes
            processes.signal(.terminate, group: group)
            DispatchQueue.global().asyncAfter(deadline: .now() + CommandRunner.stopGrace) {
                processes.signal(.kill, group: group)
            }
        }

        private func finish(_ process: any LaunchedProcess) {
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
