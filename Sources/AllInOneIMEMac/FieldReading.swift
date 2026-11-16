import AllInOneIMECore
import AppKit
import InputMethodKit
import os

/// The input method's log (its subsystem and category: `log stream --predicate 'subsystem ==
/// "com.allinoneime.inputmethod.AllInOneIME"'`), for what this library says of the field it reads: how much and how,
/// never the text.
let fieldLog = Logger(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")

/// What the field a key or a modifier change comes from says around the caret, read through IMK (the text input
/// protocol, `IMKTextInput`): only the parts the session wants (`FieldContext.Parts`, its `fieldWants` given what was
/// read so far). What only the input method's process can tell (secure input, Accessibility, the apps it knows) comes
/// from it as closures; a test's field (an `IMKTextInput` of its own) is read by the same code as an app's.
@MainActor
public struct FieldReading {
    /// Whether an app (a bundle id) is a terminal, which runs every line it is given.
    public var isTerminal: (String?) -> Bool
    /// Secure input is on, whoever has it: nothing of the field's text is read then.
    public var secureInputActive: () -> Bool
    /// Nothing is composed in the field (secure input on for its app: the input method's `SecureInput.blocksComposing`).
    public var blocksComposing: (IMKTextInput?) -> Bool
    /// Whether the focused element is a password field, as Accessibility tells it (nil: it can't tell).
    public var passwordField: () -> Bool?
    /// Whether a selection the field didn't tell may be there all the same, for Accessibility to read after the key
    /// (`FieldContext.selectionFollows`), given whether the field's app is built on Chromium or Electron; nil: the
    /// selection is never read with Accessibility (the self-test: it would read the user's own frontmost app).
    public var selectionMayBeUntold: ((IMKTextInput?, _ chromium: Bool) -> Bool)?
    /// Whether an app (a bundle id) is built on Chromium or Electron (`ChromiumApps`).
    public var chromiumApp: (String?) -> Bool
    /// What the field reported of the marked text when it was set (`MarkedTextWatch`), and the marked text the composer
    /// has now (asked only where the session wants to know whether the app took it).
    public var markedWatch: MarkedTextWatch
    public var markedText: () -> String

    public init(isTerminal: @escaping (String?) -> Bool, secureInputActive: @escaping () -> Bool,
                blocksComposing: @escaping (IMKTextInput?) -> Bool = { _ in false }, passwordField: @escaping () -> Bool? = { false },
                selectionMayBeUntold: ((IMKTextInput?, _ chromium: Bool) -> Bool)? = nil,
                chromiumApp: @escaping (String?) -> Bool = { _ in false },
                markedWatch: MarkedTextWatch = MarkedTextWatch(), markedText: @escaping () -> String = { "" }) {
        self.isTerminal = isTerminal
        self.secureInputActive = secureInputActive
        self.blocksComposing = blocksComposing
        self.passwordField = passwordField
        self.selectionMayBeUntold = selectionMayBeUntold
        self.chromiumApp = chromiumApp
        self.markedWatch = markedWatch
        self.markedText = markedText
    }

    /// The longest selection read, in UTF-16 units: a longer one isn't read (the command is then marked in the field as
    /// without one, and replaces it, as typing over a selection does). Up to `Composer.maxSelectionLength` characters a
    /// command takes it; longer, it's left as it is.
    nonisolated public static let maxSelection = 50_000

    /// What the field says around the caret as a key goes down or a modifier changes: what the session wants of it
    /// (`wants`, its `fieldWants` given what was read so far), asked again until it wants nothing more.
    public func context(in target: IMKTextInput?, wants: (FieldContext) -> FieldContext.Parts) -> FieldContext {
        var context = FieldContext(field: Self.fieldInfo(target, isTerminal: isTerminal))
        while true {
            let missing = wants(context).subtracting(context.read)
            if missing.isEmpty { return context }
            read(missing, of: target, into: &context)
        }
    }

    /// Reads `parts` of what the field says (`FieldContext`). Password fields and prompts turn on secure event input: the
    /// session composes nothing in the app that turned it on. A password field that doesn't is told by Accessibility
    /// (`passwordField`, unknown where it can't tell), asked only when the session wants it: once a field, where
    /// suggestions may show (for the English words learned it's asked off the key, `SessionOutput.readPasswordField`).
    /// The selection the field tells (`selection(in:)`; only how long it is is logged), else whether Accessibility may
    /// tell one after the key; the character before the caret, where "@" is typed; the text around the caret for
    /// `@reply`, or a snippet of more than one line put in (`FieldTextReading`), never in a field told to be a password
    /// field (the session doesn't ask for it in one it knows: `InputSession.nothingLeavesDevice`).
    public func read(_ parts: FieldContext.Parts, of target: IMKTextInput?, into context: inout FieldContext) {
        if parts.contains(.secure) { context.secure = blocksComposing(target) }
        if parts.contains(.passwordField), !context.secure {
            let told = passwordField()
            context.field?.secure = told == true
            context.passwordFieldUnknown = told == nil
        }
        if parts.contains(.markedText), let target {
            context.markedTextTaken = markedWatch.appTookText(expected: markedText(), reportedLength: Self.markedLength(target))
        }
        if parts.contains(.selectedRange) { context.selectedRange = target.flatMap { Self.range($0.selectedRange()) } }
        if parts.contains(.selection) {
            // What the field tells, at once; what only Accessibility can tell is read after the key, off this thread
            // (`SessionOutput.readSelection`): the "@" list shows on the key meanwhile.
            if let read = Self.selection(in: target) {
                fieldLog.notice("selection read (IMK, \(read.text.count) characters)")
                context.selection = Composer.Selection(text: read.text, range: read.range.location..<NSMaxRange(read.range))
            } else if let selectionMayBeUntold {
                context.selectionFollows = selectionMayBeUntold(target, chromiumApp(context.field?.app))
            }
        }
        if parts.contains(.beforeCaret) { context.beforeCaret = Self.beforeCaret(in: target) }
        if parts.contains(.text), context.field?.secure != true {
            context.text = FieldTextReading.read(from: target, before: ReplyContext.Limits.fieldBefore, after: ReplyContext.Limits.fieldAfter,
                                                 purpose: "a key (@reply, a snippet's indentation)",
                                                 secureInputActive: secureInputActive, isTerminal: isTerminal)
        }
        context.read.formUnion(parts)
    }

    /// What the field says once typing pauses (`SessionOutput.readField`: autocomplete's read, and Code's words for an
    /// `id` below 0), read on the run loop's next turn after the key that asked: secure input, whether it is a password
    /// field, and, in neither, the selection and the text around the caret.
    public func contextAfterPause(in target: IMKTextInput?, id: Int) -> FieldContext {
        var context = FieldContext(read: [.secure], field: Self.fieldInfo(target, isTerminal: isTerminal))
        context.secure = blocksComposing(target) || secureInputActive()
        if !context.secure {
            // Told for suggestions too (`FieldContext.Parts.passwordField`): both go by the same answer.
            let told = passwordField()
            context.field?.secure = told == true
            context.passwordFieldUnknown = told == nil
            context.read.insert(.passwordField)
        }
        if !context.secure, context.field?.secure != true {
            context.selectedRange = target.flatMap { Self.range($0.selectedRange()) }
            context.text = id < 0
                ? FieldTextReading.read(from: target, before: ReplyContext.Limits.fieldBefore, after: ReplyContext.Limits.fieldAfter,
                                        purpose: "Code's words", secureInputActive: secureInputActive, isTerminal: isTerminal)
                : FieldTextReading.read(from: target, before: Autocomplete.beforeLimit, after: Autocomplete.afterLimit,
                                        purpose: "autocomplete", secureInputActive: secureInputActive, isTerminal: isTerminal)
            context.read.formUnion([.selectedRange, .text])
        }
        return context
    }

    /// The field a key or a modifier change comes from (its app asked of the client once).
    nonisolated public static func fieldInfo(_ client: IMKTextInput?, isTerminal: (String?) -> Bool) -> FieldInfo {
        let app = client?.bundleIdentifier()
        return FieldInfo(app: app, terminal: isTerminal(app))
    }

    /// `range` as UTF-16 offsets; nil for a field that tells none.
    nonisolated public static func range(_ range: NSRange) -> Range<Int>? {
        range.location == NSNotFound || range.length == NSNotFound ? nil : range.location..<NSMaxRange(range)
    }

    /// The length of the app's marked text, or nil when it reports none.
    nonisolated public static func markedLength(_ client: IMKTextInput) -> Int? {
        let range = client.markedRange()
        return range.location == NSNotFound ? nil : range.length
    }

    /// What is right before the caret, as `target` tells it (`FieldContext.BeforeCaret`).
    nonisolated public static func beforeCaret(in target: IMKTextInput?) -> FieldContext.BeforeCaret {
        guard let target else { return .unknown }
        let caret = target.selectedRange()
        guard caret.location != NSNotFound else { return .unknown }  // a field that tells no caret
        guard caret.length == 0, caret.location > 0 else { return .nothing }  // a selection (a command may work on it), the start
        guard let before = target.attributedSubstring(from: NSRange(location: caret.location - 1, length: 1))?.string else {
            return .unknown  // a field that reads nothing back
        }
        return .text(before)
    }

    /// The text selected in `client`'s field and its range, as the text input protocol tells them: the client's
    /// `selectedRange()` and the text in it (`attributedSubstring`), which Cocoa (NSTextView), WebKit and most fields
    /// answer (Chromium and Electron apps often report none: the input method reads Accessibility's then, after the key).
    /// Nil when there is none, it can't be read, or it is longer than `maxSelection`. Only how long it is is logged.
    nonisolated public static func selection(in client: IMKTextInput?) -> (text: String, range: NSRange)? {
        guard let client else { return nil }
        let range = client.selectedRange()
        // Our own marked text isn't a selection (a draft is never pending here, but a field may still report one).
        let marked = client.markedRange()
        let markedNow = marked.location != NSNotFound && marked.length > 0
        guard range.location != NSNotFound, range.length != NSNotFound, range.length > 0, !markedNow else { return nil }
        guard range.length <= maxSelection else {
            fieldLog.notice("selection not read: \(range.length) UTF-16 units, more than \(maxSelection)")
            return nil
        }
        guard let text = client.attributedSubstring(from: range)?.string, !text.isEmpty else { return nil }
        return (text, range)
    }
}

/// The text around the caret in a field, as it tells it through IMK (`FieldText`: `@reply`'s context, autocomplete's,
/// Code's words, a snippet's indentation).
extension FieldTextReading {
    /// The text around the caret, up to `before` characters before it and `after` after it, for `purpose` (the log's),
    /// without the draft: past the selection or the marked text (`read(_:before:after:substring:)`). None during secure
    /// input (`secureInputActive`) or in a terminal (its text isn't being edited). In a password manager it is read only
    /// for what stays on this Mac (Code's words, a snippet's indentation): the session never asks for it for `@reply`
    /// there (`InputSession.fieldWants`, `FieldInfo.textStaysHere`).
    @MainActor
    public static func read(from target: IMKTextInput?, before beforeLimit: Int, after afterLimit: Int, purpose: String,
                            secureInputActive: () -> Bool, isTerminal: (String?) -> Bool) -> FieldText? {
        guard !secureInputActive(), let target, !isTerminal(target.bundleIdentifier()) else { return nil }
        let signals = Signals(length: target.length(), selected: target.selectedRange(), marked: target.markedRange())
        guard let text = read(signals, before: beforeLimit, after: afterLimit,
                              substring: { target.attributedSubstring(from: $0)?.string }) else {
            // Lengths only: what it told, for a field that turns out unreadable where it shouldn't.
            let caret = signals.selected.location == NSNotFound ? "none" : String(signals.selected.location)
            fieldLog.notice("field text can't be read for \(purpose, privacy: .public) (length \(signals.length), caret \(caret, privacy: .public))")
            return nil
        }
        fieldLog.notice("field text read for \(purpose, privacy: .public) (\(text.before.count) + \(text.after.count) characters)")
        return text
    }
}
