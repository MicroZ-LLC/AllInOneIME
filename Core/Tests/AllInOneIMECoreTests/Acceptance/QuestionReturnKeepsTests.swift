import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Owner decision for 0.7.6 ("keep"): the keys of an @question conversation stay as they are. Written from the
/// decision's text by a separate agent; the implementer doesn't edit it (AGENTS.md rule 11). These pin today's
/// behaviour, through the same InputSession boundary as the macOS host, the AI stubbed (no request leaves the test).
///
/// The spec: in an @question conversation ⏎ never inserts the answer: with a follow-up typed it asks it; with the
/// answer in and nothing typed it does nothing (nothing inserted, panel stays). ⇧⏎ inserts the highlighted answer.
@Suite("QuestionReturnKeeps", .serialized)
struct QuestionReturnKeepsTests {
    private let keypadEnter = KeyEvent(keyCode: VirtualKey.keypadEnter, characters: "\u{3}")

    private func host() -> (FakeHost, String) {
        let endpoint = "question-return-keeps-\(UUID().uuidString.lowercased()).test"
        var config = Config.default
        config.provider = .anthropic
        config.anthropic = ProviderSettings(baseURL: "https://\(endpoint)")
        config.rememberQuestions = false
        config.outputLanguages = [.english]
        config.rewriteStyles = []
        let fixed = config
        let converter = Converter(client: BedrockClient(session: QCStubProtocol.session()),
                                  loadConfig: { fixed }, loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
        var services = SessionServices(converter: converter, loadSettings: { fixed })
        services.loadQuestionHistory = { QuestionHistory() }
        services.recordQuestion = { _ in }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return (host, endpoint)
    }

    /// `@q` picked, `question` asked with ⏎, its answer in.
    private func asked(_ host: FakeHost, _ question: String = "q1") {
        host.press(FakeHost.at)
        host.type("q")
        host.press(FakeHost.tab)
        host.type(question)
        host.press(FakeHost.enter)
        #expect(host.settle { host.composer.phase == .choosing }, "\(host.composer.phase)")
        #expect(host.composer.isQuestionChat, "draft=\(host.composer.draft), rows=\(String(describing: host.panel?.rows.map(\.text)))")
    }

    private func requests(_ endpoint: String) -> Int { QCStubProtocol.bodies(endpoint).count }

    /// "⏎ never inserts the answer: with a follow-up typed it asks it".
    @Test func returnWithAFollowUpTypedAsksItAndInsertsNothing() {
        let (host, endpoint) = host()
        asked(host)
        host.type("q2")
        #expect(host.composer.refineLine == "q2")
        #expect(host.press(FakeHost.enter))
        #expect(host.settle { host.composer.chatRound == 2 && host.composer.phase == .choosing })
        #expect(requests(endpoint) == 2, "the follow-up is asked")
        #expect(host.composer.chatRounds.map(\.question) == ["q1", "q2"])
        #expect(host.document.isEmpty, "no answer goes in: \(host.document)")
        #expect(host.panel != nil && host.composer.isQuestionChat)
    }

    /// "⏎ never inserts the answer": round after round, each follow-up is asked and the field stays empty.
    @Test func returnNeverInsertsHoweverManyFollowUpsAreAsked() {
        let (host, endpoint) = host()
        asked(host)
        for (round, question) in ["q2", "q3"].enumerated() {
            host.type(question)
            #expect(host.press(FakeHost.enter))
            #expect(host.settle { host.composer.chatRound == round + 2 && host.composer.phase == .choosing }, "round \(round + 2)")
            #expect(host.document.isEmpty && host.panel != nil, "round \(round + 2): \(host.document)")
        }
        #expect(requests(endpoint) == 3)
        #expect(host.composer.chatRounds.map(\.question) == ["q1", "q2", "q3"])
    }

    /// "with the answer in and nothing typed it does nothing (nothing inserted, panel stays)": pressed again and again,
    /// after the first answer and after a follow-up's; no request either.
    @Test func returnWithTheAnswerInAndNothingTypedDoesNothing() {
        let (host, endpoint) = host()
        asked(host)
        let rows = host.panel?.rows.map(\.text)
        for _ in 0..<3 { #expect(host.press(FakeHost.enter), "⏎ is the panel's, never the app's") }
        #expect(requests(endpoint) == 1, "nothing is asked")
        #expect(host.document.isEmpty, "nothing inserted: \(host.document)")
        #expect(host.panel != nil && host.panel?.rows.map(\.text) == rows, "the panel stays as it was")
        #expect(host.composer.isQuestionChat && host.composer.chatRound == 1 && host.composer.phase == .choosing)

        host.type("q2")
        host.press(FakeHost.enter)
        #expect(host.settle { host.composer.chatRound == 2 && host.composer.phase == .choosing })
        #expect(host.press(FakeHost.enter))
        #expect(requests(endpoint) == 2 && host.document.isEmpty && host.panel != nil)
        #expect(host.composer.isQuestionChat && host.composer.chatRound == 2)
    }

    /// "⏎ never inserts the answer … with the answer in and nothing typed it does nothing": the keypad's Enter is ⏎.
    @Test func keypadEnterWithNothingTypedDoesNothingEither() {
        let (host, endpoint) = host()
        asked(host)
        #expect(host.press(keypadEnter))
        #expect(requests(endpoint) == 1 && host.document.isEmpty && host.panel != nil)
        #expect(host.composer.isQuestionChat && host.composer.chatRound == 1)
    }

    /// "⇧⏎ inserts the highlighted answer."
    @Test func shiftReturnInsertsTheHighlightedAnswer() {
        let (host, endpoint) = host()
        asked(host)
        #expect(host.composer.chatRounds.first?.answer == "Answer: q1")
        #expect(host.press(acceptanceShiftReturn))
        #expect(requests(endpoint) == 1, "nothing more is asked")
        #expect(host.document == "Answer: q1", "\(host.document)")
        #expect(host.panel == nil && !host.composer.isQuestionChat)
    }

    /// "⇧⏎ inserts the highlighted answer": with a follow-up half typed it is the answer that goes in, never the line,
    /// and the line isn't asked.
    @Test func shiftReturnWithAFollowUpTypedInsertsTheAnswerNotTheLine() {
        let (host, endpoint) = host()
        asked(host)
        host.type("half typed")
        #expect(host.press(acceptanceShiftReturn))
        #expect(requests(endpoint) == 1, "the line isn't asked")
        #expect(host.document == "Answer: q1" && host.panel == nil, "\(host.document)")
    }

    /// "⇧⏎ inserts the highlighted answer": after a follow-up, the answer highlighted is the one that goes in, and only
    /// after ⏎ did nothing.
    @Test func shiftReturnAfterAFollowUpInsertsTheAnswerHighlightedThen() throws {
        let (host, endpoint) = host()
        asked(host)
        host.type("q2")
        host.press(FakeHost.enter)
        #expect(host.settle { host.composer.chatRound == 2 && host.composer.phase == .choosing })
        #expect(host.press(FakeHost.enter))
        #expect(host.document.isEmpty && host.panel != nil, "⏎ did nothing: \(host.document)")
        let highlighted = try #require(host.composer.choices.indices.contains(host.composer.highlighted)
                                       ? host.composer.choices[host.composer.highlighted].text : nil)
        #expect(highlighted == "Answer: q2", "the newest answer is the one highlighted: \(highlighted)")
        #expect(host.press(acceptanceShiftReturn))
        #expect(requests(endpoint) == 2)
        #expect(host.document == highlighted && host.panel == nil, "\(host.document)")
    }
}
