import Foundation

extension Composer {
    /// In idle Chinese pinyin, a digit already in the field starts a number, time or grouped quantity.
    func handleDigitPunctuation(_ event: KeyEvent, composing: Bool) -> Response? {
        guard !composing, draft.isEmpty, !isLevelTwo, voice == .off,
              input == .language(.chinese), !typesZhuyin,
              event.modifiers.subtracting([.capsLock, .shift]).subtracting(.sides).isEmpty,
              let mark = event.printableText, [".", ",", ":"].contains(mark),
              let before = characterBeforeCaret(), before >= "0", before <= "9" else { return nil }
        return .consumed([.commit(mark)])
    }
}
