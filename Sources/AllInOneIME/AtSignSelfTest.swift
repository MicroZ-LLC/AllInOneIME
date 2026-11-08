import AllInOneIMECore
import AppKit

/// A terminal's line, as Ghostty (1.3.1) fills it from the keys the input method sees: what it sends the shell is
/// worked out from what the input method did during each key, as Ghostty's `keyDown` does. Text inserted during a key
/// goes out in the key's place (for an arrow, the arrow's sequence: the text is lost); a key that inserts nothing goes
/// out unless text was marked before it or is marked now (it only ended or changed the composition); text inserted
/// after the key goes out as it is.
@MainActor
final class GhosttyLine {
    let controller: AllInOneIMEInputController
    let client: FakeTextClient
    /// What reached the shell: the text, and ← → for the arrows.
    var shell = ""

    init(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        (self.controller, self.client) = (controller, client)
    }

    func press(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
        let markedBefore = !client.marked.isEmpty
        let before = client.inserted.count
        _ = SelfTest.press(controller, client, characters, code: code, flags: flags)
        let during = client.inserted[before...].joined()
        let arrow = [VirtualKey.left: "←", VirtualKey.right: "→"][code]
        if !during.isEmpty {
            shell += arrow ?? during
        } else if !markedBefore, client.marked.isEmpty {
            shell += arrow ?? characters
        }
        let after = client.inserted.count
        _ = SelfTest.pump(timeout: 0.2) { self.client.inserted.count > after }
        shell += client.inserted[after...].joined()
    }

    /// Each character with its key on a US layout ("@" is ⇧2, "~" ⇧`).
    func type(_ text: String) {
        for ch in text {
            switch ch {
            case "@", "~": press(String(ch), code: SelfTest.magicKeyCodes[String(ch)] ?? 0, flags: .shift)
            case ".": press(".", code: 0x2F)
            default: press(String(ch), code: SelfTest.keyCodes[ch] ?? 0)
            }
        }
    }
}

extension SelfTest {
    /// The keys of the magic keys the self-test types (`withMagicKey`), on a US layout, with Shift: "@" is ⇧2, "~" ⇧`.
    static let magicKeyCodes: [String: UInt16] = ["@": 0x13, "~": 0x32]

    /// Runs `body` with `key` as the magic key (`Config.commandTrigger`), as after picking it in Settings, then puts the
    /// one before back. Only the self-test's own settings change (`settings`): nothing is saved.
    static func withMagicKey(_ key: String, _ controller: AllInOneIMEInputController, _ body: () -> Void) {
        let before = settings.commandTrigger
        settings.commandTrigger = key
        controller.applySettings()
        defer {
            settings.commandTrigger = before
            controller.applySettings()
        }
        body()
    }

    /// The magic key in use (`Composer.commandTrigger`), typed into `client` as a US layout types it.
    @discardableResult
    static func magicKey(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        let key = controller.composer.commandTrigger
        return press(controller, client, key, code: magicKeyCodes[key] ?? 0x13, flags: .shift)
    }

    /// One @ with the magic key in use (`@` by default, `~` in `withMagicKey`), in a text view, nothing asked of the AI:
    /// the key alone lists the commands by name, the first highlighted, and Esc gives it up; a name's start and ⏎ or Tab
    /// pick its command, the whole name and Space write it, as "@name " always did; a letter no command starts with is the
    /// text (pinyin composed after the key), and Esc puts it in as typed (a mention); a sum's row goes first and ⏎ puts its
    /// value in; the key then Space is the key itself. With another magic key "@" is text like any other character.
    static func testOneAtList(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        let t = controller.composer.commandTrigger
        section("One @ with \(t) as the magic key, in a text view", needs: .composing)
        let field = FakeTextClient()
        controller.activateServer(field)
        defer {
            controller.commitComposition(field)
            controller.composer.setInputMode(settings.defaultInput)
            controller.activateServer(client)
        }
        /// The app emptied the field: nothing before the caret, nothing composed.
        func fresh(english: Bool = false) {
            controller.commitComposition(field)
            (field.document, field.marked, field.inserted) = ("", "", [])
            controller.composer.setInputMode(english ? .english : settings.defaultInput)
        }
        func tab() { _ = press(controller, field, "\t", code: VirtualKey.tab) }

        fresh()
        magicKey(controller, field)
        let rows = controller.panelModel().rows, model = controller.panelModel()
        check(field.marked == t && rows.count == Composer.oneAtRowsShown && model.highlighted == 0
              && rows.allSatisfy { !$0.text.hasPrefix(t) && $0.icon != nil && $0.label.isEmpty },
              "\(t) alone lists the commands by name, \(Composer.oneAtRowsShown) shown, the first highlighted (\(rows.map(\.text)))")
        _ = escape(controller, field)
        check(field.marked.isEmpty && field.inserted.isEmpty && controller.composer.draft.isEmpty, "…Esc gives the key up: nothing goes in")

        // Commands that ask no AI: picking one runs nothing.
        fresh()
        magicKey(controller, field)
        type("n", controller, field)
        _ = enter(controller, field)
        check(controller.composer.draft == t + "note " && field.marked == "note › " && field.inserted.isEmpty,
              "\(t)n ⏎ picks @note (\(field.marked))")
        _ = escape(controller, field)

        fresh()
        magicKey(controller, field)
        type("rem", controller, field)
        tab()
        check(controller.composer.draft == t + "reminder " && field.marked == "reminder › ", "\(t)rem Tab picks @reminder (\(field.marked))")
        _ = escape(controller, field)

        fresh()
        magicKey(controller, field)
        type("note", controller, field)
        _ = space(controller, field)
        check(controller.composer.draft == t + "note " && field.marked == "note › ", "\(t)note Space writes it, as always (\(field.marked))")
        _ = escape(controller, field)

        // A name no command has (a mention): composed after the key, put in as typed with Esc.
        fresh()
        magicKey(controller, field)
        type("z", controller, field)
        check(controller.composer.draft == t && controller.composer.engineState.isComposing && field.inserted.isEmpty,
              "\(t)z: z is pinyin after the \(t), nothing goes in yet")
        _ = escape(controller, field)
        check(field.inserted == [t + "z"] && field.marked.isEmpty && !controller.composer.isComposing,
              "…Esc puts \(t)z in as typed (\(field.inserted))")

        // A sum: its value first, ⏎ puts it in.
        fresh(english: true)
        magicKey(controller, field)
        type("3", controller, field)
        _ = press(controller, field, "*", code: 0x1C, flags: .shift)  // ⇧8
        type("7", controller, field)
        let sum = controller.panelModel().rows.first?.text
        _ = enter(controller, field)
        check(sum == "= 21" && field.inserted == ["21"] && field.marked.isEmpty, "\(t)3*7: = 21 first, ⏎ puts 21 in (\(sum ?? "-"), \(field.inserted))")

        // The key then Space: the key itself, and the space goes on to the app.
        fresh()
        magicKey(controller, field)
        check(!space(controller, field) && field.inserted == [t] && controller.composer.draft.isEmpty,
              "\(t) then Space is the \(t) itself (\(field.inserted))")

        // Another magic key: "@" types as itself, no list.
        if t != "@" {
            fresh(english: true)
            let handled = press(controller, field, "@", code: 0x13, flags: .shift)
            check(!handled && controller.composer.draft.isEmpty && field.marked.isEmpty && controller.panelModel().rows.isEmpty,
                  "with \(t) the magic key, @ is text: no list")
        }
    }

    /// The magic key (`@` by default, `~` in `withMagicKey`) right after a word is text in every app, terminals too
    /// (`ssh xyz@123.1769`, an email address), and ← → on the key alone leave it as typed. In a terminal (a fake Ghostty
    /// line, `GhosttyLine`, which tells no caret) the input method knows the word from what it typed; in a text view the
    /// field must also have it before the caret. With another magic key, "@" is text like any other character.
    static func testAtAfterAWord(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        let t = controller.composer.commandTrigger
        section("\(t) after a word, and ← → on a lone \(t), in a terminal and a text view", needs: .composing)
        let pointerBefore = controller.services.pointerUsedWithin
        controller.services.pointerUsedWithin = { _ in false }  // the user's own clicks meanwhile
        let terminal = FakeTextClient()
        terminal.bundleIDOverride = "com.mitchellh.ghostty"
        terminal.knowsRanges = false
        controller.activateServer(terminal)
        controller.composer.setInputMode(.english)  // a shell command, typed as letters
        defer {
            controller.composer.setInputMode(settings.defaultInput)
            controller.services.pointerUsedWithin = pointerBefore
            controller.activateServer(client)
        }
        let line = GhosttyLine(controller, terminal)
        var composed = false
        for ch in "ssh xyz\(t)123.1769" {
            line.type(String(ch))
            composed = composed || controller.composer.isComposing || !terminal.marked.isEmpty
        }
        check(line.shell == "ssh xyz\(t)123.1769" && !composed,
              "in a terminal, ssh xyz\(t)123.1769 goes in as typed: no command list after xyz (\(line.shell))")
        line.press("\r", code: VirtualKey.returnKey)
        line.shell = ""
        // The key alone (the list) and → : the key stays, after the arrow, which only ends the list (Ghostty would send
        // the arrow alone for text inserted during it).
        for (arrow, code) in [("\u{F703}", VirtualKey.right), ("\u{F702}", VirtualKey.left)] {
            line.type(t)
            check(controller.composer.draft == t && terminal.marked == t, "a lone \(t) opens the list (\(terminal.marked))")
            line.press(arrow, code: code)
            check(line.shell == t && terminal.marked.isEmpty && !controller.composer.isComposing && controller.panelModel().rows.isEmpty,
                  "\(code == VirtualKey.right ? "→" : "←") on it in a terminal leaves the \(t) and ends the list (\(line.shell))")
            line.type("123")
            check(line.shell == t + "123", "what's typed next follows it (\(line.shell))")
            line.press("\r", code: VirtualKey.returnKey)
            line.shell = ""
        }
        // A key that can't be in a command's name leaves the list with its character (`@ ` is an at sign).
        for key in [".", " ", ":"] {
            line.type(t)
            line.type(key)
            check(line.shell == t + key && !controller.composer.isComposing, "\(t) then '\(key)' in a terminal: '\(line.shell)'")
            line.press("\r", code: VirtualKey.returnKey)
            line.shell = ""
        }
        // After a space the list still opens.
        line.type("echo \(t)")
        check(controller.composer.draft == t && line.shell == "echo ", "after a space \(t) opens the list (\(line.shell))")
        _ = escape(controller, terminal)
        // Another magic key: "@" is text, no list (a chat app's own mention list works as always).
        if t != "@" {
            line.press("\r", code: VirtualKey.returnKey)
            line.shell = ""
            line.type("echo @")
            check(line.shell == "echo @" && controller.composer.draft.isEmpty && terminal.marked.isEmpty,
                  "with \(t) the magic key, @ is text (\(line.shell))")
            line.press("\r", code: VirtualKey.returnKey)
            line.shell = ""
        }

        // A text view: it has what the keys typed (the fake records only what the input method inserts).
        let field = FakeTextClient()
        controller.activateServer(field)
        controller.composer.setInputMode(.english)
        func typeIntoField(_ text: String) {
            for ch in text {
                let handled = magicKeyCodes[String(ch)].map { press(controller, field, String(ch), code: $0, flags: .shift) }
                    ?? press(controller, field, String(ch), code: keyCodes[ch] ?? 0)
                if !handled { field.document += String(ch) }
            }
        }
        typeIntoField("bob\(t)example.com")
        check(field.document == "bob\(t)example.com" && field.marked.isEmpty && !controller.composer.isComposing,
              "in a text view an email address goes in as typed (\(field.document))")
        // The app emptied the field (no key of ours): the field says nothing is before the caret, and the key opens the list.
        field.document = ""
        typeIntoField(t)
        check(controller.composer.draft == t && field.marked == t, "in a field emptied by the app, \(t) opens the list (\(field.marked))")
        // → there: the key goes in and the arrow goes on to the app (the caret moves), as before.
        check(!press(controller, field, "\u{F703}", code: VirtualKey.right) && field.inserted.last == t && field.marked.isEmpty
              && !controller.composer.isComposing, "→ on a lone \(t) in a text view inserts it and the app moves the caret (\(field.inserted))")
    }
}
