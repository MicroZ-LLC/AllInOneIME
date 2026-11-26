import Foundation
import Testing
@testable import AllInOneIMECore

/// Reproduces item 26: `LanguagePackLibrary.unpack` launches `tar` with no timeout and waits until EOF/exit.
///
/// Seam: `unpack` already runs `tar` through `Platform.current.processes`, so this test substitutes a fake `tar`
/// script that ignores SIGTERM. Because `unpack(_:into:)` has no timeout parameter today, a production timeout
/// (e.g. 60-300 s) can honor an optional positive `TimeInterval` override in
/// `Platform.current.processes.environment["ALLINONEIME_TAR_TIMEOUT"]` (set to `"0.3"` here) so this test stays fast.
struct LanguagePackTarTimeoutAcceptanceTests {
    struct SubstituteTar: ProcessLauncher {
        let executable: URL
        let base = FoundationProcessLauncher()
        var canLaunch: Bool { base.canLaunch }
        var environment: [String: String] {
            base.environment.merging(["ALLINONEIME_TAR_TIMEOUT": "0.3"]) { _, new in new }
        }
        var loginEnvironment: [String: String] { base.loginEnvironment }
        func isRunnable(_ program: URL) -> Bool { base.isRunnable(program) }
        func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess {
            var redirected = spec
            redirected.executable = executable
            return try base.launch(redirected)
        }
    }

    @Test func tarThatIgnoresTermReturnsWithinItsTimeout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tar-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("tar")
        // Self-kill at 3 s keeps the reproduction finite while `unpack` has no timeout.
        let script = """
            #!/bin/sh
            trap '' TERM
            (sleep 3; kill -KILL $$) >/dev/null 2>&1 &
            head -c 100000 /dev/zero >&2
            while :; do sleep 0.2 >/dev/null 2>&1; done
            """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let platform = Platform(processes: SubstituteTar(executable: executable))
        let started = Date()
        let result = Result {
            try Platform.$override.withValue(platform) {
                try LanguagePackLibrary.unpack(directory.appendingPathComponent("unused.tar.xz"), into: directory)
            }
        }
        if case .success = result { Issue.record("a stuck tar completed without an error") }
        #expect(Date().timeIntervalSince(started) < 2, "tar ignored SIGTERM and kept installation waiting")
    }
}
