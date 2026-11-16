import AllInOneIMECore
import AppKit
import InputMethodKit

/// The text field a result is typed into, for `TypeOut.Typist`, through IMK. Into a terminal, line breaks, tabs and
/// other control characters (`Composer.actsInTerminal`) are kept for pasting (the input method's `TerminalPaste`), in
/// order, not typed.
public final class TypingField: TypeOut.Field {
    public let client: IMKTextInput
    public let pastesControls: Bool
    /// What is to be pasted before typing goes on: a line break as "\n" (the Mac pastes by "\n"), the others as they are.
    public var toPaste: [String] = []

    public init(_ client: IMKTextInput, pastesControls: Bool) {
        self.client = client
        self.pastesControls = pastesControls
    }

    public var caret: Int? {
        let range = client.selectedRange()
        return range.location != NSNotFound && range.length == 0 ? range.location : nil
    }

    public var length: Int? {
        let length = client.length()
        return length >= 0 && length != NSNotFound ? length : nil
    }

    public func read(_ range: NSRange) -> String? { client.attributedSubstring(from: range)?.string }

    public func type(_ text: String) {
        if pastesControls, let character = text.first, text.count == 1, Composer.actsInTerminal(text) {
            toPaste.append(character.isNewline ? "\n" : text)
        } else {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
    }

    public func replace(_ range: NSRange, with text: String) { client.insertText(text, replacementRange: range) }
}
