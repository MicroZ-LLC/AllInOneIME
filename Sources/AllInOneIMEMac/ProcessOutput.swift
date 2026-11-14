import AllInOneIMECore
import Foundation

/// A program run to its end for what it printed (`AgentMonitor` runs `claude agents` and `claude --bg` so): its exit
/// status, standard output and standard error (read at once, so that neither pipe fills up), its standard input closed;
/// ended with what it started (SIGTERM, then SIGKILL) after `timeout` seconds, the run failing then (`TimedOut`). Its
/// end is told by its termination handler
/// (`LaunchSpec.onExit`), as the question sessions' launcher learns of it (`ProcessClaudeSessionLauncher`): never by
/// `waitUntilExit` on a dispatch thread, which missed about one exit in ten (and then never returned).
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

    /// Runs `executable` with `arguments` (in `directory`, with `environment`; nil: the launcher's) through `processes`;
    /// blocks the calling thread until it ended and what it printed was read. Throws `TimedOut` when that took longer
    /// than `timeout`.
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           directory: URL? = nil, timeout: TimeInterval,
                           processes: any ProcessLauncher = Platform.current.processes) throws -> Result {
        let out = Pipe(), errors = Pipe()
        let ended = DispatchSemaphore(value: 0)
        let launched = try processes.launch(LaunchSpec(executable: executable, arguments: arguments, environment: environment,
                                                       directory: directory, standardInput: .null, standardOutput: .pipe(out),
                                                       standardError: .pipe(errors), onExit: { _ in ended.signal() }))
        let output = Locked(initialState: Data())
        let said = Locked(initialState: Data())
        let outputRead = DispatchSemaphore(value: 0), errorsRead = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            output.withLock { $0 = data }
            outputRead.signal()
        }
        Thread.detachNewThread {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            said.withLock { $0 = data }
            errorsRead.signal()
        }
        let deadline = DispatchTime.now() + timeout
        let exited = ended.wait(timeout: deadline) == .success
        let outputDone = outputRead.wait(timeout: deadline) == .success
        let errorsDone = errorsRead.wait(timeout: deadline) == .success
        if exited && outputDone && errorsDone {
            return Result(status: launched.terminationStatus, output: output.withLock { $0 }, errors: said.withLock { $0 })
        }
        launched.terminate()
        if !exited { _ = ended.wait(timeout: .now() + 0.5) }
        if launched.treeIsRunning {
            launched.kill()
            if !exited { _ = ended.wait(timeout: .now() + 0.2) }
        }
        // The pipes are left to their readers (they end once the last writer has): closed under a read, a descriptor
        // could be another file's by the time it reads again.
        throw TimedOut(program: executable.lastPathComponent, seconds: timeout)
    }
}
