import Foundation

// MARK: - Translate as You Type

/// Translate as You Type (「边打边译」, `TranslateMode`) in the composer, while the controller has it on here (`translateMode`): what is
/// typed in another language than the one it translates into collects into a draft instead of going into the field,
/// shown after its indicator ("中→英 › 你好"). ⏎ translates the draft (pinyin still being typed is picked first) and the
/// translation goes in at once (`Effect.startTranslateMode`, `receive`); ⇧⏎ inserts it as typed. While it's translated
/// the draft shows so ("中→英 › 你好 · 翻译中…"); Esc stops it, the draft kept, and typing on stops it and goes on with
/// the draft. A failure keeps the draft, with a notice, and ⏎ tries again; so does secure input on at ⏎ (while it's on,
/// nothing collects: text goes in as typed). A draft already in the target language goes in as typed, and so does one in
/// an app with no AI, with a notice. An @ command typed at the start of a sentence works as anywhere.
extension Composer {
    /// Translate as You Type takes what would go into the field now into its draft instead: it's on, nothing else is being
    /// written (an @ command, a command's selection, results), the language typed isn't the one it translates into,
    /// and secure input is off.
    var modeCollects: Bool {
        guard let session = translateMode, draft.isEmpty, selection == nil, !isLevelTwo else { return false }
        return !inputLanguage.matches(session.target) && !secureInputActive()
    }

    /// `modeCollects` for `text`: a space (or nothing) doesn't start a draft.
    func modeCollects(_ text: String) -> Bool {
        modeCollects && !text.allSatisfy(\.isWhitespace)
    }

    /// The mode's request is in flight.
    var modeTranslating: Bool {
        if case let .translating(id) = phase, id == modeRequestID { return true }
        return false
    }

    /// What is being written is the mode's: its draft (anything but an @ command), its request, or what is being typed
    /// that will start the draft.
    public var inModeComposition: Bool {
        guard translateMode != nil, selection == nil else { return false }
        if modeTranslating { return true }
        guard !isLevelTwo else { return false }
        if !draft.isEmpty { return !draft.hasPrefix("@") }
        return modeCollects && (engineState.isComposing || !hangul.isEmpty || pendingAccent != nil)
    }

    /// The indicator of the mode on: 「中→英」, from the language typed (or, typed on in the target, the draft's).
    public var translateModeIndicator: String? {
        guard let session = translateMode else { return nil }
        let typed = inputLanguage.matches(session.target) ? Language.of(draft, french: inputLanguages.contains(.french)) : inputLanguage
        return TranslateMode.indicator(from: typed, to: session.target)
    }

    /// The draft as marked in the field: after the indicator, any "@" full-width (an app may take "@…" for a mention),
    /// and while it's translated, saying so.
    var modeShownDraft: String? {
        guard inModeComposition, let indicator = translateModeIndicator else { return nil }
        let text = draft.replacingOccurrences(of: "@", with: "＠").replacingOccurrences(of: "\n", with: Self.lineBreak)
        return indicator + " › " + text + (modeTranslating ? " · " + translateModeMessages.translating : "")
    }

    /// The candidate panel in the mode: only for the engine's candidates (and dictation); never results to pick.
    var modeWantsPanel: Bool? {
        guard inModeComposition else { return nil }
        if modeTranslating { return false }
        if voice != .off { return true }
        return engineState.isComposing && !engineState.candidates.isEmpty
    }

    /// Turns the mode on here (`session`) or off (nil), as the controller has it. Off, its draft goes in as typed (pinyin
    /// being typed picked first, a request stopped); the marked text shows the indicator, or no longer.
    public func setTranslateMode(_ session: TranslateMode.Session?) -> [Effect] {
        guard session != translateMode else { return [] }
        var effects: [Effect] = []
        if session == nil, inModeComposition, !draft.isEmpty || modeTranslating {
            var text = draft
            if !isLevelTwo, let engine, engine.snapshot().isComposing { text += engine.commitComposition() ?? "" }
            effects = finish(committing: text)
        }
        translateMode = session
        return effects + [.updateMarkedText]
    }

    /// ⏎ and ⇧⏎ on the mode's draft (or its pinyin): translate, or as typed. Space is a space there whatever the action
    /// key. Nil: the key acts as usual.
    func handleModeKey(_ event: KeyEvent) -> Response? {
        guard inModeComposition, !isLevelTwo, let engine else { return nil }
        let modifiers = event.modifiers.subtracting(.capsLock)
        switch event.keyCode {
        case VirtualKey.returnKey, VirtualKey.keypadEnter:
            if modifiers.isEmpty { return .consumed(translateModeDraft(engine)) }
            if modifiers == .shift { return .consumed(modeDraftAsTyped(engine)) }
            return nil
        case VirtualKey.space where modifiers.isEmpty && actionKey == .space && !engine.snapshot().isComposing && !draft.isEmpty:
            insertIntoDraft(" ")
            return .consumed([.updateMarkedText])
        default:
            return nil
        }
    }

    /// ⏎: pinyin still being typed is picked, then the draft is sent to be translated. Already in the language it
    /// translates into, it goes in as typed; so does it in an app with no AI, with a notice. During secure input nothing
    /// is sent: the draft stays, with a notice, for ⏎ to try again (as a failure).
    func translateModeDraft(_ engine: PinyinEngine) -> [Effect] {
        let effects = engine.snapshot().isComposing ? convertComposition(engine) : []
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session = translateMode, !text.isEmpty else {
            setLevelOnePhase()
            return effects + [.updateMarkedText]
        }
        if Language.of(text, french: inputLanguages.contains(.french)).matches(session.target) { return effects + finish(committing: draft) }
        if let refusal = aiRefusal() { return effects + finish(committing: draft) + [.notice(refusal)] }
        if secureInputActive() { return effects + modeFailed(translateModeMessages.secureInput) }
        requestCounter += 1
        modeRequestID = requestCounter
        phase = .translating(id: requestCounter)
        result = .empty
        activeCommand = nil
        highlightOverride = nil
        return effects + [.startTranslateMode(input: text, session: session, id: requestCounter), .updateMarkedText, .hidePanel]
    }

    /// ⇧⏎: the draft goes in as typed, not translated (pinyin still being typed picked first, as ⏎ does).
    func modeDraftAsTyped(_ engine: PinyinEngine) -> [Effect] {
        let effects = engine.snapshot().isComposing ? convertComposition(engine) : []
        return effects + finish(committing: draft)
    }

    /// Keys while the draft is translated: Esc (or ⌫) stops it and keeps the draft; ⇧⏎ inserts the draft as typed; ⏎
    /// waits; a key that types stops it and goes on with the draft. Nil outside the mode's request.
    func handleModeTranslatingKey(_ event: KeyEvent) -> Response? {
        guard modeTranslating else { return nil }
        let modifiers = event.modifiers.subtracting(.capsLock)
        switch event.keyCode {
        case VirtualKey.escape, VirtualKey.delete:
            return .consumed(backToDraft())
        case VirtualKey.returnKey, VirtualKey.keypadEnter:
            return .consumed(modifiers == .shift ? finish(committing: draft) : [])
        default:
            guard event.printableText != nil, modifiers.isSubset(of: .shift) else { return .consumed() }
            let back = backToDraft()
            return .consumed(back + handleLevelOne(event).effects)
        }
    }

    /// The translation: in, at once (typed out where results are), once it's complete. None: as a failure.
    func receiveModeTranslation(_ newResult: ConversionResult, isFinal: Bool) -> [Effect] {
        result = newResult
        guard isFinal else { return [] }
        let line = newResult.translations.first?.line.text ?? newResult.versions.first?.text ?? ""
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return modeFailed(messages.noResult) }
        phase = .drafting  // done, not stopped: nothing to cancel
        if typesResults { return finish(committing: "", selection: .replaced) + [.typeOut(text)] }
        return finish(committing: text)
    }

    /// The request failed (the network, a refusal, secure input): the draft stays, a notice says why, ⏎ tries again.
    func modeFailed(_ message: String) -> [Effect] {
        modeRequestID = nil
        result = .empty
        setLevelOnePhase()
        return [.updateMarkedText, .notice(translateModeMessages.failed(message))]
    }
}
