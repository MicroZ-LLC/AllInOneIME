import AllInOneIMECore
import Foundation
import Testing

/// Reproduces item 26: `Spotlight.mdfind` only sends SIGTERM at its deadline (`Stopper`) and never escalates
/// to SIGKILL, so a child that ignores SIGTERM blocks `@open` until it exits on its own.
struct SpotlightProcessTimeoutAcceptanceTests {
    @Test func mdfindEscalatesWhenTheChildIgnoresTermination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mdfind-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("mdfind")
        // Self-kill at 3 s bounds the current broken implementation without hanging the test run.
        let script = """
            #!/bin/sh
            trap '' TERM
            (sleep 3; kill -KILL $$) >/dev/null 2>&1 &
            printf ready
            while :; do sleep 0.2 >/dev/null 2>&1; done
            """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let spotlight = Spotlight(until: .now() + 0.4, executable: executable)
        let started = Date()
        let output = await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: spotlight.mdfind([])) }.start()
        }
        #expect(output == Data("ready".utf8))
        #expect(Date().timeIntervalSince(started) < 2, "mdfind ignored SIGTERM and kept the search waiting")
    }
}
