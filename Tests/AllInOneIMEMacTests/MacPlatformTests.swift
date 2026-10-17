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
