import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Regression tests for what the third review of the 0.7.6 privacy fixes found (AGENTS.md rule 20: each failed on the
// code as reviewed, for the reason its comment gives). A command reads the field (its selection, the text around the
// caret) only once the shell said this very field is no password field (the owner's decision, 2026-11-26):
//  1. A read of the field asked for in one field (`SessionOutput.readField`) and answered in the next told the next
//     one to be none, or to be a password field.
//  2. A field left (`.blur`), or keys for another app's field with no focus told before them, kept the "none" of the
//     field before.
//  3. A tap of Option that runs `@reply` didn't go by what its own read of the field said (a password field), and
//     kept the text read with a modifier change whatever the field was.
//  4. The shell was asked whether the field is a password field while secure input was on.

/// Apple's on-device model, standing in for any provider: records every request, answers "OK".
private final class ThirdPassModel: AppleModelBackend, @unchecked Sendable {
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

private final class SecureInputSwitch: @unchecked Sendable {
    private let on = Locked(initialState: false)
    var isOn: Bool {
        get { on.withLock { $0 } }
        set { on.withLock { $0 = newValue } }
    }
}

private enum ThirdPass {
    static let editor = "com.example.editor"
    static let browser = "com.example.browser"
    static let passwordManager = "com.1password.1password"
    static let optionDown = ModifierChange(key: .modifier(.option, .left), modifiers: [.option, .leftOption], timestamp: 1)
    static let optionUp = ModifierChange(key: .modifier(.option, .left), modifiers: [], timestamp: 1.1)

    /// What the field of `app` says for `key` as the Mac reads it: only what the session asks for, and whether it is a
    /// password field never with the key (told after it: `FieldContext.passwordFieldFollows`).
    static func macContext(_ host: FakeHost, for key: KeyEvent, app: String? = nil) -> FieldContext {
        let full = host.context
        var told = FieldContext(field: FieldInfo(app: app ?? host.app, terminal: host.terminal))
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

    /// A field of an ordinary app, "hunter2 secret" in it, all selected, focused; the shell's answers wait
    /// (`answerFieldReads`).
    static func host(model: ThirdPassModel = ThirdPassModel(), actionKey: ActionKey = .enter,
                     secureInput: SecureInputSwitch = SecureInputSwitch()) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .apple
        config.useSelection = true
        config.actionKey = actionKey
        config.setOrder([Language.english, .chinese])
        let fixed = config
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
                                       loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.secureInputActive = { secureInput.isOn }
        let host = FakeHost(services: services)
        host.app = editor
        host.fieldReadsWait = true
        host.selectionReadsWait = true
        host.document = "hunter2 secret"
        host.selection = 0..<14
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    /// `host`'s field told to be no password field, as its shell answers the focus's question.
    static func toldNone(_ host: FakeHost) throws {
        host.send(.passwordField(false, focus: host.session.fieldSession))
        try #require(host.session.passwordField == .no, "the premise: told none")
    }
}

// MARK: - 1. An answer for the field before

@Suite(.serialized)
struct Review076StaleFieldReadTests {
    private func rig() -> (FakeHost, Uptime) {
        var config = Config.default
        config.provider = .apple
        config.uiLanguage = "en"
        config.useSelection = true
        config.setOrder([Language.english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.autocomplete = true
        let fixed = config
        let clock = Uptime()
        var services = SessionServices(converter: Converter(loadConfig: { fixed }, appleModel: ContinuingModel(answer: { _ in "ld." })),
                                       loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.uptime = { clock.now }
        services.autocomplete = AutocompleteStore()
        let host = FakeHost(services: services)
        host.app = ThirdPass.editor
        host.appTypesKeys = true
        host.fieldReadsWait = true
        host.focus()
        return (host, clock)
    }

    /// Autocomplete's pause is over in the editor and its read of the field is on its way (the shell asked
    /// Accessibility, which said `passwordField`); the browser's field takes the focus before the read is handed back.
    private func readOnItsWayThenAnotherField(_ host: FakeHost, _ clock: Uptime, passwordField: Bool) throws {
        host.passwordField = passwordField
        host.type("Hello wor")
        clock.advance(1)
        host.fireTimers { if case .autocomplete = $0 { true } else { false } }
        try #require(host.fieldReads == 1, "the premise: the pause's read was asked for (\(host.fieldReads))")
        host.send(.blur)
        host.app = ThirdPass.browser
        host.passwordField = !passwordField
        host.document = "hunter2 secret"
        host.selection = 0..<14
        host.focus()
        try #require(host.session.passwordField == nil, "the premise: the browser's field isn't told yet")
    }

    /// The editor's read says "no password field" and comes back in the browser's field, which isn't told yet (it is
    /// one): not taken for it, and "@" there reads no selection. (Failed: `SessionEvent.field` told it none, whatever
    /// field it was asked in, and nothing the browser's own answer said could take that back but "it is one".)
    @Test func aNoneForTheFieldBeforeIsNotTakenForTheNextOne() async throws {
        try await withInterfaceLanguage("en") {
            let (host, clock) = rig()
            let editor = host.session.fieldSession
            try readOnItsWayThenAnotherField(host, clock, passwordField: false)
            // The editor's read as the Mac hands it back (`FieldReading.contextAfterPause`: it names its field, and says
            // none), for the focus it was asked in; then what else waited (the editor's focus's answer among it).
            var read = FieldContext(read: [.secure, .passwordField, .selectedRange, .text], field: FieldInfo(app: ThirdPass.editor))
            read.text = FieldText(before: "Hello wor", after: "")
            host.send(.field(read, id: 1, focus: editor))
            host.answerFieldReads()
            #expect(host.session.passwordField == nil, "told \(String(describing: host.session.passwordField)) by the field before")
            let wanted = ThirdPass.macContext(host, for: FakeHost.at).read
            #expect(!wanted.contains(.selection), "\"@\" reads the selection of a field not told to be none: \(wanted)")
        }
    }

    /// The other way round: the editor's read said "a password field" (its field was one) and comes back in an
    /// ordinary field: that one isn't a password field for it. (Failed: it stayed one until the focus moved again.)
    @Test func aPasswordFieldBeforeDoesNotMakeTheNextOneOne() async throws {
        try await withInterfaceLanguage("en") {
            let (host, clock) = rig()
            try readOnItsWayThenAnotherField(host, clock, passwordField: true)
            host.answerFieldReads()
            #expect(host.session.passwordField != .yes, "the field before makes this one a password field")
            #expect(!host.session.nothingLeavesDevice())
        }
    }

    /// A read asked for and answered in the same field still tells it (what autocomplete's pause has always done).
    @Test func aReadAnsweredInItsOwnFieldStillTellsIt() async throws {
        try await withInterfaceLanguage("en") {
            let (host, clock) = rig()
            host.type("Hello wor")
            clock.advance(1)
            host.fireTimers { if case .autocomplete = $0 { true } else { false } }
            try #require(host.fieldReads == 1 && host.session.passwordField == nil)
            host.answerFieldReads()
            #expect(host.session.passwordField == .no)
        }
    }
}

// MARK: - 2. A field left, and keys for another one

@Suite(.serialized)
struct Review076FieldLeftTests {
    /// The field is left: what was told of it is told of no other. A key that comes with no focus told before it is in
    /// a field not told yet: asked, its selection not read. (Failed: `.blur` kept the "none", so nothing was asked and
    /// "@" read the selection.)
    @Test func aFieldLeftIsToldNoLonger() throws {
        let host = ThirdPass.host()
        try ThirdPass.toldNone(host)
        try #require(ThirdPass.macContext(host, for: FakeHost.at).read.contains(.selection), "the premise: read once told none")
        host.send(.blur)
        #expect(host.session.passwordField == nil, "still \(String(describing: host.session.passwordField)) after the field was left")
        let wanted = ThirdPass.macContext(host, for: FakeHost.at, app: ThirdPass.browser).read
        #expect(wanted.contains(.passwordField) && !wanted.contains(.selection), "\(wanted)")
        let reads = host.passwordFieldReads
        host.press(FakeHost.at, with: ThirdPass.macContext(host, for: FakeHost.at, app: ThirdPass.browser))
        #expect(host.passwordFieldReads == reads + 1, "the shell wasn't asked about the field the key came for")
        #expect(host.composer.selection == nil && host.selectionReads.isEmpty)
    }

    /// Keys for another app's field with neither `.blur` nor `.focus` before them (the Mac: a key before
    /// `activateServer`): the editor's "none" isn't the browser's. Asked for itself, nothing read meanwhile, and the
    /// editor's late answer isn't taken for it. (Failed: `fieldWants` asked for the selection at once.)
    @Test func keysForAnotherFieldAreNotInTheFieldToldNone() throws {
        let host = ThirdPass.host()
        try ThirdPass.toldNone(host)
        let editor = host.session.fieldSession
        let wanted = ThirdPass.macContext(host, for: FakeHost.at, app: ThirdPass.browser).read
        #expect(wanted.contains(.passwordField) && !wanted.contains(.selection), "\(wanted)")
        let reads = host.passwordFieldReads
        host.press(FakeHost.at, with: ThirdPass.macContext(host, for: FakeHost.at, app: ThirdPass.browser))
        #expect(host.session.passwordField == nil, "\(String(describing: host.session.passwordField))")
        #expect(host.passwordFieldReads == reads + 1, "the shell wasn't asked about the browser's field")
        #expect(host.composer.selection == nil && host.selectionReads.isEmpty, "the browser's selection was read")
        host.send(.passwordField(false, focus: editor))
        #expect(host.session.passwordField == nil, "the editor's answer was taken for the browser's field")
        // The browser's own answer tells it; then keys for the editor again are in a field not told.
        host.answerFieldReads()
        #expect(host.session.passwordField == .no)
        host.press(FakeHost.escape, with: ThirdPass.macContext(host, for: FakeHost.escape, app: ThirdPass.browser))
        #expect(host.session.passwordField == .no, "asked again in the same field")
        #expect(!ThirdPass.macContext(host, for: FakeHost.at, app: ThirdPass.editor).read.contains(.selection))
    }

    /// `@reply` run by ⏎ that comes for another app's field: its text isn't asked for, nor sent where a shell told it
    /// all the same. (Failed: the text was asked for and sent.)
    @Test func replyDoesNotReadAnotherFieldsText() async throws {
        try await withInterfaceLanguage("en") {
            let model = ThirdPassModel()
            let host = ThirdPass.host(model: model)
            host.selection = nil
            try ThirdPass.toldNone(host)
            host.type("@reply")
            host.press(FakeHost.tab)
            host.type("ok")
            try #require(host.composer.draftCommand == .reply)
            let other = FieldInfo(app: ThirdPass.browser)
            let wanted = host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure, field: other))
            #expect(wanted.contains(.passwordField) && !wanted.contains(.text), "\(wanted)")
            var told = FieldContext(read: [.secure, .text], field: other)
            told.text = host.context.text
            host.press(FakeHost.enter, with: told)
            host.settle(timeout: 1.5) { !model.requests.isEmpty }
            #expect(!model.texts.contains { $0.contains("hunter2") }, "the other field's text was sent: \(model.texts)")
        }
    }
}

// MARK: - 3. A tap of Option

@Suite(.serialized)
struct Review076OptionTapTests {
    /// `@reply ok` drafted in a field told to be none, a tap of Option the action key.
    private func replyDrafted(_ model: ThirdPassModel) throws -> FakeHost {
        let host = ThirdPass.host(model: model, actionKey: .optionTap)
        host.selection = nil
        try ThirdPass.toldNone(host)
        host.type("@reply")
        host.press(FakeHost.tab)
        host.type("ok")
        try #require(host.composer.draftCommand == .reply && host.composer.actionKey == .optionTap)
        return host
    }

    private func tapOption(_ host: FakeHost, _ context: FieldContext) {
        host.send(.modifiers(ThirdPass.optionDown, context))
        host.send(.modifiers(ThirdPass.optionUp, context))
    }

    /// The premise of the tests below: in a field told to be none, the tap's read asks for the text and sends it.
    @Test func theTapReadsTheTextOfAFieldToldNone() async throws {
        try await withInterfaceLanguage("en") {
            let model = ThirdPassModel()
            let host = try replyDrafted(model)
            let field = FieldInfo(app: ThirdPass.editor)
            #expect(host.session.fieldWants(forModifiers: ThirdPass.optionUp, given: FieldContext(read: .secure, field: field)).contains(.text))
            var told = FieldContext(read: [.secure, .text], field: field)
            told.text = host.context.text
            tapOption(host, told)
            host.settle(timeout: 1.5) { !model.requests.isEmpty }
            #expect(model.texts.contains { $0.contains("hunter2") }, "the field's text wasn't sent: \(model.texts)")
        }
    }

    /// The modifier change's own read says the field is a password field (`FieldInfo.secure`), the session's last word
    /// being "none": the text isn't asked for, and one told all the same isn't sent. (Failed: the tap's path took
    /// nothing of what its read said of the field, asked for the text and sent it.)
    @Test func theTapGoesByWhatItsReadSaysOfTheField() async throws {
        try await withInterfaceLanguage("en") {
            let model = ThirdPassModel()
            let host = try replyDrafted(model)
            let field = FieldInfo(app: ThirdPass.editor, secure: true)
            let wanted = host.session.fieldWants(forModifiers: ThirdPass.optionUp, given: FieldContext(read: .secure, field: field))
            #expect(!wanted.contains(.text), "\(wanted)")
            var told = FieldContext(read: [.secure, .text], field: field)
            told.text = host.context.text
            tapOption(host, told)
            #expect(host.session.passwordField == .yes, "\(String(describing: host.session.passwordField))")
            host.settle(timeout: 1) { !model.requests.isEmpty }
            #expect(!model.texts.contains { $0.contains("hunter2") }, "a password field's text was sent: \(model.texts)")
            #expect(host.session.fieldText == nil, "a password field's text is kept")
        }
    }

    /// The tap comes for another app's field (no focus told): asked whether it is a password field, its text neither
    /// asked for nor sent. (Failed: the editor's "none" let it through.)
    @Test func theTapDoesNotReadAnotherFieldsText() async throws {
        try await withInterfaceLanguage("en") {
            let model = ThirdPassModel()
            let host = try replyDrafted(model)
            let field = FieldInfo(app: ThirdPass.browser)
            let wanted = host.session.fieldWants(forModifiers: ThirdPass.optionUp, given: FieldContext(read: .secure, field: field))
            #expect(wanted.contains(.passwordField) && !wanted.contains(.text), "\(wanted)")
            var told = FieldContext(read: [.secure, .text], field: field)
            told.text = host.context.text
            let reads = host.passwordFieldReads
            tapOption(host, told)
            #expect(host.passwordFieldReads == reads + 1, "the shell wasn't asked about the field the tap came for")
            host.settle(timeout: 1) { !model.requests.isEmpty }
            #expect(!model.texts.contains { $0.contains("hunter2") }, "the other field's text was sent: \(model.texts)")
        }
    }

    /// Text read with a modifier change isn't kept (`fieldText`, what `@reply` falls back on after dictation) where
    /// secure input is on in the field, nor from a password manager's field. (Failed: kept before either was looked at.)
    @Test func textReadWithAModifierIsNotKeptFromAPrivateField() throws {
        let secure = ThirdPass.host()
        try ThirdPass.toldNone(secure)
        var told = FieldContext(read: [.secure, .text], field: FieldInfo(app: ThirdPass.editor), secure: true)
        told.text = FieldText(before: "hunter2 secret", after: "")
        secure.send(.modifiers(ThirdPass.optionDown, told))
        #expect(secure.session.fieldText == nil, "kept where secure input is on")

        let manager = ThirdPass.host()
        try ThirdPass.toldNone(manager)
        told = FieldContext(read: [.secure, .text], field: FieldInfo(app: ThirdPass.passwordManager))
        told.text = FieldText(before: "hunter2 secret", after: "")
        manager.send(.modifiers(ThirdPass.optionDown, told))
        #expect(manager.session.fieldText == nil, "kept from a password manager's field")

        // The premise: kept in the field told to be none.
        let plain = ThirdPass.host()
        try ThirdPass.toldNone(plain)
        told = FieldContext(read: [.secure, .text], field: FieldInfo(app: ThirdPass.editor))
        told.text = FieldText(before: "hunter2 secret", after: "")
        plain.send(.modifiers(ThirdPass.optionDown, told))
        #expect(plain.session.fieldText?.before == "hunter2 secret")
    }

    /// In a field not told yet, the tap's read asks whether it is a password field, not for the text, with a tap of
    /// Option the action key (the check `Review076NeverAskedFieldTests.replyAsksBeforeItReadsTheText` made with ⏎ the
    /// action key, where no tap reads anything: it held whatever the session knew).
    @Test func theTapAsksBeforeItReadsTheText() async throws {
        try await withInterfaceLanguage("en") {
            let host = try replyDrafted(ThirdPassModel())
            let field = FieldContext(read: .secure, field: FieldInfo(app: ThirdPass.editor))
            try #require(host.session.fieldWants(forModifiers: ThirdPass.optionUp, given: field).contains(.text),
                         "the premise: the tap reads the text of a field told none")
            // Not asked in this field, as after a focus nothing told the session of.
            host.session.passwordField = nil
            host.session.passwordFieldAsked = -1
            let wanted = host.session.fieldWants(forModifiers: ThirdPass.optionUp, given: field)
            #expect(wanted.contains(.passwordField) && !wanted.contains(.text), "\(wanted)")
            host.session.passwordField = .unknown
            #expect(host.session.fieldWants(forModifiers: ThirdPass.optionUp, given: field) == [.secure], "the shell couldn't tell")
        }
    }
}

// MARK: - 4. Asked while secure input is on

@Suite(.serialized)
struct Review076SecureInputAskTests {
    /// Another app holds secure input (the field's own app doesn't: the key's read says no): "@" asks nothing of the
    /// shell, whose answer would be Accessibility's while secure input is on. Asked once it is off. (Failed: the key's
    /// read said the answer follows, and the session asked.)
    @Test func nothingIsAskedWhileSecureInputIsOn() throws {
        let secureInput = SecureInputSwitch()
        secureInput.isOn = true
        let host = ThirdPass.host(secureInput: secureInput)
        try #require(host.passwordFieldReads == 0, "the premise: not asked with the focus")
        host.press(FakeHost.at, with: ThirdPass.macContext(host, for: FakeHost.at))
        #expect(host.passwordFieldReads == 0, "asked while secure input is on")
        host.press(FakeHost.escape, with: ThirdPass.macContext(host, for: FakeHost.escape))
        secureInput.isOn = false
        host.press(FakeHost.at, with: ThirdPass.macContext(host, for: FakeHost.at))
        #expect(host.passwordFieldReads == 1, "asked \(host.passwordFieldReads) times once secure input is off")
    }
}
