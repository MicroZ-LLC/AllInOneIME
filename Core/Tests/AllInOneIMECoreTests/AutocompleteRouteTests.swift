import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The model a pause asks, as the session goes by it: with a CLI chosen as the AI, its fast fallback (`Config.fastProvider`,
/// `InputSession.autocompleteRoute`), never the provider as it is; with neither a ready provider nor Apple's model,
/// autocomplete is off: nothing read, nothing asked. AllInOneIME Cloud is never asked, whatever else can't answer.
@Suite(.serialized)
struct AutocompleteRouteTests {
    /// A field with autocomplete on and `change` made to the settings; the provider's key `key` (nil: none), the on-device
    /// model `model`; cloud providers are stubs (`StubURLProtocol`), so nothing goes out.
    func field(model: ContinuingModel, key: String?, _ change: (inout Config) -> Void) -> (host: FakeHost, clock: Uptime) {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.autocomplete = true
        change(&config)
        let fixed = config
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed },
                                  loadCredentials: { _ in throw ProviderError.missingKey(.bedrock) },
                                  loadKey: { _, _ in key }, loadJargon: { _ in [] }, appleModel: model,
                                  hasAWSProfile: { _ in false })
        let clock = Uptime()
        var services = SessionServices(converter: converter, loadSettings: { fixed })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        let host = FakeHost(services: services)
        host.appTypesKeys = true
        host.focus()
        return (host, clock)
    }

    /// The pause over, and whatever it started done.
    func pauseEnds(_ host: FakeHost, _ clock: Uptime) {
        clock.advance(2)
        host.fireTimers { if case .autocomplete = $0 { true } else { false } }
        host.settle(timeout: 5) { host.session.autocomplete.reading == nil && host.session.autocomplete.asked == nil }
    }

    /// The fast fallback looked up (a CLI chosen), as it is a moment after the field takes the focus.
    func routeLookedUp(_ host: FakeHost) {
        _ = host.settle(timeout: 0.5) { false }
    }

    func pauses(_ host: FakeHost) -> [TimeInterval] {
        host.timerDelays.compactMap { if case .autocomplete = $0.key { $0.value } else { nil } }
    }

    /// A CLI chosen, the provider set up before it without a key, Apple's model not available: no faster AI, so
    /// autocomplete is off (Settings says so under the CLI). Nothing is read of the field, nothing asked.
    @Test func aCLIWithNoFasterAIReadsAndAsksNothing() async {
        await withInterfaceLanguage("en") {
            let model = ContinuingModel(.appleIntelligenceNotEnabled) { _ in " tomorrow." }
            let (host, clock) = field(model: model, key: nil) {
                $0.provider = .anthropic
                $0.questionBackend = .claudeSession
            }
            routeLookedUp(host)
            host.type("See you")
            pauseEnds(host, clock)
            #expect(host.fieldReads == 0 && model.requests.isEmpty && host.ghost == nil)
            #expect(pauses(host).isEmpty, "no pause started")
        }
    }

    /// A CLI chosen, the provider without a key, Apple's model available: the fast fallback is the on-device model, so the
    /// pause is its (not a cloud provider's), and it answers.
    @Test func aCLIWithAppleAsTheFasterAIGoesByTheOnDeviceModel() async {
        await withInterfaceLanguage("en") {
            let model = ContinuingModel { _ in " tomorrow at noon." }
            let (host, clock) = field(model: model, key: nil) {
                $0.provider = .anthropic
                $0.questionBackend = .claudeSession
            }
            routeLookedUp(host)
            host.type("See you")
            #expect(Set(pauses(host)) == [Autocomplete.Route.onDevice.pause], "each key's pause the on-device model's")
            pauseEnds(host, clock)
            #expect(host.ghost == " tomorrow at noon." && model.requests.count == 1)
        }
    }

    /// A CLI chosen and its fallback a provider with a key: that provider, as with it chosen.
    @Test func aCLIWithAReadyProviderAsksIt() async {
        await withInterfaceLanguage("en") {
            let model = ContinuingModel(.appleIntelligenceNotEnabled)
            let (host, _) = field(model: model, key: "test-key") {
                $0.provider = .anthropic
                $0.questionBackend = .claudeSession
            }
            routeLookedUp(host)
            host.type("See you")
            #expect(Set(pauses(host)) == [Autocomplete.Route.cloud(.anthropic).pause])
        }
    }

    /// AllInOneIME Cloud picked and Apple's model not available: nothing is read or asked, and nothing goes to the hosted
    /// service (README's Privacy: autocomplete never goes there).
    @Test func cloudPickedWithNoOnDeviceModelSendsNothing() async {
        await withInterfaceLanguage("en") {
            let model = ContinuingModel(.appleIntelligenceNotEnabled) { _ in " tomorrow." }
            let (host, clock) = field(model: model, key: "token") { $0.provider = .hosted }
            host.type("See you")
            pauseEnds(host, clock)
            #expect(host.fieldReads == 0 && model.requests.isEmpty)
            #expect(StubURLProtocol.requests(host: HostedService.host ?? "").isEmpty)
        }
    }

    /// A CLI chosen with AllInOneIME Cloud signed in as its fallback, Apple's model not available: the fallback for
    /// autocomplete is the on-device model (never the hosted service), which can't run: nothing goes out.
    @Test func aCLIWithCloudAsTheFallbackNeverSendsAutocompleteThere() async throws {
        await withInterfaceLanguage("en") {
            let model = ContinuingModel(.appleIntelligenceNotEnabled) { _ in " tomorrow." }
            let (host, clock) = field(model: model, key: "token") {
                $0.provider = .hosted
                $0.questionBackend = .claudeSession
            }
            routeLookedUp(host)
            host.type("See you")
            pauseEnds(host, clock)
            #expect(host.fieldReads == 0 && model.requests.isEmpty)
            #expect(StubURLProtocol.requests(host: HostedService.host ?? "").isEmpty)
        }
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()),
                                  loadConfig: {
                                      var config = Config.default
                                      config.provider = .hosted
                                      config.questionBackend = .claudeSession
                                      return config
                                  },
                                  loadKey: { _, _ in "token" }, loadJargon: { _ in [] },
                                  appleModel: ContinuingModel(.appleIntelligenceNotEnabled))
        await #expect(throws: AppleModelError.unavailable(.appleIntelligenceNotEnabled)) {
            _ = try await converter.autocomplete(Autocomplete.Context(before: "See you"), app: nil)
        }
        #expect(StubURLProtocol.requests(host: HostedService.host ?? "").isEmpty)
    }

    /// No pause, read or request without a key that typed: a field taking the focus, the settings taken again, time going
    /// by with no key.
    @Test func nothingIsAskedWithoutTyping() async {
        await withInterfaceLanguage("en") {
            let model = ContinuingModel { _ in " tomorrow." }
            let (host, clock) = field(model: model, key: nil) { $0.provider = .apple }
            host.document = "See you"
            host.focus()
            _ = host.session.applySettings()
            clock.advance(10)
            host.fireTimers()
            _ = host.settle(timeout: 1) { false }
            #expect(host.fieldReads == 0 && model.requests.isEmpty && pauses(host).isEmpty)
        }
    }
}
