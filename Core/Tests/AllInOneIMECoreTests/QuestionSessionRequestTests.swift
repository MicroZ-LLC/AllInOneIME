import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// Each request to a question session (`ClaudeSessionManager.Request`) carries the conversation it is of and what its web
/// tools may reach, as it was made: one waiting behind a question being answered is sent with exactly those, whatever
/// another field asked meanwhile. A writing task never goes into an `@question` conversation and never has web tools.
/// And a CLI found signed in again after it wasn't is started again by the next question.
struct QuestionSessionRequestTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("session-request-\(UUID().uuidString)")
    var store: ClaudeSessionStore { ClaudeSessionStore(directory: folder) }

    func claude(_ fake: FakeClaude) -> ClaudeSessionManager {
        ClaudeSessionManager(launcher: fake, store: store, userSettings: { nil })
    }

    func value(_ flag: String, _ arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).map { arguments[$0 + 1] }
    }

    /// The conversation a Claude Code process is on.
    func conversation(_ process: FakeClaude.Process) -> String? {
        value("--session-id", process.arguments) ?? value("--resume", process.arguments)
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

    // MARK: - Claude Code

    /// A writing task asked while a question is answered, then another field's @question: the writing task goes into a
    /// conversation of its own with no web tools, the question into another of its own with them, never the writing
    /// task's.
    @Test func aWritingTaskWaitingBehindAQuestionGoesAloneWithoutTheWeb() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let first = session.ask("first question", in: QuestionConversation())
        let one = try #require(fake.last)
        one.started()
        one.text("Part")
        let writing = session.ask("rewrite this", in: .oneOff)
        let second = session.ask("second question", in: QuestionConversation())
        #expect(fake.processes.count == 1 && one.messages == ["first question"])

        one.done("Part of it.")
        #expect(await collect(first).answers.last == "Part")
        let two = try #require(fake.last)
        #expect(fake.processes.count == 2 && one.terminated, "started again without the web tools")
        #expect(value("--tools", two.arguments) == "" && !two.arguments.contains("--allowedTools"), "\(two.arguments)")
        #expect(two.messages == ["rewrite this"] && conversation(two) != conversation(one))

        two.started()
        two.done("Rewritten.")
        #expect(await collect(writing).answers == ["Rewritten."])
        let three = try #require(fake.last)
        #expect(fake.processes.count == 3 && two.terminated)
        #expect(value("--tools", three.arguments) == ClaudeSession.tools, "\(three.arguments)")
        #expect(three.messages == ["second question"])
        #expect(Set([conversation(one), conversation(two), conversation(three)]).count == 3)
        withExtendedLifetime(second) {}
    }

    /// A question with text the user didn't type (web kept to what was typed: nothing) waiting behind another: an
    /// @question with the web open made meanwhile doesn't open it for it.
    @Test func aQuestionWithTextNotTypedWaitingKeepsItsWebOff() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let first = session.ask("first question", in: QuestionConversation())
        let one = try #require(fake.last)
        one.started()
        one.text("Part")
        let selected = session.ask("summarize the selection", in: QuestionConversation(web: .only([])))
        let third = session.request(QuestionConversation())  // made meanwhile, asked later
        one.done("Done.")
        _ = await collect(first)
        let two = try #require(fake.last)
        #expect(two.messages == ["summarize the selection"] && value("--tools", two.arguments) == "", "\(two.arguments)")
        let asked = third.ask("third question")
        two.started()
        two.done("Summary.")
        _ = await collect(selected)
        let three = try #require(fake.last)
        #expect(three.messages == ["third question"] && value("--tools", three.arguments) == ClaudeSession.tools)
        withExtendedLifetime(asked) {}
    }

    /// A follow-up in the same panel conversation goes on in its agent conversation, with the web it may have now.
    @Test func aFollowUpGoesOnInItsConversation() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let panel = QuestionConversation()
        let first = session.request(panel)
        #expect(!first.continues)
        let answering = first.ask("one")
        let process = try #require(fake.last)
        process.started()
        process.done("1")
        _ = await collect(answering)
        let next = session.request(panel)
        #expect(next.continues)
        _ = next.ask("two")
        #expect(fake.processes.count == 1 && process.messages == ["one", "two"])
    }

    /// A request takes its place in the queue as it is made: another field's question asked before its message comes
    /// waits behind it, and it goes on in its conversation as `continues` said when it was made.
    @Test func aRequestKeepsItsPlaceUntilItsMessageComes() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let panel = QuestionConversation()
        let answering = session.ask("one", in: panel)
        let process = try #require(fake.last)
        process.started()
        process.done("1")
        _ = await collect(answering)
        let followUp = session.request(panel)
        #expect(followUp.continues)
        let other = session.ask("another field's", in: QuestionConversation())
        #expect(fake.processes.count == 1 && process.messages == ["one"], "sent before the request made first")
        _ = followUp.ask("two")
        #expect(fake.processes.count == 1 && process.messages == ["one", "two"])
        withExtendedLifetime(other) {}
    }

    /// Let go of without its message (the question given up before it was asked), a request's place goes.
    @Test func aRequestLetGoOfGivesUpItsPlace() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        do {
            let unasked = session.request(QuestionConversation())
            withExtendedLifetime(unasked) {}
        }
        _ = session.ask("asked", in: QuestionConversation())
        #expect(fake.last?.messages == ["asked"])
    }

    /// Ended before its message came (the session stopped): asked then, it ends so at once and nothing is sent.
    @Test func aRequestEndedBeforeItsMessageEndsWhenAsked() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let request = session.request(QuestionConversation())
        session.stop()
        #expect(await collect(request.ask("too late")).error is CancellationError)
        #expect(fake.processes.isEmpty)
    }

    /// A request of another conversation behind one being answered goes into a new agent conversation: every round of
    /// its conversation is told with it; one going on in its own isn't told what it saw.
    @Test func whatARequestMissedGoesByTheConversationItGoesInto() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let panel = QuestionConversation()
        let rounds = [QuestionChat.Round(question: "one", answer: "1")]
        let answering = session.ask("one", in: panel)
        let process = try #require(fake.last)
        process.started()
        process.done("1")
        _ = await collect(answering)
        session.remember(rounds: rounds)
        #expect(session.missing(rounds, for: session.request(panel)).isEmpty)
        // Another conversation's request made first: this one goes into a new agent conversation.
        let other = session.request(QuestionConversation())
        let after = session.request(panel)
        #expect(!after.continues && session.missing(rounds, for: after) == rounds)
        withExtendedLifetime(other) {}
    }

    /// What a question going into a new agent conversation hid is kept for that conversation: a follow-up there never
    /// gives one of its placeholders to another value.
    @Test func aNewConversationKeepsWhatItsFirstQuestionHid() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let settings = RedactionSettings(enabled: true)
        func hide(_ text: String, _ request: ClaudeSessionManager.Request) -> String {
            session.redacting(settings, for: request) { redaction in redaction?.hide(text) ?? text }.result
        }
        let first = session.request(QuestionConversation())
        #expect(hide("mail a@one.com", first) == "mail [EMAIL_1]")
        let answering = first.ask("mail [EMAIL_1]")
        let one = try #require(fake.last)
        one.started()
        one.text("Sent")
        // Another conversation starts numbering afresh; its follow-up continues from that map.
        let panel = QuestionConversation()
        let second = session.request(panel)
        #expect(!second.continues)
        #expect(hide("and b@two.com", second) == "and [EMAIL_1]")
        let asked = second.ask("and [EMAIL_1]")
        one.done("Sent.")
        _ = await collect(answering)
        let two = try #require(fake.last)
        #expect(two.messages == ["and [EMAIL_1]"] && conversation(two) != conversation(one))
        two.started()
        two.done("OK.")
        _ = await collect(asked)
        let followUp = session.request(panel)
        #expect(followUp.continues)
        #expect(hide("now c@three.com", followUp) == "now [EMAIL_2]", "a placeholder of the conversation given to another value")
    }

    /// A new conversation's question that failed before it was asked (no CLI to start) leaves its agent conversation
    /// unasked, and the next conversation goes into that one: none of the first one's hidden values or numbers go with
    /// it, so the next one's follow-up puts back its own value, never the first one's under the same placeholder.
    @Test func aConversationThatFailedBeforeItWasAskedLeavesNothingHiddenToTheNext() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let settings = RedactionSettings(enabled: true)
        func hide(_ text: String, _ request: ClaudeSessionManager.Request) -> (redaction: Redaction?, result: String) {
            session.redacting(settings, for: request) { redaction in redaction?.hide(text) ?? text }
        }
        fake.missing = true
        let first = session.request(QuestionConversation())
        #expect(hide("To a@one.com.", first).result == "To [EMAIL_1].")
        #expect(await collect(first.ask("To [EMAIL_1].")).error as? ClaudeSessionError == .notInstalled)
        fake.missing = false

        let panel = QuestionConversation()
        let second = session.request(panel)
        #expect(!second.continues)
        #expect(hide("To b@two.com.", second).result == "To [EMAIL_1].")
        let asked = second.ask("To [EMAIL_1].")
        let process = try #require(fake.last)
        process.started()
        process.done("OK.")
        _ = await collect(asked)

        let followUp = session.request(panel)
        #expect(followUp.continues)
        let shorter = hide("shorter", followUp)
        #expect(shorter.result == "shorter")
        #expect(shorter.redaction?.restore("To [EMAIL_1].") == "To b@two.com.", "the first conversation's value put back")
        #expect(hide("and c@three.com", followUp).result == "and [EMAIL_2]")
    }

    @Test func placeholdersStayWithinTheirConversation() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let settings = RedactionSettings(enabled: true)
        let first = session.request(QuestionConversation())
        let hidden = session.redacting(settings, for: first) { redaction in redaction?.hide("secret@company.com") ?? "" }
        #expect(hidden.result == "[EMAIL_1]")
        let stream = first.ask(hidden.result)
        let process = try #require(fake.last)
        process.started()
        process.done("ok")
        _ = await collect(stream)
        let second = session.request(QuestionConversation())
        let fresh = session.redacting(settings, for: second) { redaction in
            redaction?.hide("Write [EMAIL_1] literally") ?? ""
        }
        #expect(fresh.result == "Write [EMAIL_1] literally")
        #expect(fresh.redaction?.restore("[EMAIL_1]") == "[EMAIL_1]")
    }

    /// A follow-up's answer puts back what its own conversation hid before, though the follow-up itself hid nothing
    /// (only it goes in: the agent has the earlier rounds with their placeholders).
    @Test func aFollowUpPutsBackWhatItsConversationHidBefore() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let settings = RedactionSettings(enabled: true)
        let panel = QuestionConversation()
        let first = session.request(panel)
        let hidden = session.redacting(settings, for: first) { redaction in redaction?.hide("mail secret@company.com") ?? "" }
        #expect(hidden.result == "mail [EMAIL_1]")
        let stream = first.ask(hidden.result)
        let process = try #require(fake.last)
        process.started()
        process.done("ok")
        _ = await collect(stream)
        let followUp = session.request(panel)
        #expect(followUp.continues)
        let shorter = session.redacting(settings, for: followUp) { redaction in redaction?.hide("shorter") ?? "" }
        #expect(shorter.result == "shorter")
        #expect(shorter.redaction?.restore("To [EMAIL_1].") == "To secret@company.com.")
    }

    @Test func identicalAnswersToDifferentQuestionsAreDifferentTurns() throws {
        let session = claude(FakeClaude())
        let first = QuestionChat.Round(question: "Is it ready?", answer: "Yes")
        let second = QuestionChat.Round(question: "Is it safe?", answer: "Yes")
        session.remember(rounds: [first])
        #expect(session.missing([first]).isEmpty)
        #expect(session.missing([second]) == [second])
    }

    // MARK: - Codex and ACP agents

    func requests(_ process: FakeClaude.Process, _ method: String) -> [[String: Any]] {
        process.lines.filter { $0["method"] as? String == method }
    }

    func respond(_ process: FakeClaude.Process, _ method: String, _ result: [String: Any] = [:], jsonrpc: Bool) throws {
        let id = try #require(requests(process, method).last?["id"])
        process.say((jsonrpc ? ["jsonrpc": "2.0"] : [:]).merging(["id": id, "result": result]) { $1 })
    }

    /// Codex: the process is opened (its thread started), as `web` says.
    func openCodex(_ process: FakeClaude.Process, thread: String) throws {
        try respond(process, "initialize", ["userAgent": "test"], jsonrpc: false)
        try respond(process, "config/read", ["config": ["model": "gpt"]], jsonrpc: false)
        try respond(process, "thread/start", ["thread": ["id": thread, "name": NSNull()]], jsonrpc: false)
    }

    func codexTurns(_ process: FakeClaude.Process) -> [String] {
        requests(process, "turn/start").compactMap {
            (($0["params"] as? [String: Any])?["input"] as? [[String: Any]])?.first?["text"] as? String
        }
    }

    func endCodexTurn(_ process: FakeClaude.Process, thread: String) throws {
        try respond(process, "turn/start", ["turn": ["id": "turn"]], jsonrpc: false)
        process.say(["method": "turn/completed", "params": ["threadId": thread, "turn": ["id": "turn", "status": "completed"]]])
    }

    @Test func codexSendsAWaitingWritingTaskWithoutWebSearchInAThreadOfItsOwn() async throws {
        let fake = FakeClaude()
        let session = ClaudeSessionManager(backend: CodexBackend(base: folder), launcher: fake)
        defer { session.stop() }
        let first = session.ask("first question", in: QuestionConversation())
        let one = try #require(fake.last)
        #expect(one.arguments.contains(#"web_search="live""#))
        try openCodex(one, thread: "t1")
        #expect(await Timing.eventually(within: 10) { codexTurns(one) == ["first question"] })
        let writing = session.ask("rewrite this", in: .oneOff)
        let second = session.ask("second question", in: QuestionConversation())
        try endCodexTurn(one, thread: "t1")
        _ = await collect(first)
        let two = try #require(fake.last)
        #expect(fake.processes.count == 2 && one.terminated && codexTurns(one) == ["first question"])
        #expect(two.arguments.contains(#"web_search="disabled""#) && !two.arguments.contains(#"web_search="live""#))
        try openCodex(two, thread: "t2")
        #expect(await Timing.eventually(within: 10) { codexTurns(two) == ["rewrite this"] })
        try endCodexTurn(two, thread: "t2")
        _ = await collect(writing)
        let three = try #require(fake.last)
        #expect(fake.processes.count == 3 && three.arguments.contains(#"web_search="live""#))
        try openCodex(three, thread: "t3")
        #expect(await Timing.eventually(within: 10) { codexTurns(three) == ["second question"] })
        withExtendedLifetime(second) {}
    }

    func prompts(_ process: FakeClaude.Process) -> [String] {
        requests(process, "session/prompt").compactMap {
            (($0["params"] as? [String: Any])?["prompt"] as? [[String: Any]])?.first?["text"] as? String
        }
    }

    /// Kiro: the process is opened, its session in `mode`.
    func openKiro(_ process: FakeClaude.Process, session id: String) throws {
        let modes: [String: Any] = ["currentModeId": "vibe", "availableModes": [
            ["id": "vibe"], ["id": ACPBackend.kiroMode], ["id": ACPBackend.kiroOfflineMode]]]
        try respond(process, "initialize", ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]], jsonrpc: true)
        try respond(process, "session/new", ["sessionId": id, "modes": modes], jsonrpc: true)
        try respond(process, "session/set_mode", jsonrpc: true)
    }

    func mode(_ process: FakeClaude.Process) -> String? {
        (requests(process, "session/set_mode").last?["params"] as? [String: Any])?["modeId"] as? String
    }

    @Test func anACPAgentSendsAWaitingWritingTaskInItsOfflineModeInASessionOfItsOwn() async throws {
        let fake = FakeClaude()
        var kiro = ACPBackend.kiro
        kiro.base = folder
        let session = ClaudeSessionManager(backend: kiro, launcher: fake)
        defer { session.stop() }
        let first = session.ask("first question", in: QuestionConversation())
        let one = try #require(fake.last)
        try openKiro(one, session: "s1")
        #expect(mode(one) == ACPBackend.kiroMode)
        #expect(await Timing.eventually(within: 10) { prompts(one) == ["first question"] })
        let writing = session.ask("rewrite this", in: .oneOff)
        let second = session.ask("second question", in: QuestionConversation())
        try respond(one, "session/prompt", ["stopReason": "end_turn"], jsonrpc: true)
        _ = await collect(first)
        let two = try #require(fake.last)
        #expect(fake.processes.count == 2 && one.terminated && prompts(one) == ["first question"])
        try openKiro(two, session: "s2")
        #expect(mode(two) == ACPBackend.kiroOfflineMode)
        #expect(await Timing.eventually(within: 10) { prompts(two) == ["rewrite this"] })
        try respond(two, "session/prompt", ["stopReason": "end_turn"], jsonrpc: true)
        _ = await collect(writing)
        let three = try #require(fake.last)
        try openKiro(three, session: "s3")
        #expect(mode(three) == ACPBackend.kiroMode)
        #expect(await Timing.eventually(within: 10) { prompts(three) == ["second question"] })
        withExtendedLifetime(second) {}
    }

    @Test func antigravitySendsAWaitingWritingTaskWithItsOfflineAgent() async throws {
        let fake = FakeClaude()
        let session = ClaudeSessionManager(backend: AntigravityBackend(base: folder), launcher: fake)
        defer { session.stop() }
        func agent(_ process: FakeClaude.Process) -> String? { value("--agent", process.arguments) }
        /// agy's handshake: `initialize`, `session/new`, then the fast model set (`AntigravityDriver`).
        func open(_ process: FakeClaude.Process, session id: String) throws {
            try respond(process, "initialize", ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]], jsonrpc: true)
            try respond(process, "session/new", ["sessionId": id], jsonrpc: true)
            try respond(process, "session/set_model", jsonrpc: true)
        }
        let first = session.ask("first question", in: QuestionConversation())
        let one = try #require(fake.last)
        #expect(agent(one) == AntigravityBackend.agentName)
        try open(one, session: "g1")
        #expect(await Timing.eventually(within: 10) { prompts(one) == ["first question"] })
        let writing = session.ask("rewrite this", in: .oneOff)
        let second = session.ask("second question", in: QuestionConversation())
        try respond(one, "session/prompt", ["stopReason": "end_turn"], jsonrpc: true)
        _ = await collect(first)
        let two = try #require(fake.last)
        #expect(fake.processes.count == 2 && one.terminated && agent(two) == AntigravityBackend.offlineAgentName)
        try open(two, session: "g2")
        #expect(await Timing.eventually(within: 10) { prompts(two) == ["rewrite this"] })
        #expect(prompts(one) == ["first question"])
        try respond(two, "session/prompt", ["stopReason": "end_turn"], jsonrpc: true)
        _ = await collect(writing)
        let three = try #require(fake.last)
        #expect(fake.processes.count == 3 && two.terminated && agent(three) == AntigravityBackend.agentName)
        try open(three, session: "g3")
        #expect(await Timing.eventually(within: 10) { prompts(three) == ["second question"] })
        withExtendedLifetime(second) {}
    }

    /// An agent that can't have its web tools off isn't asked a writing task; a question behind it, with the web it may
    /// have, still is.
    @Test func aRequestItsAgentCantKeepToTheWebFailsAloneTheNextGoesOn() async throws {
        let fake = FakeClaude()
        let plain = ACPBackend(agent: .kiro, folderName: "plain", launch: ["acp"], availability: [], resume: [], start: [],
                               base: folder)
        let session = ClaudeSessionManager(backend: plain, launcher: fake)
        defer { session.stop() }
        var writing: AsyncThrowingStream<String, Error>?
        var question: AsyncThrowingStream<String, Error>?
        do {
            let first = session.request(QuestionConversation())  // holds the queue until it goes
            writing = session.ask("rewrite this", in: .oneOff)
            question = session.ask("a question", in: QuestionConversation())
            #expect(fake.processes.isEmpty)
            withExtendedLifetime(first) {}
        }
        #expect(await collect(try #require(writing)).error as? ClaudeSessionError == .notWebOnly)
        let process = try #require(fake.last)
        try respond(process, "initialize", ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]], jsonrpc: true)
        try respond(process, "session/new", ["sessionId": "s1"], jsonrpc: true)
        #expect(await Timing.eventually(within: 10) { prompts(process) == ["a question"] })
        #expect(fake.processes.count == 1)
        withExtendedLifetime(question) {}
    }

    // MARK: - Signed in again

    /// `claude auth status` (the sign-in check) run by `fake`: answered `signedIn`.
    func answerCheck(_ fake: FakeClaude, signedIn: Bool) async throws {
        #expect(await Timing.eventually(within: 10) { fake.processes.contains { $0.arguments.contains("auth") && !$0.terminated } })
        let check = try #require(fake.processes.last { $0.arguments.contains("auth") })
        check.say(["loggedIn": signedIn])
        check.exit(signedIn ? 0 : 1)
    }

    /// Signed out when the process started (a question failed so), then found signed in (Settings → AI looked): the next
    /// question starts the process again, on the same conversation, never asking the one with the old sign-in.
    @Test func aCLISignedInAgainIsStartedAgainByTheNextQuestion() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let panel = QuestionConversation()
        let first = session.ask("one", in: panel)
        let process = try #require(fake.last)
        process.started()
        process.say(["type": "assistant", "error": "authentication_failed",
                     "message": ["content": [["type": "text", "text": "Not logged in · Please run /login"]]]])
        process.say(["type": "result", "subtype": "success", "is_error": true, "result": "Not logged in"])
        #expect(await collect(first).error as? ClaudeSessionError == .signedOut)
        #expect(session.availability == .signedOut)
        let look = Task { await session.checkAvailability(force: true) }
        try await answerCheck(fake, signedIn: true)
        #expect(await look.value == .ready)
        _ = session.ask("two", in: panel)
        let again = try #require(fake.processes.last { !$0.arguments.contains("auth") })
        #expect(process.terminated && again !== process && again.messages == ["two"])
        #expect(conversation(again) == conversation(process))
    }

    /// Found still signed in: the process stays.
    @Test func aCLIFoundStillSignedInKeepsItsProcess() async throws {
        let fake = FakeClaude()
        let session = claude(fake)
        defer { session.stop() }
        let panel = QuestionConversation()
        let first = session.ask("one", in: panel)
        let process = try #require(fake.last)
        process.started()
        process.done("1")
        _ = await collect(first)
        let look = Task { await session.checkAvailability(force: true) }
        try await answerCheck(fake, signedIn: true)
        #expect(await look.value == .ready)
        _ = session.ask("two", in: panel)
        #expect(!process.terminated && process.messages == ["one", "two"])
    }
}
