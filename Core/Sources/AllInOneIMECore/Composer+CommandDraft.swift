import Foundation

// MARK: - A draft and the keys that end it

// A command written but not run yet ("@question …", "@improve …") never goes into the field as typed, whatever its text
// (Chinese or English): ⌘⏎ runs it as ⏎ does; the field left, the app ending the composition or any other ⌘ shortcut
// drops it (the shortcut is then the app's); ⌘← ⌘→ convert its pinyin into it before they move the cursor. Plain text and
// `@note` keep going in as typed. The owner, 2026-11-15: ⌘⏎, "send" in chat apps, typed "@question what is rust" in.

extension Composer {
    /// A draft still free of Chinese text, e.g. "hello wor" typed in English mode: a shortcut (⌘A, ⌘S …) inserts it as
    /// typed and then reaches the application; ⌘V instead takes the clipboard's text into the draft (`pasted`). Not a
    /// command not run yet ("@improve this is …"): that goes, nothing typed in (`dropsCommandDraft`).
    public var isLatinDraft: Bool { !draft.isEmpty && !draft.containsHan }

    /// The draft is a command not run yet that is dropped rather than typed in: any but `@note`, whose text is the user's
    /// own (one line goes in as typed, more go to the clipboard: `finishAsTyped`).
    var dropsCommandDraft: Bool {
        guard !isLevelTwo, let command = draftCommand else { return false }
        return command.kind != .note
    }

    /// ⌘⏎ on such a draft is ⏎: it runs the command, as at level two (`handleHandoffKey`), and never reaches the app (a
    /// chat app would send what's in its field). Any other key as it is.
    func returnForCommandDraft(_ event: KeyEvent) -> KeyEvent {
        let primary = Modifiers.kind(modifierRoles.primary)
        guard event.key == .enter || event.key == .keypadEnter, event.modifiers.subtracting(.capsLock) == primary,
              dropsCommandDraft else { return event }
        var plain = event
        plain.modifiers.remove(primary)
        return plain
    }

    /// The command not run yet goes, as Esc takes it: nothing in the field (a selection is left as it is).
    func dropCommandDraft() -> [Effect] {
        finish(committing: "", leaving: true)
    }

    /// Pinyin being typed in a command's text goes into it, converted as Space picks it, before ⌘← ⌘→ move the cursor
    /// there (nothing is typed into the field).
    func convertBeforeCursorMove() -> [Effect] {
        guard let engine, engine.snapshot().isComposing else { return [] }
        let effects = convertComposition(engine)
        setLevelOnePhase()
        return effects
    }
}
