import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Regression tests for what the second review of the 0.7.6 privacy fixes found (AGENTS.md rule 20: each failed on the
// code as reviewed, for the reason its comment gives):
//  1. A field never asked whether it is a password field was read as if told none: the first "@" read its selection,
//     `@reply` its text. A read waits for "none"; a field not asked yet is asked first.
//  2. Keys for a password manager's field the session wasn't told took the focus still fed the English words followed
//     (learned once the field was left, by the stale field) and suggestions' token.
//  4. A field told to be a password field while autocomplete's request was on its way kept the answer.
//  5. `Example.APP` wasn't an app to `@open`'s ranking.
//  6. A dead key that tells no characters at all had its key code recorded.

/// Apple's on-device model, standing in for any provider: records every request, answers "OK".
private final class SecondPassModel: AppleModelBackend, @unchecked Sendable {
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

    var texts: [String] {
        requests.map { ([$0.instructions, $0.prompt] + $0.examples.flatMap { [$0.prompt, $0.response] }).joined(separator: "\n") }
    }
}

private enum SecondPass {
    static let editor = "com.example.editor"
    static let passwordManager = "com.1password.1password"

    /// What the field says for `key` as the Mac reads it: only what the session asks for, and whether it is a password
    /// field never with the key (told after it: `FieldContext.passwordFieldFollows`).
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

    static func key(_ character: Character) -> KeyEvent {
        character == "@" ? FakeHost.at : character == " " ? FakeHost.space
            : character == "\r" ? FakeHost.enter : KeyEvent(keyCode: 0, characters: String(character))
    }
}

// MARK: - 1. A field never asked

@Suite(.serialized)
struct Review076NeverAskedFieldTests {
    /// A field of an ordinary app, "hunter2 secret" in it, all selected; nothing has the shell asked whether it is a
    /// password field (no suggestion source, no English words learned), and its answers wait (`answerFieldReads`).
    private func host(model: SecondPassModel = SecondPassModel(), passwordField: Bool, useSelection: Bool = true) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .apple
        config.useSelection = useSelection
        config.setOrder([Language.english, .chinese])
        let fixed = config
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
                                       loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        let host = FakeHost(services: services)
        host.app = SecondPass.editor
        host.passwordField = passwordField
        host.fieldReadsWait = true
        host.selectionReadsWait = true
        host.document = "hunter2 secret"
        host.selection = 0..<14
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    private func press(_ host: FakeHost, _ key: KeyEvent) {
        host.press(key, with: SecondPass.macContext(host, for: key))
    }

    /// The first "@" of a field nothing asked about yet: the shell is asked whether it is a password field, and the
    /// selection isn't read with the key nor after it; told a password field, it never is. (Failed: never asked counted
    /// as none, so the selection was asked for with the same key.)
    @Test func theFirstAtAsksBeforeItReadsTheSelection() throws {
        let host = host(passwordField: true)
        try #require(host.session.passwordField == nil && host.passwordFieldReads == 1, "the premise: asked with the focus, not answered")
        let wanted = SecondPass.macContext(host, for: FakeHost.at).read
        #expect(wanted.contains(.passwordField), "\"@\" doesn't ask whether it's a password field: \(wanted)")
        #expect(!wanted.contains(.selection), "\"@\" reads the selection of a field not known to be none: \(wanted)")
        press(host, FakeHost.at)
        #expect(host.passwordFieldReads == 1, "asked \(host.passwordFieldReads) times")
        #expect(host.composer.isComposing && host.composer.selection == nil, "the list shows, on nothing")
        #expect(host.selectionReads.isEmpty, "the selection is read before the answer: \(host.selectionReads)")
        host.answerFieldReads()
        #expect(host.session.passwordField == .yes)
        #expect(host.selectionReads.isEmpty && !host.composer.selectionPending && host.composer.selection == nil)
        #expect(!String(describing: host.panel).contains("hunter2"))
    }

    /// The same key where the answer is "none": that "@" starts on nothing and no read is asked for after it (as while
    /// the answer is awaited: `PasswordFieldUnknownTests`); the next "@" reads the selection with the key.
    @Test func theSelectionIsReadOnceToldItIsNoPasswordField() throws {
        let host = host(passwordField: false)
        press(host, FakeHost.at)
        #expect(host.passwordFieldReads == 1 && host.selectionReads.isEmpty, "\(host.passwordFieldReads), \(host.selectionReads)")
        #expect(!host.composer.selectionPending && host.composer.selection == nil)
        host.answerFieldReads()
        #expect(host.session.passwordField == .no && host.selectionReads.isEmpty)
        press(host, FakeHost.escape)
        try #require(!host.composer.isComposing)
        #expect(SecondPass.macContext(host, for: FakeHost.at).read.contains(.selection))
        press(host, FakeHost.at)
        #expect(host.composer.selection?.text == "hunter2 secret" && host.passwordFieldReads == 1)
    }

    /// The shell couldn't tell: not read then either (the owner's decision, 2026-11-26), and not asked again.
    @Test func theSelectionIsNotReadWhereTheShellCouldNotTell() throws {
        let host = host(passwordField: false)
        host.cannotTellPasswordField = true
        press(host, FakeHost.at)
        host.answerFieldReads()
        #expect(host.session.passwordField == .unknown)
        press(host, FakeHost.escape)
        try #require(!host.composer.isComposing)
        #expect(!SecondPass.macContext(host, for: FakeHost.at).read.contains(.selection))
        press(host, FakeHost.at)
        #expect(host.composer.selection == nil && host.selectionReads.isEmpty && host.passwordFieldReads == 1)
    }

    /// "@" asks where no selection would be read either ("Use the selected text" off), so that a password field is
    /// known as one by the time a command is run in it. (Failed: nothing asked, `nothingLeavesDevice` stayed false.)
    @Test func atAsksWhereTheSelectionIsNotUsed() {
        let host = host(passwordField: true, useSelection: false)
        press(host, FakeHost.at)
        #expect(host.passwordFieldReads == 1, "asked \(host.passwordFieldReads) times")
        host.answerFieldReads()
        #expect(host.session.nothingLeavesDevice())
        #expect(!host.composer.oneAtRows.contains { $0.command?.usesAI == true }, "\(host.composer.oneAtRows)")
    }

    /// `@reply`'s ⏎ in a field never asked about (the draft was there before the field was known): asked first, no text
    /// read with the key nor sent. (Failed: the text was asked for and sent.)
    @Test func replyAsksBeforeItReadsTheText() async throws {
        try await withInterfaceLanguage("en") {
            let model = SecondPassModel()
            let host = host(model: model, passwordField: true)
            host.selection = nil
            host.type("@reply")
            host.press(FakeHost.tab)
            host.type("ok")
            try #require(host.composer.draftCommand == .reply)
            // Not asked in this field, as after a focus nothing told the session of.
            host.session.passwordField = nil
            host.session.passwordFieldAsked = -1
            let reads = host.passwordFieldReads
            let wanted = host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure, field: FieldInfo(app: host.app)))
            #expect(wanted.contains(.passwordField) && !wanted.contains(.text), "\(wanted)")
            let option = ModifierChange(key: .modifier(.option, .left), modifiers: [.option, .leftOption], timestamp: 1)
            #expect(!host.session.fieldWants(forModifiers: option, given: FieldContext(read: .secure)).contains(.text))
            // A shell that told the text all the same, and nothing of a password field.
            var told = FieldContext(read: [.secure, .text], field: FieldInfo(app: host.app))
            told.text = host.context.text
            host.press(FakeHost.enter, with: told)
            #expect(host.passwordFieldReads == reads + 1, "the shell wasn't asked")
            host.settle(timeout: 1.5) { !model.requests.isEmpty }
            #expect(!model.texts.contains { $0.contains("hunter2") }, "the field's text was sent: \(model.texts)")
        }
    }
}

// MARK: - 2. A key with no activate before it

@Suite(.serialized, SuggestionsOneAtATime())
struct Review076PasswordManagerKeysTests {
    final class Learned: @unchecked Sendable { var words: [String] = [] }

    private func context(_ host: FakeHost, app: String) -> FieldContext {
        var context = host.context
        context.field = FieldInfo(app: app)
        return context
    }

    private func english(_ host: FakeHost) {
        guard host.composer.inputLanguage != .english else { return }
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: 100))
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: 100.1))
    }

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
        host.app = SecondPass.editor
        host.focus()
        english(host)
        return host
    }

    /// A password and ⏎, twice (the password, then its confirmation), each key for a field of `app`, the session's own
    /// field the editor it was last told; the field is left after each (`leave`: the focus lost, or the editor's taken
    /// again).
    private func typePasswordTwice(_ host: FakeHost, app: String, leave: (FakeHost) -> Void) {
        for _ in 0..<2 {
            for character in "zorblax\r" { host.press(SecondPass.key(character), with: context(host, app: app)) }
            leave(host)
            english(host)
        }
    }

    /// Item 2, scenario A. The word ended by ⏎ in a password manager's field is learned when the field is left, by the
    /// field the session was last told (the editor). (Failed: learned the second time, as in the editor.)
    @Test(arguments: [true, false])
    func aPasswordManagersWordIsNotLearnedWhenTheFieldIsLeft(_ blur: Bool) async throws {
        try await withInterfaceLanguage("en") {
            let leave: (FakeHost) -> Void = { host in
                if blur { host.send(.blur) }
                host.focus()
            }
            let premise = Learned()
            let editor = learningHost(premise)
            try #require(editor.composer.inputLanguage == .english)
            typePasswordTwice(editor, app: SecondPass.editor, leave: leave)
            try #require(premise.words == ["zorblax"], "the editor learns the word the second time: \(premise.words)")

            let learned = Learned()
            let host = learningHost(learned)
            typePasswordTwice(host, app: SecondPass.passwordManager, leave: leave)
            #expect(learned.words.isEmpty, "learned from a password manager's field: \(learned.words)")
        }
    }

    /// Item 2, scenario B. What is typed for a password manager's field isn't followed for suggestions either: nothing
    /// of it is left in the token once the key is handled. (Failed: every key put its character back.)
    @Test func nothingTypedInAPasswordManagerIsKeptForSuggestions() async throws {
        try await withInterfaceLanguage("en") {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            for character in "#70" { field.host.press(SuggestionKeys.key(character), with: context(field.host, app: SecondPass.editor)) }
            try #require(field.host.session.suggesting.token == "#70", "the premise: \(field.host.session.suggesting.token)")

            let other = world.field()
            for character in "#70" {
                other.host.press(SuggestionKeys.key(character), with: context(other.host, app: SecondPass.passwordManager))
                #expect(other.host.session.suggesting.token.isEmpty, "kept: \(other.host.session.suggesting.token)")
            }
        }
    }
}

// MARK: - 4. Told a password field while autocomplete asks

@Suite(.serialized)
struct Review076AutocompleteToldLaterTests {
    private func rig() -> (FakeHost, ContinuingModel, Uptime) {
        var config = Config.default
        config.provider = .apple
        config.uiLanguage = "en"
        config.setOrder([Language.english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.autocomplete = true
        let fixed = config
        let model = ContinuingModel(answer: { _ in "ld of wonders." })
        let clock = Uptime()
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, appleModel: model), loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.uptime = { clock.now }
        services.autocomplete = AutocompleteStore()
        let host = FakeHost(services: services)
        host.app = SecondPass.editor
        host.appTypesKeys = true
        host.focus()
        return (host, model, clock)
    }

    /// "Hello wor" typed, the pause over and the request on its way; `told` happens before its answer is heard.
    private func askThen(_ host: FakeHost, _ model: ContinuingModel, _ clock: Uptime, _ told: () -> Void) throws -> Autocomplete.Context {
        host.type("Hello wor")
        clock.advance(1)
        host.fireTimers { if case .autocomplete = $0 { true } else { false } }
        try #require(host.session.autocomplete.asked != nil, "the premise: a request is on its way")
        let asked = try #require(host.session.autocomplete.request)
        told()
        host.settle(timeout: 2) { !model.requests.isEmpty && host.session.autocomplete.asked == nil }
        host.settle(timeout: 0.3) { false }
        return asked
    }

    /// Item 4. The shell says the field is a password field while autocomplete's request is on its way: the request is
    /// given up, its answer isn't kept, nor what was typed. (Failed: the answer was kept for the field's text.)
    @Test func anAnswerOnItsWayIsNotKeptOnceTheFieldIsAPasswordField() async throws {
        try await withInterfaceLanguage("en") {
            let (editor, editorModel, editorClock) = rig()
            let plain = try askThen(editor, editorModel, editorClock) {}
            try #require(editor.session.services.autocomplete.kept(for: plain, in: SecondPass.editor) != nil,
                         "the premise: the answer is kept in an ordinary field")

            let (host, model, clock) = rig()
            let asked = try askThen(host, model, clock) { host.send(.passwordField(true, focus: host.session.fieldSession)) }
            #expect(host.session.passwordField == .yes)
            #expect(host.session.services.autocomplete.kept(for: asked, in: SecondPass.editor) == nil, "the answer is kept")
            #expect(host.session.autocomplete.typed.text.isEmpty, "what was typed is kept: \(host.session.autocomplete.typed.text)")
            #expect(host.session.autocomplete.known == nil && host.ghost == nil)
        }
    }
}

// MARK: - 5, 6

struct Review076SecondPassPureTests {
    /// Item 5. An app whose bundle is named in capitals is an app to the ranking: listed as one, its name without the
    /// extension, not found by "app" alone. (Failed: only ".app" in small letters.)
    @Test(arguments: ["/Applications/Example.APP", "/Applications/Example.App"])
    func anAppNamedInCapitalsRanksAsAnApp(_ path: String) {
        #expect(FileSearchRanking.isApp(path))
        #expect(FileSearchRanking.Found(path: path).ranksAsApp)
        #expect(FileSearchRanking.name(of: path) == "Example")
        #expect(FileSearchRanking.onlyByExtension(path, "app"))
        #expect(!FileSearchRanking.isApp("/Users/me/notes.app.txt") && !FileSearchRanking.isApp("/Users/me/snapp"))
    }

    /// Item 6. A dead key as AppKit tells it on a layout where it needs no modifier (the French ^, the German ´): no
    /// characters, with or without modifiers. No key code in a recording that keeps no text. (Failed: taken for a key
    /// that types nothing, its code recorded.)
    @Test(arguments: [
        KeyEvent(keyCode: 0x21, characters: "", charactersIgnoringModifiers: ""),
        KeyEvent(keyCode: 0x21, characters: "", charactersIgnoringModifiers: "", modifiers: [.shift, .leftShift]),
        KeyEvent(keyCode: 0x18, characters: "", charactersIgnoringModifiers: "", modifiers: [.option, .leftOption]),
    ])
    func aDeadKeyThatTellsNoCharactersIsRecordedWithoutItsKeyCode(_ deadKey: KeyEvent) throws {
        let redacted = HostCallRecording(keepsText: false)
        let line = redacted.event("keyDown", at: 0, redacted.key(deadKey))
        let read = try #require(HostCallRecording.parse(line))
        #expect(read.string("key") == "text" && read.fields["code"] == nil, "\(line)")
        let kept = HostCallRecording(keepsText: true)
        let keptRead = try #require(HostCallRecording.parse(kept.event("keyDown", at: 0, kept.key(deadKey))))
        #expect(keptRead.number("code") == Double(deadKey.keyCode))
        // A shortcut and a named key keep their code, as before.
        let shortcut = KeyEvent(keyCode: 0x09, characters: "", charactersIgnoringModifiers: "", modifiers: [.command, .leftCommand])
        #expect(HostCallRecording.parse(redacted.event("keyDown", at: 0, redacted.key(shortcut)))?.fields["code"] != nil)
        #expect(HostCallRecording.parse(redacted.event("keyDown", at: 0, redacted.key(FakeHost.enter)))?.fields["code"] != nil)
    }
}
