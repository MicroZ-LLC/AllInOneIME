import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Acceptance tests for the owner's decision of 2026-11-26 (0.7.6), written from the decision only, independently of
// the implementation: where the shell answers that it does NOT KNOW whether the focused field is a password field
// (`InputSession.PasswordField.unknown`: the Mac without Accessibility, nothing focused, no answer in time, the read
// failed), a command doesn't read the field's text: neither the selection ("@" on a selection) nor the text around
// the caret (@reply), exactly as in a known password field, and as in a field whose answer hasn't come back yet
// (asked, not answered: `passwordField == nil`).
//  1. @reply in a field answered unknown: the text around the caret isn't asked for, and isn't used where the shell
//     tells it anyway;
//  2. "@" on a selection in a field answered unknown: the selection isn't asked for, taken or read after the key;
//  3. the same while the answer is pending;
//  4. control: a field answered "not a password field" is read as before (passes today).
// Unchanged, and so only checked not to break: what the user typed into the draft of an AI command they ran is still
// sent (an unknown field isn't refused as a known password field is).
//
// How the field is played: a `FakeHost` tells everything with each key (`FieldContext.Parts.all`), so the session
// itself must leave the selection and the text alone; where the Mac reads only what the session asks for
// (`InputSession.fieldWants`), that is checked too. What goes to the AI is read back from a recording stand-in for
// Apple's on-device model, never assumed.
//
// ASSUMPTIONS (the narrowest reading of the decision):
//  A. "As in a password field, for reads": the reads a known password field doesn't get today, which are
//     `fieldWants` without `.text` for the key that runs @reply and without `.selection`/`.selectedRange` for "@", no
//     `SessionOutput.readSelection` after the key, no selection in the draft, and none of the field's text in any
//     request. A known password field also refuses the AI command outright; the decision doesn't ask that of an
//     unknown field (what was typed is still sent), so that isn't asserted the same.
//  B. @reply with nothing typed and no text read has nothing to reply to: it shows what it shows in a field told
//     "not a password field" that has no text at all (same draft, panel and notice), and sends nothing.
//  C. "Pending" is a field the shell was asked about off the key's thread (`passwordFieldFollows`,
//     `SessionOutput.readPasswordField`) whose answer hasn't come. A field never asked about at all isn't tested.

// MARK: - Fakes

/// Apple's on-device model, standing in for any provider: records every request a field's session makes, answers "OK".
fileprivate final class PWUnknownModel: AppleModelBackend, @unchecked Sendable {
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

// MARK: - The rig

/// A field of an ordinary editor, and what the shell says of its being a password field.
fileprivate struct PWUnknownField {
    /// What the shell told of the field.
    enum Told: CaseIterable {
        /// Answered: it can't tell (`PasswordField.unknown`).
        case unknown
        /// Asked off the key's thread, not answered yet (`passwordField == nil`).
        case pending
        /// Answered: not a password field.
        case no
    }

    /// What the field holds.
    enum Text { case selected, caretInside, empty }

    static let editor = "com.apple.TextEdit"
    /// A note, all of it selected (`Text.selected`).
    static let note = "Private note: recovery words maple orbit lantern"
    /// The text before and after the caret, nothing selected (`Text.caretInside`).
    static let before = "Bank PIN 4921, keep it safe. "
    static let after = " Safe combination 33-12-08."

    let host: FakeHost
    let model = PWUnknownModel()
    let told: Told

    init(_ told: Told, text: Text) {
        self.told = told
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
        host = FakeHost(services: services)
        host.app = Self.editor
        host.appTypesKeys = true
        switch text {
        case .selected:
            host.document = Self.note
            host.selection = 0..<(Self.note as NSString).length
        case .caretInside:
            host.document = Self.before + Self.after
            let caret = (Self.before as NSString).length
            host.selection = caret..<caret
        case .empty:
            break
        }
        // The answers asked for off the key's thread are held back while pending; every read answers "can't tell" where
        // the shell can't.
        host.fieldReadsWait = told == .pending
        host.cannotTellPasswordField = told == .unknown
        host.focus()
        host.composer.setInputMode(.english)
        switch told {
        case .unknown: host.send(.passwordField(nil, focus: host.session.fieldSession))
        case .no: host.send(.passwordField(false, focus: host.session.fieldSession))
        case .pending: break  // asked with the first key (`context`)
        }
    }

    /// What the field says with a key: all of it; while pending, that whether it is a password field follows the key.
    var context: FieldContext {
        var context = host.context
        if told == .pending { (context.passwordFieldUnknown, context.passwordFieldFollows) = (true, true) }
        return context
    }

    @discardableResult
    func press(_ key: KeyEvent) -> Bool { host.press(key, with: context) }

    /// Types `text`, a key a character.
    func type(_ text: String) {
        for character in text {
            press(character == "@" ? FakeHost.at : character == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: String(character)))
        }
    }

    /// `command` picked by name with Tab, then `typed`, then ⏎ when `run`.
    func write(_ command: String, typed: String = "", run: Bool = true) {
        type("@" + command)
        press(FakeHost.tab)
        if !typed.isEmpty { type(typed) }
        if run { press(FakeHost.enter) }
    }

    /// Waits for the requests the keys started (`expected`: at least one), handing the session its answers.
    @discardableResult
    func requests(expected: Bool) -> [String] {
        host.settle(timeout: expected ? 5 : 0.4) { expected && !model.requests.isEmpty }
        return model.texts
    }

    /// The field is told as the test means it (the premise of each case): unknown, not told yet with the shell asked
    /// once, or none. Secure input is off throughout.
    func expectTold(_ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!host.session.secureInputActive(), comment, sourceLocation: sourceLocation)
        switch told {
        case .unknown:
            #expect(host.session.passwordField == .unknown, comment, sourceLocation: sourceLocation)
        case .pending:
            #expect(host.session.passwordField == nil && host.passwordFieldReads == 1, comment, sourceLocation: sourceLocation)
        case .no:
            #expect(host.session.passwordField == .no, comment, sourceLocation: sourceLocation)
        }
    }

    /// Whether ⏎ (the key that runs the draft) asks the field for its text, once secure input is read off: what the Mac
    /// then reads.
    var textWanted: Bool {
        host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure)).contains(.text)
    }

    /// Whether "@" asks the field for its selection, once secure input is read off.
    var selectionWanted: Bool {
        !host.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure)).isDisjoint(with: [.selection, .selectedRange])
    }

    /// The parts of the field's own text found in `texts` (requests, or what is shown).
    static func leaks(_ texts: [String]) -> [String] {
        [note, "maple orbit", "4921", "33-12-08"].filter { secret in texts.contains { $0.contains(secret) } }
    }

    /// What the user sees and what was sent.
    struct Seen: Equatable, CustomStringConvertible {
        var draft: String
        var command: String?
        var composing: Bool
        var panel: PanelModel?
        var notice: String?
        var document: String
        var requests: [String]

        var description: String {
            "draft \(draft.debugDescription), command \(command ?? "none"), composing \(composing), notice "
                + "\(notice?.debugDescription ?? "none"), document \(document.debugDescription), requests \(requests), "
                + "panel \(panel.map { String(describing: $0) } ?? "none")"
        }
    }

    /// What is seen now, and what was sent (`expected`: a request is waited for).
    func seen(requests expected: Bool) -> Seen {
        var seen = Seen(draft: host.composer.draft, command: host.composer.draftCommand?.name, composing: host.composer.isComposing,
                        panel: host.panel, notice: host.noticeAlone, document: host.document, requests: [])
        seen.requests = requests(expected: expected)
        return seen
    }
}

// MARK: - The tests

@Suite(.serialized)
struct PasswordFieldUnknownTests {
    fileprivate typealias Field = PWUnknownField

    // MARK: 1. @reply in a field answered unknown

    /// @reply in a field the shell couldn't tell, the caret between two texts: ⏎ doesn't ask the field for its text (the
    /// Mac reads only what is asked), and where the shell tells it with the key anyway none of it is sent; what was
    /// typed after the command still is. (Fails today: the text is asked for and sent.)
    @Test func replyReadsNoTextWhereTheShellCouldNotTell() async {
        await withInterfaceLanguage("en") {
            let field = Field(.unknown, text: .caretInside)
            field.write("reply", typed: "ok", run: false)
            field.expectTold("the test field must be one the shell couldn't tell")
            #expect(field.host.composer.draftCommand == .reply)
            #expect(!field.textWanted, "⏎ on @reply asks for the text around the caret")
            field.press(FakeHost.enter)
            let sent = field.requests(expected: true)
            #expect(Field.leaks(sent).isEmpty, "the text around the caret was sent: \(Field.leaks(sent))")
            // Unchanged: an unknown field isn't refused as a known password field is; what was typed is sent.
            #expect(sent.contains { $0.contains("ok") }, "what was typed isn't sent: \(sent)")
            #expect(field.host.noticeAlone?.hasPrefix("Secure input is on") != true,
                    "refused as a known password field: \(String(describing: field.host.noticeAlone))")
        }
    }

    /// @reply with nothing typed there: no text read, so nothing to reply to. Nothing is sent, and what shows is what
    /// shows in a field told "not a password field" that has no text at all (ASSUMPTION B). (Fails today: the text
    /// around the caret is sent.)
    @Test func replyWithNothingTypedHasNothingToReplyToWhereTheShellCouldNotTell() async {
        await withInterfaceLanguage("en") {
            let empty = Field(.no, text: .empty)
            empty.write("reply")
            let nothing = empty.seen(requests: false)
            #expect(nothing.requests.isEmpty, "the reference itself sent something: \(nothing)")

            let field = Field(.unknown, text: .caretInside)
            field.write("reply")
            field.expectTold("the test field must be one the shell couldn't tell")
            var seen = field.seen(requests: false)
            #expect(seen.requests.isEmpty, "@reply with nothing typed sent: \(seen.requests)")
            #expect(seen.document == Field.before + Field.after, "the field's text changed: \(seen.document)")
            seen.document = nothing.document
            #expect(seen == nothing, """
                not what a field with nothing to read shows
                  couldn't tell: \(seen)
                  no text:       \(nothing)
                """)
        }
    }

    // MARK: 2. The selection in a field answered unknown

    /// A note selected in a field the shell couldn't tell: "@" doesn't ask for the selection, doesn't take it when the
    /// field tells it with the key anyway, and asks for no read of it after the key (the Mac's Accessibility read). The
    /// command starts on nothing and the field's text stays. (Fails today: the selection is read and worked on.)
    @Test func theSelectionIsNotReadWhereTheShellCouldNotTell() async {
        await withInterfaceLanguage("en") {
            // Asked for, as the Mac asks.
            let asked = Field(.unknown, text: .selected)
            asked.expectTold("the test field must be one the shell couldn't tell")
            #expect(!asked.selectionWanted, "\"@\" asks for the selection")

            // Told with the key anyway (a shell where reading is cheap tells it all).
            let told = Field(.unknown, text: .selected)
            told.press(FakeHost.at)
            told.expectTold("the test field must be one the shell couldn't tell")
            #expect(told.host.composer.isComposing, "\"@\" starts a command")
            #expect(told.host.composer.selection == nil,
                    "the command works on the selection: \(String(describing: told.host.composer.selection))")
            #expect(Field.leaks([String(describing: told.host.panel), told.host.marked]).isEmpty,
                    "the panel shows the note: \(String(describing: told.host.panel))")
            #expect(told.host.document == Field.note, "the field's text changed: \(told.host.document)")

            // Only readable after the key (the Mac's Accessibility): no read is asked for.
            let after = Field(.unknown, text: .selected)
            var context = after.context
            context.selection = nil
            context.selectionFollows = true
            after.host.press(FakeHost.at, with: context)
            #expect(after.host.selectionReads.isEmpty && !after.host.composer.selectionPending,
                    "the selection is read after the key: \(after.host.selectionReads)")
            #expect(after.host.composer.selection == nil)
        }
    }

    /// A command run on that selection sends none of it: @translate there, with nothing typed, has nothing of the field
    /// to translate. (Fails today: the note is translated.)
    @Test func aCommandSendsNoSelectionWhereTheShellCouldNotTell() async {
        await withInterfaceLanguage("en") {
            let field = Field(.unknown, text: .selected)
            field.write("translate")
            field.expectTold("the test field must be one the shell couldn't tell")
            let sent = field.requests(expected: false)
            #expect(Field.leaks(sent).isEmpty, "the selection was sent: \(sent)")
            #expect(field.host.document == Field.note, "the field's text changed: \(field.host.document)")

            // Unchanged: what is typed after the command is sent, and only that.
            let typed = Field(.unknown, text: .selected)
            typed.write("translate", typed: "hello")
            let texts = typed.requests(expected: true)
            #expect(texts.contains { $0.contains("hello") }, "what was typed isn't sent: \(texts)")
            #expect(Field.leaks(texts).isEmpty, "the selection was sent: \(texts)")
        }
    }

    // MARK: 3. Pending: asked, not answered yet

    /// While the shell's answer hasn't come (asked off the key's thread with the first key), the field is read no more
    /// than one it couldn't tell: @reply's ⏎ doesn't ask for the text around the caret and none of it is sent; "@"
    /// takes no selection and asks for no read of it after the key. (Fails today: both are read.)
    @Test func nothingIsReadWhileTheAnswerIsPending() async {
        await withInterfaceLanguage("en") {
            let reply = Field(.pending, text: .caretInside)
            reply.write("reply", typed: "ok", run: false)
            reply.expectTold("the test field must be asked about once and not told yet")
            #expect(reply.host.composer.draftCommand == .reply)
            #expect(!reply.textWanted, "⏎ on @reply asks for the text around the caret")
            reply.press(FakeHost.enter)
            reply.expectTold("no key waits for the answer")
            let sent = reply.requests(expected: true)
            #expect(Field.leaks(sent).isEmpty, "the text around the caret was sent: \(Field.leaks(sent))")
            #expect(sent.contains { $0.contains("ok") }, "what was typed isn't sent: \(sent)")

            let told = Field(.pending, text: .selected)
            told.press(FakeHost.at)
            told.expectTold("the test field must be asked about once and not told yet")
            #expect(told.host.composer.isComposing, "\"@\" starts a command")
            #expect(told.host.composer.selection == nil,
                    "the command works on the selection: \(String(describing: told.host.composer.selection))")
            #expect(told.host.document == Field.note, "the field's text changed: \(told.host.document)")

            let after = Field(.pending, text: .selected)
            var context = after.context
            context.selection = nil
            context.selectionFollows = true
            after.host.press(FakeHost.at, with: context)
            after.expectTold("the test field must be asked about once and not told yet")
            #expect(after.host.selectionReads.isEmpty && !after.host.composer.selectionPending,
                    "the selection is read after the key: \(after.host.selectionReads)")
            #expect(after.host.composer.selection == nil)
        }
    }

    // MARK: 4. Control: answered "not a password field"

    /// A field the shell told is no password field is read as before (passes today): "@" asks for the selection and
    /// works on it, a command on it sends it, and @reply asks for the text around the caret and sends it.
    @Test func aFieldToldNoPasswordFieldIsReadAsBefore() async {
        await withInterfaceLanguage("en") {
            let asked = Field(.no, text: .selected)
            asked.expectTold("the test field must be told none")
            #expect(asked.selectionWanted, "\"@\" doesn't ask for the selection")

            let told = Field(.no, text: .selected)
            told.press(FakeHost.at)
            told.expectTold("the test field must be told none")
            #expect(told.host.composer.selection?.text == Field.note, "\(String(describing: told.host.composer.selection))")

            let after = Field(.no, text: .selected)
            var context = after.context
            context.selection = nil
            context.selectionFollows = true
            after.host.press(FakeHost.at, with: context)
            #expect(after.host.selectionReads.count == 1, "the selection isn't read after the key: \(after.host.selectionReads)")

            let translate = Field(.no, text: .selected)
            translate.write("translate")
            let translated = translate.requests(expected: true)
            #expect(translated.contains { $0.contains(Field.note) }, "the selection isn't translated: \(translated)")

            let reply = Field(.no, text: .caretInside)
            reply.write("reply", typed: "ok", run: false)
            reply.expectTold("the test field must be told none")
            #expect(reply.textWanted, "⏎ on @reply doesn't ask for the text around the caret")
            reply.press(FakeHost.enter)
            let replied = reply.requests(expected: true)
            #expect(replied.contains { $0.contains("4921") && $0.contains("33-12-08") && $0.contains("ok") },
                    "the text around the caret isn't sent: \(replied)")
        }
    }
}
