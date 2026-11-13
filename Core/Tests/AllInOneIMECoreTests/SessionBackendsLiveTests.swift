import Foundation
import Testing
@testable import AllInOneIMECore

/// The real `codex` (Codex, signed in) over its app server, through the real launcher: only with
/// ALLINONEIME_CODEX_LIVE=1, since a question uses the account. The session is in a folder of its own in the temporary
/// folder, not the input method's. One short question, and two more on what it may read (the web, not this Mac's
/// files). Antigravity's: AntigravityLiveTests.
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
        let (arguments, directory, _) = try session.handOff(program: codex.path)
        print("LIVE CODEX thread: \(thread)  hand-off: \(arguments.joined(separator: " "))  in \(directory.path)")
        #expect(arguments == [codex.path, "resume", thread])
    }

    /// The real launcher, with every line the agent writes kept as well.
    final class Recording: ClaudeSessionLauncher, @unchecked Sendable {
        let inner: ProcessClaudeSessionLauncher
        let lines = Locked(initialState: [Data]())

        init(_ inner: ProcessClaudeSessionLauncher) {
            self.inner = inner
        }

        func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                   exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
            try inner.start(arguments, in: directory, output: { [lines] line in
                lines.withLock { $0.append(line) }
                output(line)
            }, exited: exited)
        }

        /// The items the agent started (`item/started`): its messages, its tool calls; an MCP tool call's server too.
        var items: [(type: String, server: String?)] {
            lines.withLock { $0 }.compactMap { line in
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["method"] as? String == "item/started",
                      let item = (object["params"] as? [String: Any])?["item"] as? [String: Any],
                      let type = item["type"] as? String else { return nil }
                return (type, item["server"] as? String)
            }
        }
    }

    /// Whether an item is one a session that reads the web only may have: nothing run, changed or looked at on this Mac,
    /// no MCP server's tool, no other agent. Codex's own MCP resource tools (server "codex") may look: with no MCP server
    /// there is nothing to list.
    static func webOnly(_ item: (type: String, server: String?)) -> Bool {
        let forbidden: Set = ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "collabAgentToolCall",
                              "subAgentActivity", "imageView", "imageGeneration"]
        return !forbidden.contains(item.type) || (item.type == "mcpToolCall" && item.server == "codex")
    }

    /// Codex, like the other sessions, reads the web and nothing of this Mac: asked for the home folder's files it runs
    /// nothing and names none of them; asked something current it searches the web. Two questions.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ALLINONEIME_CODEX_LIVE"] == "1"))
    func codexReadsTheWebNotThisMacsFiles() async throws {
        let codex = try #require(CommandRunner.resolve("codex", path: Self.path), "no codex on PATH")
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("codex-live-\(UUID().uuidString)")
        let backend = CodexBackend(base: base)
        let environment = Self.environment.merging(backend.environment) { $1 }.merging(["PATH": Self.path]) { $1 }
        let recording = Recording(ProcessClaudeSessionLauncher(executable: { codex }, environment: { environment }))
        let session = ClaudeSessionManager(backend: backend, launcher: recording)

        let files = try await ask(session, "List the files and folders in my home folder (~), one per line.")
        let tried = recording.items
        print("LIVE CODEX home folder: \(files)\nLIVE CODEX items: \(tried)")
        #expect(tried.allSatisfy(Self.webOnly))
        // None of the home folder's own names (aside from those every Mac has) is in the answer.
        let everyMac: Set = ["Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public"]
        let own = try FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory())
            .filter { !$0.hasPrefix(".") && !everyMac.contains($0) && $0.count >= 5 }
        #expect(own.filter { files.contains($0) }.isEmpty)

        let before = recording.items.count
        let current = try await ask(session, "Search the web: what is the latest released version of the OpenAI Codex CLI? Reply with the version only.")
        let searched = Array(recording.items.dropFirst(before))
        print("LIVE CODEX web: \(current)\nLIVE CODEX items: \(searched)")
        #expect(searched.contains { $0.type == "webSearch" } && !current.isEmpty)
        #expect(searched.allSatisfy(Self.webOnly))
        session.stop()
    }
}
