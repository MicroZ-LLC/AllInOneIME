#if os(macOS) || os(Linux) || os(Windows)
import Foundation

/// Foundation's `Process`: the core's only use of it (the lint guard, `Scripts/check-core-portable.sh`, keeps it so).
/// On macOS and Linux Foundation starts each program in a process group of its own, so signalling the group reaches
/// what it started too. Windows has neither signals nor groups: nothing is signalled there (its shell is to stop
/// programs with a job object).
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
        if let io = Self.handle(spec.standardOutput) { process.standardOutput = io }
        if let io = Self.handle(spec.standardError) { process.standardError = io }
        let child = FoundationProcess(process)
        if let onExit = spec.onExit { process.terminationHandler = { _ in onExit(child) } }
        try process.run()
        return child
    }

    /// What `Process` takes for `io` (nil: leave it be, the input method's own).
    private static func handle(_ io: ProcessIO) -> Any? {
        switch io {
        case .inherit: return nil
        case .null: return FileHandle.nullDevice
        case let .pipe(pipe): return pipe
        case let .file(handle): return handle
        }
    }

    public func signal(_ signal: ProcessSignal, group: Int32) -> Bool {
        #if os(Windows)
        return false
        #else
        return kill(-group, Self.number(signal)) == 0
        #endif
    }

    public func signal(_ signal: ProcessSignal, process: Int32) -> Bool {
        #if os(Windows)
        return false
        #else
        return kill(process, Self.number(signal)) == 0
        #endif
    }

    #if !os(Windows)
    private static func number(_ signal: ProcessSignal) -> Int32 {
        switch signal {
        case .terminate: return SIGTERM
        case .kill: return SIGKILL
        case .check: return 0
        }
    }
    #endif
}

/// A `Process` once started. (It may be asked about from any thread; this says so to the compiler.)
final class FoundationProcess: LaunchedProcess, @unchecked Sendable {
    let process: Process

    init(_ process: Process) { self.process = process }

    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }
    func waitUntilExit() { process.waitUntilExit() }
}
#endif
