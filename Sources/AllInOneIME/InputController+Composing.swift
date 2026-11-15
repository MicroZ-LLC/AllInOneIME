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
}
