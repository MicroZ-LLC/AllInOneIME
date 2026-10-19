import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A text field's session (`InputSession`) driven as a shell drives it (`FakeHost`): keys with what the field says
/// around them, the outputs applied to a field of the test's own, the session's work answered on the test's thread. What
/// the Mac's self-test checks of its input controller, here on every platform, without librime, a model or the system:
/// `FakeEngine` for pinyin, stand-ins for programs, notes, reminders, searches and the web page.
///
/// The session sets the process's interface language from its settings (English here): each test runs while it is held
/// (`withInterfaceLanguage`).
@Suite(.serialized)
struct InputSessionTests {
    /// The settings the session reads: pinyin first, Shift to English; English then Chinese to translate into; English
    /// interface; `@agent` in a terminal, not in the background.
    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            config.setOrder([OutputLanguage.english, .chinese])
            config.claudeInBackground = false
        }
    }

    /// A session in a field that has the focus, with `adjust`'s services (programs installed, by default).
    func host(_ settings: Settings = Settings(), _ adjust: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        adjust(&services)
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    /// `@js` stand-in: what it prints for any code (`SessionServices.runProgram`).
    static func printing(_ text: String, after delay: Duration = .zero) -> @Sendable (CustomCommand, String) -> AsyncThrowingStream<ConversionUpdate, Error> {
        { _, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    continuation.yield(ConversionUpdate(result: ConversionResult(versions: [CandidateLine(text)]), rawText: text,
                                                        isFinal: true, elapsed: 0.1, firstTokenLatency: nil, fromCache: false))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    /// Picks `command` from the list ("@" and its first letters, Tab).
    func pick(_ letters: String, in host: FakeHost) {
        host.press(FakeHost.at)
        host.type(letters)
        host.press(FakeHost.tab)
    }

    func inEnglish(_ body: () throws -> Void) rethrows { try withInterfaceLanguage("en", body) }

    // MARK: - Keys

    @Test func idleKeysGoToTheApp() {
        inEnglish {
            let host = host()
            #expect(!host.press(KeyEvent(keyCode: 0x12, characters: "1")), "a digit")
            #expect(!host.press(KeyEvent(keyCode: 0x08, characters: "c", modifiers: .command)), "⌘C")
            #expect(!host.press(FakeHost.enter), "⏎")
            #expect(host.press(KeyEvent(keyCode: 0x2B, characters: ",")) && host.document == "，", "',' types a Chinese comma (\(host.document))")
        }
    }

    @Test func pinyinIsMarkedThenPicked() {
        inEnglish {
            let host = host()
            host.type("nihao")
            #expect(host.marked == "nihao" && host.composer.isComposing)
            #expect(host.panel?.rows.map(\.text).prefix(2) == ["你好", "拟好"], "the candidates in the panel")
            host.press(FakeHost.space)
            #expect(host.document == "你好" && host.marked.isEmpty && host.panel == nil)
            host.type("nihao")
            host.press(FakeHost.enter)
            #expect(host.document == "你好nihao", "⏎ inserts the letters (\(host.document))")
        }
    }

    @Test func atOpensTheCommandList() {
        inEnglish {
            let host = host()
            host.press(FakeHost.at)
            #expect(host.marked == "@" && host.panel?.rows.first?.text.hasPrefix("@") == true)
            host.type("i")
            host.press(FakeHost.enter)
            #expect(host.marked == "improve › " && host.composer.draft == "@improve ", "@i ⏎ picks @improve (\(host.marked))")
        }
    }

    @Test func atRightAfterAWordIsText() {
        inEnglish {
            let host = host()
            host.composer.setInputMode(.english)
            for character in "bob@" {
                let key = character == "@" ? FakeHost.at : KeyEvent(keyCode: 0, characters: String(character))
                if !host.press(key) { host.document += String(character) }  // the app types it
            }
            #expect(host.document == "bob@" && !host.composer.isComposing, "no command list after a word (\(host.marked))")
            host.document += " "
            host.press(FakeHost.at)
            #expect(host.composer.draft == "@", "after a space it opens")
        }
    }

    // MARK: - Secure input and the field

    @Test func secureInputLetsKeysThrough() {
        inEnglish {
            let host = host()
            host.secure = true
            #expect(!host.press(KeyEvent(keyCode: 0, characters: "a")) && host.marked.isEmpty && !host.composer.isComposing)
            #expect(host.session.notice == "Secure input: the input method is paused, keys go straight in")
            host.secure = false
            host.type("ni")
            host.secure = true
            #expect(!host.press(KeyEvent(keyCode: 2, characters: "d")), "a key passes through once it turns on")
            #expect(host.document == "ni" && host.marked.isEmpty, "the pending letters go in as typed (\(host.document))")
        }
    }

    @Test func theAppTakingTheMarkedTextStartsOver() {
        inEnglish {
            let host = host()
            host.type("ni")
            host.appTakesMarkedText = true
            #expect(host.press(KeyEvent(keyCode: 0x04, characters: "h")), "the key is dropped")
            #expect(!host.composer.isComposing, "nothing pending: no draft shown again, doubled")
            host.type("wo")
            #expect(host.marked == "wo")
        }
    }

    @Test func fieldWantsWhatAKeyMayNeed() {
        inEnglish {
            let host = host()
            let a = KeyEvent(keyCode: 0, characters: "a")
            #expect(host.session.fieldWants(for: a, given: FieldContext()) == [.secure], "first whether anything is composed")
            #expect(host.session.fieldWants(for: a, given: FieldContext(read: .secure)) == [.secure], "then nothing else at idle")
            #expect(host.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure)) == [.secure, .selection, .selectedRange],
                    "\"@\" may start a command on the selection")
            host.type("ni")
            #expect(host.session.fieldWants(for: a, given: FieldContext(read: .secure)).contains(.markedText), "composing: the marked text")
        }
    }

    @Test func nothingIsReadInAPasswordField() {
        inEnglish {
            let host = host()
            // "@" would have the selection read; secure input on for the key's app: nothing but that.
            #expect(host.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure, secure: true)) == [.secure])
            // `@reply` written, and a key that runs it: its text would be read…
            pick("rep", in: host)
            #expect(host.composer.draftCommand == .reply, "\(host.composer.draft)")
            #expect(host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure)).contains(.text))
            // …but not in a field the shell says is a password field (Windows').
            host.send(.focus(FieldInfo(app: host.app, secure: true)))
            #expect(host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure)) == [.secure])
            #expect(host.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure)) == [.secure])
        }
    }

    // MARK: - Level two

    @Test func aRequestsResultGoesIn() {
        inEnglish {
            let host = host { $0.runProgram = Self.printing("42") }
            pick("js", in: host)
            host.composer.setInputMode(.english)
            host.type("6*7")
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.phase == .choosing })
            #expect(host.composer.choices.contains { $0.text == "42" }, "\(host.composer.choices.map(\.text))")
            host.press(FakeHost.enter)
            #expect(host.document.hasSuffix("42") && host.marked.isEmpty, "\(host.document)")
        }
    }

    @Test func resultsAreTypedOutWhereTheSettingsSay() {
        inEnglish {
            let settings = Settings()
            settings.config.typeOut = true
            let host = host(settings) { $0.runProgram = Self.printing("42") }
            pick("js", in: host)
            host.composer.setInputMode(.english)
            host.type("6*7")
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.phase == .choosing })
            host.press(FakeHost.enter)
            #expect(host.typedOut == ["42"], "\(host.typedOut)")
        }
    }

    @Test func secureInputRefusesRequests() {
        inEnglish {
            let ran = Locked(initialState: 0)
            let host = host {
                $0.secureInputActive = { true }
                $0.runProgram = { command, input in
                    ran.withLock { $0 += 1 }
                    return Self.printing("42")(command, input)
                }
            }
            pick("js", in: host)
            host.composer.setInputMode(.english)
            host.type("6*7")
            host.press(FakeHost.enter)
            #expect(host.composer.phase == .failed("Secure input is on (a password field or the lock screen): the command was not run"),
                    "\(host.composer.phase)")
            #expect(ran.withLock { $0 } == 0, "the program never ran")
        }
    }

    @Test func anAppWithoutAIRefusesIt() {
        inEnglish {
            let settings = Settings()
            settings.config.appProfiles = ["com.example.chat": AppProfile(noAI: true)]
            let host = FakeHost(services: SessionServices(loadSettings: { settings.config }))
            host.session.services.levelOne = { .engine(FakeEngine()) }
            host.app = "com.example.chat"
            host.focus()
            #expect(host.composer.aiRefusal() == InputSession.aiRefusal)
            host.app = "com.example.mail"
            host.focus()
            #expect(host.composer.aiRefusal() == nil, "another app may use AI")
        }
    }

    @Test func aNewerRequestDropsTheOldOnesAnswer() {
        inEnglish {
            let host = host { $0.runProgram = Self.printing("42", after: .milliseconds(100)) }
            pick("js", in: host)
            host.composer.setInputMode(.english)
            host.type("6*7")
            host.press(FakeHost.enter)
            host.press(FakeHost.escape)  // back to the draft: the request stops
            #expect(!host.settle(timeout: 0.3) { host.composer.phase == .choosing }, "its answer counts no more")
            #expect(host.composer.draft == "@js 6*7", "\(host.composer.draft)")
        }
    }

    @Test func anAnswerOfWorkStoppedSinceIsDroppedEvenForTheSameText() {
        inEnglish {
            // The first search answers at once; the later ones once the test lets them.
            let (later, go) = (Locked(initialState: false), Locked(initialState: false))
            let host = host {
                $0.loadContacts = {
                    guard later.withLock({ $0 }) else { return [Contact(name: "Ann Old", handles: ["+1 555 0100"])] }
                    while !go.withLock({ $0 }), !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                    return [Contact(name: "Ann New", handles: ["+1 555 0101"])]
                }
            }
            host.composer.setInputMode(.english)
            pick("ime", in: host)
            host.type("a")
            // "a"'s answer is in, not handed over yet; meanwhile "an", then "a" again: another search for the same text,
            // which the composer can't tell from the first.
            #expect(host.waitForAnswer { if case .task(_, .recipients(_, _, "a")) = $0 { true } else { false } })
            later.withLock { $0 = true }
            host.type("n")
            host.press(KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}"))
            #expect(host.composer.recipientQuery == "a", "\(host.composer.recipientQuery ?? "-")")
            host.settle(timeout: 0.3) { false }
            #expect(host.composer.currentRecipients.isEmpty, "the stopped search's answer counts no more (\(host.composer.currentRecipients))")
            go.withLock { $0 = true }
            #expect(host.settle { host.composer.currentRecipients.first?.name == "Ann New" }, "the search now does")
        }
    }

    @Test func nothingCountsOnceTheSessionIsClosed() {
        inEnglish {
            // A request on its way.
            let host = host { $0.runProgram = Self.printing("42", after: .milliseconds(100)) }
            pick("js", in: host)
            host.composer.setInputMode(.english)
            host.type("6*7")
            host.press(FakeHost.enter)
            host.send(.close)
            #expect(!host.settle(timeout: 0.4) { host.composer.phase == .choosing }, "its answer counts no more")
            // Recipients being looked up.
            let typing = self.host { $0.loadContacts = { [Contact(name: "Ann Lee", handles: ["+1 555 0100"])] } }
            typing.composer.setInputMode(.english)
            pick("ime", in: typing)
            typing.type("ann")
            typing.send(.close)
            #expect(!typing.settle(timeout: 0.4) { !typing.composer.currentRecipients.isEmpty }, "nor theirs")
        }
    }

    // MARK: - The selection

    @Test func aCommandOnTheSelectionReplacesIt() {
        inEnglish {
            let host = host { $0.runProgram = Self.printing("42") }
            host.document = "Total: 6*7 apples"
            host.selection = 7..<10
            pick("js", in: host)
            #expect(host.composer.draftInPanel && host.marked.isEmpty, "written in the panel: the field keeps its selection")
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.phase == .choosing })
            host.press(FakeHost.enter)
            #expect(host.document == "Total: 42 apples", "\(host.document)")
        }
    }

    @Test func aSelectionMovedGivesTheCommandUp() {
        inEnglish {
            let host = host()
            host.document = "hello world"
            host.selection = 6..<11
            pick("i", in: host)
            #expect(host.composer.draftInPanel)
            host.selection = 0..<5  // a click
            host.press(KeyEvent(keyCode: 0, characters: "a"))
            #expect(!host.composer.draftInPanel && host.marked == "a", "given up; the key types as usual (\(host.marked))")
        }
    }

    // MARK: - Notices, the clipboard

    @Test func aNoticeExpiresOnItsTimer() {
        inEnglish {
            let host = host()
            host.secure = true
            host.press(KeyEvent(keyCode: 0, characters: "a"))
            #expect(host.noticeAlone != nil && host.timers.count == 1)
            host.fireTimers()
            #expect(host.session.notice == nil && host.panel == nil && host.noticeAlone == nil)
        }
    }

    @Test func theClipboardIsReadOnceTheKeyIsAnswered() {
        inEnglish {
            let host = host()
            pick("i", in: host)
            host.clipboard = .text("hello there")
            #expect(host.press(FakeHost.controlV))
            #expect(host.outputs.contains { if case .readClipboard = $0 { true } else { false } }, "read once the key is answered")
            #expect(host.marked == "improve › hello there", "\(host.marked)")
        }
    }

    @Test func theClipboardIsntTakenDuringSecureInput() {
        inEnglish {
            /// ⌃V in an `@improve` draft, the clipboard answered after `meanwhile`: the draft then.
            func paste(_ adjust: (inout SessionServices) -> Void = { _ in }, meanwhile: (FakeHost) -> Void) -> String {
                let host = host(Settings(), adjust)
                pick("i", in: host)
                let asked = host.session.handle(.key(FakeHost.controlV, host.context)).outputs
                guard let id = asked.lazy.compactMap({ if case let .readClipboard(id) = $0 { id } else { nil } }).first else {
                    Issue.record("the clipboard isn't asked for: \(asked)")
                    return ""
                }
                meanwhile(host)
                host.send(.clipboard(.text("hunter2"), id: id))
                return host.composer.draft
            }
            #expect(paste(meanwhile: { _ in }).hasSuffix("hunter2"), "taken in otherwise")
            let secure = Locked(initialState: false)
            #expect(!paste({ $0.secureInputActive = { secure.withLock { $0 } } }, meanwhile: { _ in secure.withLock { $0 = true } })
                .contains("hunter2"), "secure input came on (a password prompt)")
            #expect(!paste(meanwhile: { $0.send(.focus(FieldInfo(app: $0.app, secure: true))) }).contains("hunter2"),
                    "a password field")
        }
    }

    // MARK: - Notes and reminders

    /// Saves what it's given, or fails with `failure` (`SessionServices.noteDestination`).
    struct StandInNotes: NoteDestination {
        let saved: Locked<[String]>
        var failure: (any Error)?
        var name: String { "Stand-in" }
        var leavesDevice: Bool { false }
        func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
            if let failure { throw failure }
            saved.withLock { $0.append(draft.text) }
            return SavedNoteRef(id: nil, title: draft.title)
        }
        func check() async throws -> String { "ok" }
    }

    @Test func aNoteIsSavedAndSaysWhere() {
        inEnglish {
            let saved = Locked<[String]>(initialState: [])
            let host = host { $0.noteDestination = { _ in StandInNotes(saved: saved) } }
            host.composer.setInputMode(.english)  // letters, not pinyin
            pick("no", in: host)
            host.type("milk")
            host.press(FakeHost.enter)
            #expect(host.session.notice == "Saving to Stand-in…")
            #expect(host.settle { host.session.notice == "Saved to Stand-in" }, "\(host.session.notice ?? "-")")
            #expect(saved.withLock { $0 } == ["milk"] && host.document.isEmpty)
        }
    }

    @Test func aNoteNotSavedComesBack() {
        inEnglish {
            let saved = Locked<[String]>(initialState: [])
            let host = host {
                $0.noteDestination = { _ in StandInNotes(saved: saved, failure: NoteError.notionRefused(code: "unauthorized")) }
                $0.needsTheUser = { _ in true }
            }
            host.composer.setInputMode(.english)  // letters, not pinyin
            pick("no", in: host)
            host.type("milk")
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.draft == "@note milk" }, "back in the draft (\(host.composer.draft))")
            #expect(host.copied == ["milk"] && host.session.notice?.hasPrefix("The text is on the clipboard too. ") == true,
                    "\(host.copied) \(host.session.notice ?? "-")")
        }
    }

    /// Left, and maybe focused again: the field the save came from is gone either way.
    @Test(arguments: [false, true]) func aSaveOutcomeAfterTheFieldWasLeftGoesElsewhere(focusedAgain: Bool) {
        inEnglish {
            let saved = Locked<[String]>(initialState: [])
            let host = host {
                $0.noteDestination = { _ in StandInNotes(saved: saved, failure: NoteError.notionTrouble(status: 500)) }
            }
            host.composer.setInputMode(.english)  // letters, not pinyin
            pick("no", in: host)
            host.type("milk")
            host.press(FakeHost.enter)
            host.send(.blur)
            if focusedAgain { host.focus() }
            #expect(host.settle { !host.noticesElsewhere.isEmpty })
            #expect(host.copied == ["milk"] && host.noticesElsewhere.first?.hasPrefix("Not saved; the text is on the clipboard. ") == true,
                    "\(host.noticesElsewhere)")
        }
    }

    @Test func aReminderIsReadThenAdded() {
        inEnglish {
            let added = Locked<[ReminderDraft]>(initialState: [])
            let draft = ReminderDraft(title: "Call Ann")
            let host = host {
                $0.parseReminder = { _ in draft }
                $0.addReminder = { reminder in added.withLock { $0.append(reminder) } }
            }
            host.composer.setInputMode(.english)  // letters, not pinyin
            pick("rem", in: host)
            host.type("call Ann")
            host.press(FakeHost.enter)
            #expect(host.composer.phase == .choosing && host.panel?.rows.first?.text == "Call Ann", "one row to confirm")
            host.press(FakeHost.enter)
            #expect(host.session.notice == "Adding to Reminders…")
            #expect(host.settle { host.session.notice == "Added to Reminders" }, "\(host.session.notice ?? "-")")
            #expect(added.withLock { $0 } == [draft])
        }
    }

    // MARK: - @open, @agent

    @Test func openFindsAndOpens() {
        inEnglish {
            let recorded = Locked<[String]>(initialState: [])
            let host = host {
                $0.searchFiles = { query, _ in [SearchResult(name: "notes.txt", path: "/tmp/\(query).txt")] }
                $0.recordOpen = { path in recorded.withLock { $0.append(path) } }
            }
            host.composer.setInputMode(.english)  // letters, not pinyin
            pick("ope", in: host)
            host.type("n")  // one letter: searched on ⏎ only
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.phase == .choosing })
            host.press(FakeHost.enter)
            #expect(host.opened == ["/tmp/n.txt"] && recorded.withLock { $0 } == ["/tmp/n.txt"], "\(host.opened)")
        }
    }

    @Test func agentTakesTheWebPageAlong() {
        inEnglish {
            let started = Locked<[String]>(initialState: [])
            let host = host {
                $0.page = { _ in
                    PageSource(wake: {}, release: {}) {
                        { PageContext(url: "https://example.com/build/7", title: "Build 7", visible: "Step 3 failed: missing key") }
                    }
                }
                $0.runInTerminal = { _, prompt in started.withLock { $0.append(prompt) } }
            }
            host.composer.setInputMode(.english)  // letters, not pinyin
            pick("age", in: host)
            host.type("fix it")
            host.press(FakeHost.enter)
            #expect(host.settle { !started.withLock { $0 }.isEmpty } && !host.session.waitsForPage)
            let prompt = started.withLock { $0 }.first ?? ""
            #expect(prompt.contains("fix it") && prompt.contains("Step 3 failed"), "the page went along (\(prompt.count) chars)")
            #expect(host.session.notice?.contains("Build 7") == true, "the notice names the page (\(host.session.notice ?? "-"))")
        }
    }

    @Test func commandsWhoseProgramIsMissingAreNotOffered() {
        inEnglish {
            let host = host { $0.programInstalled = { $0 != InlineCode.python } }
            #expect(host.settle { !host.composer.commands.contains(.py) })
            #expect(host.composer.commands.contains(.js))
        }
    }

    // MARK: - Terminals, voice

    @Test func inATerminalAnArrowEndsTheListTheAtAfterIt() {
        inEnglish {
            let host = host()
            host.terminal = true
            host.focus()
            host.composer.setInputMode(.english)
            host.press(FakeHost.at)
            #expect(host.composer.draft == "@")
            host.press(KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}"))
            #expect(host.document == "@" && host.outputs.last == .commitAfterKey("@") && !host.composer.isComposing,
                    "the arrow only ends the list; the \"@\" goes in after the key (\(host.document))")
        }
    }

    @Test func holdingTheVoiceKeyStartsDictation() {
        inEnglish {
            let host = host {
                $0.voiceSupported = { true }
                $0.isVoiceKeyHeld = { true }
            }
            host.modifiers(ModifierChange(key: .modifier(.option, .right), modifiers: [.option, .rightOption], timestamp: 100))
            #expect(host.timers.contains { if case .voiceHold = $0 { true } else { false } }, "\(host.timers)")
            host.fireTimers()
            guard case let .startVoice(id, language)? = host.platformActions.last else {
                Issue.record("no dictation: \(host.platformActions)")
                return
            }
            #expect(language == .chinese)
            host.send(.voice(.text("你好", id: id)))
            host.modifiers(ModifierChange(key: .modifier(.option, .right), modifiers: [], timestamp: 101))  // let go
            #expect(host.platformActions.last == .stopVoice(id: id), "\(host.platformActions)")
            host.send(.voice(.finished("你好。", id: id)))
            #expect(host.composer.voice == .off && host.document == "你好。", "the transcript goes in (\(host.document) | \(host.marked))")
        }
    }

    // MARK: - Script extensions

    @Test func aScriptExtensionRunsWhereTheShellRunsIt() {
        inEnglish {
            let folder = URL(fileURLWithPath: "/tmp/stand-in-scripts", isDirectory: true)
            let script = ScriptCommand(file: folder.appendingPathComponent("hello.sh"), name: "hello", title: "Hello", output: .show)
            let index = ExtensionIndex(commands: [script])
            let ran = Locked<[String]>(initialState: [])
            let host = host {
                $0.loadExtensions = { _, _ in index }
                $0.startScript = { command, arguments, _, event in
                    ran.withLock { $0.append(command.name + " " + arguments.joined(separator: " ")) }
                    event(.update(CommandRunner.ScriptUpdate(output: .text("hi there"), text: "hi there", isFinal: true)))
                    return 1
                }
            }
            host.send(.focus(FieldInfo(app: host.app)))  // the extensions read again
            host.composer.setInputMode(.english)  // letters, not pinyin
            pick("hel", in: host)
            host.type("you")
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.phase == .choosing }, "\(host.composer.phase)")
            #expect(ran.withLock { $0 } == ["hello you"] && host.composer.choices.first?.text == "hi there",
                    "\(ran.withLock { $0 }) \(host.composer.choices.map(\.text))")
        }
    }

    // MARK: - More of the self-test's

    @Test func aSnippetsCaretGoesWhereItsCursorIs() {
        inEnglish {
            let settings = Settings()
            settings.config.customCommands = [CustomCommand(name: "sig", type: .snippet, text: "Best,{cursor}\nAnn")]
            let host = host(settings)
            host.composer.setInputMode(.english)
            host.press(FakeHost.at)
            host.type("sig")
            host.press(FakeHost.enter)
            #expect(host.document == "Best,\nAnn", "\(host.document)")
            #expect(host.outputs.contains(.moveCaret(back: 4, after: "Best,\nAnn")), "the caret back to {cursor}: \(host.outputs.suffix(4))")
        }
    }

    @Test func nothingToTranslateIntoOpensTheSettings() {
        inEnglish {
            let settings = Settings()
            settings.config.setOrder([OutputLanguage.english])
            let host = host(settings)
            host.composer.setInputMode(.english)
            pick("tr", in: host)
            host.type("hello there")
            host.press(FakeHost.enter)
            #expect(host.settingsOpened == [.outputLanguages], "\(host.settingsOpened)")
            #expect(host.composer.phase == .failed("No language to translate into yet: add one under Translate & Rewrite in the settings"),
                    "\(host.composer.phase)")
        }
    }

    @Test func aRenameIsToldOnceAtTheFocus() {
        inEnglish {
            let told = Locked(initialState: false)
            let host = host {
                $0.takeRenameNotice = { messages in
                    told.withLock { done in
                        defer { done = true }
                        return done ? nil : messages.renamed(old: "reply", new: "myreply")
                    }
                }
            }
            let first = host.session.notice
            host.session.notice = nil
            host.focus()
            #expect(first?.contains("@myreply") == true && host.session.notice == nil, "\(first ?? "-")")
        }
    }

    @Test func thePageIsAskedForWhileAgentIsWrittenAndGivenBack() {
        inEnglish {
            let calls = Locked<[String]>(initialState: [])
            let host = host {
                $0.page = { _ in
                    PageSource(wake: { calls.withLock { $0.append("wake") } }, release: { calls.withLock { $0.append("release") } }) {
                        { nil }
                    }
                }
            }
            host.composer.setInputMode(.english)
            pick("age", in: host)
            #expect(calls.withLock { $0 } == ["wake"], "asked for once `@agent` is picked")
            host.press(FakeHost.escape)
            host.press(FakeHost.escape)
            #expect(calls.withLock { $0 } == ["wake", "release"], "given back with the draft (\(calls.withLock { $0 }))")
        }
    }

    @Test func backgroundCommandsDontRunDuringSecureInput() {
        inEnglish {
            let folder = URL(fileURLWithPath: "/tmp/stand-in-scripts", isDirectory: true)
            let script = ScriptCommand(file: folder.appendingPathComponent("sync.sh"), name: "sync", title: "Sync", input: .none,
                                       arguments: [], background: true)
            let started = Locked<[String]>(initialState: [])
            let secure = Locked(initialState: false)
            let host = host {
                $0.loadExtensions = { _, _ in ExtensionIndex(commands: [script]) }
                $0.secureInputActive = { secure.withLock { $0 } }
                $0.startScriptInBackground = { command, _, _, _ in started.withLock { $0.append(command.name) } }
            }
            host.send(.focus(FieldInfo(app: host.app)))  // the extensions read again
            host.composer.setInputMode(.english)
            secure.withLock { $0 = true }
            pick("syn", in: host)
            host.press(FakeHost.enter)
            // Said, then the composer's own notice of a background command over it (as before the session was the core's).
            #expect(started.withLock { $0 }.isEmpty
                    && host.outputs.contains(.notice("Secure input is on (a password field or the lock screen): the command was not run")),
                    "\(host.session.notice ?? "-")")
            secure.withLock { $0 = false }
            pick("syn", in: host)
            host.press(FakeHost.enter)
            #expect(started.withLock { $0 } == ["sync"], "started on its own once secure input is off")
        }
    }

    @Test func aMessageGoesToTheRecipientPicked() {
        inEnglish {
            final class Sender: MessageSender, @unchecked Sendable {
                let sent = Locked<[(String, Recipient)]>(initialState: [])
                func send(_ text: String, to recipient: Recipient) async throws { sent.withLock { $0.append((text, recipient)) } }
            }
            let sender = Sender()
            let recent = Locked<[String]>(initialState: [])
            let host = host {
                $0.loadContacts = { [Contact(name: "Ann Lee", handles: ["+1 555 0100"])] }
                $0.messageSender = sender
                $0.saveRecentHandles = { handles in recent.withLock { $0 = handles } }
            }
            host.composer.setInputMode(.english)
            pick("ime", in: host)
            host.type("ann")
            #expect(host.settle { host.composer.recipientResults.first?.name == "Ann Lee" }, "Contacts searched as typed")
            host.press(FakeHost.enter)  // the recipient
            host.type("see you at 6")
            host.press(FakeHost.enter)  // the message, to confirm
            host.press(FakeHost.enter)  // sent
            #expect(host.settle { host.session.notice == "Sent to Ann Lee" }, "\(host.session.notice ?? "-")")
            #expect(sender.sent.withLock { $0.map(\.0) } == ["see you at 6"] && recent.withLock { $0 } == ["+1 555 0100"])
        }
    }

    // MARK: - The model (a stand-in)

    @Test func aRequestToTheModelThenAFollowUp() {
        inEnglish {
            let settings = Settings()
            settings.config.provider = .apple
            let stub = StubAppleModel(answer: ["Canberra is the capital."])
            let converter = Converter(loadConfig: { settings.config }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                                      loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: stub)
            let host = host(settings) { $0.converter = converter }
            host.composer.setInputMode(.english)
            pick("que", in: host)
            host.type("capital of australia")
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.phase == .choosing }, "\(host.composer.phase)")
            #expect(host.composer.choices.contains { $0.text == "Canberra is the capital." } && host.session.lastElapsed != nil,
                    "\(host.composer.choices.map(\.text))")
            host.type("shorter")
            host.press(KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift))
            #expect(host.settle { stub.requests.count == 2 && host.composer.phase == .choosing }, "asked again (\(stub.requests.count))")
            #expect(stub.requests.last.map { "\($0)".contains("shorter") } == true, "with the follow-up")
        }
    }

    @Test func improveWithTheModel() {
        inEnglish {
            let settings = Settings()
            settings.config.provider = .apple
            settings.config.setOrder([OutputLanguage.english])
            let stub = StubAppleModel(answer: ["EN: Hello there."])
            let converter = Converter(loadConfig: { settings.config }, loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                                      loadKey: { _, _ in nil }, loadJargon: { _ in [] }, appleModel: stub)
            let host = host(settings) { $0.converter = converter }
            host.composer.setInputMode(.english)
            pick("i", in: host)
            host.type("hello thre")
            host.press(FakeHost.enter)
            #expect(host.settle { host.composer.phase == .choosing }, "\(host.composer.phase)")
            #expect(host.composer.choices.contains { $0.text == "Hello there." }, "\(host.composer.choices.map(\.text))")
            host.press(FakeHost.enter)
            #expect(host.document == "Hello there.", "the version highlighted goes in (\(host.document))")
        }
    }
}
