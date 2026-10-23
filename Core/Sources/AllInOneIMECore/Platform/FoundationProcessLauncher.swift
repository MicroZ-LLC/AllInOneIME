#if os(macOS) || os(Linux) || os(Windows)
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Foundation's `Process`: the core's only use of it (the lint guard, `Scripts/check-core-portable.sh`, keeps it so).
/// On macOS and Linux Foundation starts each program in a process group of its own, so stopping it (SIGTERM, SIGKILL to
/// the group) reaches what it started too. Windows has neither signals nor groups: there the program alone is ended
/// (`FoundationProcess`), which is why the core's programs start with `WindowsProcessLauncher` there (a job object
/// for each, `Platform.systemProcesses`).
public struct FoundationProcessLauncher: ProcessLauncher {
    public init() {}

    public var canLaunch: Bool { true }
    public var environment: [String: String] { ProcessInfo.processInfo.environment }
    public var loginEnvironment: [String: String] { ProcessInfo.processInfo.environment }
    public func isRunnable(_ program: URL) -> Bool { true }

    public func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess {
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        if let environment = spec.environment { process.environment = environment }
        if let directory = spec.directory { process.currentDirectoryURL = directory }
        if let io = Self.handle(spec.standardInput) { process.standardInput = io }
        #if canImport(Darwin)
        // What is written to its standard input once it ended without reading it fails (EPIPE), and ends nothing else:
        // no SIGPIPE for this process (one that doesn't ignore it, as the input method does: a test run, Settings).
        if case let .pipe(pipe) = spec.standardInput { _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) }
        #elseif canImport(Glibc) || canImport(Musl)
        // The same on Linux, which has no such flag for a pipe: SIGPIPE ignored in this process (`ignoresSIGPIPE`).
        if case .pipe = spec.standardInput { _ = Self.ignoresSIGPIPE }
        #endif
        if let io = Self.handle(spec.standardOutput) { process.standardOutput = io }
        if let io = Self.handle(spec.standardError) { process.standardError = io }
        let child = FoundationProcess(process)
        if let onExit = spec.onExit { process.terminationHandler = { _ in onExit(child) } }
        try process.run()
        return child
    }

    #if canImport(Glibc) || canImport(Musl)
    /// SIGPIPE ignored in this whole process, once, before the first program whose standard input is written to starts.
    /// Linux can't set it off for one pipe (Apple's F_SETNOSIGPIPE), and by default a write to a program that ended
    /// without reading its input would kill the process writing it (exit 141: a test run, the CLI) where it should only
    /// fail with EPIPE, which `CommandRunner` already ignores. Nothing of the core wants SIGPIPE. (Windows has no signals.)
    private static let ignoresSIGPIPE: Void = { _ = signal(SIGPIPE, SIG_IGN) }()
    #endif

    /// What `Process` takes for `io` (nil: leave it be, the input method's own).
    private static func handle(_ io: ProcessIO) -> Any? {
        switch io {
        case .inherit: return nil
        case .null: return FileHandle.nullDevice
        case let .pipe(pipe): return pipe
        case let .file(handle): return handle
        }
    }
}

/// A `Process` once started. (It may be asked about from any thread; this says so to the compiler.)
final class FoundationProcess: LaunchedProcess, @unchecked Sendable {
    let process: Process

    init(_ process: Process) { self.process = process }

    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }
    func waitUntilExit() { process.waitUntilExit() }

    #if os(Windows)
    // No signals or process groups: `Process.terminate()` (TerminateProcess) ends the program at once, but not what it
    // started. (`WindowsProcessLauncher`, the core's on Windows, ends the whole tree: its job object.)
    var treeIsRunning: Bool { process.isRunning }
    func terminate() -> Bool { end() }
    func kill() -> Bool { end() }

    private func end() -> Bool {
        guard process.isRunning else { return false }
        process.terminate()
        return true
    }
    #else
    var treeIsRunning: Bool { groupExists(process.processIdentifier) }
    func terminate() -> Bool { signalTree(process.processIdentifier, SIGTERM) }
    func kill() -> Bool { signalTree(process.processIdentifier, SIGKILL) }
    #endif
}

#if !os(Windows)
/// Whether process group `pid` still has a process in it.
private func groupExists(_ pid: Int32) -> Bool {
    pid > 0 && kill(-pid, 0) == 0
}

/// `number` to process group `pid`, and to process `pid` alone when it has moved to another group (`setsid`); whether
/// it went to any.
private func signalTree(_ pid: Int32, _ number: Int32) -> Bool {
    guard pid > 0 else { return false }
    let group = kill(-pid, number) == 0
    let own = getpgid(pid)
    return (own >= 0 && own != pid && kill(pid, number) == 0) || group
}
#endif
#endif
