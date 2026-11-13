import AllInOneIMECore
import Foundation

/// A program run to its end for what it printed (`AgentMonitor` runs `claude agents` and `claude --bg` so): its exit
/// status, standard output and standard error (read at once, so that neither pipe fills up), its standard input closed;
/// ended with what it started (SIGTERM) after `timeout` seconds. Its end is told by its termination handler
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

    /// Runs `executable` with `arguments` (in `directory`, with `environment`; nil: the launcher's) through `processes`;
    /// blocks the calling thread until it ended and what it printed was read.
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           directory: URL? = nil, timeout: TimeInterval,
                           processes: any ProcessLauncher = Platform.current.processes) throws -> Result {
        let out = Pipe(), errors = Pipe()
        let ended = DispatchSemaphore(value: 0)
        let launched = try processes.launch(LaunchSpec(executable: executable, arguments: arguments, environment: environment,
                                                       directory: directory, standardInput: .null, standardOutput: .pipe(out),
                                                       standardError: .pipe(errors), onExit: { _ in ended.signal() }))
        let stop = DispatchWorkItem { launched.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        let output = Locked(initialState: Data())
        let outputRead = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            output.withLock { $0 = data }
            outputRead.signal()
        }
        let said = errors.fileHandleForReading.readDataToEndOfFile()
        outputRead.wait()
        ended.wait()
        stop.cancel()
        return Result(status: launched.terminationStatus, output: output.withLock { $0 }, errors: said)
    }
}
