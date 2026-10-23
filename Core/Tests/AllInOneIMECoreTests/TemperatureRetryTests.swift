import Foundation
import Testing
@testable import AllInOneIMECore

/// A model that refuses the temperature (a reasoning model, one that won't take it along with top_p) is asked again
/// without it, once, and remembered by provider and model: for the process, and in a cache file (`TemperatureSupport`).
/// The servers are stubs (`StubURLProtocol`) answering as Bedrock, the Claude API and OpenAI do: nothing goes over the
/// network.
struct TemperatureRetryTests {
    static let credentials: ChatClient.CredentialLoader = { _ in
        AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIDTEST", secretAccessKey: "secret"), region: nil)
    }

    /// A cache file in a folder of the test's own.
    static func cacheFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("temperature-\(UUID().uuidString)/unsupported-temperature.json")
    }

    static func client(_ support: TemperatureSupport, apple: any AppleModelBackend = AIConfigTests.GuidedStub(.deviceNotEligible, answer: ""))
        -> ChatClient {
        ChatClient(bedrock: BedrockClient(session: StubURLProtocol.session(), temperatureSupport: support), apple: apple)
    }

    static func body(temperature: Double?) -> ConverseRequest {
        ConverseRequest(system: [.init("Answer briefly")], messages: [.init(role: "user", text: "Hi")],
                        inferenceConfig: .init(maxTokens: 64, temperature: temperature))
    }

    static func bedrock(region: String, model: String, temperature: Double? = 0.3) -> Config {
        var config = Config.default
        config.provider = .bedrock
        config.region = region
        config.modelId = model
        config.temperature = temperature
        return config
    }

    static func text(_ stream: AsyncThrowingStream<BedrockStreamEvent, Error>) async throws -> String {
        var text = ""
        for try await event in stream { if case let .textDelta(delta) = event { text += delta } }
        return text
    }

    /// The temperature each request to `host` had (nil: none), in order.
    static func temperatures(_ host: String, bedrock: Bool = false) -> [Double?] {
        StubURLProtocol.requests(host: host).map { request in
            let json = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
            return (bedrock ? json["inferenceConfig"] as? [String: Any] : json)?["temperature"] as? Double
        }
    }

    // MARK: - What the servers answer

    /// Bedrock's ValidationException, as its HTTP API sends it.
    static func bedrockRefusal(_ message: String) -> StubURLProtocol.Response {
        .init(status: 400, headers: ["Content-Type": "application/json",
                                     "x-amzn-ErrorType": "ValidationException:http://internal.amazon.com/coral/com.amazon.bedrock/"],
              chunks: [Data(#"{"message":"\#(message)"}"#.utf8)])
    }

    static func bedrockAnswer() throws -> StubURLProtocol.Response {
        .init(status: 200, headers: ["Content-Type": "application/vnd.amazon.eventstream"], chunks: [Data(try fixture("bedrock-converse-stream"))])
    }

    // MARK: - Asked again, and remembered

    @Test func bedrockAsksAgainWithoutTheTemperatureAndRemembersTheModel() async throws {
        let region = "us-temperature-1", host = "bedrock-runtime.us-temperature-1.amazonaws.com"
        let model = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        let file = Self.cacheFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        StubURLProtocol.register(host: host, [
            Self.bedrockRefusal("The model returned the following errors: `temperature` and `top_p` cannot both be specified for this model. Please use only one."),
            try Self.bedrockAnswer(),
        ])
        let config = Self.bedrock(region: region, model: model)
        func ask(_ client: ChatClient, _ config: Config) async throws -> String {
            try await Self.text(client.stream(Self.body(temperature: config.temperature), config: config,
                                              loadCredentials: Self.credentials, loadKey: { _, _ in nil }))
        }
        let client = Self.client(TemperatureSupport(file: file))
        #expect(try await ask(client, config).contains("under the weather"))
        #expect(Self.temperatures(host, bedrock: true) == [0.3, nil])

        // Remembered: without it from the start, in this process and the next (the file).
        StubURLProtocol.register(host: host, try Self.bedrockAnswer())
        _ = try await ask(client, config)
        _ = try await ask(Self.client(TemperatureSupport(file: file)), config)
        #expect(Self.temperatures(host, bedrock: true) == [nil, nil])
        #expect(try String(contentsOf: file, encoding: .utf8) == #"["bedrock:us.anthropic.claude-sonnet-4-5-20250929-v1:0"]"#)

        // Another model still gets the user's temperature.
        StubURLProtocol.register(host: host, try Self.bedrockAnswer())
        _ = try await ask(client, Self.bedrock(region: region, model: "us.amazon.nova-2-lite-v1:0"))
        #expect(Self.temperatures(host, bedrock: true) == [0.3])
    }

    /// Settings → Assistant and Check for problems ask Bedrock with a temperature of 0, the user's own turned off or not:
    /// a model that refuses it answers them all the same.
    @Test func theAssistantAndCheckForProblemsAskAgainWithoutTheirTemperature() async throws {
        for (index, checks) in [false, true].enumerated() {
            let region = "us-assistant-\(index)", host = "bedrock-runtime.us-assistant-\(index).amazonaws.com"
            let file = Self.cacheFile()
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            StubURLProtocol.register(host: host, [
                Self.bedrockRefusal("The model returned the following errors: temperature is not supported for this model."),
                try Self.bedrockAnswer(),
            ])
            let config = Self.bedrock(region: region, model: "us.deepseek.r1-v1:0", temperature: nil)
            let client = Self.client(TemperatureSupport(file: file))
            if checks {
                let answer = try await DoctorService(client: client, loadCredentials: Self.credentials, loadKey: { _, _ in nil })
                    .ask("why doesn't translate work", findings: Doctor.findings(Doctor.Facts(), chinese: false), config: config)
                #expect(answer.explanation.contains("under the weather") && !answer.onDevice)
            } else {
                let answer = try await AIConfigService(client: client, loadCredentials: Self.credentials, loadKey: { _, _ in nil })
                    .ask("candidates in a column", context: AIConfigPrompt.Context(config: config))
                #expect(answer.text.contains("under the weather") && !answer.onDevice)
            }
            #expect(Self.temperatures(host, bedrock: true) == [0, nil], "\(checks)")
        }
    }

    // MARK: - Not asked again

    /// A validation error about something else fails as before, after one request, and nothing is remembered.
    @Test func bedrockErrorsAboutSomethingElseAreNotAskedAgain() async throws {
        let file = Self.cacheFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let client = Self.client(TemperatureSupport(file: file))
        let host = "bedrock-runtime.us-temperature-other.amazonaws.com"
        StubURLProtocol.register(host: host, [Self.bedrockRefusal("Input is too long for requested model."), try Self.bedrockAnswer()])
        await #expect(throws: BedrockError.self) {
            let config = Self.bedrock(region: "us-temperature-other", model: "us.anthropic.claude-haiku-4-5-20251001-v1:0")
            _ = try await Self.text(client.stream(Self.body(temperature: 0.3), config: config, loadCredentials: Self.credentials,
                                                  loadKey: { _, _ in nil }))
        }
        #expect(StubURLProtocol.requests(host: host).count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func whatCountsAsRefusingTheTemperature() {
        #expect(TemperatureSupport.refuses(BedrockError.http(status: 400, type: "ValidationException", message: "temperature and top_p cannot both be specified")))
        #expect(TemperatureSupport.refuses(BedrockError.stream(type: "validationException", message: "The model does not support temperature")))
        #expect(TemperatureSupport.refuses(ProviderError.http(provider: .openai, status: 422, type: nil, message: "Unsupported parameter: 'top_p'")))
        #expect(TemperatureSupport.refuses(ProviderError.stream(provider: .anthropic, type: "invalid_request_error", message: "temperature: not supported")))
        #expect(!TemperatureSupport.refuses(BedrockError.http(status: 403, type: "AccessDeniedException", message: "not allowed to set temperature")))
        #expect(!TemperatureSupport.refuses(BedrockError.stream(type: "throttlingException", message: "Too many requests (temperature)")))
        #expect(!TemperatureSupport.refuses(ProviderError.stream(provider: .openai, type: "server_error", message: "temperature")))
        #expect(!TemperatureSupport.refuses(ProviderError.missingKey(.openai)))
        #expect(!TemperatureSupport.refuses(URLError(.timedOut)))
    }

    /// By provider and model, in the caches folder (never config.json), names only; another process's kept too.
    @Test func theModelsAreKeptByProviderAndModelInTheCaches() throws {
        #expect(TemperatureSupport.shared.file == CorePaths.cacheDir.appendingPathComponent("unsupported-temperature.json"))
        let file = Self.cacheFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let support = TemperatureSupport(file: file)
        #expect(!support.omits(.openai, model: "o4-mini"))
        support.remember(.openai, model: "o4-mini")
        TemperatureSupport(file: file).remember(.anthropic, model: "claude-opus-5-5")  // another process meanwhile
        support.remember(.bedrock, model: "us.deepseek.r1-v1:0")
        let next = TemperatureSupport(file: file)
        #expect(next.omits(.openai, model: "o4-mini") && next.omits(.anthropic, model: "claude-opus-5-5")
                && next.omits(.bedrock, model: "us.deepseek.r1-v1:0"))
        #expect(!next.omits(.anthropic, model: "o4-mini") && !next.omits(.openai, model: "gpt-6-luna"))
        #expect(try String(contentsOf: file, encoding: .utf8)
                == #"["anthropic:claude-opus-5-5","bedrock:us.deepseek.r1-v1:0","openai:o4-mini"]"#)
        // Without a file (or one that can't be written): for the process.
        let memory = TemperatureSupport(file: nil)
        memory.remember(.openai, model: "o4-mini")
        #expect(memory.omits(.openai, model: "o4-mini") && !TemperatureSupport(file: nil).omits(.openai, model: "o4-mini"))
    }

    // MARK: - The Claude API and OpenAI-compatible services

    static let claudeAnswer = StubURLProtocol.Response(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [Data("""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_test","type":"message","role":"assistant","content":[]}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"OK"}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        event: message_stop
        data: {"type":"message_stop"}


        """.utf8)])

    static let openAIAnswer = StubURLProtocol.Response(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [Data("""
        data: {"choices":[{"index":0,"delta":{"content":"OK"},"finish_reason":null}]}

        data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """.utf8)])

    static func jsonError(_ status: Int, _ body: String) -> StubURLProtocol.Response {
        .init(status: status, headers: ["Content-Type": "application/json"], chunks: [Data(body.utf8)])
    }

    @Test func theClaudeAPIAndOpenAICompatibleServicesAskAgainWithoutIt() async throws {
        let cases: [(Provider, String, String, StubURLProtocol.Response)] = [
            (.anthropic, "claude-haiku-5-5", #"""
             {"type":"error","error":{"type":"invalid_request_error","message":"`temperature` may only be set to 1 when thinking is enabled. Please consult our documentation at https://docs.claude.com/en/docs/build-with-claude/extended-thinking"},"request_id":"req_011CTemperatureTest"}
             """#, Self.claudeAnswer),
            (.openai, "o4-mini", #"""
             {"error":{"message":"Unsupported value: 'temperature' does not support 0.7 with this model. Only the default (1) value is supported.","type":"invalid_request_error","param":"temperature","code":"unsupported_value"}}
             """#, Self.openAIAnswer),
            // A compatible service passing on its model's error, with a numeric code.
            (.openai, "anthropic/claude-sonnet-4.5", #"""
             {"error":{"message":"Provider returned error: temperature and top_p cannot both be specified for this model. Please use only one.","code":400}}
             """#, Self.openAIAnswer),
        ]
        for (index, (provider, model, refusal, answer)) in cases.enumerated() {
            let host = "temperature-\(index).test"
            let file = Self.cacheFile()
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            StubURLProtocol.register(host: host, [Self.jsonError(400, refusal), answer])
            var config = Config.default
            config.provider = provider
            let settings = ProviderSettings(model: model, baseURL: "https://\(host)" + (provider == .openai ? "/v1" : ""), temperature: 0.7)
            if provider == .anthropic { config.anthropic = settings } else { config.openai = settings }
            func ask(_ client: ChatClient) async throws -> String {
                try await Self.text(client.stream(Self.body(temperature: nil), config: config, loadCredentials: Self.credentials,
                                                  loadKey: { _, _ in "sk-test" }))
            }
            let client = Self.client(TemperatureSupport(file: file))
            #expect(try await ask(client) == "OK", "\(index)")
            #expect(Self.temperatures(host) == [0.7, nil], "\(index)")
            StubURLProtocol.register(host: host, answer)
            #expect(try await ask(client) == "OK", "\(index)")
            #expect(try await ask(Self.client(TemperatureSupport(file: file))) == "OK", "\(index)")
            #expect(Self.temperatures(host) == [nil, nil], "\(index)")
            #expect(try String(contentsOf: file, encoding: .utf8) == "[\"\(provider.rawValue):\(model)\"]", "\(index)")
        }
    }

    /// Only a validation error that names the temperature (or top_p), on a request that had one, from the Claude API or
    /// an OpenAI-compatible service: anything else fails as before, after one request, and nothing is remembered.
    @Test func otherProviderErrorsAreNotAskedAgain() async throws {
        let file = Self.cacheFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let client = Self.client(TemperatureSupport(file: file))
        let failures: [(Provider, Double?, StubURLProtocol.Response)] = [
            (.openai, 0.7, Self.jsonError(400, #"{"error":{"message":"max_tokens is too large: 900000. This model supports at most 128000 completion tokens.","type":"invalid_request_error","param":"max_tokens","code":"invalid_value"}}"#)),
            (.openai, 0.7, Self.jsonError(500, #"{"error":{"message":"The server had an error while processing your request (temperature sampling).","type":"server_error"}}"#)),
            (.anthropic, 0.7, Self.jsonError(429, #"{"type":"error","error":{"type":"rate_limit_error","message":"Number of requests has exceeded your rate limit; temperature unchanged"}}"#)),
            // No temperature to leave out.
            (.anthropic, nil, Self.jsonError(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"temperature: Input should be less than or equal to 1"}}"#)),
            // Gemini sends its own as before.
            (.gemini, 0.7, Self.jsonError(400, #"{"error":{"code":400,"message":"Invalid value at 'generation_config.temperature' (TYPE_FLOAT), 3","status":"INVALID_ARGUMENT"}}"#)),
        ]
        for (index, (provider, temperature, failure)) in failures.enumerated() {
            let host = "temperature-other-\(index).test"
            StubURLProtocol.register(host: host, [failure, Self.openAIAnswer])
            var config = Config.default
            config.provider = provider
            let settings = ProviderSettings(model: "some-model", baseURL: "https://\(host)" + (provider == .openai ? "/v1" : ""), temperature: temperature)
            switch provider {
            case .anthropic: config.anthropic = settings
            case .gemini: config.gemini = settings
            default: config.openai = settings
            }
            await #expect(throws: ProviderError.self, "\(index)") {
                _ = try await Self.text(client.stream(Self.body(temperature: nil), config: config, loadCredentials: Self.credentials,
                                                      loadKey: { _, _ in "sk-test" }))
            }
            #expect(StubURLProtocol.requests(host: host).count == 1, "\(index)")
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
