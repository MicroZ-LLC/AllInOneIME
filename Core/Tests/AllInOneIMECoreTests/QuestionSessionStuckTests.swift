import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// A question session that gets stuck or can't be used (`ClaudeSessionManager`): an answer that stalls, an agent deaf
/// to the interrupt, a question waiting behind another, a process that can't start, an agent that can't be kept to the
/// web; what Terminal runs with a follow-up; the processes ended when the backend changes and when the input method
/// quits.
struct QuestionSessionStuckTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stuck-session-\(UUID().uuidString)")
    var store: ClaudeSessionStore { ClaudeSessionStore(directory: folder) }

    func manager(_ fake: any ClaudeSessionLauncher, answerClock: any Clock<Duration> = ContinuousClock()) -> ClaudeSessionManager {
        ClaudeSessionManager(launcher: fake, store: store, answerClock: answerClock, userSettings: { nil })
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

    // MARK: - Stuck

    @Test func anAnswerDeafToTheInterruptEndsItsProcessAndTheNextQuestionGoesToANewOne() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = manager(fake, answerClock: clock)
        let first = session.ask("one")
        let stuck = try #require(fake.last)
        stuck.started()
        stuck.messageStarted()
        stuck.text("Partial")
        let second = session.ask("two")
        session.interrupt()  // Esc; the agent never ends the turn
        #expect(stuck.interrupts == 1)
        #expect(await clock.sleepers(2))  // the interrupt's time, and the second question's wait
        clock.advance(by: ClaudeSessionManager.interruptTimeout)
        #expect(await Timing.eventually { stuck.terminated && fake.processes.count == 2 })
        let process = try #require(fake.last)
        #expect(process.messages == ["two"] && process.arguments.contains("--resume"))
        process.started()
        process.text("2")
        process.done("2")
        #expect(await collect(second).answers == ["2"])
        #expect(await collect(first).error is CancellationError)
    }

    @Test func anAnswerThatStallsFailsAfterTheIdleTimeAndItsProcessEnds() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = manager(fake, answerClock: clock)
        let stream = session.ask("one")
        let process = try #require(fake.last)
        process.started()
        process.messageStarted()
        process.text("Half")
        #expect(await clock.sleepers(1))
        clock.advance(by: .seconds(100))
        process.text(" more")  // a line: the idle time starts again
        #expect(await clock.sleepers(1))
        clock.advance(by: .seconds(150))
        #expect(await clock.sleepers(1))
        #expect(!process.terminated)
        clock.advance(by: .seconds(30))  // 180 s without a line
        let got = await collect(stream)
        #expect(got.answers == ["Half", "Half more"] && got.error as? ClaudeSessionError == .noResponse)
        #expect(process.terminated && !session.isRunning)
    }

    @Test func aQuestionWaitingBehindALongAnswerFallsBackAsBusy() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = manager(fake, answerClock: clock)
        let first = session.ask("one")
        let process = try #require(fake.last)
        process.started()
        process.messageStarted()
        process.text("Still")
        let second = session.ask("two")
        #expect(await clock.sleepers(2))
        clock.advance(by: ClaudeSessionManager.firstAnswerTimeout)
        let waited = await collect(second)
        #expect(waited.error as? ClaudeSessionError == .busy && ClaudeSessionError.busy.fallsBack)
        // The answer being given goes on in its process.
        #expect(!process.terminated && process.messages == ["one"])
        process.text(" going")
        process.done()
        #expect(await collect(first).answers == ["Still", "Still going"])
    }

    // MARK: - Can't be used

    @Test func aProcessThatEndsTwiceBeforeItsSessionStartsFallsBackAndIsPassedBy() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        session.availability = .ready
        let stream = session.ask("hi")
        try #require(fake.last).exit(1, "error: unknown option '--name'")
        #expect(fake.processes.count == 2)  // tried once more the other way
        try #require(fake.last).exit(1, "error: unknown option '--name'")
        let got = await collect(stream)
        let error = try #require(got.error as? ClaudeSessionError)
        #expect(error == .failedToStart(1, "error: unknown option '--name'") && error.fallsBack)
        #expect(error.fallbackNote(for: .claude).contains("unknown option"))
        #expect(session.availability == .cannotStart)
        // Automatic passes it by until it is looked at again.
        var config = Config.default
        config.agent = .claude
        #expect(!session.answersQuestions(config))
        // A picked one is still tried.
        config.questionBackend = .claudeSession
        #expect(session.answersQuestions(config))
    }

    func kiro(_ fake: FakeClaude, in name: String = "kiro") -> ClaudeSessionManager {
        ClaudeSessionManager(backend: ACPBackend.kiro, launcher: fake,
                             store: ClaudeSessionStore(directory: folder.appendingPathComponent(name), files: ACPBackend.kiro.files))
    }

    func respond(_ process: FakeClaude.Process, _ method: String, result: [String: Any] = [:], error: [String: Any]? = nil) throws {
        let request = try #require(process.lines.last { $0["method"] as? String == method })
        var line: [String: Any] = ["jsonrpc": "2.0", "id": try #require(request["id"])]
        if let error { line["error"] = error } else { line["result"] = result }
        process.say(line)
    }

    @Test func kiroThatWontGoIntoItsWebOnlyAgentIsNotAsked() async throws {
        for refused in [false, true] {
            let fake = FakeClaude()
            let session = kiro(fake, in: "kiro-\(refused)")
            let stream = session.ask("hi")
            let process = try #require(fake.last)
            try respond(process, "initialize", result: ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]])
            // Not offered, or offered and refused.
            let offered: [[String: Any]] = refused ? [["id": "kiro_default"], ["id": ACPBackend.kiroMode]] : [["id": "kiro_default"]]
            try respond(process, "session/new",
                        result: ["sessionId": "sess_1", "modes": ["currentModeId": "kiro_default", "availableModes": offered]])
            if refused { try respond(process, "session/set_mode", error: ["code": -32603, "message": "no such agent"]) }
            let got = await collect(stream)
            #expect(got.error as? ClaudeSessionError == .notWebOnly && ClaudeSessionError.notWebOnly.fallsBack, "refused \(refused)")
            #expect(!process.lines.contains { $0["method"] as? String == "session/prompt" } && process.terminated)
            #expect(session.availability == .cannotStart)
            #expect(ClaudeSessionError.notWebOnly.description(for: .kiro).contains("Kiro CLI"))
        }
    }

    // MARK: - Terminal

    @Test func aFollowUpInTerminalComesAfterWhatMakesItTheMessage() {
        let id = "8d6a1f6e-0d2c-4c4e-9a43-0c1a2b3c4d5e"
        let claude = ClaudeCodeBackend()
        #expect(claude.terminalArguments(program: "/u/claude", sessionID: id, agentSessionID: nil, resume: true)
            == ["/u/claude", "--resume", id, "--"])
        #expect(claude.terminalArguments(program: "/u/claude", sessionID: id, agentSessionID: nil, resume: true, followUp: false)
            == ["/u/claude", "--resume", id])
        #expect(ACPBackend.kiro.terminalArguments(program: "/u/kiro-cli", sessionID: id, agentSessionID: "sess_1", resume: true)
            == ["/u/kiro-cli", "chat", "--resume-id", "sess_1", "--"])
        #expect(AntigravityBackend().terminalArguments(program: "/u/agy", sessionID: id, agentSessionID: "4f1c", resume: true)
            == ["/u/agy", "--conversation", "4f1c", "-i"])
    }

    @Test func theHandOffHasTheFollowUpsArgumentsOnlyWithOne() throws {
        let session = manager(FakeClaude())
        let id = try store.sessionID()
        #expect(try session.handOff(program: "/u/claude").arguments == ["/u/claude", "--session-id", id])
        // Handed off, the conversation is Terminal's: the next hand-off is of the new one.
        let next = try store.sessionID()
        #expect(next != id)
        #expect(try session.handOff(program: "/u/claude", followUp: true).arguments == ["/u/claude", "--session-id", next, "--"])
    }

    // MARK: - Ended

    @Test func anotherBackendEndsTheOldSessionsProcess() throws {
        let claudeFake = FakeClaude(), kiroFake = FakeClaude()
        let claude = manager(claudeFake)
        let kiro = kiro(kiroFake)
        let converter = Converter(questionSessions: [.claude: claude, .kiro: kiro])
        var config = Config.default
        config.questionBackend = .claudeSession
        converter.questionSessionsFollow(config)  // noted
        claude.prewarm()
        kiro.prewarm()
        #expect(claude.isRunning && kiro.isRunning)
        converter.questionSessionsFollow(config)  // the same: nothing ends
        #expect(claude.isRunning && kiro.isRunning)
        config.questionBackend = .kiroSession
        converter.questionSessionsFollow(config)
        #expect(!claude.isRunning && claudeFake.last?.terminated == true)
        #expect(kiro.isRunning && kiroFake.last?.terminated == false)
    }

    /// A process that ends only when killed.
    final class Stubborn: ClaudeSessionLauncher, @unchecked Sendable {
        final class Process: ClaudeSessionProcess, @unchecked Sendable {
            private let lock = NSLock()
            private var _terminated = false, _killed = false
            var terminated: Bool { lock.withLock { _terminated } }
            var killed: Bool { lock.withLock { _killed } }
            func send(_ line: Data) throws {}
            func terminate() { lock.withLock { _terminated = true } }
            func kill() { lock.withLock { _killed = true } }
            var isRunning: Bool { !killed }
        }

        private let lock = NSLock()
        private var _last: Process?
        var last: Process? { lock.withLock { _last } }

        func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                   exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
            let process = Process()
            lock.withLock { _last = process }
            return process
        }
    }

    @Test func quittingEndsEachSessionsProcessKillingWhatDoesntEnd() throws {
        let stubborn = Stubborn()
        let session = manager(stubborn)
        session.prewarm()
        let process = try #require(stubborn.last)
        ClaudeSessionManager.stop([session], grace: 0.1)
        #expect(process.terminated && process.killed && !session.isRunning)
    }
}
