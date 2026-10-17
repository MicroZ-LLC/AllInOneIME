import Foundation
import AllInOneIMECore

/// The real git: /usr/bin/git (which runs the one of Xcode or the command line tools), in `environment`
/// (`ExtensionSources.gitEnvironment`), started in a session of its own: no controlling terminal (ssh can't ask for a
/// host key or a password, even when the command line runs it from Terminal), stdin closed, and stopped after `timeout`
/// with everything it started (its process group).
public struct ProcessGitRunner: GitRunning {
    public var executable: URL
    public var environment: [String: String]
    public var timeout: TimeInterval
    /// Where Xcode or the command line tools may be (`DeveloperTools.folders`): without them, /usr/bin/git only offers
    /// to install them, so it isn't run.
    public var developerFolders: [String]

    public init(executable: URL = URL(fileURLWithPath: "/usr/bin/git"), environment: [String: String],
                timeout: TimeInterval = ExtensionSources.timeout, developerFolders: [String] = DeveloperTools.folders) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
        self.developerFolders = developerFolders
    }

    /// The user's git: the login shell's environment and SSH agent. Slow the first time (the login shell is read): off
    /// the main thread.
    public static func user() async -> ProcessGitRunner {
        ProcessGitRunner(environment: ExtensionSources.gitEnvironment(base: ShellEnvironment.current, login: ShellEnvironment.login))
    }

    public func run(_ arguments: [String], in directory: URL?) async throws -> GitResult {
        if executable.path == "/usr/bin/git", !DeveloperTools.installed(in: developerFolders) {
            throw ExtensionSourceError.gitNotInstalled
        }
        let (executable, environment, timeout) = (self.executable, self.environment, self.timeout)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try Self.runNow(executable, arguments, directory: directory ?? CorePaths.home,
                                    environment: environment, timeout: timeout)
                })
            }
        }
    }

    private static func runNow(_ executable: URL, _ arguments: [String], directory: URL, environment: [String: String],
                               timeout: TimeInterval) throws -> GitResult {
        let out = Pipe(), err = Pipe()
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A new session: no controlling terminal, and a process group of its own to stop. Every signal back to its
        // default and none blocked: the input method ignores SIGTERM and SIGPIPE, and git, inheriting that, would wait
        // forever at exit for an upload-pack its SIGTERM can't stop. Only stdin, stdout and stderr are passed on.
        var defaults = sigset_t()
        sigfillset(&defaults)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var files: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&files)
        defer { posix_spawn_file_actions_destroy(&files) }
        posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&files, out.fileHandleForWriting.fileDescriptor, 1)
        posix_spawn_file_actions_adddup2(&files, err.fileHandleForWriting.fileDescriptor, 2)
        posix_spawn_file_actions_addchdir_np(&files, directory.path)
        let argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable.path, &files, &attributes, argv, envp)
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        guard spawned == 0 else {
            throw ExtensionSourceError.git("Can't start \(executable.path): \(String(cString: strerror(spawned)))")
        }
        let reading = DispatchGroup()
        let captured = Captured()
        for (pipe, isError) in [(out, false), (err, true)] {
            reading.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                captured.set(data, error: isError)
                reading.leave()
            }
        }
        let exited = DispatchSemaphore(value: 0)
        let exit = ExitStatus()
        let child = pid
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            var result = waitpid(child, &status, 0)
            while result == -1, errno == EINTR { result = waitpid(child, &status, 0) }
            if result == -1 { exit.fail(errno) } else { exit.set(status) }
            exited.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            // Its whole group (ssh and whatever else it started).
            kill(-pid, SIGTERM)
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(-pid, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            _ = reading.wait(timeout: .now() + 1)
            throw ExtensionSourceError.timedOut(timeout)
        }
        _ = reading.wait(timeout: .now() + 5)
        let (output, errors) = captured.get()
        if let failure = exit.failure() {
            throw ExtensionSourceError.git("Couldn't wait for \(executable.lastPathComponent): \(String(cString: strerror(failure)))")
        }
        let raw = exit.get()
        let status = (raw & 0x7f) == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)
        return GitResult(status: status, output: String(decoding: output, as: UTF8.self), errors: String(decoding: errors, as: UTF8.self))
    }

    /// What the two pipes held, read on two threads.
    private final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var output = Data(), errors = Data()
        func set(_ data: Data, error: Bool) { lock.withLock { if error { errors = data } else { output = data } } }
        func get() -> (Data, Data) { lock.withLock { (output, errors) } }
    }

    /// How it ended: its wait status, or the error waiting for it gave (errno).
    private final class ExitStatus: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int32 = 0
        private var error: Int32?
        func set(_ status: Int32) { lock.withLock { value = status } }
        func fail(_ code: Int32) { lock.withLock { error = code } }
        func get() -> Int32 { lock.withLock { value } }
        func failure() -> Int32? { lock.withLock { error } }
    }
}
