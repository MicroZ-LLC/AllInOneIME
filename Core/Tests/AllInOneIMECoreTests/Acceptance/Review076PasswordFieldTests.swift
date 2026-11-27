import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Reproductions for the 0.7.6 review's privacy items (AGENTS.md rule 20), written from the review's text by the
// independent test author, each failing on the code as reviewed for the item's own reason:
//  1. While the shell's answer to "is this a password field?" hasn't come back yet (asked off the key's thread,
//     `SessionOutput.readPasswordField`), `@reply` reads the text around the caret and sends it: a field not told yet
//     counts as "allowed" (`InputSession.nothingLeavesDevice`). Only the pending case is tested; what a field the shell
//     couldn't tell (`PasswordField.unknown`) may do is the owner's decision and isn't asserted here.
//  2. A key that comes for a password manager's field the session was never told took the focus (no activate: the
//     session's own `field` is still the app before) is protected only while the key is handled: the English words
//     learned, suggestions' rows and autocomplete's pause, all done after it, go by the stale field.
//  3. A field first told to be no password field and later told to be one (a later read: autocomplete's pause, the
//     shell's own) keeps suggestions' rows and what was typed for them.
//
// How the field is played: a `FakeHost`. For item 1 each key reads what the session asks for, as the Mac does
// (`InputSession.fieldWants`, asked until it wants nothing more; whether it is a password field follows the key:
// `FieldContext.passwordFieldFollows`), and the answer is held back (`FakeHost.fieldReadsWait`). For item 2 each key
// says which app's field it is for (`FieldContext.field`), as the Mac's shell says with every key. What goes to the
// AI is read back from a recording stand-in for Apple's on-device model.

// MARK: - Fakes

/// Apple's on-device model, standing in for any provider: records every request, answers "OK".
private final class Review076Model: AppleModelBackend, @unchecked Sendable {
    let availability = AppleModelAvailability.available
    let contextSize = 4096
    let supportedLanguages: Set<String> = ["en", "fr", "zh"]
    private let sent = Locked<[AppleModelRequest]>(initialState: [])
    var requests: [AppleModelRequest] { sent.withLock { $0 } }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        sent.withLock { $0.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.yield(AppleModelSnapshot(text: "OK"))
            continuation.finish()
        }
    }

    /// Every request as one text: its instructions, its prompt and its examples.
    var texts: [String] {
        requests.map { ([$0.instructions, $0.prompt] + $0.examples.flatMap { [$0.prompt, $0.response] }).joined(separator: "\n") }
    }
}

private enum Review076Field {
    static let editor = "com.example.editor"
    static let passwordManagers = ["com.1password.1password", "com.bitwarden.desktop"]
    /// The text before and after the caret: a password field's own.
    static let before = "hunter2-PIN-4921 "
    static let after = " safe-combination-33-12-08"
    static let secrets = ["hunter2", "4921", "33-12-08"]

    /// What the field says for `key` as the Mac reads it: only what the session asks for, and whether it is a password
    /// field never with the key (told after it, unknown until then).
    static func macContext(_ host: FakeHost, for key: KeyEvent) -> FieldContext {
        let full = host.context
        var told = FieldContext(field: FieldInfo(app: host.app, terminal: host.terminal))
        while true {
            let missing = host.session.fieldWants(for: key, given: told).subtracting(told.read)
            if missing.isEmpty { return told }
            told.read.formUnion(missing)
            if missing.contains(.secure) { told.secure = full.secure }
            if missing.contains(.selectedRange) { told.selectedRange = full.selectedRange }
            if missing.contains(.selection) { told.selection = full.selection }
            if missing.contains(.beforeCaret) { told.beforeCaret = full.beforeCaret }
            if missing.contains(.text) { told.text = full.text }
            if missing.contains(.passwordField) { (told.passwordFieldUnknown, told.passwordFieldFollows) = (true, true) }
        }
    }

    /// A key that types `character`.
    static func key(_ character: Character) -> KeyEvent {
        character == "@" ? FakeHost.at : character == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: String(character))
    }
}

// MARK: - 1. The answer not back yet

@Suite(.serialized)
struct Review076PasswordFieldPendingTests {
    /// A field of an ordinary app that is a password field where secure input isn't on (`host.passwordField`), the
    /// caret between two texts; the shell's answer to whether it is one is held back until `answerFieldReads()`.
    private func host(model: Review076Model, passwordField: Bool) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .apple
        config.setOrder([Language.english, .chinese])
        config.setOrder([OutputLanguage.english, OutputLanguage("fr")])
        let fixed = config
        var services = SessionServices(
            converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
            loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        // English words may be learned here, so the first letter typed has the shell asked whether it's a password field.
        services.englishDictionary = { EnglishDictionary(["hello", "world"]) }
        let host = FakeHost(services: services)
        host.app = Review076Field.editor
        host.appTypesKeys = true
        host.passwordField = passwordField
        host.fieldReadsWait = true
        host.document = Review076Field.before + Review076Field.after
        host.caretOffset = (Review076Field.before as NSString).length
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    private func press(_ host: FakeHost, _ key: KeyEvent) {
        host.press(key, with: Review076Field.macContext(host, for: key))
    }

    /// "@reply", Tab, "ok": the draft that ⏎ would run, every key read as the Mac reads it.
    private func writeReply(_ host: FakeHost) {
        for character in "@reply" { press(host, Review076Field.key(character)) }
        press(host, FakeHost.tab)
        for character in "ok" { press(host, Review076Field.key(character)) }
    }

    private func leaks(_ texts: [String]) -> [String] {
        Review076Field.secrets.filter { secret in texts.contains { $0.contains(secret) } }
    }

    /// How a shell that tells everything with the key leaves the password field's answer pending.
    enum Pending: CaseIterable {
        /// Asked whether it is a password field, it says the answer comes after the key (`passwordFieldFollows`).
        case follows
        /// It reads everything but that (`FieldContext.read` without `.passwordField`).
        case notRead
    }

    /// Everything the field says with a key (`FakeHost.context`: the selection, the text around the caret), but whether
    /// it is a password field: that answer stays pending, `pending`'s way. (`FakeHost.context` as it is answers "none"
    /// with the key, which is no pending answer.)
    private func everythingButThePasswordField(_ host: FakeHost, _ pending: Pending) -> FieldContext {
        var context = host.context
        context.field = FieldInfo(app: host.app, terminal: host.terminal)
        switch pending {
        case .follows: (context.passwordFieldUnknown, context.passwordFieldFollows) = (true, true)
        case .notRead: context.read.remove(.passwordField)
        }
        return context
    }

    /// Item 1. The shell was asked whether the field is a password field and hasn't answered: ⏎ on `@reply ok` asks the
    /// field for no text, reads none and sends none of it; and none once the answer (a password field) comes. What was
    /// typed for the command is still the user's to send: `@reply ok` is run, not refused as in a known password field,
    /// and its draft doesn't go into the field as typed. (Failed as reviewed: not told yet was taken as "no", so ⏎
    /// asked for the text around the caret and it was sent.)
    @Test(arguments: Pending.allCases)
    func replyReadsNoTextWhileThePasswordFieldAnswerIsPending(_ pending: Pending) async throws {
        try await withInterfaceLanguage("en") {
            let model = Review076Model()
            let host = host(model: model, passwordField: true)
            writeReply(host)
            // The premise: asked, off the key's thread, and not answered yet.
            try #require(host.passwordFieldReads == 1, "the shell was asked once whether it's a password field: \(host.passwordFieldReads)")
            try #require(host.session.passwordField == nil, "not told yet: \(String(describing: host.session.passwordField))")
            try #require(host.composer.draftCommand == .reply, "the draft is @reply's: \(host.composer.draft)")

            for key in [FakeHost.enter, FakeHost.space] {
                let asked = host.session.fieldWants(for: key, given: FieldContext(read: .secure, field: FieldInfo(app: host.app)))
                #expect(!asked.contains(.text),
                        "\(key.characters.debugDescription) asks for the field's text while the answer is pending: \(asked)")
            }
            // A shell that tells everything with the key but whether it's a password field (reading is cheap there; that
            // answer is still the one awaited): the text around the caret is in the key's context, and the session
            // itself leaves it alone.
            let told = everythingButThePasswordField(host, pending)
            try #require(told.read.contains(.text) && told.text == FieldText(before: Review076Field.before, after: Review076Field.after),
                         "the key tells the text around the caret: \(String(describing: told.text))")
            host.press(FakeHost.enter, with: told)
            try #require(host.session.passwordField == nil, "still not told: \(String(describing: host.session.passwordField))")
            #expect(host.settle(timeout: 5) { !model.requests.isEmpty }, "@reply ok sent nothing while the answer was pending")
            #expect(leaks(model.texts).isEmpty, "the field's text was sent while the answer was pending: \(leaks(model.texts))")
            // Not refused (a field not told yet isn't a known password field), and not typed into the field as it stands.
            #expect(host.noticeAlone != InputSession.aiRefusal, "refused as an app with no AI")
            #expect(host.noticeAlone?.hasPrefix("Secure input is on") != true,
                    "refused as a password field: \(String(describing: host.noticeAlone))")
            #expect(host.document == Review076Field.before + Review076Field.after, "went into the field as typed: \(host.document)")
            #expect(!host.document.contains("@reply"), "the draft was typed into the field: \(host.document)")

            // The answer comes: a password field. Nothing of it goes out afterwards either.
            host.answerFieldReads()
            #expect(host.session.passwordField == .yes)
            host.settle(timeout: 0.5) { false }
            #expect(leaks(model.texts).isEmpty, "the field's text was sent: \(leaks(model.texts))")
        }
    }

    /// The control (passes today): once the shell has answered "no password field", `@reply` reads the text around the
    /// caret and sends it, as before.
    @Test func replyStillReadsTheTextOnceToldItIsNoPasswordField() async throws {
        try await withInterfaceLanguage("en") {
            let model = Review076Model()
            let host = host(model: model, passwordField: false)
            writeReply(host)
            try #require(host.passwordFieldReads == 1 && host.session.passwordField == nil)
            host.answerFieldReads()
            #expect(host.session.passwordField == .no)
            #expect(host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure)).contains(.text))
            host.press(FakeHost.enter)
            #expect(host.settle(timeout: 5) { !model.requests.isEmpty }, "@reply ok sent nothing")
            #expect(model.texts.contains { $0.contains("4921") && $0.contains("33-12-08") }, "the text around the caret isn't sent: \(model.texts)")
        }
    }
}

// MARK: - 2. A key with no activate before it

@Suite(.serialized, SuggestionsOneAtATime())
struct Review076KeyWithoutActivateTests {
    final class Learned: @unchecked Sendable { var words: [String] = [] }

    /// What the field says with a key for a field of `app` the session wasn't told took the focus: everything
    /// (`FakeHost.context`), and whose field it is (`FieldContext.field`), as the Mac says with every key.
    private func context(_ host: FakeHost, app: String) -> FieldContext {
        var context = host.context
        context.field = FieldInfo(app: app)
        return context
    }

    /// `text` typed, each key for a field of `app` (Space, and "\r" Return).
    private func type(_ text: String, _ host: FakeHost, app: String) {
        for character in text {
            let key = character == "\r" ? FakeHost.enter : Review076Field.key(character)
            let handled = host.press(key, with: context(host, app: app))
            if !handled, character != "\r" { host.document += String(character) }
        }
    }

    /// A session whose field is an editor's (the focus it was last told), in English mode, words learned into `learned`.
    private func learningHost(_ learned: Learned) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.englishDictionary = { EnglishDictionary(["hello", "world", "it", "we"]) }
        services.learnEnglishWord = { learned.words.append($0) }
        let host = FakeHost(services: services)
        host.app = Review076Field.editor
        host.focus()
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: 100))
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: 100.1))
        return host
    }

    /// Item 2, the English words learned. Keys typed in English mode for a password manager's field, the session's own
    /// field still the editor it was last told: nothing typed there is learned, as when the password manager was
    /// activated. (Fails today: the word is learned once the key is handled, by the stale field.)
    @Test(arguments: Review076Field.passwordManagers)
    func nothingIsLearnedInAPasswordManagerTheSessionWasNotToldOf(_ app: String) async throws {
        try await withInterfaceLanguage("en") {
            // The premise: the same keys for the editor's field learn the word the second time.
            let premise = Learned()
            let editor = learningHost(premise)
            try #require(editor.composer.inputLanguage == .english)
            type("we zorblax it. we zorblax it. ", editor, app: Review076Field.editor)
            try #require(premise.words == ["zorblax"], "the editor learns the word the second time: \(premise.words)")

            let learned = Learned()
            let host = learningHost(learned)
            type("we zorblax it. we zorblax it. ", host, app: app)
            #expect(learned.words.isEmpty, "\(app): learned from a password manager's field: \(learned.words)")
        }
    }

    /// The field loses the focus, and a field of the host's own app takes it.
    private func leaveAndComeBack(_ host: FakeHost) {
        host.send(.blur)
        host.focus()
    }

    /// The words the session would learn if the field were left now (`EnglishModeWords.leftField`, on a copy: the
    /// session's own isn't touched).
    private func wordsHeld(_ host: FakeHost) -> [String] {
        var words = host.session.englishModeWords
        return words.leftField()
    }

    /// Item 2, the word that Return ends. A word typed for a password manager's field and ended by Return stands only
    /// once the field is left (the blur learns it, by the field the session was last told: the editor's): nothing is
    /// held for it after Return, and nothing is learned when the field loses the focus and another takes it.
    @Test(arguments: Review076Field.passwordManagers)
    func nothingIsLearnedOnLeavingAPasswordManagerTheSessionWasNotToldOf(_ app: String) async throws {
        try await withInterfaceLanguage("en") {
            // The premise: the same keys for the editor's field hold the word after Return, and leaving learns it.
            let premise = Learned()
            let editor = learningHost(premise)
            try #require(editor.composer.inputLanguage == .english)
            type("we zorblax it. we zorblax\r", editor, app: Review076Field.editor)
            try #require(premise.words.isEmpty && wordsHeld(editor) == ["zorblax"],
                         "the editor holds the word Return ended: \(premise.words) \(wordsHeld(editor))")
            leaveAndComeBack(editor)
            try #require(premise.words == ["zorblax"], "the editor learns the word once the field is left: \(premise.words)")

            let learned = Learned()
            let host = learningHost(learned)
            type("we zorblax it. we zorblax\r", host, app: app)
            #expect(wordsHeld(host).isEmpty, "\(app): a word typed in a password manager's field is held: \(wordsHeld(host))")
            leaveAndComeBack(host)
            #expect(learned.words.isEmpty, "\(app): learned from a password manager's field on leaving it: \(learned.words)")

            // A word typed once in the editor, then again for the password manager's field: the second isn't counted.
            let mixedWords = Learned()
            let mixed = learningHost(mixedWords)
            type("we zorblax it. ", mixed, app: Review076Field.editor)
            type("we zorblax\r", mixed, app: app)
            #expect(wordsHeld(mixed).isEmpty, "\(app): a word is held across fields: \(wordsHeld(mixed))")
            leaveAndComeBack(mixed)
            #expect(mixedWords.words.isEmpty, "\(app): learned from a password manager's field: \(mixedWords.words)")
        }
    }

    /// Item 2, autocomplete. Keys for a password manager's field, the session's own field still the editor (autocomplete
    /// on there): no pause starts, the field isn't read and nothing is asked of the AI. (Fails today: what is done after
    /// the key goes by the stale field, so the pause starts and the password manager's field is read and sent.)
    @Test(arguments: Review076Field.passwordManagers)
    func autocompleteStaysOffInAPasswordManagerTheSessionWasNotToldOf(_ app: String) async throws {
        try await withInterfaceLanguage("en") {
            func rig() -> (FakeHost, Review076Model) {
                var config = Config.default
                config.provider = .apple
                config.uiLanguage = "en"
                config.setOrder([Language.english])
                config.setOrder([OutputLanguage.english, .chinese])
                config.autocomplete = true
                let fixed = config
                let model = Review076Model()
                var services = SessionServices(converter: Converter(loadConfig: { fixed }, appleModel: model), loadSettings: { fixed })
                services.levelOne = { .engine(FakeEngine()) }
                let host = FakeHost(services: services)
                host.app = Review076Field.editor
                host.focus()
                return (host, model)
            }
            func pauses(_ host: FakeHost) -> [TimerID] { host.timers.filter { if case .autocomplete = $0 { true } else { false } } }
            func pauseEnds(_ host: FakeHost, _ model: Review076Model, expected: Bool) {
                host.fireTimers { if case .autocomplete = $0 { true } else { false } }
                host.settle(timeout: expected ? 5 : 0.5) { expected && !model.requests.isEmpty }
            }

            // The premise: the same keys for the editor's field start a pause, which reads the field and asks the AI.
            let (editor, editorModel) = rig()
            type("Hello wor", editor, app: Review076Field.editor)
            try #require(!pauses(editor).isEmpty, "autocomplete runs in the editor")
            pauseEnds(editor, editorModel, expected: true)
            try #require(editor.fieldReads > 0 && !editorModel.requests.isEmpty, "the editor's pause reads the field and asks")

            let (host, model) = rig()
            type("Hello wor", host, app: app)
            #expect(pauses(host).isEmpty, "\(app): a pause started for a password manager's field")
            #expect(host.session.autocomplete.typed.text.isEmpty, "\(app): what was typed there is kept for autocomplete")
            pauseEnds(host, model, expected: false)
            #expect(host.fieldReads == 0, "\(app): the field was read \(host.fieldReads) times")
            #expect(model.requests.isEmpty, "\(app): the AI was asked: \(model.texts)")
        }
    }

    /// Item 2, suggestions. A source's prefix typed for a password manager's field, the session's own field still the
    /// editor: no rows, no lookup, as when the password manager was activated
    /// (`Issue74SuggestionsPasswordManagerTests`). (Fails today: the rows show, the typed text reaches the source.)
    @Test(arguments: Review076Field.passwordManagers)
    func noSuggestionRowsInAPasswordManagerTheSessionWasNotToldOf(_ app: String) async throws {
        try await withInterfaceLanguage("en") {
            // The premise: the same keys for the editor's field show the issues.
            let editorWorld = SuggestionsWorld()
            try editorWorld.github()
            let editor = editorWorld.field()
            for character in "#70" { editor.host.press(SuggestionKeys.key(character), with: context(editor.host, app: Review076Field.editor)) }
            try #require(editor.settle { !editor.issuesShown.isEmpty }, "the editor shows the issues")

            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            // The editor's own focus loads the source once, on its own time: counted from after that load.
            try #require(field.settle { world.runtime.loads.count == 1 }, "the focus's own load")
            let loadsBefore = world.runtime.loads.count
            for character in "#70" { field.host.press(SuggestionKeys.key(character), with: context(field.host, app: app)) }
            field.idle()
            #expect(field.rows.isEmpty, "\(app): rows show in a password manager's field: \(field.rows.map(\.text))")
            #expect(world.runtime.loads.count == loadsBefore, "\(app): the source list was loaded for it")
            #expect(world.runtime.queries.isEmpty, "\(app): typed text reached the source: \(world.runtime.queries)")
            #expect(field.host.session.suggesting.token.isEmpty,
                    "\(app): what was typed there is followed: \(field.host.session.suggesting.token)")

            // Return for the same field, then the field is left and the editor's takes the focus: what was typed in the
            // password manager is followed nowhere on the way (no token, no rows, no lookup).
            field.host.press(SuggestionKeys.enter, with: context(field.host, app: app))
            #expect(field.host.session.suggesting.token.isEmpty,
                    "\(app): what was typed there is followed after Return: \(field.host.session.suggesting.token)")
            #expect(world.runtime.loads.count == loadsBefore, "\(app): the source list was loaded for it after Return")
            field.host.send(.blur)
            #expect(field.host.session.suggesting.token.isEmpty,
                    "\(app): what was typed there is kept once the field is left: \(field.host.session.suggesting.token)")
            field.host.focus()
            field.idle()
            #expect(field.host.session.suggesting.token.isEmpty,
                    "\(app): what was typed there is carried into the next field: \(field.host.session.suggesting.token)")
            #expect(field.rows.isEmpty, "\(app): rows show after the password manager's field: \(field.rows.map(\.text))")
            #expect(world.runtime.queries.isEmpty, "\(app): typed text reached the source: \(world.runtime.queries)")
        }
    }

    /// Item 2, suggestions, a word then Return. A word typed for a password manager's field, then a source's prefix,
    /// Return, and the field left for the editor's: the same keys in the editor are followed (the premise), there
    /// nothing is.
    @Test(arguments: Review076Field.passwordManagers)
    func nothingTypedInAPasswordManagerIsFollowedPastReturnAndTheFieldLeft(_ app: String) async throws {
        try await withInterfaceLanguage("en") {
            func typed(_ text: String, in field: SuggestionsField, app: String) {
                for character in text { field.host.press(SuggestionKeys.key(character), with: context(field.host, app: app)) }
            }
            // The premise: in the editor's field the prefix after a word is followed.
            let editorWorld = SuggestionsWorld()
            try editorWorld.github()
            let editor = editorWorld.field()
            typed("hello #70", in: editor, app: Review076Field.editor)
            try #require(editor.settle { !editor.issuesShown.isEmpty }, "the editor shows the issues after a word")
            try #require(!editor.host.session.suggesting.token.isEmpty, "the editor follows what is typed")

            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            typed("hello #70", in: field, app: app)
            field.host.press(SuggestionKeys.enter, with: context(field.host, app: app))
            field.idle()
            #expect(field.host.session.suggesting.token.isEmpty,
                    "\(app): what was typed there is followed: \(field.host.session.suggesting.token)")
            field.host.send(.blur)
            field.host.focus()
            field.idle()
            #expect(field.host.session.suggesting.token.isEmpty,
                    "\(app): what was typed there is carried into the next field: \(field.host.session.suggesting.token)")
            #expect(field.rows.isEmpty, "\(app): rows show: \(field.rows.map(\.text))")
            #expect(world.runtime.queries.isEmpty, "\(app): typed text reached the source: \(world.runtime.queries)")
        }
    }
}

// MARK: - 3. Told a password field after being told none

@Suite(.serialized, SuggestionsOneAtATime())
struct Review076PasswordFieldToldLaterTests {
    /// An editor's field told to be no password field with its first key, a source's rows showing for "#70".
    private func fieldShowingRows() throws -> (SuggestionsWorld, SuggestionsField) {
        let world = SuggestionsWorld()
        try world.github()
        let field = world.field()
        field.type("#70")
        try #require(field.settle { !field.issuesShown.isEmpty }, "the issues show for #70")
        try #require(field.host.session.passwordField == .no, "told none with the key: \(String(describing: field.host.session.passwordField))")
        return (world, field)
    }

    /// Item 3. The shell's own answer comes later and says it is one (`SessionEvent.passwordField`): the rows go and
    /// what was typed for them is forgotten, as on the first telling. (Fails today: only a field not told before has its
    /// suggestions cleared, `passwordFieldTold`.)
    @Test func rowsGoWhenTheShellLaterSaysItIsAPasswordField() async throws {
        try await withInterfaceLanguage("en") {
            let (world, field) = try fieldShowingRows()
            // The lookup the key started while the field was told none has gone out: only what comes after counts.
            try #require(field.settle {
                world.store.queryInFlight(CompletionSourceKey(plugin: "github", source: "issues"), timeout: 60, now: world.clock.now) == nil
            }, "the key's own lookup")
            field.host.send(.passwordField(true, focus: field.host.session.fieldSession))
            try #require(field.host.session.passwordField == .yes)
            #expect(field.rows.isEmpty, "the rows stay up in a password field: \(field.rows.map(\.text))")
            #expect(field.host.session.suggesting.token.isEmpty, "what was typed is still followed: \(field.host.session.suggesting.token)")
            let queries = world.runtime.queries.count
            field.idle()
            #expect(field.rows.isEmpty && world.runtime.queries.count == queries, "rows or lookups after it was told")
        }
    }

    /// Item 3, the other way it is told later: a read of the field once typing pauses (autocomplete's,
    /// `SessionEvent.field`) says it is a password field (`FieldInfo.secure`). The rows go then too. (Fails today.)
    @Test func rowsGoWhenAReadOfTheFieldLaterSaysItIsAPasswordField() async throws {
        try await withInterfaceLanguage("en") {
            let (_, field) = try fieldShowingRows()
            var read = field.host.context
            read.field = FieldInfo(app: field.host.app, secure: true)
            field.host.send(.field(read, id: 1))
            try #require(field.host.session.passwordField == .yes)
            #expect(field.rows.isEmpty, "the rows stay up in a password field: \(field.rows.map(\.text))")
            #expect(field.host.session.suggesting.token.isEmpty, "what was typed is still followed: \(field.host.session.suggesting.token)")
        }
    }
}
