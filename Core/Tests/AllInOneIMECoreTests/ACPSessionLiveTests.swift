import Foundation
import Testing
@testable import AllInOneIMECore

/// The real `kiro-cli` (Kiro CLI, signed in) on ACP, through the real launcher: only with ALLINONEIME_KIRO_LIVE=1, since
/// each question uses the Kiro account. The session is in a folder of its own (ALLINONEIME_KIRO_LIVE_DIR, else a new
/// one in the temporary folder). Two questions, the second about the first; the process restarted, a third about the
/// first (`session/load`); the instructions (steering) followed; the time to the first token, prewarmed and warm.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ALLINONEIME_KIRO_LIVE"] == "1"))
struct ACPSessionLiveTests {
    static let folder: URL = {
        let given = ProcessInfo.processInfo.environment["ALLINONEIME_KIRO_LIVE_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        return given.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("kiro-session-live-\(UUID().uuidString)")
    }()

    static let environment = ProcessInfo.processInfo.environment

    func manager() throws -> ClaudeSessionManager {
        let path = (Self.environment["PATH"] ?? "") + ":\(NSHomeDirectory())/.local/bin"
        let kiro = try #require(CommandRunner.resolve("kiro-cli", path: path), "no kiro-cli on PATH")
        let backend = ACPBackend.kiro
        return ClaudeSessionManager(backend: backend,
                                    launcher: ProcessClaudeSessionLauncher(executable: { kiro }, environment: { Self.environment }),
                                    store: ClaudeSessionStore(directory: Self.folder, files: backend.files))
    }

    func ask(_ session: ClaudeSessionManager, _ question: String) async throws -> (answer: String, firstToken: Double) {
        let start = ContinuousClock.now
        var first: Duration?
        var answer = ""
        for try await text in session.ask(question, in: nil) {
            if first == nil { first = ContinuousClock.now - start }
            answer = text
        }
        let d = first ?? .zero
        return (answer, Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }

    func shown(_ x: Double) -> String { String(format: "%.2f", x) }

    @Test func twoQuestionsTheSecondAboutTheFirstThenARestartAndAThird() async throws {
        let session = try manager()
        let cold = try await ask(session, "What is the capital of Australia? One word.")
        print("LIVE KIRO Q1: \(cold.answer) (first token \(shown(cold.firstToken)) s, started for it)")
        #expect(cold.answer.contains("Canberra"))
        #expect(!cold.answer.contains("**") && !cold.answer.contains("```"))  // the steering: plain text
        let second = try await ask(session, "刚才那个问题问的是哪个国家？只回答国家名。")
        print("LIVE KIRO Q2: \(second.answer) (first token \(shown(second.firstToken)) s, warm)")
        #expect(second.answer.contains("澳大利亚") || second.answer.contains("澳洲") || second.answer.contains("Australia"))
        let id = try #require(session.store.agentSessionID())
        // The process ends (idle, a crash, an update): the next one starts a new conversation (0.7.4: nothing is
        // remembered across conversations, and one the IME left is never resumed), and the panel says so.
        session.stop()
        session.prewarm()
        try await Task.sleep(for: .seconds(4))
        let third = try await ask(session, "In this session, what was my very first question? Quote it.")
        print("LIVE KIRO Q3 (new process, new conversation, prewarmed): \(third.answer) (first token \(shown(third.firstToken)) s)")
        #expect(!third.answer.contains("Australia"))
        #expect(session.store.agentSessionID() != id)
        // Only the web: no shell.
        let shell = try await ask(session, "Run the shell command `date` and give me only its output.")
        print("LIVE KIRO Q4 (shell asked): \(shell.answer)")
        session.stop()
        print("LIVE KIRO session id: \(id)  folder: \(Self.folder.path)")
        let handed = try await session.handOffOnceEnded(program: "kiro-cli")
        print("LIVE KIRO hand-off: \(handed.arguments.joined(separator: " "))")
    }
}
