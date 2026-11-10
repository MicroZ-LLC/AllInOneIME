import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Acceptance at the field's panel boundary: a canned on-device answer, real session keys, and FakeHost's PanelModel.
@Suite("Conversation pinyin", MacTerms())
struct ConversationPinyinTests {
    private final class CannedModel: AppleModelBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["en", "zh"]
        let answer: String

        init(_ answer: String) { self.answer = answer }

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: answer))
                continuation.finish()
            }
        }
    }

    private func field(answer: String) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .apple
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english, .chinese])
        let fixed = config
        let engine = FakeEngine()
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] },
                                                            appleModel: CannedModel(answer)), loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.app = "com.example.editor"
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    private func pick(_ command: String, in host: FakeHost) {
        host.type("@" + command)
        host.press(FakeHost.tab)
    }

    private func switchToChinese(_ host: FakeHost) {
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: 100))
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: 100.1))
        #expect(host.composer.inputLanguage == .chinese)
    }

    @Test func questionKeepsItsFirstRoundWhileTheNextQuestionIsComposed() async throws {
        try await withInterfaceLanguage("en") {
            let host = field(answer: "OK")
            pick("q", in: host)
            host.type("what is rust")
            host.press(FakeHost.enter)
            try #require(host.settle(timeout: 5) { host.composer.canRefine && host.composer.chatRounds.first?.answer == "OK" })
            let before = try #require(host.panel)
            #expect(before.transcript)
            #expect(before.rows.map(\.text) == ["Q: what is rust", "A: OK"])
            #expect(before.highlighted == 1)

            switchToChinese(host)
            host.type("nihao")
            #expect(host.composer.refineIsComposing)
            let composing = try #require(host.panel)
            #expect(composing.transcript)
            #expect(composing.rows == before.rows, "pinyin must not replace the conversation with candidate rows")
            #expect(composing.highlighted == before.highlighted)
            #expect(composing.input?.text == "nihao" && composing.input?.caret == 5)
            #expect(composing.input?.prompt.hasPrefix("question 2/") == true)
            #expect(composing.candidates == "1 你好   2 拟好")
            #expect(composing.candidatesHint == PanelModel.Hint("Space", "picks a word"))
            #expect(composing.footer.contains("ask") && composing.footer.contains("insert"))

            host.press(FakeHost.space)
            let picked = try #require(host.panel)
            #expect(host.composer.refineText == "你好")
            #expect(picked.transcript && picked.rows == before.rows && picked.highlighted == before.highlighted)
            #expect(picked.input?.text == "你好" && picked.candidates == nil && picked.candidatesHint == nil)

            host.press(FakeHost.enter)
            try #require(host.settle(timeout: 5) { host.composer.chatRounds.count == 2 && host.composer.canRefine })
            #expect(host.composer.chatRounds.map(\.question) == ["what is rust", "你好"])
            #expect(host.panel?.transcript == true)
            #expect(host.panel?.rows.map(\.text) == ["Q: what is rust", "A: OK", "Q: 你好", "A: OK"])
        }
    }

    @Test func improveKeepsItsResultsWhileARefineIsComposed() async throws {
        try await withInterfaceLanguage("en") {
            let host = field(answer: "EN: Hello.\nEN: Hi there.")
            pick("i", in: host)
            host.type("helo")
            host.press(FakeHost.enter)
            try #require(host.settle(timeout: 5) { host.composer.canRefine && host.composer.choices.count > 1 })
            let before = try #require(host.panel)
            #expect(before.rows.contains { $0.kind == .translation })

            switchToChinese(host)
            host.type("nihao")
            #expect(host.composer.refineIsComposing)
            let composing = try #require(host.panel)
            #expect(composing.rows == before.rows, "pinyin must not replace the rewrite results with candidate rows")
            #expect(composing.highlighted == before.highlighted)
            #expect(composing.input == PanelModel.Input(prompt: "refine › ", text: "nihao", caret: 5))
            #expect(composing.candidates == "1 你好   2 拟好")
            #expect(composing.candidatesHint == PanelModel.Hint("Space", "picks a word"))
            #expect(composing.footer.contains("refine") && composing.footer.contains("insert"))

            host.press(FakeHost.space)
            let picked = try #require(host.panel)
            #expect(host.composer.refineText == "你好")
            #expect(picked.rows == before.rows && picked.highlighted == before.highlighted)
            #expect(picked.input == PanelModel.Input(prompt: "refine › ", text: "你好", caret: 2))
            #expect(picked.candidates == nil && picked.candidatesHint == nil)
        }
    }
}
