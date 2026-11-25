import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Acceptance tests for "password managers get the terminal's treatment" (0.7.5, owner decision 2026-11-14), written
// from the spec only, independently of the implementation. In any field of a password manager (`PasswordManagers`:
// 1Password, Bitwarden, … on the Mac; their .exe names on Windows), whatever the field reports of itself:
//  1. "@" never reads the selection: a command starts on nothing, exactly as in a terminal (same draft, same panel,
//     same messages);
//  2. no text of the field leaves the device: no text before/after the caret for @reply, no browser page;
//  3. what is typed after the command is still sent (`@translate hello` translates "hello"; @question works), no
//     "No AI" refusal;
//  4. nothing else changes: autocomplete and English-word learning stay off there, outside password managers the
//     selection is still used, a real password field / secure input behaves as before.
//
// How the field is played: a `FakeHost` tells everything with each key (`FieldContext.Parts.all`: the selection and
// the text around the caret included), so the session itself must leave them alone; where the Mac reads only what the
// session asks for (`InputSession.fieldWants`), that is checked too. What goes to the AI is read back from a recording
// stand-in for Apple's on-device model (the real `Converter` and `SessionTasks` in between), never assumed.
//
// ASSUMPTIONS (the narrowest reading of the spec):
//  A. "Exactly as in a terminal" is compared on what the user sees and what is sent: the composer's draft and command,
//     the marked text, the selection it works on, the candidate panel (`PanelModel`, all of it), the notice shown, the
//     selection reads asked for after the key, and the text of every request made. The terminal is Terminal.app
//     (`FieldInfo.terminal`), focused on the same field text and selection. How an answer goes into a terminal (one
//     line, ⌘V its own) is the terminal's and isn't compared. A notice said while the panel is up is in the panel (on
//     its footer's right, `PanelModel.detail`), not on its own (`FakeHost.noticeAlone`): both are compared. (So @reply
//     with nothing to reply to shows its hint in the panel's footer in a terminal; it is compared, not assumed.)
//  B. "No text is read" for @reply: the session doesn't ask the field for its text (`FieldContext.Parts.text`) with
//     the key that runs it. (The Mac's shell never reads a terminal's text either: `readFieldText` returns nil there.)
//  C. "No browser-page context": the session doesn't wake or read a page even where the shell would give one
//     (`SessionServices.page`); the Mac gives Chrome's only today, so this guards the one Core rule.

// MARK: - Fakes

/// Apple's on-device model, standing in for any provider: records every request a field's session makes, answers "OK".
fileprivate final class PMContextModel: AppleModelBackend, @unchecked Sendable {
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

/// A web page the shell would give for any app (`SessionServices.page`): whether it was woken or read.
fileprivate final class PMContextPage: @unchecked Sendable {
    static let secret = "Page secret: account 99-1234"
    private let state = Locked<(woken: Int, read: Int)>(initialState: (0, 0))
    var woken: Int { state.withLock { $0.woken } }
    var read: Int { state.withLock { $0.read } }

    var source: PageSource {
        PageSource(wake: { [self] in state.withLock { $0.woken += 1 } }, release: {}) { [self] in
            { [self] in
                state.withLock { $0.read += 1 }
                return PageContext(url: "https://bank.example.com", title: "Bank", selection: Self.secret, visible: Self.secret)
            }
        }
    }
}

// MARK: - The rig

fileprivate enum PMContext {
    static let onePassword = "com.1password.1password"
    static let bitwarden = "com.bitwarden.desktop"
    static let windowsOnePassword = "win:1password.exe"
    static let passwordManagers = [onePassword, bitwarden, windowsOnePassword]
    static let terminalApp = "com.apple.Terminal"
    static let editor = "com.apple.TextEdit"

    /// A secret note, all of it selected (`Field.selected`).
    static let note = "Vault note: recovery words maple orbit lantern"
    /// The text before and after the caret, nothing selected (`Field.caretInside`).
    static let before = "Bank PIN 4921, keep it safe. "
    static let after = " Safe combination 33-12-08."

    enum Field: CaseIterable { case selected, caretInside }

    /// A field of `app` (a terminal's with `terminal`) holding `field`'s text, in English, its requests going to `model`.
    static func host(app: String, terminal: Bool = false, field: Field, model: PMContextModel,
                     page: PMContextPage? = nil) -> FakeHost {
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
        if let page { services.page = { _ in page.source } }
        let host = FakeHost(services: services)
        host.app = app
        host.terminal = terminal
        host.appTypesKeys = true
        switch field {
        case .selected:
            host.document = note
            host.selection = 0..<(note as NSString).length
        case .caretInside:
            host.document = before + after
            let caret = (before as NSString).length
            host.selection = caret..<caret
        }
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    /// `command` picked by name with Tab, then `typed`, then ⏎ when `run`.
    static func write(_ host: FakeHost, _ command: String, typed: String = "", run: Bool = true) {
        host.type("@" + command)
        host.press(FakeHost.tab)
        if !typed.isEmpty { host.type(typed) }
        if run { host.press(FakeHost.enter) }
    }

    /// Waits for the requests the keys started (`expected`: at least one), handing the session its answers.
    @discardableResult
    static func requests(_ host: FakeHost, _ model: PMContextModel, expected: Bool) -> [String] {
        host.settle(timeout: expected ? 5 : 0.4) { expected && !model.requests.isEmpty }
        return model.texts
    }

    /// Whether any request or anything shown has the field's own text in it.
    static func leaks(_ texts: [String]) -> [String] {
        let secrets = [note, "maple orbit", "4921", "33-12-08", PMContextPage.secret]
        return secrets.filter { secret in texts.contains { $0.contains(secret) } }
    }

    /// Whether "@" (typed first in the field) asks the field for its selection, once secure input is read off.
    static func selectionWanted(_ host: FakeHost) -> Bool {
        !host.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure)).isDisjoint(with: [.selection, .selectedRange])
    }

    /// What the user sees and what was sent after some keys (ASSUMPTION A).
    struct Seen: Equatable, CustomStringConvertible {
        var draft: String
        var command: String?
        var marked: String
        var selection: String?
        var panel: PanelModel?
        var notice: String?
        var selectionReads: Int
        var requests: [String]

        var description: String {
            "draft \(draft.debugDescription), command \(command ?? "none"), marked \(marked.debugDescription), selection "
                + "\(selection?.debugDescription ?? "none"), notice \(notice?.debugDescription ?? "none"), selection reads "
                + "\(selectionReads), requests \(requests), panel \(panel.map { String(describing: $0) } ?? "none")"
        }
    }

    /// The keys of one scenario, and whether they start a request.
    struct Keys {
        var name: String
        var requests: Bool
        var press: (FakeHost) -> Void
    }

    static var scenarios: [Keys] {
        [
            Keys(name: "@", requests: false) { $0.type("@") },
            Keys(name: "@improve", requests: false) { $0.type("@improve") },
            Keys(name: "@improve ⇥ ⏎", requests: false) { write($0, "improve") },
            Keys(name: "@translate ⇥ hello ⏎", requests: true) { write($0, "translate", typed: "hello") },
            Keys(name: "@reply ⇥ ⏎", requests: false) { write($0, "reply") },
            Keys(name: "@reply ⇥ ok ⏎", requests: true) { write($0, "reply", typed: "ok") },
            Keys(name: "@question ⇥ what is it ⏎", requests: true) { write($0, "question", typed: "what is it") },
        ]
    }

    /// "@reply", Tab, ⏎: @reply with nothing typed.
    static var emptyReply: Keys { Keys(name: "@reply ⇥ ⏎", requests: false) { write($0, "reply") } }

    /// `keys` pressed in a field of `app` (a terminal's with `terminal`) holding `field`'s text, the shell giving `page`
    /// for it if any: what was seen and sent.
    static func seen(_ keys: Keys, app: String, terminal: Bool = false, field: Field, page: PMContextPage? = nil) -> Seen {
        let model = PMContextModel()
        let host = host(app: app, terminal: terminal, field: field, model: model, page: page)
        keys.press(host)
        let shown = Seen(draft: host.composer.draft, command: host.composer.draftCommand?.name, marked: host.marked,
                         selection: host.composer.selection?.text, panel: host.panel, notice: host.noticeAlone,
                         selectionReads: host.selectionReads.count, requests: [])
        var seen = shown
        seen.requests = requests(host, model, expected: keys.requests)
        return seen
    }
}

// MARK: - The tests

@Suite(.serialized)
struct PasswordManagerContextTests {
    /// The apps the spec names are password managers by the one Core list (passes today: the premise).
    @Test func premise_theAppsArePasswordManagers() {
        for app in PMContext.passwordManagers {
            #expect(PasswordManagers.contains(app), "\(app)")
        }
        #expect(!PasswordManagers.contains(PMContext.editor) && !PasswordManagers.contains(PMContext.terminalApp))
    }

    // MARK: 1. "@" never reads the selection

    /// A note selected in a password manager's field that isn't a password field (secure input off, told none): "@"
    /// doesn't ask for the selection (the Mac reads only what is asked), doesn't take it when the field tells it with
    /// the key anyway, and asks for no read of it after the key (the Mac's Accessibility read). The command starts on
    /// nothing, as in a terminal. (Fails today: the selection is read and worked on.)
    @Test func selectionIsNeverReadInAPasswordManager() async {
        await withInterfaceLanguage("en") {
            for app in PMContext.passwordManagers {
                // Asked for, as the Mac asks.
                let asked = PMContext.host(app: app, field: .selected, model: PMContextModel())
                #expect(!PMContext.selectionWanted(asked), "\(app): \"@\" asks for the selection")

                // Told with the key anyway (a shell where reading is cheap tells it all).
                let told = PMContext.host(app: app, field: .selected, model: PMContextModel())
                told.press(FakeHost.at)
                #expect(told.composer.isComposing, "\(app): \"@\" starts a command")
                #expect(told.composer.selection == nil, "\(app): the command works on the selection: \(String(describing: told.composer.selection))")
                #expect(PMContext.leaks([String(describing: told.panel), told.marked]).isEmpty,
                        "\(app): the panel shows the note: \(String(describing: told.panel))")
                #expect(told.document == PMContext.note, "\(app): the field's text changed: \(told.document)")

                // Only readable after the key (the Mac's Accessibility): no read is asked for.
                let after = PMContext.host(app: app, field: .selected, model: PMContextModel())
                var context = after.context
                context.selection = nil
                context.selectionFollows = true
                after.press(FakeHost.at, with: context)
                #expect(after.selectionReads.isEmpty && !after.composer.selectionPending,
                        "\(app): the selection is read after the key: \(after.selectionReads)")
                #expect(after.composer.selection == nil)
            }
        }
    }

    /// The same keys in a password manager and in a terminal, on the same field text (a selected note; the caret
    /// between two texts): the same draft, the same panel, the same notices, the same requests (ASSUMPTION A). (Fails
    /// today for the selected note: the password manager's commands work on it; and for @reply around the caret: its
    /// text is sent, where a terminal shows the hint.)
    @Test func aPasswordManagerGivesWhatATerminalGives() async {
        await withInterfaceLanguage("en") {
            for field in PMContext.Field.allCases {
                for keys in PMContext.scenarios {
                    let terminal = PMContext.seen(keys, app: PMContext.terminalApp, terminal: true, field: field)
                    #expect(PMContext.leaks(terminal.requests).isEmpty, "the terminal itself sent the field's text: \(terminal)")
                    #expect(terminal.requests.isEmpty != keys.requests, "\(field), \(keys.name) in the terminal: \(terminal)")
                    for app in PMContext.passwordManagers {
                        let manager = PMContext.seen(keys, app: app, field: field)
                        #expect(manager == terminal, """
                            \(app), \(field), \(keys.name): not what a terminal gives
                              password manager: \(manager)
                              terminal:         \(terminal)
                            """)
                    }
                }
            }
        }
    }

    // MARK: 2. No text of the field is read or sent

    /// @reply in a password manager, the caret between two texts: with something typed, only that is sent, never the
    /// text before or after the caret; with nothing typed, nothing is sent and what is shown is what a terminal shows on
    /// the same field (the same notice, the same panel, the same draft: ASSUMPTION A). (Fails today: the text around the
    /// caret is sent both times.)
    @Test func replySendsNoTextAroundTheCaret() async {
        await withInterfaceLanguage("en") {
            let terminal = PMContext.seen(PMContext.emptyReply, app: PMContext.terminalApp, terminal: true, field: .caretInside)
            #expect(terminal.requests.isEmpty, "the terminal itself sent something: \(terminal)")
            for app in PMContext.passwordManagers {
                let model = PMContextModel()
                let host = PMContext.host(app: app, field: .caretInside, model: model)
                PMContext.write(host, "reply", typed: "ok")
                let sent = PMContext.requests(host, model, expected: true)
                #expect(!sent.isEmpty, "\(app): @reply ok sent nothing")
                #expect(sent.contains { $0.contains("ok") }, "\(app): what was typed isn't sent: \(sent)")
                #expect(PMContext.leaks(sent).isEmpty, "\(app): the field's text was sent: \(PMContext.leaks(sent))")

                let empty = PMContext.seen(PMContext.emptyReply, app: app, field: .caretInside)
                #expect(empty.requests.isEmpty, "\(app): @reply with nothing typed sent: \(empty.requests)")
                #expect(empty == terminal, """
                    \(app): @reply with nothing typed isn't what a terminal shows
                      password manager: \(empty)
                      terminal:         \(terminal)
                    """)
            }
        }
    }

    /// The keys that may run @reply in a password manager (⏎, Space) don't ask the field for its text (ASSUMPTION B: the
    /// Mac reads it only when asked, and never reads a terminal's); and nothing asks for the field's text
    /// after a pause (autocomplete's read: off there already). (Fails today: ⏎ asks for the text.)
    @Test func replyDoesNotAskForTheFieldsText() async {
        await withInterfaceLanguage("en") {
            for app in PMContext.passwordManagers {
                let host = PMContext.host(app: app, field: .caretInside, model: PMContextModel())
                PMContext.write(host, "reply", typed: "ok", run: false)
                #expect(host.composer.draftCommand == .reply)
                for key in [FakeHost.enter, FakeHost.space] {
                    let asked = host.session.fieldWants(for: key, given: FieldContext(read: .secure))
                    #expect(!asked.contains(.text), "\(app): \(key.characters.debugDescription) asks for the field's text: \(asked)")
                }
                #expect(host.fieldReads == 0, "\(app): the field was read after a pause \(host.fieldReads) times")
            }
        }
    }

    /// A web page the shell would give for any app (ASSUMPTION C): @reply with nothing typed in a password manager wakes
    /// and reads no page, sends nothing and shows what a terminal given the same page shows (the same notice, the same
    /// panel, the same requests: ASSUMPTION A); in an ordinary app the page is still read. (Fails today: the page is read
    /// and sent from a password manager too.)
    @Test func noPageIsReadInAPasswordManager() async {
        await withInterfaceLanguage("en") {
            let terminalPage = PMContextPage()
            let terminal = PMContext.seen(PMContext.emptyReply, app: PMContext.terminalApp, terminal: true, field: .caretInside,
                                          page: terminalPage)
            #expect(terminalPage.woken == 0 && terminalPage.read == 0 && PMContext.leaks(terminal.requests).isEmpty,
                    "the terminal itself took the page (woken \(terminalPage.woken), read \(terminalPage.read)): \(terminal)")
            for app in PMContext.passwordManagers {
                let page = PMContextPage()
                let manager = PMContext.seen(PMContext.emptyReply, app: app, field: .caretInside, page: page)
                #expect(page.woken == 0 && page.read == 0, "\(app): the page was woken \(page.woken), read \(page.read) times")
                #expect(PMContext.leaks(manager.requests).isEmpty, "\(app): sent \(manager.requests)")
                #expect(manager == terminal, """
                    \(app): @reply with nothing typed isn't what a terminal shows
                      password manager: \(manager)
                      terminal:         \(terminal)
                    """)
            }

            // Control: an ordinary app still takes its page.
            let page = PMContextPage()
            let model = PMContextModel()
            let host = PMContext.host(app: PMContext.editor, field: .caretInside, model: model, page: page)
            PMContext.write(host, "reply")
            host.settle(timeout: 5) { !model.requests.isEmpty }
            #expect(page.read > 0, "the editor's page wasn't read")
            #expect(model.texts.contains { $0.contains(PMContextPage.secret) }, "the editor's page wasn't sent: \(model.texts)")
        }
    }

    // MARK: 3. What is typed still works

    /// A note selected in a password manager: `@translate hello` ⏎ translates "hello", `@question …` ⏎ asks it, and
    /// neither sends the note; no refusal. (Fails today: the selected note is sent with them.)
    @Test func typedTextIsSentAndNotTheSelection() async {
        await withInterfaceLanguage("en") {
            for app in PMContext.passwordManagers {
                for (command, typed) in [("translate", "hello"), ("question", "what is the capital of France")] {
                    let model = PMContextModel()
                    let host = PMContext.host(app: app, field: .selected, model: model)
                    PMContext.write(host, command, typed: typed)
                    let sent = PMContext.requests(host, model, expected: true)
                    #expect(sent.contains { $0.contains(typed) }, "\(app) @\(command): \"\(typed)\" isn't sent: \(sent)")
                    #expect(PMContext.leaks(sent).isEmpty, "\(app) @\(command): the selected note was sent: \(PMContext.leaks(sent))")
                    #expect(host.noticeAlone != InputSession.aiRefusal, "\(app) @\(command): refused as an app with no AI")
                }
            }
        }
    }

    /// Commands stay available in a password manager (nothing selected): one @ lists the AI's rows, `@translate hello`
    /// and `@question` are sent as typed, with no "No AI" or secure-input refusal, and the draft doesn't go into the
    /// field as typed. (Passes today: a guard against treating every password manager field as a password field.)
    @Test func commandsStayAvailableInAPasswordManager() async {
        await withInterfaceLanguage("en") {
            for app in PMContext.passwordManagers {
                let rows = PMContext.host(app: app, field: .caretInside, model: PMContextModel())
                rows.type("@hello")
                #expect(rows.composer.oneAtRows.contains { $0.command?.usesAI == true },
                        "\(app): no AI row: \(rows.composer.oneAtRows.map(\.id))")

                for (command, typed) in [("translate", "hello"), ("question", "what time is it in Paris")] {
                    let model = PMContextModel()
                    let host = PMContext.host(app: app, field: .caretInside, model: model)
                    PMContext.write(host, command, typed: typed)
                    let sent = PMContext.requests(host, model, expected: true)
                    #expect(sent.contains { $0.contains(typed) }, "\(app) @\(command): not sent: \(sent)")
                    #expect(host.noticeAlone != InputSession.aiRefusal, "\(app) @\(command): refused as an app with no AI")
                    #expect(host.noticeAlone?.hasPrefix("Secure input is on") != true,
                            "\(app) @\(command): refused as a password field: \(String(describing: host.noticeAlone))")
                    #expect(host.document == PMContext.before + PMContext.after,
                            "\(app) @\(command): went into the field as typed: \(host.document)")
                }
            }
        }
    }

    // MARK: 4. Nothing else changes

    /// Outside password managers the selection is still read and worked on, and @reply still sends the text around the
    /// caret (passes today: the control).
    @Test func outsidePasswordManagersTheSelectionIsStillUsed() async {
        await withInterfaceLanguage("en") {
            let asked = PMContext.host(app: PMContext.editor, field: .selected, model: PMContextModel())
            #expect(PMContext.selectionWanted(asked), "\"@\" asks for the selection")
            let host = PMContext.host(app: PMContext.editor, field: .selected, model: PMContextModel())
            host.press(FakeHost.at)
            #expect(host.composer.selection?.text == PMContext.note, "\(String(describing: host.composer.selection))")

            let model = PMContextModel()
            let translate = PMContext.host(app: PMContext.editor, field: .selected, model: model)
            PMContext.write(translate, "translate")
            let sent = PMContext.requests(translate, model, expected: true)
            #expect(sent.contains { $0.contains(PMContext.note) }, "the selection isn't translated: \(sent)")

            let replyModel = PMContextModel()
            let reply = PMContext.host(app: PMContext.editor, field: .caretInside, model: replyModel)
            PMContext.write(reply, "reply", typed: "ok", run: false)
            #expect(reply.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure)).contains(.text))
            reply.press(FakeHost.enter)
            let replied = PMContext.requests(reply, replyModel, expected: true)
            #expect(replied.contains { $0.contains("4921") && $0.contains("33-12-08") }, "the text around the caret isn't sent: \(replied)")
        }
    }

    /// A real password field in a password manager (told one by the shell) and secure input there behave as before
    /// (passes today): an AI command typed in a known password field is refused, what was typed goes in as typed and ⏎
    /// goes on to the field; with secure input on, "@" goes straight in and nothing is composed.
    @Test func aRealPasswordFieldOrSecureInputIsUnchanged() async {
        await withInterfaceLanguage("en") {
            for app in PMContext.passwordManagers {
                let model = PMContextModel()
                let known = PMContext.host(app: app, field: .caretInside, model: model)
                known.document = ""
                known.selection = nil
                known.send(.passwordField(true, focus: known.session.fieldSession))
                #expect(known.session.nothingLeavesDevice(), "\(app): not a known password field")
                PMContext.write(known, "question", typed: "what", run: false)
                #expect(!known.press(FakeHost.enter), "\(app): ⏎ doesn't go on to the password field")
                #expect(known.document == "@question what" && !known.composer.isComposing, "\(app): \(known.document)")
                #expect(known.noticeAlone?.hasPrefix("Secure input is on") == true, "\(app): \(String(describing: known.noticeAlone))")
                #expect(PMContext.requests(known, model, expected: false).isEmpty, "\(app): a request was sent")

                let secure = PMContext.host(app: app, field: .selected, model: PMContextModel())
                secure.secure = true
                #expect(!secure.press(FakeHost.at), "\(app): \"@\" was taken during secure input")
                #expect(!secure.composer.isComposing && secure.composer.selection == nil, "\(app): composed during secure input")
                #expect(secure.document == "@", "\(app): \"@\" didn't go in over the selection: \(secure.document)")
            }
        }
    }

    /// Autocomplete and English-word learning stay off in password managers, as before (passes today).
    @Test func autocompleteAndLearningStayOff() {
        for app in PMContext.passwordManagers {
            let field = FieldInfo(app: app)
            #expect(Autocomplete.blocker(in: field, secureInput: false, config: .default, composing: false, translating: false)
                == .passwordManager, "\(app)")
            #expect(!EnglishWords.mayLearn(in: field, secureInput: false, config: { .default }), "\(app)")
        }
        #expect(Autocomplete.blocker(in: FieldInfo(app: PMContext.editor), secureInput: false, config: .default, composing: false,
                                     translating: false) == nil)
    }
}
