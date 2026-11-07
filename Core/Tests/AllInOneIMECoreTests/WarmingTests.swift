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

    func host(_ settings: Settings, model: WarmingModel = WarmingModel(), clock: Uptime = Uptime(), session: URLSession? = nil,
              converter: Converter? = nil, _ adjust: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        let converter = converter ?? Converter(client: session.map { BedrockClient(session: $0) } ?? BedrockClient(),
                                               loadConfig: { settings.config }, appleModel: model)
        var services = SessionServices(converter: converter, loadSettings: { settings.config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        services.warmsConnections = session != nil
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

    /// The draft an AI command: one HEAD to the provider's base URL, with no key, no credentials, no body, on the requests'
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
            #expect(head.httpMethod == "HEAD" && head.url?.absoluteString == "https://\(server)")
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
            #expect(!ConnectionWarmth(now: { 0 }).due(url), "\(address)")
        }
        for address in ["https://api.openai.com/v1", "https://api.deepseek.com", "https://dashscope.aliyuncs.com/compatible-mode/v1",
                        "https://bedrock-runtime.us-east-1.amazonaws.com"] {
            #expect(ConnectionWarmth(now: { 0 }).due(try #require(URL(string: address))), "\(address)")
        }
    }

}
