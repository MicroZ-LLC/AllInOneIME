import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Autocomplete (续写) diagnosis of release-0.6.7 (8eccc069), the build on the owner's iMac. Each test is one bug, marked
// AC-<n> as in the diagnosis report, and fails until that bug is fixed; the cases marked "control" pass today and keep a
// fix from going too far. The model answers marked "real" are what Apple's on-device model (Mac mini M4, macOS 27)
// answered, word for word, to the request 0.6.7 sends (`Prompt.autocompleteRequest`, temperature 0.2). Nothing here calls
// a model or the network.

/// Stands in for the on-device model: answers each request with `answer(prompt)` at once, and records the prompts.
final class DiagnosisModel: AppleModelBackend, @unchecked Sendable {
    let availability = AppleModelAvailability.available
    let contextSize = 8192
    let supportedLanguages: Set<String> = ["en", "zh", "ja", "fr", "de", "es"]
    private let lock = NSLock()
    private var _prompts: [String] = []
    let answer: @Sendable (String) -> String

    init(_ answer: @escaping @Sendable (String) -> String) { self.answer = answer }

    var prompts: [String] { lock.withLock { _prompts } }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        lock.withLock { _prompts.append(request.prompt) }
        let text = answer(request.prompt)
        return AsyncThrowingStream { continuation in
            continuation.yield(AppleModelSnapshot(text: text))
            continuation.finish()
        }
    }
}

/// The session's time (`SessionServices.uptime`), moved by the test.
final class DiagnosisClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 5000
    var now: TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

/// What the model answered (`raw`) after `before`, and what should be shown after the caret (nil: nothing).
struct TrimCase: Sendable, CustomTestStringConvertible {
    let raw: String
    let before: String
    let shown: String?
    let note: String

    init(_ raw: String, after before: String, shows shown: String?, _ note: String) {
        (self.raw, self.before, self.shown, self.note) = (raw, before, shown, note)
    }

    var testDescription: String { "\(note): \(before.debugDescription) + \(raw.debugDescription)" }
}

@Suite(.serialized)
struct AutocompleteDiagnosisTests {
    /// The owner's settings: Bedrock with Claude Haiku picked, autocomplete on but never asked about the cloud (no
    /// `autocompleteCloud`), "frobnicate" learned as an English word; typing English. Not the owner's "~" command
    /// trigger: a session puts its trigger in the process's interface text (`UIText.commandTrigger`), which the suites
    /// running alongside read as @ (CommandTriggerTextTests, SessionTextTests).
    static func ownersConfig() -> Config {
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .bedrock
        config.modelId = "us.anthropic.claude-haiku-5-5"
        config.autocomplete = true
        config.autocompleteCloud = nil
        config.englishWords = ["frobnicate"]
        config.setOrder([Language.english])
        config.setOrder([OutputLanguage.english, .chinese])
        return config
    }

    final class Settings: @unchecked Sendable {
        var config: Config
        init(_ config: Config = AutocompleteDiagnosisTests.ownersConfig()) { self.config = config }
    }

    /// A text field typed into through a FakeHost, its session's model a `DiagnosisModel`.
    struct Field {
        let host: FakeHost
        let model: DiagnosisModel
        let clock: DiagnosisClock
        let store: AutocompleteStore
        /// How often the cloud's credentials or keys were asked for: never, on the on-device model.
        let cloudAsked: Locked<Int>

        var pauses: [TimerID] { host.timers.filter { if case .autocomplete = $0 { true } else { false } } }

        /// The pause runs out: the field is read, a request (if any) is answered and handled.
        func pauseEnds() {
            clock.advance(0.2)
            host.fireTimers { if case .autocomplete = $0 { true } else { false } }
            host.settle(timeout: 10) { host.session.autocomplete.asked == nil }
        }

        /// The caret put after the first `caret` characters of `document` (UTF-16), as a click or an arrow key would,
        /// without the session hearing of it (the pause then reads the field as it is).
        func place(_ document: String, caret: Int) {
            host.document = document
            host.selection = caret..<caret
        }
    }

    func field(_ settings: Settings = Settings(), app: String = "com.apple.TextEdit", store: AutocompleteStore = AutocompleteStore(),
               model: DiagnosisModel) -> Field {
        let clock = DiagnosisClock()
        let cloudAsked = Locked(initialState: 0)
        let converter = Converter(loadConfig: { settings.config },
                                  loadCredentials: { _ in cloudAsked.withLock { $0 += 1 }; throw ProviderError.missingKey(.bedrock) },
                                  loadKey: { _, _ in cloudAsked.withLock { $0 += 1 }; return nil },
                                  loadJargon: { _ in [] }, appleModel: model)
        var services = SessionServices(converter: converter, loadSettings: { settings.config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        services.autocomplete = store
        services.appName = { ["com.apple.TextEdit": "TextEdit", "com.apple.Notes": "Notes", "com.example.editor": "Editor"][$0] }
        let host = FakeHost(services: services)
        host.app = app
        host.appTypesKeys = true
        host.focus()
        return Field(host: host, model: model, clock: clock, store: store, cloudAsked: cloudAsked)
    }

    // MARK: - AC-1: "Frobnicate"

    /// The owner's case as reproduced: "iss" typed at the end of a line, with "Frobnicate" (the word just taught to
    /// English-word learning, as macOS capitalizes it at a line's start) on the line after it. The request goes to the
    /// on-device model, not Haiku (no yes to the cloud), with the text after the caret; the model answers with that text,
    /// 10 characters, and it is shown.
    @Test(.bug(id: "AC-1", "a suggestion that copies the text after the caret is shown"))
    func theOwnersFrobnicateIsTheTextAfterTheCaretCopied() {
        withInterfaceLanguage("en") {
            // Real: the on-device model's answers to these two requests (3 of 3 and 5 of 5 runs).
            let model = DiagnosisModel { prompt in
                prompt == "<before>iss</before>\n<after>\nFrobnicate</after>" ? "Frobnicate" : "<after>iss</after>"
            }
            let f = field(model: model)
            f.host.type("iss")
            f.place("iss\nFrobnicate", caret: 3)
            f.pauseEnds()
            // What happened (passes): the on-device model was asked, the cloud never; what it was sent.
            #expect(Autocomplete.route(Self.ownersConfig()) == .onDevice && f.cloudAsked.withLock { $0 } == 0)
            #expect(model.prompts == ["<before>iss</before>\n<after>\nFrobnicate</after>"])
            // The bug: the text right after the caret, said again by the model, is up as the suggestion.
            #expect(f.host.ghost == nil, "AC-1: shown \(f.host.ghost.map { "“\($0)”" } ?? "nothing"), the word already after the caret")
            f.clock.advance(0.5)
            f.host.press(FakeHost.tab)
            #expect(!f.host.document.hasPrefix("issFrobnicate"), "AC-1: Tab made the field \(f.host.document.debugDescription)")
        }
    }

    /// The same with the word before the caret: a small model copies a word of the field after a partial word.
    @Test(.bug(id: "AC-1", "a suggestion that copies a word of the field after a partial word is shown"))
    func aWordOfTheFieldCopiedAfterAPartialWordIsNotShown() {
        withInterfaceLanguage("en") {
            // Real: 3 of 3 runs.
            let model = DiagnosisModel { _ in "<after>frobnicate</after>" }
            let f = field(model: model)
            f.host.document = "Testing English words: frobnicate\n"
            f.host.type("iss")
            f.pauseEnds()
            #expect(model.prompts == ["<before>Testing English words: frobnicate\niss</before>"])
            #expect(f.host.ghost == nil, "AC-1: shown \(f.host.ghost.map { "“\($0)”" } ?? "nothing") right after “iss”")
        }
    }

    /// Kept suggestions are found by the text before the caret alone, in any field of any app: the one AC-1 made in
    /// TextEdit (for "iss" with "Frobnicate" after it) comes up in an empty note that only says "iss", with no request.
    @Test(.bug(id: "AC-7", "the kept suggestions ignore the text after the caret and the app"))
    func aSuggestionKeptForOneFieldIsNotShownInAnotherThatDiffersAfterTheCaret() {
        withInterfaceLanguage("en") {
            let model = DiagnosisModel { prompt in
                prompt == "<before>iss</before>\n<after>\nFrobnicate</after>" ? "Frobnicate" : "<after>ue</after>"
            }
            let store = AutocompleteStore()
            let editor = field(store: store, model: model)
            editor.host.type("iss")
            editor.place("iss\nFrobnicate", caret: 3)
            editor.pauseEnds()
            editor.host.press(FakeHost.escape)
            let notes = field(app: "com.apple.Notes", store: store, model: model)
            notes.host.type("iss")
            notes.pauseEnds()
            #expect(model.prompts.count == 2, "AC-7: the note's “iss” wasn't asked about: \(model.prompts)")
            #expect(notes.host.ghost != "Frobnicate", "AC-7: TextEdit's suggestion, made for the text after its caret, is up in Notes")
        }
    }

    // MARK: - The owner's "iss", typical on-device answers

    static let issAnswers: [TrimCase] = [
        TrimCase("", after: "iss", shows: nil, "control, nothing"),
        TrimCase("<after></after>", after: "iss", shows: nil, "control, empty tags"),
        TrimCase("<after>ue</after>", after: "iss", shows: "ue", "control, the word finished"),
        TrimCase("ue to reschedule.", after: "iss", shows: "ue to reschedule.", "control, real with few-shot examples"),
        TrimCase("<after>iss</after>", after: "iss", shows: nil, "AC-2, real (5 of 5): the partial word again"),
        TrimCase("iss", after: "iss", shows: nil, "AC-2, the partial word again, no tags"),
        TrimCase("<after>issue</after>", after: "iss", shows: "ue", "AC-2, the whole word, its start again"),
        TrimCase("Frobnicate", after: "iss", shows: nil, "AC-5, real (with Frobnicate after the caret): a new word glued on"),
    ]

    /// "iss" typed into an empty field with the owner's settings, the model answering as the on-device one does.
    @Test(.bug(id: "AC-2"), .bug(id: "AC-5"), arguments: issAnswers)
    func whatIsShownAfterTheOwnersIss(_ answer: TrimCase) {
        withInterfaceLanguage("en") {
            let f = field(model: DiagnosisModel { _ in answer.raw })
            f.host.type("iss")
            f.pauseEnds()
            #expect(f.model.prompts == ["<before>iss</before>"] && f.cloudAsked.withLock { $0 } == 0)
            #expect(f.host.ghost == answer.shown, "\(answer.note): shown \(f.host.ghost.map { "“\($0)”" } ?? "nothing")")
        }
    }

    // MARK: - AC-2: the text said again

    static let echoes: [TrimCase] = [
        TrimCase("<after>iss</after>", after: "iss", shows: nil, "real"),
        TrimCase("<after>iss", after: "Frobnicate\niss", shows: nil, "real"),
        TrimCase("<after>iss</after>", after: "Frobnicate. iss", shows: nil, "real"),
        TrimCase("<after>the rep</after>", after: "I will send you the rep", shows: nil, "real"),
        TrimCase("iss.", after: "Testing English words: frobnicate\niss", shows: nil, "real with few-shot examples"),
        TrimCase("<after>issue</after>", after: "iss", shows: "ue", "the whole word"),
        TrimCase("<after>about the iss</after>", after: "Hello, I wanted to ask about the iss", shows: nil, "control, real (8+ characters)"),
        TrimCase("Please find attached the", after: "Please find attached the", shows: nil, "control, real"),
        TrimCase("<after>that's right.</after>", after: "I think that", shows: " that's right.", "control: only starts like the text's end"),
    ]

    /// `droppingEcho` only drops an echo of 8 characters or more: the end of the text said again in fewer (the partial
    /// word, the last two words) is shown after it ("iss" + "iss", "the rep" + " the rep").
    @Test(.bug(id: "AC-2", "the end of the text said again in under 8 characters is shown"), arguments: echoes)
    func anAnswerThatSaysTheTextsEndAgainIsNotShown(_ c: TrimCase) {
        #expect(Autocomplete.trimmed(c.raw, before: c.before) == c.shown, "\(c.note)")
    }

    // MARK: - AC-3, AC-4: the space before a new word

    static let shortWords: [TrimCase] = [
        TrimCase("<after>there</after>", after: "Hi", shows: " there", "real"),
        TrimCase("<after>another time?</after>", after: "Can we move the meeting to", shows: " another time?", "real"),
        TrimCase("<after>the meeting</after>", after: "Looking forward to", shows: " the meeting", "real"),
        TrimCase("<after>need more details</after>", after: "Let me know if you have any questions or", shows: " need more details", "real"),
        TrimCase("<after>go ahead</after>", after: "I think we should", shows: " go ahead", "control, real"),
        TrimCase("<after>ld</after>", after: "Hello wor", shows: "ld", "control, real"),
        TrimCase("<after>is</after>", after: "Th", shows: "is", "control, real"),
        TrimCase("<after>sure</after>", after: "ok", shows: " sure", "control, real (ok is in the tech list)"),
    ]

    /// The word list `needsSpace` goes by (`RedactionWords`, web2's words of 3 letters or more) has no word of one or two
    /// letters, so after "to", "or", "Hi", "is", "we" … the next word is glued on ("toanother", "Hithere").
    @Test(.bug(id: "AC-3", "no space after a word of one or two letters"), arguments: shortWords)
    func aNewWordAfterAShortWordGetsItsSpace(_ c: TrimCase) {
        #expect(Autocomplete.trimmed(c.raw, before: c.before) == c.shown, "\(c.note)")
    }

    static let punctuation: [TrimCase] = [
        TrimCase("<after>meeting</after>", after: "Could you please send me the slides from yesterday's", shows: " meeting", "real"),
        TrimCase("<after>what's up</after>", after: "Hi John,", shows: " what's up", "real answer (asked after “Hi John, ”)"),
        TrimCase("<after>I will review it today.</after>", after: "Thanks for the update.", shows: " I will review it today.", "after a full stop"),
        TrimCase("<after>on the second floor</after>", after: "The meeting is at 3pm in room 4", shows: " on the second floor", "after a digit"),
        TrimCase("<after>5 of the app</after>", after: "We shipped version 3.", shows: "5 of the app", "control: a decimal"),
        TrimCase("<after>明天见</after>", after: "好的，", shows: "明天见", "control: Chinese"),
        TrimCase("<after>meeting?</after>", after: "Could you please send me the slides from yesterday's ", shows: "meeting?", "control, real: after a space"),
    ]

    /// `needsSpace` only looks at Latin letters: after a comma, a full stop, a digit or "yesterday's" the next word is glued
    /// on ("John,what's", "update.I", "4on").
    @Test(.bug(id: "AC-4", "no space after punctuation, a digit or an apostrophe"), arguments: punctuation)
    func aNewWordAfterPunctuationGetsItsSpace(_ c: TrimCase) {
        #expect(Autocomplete.trimmed(c.raw, before: c.before) == c.shown, "\(c.note)")
    }

    // MARK: - AC-5: a partial word and a new one

    static let gluedWords: [TrimCase] = [
        TrimCase("<after>later</after>", after: "See you tomo", shows: nil, "real: “tomolater”"),
        TrimCase("<after>it means to fiddle with something</after>", after: "I learned the word frobnicate today. iss", shows: nil, "real"),
        TrimCase("Frobnicate", after: "iss", shows: nil, "real: a capital right after small letters"),
        TrimCase("<after>meeting</after>", after: "Thanks for the mee", shows: "ting", "a whole word for a partial one: its rest"),
        TrimCase("<after>ld</after>", after: "Hello wor", shows: "ld", "control, real"),
        TrimCase("<after>rrow!</after>", after: "See you tomo", shows: "rrow!", "control"),
    ]

    /// When the text ends in the middle of a word, an answer that doesn't finish it (a new word, the whole word again) is
    /// glued onto it: "tomo" + "later", "iss" + "Frobnicate", "mee" + "meeting".
    @Test(.bug(id: "AC-5", "an unfinished word gets an unrelated word glued on"), arguments: gluedWords)
    func anUnfinishedWordIsFinishedOrNothingIsShown(_ c: TrimCase) {
        #expect(Autocomplete.trimmed(c.raw, before: c.before) == c.shown, "\(c.note)")
    }

    // MARK: - AC-11: abbreviations

    static let abbreviations: [TrimCase] = [
        TrimCase(" Mr. Smith about the delay.", after: "Please tell", shows: " Mr. Smith about the delay.", "a title"),
        TrimCase(", e.g. grep or ripgrep.", after: "Use a search tool", shows: ", e.g. grep or ripgrep.", "e.g."),
        TrimCase(" version 3.5 of the app", after: "We shipped", shows: " version 3.5 of the app", "control: a decimal"),
    ]

    /// `sentenceEnd` takes any full stop before a space for a sentence's end: a suggestion is cut after "Mr." or "e.g.".
    @Test(.bug(id: "AC-11", "a suggestion is cut after an abbreviation's full stop"), arguments: abbreviations)
    func anAbbreviationDoesNotEndTheSuggestion(_ c: TrimCase) {
        #expect(Autocomplete.trimmed(c.raw, before: c.before) == c.shown, "\(c.note)")
    }

    // MARK: - AC-8: an app set to always

    /// In an app set to autocomplete always (Settings → Apps), the 30th suggestion in a row not taken says it stopped
    /// there, though it doesn't (`Autocomplete.isOn` goes by the app's choice first).
    @Test(.bug(id: "AC-8", "“it stopped there” is said in an app set to Always, where it doesn't stop"))
    func anAppSetToAlwaysIsNotSaidToHaveStopped() {
        withInterfaceLanguage("en") {
            let settings = Settings()
            settings.config.appProfiles = ["com.example.editor": AppProfile(autocomplete: true)]
            let store = AutocompleteStore()
            store.learn { learning in for _ in 0..<29 { _ = learning.record(false, in: "com.example.editor") } }
            let f = field(settings, app: "com.example.editor", store: store, model: DiagnosisModel { _ in "<after>ld, how are you?</after>" })
            f.host.type("Hello wor")
            f.pauseEnds()
            #expect(f.host.ghost == "ld, how are you?")
            #expect(f.host.press(FakeHost.escape))
            let said = f.host.outputs.compactMap { if case let .notice(text) = $0 { text } else { nil } }
            #expect(!said.contains { $0.contains("stopped") }, "AC-8: said \(said)")
            #expect(store.metrics.stoppedApps == 0, "AC-8: counted as stopped")
            f.host.type("l")
            #expect(!f.pauses.isEmpty, "control: it goes on in an app set to always")
        }
    }

    // MARK: - AC-9: the yes to the cloud

    /// The yes is to the provider named in the question ("Use Amazon Bedrock for Autocomplete?"), but it is kept as a plain
    /// Bool: once the provider changes (here, or on another Mac: "provider" is synced through iCloud, "autocompleteCloud"
    /// isn't), each pause sends the text before the caret to the new one, and nothing asks.
    @Test(.bug(id: "AC-9", "the yes to one cloud provider sends text to another"))
    func theYesToOneProviderIsNotAYesToAnother() {
        var config = Self.ownersConfig()
        config.autocompleteCloud = true  // "Use Amazon Bedrock" in the question
        #expect(Autocomplete.route(config) == .cloud(.bedrock), "control")
        #expect(ICloudSync.settingsKeys.contains("provider") && ICloudSync.neverSynced.contains("autocompleteCloud"), "control")
        config.provider = .openai
        config.openai = ProviderSettings(model: "gpt-small", baseURL: "https://api.openai.com/v1")
        #expect(Autocomplete.route(config) == .onDevice, "AC-9: now \(Autocomplete.route(config)), never asked about OpenAI")
        #expect(Autocomplete.asksForCloud(config), "AC-9: turning it on again wouldn't ask")
    }
}
