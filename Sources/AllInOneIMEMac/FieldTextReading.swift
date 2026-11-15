import AllInOneIMECore
import Foundation

/// The text around the caret, read from what a field tells the input method (IMK's `length()`, `selectedRange()`,
/// `markedRange()` and `attributedSubstring(from:)`, `substring` here): up to `before` characters before the caret (or the
/// marked text, or the selection) and `after` after it. Nil: the field's text can't be read.
public enum FieldTextReading {
    /// What the field told: IMK's `length()`, `selectedRange()` and `markedRange()`, as they came.
    public struct Signals: Equatable, Sendable {
        public var length: Int
        public var selected: NSRange
        public var marked: NSRange

        public init(length: Int, selected: NSRange, marked: NSRange = NSRange(location: NSNotFound, length: 0)) {
            (self.length, self.selected, self.marked) = (length, selected, marked)
        }
    }

    public static func read(_ signals: Signals, before beforeLimit: Int, after afterLimit: Int,
                            substring: (NSRange) -> String?) -> FieldText? {
        let length = signals.length
        guard length > 0, length != NSNotFound else { return nil }
        let (marked, selected) = (signals.marked, signals.selected)
        let around: NSRange
        if marked.location != NSNotFound, marked.length > 0 {
            around = marked
        } else if selected.location != NSNotFound, selected.length != NSNotFound {
            around = selected
        } else {
            return nil
        }
        // UTF-16 units, twice the characters kept: an emoji or a rare character takes two.
        let (span, afterSpan) = (beforeLimit * 2, afterLimit * 2)
        let start = min(around.location, length)
        let end = min(NSMaxRange(around), length)
        let beforeRange = NSRange(location: max(0, start - span), length: start - max(0, start - span))
        let afterRange = NSRange(location: end, length: min(afterSpan, length - end))
        let before = beforeRange.length > 0 ? substring(beforeRange) ?? "" : ""
        let after = afterRange.length > 0 ? substring(afterRange) ?? "" : ""
        guard !before.isEmpty || !after.isEmpty else { return nil }
        return FieldText(before: before, after: after)
    }
}
