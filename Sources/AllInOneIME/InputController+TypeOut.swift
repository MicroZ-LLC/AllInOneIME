import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import InputMethodKit

/// Typing a result out character by character (`Config.typeOut`), and stopping it (`stopTyping`, beside the keys).
extension AllInOneIMEInputController {
    /// Types `text` into `client` character by character, like a person typing (`TypeOut.plan`), with an
    /// occasional typo fixed on the way (`typeOutMistakes`) where the field can take one back.
    ///
    /// A typo is taken back by replacing its range: `insertText` with a `replacementRange`, which the text input
    /// protocol has every text field honor (NSTextView, WebKit, Chromium and Electron do). Only in a field that
    /// says where its caret is, right where the text typed so far ends, and reads that text back as typed
    /// (`attributedSubstring`); while a typo is in the field, and after each fix, that's checked before every step
    /// (`TypeOut.Typist`). Never in a terminal (keys go to a shell). An app that doesn't keep a fix as asked is
    /// remembered (`LearnedShared`) and gets no typos again. (A ⌫ posted as a key would need the Accessibility
    /// permission and could reach the app after the next character: never here.)
    @MainActor
    func typeOut(_ text: String, into client: IMKTextInput) {
        stopTyping(insertingRest: true, waiting: false)
        let field = TypingField(client, pastesControls: Composer.actsInTerminal(text) && Self.isTerminal(client) && canPasteInTerminal())
        typingField = field
        typingPastes = field.pastesControls
        let caret = field.caret
        let app = client.bundleIdentifier() ?? ""
        let mistakes = session.typeOutMistakes && !Self.isTerminal(client) && !LearnedShared.store.typosOff(in: app) && caret != nil
        // Wrong letters from the keys next to the right one on the keyboard the keys come from (AZERTY, QWERTZ …).
        let layout = appliedLayout.flatMap(KeyboardLayout.cached(id:)) ?? KeyboardLayout.current()
        let keyboard = layout.map(TypeOut.Keyboard.init(layout:)) ?? .qwerty
        let random = typeOutRandom ?? { Double.random(in: 0..<1) }
        typist = TypeOut.Typist(TypeOut.plan(for: text, rate: session.typeOutRate, varies: session.typeOutVaries, mistakes: mistakes,
                                             keyboard: keyboard, random: random), start: caret ?? 0, length: field.length)
        let sleep = typeOutSleep
        log.notice("typing out \(text.count) characters (\(self.typist.typing.runs.filter(\.isSlip).count) typos to fix)")
        typingTask = Task { @MainActor [weak self] in
            var waited = false
            while true {
                if !waited, let delay = self?.typist.nextDelay { await sleep(delay) }
                guard let self, !Task.isCancelled, let field = self.typingField else { return }
                let progress = self.typist.step(in: field)
                self.rememberFailure(app)
                if progress == .done { break }
                waited = progress == .waiting
                if waited { await sleep(0.05) }  // the field catching up (Chromium tells its caret late)
                while !field.toPaste.isEmpty {
                    let control = field.toPaste.removeFirst()
                    // Not pasted (what is on the clipboard couldn't be kept): a space, as on one line. Typing stopped
                    // meanwhile: nothing more, no space either (a ⌘V not posted by then never is: `TerminalPaste.paste`).
                    // Another app frontmost now (⌘-Tab): the rest isn't typed, as once the field is left.
                    let pasted = await self.pasteInTerminal(control)
                    guard !Task.isCancelled else { return }
                    guard let pasted else {
                        self.stopTyping(insertingRest: false)
                        return
                    }
                    if !pasted { field.type(" ") }
                }
            }
            guard let self, !Task.isCancelled else { return }
            let typedInto = self.typingField?.client
            self.typingTask = nil
            self.typingField = nil
            if let back = self.caretAfterTyping {
                self.caretAfterTyping = nil
                self.moveCaret(back: back, after: text, in: typedInto)
            }
        }
    }

    /// A snippet's `{cursor}` (`Composer.Effect.moveCaret`): the caret goes `back` UTF-16 units into the text just put in.
    /// Only in a field that says where its caret is and has that text right before it; not in a terminal (keys there go
    /// to a shell). Elsewhere the caret stays at the end, as after any result.
    ///
    /// A text view keeps its caret where it is when a range is replaced (`insertText` with a range), so the caret is
    /// moved with marked text, which puts it where it says: empty marked text at the place. Nothing else is tried: where
    /// that doesn't arrive or isn't taken (the input method connection may drop empty text with a range; a browser may
    /// report its caret late), the caret stays at the end, which is harmless. Marking a character of the text instead
    /// could lose or double it where the field's ranges lag behind.
    @MainActor
    func moveCaret(back: Int, after inserted: String?, in client: IMKTextInput?) {
        guard back > 0, let inserted, let client, !Self.isTerminal(client) else { return }
        let caret = client.selectedRange()
        let length = inserted.utf16.count
        guard caret.location != NSNotFound, caret.length == 0, back <= length, caret.location >= length else { return }
        // The end of what was inserted, before the caret (no more than a line or two of it is read back).
        let checked = min(length, 200)
        let expected = String(decoding: inserted.utf16.suffix(checked), as: UTF16.self)
        guard client.attributedSubstring(from: NSRange(location: caret.location - checked, length: checked))?.string == expected else {
            log.notice("caret not moved: the field doesn't have the snippet before its caret")
            return
        }
        let target = caret.location - back
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: target, length: 0))
        if client.selectedRange().location != target { log.notice("caret not moved: the field didn't take it; it stays at the end") }
    }

    /// Remembers `app` when its field didn't take a typo's fix (`LearnedShared`): no typos there again.
    @MainActor
    func rememberFailure(_ app: String) {
        guard typist.fieldFailed, LearnedShared.store.turnTyposOff(in: app) else { return }
        log.error("typing out: \(app, privacy: .public) didn't take a typo's fix (\(self.typist.failure ?? "", privacy: .public)); no typos there again")
    }

    /// Typing out stopped while the field doesn't tell what was typed yet (`TypeOut.Typist.stopping`: Chromium tells its
    /// text late), looked at again a little later (`typeOutSleep`), off the key that stopped it: no key waits on the main
    /// thread. Typing out goes on stopping meanwhile (`isTypingOut`; a key only finishes it), in this field and this typing
    /// out only: another field took the focus, it is left as it is.
    @MainActor
    func settleStop(in field: TypingField, insertingRest: Bool) {
        stopsInsertingRest = insertingRest
        let (session, sleep) = (fieldSession, typeOutSleep)
        typingTask = Task { @MainActor [weak self] in
            await sleep(0.02)
            guard let self, !Task.isCancelled, self.typingField === field else { return }
            guard self.fieldSession == session else {
                log.notice("typing out stopped (the field left before it told what was typed)")
                (self.typingTask, self.typist, self.typingField, self.typingPastes) = (nil, TypeOut.Typist([], start: 0), nil, false)
                (self.stopsInsertingRest, self.caretAfterTyping) = (nil, nil)
                return
            }
            self.stopTyping(insertingRest: insertingRest)
        }
    }
}
