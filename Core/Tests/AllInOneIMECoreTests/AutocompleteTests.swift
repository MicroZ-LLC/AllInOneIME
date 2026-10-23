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
        #expect(Autocomplete.trimmed(" Dr. Chen, i.e. the new lead. Then", before: "Ask") == " Dr. Chen, i.e. the new lead.")
        #expect(Autocomplete.trimmed(" until the summer. Then", before: "Wait") == " until the summer.")
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

    @Test func anAnswerInAnotherScriptThanTheTextsIsNotShown() {
        // Real (0.6.7's request): "Hi" + "你好。"; with examples, "Thanks for the update." + "我们下周再聚。".
        #expect(Autocomplete.trimmed("你好。", before: "Hi") == nil)
        #expect(Autocomplete.trimmed("我们下周再聚。", before: "Thanks for the update.") == nil)
        // Text with Chinese in it may go on in it.
        #expect(Autocomplete.trimmed("周五见。", before: "Swift 课程，") == "周五见。")
    }

    @Test func aNewWordGetsTheSpaceTheModelLeftOut() {
        #expect(Autocomplete.trimmed("<after>be late</after>", before: "I might") == " be late")
        #expect(Autocomplete.trimmed("<after>worry about it.</after>", before: "Don't you") == " worry about it.")
        #expect(Autocomplete.trimmed("<after>worry.</after>", before: "Please don't") == " worry.")
        #expect(Autocomplete.trimmed("<after>Thanks!</after>", before: "Done!") == " Thanks!")
        #expect(Autocomplete.trimmed("<after>grep.</after>", before: "Use a tool, e.g.") == " grep.")
        #expect(Autocomplete.trimmed("<after>maybe later</after>", before: "Well...") == " maybe later")
        // None inside a number, a time, a web address, after a number's ending.
        #expect(Autocomplete.trimmed("<after>000 people</after>", before: "About 1,") == "000 people")
        #expect(Autocomplete.trimmed("<after>30 tomorrow</after>", before: "See you at 10:") == "30 tomorrow")
        #expect(Autocomplete.trimmed("<after>com for details</after>", before: "Go to example.") == "com for details")
        #expect(Autocomplete.trimmed("<after>th floor</after>", before: "Room 4") == "th floor")
        #expect(Autocomplete.trimmed("<after>am tomorrow</after>", before: "Call me at 9") == "am tomorrow")
    }

    @Test func anUnfinishedWordIsFinishedNotGluedOn() {
        #expect(Autocomplete.trimmed("<after>later today</after>", before: "Thanks for the mee") == nil)
        #expect(Autocomplete.trimmed("Tomorrow works.", before: "Thanks for the mee") == nil)
        #expect(Autocomplete.trimmed("<after>ting tomorrow</after>", before: "Thanks for the mee") == "ting tomorrow")
        // A piece that is no word may finish one the word list lacks; a word of the field written whole: its rest.
        #expect(Autocomplete.trimmed("<after>ur à tous</after>", before: "Bonjo") == "ur à tous")
        #expect(Autocomplete.trimmed("<after>Zorblax 2.</after>", before: "Zorblax 1 is out. Next: zor") == "blax 2.")
        // After a word on its own, a new word: its space.
        #expect(Autocomplete.trimmed("<after>later today</after>", before: "Let's talk") == " later today")
        // The unfinished word's last letters said again (real, on-device): what finishes it from before them.
        #expect(Autocomplete.trimmed("morrow at ten.", before: "Sounds good, see you tomo") == "rrow at ten.")
        #expect(Autocomplete.trimmed("mand: make install", before: "Run this comm") == "and: make install")
        #expect(Autocomplete.trimmed("so good.", before: "This is") == " so good.")
    }

    @Test func theTextAfterTheCaretSaidAgainIsNotShown() {
        // Its start, all of its first line with something on it and more, two words of it or more.
        #expect(Autocomplete.trimmed("Best regards,", before: "Thanks again.", after: "\n\nBest regards,\nTom") == nil)
        #expect(Autocomplete.trimmed(" see you then.", before: "Great,", after: "\nSee you then! Bye") == nil)
        #expect(Autocomplete.trimmed("<after>带伞</after>", before: "周末我想去", after: "\n记得带伞") == nil)
        #expect(Autocomplete.trimmed("the report tomorrow morning.", before: "I will send you the report", after: "\ntomorrow morning") == nil)
        // Not one word of it the same elsewhere, nor a next line without words.
        #expect(Autocomplete.trimmed(" the park.", before: "Let's go to", after: "\nThe end") == " the park.")
        #expect(Autocomplete.trimmed(" the next one.", before: "Let's go to", after: "\nAfter that, the next one") == nil)
        #expect(Autocomplete.trimmed(" tomorrow.", before: "See you", after: "  \n---\nTomorrow") == " tomorrow.")
    }

    @Test func theEndOfTheTextSaidAgainIsNotShown() {
        // All of the answer is the end of the text, from a word's start, in any case: nothing.
        #expect(Autocomplete.trimmed("Hello.", before: "Just say hello") == nil)
        #expect(Autocomplete.trimmed("<after>会议</after>", before: "明天下午三点的会议") == nil)
        // The unfinished word written whole: its rest. A word that is one on its own stays.
        #expect(Autocomplete.trimmed("Schedule a call.", before: "Please sched") == "ule a call.")
        #expect(Autocomplete.trimmed("documents by Friday.", before: "Sign the docu") == "ments by Friday.")
        #expect(Autocomplete.trimmed("there.", before: "Over there") == nil)
        #expect(Autocomplete.trimmed("there is more.", before: "Over there") == " there is more.")
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
        // Chinese characters count up to 25, not as words (real: "<after>性能优化和用户体验提升</" was read only so far).
        #expect(!Autocomplete.isEnough("<after>性能优化和用户体验提升"))
        #expect(Autocomplete.isEnough(String(repeating: "很", count: 26)))
    }

    @Test func aTagCutShortAtTheEndGoes() {
        #expect(Autocomplete.trimmed("<after>性能优化和用户体验提升</", before: "主要改进包括") == "性能优化和用户体验提升")
        #expect(Autocomplete.trimmed("<after>sure thing</after", before: "OK,") == " sure thing")
        #expect(Autocomplete.trimmed(" and more <a", before: "Lunch") == " and more")
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

    @Test func onlyTheNextLineAfterTheCaretIsSent() {
        // What a model needs so as not to write it again: up to the end of the first line with something on it.
        #expect(Autocomplete.context(FieldText(before: "Dear Ann,", after: "\n\nBest regards,\nTom\n"))?.after == "\n\nBest regards,")
        #expect(Autocomplete.context(FieldText(before: "Dear Ann,", after: "  \n \n"))?.after == "")
    }

    @Test func theOnDeviceModelHasExamplesInTheTextsOwnScript() {
        func request(_ before: String, onDevice: Bool = true) -> ConverseRequest {
            Prompt.autocompleteRequest(Autocomplete.Context(before: before), app: nil, onDevice: onDevice)
        }
        func answers(_ request: ConverseRequest) -> [String] {
            request.messages.filter { $0.role == "assistant" }.map { $0.content[0].text }
        }
        // English: four, asked to start with no space (the English words put it in), and the text last, as it was.
        let english = request("Sounds good, see you tomo")
        #expect(english.messages.count == 9 && english.messages.last?.content[0].text == "<before>Sounds good, see you tomo</before>")
        #expect(answers(english).contains("next Wednesday?") && !answers(english).contains { $0.hasPrefix(" ") })
        #expect(english.system[0].text.contains("Never start with a space"))
        // Another language in Latin letters keeps the model's spaces; Chinese gets the Chinese ones; Japanese none.
        let german = request("Vielen Dank für die schnelle Antwort. Wir sehen uns")
        #expect(answers(german).contains(" next Wednesday?") && !german.system[0].text.contains("Never start with a space"))
        #expect(answers(request("谢谢你的帮助，")) == Prompt.autocompleteChineseExamples.map(\.answer))
        #expect(request("明日の会議は").messages.count == 1)
        // A cloud model gets none.
        #expect(request("Sounds good, see you tomo", onDevice: false).messages.count == 1)
        // As the on-device model takes it: the examples earlier turns, the text the prompt.
        let apple = AppleModel.request(from: english, maxTokens: Autocomplete.maxTokens, contextSize: 4096)
        #expect(apple.examples.count == 4 && apple.prompt == "<before>Sounds good, see you tomo</before>")
    }

    @Test func englishIsToldByItsWords() {
        #expect(Autocomplete.looksEnglish("Thanks for the quick reply. I will send you the rep"))
        #expect(Autocomplete.looksEnglish("iss"))
        #expect(!Autocomplete.looksEnglish("Vielen Dank für die schnelle Antwort. Wir sehen uns"))
        #expect(!Autocomplete.looksEnglish("Merci pour votre message. Je vous envoie le rapport"))
    }

    // MARK: - The model

    @Test func theOnDeviceModelUnlessTheUserAgreedToTheirCloudProvider() {
        var config = Config.default  // Bedrock
        #expect(Autocomplete.route(config) == .onDevice && Autocomplete.asksForCloud(config))
        Autocomplete.answer(false, in: &config)
        #expect(Autocomplete.route(config) == .onDevice && !Autocomplete.asksForCloud(config))
        Autocomplete.answer(true, in: &config)
        #expect(Autocomplete.route(config) == .cloud(.bedrock))
        config.provider = .apple
        config.autocompleteCloud = nil
        #expect(Autocomplete.route(config) == .onDevice && !Autocomplete.asksForCloud(config))
        #expect(Autocomplete.Route.onDevice.pause == 0.35 && Autocomplete.Route.cloud(.anthropic).pause == 0.5)
    }

    /// The yes is for where the requests went when it was given: the provider and its host (for Bedrock, the AWS profile
    /// and region). Another one, picked in Settings, by the Assistant or by iCloud sync, is asked about again, and gets
    /// nothing meanwhile; back to the one agreed to, the yes holds again.
    @Test func theYesIsForTheProviderAndHostItWasGivenFor() throws {
        var config = Config.default  // Bedrock, the default profile and its region
        #expect(Autocomplete.destination(config) == "bedrock default")
        Autocomplete.answer(true, in: &config)
        #expect(config.autocompleteCloud == Autocomplete.Consent(allowed: true, destination: "bedrock default"))
        #expect(Autocomplete.route(config) == .cloud(.bedrock) && Autocomplete.cloudAnswer(config) == true)
        // Gemini, as the Assistant picks it ("use Gemini"), or as iCloud sync brings it.
        _ = AIConfig.apply([.provider(.gemini)], to: &config)
        #expect(Autocomplete.destination(config) == "gemini generativelanguage.googleapis.com")
        #expect(Autocomplete.route(config) == .onDevice && Autocomplete.asksForCloud(config) && Autocomplete.cloudAnswer(config) == nil)
        config.provider = .bedrock
        #expect(Autocomplete.route(config) == .cloud(.bedrock))
        // Another region, another profile: another place, another account.
        config.region = "eu-central-1"
        #expect(Autocomplete.route(config) == .onDevice && Autocomplete.asksForCloud(config))
        config.region = nil
        config.awsProfile = "work"
        #expect(Autocomplete.route(config) == .onDevice && Autocomplete.asksForCloud(config))
        // An OpenAI-compatible service agreed to, then its address changed: another service.
        config.provider = .openai
        config.openai.baseURL = "https://api.openai.com/v1"
        Autocomplete.answer(true, in: &config)
        #expect(Autocomplete.route(config) == .cloud(.openai))
        config.openai.baseURL = "https://api.deepseek.com/v1"
        #expect(Autocomplete.destination(config) == "openai api.deepseek.com")
        #expect(Autocomplete.route(config) == .onDevice && Autocomplete.asksForCloud(config))
        // A no is for its destination too: another one is asked about.
        Autocomplete.answer(false, in: &config)
        #expect(!Autocomplete.asksForCloud(config) && Autocomplete.cloudAnswer(config) == false)
        config.openai.baseURL = "https://api.openai.com/v1"
        #expect(Autocomplete.asksForCloud(config))
    }

    /// Agreed to one provider, then another picked while autocomplete is on: the on-device model meanwhile (nothing goes to
    /// the new one), said once.
    @Test func anotherProviderThanTheOneAgreedToIsSaidOnce() {
        withInterfaceLanguage("en") {
            let settings = Settings()
            Autocomplete.answer(true, in: &settings.config)  // Bedrock
            settings.config.provider = .gemini
            let r = rig(settings)
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost == "ld, how are you?" && r.model.requests.count == 1, "the on-device model's")
            #expect(r.host.noticeAlone == "Your AI provider changed: Autocomplete uses the model on this Mac until you agree to send text to Gemini API (“Autocomplete with Gemini API” in the input menu)")
            r.host.press(FakeHost.escape)
            r.host.type("l")
            r.pauseEnds(expecting: "x")
            #expect(r.host.outputs.filter { if case let .notice(text) = $0 { text.hasPrefix("Your AI provider changed") } else { false } }.count == 1)
        }
    }

    /// AllInOneIME Cloud is never autocomplete's model, agreed to or not: its free requests a day are the @ commands', and
    /// a few minutes of pauses would use them up. The on-device model is asked instead, and the Assistant says why.
    @Test func allInOneIMECloudIsNeverAsked() async throws {
        var config = Config.default
        config.provider = .hosted
        #expect(Autocomplete.route(config) == .onDevice && !Autocomplete.asksForCloud(config))
        config.autocompleteCloud = Autocomplete.Consent(allowed: true, destination: "hosted")  // a config file written by hand
        #expect(Autocomplete.route(config) == .onDevice && !Autocomplete.asksForCloud(config))
        let model = ContinuingModel { _ in " tomorrow at noon." }
        let fixed = config
        let keyAsked = Locked(initialState: false)
        let converter = Converter(loadConfig: { fixed }, loadKey: { _, _ in keyAsked.withLock { $0 = true }; return "token" },
                                  appleModel: model)
        let answer = try await converter.autocomplete(Autocomplete.Context(before: "See you"), app: nil)
        #expect(answer.route == .onDevice && answer.text == " tomorrow at noon." && model.requests.count == 1)
        #expect(!keyAsked.withLock { $0 })
        let env = AIConfig.Environment(packInstalled: { _ in true }, apps: AIConfig.AppCatalog(apps: []), awsProfiles: { [] },
                                       knownModels: { _ in [] }, offeredProviders: [.hosted, .bedrock], hasKey: { _ in true },
                                       chinese: false)
        config.autocompleteCloud = nil
        let on = try AIConfig.parse(#"{"changes": [{"key": "autocomplete", "value": true}]}"#)
        #expect(AIConfig.check(on, config: config, environment: env).rows.map { $0.text(chinese: false) }
            == ["Autocomplete: off → on (it uses only the model on this Mac: AllInOneIME Cloud's free requests a day are kept for @ commands)"])
    }

    @Test func theSwitchAndTheConsentAreKeptOnlyOnceSet() throws {
        let plain = String(decoding: try JSONEncoder().encode(Config.default), as: UTF8.self)
        #expect(!plain.contains("autocomplete"))
        var config = Config.default
        config.autocomplete = true
        Autocomplete.answer(false, in: &config)
        config.appProfiles = ["com.example.app": AppProfile(autocomplete: false)]
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(back.autocomplete && back.autocompleteCloud == Autocomplete.Consent(allowed: false, destination: "bedrock default")
                && back.profile(for: "com.example.app")?.autocomplete == false)
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(back)) as? [String: Any]
        #expect(written?["autocompleteCloud"] as? [String: AnyHashable] == ["allowed": false, "destination": "bedrock default"])
        #expect(!AppProfile(autocomplete: false).isEmpty)
        // A value of the wrong type reads as none; so does a yes without where it was about (an early build's): asked again.
        let odd = try JSONDecoder().decode(Config.self, from: Data(#"{"autocomplete": "yes", "autocompleteCloud": "no"}"#.utf8))
        #expect(!odd.autocomplete && odd.autocompleteCloud == nil)
        let early = try JSONDecoder().decode(Config.self, from: Data(#"{"autocomplete": true, "autocompleteCloud": true}"#.utf8))
        #expect(early.autocompleteCloud == nil && Autocomplete.route(early) == .onDevice && Autocomplete.asksForCloud(early))
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

    @Test func theConverterShowsNothingThatIsAfterTheCaretAlready() async throws {
        let model = ContinuingModel { _ in " tomorrow at noon." }
        var config = Config.default
        config.provider = .apple
        let fixed = config
        let converter = Converter(loadConfig: { fixed }, appleModel: model)
        let answer = try await converter.autocomplete(Autocomplete.Context(before: "See you", after: "\nTomorrow at noon, then"), app: nil)
        #expect(answer.text == nil && model.requests.count == 1)
        #expect(model.requests.first?.examples.count == 4 && model.requests.first?.prompt == "<before>See you</before>\n<after>\nTomorrow at noon, then</after>")
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
        Autocomplete.answer(true, in: &config)
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
        #expect(rows.map { $0.text(chinese: false) } == ["Autocomplete: off → on (it uses the model on this Mac; to use Amazon Bedrock, choose “Autocomplete with Amazon Bedrock” in the input menu)"])
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

    /// Sentences that turn Autocomplete on, and off, in the interface's languages, with the usual words for it.
    static let turnedOn = ["我要把 auto complete 打开", "打开续写", "开启自动补全", "启用自动联想", "把续写开了", "turn on autocomplete",
                           "I want auto complete on", "enable auto-complete", "打開續寫", "オートコンプリートをオンにして", "자동 완성 켜 줘",
                           "Autovervollständigen einschalten", "Active la complétion automatique", "Activa el autocompletado",
                           "Ative o autocompletar"]
    static let turnedOff = ["我要把 auto complete 关闭", "关闭续写", "关掉自动补全", "把自动联想关了", "turn off autocomplete",
                            "disable auto-complete", "Autocomplete off", "關閉續寫", "オートコンプリートを無効にして", "자동 완성 꺼 줘",
                            "Autovervollständigung ausschalten", "Désactive la complétion automatique", "Desactiva el autocompletado",
                            "Desligue o autocompletar"]

    /// The bug as reported: "我要把 auto complete 关闭" and "我要把 auto complete 打开" both said "Already set that way", the
    /// on-device model answering with the setting as it was (on macOS 27.2; with nothing, or another app's settings, too).
    /// A sentence that only turns Autocomplete on or off is done as it says, whatever the model would answer: it isn't
    /// asked.
    @Test func aSentenceThatOnlyTurnsItOnOrOffIsDoneAsItSays() async throws {
        for (sentences, on) in [(Self.turnedOn, true), (Self.turnedOff, false)] {
            for sentence in sentences {
                for now in [false, true] {
                    let model = AIConfigTests.GuidedStub(answer: #"{"changes": [{"key": "autocomplete", "value": \#(now)}]}"#)
                    var config = Config.default
                    config.autocomplete = now
                    let answer = try await AIConfigService(client: ChatClient(apple: model)).ask(sentence, context: .init(config: config))
                    let env = AIConfig.Environment(chinese: true, typedText: sentence)
                    let preview = AIConfig.preview(try AIConfig.parse(answer.text), config: config, environment: env)
                    if on == now {
                        #expect(preview == .failure(.alreadySet), "“\(sentence)”, now \(now): \(preview)")
                    } else {
                        #expect((try? preview.get())?.edits == [.autocomplete(on)], "“\(sentence)”, now \(now): \(preview)")
                    }
                    #expect(model.schemas.isEmpty, "“\(sentence)”: the model was asked")
                }
            }
        }
    }

    /// A sentence that says more goes to the model: Autocomplete is as the sentence turns it whatever the model answered
    /// for it (the other way, or nothing, its note about that left out), the rest as the model answered.
    @Test func aSentenceThatSaysMoreTurnsItAsItSaysToo() async throws {
        var config = Config.default
        config.candidateLayout = .horizontal
        let column = #"{"key": "candidateLayout", "value": "vertical"}"#
        for (sentence, on, answer) in [
            ("打开续写，候选竖排", true, #"{"changes": [\#(column), {"key": "autocomplete", "value": false}], "note": "续写已经关了"}"#),
            ("turn on autocomplete and put the candidates in a column", true, #"{"changes": [\#(column)]}"#),
            ("关闭自动补全，候选竖排", false, #"{"changes": [\#(column), {"key": "autocomplete", "value": true}], "note": "续写已经开了"}"#),
        ] {
            config.autocomplete = !on
            let model = AIConfigTests.GuidedStub(answer: answer)
            let text = try await AIConfigService(client: ChatClient(apple: model)).ask(sentence, context: .init(config: config)).text
            let preview = AIConfig.preview(try AIConfig.parse(text), config: config, environment: AIConfig.Environment(chinese: true, typedText: sentence))
            let shown = try #require(try? preview.get(), "“\(sentence)”: \(preview)")
            #expect(shown.edits == [.candidateLayout(.vertical), .autocomplete(on)] && shown.note == nil, "“\(sentence)”: \(shown)")
            #expect(model.schemas.count == 1)
        }
        // For one app, it is set in Settings → Apps: the answer is taken as it is.
        let wechat = AIConfig.AppCatalog(apps: [.init(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"])])
        config.autocomplete = false
        let env = AIConfig.Environment(apps: wechat, chinese: true, typedText: "在微信里打开续写")
        #expect(AIConfig.preview(try AIConfig.parse(#"{"changes": [], "note": "-"}"#), config: config, environment: env) == .failure(.notUnderstood))
    }

    /// "Already set that way" only when what the answer keeps as it is is what the sentence asks for: a switch it turns
    /// the other way ("打开逐字上屏" answered with it off, as it is), or only settings it isn't about, say what wasn't
    /// understood instead.
    @Test func alreadySetOnlyWhenItIsWhatTheSentenceAsks() throws {
        var config = Config.default
        config.typeOut = false
        config.autocomplete = false
        config.candidateLayout = .vertical
        func outcome(_ sentence: String, _ answer: String, chinese: Bool = true) throws -> (Result<AIConfig.Preview, AIConfig.Failure>, String?) {
            let env = AIConfig.Environment(chinese: chinese, typedText: sentence)
            let proposal = try AIConfig.parse(answer)
            let preview = AIConfig.preview(proposal, config: config, environment: env)
            guard case let .failure(failure) = preview else { return (preview, nil) }
            return (preview, AIConfig.failureLine(failure, proposal: proposal, config: config, environment: env))
        }
        let typeOutOff = #"{"changes": [{"key": "typeOut", "value": false}]}"#
        let inputs = #"{"changes": [{"key": "inputLanguages", "value": ["\#(config.inputLanguages.map(\.rawValue).joined(separator: #"", ""#))"]}]}"#
        var (preview, line) = try outcome("打开逐字上屏", typeOutOff)
        #expect(preview == .failure(.unclearSwitch(.setting(.typeOut))) && line == "没看懂要打开还是关闭「逐字上屏」", "\(preview) \(line ?? "")")
        (preview, line) = try outcome("turn on typing out", typeOutOff, chinese: false)
        #expect(line == "Couldn't tell whether to turn Type results out on or off", "\(line ?? "")")
        (preview, line) = try outcome("候选竖排", inputs)
        #expect(preview == .failure(.unclearSetting) && line == "没看懂这句话要改哪项设置", "\(preview) \(line ?? "")")
        (preview, line) = try outcome("candidates in a column", inputs, chinese: false)
        #expect(line == "Couldn't tell which setting that is about", "\(line ?? "")")
        // Autocomplete, which the sentence doesn't name, is another setting than the typing out it names.
        let autocompleteOff = #"{"changes": [{"key": "autocomplete", "value": false}]}"#
        #expect(try outcome("打开逐字上屏", autocompleteOff).0 == .failure(.unclearSetting))
        // Already so as it asks: said so.
        for (sentence, answer) in [("关闭逐字上屏", typeOutOff), ("候选竖排", #"{"changes": [{"key": "candidateLayout", "value": "vertical"}]}"#),
                                   ("关闭自动补全", inputs), ("我要把 auto complete 关闭", autocompleteOff), ("关掉灰字", autocompleteOff),
                                   // Neither on nor off (a negation), or no setting named: taken at the answer's word.
                                   ("别打开逐字上屏", typeOutOff), ("", typeOutOff), ("就这样吧", inputs)] {
            #expect(try outcome(sentence, answer).0 == .failure(.alreadySet), "“\(sentence)” → \(answer)")
        }
    }

    /// Autocomplete by the names the interface gives it in its languages and the usual others: the on-device model's
    /// small context gets its setting (`AIConfigFit.relevance`), the instructions have them; on or off as the
    /// interface's languages say it, nothing when the sentence says both or a negation.
    @Test func itsNamesAndOnAndOffInTheInterfacesLanguages() async throws {
        let context = AIConfigPrompt.Context(config: .default)
        for name in ["auto complete", "Autocomplete", "autocompletion", "续写", "續寫", "自动补全", "自动完成", "自动联想", "自動完成", "オートコンプリート",
                     "自動補完", "자동 완성", "Autovervollständigen", "Autovervollständigung", "Complétion automatique", "autocomplétion",
                     "Autocompletar", "autocompletado"] {
            #expect(AIConfigFit.relevance(["\(name)?"], context: context).parts == [.typing], "\(name)")
        }
        // Fitted to a 4096-token context, a sentence that says more has Autocomplete's switch in its schema.
        let model = ContextLimitedModel(contextSize: 4096)
        let big = AIConfigContextTests.context(AIConfigContextTests.bigConfig(apps: 60))
        _ = try await AIConfigContextTests.service(model).ask("Autovervollständigen ausschalten und Kandidaten in einer Spalte", context: big,
                                                               tools: AIConfigContextTests.tools)
        let keys = AIConfigContextTests.keys(try #require(model.sent.last).schema)
        #expect(keys.contains("autocomplete") && keys.contains("candidateLayout"), "\(keys)")
        let prompt = AIConfigPrompt.system(context, compact: true, refining: false)
        #expect(["自动补全", "自动联想", #""打开续写""#, #""turn off autocomplete""#].allSatisfy(prompt.contains))

        for sentence in Self.turnedOn { #expect(AIConfig.switchAsked(sentence) == true, "\(sentence)") }
        for sentence in Self.turnedOff { #expect(AIConfig.switchAsked(sentence) == false, "\(sentence)") }
        for sentence in ["续写", "don't turn off autocomplete", "不要关闭续写", "Autovervollständigen nicht ausschalten", "ne désactive pas la complétion",
                         "打开逐字上屏，关闭续写", "자동 완성 끄지 마", "autocomplete is an annoyance", "关于续写", "自動補完を無効にしないで"] {
            #expect(AIConfig.switchAsked(sentence) == nil, "\(sentence)")
        }
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

    /// Code editors: Tab indents there and takes the editor's own completion, so it's off there unless the app is set to
    /// autocomplete always.
    @Test func offInCodeEditorsUnlessTheAppIsSetToAlways() {
        var config = Config.default
        config.autocomplete = true
        for app in ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
                    "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.google.android.studio", "dev.zed.Zed",
                    "com.sublimetext.4", "win:Code.exe", "win:devenv.exe", "win:pycharm64.exe"] {
            #expect(Autocomplete.isCodeEditor(app) && !Autocomplete.isOn(in: app, config: config, stopped: false), "\(app)")
        }
        for app in ["com.apple.TextEdit", "com.tinyspeck.slackmacgap", "com.google.Chrome", "com.microsoft.Word", "win:notepad.exe", nil] {
            #expect(!Autocomplete.isCodeEditor(app) && Autocomplete.isOn(in: app, config: config, stopped: false), "\(app ?? "none")")
        }
        config.appProfiles = ["com.microsoft.vscode": AppProfile(autocomplete: true)]
        #expect(Autocomplete.isOn(in: "com.microsoft.VSCode", config: config, stopped: false))
        withInterfaceLanguage("en") {
            let xcode = rig(app: "com.apple.dt.Xcode")
            xcode.host.type("Hello wor")
            #expect(xcode.pauses.isEmpty)
            let settings = Settings()
            settings.config.appProfiles = ["com.apple.dt.Xcode": AppProfile(autocomplete: true)]
            let always = rig(settings, app: "com.apple.dt.Xcode")
            always.host.type("Hello wor")
            always.pauseEnds(expecting: "x")
            #expect(always.host.ghost == "ld, how are you?")
        }
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
        store.flush()  // else written a moment later (`whatIsCountedIsWrittenLaterAllAtOnce`)
        let again = AutocompleteStore(defaults: defaults).metrics
        #expect(again.shown == 2 && again.fromCache == 1 && again.acceptance == 0.5 && again.acceptedShare == 3.0 / 8)
        #expect(again.p90 == 400 && again.turnedOn == 2 && again.turnedOffWithinADay == 1 && again.offWithinADayShare == 0.5)
        #expect(again.summary(language: "en") == "Shown 2 times · 50% taken · 90% within 400 ms")
        #expect(Autocomplete.Metrics().summary(language: "en") == nil)
    }

    /// Counting and learning never write the defaults as they happen (a key's end of a suggestion would wait for it): a
    /// while later, all at once, off the session's thread.
    @Test func whatIsCountedIsWrittenLaterAllAtOnce() async throws {
        final class Writes: KeyValueStore, @unchecked Sendable {
            let kept = MemoryKeyValueStore()
            private let lock = NSLock()
            private var _keys: [String] = []
            var keys: [String] { lock.withLock { _keys } }
            func data(forKey key: String) -> Data? { kept.data(forKey: key) }
            func string(forKey key: String) -> String? { kept.string(forKey: key) }
            func bool(forKey key: String) -> Bool { kept.bool(forKey: key) }
            func set(_ data: Data, forKey key: String) { lock.withLock { _keys.append(key) }; kept.set(data, forKey: key) }
            func set(_ string: String, forKey key: String) { lock.withLock { _keys.append(key) }; kept.set(string, forKey: key) }
            func set(_ bool: Bool, forKey key: String) { lock.withLock { _keys.append(key) }; kept.set(bool, forKey: key) }
            func removeValue(forKey key: String) { kept.removeValue(forKey: key) }
        }
        let defaults = Writes()
        let store = AutocompleteStore(defaults: defaults, writeDelay: 0.1)
        for _ in 0..<10 {
            store.count { $0.shown("abc", after: 0.2, fromCache: false) }
            store.learn { _ = $0.record(false, in: "com.example.editor") }
        }
        #expect(defaults.keys.isEmpty, "written as counted: \(defaults.keys)")
        let deadline = Date().addingTimeInterval(10)
        while defaults.keys.count < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(defaults.keys.sorted() == ["autocompleteLearning", "autocompleteMetrics"], "\(defaults.keys)")
        let again = AutocompleteStore(defaults: defaults)
        #expect(again.metrics.shown == 10 && again.learning.apps["com.example.editor"]?.outcomes.count == 10)
    }

    /// With the switch off (and no app set to always), a key does nothing for autocomplete: no pointer asked, nothing typed
    /// kept, no pause.
    @Test func offItDoesNothingForAKey() {
        withInterfaceLanguage("en") {
            let asked = Locked(initialState: 0)
            let settings = Settings()
            settings.config.autocomplete = false
            let r = rig(settings) { $0.pointerUsedWithin = { _ in asked.withLock { $0 += 1 }; return false } }
            r.host.type("Hello world, how are you?")
            r.host.press(KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}"))
            #expect(asked.withLock { $0 } == 0 && r.host.session.autocomplete.typed.text.isEmpty && r.pauses.isEmpty)
            // On in this app by its own choice: it runs.
            settings.config.appProfiles = ["com.example.editor": AppProfile(autocomplete: true)]
            r.host.focus()
            r.host.type("Hello wor")
            #expect(r.host.session.autocomplete.typed.text == "Hello wor" && !r.pauses.isEmpty)
        }
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
            #expect(r.pauses.count == 9 && r.host.timerDelays[r.pauses.last!] == 0.35)
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

    /// What Tab puts in goes in as the input method's own commits do: the letters typed before it in English mode ("zorbl"
    /// of "zorble") are the start of a word, not one, and never learned as one (`EnglishModeWords`).
    @Test func whatTabPutsInEndsNoWordTypedInEnglishMode() {
        withInterfaceLanguage("en") {
            let learned = Locked(initialState: [String]())
            let r = rig(model: ContinuingModel { _ in "e went well. Then" }) {
                $0.englishDictionary = { EnglishDictionary(["hello", "world", "it"]) }
                $0.learnEnglishWord = { word in learned.withLock { $0.append(word) } }
            }
            for _ in 0..<2 {
                r.host.type(" zorbl")
                r.pauseEnds(expecting: "x")
                #expect(r.host.ghost == "e went well.")
                r.clock.advance(0.5)
                #expect(r.host.press(FakeHost.tab))
                r.host.type(" ok ")
            }
            #expect(r.host.document == " zorble went well. ok  zorble went well. ok ")
            #expect(learned.withLock { $0 }.isEmpty)
        }
    }

    /// Tab, then ⌘Z as the next key within a few seconds (`Autocomplete.undoWindow`): taken back, so not taken at all
    /// (a habitual Tab after a pause in Jupyter, say): counted as waved away and undone, and learned so for the app, where
    /// it may stop. Later, or after another key, ⌘Z is the user's own.
    @Test func aTabTakenBackWithCommandZIsNotTaken() {
        withInterfaceLanguage("en") {
            let undo = KeyEvent(keyCode: 0x06, characters: "z", charactersIgnoringModifiers: "z", modifiers: .command)
            let store = AutocompleteStore()
            store.learn { learning in for _ in 0..<29 { _ = learning.record(false, in: "com.example.editor") } }
            let r = rig(store: store)
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            r.clock.advance(0.5)
            #expect(r.host.press(FakeHost.tab))
            #expect(store.metrics.accepted == 1 && store.metrics.acceptedCharacters == 16 && !store.stopped(in: "com.example.editor"))
            r.clock.advance(3)
            r.host.press(undo)
            let metrics = store.metrics
            #expect(metrics.accepted == 0 && metrics.undone == 1 && metrics.dismissed == 1 && metrics.acceptedCharacters == 0)
            #expect(store.learning.apps["com.example.editor"]?.outcomes.contains(true) == false)
            #expect(store.stopped(in: "com.example.editor") && metrics.stoppedApps == 1)
            #expect(r.host.noticeAlone == "Autocomplete wasn't used in Editor, so it stopped there (Settings → Apps can keep it on)")
            // Too late, or not the next key: the user's own ⌘Z, the Tab taken.
            for (wait, key) in [(6.0, nil), (0.5, FakeHost.space)] as [(TimeInterval, KeyEvent?)] {
                let later = rig()
                later.host.type("Hello wor")
                later.pauseEnds(expecting: "x")
                later.clock.advance(0.5)
                later.host.press(FakeHost.tab)
                later.clock.advance(wait)
                if let key { later.host.press(key) }
                later.host.press(undo)
                #expect(later.store.metrics.accepted == 1 && later.store.metrics.undone == 0, "\(wait)")
            }
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

    /// The model's answer to what ends "Hello wor" or "Hello worl" (the rest of "Hello world, how are you?"), and to
    /// anything else.
    static func helloWorld() -> ContinuingModel {
        ContinuingModel { prompt in
            prompt.hasSuffix("Hello wor</before>") ? "ld, how are you?" : prompt.hasSuffix("Hello worl</before>") ? "d, how are you?" : " and so on."
        }
    }

    @Test func escTakesItDownAndAnyOtherKeyGoesOnToTheApp() {
        withInterfaceLanguage("en") {
            let r = rig(model: Self.helloWorld())
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost == "ld, how are you?")
            #expect(r.host.press(FakeHost.escape))
            #expect(r.host.ghost == nil)
            // Not this one: not shown again for the same text, nor as it's typed along, from what was kept or said again
            // by the model.
            r.host.type("l")
            r.pauseEnds()
            #expect(r.host.ghost == nil && r.model.requests.count == 2 && r.store.metrics.fromCache == 0)
            r.host.press(KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}"))
            r.host.document = "Hello wo"
            r.host.type("r")
            r.pauseEnds()
            #expect(r.host.ghost == nil && r.model.requests.count == 3 && r.store.metrics.shown == 1)
            // Other text: suggestions as before; any key but Tab and Esc goes on to the app.
            r.host.document = "Hello there"
            r.host.type(",")
            r.pauseEnds(expecting: "x")
            #expect(r.host.ghost == " and so on.")
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

    /// A field the shell tells is a password field when it's read (the Mac's Accessibility), secure input off: nothing of it
    /// is sent, nor what was typed into it where it tells nothing of its text, and it's off in that field from then on.
    @Test func aFieldMarkedSecureWhenReadSendsNothingNotEvenWhatWasTyped() {
        withInterfaceLanguage("en") {
            let r = rig()
            r.host.tellsNoText = true
            r.host.passwordField = true
            r.host.type("hunter2pass")
            r.pauseEnds()
            #expect(r.host.fieldReads == 1 && r.model.requests.isEmpty && r.host.ghost == nil)
            r.host.type("x")
            r.pauseEnds()
            #expect(r.host.fieldReads == 1 && r.model.requests.isEmpty && r.pauses.isEmpty, "off in the field")
            // Another field: on again.
            r.host.passwordField = false
            r.host.focus()
            r.host.type("Hello wor")
            r.pauseEnds(expecting: "x")
            #expect(r.model.requests.count == 1 && r.model.requests.first?.prompt == "<before>Hello wor</before>")
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
            #expect(r.host.timerDelays[r.pauses.last!] == 0.7)  // waved away often: it waits longer
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

    /// Turned on elsewhere than the input method's own switch (Settings → Assistant, a hand edit of the config file): seen
    /// as the next field takes the focus or the settings change, it is counted and every app starts over, as with the
    /// switch; the switch itself isn't counted twice.
    @Test func turnedOnByTheAssistantEveryAppStartsOver() {
        withInterfaceLanguage("en") {
            let store = AutocompleteStore()
            store.learn { learning in for _ in 0..<30 { _ = learning.record(false, in: "com.example.editor") } }
            let settings = Settings()
            settings.config.autocomplete = false
            let r = rig(settings, store: store)
            #expect(store.stopped(in: "com.example.editor") && store.metrics.turnedOn == 0)
            // "Turn on autocomplete", as Settings → Assistant applies it.
            _ = AIConfig.apply([.autocomplete(true)], to: &settings.config)
            r.host.focus()
            #expect(!store.stopped(in: "com.example.editor") && store.metrics.turnedOn == 1)
            r.host.type("Hello wor")
            #expect(!r.pauses.isEmpty)
            // Off the same way, within a day: counted as the switch counts it.
            _ = AIConfig.apply([.autocomplete(false)], to: &settings.config)
            r.host.send(.configChanged)
            #expect(store.metrics.turnedOffWithinADay == 1)
            // The input method's own switch says so itself (`switched`): seen after it, it isn't counted again.
            settings.config.autocomplete = true
            store.switched(on: true)
            r.host.focus()
            #expect(store.metrics.turnedOn == 2)
            // What was kept says what was seen last: another launch counts nothing for the same switch.
            let defaults = MemoryKeyValueStore()
            let first = AutocompleteStore(defaults: defaults)
            first.saw(switch: true)
            let relaunched = AutocompleteStore(defaults: defaults)
            relaunched.saw(switch: true)
            #expect(relaunched.metrics.turnedOn == 0)
        }
    }

    /// The on-device model can't run (and no cloud provider was agreed to): nothing would answer, so the field isn't even
    /// read at the pause; said once.
    @Test func theOnDeviceModelUnavailableShowsNothingAndSaysSoOnce() {
        withInterfaceLanguage("en") {
            let r = rig(model: ContinuingModel(.appleIntelligenceNotEnabled))
            r.host.type("Hello wor")
            r.pauseEnds()
            r.host.settle(timeout: 5) { r.host.noticeAlone != nil }
            #expect(r.host.ghost == nil && r.host.noticeAlone?.hasPrefix("Autocomplete needs Apple Intelligence on this Mac") == true)
            #expect(r.host.fieldReads == 0 && r.model.requests.isEmpty && r.store.metrics.asked == 0)
            r.host.type("l")
            r.pauseEnds()
            #expect(r.host.fieldReads == 0)
            #expect(r.host.outputs.filter { if case let .notice(text) = $0 { text.hasPrefix("Autocomplete needs") } else { false } }.count == 1)
        }
    }

    @Test func aCloudProviderAgreedToWaitsLonger() {
        withInterfaceLanguage("en") {
            let settings = Settings()
            settings.config.provider = .anthropic
            Autocomplete.answer(true, in: &settings.config)
            let r = rig(settings)
            r.host.type("Hi")
            #expect(r.host.timerDelays[r.pauses.last!] == 0.5)
        }
    }

    @Test func theModelIsLoadedWhenAFieldTakesTheFocusAtMostOnceAMinute() {
        withInterfaceLanguage("en") {
            let store = AutocompleteStore()
            #expect(store.prewarmDue(at: 10) && !store.prewarmDue(at: 30) && store.prewarmDue(at: 71))
        }
    }
}
