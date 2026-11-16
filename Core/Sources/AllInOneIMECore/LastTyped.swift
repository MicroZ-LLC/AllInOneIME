import Foundation

/// The last character the user typed straight into the text field: a key the input method let through that types one,
/// or one whose character went in with what the input method inserted for it (a terminal gets "@x" in one piece). A
/// terminal tells nothing of its text, so this is how an "@" right after a word ("ssh user@host") is known there
/// (`Composer.characterBeforeCaret`). Not known after any other key (an arrow, ⌫, ⏎, a shortcut), after text the input
/// method inserted (a result, a conversion, a draft as typed: no word being typed; Code's word held, though, is what was
/// typed: `typedIn`), nor in another text field.
public struct LastTyped: Equatable, Sendable {
    public private(set) var character: Character?
    /// The field's last ASCII digit, including one committed by the input method for a different key.
    public private(set) var fieldCharacter: Character?
    /// When it was typed (`ProcessInfo.systemUptime`): a click since may have moved the caret.
    public private(set) var time: TimeInterval = 0

    public init() {}

    /// `key` was answered: it went on to the app (`passedOn`), and `inserted` is the last text the input method put in
    /// during it (nil: none). A committed digit is kept even when a candidate key did not itself type that digit.
    public mutating func answered(_ key: KeyEvent, passedOn: Bool, inserted: String?, at time: TimeInterval) {
        let typed = key.printableText
        if passedOn {
            (character, fieldCharacter, self.time) = (typed?.last, Self.asciiDigit(typed), time)
        } else if let inserted {
            // What went in ends with the key's character: typed. Else it was a result or a conversion.
            character = typed.flatMap { inserted.hasSuffix($0) ? $0.last : nil }
            (fieldCharacter, self.time) = (Self.asciiDigit(inserted), time)
        }
        // Taken by the input method with nothing inserted (pinyin, a move in the list): the field is as it was.
    }

    /// The input method inserted text outside a key (a click on a result, dictation, after a key), or another text field.
    public mutating func forget() { character = nil; fieldCharacter = nil }

    /// Text inserted without a pass-through key is useful only when its last character is an ASCII digit.
    public mutating func committed(_ text: String, at time: TimeInterval) {
        (character, fieldCharacter, self.time) = (nil, Self.asciiDigit(text), time)
    }

    private static func asciiDigit(_ text: String?) -> Character? {
        guard let last = text?.last, last >= "0", last <= "9" else { return nil }
        return last
    }

    /// What the user typed went in at `time` without the key that typed it: Code's word held as marked text, put in as
    /// typed (→ or Esc on its rows, decision 33). Its last character is the last one typed.
    public mutating func typedIn(_ text: String, at time: TimeInterval) {
        guard let last = text.last else { return }
        (character, fieldCharacter, self.time) = (last, Self.asciiDigit(text), time)
    }
}
