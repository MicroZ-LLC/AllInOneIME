import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// `InputSession.nothingLeavesDevice`: secure input on, or a field told to be a password field where it isn't, the one
/// check for what may leave the device (GitHub #70, #71).
@Suite(.serialized)
struct NothingLeavesDeviceTests {
    /// A field (English) whose secure input elsewhere is `secure`'s.
    private func field(secure: Locked<Bool> = Locked(initialState: false)) -> FakeHost {
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.secureInputActive = { secure.withLock { $0 } }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    private func tell(_ host: FakeHost, passwordField told: Bool?) {
        host.send(.passwordField(told, focus: host.session.fieldSession))
    }

    @Test func secureInputOrAKnownPasswordField() {
        let secure = Locked(initialState: false)
        let host = field(secure: secure)
        #expect(!host.session.nothingLeavesDevice(), "a field not told yet is as any other")
        #expect(host.session.fieldMayNotBeRead(), "but isn't read until it is told none")
        tell(host, passwordField: nil)
        #expect(!host.session.nothingLeavesDevice(), "nor one the shell couldn't tell: only its reads stop (`fieldMayNotBeRead`)")
        #expect(host.session.fieldMayNotBeRead() && !host.composer.secureInputActive())
        tell(host, passwordField: false)
        #expect(!host.session.nothingLeavesDevice() && !host.composer.secureInputActive())
        #expect(!host.session.fieldMayNotBeRead(), "told none after it couldn't tell: read")
        secure.withLock { $0 = true }
        #expect(host.session.nothingLeavesDevice() && host.composer.secureInputActive(), "secure input on anywhere")
        secure.withLock { $0 = false }
        tell(host, passwordField: true)
        #expect(host.session.nothingLeavesDevice() && !host.session.secureInputActive(), "a known password field")
        #expect(host.composer.secureInputActive(), "the composer goes by the same check")
        // Told none after: it stays one until another field takes the focus.
        tell(host, passwordField: false)
        #expect(host.session.nothingLeavesDevice())
        host.focus()
        #expect(!host.session.nothingLeavesDevice() && !host.composer.secureInputActive())
    }

    @Test func aKnownPasswordFieldIsNotReadForReply() {
        // Whether ⏎ on "@reply ok" asks for the text around the caret, once secure input is read off.
        func textWanted(_ host: FakeHost) -> Bool {
            host.type("@reply")
            host.press(FakeHost.tab)
            host.type("ok")
            #expect(host.composer.draftCommand == .reply)
            return host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure)).contains(.text)
        }
        let known = field()
        tell(known, passwordField: true)
        #expect(!textWanted(known))
        // One the shell couldn't tell is read no more than a password field (the owner's decision, 2026-11-26).
        let untold = field()
        untold.cannotTellPasswordField = true  // each key's read can't tell either
        tell(untold, passwordField: nil)
        #expect(!textWanted(untold), "the shell couldn't tell: not read")
        let none = field()
        tell(none, passwordField: false)
        #expect(textWanted(none), "told none: read")
        #expect(textWanted(field()), "told none with its keys (a shell that reads it all): read")
    }

    @Test func aKnownPasswordFieldHasNoAIRowsNorTranslateAsYouType() {
        let host = field()
        tell(host, passwordField: true)
        host.type("x!@abc")
        #expect(!host.composer.oneAtRows.contains { $0.command?.usesAI == true }, "\(host.composer.oneAtRows)")
        let mode = field()
        tell(mode, passwordField: true)
        _ = mode.composer.setTranslateMode(TranslateMode.Session(target: OutputLanguage("fr")))
        mode.type("Qwerty")
        #expect(mode.composer.draft.isEmpty && !mode.composer.modeCollects)
    }

    /// An AI command typed by its name and run with ⏎: refused in either case; in a known password field what was typed
    /// goes in as typed and ⏎ goes on to the field (where secure input is on elsewhere: refused in the panel, as before).
    @Test func aRefusedRequestInAKnownPasswordFieldGoesInAsTyped() async {
        await withInterfaceLanguage("en") {
            func run(_ host: FakeHost) -> Bool {
                host.type("@question")
                host.press(FakeHost.tab)
                host.type("what")
                #expect(host.composer.draftCommand == .question)
                return host.press(FakeHost.enter)
            }
            let known = field()
            tell(known, passwordField: true)
            #expect(!run(known), "⏎ goes on to the password field")
            #expect(known.document == "@question what" && !known.composer.isComposing && known.panel == nil)
            #expect(known.noticeAlone?.hasPrefix("Secure input is on") == true, "\(String(describing: known.noticeAlone))")

            let secure = Locked(initialState: true)
            let elsewhere = field(secure: secure)
            #expect(run(elsewhere), "taken: the draft stays, refused")
            #expect(elsewhere.document.isEmpty && elsewhere.composer.draft == "@question what")
            if case let .failed(message) = elsewhere.composer.phase {
                #expect(message.hasPrefix("Secure input is on"))
            } else {
                Issue.record("not refused: \(elsewhere.composer.phase)")
            }
        }
    }
}
