import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// Stands in for `claude`: each start is a `Process` the test drives, saying what Claude Code would (`started`, `text`,
/// `done`, `exit`) and seeing what it was sent (`messages`, `interrupts`).
final class FakeClaude: ClaudeSessionLauncher, @unchecked Sendable {
    final class Process: ClaudeSessionProcess, @unchecked Sendable {
        let arguments: [String]
        let directory: URL
        private let output: @Sendable (Data) -> Void
        private let exited: @Sendable (Int32, String) -> Void
        private let lock = NSLock()
        private var _lines: [[String: Any]] = []
        private var _terminated = false

        init(arguments: [String], directory: URL, output: @escaping @Sendable (Data) -> Void,
             exited: @escaping @Sendable (Int32, String) -> Void) {
            self.arguments = arguments
            self.directory = directory
            self.output = output
            self.exited = exited
        }

        var terminated: Bool { lock.withLock { _terminated } }
        var lines: [[String: Any]] { lock.withLock { _lines } }
        /// The user messages sent, in order.
        var messages: [String] {
            lines.compactMap { $0["type"] as? String == "user" ? ($0["message"] as? [String: Any])?["content"] as? String : nil }
        }
        var interrupts: Int {
            lines.filter { ($0["request"] as? [String: Any])?["subtype"] as? String == "interrupt" }.count
        }

        func send(_ line: Data) throws {
            #expect(line.last == 0x0A)
            let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
            lock.withLock { _lines.append(object) }
        }

        func terminate() { lock.withLock { _terminated = true } }

        func say(_ object: [String: Any]) { output(try! JSONSerialization.data(withJSONObject: object)) }
        func started() { say(["type": "system", "subtype": "init", "session_id": "x"]) }
        func text(_ text: String) {
            say(["type": "stream_event", "parent_tool_use_id": NSNull(),
                 "event": ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text]]])
        }
        func messageStarted() { say(["type": "stream_event", "parent_tool_use_id": NSNull(), "event": ["type": "message_start"]]) }
        func done(_ result: String = "") {
            say(["type": "result", "subtype": "success", "is_error": false, "result": result, "terminal_reason": "completed"])
        }
        func interrupted() {
            say(["type": "result", "subtype": "error_during_execution", "is_error": true, "terminal_reason": "aborted_streaming"])
        }
        func exit(_ status: Int32 = 1, _ message: String = "") { exited(status, message) }
    }

    private let lock = NSLock()
    private var _processes: [Process] = []
    private var _missing = false
    var processes: [Process] { lock.withLock { _processes } }
    var last: Process? { processes.last }
    /// No `claude` on this Mac.
    var missing: Bool {
        get { lock.withLock { _missing } }
        set { lock.withLock { _missing = newValue } }
    }

    func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
               exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
        if missing { throw ClaudeSessionError.notInstalled }
        let process = Process(arguments: arguments, directory: directory, output: output, exited: exited)
        lock.withLock { _processes.append(process) }
        return process
    }
}

/// The input method's own Claude Code session (`ClaudeSession`, `ClaudeSessionManager`): the flags it starts with, what
/// it reads, and the process kept running: started ahead (prewarm), resumed, ended when idle, started again after a
/// crash, a turn interrupted, handed to Terminal; and `@question` going to it, or to the provider when it can't answer.
struct ClaudeSessionTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("claude-session-\(UUID().uuidString)")
    var store: ClaudeSessionStore { ClaudeSessionStore(directory: folder) }

    func manager(_ fake: FakeClaude, clock: any Clock<Duration> = ContinuousClock(),
                 alive: @escaping @Sendable (Int32) -> Bool = { _ in false }) -> ClaudeSessionManager {
        // Not the user's real Claude Code settings (ClaudeSessionProviderTests has those).
        ClaudeSessionManager(launcher: fake, store: store, clock: clock, isAlive: alive, userSettings: { nil })
    }

    /// Everything `stream` gives, and how it ended.
    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (answers: [String], error: Error?) {
        var answers: [String] = []
        do {
            for try await answer in stream { answers.append(answer) }
            return (answers, nil)
        } catch {
            return (answers, error)
        }
    }

    /// `process` answers `text` to the question it was sent.
    func answer(_ process: FakeClaude.Process, _ text: String) {
        process.started()
        for word in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            process.text((word.offset == 0 ? "" : " ") + word.element)
        }
        process.done(text)
    }

    // MARK: - What it starts with and reads

    @Test func theFlagsAreTheCheckedOnes() {
        let id = "8d6a1f6e-0d2c-4c4e-9a43-0c1a2b3c4d5e"
        let common = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        let rest = ["--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch", "--permission-mode", "dontAsk",
                    "--setting-sources", "project", "--strict-mcp-config"]
        #expect(ClaudeSession.arguments(sessionID: id, resume: false) == common + ["--session-id", id] + rest)
        #expect(ClaudeSession.arguments(sessionID: id, resume: true) == common + ["--resume", id] + rest)
        #expect(ClaudeSession.terminalArguments(claude: "/u/claude", sessionID: id, resume: true) == ["/u/claude", "--resume", id])
    }

    @Test func linesAreReadAsClaudeCodeWritesThem() {
        func event(_ text: String) -> ClaudeSession.Event { ClaudeSession.event(Data(text.utf8)) }
        // As Claude Code 2.1.303 wrote them (shortened).
        #expect(event(#"{"type":"system","subtype":"init","cwd":"/x","session_id":"s","tools":["WebFetch","WebSearch"]}"#) == .started)
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"OK"}},"session_id":"s","parent_tool_use_id":null}"#) == .text("OK"))
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}},"parent_tool_use_id":null}"#) == .other)
        #expect(event(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"sub"}},"parent_tool_use_id":"toolu_1"}"#) == .other)
        #expect(event(#"{"type":"stream_event","event":{"type":"message_start","message":{}},"parent_tool_use_id":null}"#) == .messageStarted)
        #expect(event(#"{"type":"result","subtype":"success","is_error":false,"result":"OK","terminal_reason":"completed"}"#)
                == .result(error: false, interrupted: false, text: "OK", status: nil))
        #expect(event(#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":null,"terminal_reason":"aborted_streaming"}"#)
                == .result(error: true, interrupted: true, text: "", status: nil))
        #expect(event(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Not logged in · Please run /login"}]},"error":"authentication_failed"}"#)
                == .apiError(code: "authentication_failed", message: "Not logged in · Please run /login"))
        #expect(event(#"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Bash"}}"#)
                == .permissionRequest(id: "r1"))
        #expect(event(#"{"type":"control_response","response":{"subtype":"success","request_id":"int1"}}"#) == .other)
        #expect(event("not json") == .other)
        #expect(ClaudeSession.signedIn(authStatus: Data(#"{"loggedIn": true, "authMethod": "claude.ai"}"#.utf8)) == true)
        #expect(ClaudeSession.signedIn(authStatus: Data(#"{"loggedIn": false}"#.utf8)) == false)
        #expect(ClaudeSession.signedIn(authStatus: Data("".utf8)) == nil)
    }

    @Test func theIdIsMadeOnceAndTheFolderHasItsInstructions() throws {
        let id = try store.sessionID()
        #expect(UUID(uuidString: id) != nil && id == id.lowercased())
        #expect(try store.sessionID() == id)
        let instructions = try String(contentsOf: folder.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        #expect(instructions.hasPrefix("You are the assistant inside an input method."))
        let fresh = try store.startOver()
        let now = try store.sessionID()
        #expect(fresh != id && now == fresh && !store.resumable)
    }

    // MARK: - The process

    @Test func theFirstQuestionStartsTheSessionAndALaterProcessResumesIt() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("what is rust")
        let first = try #require(fake.last)
        let id = try store.sessionID()
        #expect(first.arguments.contains("--session-id") && first.arguments.contains(id) && first.directory == folder)
        #expect(first.messages == ["what is rust"])
        answer(first, "A systems language.")
        let got = await collect(stream)
        #expect(got.answers == ["A", "A systems", "A systems language."] && got.error == nil)
        #expect(store.resumable && session.availability == .ready)

        // It ended (killed, a crash): the next question starts it again, on the same session.
        first.exit(9)
        #expect(!session.isRunning)
        let next = session.ask("and go?")
        let second = try #require(fake.last)
        #expect(fake.processes.count == 2 && Array(second.arguments.drop { $0 != "--resume" }.prefix(2)) == ["--resume", id])
        answer(second, "Also a systems language.")
        #expect(await collect(next).answers.last == "Also a systems language.")
    }

    @Test func prewarmStartsTheProcessTheQuestionThenUsesIt() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        session.prewarm()
        let process = try #require(fake.last)
        #expect(session.isRunning && process.lines.isEmpty)
        session.prewarm()  // already running
        let stream = session.ask("刚才那个问题")
        #expect(fake.processes.count == 1 && process.messages == ["刚才那个问题"])
        answer(process, "你问的是 rust")
        #expect(await collect(stream).answers.last == "你问的是 rust")
    }

    @Test func idleForFifteenMinutesTheProcessEnds() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = manager(fake, clock: clock)
        let stream = session.ask("one")
        let process = try #require(fake.last)
        answer(process, "1")
        _ = await collect(stream)
        #expect(await clock.sleepers(1))
        clock.advance(by: .seconds(14 * 60))
        #expect(!process.terminated)
        clock.advance(by: .seconds(60))
        #expect(await Timing.eventually { process.terminated })
        #expect(!session.isRunning)
        // Its exit afterwards is of no session; the next question resumes it.
        process.exit(0)
        _ = session.ask("two")
        #expect(fake.processes.count == 2 && fake.last?.arguments.contains("--resume") == true)
    }

    @Test func aQuestionPutsTheIdleTimeOffAndAPrewarmedProcessEndsToo() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = manager(fake, clock: clock)
        session.prewarm()
        let process = try #require(fake.last)
        #expect(await clock.sleepers(1))
        let stream = session.ask("slow one")
        #expect(await Timing.eventually { clock.sleeping == 0 })  // no idle time while it answers
        clock.advance(by: .seconds(20 * 60))
        #expect(!process.terminated)
        answer(process, "done")
        _ = await collect(stream)
        #expect(await clock.sleepers(1))
        clock.advance(by: .seconds(15 * 60))
        #expect(await Timing.eventually { process.terminated })
    }

    @Test func aCrashWhileAnsweringFailsThatQuestionAndTheNextResumes() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("one")
        let process = try #require(fake.last)
        process.started()
        process.text("Half")
        process.exit(134, "Segmentation fault")
        let got = await collect(stream)
        #expect(got.answers == ["Half"] && got.error as? ClaudeSessionError == .exited(134, "Segmentation fault"))
        #expect((got.error as? ClaudeSessionError)?.fallsBack == false)
        let next = session.ask("again")
        let restarted = try #require(fake.last)
        #expect(fake.processes.count == 2 && restarted.arguments.contains("--resume") && restarted.messages == ["again"])
        answer(restarted, "Whole")
        #expect(await collect(next).answers.last == "Whole")
    }

    @Test func aSessionThatCantStartIsStartedOnceMoreTheOtherWay() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        _ = try store.sessionID()
        store.markResumable()  // but Claude Code has no conversation for it ("No conversation found")
        let stream = session.ask("hello")
        let first = try #require(fake.last)
        #expect(first.arguments.contains("--resume"))
        first.say(["type": "result", "subtype": "error_during_execution", "is_error": true])  // before any init
        first.exit(1, "No conversation found with session ID")
        let second = try #require(fake.last)
        #expect(fake.processes.count == 2 && second.arguments.contains("--session-id") && second.messages == ["hello"])
        answer(second, "Hi")
        #expect(await collect(stream).answers.last == "Hi")
        #expect(store.resumable)
    }

    @Test func givingUpTheAnswerInterruptsTheTurnAndTheProcessStays() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("count to 200")
        let process = try #require(fake.last)
        process.started()
        process.text("1 2 3")
        let reading = Task { await collect(stream) }
        try await Task.sleep(for: .milliseconds(50))
        reading.cancel()
        #expect(await Timing.eventually { process.interrupts == 1 })
        #expect(!process.terminated && session.isRunning)
        // A question asked meanwhile waits for the interrupted turn to end.
        let next = session.ask("still there?")
        #expect(process.messages == ["count to 200"])
        process.interrupted()
        #expect(process.messages == ["count to 200", "still there?"])
        answer(process, "yes")
        #expect(await collect(next).answers.last == "yes")
        #expect(fake.processes.count == 1)
    }

    @Test func interruptEndsTheAnswerAtOnce() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("long")
        let process = try #require(fake.last)
        process.started()
        process.text("a")
        session.interrupt()
        #expect(await collect(stream).error is CancellationError)
        #expect(process.interrupts == 1 && !process.terminated)
    }

    @Test func aWebSearchStartsTheAnswerAgain() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("weather in Paris now")
        let process = try #require(fake.last)
        process.started()
        process.messageStarted()
        process.text("Let me look.")
        process.messageStarted()  // after the search's result
        process.text("Sunny, 18 °C.")
        process.done("Sunny, 18 °C.")
        #expect(await collect(stream).answers == ["Let me look.", "Sunny, 18 °C."])
    }

    @Test func aPermissionRequestIsDenied() throws {
        let fake = FakeClaude()
        let session = manager(fake)
        _ = session.ask("run ls")
        let process = try #require(fake.last)
        process.say(["type": "control_request", "request_id": "p1", "request": ["subtype": "can_use_tool", "tool_name": "Bash"]])
        let reply = try #require(process.lines.last?["response"] as? [String: Any])
        #expect(reply["request_id"] as? String == "p1" && (reply["response"] as? [String: Any])?["behavior"] as? String == "deny")
    }

    @Test func handingOffEndsTheProcessAndNoneStartsWhileTerminalHasIt() async throws {
        let fake = FakeClaude()
        let terminal = Locked(initialState: true)
        let session = manager(fake, alive: { pid in pid == 4242 && terminal.withLock { $0 } })
        let stream = session.ask("one")
        let process = try #require(fake.last)
        answer(process, "1")
        _ = await collect(stream)
        let (arguments, directory) = try session.handOff(claude: "/u/claude")
        #expect(process.terminated && !session.isRunning)
        let id = try store.sessionID()
        #expect(arguments == ["/u/claude", "--resume", id] && directory == folder)
        // Terminal's Claude Code runs (its script wrote its id): no process here, the question goes elsewhere.
        try Data("4242".utf8).write(to: store.terminalPIDFile)
        session.prewarm()
        let refused = await collect(session.ask("two"))
        #expect(refused.error as? ClaudeSessionError == .openInTerminal && (refused.error as? ClaudeSessionError)?.fallsBack == true)
        #expect(fake.processes.count == 1)
        // It quit: the next question resumes the session here.
        terminal.withLock { $0 = false }
        _ = session.ask("three")
        #expect(fake.processes.count == 2 && fake.last?.arguments.contains("--resume") == true)
        #expect(store.terminalPID() == nil)
    }

    @Test func signedOutAndNotInstalledFallBack() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("hi")
        let process = try #require(fake.last)
        process.started()
        process.say(["type": "assistant", "error": "authentication_failed",
                     "message": ["content": [["type": "text", "text": "Not logged in · Please run /login"]]]])
        process.say(["type": "result", "subtype": "success", "is_error": true, "result": "Not logged in · Please run /login",
                     "terminal_reason": "api_error"])
        let signedOut = await collect(stream)
        #expect(signedOut.answers.isEmpty && signedOut.error as? ClaudeSessionError == .signedOut)
        #expect(session.availability == .signedOut)
        // Over the subscription's limit.
        let limited = session.ask("hi again")
        process.started()
        process.say(["type": "assistant", "error": "rate_limit", "message": ["content": [["type": "text", "text": "You've hit your limit"]]]])
        process.say(["type": "result", "subtype": "success", "is_error": true, "result": "You've hit your limit"])
        #expect(await collect(limited).error as? ClaudeSessionError == .limitReached("You've hit your limit"))

        let missing = FakeClaude()
        missing.missing = true
        let none = ClaudeSessionManager(launcher: missing, store: ClaudeSessionStore(directory: folder.appendingPathComponent("b")))
        let error = await collect(none.ask("hi")).error as? ClaudeSessionError
        #expect(error == .notInstalled && error?.fallsBack == true && none.availability == .notInstalled)
    }

    @Test func whichBackendAnswers() {
        let session = manager(FakeClaude())
        var config = Config.default
        #expect(!session.answersQuestions(config))  // not looked at yet
        session.availability = .ready
        #expect(session.answersQuestions(config))
        config.questionBackend = .provider
        #expect(!session.answersQuestions(config))
        config.questionBackend = .claudeSession
        session.availability = .notInstalled
        #expect(session.answersQuestions(config))  // picked: tried, and the provider answers with why (see below)
        // Kept in the file only once picked.
        #expect(!String(decoding: try! JSONEncoder().encode(Config.default), as: UTF8.self).contains("questionBackend"))
        let decoded = try? JSONDecoder().decode(Config.self, from: Data(#"{"questionBackend":"claudeSession"}"#.utf8))
        #expect(decoded?.questionBackend == .claudeSession)
        #expect(ICloudSync.category(of: "questionBackend") == nil)
    }

    // MARK: - @question through the converter

    @Test func aQuestionGoesToTheSessionAloneAndItsFollowUpAlone() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        var settings = Config.default
        settings.provider = .apple
        settings.questionBackend = .claudeSession
        let config = settings
        let apple = StubAppleModel(answer: ["from the provider"])
        let converter = Converter(loadConfig: { config }, appleModel: apple, claudeSession: session)
        let stream = converter.generate(.question, input: "what is rust")
        #expect(await Timing.eventually { fake.last?.messages == ["what is rust"] })
        answer(try #require(fake.last), "A systems language.")
        var last: ConversionUpdate?
        for try await update in stream { last = update }
        #expect(last?.isFinal == true && last?.result.versions.first?.text == "A systems language." && last?.note == nil)
        #expect(apple.requests.isEmpty)
        // A follow-up in the panel: only the new question goes (the session has the first).
        let turns = [Refinement.Turn(answer: ConversionResult(versions: [CandidateLine("A systems language.")]), instruction: "刚才那个问题的答案再短一点")]
        let followUp = converter.generate(.question, input: "what is rust", turns: turns)
        #expect(await Timing.eventually { fake.last?.messages.count == 2 })
        #expect(fake.last?.messages.last == "刚才那个问题的答案再短一点")
        answer(try #require(fake.last), "Rust.")
        last = nil
        for try await update in followUp { last = update }
        #expect(last?.result.versions.first?.text == "Rust.")
    }

    @Test func aQuestionAboutAllInOneIMEGoesToTheSessionWithTheGuidesExcerpts() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        var settings = Config.default
        settings.provider = .apple
        settings.questionBackend = .claudeSession
        let config = settings
        let apple = StubAppleModel(answer: ["from the provider"])
        let guide = "## Shuangpin / 双拼\nSettings → Input → Chinese → Typing.\n## Magic key / 魔法键\nSettings → General → Magic key."
        let converter = Converter(loadConfig: { config }, loadUserGuide: { guide }, appleModel: apple, claudeSession: session)
        let about = converter.generate(.question, input: "怎么打开双拼")
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        let message = try #require(fake.last?.messages.first)
        // The question first, then the excerpts as the provider gets them (`Prompt.userGuide`).
        #expect(message.hasPrefix("怎么打开双拼\n\n") && message.contains(Prompt.userGuideTitle)
                && message.contains("Settings → Input → Chinese → Typing."))
        answer(try #require(fake.last), "Settings → Input → Chinese → Typing.")
        for try await _ in about {}
        // Any other question goes as it was typed.
        let other = converter.generate(.question, input: "what is rust")
        #expect(await Timing.eventually { fake.last?.messages.count == 2 })
        #expect(fake.last?.messages.last == "what is rust")
        answer(try #require(fake.last), "A systems language.")
        for try await _ in other {}
        #expect(apple.requests.isEmpty)
    }

    @Test func withoutClaudeTheProviderAnswersAndThePanelSaysWhy() async throws {
        let fake = FakeClaude()
        fake.missing = true
        let session = manager(fake)
        var settings = Config.default
        settings.provider = .apple
        settings.questionBackend = .claudeSession
        let config = settings
        let apple = StubAppleModel(answer: ["From the provider."])
        let converter = Converter(loadConfig: { config }, appleModel: apple, claudeSession: session)
        var last: ConversionUpdate?
        for try await update in converter.generate(.question, input: "what is rust") { last = update }
        #expect(last?.result.versions.first?.text == "From the provider." && apple.requests.count == 1)
        #expect(last?.note == ClaudeSessionError.notInstalled.fallbackNote)
        // Writing never goes to the session.
        session.availability = .ready
        for try await _ in converter.convert("hello wrold") {}
        #expect(fake.processes.isEmpty && apple.requests.count == 2)
    }

    // MARK: - The panel

    @Test func inTheSessionThereIsNoLastRoundAndTheHandOffResumesIt() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.questionRounds = 2
        c.questionSession = true
        c.handoffChoices = ChatHandoff.withSession([.claudeCode, .claudeWeb, .copy])
        #expect(c.handoffChoices == [.claudeSession, .claudeWeb, .copy])
        c.remembersQuestions = false
        c.setInputMode(.english)
        let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
        let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
        func type(_ s: String) { for ch in s { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) } }
        _ = c.handleKeyDown(at)
        type("question")
        _ = c.handleKeyDown(tab)
        type("one")
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("1")]), isFinal: true, id: 1)
        for (round, question) in ["two", "three"].enumerated() {
            type(question)
            // ⏎ asks the follow-up (⇧⏎ inserts the answer).
            let started = c.handleKeyDown(enterKey).effects.compactMap { effect -> Int? in
                if case let .startRefine(_, id) = effect { return id } else { return nil }
            }.first
            guard let id = started else {
                Issue.record("round \(round + 2) wasn't asked")
                return
            }
            _ = c.receive(ConversionResult(versions: [CandidateLine(question)]), isFinal: true, id: id)
        }
        #expect(c.chatRound == 3 && !c.chatAtLimit && !c.showsHandoff)  // past `questionRounds` (2)
        let commandReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .command)
        _ = c.handleKeyDown(commandReturn)
        #expect(c.showsHandoff)
        type("and four")
        let effects = c.handOff(to: .claudeSession)
        #expect(effects.contains(.continueClaudeSession(followUp: "and four")))
        #expect(!effects.contains { if case .continueInClaudeCode = $0 { return true } else { return false } })
        #expect(ChatHandoff.shownIndices([.claudeSession, .copy], picked: .claude, installed: { _ in true }) == [1])
    }
}
