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
        #if canImport(Glibc) || canImport(Musl)
        // Linux refuses to start a program file open for writing (ETXTBSY), and one just written stays open in each
        // program another thread starts meanwhile, until it runs: a script written and started at once can fail to
        // start (one start in eight, with programs starting on six other threads), and starts a moment later. Tried
        // again a few times, each in a Process of its own (a Process starts once), only while the program is there and
        // executable: one that is missing or can't run fails at once, as on the Mac.
        for _ in 0..<4 {
            if let started = try? Self.unblocked({ try start(spec) }) { return started }
            guard FileManager.default.isExecutableFile(atPath: spec.executable.path) else { break }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return try Self.unblocked { try start(spec) }
        #else
        return try start(spec)
        #endif
    }

    #if canImport(Glibc) || canImport(Musl)
    /// `body` (a program started) with no signal blocked on this thread, its mask as it was after. A program starts with
    /// the signal mask of the thread that starts it, and libdispatch's threads block nearly every signal (SIGTERM,
    /// SIGINT, SIGCHLD …): started from one (`CommandRunner` starts programs on a queue), it could never be asked to end,
    /// only killed. Started with none blocked, as a shell starts it; only while it starts, never across a wait.
    private static func unblocked<T>(_ body: () throws -> T) rethrows -> T {
        var none = sigset_t(), mask = sigset_t()
        sigemptyset(&none)
        pthread_sigmask(SIG_SETMASK, &none, &mask)
        defer { pthread_sigmask(SIG_SETMASK, &mask, nil) }
        return try body()
    }
    #endif

    /// `spec` started in a new Process.
    private func start(_ spec: LaunchSpec) throws -> FoundationProcess {
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
        #if canImport(Glibc) || canImport(Musl)
        // Foundation's own word of its end comes late on Linux, with either C library (`FoundationProcess.watchExit`).
        let child = FoundationProcess(process, onExit: spec.onExit)
        try child.start()
        #else
        let child = FoundationProcess(process)
        if let onExit = spec.onExit { process.terminationHandler = { _ in onExit(child) } }
        do {
            try process.run()
        } catch {
            // Never started, its handler never runs: let go here, or it would keep the child, and the child the Process.
            process.terminationHandler = nil
            throw error
        }
        #endif
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

    #if canImport(Glibc) || canImport(Musl)
    /// Told once it ended (`LaunchSpec.onExit`).
    private let onExit: ((any LaunchedProcess) -> Void)?

    init(_ process: Process, onExit: ((any LaunchedProcess) -> Void)? = nil) {
        self.process = process
        self.onExit = onExit
        ending.enter()
    }
    #else
    init(_ process: Process) { self.process = process }
    #endif

    var processIdentifier: Int32 { process.processIdentifier }
    #if canImport(Glibc) || canImport(Musl)
    var isRunning: Bool { status.withLock { $0 == nil } && process.isRunning }
    var terminationStatus: Int32 { status.withLock { $0 } ?? process.terminationStatus }
    // swiftlint:disable:next blocking_call - the caller's own thread waits, as with Process.waitUntilExit (never main)
    func waitUntilExit() { ending.wait() }

    /// Its exit status once it ended, as told first: by `watchExit` or by Foundation.
    private let status = Locked<Int32?>(initialState: nil)
    /// Left once it ended.
    private let ending = DispatchGroup()

    /// The programs whose end a `watchExit` thread waits for, each by its process ID. Held while a program starts: a
    /// watcher that finds another program under its ID knows its own was collected by Foundation and the ID given out
    /// again (`watchExit`).
    private static let watched = Locked(initialState: [Int32: ObjectIdentifier]())

    /// Starts it, its end told by Foundation or by `watchExit`, whichever comes first. The termination handler keeps
    /// this object until it ran (the end is told even to a caller that kept nothing), and the Process keeps its
    /// handler: let go once it ran, or when the program never started. Left in place, every program started stayed in
    /// memory with its Process and its pipes' descriptors.
    func start() throws {
        process.terminationHandler = { [self] process in
            ended(nil)
            process.terminationHandler = nil
        }
        do {
            try Self.watched.withLock { watched in
                try process.run()
                watched[process.processIdentifier] = ObjectIdentifier(self)
            }
        } catch {
            process.terminationHandler = nil
            // Nothing will end: the group is left as it was entered (libdispatch crashes on one freed while entered).
            ending.leave()
            throw error
        }
        watchExit()
    }

    /// Its end told as soon as it comes. Foundation on Linux learns of a program's end only when every process that
    /// inherited its descriptors has gone too: `sh -c "job & exit 0"` ended at once, but its termination handler came
    /// when `job` ended, seconds or days later (a login shell's startup files can leave such a job; the Linux CI's
    /// ProcessOutputTests.whatItLeftRunningDoesntHoldTheRunUp, 3 of 3). That is Foundation's own way of waiting (a
    /// socket the program's descendants inherit), whatever the C library: Musl as Glibc. `waitid` with WNOWAIT, on a
    /// thread of its own, sees the end at once without collecting it: Foundation still reaps the program, when it gets
    /// there. Its status is `si_status`: the exit code, or the signal that ended it, as Foundation's
    /// `terminationStatus` tells them.
    ///
    /// A process ID alone doesn't say whose end `waitid` saw: once Foundation collected this program, the next one
    /// started may be given its ID, and `waitid` then waits for that one. Every program is started under `watched`'s
    /// lock and put there under its ID, so what `waitid` saw counts only while this program is still the one there: a
    /// program that took its ID has replaced it by the time the lock is had (it can't have ended before it started,
    /// under the lock), and this one's end is then Foundation's to tell.
    private func watchExit() {
        let pid = process.processIdentifier
        let id = id_t(pid)
        Thread.detachNewThread { [self] in
            var info = siginfo_t()
            var result: Int32
            repeat { result = waitid(P_PID, id, &info, WEXITED | WNOWAIT) } while result == -1 && errno == EINTR
            let own = Self.watched.withLock { watched -> Bool in
                guard watched[pid] == ObjectIdentifier(self) else { return false }
                watched[pid] = nil
                return true
            }
            // Failed (ECHILD: Foundation reaped it first) or another program's end: its termination handler tells it.
            if result == 0, own { ended(childStatus(info)) }
            // Foundation on Linux lets go of a Process (and so of its pipes' descriptors) only once something waited for
            // it with its own waitUntilExit: a program nobody waited for stayed in memory, its handler cleared or not
            // (measured with swift:6.4). This thread is the one that waits, until Foundation knows of the end too.
            // swiftlint:disable:next blocking_call - this thread of its own, never main
            process.waitUntilExit()
        }
    }

    /// It ended with `told` (nil: Foundation's word, its `terminationStatus`); `onExit` told once, the first time.
    func ended(_ told: Int32?) {
        let first = status.withLock { stored -> Bool in
            guard stored == nil else { return false }
            stored = told ?? process.terminationStatus
            return true
        }
        guard first else { return }
        ending.leave()
        onExit?(self)
    }
    #else
    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }
    func waitUntilExit() { process.waitUntilExit() }
    #endif

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
    var treeIsRunning: Bool { groupIsRunning(process.processIdentifier) }
    func terminate() -> Bool { signalTree(process.processIdentifier, SIGTERM) }
    func kill() -> Bool { signalTree(process.processIdentifier, SIGKILL) }
    #endif
}

#if !os(Windows)
/// Whether process group `pid` still has a process running in it. On Linux a program that ended stays in its group
/// until Foundation collects it, which can be long after (`FoundationProcess.watchExit`): a group of such only (`kill`
/// still finds it) has nothing left to wait for or to end.
private func groupIsRunning(_ pid: Int32) -> Bool {
    guard pid > 0, kill(-pid, 0) == 0 else { return false }
    #if canImport(Glibc) || canImport(Musl)
    return groupHasLiving(pid)
    #else
    return true
    #endif
}

#if canImport(Glibc) || canImport(Musl)
/// `si_status` of what `waitid` told of a child (SIGCHLD's fields): after `si_signo`, `si_errno` and `si_code`, aligned
/// as the pointers beside it, then `si_pid` and `si_uid`. Read at its place, which is the kernel's on every Linux,
/// where Glibc and Musl name the fields on the way to it differently.
private func childStatus(_ info: siginfo_t) -> Int32 {
    let offset = MemoryLayout<Int>.size == 8 ? 24 : 20
    return withUnsafeBytes(of: info) { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
}

/// The state ("R", "S", "Z" for one that ended and wasn't collected yet …) and the process group of process `pid`, as
/// /proc/<pid>/stat has them ("pid (name) state parent group …"; the name may hold spaces and brackets, so read from
/// its last bracket on); nil when the process is gone or there is no /proc.
private func stateAndGroup(_ pid: Int32) -> (state: Substring, group: Int32)? {
    let file = open("/proc/\(pid)/stat", O_RDONLY | O_CLOEXEC)
    guard file >= 0 else { return nil }
    defer { close(file) }
    var bytes = [UInt8](repeating: 0, count: 512)
    let count = read(file, &bytes, bytes.count)
    guard count > 0 else { return nil }
    let text = String(decoding: bytes[..<count], as: UTF8.self)
    guard let name = text.lastIndex(of: ")") else { return nil }
    let fields = text[text.index(after: name)...].split(separator: " ")
    guard fields.count >= 3, let group = Int32(fields[2]) else { return nil }
    return (fields[0], group)
}

/// Whether process group `group`, which exists, has a process that hasn't ended: its first one usually (asked first),
/// else any of /proc's. Without /proc nothing says, and it counts as running, as the group is there.
private func groupHasLiving(_ group: Int32) -> Bool {
    func lives(_ pid: Int32) -> Bool {
        guard let process = stateAndGroup(pid) else { return false }
        return process.group == group && process.state != "Z" && process.state != "X"
    }
    if lives(group) { return true }
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return true }
    return names.contains { name in Int32(name).map(lives) ?? false }
}
#endif

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
