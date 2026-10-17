import Foundation
import AllInOneIMECore

extension Platform {
    /// The Mac's: the core's Apple defaults (Keychain, JavaScriptCore, Foundation Models, NaturalLanguage,
    /// NSDataDetector, PDFKit), and programs started with the login shell's environment (`MacProcessLauncher`).
    /// The input method, its command line and the installer install it at launch.
    public static var mac: Platform {
        var platform = Platform()
        platform.processes = MacProcessLauncher()
        return platform
    }
}

/// Programs as the input method starts them on the Mac: Foundation's `Process` (`FoundationProcessLauncher`), with the
/// PATH and variables of the user's login shell (`ShellEnvironment`: an input method started by launchd has neither),
/// and a developer-tools stand-in in /usr/bin counted only with Xcode or the command line tools (`DeveloperTools`).
public struct MacProcessLauncher: ProcessLauncher {
    private let base = FoundationProcessLauncher()

    public init() {}

    public var canLaunch: Bool { true }
    public var environment: [String: String] { ShellEnvironment.current }
    public var loginEnvironment: [String: String] { ShellEnvironment.login }

    public func isRunnable(_ program: URL) -> Bool {
        !DeveloperTools.isStandIn(program) || DeveloperTools.installed(in: DeveloperTools.folders)
    }

    public func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess { try base.launch(spec) }
    public func signal(_ signal: ProcessSignal, group: Int32) -> Bool { base.signal(signal, group: group) }
    public func signal(_ signal: ProcessSignal, process: Int32) -> Bool { base.signal(signal, process: process) }
}
