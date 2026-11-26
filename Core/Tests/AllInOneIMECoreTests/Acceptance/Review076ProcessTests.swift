#if !os(Windows)
import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

// The 0.7.6 review's findings on the Linux child processes (#169), items 30 to 33: `FoundationProcessLauncher` as the
// core's programs start with it on macOS and Linux, each program `/bin/sh` (item 34: on Windows this file isn't built,
// as the core's programs start with `WindowsProcessLauncher` there; ProcessOutputTests still names /bin/sh on Windows).
// The code these are about is Linux's (`#if canImport(Glibc)`): on the Mac they pass and guard the same contract.
//
// Item 31 (`FoundationProcess.watchExit`: `waitid(P_PID, pid, …)` may wait for another child that was given the same
// process ID, once Foundation reaped this one) has no test here: it needs the kernel to hand a process ID out again
// between Foundation's `waitpid` and the watcher's `waitid`, which no test can arrange without a seam, and a seam
// would have to fit the fix chosen. What the fix has to hold, for whoever writes it: the watcher never reports, as
// this program's end or status, the end of a process it didn't start. A test could then give the watcher its wait
// (`FoundationProcessLauncher(exitWatch:)`, a closure standing in for `waitid`, returning another process's status
// after Foundation reaped the program) and expect `terminationStatus` to be the program's own.

@Suite(.serialized)
struct Review076ProcessTests {
    /// What a launch left behind once the test let go of it.
    final class Kept: @unchecked Sendable {
        weak var process: (any LaunchedProcess)?
        weak var output: Pipe?
        weak var errors: Pipe?
        weak var input: Pipe?
        let told = Locked(initialState: 0)
    }

    static let shell = URL(fileURLWithPath: "/bin/sh")

    /// `script` run to its end with three pipes, as `CommandRunner` and `ProcessOutput` start a program, everything
    /// of it let go by the time this returns.
    func runAndLetGo(_ script: String, into kept: Kept) throws {
        let output = Pipe(), errors = Pipe(), input = Pipe()
        let spec = LaunchSpec(executable: Self.shell, arguments: ["-c", script], standardInput: .pipe(input),
                              standardOutput: .pipe(output), standardError: .pipe(errors)) { [told = kept.told] _ in
            told.withLock { $0 += 1 }
        }
        let process = try FoundationProcessLauncher().launch(spec)
        (kept.process, kept.output, kept.errors, kept.input) = (process, output, errors, input)
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        _ = try? output.fileHandleForReading.readToEnd()
        _ = try? errors.fileHandleForReading.readToEnd()
    }

    /// Whether `condition` came to hold within `seconds`.
    func eventually(_ seconds: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Item 30. A program that ended, and that nobody keeps, is freed with its pipes: on Linux its termination handler
    /// keeps the `FoundationProcess`, which keeps the `Process`, which keeps the handler (FoundationProcessLauncher's
    /// `process.terminationHandler = { _ in child.ended(nil) }`), so each program started leaks its `Process` and the
    /// descriptors of its three pipes, until the input method has none left.
    @Test func aProgramThatEndedIsFreedWithItsPipes() async throws {
        let kept = Kept()
        try runAndLetGo("printf out; exit 0", into: kept)
        #expect(await eventually(5) { kept.told.withLock { $0 } == 1 }, "its end told once")
        let freed = await eventually(5) { kept.process == nil && kept.output == nil && kept.errors == nil && kept.input == nil }
        #expect(freed, """
            still kept 5 s after it ended: \(kept.process == nil ? "" : "the launched process ")\
            \(kept.output == nil ? "" : "its output pipe ")\(kept.errors == nil ? "" : "its error pipe ")\
            \(kept.input == nil ? "" : "its input pipe")
            """)
    }

    /// The descriptors this process has open now.
    static func openDescriptors() -> Int {
        for folder in ["/proc/self/fd", "/dev/fd"] {
            if let names = try? FileManager.default.contentsOfDirectory(atPath: folder) { return names.count }
        }
        return -1
    }

    /// Item 30, as the user meets it: forty programs later the input method has no more descriptors open than before
    /// (three pipes each, six descriptors: 240 leaked on Linux today; the bound leaves room for what else the test run
    /// opens meanwhile).
    @Test func programsStartedLeaveNoDescriptorsOpen() async throws {
        let warmUp = Kept()
        try runAndLetGo("exit 0", into: warmUp)
        let before = Self.openDescriptors()
        try #require(before > 0, "no list of this process's descriptors")
        for _ in 0..<40 { try runAndLetGo("exit 0", into: Kept()) }
        let settled = await eventually(5) { Self.openDescriptors() < before + 60 }
        #expect(settled, "\(Self.openDescriptors()) descriptors open after 40 programs, \(before) before them")
    }

    /// Item 32. Once the program ended and nothing it started is left in its process group, its tree isn't running,
    /// whether or not Foundation has collected it yet. On Linux a detached job inherits the output pipe, delaying
    /// Foundation's collection of the shell; the shell remains a zombie in its own otherwise empty group. The raw
    /// `kill(-pid, 0)` still finds that group: `treeIsRunning` stays true, and
    /// `CommandRunner.stop` (quitting, an update) waits its whole grace for a tree that has nothing left to end.
    /// (Without `setsid`, as on the Mac, the program just ends: it is collected at once there.)
    @Test func aTreeOfOnlyAnEndedProgramIsntRunning() async throws {
        let ended = Locked(initialState: false)
        let output = Pipe()
        let script = "if command -v setsid >/dev/null 2>&1; then setsid sleep 4 & fi; exit 0"
        let spec = LaunchSpec(executable: Self.shell, arguments: ["-c", script], standardInput: .null,
                              standardOutput: .pipe(output), standardError: .null) { _ in ended.withLock { $0 = true } }
        let process = try FoundationProcessLauncher().launch(spec)
        try #require(await eventually(3) { ended.withLock { $0 } }, "its end wasn't told within 3 s")
        #expect(!process.isRunning)
        // A moment for the Mac's Foundation to collect it; far less than the job's 4 s.
        #expect(await eventually(1) { !process.treeIsRunning },
                "nothing is left in its process group but the ended program itself, and its tree still counts as running")
        let started = Date()
        CommandRunner.stop([process], grace: 2)
        let took = Date().timeIntervalSince(started)
        #expect(took < 1, "stopping a tree that had already ended waited \(took) s of its 2 s grace")
    }

    /// Item 33. A program's end is told when it ends, with its status, while a job it left in the background still
    /// runs (and holds what it inherited): `onExit` and `waitUntilExit` don't wait for the job. Glibc's Linux has a
    /// watcher for it (`FoundationProcess.watchExit`); Musl's has the launch's other patches but not this one
    /// (`#if canImport(Glibc)` where the rest say `canImport(Glibc) || canImport(Musl)`), so there the end comes when
    /// the job ends, 6 s later here.
    @Test func aProgramsEndIsToldWhileItsBackgroundJobStillRuns() async throws {
        let told = Locked<Date?>(initialState: nil)
        let spec = LaunchSpec(executable: Self.shell, arguments: ["-c", "sleep 6 & exit 7"], standardInput: .null,
                              standardOutput: .null, standardError: .null) { _ in told.withLock { $0 = $0 ?? Date() } }
        let started = Date()
        let process = try FoundationProcessLauncher().launch(spec)
        defer { process.kill() }
        let waited = Locked<Date?>(initialState: nil)
        Thread {
            process.waitUntilExit()
            waited.withLock { $0 = Date() }
        }.start()
        let both = await eventually(3) { told.withLock { $0 } != nil && waited.withLock { $0 } != nil }
        let after = { (date: Date?) in date.map { String(format: "%.2f s", $0.timeIntervalSince(started)) } ?? "not yet" }
        #expect(both, "3 s after `exit 7`, its job still running: onExit \(after(told.withLock { $0 })), waitUntilExit \(after(waited.withLock { $0 }))")
        #expect(!process.isRunning)
        #expect(process.terminationStatus == 7)
        #expect(process.treeIsRunning, "its job is still in its process group")
    }
}
#endif
