import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Typing while an @question's FIRST answer is still coming in, with Chinese (pinyin) input: what is typed starts the
/// follow-up line ("question 2 ›"), as it does from round 2 on. Pinyin composes on that line and Space picks its first
/// candidate there; the answer goes on and is not asked again; the first question stays as it was asked; nothing goes
/// into the field. Once the answer is in, the line typed meanwhile is still there and ⏎ asks it as round 2. ⏎ before
/// that neither stops the answer nor inserts anything: the question waits. Esc closes the panel and leaves nothing in
/// the field. The footer says the next question can be typed meanwhile.
///
/// Through a field's session (`FakeHost`), typed as the user types it. The AI is a stand-in for the on-device model
/// whose answer comes in two parts: the first at once, the rest when the test lets it (`finish`), so the first answer is
/// still streaming for as long as the test types, however slow the machine. What it was asked is kept.
extension OneAtAcceptanceTests {
    /// The on-device model, answering in two parts: "… part" at once, "… part and the rest." once `finish` was called
    /// for that request (or `patience` seconds went by, so a test that fails never hangs).
    final class HeldModel: AppleModelBackend, @unchecked Sendable {
        static let patience: TimeInterval = 30

        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["de", "en", "es", "fr", "ja", "ko", "zh"]
        private let asked = Locked<[AppleModelRequest]>(initialState: [])
        private let finished = Locked<Int>(initialState: 0)

        var requests: [AppleModelRequest] { asked.withLock { $0 } }

        static func part(_ number: Int) -> String { "Answer \(number) part" }
        static func whole(_ number: Int) -> String { "Answer \(number) part and the rest." }

        /// Lets the answers of the first `count` requests end.
        func finish(_ count: Int) { finished.withLock { $0 = max($0, count) } }

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            let number = asked.withLock { requests -> Int in
                requests.append(request)
                return requests.count
            }
            let finished = finished
            return AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: Self.part(number)))
                Task {
                    let deadline = Date().addingTimeInterval(Self.patience)
                    while finished.withLock({ $0 }) < number, Date() < deadline {
                        try? await Task.sleep(nanoseconds: 20_000_000)
                    }
                    continuation.yield(AppleModelSnapshot(text: Self.whole(number)))
                    continuation.finish()
                }
            }
        }
    }

    /// A field with Chinese input where "@你吃饭了吗" was asked and its first answer is still coming in.
    final class StreamingFirstAnswer {
        static let question = "你吃饭了吗"

        let host: FakeHost
        let model = HeldModel()

        var composer: Composer { host.composer }
        var rounds: [QuestionChat.Round] { composer.chatRounds }
        /// The follow-up line as the panel shows it, the pinyin's spaces left out ("" when none is started).
        var line: String { (composer.refineLine ?? "").filter { $0 != " " } }
        var footer: String { host.panel?.footer ?? "" }
        /// The first answer is still coming in: its first part shown, the rest not yet.
        var firstAnswerIsStreaming: Bool {
            composer.isQuestionChat && rounds.count == 1 && rounds[0].answer == HeldModel.part(1) && !composer.canRefine
        }
        /// What the field holds: its text and what is marked in it.
        var inField: String { host.document + host.marked }
        /// What the field showed as marked text (the question's line) when the first answer started.
        private(set) var questionLine = ""
        /// Nothing was inserted into the field, and what it shows of the question is as it was when the answer started.
        var nothingInsertedAndTheQuestionLineUnchanged: Bool { host.document.isEmpty && host.marked == questionLine }

        init(session: Bool) {
            let fixed = World().config
            let engine = FakeEngine()
            engine.dictionary.merge(Suite.pinyin) { $1 }
            var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
                                           loadSettings: { fixed })
            services.levelOne = { .engine(engine) }
            host = FakeHost(services: services)
            host.focus()
            host.composer.questionSession = session
            host.type("@")
            host.type("nichifanlema")
            host.press(FakeHost.space)
            host.press(FakeHost.enter)
        }

        /// The first part of the first answer is shown (false: it wasn't within ten seconds).
        func waitForFirstPart() -> Bool {
            let started = host.settle(timeout: 10) { !model.requests.isEmpty && rounds.first?.answer == HeldModel.part(1) }
            questionLine = host.marked
            return started
        }

        /// Lets the first answer end, and waits until it is all in (false: it wasn't within ten seconds).
        func firstAnswerComesIn() -> Bool {
            model.finish(1)
            return host.settle(timeout: 10) { composer.canRefine && rounds.first?.answer == HeldModel.whole(1) }
        }
    }

    // MARK: - 1. Letters start the follow-up line

    @Test(arguments: [false, true])
    func lettersTypedWhileTheFirstAnswerStreamsComposeOnTheFollowUpLine(session: Bool) async throws {
        try await inEnglish {
            let chat = StreamingFirstAnswer(session: session)
            try #require(chat.waitForFirstPart(), "the first answer never started")
            try #require(chat.firstAnswerIsStreaming)

            chat.host.type("nihao")
            // The pinyin is on the follow-up line, composing.
            #expect(chat.composer.refineIsComposing, "the pinyin isn't composed on the follow-up line")
            #expect(chat.line == "nihao", "the follow-up line: \(chat.composer.refineLine ?? "nil")")
            // The question is as it was asked, its answer still coming in: no draft back, nothing appended.
            #expect(chat.composer.isQuestionChat, "the conversation is gone: phase \(chat.composer.phase), draft \(chat.composer.draft)")
            #expect(chat.rounds.map(\.question) == [StreamingFirstAnswer.question], "rounds: \(chat.rounds)")
            #expect(chat.firstAnswerIsStreaming, "the first answer no longer streams: phase \(chat.composer.phase)")
            #expect(chat.nothingInsertedAndTheQuestionLineUnchanged, "in the field: \(chat.host.document), marked: \(chat.host.marked)")
            #expect(chat.model.requests.count == 1)

            // The answer wasn't cancelled: the rest of it comes in, for the question as asked, and nothing was asked again.
            #expect(chat.firstAnswerComesIn(), "the rest of the first answer never came: phase \(chat.composer.phase), rounds \(chat.rounds)")
            #expect(chat.rounds == [QuestionChat.Round(question: StreamingFirstAnswer.question, answer: HeldModel.whole(1))])
            #expect(chat.model.requests.count == 1)
            #expect(chat.line == "nihao", "the pinyin typed meanwhile: \(chat.composer.refineLine ?? "nil")")
            #expect(chat.nothingInsertedAndTheQuestionLineUnchanged, "in the field: \(chat.host.document), marked: \(chat.host.marked)")
        }
    }

    // MARK: - 2. Space picks the first candidate into the line

    @Test(arguments: [false, true])
    func spaceWhileTheFirstAnswerStreamsPicksTheFirstCandidateIntoTheFollowUpLine(session: Bool) async throws {
        try await inEnglish {
            let chat = StreamingFirstAnswer(session: session)
            try #require(chat.waitForFirstPart(), "the first answer never started")

            chat.host.type("nihao")
            chat.host.press(FakeHost.space)
            #expect(chat.line == "你好", "the follow-up line: \(chat.composer.refineLine ?? "nil")")
            #expect(!chat.composer.engineState.isComposing)
            // Nothing went into the field, and the question wasn't touched ("你吃饭了吗你好").
            #expect(chat.nothingInsertedAndTheQuestionLineUnchanged, "in the field: \(chat.host.document), marked: \(chat.host.marked)")
            #expect(chat.rounds.map(\.question) == [StreamingFirstAnswer.question], "rounds: \(chat.rounds), draft: \(chat.composer.draft)")
            #expect(chat.firstAnswerIsStreaming, "the first answer no longer streams: phase \(chat.composer.phase)")
            #expect(chat.model.requests.count == 1)
        }
    }

    // MARK: - 3. The line is still there when the answer is in, and ⏎ asks it

    @Test(arguments: [false, true])
    func theFollowUpTypedMeanwhileIsAskedByReturnOnceTheFirstAnswerIsIn(session: Bool) async throws {
        try await inEnglish {
            let chat = StreamingFirstAnswer(session: session)
            try #require(chat.waitForFirstPart(), "the first answer never started")
            chat.host.type("nihao")
            chat.host.press(FakeHost.space)

            #expect(chat.firstAnswerComesIn(), "the rest of the first answer never came: phase \(chat.composer.phase), rounds \(chat.rounds)")
            #expect(chat.line == "你好", "the follow-up line once the answer is in: \(chat.composer.refineLine ?? "nil")")
            #expect(chat.rounds == [QuestionChat.Round(question: StreamingFirstAnswer.question, answer: HeldModel.whole(1))])
            #expect(chat.model.requests.count == 1)

            // ⏎: round 2, a second request with that question.
            chat.host.press(FakeHost.enter)
            #expect(chat.host.settle(timeout: 10) { chat.model.requests.count == 2 }, "⏎ asked nothing: \(chat.model.requests.count) request(s)")
            #expect(chat.model.requests.count == 2)
            #expect(chat.model.requests.last?.prompt.contains("你好") == true, "asked: \(chat.model.requests.last?.prompt ?? "nil")")
            chat.model.finish(2)
            #expect(chat.host.settle(timeout: 10) { chat.composer.canRefine && chat.rounds.count == 2 }, "rounds: \(chat.rounds)")
            #expect(chat.rounds == [QuestionChat.Round(question: StreamingFirstAnswer.question, answer: HeldModel.whole(1)),
                                    QuestionChat.Round(question: "你好", answer: HeldModel.whole(2))])
            #expect(chat.nothingInsertedAndTheQuestionLineUnchanged, "in the field: \(chat.host.document), marked: \(chat.host.marked)")
        }
    }

    // MARK: - 4. ⏎ while the answer streams: the question waits

    @Test(arguments: [false, true])
    func returnWhileTheFirstAnswerStreamsKeepsTheAnswerAndTheFollowUpWaits(session: Bool) async throws {
        try await inEnglish {
            let chat = StreamingFirstAnswer(session: session)
            try #require(chat.waitForFirstPart(), "the first answer never started")
            chat.host.type("nihao")
            chat.host.press(FakeHost.space)

            chat.host.press(FakeHost.enter)
            // Nothing inserted, the answer not stopped, nothing asked yet: the question waits on its line.
            #expect(chat.nothingInsertedAndTheQuestionLineUnchanged, "in the field: \(chat.host.document), marked: \(chat.host.marked)")
            #expect(chat.host.panel != nil, "the panel closed")
            #expect(chat.firstAnswerIsStreaming, "the first answer no longer streams: phase \(chat.composer.phase), rounds \(chat.rounds)")
            #expect(chat.line == "你好", "the follow-up line: \(chat.composer.refineLine ?? "nil")")
            #expect(chat.model.requests.count == 1)

            #expect(chat.firstAnswerComesIn(), "the rest of the first answer never came: phase \(chat.composer.phase), rounds \(chat.rounds)")
            #expect(chat.rounds == [QuestionChat.Round(question: StreamingFirstAnswer.question, answer: HeldModel.whole(1))])
            #expect(chat.line == "你好", "the follow-up line once the answer is in: \(chat.composer.refineLine ?? "nil")")
            #expect(chat.nothingInsertedAndTheQuestionLineUnchanged, "in the field: \(chat.host.document), marked: \(chat.host.marked)")

            // ⏎ now asks it.
            chat.host.press(FakeHost.enter)
            #expect(chat.host.settle(timeout: 10) { chat.model.requests.count == 2 }, "⏎ asked nothing: \(chat.model.requests.count) request(s)")
            #expect(chat.model.requests.last?.prompt.contains("你好") == true, "asked: \(chat.model.requests.last?.prompt ?? "nil")")
            #expect(chat.host.settle(timeout: 10) { chat.rounds.count == 2 }, "rounds: \(chat.rounds)")
            #expect(chat.rounds.map(\.question) == [StreamingFirstAnswer.question, "你好"])
            #expect(chat.nothingInsertedAndTheQuestionLineUnchanged, "in the field: \(chat.host.document), marked: \(chat.host.marked)")
        }
    }

    // MARK: - 5. Esc closes, nothing left in the field

    /// What was typed on the follow-up line before Esc: nothing, pinyin still composing, a question picked.
    enum FollowUpTyped: String, CaseIterable, Sendable {
        case nothing, pinyin, picked
    }

    @Test(arguments: [false, true], FollowUpTyped.allCases)
    func escWhileTheFirstAnswerStreamsClosesAndLeavesNothingInTheField(session: Bool, typed: FollowUpTyped) async throws {
        try await inEnglish {
            let chat = StreamingFirstAnswer(session: session)
            try #require(chat.waitForFirstPart(), "the first answer never started")
            if typed != .nothing { chat.host.type("nihao") }
            if typed == .picked { chat.host.press(FakeHost.space) }

            chat.host.press(FakeHost.escape)
            #expect(chat.host.panel == nil, "the panel is still up: \(chat.host.panel?.rows.map(\.text) ?? [])")
            #expect(!chat.composer.isQuestionChat && chat.composer.phase == .idle, "phase \(chat.composer.phase), draft \(chat.composer.draft)")
            #expect(chat.inField.isEmpty, "in the field: \(chat.inField)")
            // And nothing arrives later: the rest of the answer, had it gone on, changes nothing.
            chat.model.finish(1)
            chat.host.settle(timeout: 0.5) { false }
            #expect(chat.host.panel == nil && chat.inField.isEmpty, "in the field: \(chat.inField)")
            #expect(chat.model.requests.count == 1)
        }
    }

    // MARK: - 6. The footer

    @Test(arguments: [false, true])
    func theFooterWhileTheFirstAnswerStreamsSaysTheNextQuestionCanBeTyped(session: Bool) async throws {
        try await inEnglish {
            let chat = StreamingFirstAnswer(session: session)
            try #require(chat.waitForFirstPart(), "the first answer never started")
            try #require(chat.firstAnswerIsStreaming)
            #expect(chat.footer.contains("type the next question meanwhile"), "the footer: \(chat.footer)")

            // Still so with a follow-up on its line.
            chat.host.type("nihao")
            chat.host.press(FakeHost.space)
            #expect(chat.footer.contains("type the next question meanwhile"), "the footer with a follow-up typed: \(chat.footer)")
        }
    }
}
