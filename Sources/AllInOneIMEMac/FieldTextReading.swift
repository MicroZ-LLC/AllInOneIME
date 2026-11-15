import AllInOneIMECore
import Foundation

/// The text around the caret, read from what a field tells the input method (IMK's `length()`, `selectedRange()`,
/// `markedRange()` and `attributedSubstring(from:)`, `substring` here): up to `before` characters before the caret (or the
/// marked text, or the selection) and `after` after it.
///
/// Empty (both empty) is a field read with nothing around the caret; nil, one whose text can't be read, where
/// autocomplete goes by what was typed into it (`FieldContext.text`). What fields told on a real Mac (2026-11-14): an
/// empty NSTextView, and one its app cleared (a chat app's, once its message is sent), length 0 and the caret at 0;
/// Chromium (Brave, Slack) and Qt tell length 0 whatever their text (they don't implement `attributedString()`), the
/// caret where it is, and read their text back up to it; a field that can't be read tells length 0 and either no caret
/// or one past its length, and reads nothing back; an app with no text field focused, length 2147483647 and no caret.
public enum FieldTextReading {
    /// What the field told: IMK's `length()`, `selectedRange()` and `markedRange()`, as they came.
    public struct Signals: Equatable, Sendable {
        public var length: Int
        public var selected: NSRange
        public var marked: NSRange

        public init(length: Int, selected: NSRange, marked: NSRange = NSRange(location: NSNotFound, length: 0)) {
            (self.length, self.selected, self.marked) = (length, selected, marked)
        }

        /// The length where one is told: not 0 (Chromium's and Qt's, whatever their text), NSNotFound, or 2147483647
        /// (an app with no text field focused).
        var toldLength: Int? { length > 0 && length != NSNotFound && length < Int(Int32.max) ? length : nil }
    }

    public static func read(_ signals: Signals, before beforeLimit: Int, after afterLimit: Int,
                            substring: (NSRange) -> String?) -> FieldText? {
        let (marked, selected) = (signals.marked, signals.selected)
        let around: NSRange
        if marked.location != NSNotFound, marked.length > 0, marked.length != NSNotFound {
            around = marked
        } else if selected.location != NSNotFound, selected.length != NSNotFound {
            around = selected
        } else {
            return nil  // no caret: a field of its own drawing (a game), or no text field at all
        }
        // UTF-16 units, twice the characters kept: an emoji or a rare character takes two.
        let (span, afterSpan) = (beforeLimit * 2, afterLimit * 2)
        guard let length = signals.toldLength else {
            return readToTheCaret(around.location, end: NSMaxRange(around), span: span, afterSpan: afterSpan,
                                  substring: substring)
        }
        let start = min(around.location, length)
        let end = min(NSMaxRange(around), length)
        let beforeRange = NSRange(location: max(0, start - span), length: start - max(0, start - span))
        let afterRange = NSRange(location: end, length: min(afterSpan, length - end))
        let before = beforeRange.length > 0 ? substring(beforeRange) : ""
        let after = afterRange.length > 0 ? substring(afterRange) : ""
        // Text it says it has, and none of it read back: it can't be read. Nothing around the caret (only marked text, all
        // of it selected): read, and empty.
        let readBack = (beforeRange.length > 0 && before != nil) || (afterRange.length > 0 && after != nil)
        guard readBack || (beforeRange.length == 0 && afterRange.length == 0) else { return nil }
        return FieldText(before: before ?? "", after: after ?? "")
    }

    /// A field that tells no length: what is before the caret (or the marked text, or the selection), read up to it, and
    /// what is after its `end`, as far as it reads
    /// back (where its text ends isn't told: Chromium reads nil for a range past its end). The caret at the start and
    /// nothing after it: empty. Nothing read back before a caret past the start: it can't be read.
    static func readToTheCaret(_ caret: Int, end: Int, span: Int, afterSpan: Int,
                               substring: (NSRange) -> String?) -> FieldText? {
        let after = readAfter(end, span: afterSpan, substring: substring)
        guard caret > 0 else { return FieldText(before: "", after: after) }
        let from = max(0, caret - span)
        guard let before = substring(NSRange(location: from, length: caret - from)), !before.isEmpty else { return nil }
        return FieldText(before: before, after: after)
    }

    /// The text after the caret in a field that tells no length: the longest range up to `span` that reads back, halving
    /// it until one does (a range past the end reads nil). Editing inside a line keeps its rest, so autocomplete, which
    /// asks only at the end of a line, doesn't take it for the end.
    static func readAfter(_ caret: Int, span: Int, substring: (NSRange) -> String?) -> String {
        guard span > 0, let first = substring(NSRange(location: caret, length: 1)), !first.isEmpty else { return "" }
        var length = span
        while length > 1 {
            if let text = substring(NSRange(location: caret, length: length)), !text.isEmpty { return text }
            length /= 2
        }
        return first
    }
}
