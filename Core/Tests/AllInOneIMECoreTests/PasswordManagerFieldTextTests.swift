import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Password managers get the terminal's treatment (0.7.5): in any field of one, whatever the field says of itself, a
/// command reads none of the field's text (`FieldInfo.textStaysHere`): "@" starts with no selection, as in a terminal,
/// `@reply` takes no text around the caret, `@agent` and `@reply` no page; what is typed after the command is sent as
/// usual. Elsewhere nothing changes.
extension InputSessionTests {
    static let passwordManager = "com.1password.1password"

    /// A session in a field of `app` (a terminal with `terminal`), in English, with `adjust`'s services.
    func inApp(_ app: String, terminal: Bool = false, _ settings: Settings = Settings(),
               _ adjust: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        let host = host(settings, adjust)
        (host.app, host.terminal) = (app, terminal)
        host.focus()
        host.composer.setInputMode(.english)
        return host
    }

    @Test func theFieldsTextStaysHereInATerminalOrAPasswordManager() {
        #expect(!FieldInfo(app: "com.example.editor").textStaysHere && !FieldInfo().textStaysHere)
        #expect(!FieldInfo(app: "com.example.editor", secure: true).textStaysHere, "a password field: secure input's rules, not these")
        #expect(FieldInfo(app: "com.apple.Terminal", terminal: true).textStaysHere)
        for app in [Self.passwordManager, "com.agilebits.onepassword7", "com.apple.Passwords", "com.apple.keychainaccess",
                    "com.bitwarden.desktop", "org.keepassxc.keepassxc", "win:1password.exe", "win:Bitwarden.exe"] {
            #expect(FieldInfo(app: app).textStaysHere, "\(app)")
        }
        #expect(!FieldInfo(app: "win:notepad.exe").textStaysHere && !FieldInfo(app: "com.apple.TextEdit").textStaysHere)
    }

    /// "@" with text selected: in a password manager nothing of the field is asked for or taken, as in a terminal; the
    /// command is written in the field as there. An editor's selection is used as before.
    @Test func atStartsWithNoSelectionInAPasswordManager() async {
        await inEnglish {
            func fields() -> [FakeHost] {
                let hosts = [inApp("com.example.editor"), inApp("com.apple.Terminal", terminal: true), inApp(Self.passwordManager)]
                for host in hosts {
                    host.document = "Recovery code: 4F2K-9QX1"
                    host.selection = 15..<24
                    // Told to be no password field: only then is a field read at all (`fieldMayNotBeRead`).
                    host.send(.passwordField(false, focus: host.session.fieldSession))
                }
                return hosts
            }
            func at(_ host: FakeHost) -> FieldContext.Parts {
                host.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure))
            }
            // Asked for: an editor's selection (and, after a character typed, the one before the caret first); none of a
            // password manager's, as none of a terminal's.
            let typed = fields()
            for host in typed { host.press(KeyEvent(keyCode: 0, characters: "a")) }
            #expect(at(typed[0]).contains(.beforeCaret), "\(at(typed[0]))")
            let fresh = fields()
            let (editor, terminal, vault) = (fresh[0], fresh[1], fresh[2])
            #expect(at(editor).contains(.selection), "\(at(editor))")
            for host in [typed[1], typed[2], terminal, vault] {
                #expect(at(host).isDisjoint(with: [.beforeCaret, .selection, .text]), "\(host.app ?? "-"): \(at(host))")
            }
            #expect(at(vault) == at(terminal) && at(typed[2]) == at(typed[1]), "the same as a terminal: \(at(vault)) \(at(terminal))")

            // The field tells all of itself with the key (a shell where reading is cheap): only the editor's is taken.
            for host in [editor, terminal, vault] { host.press(FakeHost.at) }
            #expect(editor.composer.selection?.text == "4F2K-9QX1" && editor.composer.draftInPanel)
            for host in [terminal, vault] {
                #expect(host.composer.selection == nil && !host.composer.draftInPanel && host.preedit == "@"
                        && host.composer.draft == "@", "\(host.app ?? "-"): \(host.composer.draft) \(host.preedit)")
            }
            #expect(vault.panel?.rows.map(\.text) == terminal.panel?.rows.map(\.text) && vault.panel?.footer == terminal.panel?.footer,
                    "the same list as a terminal's")
            // A command picked works on what is typed only.
            vault.type("i")
            vault.press(FakeHost.tab)
            #expect(vault.composer.draftCommand == .improve && vault.composer.selection == nil && vault.document == "Recovery code: 4F2K-9QX1",
                    "\(vault.composer.draft)")

            // Read as the Mac reads it (only what is wanted): the same.
            let mac = inApp(Self.passwordManager)
            mac.readsWhatIsWanted = true
            (mac.document, mac.selection) = ("Recovery code: 4F2K-9QX1", 15..<24)
            mac.press(FakeHost.at)
            #expect(mac.composer.selection == nil && mac.marked.isEmpty && mac.preedit == "@")
        }
    }

    /// A command typed in a password manager is sent as usual, with what is typed and nothing of the field: no "No AI".
    @Test func aCommandInAPasswordManagerSendsWhatIsTypedOnly() async {
        await inEnglish {
            let settings = Settings()
            settings.config.provider = .apple
            let model = StubAppleModel(answer: ["Bonjour"])
            let vault = inApp(Self.passwordManager, settings) {
                $0.converter = Converter(loadConfig: { settings.config }, appleModel: model)
            }
            vault.document = "Secret note: the safe opens with 4-8-15"
            vault.selection = 0..<11
            pick("tra", in: vault)
            #expect(vault.composer.draftCommand == .translate && vault.composer.selection == nil, "\(vault.composer.draft)")
            vault.type("hello")
            vault.press(FakeHost.enter)
            #expect(vault.settle { vault.composer.phase == .choosing }, "\(vault.composer.phase)")
            let prompts = model.requests.map(\.prompt)
            #expect(prompts.contains { $0.contains("hello") }, "\(prompts)")
            #expect(!prompts.contains { $0.contains("Secret") || $0.contains("4-8-15") }, "\(prompts)")
        }
    }

    /// `@reply` in a password manager: its text around the caret is neither asked for nor taken, whatever the shell
    /// tells (by a key or a tap of Option); the reply is written from what is typed. In an editor it goes along as before.
    @Test func replyInAPasswordManagerTakesNoTextAroundTheCaret() async {
        await inEnglish {
            let settings = Settings()
            settings.config.provider = .apple
            let model = StubAppleModel(answer: ["1. Sure\n2. Fine\n3. OK"])
            func reply(_ app: String) -> FakeHost {
                let host = inApp(app, settings) { $0.converter = Converter(loadConfig: { settings.config }, appleModel: model) }
                host.document = "Bank PIN 4815, door code 1623"
                pick("rep", in: host)
                host.type("ok")
                #expect(host.composer.draftCommand == .reply, "\(host.composer.draft)")
                return host
            }
            let editor = reply("com.example.editor"), vault = reply(Self.passwordManager)
            func wants(_ host: FakeHost) -> FieldContext.Parts {
                host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure))
            }
            #expect(wants(editor).contains(.text) && !wants(vault).contains(.text), "\(wants(editor)) \(wants(vault))")
            vault.composer.actionKey = .optionTap
            let option = ModifierChange(key: .modifier(.option, .left), modifiers: [.option], timestamp: 0)
            #expect(vault.session.fieldWants(forModifiers: option, given: FieldContext(read: .secure)) == [.secure])
            vault.composer.actionKey = .enter

            vault.press(FakeHost.enter)  // the fake field tells its text with the key all the same
            #expect(vault.composer.replyContext?.field == nil && vault.composer.replyContext?.intent == "ok",
                    "\(String(describing: vault.composer.replyContext))")
            #expect(vault.settle { !model.requests.isEmpty })
            #expect(!model.requests.contains { $0.prompt.contains("4815") || $0.prompt.contains("1623") })
            editor.press(FakeHost.enter)
            #expect(editor.composer.replyContext?.field?.before.contains("4815") == true, "as before elsewhere")
        }
    }

    /// `@agent` in a password manager takes no page along, and none is asked for while it is written.
    @Test func agentTakesNoPageInAPasswordManager() async {
        await inEnglish {
            let asked = Locked(initialState: 0)
            let started = Locked<[String]>(initialState: [])
            let vault = inApp(Self.passwordManager) {
                $0.page = { _ in
                    asked.withLock { $0 += 1 }
                    return PageSource(wake: {}, release: {}) {
                        { PageContext(url: "https://vault.example.com", title: "Vault", visible: "hunter2") }
                    }
                }
                $0.runInTerminal = { _, prompt in started.withLock { $0.append(prompt) } }
            }
            pick("age", in: vault)
            vault.type("fix it")
            vault.press(FakeHost.enter)
            #expect(vault.settle { !started.withLock { $0 }.isEmpty } && !vault.session.waitsForPage)
            let prompt = started.withLock { $0 }.first ?? ""
            #expect(prompt.contains("fix it") && !prompt.contains("hunter2"), "\(prompt)")
            #expect(asked.withLock { $0 } == 0, "the page wasn't asked for")
        }
    }
}
