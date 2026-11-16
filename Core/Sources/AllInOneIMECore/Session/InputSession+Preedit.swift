import Foundation

// MARK: - What is being typed, in the panel only

/// What is being typed (pinyin, a command's draft, a note, Code's word, a dead key's accent, what dictation heard so far)
/// is never marked in the field, in any app: the candidate panel's input line shows it, with its caret, and the field gets
/// text only when something is put in (the owner, 2026-11-15; #115, #116). Chromium's pages, Electron's apps and AppKit's
/// text fields put marked text in as text themselves when the focus leaves, before the input method hears of it; with
/// nothing marked, leaving a field while typing leaves nothing there. The composer still has its composition
/// (`Composer.markedText`, `markedCursor`); only the shell is never asked to mark it.
extension InputSession {
    /// What is being typed is left (`SessionEvent.commit`, `cancel`, `pointerDown`): the app's commit and a click put in
    /// what the composer leaves a field with (`Composer.leaveField`: never the pinyin nor a command not run yet; a note or
    /// what dictation heard, as typed), as leaving the field does; cancelled, nothing pending goes in
    /// (`appTookMarkedText`). A click (or the app's commit on one) may have moved the caret: the suggestion token ends.
    func left(_ event: SessionEvent) {
        autocompleteLeft(.ignored)
        clipboardLeft()
        if case .cancel = event { perform(composer.appTookMarkedText()) } else { perform(composer.leaveField()) }
        if case .cancel = event { return }
        suggestionsClicked()
    }

    /// The panel told again once what is being typed changed since it was last told: after everything the shell is told
    /// of an event, so the input line is never left behind (the composition ended by a commit, a key Code's word ended on).
    func followPreedit() {
        guard SessionText.panelInput(composer) != preeditShown else { return }
        showPanel()
    }

    /// `panel` as the shell is told it (`emit`): with the input line on top while something is being typed, on its own
    /// (the notice up now beside it) where nothing else shows; never over clipboard history's. Nil: none.
    func withPreedit(_ panel: PanelModel?) -> PanelModel? {
        guard let input = SessionText.panelInput(composer), !clipboard.shown else { return panel }
        var panel = panel ?? PanelModel(detail: notice)
        if panel.input == nil { panel.input = input }
        return panel
    }
}
