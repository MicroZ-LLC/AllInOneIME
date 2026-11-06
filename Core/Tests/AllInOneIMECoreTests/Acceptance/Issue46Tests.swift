import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #46: a base URL typed without its scheme (api.deepseek.com/v1) is reported as what it is, "Invalid base URL:
/// api.deepseek.com/v1", straight away. It was taken for a key problem: with no host, the key was looked up for "" and
/// the one saved for api.openai.com (or $OPENAI_API_KEY) was refused for it, so the user was told to save the key
/// again, and only once they did saw the base URL was wrong. Through Test Connection (`SettingsStore.testConnection`)
/// and a conversion (`Converter`, as a command runs it), with the key saved the way Settings saves it, in memory
/// (`MemorySecrets`): the user's keychain and shell are never read.
@Suite(.serialized)
struct Issue46Tests {
    let typed = "api.deepseek.com/v1"

    /// A Settings store on a config file of its own, set to the OpenAI-compatible provider with a model.
    func store() throws -> (SettingsStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue46-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = SettingsStore(configURL: folder.appendingPathComponent("config.json"))
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .openai
        config.openai.model = "deepseek-chat"
        config.rewriteStyles = []
        store.config = config
        return (store, folder)
    }

    /// What Test Connection shows for `config`, in English.
    func testConnection(_ config: Config) async -> SettingsStore.TestStatus {
        await UIText.$scopedLanguage.withValue("en") {
            await SettingsStore.testConnection(config, loadCredentials: { _ in
                throw BedrockError.invalidResponse("no AWS credentials in this test")
            })
        }
    }

    /// The issue's trigger: an OpenAI key saved with the default base URL, then the base URL changed to one without
    /// https://. Test Connection says the base URL is invalid, and nothing about the key.
    @Test(MemorySecrets()) func testConnectionSaysTheBaseURLIsInvalidNotToSaveTheKeyAgain() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(store.saveKey("sk-test-issue46-openai-0001", for: .openai) == nil)
        store.setProviderField(.openai, \.baseURL, to: typed)
        #expect(store.config.openai.baseURL == typed)

        let status = await testConnection(store.config)
        #expect(status == .failed("Invalid base URL: \(typed)"), "\(status)")
    }

    /// The same through a conversion (a command's request): `ProviderError.invalidBaseURL` with the URL as typed, not
    /// `keyForAnotherHost`.
    @Test(MemorySecrets()) func aCommandSaysTheBaseURLIsInvalidWithAKeySavedForAnotherHost() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(store.saveKey("sk-test-issue46-openai-0002", for: .openai) == nil)
        store.setProviderField(.openai, \.baseURL, to: typed)
        let config = store.config
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { config })
        await #expect(throws: ProviderError.invalidBaseURL(typed)) {
            for try await _ in converter.convert("你好") {}
        }
    }

    /// No key saved, the one in the login shell ($OPENAI_API_KEY): the base URL is invalid, not "$OPENAI_API_KEY is
    /// sent only to api.openai.com".
    @Test(MemorySecrets(environment: ["OPENAI_API_KEY": "sk-proj-shell-issue46-a1b2"]))
    func aShellKeyIsNotBlamedForABaseURLWithoutAScheme() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.setProviderField(.openai, \.baseURL, to: typed)
        let config = store.config
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { config })
        await #expect(throws: ProviderError.invalidBaseURL(typed)) {
            for try await _ in converter.convert("你好") {}
        }
        let status = await testConnection(config)
        #expect(status == .failed("Invalid base URL: \(typed)"), "\(status)")
    }

    /// Whatever the key lookup would say about the host (here: saved for another), a base URL with no host is invalid:
    /// the issue's own test, on the request itself, for each provider with a base URL of its own.
    @Test func theRequestSaysTheBaseURLIsInvalidWhateverTheKeyLookupSays() async throws {
        let cases: [(Provider, String, String)] = [
            (.openai, "api.example.com/v1", "gpt-test"),
            (.openai, typed, "deepseek-chat"),
            (.anthropic, "api.anthropic.example", "claude-test"),
            (.gemini, "generativelanguage.example/v1beta", "gemini-test"),
        ]
        for (provider, base, model) in cases {
            var config = Config.default
            config.provider = provider
            switch provider {
            case .anthropic: config.anthropic.baseURL = base; config.anthropic.model = model
            case .gemini: config.gemini.baseURL = base; config.gemini.model = model
            default: config.openai.baseURL = base; config.openai.model = model
            }
            let body = ConverseRequest(system: [.init("Answer briefly")], messages: [.init(role: "user", text: "Hi")],
                                       inferenceConfig: .init(maxTokens: 64))
            let stream = ChatClient(bedrock: BedrockClient(session: StubURLProtocol.session()))
                .stream(body, config: config, loadCredentials: { _ in throw BedrockError.invalidResponse("not Bedrock") },
                        loadKey: { provider, _ in throw ProviderError.keyForAnotherHost(provider, saved: provider.ownHost) })
            await #expect(throws: ProviderError.invalidBaseURL(base), "\(provider) \(base)") {
                for try await _ in stream {}
            }
        }
    }
}
