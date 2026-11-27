import Foundation

// MARK: - Leaving the field while typing

extension Composer {
    /// The user left the field while typing: a click elsewhere or in it, another field, another app, the window closed
    /// (the shell's blur and commit). What is being composed and not yet confirmed (pinyin) is dropped and nothing of it
    /// goes in, the same in every app (the owner, 2026-11-15; #116). The rest goes as `commitAll` has it.
    public func leaveField() -> [Effect] { commitAll(convertingComposition: false) }

    /// Whether what is being typed can wait for the field while the focus is elsewhere (`InputSession.blurred`): pinyin
    /// not yet confirmed, the "@" list's text, a command not run yet with its text. Not what is already on its way
    /// (a command that ran, dictation, a key parked for the selection's read, Translate as You Type's sentence), nor what
    /// another key was to finish (a dead key's accent, a Hangul syllable, Code's word), nor `@note`, whose text goes in
    /// as typed on every way out (the owner kept it so): those leave as before.
    var waitsForField: Bool {
        phase == .drafting && voice == .off && parkedForSelection == nil && !selectionPending && translateMode == nil
            && pendingAccent == nil && hangul.isEmpty && codeWord == nil && draftCommand?.kind != .note
    }
}
