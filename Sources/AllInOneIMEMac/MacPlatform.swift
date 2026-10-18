import Foundation
import AllInOneIMECore

extension Platform {
    /// The Mac's: the core's Apple defaults (Keychain, JavaScriptCore, Foundation Models, NaturalLanguage,
    /// NSDataDetector, PDFKit), and programs started with the login shell's environment (`MacProcessLauncher`).
    /// The input method, its command line and the installer install it at launch.
    ///
    /// The keys: in the input method signed with the provisioning profile (entitled to the shared keychain access group),
    /// the data protection keychain, synced through iCloud Keychain as the config says (`KeySync.system`, its switch set
    /// here); anywhere else (a development or ad-hoc build, the command line, the installer) the login keychain, as before.
    public static var mac: Platform {
        var platform = Platform()
        platform.processes = MacProcessLauncher()
        if let keys = KeySync.system {
            keys.start(syncing: ((try? Config.load()) ?? .default).iCloudSync.syncsKeys)
            platform.secrets = keys.store
        }
        return platform
    }
}

/// Programs as the input method starts them on the Mac: Foundation's `Process` (`FoundationProcessLauncher`), with the
/// PATH and variables of the user's login shell (`ShellEnvironment`: an input method started by launchd has neither),
/// and a developer-tools stand-in in /usr/bin counted only with Xcode or the command line tools (`DeveloperTools`).
public struct MacProcessLauncher: ProcessLauncher {
    private let base = FoundationProcessLauncher()
    /// Where Xcode or the command line tools are looked for, each time (`DeveloperTools.folders`; tests give their own).
    private let developerFolders: @Sendable () -> [String]

    public init(developerFolders: @escaping @Sendable () -> [String] = { DeveloperTools.folders }) {
        self.developerFolders = developerFolders
    }

    public var canLaunch: Bool { true }
    public var environment: [String: String] { ShellEnvironment.current }
    public var loginEnvironment: [String: String] { ShellEnvironment.login }

    public func isRunnable(_ program: URL) -> Bool {
        !DeveloperTools.isStandIn(program) || DeveloperTools.installed(in: developerFolders())
    }

    public func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess { try base.launch(spec) }
}
