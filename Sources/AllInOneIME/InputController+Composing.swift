import AllInOneIMECore
import AllInOneIMEMac
import InputMethodKit

extension AllInOneIMEInputController {
    /// Whether what a key that composes puts in goes in as marked text during it (`marksRow`, a page's app); never for a
    /// command written on the selection, which nothing may be marked over (`Composer.draftInPanel`).
    @MainActor
    func composingKeyMarks(in target: IMKTextInput?) -> Bool {
        !composer.draftInPanel && marksRow(in: target)
    }

    /// A key the input method took that put nothing in, in an app built on Chromium or Electron (`marksRow`): kept from
    /// the page. A key that composes (`composes`): a space marked at the caret and taken out once the key is done, the
    /// field's own text never marked again (a page that emptied the field still tells the text it had: #115, the real
    /// Brave put it back). A row that adds nothing: what is before the caret, marked in its place (`markBeforeCaret`).
    @MainActor
    func markKeyAddingNothing(in target: IMKTextInput, composes: Bool) {
        if composes {
            markRow(" ", replacing: nil, in: target, for: "a key that composes", takenOut: true)
        } else {
            markBeforeCaret(in: target, for: "a row put in by a key, adding nothing")
        }
    }

    /// Whether what a key the rows took puts in (`SessionOutput.rowByKey`: a row), or nothing (`rowsTookKey`: ↓ ↑ → Esc),
    /// goes in as marked text during the key in `client` (`markRow`): only in an app built on Chromium or Electron
    /// (`chromiumApp`), whose page would get the key as well; not in a terminal (its keys go to a shell, and it takes no
    /// marked text in place of a range), nor where marked text of ours is in the field before the key (Code's word: the
    /// page has the key as the input method's already). Everywhere else (AppKit's fields, WebKit's: Messages, Notes, Mail,
    /// Safari) what the key puts in goes in as 0.6.7.1 put it, a row in the token's place with its range: those never act
    /// on a key the input method took. The same keys and rows everywhere; only how they go in differs.
    @MainActor
    func marksRow(in client: IMKTextInput?) -> Bool {
        guard !atTap, let client, !hasMarkedText else { return false }
        let app = client.bundleIdentifier()
        guard !Self.isTerminal(app: app), chromiumApp(app) else { return false }
        KeyGuard.shared.markedInstead()
        return true
    }
}
