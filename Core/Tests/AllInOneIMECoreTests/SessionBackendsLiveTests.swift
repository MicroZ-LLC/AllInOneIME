import Foundation
import Testing
@testable import AllInOneIMECore

/// The real `codex` (Codex, signed in) over its app server, and the real `gemini` (Gemini CLI) on ACP, through the real
/// launcher: only with ALLINONEIME_CODEX_LIVE=1 / ALLINONEIME_GEMINI_LIVE=1, since a question uses the account. Each
/// session is in a folder of its own in the temporary folder, not the input method's. One short question each; Gemini
/// CLI signed out (its settings and files say so): no question, its handshake only, which fails signed out.
@Suite(.serialized)
struct SessionBackendsLiveTests {
    static let environment = ProcessInfo.processInfo.environment
    static let path = (environment["PATH"] ?? "") + ":\(NSHomeDirectory())/.local/bin"

    func manager(_ backend: any SessionBackend, program: URL, path: String = Self.path) -> ClaudeSessionManager {
        let environment = Self.environment.merging(backend.environment) { $1 }.merging(["PATH": path]) { $1 }
        return ClaudeSessionManager(backend: backend,
                                    launcher: ProcessClaudeSessionLauncher(executable: { program }, environment: { environment }))
    }

    func ask(_ session: ClaudeSessionManager, _ question: String) async throws -> String {
        var answer = ""
        for try await text in session.ask(question) { answer = text }
        return answer
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALLINONEIME_CODEX_LIVE"] == "1"))
    func codexAnswersOneQuestionInANamedThread() async throws {
        let codex = try #require(CommandRunner.resolve("codex", path: Self.path), "no codex on PATH")
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("codex-live-\(UUID().uuidString)")
        let session = manager(CodexBackend(base: base), program: codex)
        let started = ContinuousClock.now
        let availability = await session.checkAvailability()
        print("LIVE CODEX sign-in (account/read): \(availability) in \(ContinuousClock.now - started)")
        #expect(availability == .ready)
        let asked = ContinuousClock.now
        let answer = try await ask(session, "Reply with the word ok")
        print("LIVE CODEX answer: \(answer) (\(ContinuousClock.now - asked))")
        #expect(answer.lowercased().contains("ok"))
        let thread = try #require(session.store.agentSessionID())
        let (arguments, directory) = try session.handOff(program: codex.path)
        print("LIVE CODEX thread: \(thread)  hand-off: \(arguments.joined(separator: " "))  in \(directory.path)")
        #expect(arguments == [codex.path, "resume", thread])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALLINONEIME_GEMINI_LIVE"] == "1"))
    func geminiOpensItsSessionOrSaysItIsSignedOut() async throws {
        // Gemini CLI is a Node script: node where its own folder is, or on the PATH.
        let extra = ["\(NSHomeDirectory())/.local/opt/gemini-cli/bin", "\(NSHomeDirectory())/.local/opt/node/bin"]
        let path = ([Self.path] + extra).joined(separator: ":")
        let gemini = try #require(CommandRunner.resolve("gemini", path: path), "no gemini on PATH")
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("gemini-live-\(UUID().uuidString)")
        var backend = ACPBackend.gemini
        backend.base = base
        let session = manager(backend, program: gemini, path: path)
        let availability = await session.checkAvailability()
        print("LIVE GEMINI sign-in (settings and files): \(availability)")
        do {
            let answer = try await ask(session, "Reply with the word ok")
            print("LIVE GEMINI answer: \(answer)")
            #expect(availability == .ready && answer.lowercased().contains("ok"))
        } catch let error as ClaudeSessionError {
            print("LIVE GEMINI session: \(error.description(for: .gemini))")
            #expect(availability == .signedOut && error == .signedOut && error.fallsBack)
        }
        session.stop()
    }
}
