import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The model made ready before ⏎ (InputSession+Warming.swift): the on-device model loaded as the draft becomes an AI
/// command or Translate as You Type turns on.
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
}
