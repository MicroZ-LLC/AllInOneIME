import CryptoKit
import Foundation
import os
import Testing
@testable import AllInOneIMECore
#if canImport(FoundationModels)
import FoundationModels
#endif

// Acceptance tests for Apple's on-device model as a provider (`"provider": "apple"`), written from the spec by an
// independent reviewer. The model is a stub behind `AppleModelBackend`, so they run on any Mac and any macOS.
// Each test names the spec point it covers (S1 … S10).

// MARK: - Stubs

/// What a stub model was asked, and whether its streams were torn down.
final class AppleStubLog: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (requests: [AppleModelRequest](), terminations: 0))
    func record(_ request: AppleModelRequest) { state.withLock { $0.requests.append(request) } }
    func terminated() { state.withLock { $0.terminations += 1 } }
    var requests: [AppleModelRequest] { state.withLock { $0.requests } }
    var terminations: Int { state.withLock { $0.terminations } }
}

/// The on-device model, scripted.
struct ScriptedAppleModel: AppleModelBackend {
    enum Behavior: Sendable {
        /// Streams these snapshots (each the whole answer so far), `interval` apart, then finishes.
        case answer([AppleModelSnapshot], interval: Duration = .zero)
        /// Streams these snapshots, then throws.
        case fail([AppleModelSnapshot], any Error)
        /// Streams these snapshots, then nothing more until it is cancelled.
        case stall([AppleModelSnapshot])
        /// Like the framework: throws `contextExceeded` when the request (a byte-based guess at its tokens) and the
        /// answer's limit don't fit in the context; otherwise answers `text`.
        case frameworkLike(String)
    }

    var availability: AppleModelAvailability = .available
    var contextSize = 4096
    /// What `SystemLanguageModel.supportedLanguages` says on macOS 27.2 (24 locales; no Hindi).
    var supportedLanguages: Set<String> = ScriptedAppleModel.macOS27Languages
    var behavior: Behavior
    let log = AppleStubLog()

    static let macOS27Languages: Set<String> = ["da", "de", "en", "es", "fr", "it", "ja", "ko", "nb", "nl", "pt", "sv", "tr",
                                                "vi", "zh"]

    init(_ behavior: Behavior, availability: AppleModelAvailability = .available, contextSize: Int = 4096) {
        self.behavior = behavior
        self.availability = availability
        self.contextSize = contextSize
    }

    /// Answers `text`, streamed a few characters at a time.
    static func answering(_ text: String, contextSize: Int = 4096) -> ScriptedAppleModel {
        ScriptedAppleModel(.answer(AppleAcceptance.snapshots(text, characters: 3)), contextSize: contextSize)
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        log.record(request)
        let behavior = self.behavior, log = self.log, contextSize = self.contextSize
        return AsyncThrowingStream { continuation in
            let task = Task {
                switch behavior {
                case let .answer(snapshots, interval):
                    for snapshot in snapshots {
                        if interval > .zero { try? await Task.sleep(for: interval) }
                        if Task.isCancelled { break }
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                case let .fail(snapshots, error):
                    for snapshot in snapshots { continuation.yield(snapshot) }
                    continuation.finish(throwing: error)
                case let .stall(snapshots):
                    for snapshot in snapshots { continuation.yield(snapshot) }
                    while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
                case let .frameworkLike(text):
                    let all = [request.instructions, request.prompt] + request.examples.flatMap { [$0.prompt, $0.response] }
                    let tokens = all.reduce(0) { $0 + $1.utf8.count / 3 }
                    if tokens + request.maximumResponseTokens > contextSize {
                        continuation.finish(throwing: AppleModelError.contextExceeded)
                    } else {
                        continuation.yield(AppleModelSnapshot(text: text))
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                log.terminated()
            }
        }
    }
}

/// Fails every request made through it, and counts them: the on-device model must never reach the network.
final class AppleNoNetworkProtocol: URLProtocol, @unchecked Sendable {
    static let count = OSAllocatedUnfairLock(initialState: 0)

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppleNoNetworkProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count.withLock { $0 += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// Credentials and keys asked for: none should be, for the on-device model.
final class AppleSecretsLog: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)
    func asked() { state.withLock { $0 += 1 } }
    var count: Int { state.withLock { $0 } }
}

enum AppleAcceptance {
    struct NoCredentials: Error {}

    /// A config using the on-device model, with the languages and styles of `base`.
    static func apple(_ base: Config = .default) -> Config {
        var config = base
        config.provider = .apple
        return config
    }

    /// Chinese and English typed, three English versions or a line each.
    static var bilingual: Config {
        var config = Config.default
        config.setOrder([OutputLanguage.english, .chinese])
        config.setOrder([Language.chinese, .english])
        return config
    }

    static func converter(_ config: Config, _ model: ScriptedAppleModel, secrets: AppleSecretsLog = AppleSecretsLog()) -> Converter {
        Converter(
            client: BedrockClient(session: AppleNoNetworkProtocol.session()),
            loadConfig: { config },
            loadCredentials: { _ in
                secrets.asked()
                throw NoCredentials()
            },
            loadKey: { _, _ in
                secrets.asked()
                return "sk-should-not-be-used"
            },
            appleModel: model)
    }

    /// Prefixes of `text` every `characters` Characters (the last is `text`).
    static func snapshots(_ text: String, characters: Int) -> [AppleModelSnapshot] {
        var out: [AppleModelSnapshot] = []
        var index = text.startIndex
        while index < text.endIndex {
            index = text.index(index, offsetBy: characters, limitedBy: text.endIndex) ?? text.endIndex
            out.append(AppleModelSnapshot(text: String(text[..<index])))
        }
        return out
    }

    /// Prefixes of `text` at every Unicode scalar: some end inside a grapheme cluster (an emoji's skin tone or
    /// ZWJ sequence, a flag's second half), as a token boundary may.
    static func scalarSnapshots(_ text: String) -> [AppleModelSnapshot] {
        var scalars = String.UnicodeScalarView()
        return text.unicodeScalars.map { scalar in
            scalars.append(scalar)
            return AppleModelSnapshot(text: String(scalars))
        }
    }

    enum Outcome: Sendable {
        case finished([ConversionUpdate])
        case failed(any Error, [ConversionUpdate])
        case hung

        var error: (any Error)? {
            if case let .failed(error, _) = self { return error }
            return nil
        }

        var final: ConversionUpdate? {
            if case let .finished(updates) = self { return updates.last }
            return nil
        }
    }

    /// Runs `stream` to the end, or gives up after `limit` (a hang).
    static func outcome(_ stream: AsyncThrowingStream<ConversionUpdate, Error>, limit: Duration = .seconds(10)) async -> Outcome {
        await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                var updates: [ConversionUpdate] = []
                do {
                    for try await update in stream { updates.append(update) }
                    return .finished(updates)
                } catch {
                    return .failed(error, updates)
                }
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return .hung
            }
            let first = await group.next() ?? .hung
            group.cancelAll()
            return first
        }
    }

    /// All events of the provider stream, or the error it ended with.
    static func events(_ stream: AsyncThrowingStream<BedrockStreamEvent, Error>) async -> ([BedrockStreamEvent], (any Error)?) {
        var events: [BedrockStreamEvent] = []
        do {
            for try await event in stream { events.append(event) }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }

    /// The text the events add up to: deltas appended, a replacement in place of what came before.
    static func text(_ events: [BedrockStreamEvent]) -> String {
        var text = ""
        for event in events {
            if case let .textDelta(delta) = event { text += delta }
            if case let .textReplaced(whole) = event { text = whole }
        }
        return text
    }

    /// The tags of the lines the system prompt asks for ("EN", "EN", "EN", "STYLE_POLISH" …), read from its
    /// "Reply in exactly this format" block.
    static func formatTags(_ system: String) -> [String] {
        guard let start = system.range(of: "Reply in exactly this format and nothing else:\n") else { return [] }
        let block = system[start.upperBound...].components(separatedBy: "\n\n").first ?? ""
        return block.split(separator: "\n").map { String($0.prefix { $0 != ":" }) }
    }

    static func tags(_ answer: String) -> [String] {
        answer.split(separator: "\n").map { String($0.prefix { $0 != ":" }) }
    }

    /// A well-formed answer for `system`'s format: a line per tag.
    static func answer(for system: String) -> String {
        formatTags(system).enumerated().map { "\($0.element): Sample line \($0.offset + 1) 样例。" }.joined(separator: "\n")
    }

    /// The (user, assistant) example pairs of a writing request: every message but the last.
    static func pairs(_ body: ConverseRequest) -> [AppleModelRequest.Turn] {
        let messages = body.messages.dropLast().map { $0.content.map(\.text).joined() }
        return stride(from: 0, to: messages.count - 1, by: 2).map { .init(prompt: messages[$0], response: messages[$0 + 1]) }
    }
}

// MARK: - Tests

struct AppleModelAcceptanceTests {
    typealias A = AppleAcceptance

    // MARK: S1 Config

    @Test func s1_appleProviderRoundTripsThroughTheConfig() throws {
        let config = A.apple(A.bilingual)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["provider"] as? String == "apple")
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        #expect(decoded == config)
        #expect(decoded.provider == .apple)
        // Written by hand, as a user would.
        let minimal = try JSONDecoder().decode(Config.self, from: Data(#"{"provider": "apple"}"#.utf8))
        #expect(minimal.provider == .apple)
        // Through the file, as the app loads it.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aio-apple-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.write(to: url)
        #expect(try Config.load(from: url) == config)
    }

    @Test func s1_oldAndUnknownProviderConfigsBehaveAsBefore() throws {
        // A config from before providers stays on Bedrock with its settings.
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"awsProfile":"work","region":"eu-west-1"}"#.utf8))
        #expect(old.provider == .bedrock && old.awsProfile == "work" && old.region == "eu-west-1")
        // A provider this version doesn't know: the file is reported malformed, as in 0.6.3 (also checked byte for
        // byte against 0.6.3 in s4_…).
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aio-apple-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"provider":"martian"}"#.utf8).write(to: url)
        #expect(throws: ConfigError.self) { try Config.load(from: url) }
    }

    // MARK: S2 Availability

    @Test func s2_listedOnlyFromMacOS26() {
        #expect(!Provider.offered(apple: .unsupportedSystem).contains(.apple))
        for reason in [AppleModelAvailability.available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady] {
            // Listed (greyed out with the reason in the settings) wherever macOS 26 is.
            #expect(Provider.offered(apple: reason).contains(.apple), "\(reason)")
            // The others are as they were.
            #expect(Provider.offered(apple: reason).filter { $0 != .apple } == Provider.offered(apple: .unsupportedSystem))
        }
        // This Mac.
        if #available(macOS 26, *) {
            #expect(AppleModel.system.availability != .unsupportedSystem)
            #expect(Provider.offered.contains(.apple))
        } else {
            #expect(AppleModel.system.availability == .unsupportedSystem)
            #expect(!Provider.offered.contains(.apple))
        }
    }

    @Test func s2_unavailableReasonsAreClearAndPointToSettings() throws {
        let reasons: [AppleModelAvailability] = [.deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady]
        let messages = reasons.map { AppleModelError.unavailable($0).errorDescription ?? "" }
        #expect(messages.allSatisfy { $0.count > 20 })
        #expect(Set(messages).count == reasons.count)  // each its own reason
        #expect(messages[0].contains("can't run Apple Intelligence"))
        #expect(messages[1].contains("System Settings") && messages[1].contains("Apple Intelligence & Siri"))
        #expect(messages[2].lowercased().contains("ready"))
        // The settings' button opens System Settings.
        #expect(AppleModel.settingsURL.scheme == "x-apple.systempreferences")
    }

    @Test(arguments: [AppleModelAvailability.unsupportedSystem, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady])
    func s2_selectedWhileUnavailableEveryCommandFailsWithTheReason(_ reason: AppleModelAvailability) async throws {
        let model = ScriptedAppleModel(.answer([AppleModelSnapshot(text: "EN: should not be asked")]), availability: reason)
        let secrets = AppleSecretsLog()
        var config = A.apple(A.bilingual)
        config.timeoutSeconds = 30
        config.customCommands = [CustomCommand(name: "tweetit", type: .prompt, prompt: "Rewrite this as a tweet.")]
        let converter = A.converter(config, model, secrets: secrets)
        let custom = try #require(Command.catalog(config.customCommands).first { $0.name == "tweetit" })
        let network = AppleNoNetworkProtocol.count.withLock { $0 }
        let runs: [(String, AsyncThrowingStream<ConversionUpdate, Error>)] = [
            ("@improve", converter.convert("我今天有点不舒服", mode: .improve)),
            ("@translate", converter.convert("i dont feel so good today", mode: .translate)),
            ("@translate @improve", converter.convert("我今天有点不舒服", mode: .both)),
            ("@question", converter.generate(.question, input: "什么是量子计算？")),
            ("custom prompt", converter.generate(custom, input: "we shipped it")),
            ("selection", converter.generate(.edit, input: Prompt.editRequest(instruction: "improve", text: "i dont feel good"))),
        ]
        for (name, stream) in runs {
            let started = ContinuousClock.now
            // Not a hang, and not a failure that waited for the request's timeout (30 s). (The bound leaves room for
            // the full parallel suite, whose blocking tests can hold up the start of a task by a few seconds.)
            let outcome = await A.outcome(stream, limit: .seconds(10))
            #expect(ContinuousClock.now - started < .seconds(10), "\(name) took \(ContinuousClock.now - started)")
            let error = try #require(outcome.error, "\(name): \(outcome)")
            #expect(error as? AppleModelError == .unavailable(reason), "\(name): \(error)")
            #expect(!(error.localizedDescription).isEmpty)
        }
        #expect(model.log.requests.isEmpty)  // the model wasn't asked
        #expect(secrets.count == 0)  // no key or AWS profile was looked for: no fallback
        #expect(AppleNoNetworkProtocol.count.withLock { $0 } == network)  // nothing went to the network
    }

    // MARK: S3 Same prompts

    /// Every writing request: the instructions, the text and the settings are the other providers'; the examples are
    /// those of the other providers in the input's own language whose answer has the same lines.
    @Test func s3_sameInstructionsAndOnlyExamplesInTheInputsLanguageWithTheSameLines() throws {
        let inputs = ["我今天有点不舒服", "i dont feel so good today", "这个PR我review一下明天给你反馈", "오늘 몸이 좀 안 좋아요",
                      "आज मेरी तबीयत ठीक नहीं है", "je me sens pas tres bien aujourdhui"]
        var withExamples = 0
        for (configName, base) in AcceptanceGolden.configs(.bedrock) {
            for input in inputs {
                for mode in [WritingMode.improve, .translate, .both] {
                    let label = "\(configName) \(mode) \(input)"
                    var appleConfig = base
                    appleConfig.provider = .apple
                    let other = Prompt.request(for: input, mode: mode, config: base)
                    let apple = Prompt.request(for: input, mode: mode, config: appleConfig)
                    #expect(apple.system == other.system, "\(label)")
                    #expect(apple.inferenceConfig == other.inferenceConfig, "\(label)")
                    #expect(apple.messages.last == other.messages.last, "\(label)")
                    #expect(apple.messages.last?.role == "user" && apple.messages.last?.content.first?.text == input)
                    let system = other.system.map(\.text).joined(separator: "\n\n")
                    let wanted = A.formatTags(system)
                    #expect(!wanted.isEmpty, "\(label)")
                    let language = OutputLanguage(base.language(of: input))
                    let expected = A.pairs(other).filter {
                        OutputLanguage(base.language(of: $0.prompt)) == language && A.tags($0.response) == wanted
                    }
                    #expect(A.pairs(apple) == expected, "\(label)")
                    // Roles alternate user / assistant, ending with the user's text.
                    #expect(apple.messages.enumerated().allSatisfy { $0.element.role == ($0.offset % 2 == 0 ? "user" : "assistant") })
                    if !expected.isEmpty { withExamples += 1 }

                    // What reaches the model: the instructions, the examples as earlier turns, the text as the prompt.
                    let request = AppleModel.request(from: apple, maxTokens: apple.inferenceConfig.maxTokens ?? base.maxTokens,
                                                     contextSize: 1_000_000)
                    #expect(request.instructions == system, "\(label)")
                    #expect(request.examples == expected, "\(label)")
                    #expect(request.prompt == input, "\(label)")
                    #expect(request.temperature == base.temperature, "\(label)")
                }
            }
        }
        #expect(withExamples > 10)  // Chinese and English text does get examples
    }

    @Test func s3_commandRequestsAreTheOtherProviders() throws {
        let tweet = CustomCommand(name: "tweetit", type: .prompt, prompt: "Rewrite this as a short tweet.")
        let custom = try #require(Command.catalog([tweet]).first { $0.name == "tweetit" })
        for (command, input) in [(Command.question, "什么是量子计算？"), (custom, "we shipped it"),
                                 (Command.edit, Prompt.editRequest(instruction: "translate: ja", text: "我今天有点不舒服"))] {
            let other = Prompt.commandRequest(command, input: input, config: A.bilingual)
            let apple = Prompt.commandRequest(command, input: input, config: A.apple(A.bilingual))
            #expect(apple == other, "\(command.name)")
            let request = AppleModel.request(from: apple, maxTokens: 1000, contextSize: 4096)
            #expect(request.instructions == other.system.map(\.text).joined(separator: "\n\n"))
            #expect(request.examples.isEmpty && request.prompt == input)
        }
    }

    /// The streamed answer becomes the same candidates as the same text from an OpenAI-compatible API.
    @Test func s3_streamedOutputParsesIntoTheSameCandidatesAsAnotherProvider() async throws {
        let host = "apple-parity.acceptance.test"
        for (input, mode) in [("我今天有点不舒服", WritingMode.both), ("i dont feel so good today", .improve),
                              ("我今天有点不舒服", .translate)] {
            var config = A.bilingual
            config.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja")])
            let system = Prompt.request(for: input, mode: mode, config: config).system.map(\.text).joined(separator: "\n\n")
            let text = A.answer(for: system)

            // The same text from an OpenAI-compatible API, streamed as server-sent events.
            config.provider = .openai
            config.openai = ProviderSettings(model: "some-model", baseURL: "https://\(host)/v1")
            let chunks = A.snapshots(text, characters: 5).map(\.text)
            var sse = ""
            var previous = ""
            for chunk in chunks {
                let delta = String(chunk.dropFirst(previous.count))
                previous = chunk
                let payload = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": delta]]]])
                sse += "data: \(String(decoding: payload, as: UTF8.self))\n\n"
            }
            sse += "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
            StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"],
                                                       chunks: [Data(sse.utf8)]))
            let fixed = config
            let http = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed },
                                 loadKey: { _, _ in "k" })
            let fromHTTP = try #require(await A.outcome(http.convert(input, mode: mode)).final)

            let model = ScriptedAppleModel.answering(text)
            let fromApple = try #require(await A.outcome(A.converter(A.apple(config), model).convert(input, mode: mode)).final)
            #expect(!fromApple.result.isEmpty)
            #expect(fromApple.result == fromHTTP.result, "\(mode) \(input)")
            #expect(fromApple.rawText == text)
            #expect(model.log.requests.count == 1)
        }
    }

    // MARK: S4 Other providers unchanged

    @Test func s4_otherProvidersRequestsAreByteIdenticalToRelease063() throws {
        let groups = AcceptanceGolden.groups()
        #expect(groups.count == Self.golden063.count)
        for (name, text) in groups {
            let golden = try #require(Self.golden063[name], "no golden for \(name)")
            #expect(AcceptanceGolden.sha256(text) == golden, "\(name) differs from 55d496e")
        }
    }

    // MARK: S5 Small context

    @Test func s5_longInputDropsExamplesFirstKeepingRoomForTheAnswer() async throws {
        let config = A.apple(A.bilingual)
        let sentence = "今天开会讨论了下个季度的计划，大家意见不太一致。"
        let full = Prompt.request(for: sentence, mode: .both, config: config)
        let allExamples = A.pairs(full).count
        #expect(allExamples > 0)
        var kept: [Int] = []
        for repeats in [1, 20, 40, 60, 70, 80, 90, 100] {
            let input = String(repeating: sentence, count: repeats)
            let model = ScriptedAppleModel(.frameworkLike("EN: ok\nEN: ok\nEN: ok"))
            let outcome = await A.outcome(A.converter(config, model).convert(input, mode: .both))
            let request = try #require(model.log.requests.first)
            let examples = A.pairs(Prompt.request(for: input, mode: .both, config: config))
            // Left out from the first: the ones kept are the last ones, in order.
            #expect(Array(examples.suffix(request.examples.count)) == request.examples, "\(repeats)")
            #expect(request.prompt == input)
            if !request.examples.isEmpty {
                // Examples go before the answer's room does.
                #expect(request.maximumResponseTokens >= min(config.maxTokens, 1000), "\(repeats)")
                #expect(outcome.final != nil, "\(repeats): \(outcome)")
            }
            kept.append(request.examples.count)
        }
        #expect(kept.first == allExamples)  // a short text keeps them all
        #expect(zip(kept, kept.dropFirst()).allSatisfy { $0 >= $1 })  // fewer as the text grows
        #expect(kept.contains { $0 > 0 && $0 < allExamples })  // some dropped, some kept
        #expect(kept.last == 0)

        // A larger context (macOS 27) keeps more of them for the same text.
        let input = String(repeating: sentence, count: 80)
        let small = ScriptedAppleModel(.frameworkLike("EN: ok"), contextSize: 4096)
        let large = ScriptedAppleModel(.frameworkLike("EN: ok"), contextSize: 8192)
        _ = await A.outcome(A.converter(config, small).convert(input))
        _ = await A.outcome(A.converter(config, large).convert(input))
        let smallKept = try #require(small.log.requests.first).examples.count
        let largeKept = try #require(large.log.requests.first).examples.count
        #expect(largeKept > smallKept)
    }

    @Test func s5_textTooLongForTheContextGivesAClearMessage() async throws {
        let config = A.apple(A.bilingual)
        let input = String(repeating: "今天开会讨论了下个季度的计划，大家意见不太一致。", count: 400)  // ~9600 characters
        let model = ScriptedAppleModel(.frameworkLike("EN: never"))
        let outcome = await A.outcome(A.converter(config, model).convert(input))
        let request = try #require(model.log.requests.first)
        #expect(request.examples.isEmpty)
        let error = try #require(outcome.error, "\(outcome)")
        #expect(error as? AppleModelError == .contextExceeded)
        let message = try #require((error as? LocalizedError)?.errorDescription)
        #expect(message.lowercased().contains("too long"))
        // The same for a command.
        let question = await A.outcome(A.converter(config, ScriptedAppleModel(.frameworkLike("x"))).generate(.question, input: input))
        #expect(question.error as? AppleModelError == .contextExceeded)
    }

    @Test(arguments: [
        (AppleModelError.unsupportedLanguage as any Error, "language"),
        (AppleModelError.busy, "busy"),
        (ProviderError.refused(.apple), "declined"),
        (AppleModelError.unavailable(.modelNotReady), "ready"),  // assets not ready
        (AppleModelError.contextExceeded, "too long"),
    ])
    func s5_modelErrorsGiveAClearMessage(_ thrown: any Error, _ words: String) async throws {
        // Some of the answer may have streamed before it. (Text in languages the model speaks: Hindi is now turned
        // away before the model is asked, s5_unsupportedLanguageIsToldUpFront.)
        let model = ScriptedAppleModel(.fail([AppleModelSnapshot(text: "EN: Part")], thrown))
        for stream in [A.converter(A.apple(A.bilingual), model).convert("我今天有点不舒服，明天的会能不能改到下午"),
                       A.converter(A.apple(A.bilingual), model).generate(.question, input: "How are you doing today?")] {
            let outcome = await A.outcome(stream)
            let error = try #require(outcome.error, "\(outcome)")
            #expect(error.localizedDescription == thrown.localizedDescription)
            let message = try #require((error as? LocalizedError)?.errorDescription)
            #expect(message.lowercased().contains(words), "\(message)")
        }
    }

    /// Text in a language the model doesn't speak is turned away with a clear message before the model is asked.
    @Test func s5_unsupportedLanguageIsToldUpFront() async throws {
        let hindi = ["आज मेरी तबीयत ठीक नहीं है", "कल की मीटिंग में मैं नहीं आ पाऊँगा, माफ़ कीजिए",
                     "@question के लिए: भारत की राजधानी क्या है?"]
        let secrets = AppleSecretsLog()
        for text in hindi {
            for (name, stream) in [("@improve", { (c: Converter) in c.convert(text, mode: .improve) }),
                                   ("@translate", { (c: Converter) in c.convert(text, mode: .translate) }),
                                   ("@question", { (c: Converter) in c.generate(.question, input: text) })] {
                let model = ScriptedAppleModel.answering("EN: never")
                let outcome = await A.outcome(stream(A.converter(A.apple(A.bilingual), model, secrets: secrets)))
                let error = try #require(outcome.error, "\(name) \(text): \(outcome)")
                #expect(error as? AppleModelError == .unsupportedLanguage, "\(name) \(text)")
                #expect(error.localizedDescription.contains("doesn't support this language"))
                #expect(model.log.requests.isEmpty, "\(name) \(text): the model was asked")
            }
        }
        #expect(secrets.count == 0)
    }

    /// What the model does speak, and text too short or too mixed to tell, still goes to it.
    @Test(arguments: [
        "我今天有点不舒服",  // Chinese
        "明天的会我可能去不了因为家里有点事情不好意思",
        "i dont feel so good today",  // English, unpunctuated
        "lgtm, ship it",
        "this bug is blocker, your team need fix it asap",
        "这个PR我review一下明天给你反馈",  // mixed
        "帮我check一下这个deadline是不是Friday",
        "wo jin tian you dian bu shu fu",  // pinyin, as typed in English mode
        "ming tian de hui wo ke neng qu bu liao",
        "nihao shijie",
        "zhe ge gong neng tai nan yong le",
        "mingtian dehui wo kenengqu buliao",
        "je me sens pas tres bien aujourdhui",  // French without accents
        "오늘 몸이 좀 안 좋아요",  // Korean
        "今日はちょっと体調が悪いです",  // Japanese
        "ok",  // short
        "नमस्ते",  // Hindi, but too short to judge
        "ok नमस्ते thanks",  // mixed
        "https://github.com/MicroZ-LLC/AllInOneIME/issues/42",
    ])
    func s5_supportedShortAndMixedTextGoesToTheModel(_ text: String) async throws {
        for (name, mode) in [("@improve", WritingMode.improve), ("@translate", .translate)] {
            let model = ScriptedAppleModel.answering("EN: fine")
            let outcome = await A.outcome(A.converter(A.apple(A.bilingual), model).convert(text, mode: mode))
            #expect(outcome.error == nil, "\(name) \(text): \(String(describing: outcome.error))")
            #expect(model.log.requests.count == 1, "\(name) \(text)")
        }
        let model = ScriptedAppleModel.answering("Fine.")
        let question = await A.outcome(A.converter(A.apple(A.bilingual), model).generate(.question, input: text))
        #expect(question.error == nil, "@question \(text): \(String(describing: question.error))")
    }

    /// Latin-script languages always go to the model (pinyin reads as one of them); a non-Latin script whose
    /// language the model doesn't speak is told up front, for every AI command, the selection ones too.
    @Test func s5_latinScriptGoesToTheModelOtherUnsupportedScriptsAreToldUpFront() async throws {
        let latin = ["Saya tidak enak badan hari ini, mungkin besok saya tidak masuk kerja",  // Indonesian
                     "Hôm nay tôi cảm thấy không được khỏe lắm, mai tôi xin nghỉ nhé",  // Vietnamese (supported anyway)
                     "Saya tak sihat hari ini dan tidak dapat datang ke mesyuarat",  // Malay
                     "Dziś nie czuję się najlepiej, jutro chyba nie przyjdę",  // Polish
                     "Hoy no me siento muy bien, mañana no podré ir"]  // Spanish
        for text in latin {
            let model = ScriptedAppleModel.answering("EN: fine")
            let outcome = await A.outcome(A.converter(A.apple(A.bilingual), model).convert(text, mode: .improve))
            #expect(outcome.error == nil, "\(text): \(String(describing: outcome.error))")
            #expect(model.log.requests.count == 1, "\(text)")
        }
        let blocked = ["Сегодня я плохо себя чувствую, завтра не приду на встречу",  // Russian
                       "أنا لا أشعر بخير اليوم ولن أتمكن من حضور الاجتماع غدا",  // Arabic
                       "วันนี้ฉันรู้สึกไม่ค่อยสบาย พรุ่งนี้อาจจะไม่ได้ไปประชุม",  // Thai
                       "कल की मीटिंग में मैं नहीं आ पाऊँगा, माफ़ कीजिए"]  // Hindi
        for text in blocked {
            let runs: [(String, (Converter) -> AsyncThrowingStream<ConversionUpdate, Error>)] = [
                ("@improve", { $0.convert(text, mode: .improve) }),
                ("@translate", { $0.convert(text, mode: .translate) }),
                ("@question", { $0.generate(.question, input: text) }),
                ("@question on a selection", { $0.generate(.question, input: Prompt.question("总结一下", about: text)) }),
                ("@improve on a selection", { $0.generate(.edit, input: Prompt.editRequest(instruction: "improve", text: text)) }),
                ("@translate on a selection",
                 { $0.generate(.edit, input: Prompt.editRequest(instruction: "translate: en", text: text)) }),
            ]
            for (name, run) in runs {
                let model = ScriptedAppleModel.answering("never")
                let outcome = await A.outcome(run(A.converter(A.apple(A.bilingual), model)))
                #expect(outcome.error as? AppleModelError == .unsupportedLanguage, "\(name): \(text)")
                #expect(model.log.requests.isEmpty, "\(name): \(text): the model was asked")
            }
        }
    }

    #if canImport(FoundationModels)
    /// The framework's own errors become the ones above (the backend that runs on a real Mac).
    @Test func s5_frameworkErrorsMapToTheClearErrors() {
        guard #available(macOS 26, *) else { return }
        typealias G = LanguageModelSession.GenerationError
        let context = G.Context(debugDescription: "test")
        let cases26: [(any Error, String)] = [
            (G.exceededContextWindowSize(context), "contextExceeded"),
            (G.unsupportedLanguageOrLocale(context), "unsupportedLanguage"),
            (G.guardrailViolation(context), "refused"),
            (G.rateLimited(context), "busy"),
            (G.concurrentRequests(context), "busy"),
            (G.assetsUnavailable(context), "notReady"),
        ]
        func kind(_ error: any Error) -> String {
            switch error {
            case AppleModelError.contextExceeded: return "contextExceeded"
            case AppleModelError.unsupportedLanguage: return "unsupportedLanguage"
            case AppleModelError.busy: return "busy"
            case AppleModelError.unavailable(.modelNotReady): return "notReady"
            case ProviderError.refused(.apple): return "refused"
            default: return "other: \(error)"
            }
        }
        for (error, expected) in cases26 {
            #expect(kind(FoundationModelsBackend.mapped(error)) == expected, "\(error)")
        }
        if #available(macOS 27, *) {
            let cases27: [(any Error, String)] = [
                (LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "")),
                 "contextExceeded"),
                (LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: "hi", debugDescription: "")),
                 "unsupportedLanguage"),
                (LanguageModelError.refusal(.init(explanation: "", debugDescription: "")), "refused"),
                (LanguageModelError.guardrailViolation(.init(debugDescription: "")), "refused"),
                (LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "")), "busy"),
                (LanguageModelSession.Error.concurrentRequests, "busy"),
                (SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "")), "notReady"),
            ]
            for (error, expected) in cases27 {
                #expect(kind(FoundationModelsBackend.mapped(error)) == expected, "\(error)")
            }
        }
    }
    #endif

    // MARK: S6 Streaming

    @Test func s6_snapshotsBecomeDeltasWithCJKSplitAcrossSnapshots() async throws {
        let text = "ZH: 我今天有点不舒服，想早点回家休息。\nZH: 今天身体不太好！\nEN: I'm not feeling great today."
        for size in [1, 2, 3, 7] {
            let model = ScriptedAppleModel(.answer(A.snapshots(text, characters: size)))
            let (events, error) = await A.events(AppleModel.stream(Prompt.request(for: "我今天有点不舒服", config: A.apple()),
                                                                   backend: model, maxTokens: 1000, timeout: 5))
            #expect(error == nil)
            #expect(A.text(events) == text, "\(size)")
            // Deltas, not snapshots: no event repeats text already sent.
            let deltas = events.compactMap { event -> String? in
                if case let .textDelta(delta) = event { return delta }
                return nil
            }
            #expect(deltas.allSatisfy { $0.count <= size }, "\(size)")
            #expect(events.last == .messageStop(reason: "end_turn"))
        }
    }

    @Test func s6_snapshotsSplitInsideAnEmojiLoseOrRepeatNothing() async throws {
        let text = "EN: Great job 👍🏽 team 👨‍👩‍👧 🇺🇸!\nZH: 干得好 👍🏽 加油 🇨🇳"
        let model = ScriptedAppleModel(.answer(A.scalarSnapshots(text)))
        let (events, error) = await A.events(AppleModel.stream(Prompt.request(for: "great job team", config: A.apple()),
                                                               backend: model, maxTokens: 1000, timeout: 5))
        #expect(error == nil)
        let streamed = A.text(events)
        #expect(streamed == text)
        #expect(Array(streamed.unicodeScalars) == Array(text.unicodeScalars))
        // Through the converter too: what it shows is what the model wrote.
        let outcome = await A.outcome(A.converter(A.apple(), ScriptedAppleModel(.answer(A.scalarSnapshots(text))))
            .generate(.question, input: "say something nice"))
        #expect(outcome.final?.rawText == text)
    }

    @Test func s6_finalTextEqualsTheModelsFullOutput() async throws {
        // Snapshots that arrive unevenly (several characters, then one, an unchanged one, then many).
        let text = "EN: It's 3 PM — let's sync.\nEN: 好的，三点见。\nEN: See you at 3 😀"
        let cuts = [4, 5, 5, 20, 21, 30, text.count]
        let snapshots = cuts.map { AppleModelSnapshot(text: String(text.prefix($0))) }
        let model = ScriptedAppleModel(.answer(snapshots))
        let outcome = await A.outcome(A.converter(A.apple(), model).generate(.question, input: "when?"))
        let final = try #require(outcome.final)
        #expect(final.rawText == text)
        #expect(final.result.versions.first?.text == Converter.lines(text))
    }

    /// A snapshot that doesn't extend the one before (the model revised its answer): the text ends as the model's.
    @Test func s6_revisedSnapshotsEndAsTheModelsText() async throws {
        let scripts: [[String]] = [
            ["EN: Hello wor", "EN: Hi world", "EN: Hi world\nEN: Hey 👋🏽"],  // revised, then grows again
            ["ZH: 我今天有点", "ZH: 我今天身体", "ZH: 我今天身体不太好。"],  // CJK revised
            ["EN: 👍", "EN: 👍🏽", "EN: 👎🏽", "EN: 👎🏽 no"],  // inside a character, then revised
            ["EN: Long answer that the model", "EN: Short"],  // shrinks
            ["EN: same", "EN: same", "EN: same!"],  // an unchanged snapshot
        ]
        for script in scripts {
            let snapshots = script.map { AppleModelSnapshot(text: $0) }
            let model = ScriptedAppleModel(.answer(snapshots))
            let (events, error) = await A.events(AppleModel.stream(Prompt.request(for: "hi", config: A.apple()), backend: model,
                                                                   maxTokens: 1000, timeout: 5))
            #expect(error == nil)
            #expect(A.text(events) == script.last, "\(script)")
            // A revision is a replacement, not a delta appended to the old text.
            let revised = zip(script, script.dropFirst()).contains { !$1.unicodeScalars.starts(with: $0.unicodeScalars) }
            #expect(events.contains { if case .textReplaced = $0 { return true } else { return false } } == revised, "\(script)")
            // Through the converter, for a command and for the writing commands.
            let command = await A.outcome(A.converter(A.apple(), ScriptedAppleModel(.answer(snapshots)))
                .generate(.question, input: "hi"))
            #expect(command.final?.rawText == script.last, "\(script)")
            #expect(command.final?.result.versions.first?.text == Converter.lines(script.last!))
            let writing = await A.outcome(A.converter(A.apple(), ScriptedAppleModel(.answer(snapshots)))
                .convert("i dont feel so good today", mode: .improve))
            #expect(writing.final?.rawText == script.last, "\(script)")
            // Every update shows text the model wrote at that point, never old and new run together.
            if case let .finished(updates) = writing {
                #expect(updates.allSatisfy { script.contains($0.rawText) }, "\(updates.map(\.rawText))")
            }
        }
    }

    /// macOS 26 doesn't count the tokens generated: an answer about as long as its limit may have been cut, and isn't
    /// kept in the cache (or offered with an unfinished last line); a short one is.
    @Test func s6_macOS26AnswerNearItsLimitIsNotCached() async throws {
        var config = A.apple(A.bilingual)
        config.maxTokens = 300
        // Snapshots without a token count, as on macOS 26.
        let long = "ZH: " + String(repeating: "今天开会讨论了下个季度的计划。", count: 20) + "\nZH: 今天开会讨论"  // ~300 CJK characters
        let short = "ZH: 我今天身体不太好。\nZH: 今天有点不舒服。\nZH: 我今天不太舒服。"
        let input = "我今天有点不舒服"
        do {
            let model = ScriptedAppleModel(.answer(A.snapshots(long, characters: 7)))
            let converter = A.converter(config, model)
            let (events, _) = await A.events(AppleModel.stream(Prompt.request(for: input, mode: .improve, config: config),
                                                               backend: model, maxTokens: 300, timeout: 5))
            #expect(events.last == .messageStop(reason: "max_tokens"))
            let first = try #require(await A.outcome(converter.convert(input, mode: .improve)).final)
            #expect(!first.result.versions.contains { $0.text == "今天开会讨论" })  // the unfinished line is left out
            let again = try #require(await A.outcome(converter.convert(input, mode: .improve)).final)
            #expect(again.fromCache == false)
            // A command's answer is kept, but not cached either.
            _ = await A.outcome(converter.generate(.question, input: "总结一下"))
            let question = try #require(await A.outcome(converter.generate(.question, input: "总结一下")).final)
            #expect(question.fromCache == false)
        }
        do {
            let model = ScriptedAppleModel(.answer(A.snapshots(short, characters: 3)))
            let converter = A.converter(config, model)
            _ = await A.outcome(converter.convert(input, mode: .improve))
            let again = try #require(await A.outcome(converter.convert(input, mode: .improve)).final)
            #expect(again.fromCache == true)
            #expect(model.log.requests.count == 1)
        }
    }

    @Test func s6_noNewTextWithinTheTimeoutStops() async throws {
        var config = A.apple()
        config.timeoutSeconds = 0.6
        for before in [[], [AppleModelSnapshot(text: "EN: I'm")]] {
            let model = ScriptedAppleModel(.stall(before))
            let started = ContinuousClock.now
            let outcome = await A.outcome(A.converter(config, model).convert("i dont feel good"), limit: .seconds(10))
            let elapsed = ContinuousClock.now - started
            let error = try #require(outcome.error, "\(outcome)")
            #expect(error as? AppleModelError == .timedOut(0.6))
            #expect(((error as? LocalizedError)?.errorDescription ?? "").contains("didn't answer"))
            // Well before the 10-second hang guard (with room for a busy test run).
            #expect(elapsed >= .milliseconds(550) && elapsed < .seconds(5), "\(elapsed)")
            // The model's stream is let go of, not left running.
            try await Task.sleep(for: .milliseconds(300))
            #expect(model.log.terminations == 1)
        }
    }

    @Test func s6_steadySlowAnswerIsNotATimeout() async throws {
        var config = A.apple()
        config.timeoutSeconds = 1.5
        let text = "EN: I'm not feeling great today.\nEN: I feel a bit off.\nEN: Not my best day."
        // About 3 seconds in all (twice the timeout), never 1.5 s without something new.
        let model = ScriptedAppleModel(.answer(A.snapshots(text, characters: 10), interval: .milliseconds(400)))
        let outcome = await A.outcome(A.converter(config, model).convert("i dont feel good", mode: .improve))
        #expect(outcome.final?.rawText == text, "\(outcome)")
    }

    @Test func s6_temperatureAndMaxTokensFromTheConfigAreApplied() async throws {
        for temperature in [0.7, nil] as [Double?] {
            var config = A.apple()
            config.temperature = temperature
            config.maxTokens = 300
            let model = ScriptedAppleModel.answering("EN: ok")
            _ = await A.outcome(A.converter(config, model).convert("i dont feel good"))
            _ = await A.outcome(A.converter(config, model).generate(.question, input: "why?"))
            #expect(model.log.requests.count == 2)
            for request in model.log.requests {
                #expect(request.temperature == temperature)
                #expect(request.maximumResponseTokens == 300)
            }
        }
    }

    @Test func s6_smallMaxTokensSettingIsApplied() async throws {
        // The settings allow 200 output tokens (Stepper 200...4000).
        var config = A.apple()
        config.maxTokens = 200
        let model = ScriptedAppleModel.answering("EN: ok")
        _ = await A.outcome(A.converter(config, model).generate(.question, input: "why?"))
        #expect(model.log.requests.first?.maximumResponseTokens == 200)
    }

    @Test func s6_answerCutAtTheLimitIsNotCached() async throws {
        var config = A.apple()
        config.maxTokens = 300
        let text = "EN: I'm not feeling\nEN: I feel a bit"
        let model = ScriptedAppleModel(.answer([AppleModelSnapshot(text: text, outputTokens: 300)]))
        let converter = A.converter(config, model)
        let (events, _) = await A.events(AppleModel.stream(Prompt.request(for: "x", config: config), backend: model,
                                                           maxTokens: 300, timeout: 5))
        #expect(events.last == .messageStop(reason: "max_tokens"))
        _ = await A.outcome(converter.convert("i dont feel good"))
        let again = await A.outcome(converter.convert("i dont feel good"))
        #expect(again.final?.fromCache == false)
    }

    // MARK: S7 Test Connection

    /// As Settings → Test Connection runs it (`SettingsModel.runTest`): the sample sentence of the first input
    /// language, through a `Converter` with the settings being edited.
    @Test func s7_testConnectionWorksAndReportsUnavailability() async throws {
        let config = A.apple(A.bilingual)  // first input language Chinese: "我今天有点不舒服"
        let system = Prompt.request(for: "我今天有点不舒服", config: config).system.map(\.text).joined(separator: "\n\n")
        let model = ScriptedAppleModel.answering(A.answer(for: system))
        let passed = await A.outcome(A.converter(config, model).convert("我今天有点不舒服"))
        let final = try #require(passed.final)
        #expect(final.result.versions.first?.text != nil || final.result.translations.first != nil)

        let off = ScriptedAppleModel(.answer([]), availability: .appleIntelligenceNotEnabled)
        let failed = await A.outcome(A.converter(config, off).convert("我今天有点不舒服"))
        let error = try #require(failed.error)
        #expect(error as? AppleModelError == .unavailable(.appleIntelligenceNotEnabled))
        #expect(error.localizedDescription.contains("Apple Intelligence & Siri"))
    }

    // MARK: S8 @reportissue

    @Test func s8_reportIssueSaysAppleAndNoModelOrSecrets() throws {
        var config = A.apple(A.bilingual)
        config.awsProfile = "jane-doe-prod"
        config.region = "eu-central-1"
        config.modelId = "arn:aws:bedrock:eu-central-1:123456789012:inference-profile/secret"
        config.anthropic = ProviderSettings(model: "claude-acme-internal", baseURL: "https://llm.acme-corp.example")
        config.openai = ProviderSettings(model: "acme-secret-model", baseURL: "https://10.1.2.3/v1")
        let diagnostics = IssueReport.Diagnostics(config: config, appVersion: "0.6.3", macOS: "27.2", architecture: "arm64",
                                                  interfaceLanguage: "en", languagePacks: [], plugins: 0, extensions: 0)
        #expect(diagnostics.provider == "apple")
        #expect(diagnostics.model == nil)
        let report = IssueReport(title: "Apple Intelligence answers in the wrong language", diagnostics: diagnostics)
        let everything = (report.lines + [report.body(lines: report.lines), report.url.absoluteString]).joined(separator: "\n")
        #expect(report.lines.contains("AI provider: apple"))
        for secret in [AppleModel.modelName, "jane-doe", "eu-central-1", "123456789012", "acme", "10.1.2.3"] {
            #expect(!everything.contains(secret), "\(secret)")
        }
    }

    // MARK: S9 Commands

    @Test func s9_writingCommandsWorkThroughTheOnDeviceModel() async throws {
        let config = A.apple(A.bilingual)
        for (input, mode) in [("我今天有点不舒服", WritingMode.improve), ("i dont feel so good today", .improve),
                              ("我今天有点不舒服", .translate), ("i dont feel so good today", .translate),
                              ("我今天有点不舒服", .both)] {
            let body = Prompt.request(for: input, mode: mode, config: config)
            let system = body.system.map(\.text).joined(separator: "\n\n")
            let text = A.answer(for: system)
            let model = ScriptedAppleModel.answering(text)
            let outcome = await A.outcome(A.converter(config, model).convert(input, mode: mode))
            let final = try #require(outcome.final, "\(mode) \(input): \(outcome)")
            let plan = WritingPlan.make(mode, text: input, config: config)
            #expect(final.result == CandidateParser.parse(text, isFinal: true, output: plan.versions, translations: plan.translations),
                    "\(mode) \(input)")
            #expect(!final.result.isEmpty)
            let request = try #require(model.log.requests.first)
            #expect(request.instructions == system && request.prompt == input)
        }
    }

    @Test func s9_questionCustomPromptAndSelectionCommandsWork() async throws {
        let tweet = CustomCommand(name: "tweetit", type: .prompt, prompt: "Rewrite this as a short tweet.")
        var config = A.apple(A.bilingual)
        config.customCommands = [tweet]
        let custom = try #require(Command.catalog(config.customCommands).first { $0.name == "tweetit" })
        let runs: [(Command, String, String)] = [
            (.question, "什么是量子计算？", "量子计算利用量子比特的叠加和纠缠来处理信息。"),
            (.question, Prompt.question("总结一下", about: "The meeting moved to Friday at 3pm."), "会议改到周五下午三点。"),
            (custom, "we shipped the new release today", "We shipped it! 🚀"),
            (.edit, Prompt.editRequest(instruction: "translate: ja", text: "我今天有点不舒服"), "今日はちょっと体調が悪いです。"),
            (.edit, Prompt.editRequest(instruction: "improve", text: "i dont feel so good today"), "I don't feel so good today."),
        ]
        for (command, input, answer) in runs {
            let model = ScriptedAppleModel.answering(answer)
            let outcome = await A.outcome(A.converter(config, model).generate(command, input: input))
            let final = try #require(outcome.final, "\(command.name): \(outcome)")
            #expect(final.result.versions.first?.text == answer)
            let request = try #require(model.log.requests.first)
            #expect(request.instructions == Prompt.commandRequest(command, input: input, config: config).system.map(\.text)
                .joined(separator: "\n\n"))
            #expect(request.prompt == input)
        }
    }

    // MARK: S10 macOS 14 safety

    /// FoundationModels is weak-linked, and nothing of it is used outside `#if canImport(FoundationModels)` and an
    /// availability check (the binary itself is checked with `otool -l`, by hand).
    @Test func s10_foundationModelsIsWeakLinkedAndGated() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(package.contains(#""-weak_framework", "-Xlinker", "FoundationModels""#))
        #expect(package.contains("platforms: [.macOS(.v14)]"))

        let symbols = ["FoundationModels", "SystemLanguageModel", "LanguageModelSession", "GenerationOptions", "Transcript",
                       "LanguageModelError", "FoundationModelsBackend"]
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(files.count > 50)
        var uses = 0
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            var gate: [String] = []  // the #if conditions around the line
            var available = false  // inside a declaration or block marked for macOS 26 or later
            var depth = 0, availableDepth = Int.max
            for (number, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if ") { gate.append(trimmed) }
                if trimmed.hasPrefix("#endif") { _ = gate.popLast() }
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") { continue }
                if line.contains("@available(macOS 26") || line.contains("#available(macOS 26")
                    || line.contains("@available(macOS 27") || line.contains("#available(macOS 27") {
                    if !available { availableDepth = depth }
                    available = true
                }
                let code = line.components(separatedBy: "//").first ?? line
                let used = symbols.filter { symbol in
                    code.range(of: "\\b\(symbol)\\b", options: .regularExpression) != nil
                }
                // `AppleModel.system`'s stand-in names the type inside the gate; a comment or string isn't a use.
                if !used.isEmpty, !code.contains("\"") {
                    uses += 1
                    let where_ = "\(file.lastPathComponent):\(number + 1): \(trimmed)"
                    #expect(gate.contains("#if canImport(FoundationModels)"), "ungated: \(where_)")
                    if !trimmed.hasPrefix("import ") {
                        #expect(available, "no availability check: \(where_)")
                    }
                }
                depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                if available, depth <= availableDepth, line.contains("}") { available = false; availableDepth = .max }
            }
        }
        #expect(uses > 5)
    }
}

// MARK: - Golden requests (spec 4): the same code runs against release-0.6.3 (55d496e) to make the goldens.

enum AcceptanceGolden {
    static let inputs = [
        "我今天有点不舒服",
        "i dont feel so good today",
        "这个PR我review一下明天给你反馈",
        "오늘 몸이 좀 안 좋아요",
        "आज मेरी तबीयत ठीक नहीं है",
        "je me sens pas tres bien aujourdhui",
        String(repeating: "今天开会讨论了下个季度的计划，大家意见不太一致。", count: 60),
        "great job 👍🏽 team 🎉",
    ]

    static func configs(_ provider: Provider) -> [(String, Config)] {
        var a = Config.default
        a.provider = provider
        a.region = "us-west-2"
        var b = a
        b.setOrder([OutputLanguage.chinese, .english])
        b.setOrder([Language.chinese, .english])
        var c = a
        c.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja")])
        c.setOrder([Language.chinese, .english, .french, .korean, .hindi])
        c.rewriteStyles = []
        c.maxTokens = 700
        c.temperature = nil
        c.timeoutSeconds = 30
        return [("A", a), ("B", b), ("C", c)]
    }

    /// The provider variants: (name, provider, settings applied to the config).
    static var variants: [(String, Provider, @Sendable (inout Config) -> Void)] { [
        ("bedrock", .bedrock, { _ in }),
        ("anthropic", .anthropic, { _ in }),
        ("anthropic-opus", .anthropic, { $0.anthropic = ProviderSettings(model: "claude-opus-5-5", effort: "medium") }),
        ("gemini", .gemini, { _ in }),
        ("openai", .openai, { _ in }),
        ("ollama", .openai, { $0.openai = ProviderSettings(model: "llama3.1:8b", baseURL: "http://localhost:11434/v1") }),
        ("deepseek", .openai, { $0.openai = ProviderSettings(model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1", temperature: 0.7) }),
        ("hosted", .hosted, { _ in }),
    ] }

    /// What goes on the wire for `body`, as `ChatClient.stream` makes it for `config.provider`.
    static func wire(_ body: ConverseRequest, _ config: Config) -> String {
        do {
            let request: URLRequest
            if config.provider == .bedrock {
                request = try BedrockClient.makeRequest(
                    body, modelId: config.modelId, region: config.region ?? "us-east-1",
                    credentials: AWSCredentials(accessKeyId: "AKIDGOLDEN", secretAccessKey: "golden-secret"),
                    timeout: config.timeoutSeconds, date: Date(timeIntervalSince1970: 1_790_000_000))
            } else {
                request = try HTTPProviders.makeRequest(
                    body, provider: config.provider, settings: config.settings(for: config.provider), key: "sk-golden",
                    maxTokens: body.inferenceConfig.maxTokens ?? config.maxTokens, timeout: config.timeoutSeconds)
            }
            var body = request.httpBody ?? Data()
            var headers = request.allHTTPHeaderFields ?? [:]
            if config.provider == .bedrock {
                // JSONEncoder's key order changes from run to run (in both versions): compare the JSON, sorted, and
                // the signature's scope (the signature itself signs those unsorted bytes).
                let object = try JSONSerialization.jsonObject(with: body)
                body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                headers["Authorization"] = headers["Authorization"].map { String($0.prefix { $0 != "," }) + ", <signature>" }
            }
            let lines = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            return ([request.httpMethod ?? "", request.url?.absoluteString ?? "", "timeout \(request.timeoutInterval)"]
                + lines + [String(decoding: body, as: UTF8.self)]).joined(separator: "\n")
        } catch {
            return "error: \(error)"
        }
    }

    static func commands() -> [(String, Command, String)] {
        let tweet = CustomCommand(name: "tweetit", type: .prompt, prompt: "Rewrite this as a short, upbeat tweet.")
        let custom = Command.catalog([tweet]).first { $0.name == "tweetit" }!
        return [
            ("question", .question, "什么是量子计算？"),
            ("question-selection", .question, Prompt.question("总结一下", about: "The meeting moved to Friday at 3pm.")),
            ("edit-translate", .edit, Prompt.editRequest(instruction: "translate: ja", text: "我今天有点不舒服")),
            ("edit-improve", .edit, Prompt.editRequest(instruction: "improve", text: "i dont feel so good today")),
            ("custom", custom, "we shipped the new release today"),
        ]
    }

    /// Group name → every request of the group, in order.
    static func groups() -> [(String, String)] {
        var out: [(String, String)] = []
        for (name, provider, apply) in variants {
            for (configName, base) in configs(provider) {
                var config = base
                apply(&config)
                var all: [String] = []
                for input in inputs {
                    for mode in [WritingMode.improve, .translate, .both] {
                        all.append(wire(Prompt.request(for: input, mode: mode, config: config), config))
                    }
                }
                out.append(("\(name)/\(configName)/writing", all.joined(separator: "\n----\n")))
                let commands = commands().map { wire(Prompt.commandRequest($0.1, input: $0.2, config: config), config) }
                out.append(("\(name)/\(configName)/commands", commands.joined(separator: "\n----\n")))
            }
        }
        // The config file: an old one without "provider", and one with a provider this version doesn't know.
        let old = #"{"awsProfile":"work","region":"eu-west-1","maxTokens":900,"rewriteStyles":["润色"]}"#
        let unknown = #"{"provider":"martian","maxTokens":900}"#
        for (name, json) in [("config/old", old), ("config/unknown", unknown)] {
            let text: String
            do {
                let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                text = String(decoding: try encoder.encode(config), as: UTF8.self)
            } catch {
                text = "throws"
            }
            out.append((name, text))
        }
        return out
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleModelAcceptanceTests {
    /// `AcceptanceGolden.groups()` at release-0.6.3 (55d496e), made by running the same code in a worktree of it.
    static let golden063: [String: String] = [
        "bedrock/A/writing": "9f8fd9de657ddef1b2e1368fc04c9ebbf485e40b1f46ffd6a224efd3f84bcb32",
        "bedrock/A/commands": "8e4e4b3949a9eaa7dedce9a7d8c315610de034f7cc02d6ca03d2fcfbe02885ab",
        "bedrock/B/writing": "b95312e196a7e737a5b6604e41eceec7f1190bed0f152afa5998d2feda279bf3",
        "bedrock/B/commands": "8e4e4b3949a9eaa7dedce9a7d8c315610de034f7cc02d6ca03d2fcfbe02885ab",
        "bedrock/C/writing": "c83f077cb7ea13286949a52dbe1d9637b1e41bb6ba2fb6d4f488476a22b6aa0f",
        "bedrock/C/commands": "f7130593047aa55bc8d57697bb6762c1ecbc6e7bc45e6a83e400b9351cebce11",
        "anthropic/A/writing": "01ca63f51efff3b3748c3126676ffc9f79a0832dee8a1eeaa5f7ea636400b109",
        "anthropic/A/commands": "1fc3068b8c140a43515c98c5bc149fc6e083e3452b1d55e97fdbf00f69b3761e",
        "anthropic/B/writing": "ebcb520f3e0e77be32fa60d395292fd9d993b3a76e9d5b1b90491b98ea4a613b",
        "anthropic/B/commands": "1fc3068b8c140a43515c98c5bc149fc6e083e3452b1d55e97fdbf00f69b3761e",
        "anthropic/C/writing": "b2e1ce80aee92b859604d09f15f7324f2dcc23f991a57de39a65d51f3b67d031",
        "anthropic/C/commands": "a9e1a4de8af6891a1c432af80a400ce61c20ff8072395ea3cb5539cbb2ee70f8",
        "anthropic-opus/A/writing": "7c0c4da5e66e3338a6981ef9b71cbcdd91e9e74b84de29f288d81a15e534c7ad",
        "anthropic-opus/A/commands": "07cceb4a64804114f97fc8cb5523d6eb200cd35d0c9e149cd0a3e49621eea612",
        "anthropic-opus/B/writing": "c0dea60788502dcf2cc9d9c1b71ad4ffe87b288ae89969215c5fbcdb0becbc92",
        "anthropic-opus/B/commands": "07cceb4a64804114f97fc8cb5523d6eb200cd35d0c9e149cd0a3e49621eea612",
        "anthropic-opus/C/writing": "ef1cf1c69d677af7cfd9ffa5b91a76bb1128f6e782f4ec17c0307323fab29323",
        "anthropic-opus/C/commands": "646dcd5d1a7aa187c08dcb236ab9e1f3b29b51d0e093e1a9514f2cae3be51957",
        "gemini/A/writing": "bd801c7819862b906397c53168ae155c65d266530eeae2d6e8a7cff31312f947",
        "gemini/A/commands": "b32e46c8128374e86c8f3ef47a315d8ad2e36f9e4c34d3491fcda26a5c2ae922",
        "gemini/B/writing": "c071dacc6741bd92b38f73eb59165b92f94c584d5a39f5210271ee53b32feda2",
        "gemini/B/commands": "b32e46c8128374e86c8f3ef47a315d8ad2e36f9e4c34d3491fcda26a5c2ae922",
        "gemini/C/writing": "ae42f10cc3ecee1b65263a0cbff6209aca4c4a380da2d7e0510fec3e56dbb2e0",
        "gemini/C/commands": "1d45101334c5a49d5c9a28158933e89a0da1a3dfd4a1991bd12704b453bc9f72",
        "openai/A/writing": "f153fde115c8d71b93b332dae9648bda37ee67f18f0a075f8e6c73a2492a577e",
        "openai/A/commands": "23688f2d48f6c24d7bcc04794a1422917f5763271697a87a36ccdd70912ce9b0",
        "openai/B/writing": "af4d7358490e871e5645f98914745e945a9e518975397853ba4877ec1167c28d",
        "openai/B/commands": "23688f2d48f6c24d7bcc04794a1422917f5763271697a87a36ccdd70912ce9b0",
        "openai/C/writing": "764fe29f88a37be96c0424f297abf8518df756cfa942505e2a192c336d65c1eb",
        "openai/C/commands": "b653d4e2a3536704262b453ee3728b55538598538addde8c6a44cc76d5ac2a0c",
        "ollama/A/writing": "61f9b5138f4e31f9dde6c75d79692010364a32d0a12f094bceabe443bb026dfa",
        "ollama/A/commands": "718b5ae73c43a7a517a7d6d376f0859b5732eec5a4c8439fe0b05739d8ba7e2f",
        "ollama/B/writing": "415671d79cf07476861460ddf2d8948ec62c6f89ed79ae8d24bc610625af37b9",
        "ollama/B/commands": "718b5ae73c43a7a517a7d6d376f0859b5732eec5a4c8439fe0b05739d8ba7e2f",
        "ollama/C/writing": "8178c22c9817b53334d36543e2458595f24272f69e22a72c9af32f5efcc07c61",
        "ollama/C/commands": "cb6823af8ce904c0e805b580c6eda49c4c44cc5d415085b4a53340ba519f3406",
        "deepseek/A/writing": "7def1982ac5c6bc945685818a6d0128a204be4129167d5c04f4ab59d4189fe92",
        "deepseek/A/commands": "19929644680b309c7d3703ee51303d9755edf7f1b3d373553e058fdeeb3048eb",
        "deepseek/B/writing": "a2ff7210ab5b565072fb53302241662bdd311ab71ba5e175b3504ffed1ad18d1",
        "deepseek/B/commands": "19929644680b309c7d3703ee51303d9755edf7f1b3d373553e058fdeeb3048eb",
        "deepseek/C/writing": "c507b13fd3b376325837ed648435f3b5f03ba7d4cf54150da3b01305546eb54a",
        "deepseek/C/commands": "d4c4243f1a1a296370207317d70d8fbcb3c020f0b11c24deb753e7aebc7d017e",
        "hosted/A/writing": "d1276836dca6892fc4fcf07c13a872ee80cfe6427e9aed91dbdb4a0caaad5fbc",
        "hosted/A/commands": "808767aa7250d664d6571e30f7eeab80f20c5168f40b8e2023c231b187d55a77",
        "hosted/B/writing": "f836b10a4c4caf355709a2722f33e55bab2216115bdf187cb41f7b3de8258cca",
        "hosted/B/commands": "808767aa7250d664d6571e30f7eeab80f20c5168f40b8e2023c231b187d55a77",
        "hosted/C/writing": "5e063ccc41332eacab162050cc5e9ff0f2ce491c76ab14559eddaad8bdf59ce1",
        "hosted/C/commands": "5c2486b6205a7f0875386c4b0a56ec37eec8e1418a114b20feafb396f131428a",
        "config/old": "2b4fc5fdbb1891ecb393c708ca70319d0c93434f924f2091bd272a0c3e28211a",
        "config/unknown": "754c93cbd85e6d1a2f5a4828bce4dd088feb87552cadf6c28a08580c4b0eec67",
    ]
}
