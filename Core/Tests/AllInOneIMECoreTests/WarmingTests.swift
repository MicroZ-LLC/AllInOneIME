import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The model made ready before ⏎ (InputSession+Warming.swift): the on-device model loaded as the draft becomes an AI
/// command or Translate as You Type turns on, a cloud provider's connection opened then (a HEAD with nothing of the
/// user's, `ConnectionWarmth`), and at the first key of a field with cloud autocomplete.
@Suite(.serialized)
struct WarmingTests {
    /// The on-device model, counting the times it was loaded ahead (`AppleGuidedBackend.prewarm`).
    final class WarmingModel: AppleGuidedBackend, @unchecked Sendable {
        let availability = AppleModelAvailability.available
        let contextSize = 4096
        let supportedLanguages = StubAppleModel.languages
        private let lock = NSLock()
        private var count = 0
        var prewarms: Int { lock.withLock { count } }

        func prewarm() { lock.withLock { count += 1 } }
        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String { "{}" }
    }

    final class Settings: @unchecked Sendable {
        var config: Config
        init(_ provider: Provider) {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.english])
            config.setOrder([OutputLanguage.english, .chinese])
            config.provider = provider
        }
    }

    /// A field with `settings`; the provider set up (a key, an AWS profile) unless `setUp` says not.
    func host(_ settings: Settings, model: WarmingModel = WarmingModel(), clock: Uptime = Uptime(), session: URLSession? = nil,
              converter: Converter? = nil, setUp: Bool = true, _ adjust: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        let converter = converter ?? Converter(client: session.map { BedrockClient(session: $0) } ?? BedrockClient(),
                                               loadConfig: { settings.config }, appleModel: model)
        var services = SessionServices(converter: converter, loadSettings: { settings.config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        services.warmsConnections = session != nil
        services.providerSetUp = { _, _ in setUp }
        adjust(&services)
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    func settled(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        return condition()
    }

    // MARK: - The on-device model

    /// "@" with `@improve` highlighted, its name picked, typed on: loaded once; a minute later, in another field, the next
    /// AI command loads it again. The commands that ask no model (`@note`, `@agent`: the agent has its own) don't.
    @Test func anAICommandLoadsTheOnDeviceModel() async {
        await withInterfaceLanguage("en") {
            let (model, clock, store) = (WarmingModel(), Uptime(), AutocompleteStore())
            let settings = Settings(.apple)
            let first = host(settings, model: model, clock: clock) { $0.autocomplete = store }
            first.press(FakeHost.at)
            #expect(first.composer.paletteMatches.first == .improve)
            #expect(settled { model.prewarms == 1 }, "the highlighted row asks the model")
            first.type("i")
            first.press(FakeHost.tab)
            first.type("hello")
            #expect(first.composer.draftCommand == .improve)
            Thread.sleep(forTimeInterval: 0.05)
            #expect(model.prewarms == 1, "once a minute at most")
            clock.advance(61)
            let question = host(settings, model: model, clock: clock) { $0.autocomplete = store }
            question.press(FakeHost.at)
            question.type("question")
            question.press(FakeHost.tab)
            #expect(question.composer.draftCommand == .question)
            #expect(settled { model.prewarms == 2 })
            #expect(!InputSession.asksTheModel(.note) && !InputSession.asksTheModel(.agent) && !InputSession.asksTheModel(.open))
            #expect(InputSession.asksTheModel(.translate) && InputSession.asksTheModel(.reply))
        }
    }

    /// Translate as You Type turned on in a field: the model it translates with loaded.
    @Test func translateAsYouTypeLoadsTheOnDeviceModel() async {
        await withInterfaceLanguage("en") {
            let model = WarmingModel()
            let host = host(Settings(.apple), model: model)
            _ = host.session.apply(host.composer.setTranslateMode(TranslateMode.Session(target: .chinese)))
            #expect(settled { model.prewarms == 1 })
        }
    }

    /// In an app with no AI, and during secure input: nothing loaded (nothing would be asked).
    @Test func noAIAndSecureInputLoadNothing() async {
        await withInterfaceLanguage("en") {
            let settings = Settings(.apple)
            settings.config.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            let model = WarmingModel()
            let host = host(settings, model: model)
            host.press(FakeHost.at)
            host.type("i")
            host.press(FakeHost.tab)
            #expect(host.composer.draftCommand == .improve)
            Thread.sleep(forTimeInterval: 0.05)
            #expect(model.prewarms == 0)
        }
    }

    // MARK: - A cloud provider's connection

    /// The draft an AI command: one HEAD to the provider's origin, with no key, no credentials, no body, on the requests'
    /// own session; none again while the draft stays one, nor within `ConnectionWarmth.idle` of it.
    @Test func anAICommandOpensTheProvidersConnection() async throws {
        try await withInterfaceLanguage("en") {
            let server = "warm-anthropic.example.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.anthropic)
            settings.config.anthropic.baseURL = "https://\(server)"
            let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { settings.config })
            let host = host(settings, session: StubURLProtocol.session(), converter: converter)
            host.press(FakeHost.at)
            #expect(settled { StubURLProtocol.requests(host: server).count == 1 })
            let head = try #require(StubURLProtocol.requests(host: server).first)
            #expect(head.httpMethod == "HEAD" && head.url?.absoluteString == "https://\(server)/", "\(head.url?.absoluteString ?? "")")
            #expect(head.value(forHTTPHeaderField: "x-api-key") == nil && head.value(forHTTPHeaderField: "Authorization") == nil)
            #expect((head.httpBody ?? Data()).isEmpty)
            host.type("i")
            host.press(FakeHost.tab)
            host.type("hello")
            // Another field, its draft an AI command too, on the same session: nothing went there for 90 s yet.
            let next = self.host(settings, session: StubURLProtocol.session(), converter: converter)
            next.press(FakeHost.at)
            Thread.sleep(forTimeInterval: 0.1)
            #expect(StubURLProtocol.requests(host: server).count == 1, "one an idle period")
        }
    }

    /// Bedrock: its region's endpoint, where the settings name the region.
    @Test func bedrocksConnectionIsItsRegions() async {
        await withInterfaceLanguage("en") {
            let server = "bedrock-runtime.warm-west-9.amazonaws.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.bedrock)
            settings.config.region = "warm-west-9"
            let host = host(settings, session: StubURLProtocol.session())
            host.press(FakeHost.at)
            #expect(settled { StubURLProtocol.requests(host: server).first?.httpMethod == "HEAD" })
        }
    }

    /// AllInOneIME Cloud gets no HEAD (it would run the service); nor does any provider in an app with no AI, or during
    /// secure input.
    @Test func noHEADForTheHostedServiceNoAIOrSecureInput() async {
        await withInterfaceLanguage("en") {
            let server = "warm-quiet.example.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let hosted = Settings(.hosted)
            let noAI = Settings(.openai)
            noAI.config.openai.baseURL = "https://\(server)/v1"
            noAI.config.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            let secure = Settings(.openai)
            secure.config.openai.baseURL = "https://\(server)/v1"
            for (settings, secureInput) in [(hosted, false), (noAI, false), (secure, true)] {
                let host = host(settings, session: StubURLProtocol.session()) { $0.secureInputActive = { secureInput } }
                host.press(FakeHost.at)
                host.type("i")
                host.press(FakeHost.tab)
            }
            Thread.sleep(forTimeInterval: 0.1)
            #expect(StubURLProtocol.requests(host: server).isEmpty)
        }
    }

    /// Translate as You Type turned on with a cloud provider: no HEAD (only an AI command and autocomplete open one).
    @Test func translateAsYouTypeOpensNoConnection() async {
        await withInterfaceLanguage("en") {
            let server = "warm-translate.example.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.anthropic)
            settings.config.anthropic.baseURL = "https://\(server)"
            let host = host(settings, session: StubURLProtocol.session())
            _ = host.session.apply(host.composer.setTranslateMode(TranslateMode.Session(target: .chinese)))
            Thread.sleep(forTimeInterval: 0.1)
            #expect(StubURLProtocol.requests(host: server).isEmpty)
        }
    }

    /// Cloud autocomplete: the field's first key that types opens the connection, before the pause is over.
    @Test func autocompletesFirstKeyOpensTheConnection() async {
        await withInterfaceLanguage("en") {
            let server = "warm-gemini.example.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.gemini)
            settings.config.gemini.baseURL = "https://\(server)"
            settings.config.autocomplete = true
            let host = host(settings, session: StubURLProtocol.session())
            host.appTypesKeys = true
            host.type("H")
            #expect(settled { StubURLProtocol.requests(host: server).count == 1 })
            host.type("ello")
            Thread.sleep(forTimeInterval: 0.1)
            #expect(StubURLProtocol.requests(host: server).count == 1)
        }
    }

    // MARK: - When a HEAD goes

    /// A provider that isn't set up (no key, no AWS profile or keys) gets no HEAD: Bedrock, the default provider, for
    /// someone who never set it up.
    @Test func aProviderNotSetUpGetsNoHEAD() async throws {
        try await withInterfaceLanguage("en") {
            let server = "bedrock-runtime.warm-east-7.amazonaws.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.bedrock)
            settings.config.region = "warm-east-7"
            let host = host(settings, session: StubURLProtocol.session(), setUp: false)
            host.press(FakeHost.at)
            Thread.sleep(forTimeInterval: 0.1)
            #expect(StubURLProtocol.requests(host: server).isEmpty)
            // Set up: the AWS keys in the environment, or the profile in the AWS files.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("warm-aws-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let config = folder.appendingPathComponent("config")
            try "[profile work]\nregion = eu-west-1\n".write(to: config, atomically: true, encoding: .utf8)
            var work = settings.config
            work.awsProfile = "work"
            let files = ["AWS_CONFIG_FILE": config.path, "AWS_SHARED_CREDENTIALS_FILE": folder.appendingPathComponent("none").path]
            #expect(ConnectionWarmth.isSetUp(.bedrock, config: work, environment: files))
            #expect(!ConnectionWarmth.isSetUp(.bedrock, config: settings.config, environment: files), "no profile \"default\"")
            #expect(ConnectionWarmth.isSetUp(.bedrock, config: settings.config,
                                             environment: ["AWS_ACCESS_KEY_ID": "AKIAEXAMPLE", "AWS_SECRET_ACCESS_KEY": "x"]))
            #expect(!ConnectionWarmth.isSetUp(.hosted, config: settings.config) && !ConnectionWarmth.isSetUp(.apple, config: settings.config))
        }
    }

    /// Only to an https address on the internet nothing went to in the last 90 s: a request counts as something sent.
    @Test func aHEADGoesOnlyAfterAnIdlePeriod() throws {
        let clock = Uptime()
        let warmth = ConnectionWarmth(now: { clock.now })
        let api = try #require(URL(string: "https://api.example.com/v1"))
        #expect(warmth.due(api) && !warmth.due(api))
        clock.advance(ConnectionWarmth.idle + 1)
        warmth.sending(to: URL(string: "https://API.example.com:443/v1/chat/completions"))
        clock.advance(ConnectionWarmth.idle - 1)
        #expect(!warmth.due(api), "a request went 89 s ago")
        clock.advance(2)
        #expect(warmth.due(api))
        // Another service is another connection; none to this Mac, the local network, or over http.
        #expect(warmth.due(try #require(URL(string: "https://api.other.example.com"))))
        for local in ["https://localhost:11434/v1", "https://192.168.1.20/v1", "http://api.example.org"] {
            #expect(!warmth.due(try #require(URL(string: local))), "\(local)")
        }
    }

    /// Never this Mac, the local network or a VPN's names, in any spelling: an IP address, a name of one label, a
    /// private-use name; nor the hosted service by its host.
    @Test func aHEADGoesOnlyToAHostOnTheInternet() throws {
        let local = ["https://nas.lan:8443/v1", "https://mac-mini.tail1234.ts.net/v1", "https://100.64.0.7/v1", "https://100.101.102.103",
                     "https://myserver/v1", "https://router.home.arpa/v1", "https://0.0.0.0/v1", "https://[::ffff:127.0.0.1]/v1",
                     "https://127.1/v1", "https://localhost./v1", "https://LOCALHOST:8080", "https://foo.localhost/v1",
                     "https://user:pass@proxy/v1", "https://box.local/v1", "https://llm.internal/v1", "https://2130706433/v1",
                     "https://0x7f000001/v1", "https://[::1]:11434/v1", "https://[fd00::1]/v1", "https://api.test/v1",
                     HostedService.baseURL + "/v1"]
        for address in local {
            let url = try #require(URL(string: address), "\(address)")
            #expect(ConnectionWarmth.headURL(url) == nil, "\(address)")
            #expect(!ConnectionWarmth(now: { 0 }).due(url), "\(address)")
        }
        for address in ["https://api.openai.com/v1", "https://api.deepseek.com", "https://dashscope.aliyuncs.com/compatible-mode/v1",
                        "https://bedrock-runtime.us-east-1.amazonaws.com"] {
            #expect(ConnectionWarmth.headURL(try #require(URL(string: address))) != nil, "\(address)")
        }
    }

    /// The HEAD goes to the origin alone: no user or password, path or query of the base URL.
    @Test func aHEADGoesToTheOriginAlone() throws {
        let url = try #require(URL(string: "https://user:pass@llm.example.com:8443/v1/chat?key=secret"))
        #expect(ConnectionWarmth.headURL(url)?.absoluteString == "https://llm.example.com:8443/")
        #expect(ConnectionWarmth.headURL(try #require(URL(string: "https://API.Example.com/v1")))?.absoluteString == "https://api.example.com/")
    }

    #if canImport(Darwin)
    /// A server asking the HEAD to authenticate (Basic, a client certificate): refused, never answered with a credential
    /// the system keeps; the server's certificate is still checked as usual. Other requests leave it to the system.
    @Test func aHEADRefusesEveryAuthentication() throws {
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: try #require(URL(string: "https://warm-auth.example.com/")))
        func disposition(_ method: String, refusing: Bool) -> URLSession.AuthChallengeDisposition? {
            let space = URLProtectionSpace(host: "warm-auth.example.com", port: 443, protocol: "https", realm: "relay",
                                           authenticationMethod: method)
            let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
                                                       failureResponse: nil, error: nil, sender: Sender())
            let told = Locked<URLSession.AuthChallengeDisposition?>(initialState: nil)
            HTTPStream.Receiver(redirect: nil, refusesAuthentication: refusing)
                .urlSession(session, task: task, didReceive: challenge) { answer, _ in told.withLock { $0 = answer } }
            return told.withLock { $0 }
        }
        for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM,
                       NSURLAuthenticationMethodClientCertificate, NSURLAuthenticationMethodDefault] {
            #expect(disposition(method, refusing: true) == .cancelAuthenticationChallenge, "\(method)")
            #expect(disposition(method, refusing: false) == .performDefaultHandling, "\(method)")
        }
        #expect(disposition(NSURLAuthenticationMethodServerTrust, refusing: true) == .performDefaultHandling)
        task.cancel()
    }

    final class Sender: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
    }
    #endif
}
