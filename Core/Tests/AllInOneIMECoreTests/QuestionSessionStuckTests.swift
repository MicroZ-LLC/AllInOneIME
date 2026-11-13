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
        let first = session.ask("one", in: nil)
        let stuck = try #require(fake.last)
        stuck.started()
        stuck.messageStarted()
        stuck.text("Partial")
        let second = session.ask("two", in: nil)
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
        let stream = session.ask("one", in: nil)
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
        let first = session.ask("one", in: nil)
        let process = try #require(fake.last)
        process.started()
        process.messageStarted()
        process.text("Still")
        let second = session.ask("two", in: nil)
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
        let stream = session.ask("hi", in: nil)
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

    /// A program found (its install check passed) that won't launch: gone since, or not executable. The launcher says
    /// which (Foundation's own error calls both "doesn't exist"); the question fails so that the provider answers,
    /// saying why; the agent can't start until it is looked at again, no sooner than `recheckInterval` after.
    @Test func aProgramThatWontLaunchFallsBackAndIsLookedAtAgainLater() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let gone = folder.appendingPathComponent("gone/claude")
        let program = folder.appendingPathComponent("claude")
        try Data("#!/bin/sh\necho '{\"loggedIn\": true}'\n".utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: program.path)
        func launcher(_ url: URL) -> ProcessClaudeSessionLauncher {
            ProcessClaudeSessionLauncher(processes: FoundationProcessLauncher(), executable: { url }, environment: { [:] })
        }
        try await withInterfaceLanguage("en") {
            for (url, reason) in [(gone, "Program not found: \(gone.path)"), (program, "\(program.path) isn't executable")] {
                #expect(launcher(url).installed())
                #expect(throws: ClaudeSessionError.cannotLaunch(reason)) {
                    try launcher(url).start([], in: folder, output: { _ in }, exited: { _, _ in })
                }
            }
            let error = ClaudeSessionError.cannotLaunch("Program not found: /u/agy")
            #expect(error.fallsBack && error.fallbackNote(for: .antigravity)
                == "The Antigravity session couldn't start: Program not found: /u/agy; the AI provider answered this time")
        }

        let now = Locked(initialState: 1000.0)
        let session = ClaudeSessionManager(launcher: launcher(program), store: store, userSettings: { nil },
                                           uptime: { now.withLock { $0 } })
        let error = try #require(await collect(session.ask("hi", in: nil)).error as? ClaudeSessionError)
        guard case let .cannotLaunch(reason) = error else {
            Issue.record("\(error)")
            return
        }
        #expect(error.fallsBack && reason.contains(program.path))
        #expect(session.availability == .cannotStart && !session.isRunning)
        // Made executable meanwhile: Settings looks again once `recheckInterval` has passed, and finds it ready.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        #expect(await session.checkAvailability() == .cannotStart)
        now.withLock { $0 += ClaudeSessionManager.recheckInterval }
        #expect(await session.checkAvailability() == .ready)
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
            let stream = session.ask("hi", in: nil)
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
        #expect(claude.terminalArguments(program: "/u/claude", sessionID: id, agentSessionID: nil, resume: true, followUp: true)
            == ["/u/claude", "--resume", id, "--"])
        #expect(claude.terminalArguments(program: "/u/claude", sessionID: id, agentSessionID: nil, resume: true, followUp: false)
            == ["/u/claude", "--resume", id])
        #expect(ACPBackend.kiro.terminalArguments(program: "/u/kiro-cli", sessionID: id, agentSessionID: "sess_1", resume: true, followUp: true)
            == ["/u/kiro-cli", "chat", "--resume-id", "sess_1", "--"])
        #expect(AntigravityBackend().terminalArguments(program: "/u/agy", sessionID: id, agentSessionID: "4f1c", resume: true, followUp: true)
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

    /// A process stopped whose end is never told (it ignores even the kill, or what told it is stuck): a question asked
    /// meanwhile waits for its own process `firstAnswerTimeout` at most, then fails so that the provider answers; no
    /// second process starts while the first may still run.
    @Test func aQuestionWaitingForAProcessThatNeverEndsFallsBack() async throws {
        let stubborn = Stubborn()
        let clock = ManualClock()
        let session = manager(stubborn, answerClock: clock)
        defer { session.stop() }
        session.prewarm()
        let first = try #require(stubborn.last)
        session.stop()
        let stream = session.ask("hi", in: nil)
        try #require(await clock.sleepers(within: 10), "the question waits with no time limit")
        clock.advance(by: ClaudeSessionManager.firstAnswerTimeout)
        #expect(await collect(stream).error as? ClaudeSessionError == .noResponse)
        #expect(stubborn.last === first && first.terminated)
    }

    #if os(macOS)
    /// A session's program (`script`'s text after `#!/bin/sh`) that leaves a child in a process group of its own (`set
    /// -m`) holding its output open for a minute, each child's pid written to `children`; the children killed by `body`'s end.
    func withAChildOutsideTheGroup(_ script: String, _ body: (_ program: URL, _ children: URL) async throws -> Void) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let children = folder.appendingPathComponent("children")
        let program = folder.appendingPathComponent("claude")
        try Data("#!/bin/sh\nset -m\n/bin/sleep 60 &\necho $! >> '\(children.path)'\n\(script)\n".utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        defer {
            let pids = (try? String(contentsOf: children, encoding: .utf8)) ?? ""
            for pid in pids.split(whereSeparator: \.isNewline).compactMap({ Int32($0) }) { _ = kill(pid, SIGKILL) }
        }
        try await body(program, children)
    }

    func count(_ children: URL) -> Int {
        ((try? String(contentsOf: children, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).count
    }

    /// Killed, a session's process is ended as soon as it has ended itself, though a child that left its group (which the
    /// kill doesn't reach) holds its output open: its exit is told, its pipes no longer read.
    @Test func aKilledProcessEndsThoughAChildOutsideItsGroupHoldsItsOutput() async throws {
        try await withAChildOutsideTheGroup("exec /bin/sleep 60") { program, children in
            let launcher = ProcessClaudeSessionLauncher(processes: FoundationProcessLauncher(), executable: { program },
                                                        environment: { [:] })
            let ended = Locked<Int32?>(initialState: nil)
            let process = try launcher.start([], in: folder, output: { _ in },
                                             exited: { status, _ in ended.withLock { $0 = status } })
            #expect(await Timing.eventually(within: 10) { count(children) == 1 })
            process.kill()
            #expect(await Timing.eventually(within: 15) { ended.withLock { $0 } != nil }, "its end never told")
            #expect(!process.isRunning)
        }
    }

    /// Stopped, a session's process that ends at once (SIGTERM), leaving a child outside its group holding its output: its
    /// end is told all the same, and the session starts its next process (a prewarm's, waiting for it).
    @Test func aStoppedProcessWhoseChildHoldsItsOutputLetsTheNextOneStart() async throws {
        try await withAChildOutsideTheGroup("exec /bin/sleep 60") { program, children in
            let session = manager(ProcessClaudeSessionLauncher(processes: FoundationProcessLauncher(), executable: { program },
                                                               environment: { [:] }))
            defer { session.stop() }
            session.prewarm()
            #expect(await Timing.eventually(within: 10) { count(children) == 1 })
            session.stop()
            session.prewarm()
            #expect(await Timing.eventually(within: 15) { count(children) == 2 }, "the next process never started")
            #expect(session.isRunning)
        }
    }
    #endif
}
