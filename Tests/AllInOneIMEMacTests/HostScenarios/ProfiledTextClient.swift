import AppKit
import InputMethodKit

/// A host's kind of text field, as the host scenario contract (v1) has them: what each tells the input method through
/// IMK, and what it does with the marked text on a click or when it loses the focus.
enum HostProfile: String, CaseIterable, Sendable, CustomStringConvertible {
    /// NSTextView: the real length, document-wide offsets, a real caret rectangle; a click outside the marked text gets
    /// commitComposition.
    case nstextview
    /// Chromium: length() 0, a real selectedRange, substrings only within caret ±100 UTF-16 units (nil past the end),
    /// the old ranges during a key, every modifier change and unhandled key down twice (the copy 5–20 ms later, the same
    /// timestamp), a click finishes the composition itself, and so does losing the focus (then it cancels it).
    case chromium
    /// Chromium, with the copies 100 ms or more late, after the next change.
    case electron
    /// A terminal or WeChat: no selection (NotFound), length 0, no text, a fixed caret rectangle.
    case tellsnothing

    var description: String { rawValue }

    /// The app it imitates (none of them a terminal: the input method's list of terminals is the app's).
    var app: String {
        switch self {
        case .nstextview: "com.apple.TextEdit"
        case .chromium: "com.google.Chrome"
        case .electron: "com.tinyspeck.slackmacgap"
        case .tellsnothing: "com.tencent.xinWeChat"
        }
    }

    var isChromium: Bool { self == .chromium || self == .electron }
}

/// A text field as `HostProfile`'s host has it, at the IMK level (`IMKTextInput`), for the input method's reading and
/// anchoring code (`FieldReading`, `FieldTextReading`, `FieldAnchor`, `TypingField`). Its text is held as NSTextView
/// holds it: the marked text is part of it, at `marked`; `doc` is the text without it. Every call through IMK is counted
/// (`calls`). What the host does on its own (a click, the app typing a key the input method left it, losing the focus,
/// emptying the field) is `click`, `appTypes`, `resign`, `clear` and the others below, never through IMK.
final class ProfiledTextClient: NSObject, IMKTextInput {
    let profile: HostProfile

    /// What the host has: all of its text (with the marked text), the selection (the caret: length 0), the marked range.
    struct State: Equatable {
        var text = ""
        var selection = NSRange(location: 0, length: 0)
        var marked: NSRange?
    }

    private(set) var state = State()
    /// Chromium's view during a key (`beginTurn`): the ranges and text as they were when the key came.
    private var stale: State?
    /// Undo's states, the latest last (⌘Z), one per change the host made.
    private var undoStack: [State] = []
    /// The field has the focus: what the input method inserts or marks goes in (a resigned page drops it; a closed window
    /// has nothing to put it in).
    var focused = true
    /// Chromium's view after its page emptied the field mid-composition: the marked range it last had, told still (the
    /// page tells it nothing; a real Brave, 2026-11-15), until the input method marks or inserts again.
    private var leftoverMarked: NSRange?
    /// The calls through IMK since `resetCalls`, by name.
    private(set) var calls: [String: Int] = [:]

    /// One screen, a window on it, the field's first line in it, a character 8 points wide.
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let window = CGRect(x: 100, y: 80, width: 1200, height: 780)
    static let lineOrigin = CGPoint(x: 160, y: 600)
    static let characterWidth: CGFloat = 8, lineHeight: CGFloat = 18
    /// Where a terminal or WeChat tells its caret, whatever the text.
    static let fixedCaret = CGRect(x: 300, y: 300, width: 1, height: 18)

    init(_ profile: HostProfile, text: String = "", selection: NSRange? = nil, marked: NSRange? = nil) {
        self.profile = profile
        super.init()
        state = State(text: text, selection: selection ?? NSRange(location: (text as NSString).length, length: 0), marked: marked)
    }

    // MARK: What the host shows

    /// The field's text without the marked text.
    var doc: String {
        guard let marked = state.marked else { return state.text }
        return (state.text as NSString).replacingCharacters(in: marked, with: "")
    }

    /// The marked text in the field (nil: none).
    var markedText: String? {
        state.marked.map { (state.text as NSString).substring(with: $0) }
    }

    func resetCalls() { calls = [:] }

    private func count(_ name: String) { calls[name, default: 0] += 1 }

    // MARK: Turns (Chromium's stale ranges)

    /// A key comes: until `endTurn`, Chromium's view tells the ranges and text as they are now.
    func beginTurn() {
        if profile.isChromium { stale = state }
    }

    /// The run loop's next turn: Chromium's view tells what it has now.
    func endTurn() { stale = nil }

    /// What the field tells through IMK now: Chromium's old view during a key.
    private var told: State { stale ?? state }

    // MARK: IMKTextInput

    func insertText(_ string: Any!, replacementRange: NSRange) {
        count("insertText")
        leftoverMarked = nil
        guard focused else { return }
        let text = Self.plain(string)
        let range: NSRange
        if replacementRange.location != NSNotFound {
            // A range of the text in place: the marked text there or not, it is plain text now.
            guard NSMaxRange(replacementRange) <= length(of: state) else { return }
            range = replacementRange
        } else {
            range = state.marked ?? state.selection
        }
        change { state in
            state.text = (state.text as NSString).replacingCharacters(in: range, with: text)
            state.marked = nil
            state.selection = NSRange(location: range.location + (text as NSString).length, length: 0)
        }
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        count("setMarkedText")
        leftoverMarked = nil
        guard focused else { return }
        let text = Self.plain(string)
        let range: NSRange
        if replacementRange.location != NSNotFound {
            guard NSMaxRange(replacementRange) <= length(of: state) else { return }
            range = replacementRange
        } else {
            range = state.marked ?? state.selection
        }
        let length = (text as NSString).length
        change { state in
            state.text = (state.text as NSString).replacingCharacters(in: range, with: text)
            if length == 0 {
                state.marked = nil
                state.selection = NSRange(location: range.location, length: 0)
            } else {
                state.marked = NSRange(location: range.location, length: length)
                let at = min(max(selectionRange.location, 0), length)
                state.selection = NSRange(location: range.location + at, length: min(selectionRange.length, length - at))
            }
        }
    }

    func selectedRange() -> NSRange {
        count("selectedRange")
        return profile == .tellsnothing ? NSRange(location: NSNotFound, length: NSNotFound) : told.selection
    }

    func markedRange() -> NSRange {
        count("markedRange")
        guard profile != .tellsnothing, let marked = told.marked ?? leftoverMarked else { return NSRange(location: NSNotFound, length: 0) }
        return marked
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        count("substring")
        return substring(range).map { NSAttributedString(string: $0) }
    }

    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        count("string")
        return substring(range)
    }

    func length() -> Int {
        count("length")
        return profile == .nstextview ? length(of: told) : 0
    }

    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }

    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        count("attributes")
        // The line the marked text (else the caret) is on, a line under it as InputMethodKit's own panels go.
        let at = told.marked?.location ?? told.selection.location
        let rect = caretRect(at: at)
        lineRect?.pointee = rect == .zero ? rect : CGRect(x: rect.minX, y: rect.minY - rect.height, width: 1, height: rect.height)
        return [:]
    }

    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
        count("firstRect")
        guard aRange.location != NSNotFound else { return .zero }
        let rect = caretRect(at: aRange.location)
        return rect == .zero ? rect : CGRect(x: rect.minX, y: rect.minY, width: Self.characterWidth * CGFloat(max(aRange.length, 0)),
                                             height: rect.height)
    }

    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }

    func bundleIdentifier() -> String! {
        count("bundleIdentifier")
        return profile.app
    }

    func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "host-scenario-\(profile.rawValue)" }

    // MARK: What each profile tells

    /// The text in `range` as the field tells it: NSTextView's within its text (cut at its end), Chromium's only within
    /// ±100 UTF-16 units of its caret (none past the end), none from a terminal or WeChat.
    private func substring(_ range: NSRange) -> String? {
        guard range.location != NSNotFound, range.length != NSNotFound, range.location >= 0, range.length >= 0 else { return nil }
        let view = told, total = length(of: view)
        switch profile {
        case .nstextview:
            guard range.location <= total else { return nil }
            let cut = NSRange(location: range.location, length: min(range.length, total - range.location))
            return (view.text as NSString).substring(with: cut)
        case .chromium, .electron:
            let caret = view.selection.location
            let window = NSRange(location: max(0, caret - 100), length: min(total, caret + 100) - max(0, caret - 100))
            guard range.location >= window.location, NSMaxRange(range) <= NSMaxRange(window) else { return nil }
            return (view.text as NSString).substring(with: range)
        case .tellsnothing:
            return nil
        }
    }

    /// Where the character at `index` is on the screen (AppKit's coordinates, one line): a terminal's or WeChat's fixed
    /// rectangle; Chromium's page corner before the page sent its bounds (the first key of a composition, nothing marked
    /// in its view yet), a rect at the window's top-left with no height.
    private func caretRect(at index: Int) -> CGRect {
        if profile == .tellsnothing { return Self.fixedCaret }
        if profile.isChromium, stale != nil, told.marked == nil {
            return CGRect(x: Self.window.minX, y: Self.window.maxY, width: 0, height: 0)
        }
        let at = min(max(index, 0), length(of: told))
        return CGRect(x: Self.lineOrigin.x + Self.characterWidth * CGFloat(at), y: Self.lineOrigin.y, width: 1, height: Self.lineHeight)
    }

    // MARK: What the host does on its own

    /// A click at `offset` of the field's text as shown (the marked text in it): the caret goes there.
    func moveCaret(to offset: Int) {
        let at = min(max(offset, 0), length(of: state))
        state.selection = NSRange(location: at, length: 0)
    }

    /// Whether `offset` is inside the marked text (a click there goes to the input method's marked text, as NSTextView
    /// hands it over).
    func isInsideMarkedText(_ offset: Int) -> Bool {
        guard let marked = state.marked else { return false }
        return offset >= marked.location && offset <= NSMaxRange(marked)
    }

    /// Chromium's `finishComposingText`: the marked text becomes plain text where it is, the caret after it; the input
    /// method isn't told.
    func finishComposingText() {
        guard let marked = state.marked else { return }
        change { state in
            state.marked = nil
            state.selection = NSRange(location: NSMaxRange(marked), length: 0)
        }
    }

    /// The field loses the focus: Chromium's page commits the marked text on blur (`finishComposingText`) and then drops
    /// what the input method sends; NSTextView, a terminal and WeChat take what the input method sends while it lets the
    /// field go, and lose the focus once it has (`deactivated`).
    func resign() {
        if profile.isChromium { finishComposingText() }
        focused = !profile.isChromium
    }

    /// The input method let the field go (`deactivateServer`): it has no focus now, whatever the host.
    func deactivated() { focused = false }

    /// The field has the focus again.
    func becomeFocused() { focused = true }

    /// The app empties the field (a chat app's send): its text, the marked text and all; the input method isn't told.
    func clear() {
        if profile.isChromium { leftoverMarked = state.marked }
        change { state in state = State() }
    }

    /// The app types `text` from a key the input method left it, in place of the selection.
    func appTypes(_ text: String) {
        guard focused else { return }
        let range = state.selection
        change { state in
            state.text = (state.text as NSString).replacingCharacters(in: range, with: text)
            state.selection = NSRange(location: range.location + (text as NSString).length, length: 0)
        }
    }

    /// The app's ⌫: the selection, else the character before the caret, whole (a surrogate pair, a letter with its marks).
    func appDeletesBackward() {
        guard focused else { return }
        let text = state.text as NSString
        var range = state.selection
        if range.length == 0 {
            guard range.location > 0 else { return }
            range = text.rangeOfComposedCharacterSequence(at: range.location - 1)
        }
        change { state in
            state.text = text.replacingCharacters(in: range, with: "")
            state.selection = NSRange(location: range.location, length: 0)
            if let marked = state.marked, NSMaxRange(marked) > (state.text as NSString).length { state.marked = nil }
        }
    }

    /// The app's ← and → (nothing selected after).
    func appMovesCaret(by delta: Int) {
        guard focused else { return }
        moveCaret(to: state.selection.location + delta)
    }

    /// The app's ⌘Z: the field's text as it was before its last change, marked text never coming back (what was being
    /// composed is no change of its own to undo).
    func undo() {
        guard focused else { return }
        let text = doc
        while let last = undoStack.popLast() {
            guard last.marked == nil, last.text != text else { continue }
            state = last
            return
        }
    }

    // MARK: Helpers

    private func change(_ body: (inout State) -> Void) {
        undoStack.append(state)
        body(&state)
    }

    private func length(of view: State) -> Int { (view.text as NSString).length }

    private static func plain(_ value: Any?) -> String {
        if let attributed = value as? NSAttributedString { return attributed.string }
        return value as? String ?? ""
    }
}
