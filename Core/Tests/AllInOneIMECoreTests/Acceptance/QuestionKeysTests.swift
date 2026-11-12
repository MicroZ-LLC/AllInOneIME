import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The owner's 0.7.3 key rule, driven through the same InputSession boundary as the macOS host.
@Suite("QuestionKeys", .serialized)
struct QuestionKeysTests {
    private func host() -> (FakeHost, String) {
        let endpoint = "question-keys-\(UUID().uuidString.lowercased()).test"
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

    private func answered(_ host: FakeHost, command: String = "q", input: String = "q1") {
        host.press(FakeHost.at)
        host.type(command)
        host.press(FakeHost.tab)
        host.type(input)
        host.press(FakeHost.enter)
        #expect(host.settle { host.composer.phase == .choosing }, "\(host.composer.phase)")
        #expect(host.composer.isQuestionChat == (command == "q"), "draft=\(host.composer.draft), command=\(String(describing: host.composer.activeCommand)), rows=\(String(describing: host.panel?.rows.map(\.text)))")
    }

    private func requests(_ endpoint: String) -> Int { QCStubProtocol.bodies(endpoint).count }

    @Test func returnWithFollowUpStartsRoundTwoWithoutInserting() {
        let (host, endpoint) = host()
        answered(host)
        host.type("q2")
        #expect(host.composer.refineLine == "q2")
        host.press(FakeHost.enter)
        #expect(host.settle { host.composer.chatRound == 2 && host.composer.phase == .choosing })
        #expect(requests(endpoint) == 2)
        #expect(host.composer.chatRounds.map(\.question) == ["q1", "q2"])
        #expect(host.document.isEmpty && host.panel != nil)
    }

    @Test func returnWithNothingTypedKeepsAnswerPanelAndInsertsNothing() {
        let (host, endpoint) = host()
        answered(host)
        host.press(FakeHost.enter)
        #expect(requests(endpoint) == 1)
        #expect(host.document.isEmpty && host.panel != nil)
        #expect(host.composer.isQuestionChat && host.composer.chatRound == 1)
    }

    @Test func shiftReturnInsertsHighlightedAnswer() {
        let (host, endpoint) = host()
        answered(host)
        host.press(acceptanceShiftReturn)
        #expect(requests(endpoint) == 1)
        #expect(host.document == "Answer: q1" && host.panel == nil)
    }

    @Test func shiftReturnDropsHalfTypedFollowUpAndInsertsHighlightedAnswer() {
        let (host, endpoint) = host()
        answered(host)
        host.type("half typed")
        host.press(acceptanceShiftReturn)
        #expect(requests(endpoint) == 1)
        #expect(host.document == "Answer: q1" && host.panel == nil)
        #expect(!host.document.contains("half typed"))
    }

    @Test func clickingAnAnswerRowInsertsThatAnswer() throws {
        let (host, endpoint) = host()
        answered(host)
        #expect(host.composer.chatRounds.first?.answer == "Answer: q1")
        let rows = try #require(host.panel?.rows)
        let row = try #require(rows.firstIndex { $0.choice != nil }, "rows=\(rows.map(\.text))")
        host.send(.pick(row))
        #expect(requests(endpoint) == 1)
        #expect(host.document == "Answer: q1" && host.panel == nil)
    }

    @Test func improveKeepsReturnInsertAndShiftReturnRefine() {
        let (insert, insertEndpoint) = host()
        QCStubProtocol.enqueue(insertEndpoint, .answer("EN: Improved sentence."))
        answered(insert, command: "i", input: "bad sentence")
        insert.press(FakeHost.enter)
        #expect(requests(insertEndpoint) == 1 && insert.document == "Improved sentence.")

        let (refine, refineEndpoint) = host()
        QCStubProtocol.enqueue(refineEndpoint, .answer("EN: Improved sentence."), .answer("EN: Short."))
        answered(refine, command: "i", input: "bad sentence")
        refine.type("shorter")
        refine.press(acceptanceShiftReturn)
        #expect(refine.settle { requests(refineEndpoint) == 2 && refine.composer.phase == .choosing })
        #expect(refine.document.isEmpty && refine.composer.refineHistory == ["shorter"])
    }
}
