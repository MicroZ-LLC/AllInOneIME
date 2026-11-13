import Foundation
import Testing
@testable import AllInOneIMECore

/// The real `claude` (Claude Code, signed in), through the real launcher (`ProcessClaudeSessionLauncher`): only with
/// ALLINONEIME_CLAUDE_LIVE=1, since each question uses the subscription. The session is in a folder of its own
/// (ALLINONEIME_CLAUDE_LIVE_DIR, else a new one in the temporary folder), not the input method's. It prints the time to
/// the first token of a question to a process that is up (prewarmed, or used), to one started for it, and to the
/// provider configured in ~/.config/allinoneime/config.json (or ALLINONEIME_CLAUDE_LIVE_PROVIDER's, with its settings
/// there), and the session's id and folder, to look at it with
/// `claude --resume <id>`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ALLINONEIME_CLAUDE_LIVE"] == "1"))
struct ClaudeSessionLiveTests {
    static let folder: URL = {
        let given = ProcessInfo.processInfo.environment["ALLINONEIME_CLAUDE_LIVE_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        return given.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("claude-session-live-\(UUID().uuidString)")
    }()

    /// The environment without this process's own Claude Code variables (a test run inside a Claude Code session).
    static let environment: [String: String] = ProcessInfo.processInfo.environment.filter {
        !$0.key.hasPrefix("CLAUDE") && $0.key != "AI_AGENT"
    }

    static func claude() -> URL? {
        CommandRunner.resolve("claude", path: environment["PATH"].map { $0 + ":\(NSHomeDirectory())/.local/bin" })
    }

    func manager() throws -> ClaudeSessionManager {
        let claude = try #require(Self.claude(), "no claude on PATH")
        return ClaudeSessionManager(launcher: ProcessClaudeSessionLauncher(executable: { claude }, environment: { Self.environment }),
                                    store: ClaudeSessionStore(directory: Self.folder))
    }

    /// The answer to `question`, and the seconds from asking to its first text.
    func ask(_ session: ClaudeSessionManager, _ question: String) async throws -> (answer: String, firstToken: Double) {
        let start = ContinuousClock.now
        var first: Duration?
        var answer = ""
        for try await text in session.ask(question) {
            if first == nil { first = ContinuousClock.now - start }
            answer = text
        }
        return (answer, seconds(first ?? .zero))
    }

    func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
    func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }
    func shown(_ xs: [Double]) -> String { xs.map { String(format: "%.2f", $0) }.joined(separator: ", ") }

    @Test func twoQuestionsInARowTheSecondAboutTheFirstAndAfterARestart() async throws {
        let session = try manager()
        session.prewarm()
        try await Task.sleep(for: .seconds(5))
        let first = try await ask(session, "What is the capital of Australia? One word.")
        print("LIVE Q1: \(first.answer) (first token \(String(format: "%.2f", first.firstToken)) s, prewarmed)")
        let second = try await ask(session, "刚才那个问题问的是哪个国家？只回答国家名。")
        print("LIVE Q2: \(second.answer)")
        #expect(second.answer.contains("澳大利亚") || second.answer.contains("澳洲") || second.answer.contains("Australia"))
        // The process ends (idle, a crash): the next one resumes the session and still knows.
        session.stop()
        let third = try await ask(session, "In this session, what was my very first question? Quote it.")
        print("LIVE Q3 (after a restart, --resume): \(third.answer)")
        #expect(third.answer.contains("Australia"))
        session.stop()
        print("LIVE session id: \(try session.store.sessionID())  folder: \(Self.folder.path)")
    }

    @Test func timeToFirstToken() async throws {
        let session = try manager()
        let questions = ["What is 17 times 23? Just the number.", "Opposite of 'ancient'? One word.",
                         "Translate 'good morning' into French. Only the translation.", "How many legs does a spider have? Just the number."]
        // Started for the question (what every question would pay without a process kept up).
        var cold: [Double] = []
        for question in questions.prefix(3) {
            session.stop()
            cold.append(try await ask(session, question).firstToken)
        }
        // Prewarmed: started when the command trigger was typed, a few seconds before the question.
        var prewarmed: [Double] = []
        var warm: [Double] = []
        for round in 0..<2 {
            session.stop()
            session.prewarm()
            try await Task.sleep(for: .seconds(6))
            prewarmed.append(try await ask(session, questions[round]).firstToken)
            for question in questions.suffix(2) { warm.append(try await ask(session, question).firstToken) }
        }
        session.stop()
        print("LIVE TTFT cold start (spawn + first token): median \(String(format: "%.2f", median(cold))) s [\(shown(cold))]")
        print("LIVE TTFT prewarmed process: median \(String(format: "%.2f", median(prewarmed))) s [\(shown(prewarmed))]")
        print("LIVE TTFT warm process (answered before): median \(String(format: "%.2f", median(warm))) s [\(shown(warm))]")

        // The provider configured here, for the same questions (fresh: past the cache).
        guard var config = try? Config.load() else { return print("LIVE provider: no config") }
        // Another provider than the one configured (ALLINONEIME_CLAUDE_LIVE_PROVIDER=bedrock …), with its settings there.
        if let other = ProcessInfo.processInfo.environment["ALLINONEIME_CLAUDE_LIVE_PROVIDER"].flatMap(Provider.init(rawValue:)) {
            config.provider = other
        }
        let settings = config
        let converter = Converter(loadConfig: { settings })
        var provider: [Double] = []
        for question in questions {
            do {
                var first: Double?
                for try await update in converter.generate(.question, input: question, fresh: true) {
                    first = first ?? update.firstTokenLatency
                }
                if let first { provider.append(first) }
            } catch {
                print("LIVE provider \(settings.provider.rawValue): \(UIText.describe(error))")
                break
            }
        }
        if !provider.isEmpty {
            print("LIVE TTFT provider \(settings.provider.rawValue) (\(settings.activeModel)): median \(String(format: "%.2f", median(provider))) s [\(shown(provider))]")
        }
    }
}
