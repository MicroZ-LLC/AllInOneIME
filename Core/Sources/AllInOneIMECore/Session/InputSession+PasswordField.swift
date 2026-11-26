import Foundation

/// Whether the field that has the focus is a password field where secure input isn't on (`passwordField`), as the shell
/// tells it: with a key where suggestions may show (`FieldContext.Parts.passwordField`), or after it, off the key's thread
/// (`SessionOutput.readPasswordField`: the Mac's Accessibility, which may wait on a slow app), where English words may be
/// learned and where the shell tells it so (`FieldContext.passwordFieldFollows`); and with each read autocomplete's pause
/// makes.
extension InputSession {
    /// A key may arrive for another field before activate; stop carrying private text, rows or a completion into it.
    func prepareKeyField(_ context: FieldContext) {
        if fieldTextStaysHere { fieldText = nil }
        else if context.read.contains(.text) { fieldText = context.text }
        if let current = context.field, current != field, current.textStaysHere {
            autocompleteLeft(.unseen)
            suggestionsSecure()
        }
    }

    /// Whether nothing of this field may leave the device: secure input on (`secureInputActive`), or a field told to be a
    /// password field where it isn't (`passwordField`), as if it were. Then no AI row is listed, an AI command, a message
    /// or a note to Notion is refused, a script isn't given what is typed, Translate as You Type collects nothing, and
    /// neither the selection nor the text around the caret is read for a command. While an answer is pending, it is
    /// treated as private; a field the shell couldn't tell keeps the existing unknown policy.
    public func nothingLeavesDevice() -> Bool {
        secureInputActive() || passwordField == .yes || passwordField == nil && passwordFieldAsked == fieldSession
    }

    /// What the shell told of the field that has the focus being a password field where secure input isn't on
    /// (`passwordField`).
    enum PasswordField: Equatable {
        /// One (the Mac: Accessibility tells an `AXSecureTextField`).
        case yes
        /// None.
        case no
        /// The shell was asked and couldn't tell (the Mac: no Accessibility, nothing focused, no answer in time, the read
        /// failed): not asked again in this field.
        case unknown
    }

    /// Whether nothing of this field may be read, sent or learned from: secure input on (`secureInputActive`), or a
    /// password field where it isn't (`passwordField`), as if it were. `unknown` is what a field not told yet counts as
    /// (true where nothing is done until it's known: suggestions' rows, Code's reads of the field, the English words
    /// learned; false for autocomplete, whose read of the field once its pause is over tells it); `untold` what one the
    /// shell couldn't tell counts as (`PasswordField.unknown`): true for the English words learned, so that without
    /// Accessibility nothing is learned in a field secure input isn't on in (a password field can't be told apart there);
    /// false for autocomplete and suggestions, which have always taken it as none. The one check learning, autocomplete
    /// and suggestions go by.
    func fieldIsPrivate(unknown: Bool, untold: Bool = false) -> Bool {
        guard !secureInputActive() else { return true }
        switch passwordField {
        case .yes?: return true
        case .no?: return false
        case .unknown?: return untold
        case nil: return unknown
        }
    }

    /// What `context` tells of the field being a password field where secure input isn't on (`passwordField`): one
    /// (`field`'s `secure`), else asked (`.passwordField`) none or, where the shell couldn't tell
    /// (`passwordFieldUnknown`), unknown (`takePasswordField(_:)`); where the shell tells it after the key
    /// (`passwordFieldFollows`), not told yet until it does (`askPasswordField`): no rows, nothing learned meanwhile.
    func takePasswordField(_ context: FieldContext) {
        guard context.read.contains(.secure), !context.secure else { return }
        if context.field?.secure == true {
            takePasswordField(.yes)
        } else if context.passwordFieldFollows {
            askPasswordField()
        } else if context.read.contains(.passwordField),
                  context.field != nil || context.passwordFieldUnknown || passwordFieldAsked != fieldSession {
            takePasswordField(context.passwordFieldUnknown ? .unknown : .no)
        }
    }

    /// `told` of the field that has the focus: one stays one until another field takes the focus; none is taken over
    /// one not told yet or not told apart (a read that tells after one that couldn't); unknown only over one not told
    /// yet.
    func takePasswordField(_ told: PasswordField) {
        let before = passwordField
        switch (told, passwordField) {
        case (.yes, _), (_, nil), (.no, .unknown?): passwordField = told
        default: break
        }
        if before != .yes, passwordField == .yes { suggestionsSecure() }
    }

    /// The shell asked, off the key's thread (`SessionOutput.readPasswordField`), whether the field that has the focus is a
    /// password field: once a field, while it isn't told yet. No key waits for the answer (`passwordFieldTold`).
    func askPasswordField() {
        guard passwordField == nil, passwordFieldAsked != fieldSession else { return }
        passwordFieldAsked = fieldSession
        emit(.readPasswordField(focus: fieldSession))
    }

    /// The shell's answer for the field that had the focus when it was asked (`SessionEvent.passwordField`, `focus`; nil:
    /// it couldn't tell), taken unless that field has lost the focus since; told just now, the rows for what is typed show
    /// where they may (none did until then), or none in a password field.
    func passwordFieldTold(_ told: Bool?, focus: Int) {
        guard focus == fieldSession else { return }
        let before = passwordField
        takePasswordField(told.map { $0 ? .yes : .no } ?? .unknown)
        if before == nil, passwordField != .yes, !composesBesidesCodeWord { suggestionsUpdate() }
    }
}
