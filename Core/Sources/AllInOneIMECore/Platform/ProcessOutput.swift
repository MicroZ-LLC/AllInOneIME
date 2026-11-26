import Foundation

/// A program run to its end for what it printed, through a `ProcessLauncher`: its exit status, standard output and
/// standard error (each read as it comes, on a thread of its own, so that neither pipe fills up), its standard input
/// closed or `input` written to it; ended with what it started (SIGTERM, then SIGKILL) after `timeout` seconds. Its end
/// is told by its termination handler (`LaunchSpec.onExit`), as the question sessions' launcher learns of it
/// (`ProcessClaudeSessionLauncher`): never by `waitUntilExit` on a dispatch thread, which missed about one exit in ten
/// (and then never returned). Once it has ended, its pipes get a moment more to end (`pipesAfterExit`): past that,
/// something it left running holds them (a job a login shell's startup files start in the background), and what was
/// read is what it printed. Every program the input method runs for its output runs so (`@tasks`' `claude`,
/// osascript, mdfind, tar, the login shell, the updater's tools); only the update helper, which outlives the input
/// method, starts on its own.
public enum ProcessOutput {
    public struct Result: Equatable, Sendable {
        public var status: Int32
        public var output: Data
        public var errors: Data

        public init(status: Int32, output: Data, errors: Data) {
            self.status = status
            self.output = output
            self.errors = errors
        }
    }

    /// The program (its name) didn't end, and what it printed wasn't read to its end, within `seconds`: it was ended.
    public struct TimedOut: LocalizedError, Equatable, Sendable {
        public var program: String
        public var seconds: TimeInterval

        public init(program: String, seconds: TimeInterval) {
            self.program = program
            self.seconds = seconds
        }

        public var errorDescription: String? {
            let seconds = String(format: "%g", self.seconds)
            return tr("\(program) 超时（\(seconds) 秒），已停止", "\(program) timed out after \(seconds) seconds and was stopped")
        }
    }

    /// A run as `gather` returns it: what the program printed by the time it ended, or was ended at its time limit
    /// (`timedOut`; its status is then the signal's, -1 if it hadn't ended even so).
    public struct Gathered: Equatable, Sendable {
        public var result: Result
        public var timedOut: Bool
    }

    /// How long the pipes are read once the program has ended (`run`) or was ended (`gather`) before what was read is
    /// all it printed: they end at once unless something it started still holds them.
    static let pipesAfterExit: TimeInterval = 1
    static let pipesAfterKill: TimeInterval = 0.2

    /// Runs `executable` with `arguments` (in `directory`, with `environment`; nil: the launcher's) through `processes`;
    /// blocks the calling thread until it ended and what it printed was read. `input` is written to its standard input
    /// (else it's closed). Throws `TimedOut` when it didn't end within `timeout`.
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           directory: URL? = nil, input: Data? = nil, timeout: TimeInterval,
                           processes: any ProcessLauncher = Platform.current.processes) throws -> Result {
        let gathered = try gather(executable, arguments, environment: environment, directory: directory, input: input,
                                  timeout: timeout, processes: processes)
        guard !gathered.timedOut else { throw TimedOut(program: executable.lastPathComponent, seconds: timeout) }
        return gathered.result
    }

    /// `run`'s run, a program past its time ended the same way, with what it printed by then rather than an error (an
    /// mdfind stopped at the search's time limit, a login shell's values printed before it hung). `started` is told the
    /// program as soon as it runs, so that it can be stopped sooner (`LaunchedProcess.terminate`: a cancelled search).
    public static func gather(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                              directory: URL? = nil, input: Data? = nil, timeout: TimeInterval,
                              processes: any ProcessLauncher = Platform.current.processes,
                              started: ((any LaunchedProcess) -> Void)? = nil) throws -> Gathered {
        let out = Pipe(), errors = Pipe(), feed = input.map { _ in Pipe() }
        let ended = DispatchSemaphore(value: 0)
        let launched = try processes.launch(LaunchSpec(executable: executable, arguments: arguments, environment: environment,
                                                       directory: directory, standardInput: feed.map(ProcessIO.pipe) ?? .null,
                                                       standardOutput: .pipe(out), standardError: .pipe(errors),
                                                       onExit: { _ in ended.signal() }))
        started?(launched)
        if let feed, let input { write(input, to: feed.fileHandleForWriting) }
        let output = PipeReader(out.fileHandleForReading), said = PipeReader(errors.fileHandleForReading)
        let exited = ended.wait(timeout: .now() + max(timeout, 0)) == .success
        let endedAtLast = exited || stop(launched, ended: ended)
        let pipes = DispatchTime.now() + (exited ? pipesAfterExit : pipesAfterKill)
        _ = output.done.wait(timeout: pipes)
        _ = said.done.wait(timeout: pipes)
        // The pipes are left to their readers (they end once the last writer has): closed under a read, a descriptor
        // could be another file's by the time it reads again.
        let result = Result(status: endedAtLast ? launched.terminationStatus : -1, output: output.take(), errors: said.take())
        return Gathered(result: result, timedOut: !exited)
    }

    /// Ends `launched` and what it started: asked first (SIGTERM), killed half a second later if anything of it is
    /// still there (SIGKILL). Whether it has ended (`ended` signalled).
    private static func stop(_ launched: any LaunchedProcess, ended: DispatchSemaphore) -> Bool {
        launched.terminate()
        var exited = ended.wait(timeout: .now() + 0.5) == .success
        if launched.treeIsRunning {
            launched.kill()
            if !exited { exited = ended.wait(timeout: .now() + 0.2) == .success }
        }
        return exited
    }

    /// `data` written to a program's standard input, then closed, on a thread of its own: a program that doesn't read
    /// it never holds the caller up. One that ended without reading it fails the write (EPIPE: no SIGPIPE, the
    /// launcher sees to that).
    private static func write(_ data: Data, to handle: FileHandle) {
        Thread.detachNewThread {
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
}

/// One pipe read to its end on a thread of its own, as it comes: what was read so far is taken once (`take`). After
/// that the pipe is still read to its end (a background job left holding it never blocks on a full pipe) but nothing
/// more is kept: such a job may print for days.
private final class PipeReader: @unchecked Sendable {
    /// Signalled at the end of the pipe.
    let done = DispatchSemaphore(value: 0)
    /// What was read; nil once taken.
    private let data = Locked<Data?>(initialState: Data())

    init(_ handle: FileHandle) {
        Thread.detachNewThread { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                data.withLock { $0?.append(chunk) }
            }
            done.signal()
        }
    }

    /// What was read so far; later chunks are read and dropped.
    func take() -> Data {
        data.withLock { stored in
            defer { stored = nil }
            return stored ?? Data()
        }
    }
}
