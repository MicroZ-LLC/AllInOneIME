import Foundation

extension InputSession {
    /// What `.` `,` `:` read of the field: the selection's range and the character before the caret (one substring call:
    /// never the text around it, which a field that tells no length reads in many calls, each a wait on a slow app);
    /// only the caret's range in a terminal or password manager, where the field's text stays in the app.
    func digitPunctuationWants(for key: KeyEvent, context: FieldContext) -> FieldContext.Parts {
        guard composer.input == .language(.chinese), !composer.isComposing,
              [".", ",", ":"].contains(key.printableText ?? ""), !(context.field ?? field).secure else { return [] }
        return (context.field ?? field).textStaysHere ? [.selectedRange] : [.selectedRange, .beforeCaret]
    }

    /// The composer's command trigger keeps its existing typed-word rule; digit punctuation reads field text first.
    func characterBeforeCaret() -> Character? {
        keyContext.flatMap { characterBeforeCaret(in: $0) }
    }

    func characterBeforeCaret(in context: FieldContext) -> Character? {
        if [".", ",", ":"].contains(keyBeingHandled?.printableText ?? "") {
            return characterBeforeDigitPunctuation(in: context)
        }
        guard let typed = remembered(lastTyped.character) else { return nil }
        guard !(context.field ?? field).textStaysHere, context.read.contains(.beforeCaret) else { return typed }
        switch context.beforeCaret {
        case .unknown: return typed
        case .nothing: return nil
        case let .text(before): return before == String(typed) ? typed : nil
        }
    }

    private func characterBeforeDigitPunctuation(in context: FieldContext) -> Character? {
        if context.selectedRange?.isEmpty == false { return nil }
        if context.read.contains(.beforeCaret), context.beforeCaret == .nothing { return nil }
        if !(context.field ?? field).textStaysHere, context.read.contains(.text), let text = context.text {
            return text.before.last
        }
        if !(context.field ?? field).textStaysHere, case let .text(before) = context.beforeCaret,
           context.read.contains(.beforeCaret) { return before.last }
        return remembered(lastTyped.fieldCharacter)
    }

    private func remembered(_ character: Character?) -> Character? {
        guard let character, !caretMayHaveMoved(within: ProcessInfo.processInfo.systemUptime - lastTyped.time) else { return nil }
        return character
    }
}
