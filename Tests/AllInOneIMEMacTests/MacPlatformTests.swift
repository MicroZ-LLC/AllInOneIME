import Foundation
import Testing
@testable import AllInOneIMECore

/// The Mac's platform (`Platform.mac`), as the input method, its command line and the installer install it: programs
/// through `MacProcessLauncher`. Scoped to each test (`Platform.override`), with an in-memory secret store.
struct MacPlatformTests {
    var mac: Platform {
        var platform = Platform.mac
        platform.secrets = .inMemory()
        return platform
    }

    @Test func programsGoThroughTheMacsLauncher() throws {
        let launcher = try #require(Platform.mac.processes as? MacProcessLauncher)
        #expect(launcher.canLaunch)
        // The login shell's PATH (an input method started by launchd has only the system's) and variables.
        #expect(launcher.environment == ShellEnvironment.current)
        #expect(launcher.loginEnvironment == ShellEnvironment.login)
        // The developer tools' stand-ins count only with the tools (`DeveloperTools`).
        for program in ["/usr/bin/python3", "/usr/bin/git", "/bin/sh"].map(URL.init(fileURLWithPath:)) {
            #expect(launcher.isRunnable(program)
                == (!DeveloperTools.isStandIn(program) || DeveloperTools.installed(in: DeveloperTools.folders)))
        }
    }

    /// A program run with no environment of its own gets the login shell's PATH.
    @Test func aProgramGetsTheLoginShellsPath() async throws {
        let command = CustomCommand(name: "path", type: .run, argv: ["/usr/bin/printenv", "PATH"])
        let path = try await Platform.$override.withValue(mac) {
            var text = ""
            for try await update in CommandRunner.run(command, input: "") where update.isFinal { text = update.rawText }
            return text
        }
        #expect(path == ShellEnvironment.current["PATH"])
    }

    /// A key set in the login shell is found there when the keychain has none (`APIKeys.load`).
    @Test func keysFromTheLoginShell() throws {
        let (name, value) = try #require(ShellEnvironment.login.first { $0.key == "PATH" })
        Platform.$override.withValue(mac) {
            #expect(APIKeys.load(account: "test-\(UUID().uuidString)", variables: ["NO_SUCH_VARIABLE_HERE", name]) == value)
            #expect(CommandRunner.isInstalled("sh", path: "/bin"))
            #expect(CommandRunner.isInstalled("python3", path: "/usr/bin")
                == (FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") && DeveloperTools.installed(in: DeveloperTools.folders)))
        }
    }
}

/// The keys' store as `Platform.mac` chooses it: the test process has no keychain entitlement, so it is the login
/// keychain, as in 0.6.4 (an input method signed with the provisioning profile gets `KeySync.system`'s routed store).
struct MacPlatformKeysTests {
    @Test func withoutTheEntitlementKeysStayInTheLoginKeychain() {
        #expect(!APIKeys.Keychain.processIsEntitled)
        #expect(KeySync.system == nil)
        #expect(Platform.mac.secrets.kind == .legacy)
    }
}

/// The keychain access group the Makefile signs the input method with is the one the core queries: KEYCHAIN_GROUPS,
/// its team the Makefile's TEAM_ID (`$(TEAM_ID)`, as 0.7.4 writes it).
struct KeychainGroupTests {
    @Test func theMakefilesGroupIsTheCoresAccessGroup() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)
        let lines = makefile.split(separator: "\n")
        /// The value the Makefile gives `name` (`name := value`).
        func value(_ name: String) -> String? {
            lines.first { $0.split(separator: " ").first.map(String.init) == name }?
                .split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let team = try #require(value("TEAM_ID"), "no TEAM_ID in the Makefile")
        let line = try #require(value("KEYCHAIN_GROUPS"), "no KEYCHAIN_GROUPS in the Makefile")
        let groups = line.replacingOccurrences(of: "$(TEAM_ID)", with: team).split(separator: " ").map(String.init)
        #expect(groups == [KeySync.accessGroup], "KEYCHAIN_GROUPS in the Makefile (\(line)) isn't KeySync.accessGroup")
    }
}
