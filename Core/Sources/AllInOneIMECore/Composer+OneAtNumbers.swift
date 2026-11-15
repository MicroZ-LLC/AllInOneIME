import Foundation

extension Composer {
    /// ⌘1 … ⌘7 on one @'s list (Ctrl+1 … on Windows: `ModifierRoles.primary`, alone): the row shown with that number
    /// (`PanelPresenter`'s labels, by place among the rows shown), done as a click on it does it (`choose(index:)`), the
    /// highlight on it first. A number with no row shown does nothing, the key taken all the same. Digits alone are the
    /// text's there (`@1+2`, `@base64`) or pick a pinyin candidate, and Shift with one types a symbol a sum needs (* ( )),
    /// so the rows are picked as a conversation's hand-off choices are (⌘1 …, `handleHandoffKey`). Nil: not one @'s.
    func handleOneAtNumberKey(_ event: KeyEvent) -> Response? {
        guard oneAt != nil, event.modifiers.subtracting(.capsLock) == Modifiers.kind(modifierRoles.primary),
              event.charactersIgnoringModifiers.count == 1, let digit = event.charactersIgnoringModifiers.first?.wholeNumberValue
        else { return nil }
        guard digit >= 1, digit <= oneAtVisible.count else { return .consumed() }
        return .consumed(choose(index: digit - 1))
    }
}
