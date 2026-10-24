import Foundation

// MARK: - Code's word (decision 33)

/// Code holds the word being typed as marked text (decision 33), as the command list holds what is typed after its trigger:
/// where Code's rows may show (`holdsCodeWord`, the session's: not in a terminal, in secure input or a password field),
/// a word's characters (`isCodeWordCharacter`: letters, digits, "_"; it starts with a letter or "_", as an identifier
/// does) collect into the draft, shown as typed, instead of going into the field one by one, and the rows follow it. A
/// number, or "#123" for a plugin's rows, goes straight in as before. Chromium's pages and Electron's apps hand a key the input
/// method took to the page too when nothing is marked before or after it: ↑ on the rows moved the page's caret as well.
/// ⌫ takes the word's last character back (none left: nothing is held, and the next ⌫ is the app's). The rows' keys are
/// the session's (`InputSession.suggestionsBeforeKey`: a row put in takes the word's place, → and Esc put it in as
/// typed); any other key ends the word: it goes in as typed, then the key acts as it would have (the app's: a space, a
/// mark, a bracket the editor closes, Return it indents on, a shortcut). A click, another field, the app's commit and a
/// tap of Shift put it in as typed too (`commitAll`, `switchInputLanguage`).
extension Composer {
    /// Whether `character` is part of the word Code holds: what Code's rows go by (`SuggestionsToken.isIdentifierCharacter`),
    /// its full-width form too.
    static func isCodeWordCharacter(_ character: Character) -> Bool {
        SuggestionsToken.isIdentifierCharacter(Character(SuggestionsToken.normalized(String(character))))
    }

    /// The word Code holds, as typed: the draft while it is one (a command's starts with its trigger, never a word's
    /// character). Nil: none is held.
    public var codeWord: String? {
        guard coding, !draft.isEmpty, selection == nil, !isLevelTwo, draft.allSatisfy(Self.isCodeWordCharacter) else { return nil }
        return draft
    }

    /// Whether `text`, typed with nothing being written, starts the word Code holds: a word's characters, the first no
    /// digit, where it holds one.
    func startsCodeWord(_ text: String) -> Bool {
        guard coding, !isComposing, let first = text.first, !Character(SuggestionsToken.normalized(String(first))).isNumber
        else { return false }
        return text.allSatisfy(Self.isCodeWordCharacter) && holdsCodeWord()
    }

    /// A key in Code, before anything else has it: a word's character starts the word (`startsCodeWord`) or extends the one
    /// held; ⌫ takes its last character back; any other key ends it (`endCodeWord(then:)`), and so does any key once
    /// Code holds no word here (the switches turned off meanwhile). Nil: the key acts as usual.
    func handleCodeWordKey(_ event: KeyEvent) -> Response? {
        guard coding, voice == .off, pendingAccent == nil else { return nil }
        let modifiers = event.modifiers.subtracting(.capsLock).subtracting(.sides)
        let text = modifiers.isSubset(of: .shift) && !event.isDeadKey ? event.printableText : nil
        let typesWord = text.map { $0.allSatisfy(Self.isCodeWordCharacter) } == true
        guard codeWord != nil else {
            guard typesWord, let text, startsCodeWord(text) else { return nil }
            insertIntoDraft(text)
            setLevelOnePhase()
            return .consumed([.updateMarkedText])
        }
        guard holdsCodeWord() else { return endCodeWord(then: event) }
        if typesWord, let text {
            insertIntoDraft(text)
            return .consumed([.updateMarkedText])
        }
        if event.key == .backspace, modifiers.isEmpty {
            deleteBeforeCursor()
            setLevelOnePhase()
            return .consumed([.updateMarkedText])
        }
        return endCodeWord(then: event)
    }

    /// The word held goes in as typed, then `event` acts as it would have with nothing held, as a key after the command
    /// list's letters does (`commitPalette`). The command trigger right after the word is text, as after a word typed
    /// straight in ("user@host": `continuesWord`).
    private func endCodeWord(then event: KeyEvent) -> Response {
        let word = draft
        let typed = endCodeWord()
        if event.printableText == commandTrigger, let last = word.last, Self.continuesWord(last) {
            return Response(effects: typed, handled: false)
        }
        let next = handleOtherKeyDown(event)
        return Response(effects: typed + next.effects, handled: next.handled)
    }

    /// The word held ends: it goes in as typed (→ or Esc on its rows, Code left), or `text` in its place (a row put in:
    /// the word and what the row adds to it). What the shell is to do; nothing of the composer's panel was up for it.
    public func endCodeWord(inserting text: String? = nil) -> [Effect] {
        guard let word = codeWord else { return [] }
        return finish(committing: text ?? word).filter { $0 != .hidePanel }
    }
}
