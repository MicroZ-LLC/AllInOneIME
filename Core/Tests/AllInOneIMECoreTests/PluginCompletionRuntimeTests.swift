import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

#if !os(Windows)
/// The completion runtime's child process (`PluginCompletionRuntime`, `CommandRunner.output`): what it is given and what
/// it does with a script that hangs, prints too much, crashes or is no longer wanted. A shell script stands in for the
/// input method's binary (`--run-plugin <folder> --completion load|query`), so these need no build of the app.
struct PluginCompletionRuntimeTests {
    /// A folder with a stand-in executable running `body` (sh), its arguments written to `arguments` beside it.
    final class StandIn {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("completion-runtime-\(UUID().uuidString)", isDirectory: true)
        var executable: URL { folder.appendingPathComponent("allinoneime") }
        var arguments: URL { folder.appendingPathComponent("arguments") }

        init(_ body: String) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(arguments.path)'\n\(body)\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        var runtime: PluginCompletionRuntime { PluginCompletionRuntime(executable: executable.path) }
    }

    static let plugin = InstalledPlugin(manifest: PluginManifest(name: "github", version: "1.0.0", type: .script, script: "main.js"),
                                        directory: URL(fileURLWithPath: "/tmp/plugins/github", isDirectory: true), isLocal: true)
    static let issues = CompletionSource(name: "issues", title: LocalizedText(en: "Issues"), prefix: "#", list: true, query: true,
                                         queryMinChars: 2)

    static func call(timeout: TimeInterval) -> CompletionCall {
        CompletionCall(plugin: plugin, source: issues,
                       context: CompletionContext(source: "issues", preferences: ["repos": "octo-org/octo-repo", "token": "t0ken"],
                                                  language: .english),
                       timeout: timeout, hosts: ["api.github.com"])
    }

    /// What it runs: `--run-plugin <folder> --completion query`, nothing else on the command line; the `ctx` (passwords
    /// too), the query's text and the hosts approved on standard input; what it prints comes back as it is.
    @Test func itRunsTheChildWithEverythingOnStandardInput() async throws {
        let standIn = try StandIn("cat")
        let output = try await standIn.runtime.query("12", Self.call(timeout: 10))
        let input = try JSONDecoder().decode(PluginHost.CompletionInput.self, from: output)
        #expect(input == PluginHost.CompletionInput(Self.call(timeout: 10).context, text: "12", hosts: ["api.github.com"]))
        let arguments = try String(contentsOf: standIn.arguments, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(arguments == ["--run-plugin", "/tmp/plugins/github", "--completion", "query"], "\(arguments)")
        #expect(!arguments.contains { $0.contains("t0ken") })
    }

    /// A script that hangs is stopped at the call's timeout, well before it would end.
    @Test func aScriptThatHangsIsStoppedAtItsTimeout() async throws {
        let standIn = try StandIn("sleep \(Timing.longSleep)")
        let started = Date()
        await #expect(throws: CommandRunner.RunError.timedOut(0.5)) { try await standIn.runtime.load(Self.call(timeout: 0.5)) }
        #expect(Date().timeIntervalSince(started) < Timing.wellBeforeLongSleep)
    }

    /// One that prints more than a list may be (4 MiB, and room for its JSON) is stopped, and fails.
    @Test func aScriptThatPrintsTooMuchIsStopped() async throws {
        let standIn = try StandIn("head -c 6000000 /dev/zero | tr '\\\\000' x")
        await #expect(throws: CommandRunner.RunError.tooMuchOutput) { try await standIn.runtime.load(Self.call(timeout: 20)) }
    }

    /// One that crashes (or exits with an error) fails, with what it said on standard error.
    @Test func aScriptThatCrashesFails() async throws {
        let crash = try StandIn("kill -SEGV $$")
        await #expect(throws: CommandRunner.RunError.self) { try await crash.runtime.load(Self.call(timeout: 10)) }
        let failing = try StandIn("echo 'Plugin github: no script' >&2; exit 1")
        await #expect(throws: CommandRunner.RunError.failed(status: 1, message: "Plugin github: no script")) {
            try await failing.runtime.load(Self.call(timeout: 10))
        }
    }

    /// A call no longer wanted (a newer token's query in its place) is cancelled as its task is: the child stops at once,
    /// not at its timeout.
    @Test func aCancelledCallStopsItsChild() async throws {
        let placeholder = try StandIn("")
        let pidFile = placeholder.folder.appendingPathComponent("pid")
        let standIn = try StandIn("echo $$ > '\(pidFile.path)'; exec sleep \(Timing.longSleep * 2)")
        let runtime = standIn.runtime
        let task = Task { try await runtime.query("12", Self.call(timeout: Double(Timing.longSleep * 4))) }
        // Started (under load, the first program run may wait for the user's shell's PATH).
        var pid: Int32?
        let waiting = Date()
        while pid == nil, Date().timeIntervalSince(waiting) < Double(Timing.longSleep) {
            try await Task.sleep(for: .milliseconds(50))
            pid = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        let child = try #require(pid, "the child started")
        let cancelled = Date()
        task.cancel()
        _ = try? await task.value
        #expect(Date().timeIntervalSince(cancelled) < Timing.wellBeforeLongSleep)
        // Gone (asked to end, killed after a grace): signal 0 reaches no process.
        let deadline = Date().addingTimeInterval(5)
        while kill(child, 0) == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(kill(child, 0) != 0, "the child \(child) still runs")
    }
}
#endif
