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

    /// A field with `settings`, its requests on `session` (a stub's; else one that answers nothing), the origins a
    /// request succeeded at kept in memory, never in the user's caches (`BedrockClient(session:)`).
    func host(_ settings: Settings, model: WarmingModel = WarmingModel(), clock: Uptime = Uptime(), session: URLSession? = nil,
              converter: Converter? = nil, _ adjust: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        let converter = converter ?? Converter(client: BedrockClient(session: session ?? StubURLProtocol.session()),
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

    /// A converter on the stub's session whose client has seen a request succeed at each of `origins` (as one does,
    /// `ConnectionWarmth.answered`).
    func converter(_ settings: Settings, succeededAt origins: [String]) -> Converter {
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { settings.config })
        for origin in origins { converter.client.bedrock.warmth.succeeded.remember(origin) }
        return converter
    }

    /// `host`'s work's answers handed to its session for `seconds`, whatever they are (a HEAD made ready starts only once
    /// the session has checked again: `InputSession.warmDue`).
    func answer(_ host: FakeHost, for seconds: TimeInterval = 0.1) {
        let deadline = Date().addingTimeInterval(seconds)
        host.settle(timeout: seconds) { Date() >= deadline }
    }

    func settled(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        return condition()
    }

    // MARK: - The on-device model

    /// "@" alone loads nothing (a mention, a sum, an app); "@hello" with Improve highlighted loads it once, and typing on,
    /// the command picked, doesn't again; a minute later, in another field, the next AI command loads it again. The
    /// commands that ask no model (`@note`, `@agent`: the agent has its own) don't.
    @Test func anAICommandLoadsTheOnDeviceModel() async {
        await withInterfaceLanguage("en") {
            let (model, clock, store) = (WarmingModel(), Uptime(), AutocompleteStore())
            let settings = Settings(.apple)
            let first = host(settings, model: model, clock: clock) { $0.autocomplete = store }
            first.press(FakeHost.at)
            Thread.sleep(forTimeInterval: 0.05)
            #expect(model.prewarms == 0, "\"@\" alone asks nothing")
            first.type("hello")
            #expect(first.composer.oneAtRows.first == .write(.improve), "\(first.composer.oneAtRows.map(\.id))")
            #expect(settled { model.prewarms == 1 }, "the highlighted row asks the model")
            first.press(FakeHost.enter)
            #expect(first.composer.isLevelTwo || first.composer.draftCommand == .improve)
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

    /// One @'s highlighted row an AI command ("@hello": Improve), the Claude API at its own address, where a request
    /// succeeded before: one HEAD to its origin, with no key, no credentials, no body, on the requests' own session; none
    /// again while the draft stays one, nor within `ConnectionWarmth.idle` of it.
    @Test func anAICommandOpensTheProvidersConnection() async throws {
        try await withInterfaceLanguage("en") {
            let server = "api.anthropic.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.anthropic)
            let converter = converter(settings, succeededAt: ["https://api.anthropic.com:443"])
            let host = host(settings, session: StubURLProtocol.session(), converter: converter)
            host.type("@hello")
            #expect(host.settle(timeout: 5) { StubURLProtocol.requests(host: server).count == 1 })
            let head = try #require(StubURLProtocol.requests(host: server).first)
            #expect(head.httpMethod == "HEAD" && head.url?.absoluteString == "https://\(server)/", "\(head.url?.absoluteString ?? "")")
            #expect(head.value(forHTTPHeaderField: "x-api-key") == nil && head.value(forHTTPHeaderField: "Authorization") == nil)
            #expect((head.httpBody ?? Data()).isEmpty)
            host.type("i")
            host.press(FakeHost.tab)
            host.type("hello")
            // Another field, its draft an AI command too, on the same session: nothing went there for 90 s yet.
            let next = self.host(settings, session: StubURLProtocol.session(), converter: converter)
            next.type("@hello")
            answer(next)
            #expect(StubURLProtocol.requests(host: server).count == 1, "one an idle period")
        }
    }

    /// Bedrock: its region's endpoint, the region the settings name; without one, the endpoint a request succeeded at
    /// last (nothing of the AWS files or the environment read).
    @Test func bedrocksConnectionIsItsRegions() async {
        await withInterfaceLanguage("en") {
            let (named, last) = ("bedrock-runtime.warm-west-9.amazonaws.com", "bedrock-runtime.warm-north-4.amazonaws.com")
            for server in [named, last] { StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: [])) }
            let settings = Settings(.bedrock)
            settings.config.region = "warm-west-9"
            let origins = ["https://\(named):443", "https://bedrock-runtime.warm-east-3.amazonaws.com:443", "https://\(last):443"]
            let converter = converter(settings, succeededAt: origins)
            let host = host(settings, session: StubURLProtocol.session(), converter: converter)
            host.type("@hello")
            #expect(host.settle(timeout: 5) { StubURLProtocol.requests(host: named).first?.httpMethod == "HEAD" })
            settings.config.region = nil
            let unnamed = self.host(settings, session: StubURLProtocol.session(), converter: converter)
            unnamed.type("@hello")
            #expect(unnamed.settle(timeout: 5) { StubURLProtocol.requests(host: last).first?.httpMethod == "HEAD" })
        }
    }

    /// AllInOneIME Cloud gets no HEAD (it would run the service); nor does any provider in an app with no AI, or during
    /// secure input.
    @Test func noHEADForTheHostedServiceNoAIOrSecureInput() async {
        await withInterfaceLanguage("en") {
            let server = "api.openai.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let hosted = Settings(.hosted)
            let noAI = Settings(.openai)
            noAI.config.appProfiles["com.example.editor"] = AppProfile(noAI: true)
            let secure = Settings(.openai)
            let origins = ["https://api.openai.com:443"] + (HostedService.host.map { ["https://\($0):443"] } ?? [])
            for (settings, secureInput) in [(hosted, false), (noAI, false), (secure, true)] {
                let host = host(settings, session: StubURLProtocol.session(), converter: converter(settings, succeededAt: origins)) {
                    $0.secureInputActive = { secureInput }
                }
                host.press(FakeHost.at)
                host.type("i")
                host.press(FakeHost.tab)
                answer(host)
            }
            #expect(StubURLProtocol.requests(host: server).isEmpty)
            #expect(ConnectionWarmth.headURL(URL(string: HostedService.baseURL)!) == nil)
        }
    }

    /// Translate as You Type turned on with a cloud provider: no HEAD (only an AI command and autocomplete open one).
    @Test func translateAsYouTypeOpensNoConnection() async {
        await withInterfaceLanguage("en") {
            let server = "api.anthropic.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.anthropic)
            let host = host(settings, session: StubURLProtocol.session(),
                            converter: converter(settings, succeededAt: ["https://api.anthropic.com:443"]))
            _ = host.session.apply(host.composer.setTranslateMode(TranslateMode.Session(target: .chinese)))
            answer(host)
            #expect(StubURLProtocol.requests(host: server).isEmpty)
        }
    }

    /// Cloud autocomplete: the field's first key that types opens the connection, before the pause is over.
    @Test func autocompletesFirstKeyOpensTheConnection() async {
        await withInterfaceLanguage("en") {
            let server = "generativelanguage.googleapis.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.gemini)
            settings.config.autocomplete = true
            let host = host(settings, session: StubURLProtocol.session(),
                            converter: converter(settings, succeededAt: ["https://\(server):443"]))
            host.appTypesKeys = true
            host.type("H")
            #expect(host.settle(timeout: 5) { StubURLProtocol.requests(host: server).count == 1 })
            host.type("ello")
            answer(host)
            #expect(StubURLProtocol.requests(host: server).count == 1)
        }
    }

    // MARK: - When a HEAD goes

    /// One @: "@" alone opens nothing, also with ↓ onto an AI command (it is often a mention, a sum, an app); text typed
    /// with an AI row highlighted does, and so does "@" alone on a selection, whose first row is the AI's.
    @Test func oneAtOpensTheConnectionOnlyForTextOrASelection() async {
        await withInterfaceLanguage("en") {
            let server = "api.anthropic.com"
            StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
            let settings = Settings(.anthropic)
            let alone = host(settings, session: StubURLProtocol.session(),
                             converter: converter(settings, succeededAt: ["https://api.anthropic.com:443"]))
            alone.press(FakeHost.at)
            alone.press(FakeHost.down)
            #expect(alone.composer.oneAtRows.contains { InputSession.asksTheModel($0) != nil })
            answer(alone)
            #expect(StubURLProtocol.requests(host: server).isEmpty, "\"@\" alone")
            let selected = host(settings, session: StubURLProtocol.session(),
                                converter: converter(settings, succeededAt: ["https://api.anthropic.com:443"]))
            selected.document = "The report looks good"
            selected.selection = 0..<21
            selected.press(FakeHost.at)
            #expect(selected.settle(timeout: 5) { StubURLProtocol.requests(host: server).count == 1 }, "a selection's AI row")
        }
    }

    /// Only where a real request succeeded before: none for a provider no request went to (Bedrock, the default
    /// provider, for someone who never set it up), none after a request that was refused; after one answered, the next
    /// AI command opens the connection. A base URL of the user's is never one, answered or not.
    @Test func onlyWhereARequestSucceededBefore() async throws {
        func heads(_ host: String) -> Int { StubURLProtocol.requests(host: host).filter { $0.httpMethod == "HEAD" }.count }
        /// An AI command typed in a field of `settings` whose requests `converter` makes (nil: one of its own).
        func typeAnAICommand(_ settings: Settings, converter: Converter? = nil) async {
            await withInterfaceLanguage("en") {
                let field = host(settings, session: StubURLProtocol.session(), converter: converter)
                field.type("@hello")
                answer(field)
            }
        }
        let never = Settings(.bedrock)
        never.config.region = nil
        await typeAnAICommand(never)
        #expect(heads("bedrock-runtime.us-east-1.amazonaws.com") == 0)

        let server = "api.anthropic.com"
        let settings = Settings(.anthropic)
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { settings.config },
                                  loadKey: { _, _ in "sk-ant-test-0000" })
        let refused = StubURLProtocol.Response(status: 401, headers: [:], chunks: [Data(#"{"error":{"message":"invalid x-api-key"}}"#.utf8)])
        StubURLProtocol.register(host: server, [refused])
        do { for try await _ in converter.convert("hello") {} } catch {}
        #expect(!StubURLProtocol.requests(host: server).isEmpty, "the request")
        await typeAnAICommand(settings, converter: converter)
        #expect(heads(server) == 0, "no HEAD after a refusal")

        StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: []))
        do { for try await _ in converter.convert("hello again") {} } catch {}
        #expect(converter.client.bedrock.warmth.succeeded.knows("https://api.anthropic.com:443"))
        // Idle since the request: the next AI command opens the connection.
        let clock = Uptime()
        let later = ConnectionWarmth(succeeded: converter.client.bedrock.warmth.succeeded, now: { clock.now })
        clock.advance(ConnectionWarmth.idle + 1)
        #expect(later.due(try #require(URL(string: "https://api.anthropic.com"))))

        // A relay of the user's, answered: never remembered, never warmed.
        let relay = "warm-relay.example.com"
        StubURLProtocol.register(host: relay, StubURLProtocol.Response(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: []))
        let custom = Settings(.anthropic)
        custom.config.anthropic.baseURL = "https://\(relay)"
        let relayed = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { custom.config },
                                loadKey: { _, _ in "sk-ant-test-0000" })
        do { for try await _ in relayed.convert("hello") {} } catch {}
        #expect(!StubURLProtocol.requests(host: relay).isEmpty)
        #expect(!relayed.client.bedrock.warmth.succeeded.knows("https://\(relay):443"))
        await typeAnAICommand(custom, converter: relayed)
        #expect(heads(relay) == 0, "no HEAD to a base URL of the user's")
    }

    /// Only for a provider at its own default base URL: one of the user's is never warmed, even on another built-in
    /// provider's host where a request succeeded (Anthropic set to OpenAI's address, after an OpenAI success: no HEAD
    /// there, nor to Anthropic's). Its own written with a "/" after it, or its host in capitals, is its own.
    @Test func aCustomBaseURLIsNeverWarmedEvenOnABuiltInHost() async {
        await withInterfaceLanguage("en") {
            func heads(_ host: String) -> Int { StubURLProtocol.requests(host: host).filter { $0.httpMethod == "HEAD" }.count }
            let (openai, anthropic) = ("api.openai.com", "api.anthropic.com")
            for server in [openai, anthropic] { StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: [])) }
            let settings = Settings(.anthropic)
            settings.config.anthropic.baseURL = "https://api.openai.com/v1"
            let converter = converter(settings, succeededAt: ["https://api.openai.com:443", "https://api.anthropic.com:443"])
            let custom = host(settings, session: StubURLProtocol.session(), converter: converter)
            custom.type("@hello")
            answer(custom)
            #expect(heads(openai) == 0 && heads(anthropic) == 0, "\(heads(openai)) \(heads(anthropic))")
            for (base, provider) in [("https://api.openai.com/v1", Provider.anthropic), ("https://api.openai.com", .openai),
                                     ("https://api.anthropic.com/v1", .anthropic), ("https://generativelanguage.googleapis.com", .openai),
                                     ("https://user@api.anthropic.com", .anthropic), ("https://api.anthropic.com:8443", .anthropic)] {
                #expect(!ConnectionWarmth.isDefault(base, for: provider), "\(base) for \(provider)")
            }
            for (base, provider) in [("https://api.anthropic.com", Provider.anthropic), ("https://api.anthropic.com/", .anthropic),
                                     ("HTTPS://API.Anthropic.com", .anthropic), ("https://api.openai.com/v1/", .openai),
                                     ("https://generativelanguage.googleapis.com", .gemini)] {
                #expect(ConnectionWarmth.isDefault(base, for: provider), "\(base) for \(provider)")
            }
            // At its own address again, the same success known: warmed.
            settings.config.anthropic.baseURL = nil
            let own = host(settings, session: StubURLProtocol.session(), converter: converter)
            own.type("@hello")
            #expect(own.settle(timeout: 5) { heads(anthropic) == 1 } && heads(openai) == 0)
        }
    }

    /// Checked again right before the HEAD starts, not only when it is asked for: made ready off the session's thread, it
    /// comes back and goes only if secure input is still off, the app still has AI, and the provider and its base URL are
    /// still the ones it was asked for (in the field it was asked for in). One changed between: no HEAD. Nothing changed:
    /// it goes.
    @Test func checkedAgainRightBeforeTheHEADStarts() async {
        await withInterfaceLanguage("en") {
            let server = "api.anthropic.com"
            func heads() -> Int { StubURLProtocol.requests(host: server).filter { $0.httpMethod == "HEAD" }.count }
            let changes: [(String, (Settings, Locked<Bool>, FakeHost) -> Void)] = [
                ("secure input turned on", { _, secure, _ in secure.withLock { $0 = true } }),
                ("No AI set for the app", { settings, _, _ in settings.config.appProfiles["com.example.editor"] = AppProfile(noAI: true) }),
                ("another provider", { settings, _, _ in settings.config.provider = .openai }),
                ("a base URL of the user's", { settings, _, _ in settings.config.anthropic.baseURL = "https://relay.example.com" }),
                ("another field", { _, _, host in host.send(.blur) }),
                ("nothing", { _, _, _ in }),
            ]
            for (change, make) in changes {
                StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
                let settings = Settings(.anthropic)
                let secure = Locked(initialState: false)
                let host = host(settings, session: StubURLProtocol.session(),
                                converter: converter(settings, succeededAt: ["https://api.anthropic.com:443"])) {
                    $0.secureInputActive = { secure.withLock { $0 } }
                }
                host.type("@hello")
                // Asked for and made ready, not started: the session hasn't heard back yet.
                #expect(host.waitForAnswer(timeout: 5) { if case .task(_, .warmDue) = $0 { true } else { false } }, "\(change)")
                #expect(heads() == 0, "\(change): not before the session checked again")
                make(settings, secure, host)
                if change == "nothing" {
                    #expect(host.settle(timeout: 5) { heads() == 1 }, "\(change)")
                } else {
                    answer(host, for: 0.2)
                    #expect(heads() == 0, "\(change)")
                }
            }
        }
    }

    /// The last check and the HEAD's start are one step: the HEAD is made ready first (its request and its task), then
    /// checked and started at once, nothing scheduled between. A fake that turns secure input on once the HEAD is made
    /// ready, before it would start: no HEAD goes, and the one made ready is cancelled unsent. Nothing turned on: it goes.
    @Test func secureInputOnBetweenTheHEADMadeReadyAndItsStart() async {
        await withInterfaceLanguage("en") {
            let server = "api.anthropic.com"
            func heads() -> Int { StubURLProtocol.requests(host: server).filter { $0.httpMethod == "HEAD" }.count }
            for turnsOn in [true, false] {
                StubURLProtocol.register(host: server, StubURLProtocol.Response(status: 404, headers: [:], chunks: []))
                let settings = Settings(.anthropic)
                let (secure, made) = (Locked(initialState: false), Locked<[URLRequest]>(initialState: []))
                let origins = WarmOrigins(file: nil)
                origins.remember("https://api.anthropic.com:443")
                let warmth = ConnectionWarmth(succeeded: origins, now: { ProcessInfo.processInfo.systemUptime }, prepared: { request in
                    made.withLock { $0.append(request) }
                    if turnsOn { secure.withLock { $0 = true } }
                })
                let converter = Converter(client: BedrockClient(session: StubURLProtocol.session(), warmth: warmth),
                                          loadConfig: { settings.config })
                let host = host(settings, session: StubURLProtocol.session(), converter: converter) {
                    $0.secureInputActive = { secure.withLock { $0 } }
                }
                host.type("@hello")
                if turnsOn {
                    answer(host, for: 0.3)
                    #expect(heads() == 0, "secure input came on before the start")
                } else {
                    #expect(host.settle(timeout: 5) { heads() == 1 }, "nothing changed")
                }
                let ready = made.withLock { $0 }
                #expect(ready.count == 1 && ready.first?.httpMethod == "HEAD" && ready.first?.url?.absoluteString == "https://\(server)/",
                        "made ready once: \(ready.map { $0.url?.absoluteString ?? "" })")
            }
        }
    }

    /// At most one HEAD per origin in 90 s: a request counts as something sent.
    @Test func aHEADGoesOnlyAfterAnIdlePeriod() throws {
        let clock = Uptime()
        let origins = WarmOrigins(file: nil)
        for origin in ["https://api.openai.com:443", "https://api.anthropic.com:443"] { origins.remember(origin) }
        let warmth = ConnectionWarmth(succeeded: origins, now: { clock.now })
        let api = try #require(URL(string: "https://api.openai.com/v1"))
        #expect(warmth.due(api) && !warmth.due(api))
        clock.advance(ConnectionWarmth.idle + 1)
        warmth.sending(to: URL(string: "https://API.openai.com:443/v1/chat/completions"))
        clock.advance(ConnectionWarmth.idle - 1)
        #expect(!warmth.due(api), "a request went 89 s ago")
        clock.advance(2)
        #expect(warmth.due(api))
        // Another service is another connection; none to one no request succeeded at.
        #expect(warmth.due(try #require(URL(string: "https://api.anthropic.com"))))
        #expect(!warmth.due(try #require(URL(string: "https://generativelanguage.googleapis.com"))))
    }

    /// Only to a built-in provider's own host at its default address: the Claude API's, the Gemini API's, OpenAI's,
    /// Bedrock's in a region. Never a base URL of the user's (another service, a relay, another port, a model on this Mac
    /// or the network), never plain http, never the hosted service.
    @Test func aHEADGoesOnlyToABuiltInProvidersOwnHost() throws {
        let custom = ["https://api.deepseek.com", "https://dashscope.aliyuncs.com/compatible-mode/v1", "https://llm.example.com/v1",
                      "https://api.openai.com:8443/v1", "https://api.openai.com.relay.example/v1", "https://relay.example/api.anthropic.com",
                      "http://api.openai.com/v1", "https://localhost:11434/v1", "https://127.0.0.1/v1", "https://192.168.1.20/v1",
                      "https://nas.lan:8443/v1", "https://bedrock-runtime.amazonaws.com", "https://bedrock-runtime..amazonaws.com",
                      "https://xbedrock-runtime.us-east-1.amazonaws.com", "https://bedrock-runtime.us_east.amazonaws.com",
                      "https://bedrock-runtime.us-east-1.amazonaws.com:8443", "https://bedrock.us-east-1.amazonaws.com",
                      HostedService.baseURL + "/v1"]
        let origins = WarmOrigins(file: nil)
        for address in custom {
            let url = try #require(URL(string: address), "\(address)")
            #expect(ConnectionWarmth.headURL(url) == nil, "\(address)")
            if let origin = ConnectionWarmth.origin(url) { origins.remember(origin) }
            #expect(!ConnectionWarmth(succeeded: origins, now: { 0 }).due(url), "\(address): even where a request went")
        }
        for (address, head) in [("https://api.anthropic.com", "https://api.anthropic.com/"),
                                ("https://generativelanguage.googleapis.com", "https://generativelanguage.googleapis.com/"),
                                ("https://api.openai.com/v1", "https://api.openai.com/"), ("https://API.Anthropic.com:443/v1", "https://api.anthropic.com/"),
                                ("https://bedrock-runtime.us-east-1.amazonaws.com", "https://bedrock-runtime.us-east-1.amazonaws.com/")] {
            #expect(ConnectionWarmth.headURL(try #require(URL(string: address)))?.absoluteString == head, "\(address)")
        }
    }

    /// The HEAD goes to the origin alone: no user or password, path or query of the base URL.
    @Test func aHEADGoesToTheOriginAlone() throws {
        let url = try #require(URL(string: "https://user:pass@api.openai.com/v1/chat?key=secret"))
        #expect(ConnectionWarmth.headURL(url)?.absoluteString == "https://api.openai.com/")
    }

    /// Where a request succeeded is kept on this computer, in a file of its own (the app's among its caches): the origin
    /// and the time alone; an origin not succeeded at for 30 days is forgotten. Each test's is in memory or a temporary
    /// folder, never the user's.
    @Test func whereARequestSucceededIsKeptLocally() throws {
        #expect(WarmOrigins.shared.file == CorePaths.cacheDir.appendingPathComponent("warm-origins.json"))
        #expect(BedrockClient(session: StubURLProtocol.session()).warmth.succeeded.file == nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("warm-origins-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("warm-origins.json")
        let day: TimeInterval = 24 * 3600
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let clock = Locked(initialState: start)
        let kept = WarmOrigins(file: file, today: { clock.withLock { $0 } })
        kept.remember("https://api.anthropic.com:443")
        clock.withLock { $0 = start.addingTimeInterval(10 * day) }
        kept.remember("https://bedrock-runtime.us-west-2.amazonaws.com:443")
        let read = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String]
        #expect(Set(read.map { Array($0.keys) } ?? []) == ["https://api.anthropic.com:443", "https://bedrock-runtime.us-west-2.amazonaws.com:443"],
                "\(String(describing: read))")
        #expect(read?.values.allSatisfy { ISO8601DateFormatter().date(from: $0) != nil } == true, "the times alone")
        // Another process, or the next launch, from the file.
        let again = WarmOrigins(file: file, today: { start.addingTimeInterval(29 * day) })
        #expect(again.knows("https://api.anthropic.com:443") && !again.knows("https://api.openai.com:443"))
        #expect(again.latest { $0.contains("bedrock-runtime.") } == "https://bedrock-runtime.us-west-2.amazonaws.com:443")
        let month = WarmOrigins(file: file, today: { start.addingTimeInterval(30 * day + 1) })
        #expect(!month.knows("https://api.anthropic.com:443"), "30 days without a success")
        #expect(month.knows("https://bedrock-runtime.us-west-2.amazonaws.com:443"))
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
