import Foundation

extension ModifierRoles {
    /// With a digit, picks a numbered choice: one @'s rows, where a conversation can go on (`Composer.handleNumberedPick`).
    /// Option on the Mac, Alt on Windows: apps take ⌘ (Ctrl) and a digit for their own menus (a browser's first tab)
    /// before an input method sees it, while ⌥ and a digit reaches it in every app.
    public var pick: Key.ModifierKind { .option }
}

extension KeyEvent {
    /// The digit of the key by where it is (`usage`): the digit row's 1 … 9 and 0, the keypad's too; nil for another
    /// key. ⌥ and a digit types something else on each layout (¡, ™ …), so it is read from the key, not its text.
    public var placeDigit: Int? {
        switch usage {
        case 0x1E...0x26: return Int(usage - 0x1E) + 1  // 1 … 9
        case 0x27, 0x62: return 0
        case 0x59...0x61: return Int(usage - 0x59) + 1  // the keypad's 1 … 9
        default: return nil
        }
    }
}

extension Composer {
    /// ⌥1 … ⌥9 (Alt on Windows: `ModifierRoles.pick` alone, Caps Lock ignored) pick a numbered choice shown, the n-th:
    /// one @'s rows (`PanelPresenter`'s labels, by place among the rows shown), done as a click on the row does it
    /// (`choose(index:)`), and where a conversation can go on (`handOff(digit:)`). A number with nothing shown at it does
    /// nothing, the key taken all the same. Digits alone are the text's in one @ (`@1+2`, `@base64`) or pick a pinyin
    /// candidate. Read before a dead key would wait (⌥ and a digit is one on some layouts). Nil: no numbered choices
    /// shown, or not such a key: it acts as usual (⌥ and a digit types its character).
    func handleNumberedPick(_ event: KeyEvent) -> Response? {
        guard event.modifiers.subtracting([.capsLock]).subtracting(Modifiers.sides) == Modifiers.kind(modifierRoles.pick),
              let digit = event.placeDigit else { return nil }
        if isQuestionChat, phase == .choosing, showsHandoff { return .consumed(digit >= 1 ? handOff(digit: digit) : []) }
        guard oneAt != nil else { return nil }
        guard digit >= 1, digit <= oneAtVisible.count else { return .consumed() }
        return .consumed(choose(index: digit - 1))
    }
}
