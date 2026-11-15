import Foundation
import AllInOneIMECore

/// What a shell reads of the field for the session (`FieldContext`), through the host's API alone (`HostField`): the
/// parts the session wants of a key (`InputSession.fieldWants`), as the Mac's input controller reads them, without
/// trusting what a host gets wrong: a length of 0 is no length told (Chromium's), and a host that reads only near the
/// caret (Chromium's 100 UTF-16 units) is read near it.
struct FieldReader {
    let field: HostField

    /// How far around the caret a host that reads only near it does (`HostProfile.substringReach`): a shell that got
    /// nothing reading further tries this near.
    static let nearCaret = 100

    /// What the field says, as the session wants it: asked again, given what was read, until it wants nothing more.
    func context(wants: (FieldContext) -> FieldContext.Parts) -> FieldContext {
        var context = FieldContext(field: FieldInfo(app: field.profile.app))
        while true {
            let missing = wants(context).subtracting(context.read)
            if missing.isEmpty { return context }
            read(missing, into: &context)
        }
    }

    /// What the field says when it is read outside a key (`SessionOutput.readField`, `readSelection`): whether it is
    /// secure, where the selection is and what it holds, the text around it.
    func everything() -> FieldContext {
        var context = FieldContext(field: FieldInfo(app: field.profile.app))
        read([.secure, .passwordField, .selectedRange, .selection, .text], into: &context)
        return context
    }

    func read(_ parts: FieldContext.Parts, into context: inout FieldContext) {
        if parts.contains(.secure) { context.secure = false }
        if parts.contains(.passwordField) {
            context.field?.secure = false
            context.passwordFieldUnknown = !field.profile.tellsPasswordField
        }
        if parts.contains(.selectedRange) { context.selectedRange = field.selectedRange() }
        if parts.contains(.selection) { context.selection = selection() }
        if parts.contains(.beforeCaret) { context.beforeCaret = beforeCaret() }
        if parts.contains(.text) { context.text = text(before: ReplyContext.Limits.fieldBefore, after: ReplyContext.Limits.fieldAfter) }
        context.read.formUnion(parts)
    }

    /// The selected text where the field tells it; nil: nothing selected, or not told.
    private func selection() -> Composer.Selection? {
        guard let range = field.selectedRange(), !range.isEmpty, let text = field.substring(range) else { return nil }
        return Composer.Selection(text: text, range: range)
    }

    /// What is right before the caret, as the Mac's input controller asks it.
    private func beforeCaret() -> FieldContext.BeforeCaret {
        guard let caret = field.selectedRange() else { return .unknown }
        guard caret.isEmpty, caret.lowerBound > 0 else { return .nothing }
        guard let before = field.substring(caret.lowerBound - 1..<caret.lowerBound) else { return .unknown }
        return .text(before)
    }

    /// The text around the caret (past the marked text or the selection), up to `before` characters before it and
    /// `after` after it; nil where the field tells none.
    func text(before: Int, after: Int) -> FieldText? {
        guard let selected = field.selectedRange() else { return nil }
        let around = field.markedRange() ?? selected
        let length = field.length()
        let start = around.lowerBound, end = around.upperBound
        // UTF-16 units, twice the characters: an emoji or a rare character takes two.
        let beforeText = textBefore(start, span: before * 2)
        let afterText = textAfter(end, span: after * 2, length: length)
        guard beforeText != nil || afterText != nil else { return nil }
        return FieldText(before: beforeText ?? "", after: afterText ?? "")
    }

    private func textBefore(_ start: Int, span: Int) -> String? {
        let reach = min(start, span)
        guard reach > 0 else { return "" }
        if let text = field.substring(start - reach..<start) { return text }
        guard reach > Self.nearCaret else { return nil }
        return field.substring(start - Self.nearCaret..<start)
    }

    /// With no length told, the longest run after the caret the host reads (it tells nil past the end), near it.
    private func textAfter(_ end: Int, span: Int, length: Int) -> String? {
        if length > 0 {
            let count = min(span, max(length - end, 0))
            return count > 0 ? field.substring(end..<end + count) : ""
        }
        var (shortest, longest) = (0, min(span, Self.nearCaret))
        var found: String? = nil
        while shortest < longest {
            let middle = (shortest + longest + 1) / 2
            if let text = field.substring(end..<end + middle) {
                (shortest, found) = (middle, text)
            } else {
                longest = middle - 1
            }
        }
        return found ?? (shortest == 0 ? "" : nil)
    }
}
