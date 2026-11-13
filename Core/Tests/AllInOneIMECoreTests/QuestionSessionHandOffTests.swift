import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// One writer per conversation: handing it to Terminal (⌘⏎) ends our process first and waits for it, the conversation is
/// Terminal's from then on (a question or a prewarm after it starts a new one), our process holds the conversation's
/// lock while it runs and Terminal's CLI holds it while it runs (`ClaudeSessionManager.terminalCommand`), and a relaunch
/// never resumes the conversation it was answering in.
struct QuestionSessionHandOffTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hand-off-\(UUID().uuidString)")
    var store: ClaudeSessionStore { ClaudeSessionStore(directory: folder) }

    func claude(_ launcher: any ClaudeSessionLauncher) -> ClaudeSessionManager {
        ClaudeSessionManager(launcher: launcher, store: store, userSettings: { nil })
    }

    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (answers: [String], error: Error?) {
        var answers: [String] = []
        do {
            for try await answer in stream { answers.append(answer) }
            return (answers, nil)
        } catch {
            return (answers, error)
        }
    }

    func answer(_ process: FakeClaude.Process, _ text: String) {
        process.started()
        process.text(text)
        process.done(text)
    }

    /// FakeClaude's processes, each still running for `dying` seconds after it is asked to end (nil: until killed).
    final class Dying: ClaudeSessionLauncher, @unchecked Sendable {
        final class Process: ClaudeSessionProcess, @unchecked Sendable {
            let inner: FakeClaude.Process
            let dying: TimeInterval?
            private let ends = Locked<Date?>(initialState: .distantFuture)
            private let killed = Locked(initialState: false)

            init(_ inner: FakeClaude.Process, dying: TimeInterval?) {
                self.inner = inner
                self.dying = dying
            }

            func send(_ line: Data) throws { try inner.send(line) }
            func terminate() {
                inner.terminate()
                ends.withLock { ends in if ends == .distantFuture { ends = dying.map { Date().addingTimeInterval($0) } ?? .distantFuture } }
            }
            func kill() {
                killed.withLock { $0 = true }
                ends.withLock { $0 = Date() }
            }
            var wasKilled: Bool { killed.withLock { $0 } }
            var isRunning: Bool { ends.withLock { $0.map { Date() < $0 } ?? false } }
        }

        let fake = FakeClaude()
        let dying: TimeInterval?
        private let started = Locked<[Process]>(initialState: [])
        var processes: [Process] { started.withLock { $0 } }

        init(dying: TimeInterval?) {
            self.dying = dying
        }

        func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                   exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
            let inner = try fake.start(arguments, in: directory, output: output, exited: exited)
            let process = Process(try #require(inner as? FakeClaude.Process), dying: dying)
            started.withLock { $0.append(process) }
            return process
        }
    }

    @Test func theHandOffEndsOurProcessAndWaitsForItBeforeTerminalStarts() async throws {
        let launcher = Dying(dying: 0.3)
        let session = claude(launcher)
        defer { session.stop() }
        let stream = session.ask("one", in: nil)
        let process = try #require(launcher.processes.last)
        answer(process.inner, "1")
        _ = await collect(stream)
        let id = try store.sessionID()
        let before = Date()
        let (arguments, _, lock) = try session.handOff(program: "/u/claude")
        // Returned once our process had ended (it took 0.3 s), not killed.
        #expect(Date().timeIntervalSince(before) >= 0.25 && !process.isRunning && !process.wasKilled)
        #expect(arguments == ["/u/claude", "--resume", id] && lock == store.lockFile(id))
        // Its lock let go: Terminal can have it.
        let terminal = try #require(ConversationLock.take(lock))
        terminal.release()
    }

    @Test func oneThatDoesNotEndIsKilledBeforeTerminalStarts() async throws {
        let launcher = Dying(dying: nil)
        let session = claude(launcher)
        defer { session.stop() }
        session.prewarm()
        let process = try #require(launcher.processes.last)
        let before = Date()
        _ = try session.handOff(program: "/u/claude")
        #expect(process.wasKilled && !process.isRunning)
        #expect(Date().timeIntervalSince(before) < 3)
    }

    @Test func aQuestionAnsweredWhenHandedOffStopsAndWhatComesAfterGoesIntoANewConversation() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let enteredConversation1: QuestionConversation? = QuestionConversation()
        let answering = session.ask("one", in: enteredConversation1)
        let process = try #require(fake.last)
        process.started()
        process.text("Part")
        let id = try store.sessionID()
        let (arguments, _, _) = try session.handOff(program: "/u/claude", followUp: true)
        #expect(arguments == ["/u/claude", "--resume", id, "--"])
        #expect(await collect(answering).error is CancellationError && process.terminated)
        // What our process still says is of no conversation now.
        process.text(" more")
        // An @ typed during the hand-off: a process on a new conversation, never the one Terminal has.
        session.prewarm()
        let next = try #require(fake.last)
        #expect(fake.processes.count == 2 && !next.arguments.contains(id) && next.arguments.contains("--session-id"))
        let newID = try store.sessionID()
        #expect(newID != id && next.arguments.contains(newID))
        // A later question (a new @question conversation) goes there too.
        let enteredConversation2: QuestionConversation? = QuestionConversation()
        let later = session.ask("two", in: enteredConversation2)
        #expect(fake.processes.count == 2 && next.messages == ["two"])
        withExtendedLifetime(later) {}
    }

    @Test func ourProcessHoldsItsConversationsLockWhileItRuns() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        session.prewarm()
        let process = try #require(fake.last)
        let file = store.lockFile(try store.sessionID())
        #expect(ConversationLock.take(file) == nil, "held while our process runs")
        process.exit(0)  // it ended
        let lock = try #require(ConversationLock.take(file))
        lock.release()
    }

    @Test func codexsHandOffGivesItsThreadAndTheNextConversationOpensANewOne() async throws {
        let fake = FakeClaude()
        let backend = CodexBackend(base: folder)
        let session = ClaudeSessionManager(backend: backend, launcher: fake)
        defer { session.stop() }
        session.prewarm()
        let process = try #require(fake.last)
        func respond(_ process: FakeClaude.Process, _ method: String, _ result: [String: Any]) throws {
            let id = try #require(process.lines.last { $0["method"] as? String == method }?["id"])
            process.say(["id": id, "result": result])
        }
        try respond(process, "initialize", ["userAgent": "test"])
        try respond(process, "config/read", ["config": ["model": "gpt"]])
        try respond(process, "thread/start", ["thread": ["id": "t1", "name": NSNull()]])
        let (arguments, directory, _) = try session.handOff(program: "/u/codex")
        #expect(arguments == ["/u/codex", "resume", "t1"] && directory == backend.directory && process.terminated)
        #expect(ClaudeSessionStore(backend).agentSessionID() == nil)
        session.prewarm()
        let next = try #require(fake.last)
        try respond(next, "initialize", ["userAgent": "test"])
        try respond(next, "config/read", ["config": ["model": "gpt"]])
        #expect(next.lines.contains { $0["method"] as? String == "thread/start" })
        #expect(!next.lines.contains { $0["method"] as? String == "thread/resume" })
    }

    @Test func aRelaunchWhileAnsweringNeverResumesThatConversation() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        let enteredConversation3: QuestionConversation? = QuestionConversation()
        let answering = session.ask("one", in: enteredConversation3)
        let process = try #require(fake.last)
        process.started()
        process.text("Part")
        let id = try store.sessionID()
        // The update quits the input method: every session's process ends.
        ClaudeSessionManager.stop([session], grace: 0.5)
        #expect(await collect(answering).error is CancellationError && process.terminated)
        // Relaunched: the next question, of a new conversation, goes into a new agent conversation.
        let relaunched = claude(fake)
        defer { relaunched.stop() }
        let relaunchedConversation = QuestionConversation()
        let next = relaunched.ask("two", in: relaunchedConversation)
        let started = try #require(fake.last)
        #expect(fake.processes.count == 2 && !started.arguments.contains(id) && started.arguments.contains("--session-id"))
        withExtendedLifetime(next) {}
    }

    #if os(macOS)
    /// Terminal runs the CLI under `lockf`, which waits for our lock to be let go, then holds it while the CLI runs.
    @Test func terminalHoldsTheConversationsLockWhileItsCLIRuns() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/lockf") else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("conversation.lock")
        let ran = folder.appendingPathComponent("ran")
        let ours = try #require(ConversationLock.take(file))
        let command = ClaudeSessionManager.terminalCommand(["/bin/sh", "-c", "touch \"$0\"; sleep 1", ran.path], lock: file)
        let terminal = Process()
        terminal.executableURL = URL(fileURLWithPath: command[0])
        terminal.arguments = Array(command.dropFirst())
        try terminal.run()
        // Ours still held: the CLI waits.
        try await Task.sleep(for: .milliseconds(500))
        #expect(!FileManager.default.fileExists(atPath: ran.path))
        ours.release()
        #expect(await Timing.eventually(within: 10) { FileManager.default.fileExists(atPath: ran.path) })
        #expect(ConversationLock.take(file) == nil, "held while Terminal's CLI runs")
        #expect(await Timing.eventually(within: 10) { !terminal.isRunning })
        let after = try #require(ConversationLock.take(file))
        after.release()
    }
    #endif
}
