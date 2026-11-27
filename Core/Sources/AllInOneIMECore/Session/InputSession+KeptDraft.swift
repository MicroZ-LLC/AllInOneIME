import Foundation

// MARK: - A draft kept while the focus is elsewhere

/// The field lost the focus without a click while something was being typed (a notification or a dialog took it, ⌘-Tab,
/// the page moved it): the panel hides and what is being typed is kept for that field, nothing of it in and nothing
/// lost, the same in every app (the owner, #180). Back in the same field, the panel and the draft are as they were and
/// typing goes on; another field taking the focus instead drops it and starts clean. A click leaves as before
/// (`SessionEvent.pointerDown` comes first and drops it). The composer is left as it is meanwhile: only the panel is
/// kept from showing (`withPreedit`, `followPreedit`).
extension InputSession {
    /// Whether a draft is kept for the field left (the shell: another field of its own taking the focus ends it with
    /// `SessionEvent.cancel`, where the session isn't the one told of that focus).
    public var keepsDraft: Bool { keptDraft != nil }

    /// `SessionEvent.blur`: what is being typed is kept where it can wait (`Composer.waitsForField`), else it leaves as
    /// the composer has it (`Composer.leaveField`).
    func blurred() {
        autocompleteLeft(.ignored)
        clipboardLeft()
        suggestionsLeft()
        if keptDraft == nil {
            if composer.waitsForField {
                keptDraft = field
                emit(.panel(nil))
            } else {
                perform(composer.leaveField())
            }
        }
        fieldSession += 1
        fieldText = nil
        lastTyped.forget()
    }

    /// The kept draft goes, nothing of it in: the focus went to another field (`unlessIn`: the one taking it, which keeps
    /// the draft when it is the field that was left), the session closes, or the app ended the composition meanwhile.
    func dropKeptDraft(unlessIn field: FieldInfo? = nil) {
        guard let kept = keptDraft, kept != field else { return }
        keptDraft = nil
        perform(composer.appTookMarkedText())
    }

    /// Back in the field the draft was kept for: the panel and the draft as they were.
    func showKeptDraft() {
        guard keptDraft != nil else { return }
        keptDraft = nil
        // The engine was let go meanwhile (librime deployed again): its pinyin went with it.
        guard composer.isComposing else { return }
        showPanel()
    }
}
