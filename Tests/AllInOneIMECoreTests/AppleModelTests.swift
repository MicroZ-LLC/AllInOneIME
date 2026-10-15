import Foundation
import Testing
@testable import AllInOneIMECore

/// Stands in for the on-device model: records the requests, answers with the snapshots given (each the whole answer
/// so far), then fails with `error`, or never finishes (`hangs`).
final class StubAppleModel: AppleModelBackend, @unchecked Sendable {
    let availability: AppleModelAvailability
    let contextSize: Int
    let supportedLanguages: Set<String>
    let snapshots: [AppleModelSnapshot]
    let error: Error?
    let hangs: Bool
    private let lock = NSLock()
    private var _requests: [AppleModelRequest] = []
    var requests: [AppleModelRequest] { lock.withLock { _requests } }

    /// The languages macOS 27.2's model lists.
    static let languages: Set<String> = ["da", "de", "en", "es", "fr", "it", "ja", "ko", "nb", "nl", "pt", "sv", "tr", "vi", "zh"]

    init(_ availability: AppleModelAvailability = .available, contextSize: Int = 4096, languages: Set<String> = StubAppleModel.languages,
         answer: [String] = [], outputTokens: Int? = nil, error: Error? = nil, hangs: Bool = false) {
        self.availability = availability
        self.contextSize = contextSize
        supportedLanguages = languages
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

    // MARK: Fixes after the acceptance tests

    func events(_ stub: StubAppleModel, maxTokens: Int = 100) async throws -> [BedrockStreamEvent] {
        var events: [BedrockStreamEvent] = []
        for try await event in AppleModel.stream(Prompt.commandRequest(.question, input: "q", config: config), backend: stub,
                                                 maxTokens: maxTokens, timeout: 5) {
            events.append(event)
        }
        return events
    }

    func joined(_ events: [BedrockStreamEvent]) -> String {
        events.reduce(into: "") { text, event in
            if case let .textDelta(delta) = event { text += delta }
            if case let .textReplaced(whole) = event { text = whole }
        }
    }

    @Test func snapshotsEndingInsideACharacter() async throws {
        // A skin tone added to 👍; a family emoji built up scalar by scalar.
        let thumbs = try await events(StubAppleModel(answer: ["ok 👍", "ok 👍🏽"]))
        #expect(thumbs == [.textDelta("ok 👍"), .textDelta("\u{1F3FD}"), .messageStop(reason: "end_turn")])
        #expect(joined(thumbs) == "ok 👍🏽" && joined(thumbs).unicodeScalars.count == "ok 👍🏽".unicodeScalars.count)
        let family = "EN: 👨‍👩‍👧 home"
        let growing = family.unicodeScalars.indices.map { String(family.unicodeScalars[...$0]) }
        let built = try await events(StubAppleModel(answer: growing))
        #expect(joined(built) == family && joined(built).unicodeScalars.elementsEqual(family.unicodeScalars))
        #expect(!built.contains { if case .textReplaced = $0 { return true } else { return false } })
        // Through the converter: the final text is the model's.
        let update = try #require(try await final(converter(StubAppleModel(answer: growing)).generate(.question, input: "x")))
        #expect(update.rawText == family)
    }

    @Test func aRevisedAnswerReplacesWhatWentOut() async throws {
        let revised = try await events(StubAppleModel(answer: ["EN: Hello", "EN: Hi there", "EN: Hi there."]))
        #expect(revised == [.textDelta("EN: Hello"), .textReplaced("EN: Hi there"), .textDelta("."), .messageStop(reason: "end_turn")])
        let update = try #require(try await final(converter(StubAppleModel(answer: ["EN: Hello", "EN: Hi there."])).convert("你好")))
        #expect(update.rawText == "EN: Hi there." && update.result.versions.map(\.text) == ["Hi there."])
    }

    @Test func unsupportedLanguageFailsFast() async throws {
        let hindi = "आज मेरी तबीयत ठीक नहीं है, मैं घर जा रहा हूँ"
        let stub = StubAppleModel(answer: ["HI: …"])
        await #expect(throws: AppleModelError.unsupportedLanguage) {
            _ = try await final(converter(stub).generate(.question, input: hindi))
        }
        #expect(stub.requests.isEmpty, "nothing sent to the model")
        // A language it speaks once it's listed; short or mixed text isn't judged; Chinese and English pass.
        let withHindi = StubAppleModel(languages: StubAppleModel.languages.union(["hi"]), answer: ["ठीक है"])
        #expect(try await final(converter(withHindi).generate(.question, input: hindi))?.rawText == "ठीक है")
        for text in ["नमस्ते", "Please tell the team नमस्ते आप कैसे हैं before the meeting tomorrow",
                     "这个方案我觉得还可以但是预算有点超了", "i think we should moved the meeting to next week", "wo jintian youdian bushufu"] {
            let passes = StubAppleModel(answer: ["ok"])
            #expect(try await final(converter(passes).generate(.question, input: text))?.rawText == "ok", "\(text)")
        }
        #expect(AppleModel.unsupportedLanguage(of: "Сегодня я плохо себя чувствую", supported: StubAppleModel.languages) == "ru")
        #expect(AppleModel.unsupportedLanguage(of: "Сегодня я плохо себя чувствую", supported: StubAppleModel.languages.union(["ru"])) == nil)
        #expect(AppleModel.unsupportedLanguage(of: "我今天有点不舒服，想请假一天回家休息", supported: StubAppleModel.languages) == nil)
    }

    @Test func latinTextIsNeverTurnedAway() async throws {
        // Pinyin reads as Indonesian (0.9 and more) or Vietnamese; those and Romanian, with their accents, are Latin too.
        for text in ["ming tian de hui wo ke neng qu bu liao", "mingtian dehui wo kenengqu buliao", "wo jintian youdian bushufu",
                     "Hôm nay tôi cảm thấy không được khỏe lắm", "Saya merasa kurang sehat hari ini, maaf ya",
                     "Bună ziua, ce mai faceți astăzi?", "aap kaise ho mera naam rahul hai"] {
            #expect(AppleModel.unsupportedLanguage(of: text, supported: ["en", "zh"]) == nil, "\(text)")
            let passes = StubAppleModel(languages: ["en", "zh"], answer: ["ok"])
            #expect(try await final(converter(passes).generate(.question, input: text))?.rawText == "ok", "\(text)")
        }
        // Hindi in its own script still is.
        #expect(AppleModel.unsupportedLanguage(of: "आज मेरी तबीयत ठीक नहीं है, मैं घर जा रहा हूँ", supported: StubAppleModel.languages) == "hi")
        #expect(AppleModel.mostlyLatin("Hôm nay tôi cảm thấy") && !AppleModel.mostlyLatin("आज मेरी तबीयत ठीक") && !AppleModel.mostlyLatin("我今天 ok"))
    }

    @Test func aSelectionIsJudgedWithoutTheAppsWrapping() async throws {
        let hindi = "आज मेरी तबीयत ठीक नहीं है"  // short: the wrapping's Latin letters used to outweigh it
        for input in [Prompt.editRequest(instruction: "improve", text: hindi), Prompt.editRequest(instruction: "translate: en", text: hindi)] {
            #expect(AppleModel.usersText(input).trimmingCharacters(in: .whitespacesAndNewlines) == hindi)
            let stub = StubAppleModel(answer: ["ok"])
            await #expect(throws: AppleModelError.unsupportedLanguage) {
                _ = try await final(converter(stub).generate(.edit, input: input))
            }
            #expect(stub.requests.isEmpty)
        }
        // A question about a selection: both, without the tags. An English question about Chinese text goes through.
        let question = Prompt.question("what does this mean", about: "这个方案我觉得还可以但是预算有点超了")
        #expect(!AppleModel.usersText(question).contains("selected_text"))
        let stub = StubAppleModel(answer: ["ok"])
        #expect(try await final(converter(stub).generate(.question, input: question))?.rawText == "ok")
        await #expect(throws: AppleModelError.unsupportedLanguage) {
            _ = try await final(converter(StubAppleModel(answer: ["ok"])).generate(.question, input: Prompt.question("?", about: hindi)))
        }
        // A selection in a supported language, with an English instruction, goes through.
        let supported = StubAppleModel(answer: ["ok"])
        let edit = Prompt.editRequest(instruction: "translate: hi", text: "I don't feel well today, I'm going home")
        #expect(try await final(converter(supported).generate(.edit, input: edit))?.rawText == "ok")
    }

    @Test func outputTokensEstimate() {
        #expect(AppleModel.estimatedOutputTokens(String(repeating: "abcd", count: 25)) == 25)  // 100 ASCII characters
        #expect(AppleModel.estimatedOutputTokens("我今天有点不舒服") == 8)
        #expect(AppleModel.estimatedOutputTokens("EN: 你好") == 3)  // "EN: " a token, two CJK
        #expect(!AppleModel.possiblyCut(String(repeating: "word ", count: 28), limit: 40))  // 35 tokens: under 36
        #expect(AppleModel.possiblyCut(String(repeating: "word ", count: 29), limit: 40))  // 37
    }

    @Test func theUsersMaxTokensIsNeverRaised() {
        let body = Prompt.commandRequest(.question, input: "q", config: config)
        #expect(AppleModel.request(from: body, maxTokens: 200, contextSize: 4096).maximumResponseTokens == 200)
        #expect(AppleModel.request(from: body, maxTokens: 100, contextSize: 4096).maximumResponseTokens == 100)
        // Lowered to what the context has left, not below the minimum unless the user's is lower.
        let long = Prompt.commandRequest(.question, input: String(repeating: "很长的问题。", count: 800), config: config)
        #expect(AppleModel.request(from: long, maxTokens: 1000, contextSize: 4096).maximumResponseTokens == AppleModel.minimumAnswer)
        #expect(AppleModel.request(from: long, maxTokens: 200, contextSize: 4096).maximumResponseTokens == 200)
        #expect(AppleModel.request(from: body, maxTokens: 3000, contextSize: 4096).maximumResponseTokens <= 3000)
    }

    @Test func withoutATokenCountANearlyFullAnswerCountsAsCut() async throws {
        var config = self.config
        config.maxTokens = 40
        // About 44 estimated tokens against a limit of 40: possibly cut (macOS 26, no count).
        let long = "EN: " + String(repeating: "word ", count: 30) + "\nEN: unfinished line"
        #expect(AppleModel.possiblyCut(long, limit: 40) && !AppleModel.possiblyCut("EN: short", limit: 40))
        let estimated = StubAppleModel(answer: [long])
        #expect(try await events(estimated, maxTokens: 40).last == .messageStop(reason: "max_tokens"))
        let c = converter(estimated, config)
        let first = try #require(try await final(c.generate(.question, input: "q")))
        _ = try await final(c.generate(.question, input: "q"))
        #expect(!first.fromCache && estimated.requests.count == 3, "not cached: asked again")
        // macOS 27 says how many: below the limit, finished, whatever the estimate.
        let counted = StubAppleModel(answer: [long], outputTokens: 30)
        #expect(try await events(counted, maxTokens: 40).last == .messageStop(reason: "end_turn"))
        let d = converter(counted, config)
        _ = try await final(d.generate(.question, input: "q"))
        let again = try #require(try await final(d.generate(.question, input: "q")))
        #expect(again.fromCache && counted.requests.count == 2)
    }

    @Test func refusalReadsNaturally() {
        #expect(ProviderError.refused(.apple).errorDescription == "Apple Intelligence declined this request")
        #expect(ProviderError.refused(.gemini).errorDescription == "The Gemini API declined this request")
    }
}
