import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// An `@question`'s answer the session takes longer for: in the panel when it is done in time, else in the background,
/// then a notification and clipboard history (`AnswerRelay`, `LateAnswer`, `InputSession.answerToBackground`).
struct LateAnswerTests {
    func update(_ text: String, final: Bool) -> ConversionUpdate {
        ConversionUpdate(result: ConversionResult(versions: [CandidateLine(text, isComplete: final)]), rawText: text, isFinal: final,
                         elapsed: 0, firstTokenLatency: nil, fromCache: false)
    }

    final class Delivered: @unchecked Sendable {
        let answers = Locked<[LateAnswer]>(initialState: [])
        var all: [LateAnswer] { answers.withLock { $0 } }
        var deliver: @Sendable (LateAnswer) -> Void { { answer in self.answers.withLock { $0.append(answer) } } }
    }

    // MARK: - The relay

    @Test func doneInTimeEverythingGoesToTheFieldAndNothingIsDelivered() async throws {
        let delivered = Delivered()
        let relay = AnswerRelay(question: "q", deliver: delivered.deliver)
        relay.answeredInSession(true)
        let (source, continuation) = AsyncThrowingStream<ConversionUpdate, Error>.makeStream()
        let field = relay.attach(source)
        continuation.yield(update("An", final: false))
        continuation.yield(update("An answer", final: true))
        continuation.finish()
        var texts: [String] = []
        for try await update in field { texts.append(update.result.versions.first?.text ?? "") }
        #expect(texts == ["An", "An answer"])
        #expect(!relay.detach() && delivered.all.isEmpty)
    }

    @Test func detachedTheFieldsStreamEndsAndTheAnswerIsDeliveredWhenDone() async throws {
        let delivered = Delivered()
        let relay = AnswerRelay(question: "What changed in the deploy?\nand why", deliver: delivered.deliver)
        let (source, continuation) = AsyncThrowingStream<ConversionUpdate, Error>.makeStream()
        let field = relay.attach(source)
        let reading = Task { () -> Int in
            var count = 0
            for try await _ in field { count += 1 }
            return count
        }
        continuation.yield(update("The", final: false))
        #expect(!relay.detach(), "not told a session answers yet")
        relay.answeredInSession(true)
        #expect(await Timing.eventually(within: 5) { relay.detachable })
        #expect(relay.detach())
        #expect(try await reading.value <= 1)  // the field's stream ended there, not given up
        continuation.yield(update("The deploy went out at 10:42.\n\nDetails: …", final: true))
        continuation.finish()
        #expect(await Timing.eventually(within: 5) { delivered.all.count == 1 })
        let answer = try #require(delivered.all.first)
        #expect(answer.answer == "The deploy went out at 10:42.\n\nDetails: …")
        #expect(answer.title == "What changed in the deploy? and why" && answer.body == "The deploy went out at 10:42.")
    }

    @Test func givenUpInThePanelTheAnswerStops() async throws {
        let delivered = Delivered()
        let relay = AnswerRelay(question: "q", deliver: delivered.deliver)
        relay.answeredInSession(true)
        let stopped = Locked(initialState: false)
        let source = AsyncThrowingStream<ConversionUpdate, Error> { continuation in
            continuation.onTermination = { termination in
                if case .cancelled = termination { stopped.withLock { $0 = true } }
            }
        }
        let field = relay.attach(source)
        let reading = Task { for try await _ in field {} }
        try await Task.sleep(nanoseconds: 20_000_000)
        reading.cancel()  // Esc: the field's request stopped
        #expect(await Timing.eventually(within: 5) { stopped.withLock { $0 } })
        #expect(!relay.detach() && delivered.all.isEmpty)
    }

    @Test func failingInTheBackgroundIsDeliveredAsAFailure() async throws {
        let delivered = Delivered()
        let relay = AnswerRelay(question: "q", deliver: delivered.deliver)
        relay.answeredInSession(true)
        let (source, continuation) = AsyncThrowingStream<ConversionUpdate, Error>.makeStream()
        let field = relay.attach(source)
        #expect(relay.detach())
        continuation.finish(throwing: DescribedError(message: "The session ended"))
        #expect(await Timing.eventually(within: 5) { delivered.all.count == 1 })
        #expect(delivered.all.first?.answer == nil && delivered.all.first?.body == "The session ended")
        withExtendedLifetime(field) {}
    }

    // MARK: - What the shell does with it

    @Test func aNotificationAlwaysTheHistoryWhenItIsOn() {
        let answer = LateAnswer(question: String(repeating: "q", count: 100), answer: "\n  First line.  \nSecond line.")
        #expect(answer.title.count == 60 && answer.title.hasSuffix("…"))
        #expect(answer.actions(historyOn: true) == [
            .notify(title: answer.title, body: "First line.", copies: answer.answer),
            .keepInClipboardHistory("\n  First line.  \nSecond line."),
        ])
        #expect(answer.actions(historyOn: false) == [.notify(title: answer.title, body: "First line.", copies: answer.answer)])
        // Failed: said, nothing to keep or copy.
        let failed = LateAnswer(question: "q", answer: nil, failure: "Signed out")
        #expect(failed.actions(historyOn: true) == [.notify(title: "q", body: "Signed out", copies: nil)])
        // Too long for the history: notified (a click copies it), not kept.
        let long = LateAnswer(question: "q", answer: String(repeating: "x", count: ClipboardHistoryItem.maxLength + 1))
        #expect(long.actions(historyOn: true).count == 1)
    }

    // MARK: - In a field

    final class Settings: @unchecked Sendable {
        var config: Config
        init(_ backend: QuestionBackend) {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.english])
            config.provider = .apple
            config.questionBackend = backend
        }
    }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("late-answer-\(UUID().uuidString)")

    /// A field whose questions go to a Claude Code session (`fake`) or the provider, the shell's snapshot a Slack
    /// channel's (counted), its late answers kept in `delivered`.
    func host(_ backend: QuestionBackend, fake: FakeClaude, delivered: Delivered, snapshots: Locked<[AppSnapshot.Request]>) -> FakeHost {
        let settings = Settings(backend)
        let session = ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder))
        let converter = Converter(loadConfig: { settings.config }, appleModel: StubAppleModel(answer: ["From the provider."]),
                                  claudeSession: session)
        var services = SessionServices(converter: converter, loadSettings: { settings.config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.appSnapshot = { app, request in
            snapshots.withLock { $0.append(request) }
            return {
                AppSnapshot(appName: "Slack", bundleID: SlackAdapter.bundleID, windowTitle: "general - Slack", typed: request.typed,
                            detail: AppDetail(kind: "slack", fields: [AppDetail.Field("channel_id", SlackTree.channel)],
                                              messages: [AppMessage(sender: "Alice", text: "Deploy at 10?", link: SlackTree.permalink(1))]))
            }
        }
        services.lateAnswer = delivered.deliver
        let host = FakeHost(services: services)
        host.app = SlackAdapter.bundleID
        host.focus()
        return host
    }

    func ask(_ host: FakeHost, _ question: String) {
        host.press(FakeHost.at)
        host.type("question")
        host.press(FakeHost.tab)
        host.type(question)
        host.press(FakeHost.enter)
    }

    var isLateAnswer: (TimerID) -> Bool { { if case .lateAnswer = $0 { true } else { false } } }

    /// Waits (blocking, as `FakeHost.settle`) until `condition` holds, 5 s at most.
    func waited(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        return condition()
    }

    @Test func pastTheWaitThePanelGoesAndTheAnswerComesInTheBackground() async throws {
        try await withInterfaceLanguage("en") {
            let (fake, delivered, snapshots) = (FakeClaude(), Delivered(), Locked<[AppSnapshot.Request]>(initialState: []))
            let host = host(.claudeSession, fake: fake, delivered: delivered, snapshots: snapshots)
            ask(host, "what changed")
            #expect(host.settle(timeout: 5) { fake.last?.messages.count == 1 })
            let process = try #require(fake.last)
            let sent = try #require(process.messages.first)
            // The question, then what the user was looking at.
            #expect(sent.hasPrefix("what changed\n\n<context>") && sent.contains(#"<app name="Slack""#) && sent.contains("Deploy at 10?"))
            #expect(sent.contains(SlackTree.permalink(1)) && sent.contains(SlackTree.channel))  // nothing hidden by default
            #expect(snapshots.withLock { $0.first?.typed } == "what changed")
            #expect(host.timerDelays.first { isLateAnswer($0.key) }?.value == LateAnswer.panelWait)
            process.started()
            process.messageStarted()
            process.text("It was")
            #expect(host.settle(timeout: 5) { host.panel != nil && host.composer.result.versions.first?.text == "It was" })
            // The wait is over: the panel says where the answer will come and goes; the draft goes with it.
            host.fireTimers(where: isLateAnswer)
            #expect(host.panel == nil && host.composer.phase == .idle && host.marked.isEmpty && host.document.isEmpty)
            #expect(host.noticeAlone?.contains("in the background") == true, "\(host.noticeAlone ?? "-")")
            // The session goes on (no interrupt) and the answer comes as a notification and in clipboard history.
            process.text(" the deploy at 10:42.\nMore details.")
            process.done()
            #expect(waited { delivered.all.count == 1 })
            #expect(process.interrupts == 0)
            let answer = try #require(delivered.all.first)
            #expect(answer.title == "what changed" && answer.body == "It was the deploy at 10:42.")
            #expect(answer.answer == "It was the deploy at 10:42.\nMore details.")
            #expect(answer.actions(historyOn: true).contains(.keepInClipboardHistory("It was the deploy at 10:42.\nMore details.")))
            // Nothing of it comes back into the field.
            host.settle(timeout: 0.2) { false }
            #expect(host.panel == nil && host.document.isEmpty)
        }
    }

    @Test func doneInTimeItStaysInThePanel() async throws {
        try await withInterfaceLanguage("en") {
            let (fake, delivered, snapshots) = (FakeClaude(), Delivered(), Locked<[AppSnapshot.Request]>(initialState: []))
            let host = host(.claudeSession, fake: fake, delivered: delivered, snapshots: snapshots)
            ask(host, "what changed")
            #expect(host.settle(timeout: 5) { fake.last?.messages.count == 1 })
            let process = try #require(fake.last)
            process.started()
            process.messageStarted()
            process.text("Nothing.")
            process.done()
            #expect(host.settle(timeout: 5) { host.composer.phase == .choosing })
            host.fireTimers(where: isLateAnswer)
            #expect(host.composer.phase == .choosing && host.panel?.rows.map(\.text) == ["Q: what changed", "A: Nothing."],
                    "\(host.panel?.rows.map(\.text) ?? [])")
            Thread.sleep(forTimeInterval: 0.05)
            #expect(delivered.all.isEmpty)
        }
    }

    @Test func escInThePanelStopsItAsBefore() async throws {
        try await withInterfaceLanguage("en") {
            let (fake, delivered, snapshots) = (FakeClaude(), Delivered(), Locked<[AppSnapshot.Request]>(initialState: []))
            let host = host(.claudeSession, fake: fake, delivered: delivered, snapshots: snapshots)
            ask(host, "what changed")
            #expect(host.settle(timeout: 5) { fake.last?.messages.count == 1 })
            let process = try #require(fake.last)
            process.started()
            host.press(FakeHost.escape)
            #expect(waited { process.interrupts == 1 })
            host.fireTimers(where: isLateAnswer)
            process.interrupted()
            Thread.sleep(forTimeInterval: 0.05)
            #expect(delivered.all.isEmpty)
        }
    }

    @Test func leavingTheFieldTheAnswerGoesOn() async throws {
        try await withInterfaceLanguage("en") {
            let (fake, delivered, snapshots) = (FakeClaude(), Delivered(), Locked<[AppSnapshot.Request]>(initialState: []))
            let host = host(.claudeSession, fake: fake, delivered: delivered, snapshots: snapshots)
            ask(host, "what changed")
            #expect(host.settle(timeout: 5) { fake.last?.messages.count == 1 })
            let process = try #require(fake.last)
            process.started()
            host.send(.blur)
            host.send(.close)
            process.messageStarted()
            process.text("Later.")
            process.done()
            #expect(waited { delivered.all.count == 1 })
            #expect(process.interrupts == 0 && delivered.all.first?.answer == "Later.")
        }
    }

    @Test func withTheProviderPickedNothingIsReadOrMoved() async throws {
        try await withInterfaceLanguage("en") {
            let (fake, delivered, snapshots) = (FakeClaude(), Delivered(), Locked<[AppSnapshot.Request]>(initialState: []))
            let host = host(.provider, fake: fake, delivered: delivered, snapshots: snapshots)
            ask(host, "what changed")
            #expect(host.settle(timeout: 5) { host.composer.phase == .choosing })
            #expect(host.composer.result.versions.first?.text == "From the provider.", "\(host.panel?.rows.map(\.text) ?? [])")
            #expect(snapshots.withLock { $0.isEmpty } && fake.processes.isEmpty && !host.timers.contains(where: isLateAnswer))
        }
    }
}
