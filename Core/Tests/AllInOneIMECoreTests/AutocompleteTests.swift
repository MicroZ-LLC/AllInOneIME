import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Stands in for the on-device model in autocomplete's tests: answers each request with what `answer` gives for its
/// prompt (the whole answer at once), or waits for the test (`hold`, then `release`); records the requests.
final class ContinuingModel: AppleModelBackend, @unchecked Sendable {
    let availability: AppleModelAvailability
    let contextSize = 4096
    let supportedLanguages = StubAppleModel.languages
    private let lock = NSLock()
    private var _requests: [AppleModelRequest] = []
    private var held: [AsyncThrowingStream<AppleModelSnapshot, Error>.Continuation] = []
    private var terminated = 0
    var answer: @Sendable (String) -> String
    var hold = false

    init(_ availability: AppleModelAvailability = .available, answer: @escaping @Sendable (String) -> String = { _ in "" }) {
        self.availability = availability
        self.answer = answer
    }

    var requests: [AppleModelRequest] { lock.withLock { _requests } }
    var waiting: Int { lock.withLock { held.count } }
    var stopped: Int { lock.withLock { terminated } }
    func isWaiting() -> Bool { waiting == 1 }
    func wasStopped() -> Bool { stopped == 1 }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        lock.withLock { _requests.append(request) }
        let text = answer(request.prompt)
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.lock.withLock { self?.terminated += 1 } }
            if lock.withLock({ hold }) {
                lock.withLock { held.append(continuation) }
                return
            }
            continuation.yield(AppleModelSnapshot(text: text))
            continuation.finish()
        }
    }

    /// The held requests answered with `text`.
    func release(_ text: String) {
        let waiting = lock.withLock { () -> [AsyncThrowingStream<AppleModelSnapshot, Error>.Continuation] in
            defer { held = [] }
            return held
        }
        for continuation in waiting {
            continuation.yield(AppleModelSnapshot(text: text))
            continuation.finish()
        }
    }
}

extension AutocompleteStore {
    func hasLate() -> Bool { metrics.late == 1 }
}

/// The session's time (`SessionServices.uptime`), moved by the test.
final class Uptime: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 1000
    var now: TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

@Suite(.serialized)
struct AutocompleteTests {
    // MARK: - What is shown

    @Test func aSuggestionEndsWithItsSentence() {
        #expect(Autocomplete.trimmed("ld, how are you? I hope all is well.", before: "Hello wor") == "ld, how are you?")
        #expect(Autocomplete.trimmed(" see you tomorrow. Bye", before: "OK,") == " see you tomorrow.")
        #expect(Autocomplete.trimmed("今天下午三点开会。然后吃饭", before: "我们") == "今天下午三点开会。")
        // A decimal point or an abbreviation's dot inside isn't a sentence's end.
        #expect(Autocomplete.trimmed(" version 3.5 of the app", before: "We shipped") == " version 3.5 of the app")
        // Closing quotes stay with the sentence.
        #expect(Autocomplete.trimmed(" said “no.” Then", before: "She") == " said “no.”")
    }

    @Test func aSuggestionIsADozenWordsOr25ChineseCharactersAtMost() {
        let long = " one two three four five six seven eight nine ten eleven twelve thirteen fourteen"
        #expect(Autocomplete.trimmed(long, before: "Count:") == " one two three four five six seven eight nine ten eleven twelve")
        let chinese = String(repeating: "很", count: 40)
        #expect(Autocomplete.trimmed(chinese, before: "今天") == String(repeating: "很", count: 25))
    }

    @Test func aSuggestionIsOneLineWithoutQuotesOrTheTextAgain() {
        #expect(Autocomplete.trimmed("\"the meeting at noon\"", before: "Let's move ") == "the meeting at noon")
        #expect(Autocomplete.trimmed("<continuation> at noon</continuation>", before: "Lunch") == " at noon")
        #expect(Autocomplete.trimmed("\n\nfirst line\nsecond line", before: "A ") == "first line")
        // The model said the end of the text again: only what follows.
        #expect(Autocomplete.trimmed("move the meeting to Friday", before: "I think we should move the meeting") == " to Friday")
        // A small model's answer in the request's tags, without the space before a new word, or with the text again.
        #expect(Autocomplete.trimmed("<after>day.</after>", before: "by the end of the ") == "day.")
        #expect(Autocomplete.trimmed("<after>file?</after>", before: "Can you send me the") == " file?")
        #expect(Autocomplete.trimmed("<after>ld</after>", before: "Hello wor") == "ld")
        #expect(Autocomplete.trimmed("<after>今天天气很好，我们去公园散步吧</after>", before: "今天天气很好，我们") == "去公园散步吧")
        // After a space (or CJK, or a line's start) no space of its own.
        #expect(Autocomplete.trimmed("   tomorrow", before: "See you ") == "tomorrow")
        #expect(Autocomplete.trimmed(" 明天见", before: "好的，") == "明天见")
        // Nothing worth showing.
        #expect(Autocomplete.trimmed("", before: "Hi") == nil)
        #expect(Autocomplete.trimmed("  ...  ", before: "Hi") == nil)
        #expect(Autocomplete.trimmed("\n\n", before: "Hi") == nil)
    }

    @Test func aCloudProvidersTokensAreTold() throws {
        let start = try HTTPProviders.events(fromData: #"{"type":"message_start","message":{"id":"m","usage":{"input_tokens":120}}}"#,
                                             provider: .anthropic)
        #expect(start == [.metadata(latencyMs: nil, inputTokens: 120, outputTokens: nil)])
        let end = try HTTPProviders.events(fromData: #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}"#,
                                           provider: .anthropic)
        #expect(end == [.metadata(latencyMs: nil, inputTokens: nil, outputTokens: 7), .messageStop(reason: "end_turn")])
        let openai = try HTTPProviders.events(fromData: #"{"choices":[],"usage":{"prompt_tokens":90,"completion_tokens":5}}"#, provider: .openai)
        #expect(openai == [.metadata(latencyMs: nil, inputTokens: 90, outputTokens: 5)])
        let gemini = try HTTPProviders.events(fromData: #"{"candidates":[{"content":{"parts":[{"text":"Hi"}]}}],"usageMetadata":{"promptTokenCount":80,"candidatesTokenCount":2}}"#,
                                              provider: .gemini)
        #expect(gemini == [.textDelta("Hi"), .metadata(latencyMs: nil, inputTokens: 80, outputTokens: 2)])
    }

    @Test func theRequestStopsReadingOnceItHasASuggestion() {
        #expect(!Autocomplete.isEnough(" and then"))
        #expect(Autocomplete.isEnough(" and then we left. Later"))
        #expect(Autocomplete.isEnough(" and then\nmore"))
        #expect(Autocomplete.isEnough(" a b c d e f g h i j k l m n"))
        #expect(Autocomplete.isEnough("然后我们去吃饭。"))
    }

    // MARK: - What is sent

    @Test func onlyAtTheEndOfALineWithNothingSelected() {
        #expect(Autocomplete.context(FieldText(before: "Hello wor", after: "")) == Autocomplete.Context(before: "Hello wor"))
        #expect(Autocomplete.context(FieldText(before: "Hello wor", after: "  \nnext line")) == Autocomplete.Context(before: "Hello wor", after: "  \nnext line"))
        #expect(Autocomplete.context(FieldText(before: "Hello ", after: "world")) == nil)
        #expect(Autocomplete.context(FieldText(before: "Hello", after: ""), selection: 2..<4) == nil)
        #expect(Autocomplete.context(FieldText(before: "Hello", after: ""), selection: 5..<5) != nil)
        // Two characters on the line at least; not a code or a card's number.
        #expect(Autocomplete.context(FieldText(before: "Long line\nH", after: "")) == nil)
        #expect(Autocomplete.context(FieldText(before: "Code: \n4921 8812", after: "")) == nil)
        #expect(Autocomplete.context(FieldText(before: "Room 4921 is", after: "")) != nil)
        // The field tells nothing: what was typed into it stands in.
        #expect(Autocomplete.context(nil, typed: "我们明天") == Autocomplete.Context(before: "我们明天"))
        #expect(Autocomplete.context(nil, typed: "") == nil)
    }

    @Test func atMost1500CharactersBeforeAnd200After() {
        let before = String(repeating: "a", count: 2000) + "end"
        let after = "\n" + String(repeating: "b", count: 500)
        let context = Autocomplete.context(FieldText(before: before, after: after))
        #expect(context?.before.count == 1500 && context?.before.hasSuffix("end") == true)
        #expect(context?.after.count == 200)
    }

    @Test func theRequestSaysWhereItIsTyped() {
        let chat = Prompt.autocompleteRequest(Autocomplete.Context(before: "Hi Bob, can you"), app: "com.tinyspeck.slackmacgap")
        #expect(chat.system[0].text.contains("a chat message") && chat.messages[0].content[0].text == "<before>Hi Bob, can you</before>")
        #expect(chat.inferenceConfig.maxTokens == Autocomplete.maxTokens)
        let mail = Prompt.autocompleteRequest(Autocomplete.Context(before: "Dear Ann", after: "\nBest"), app: "com.apple.mail")
        #expect(mail.system[0].text.contains("an email") && mail.messages[0].content[0].text.hasSuffix("<after>\nBest</after>"))
    }

    // MARK: - The model

    @Test func theOnDeviceModelUnlessTheUserAgreedToTheirCloudProvider() {
        var config = Config.default  // Bedrock
        #expect(Autocomplete.route(config) == .onDevice && Autocomplete.asksForCloud(config))
        config.autocompleteCloud = false
        #expect(Autocomplete.route(config) == .onDevice && !Autocomplete.asksForCloud(config))
        config.autocompleteCloud = true
        #expect(Autocomplete.route(config) == .cloud(.bedrock))
        config.provider = .apple
        config.autocompleteCloud = nil
        #expect(Autocomplete.route(config) == .onDevice && !Autocomplete.asksForCloud(config))
        #expect(Autocomplete.Route.onDevice.pause == 0.15 && Autocomplete.Route.cloud(.anthropic).pause == 0.35)
    }

    @Test func theSwitchAndTheConsentAreKeptOnlyOnceSet() throws {
        let plain = String(decoding: try JSONEncoder().encode(Config.default), as: UTF8.self)
        #expect(!plain.contains("autocomplete"))
        var config = Config.default
        config.autocomplete = true
        config.autocompleteCloud = false
        config.appProfiles = ["com.example.app": AppProfile(autocomplete: false)]
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(back.autocomplete && back.autocompleteCloud == false && back.profile(for: "com.example.app")?.autocomplete == false)
        #expect(!AppProfile(autocomplete: false).isEmpty)
        // A value of the wrong type reads as none.
        let odd = try JSONDecoder().decode(Config.self, from: Data(#"{"autocomplete": "yes", "autocompleteCloud": "no"}"#.utf8))
        #expect(!odd.autocomplete && odd.autocompleteCloud == nil)
        #expect(ICloudSync.neverSynced.contains("autocompleteCloud"))
    }

    @Test func theConverterAsksTheOnDeviceModelAndNeverTheCloudInItsPlace() async throws {
        let model = ContinuingModel { _ in " tomorrow at noon. And more" }
        var config = Config.default
        config.provider = .anthropic  // a cloud provider, not agreed to
        let fixed = config
        let keyAsked = Locked(initialState: false)
        let converter = Converter(loadConfig: { fixed }, loadKey: { _, _ in keyAsked.withLock { $0 = true }; return "k" }, appleModel: model)
        let answer = try await converter.autocomplete(Autocomplete.Context(before: "See you"), app: nil)
        #expect(answer.text == " tomorrow at noon." && answer.route == .onDevice && answer.before == "See you")
        #expect(model.requests.first?.maximumResponseTokens == Autocomplete.maxTokens)
        #expect(model.requests.first?.prompt == "<before>See you</before>")
        // Unavailable: an error, and still no key asked for.
        let off = Converter(loadConfig: { fixed }, loadKey: { _, _ in keyAsked.withLock { $0 = true }; return "k" },
                            appleModel: ContinuingModel(.appleIntelligenceNotEnabled))
        await #expect(throws: AppleModelError.unavailable(.appleIntelligenceNotEnabled)) {
            _ = try await off.autocomplete(Autocomplete.Context(before: "See you"), app: nil)
        }
        #expect(!keyAsked.withLock { $0 })
    }

    @Test func theConverterHidesValuesAndPutsThemBack() async throws {
        let model = ContinuingModel { prompt in
            prompt.contains("[EMAIL_1]") ? " [EMAIL_1] by Friday." : " nowhere."
        }
        var config = Config.default
        config.provider = .apple
        config.redaction = RedactionSettings(enabled: true)
        let fixed = config
        let converter = Converter(loadConfig: { fixed }, appleModel: model)
        let answer = try await converter.autocomplete(Autocomplete.Context(before: "Write to ann@example.com or to"), app: nil)
        #expect(model.requests.first?.prompt.contains("ann@example.com") == false)
        #expect(answer.text == " ann@example.com by Friday.")
    }

    @Test func aCloudProviderTheUserAgreedToGetsTheRequest() async throws {
        let host = "autocomplete-cloud.test"
        let events = [
            #"data: {"choices":[{"index":0,"delta":{"content":" at the"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"index":0,"delta":{"content":" station. Then"},"finish_reason":null}]}"#,
            "data: [DONE]",
        ].map { Data(($0 + "\n\n").utf8) }
        StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: events))
        var config = Config.default
        config.provider = .openai
        config.openai = ProviderSettings(model: "small", baseURL: "https://\(host)/v1")
        config.autocompleteCloud = true
        let fixed = config
        let model = ContinuingModel { _ in " never asked." }
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed },
                                  loadKey: { _, _ in "test-key" }, appleModel: model)
        let answer = try await converter.autocomplete(Autocomplete.Context(before: "Meet me"), app: nil)
        #expect(answer.text == " at the station." && answer.route == .cloud(.openai))
        #expect(model.requests.isEmpty)
        let body = try #require(StubURLProtocol.lastRequest(host: host).flatMap { $0.httpBody ?? $0.httpBodyStream.map(Self.read) })
        #expect(String(decoding: body, as: UTF8.self).contains("<before>Meet me</before>"))
    }

    static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    // MARK: - Settings → Assistant

    @Test func theAssistantTurnsItOnAndOffButNeverAgreesToTheCloud() throws {
        #expect(AIConfig.Key.parse("autocomplete") == .autocomplete)
        #expect(AIConfig.Key.parse("autocompleteCloud") == .forbidden("autocompleteCloud", secret: false))
        let env = AIConfig.Environment(packInstalled: { _ in true }, apps: AIConfig.AppCatalog(apps: []), awsProfiles: { [] },
                                       knownModels: { _ in [] }, offeredProviders: [.bedrock, .anthropic], hasKey: { _ in false },
                                       chinese: false)
        let on = try AIConfig.parse(#"{"changes": [{"key": "autocomplete", "value": true}]}"#)
        var config = Config.default  // Bedrock, not agreed to
        let rows = AIConfig.check(on, config: config, environment: env).rows
        #expect(rows.map { $0.text(chinese: false) } == ["Autocomplete: off → on (it uses the model on this Mac; to use your AI provider, agree when you turn on Autocomplete in the input menu)"])
        let undo = AIConfig.apply(rows.compactMap { $0.edit }, to: &config)
        #expect(config.autocomplete && config.autocompleteCloud == nil && undo == [.autocomplete(false)])
        config.provider = .apple
        config.autocomplete = false
        #expect(AIConfig.check(on, config: config, environment: env).rows.map { $0.text(chinese: false) } == ["Autocomplete: off → on"])
        let refused = try AIConfig.parse(#"{"changes": [{"key": "autocompleteCloud", "value": true}, {"key": "autocomplete", "value": "yes"}]}"#)
        let refusedRows = AIConfig.check(refused, config: config, environment: env).rows
        #expect(refusedRows.count == 2 && refusedRows.allSatisfy { $0.isRefused })
        // The on-device model's small context gets it with the typing settings.
        let prompt = AIConfigPrompt.system(AIConfigPrompt.Context(config: config), compact: true, refining: false,
                                           scope: AIConfigPrompt.Scope(parts: [.typing]))
        #expect(prompt.contains("autocomplete: true or false"))
    }

    // MARK: - Keys

    @Test func tabTakesItOnlyOnceItHasBeenUpAMoment() {
        let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
        #expect(Autocomplete.tab(tab, shownFor: 0.5) == .accept)
        #expect(Autocomplete.tab(tab, shownFor: 0.119) == .passOn)
        #expect(Autocomplete.tab(KeyEvent(keyCode: VirtualKey.tab, characters: "\t", modifiers: .shift), shownFor: 1) == .passOn)
        #expect(Autocomplete.tab(KeyEvent(keyCode: VirtualKey.tab, characters: "\t", modifiers: .option), shownFor: 1) == .passOn)
        #expect(Autocomplete.tab(KeyEvent(keyCode: VirtualKey.tab, characters: "\t", modifiers: .capsLock), shownFor: 1) == .accept)
        #expect(Autocomplete.tab(KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}"), shownFor: 1) == nil)
    }

    // MARK: - Where it never runs

    @Test func neverInPasswordFieldsTerminalsRemoteDesktopsPasswordManagersOrAppsWithoutAI() {
        var config = Config.default
        config.appProfiles = ["com.example.quiet": AppProfile(noAI: true)]
        func blocker(_ field: FieldInfo, secure: Bool = false, composing: Bool = false, translating: Bool = false) -> Autocomplete.Blocker? {
            Autocomplete.blocker(in: field, secureInput: secure, config: config, composing: composing, translating: translating)
        }
        #expect(blocker(FieldInfo(app: "com.apple.TextEdit")) == nil)
        #expect(blocker(FieldInfo(app: "com.apple.TextEdit"), secure: true) == .secureInput)
        #expect(blocker(FieldInfo(app: "win:notepad.exe", secure: true)) == .secureInput)
        #expect(blocker(FieldInfo(app: "com.apple.Terminal", terminal: true)) == .terminal)
        #expect(blocker(FieldInfo(app: "com.microsoft.rdc.macos")) == .remote)
        #expect(blocker(FieldInfo(app: "com.1password.1password")) == .passwordManager)
        #expect(blocker(FieldInfo(app: "com.apple.Passwords")) == .passwordManager)
        #expect(blocker(FieldInfo(app: "win:KeePassXC.exe")) == .passwordManager)
        #expect(blocker(FieldInfo(app: "com.example.quiet")) == .noAI)
        #expect(blocker(FieldInfo(app: "com.apple.TextEdit"), translating: true) == .translating)
        #expect(blocker(FieldInfo(app: "com.apple.TextEdit"), composing: true) == .composing)
    }

    @Test func anAppsOwnChoiceOverTheSwitchAndWhatWasLearned() {
        var config = Config.default
        #expect(!Autocomplete.isOn(in: "com.a", config: config, stopped: false))
        config.autocomplete = true
        #expect(Autocomplete.isOn(in: "com.a", config: config, stopped: false))
        #expect(!Autocomplete.isOn(in: "com.a", config: config, stopped: true))
        config.appProfiles = ["com.a": AppProfile(autocomplete: true), "com.b": AppProfile(autocomplete: false)]
        #expect(Autocomplete.isOn(in: "com.a", config: config, stopped: true))
        #expect(!Autocomplete.isOn(in: "com.b", config: config, stopped: false))
        config.autocomplete = false
        #expect(Autocomplete.isOn(in: "com.a", config: config, stopped: false))
    }

    // MARK: - Kept, learned, counted

    @Test func aSuggestionKeptIsShownAgainAndAsItIsTypedAlong() {
        var cache = Autocomplete.Cache()
        cache.add(" world, how are you?", after: "Hello")
        #expect(cache.rest(after: "Hello") == " world, how are you?")
        #expect(cache.rest(after: "Hello wor") == "ld, how are you?")
        #expect(cache.rest(after: "Hello world, how are you?") == nil)
        #expect(cache.rest(after: "Hello there") == nil)
        #expect(cache.rest(after: "Oh Hello") == nil)
        // A long text read up to its last 1,500 characters: the same end is the same text.
        let long = String(repeating: "x", count: 1500)
        cache.add(" and so on.", after: long)
        #expect(cache.rest(after: String((long + " and").suffix(1500))) == " so on.")
        for n in 0..<25 { cache.add(" \(n).", after: "Item \(n)") }
        #expect(cache.entries.count == Autocomplete.Cache.capacity && cache.rest(after: "Hello") == nil)
    }

    @Test func itStopsInAnAppWhereNoneOfTheLast30WasTaken() {
        var learning = Autocomplete.Learning()
        let early = (0..<29).map { _ in learning.record(false, in: "com.Example.app") }
        #expect(!early.contains(true) && !learning.stopped("com.example.app"))
        let thirtieth = learning.record(false, in: "com.example.app")
        #expect(thirtieth && learning.stopped("com.example.APP"))
        let again = learning.record(false, in: "com.example.app")
        #expect(!again)  // said once
        // Waved away often: it waits longer, up to twice as long.
        #expect(learning.pause(0.15, in: "com.example.app") == 0.3)
        #expect(learning.pause(0.15, in: "com.other") == 0.15)
        // One taken among the last 30 keeps it going.
        var kept = Autocomplete.Learning()
        _ = kept.record(true, in: "com.b")
        for _ in 0..<29 { _ = kept.record(false, in: "com.b") }
        #expect(!kept.stopped("com.b"))
        let last = kept.record(false, in: "com.b")
        #expect(last)
        learning.restart()
        #expect(!learning.stopped("com.example.app"))
    }

    @Test func metricsAreKeptOnThisDevice() throws {
        let defaults = MemoryKeyValueStore()
        let store = AutocompleteStore(defaults: defaults)
        store.count {
            $0.shown("abc", after: 0.2, fromCache: false)
            $0.shown("defgh", after: 0.4, fromCache: true)
            $0.accepted += 1
            $0.acceptedCharacters += 3
        }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        store.switched(on: true, at: start)
        store.switched(on: false, at: start.addingTimeInterval(3600))
        store.switched(on: true, at: start.addingTimeInterval(7200))
        store.switched(on: false, at: start.addingTimeInterval(7200 + 2 * 86400))
        let again = AutocompleteStore(defaults: defaults).metrics
        #expect(again.shown == 2 && again.fromCache == 1 && again.acceptance == 0.5 && again.acceptedShare == 3.0 / 8)
        #expect(again.p90 == 400 && again.turnedOn == 2 && again.turnedOffWithinADay == 1 && again.offWithinADayShare == 0.5)
        #expect(again.summary(language: "en") == "Shown 2 times · 50% taken · 90% within 400 ms")
        #expect(Autocomplete.Metrics().summary(language: "en") == nil)
    }

    // MARK: - In a session

    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.english])
            config.setOrder([OutputLanguage.english, .chinese])
            config.autocomplete = true
        }
    }

    struct Rig {
        let host: FakeHost
        let model: ContinuingModel
        let clock: Uptime
        let store: AutocompleteStore

        var pauses: [TimerID] { host.timers.filter { if case .autocomplete = $0 { true } else { false } } }

        /// The pause runs out: the field is read, and what it asks is answered.
        func pauseEnds(expecting text: String? = nil) {
            clock.advance(0.2)
            host.fireTimers { if case .autocomplete = $0 { true } else { false } }
            if text != nil { host.settle(timeout: 5) { host.ghost != nil } } else { host.settle(timeout: 0.3) { false } }
        }
    }

    func rig(_ settings: Settings = Settings(), app: String = "com.example.editor", model: ContinuingModel? = nil,
             store: AutocompleteStore = AutocompleteStore(), _ adjust: (inout SessionServices) -> Void = { _ in }) -> Rig {
        let model = model ?? ContinuingModel { _ in "ld, how are you? Fine." }
        let clock = Uptime()
        let engine = FakeEngine()
        var services = SessionServices(converter: Converter(loadConfig: { settings.config }, appleModel: model),
                                       loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        services.autocomplete = store
        services.appName = { $0 == "com.example.editor" ? "Editor" : nil }
        adjust(&services)
        let host = FakeHost(services: services)
        host.app = app
        host.appTypesKeys = true
        host.focus()
        return Rig(host: host, model: model, clock: clock, store: store)
    }

    @Test func aPauseAfterTypingShowsTheRestAndTabPutsItIn() {
        withInterfaceLanguage("en") {
            let r = rig()
            r.host.type("Hello wor")
            #expect(r.host.document == "Hello wor")
            #expect(r.pauses.count == 9 && r.host.timerDelays[r.pauses.last!] == 0.15)
            r.pauseEnds(expecting: "ld, how are you?")
            #expect(r.host.ghost == "ld, how are you?" && r.host.fieldReads == 1)
            #expect(r.model.requests.first?.prompt == "<before>Hello wor</before>")
            r.clock.advance(0.5)
            #expect(r.host.press(FakeHost.tab))
            #expect(r.host.document == "Hello world, how are you?" && r.host.ghost == nil)
            let metrics = r.store.metrics
            #expect(metrics.asked == 1 && metrics.shown == 1 && metrics.accepted == 1 && metrics.acceptedCharacters == 16)
            #expect(metrics.latencies == [200])
            // ⌘Z right after is counted as taken by mistake.
            r.host.press(KeyEvent(keyCode: 0x06, characters: "z", charactersIgnoringModifiers: "z", modifiers: .command))
            #expect(r.store.metrics.undone == 1)
        }
    }

    @Test func aTabRightAsItAppearsOrWithAModifierIsTheApps() {
        withInterfaceLanguage("en") {
            let r = rig()
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            r.clock.advance(0.05)
            #expect(!r.host.press(FakeHost.tab))
            #expect(r.host.ghost == nil && r.host.document == "Hello wor")
            // Typed on: the rest of what was kept, with no request.
            r.host.type("l")
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost == "d, how are you?" && r.model.requests.count == 1)
            r.clock.advance(1)
            #expect(!r.host.press(KeyEvent(keyCode: VirtualKey.tab, characters: "\t", modifiers: .shift)))
            #expect(r.host.ghost == nil && r.host.document == "Hello worl")
            #expect(r.store.metrics.dismissed == 2 && r.store.metrics.accepted == 0)
        }
    }

    @Test func escTakesItDownAndAnyOtherKeyGoesOnToTheApp() {
        withInterfaceLanguage("en") {
            let r = rig(model: ContinuingModel { $0 == "<before>Hello worl</before>" ? "d, how are you? Fine." : "ld, how are you? Fine." })
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            #expect(r.host.press(FakeHost.escape))
            #expect(r.host.ghost == nil)
            // Not this one: not shown again for the same text, from what was kept or said again by the model.
            r.host.type("l")
            r.host.press(KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}"))
            r.host.document = "Hello wor"
            r.host.type("l")
            r.pauseEnds()
            #expect(r.host.ghost == nil && r.model.requests.count == 2 && r.store.metrics.fromCache == 0)
            r.host.document = "Bye wor"
            r.host.type("l")
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost == "ld, how are you?")
            r.clock.advance(1)
            #expect(!r.host.press(KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}")))
            #expect(r.host.ghost == nil)
        }
    }

    @Test func typingAlongTakesItOnAndToItsEnd() {
        withInterfaceLanguage("en") {
            let r = rig()
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            r.host.type("ld,")
            #expect(r.host.ghost == " how are you?" && r.pauses.isEmpty)
            r.host.type(" how are you?")
            #expect(r.host.ghost == nil && r.host.document == "Hello world, how are you?")
            #expect(r.store.metrics.typedThrough == 1 && r.store.metrics.acceptedCharacters == 16 && r.model.requests.count == 1)
            // Something else typed: it goes.
            r.host.document = "Hello wor"
            r.host.type("l")
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost == "d, how are you?")
            r.host.type("x")
            #expect(r.host.ghost == nil && r.store.metrics.dismissed == 1)
        }
    }

    @Test func everyKeyStopsTheRequest() {
        withInterfaceLanguage("en") {
            let model = ContinuingModel { _ in "" }
            model.hold = true
            let r = rig(model: model)
            r.host.type("Hello wor")
            r.clock.advance(0.2)
            r.host.fireTimers { if case .autocomplete = $0 { true } else { false } }
            #expect(r.host.settle(timeout: 20, until: model.isWaiting))
            r.host.type("l")
            #expect(r.host.settle(timeout: 20, until: model.wasStopped))
            model.release("d today.")
            r.host.settle(timeout: 0.3) { false }
            #expect(r.host.ghost == nil && r.store.metrics.shown == 0)
        }
    }

    @Test func anAnswerThatComesTooLateIsDropped() {
        withInterfaceLanguage("en") {
            let model = ContinuingModel { _ in "" }
            model.hold = true
            let r = rig(model: model)
            r.host.type("Hello wor")
            r.clock.advance(0.2)
            r.host.fireTimers { if case .autocomplete = $0 { true } else { false } }
            #expect(r.host.settle(timeout: 20, until: model.isWaiting))
            // Waited past what the on-device model is allowed: dropped, and counted.
            r.clock.advance(3)
            model.release("d today.")
            r.host.settle(timeout: 20, until: r.store.hasLate)
            #expect(r.host.ghost == nil && r.store.metrics.late == 1)
        }
    }

    @Test func chineseComesBackAfterWhatIsComposedIsItsStart() {
        withInterfaceLanguage("en") {
            let settings = Settings()
            settings.config.setOrder([Language.chinese, .english])
            let r = rig(settings, model: ContinuingModel { _ in "，今天怎么样？" })
            r.host.type("nihao")
            #expect(r.pauses.isEmpty)  // composing: no pause
            r.host.press(FakeHost.space)
            #expect(r.host.document == "你好" && r.pauses.count == 1)
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost == "，今天怎么样？")
            r.host.type(",")
            #expect(r.host.document == "你好，" && r.host.ghost == "今天怎么样？")
            r.host.type("jintian")
            #expect(r.host.ghost == nil)  // held while pinyin is composed
            r.host.press(FakeHost.space)
            #expect(r.host.document == "你好，今天" && r.host.ghost == "怎么样？" && r.model.requests.count == 1)
            r.host.type("wo")
            r.host.press(FakeHost.space)
            #expect(r.host.ghost == nil && r.store.metrics.dismissed == 1)
        }
    }

    @Test func neverWhereItMustNot() {
        withInterfaceLanguage("en") {
            // A terminal, a password manager, a remote desktop, an app with no AI, a password field.
            for app in ["com.apple.Terminal", "com.1password.1password", "com.microsoft.rdc.macos", "com.example.quiet"] {
                let settings = Settings()
                settings.config.appProfiles = ["com.example.quiet": AppProfile(noAI: true)]
                let r = rig(settings, app: app)
                if app == "com.apple.Terminal" {
                    r.host.terminal = true
                    r.host.focus()
                }
                r.host.type("Hello wor")
                #expect(r.pauses.isEmpty, "\(app)")
            }
            let secure = rig()
            secure.host.secure = true
            secure.host.type("Hello wor")
            #expect(secure.pauses.isEmpty)
            // Secure input on anywhere when the pause ends: nothing read, nothing asked.
            let elsewhere = Locked(initialState: false)
            let late = rig { $0.secureInputActive = { elsewhere.withLock { $0 } } }
            late.host.type("Hello wor")
            elsewhere.withLock { $0 = true }
            late.pauseEnds()
            #expect(late.host.fieldReads == 0 && late.model.requests.isEmpty)
            // Off: nothing.
            let settings = Settings()
            settings.config.autocomplete = false
            let off = rig(settings)
            off.host.type("Hello wor")
            #expect(off.pauses.isEmpty)
            // An @ command being written.
            let command = rig()
            command.host.press(FakeHost.at)
            command.host.type("improve")
            #expect(command.pauses.isEmpty)
        }
    }

    @Test func notWhileTranslateAsYouTypeIsOn() {
        withInterfaceLanguage("en") {
            let settings = Settings()
            settings.config.setOrder([Language.chinese, .english])
            let r = rig(settings)
            r.host.type("nihao")
            r.host.press(FakeHost.space)
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost != nil)
            let outputs = r.host.session.apply(r.host.composer.setTranslateMode(TranslateMode.Session(target: .english)))
            #expect(outputs.contains(.ghost(nil)))
            #expect(!r.host.session.autocompleteMayRun() && r.host.session.autocomplete.suggestion == nil)
        }
    }

    @Test func notBeforeTheEndOfALineNorWithTextSelected() {
        withInterfaceLanguage("en") {
            let r = rig()
            r.host.type("Hello wor")
            r.host.document = "Hello wor and more"
            r.host.selection = 9..<9
            r.pauseEnds()
            #expect(r.host.fieldReads == 1 && r.model.requests.isEmpty && r.host.ghost == nil)
            r.host.selection = nil
            r.host.document = "Hello wor"
            r.host.type("l")
            r.host.selection = 2..<5
            r.pauseEnds()
            #expect(r.model.requests.isEmpty)
        }
    }

    @Test func aFieldThatTellsNothingContinuesWhatWasTypedIntoIt() {
        withInterfaceLanguage("en") {
            let r = rig()
            r.host.tellsNoText = true
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            #expect(r.model.requests.first?.prompt == "<before>Hello wor</before>" && r.host.ghost != nil)
            // A click: what was typed is forgotten (the caret may be anywhere).
            r.host.send(.commit)
            #expect(r.host.ghost == nil)
            r.host.type("l")
            r.pauseEnds()
            #expect(r.model.requests.count == 1)
        }
    }

    @Test func aClickSinceItCameUpTakesItAwayAndTabGoesToTheApp() {
        withInterfaceLanguage("en") {
            let clicked = Locked(initialState: false)
            let r = rig { $0.pointerUsedWithin = { _ in clicked.withLock { $0 } } }
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            r.clock.advance(1)
            clicked.withLock { $0 = true }
            #expect(!r.host.press(FakeHost.tab))
            #expect(r.host.document == "Hello wor" && r.host.ghost == nil)
        }
    }

    @Test func itStopsInAnAppWhereItIsntUsedAndSaysSoOnce() {
        withInterfaceLanguage("en") {
            let store = AutocompleteStore()
            store.learn { learning in for _ in 0..<29 { _ = learning.record(false, in: "com.example.editor") } }
            let r = rig(store: store)
            #expect(r.store.pause(0.15, in: "com.example.editor") == 0.3)
            r.host.type("Hello wor")
            #expect(r.host.timerDelays[r.pauses.last!] == 0.3)  // waved away often: it waits longer
            r.pauseEnds(expecting: "x")
            #expect(r.host.press(FakeHost.escape))
            #expect(store.stopped(in: "com.example.editor") && store.metrics.stoppedApps == 1)
            #expect(r.host.noticeAlone == "Autocomplete wasn't used in Editor, so it stopped there (Settings → Apps can keep it on)")
            r.host.type("l")
            #expect(r.pauses.isEmpty)
            // The app set to autocomplete always: on again there.
            let settings = Settings()
            settings.config.appProfiles = ["com.example.editor": AppProfile(autocomplete: true)]
            let always = rig(settings, store: store)
            always.host.type("Hello wor")
            #expect(!always.pauses.isEmpty)
            // Set never: off there, the switch on.
            settings.config.appProfiles = ["com.example.editor": AppProfile(autocomplete: false)]
            let never = rig(settings, store: AutocompleteStore())
            never.host.type("Hello wor")
            #expect(never.pauses.isEmpty)
        }
    }

    @Test func theOnDeviceModelUnavailableShowsNothingAndSaysSoOnce() {
        withInterfaceLanguage("en") {
            let r = rig(model: ContinuingModel(.appleIntelligenceNotEnabled))
            r.host.type("Hello wor")
            r.pauseEnds()
            r.host.settle(timeout: 5) { r.host.noticeAlone != nil }
            #expect(r.host.ghost == nil && r.host.noticeAlone?.hasPrefix("Autocomplete needs Apple Intelligence on this Mac") == true)
            #expect(r.store.metrics.failed == 1)
            r.host.type("l")
            r.pauseEnds()
            r.host.settle(timeout: 5) { r.store.metrics.failed == 2 }
            #expect(r.host.outputs.filter { if case let .notice(text) = $0 { text.hasPrefix("Autocomplete needs") } else { false } }.count == 1)
        }
    }

    @Test func aCloudProviderAgreedToWaitsLonger() {
        withInterfaceLanguage("en") {
            let settings = Settings()
            settings.config.provider = .anthropic
            settings.config.autocompleteCloud = true
            let r = rig(settings)
            r.host.type("Hi")
            #expect(r.host.timerDelays[r.pauses.last!] == 0.35)
        }
    }

    @Test func theModelIsLoadedWhenAFieldTakesTheFocusAtMostOnceAMinute() {
        withInterfaceLanguage("en") {
            let store = AutocompleteStore()
            #expect(store.prewarmDue(at: 10) && !store.prewarmDue(at: 30) && store.prewarmDue(at: 71))
        }
    }
}
