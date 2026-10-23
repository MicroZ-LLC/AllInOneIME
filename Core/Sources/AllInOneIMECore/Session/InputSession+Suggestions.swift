import Foundation

/// Suggestions in one text field's session (spec Suggestions v1, Suggestions/): the token typed into the field since a
/// boundary, the rows its sources have for it (plugin lists and queries, coding packs and the field's own words), the
/// keys they take per app class, the chooser a long press of Shift opens (Translate as You Type, coding mode), and the
/// timers they wait on.
struct SuggestionsField {
    /// What was typed into this field since the last boundary, as typed (token characters only), and when it changed
    /// last (`SessionServices.uptime`); where no rows may show (`unasked`: the pointer isn't asked with a key there),
    /// when it started.
    var token = ""
    var tokenAt: TimeInterval = 0
    var unasked = false
    /// The token started with "@" (or the command trigger): the command list's, no token until the next boundary.
    var dead = false
    /// Rows showed for this token: neither it nor the word it ends as is learned as an English word (spec 6.15); the
    /// last few such words.
    var showedRows = false
    var notLearned: [String] = []
    /// The rows shown, the token and class of app they are for.
    var rows: [SuggestionRow] = []
    var rowsToken: String?
    var appClass = SuggestionsAppClass.ordinary
    var highlighted = 0
    /// ↓ or ↑ moved the highlight: Return inserts it.
    var moved = false
    /// The token Esc hid the rows for (spec 6.12).
    var hiddenFor: String?
    /// The panel shows the rows or the chooser.
    var shown = false
    /// The chooser is open, this row highlighted.
    var chooser: Int?
    /// Shift's presses on its own counted (an older one's timer does nothing), and the hint of the one going on, up.
    var shift = 0
    var hint: String?
    /// The last key (`uptime`); the pause before a query is asked again, counted, and the token it is for.
    var lastKeyAt: TimeInterval = 0
    var queryWait = 0
    var queryWaitFor: String?
    /// The refresh timer, counted, and when it is due.
    var refresh = 0
    var refreshDue: Date?
    /// The field's own words and the leading whitespace of the caret's line (a snippet's later lines get it), from what
    /// the field said last: read once typing pauses (spec 2), or told with a key; the pause counted, and the one whose
    /// read is awaited.
    var words: [String] = []
    var indent = ""
    var wordsPause = 0
    var wordsReading: Int?
    /// The field reported where its selection is with the last key: a snippet's caret can go back into what went in.
    var ranges = false
}

extension InputSession {
    /// How long Shift is held on its own before the chooser opens (spec 2).
    static let chooserHold: TimeInterval = 1
    /// The pause in typing before a query is asked again (spec 6.4).
    static let queryPause: TimeInterval = 0.15
    /// The most rows shown.
    static let maxSuggestionRows = 5
    /// A query takes this long at most.
    static let queryTimeout: TimeInterval = 3
    /// The pause in typing after which coding mode reads the field's words again.
    static let wordsPause: TimeInterval = 0.3

    /// A completion source that may run here: its plugin's, enabled with what the plugin is now, not the command
    /// trigger's.
    struct ActiveSource {
        var plugin: InstalledPlugin
        var source: CompletionSource
        var key: CompletionSourceKey
        /// The hosts the user approved with it: its script fetches from those only (`CompletionCall.hosts`).
        var hosts: [String]
        /// The SHA-256 of the script the user approved: only that one runs (`CompletionCall.scriptSHA256`).
        var scriptSHA256: String
    }

    // MARK: - The sources

    /// The completion sources enabled (`SuggestionsSettings.enabled`) with the hosts, query, script and terms (prefix,
    /// when the query is first asked, how it compares) their plugin has now (an update that changed one needs enabling
    /// again), and active with the settings (`inactiveReason`).
    func activeSources(_ settings: SuggestionsSettings, plugins: [InstalledPlugin]? = nil) -> [ActiveSource] {
        guard !settings.enabled.isEmpty else { return [] }
        let config = services.loadSettings()
        let store = services.suggestions.store
        var active: [ActiveSource] = []
        for plugin in plugins ?? services.plugins(false) where !plugin.manifest.completions.isEmpty {
            let approvals = settings.enabled.filter { $0.plugin == plugin.name }
            guard !approvals.isEmpty, let script = plugin.scriptURL, let sha = store.sha256(of: script) else { continue }
            for source in plugin.manifest.completions where source.inactiveReason(config) == nil {
                guard let approval = approvals.first(where: { $0.holds(for: source, hosts: plugin.manifest.hosts, scriptSHA256: sha) })
                else { continue }
                active.append(ActiveSource(plugin: plugin, source: source, key: CompletionSourceKey(plugin: plugin.name, source: source.name),
                                           hosts: approval.hosts, scriptSHA256: approval.scriptSHA256))
            }
        }
        return active
    }

    /// The input menu's switch (on unless turned off) and the app's (Settings → Apps; absent: on).
    func suggestionsOn(_ settings: SuggestionsSettings) -> Bool {
        guard settings.master != false else { return false }
        guard let app else { return true }
        return settings.apps.first { $0.key.caseInsensitiveCompare(app) == .orderedSame }?.value != false
    }

    /// Whether rows may show in this field at all: a source enabled or coding mode on, and the switches on. None may: a
    /// key asks nothing of the pointer for the token (`suggestionsAfterKey`).
    func suggestionsMayShow() -> Bool {
        let settings = services.suggestions.settings()
        return (!settings.enabled.isEmpty || services.suggestions.codingMode()) && suggestionsOn(settings)
    }

    /// Whether coding mode reads the field's text here (its words, the caret's line's indentation): it is on, the field is
    /// no terminal's, not in secure input, and rows may show in it (the input menu's and the app's switches on, not an app
    /// with none: a remote desktop, a virtual machine, an SSH client, a launcher). Nowhere else is the field read for it.
    func codingModeReadsTheField() -> Bool {
        services.suggestions.codingMode() && !terminal && !secureInputActive()
            && SuggestionsAppClass(app: app, terminal: terminal) != .none && suggestionsOn(services.suggestions.settings())
    }

    /// Whether rows, the chooser or coding mode hold the caret: no ghost text then (spec 0, 2).
    var suggestionsHoldTheCaret: Bool {
        suggesting.shown || services.suggestions.codingMode()
    }

    // MARK: - Events

    /// A field took the focus: nothing of the one before; the sources' state taken in (lists cached, loads due, sources
    /// disabled forgotten). Shift's changes meanwhile went to other fields: no press, Shift as it is now, so the change
    /// seen last here (Shift down as Shift+Tab left) passes for no copy of the next one.
    func suggestionsFocused() {
        chooserPress.resync(shiftDown: services.suggestions.shiftDown())
        let (refresh, shift) = (suggesting.refresh, suggesting.shift)
        suggesting = SuggestionsField()
        (suggesting.refresh, suggesting.shift) = (refresh, shift + 1)
        // Told of what comes back, whichever field asked for it.
        services.suggestions.store.listen(ObjectIdentifier(self), tasks.deliver)
        suggestionsMaintain(prune: true)
    }

    /// The field was left or closed: its rows go.
    func suggestionsLeft() {
        let shown = suggesting.shown
        let (refresh, shift, notLearned) = (suggesting.refresh, suggesting.shift, suggesting.notLearned)
        suggesting = SuggestionsField()
        (suggesting.refresh, suggesting.shift, suggesting.notLearned) = (refresh, shift + 1, notLearned)
        services.suggestions.store.listen(ObjectIdentifier(self), nil)
        if shown { emit(.panel(nil)) }
    }

    /// The settings changed (`SessionEvent.configChanged`): a source disabled forgotten (its cache deleted), one whose
    /// approval no longer holds marked lapsed, "Refresh now" acted on, the rows made again.
    func suggestionsSettingsChanged() {
        suggestionsMaintain(prune: true)
        suggestionsUpdate()
    }

    /// The app wants what's pending in (a click in the field): the caret may be elsewhere.
    func suggestionsClicked() {
        suggestionsBoundary()
        suggestionsUpdate()
    }

    /// Secure input in the field: nothing typed there is followed, no rows, no chooser.
    func suggestionsSecure() {
        suggesting.chooser = nil
        suggestionsBoundary()
        suggestionsUpdate()
    }

    /// A row of the panel clicked: the chooser's mode, or the row put in (true); false: not ours.
    func suggestionsPick(_ index: Int) -> Bool {
        if suggesting.chooser != nil {
            guard (0...1).contains(index) else { return true }
            chooserChoose(index)
            return true
        }
        guard suggesting.shown, suggesting.rows.indices.contains(index) else { return false }
        suggestionsInsert(suggesting.rows[index], key: nil)
        return true
    }

    /// A load or query came back: its result taken in, the rows made again for the token as it is.
    func suggestionsAnswered() {
        suggestionsMaintain()
        suggestionsUpdate()
    }

    func suggestionsTimer(_ timer: SuggestionsTimer) {
        switch timer {
        case let .chooserHint(press), let .chooser(press):
            guard press == suggesting.shift, let held = chooserPress.held, !secureInputActive(), composer.voice == .off else { return }
            // Shift let go unseen (another app had the release, an event lost): the press is over, and the next one counts.
            guard services.suggestions.shiftHeld() else { return suggestionsModifiersMissed(shiftDown: false) }
            switch chooserPress.poll(pointerUsed: services.pointerUsedWithin(held)) {
            case .toggle?:
                chooserPress.cancel()
                chooserHintEnds()
                chooserOpen()
            case .hint?:
                // Half way: "Keep holding → …", up about until the chooser comes.
                if let hint = services.suggestions.chooserHint() {
                    suggesting.hint = hint
                    say(hint, lasting: TranslateMode.ShiftHold.toggleAfter - TranslateMode.ShiftHold.hintAfter + 0.3)
                }
            case nil:
                // Early, or the pointer used or moved (a Shift-click): the press ended.
                if chooserPress.held == nil { chooserHintEnds() }
            }
        case let .query(wait):
            guard wait == suggesting.queryWait, suggesting.queryWaitFor == suggesting.token else { return }
            let paused = services.uptime() - suggesting.lastKeyAt
            guard paused >= Self.queryPause - 0.01 else {
                emit(.startTimer(.suggestions(.query(wait)), after: Self.queryPause - paused))
                return
            }
            suggesting.queryWaitFor = nil
            suggestionsUpdate(askAgain: true)
        case let .refresh(count):
            guard count == suggesting.refresh else { return }
            suggesting.refreshDue = nil
            suggestionsMaintain()
            suggestionsUpdate()
        case let .words(pause):
            // Typing paused: coding mode's words read again, by the shell after the key (`SessionOutput.readField`, this
            // pause's id below 0).
            guard pause == suggesting.wordsPause, codingModeReadsTheField() else { return }
            suggesting.wordsReading = pause
            emit(.readField(id: -pause))
        }
    }

    /// What the field said once typing paused (`SuggestionsTimer.words`, `pause`): coding mode's words and the caret's
    /// line's indentation from its text, the rows made again with them.
    func suggestionsFieldRead(_ context: FieldContext, pause: Int) {
        guard pause == suggesting.wordsReading else { return }
        suggesting.wordsReading = nil
        guard context.read.contains(.secure), !context.secure, codingModeReadsTheField(), context.read.contains(.text),
              let text = context.text else { return }
        (suggesting.words, suggesting.indent) = (CodingRows.words(text), CodingRows.indent(text.before))
        log.notice("suggestions: the field's words read (\(suggesting.words.count))")
        if !suggesting.token.isEmpty { suggestionsUpdate() }
    }

    /// A modifier changed: Shift down on its own starts the long press the chooser opens after (`TranslateMode.ShiftHold`:
    /// not with fn or another modifier held, not with Sticky Keys, not the same change handed over again); anything else
    /// ends it.
    func suggestionsModifiers(_ change: ModifierChange) {
        if chooserPress.flagsChanged(key: change.key, modifiers: change.modifiers) {
            suggesting.shift += 1
            emit(.startTimer(.suggestions(.chooserHint(suggesting.shift)), after: TranslateMode.ShiftHold.hintAfter))
            emit(.startTimer(.suggestions(.chooser(suggesting.shift)), after: Self.chooserHold))
        } else if chooserPress.held == nil {
            suggesting.shift += 1
            chooserHintEnds()
        }
    }

    /// The press ended short of the chooser (released, a key, another modifier), or the chooser came: its hint goes, if
    /// it's still the notice up.
    func chooserHintEnds() {
        guard let hint = suggesting.hint else { return }
        suggesting.hint = nil
        _ = endNotice(hint)
    }

    /// Modifier changes may have gone unseen (secure input, another field): no press, Shift as it is now.
    func suggestionsModifiersMissed(shiftDown: Bool) {
        chooserPress.resync(shiftDown: shiftDown)
        suggesting.shift += 1
        chooserHintEnds()
    }

    /// Another app became active (the shell's), with a text field or not: Shift's changes go there now. A long press of
    /// Shift here ends, its hint with it, and Shift is taken as it is (`SuggestionsServices.shiftDown`). What the shell is
    /// to do.
    public func otherAppActivated() -> [SessionOutput] {
        collect { suggestionsModifiersMissed(shiftDown: services.suggestions.shiftDown()) }
    }

    // MARK: - Keys

    /// What the field `key` may need for suggestions: the selection where rows show (a snippet's caret); the text where
    /// it puts in a snippet of more than one line (its later lines get the caret's line's indentation as it is now). The
    /// field's words are read once typing pauses, never with a key.
    func suggestionsFieldWants(for key: KeyEvent) -> FieldContext.Parts {
        var wants: FieldContext.Parts = []
        if suggesting.shown { wants.insert(.selectedRange) }
        if let row = suggestionsRowPut(by: key), row.insertion.contains(where: \.isNewline), codingModeReadsTheField() {
            wants.insert(.text)
        }
        return wants
    }

    /// The row `key` would put in where rows show (`suggestionsBeforeKey`): Tab's, or Return's once ↓/↑ moved; nil: none.
    func suggestionsRowPut(by key: KeyEvent) -> SuggestionRow? {
        guard suggesting.shown, suggesting.chooser == nil, !suggesting.rows.isEmpty, !composer.isComposing,
              key.modifiers.subtracting(.capsLock).subtracting(.sides).isEmpty else { return nil }
        switch (suggesting.appClass, key.key) {
        case (.ordinary, .tab): return suggesting.rows[suggesting.highlighted]
        case (.chat, .tab): return suggesting.rows[0]
        case (.ordinary, .enter), (.ordinary, .keypadEnter): return suggesting.moved ? suggesting.rows[suggesting.highlighted] : nil
        default: return nil
        }
    }

    /// Before the composer has `event`: the chooser's keys while it is open; the rows' keys of the app's class while they
    /// show (spec 1.4: Tab, ↓ ↑, Return once moved, Esc; digits never). Nil: the key goes on.
    func suggestionsBeforeKey(_ event: KeyEvent, _ context: FieldContext) -> Bool? {
        // A key while Shift is held is no long press of it.
        chooserPress.keyDown()
        suggesting.shift += 1
        chooserHintEnds()
        suggesting.lastKeyAt = services.uptime()
        suggesting.ranges = context.read.contains(.selectedRange) && context.selectedRange != nil
        if let highlighted = suggesting.chooser { return chooserKey(event, highlighted) }
        // The caret's line as the field tells it now: a snippet the key puts in is indented as it is.
        if context.read.contains(.text), let text = context.text, CodingRows.indent(text.before) != suggesting.indent,
           codingModeReadsTheField() {
            suggesting.indent = CodingRows.indent(text.before)
            if suggesting.shown { suggestionsUpdate() }
        }
        guard suggesting.shown, !suggesting.rows.isEmpty, !composer.isComposing,
              event.modifiers.subtracting(.capsLock).subtracting(.sides).isEmpty else { return nil }
        switch (suggesting.appClass, event.key) {
        case (.ordinary, .tab):
            suggestionsInsert(suggesting.rows[suggesting.highlighted], key: event)
            return true
        case (.chat, .tab):
            suggestionsInsert(suggesting.rows[0], key: event)
            return true
        case (.codeEditor, .tab):
            return suggestionsCompleteShared(event) ? true : nil
        case (.ordinary, .arrow(.down)), (.ordinary, .arrow(.up)):
            let count = suggesting.rows.count
            suggesting.highlighted = (suggesting.highlighted + (event.key == .arrow(.down) ? 1 : -1) + count) % count
            suggesting.moved = true
            suggestionsShow()
            return true
        case (.ordinary, .enter), (.ordinary, .keypadEnter):
            guard suggesting.moved else { return nil }
            suggestionsInsert(suggesting.rows[suggesting.highlighted], key: event)
            return true
        case (.ordinary, .escape):
            suggesting.hiddenFor = suggesting.token
            suggestionsUpdate()
            return true
        default:
            return nil
        }
    }

    /// After the composer had `key`: what went into the field with it (`inserted`: what the input method put in, the key's
    /// own text where the app typed it) extends the token or ends it; a key the app had that typed nothing ends it (an
    /// arrow, Home, End, Return, a shortcut: ⌘V), but ⌫, which takes its last character back. Then the rows for it.
    /// A click since its last key ends it. Where no rows may show (`suggestionsMayShow`) a key asks nothing of the
    /// pointer (as autocomplete off does nothing for a key), and a click since the token started is looked for once
    /// they may: where it left the caret isn't known then, no token until the next boundary.
    func suggestionsAfterKey(_ key: KeyEvent, handled: Bool, inserted: String, context: FieldContext) {
        guard !secureInputActive() else { return suggestionsSecure() }
        let now = services.uptime()
        let mayShow = suggestionsMayShow()
        if mayShow, !suggesting.token.isEmpty, services.pointerUsedWithin(now - suggesting.tokenAt) {
            let unasked = suggesting.unasked
            suggestionsBoundary()
            suggesting.dead = unasked
        }
        let started = suggesting.token.isEmpty
        if !inserted.isEmpty {
            suggestionsTyped(inserted)
        } else if !handled, key.key.modifierKind == nil, key.key != .capsLock, key.key != .function {
            let plain = key.modifiers.subtracting(.capsLock).subtracting(.sides).isDisjoint(with: [.command, .control, .option])
            if key.key == .backspace, plain, !suggesting.token.isEmpty {
                suggesting.token.removeLast()
                if suggesting.token.isEmpty { suggestionsBoundary() }
            } else {
                suggestionsBoundary()
            }
        }
        suggestionsFollowed(started: started, mayShow: mayShow, at: now)
        if codingModeReadsTheField() {
            // The field told its text with the key (a shell where that's cheap): its words now.
            if context.read.contains(.text), let text = context.text {
                (suggesting.words, suggesting.indent) = (CodingRows.words(text), CodingRows.indent(text.before))
            }
            // Something typed: the words read again once typing pauses.
            if !inserted.isEmpty || key.key == .backspace {
                suggesting.wordsPause += 1
                emit(.startTimer(.suggestions(.words(suggesting.wordsPause)), after: Self.wordsPause))
            }
        }
        suggestionsUpdate()
    }

    /// Autocomplete's Tab put `text` in, a key the rows never saw (`autocompleteBeforeKey`): followed as what a key
    /// puts in is, so the token is the one before the caret, not what was typed before the gray text.
    func suggestionsGhostTaken(_ text: String) {
        let started = suggesting.token.isEmpty
        suggestionsTyped(text)
        suggestionsFollowed(started: started, mayShow: suggestionsMayShow(), at: services.uptime())
    }

    /// The token as it is after a key (`started`: it was empty before): `tokenAt` the key's time where rows may show,
    /// else the token's start.
    private func suggestionsFollowed(started: Bool, mayShow: Bool, at now: TimeInterval) {
        if mayShow || started || suggesting.token.isEmpty { suggesting.tokenAt = now }
        suggesting.unasked = !mayShow && !suggesting.token.isEmpty
    }

    /// `text` went into the field: its token characters extend the token, any other character ends it.
    func suggestionsTyped(_ text: String) {
        let trigger = services.loadSettings().commandTrigger
        for character in text {
            let normalized = Character(SuggestionsToken.normalized(String(character)))
            guard SuggestionsToken.isTokenCharacter(normalized) else {
                suggestionsBoundary()
                continue
            }
            if suggesting.token.isEmpty, !suggesting.dead, normalized == "@" || String(normalized) == trigger {
                suggesting.dead = true  // the command list's (spec 1.3)
            }
            guard !suggesting.dead else { continue }
            suggesting.token.append(character)
            if suggesting.token.count > 96 { suggesting.dead = true }
        }
    }

    /// The token ends (spec 1.3: a space, other punctuation, Return, a click, another field, a paste, the caret moved).
    func suggestionsBoundary() {
        if suggesting.showedRows {
            let normalized = SuggestionsToken.normalized(suggesting.token).lowercased()
            suggesting.notLearned = Array((suggesting.notLearned + [normalized, SuggestionsToken.identifier(endingAt: normalized)])
                .suffix(16))
        }
        suggesting.token = ""
        suggesting.dead = false
        suggesting.showedRows = false
        suggesting.hiddenFor = nil
    }

    /// Whether `word` (typed in English mode) is kept from being learned: a token rows showed for (spec 6.15).
    func suggestionsKeepFromLearning(_ word: String) -> Bool {
        let key = word.lowercased()
        if suggesting.notLearned.contains(key) { return true }
        guard suggesting.showedRows else { return false }
        return SuggestionsToken.identifier(endingAt: SuggestionsToken.normalized(suggesting.token).lowercased()) == key
    }

    // MARK: - Putting a row in

    /// `row` put in: what wasn't typed of it (spec 1.4), the caret at a snippet's `$0` where the field reports ranges
    /// (else at the end); picked before, it comes first next time. The token ends with it.
    func suggestionsInsert(_ row: SuggestionRow, key: KeyEvent?) {
        let rest = row.rest
        if !rest.isEmpty {
            emit(.commit(rest))
            lastTyped.forget()
            followEnglishInserted(rest)
        }
        if row.caretBack > 0, suggesting.ranges, !rest.isEmpty {
            emit(.moveCaret(back: min(row.caretBack, rest.utf16.count), after: rest))
        }
        if let pick = row.pick { services.suggestions.recordPick(pick) }
        log.notice("suggestions: a row put in (\(rest.count) characters)")
        suggesting.showedRows = true
        suggestionsBoundary()
        suggestionsUpdate()
        if let key { autocompleteAfterKey(key, handled: true, inserted: rest) }
    }

    /// Tab in a terminal or code editor: the common start of what every row for the token completes (not only the 5
    /// shown), when it adds to what was typed (spec 6.10); the token goes on with it, the rows stay.
    func suggestionsCompleteShared(_ key: KeyEvent) -> Bool {
        let typed = suggesting.rows[0].typed
        let common = suggestionsSharedCompletion(typed)
        guard common.count > typed.count,
              SuggestionsToken.normalized(common).lowercased().hasPrefix(SuggestionsToken.normalized(typed).lowercased()) else { return false }
        let rest = String(common.dropFirst(typed.count))
        emit(.commit(rest))
        lastTyped.forget()
        followEnglishInserted(rest)
        suggesting.token += rest
        suggesting.tokenAt = services.uptime()
        suggestionsUpdate()
        autocompleteAfterKey(key, handled: true, inserted: rest)
        return true
    }

    /// What the completions of all the rows for the token that answer `typed` (the whole token, or coding's identifier)
    /// start with, in any case (`commonPrefix`): the plugins' items (looked through until nothing more is shared) and
    /// coding mode's.
    func suggestionsSharedCompletion(_ typed: String) -> String {
        let s = services.suggestions
        let appClass = SuggestionsAppClass(app: app, terminal: terminal)
        let t = InterfaceWords(language: UIText.language)
        let token = suggesting.token
        var common: String?
        var commonCount = 0
        let typedCount = typed.count
        /// `completion` taken in: false once nothing more than what was typed is shared. (What is shared only ever gets
        /// shorter: its characters counted again only then.)
        func share(_ completion: String) -> Bool {
            let shared = commonPrefix(common ?? completion, completion)
            if shared.utf8.count != common?.utf8.count { (common, commonCount) = (shared, shared.count) }
            return commonCount > typedCount
        }
        // A plugin's rows answer the whole token.
        sources: for active in activeSources(s.settings()) where typed == token {
            guard let after = PluginRows.afterPrefix(token, active.source) else { continue }
            let list = active.source.list ? s.store.list(active.key) : nil
            let answers = active.source.query && active.source.prefix != nil
                ? s.store.answers(active.key, for: after.lowercased(), now: s.now()) : []
            var more = true
            PluginRows.eachCompletion(token, plugin: active.plugin, source: active.source,
                                      lists: (list.map { [$0.items] } ?? []) + answers.map(\.items), appClass: appClass, in: t) { completion in
                more = share(completion)
                return more
            }
            if !more { break sources }
        }
        if s.codingMode(), common.map({ $0.count > typed.count }) ?? true {
            let identifier = SuggestionsToken.identifier(endingAt: SuggestionsToken.normalized(token))
            for row in CodingRows.rows(identifier, packs: s.codingPacks(), words: terminal ? [] : suggesting.words, appClass: appClass, in: t)
            where row.typed == typed {
                if !share(row.completion) { break }
            }
        }
        return common ?? typed
    }

    // MARK: - The rows

    /// The rows for the token now, shown (or hidden): the highlight and Esc's hiding kept while the token stays; rows
    /// shown, autocomplete's gray text goes (spec 0). `askAgain`: the pause before a query is asked again is over.
    func suggestionsUpdate(askAgain: Bool = false) {
        let (rows, appClass) = suggestionsRows(askAgain: askAgain)
        let sameToken = suggesting.rowsToken == suggesting.token
        suggesting.rows = rows
        suggesting.appClass = appClass
        suggesting.rowsToken = suggesting.token
        if sameToken {
            suggesting.highlighted = min(suggesting.highlighted, max(rows.count - 1, 0))
        } else {
            (suggesting.highlighted, suggesting.moved) = (0, false)
        }
        if !rows.isEmpty {
            suggesting.showedRows = true
            if autocomplete.suggestion != nil || autocomplete.reading != nil || autocomplete.asked != nil {
                autocompleteEnded(.unseen)
                autocomplete.pause += 1
                (autocomplete.reading, autocomplete.asked) = (nil, nil)
                tasks.cancel(.autocomplete)
            }
        }
        suggestionsShow()
    }

    /// The panel as the rows and the chooser have it now: shown, or (theirs gone) back to the composer's.
    func suggestionsShow() {
        if suggesting.chooser != nil || !suggesting.rows.isEmpty {
            suggesting.shown = true
            if let panel = suggestionsPanel() { emit(.panel(panel)) }
        } else if suggesting.shown {
            suggesting.shown = false
            emit(.panel(composer.wantsPanel ? panelModel() : nil))
        }
    }

    /// The rows for the token (5 at most) and the class of app they are for: the plugins' sources that apply (their
    /// list's and queries' items, those picked before first), coding mode's (the packs', the field's words). None while
    /// something is composed, in secure input, where a switch is off or the app has none (spec 1.5). Asks the queries
    /// due (spec 6.4) and marks the sources used. Each source's items are looked through only for what matches, until
    /// its first 5 rows (with the rows picked before, wherever they are): a list may have 20,000.
    func suggestionsRows(askAgain: Bool) -> ([SuggestionRow], SuggestionsAppClass) {
        let appClass = SuggestionsAppClass(app: app, terminal: terminal)
        let s = services.suggestions
        let settings = s.settings()
        guard !suggesting.token.isEmpty, !suggesting.dead, suggesting.hiddenFor != suggesting.token, suggesting.chooser == nil,
              !composer.isComposing, !composer.wantsPanel, !secureInputActive(), appClass != .none, suggestionsOn(settings)
        else { return ([], appClass) }
        let now = s.now()
        let t = InterfaceWords(language: UIText.language)
        let scores = Frecency.scores(s.loadPicks())
        var rows: [SuggestionRow] = []
        let token = suggesting.token
        for active in activeSources(settings) {
            guard let after = PluginRows.afterPrefix(token, active.source), PluginRows.templates(active.source, appClass) != nil
            else { continue }
            s.store.markUsed(active.key, now: now)
            if active.source.list { suggestionsLoadIfDue(active, settings: settings, now: now) }
            let list = active.source.list ? s.store.list(active.key) : nil
            let lowered = after.lowercased()
            let answers = active.source.query && active.source.prefix != nil ? s.store.answers(active.key, for: lowered, now: now) : []
            let picked = Set(scores.keys.filter { $0.plugin == active.key.plugin && $0.source == active.key.source }.map(\.match))
            rows += PluginRows.rows(token, plugin: active.plugin, source: active.source,
                                    lists: (list.map { [$0.items] } ?? []) + answers.map(\.items), madeAt: list?.madeAt, appClass: appClass,
                                    picked: picked, limit: Self.maxSuggestionRows, in: t)
            // Never without a prefix (the declaration refuses it): any number typed would go out.
            if active.source.query, active.source.prefix != nil, after.count >= active.source.queryMinChars {
                suggestionsQuery(active, text: after, answers: answers, askAgain: askAgain, now: now)
            }
        }
        rows = Frecency.ordered(rows, scores: scores)
        if s.codingMode() {
            let identifier = SuggestionsToken.identifier(endingAt: SuggestionsToken.normalized(token))
            rows += Frecency.ordered(CodingRows.rows(identifier, packs: s.codingPacks(), words: terminal ? [] : suggesting.words,
                                                     indent: suggesting.indent, appClass: appClass, in: t), scores: scores)
        }
        return (Array(rows.prefix(Self.maxSuggestionRows)), appClass)
    }

    /// The panel of the rows (or the chooser): no number on a row (digits are typed, spec 6.1), the keys of the app's
    /// class in the footer, the source and its list's age (once older than 10 minutes) on its right, or the notice.
    func suggestionsPanel() -> PanelModel? {
        if let highlighted = suggesting.chooser { return chooserPanel(highlighted) }
        guard suggesting.shown, let first = suggesting.rows.first else { return nil }
        let t = InterfaceWords(language: UIText.language)
        let rows = suggesting.rows.enumerated().map { index, row in
            PanelModel.Row(label: "", text: row.text, comment: row.comment, kind: .candidate, choice: index)
        }
        let enter = Platform.current.terms.enter
        let footer: String
        switch suggesting.appClass {
        case .ordinary: footer = t.tr("Tab 插入 · ↑↓ \(enter) 选择 · Esc 隐藏", "Tab inserts · ↑↓ \(enter) to pick · Esc hides")
        case .chat: footer = t.tr("Tab 插入第一行", "Tab inserts the first row")
        case .codeEditor, .none: footer = t.tr("Tab 补全它们共同的开头", "Tab completes what they share")
        }
        let shown = suggesting.rows[suggesting.appClass == .ordinary ? suggesting.highlighted : 0]
        var detail = shown.source
        if let madeAt = shown.madeAt ?? first.madeAt, let age = Self.listAge(madeAt, now: services.suggestions.now(), in: t) {
            detail += " · " + age
        }
        return PanelModel(rows: rows, highlighted: suggesting.appClass == .codeEditor ? nil : (suggesting.appClass == .chat ? 0 : suggesting.highlighted),
                          footer: footer, detail: notice ?? detail)
    }

    /// A list's age as the footer says it, once older than 10 minutes: "12 min ago", "2 h ago", "3 d ago".
    static func listAge(_ madeAt: Date, now: Date, in t: InterfaceWords) -> String? {
        let seconds = now.timeIntervalSince(madeAt)
        guard seconds >= 600 else { return nil }
        let (minutes, hours, days) = (Int(seconds / 60), Int(seconds / 3600), Int(seconds / 86400))
        if hours < 1 { return t.tr("\(minutes) 分钟前", "\(minutes) min ago") }
        if days < 1 { return t.tr("\(hours) 小时前", "\(hours) h ago") }
        return t.tr("\(days) 天前", "\(days) d ago")
    }

    // MARK: - Lists and queries

    /// The results that came back taken in (now), Settings told of each source whose status changed; the lists due
    /// loaded (`prune`, as a field takes the focus or the settings change, the plugins just scanned again: the sources
    /// disabled forgotten first, their cache deleted, and the shell told of those whose approval no longer holds, to mark
    /// it lapsed: kept, with its cache); the next refresh's timer.
    func suggestionsMaintain(prune: Bool = false) {
        let s = services.suggestions
        let settings = s.settings()
        let plugins = services.plugins(false)
        let committed = s.store.commit(now: s.now(), folder: s.cacheFolder,
                                       versions: Dictionary(plugins.map { ($0.name, $0.manifest.version) }, uniquingKeysWith: { a, _ in a }))
        if !committed.cached.isEmpty { log.notice("suggestions: \(committed.cached.count) list(s) read from the cache") }
        for key in committed.statusChanged {
            if let status = s.store.status(plugin: key.plugin, source: key.source) {
                log.notice("suggestions: a list \(status.error == nil ? "loaded (\(status.items) items)" : "failed\(status.paused ? ", paused" : "")")")
                s.reportStatus(status)
            }
        }
        if prune {
            s.store.prune(keeping: Set(settings.enabled.map { CompletionSourceKey(plugin: $0.plugin, source: $0.source) }),
                          folder: s.cacheFolder)
            let lapsed = CompletionSourceApproval.lapsed(settings.enabled, plugins: plugins, sha256: s.store.sha256)
            if !lapsed.isEmpty {
                log.notice("suggestions: \(lapsed.count) source(s) no longer approved (their plugin changed): off until enabled again")
                s.approvalsLapsed(lapsed)
            }
        }
        guard settings.master != false, !secureInputActive() else { return }
        let active = activeSources(settings, plugins: plugins).filter(\.source.list)
        let now = s.now()
        for source in active { suggestionsLoadIfDue(source, settings: settings, now: now) }
        // The next refresh, back-off's end or pause's: a timer.
        let due = s.store.nextDue(active.map { ($0.key, $0.source.refresh) }, now: now)
        guard due != suggesting.refreshDue else { return }
        suggesting.refreshDue = due
        suggesting.refresh += 1
        if let due { emit(.startTimer(.suggestions(.refresh(suggesting.refresh)), after: max(due.timeIntervalSince(now), 1))) }
    }

    /// `active`'s list loaded if it is due (`SuggestionsStore.plan`): its cache on disk read first, once a launch (off the
    /// session's thread: until it is, nothing is due).
    func suggestionsLoadIfDue(_ active: ActiveSource, settings: SuggestionsSettings, now: Date) {
        let s = services.suggestions
        if let folder = s.cacheFolder { _ = s.store.readCache(active.key, in: folder, from: ObjectIdentifier(self), starter: tasks.deliver) }
        let request = settings.refreshes.last { $0.plugin == active.plugin.name && $0.source == active.source.name }
        let plan = s.store.plan(active.key, refresh: active.source.refresh, timeout: active.plugin.manifest.timeout,
                                version: active.plugin.manifest.version, request: request, now: now)
        if plan.resumed, let status = s.store.status(plugin: active.key.plugin, source: active.key.source) { s.reportStatus(status) }
        guard plan.load else { return }
        let id = s.store.startLoad(active.key, now: now)
        let call = completionCall(active, timeout: active.plugin.manifest.timeout)
        let (runtime, store, deliver, key, digitsOnly) = (s.runtime, s.store, tasks.deliver, active.key, active.source.prefix == nil)
        let session = ObjectIdentifier(self)
        let preferences = completionPreferences(active.plugin)
        log.notice("suggestions: loading a list")
        SuggestionsWork.start {
            var call = call
            call.context.preferences = preferences()
            let result: Result<SuggestionsStore.LoadedList, SuggestionsStore.LoadFailure>
            do {
                switch CompletionOutput.read(try await runtime.load(call), digitsOnly: digitsOnly) {
                case let .success(list): result = .success(SuggestionsStore.LoadedList(list))
                case let .failure(failure): result = .failure(.init(message: failure.message))
                }
            } catch {
                result = .failure(.init(message: InputSession.describeFailure(error)))
            }
            store.deposit(key, .load(id: id, result), from: session, starter: deliver)
        }
    }

    /// The query for `text` (after the prefix, as typed) asked when it is due (spec 6.4): first when there is no answer
    /// for a start of it (nor one on its way); after that only when the answer kept for the longest start of it leaves
    /// fewer than 5 rows, once typing pauses. One at a time for a source: one on its way for a start of `text` is waited
    /// for, another is cancelled.
    func suggestionsQuery(_ active: ActiveSource, text: String, answers: [(text: String, items: CompletionItems)],
                          askAgain: Bool, now: Date) {
        let s = services.suggestions
        let lowered = text.lowercased()
        guard answers.first?.text != lowered, !s.store.queriesRest(active.key, now: now) else { return }
        let timeout = min(Self.queryTimeout, active.plugin.manifest.timeout)
        let inFlight = s.store.queryInFlight(active.key, timeout: timeout, now: now)
        if let inFlight, lowered.hasPrefix(inFlight) { return }
        if let longest = answers.first {
            let token = SuggestionsToken.normalized(suggesting.token).lowercased()
            guard PluginRows.count(longest.items, answering: token, active.source, upTo: Self.maxSuggestionRows) < Self.maxSuggestionRows
            else { return }
            guard askAgain else {
                if suggesting.queryWaitFor != suggesting.token {
                    suggesting.queryWait += 1
                    suggesting.queryWaitFor = suggesting.token
                    let waited = services.uptime() - suggesting.lastKeyAt
                    emit(.startTimer(.suggestions(.query(suggesting.queryWait)), after: max(Self.queryPause - waited, 0.01)))
                }
                return
            }
        }
        let id = s.store.startQuery(active.key, text: lowered, now: now)
        let call = completionCall(active, timeout: timeout)
        let (runtime, store, deliver, key, digitsOnly) = (s.runtime, s.store, tasks.deliver, active.key, active.source.prefix == nil)
        let session = ObjectIdentifier(self)
        let preferences = completionPreferences(active.plugin)
        log.notice("suggestions: a query asked (\(text.count) characters)")
        let task = SuggestionsWork.start {
            var call = call
            call.context.preferences = preferences()
            var items: CompletionItems?
            do {
                if case let .success(list) = CompletionOutput.read(try await runtime.query(text, call), digitsOnly: digitsOnly) {
                    items = CompletionItems(list.items)
                }
            } catch {}
            store.deposit(key, .query(id: id, text: lowered, items: items, cancelled: Task.isCancelled), from: session,
                          starter: deliver)
        }
        s.store.setQueryTask(active.key, id: id, task: task)
    }

    /// The call into `active`'s script: its `ctx` (its preferences filled in off the session's thread, `completionPreferences`),
    /// the hosts and the script approved.
    func completionCall(_ active: ActiveSource, timeout: TimeInterval) -> CompletionCall {
        CompletionCall(plugin: active.plugin, source: active.source,
                       context: CompletionContext(source: active.source.name, preferences: [:], language: UIText.pluginLanguage),
                       timeout: timeout, hosts: active.hosts, scriptSHA256: active.scriptSHA256)
    }

    /// What reads `plugin`'s preferences for its script (off the session's thread: passwords come from the secret store):
    /// those the user set, else the manifest's defaults; only those it declares (`PluginPreference.values`).
    func completionPreferences(_ plugin: InstalledPlugin) -> @Sendable () -> [String: String] {
        let read = services.suggestions.preferences
        return { PluginPreference.values(for: plugin, set: read(plugin)) }
    }

    /// Why a script's call failed, as Settings says it.
    static func describeFailure(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription, !description.isEmpty { return description }
        let text = String(describing: error)
        return text.isEmpty ? tr("插件出错了", "The plugin failed") : text
    }

    // MARK: - The chooser (spec 2, 6.2)

    /// Translate as You Type came on otherwise than from the chooser (an app set to translate always, as a field of it
    /// took the focus: the shell's): coding mode, exclusive with it, goes off, its rows with it. What the shell is to do.
    public func translateAsYouTypeCameOn() -> [SessionOutput] {
        collect {
            let s = services.suggestions
            guard s.codingMode() else { return }
            s.setCodingMode(false)
            log.notice("coding mode off (Translate as You Type came on)")
            applyCodingMode()
            suggestionsUpdate()
        }
    }

    func chooserOpen() {
        guard !secureInputActive() else { return }
        // The mode that is on highlighted (⏎ turns it off), else Translate as You Type.
        suggesting.chooser = services.suggestions.codingMode() ? 1 : 0
        log.notice("the chooser of Translate as You Type and coding mode opened")
        suggestionsShow()
    }

    /// The chooser's keys: ↑ ↓ move, 1 or 2 and Return choose, Esc closes; any other key closes it and goes on.
    func chooserKey(_ event: KeyEvent, _ highlighted: Int) -> Bool? {
        let plain = event.modifiers.subtracting(.capsLock).subtracting(.sides).subtracting(.shift).isEmpty
        switch event.key {
        case .arrow(.down), .arrow(.up):
            suggesting.chooser = 1 - highlighted
            suggestionsShow()
            return true
        case .enter, .keypadEnter:
            chooserChoose(highlighted)
            return true
        case .escape:
            chooserClose()
            return true
        case .character where plain && (event.characters == "1" || event.characters == "2"):
            chooserChoose(event.characters == "1" ? 0 : 1)
            return true
        default:
            chooserClose()
            return nil
        }
    }

    func chooserClose() {
        suggesting.chooser = nil
        suggestionsUpdate()
    }

    /// Translate as You Type (0) or coding mode (1) chosen: turned on, the other off (they're exclusive); the one on
    /// turned off.
    func chooserChoose(_ index: Int) {
        let s = services.suggestions
        let t = InterfaceWords(language: UIText.language)
        // The chooser goes first: what the mode then says (its notice) stays up.
        suggesting.chooser = nil
        suggestionsUpdate()
        if index == 0 {
            if s.translateAsYouType() {
                s.setTranslateAsYouType(false)
            } else {
                if s.codingMode() {
                    s.setCodingMode(false)
                    applyCodingMode()
                }
                s.setTranslateAsYouType(true)
            }
            log.notice("Translate as You Type \(s.translateAsYouType() ? "on" : "off") (the chooser)")
        } else {
            let on = !s.codingMode()
            if on, s.translateAsYouType() { s.setTranslateAsYouType(false) }
            s.setCodingMode(on)
            log.notice("coding mode \(on ? "on" : "off") (the chooser)")
            applyCodingMode()
            suggestionsUpdate()
            say(on ? t.tr("编码模式已开：关键字、代码片段和字段里的词，Tab 补全", "Coding mode on: keywords, snippets and the field's words, Tab completes")
                   : t.tr("编码模式已关", "Coding mode off"))
        }
    }

    func chooserPanel(_ highlighted: Int) -> PanelModel {
        let s = services.suggestions
        let t = InterfaceWords(language: UIText.language)
        let on = t.tr("已开：再选一次就关", "On: choose it again to turn it off")
        let rows = [
            PanelModel.Row(label: "1", text: t.tr("边打边译", "Translate as You Type"), comment: s.translateAsYouType() ? on : "",
                           kind: .candidate, choice: 0),
            PanelModel.Row(label: "2", text: t.tr("编码模式", "Coding mode"), comment: s.codingMode() ? on : "", kind: .candidate, choice: 1),
        ]
        let enter = Platform.current.terms.enter
        return PanelModel(rows: rows, highlighted: highlighted,
                          footer: t.tr("↑↓ 或 1–2 选，\(enter) 确定，Esc 取消", "↑↓ or 1–2 to choose, \(enter) to confirm, Esc to cancel"),
                          detail: notice)
    }
}
