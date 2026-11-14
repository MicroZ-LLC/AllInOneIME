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

    /// FakeClaude's processes, each still running for `dying` seconds after it is asked to end (nil: until killed; not
    /// `killable`: even then).
    final class Dying: ClaudeSessionLauncher, @unchecked Sendable {
        final class Process: ClaudeSessionProcess, @unchecked Sendable {
            let inner: FakeClaude.Process
            let dying: TimeInterval?
            let killable: Bool
            private let ends = Locked<Date?>(initialState: .distantFuture)
            private let killed = Locked(initialState: false)

            init(_ inner: FakeClaude.Process, dying: TimeInterval?, killable: Bool) {
                self.inner = inner
                self.dying = dying
                self.killable = killable
            }

            func send(_ line: Data) throws { try inner.send(line) }
            func terminate() {
                inner.terminate()
                ends.withLock { ends in if ends == .distantFuture { ends = dying.map { Date().addingTimeInterval($0) } ?? .distantFuture } }
            }
            func kill() {
                killed.withLock { $0 = true }
                if killable { ends.withLock { $0 = Date() } }
            }
            var wasKilled: Bool { killed.withLock { $0 } }
            var isRunning: Bool { ends.withLock { $0.map { Date() < $0 } ?? false } }
        }

        let fake = FakeClaude()
        let dying: TimeInterval?
        let killable: Bool
        private let started = Locked<[Process]>(initialState: [])
        var processes: [Process] { started.withLock { $0 } }

        init(dying: TimeInterval?, killable: Bool = true) {
            self.dying = dying
            self.killable = killable
        }

        func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                   exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
            let inner = try fake.start(arguments, in: directory, output: output, exited: exited)
            let process = Process(try #require(inner as? FakeClaude.Process), dying: dying, killable: killable)
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
        let (arguments, _, lock) = try await session.handOffOnceEnded(program: "/u/claude")
        // Returned once our process had ended (it took 0.3 s), not killed.
        #expect(Date().timeIntervalSince(before) >= 0.25 && !process.isRunning && !process.wasKilled)
        #expect(arguments == ["/u/claude", "--resume", id] && lock == store.lockFile(id))
        // Its lock let go: Terminal can have it.
        let terminal = try #require(ConversationLock.take(lock))
        terminal.release()
    }

    /// The hand-off asks our process to end and moves on to a new conversation at once, in one step, while it waits
    /// for the process to end: the conversation is Terminal's already.
    @Test func theHandOffMovesOnAtOnceWhileItWaits() async throws {
        let launcher = Dying(dying: 0.3)
        let session = claude(launcher)
        defer { session.stop() }
        session.prewarm()
        let process = try #require(launcher.processes.last)
        let id = try store.sessionID()
        let handing = Task { try await session.handOffOnceEnded(program: "/u/claude") }
        #expect(await Timing.eventually(within: 0.2) { (try? store.sessionID()) != id }, "not moved on at once")
        #expect(process.inner.terminated && process.isRunning)
        let (arguments, _, _) = try await handing.value
        #expect(arguments == ["/u/claude", "--session-id", id] && !process.isRunning)
    }

    @Test func oneThatDoesNotEndIsKilledBeforeTerminalStarts() async throws {
        let launcher = Dying(dying: nil)
        let session = claude(launcher)
        defer { session.stop() }
        session.prewarm()
        let process = try #require(launcher.processes.last)
        let before = Date()
        _ = try await session.handOffOnceEnded(program: "/u/claude")
        #expect(process.wasKilled && !process.isRunning)
        // Killed once `handOffGrace` is over: about half a second alone, 4–5 seconds seen under the full suite's parallel
        // load. The bound holds under that load and still fails a hand-off that waits far longer than its grace.
        #expect(Date().timeIntervalSince(before) < 15)
    }

    /// The hand-off that can't end our process (still running a moment after it was killed) opens no Terminal, and the
    /// conversation stays the one questions here go into, never a new one with Terminal not opened on the old: a retry
    /// hands off the same. It says only that Terminal wasn't opened on it, and why, in the interface language: not that
    /// the conversation is still here (the panel closed as ⌘⏎ was pressed).
    @Test func aProcessThatOutlivesItsKillKeepsTheConversationHere() async throws {
        let launcher = Dying(dying: nil, killable: false)
        let session = claude(launcher)
        defer { session.stop() }
        let panel = QuestionConversation()
        let stream = session.ask("one", in: panel)
        let process = try #require(launcher.processes.last)
        answer(process.inner, "1")
        _ = await collect(stream)
        let id = try store.sessionID()
        var failure: SessionHandOffError?
        do {
            _ = try await session.handOffOnceEnded(program: "/u/claude") { _, _, _ in Issue.record("Terminal opened") }
        } catch {
            failure = error as? SessionHandOffError
        }
        let error = try #require(failure, "not the hand-off's error")
        #expect(error == SessionHandOffError(reason: .stillRunning, kept: true) && process.wasKilled)
        #expect(try store.sessionID() == id && store.resumable, "the conversation now is a new one")
        #expect(session.request(panel).continues, "its follow-up goes on in it")
        let english = await withInterfaceLanguage("en") { error.localizedDescription }
        let chinese = await withInterfaceLanguage("zh-Hans") { error.localizedDescription }
        #expect(english == "Couldn't open the conversation in Terminal (the session's process didn't end)")
        #expect(chinese == "没能在终端打开这个对话（会话的进程没有结束）")
    }

    /// Terminal that can't be opened once our process has ended (`open` throws): the conversation stays here too, and
    /// the next question resumes it in a process of ours.
    @Test func aTerminalThatWontOpenKeepsTheConversationHere() async throws {
        struct NoTerminal: LocalizedError { var errorDescription: String? { "no Terminal" } }
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let panel = QuestionConversation()
        let stream = session.ask("one", in: panel)
        let process = try #require(fake.last)
        answer(process, "1")
        _ = await collect(stream)
        let id = try store.sessionID()
        var failure: Error?
        do {
            _ = try await session.handOffOnceEnded(program: "/u/claude") { _, _, _ in throw NoTerminal() }
        } catch {
            failure = error
        }
        #expect(failure as? SessionHandOffError == SessionHandOffError(reason: .terminal("no Terminal"), kept: true))
        #expect(try store.sessionID() == id && process.terminated)
        let followUp = session.request(panel)
        #expect(followUp.continues)
        let next = followUp.ask("two")
        let resumed = try #require(fake.last)
        #expect(fake.processes.count == 2 && resumed.arguments.contains("--resume") && resumed.arguments.contains(id))
        withExtendedLifetime(next) {}
    }

    /// A question asked while the hand-off waited went into the new conversation: a hand-off that fails then can't put
    /// the old one back. It says the same as one that did: Terminal wasn't opened on the conversation, and why.
    @Test func aHandOffThatFailsAfterAQuestionMeanwhileLeavesTheNewConversation() async throws {
        let launcher = Dying(dying: nil, killable: false)
        let session = claude(launcher)
        defer { session.stop() }
        session.prewarm()
        let id = try store.sessionID()
        let handing = Task { try await session.handOffOnceEnded(program: "/u/claude") }
        #expect(await Timing.eventually(within: 5) { (try? store.sessionID()) != id }, "handed over")
        let meanwhile = session.request(QuestionConversation())
        var failure: Error?
        do { _ = try await handing.value } catch { failure = error }
        let error = try #require(failure as? SessionHandOffError)
        #expect(error == SessionHandOffError(reason: .stillRunning, kept: false))
        #expect(try store.sessionID() != id)
        let english = await withInterfaceLanguage("en") { error.localizedDescription }
        let chinese = await withInterfaceLanguage("zh-Hans") { error.localizedDescription }
        #expect(english == "Couldn't open the conversation in Terminal (the session's process didn't end)")
        #expect(chinese == "没能在终端打开这个对话（会话的进程没有结束）")
        withExtendedLifetime(meanwhile) {}
    }

    /// Our process ended, its exit told only later (its output still being read, say): the hand-off goes on, by the
    /// process's own end, and lets go of its lock for Terminal; the next process starts once the exit is told.
    @Test func aLateExitDoesNotFailTheHandOff() async throws {
        let launcher = Dying(dying: 0.1)
        let session = claude(launcher)
        defer { session.stop() }
        session.prewarm()
        let process = try #require(launcher.processes.last)
        process.inner.autoExitOnTerminate = false
        let (_, _, lock) = try await session.handOffOnceEnded(program: "/u/claude")
        #expect(!process.isRunning && !process.wasKilled)
        let terminal = try #require(ConversationLock.take(lock), "our lock is still held")
        terminal.release()
        // Told now: a prewarm meanwhile starts its process then.
        session.prewarm()
        #expect(launcher.processes.count == 1)
        process.inner.exit(143)
        #expect(launcher.processes.count == 2)
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
        let (arguments, _, _) = try await session.handOffOnceEnded(program: "/u/claude", followUp: true)
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
        let (arguments, directory, _) = try await session.handOffOnceEnded(program: "/u/codex")
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
