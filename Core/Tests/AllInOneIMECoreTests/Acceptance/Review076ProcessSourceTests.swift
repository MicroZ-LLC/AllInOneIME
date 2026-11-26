import Foundation
import Testing

/// Source checks for platform failures that cannot be reproduced by a macOS process run.
struct Review076ProcessSourceTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Item 30: the termination handler must not keep the launched process alive through itself.
    @Test func terminationHandlerDoesNotRetainItsOwnProcess() throws {
        let launcher = try Self.source("Sources/AllInOneIMECore/Platform/FoundationProcessLauncher.swift")
        #expect(!launcher.contains("process.terminationHandler = { _ in child.ended(nil) }"),
                "Process retains its handler, which retains the child and Process again")
    }

    /// Item 31: a PID alone does not identify the child after Foundation has reaped it.
    @Test func exitWatchDoesNotWaitOnAnUnprotectedPid() throws {
        let launcher = try Self.source("Sources/AllInOneIMECore/Platform/FoundationProcessLauncher.swift")
        #expect(!launcher.contains("waitid(P_PID, id_t(pid)"),
                "the exit watcher can collect a different child if this PID is reused")
    }

    /// Item 32: a group containing only a zombie is no longer a running tree.
    @Test func processTreeCheckDoesNotEquateGroupExistenceWithRunning() throws {
        let launcher = try Self.source("Sources/AllInOneIMECore/Platform/FoundationProcessLauncher.swift")
        #expect(!launcher.contains("var treeIsRunning: Bool { groupExists(process.processIdentifier) }"),
                "kill(group, 0) reports a group whose last member is a zombie as running")
    }

    /// Item 33: the Linux launch path needs the early exit watcher on both C libraries.
    @Test func muslUsesTheEarlyExitWatcher() throws {
        let launcher = try Self.source("Sources/AllInOneIMECore/Platform/FoundationProcessLauncher.swift")
        #expect(!launcher.contains("#if canImport(Glibc)\n        let child = FoundationProcess(process, onExit: spec.onExit)"),
                "Musl uses the late Foundation termination handler while background jobs hold inherited pipes")
    }

    /// Item 34: Windows cannot run the Unix shell named in these cross-platform tests.
    @Test func processOutputTestsDoNotRequireTheUnixShellOnWindows() throws {
        let tests = try Self.source("Tests/AllInOneIMECoreTests/ProcessOutputTests.swift")
        #expect(!tests.contains("URL(fileURLWithPath: \"/bin/sh\")"),
                "ProcessOutputTests hard-codes a shell absent on Windows")
    }
}
