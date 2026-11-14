import Foundation
import AllInOneIMECore

/// The environment a program started from the input method gets: the input method's own, with the
/// PATH of the user's login shell (an input method started by launchd only has the system folders,
/// so `python3` from Homebrew, pyenv or nvm wouldn't be found). The shell is asked once, in the background at launch
/// (`warmUp`); the main thread never waits for it (`path`, `readiness`).
public enum ShellEnvironment {
    public static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// How long the login shell has to start and print (`loginValues`). What it gave is kept for the session, so a
    /// shell cut off on a busy Mac (at login, as everything starts; in a loaded test run 3 s were once not enough)
    /// leaves the fallback PATH and no keys until the input method restarts: generous, as only a shell that hangs
    /// waits it out.
    static let loginTimeout: TimeInterval = 10

    public static let current: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = login["PATH"] ?? fallbackPath
        return env
    }()

    /// `current` with the login shell's values of `names` the input method's own environment doesn't set (or sets
    /// empty): what a program that needs more of the user's setup than PATH starts with (a question session's agent,
    /// `SessionAgent.environmentVariables`: its settings folder, its key, its provider). The values are passed on, never
    /// logged.
    public static func current(with names: [String]) -> [String: String] {
        var env = current
        for name in names where env[name]?.isEmpty != false {
            if let value = login[name] { env[name] = value }
        }
        return env
    }

    /// The variables the input method reads from the user's shell: PATH, the providers' API keys
    /// (`Provider.keyVariables`), for a key that is set there instead of in the keychain, the SSH agent and ssh command git uses (`ExtensionSources.gitEnvironment`),
    /// the AWS variables Bedrock's credentials may come from (`AWSEnvironment`), and what the questions' sessions need
    /// (`SessionAgent.environmentVariables`).
    public static let login: [String: String] = {
        let values = loginValues(["PATH"] + Provider.allCases.flatMap(\.keyVariables)
                                 + ["SSH_AUTH_SOCK", "GIT_SSH_COMMAND"]
                                 + AWSEnvironment.variables + SessionAgent.environmentVariables)
        readiness.markReady()
        return values
    }()

    /// Whether the login shell has answered (`login` read, by whoever asked first). Until then the main thread doesn't ask
    /// it, which would wait for the shell (a `.zshrc` that takes seconds held the first text field's focus, and the keys
    /// typed meanwhile, that long; one that hangs, `loginTimeout`): it takes the fallback (`path`) and asks again once
    /// the shell has answered (`ShellReadiness.whenReady`).
    public static let readiness = ShellReadiness { DispatchQueue.global(qos: .utility).async { _ = current } }

    /// Reads the login shell in the background, once: the input method at launch; else the main thread's first question.
    public static func warmUp() { readiness.start() }

    /// The PATH programs are looked for on: the login shell's (`current`'s). On the main thread never waited for: the
    /// fallback PATH until the shell has answered (`readiness`, the read started then), so an answer found on it isn't
    /// to be kept. Anywhere else waited for, as `current` is.
    public static var path: String {
        readiness.value(fallback: fallbackPath) { current["PATH"] ?? fallbackPath }
    }

    /// `names` as the user's interactive login shell sets them up (unset ones are left out): those it printed in
    /// `loginTimeout` seconds, none if it printed nothing by then.
    static func loginValues(_ names: [String]) -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = "__AllInOneIME_\(UUID().uuidString)__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Interactive too: pyenv, nvm and the like are usually set up in .zshrc. Each value is printed
        // between markers, so whatever the shell's startup files print is skipped.
        let script = names.map { "printf '\(marker)\($0)=%s' \"${\($0)}\"" }.joined(separator: "; ") + "; printf '\(marker)'"
        process.arguments = ["-ilc", script]
        process.currentDirectoryURL = CorePaths.home
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        // Read as it comes, up to the last marker, not to the end: a job the startup files leave in the background
        // (`foo &!`, `nohup foo &`) keeps the output open after the shell has exited, until the job ends. The reading
        // goes on until then, on its own, so the job never waits on a full pipe.
        let output = LoginOutput(marker: marker, markers: names.count + 1)
        let reading = out.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = reading.availableData
                output.add(data)
                if data.isEmpty { break }
            }
        }
        if output.complete.wait(timeout: .now() + loginTimeout) == .timedOut, process.isRunning {
            process.terminate()
        }
        var values: [String: String] = [:]
        // The part after the last marker is what came after the values, or a value cut off at the timeout.
        for part in output.take().components(separatedBy: marker).dropFirst().dropLast() {
            guard let eq = part.firstIndex(of: "="), names.contains(String(part[..<eq])) else { continue }
            let value = String(part[part.index(after: eq)...])
            if !value.isEmpty { values[String(part[..<eq])] = value }
        }
        return values
    }
}

/// Whether the login shell has answered (`ShellEnvironment.readiness`; a test makes its own), and what waits for that on
/// the main thread.
public final class ShellReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var ready: Bool
    private var started = false
    private var waiting: [@MainActor @Sendable () -> Void] = []
    /// Reads the shell in the background, `markReady` once it has answered.
    private let read: @Sendable () -> Void

    /// `ready`: answered already; `read`: reads the shell in the background (asked once, by `start`).
    public init(ready: Bool = false, read: @escaping @Sendable () -> Void = {}) {
        self.ready = ready
        self.read = read
    }

    public var isReady: Bool { lock.withLock { ready } }

    /// Starts reading the shell (`read`), unless it has answered or is being read.
    public func start() {
        let starts = lock.withLock { () -> Bool in
            guard !ready, !started else { return false }
            started = true
            return true
        }
        if starts { read() }
    }

    /// The shell has answered: what waits for it (`whenReady`) runs on the main thread.
    public func markReady() {
        let actions = lock.withLock { () -> [@MainActor @Sendable () -> Void] in
            ready = true
            defer { waiting = [] }
            return waiting
        }
        guard !actions.isEmpty else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { for action in actions { action() } } }
    }

    /// Runs `action` on the main thread once the shell has answered (the read started if it wasn't); soon, after what
    /// is queued there, when it has already.
    public func whenReady(_ action: @escaping @MainActor @Sendable () -> Void) {
        let waits = lock.withLock { () -> Bool in
            guard !ready else { return false }
            waiting.append(action)
            return true
        }
        if waits {
            start()
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
        }
    }

    /// `value()`, what the shell gave (waited for), once it has answered or off the main thread; on the main thread
    /// before then, `fallback`, never waited for (the read started).
    public func value<Value>(onMainThread: Bool = Thread.isMainThread, fallback: Value, _ value: () -> Value) -> Value {
        guard onMainThread, !isReady else { return value() }
        start()
        return fallback
    }
}

/// What the login shell prints (`ShellEnvironment.loginValues`), as it comes: complete once its last marker or the end
/// of the output is there. Nothing that comes after that, or after it has been taken, is kept.
private final class LoginOutput: @unchecked Sendable {
    let complete = DispatchSemaphore(value: 0)
    private let marker: String
    private let markers: Int
    private let lock = NSLock()
    private var data = Data()
    private var done = false

    /// `markers`: how many the shell prints.
    init(marker: String, markers: Int) {
        self.marker = marker
        self.markers = markers
    }

    /// Adds what was read; an empty chunk is the end of the output.
    func add(_ chunk: Data) {
        let completed = lock.withLock { () -> Bool in
            guard !done else { return false }
            data.append(chunk)
            done = chunk.isEmpty || String(decoding: data, as: UTF8.self).components(separatedBy: marker).count > markers
            return done
        }
        if completed { complete.signal() }
    }

    /// What has come so far.
    func take() -> String {
        lock.withLock {
            done = true
            return String(decoding: data, as: UTF8.self)
        }
    }
}

/// The stand-ins macOS keeps in /usr/bin for the developer tools: `python3`, `git`, `make`, `swift` and
/// the others are one small program (hard links of one file) that runs the real tool from Xcode or the
/// command line tools, and without those only offers to install them.
public enum DeveloperTools {
    /// Where Xcode or the command line tools may be: the folder chosen with `xcode-select -s`, then the
    /// default places.
    public static var folders: [String] {
        let chosen = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")
        return (chosen.map { [$0] } ?? []) + ["/Applications/Xcode.app/Contents/Developer", "/Library/Developer/CommandLineTools"]
    }

    /// Whether one of `folders` has the tools.
    public static func installed(in folders: [String]) -> Bool {
        folders.contains { folder in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: folder + "/usr/bin", isDirectory: &isFolder) && isFolder.boolValue
        }
    }

    /// Whether `url` (after symbolic links) is the same file as `standIn`: /usr/bin/python3 has been one
    /// of the stand-ins on every macOS since 10.15.
    public static func isStandIn(_ url: URL, standIn: String = "/usr/bin/python3") -> Bool {
        var file = stat(), known = stat()
        guard stat(url.path, &file) == 0, stat(standIn, &known) == 0 else { return false }
        return file.st_dev == known.st_dev && file.st_ino == known.st_ino
    }
}

extension CommandRunner {
    /// `isInstalled` as the Mac has it (`MacProcessLauncher.isRunnable`), with the developer tools looked for in
    /// `developerFolders`.
    public static func isInstalled(_ program: String, path: String?, developerFolders: [String]) -> Bool {
        guard let url = resolve(program, path: path) else { return false }
        return MacProcessLauncher(developerFolders: { developerFolders }).isRunnable(url)
    }
}
