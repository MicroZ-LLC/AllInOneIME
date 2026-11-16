import Foundation
import AllInOneIMECore
import AllInOneIMETestSupport

/// What the user and the app do to the field besides typing, as each profile's host does it.
extension HostRun {
    // MARK: The app

    /// `TEXT`: the app sets the field's text (the session isn't told): what it holds from now on.
    func setField(_ markup: FieldMarkup) {
        let text = markup.text as NSString
        host.document = markup.text
        host.selection = markup.selection
        host.caretOffset = markup.marked?.at ?? markup.caret ?? markup.selection?.lowerBound ?? text.length
        host.marked = markup.marked?.text ?? ""
        markedBySession = false
        ledger.reset(to: markup.text)
        undo = []
    }

    /// `APP clears`: the app empties the field on its own (a chat app's send) and drops its marked text (Chromium cancels
    /// the composition), the session not told: the core has no event for it; the shell learns of it at the next key, the
    /// marked text gone (`FieldContext.markedTextTaken`). Contract v1.3: the composition (in the panel only) may be kept.
    func appClears() {
        host.document = ""
        host.selection = nil
        host.caretOffset = 0
        host.marked = ""
        markedBySession = false
        ledger.reset(to: "")
        undo = []
    }

    /// The app's own handling of a key the input method let through (`typing`: one it has to type itself, the input
    /// source ABC: `FakeHost.appTypesKeys` types the others): text typed, ⌫ and ⌦, Return and Tab, the caret moved, ⌘A,
    /// ⌘Z.
    func appActs(on key: KeyEvent, typing: Bool) {
        let modifiers = key.modifiers.subtracting(.capsLock).subtracting(.sides)
        let command = modifiers.contains(.command)
        if command, key.charactersIgnoringModifiers.lowercased() == "z" { return undoLast() }
        if command, key.charactersIgnoringModifiers.lowercased() == "a" {
            host.selection = 0..<(host.document as NSString).length
            return
        }
        guard modifiers.isDisjoint(with: [.command, .control]) else { return }
        let before = (host.document, host.caret, ledger)
        switch key.key {
        case .backspace: delete(forward: false)
        case .forwardDelete: delete(forward: true)
        case .enter, .keypadEnter: appTypes("\n")
        case .tab: appTypes("\t")
        case .arrow(.left), .arrow(.up), .home: moveCaret(to: key.key == .arrow(.left) ? host.caret - 1 : 0)
        case .arrow(.right), .arrow(.down), .end:
            let end = (host.document as NSString).length
            moveCaret(to: key.key == .arrow(.right) ? (host.selection?.upperBound ?? host.caret) + 1 : end)
        case .character where typing, .space where typing:
            if let text = key.printableText { appTypes(text) }
        default:
            break
        }
        // A key the session had is remembered with what the session did (`deliverKey`).
        if typing { remember(before) }
    }

    private func appTypes(_ text: String) {
        let document = host.document as NSString
        let range = host.selection ?? host.caret..<host.caret
        ledger.take(document.substring(with: NSRange(location: range.lowerBound, length: range.count)))
        ledger.put(text)
        host.document = document.replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: text)
        host.selection = nil
        host.caretOffset = range.lowerBound + (text as NSString).length
    }

    private func delete(forward: Bool) {
        let document = host.document as NSString
        let caret = host.caret
        let range = host.selection.flatMap { $0.isEmpty ? nil : $0 }
            ?? (forward ? caret..<min(caret + 1, document.length) : max(caret - 1, 0)..<caret)
        guard !range.isEmpty else { return }
        // A character of two UTF-16 units (an emoji) goes whole.
        let whole = document.rangeOfComposedCharacterSequences(for: NSRange(location: range.lowerBound, length: range.count))
        ledger.take(document.substring(with: whole))
        host.document = document.replacingCharacters(in: whole, with: "")
        host.selection = nil
        host.caretOffset = whole.location
    }

    private func moveCaret(to offset: Int) {
        host.selection = nil
        host.caretOffset = min(max(offset, 0), (host.document as NSString).length)
    }

    /// The field before an event, kept for the app's undo where the event changed it.
    func remember(_ before: (document: String, caret: Int, ledger: CommitLedger)) {
        guard before.document != host.document else { return }
        undo.append(before)
    }

    /// ⌘Z the app had: the field as it was before the last change.
    private func undoLast() {
        guard let last = undo.popLast() else { return }
        host.document = last.document
        host.selection = nil
        host.caretOffset = last.caret
        host.marked = ""
        ledger = last.ledger
    }

    /// The host commits the marked text it shows as it is (Chromium's `finishComposingText`), the input method not told.
    func hostCommitsMarkedText() {
        guard !host.marked.isEmpty else { return }
        ledger.put(host.marked)
        let caret = host.caret
        host.document = (host.document as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: host.marked)
        host.caretOffset = caret + (host.marked as NSString).length
        host.selection = nil
        host.marked = ""
    }

    // MARK: The user

    /// `CLICK`: at `offset` in the field's text (UTF-16), or outside the field (nil). First the shell's mouse-down watch
    /// tells the session (`pointerDown`, contract v1.4: what isn't committed is dropped, the panel hidden), while the
    /// input method is the field's. Then the host does what it does: marked text in it (the app's own) is committed:
    /// by the host itself (Chromium's), or by the input method asked to (`commitComposition`) for a click outside the
    /// marked text (one inside it is the input method's: nothing moves). The caret goes to the offset after that.
    func click(at offset: Int?) {
        clock.clicked = true
        guard focused else { return }
        let start = host.outputs.count
        field.beginTurn()
        defer {
            field.endTurn()
            followOutputs(from: start)
            _ = field.takeCalls()
        }
        if !inABC { host.send(.pointerDown) }
        if let marked = field.markedNow {
            if profile.clickCommitsMarkedText {
                hostCommitsMarkedText()
            } else if let offset, offset >= marked.lowerBound, offset <= marked.upperBound, !inABC {
                return
            } else if !inABC {
                host.send(.commit)
            }
        }
        guard let offset else { return }
        moveCaret(to: offset)
    }

    /// `FOCUS`: the field loses the focus (to another field of the app, another app, its window closing) or takes it
    /// again. Losing it, the session is told (`blur`; `close` too as the window closes) and what it commits goes in, or,
    /// in a host that cancels the composition then (Chromium's), the host commits the marked text it shows and drops what
    /// the session puts in.
    func focus(_ change: FocusChange) {
        switch change {
        case .away, .otherapp: leave(closing: false)
        case .closewindow: leave(closing: true)
        case .back:
            guard !focused else { return }
            inABC = false
            focusAgain()
        }
    }

    private func leave(closing: Bool) {
        guard focused else { return }
        let start = host.outputs.count
        field.beginTurn()
        if profile.blurDropsComposition {
            hostCommitsMarkedText()
            host.acceptsText = false
        }
        if !inABC { host.send(.blur) }
        if closing { host.send(.close) }
        host.acceptsText = false
        focused = false
        field.endTurn()
        followOutputs(from: start)
        _ = field.takeCalls()
    }

    /// The field takes the focus (again): the session is told, and the shell knows nothing of how it tells its marked
    /// text yet.
    func focusAgain() {
        let start = host.outputs.count
        host.acceptsText = true
        focused = true
        field.beginTurn()
        host.focus()
        field.endTurn()
        followOutputs(from: start)
        _ = field.takeCalls()
    }

    /// `SWITCH`: the input source switched to ABC (the system has the input method commit what it composes first, then
    /// leaves it: keys go to the app as they are), and back.
    func switchSource(toABC: Bool) {
        guard focused, toABC != inABC else { return }
        guard toABC else {
            inABC = false
            return focusAgain()
        }
        let start = host.outputs.count
        field.beginTurn()
        host.send(.commit)
        host.send(.blur)
        host.acceptsText = false
        inABC = true
        field.endTurn()
        followOutputs(from: start)
        _ = field.takeCalls()
    }
}
