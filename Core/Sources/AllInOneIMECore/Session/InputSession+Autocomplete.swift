import Foundation

/// Autocomplete in one text field's session (`Autocomplete`): the suggestion up now, the pause being waited out, the
/// read of the field and the request after it, what was typed into the field.
struct AutocompleteField {
    /// A suggestion up, or held while something is composed (`hidden`): its rest comes back if what goes in is its start.
    struct Suggestion {
        /// What is left of it to go in.
        var text: String
        /// When it came up (`SessionServices.uptime`), or came back after what was composed.
        var shownAt: TimeInterval
        var hidden = false
        /// Its characters typed along so far.
        var typed = 0
        /// It as kept (`Autocomplete.Cache`): what Esc waves away.
        var kept: Autocomplete.Cache.Entry
    }

    var suggestion: Suggestion?
    /// Counts the pauses: an older one's timer, read and request do nothing.
    var pause = 0
    /// When the pause began: the last key that typed.
    var pauseStarted: TimeInterval = 0
    /// The pause whose read of the field is awaited, and the one whose request is, with what it continues.
    var reading: Int?
    var asked: Int?
    var request: Autocomplete.Context?
    /// When it was asked for (the pause over): what `Autocomplete.Route.late` goes by.
    var askedAt: TimeInterval = 0
    /// What was typed into the field, for one that tells nothing of its text (`Autocomplete.Typed`), and when last.
    var typed = Autocomplete.Typed()
    var typedAt: TimeInterval = 0
    /// When Tab last put a suggestion in: ⌘Z right after is counted (`Autocomplete.Metrics.undone`).
    var acceptedAt: TimeInterval?
}

/// What autocomplete says, in the interface language.
struct AutocompleteMessages {
    let words: InterfaceWords

    init(language: String) { words = InterfaceWords(language: language) }

    /// It stopped in `app` (its name) for want of use.
    func stopped(in app: String) -> String {
        words.tr("续写在「\(app)」里没用上，已在这个 App 里停下（设置 → 按 App 设置 可以让它一直续写）",
                 "Autocomplete wasn't used in \(app), so it stopped there (Settings → Apps can keep it on)")
    }

    /// The on-device model can't run (`reason`): nothing is shown, and nothing goes to the cloud.
    func unavailable(_ reason: String) -> String {
        words.tr("续写需要本机的 Apple Intelligence：\(reason)", "Autocomplete needs Apple Intelligence on this Mac: \(reason)")
    }
}

extension InputSession {
    /// How a suggestion ended, for what is learned and counted.
    enum SuggestionEnd {
        /// Tab put it in.
        case accepted
        /// Typed to its end.
        case typedThrough
        /// Esc, or a key that typed something else, moved the caret or ⌫.
        case dismissed
        /// The field was left, or clicked in.
        case ignored
        /// Gone for a reason that says nothing of it: secure input, another field, the settings.
        case unseen
    }

    /// Whether autocomplete may run in this field now: on in its app (`Autocomplete.isOn`), and nothing keeps it from
    /// running (`Autocomplete.blocker`).
    func autocompleteMayRun() -> Bool {
        let config = services.loadSettings()
        guard Autocomplete.isOn(in: app, config: config, stopped: services.autocomplete.stopped(in: app)) else { return false }
        let info = FieldInfo(app: app, terminal: terminal, secure: field.secure)
        return Autocomplete.blocker(in: info, secureInput: secureInputActive(), config: config, composing: composer.isComposing,
                                    translating: composer.translateMode != nil) == nil
    }

    /// A field took the focus: nothing of the field before; the on-device model loaded ahead of the first pause (once a
    /// minute at most).
    func autocompleteFocused() {
        autocompleteEnded(.unseen)
        let pause = autocomplete.pause + 1
        autocomplete = AutocompleteField()
        autocomplete.pause = pause
        tasks.cancel(.autocomplete)
        guard autocompleteMayRun(), Autocomplete.route(services.loadSettings()) == .onDevice,
              services.autocomplete.prewarmDue(at: services.uptime()) else { return }
        services.converter.prewarmOnDevice()
    }

    /// The field was left or clicked in (`ignored`), or is in secure input (`unseen`): the suggestion goes, the pause and
    /// the request stop, what was typed is forgotten (the caret may be elsewhere).
    func autocompleteLeft(_ end: SuggestionEnd) {
        autocompleteEnded(end)
        autocomplete.pause += 1
        autocomplete.typed.forget()
        tasks.cancel(.autocomplete)
    }

    /// Before the composer has `event`. Every key ends the pause and stops the request; ⌘Z right after a Tab is counted.
    /// With a suggestion up: Tab puts it in (true), or goes to the app as it would (`Autocomplete.tab`: ⇧Tab, ⌥Tab, a Tab
    /// right as it came up) and the suggestion goes; Esc takes it down (true). Nil: the key goes on.
    func autocompleteBeforeKey(_ event: KeyEvent) -> Bool? {
        let now = services.uptime()
        if let at = autocomplete.acceptedAt, now - at <= Autocomplete.undoWindow, Self.isUndo(event) {
            services.autocomplete.count { $0.undone += 1 }
            log.notice("autocomplete: ⌘Z right after a suggestion went in")
        }
        autocomplete.acceptedAt = nil
        autocomplete.pause += 1
        (autocomplete.reading, autocomplete.asked) = (nil, nil)
        tasks.cancel(.autocomplete)
        guard let suggestion = autocomplete.suggestion, !suggestion.hidden else { return nil }
        // A click or the wheel since it came up: the caret may be elsewhere (the shell has taken it down).
        if services.pointerUsedWithin(now - suggestion.shownAt) {
            autocompleteEnded(.ignored)
            return nil
        }
        if let use = Autocomplete.tab(event, shownFor: now - suggestion.shownAt) {
            guard use == .accept else {
                autocompleteEnded(.dismissed)
                return nil
            }
            emit(.commit(suggestion.text))
            autocompleteEnded(.accepted)
            log.notice("autocomplete: suggestion taken (\(suggestion.text.count) characters)")
            autocomplete.typed.add(suggestion.text)
            autocomplete.typedAt = now
            autocomplete.acceptedAt = now
            lastTyped.forget()
            // What it put in is a commit like any: a pause after it asks for what follows.
            autocompleteSchedulePause()
            return true
        }
        if event.key == .escape, event.modifiers.subtracting(.capsLock).subtracting(.sides).isEmpty {
            // Not this one: it isn't shown again for this text, kept or said again.
            services.autocomplete.reject(suggestion.kept)
            autocompleteEnded(.dismissed)
            return true
        }
        return nil
    }

    /// ⌘Z (Ctrl+Z on Windows) alone.
    static func isUndo(_ event: KeyEvent) -> Bool {
        let modifiers = event.modifiers.subtracting(.capsLock).subtracting(.sides)
        return (modifiers == .command || modifiers == .control) && event.charactersIgnoringModifiers.lowercased() == "z"
    }

    /// After the composer had `key`: `inserted`, what it put into the field (the key's own text where the app typed it,
    /// what the input method put in). While something is composed, a suggestion up is held. Text that is the start of
    /// the suggestion takes it on (typed along: its rest shows, from the caret on); anything else ends it. A key that
    /// typed starts the pause (`autocompleteSchedulePause`).
    func autocompleteAfterKey(_ key: KeyEvent, handled: Bool, inserted: String) {
        let now = services.uptime()
        // A key that types, pinyin's too: the user's rhythm, what the pause goes by.
        if key.printableText != nil, key.modifiers.isDisjoint(with: [.command, .control]) { services.autocomplete.keyTyped(at: now) }
        if services.pointerUsedWithin(now - autocomplete.typedAt) { autocomplete.typed.forget() }
        if !inserted.isEmpty {
            autocomplete.typed.add(inserted)
            autocomplete.typedAt = now
        } else if !handled {
            // The app had a key that typed nothing: ⌫ takes a character back, anything else may move the caret.
            let plain = key.modifiers.subtracting(.capsLock).subtracting(.sides).isDisjoint(with: [.command, .control, .option])
            if key.key == .backspace, plain { autocomplete.typed.backspace() } else if key.key.modifierKind == nil { autocomplete.typed.forget() }
        }
        if composer.isComposing {
            if var suggestion = autocomplete.suggestion, !suggestion.hidden {
                suggestion.hidden = true
                autocomplete.suggestion = suggestion
                emit(.ghost(nil))
            }
            return
        }
        if var suggestion = autocomplete.suggestion {
            if !inserted.isEmpty, suggestion.text.hasPrefix(inserted), autocompleteMayRun() {
                suggestion.text.removeFirst(inserted.count)
                suggestion.typed += inserted.count
                if suggestion.hidden { (suggestion.hidden, suggestion.shownAt) = (false, now) }
                autocomplete.suggestion = suggestion
                if suggestion.text.isEmpty { autocompleteEnded(.typedThrough) } else { emit(.ghost(suggestion.text)) }
                return
            }
            autocompleteEnded(.dismissed)
        }
        guard !inserted.isEmpty, autocompleteMayRun() else { return }
        autocompleteSchedulePause()
    }

    /// The pause starts: its timer, as long as the model's (`Autocomplete.Route.pause`) or longer for one who types
    /// slowly (`Autocomplete.Rhythm`), longer in an app where suggestions are waved away
    /// (`Autocomplete.Learning.pause`).
    func autocompleteSchedulePause() {
        let base = Autocomplete.route(services.loadSettings()).pause
        autocomplete.pause += 1
        autocomplete.pauseStarted = services.uptime()
        emit(.startTimer(.autocomplete(autocomplete.pause), after: services.autocomplete.pause(base, in: app)))
    }

    /// The pause is over: what the field says is read (`SessionOutput.readField`).
    func autocompletePaused(_ token: Int) {
        guard token == autocomplete.pause, autocomplete.suggestion == nil, autocompleteMayRun() else { return }
        autocomplete.reading = token
        emit(.readField(id: token))
    }

    /// What the field said once the pause was over: a suggestion kept for its text in this app (`Autocomplete.Cache`),
    /// else a request. Nothing where it isn't to run (`Autocomplete.context`: a selection, the caret before the line's
    /// end …).
    func autocompleteRead(_ context: FieldContext, id: Int) {
        guard id == autocomplete.reading, id == autocomplete.pause, autocomplete.suggestion == nil else { return }
        autocomplete.reading = nil
        guard context.read.contains(.secure), !context.secure, autocompleteMayRun() else { return }
        let text = context.read.contains(.text) ? context.text : nil
        let selection = context.read.contains(.selectedRange) ? context.selectedRange : nil
        // What was typed stands in only where the field tells nothing, and not past a click.
        let typed = services.pointerUsedWithin(services.uptime() - autocomplete.typedAt) ? "" : autocomplete.typed.text
        guard let request = Autocomplete.context(text, selection: selection, typed: typed) else { return }
        if let kept = services.autocomplete.kept(for: request, in: app) {
            autocompleteShow(kept.rest, kept: kept.entry, fromCache: true)
            return
        }
        autocomplete.asked = id
        autocomplete.request = request
        autocomplete.askedAt = services.uptime()
        services.autocomplete.count { $0.asked += 1 }
        log.notice("autocomplete \(id): asked (\(request.before.count) + \(request.after.count) characters)")
        tasks.autocomplete(request, app: app, id: id, converter: services.converter)
    }

    /// Request `request` answered: its suggestion kept, and shown if it's still wanted and not too late
    /// (`Autocomplete.Route.late`); neither if it is one waved away for this text. A failure shows nothing; the
    /// on-device model unavailable is said once.
    func autocompleteAnswered(_ result: Result<Autocomplete.Answer, any Error>, request: Int) {
        guard autocomplete.asked == request, request == autocomplete.pause else { return }
        autocomplete.asked = nil
        switch result {
        case let .failure(error):
            services.autocomplete.count { $0.failed += 1 }
            log.notice("autocomplete \(request): no suggestion (\(errorKind(error)))")
            if case AppleModelError.unavailable = error, services.autocomplete.once("unavailable") {
                say(AutocompleteMessages(language: UIText.language).unavailable(UIText.describe(error)), long: true)
            }
        case let .success(answer):
            if answer.inputTokens != nil || answer.outputTokens != nil {
                services.autocomplete.count {
                    $0.cloudInputTokens += answer.inputTokens ?? 0
                    $0.cloudOutputTokens += answer.outputTokens ?? 0
                }
            }
            guard let text = answer.text else {
                log.notice("autocomplete \(request): nothing to suggest")
                return
            }
            let asked = autocomplete.request ?? Autocomplete.Context(before: answer.before)
            let kept = Autocomplete.Cache.Entry(text, for: asked, in: app)
            guard services.autocomplete.keep(kept) else {
                log.notice("autocomplete \(request): the suggestion waved away again")
                return
            }
            guard autocomplete.suggestion == nil, autocompleteMayRun() else { return }
            let waited = services.uptime() - autocomplete.askedAt
            guard waited <= answer.route.late else {
                services.autocomplete.count { $0.late += 1 }
                log.notice("autocomplete \(request): too late (\(Int(waited * 1000)) ms)")
                return
            }
            autocompleteShow(text, kept: kept, fromCache: false)
        }
    }

    /// `text` up after the caret (`SessionOutput.ghost`), what is left of `kept`, counted with how long it took from
    /// the pause's start.
    func autocompleteShow(_ text: String, kept: Autocomplete.Cache.Entry, fromCache: Bool) {
        let now = services.uptime()
        autocomplete.suggestion = AutocompleteField.Suggestion(text: text, shownAt: now, kept: kept)
        let waited = now - autocomplete.pauseStarted
        services.autocomplete.count { $0.shown(text, after: waited, fromCache: fromCache) }
        emit(.ghost(text))
    }

    /// The suggestion ends (`end`): it goes from the screen, and what happened to it is counted and learned for the
    /// app, where it stops after `Autocomplete.Learning.window` not taken (said once, `AutocompleteMessages.stopped`),
    /// unless the app is set to always or never (Settings → Apps): there it goes by that.
    func autocompleteEnded(_ end: SuggestionEnd) {
        guard let suggestion = autocomplete.suggestion else { return }
        autocomplete.suggestion = nil
        if !suggestion.hidden { emit(.ghost(nil)) }
        guard end != .unseen else { return }
        services.autocomplete.count { metrics in
            switch end {
            case .accepted:
                metrics.accepted += 1
                metrics.acceptedCharacters += suggestion.typed + suggestion.text.count
            case .typedThrough:
                metrics.typedThrough += 1
                metrics.acceptedCharacters += suggestion.typed
            case .dismissed, .ignored:
                metrics.dismissed += 1
                metrics.acceptedCharacters += suggestion.typed
            case .unseen:
                break
            }
        }
        guard let app else { return }
        let mayStop = services.loadSettings().profile(for: app)?.autocomplete == nil
        guard services.autocomplete.learn({ $0.record(end == .accepted || end == .typedThrough, in: app, mayStop: mayStop) }) else { return }
        services.autocomplete.count { $0.stoppedApps += 1 }
        log.notice("autocomplete stopped in an app: none of its last \(Autocomplete.Learning.window) suggestions was taken")
        say(AutocompleteMessages(language: UIText.language).stopped(in: services.appName(app) ?? app), long: true)
    }

    /// After an event that isn't a key: a suggestion up is held while something is composed (dictation), and goes where
    /// autocomplete may no longer run (the settings, Translate as You Type); one held for what was composed goes once
    /// that is done some other way (a click on a candidate).
    func autocompleteSettle() {
        guard var suggestion = autocomplete.suggestion else { return }
        if composer.isComposing {
            guard !suggestion.hidden else { return }
            suggestion.hidden = true
            autocomplete.suggestion = suggestion
            emit(.ghost(nil))
            return
        }
        if suggestion.hidden || !autocompleteMayRun() { autocompleteEnded(.unseen) }
    }
}
