import Foundation

/// A field's switch of its input with Shift before anything was typed in it (Settings v2 §3.1), followed from the focus
/// to the field's first key that types or composes: the input it was corrected to then teaches its app
/// (`LearnedStore.corrected`: twice in a row, the app's fields start in it). A switch after that key teaches nothing,
/// and a field left before typing anything tells nothing.
struct StartingCorrection {
    /// The input the field was in as it took the focus (as its starting input was applied); nil once a key typed in it,
    /// and where nothing is learned (no app, a password field).
    var started: Input?
    /// The input a tap of Shift last left it in, before anything was typed.
    var switchedTo: Input?
}

/// What the session says of what an app learned, in the interface language.
struct LearnedMessages {
    let words: InterfaceWords

    init(language: String) { words = InterfaceWords(language: language) }

    /// `app` (its name) starts in `input` (its name) from now on.
    func startsIn(_ app: String, _ input: String) -> String {
        words.tr("\(app) 以后用\(input)开始", "\(app) starts in \(input) from now on")
    }
}

extension InputSession {
    /// A field took the focus, its starting input applied: what Shift does in it before anything is typed is followed,
    /// from the app's starting input (`appliedDefaultInput`), not the input the composer happens to be in: another field
    /// of the same session (a page's next field in Chrome, an Electron window's) keeps the last one's input, and a
    /// switch back to the app's own from there is no correction.
    func learningFocused() {
        let learns = field.app?.isEmpty == false && !secureInputActive()
        startingCorrection = StartingCorrection(started: learns ? appliedDefaultInput ?? composer.input : nil)
    }

    /// The field's starting input applied again before anything was typed or switched in it (the engine came, the
    /// settings changed): that is where it started.
    func learningApplied() {
        guard startingCorrection.started != nil, startingCorrection.switchedTo == nil else { return }
        startingCorrection.started = appliedDefaultInput ?? composer.input
    }

    /// A modifier changed (a tap of Shift, say) with the field in `before`: the input it is in now, if that changed
    /// before anything was typed.
    func learningSwitched(from before: Input) {
        guard startingCorrection.started != nil, composer.input != before else { return }
        startingCorrection.switchedTo = composer.input
    }

    /// `key` is about to be handled: the first in the field that types or composes ends what Shift may teach there. A
    /// field it finds corrected to another input than it started in tells its app (`LearnedStore.corrected`). What was
    /// learned now, to be said once the key is handled; nil: nothing.
    func learningTyped(_ key: KeyEvent) -> String? {
        guard let started = startingCorrection.started, key.printableText != nil || key.isDeadKey else { return nil }
        let switched = startingCorrection.switchedTo
        startingCorrection = StartingCorrection()
        guard let app = field.app, let input = switched, input == composer.input, input != started else { return nil }
        guard services.learned.corrected(app, to: input) else { return nil }
        // This field is in it already: the settings applied again later don't switch it back or over.
        appliedDefaultInput = input
        log.notice("an app learned its starting input (\(input == .code ? "Code" : "a language"))")
        let coding = services.loadSettings().codingLanguage.map { CodingLanguagePack.title(of: $0) }
        let name = SessionText.inputName(input, language: UIText.language, coding: coding)
        return LearnedMessages(language: UIText.language).startsIn(services.appName(app) ?? SettingsSchema.appName(app), name)
    }
}
