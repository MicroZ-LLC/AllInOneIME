import Foundation

// MARK: - A draft and the keys that end it

// A command written but not run yet ("@question …", "@improve …") never goes into the field as typed, whatever its text
// (Chinese or English): ⌘⏎ runs it as ⏎ does (`@note` too: it saves); the field left, the app ending the composition or
// any other ⌘ shortcut drops it (the shortcut is then the app's); ⌘← ⌘→ convert its pinyin into it before they move the
// cursor; ⌘V pastes into it in every app, terminals and Notes too. A command that ran (results up, or still coming) leaves
// nothing either when the field is left: its run stops. Plain text and a one-line `@note` not saved keep going in as typed.
// The owner, 2026-11-15: ⌘⏎, "send" in chat apps, typed "@question what is rust" in.

extension Composer {
    /// A draft still free of Chinese text, e.g. "hello wor" typed in English mode: a shortcut (⌘A, ⌘S …) inserts it as
    /// typed and then reaches the application; ⌘V instead takes the clipboard's text into the draft (`pasted`). Not a
    /// command not run yet ("@improve this is …"): that goes, nothing typed in (`dropsCommandDraft`).
    public var isLatinDraft: Bool { !draft.isEmpty && !draft.containsHan }

    /// The draft is a command not run yet, `@note` included: ⌘⏎ runs it (`returnForCommandDraft`), ⌘V pastes into it.
    public var isCommandDraft: Bool { !isLevelTwo && draftCommand != nil }

    /// The draft is a command not run yet that is dropped rather than typed in: any but `@note`, whose text is the user's
    /// own (one line goes in as typed, more go to the clipboard: `finishAsTyped`).
    var dropsCommandDraft: Bool { isCommandDraft && draftCommand?.kind != .note }

    /// Nothing goes into the field when it's left (`commitAll`) or a password field takes over (`passwordFieldTakesOver`):
    /// a command not run yet but `@note`, or one that ran (level two: results shown or still coming), whose run stops.
    var leavesNothing: Bool { isLevelTwo || dropsCommandDraft }

    /// ⌘V takes the clipboard into the command not run yet in every app, as ⌃V does: also where the app pastes on ⌘V
    /// itself (terminals, Notes; `pastesIntoDraft`), whose shell keeps the key from it then (the Mac's key tap).
    public var pastesIntoCommand: Bool { isCommandDraft && takesPasteAnywhere }

    /// ⌘⏎ on a command not run yet is ⏎: it runs the command (`@note` saves), as at level two (`handleHandoffKey`), and
    /// never reaches the app (a chat app would send what's in its field). Any other key as it is.
    func returnForCommandDraft(_ event: KeyEvent) -> KeyEvent {
        let primary = Modifiers.kind(modifierRoles.primary)
        guard event.key == .enter || event.key == .keypadEnter, event.modifiers.subtracting(.capsLock) == primary,
              isCommandDraft else { return event }
        var plain = event
        plain.modifiers.remove(primary)
        return plain
    }

    /// The field turned into a password field, or secure input came on in it: what's pending goes in as typed
    /// (`commitAsTyped`), but never a command (`leavesNothing`): one not run yet goes, one that ran stops. (A request
    /// refused in a known password field still types its draft in, and ⏎ signs in: `commitAsTyped`.)
    public func passwordFieldTakesOver() -> [Effect] {
        leavesNothing ? dropCommandDraft() : commitAsTyped()
    }

    /// The command goes, as Esc takes it: nothing in the field (a selection is left as it is), a run going on cancelled (a
    /// script showing its output is detached: `finish`).
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
