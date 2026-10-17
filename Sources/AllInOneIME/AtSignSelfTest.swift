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

    /// Each character with its key on a US layout ("@" is ⇧2).
    func type(_ text: String) {
        for ch in text {
            switch ch {
            case "@": press("@", code: 0x13, flags: .shift)
            case ".": press(".", code: 0x2F)
            default: press(String(ch), code: SelfTest.keyCodes[ch] ?? 0)
            }
        }
    }
}

extension SelfTest {
    /// "@" right after a word is text in every app, terminals too (`ssh xyz@123.1769`, an email address), and ← → on a
    /// lone "@" leave it as typed. In a terminal (a fake Ghostty line, `GhosttyLine`, which tells no caret) the input
    /// method knows the word from what it typed; in a text view the field must also have it before the caret.
    static func testAtAfterAWord(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("@ after a word, and ← → on a lone @, in a terminal and a text view", needs: .composing)
        let pointerBefore = controller.pointerUsedWithin
        controller.pointerUsedWithin = { _ in false }  // the user's own clicks meanwhile
        let terminal = FakeTextClient()
        terminal.bundleIDOverride = "com.mitchellh.ghostty"
        terminal.knowsRanges = false
        controller.activateServer(terminal)
        controller.composer.setInputMode(.english)  // a shell command, typed as letters
        defer {
            controller.composer.setInputMode(settings.defaultInput)
            controller.pointerUsedWithin = pointerBefore
            controller.activateServer(client)
        }
        let line = GhosttyLine(controller, terminal)
        var composed = false
        for ch in "ssh xyz@123.1769" {
            line.type(String(ch))
            composed = composed || controller.composer.isComposing || !terminal.marked.isEmpty
        }
        check(line.shell == "ssh xyz@123.1769" && !composed,
              "in a terminal, ssh xyz@123.1769 goes in as typed: no command list after xyz (\(line.shell))")
        line.press("\r", code: VirtualKey.returnKey)
        line.shell = ""
        // A lone "@" (the list) and → : the "@" stays, after the key, which only ends the list (Ghostty would send the
        // arrow alone for text inserted during it).
        for (arrow, code) in [("\u{F703}", VirtualKey.right), ("\u{F702}", VirtualKey.left)] {
            line.type("@")
            check(controller.composer.draft == "@" && terminal.marked == "@", "a lone @ opens the list (\(terminal.marked))")
            line.press(arrow, code: code)
            check(line.shell == "@" && terminal.marked.isEmpty && !controller.composer.isComposing && controller.panelModel().rows.isEmpty,
                  "\(code == VirtualKey.right ? "→" : "←") on it in a terminal leaves the @ and ends the list (\(line.shell))")
            line.type("123")
            check(line.shell == "@123", "what's typed next follows it (\(line.shell))")
            line.press("\r", code: VirtualKey.returnKey)
            line.shell = ""
        }
        // A key that can't be in a command's name leaves the list with its character.
        for key in [".", " ", ":"] {
            line.type("@")
            line.type(key)
            check(line.shell == "@" + key && !controller.composer.isComposing, "@ then '\(key)' in a terminal: '\(line.shell)'")
            line.press("\r", code: VirtualKey.returnKey)
            line.shell = ""
        }
        // After a space the list still opens.
        line.type("echo @")
        check(controller.composer.draft == "@" && line.shell == "echo ", "after a space @ opens the list (\(line.shell))")
        _ = escape(controller, terminal)

        // A text view: it has what the keys typed (the fake records only what the input method inserts).
        let field = FakeTextClient()
        controller.activateServer(field)
        controller.composer.setInputMode(.english)
        func typeIntoField(_ text: String) {
            for ch in text {
                let handled = ch == "@" ? press(controller, field, "@", code: 0x13, flags: .shift)
                    : press(controller, field, String(ch), code: keyCodes[ch] ?? 0)
                if !handled { field.document += String(ch) }
            }
        }
        typeIntoField("bob@example.com")
        check(field.document == "bob@example.com" && field.marked.isEmpty && !controller.composer.isComposing,
              "in a text view an email address goes in as typed (\(field.document))")
        // The app emptied the field (no key of ours): the field says nothing is before the caret, and "@" opens the list.
        field.document = ""
        typeIntoField("@")
        check(controller.composer.draft == "@" && field.marked == "@", "in a field emptied by the app, @ opens the list (\(field.marked))")
        // → there: the "@" goes in and the key goes on to the app (the caret moves), as before.
        check(!press(controller, field, "\u{F703}", code: VirtualKey.right) && field.inserted.last == "@" && field.marked.isEmpty
              && !controller.composer.isComposing, "→ on a lone @ in a text view inserts it and the app moves the caret (\(field.inserted))")
    }
}
