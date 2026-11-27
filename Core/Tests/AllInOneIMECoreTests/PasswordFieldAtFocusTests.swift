import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The shell is asked whether a field is a password field as the field takes the focus
/// (`InputSession.passwordFieldFocused`), off the key's thread, so that its answer is usually back before the first
/// key: the first "@" in a field then takes the selected text. Once a field, never during secure input.
@Suite(.serialized)
struct PasswordFieldAtFocusTests {
    private static let editor = "com.example.editor"

    /// A session with "The report looks good" in its field, all selected, in an ordinary app; nothing focused yet.
    private func host() -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.useSelection = true
        config.setOrder([Language.english, .chinese])
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        let host = FakeHost(services: services)
        host.app = Self.editor
        host.document = "The report looks good"
        host.selection = 0..<21
        return host
    }

    /// What the field says for `key` as the Mac reads it: only what the session asks for, and whether it is a password
    /// field never with the key (told after it: `FieldContext.passwordFieldFollows`).
    private func macContext(_ host: FakeHost, for key: KeyEvent) -> FieldContext {
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

    private func asks(_ outputs: [SessionOutput]) -> [Int] {
        outputs.compactMap { if case let .readPasswordField(focus) = $0 { return focus } else { return nil } }
    }

    /// The focus asks, once, for the field that took it; no key asks again, and the next field is asked for itself.
    @Test func theFocusAsksOnceAField() {
        let host = host()
        let field = FieldInfo(app: Self.editor, terminal: false)
        let first = host.session.handle(.focus(field)).outputs
        #expect(asks(first) == [host.session.fieldSession], "\(first)")
        #expect(host.session.passwordField == nil, "not told until the shell answers")
        let key = host.session.handle(.key(FakeHost.at, macContext(host, for: FakeHost.at))).outputs
        #expect(asks(key).isEmpty, "asked again with a key: \(key)")
        let asked = host.session.fieldSession
        let second = host.session.handle(.focus(field)).outputs
        #expect(asks(second) == [host.session.fieldSession] && host.session.fieldSession != asked, "\(second)")
    }

    /// Nothing is asked where nothing is read whatever the answer: a field secure input is on in, the system's secure
    /// input, a password manager's field.
    @Test func noFocusAsksDuringSecureInputNorInAPasswordManager() {
        let secure = host()
        #expect(asks(secure.session.handle(.focus(FieldInfo(app: Self.editor, terminal: false, secure: true))).outputs).isEmpty)

        var config = Config.default
        config.uiLanguage = "en"
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.secureInputActive = { true }
        let system = FakeHost(services: services)
        #expect(asks(system.session.handle(.focus(FieldInfo(app: Self.editor, terminal: false))).outputs).isEmpty)

        let manager = host()
        let field = FieldInfo(app: "com.1password.1password", terminal: false)
        #expect(field.textStaysHere, "the premise: a password manager")
        #expect(asks(manager.session.handle(.focus(field)).outputs).isEmpty)
    }

    /// Answered "none" before the first key: the first "@" reads the selection with the key.
    @Test func theFirstAtReadsTheSelectionOnceToldNone() throws {
        let host = host()
        host.focus()
        try #require(host.passwordFieldReads == 1 && host.session.passwordField == nil)
        host.send(.passwordField(false, focus: host.session.fieldSession))
        #expect(host.session.passwordField == .no)
        let context = macContext(host, for: FakeHost.at)
        #expect(context.read.contains(.selection), "\(context.read)")
        host.press(FakeHost.at, with: context)
        #expect(host.composer.selection?.text == "The report looks good")
        #expect(host.passwordFieldReads == 1, "asked \(host.passwordFieldReads) times")
    }

    /// Answered that it can't tell: the first "@" starts on nothing, the selection is neither read with the key nor
    /// after it, and the field isn't asked again.
    @Test func theFirstAtReadsNothingWhereTheShellCouldNotTell() throws {
        let host = host()
        host.cannotTellPasswordField = true
        host.focus()
        try #require(host.passwordFieldReads == 1)
        host.send(.passwordField(nil, focus: host.session.fieldSession))
        #expect(host.session.passwordField == .unknown)
        let context = macContext(host, for: FakeHost.at)
        #expect(!context.read.contains(.selection), "\(context.read)")
        host.press(FakeHost.at, with: context)
        #expect(host.composer.isComposing && host.composer.selection == nil && !host.composer.selectionPending)
        #expect(host.selectionReads.isEmpty && host.passwordFieldReads == 1)
    }

    /// The answer not back by the first "@": that one starts on nothing (as before); the next, after the answer, reads
    /// the selection. An answer for a field left since is dropped.
    @Test func anAtBeforeTheAnswerStartsOnNothing() throws {
        let host = host()
        host.fieldReadsWait = true
        host.focus()
        host.press(FakeHost.at, with: macContext(host, for: FakeHost.at))
        #expect(host.composer.isComposing && host.composer.selection == nil && host.passwordFieldReads == 1)
        host.answerFieldReads()
        #expect(host.session.passwordField == .no)
        host.press(FakeHost.escape, with: macContext(host, for: FakeHost.escape))
        try #require(!host.composer.isComposing)
        host.press(FakeHost.at, with: macContext(host, for: FakeHost.at))
        #expect(host.composer.selection?.text == "The report looks good")

        let asked = host.session.fieldSession
        host.focus()
        host.send(.passwordField(true, focus: asked))
        #expect(host.session.passwordField == nil, "the field it was asked in has lost the focus")
    }
}
