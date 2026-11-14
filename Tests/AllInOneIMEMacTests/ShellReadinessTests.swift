import Foundation
import Testing
import AllInOneIMECore

/// The main thread never waits for the login shell (`ShellEnvironment`): a `.zshrc` that took seconds held the first text
/// field's focus that long, and the keys typed meanwhile (the `@question` hand-off's agents were looked up on its PATH).
/// Until the shell has answered (`ShellReadiness`, made here, never the input method's) the main thread takes the
/// fallback PATH, keeps no answer found on it (`ProgramAvailability`), and asks again once the shell has answered.
@MainActor
struct ShellReadinessTests {
    /// How often something ran, on the main thread.
    final class Count {
        var value = 0
    }

    /// Whether `condition` holds within ten seconds, the main thread free meanwhile (what waits runs there).
    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test func beforeTheShellAnswersTheMainThreadTakesTheFallback() {
        let reads = Locked(initialState: 0)
        let readiness = ShellReadiness { reads.withLock { $0 += 1 } }
        #expect(!readiness.isReady)
        // Here, on the main thread: the fallback, the shell never waited for.
        #expect(Thread.isMainThread)
        for _ in 0..<3 {
            #expect(readiness.value(fallback: "/fallback") {
                Issue.record("waited for the login shell on the main thread")
                return "/login"
            } == "/fallback")
        }
        #expect(reads.withLock { $0 } == 1, "the shell is read once, in the background")
        // Anywhere else it is waited for, as before.
        #expect(readiness.value(onMainThread: false, fallback: "/fallback") { "/login" } == "/login")

        readiness.markReady()
        #expect(readiness.isReady)
        #expect(readiness.value(fallback: "/fallback") { "/login" } == "/login", "the shell's, once it has answered")
        readiness.start()
        #expect(reads.withLock { $0 } == 1, "not read again")
    }

    @Test func whatWaitsForTheShellRunsOnTheMainThreadOnceItAnswers() async {
        let reads = Locked(initialState: 0)
        let readiness = ShellReadiness { reads.withLock { $0 += 1 } }
        let ran = Count()
        readiness.whenReady {
            #expect(Thread.isMainThread)
            ran.value += 1
        }
        #expect(reads.withLock { $0 } == 1, "waiting for it starts the read")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(ran.value == 0, "not before it answered")
        // The shell answers on its own thread.
        DispatchQueue.global().async { readiness.markReady() }
        #expect(await eventually { ran.value == 1 })
        readiness.markReady()
        // Asked once it has answered: soon, on the main thread.
        readiness.whenReady { ran.value += 10 }
        #expect(await eventually { ran.value == 11 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(ran.value == 11, "each ran once")
        #expect(reads.withLock { $0 } == 1)
    }

    /// An agent only on the login shell's PATH (nvm's folder, say) isn't on the fallback one: shown as not installed until
    /// the shell has answered, then asked again and found.
    @Test func anAnswerFoundBeforeTheShellAnsweredIsNotKept() async {
        let readiness = ShellReadiness()
        let changed = Count()
        let programs = ProgramAvailability(readiness: readiness) { changed.value += 1 }
        var lookups = 0
        func lookUp(found: Bool) -> () -> Bool {
            { lookups += 1; return found }
        }
        #expect(!programs.installed("codex", lookUp: lookUp(found: false)))
        #expect(!programs.installed("codex", lookUp: lookUp(found: false)))
        #expect(!programs.installed("kiro-cli", lookUp: lookUp(found: false)))
        #expect(lookups == 3, "looked up each time: nothing kept")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changed.value == 0)

        readiness.markReady()
        #expect(await eventually { changed.value == 1 }, "asked again once the shell answered")
        #expect(programs.installed("codex", lookUp: lookUp(found: true)))
        #expect(programs.installed("codex", lookUp: lookUp(found: false)), "kept")
        #expect(lookups == 4)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changed.value == 1, "told once, however often it was asked before")

        programs.forget()  // the settings window opens
        #expect(!programs.installed("codex", lookUp: lookUp(found: false)))
        #expect(lookups == 5)
    }

    /// Once the shell has answered, as before: each program looked up once and kept, nothing told.
    @Test func onceTheShellHasAnsweredAnswersAreKept() async {
        let changed = Count()
        let programs = ProgramAvailability(readiness: ShellReadiness(ready: true)) { changed.value += 1 }
        var lookups = 0
        #expect(programs.installed("claude") { lookups += 1; return true })
        #expect(programs.installed("claude") { lookups += 1; return false })
        #expect(lookups == 1)
        programs.pretend("claude", installed: false)
        #expect(!programs.installed("claude") { lookups += 1; return true })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changed.value == 0 && lookups == 1)
    }
}

/// The input method's own shell: ready once `login` has been read, its PATH the same then on every thread.
struct ShellEnvironmentReadinessTests {
    @Test func readyOnceTheLoginShellHasAnswered() async {
        _ = ShellEnvironment.login  // off the main thread: waited for
        #expect(ShellEnvironment.readiness.isReady)
        #expect(ShellEnvironment.path == ShellEnvironment.current["PATH"])
        let onMain = await MainActor.run { ShellEnvironment.path }
        #expect(onMain == ShellEnvironment.current["PATH"])
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The Swift source at `path` without comments.
    func code(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.range(of: "//").map { line[..<$0.lowerBound] } ?? line }
            .joined(separator: "\n")
    }

    /// Read from the input method's sources (the executable target can't be linked into a test): what looks programs up
    /// on the main thread (the focus's and the keys' `@question` hand-off, `@agent`, a `terminal` command, Settings) takes
    /// the PATH that never waits (`ShellEnvironment.path`) and keeps answers through `ProgramAvailability`; the shell is
    /// read at launch with `warmUp`.
    @Test func theInputMethodsLookupsNeverWaitForTheShellOnTheMainThread() throws {
        let sessions = try code("Sources/AllInOneIME/ClaudeSessionMac.swift")
        #expect(!sessions.contains("ShellEnvironment.current["), "a lookup on the PATH that waits")
        let terminal = try code("Sources/AllInOneIME/TerminalLauncher.swift")
        #expect(!terminal.contains("ShellEnvironment.current"), "the script's PATH waited for")
        #expect(terminal.components(separatedBy: "write(path: ShellEnvironment.path)").count == 3,
                "written with the PATH known now, again with the shell's in the background")
        let availability = try code("Sources/AllInOneIME/AgentSettings.swift")
        #expect(availability.contains("ProgramAvailability") && !availability.contains("ShellEnvironment.current"))
        let main = try code("Sources/AllInOneIME/main.swift")
        #expect(main.contains("ShellEnvironment.warmUp()"))
    }
}
