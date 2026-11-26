import Foundation

/// Whether the field that has the focus is a password field where secure input isn't on (`passwordField`), as the shell
/// tells it: with a key where suggestions may show (`FieldContext.Parts.passwordField`), or after it, off the key's thread
/// (`SessionOutput.readPasswordField`: the Mac's Accessibility, which may wait on a slow app), where English words may be
/// learned and where the shell tells it so (`FieldContext.passwordFieldFollows`); and with each read autocomplete's pause
/// makes.
extension InputSession {
    /// A key may arrive for another field before activate; stop carrying private text, rows or a completion into it.
    func prepareKeyField(_ context: FieldContext) {
        if fieldTextStaysHere {
            fieldText = nil
            // Nor is the word before kept: learned once the field is left, it would go by the field the session was told.
            englishModeWords = EnglishModeWords()
        } else if context.read.contains(.text) {
            fieldText = context.text
        }
        if let current = context.field, current != field, current.textStaysHere {
            autocompleteLeft(.unseen)
            suggestionsSecure()
        }
    }

    /// Whether nothing of this field may leave the device: secure input on (`secureInputActive`), or a field told to be a
    /// password field where it isn't (`passwordField`), as if it were. Then no AI row is listed, an AI command, a message
    /// or a note to Notion is refused, a script isn't given what is typed, Translate as You Type collects nothing, and
    /// neither the selection nor the text around the caret is read for a command. A field not told yet, or one the shell
    /// couldn't tell, isn't refused so: a command still sends what the user typed for it there, but doesn't read the
    /// field (`fieldMayNotBeRead`).
    public func nothingLeavesDevice() -> Bool {
        secureInputActive() || passwordField == .yes
    }

    /// Whether a command may not read this field (the selection, the text around the caret): anywhere but in a field
    /// told to be no password field (`PasswordField.no`) with secure input off. So also not in one the shell couldn't
    /// tell (`PasswordField.unknown`: the Mac without Accessibility can't tell a password field apart), nor in one not
    /// told yet, asked about or not: read as a password field is, that is, not at all, until it is known to be none (the
    /// owner's decision, 2026-11-26). A field is asked about as it takes the focus (`passwordFieldFocused`); one not
    /// asked about yet is asked before anything reads it (`fieldWants`, `fieldMayBeReadOrAsks`), and what would have
    /// read it goes on without. What the user typed for the command is theirs to send
    /// (`nothingLeavesDevice` is no wider), and autocomplete's own read is its own (`fieldIsPrivate`).
    func fieldMayNotBeRead() -> Bool {
        secureInputActive() || passwordField != .no
    }

    /// Whether a command may read the field once `context` (a key's reads so far) is taken (`takePasswordField`): told
    /// to be no password field before, or by `context`. What `fieldWants` goes by, before the key is handled.
    func fieldMayBeRead(given context: FieldContext) -> Bool {
        guard !secureInputActive(), !context.secure else { return false }
        guard let told = told(by: context) else { return passwordField == .no }
        return passwordField(told: told) == .no
    }

    /// Whether a command may read the field now (`fieldMayNotBeRead`); in a field not asked about yet, the shell is asked
    /// (`askPasswordField`: told later, read from then on).
    func fieldMayBeReadOrAsks() -> Bool {
        if passwordField == nil, !secureInputActive() { askPasswordField() }
        return !fieldMayNotBeRead()
    }

    // MARK: What the composer asks of the field

    /// Whether "@" may read the field's selection and work on it: with the setting on (`useSelection`) and the app not
    /// learned as one whose field doesn't take a result in its place (`usesSelection`), never during secure input, nor in
    /// a field not known to be no password field (`fieldMayNotBeRead`: one not asked about is asked now, and "@" starts
    /// on nothing meanwhile), nor in a terminal (its selection is no text being edited: what goes back would be typed at
    /// the prompt), nor in a password manager, whatever its field says (`FieldInfo.textStaysHere`: a command starts
    /// there as in a terminal).
    func selectionMayBeRead() -> Bool {
        usesSelection(in: app, config: services.loadSettings()) && !fieldTextStaysHere && fieldMayBeReadOrAsks()
    }

    /// `selected`, read after the "@" key, where the draft may take it (`selectionMayBeRead`: a field told a password field
    /// meanwhile too).
    func usable(_ selected: Composer.Selection?) -> Composer.Selection? {
        guard let selected, !selected.text.isEmpty, selectionMayBeRead() else { return nil }
        return selected
    }

    /// The text around the caret, for `@reply` (`Composer.readFieldText`): as the field told it with the key that runs it
    /// (or last: after dictation). None during secure input, in a field known as a password field or in one not known to
    /// be none (`fieldMayNotBeRead`: one not asked about is asked now), nor in a terminal or a password manager
    /// (`FieldInfo.textStaysHere`).
    func readFieldText() -> FieldText? {
        guard !fieldTextStaysHere, fieldMayBeReadOrAsks() else { return nil }
        if let context = keyContext, context.read.contains(.text) { return context.text }
        return fieldText
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
    /// (`passwordFieldFollows`), not told yet until it does (`askPasswordField`): no rows, nothing learned, nothing read
    /// for a command meanwhile.
    func takePasswordField(_ context: FieldContext) {
        guard context.read.contains(.secure), !context.secure else { return }
        if let told = told(by: context) {
            takePasswordField(told)
        } else if context.passwordFieldFollows {
            askPasswordField()
        }
    }

    /// What `context` says the field is (nil: nothing, or that it is told after the key). A "none" that doesn't say
    /// whose field it is (`FieldContext.field`) isn't taken while the shell's own answer is awaited
    /// (`passwordFieldAwaited`): that answer tells it.
    private func told(by context: FieldContext) -> PasswordField? {
        guard context.read.contains(.secure), !context.secure else { return nil }
        if context.field?.secure == true { return .yes }
        guard !context.passwordFieldFollows, context.read.contains(.passwordField),
              context.field != nil || context.passwordFieldUnknown || !passwordFieldAwaited else { return nil }
        return context.passwordFieldUnknown ? .unknown : .no
    }

    /// What the field is once it is `told`: one stays one until another field takes the focus; none is taken over one
    /// not told yet or not told apart (a read that tells after one that couldn't); unknown only over one not told yet.
    private func passwordField(told: PasswordField) -> PasswordField? {
        switch (told, passwordField) {
        case (.yes, _), (_, nil), (.no, .unknown?): return told
        default: return passwordField
        }
    }

    /// `told` of the field that has the focus (`passwordField(told:)`). Told a password field just now, nothing of it is
    /// kept: suggestions' rows and token go, autocomplete's pause, its request on its way and what was typed for it
    /// (as where secure input comes on); and an "@" list open is shown again, without its AI rows (`Composer.oneAtRows`).
    func takePasswordField(_ told: PasswordField) {
        let before = passwordField
        passwordField = passwordField(told: told)
        guard before != .yes, passwordField == .yes else { return }
        autocompleteLeft(.unseen)
        suggestionsSecure()
        if composer.oneAt != nil { perform([.showPanel]) }
    }

    /// Whether the shell was asked about this field (`askPasswordField`: as it took the focus, mostly) and hasn't
    /// answered yet.
    private var passwordFieldAwaited: Bool { passwordFieldAsked == fieldSession && passwordField == nil }

    /// A field took the focus: nothing is told of it yet, and the shell is asked at once (`askPasswordField`, off the
    /// main thread on the Mac), so that the answer is usually back before the first key: an "@" pressed first in a field
    /// then takes the selected text (`selectionMayBeRead`). Not during secure input (nothing is read there whatever the
    /// answer), nor where no command reads the field whatever it is (a terminal, a password manager:
    /// `FieldInfo.textStaysHere`; what else goes by the answer there asks with its key, as before).
    func passwordFieldFocused() {
        passwordField = nil
        if !secureInputActive(), !field.textStaysHere { askPasswordField() }
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
