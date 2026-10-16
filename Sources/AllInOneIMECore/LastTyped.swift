import Foundation

/// The last character the user typed straight into the text field: a key the input method let through that types one,
/// or one whose character went in with what the input method inserted for it (a terminal gets "@x" in one piece). A
/// terminal tells nothing of its text, so this is how an "@" right after a word ("ssh user@host") is known there
/// (`Composer.characterBeforeCaret`). Not known after any other key (an arrow, ⌫, ⏎, a shortcut), after text the input
/// method inserted (a result, a conversion, a draft as typed: no word being typed), nor in another text field.
public struct LastTyped: Equatable, Sendable {
    public private(set) var character: Character?
    /// When it was typed (`ProcessInfo.systemUptime`): a click since may have moved the caret.
    public private(set) var time: TimeInterval = 0

    public init() {}

    /// `key` was answered: it went on to the app (`passedOn`), and `inserted` is the last text the input method put in
    /// during it (nil: none).
    public mutating func answered(_ key: KeyEvent, passedOn: Bool, inserted: String?, at time: TimeInterval) {
        let typed = key.printableText
        if passedOn {
            (character, self.time) = (typed?.last, time)  // the app types it; a key without a character may move the caret
        } else if let inserted {
            // What went in ends with the key's character: typed. Else a result, a conversion, the draft as typed.
            (character, self.time) = (typed.flatMap { inserted.hasSuffix($0) ? $0.last : nil }, time)
        }
        // Taken by the input method with nothing inserted (pinyin, a move in the list): the field is as it was.
    }

    /// The input method inserted text outside a key (a click on a result, dictation, after a key), or another text field.
    public mutating func forget() { character = nil }
}
