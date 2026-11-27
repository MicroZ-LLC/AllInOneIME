import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What the Mac's main thread never waits for (0.7.6, AGENTS.md rule 6), as the core has it: a stop of typing out asks
/// to be asked again instead of waiting (`TypeOut.Typist.stopping`); a password field told after the key
/// (`FieldContext.passwordFieldFollows`) leaves rows out until it is.
struct MainThreadWaitsTests {
    typealias Seeded = TypeOutMistakesTests.Seeded

    /// In a field that tells its text late, `stopping` never waits itself: it asks to be asked again (nil), `patience`
    /// times at most for each of its two checks, and then ends as `stop` does; `waiting` false ends it at once.
    @Test func stoppingAsksAgainInsteadOfWaiting() {
        var askedAgain = 0
        for text in TypistTests.texts { for seed in UInt64(0)..<10 {
            var random = Seeded(state: seed)
            let plan = TypistTests.plan(text, &random)
            guard plan.contains(where: \.isSlip) else { continue }
            // Typed into a field that keeps up (typos are made where it holds what was typed), stopped in one that tells
            // its text late after an edit: taking the typo out.
            let field = TypistTests.SimField("> ")
            field.random = Seeded(state: seed &* 31 &+ 7)
            // A field a fix was seen taken in: typos of more than a character, each one's fix checked.
            var typist = TypeOut.Typist(plan, start: 2, length: field.text.count, proven: true)
            for _ in 0..<100_000 {
                let (looked, whole, now) = (field.copy(), field.copy(), field.copy())
                (looked.lag, whole.lag, now.lag) = (0.9, 0.9, 0.9)
                var (stepwise, once, atOnce) = (typist, typist, typist)
                var (rest, nils) = (String?.none, 0)
                while rest == nil {
                    rest = stepwise.stopping(insertingRest: true, in: looked)
                    if rest == nil { nils += 1 }
                }
                #expect(nils <= 2 * TypeOut.Typist.patience, "seed \(seed): asked again \(nils) times")
                #expect(rest == once.stop(insertingRest: true, in: whole) && looked.string == whole.string, "seed \(seed)")
                #expect(atOnce.stopping(insertingRest: true, in: now, waiting: false) != nil, "seed \(seed): not at once")
                askedAgain += nils
                if typist.step(in: field) == .done { break }
            }
        } }
        #expect(askedAgain > 0, "a field that tells its text late was asked again")
    }

    /// A key that types `character` (on a US keyboard's place of A: what is typed is what the test looks at).
    static func letter(_ character: String) -> KeyEvent { KeyEvent(keyCode: 0x00, characters: character) }

    /// A host that tells whether the field is a password field after the key (the Mac since 0.7.6: Accessibility is
    /// never asked with it), its first key read with it asked for.
    static func keyTellingPasswordFieldLater(_ host: FakeHost) -> FieldContext {
        var context = host.context
        context.read.insert(.passwordField)
        (context.passwordFieldUnknown, context.passwordFieldFollows) = (true, true)
        return context
    }

    /// Told after the key: not told until the answer comes, asked once a field (a key meanwhile doesn't ask again), the
    /// answer taken for the field it was asked in only.
    @Test func aPasswordFieldToldAfterTheKeyIsAskedOnceAndUnknownUntilThen() {
        let host = FakeHost(services: SessionServices())
        host.fieldReadsWait = true
        host.focus()
        let context = Self.keyTellingPasswordFieldLater(host)
        host.press(Self.letter("a"), with: context)
        host.press(Self.letter("b"), with: context)
        #expect(host.passwordFieldReads == 1, "asked once a field: \(host.passwordFieldReads)")
        #expect(host.session.passwordField == nil, "not told until the answer comes")
        #expect(host.session.fieldIsPrivate(unknown: true), "no rows, nothing learned meanwhile")
        host.answerFieldReads()
        #expect(host.session.passwordField == InputSession.PasswordField.no)
        // An answer for a field left since is dropped.
        host.focus()
        host.press(Self.letter("c"), with: Self.keyTellingPasswordFieldLater(host))
        let asked = host.session.fieldSession
        host.focus()
        host.send(.passwordField(true, focus: asked))
        #expect(host.session.passwordField == nil, "the field it was asked in has lost the focus")
    }

    /// A shell that reads the password field with the key (`passwordFieldFollows` false) is as before: told at once,
    /// nothing asked after it (the focus asked, once; its answer hasn't come).
    @Test func aPasswordFieldReadWithTheKeyIsToldAtOnce() {
        let host = FakeHost(services: SessionServices())
        host.fieldReadsWait = true
        host.focus()
        var context = host.context
        context.read.insert(.passwordField)
        context.passwordFieldUnknown = true
        host.press(Self.letter("a"), with: context)
        #expect(host.session.passwordField == InputSession.PasswordField.unknown && host.passwordFieldReads == 1)
    }
}
