import Foundation

// MARK: - A draft kept while the focus is elsewhere

/// The field lost the focus without a click while something was being typed (a notification or a dialog took it, ⌘-Tab,
/// the page moved it): the panel hides and what is being typed is kept for that field, nothing of it in and nothing
/// lost, the same in every app (the owner, #180). Back in the same field, the panel and the draft are as they were and
/// typing goes on; another field taking the focus instead drops it and starts clean. A click leaves as before
/// (`SessionEvent.pointerDown` comes first and drops it). The composer is left as it is meanwhile: only the panel is
/// kept from showing (`withPreedit`, `followPreedit`).
extension InputSession {
    /// A draft kept for the field left: the field as the session was told it, when it was left (`SessionServices.uptime`),
    /// and whether the shell holds it (`holdKeptDraft`).
    struct KeptDraft {
        var field: FieldInfo
        var since: TimeInterval
        var held = false
    }

    /// How long a draft is kept for its field (seconds): after that it doesn't come back.
    public static let keptDraftLife: TimeInterval = 600

    /// Whether a draft is kept for the field left (the shell: another field of its own taking the focus ends it with
    /// `SessionEvent.cancel`, where the session isn't the one told of that focus).
    public var keepsDraft: Bool { keptDraft != nil }

    /// The shell can't tell yet whether the field about to take the focus is the one the draft is kept for (two fields
    /// of an app are the same `FieldInfo`; the Mac asks Accessibility, off the main thread): told before that
    /// `SessionEvent.focus`, the draft stays kept and hidden through it, until the shell says it is that field
    /// (`releaseKeptDraft`) or another (`SessionEvent.cancel`). A key typed before it said either drops the draft: the
    /// field it is typed in may be another one.
    public func holdKeptDraft() {
        keptDraft?.held = true
    }

    /// The field that took the focus is the one the draft is kept for (after `holdKeptDraft`): the panel and the draft
    /// as they were. Nothing where none is kept any more.
    public func releaseKeptDraft() -> [SessionOutput] {
        collect {
            keptDraft?.held = false
            showKeptDraft()
        }
    }

    /// `SessionEvent.blur`: what is being typed is kept where it can wait (`Composer.waitsForField`), else it leaves as
    /// the composer has it (`Composer.leaveField`).
    func blurred() {
        autocompleteLeft(.ignored)
        clipboardLeft()
        suggestionsLeft()
        if keptDraft == nil {
            if composer.waitsForField {
                composer.modifierChangesMissed()  // a modifier held now is released elsewhere, as `leaveField` has it
                keptDraft = KeptDraft(field: field, since: services.uptime())
                emit(.panel(nil))
            } else {
                perform(composer.leaveField())
            }
        }
        fieldSession += 1
        fieldText = nil
        lastTyped.forget()
    }

    /// The session closes: a kept draft goes, and autocomplete's ghost with nothing shown of it.
    func closedKeptDraftAndAutocomplete() {
        dropKeptDraft()
        autocompleteLeft(.unseen)
    }

    /// The kept draft goes, nothing of it in: the focus went to another field (`unlessIn`: the one taking it, which keeps
    /// the draft when it is the field that was left), the session closes, or the app ended the composition meanwhile.
    func dropKeptDraft(unlessIn field: FieldInfo? = nil) {
        guard let kept = keptDraft, kept.field != field else { return }
        keptDraft = nil
        perform(composer.appTookMarkedText())
    }

    /// A key with no focus told first: the field is typed in again, and the draft shows. One the shell still holds
    /// (`holdKeptDraft`) goes instead, nothing of it in: the field typed in may not be the one it was kept for. So does
    /// one in a field the key tells is a password field (`keptDraftMustGo`), before the key does anything with it.
    func keptDraftTypedIn(_ context: FieldContext) {
        guard let kept = keptDraft else { return }
        if kept.held || keptDraftMustGo(context) { dropKeptDraft() } else { showKeptDraft() }
    }

    /// A modifier key with no focus told first, as a key (`keptDraftTypedIn`), before it acts: Shift's tap, Caps Lock
    /// and Option's tap work on what is composed, and never on a draft the shell holds, which goes first. Only a
    /// modifier let go that does nothing leaves a held one held (`releasesIdly`: ⌘ after ⌘-Tab comes before the shell
    /// can tell which field it is).
    func keptDraftBeforeModifiers(_ change: ModifierChange, _ context: FieldContext) {
        guard let kept = keptDraft else { return }
        if keptDraftMustGo(context) { return dropKeptDraft() }
        guard kept.held else { return showKeptDraft() }
        if !releasesIdly(change) { dropKeptDraft() }
    }

    /// Whether the field a key or a modifier key is told in is one a kept draft must never show in, as the key tells
    /// it, before the session takes that over from it (`takePasswordField`): secure input on for it or anywhere, a
    /// password field, or one the shell was asked about and couldn't tell.
    private func keptDraftMustGo(_ context: FieldContext) -> Bool {
        context.secure || context.field?.secure == true || nothingLeavesDevice()
            || context.read.contains(.passwordField) && context.passwordFieldUnknown
    }

    /// Whether `change` is a modifier let go that does nothing on its own: none of those a tap or a hold of which acts
    /// as it is let go (Shift's tap, the action key's, the voice key's), and no key going down (Caps Lock, fn).
    private func releasesIdly(_ change: ModifierChange) -> Bool {
        guard case let .modifier(kind, _) = change.key, !change.modifiers.contains(Modifiers.kind(kind)) else { return false }
        let roles = composer.modifierRoles
        return kind != .shift && kind != roles.actionTap && kind != roles.voiceHold.kind
    }

    /// `SessionEvent.focus`: a draft kept for another field goes, and so does one where secure input is on or the field
    /// is a secure one, before the field is taken; the one kept for `info` shows there again.
    func focusing(_ info: FieldInfo, _ focus: () -> Void) {
        dropKeptDraft(unlessIn: info)  // another field's: it starts clean
        if info.secure || services.secureInputActive() { dropKeptDraft() }
        focus()
        showKeptDraft()
    }

    /// Back in the field the draft was kept for: the panel and the draft as they were, unless the shell holds it.
    /// Never in a password field or while secure input is on (the field isn't the one left, or mustn't be given what was
    /// typed elsewhere), nor one kept longer than `keptDraftLife`: it goes, nothing of it in.
    func showKeptDraft() {
        guard let kept = keptDraft, !kept.held else { return }
        if nothingLeavesDevice() || services.uptime() - kept.since > Self.keptDraftLife { return dropKeptDraft() }
        keptDraft = nil
        // The engine was let go meanwhile (librime deployed again): its pinyin went with it.
        guard composer.isComposing else { return }
        showPanel()
    }
}
