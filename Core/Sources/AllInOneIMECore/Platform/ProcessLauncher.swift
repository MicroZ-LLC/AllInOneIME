import Foundation

/// Starts programs for the core: `run` commands and script extensions (`CommandRunner`), `@py`, `@js` and plugin
/// scripts (in a child process, through `CommandRunner`), AWS `credential_process` (`AWSProcessRunner`), a language
/// pack's archive (`LanguagePackLibrary`). Foundation's `Process` on macOS and Linux (`FoundationProcessLauncher`; the
/// macOS shell adds the login shell's environment and the developer-tools check), `CreateProcessW` in a job object on
/// Windows (`WindowsProcessLauncher`); none on iOS and Android, where apps have no child processes
/// (`NoProcessLauncher`): the commands that need one aren't offered (`canLaunch`).
public protocol ProcessLauncher: Sendable {
    /// Whether programs can be started here at all.
    var canLaunch: Bool { get }
    /// The environment a program gets when the caller has none of its own.
    var environment: [String: String] { get }
    /// The variables the user set up for their programs (API keys, AWS, the SSH agent): on the Mac, those of the user's
    /// login shell, which an input method started by launchd doesn't inherit.
    var loginEnvironment: [String: String] { get }
    /// Whether `program` (found, executable) really runs: on the Mac, a developer-tools stand-in in /usr/bin only does
    /// with Xcode or the command line tools installed.
    func isRunnable(_ program: URL) -> Bool
    /// Starts a program: in a process group of its own where there are groups (on Windows a job object; what it starts
    /// is in it too), so that stopping it (`LaunchedProcess.terminate`, `kill`) stops what it started too.
    func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess
}

/// Where a program's standard input, output or error goes.
public enum ProcessIO {
    /// The input method's own.
    case inherit
    /// /dev/null.
    case null
    case pipe(Pipe)
    case file(FileHandle)
}

/// A program to start.
public struct LaunchSpec {
    public var executable: URL
    public var arguments: [String]
    /// Nil: the input method's own.
    public var environment: [String: String]?
    /// Nil: the input method's own working directory.
    public var directory: URL?
    public var standardInput: ProcessIO
    public var standardOutput: ProcessIO
    public var standardError: ProcessIO
    /// Called once it ended (on another thread), with what `launch` returned.
    public var onExit: (@Sendable (any LaunchedProcess) -> Void)?

    public init(executable: URL, arguments: [String] = [], environment: [String: String]? = nil, directory: URL? = nil,
                standardInput: ProcessIO = .inherit, standardOutput: ProcessIO = .inherit, standardError: ProcessIO = .inherit,
                onExit: (@Sendable (any LaunchedProcess) -> Void)? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.directory = directory
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.onExit = onExit
    }
}

/// A program started by a `ProcessLauncher`. Stopping it stops what it started too: its whole tree (on macOS and Linux
/// its process group).
public protocol LaunchedProcess: AnyObject, Sendable {
    /// Its process ID (on macOS and Linux its process group's too).
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    /// Whether it or anything it started is still running (on macOS and Linux: its process group is still there).
    var treeIsRunning: Bool { get }
    /// Its exit status, once it ended.
    var terminationStatus: Int32 { get }
    func waitUntilExit()
    /// Asks it and what it started to end (SIGTERM); whether anything was asked (false: all gone).
    @discardableResult func terminate() -> Bool
    /// Ends it and what it started at once (SIGKILL); whether anything was (false: all gone).
    @discardableResult func kill() -> Bool
}

public enum ProcessLaunchError: Error, LocalizedError, Equatable {
    /// No child processes on this platform.
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .unsupported: return "Programs can't be started on this platform"
        }
    }
}

/// No child processes (iOS, Android): nothing starts, and what needs a program isn't offered.
public struct NoProcessLauncher: ProcessLauncher {
    public init() {}
    public var canLaunch: Bool { false }
    public var environment: [String: String] { ProcessInfo.processInfo.environment }
    public var loginEnvironment: [String: String] { [:] }
    public func isRunnable(_ program: URL) -> Bool { false }
    public func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess { throw ProcessLaunchError.unsupported }
}
