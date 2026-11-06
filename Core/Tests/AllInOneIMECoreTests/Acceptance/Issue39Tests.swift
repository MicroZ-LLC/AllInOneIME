import Foundation
import Testing
@testable import AllInOneIMECore

// Issue #39: an OpenAI base URL with a trailing slash (or in another case) loses the default model. With the model left
// empty, OpenAI's own base URL uses OpenAI's default model, and another service's has none. But that base URL is told
// apart by its exact text: "https://api.openai.com/v1/" or "https://API.openai.com/v1" is taken for another service,
// and every request fails with "No model set for the OpenAI-compatible API", while Settings shows the default model as
// the placeholder. Expected: the same base URL written another way uses the default model, as "…/v1" does. Checked as
// the user gets there: config.json as written, the base URL typed in Settings, and `@question` asked through the real
// `Converter` to a stubbed OpenAI API (`StubURLProtocol`).

private enum Issue39 {
    /// OpenAI's own base URL, written other ways: a trailing slash, the host or the scheme in capitals.
    static let openAIWrittenOtherwise = [
        "https://api.openai.com/v1/",
        "https://API.OpenAI.com/v1",
        "HTTPS://api.openai.com/v1",
        "https://Api.OpenAI.com/v1/",
    ]

    static var defaultModel: String { ProviderSettings.defaults(for: .openai).model ?? "" }

    /// The config.json of someone on the OpenAI-compatible provider at `baseURL`, the model left empty.
    static func config(baseURL: String) throws -> Config {
        let json: [String: Any] = ["provider": "openai", "openai": ["baseURL": baseURL]]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue39-\(UUID().uuidString)",
                                                                                   isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return try Config.load(from: url)
    }

    /// The host requests to `baseURL` go to, as written and in lower case (whichever a fix sends to).
    static func hosts(of baseURL: String) -> [String] {
        let host = URL(string: baseURL)?.host ?? ""
        return Array(Set([host, host.lowercased()]))
    }

    /// The OpenAI API's answer to every request to `baseURL`'s host.
    static func serve(_ baseURL: String) {
        let chunk = #"{"choices":[{"index":0,"delta":{"content":"A qubit is a quantum bit."},"finish_reason":"stop"}]}"#
        let sse = "data: \(chunk)\r\n\r\ndata: [DONE]\r\n\r\n"
        for host in hosts(of: baseURL) {
            StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"],
                                                       chunks: [Data(sse.utf8)]))
        }
    }

    /// Every request sent to `baseURL`'s host since `serve`.
    static func requests(_ baseURL: String) -> [URLRequest] {
        hosts(of: baseURL).flatMap { StubURLProtocol.requests(host: $0) }
    }

    /// The model a request asked for.
    static func model(_ request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return object["model"] as? String
    }

    /// A converter on the OpenAI-compatible provider at `baseURL`, the model left empty, with a key.
    static func converter(baseURL: String) throws -> Converter {
        var config = try config(baseURL: baseURL)
        config.rewriteStyles = []
        let fixed = config
        return Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed },
                         loadKey: { provider, _ in provider == .openai ? "test-key" : nil })
    }

    /// The final update of a request, or the error it ended with.
    static func ask(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async -> Result<ConversionUpdate?, Error> {
        do {
            var final: ConversionUpdate?
            for try await update in stream where update.isFinal { final = update }
            return .success(final)
        } catch {
            return .failure(error)
        }
    }

    static func describe(_ result: Result<ConversionUpdate?, Error>) -> String {
        switch result {
        case let .success(update): return update.map { $0.rawText.debugDescription } ?? "no answer"
        case let .failure(error): return (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// Serialized: every case asks the same stubbed host (api.openai.com), and registering it again forgets what it was asked.
@Suite(.serialized) struct Issue39Tests {
    // MARK: config.json

    /// OpenAI's base URL written another way, the model left empty: OpenAI's default model, as for "…/v1".
    @Test(arguments: Issue39.openAIWrittenOtherwise)
    func openAIsBaseURLWrittenOtherwiseUsesTheDefaultModel(baseURL: String) throws {
        let config = try Issue39.config(baseURL: baseURL)
        #expect(config.provider == .openai && config.openai.model == nil, "control: the model is left empty")
        #expect(config.settings(for: .openai).model == Issue39.defaultModel,
                "\(baseURL) has no model: \(String(describing: config.settings(for: .openai).model))")
        #expect(config.activeModel == "openai:\(Issue39.defaultModel)", "\(baseURL): \(config.activeModel)")
    }

    /// The control: OpenAI's base URL as the default has it uses the default model (as today).
    @Test func openAIsBaseURLAsTheDefaultHasItUsesTheDefaultModel() throws {
        let config = try Issue39.config(baseURL: "https://api.openai.com/v1")
        #expect(!Issue39.defaultModel.isEmpty)
        #expect(config.settings(for: .openai).model == Issue39.defaultModel)
    }

    /// The control: another service's base URL, with or without the slash, still has no default model (OpenAI's model
    /// isn't sent to DeepSeek).
    @Test(arguments: ["https://api.deepseek.com/v1", "https://api.deepseek.com/v1/", "https://api.openai.com.relay.example/v1/"])
    func anotherServicesBaseURLHasNoDefaultModel(baseURL: String) throws {
        let config = try Issue39.config(baseURL: baseURL)
        #expect(config.settings(for: .openai).model == nil, "\(baseURL): \(String(describing: config.settings(for: .openai).model))")
    }

    // MARK: Settings

    /// The base URL typed in Settings with a trailing slash, the model field left empty (its placeholder the default
    /// model): the default model is what requests use, once saved and read again.
    @Test func aBaseURLTypedInSettingsWithASlashUsesTheDefaultModel() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue39-\(UUID().uuidString)",
                                                                                   isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"provider": "openai"}"#.utf8).write(to: url)
        let store = SettingsStore(configURL: url)
        store.setProviderField(.openai, \.baseURL, to: " https://api.openai.com/v1/ ")
        #expect(store.config.openai.model == nil, "control: the model is left empty")
        #expect(store.config.settings(for: .openai).model == Issue39.defaultModel,
                "in Settings: \(String(describing: store.config.settings(for: .openai).model))")
        let saved = try Config.load(from: url)
        #expect(saved.settings(for: .openai).model == Issue39.defaultModel,
                "saved: \(String(describing: saved.settings(for: .openai).model))")
    }

    // MARK: Asked as the user asks

    /// `@question` with OpenAI's base URL written another way: the request goes to OpenAI with the default model,
    /// instead of failing with "No model set for the OpenAI-compatible API".
    @Test(arguments: Issue39.openAIWrittenOtherwise)
    func aQuestionGoesToOpenAIWithTheDefaultModel(baseURL: String) async throws {
        Issue39.serve(baseURL)
        let converter = try Issue39.converter(baseURL: baseURL)
        let result = await Issue39.ask(converter.generate(.question, input: "what is a qubit (\(baseURL))"))
        if case let .failure(error) = result {
            #expect(error as? ProviderError != .missingModel(.openai), "\(baseURL): \(Issue39.describe(result))")
        }
        let sent = Issue39.requests(baseURL)
        #expect(!sent.isEmpty, "\(baseURL): nothing was sent; \(Issue39.describe(result))")
        #expect(sent.allSatisfy { Issue39.model($0) == Issue39.defaultModel },
                "\(baseURL): asked for \(sent.map { Issue39.model($0) ?? "no model" })")
        #expect(Issue39.describe(result).contains("qubit"), "\(baseURL): \(Issue39.describe(result))")
    }

    /// The control: `@question` with OpenAI's base URL as the default has it (as today).
    @Test func aQuestionWithTheDefaultBaseURLGoesToOpenAI() async throws {
        let baseURL = "https://api.openai.com/v1"
        Issue39.serve(baseURL)
        let converter = try Issue39.converter(baseURL: baseURL)
        let result = await Issue39.ask(converter.generate(.question, input: "what is a qubit (default)"))
        #expect(Issue39.requests(baseURL).map(Issue39.model) == [Issue39.defaultModel], "\(Issue39.describe(result))")
        #expect(Issue39.describe(result).contains("qubit"), "\(Issue39.describe(result))")
    }
}
