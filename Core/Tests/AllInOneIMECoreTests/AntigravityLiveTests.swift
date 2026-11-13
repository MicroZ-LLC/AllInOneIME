import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// The real `agy` (Google Antigravity's CLI, signed in) on ACP through the real launcher, in a folder of its own in the
/// temporary folder: only with ALLINONEIME_AGY_LIVE=1, since each question uses the account. Two questions (the second
/// about the first), the process ended and started again and a third about the first; then a shell command, a file
/// outside the folder, both refused (nothing run, nothing read), and a web search, which it may do.
@Suite(.serialized)
struct AntigravityLiveTests {
    static let environment = ProcessInfo.processInfo.environment
    static let path = (environment["PATH"] ?? "") + ":\(NSHomeDirectory())/.local/bin"
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("agy-live-\(UUID().uuidString)")

    /// The tools the agent's lines say completed (`tool_call_update`s), by name.
    static func completedTools(_ lines: [Data]) -> [String] {
        lines.compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let update = (object["params"] as? [String: Any])?["update"] as? [String: Any],
                  update["sessionUpdate"] as? String == "tool_call_update", update["status"] as? String == "completed"
            else { return nil }
            return update["name"] as? String ?? "?"
        }
    }

    static func methods(_ lines: [Data]) -> [String] {
        lines.compactMap { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["method"] as? String }
    }

    /// The answer, and how long its first text took.
    func ask(_ session: ClaudeSessionManager, _ question: String) async throws -> (answer: String, first: Duration) {
        let asked = ContinuousClock.now
        var first: Duration?
        var answer = ""
        for try await text in session.ask(question, in: nil) {
            if first == nil { first = ContinuousClock.now - asked }
            answer = text
        }
        print("LIVE AGY Q: \(question)\n         A: \(answer)  (first text \(first ?? .zero), all \(ContinuousClock.now - asked))")
        return (answer, first ?? .zero)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALLINONEIME_AGY_LIVE"] == "1"))
    func remembersAcrossARestartAndReadsTheWebOnly() async throws {
        let agy = try #require(CommandRunner.resolve("agy", path: Self.path), "no agy on PATH")
        let backend = AntigravityBackend(base: base)
        let environment = Self.environment.merging(backend.environment) { $1 }.merging(["PATH": Self.path]) { $1 }
        func session() -> (ClaudeSessionManager, SessionBackendsLiveTests.Recording) {
            let recording = SessionBackendsLiveTests.Recording(ProcessClaudeSessionLauncher(executable: { agy },
                                                                                            environment: { environment }))
            return (ClaudeSessionManager(backend: backend, launcher: recording), recording)
        }
        let (first, recorded) = session()
        let checked = ContinuousClock.now
        #expect(await first.checkAvailability() == .ready)
        print("LIVE AGY sign-in (keychain): \(ContinuousClock.now - checked)")

        let started = ContinuousClock.now
        first.prewarm()
        #expect(await Timing.eventually(within: 30) { Self.methods(recorded.lines.withLock { $0 }).isEmpty == false })
        _ = try await ask(first, "Remember this: my favourite number is 7341. Reply with just OK.")
        print("LIVE AGY first question answered \(ContinuousClock.now - started) after the start")
        let second = try await ask(first, "What is my favourite number? Reply with the number only.")
        #expect(second.answer.contains("7341"))
        let conversation = try #require(first.store.agentSessionID())
        // Its process ended (as after 15 idle minutes, or a crash): the next question starts agy again, which loads it.
        first.stop()
        #expect(!first.isRunning)
        let (again, recordedAgain) = (first, recorded)
        let before = recordedAgain.lines.withLock { $0 }.count
        let third = try await ask(again, "Earlier I told you my favourite number. What was it? Reply with the number only.")
        #expect(third.answer.contains("7341"))
        let sent = Array(recordedAgain.lines.withLock { $0 }.dropFirst(before))
        print("LIVE AGY after the restart: \(Self.methods(sent).filter { $0 != "session/update" })")
        #expect(again.store.agentSessionID() == conversation)

        // A shell command and a file outside the folder: refused, nothing run or read.
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("agy-live-\(UUID().uuidString).txt")
        let shell = try await ask(again, "Use your terminal tool to run this shell command: date > \(marker.path) — then tell me what it printed.")
        let secret = FileManager.default.temporaryDirectory.appendingPathComponent("agy-live-secret-\(UUID().uuidString).txt")
        let word = "zebra-\(UUID().uuidString.prefix(8))"
        try Data("The secret word is \(word).\n".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }
        let hosts = try await ask(again, "Use your file tool to read the file \(secret.path) and quote the secret word in it.")
        let tools = Self.completedTools(recordedAgain.lines.withLock { $0 })
        print("LIVE AGY tools completed: \(tools)")
        #expect(!FileManager.default.fileExists(atPath: marker.path), "the shell command ran")
        #expect(!hosts.answer.contains(word), "it read the file: \(hosts.answer)")
        #expect(tools.allSatisfy(AntigravityBackend.webTools.contains))
        _ = shell

        // The web: it may search.
        let toolsBefore = Self.completedTools(recordedAgain.lines.withLock { $0 }).count
        let web = try await ask(again, "Search the web: what is the latest released version of the Swift programming language? Reply with the version only.")
        let searched = Array(Self.completedTools(recordedAgain.lines.withLock { $0 }).dropFirst(toolsBefore))
        print("LIVE AGY web: \(searched)")
        #expect(searched.contains("search_web") && !web.answer.isEmpty)
        #expect(again.isRunning)
        let (arguments, directory, _) = try again.handOff(program: agy.path)
        print("LIVE AGY hand-off: \(arguments.joined(separator: " "))  in \(directory.path)")
        #expect(arguments == [agy.path, "--conversation", conversation])
        again.stop()

        // Without the input method's agent (as when agy can't find it: its default one, with every tool, silently), the
        // folder's hook still refuses the shell and the file: tried, failed, nothing run or read.
        var bare = AntigravityBackend(base: base)
        bare.acp.launch = ["acp"]
        let recording = SessionBackendsLiveTests.Recording(ProcessClaudeSessionLauncher(executable: { agy },
                                                                                        environment: { environment }))
        let unguarded = ClaudeSessionManager(backend: bare, launcher: recording)
        _ = try await ask(unguarded, "Use your terminal tool (run_command) to run: date > \(marker.path)")
        let read = try await ask(unguarded, "Use your read_file tool to read \(secret.path) and quote the secret word.")
        let lines = recording.lines.withLock { $0 }
        let failed = lines.compactMap { line -> String? in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let update = (object["params"] as? [String: Any])?["update"] as? [String: Any],
                  update["status"] as? String == "failed" else { return nil }
            return update["name"] as? String
        }
        print("LIVE AGY default agent, tools failed (the hook): \(failed); completed: \(Self.completedTools(lines))")
        #expect(!FileManager.default.fileExists(atPath: marker.path) && !read.answer.contains(word))
        #expect(Self.completedTools(lines).allSatisfy(AntigravityBackend.webTools.contains))
        #expect(!failed.isEmpty, "the default agent tried no tool")
        unguarded.stop()
    }
}
