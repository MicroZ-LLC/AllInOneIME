import Foundation
import Testing
@testable import AllInOneIMECore

/// Stands in for the on-device model: records the requests, answers with the snapshots given (each the whole answer
/// so far), then fails with `error`, or never finishes (`hangs`).
final class StubAppleModel: AppleModelBackend, @unchecked Sendable {
    let availability: AppleModelAvailability
    let contextSize: Int
    let snapshots: [AppleModelSnapshot]
    let error: Error?
    let hangs: Bool
    private let lock = NSLock()
    private var _requests: [AppleModelRequest] = []
    var requests: [AppleModelRequest] { lock.withLock { _requests } }

    init(_ availability: AppleModelAvailability = .available, contextSize: Int = 4096, answer: [String] = [],
         outputTokens: Int? = nil, error: Error? = nil, hangs: Bool = false) {
        self.availability = availability
        self.contextSize = contextSize
        snapshots = answer.map { AppleModelSnapshot(text: $0, outputTokens: outputTokens) }
        self.error = error
        self.hangs = hangs
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        lock.withLock { _requests.append(request) }
        let (snapshots, error, hangs) = (snapshots, error, hangs)
        return AsyncThrowingStream { continuation in
            let task = Task {
                for snapshot in snapshots { continuation.yield(snapshot) }
                if hangs {
                    try? await Task.sleep(for: .seconds(30))
                    return
                }
                if let error { continuation.finish(throwing: error) } else { continuation.finish() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct AppleModelTests {
    var config: Config {
        var config = Config.default
        config.provider = .apple
        config.setOrder([OutputLanguage.english])
        return config
    }

    func converter(_ stub: StubAppleModel, _ config: Config? = nil) -> Converter {
        let config = config ?? self.config
        return Converter(loadConfig: { config }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                         loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: stub)
    }

    func final(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> ConversionUpdate? {
        var last: ConversionUpdate?
        for try await update in stream { last = update }
        return last
    }

    // MARK: Availability

    @Test func offeredOnMacOS26AndLater() {
        #expect(!Provider.offered(apple: .unsupportedSystem).contains(.apple))
        for reason in [AppleModelAvailability.available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady] {
            #expect(Provider.offered(apple: reason).last == .apple, "listed (greyed out when not available): \(reason)")
        }
        // The others as before.
        #expect(Array(Provider.offered(apple: .available).prefix(4)) == [.bedrock, .anthropic, .gemini, .openai])
    }

    @Test func notAvailableSaysWhyAndSendsNothing() async {
        for reason in [AppleModelAvailability.unsupportedSystem, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady] {
            let stub = StubAppleModel(reason, answer: ["EN: Hi."])
            await #expect(throws: AppleModelError.unavailable(reason)) {
                _ = try await final(converter(stub).convert("你好"))
            }
            #expect(stub.requests.isEmpty)
            #expect(AppleModelError.unavailable(reason).errorDescription?.isEmpty == false)
        }
        #expect(AppleModelError.unavailable(.appleIntelligenceNotEnabled).errorDescription?
            .contains("System Settings → Apple Intelligence & Siri") == true)
        #expect(AppleModel.settingsURL.absoluteString == "x-apple.systempreferences:com.apple.Siri-Settings.extension")
    }

    @Test func unsupportedSystemStandIn() async {
        let backend = UnsupportedBackend()
        #expect(backend.availability == .unsupportedSystem && !backend.availability.isOffered)
        await #expect(throws: AppleModelError.unavailable(.unsupportedSystem)) {
            for try await _ in backend.respond(to: AppleModel.request(from: Prompt.commandRequest(.question, input: "hi", config: config),
                                                                       maxTokens: 100, contextSize: 4096)) {}
        }
    }

    // MARK: Config

    @Test func configRoundTrip() throws {
        let data = try JSONEncoder().encode(config)
        #expect(String(decoding: data, as: UTF8.self).contains(#""provider":"apple""#))
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
        let written = try JSONDecoder().decode(Config.self, from: Data(#"{"provider": "apple"}"#.utf8))
        #expect(written.provider == .apple)
        #expect(written.settings(for: .apple).model == AppleModel.modelName)
        #expect(written.activeModel == "apple:" + AppleModel.modelName)
        #expect(Provider.apple.keyVariables.isEmpty && Provider.apple.displayName == "Apple Intelligence (on this Mac)")
    }

    @Test func issueReportSaysApple() {
        let d = IssueReport.Diagnostics(config: config, macOS: "26.1", architecture: "arm64", interfaceLanguage: "en",
                                        languagePacks: [], plugins: 0, extensions: 0)
        #expect(d.provider == "apple" && d.model == nil)
        #expect(IssueReport(title: "x", diagnostics: d).lines.contains("AI provider: apple"))
    }

    // MARK: Requests

    @Test func requestFromThePrompt() {
        var config = self.config
        config.temperature = 0.4
        let body = Prompt.request(for: "我今天有点不舒服", mode: .improve, config: config)
        let request = AppleModel.request(from: body, maxTokens: 1000, contextSize: 4096)
        // The same instructions as the other providers; the few-shot turns as the transcript, the sentence as the prompt.
        var bedrock = config
        bedrock.provider = .bedrock
        #expect(request.instructions == Prompt.request(for: "我今天有点不舒服", mode: .improve, config: bedrock).system[0].text)
        #expect(request.prompt == "我今天有点不舒服")
        #expect(request.examples.map(\.prompt) == stride(from: 0, to: body.messages.count - 1, by: 2).map { body.messages[$0].content[0].text })
        #expect(request.examples.map(\.response) == stride(from: 1, to: body.messages.count - 1, by: 2).map { body.messages[$0].content[0].text })
        #expect(request.examples.first?.response.hasPrefix("ZH: ") == true)
        #expect(request.temperature == 0.4 && request.maximumResponseTokens == 1000)
    }

    @Test func examplesInTheSentencesOwnLanguageAndLines() {
        // A Chinese sentence: only the Chinese examples; an English one: only the English ones. Other providers get all.
        let chinese = Prompt.request(for: "我今天有点不舒服", mode: .both, config: config)
        let english = Prompt.request(for: "i want go home tomorow", mode: .both, config: config)
        let inputs = { (body: ConverseRequest) in stride(from: 0, to: body.messages.count - 1, by: 2).map { body.messages[$0].content[0].text } }
        #expect(!inputs(chinese).isEmpty && inputs(chinese).allSatisfy { $0.containsHan })
        #expect(!inputs(english).isEmpty && inputs(english).allSatisfy { !$0.containsHan })
        var bedrock = config
        bedrock.provider = .bedrock
        #expect(inputs(Prompt.request(for: "我今天有点不舒服", mode: .both, config: bedrock)).count == Prompt.examples.count)
        #expect(chinese.system == Prompt.request(for: "我今天有点不舒服", mode: .both, config: bedrock).system)
    }

    @Test func examplesLeftOutToFitTheContext() {
        let body = Prompt.request(for: "我今天有点不舒服", mode: .both, config: config)
        let all = AppleModel.request(from: body, maxTokens: 1000, contextSize: 4096)
        let small = AppleModel.request(from: body, maxTokens: 1000, contextSize: 1600)
        #expect(!small.examples.isEmpty && small.examples.count < all.examples.count)
        #expect(Array(all.examples.suffix(small.examples.count)) == small.examples, "the first ones go")
        #expect(small.maximumResponseTokens >= AppleModel.minimumAnswer && small.maximumResponseTokens <= 1000)
        // Too long even alone: sent without examples (the model says if it doesn't fit), the answer at its minimum.
        let long = Prompt.request(for: String(repeating: "这是一段很长的文字。", count: 600), mode: .both, config: config)
        let tight = AppleModel.request(from: long, maxTokens: 1000, contextSize: 4096)
        #expect(tight.examples.isEmpty && tight.maximumResponseTokens == AppleModel.minimumAnswer)
    }

    @Test func commandRequest() {
        let request = AppleModel.request(from: Prompt.commandRequest(.question, input: "光速是多少", config: config),
                                         maxTokens: 1000, contextSize: 4096)
        #expect(request.examples.isEmpty && request.prompt == "光速是多少")
        #expect(request.instructions == Prompt.commandSystem(.question))
        #expect(request.temperature == Config.default.temperature)
    }

    // MARK: Streaming

    @Test func streamsIntoTheParser() async throws {
        let answer = "ZH: 我今天有点不舒服。\nZH: 今天我身体有点不适。\nZH: 我今天感觉不太舒服。\nSTYLE_CONCISE: 今天不太舒服。"
        let stub = StubAppleModel(answer: [String(answer.prefix(8)), String(answer.prefix(30)), answer])
        var config = self.config
        config.rewriteStyles = ["简洁"]
        let update = try #require(try await final(converter(stub, config).convert("wo jintian youdian bushufu 我今天有点不舒服", mode: .improve)))
        #expect(update.isFinal && update.rawText == answer)
        #expect(update.result.versions.map(\.text) == ["我今天有点不舒服。", "今天我身体有点不适。", "我今天感觉不太舒服。"])
        #expect(update.result.rewrite("简洁")?.text == "今天不太舒服。")
        #expect(stub.requests.count == 1)
    }

    @Test func cutOffAtTheLimitDropsTheLastLine() async throws {
        let stub = StubAppleModel(answer: ["EN: Hello there.\nEN: Hi there.\nEN: Hey th"], outputTokens: 1000)
        let update = try #require(try await final(converter(stub).convert("你好")))
        #expect(update.result.versions.map(\.text) == ["Hello there.", "Hi there."])
    }

    @Test func eventsAreDeltas() async throws {
        let stub = StubAppleModel(answer: ["EN: A", "EN: AB", "EN: ABC"])
        var events: [BedrockStreamEvent] = []
        for try await event in AppleModel.stream(Prompt.commandRequest(.question, input: "q", config: config), backend: stub,
                                                 maxTokens: 100, timeout: 5) {
            events.append(event)
        }
        #expect(events == [.textDelta("EN: A"), .textDelta("B"), .textDelta("C"), .messageStop(reason: "end_turn")])
    }

    @Test func timesOutWhenNothingArrives() async {
        var config = self.config
        config.timeoutSeconds = 0.3
        let started = Date()
        await #expect(throws: AppleModelError.timedOut(0.3)) {
            _ = try await final(converter(StubAppleModel(answer: ["EN: Hel"], hangs: true), config).convert("你好"))
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func errorsComeThroughWithClearMessages() async {
        for error in [AppleModelError.contextExceeded, .unsupportedLanguage, .busy] {
            await #expect(throws: error) {
                _ = try await final(converter(StubAppleModel(error: error)).convert("안녕하세요"))
            }
        }
        #expect(AppleModelError.contextExceeded.errorDescription?.contains("Too long") == true)
        #expect(AppleModelError.unsupportedLanguage.errorDescription?.contains("language") == true)
        await #expect(throws: ProviderError.refused(.apple)) {
            _ = try await final(converter(StubAppleModel(error: ProviderError.refused(.apple))).generate(.question, input: "x"))
        }
    }

    @Test func questionAnswerAsOneVersion() async throws {
        let stub = StubAppleModel(answer: ["Canberra", "Canberra is the capital."])
        let update = try #require(try await final(converter(stub).generate(.question, input: "capital of australia")))
        #expect(update.result.versions.map(\.text) == ["Canberra is the capital."])
        #expect(stub.requests.first?.instructions == Prompt.commandSystem(.question))
    }
}
