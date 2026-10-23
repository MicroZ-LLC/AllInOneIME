import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The suggestions kept (`Autocomplete.Cache`): for the text before the caret and after it, in the app they were made in
/// (AC-7); one waved away with Esc is not shown again for that text, kept or said again by the model (AC-10).
@Suite(.serialized)
struct AutocompleteKeptTests {
    static let iss = Autocomplete.Context(before: "iss", after: "\nFrobnicate")

    @Test(.bug(id: "AC-7", "the kept suggestions ignore the text after the caret and the app"))
    func aSuggestionIsKeptForTheTextAfterTheCaretAndTheApp() {
        var cache = Autocomplete.Cache()
        cache.add(Autocomplete.Cache.Entry("ue", for: Self.iss, in: "com.apple.TextEdit"))
        #expect(cache.kept(for: Self.iss, in: "com.apple.textedit")?.rest == "ue")
        #expect(cache.kept(for: Autocomplete.Context(before: "issu", after: "\nFrobnicate"), in: "com.apple.TextEdit")?.rest == "e")
        // Another text after the caret, another app, an app not told: not the same text.
        #expect(cache.kept(for: Autocomplete.Context(before: "iss"), in: "com.apple.TextEdit") == nil)
        #expect(cache.kept(for: Self.iss, in: "com.apple.Notes") == nil)
        #expect(cache.kept(for: Self.iss, in: nil) == nil)
        // Kept for each: one for each.
        cache.add(Autocomplete.Cache.Entry("ue to fix", for: Self.iss, in: "com.apple.Notes"))
        #expect(cache.entries.count == 2 && cache.kept(for: Self.iss, in: "com.apple.TextEdit")?.rest == "ue")
    }

    @Test(.bug(id: "AC-10", "Esc takes a suggestion down, and it comes back for the same text"))
    func oneWavedAwayGoesAndIsNotShownAgainForItsText() {
        var cache = Autocomplete.Cache()
        let hello = Autocomplete.Context(before: "Hello")
        let entry = Autocomplete.Cache.Entry(" world, how are you?", for: hello, in: "com.example.editor")
        cache.add(entry)
        cache.reject(entry)
        #expect(cache.entries.isEmpty && cache.kept(for: hello, in: "com.example.editor") == nil)
        // The same words for the same text, typed along or not, but for spaces and its closing mark: waved away.
        #expect(cache.isRejected(" world, how are you?", for: hello, in: "com.example.editor"))
        #expect(cache.isRejected("world, how are you", for: hello, in: "com.example.editor"))
        #expect(cache.isRejected("ld, how are you?", for: Autocomplete.Context(before: "Hello wor"), in: "com.example.editor"))
        // Another suggestion, other text, another app: not.
        #expect(!cache.isRejected(" there, how are you?", for: hello, in: "com.example.editor"))
        #expect(!cache.isRejected(" world, how are you?", for: Autocomplete.Context(before: "Oh, Hello"), in: "com.example.editor"))
        #expect(!cache.isRejected(" world, how are you?", for: hello, in: "com.apple.Notes"))
        // A new suggestion for the text is kept and shown.
        cache.add(Autocomplete.Cache.Entry(" there!", for: hello, in: "com.example.editor"))
        #expect(cache.kept(for: hello, in: "com.example.editor")?.rest == " there!")
        for n in 0..<25 { cache.reject(Autocomplete.Cache.Entry(" \(n).", for: Autocomplete.Context(before: "Item \(n)"), in: nil)) }
        #expect(cache.rejected.count == Autocomplete.Cache.capacity)
    }

    // MARK: - In a session

    func field(_ answer: @escaping @Sendable (String) -> String, app: String = "com.example.editor",
               store: AutocompleteStore = AutocompleteStore()) -> (host: FakeHost, model: ContinuingModel, clock: Uptime) {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.autocomplete = true
        let fixed = config
        let model = ContinuingModel(answer: answer)
        let clock = Uptime()
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, appleModel: model), loadSettings: { fixed })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        services.autocomplete = store
        let host = FakeHost(services: services)
        host.app = app
        host.appTypesKeys = true
        host.focus()
        return (host, model, clock)
    }

    func pauseEnds(_ host: FakeHost, _ clock: Uptime) {
        clock.advance(1)
        host.fireTimers { if case .autocomplete = $0 { true } else { false } }
        host.settle(timeout: 5) { host.session.autocomplete.asked == nil }
    }

    /// Esc on a suggestion typed along: deleted back and typed again, or typed on, it isn't shown again, though the
    /// model says it again; another one is. The model's answers are for the text it is asked about.
    @Test(.bug(id: "AC-10", "Esc takes a suggestion down, and it comes back for the same text"))
    func escMeansNotThisOne() {
        withInterfaceLanguage("en") {
            let (host, model, clock) = field { prompt in
                let before = prompt.components(separatedBy: "</before>")[0].replacingOccurrences(of: "<before>", with: "")
                let sentence = "See you tomorrow at noon."
                if before.hasPrefix("See you") { return String(sentence.dropFirst(before.count)) }
                return " and more."
            }
            host.type("See you")
            pauseEnds(host, clock)
            #expect(host.ghost == " tomorrow at noon.")
            host.type(" to")
            #expect(host.ghost == "morrow at noon.")
            #expect(host.press(FakeHost.escape) && host.ghost == nil)
            // Typed on: asked again, the same answer, not shown.
            host.type("m")
            pauseEnds(host, clock)
            #expect(model.requests.count == 2 && host.ghost == nil)
            // Deleted back to where it was first shown: not kept any more, asked, said again, not shown.
            host.document = "See yo"
            host.type("u")
            pauseEnds(host, clock)
            #expect(model.requests.count == 3 && host.ghost == nil)
            // Other text: its own suggestion.
            host.document = "Thanks, se"
            host.type("e")
            pauseEnds(host, clock)
            #expect(host.ghost == " and more.")
        }
    }

    /// Esc in one app: the same suggestion for the same text is still shown in another.
    @Test(.bug(id: "AC-10", "Esc takes a suggestion down, and it comes back for the same text"))
    func notThisOneInThisApp() {
        withInterfaceLanguage("en") {
            let store = AutocompleteStore()
            let editor = field({ _ in "ld, how are you?" }, store: store)
            editor.host.type("Hello wor")
            pauseEnds(editor.host, editor.clock)
            #expect(editor.host.press(FakeHost.escape))
            let notes = field({ _ in "ld, how are you?" }, app: "com.apple.Notes", store: store)
            notes.host.type("Hello wor")
            pauseEnds(notes.host, notes.clock)
            #expect(notes.host.ghost == "ld, how are you?")
        }
    }
}
