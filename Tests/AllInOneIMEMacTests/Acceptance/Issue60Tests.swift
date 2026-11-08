@testable import AllInOneIMEMac
import Foundation
import Testing

// Issue #60: reading the login shell can hang the input method for good. The input method reads PATH and the keys from
// the user's interactive login shell (`ShellEnvironment.loginValues`, behind `ShellEnvironment.login` and `.current`,
// warmed at launch; Settings, `@agent`, the Terminal launch and AI requests without a keychain key wait on it from the
// main thread). If .zshrc or .zprofile starts a job in the background without redirecting its output (`foo &!`,
// `nohup foo &`), that job keeps the shell's stdout open after the shell has exited: the 10 s timeout covers only the
// shell exiting, and the read of its output after that waits for the job to end, so typing freezes on every launch.
// Expected: the read ends after the timeout at the latest, with whatever arrived (here, all of it: the shell printed
// everything and exited at once).
//
// The login shell is a zsh of the test's: $SHELL, as the input method reads it, is for the call a small script that runs
// /bin/zsh with ZDOTDIR a folder of the test's, so the user's startup files are never run, and its .zprofile or .zshrc
// adds a folder to PATH and starts `sleep 60` in the background with its output left on the shell's. The jobs are
// killed at the end of the test, so a run where the read hangs ends in seconds too. `ShellEnvironment.login` is read
// first (with the Mac's own shell): nothing else picks the test's shell up while $SHELL is set for the call.

@Suite(.serialized)
struct Issue60Tests {
    /// A startup file and the line in it that starts the background job.
    struct Case: CustomTestStringConvertible, Sendable {
        var file: String
        var line: String
        var testDescription: String { "\(file): \(line)" }

        static let all = [
            Case(file: ".zshrc", line: "/bin/sleep 60 &!"),
            Case(file: ".zprofile", line: "nohup /bin/sleep 60 &"),
        ]
    }

    /// The folder the startup file puts first in PATH: PATH came from the login shell.
    static let folder = "/issue60/bin"

    /// How long the read may take: the 10 s timeout (`ShellEnvironment.loginTimeout`), with room for a loaded Mac.
    static let deadline: TimeInterval = 15

    @Test(arguments: Case.all)
    func aBackgroundJobOfTheStartupFilesDoesNotHangReadingTheLoginShell(_ item: Case) throws {
        _ = ShellEnvironment.login
        let shell = try Issue60Shell(item)
        defer { shell.remove() }

        let result = Issue60Result()
        let started = Date()
        let previous = ProcessInfo.processInfo.environment["SHELL"]
        setenv("SHELL", shell.executable.path, 1)
        Thread.detachNewThread { result.set(ShellEnvironment.loginValues(["PATH"])) }
        // $SHELL is read as the shell is started: put back once the startup file has run.
        shell.waitForJob(timeout: Self.deadline)
        if let previous { setenv("SHELL", previous, 1) } else { unsetenv("SHELL") }

        let values = result.wait(timeout: Self.deadline - Date().timeIntervalSince(started))
        let took = Date().timeIntervalSince(started)
        shell.killJobs()
        _ = result.wait(timeout: 10)  // the read, if it hung, ends with the job

        #expect(shell.jobs.count >= 1, "the startup file's background job didn't start (the test missed its setup)")
        #expect(values != nil, """
            \(item): reading the login shell hadn't ended after \(Int(took)) s: the background job keeps the shell's \
            output open, and the read waits for it to end (60 s) instead of stopping at the \
            \(Int(ShellEnvironment.loginTimeout)) s timeout
            """)
        if let values {
            #expect(values["PATH"]?.hasPrefix(Self.folder + ":") == true,
                    "\(item): the login shell's PATH wasn't read (got \(values["PATH"] ?? "nothing"))")
        }
    }
}

/// A login shell for the test: a script that runs zsh with startup files of its own (ZDOTDIR), one of them starting a job
/// in the background that writes its pid to `pids` and then sleeps with the shell's stdout.
struct Issue60Shell {
    let folder: URL
    var executable: URL { folder.appendingPathComponent("shell") }
    var pids: URL { folder.appendingPathComponent("pids") }

    init(_ item: Issue60Tests.Case) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("Issue60-\(UUID().uuidString)")
        let dotdir = folder.appendingPathComponent("zdotdir")
        try FileManager.default.createDirectory(at: dotdir, withIntermediateDirectories: true)
        try "#!/bin/sh\nZDOTDIR='\(dotdir.path)' exec /bin/zsh \"$@\"\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        // The job's own pid (`$$` before the exec): `sleep` is what holds stdout.
        let job = item.line.replacingOccurrences(
            of: "/bin/sleep 60", with: "/bin/sh -c 'echo $$ >> \"\(pids.path)\"; exec /bin/sleep 60'")
        var files = [".zshrc": "export PATH=\"\(Issue60Tests.folder):$PATH\"\n"]
        files[item.file, default: ""] += job + "\n"
        for (name, text) in files {
            try text.write(to: dotdir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    var jobs: [Int32] {
        ((try? String(contentsOf: pids, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { Int32($0) }
    }

    /// Waits until the startup file has started its job.
    func waitForJob(timeout: TimeInterval) {
        let end = Date().addingTimeInterval(timeout)
        while jobs.isEmpty, Date() < end { Thread.sleep(forTimeInterval: 0.05) }
    }

    func killJobs() {
        for pid in jobs { kill(pid, SIGKILL) }
    }

    func remove() {
        killJobs()
        try? FileManager.default.removeItem(at: folder)
    }
}

/// What `loginValues` returned, from the thread it ran on.
final class Issue60Result: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var values: [String: String]?

    func set(_ values: [String: String]) {
        lock.withLock { self.values = values }
        done.signal()
    }

    /// The values, or nil if they hadn't come in `timeout` seconds.
    func wait(timeout: TimeInterval) -> [String: String]? {
        if let values = lock.withLock({ self.values }) { return values }
        guard done.wait(timeout: .now() + max(timeout, 0)) == .success else { return nil }
        done.signal()
        return lock.withLock { self.values }
    }
}
