import Foundation

// One @ (0.7.0, `OneAt`): the magic key at the start of a draft, then whatever the user wants, and no command written
// after it. The list says what can be done with the text, the likeliest first; ⏎ (the action key) does the highlighted
// row, ↑↓ move, Tab picks a command or does the row, Esc leaves the text as typed. Letters right after the key are
// searched as names and, in Chinese, composed as pinyin at the same time: the rows are for the text as it would be with
// the first candidate. The rows are worked out on the key that changed the text, from what is in memory; the files
// Spotlight finds join them as they come (`oneAtFiles`, a `LiveRows`).
extension Composer {
    /// How many rows of the list show at once (the rest scroll into view).
    public static let oneAtRowsShown = 7

    /// The text after the magic key while one @ is written (no command at the start of the draft), as it would be with the
    /// pinyin's first candidate, and the letters right after the key: a name being typed (letters and digits only), or
    /// pinyin being composed there. Nil otherwise (level two, dictation, a command written).
    public var oneAt: (text: String, letters: String?)? {
        guard !isLevelTwo, voice == .off, draft.hasPrefix(commandTrigger), !draftHasCommand else { return nil }
        let after = draft.dropFirst(commandTrigger.count)
        guard engineState.isComposing, let engine else {
            let name = after.first?.isLetter == true && after.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            return (String(after), name ? String(after) : nil)
        }
        let state = engineState
        let candidate = state.candidates.indices.contains(state.highlighted) ? state.candidates[state.highlighted].text : engine.rawInput
        let at = after.count - cursorTailCount
        let text = String(after.prefix(at)) + candidate + String(after.dropFirst(at))
        let letters = after.isEmpty ? engine.rawInput.filter { $0.isASCII && ($0.isLetter || $0.isNumber) } : nil
        return (text, letters?.isEmpty == false ? letters : nil)
    }

    /// The rows of the one @ list (`OneAt.actions`), worked out once for what they come from (the text, the selection,
    /// the commands, their use, the app, Spotlight's files so far). While secure input is on (`secureInputActive`) it is
    /// as in an app with No AI: no AI row is guessed (an AI command typed by its name is listed, and refused when run).
    public var oneAtRows: [OneAt.Action] {
        guard let (text, letters) = oneAt else { return [] }
        let app = appInUse(), noAI = !aiAllowed() || secureInputActive()
        // Spotlight's files for the text: those found for it, else those for the text before that still match it.
        let fileQuery = oneAtFileQuery
        if fileQuery != nil, oneAtFiles.query != fileQuery { showOneAtFiles() }
        let files = fileQuery != nil && oneAtFiles.query == fileQuery ? oneAtFiles.rows : []
        let key = OneAtKey(text: text, letters: letters, selection: selection?.text, generation: commandsGeneration, usage: commandUsage,
                           app: app, noAI: noAI, files: files.map(\.path), main: inputLanguages.first ?? .chinese,
                           language: messages.language)
        if let cached = oneAtCache, cached.key == key { return cached.rows }
        // The commands the letters start (nothing typed: all of them, as the command list keeps them).
        let named = letters.map { matches(for: $0) } ?? (text.isEmpty && selection == nil ? matches(for: "") : [])
        let input = OneAt.Input(text: text, letters: letters, selection: selection.flatMap { selectionFits ? $0.text : nil },
                                commands: commands, named: named, usage: commandUsage, app: app,
                                chat: AppClass(app: app) == .chat, noAI: noAI, mainLanguage: key.main,
                                instant: instantResults, files: files, reminder: { [parseReminder] in parseReminder($0) },
                                words: commandWords())
        var rows = OneAt.actions(input)
        // A selection in an app with No AI and nothing typed: no action is left for it but the commands that don't use AI.
        if rows.isEmpty, selection != nil, text.isEmpty {
            rows = Command.palette("", in: commands, usage: commandUsage, app: app, limit: .max).filter { !$0.usesAI }.map(OneAt.Action.command)
        }
        // A new text (or selection): the highlight on its first row. The same text with rows that came or went (Spotlight's
        // files, the commands): a highlight moved with ↑↓ stays on its row while it is listed.
        let before = oneAtCache?.key
        if before?.text != key.text || before?.letters != key.letters || before?.selection != key.selection {
            oneAtReset()
        } else if oneAtHighlightMoved, let id = oneAtHighlightedID, let index = rows.firstIndex(where: { $0.id == id }) {
            oneAtHighlight = index
        } else {
            oneAtHighlight = 0
            oneAtHighlightMoved = false
        }
        oneAtCache = (key, rows)
        return rows
    }

    /// What the rows were worked out from: the same, the same rows.
    struct OneAtKey: Equatable {
        var text: String
        var letters: String?
        var selection: String?
        var generation: Int
        var usage: CommandUsage
        var app: String?
        var noAI: Bool
        var files: [String]
        var main: Language
        var language: String
    }

    /// The words each of the user's commands is found by (`words(of:)`, split as `OneAt.words` splits them), worked out
    /// once for the commands: with many extensions a key mustn't fold all their titles again.
    private func commandWords() -> (Command) -> [String] {
        if oneAtWords.generation != commandsGeneration {
            var words: [String: [String]] = [:]
            for command in commands where command.custom != nil || command.plugin != nil || command.script != nil {
                words[command.name] = Self.words(of: command).flatMap(OneAt.words)
            }
            oneAtWords = (commandsGeneration, words)
        }
        let words = oneAtWords.words
        return { words[$0.name] ?? [] }
    }

    /// The words a command is found by besides its name (`OneAt.found(byWords:)`): a custom command's or a snippet's
    /// summary, a plugin's (in English and Chinese), a script extension's title and keywords.
    static func words(of command: Command) -> [String] {
        var words: [String] = []
        if let summary = command.custom?.summary { words.append(summary) }
        if let summary = command.plugin?.manifest.summary { words += [summary.en] + (summary.zh.map { [$0] } ?? []) }
        if let script = command.script { words += [script.title] + script.searchTerms }
        return words
    }

    /// The highlighted row, among `oneAtRows`.
    public var oneAtHighlighted: Int {
        let count = oneAtRows.count
        return count == 0 ? 0 : min(oneAtHighlight, count - 1)
    }

    /// The first row shown: where the list was scrolled to, moved just enough to show the highlight.
    public var oneAtFirstVisible: Int {
        let count = oneAtRows.count, highlight = oneAtHighlighted, shown = Self.oneAtRowsShown
        var top = min(oneAtTop, max(count - shown, 0))
        if highlight < top { top = highlight } else if highlight >= top + shown { top = highlight - shown + 1 }
        return max(top, 0)
    }

    /// The rows shown now.
    public var oneAtVisible: ArraySlice<OneAt.Action> {
        let rows = oneAtRows, first = oneAtFirstVisible
        return rows[first..<min(first + Self.oneAtRowsShown, rows.count)]
    }

    /// The highlight and the scroll back where a new list starts.
    func oneAtReset() {
        oneAtHighlight = 0
        oneAtTop = 0
        oneAtHighlightMoved = false
        oneAtHighlightedID = nil
    }

    /// Moves the highlight by `steps` (↑↓, the scroll wheel), round the ends, scrolling with it.
    func moveOneAtHighlight(by steps: Int, wraps: Bool = true) {
        let rows = oneAtRows, count = rows.count
        guard count > 0 else { return }
        let current = oneAtHighlighted
        oneAtHighlight = wraps ? ((current + steps) % count + count) % count : min(max(current + steps, 0), count - 1)
        oneAtTop = oneAtFirstVisible
        oneAtHighlightMoved = true
        oneAtHighlightedID = rows[oneAtHighlight].id
    }

    /// Keys while one @ is written. ⏎ and the action key do the highlighted row (with a lone magic key and no selection
    /// ⏎ puts the key in, as before); Tab picks a command or does the row; ↑↓ move among the rows, also while pinyin is
    /// composed; Esc leaves the text as typed, also while pinyin is composed (a selection as it is); a digit that goes on
    /// a name composed after the key is part of it (`@base64`); → at the end of the text leaves it as typed and
    /// moves on in the app. Right after the magic key a space or a mark leaves it as typed (`@ ` is an at sign); letters,
    /// digits and "(" start the text. While the letters composed are a command's whole name, Space picks the command, as
    /// `@name ` writes it. Nil: the key acts as usual (into the text, the engine, ⌫).
    func handleOneAtKey(_ event: KeyEvent, composing: Bool) -> Response? {
        guard oneAt != nil else { return nil }
        let modifiers = event.modifiers.subtracting(.capsLock)
        let plain = modifiers.subtracting(.shift).isEmpty
        let lone = draft == commandTrigger && !composing
        switch event.key {
        case .enter, .keypadEnter:
            // ⇧⏎: as typed.
            if modifiers == [.shift] { return .consumed(finishOneAsTyped()) }
            guard modifiers.isEmpty else { return nil }
            if lone, selection == nil { return .consumed(finish(committing: draft, selection: .kept)) }
            // No row at all (a text in an app with No AI): the text goes in as typed, never a dead end.
            if oneAtRows.isEmpty, selection == nil { return .consumed(finishOneAsTyped()) }
            return .consumed(doHighlightedOneAt(run: true))
        case .tab where plain:
            guard !oneAtRows.isEmpty else { return lone ? commitPalette(then: event) : .consumed() }
            return .consumed(doHighlightedOneAt(run: false))
        case .arrow(.up), .arrow(.down):
            guard plain else { return nil }
            moveOneAtHighlight(by: event.key == .arrow(.up) ? -1 : 1)
            return .consumed([.showPanel])
        case .escape:
            if selection != nil { return .consumed(finish(committing: "", selection: .kept)) }
            // The magic key alone is given up, as before; a text stays as typed, pinyin composed as its letters.
            guard lone else { return .consumed(finishOneAsTyped()) }
            draft = ""
            setLevelOnePhase()
            return .consumed([.updateMarkedText, .hidePanel])
        case .arrow(.right) where !composing && plain && cursorTailCount == 0:
            // The keys given back: the text goes in as typed, and → moves on in the app.
            if selection != nil { return Response(effects: finish(committing: "", selection: .kept), handled: false) }
            return commitPalette(then: event)
        case .space where composing && plain:
            // The letters are a command's whole name: Space picks it, as "@name " writes it.
            guard let letters = oneAt?.letters?.lowercased(), let command = commands.first(where: { $0.name == letters }) else { return nil }
            return .consumed(doOneAt(.command(command), run: false))
        default:
            break
        }
        // A digit that goes on the name composed right after the key (`@base6`) is part of it, as in 0.6.9: the letters
        // leave the engine, as typed; any other digit picks a candidate.
        if composing, draft == commandTrigger, plain, let engine, let text = event.printableText, text.count == 1,
           let c = text.first, c.isASCII, c.isNumber, case let name = engine.rawInput.lowercased() + text,
           name.first?.isLetter == true, commands.contains(where: { $0.name.hasPrefix(name) }) {
            let letters = engine.rawInput
            engine.clearComposition()
            engineState = engine.snapshot()
            draft += letters + text
            setLevelOnePhase()
            return .consumed([.updateMarkedText, .showPanel])
        }
        guard lone else { return nil }
        // Right after the magic key: a key that isn't the list's (←, Home, End, Page Up…, a shortcut such as ⌃V) puts the
        // key in and goes to the app, as in 0.6.9; so does a space or a mark (`@ ` is an at sign).
        if [Key.arrow(.left), .home, .end, .pageUp, .pageDown, .forwardDelete].contains(event.key)
            || !modifiers.isDisjoint(with: [.control, .command]) { return commitPalette(then: event) }
        if event.key == .space { return plain ? commitPalette(then: event) : nil }
        guard plain, let text = event.printableText, let c = text.first, text.count == 1 else { return nil }
        if c.isLetter || c.isNumber || c == "(" || !c.isASCII { return nil }
        return commitPalette(then: event)
    }

    /// The action key on one @ (nil: not written): the highlighted row, as ⏎ does it (a lone magic key without a
    /// selection: nil, the key as before).
    func oneAtActionKey() -> [Effect]? {
        guard oneAt != nil else { return nil }
        if draft == commandTrigger, !engineState.isComposing, selection == nil { return nil }
        if oneAtRows.isEmpty, selection == nil { return finishOneAsTyped() }
        return doHighlightedOneAt(run: true)
    }

    /// A row clicked (`index` among those shown): done as ⏎ does it. Clicked while the selection is read after the key
    /// (`selectionPending`), the row shown is parked for the read and done once it is in; clicked while a key is parked,
    /// that key is done first, as if nothing were selected, and the row then only if it is still listed.
    func chooseOneAt(_ index: Int) -> [Effect] {
        let row = oneAtFirstVisible + index, rows = oneAtRows
        guard rows.indices.contains(row) else { return [] }
        guard selectionPending else {
            oneAtHighlight = row
            return doOneAt(rows[row], run: true)
        }
        if parkedForSelection == nil {
            parkForSelection(.row(rows[row]))
            return []
        }
        let settled = selectionRead(nil)
        guard oneAt != nil, let listed = oneAtRows.firstIndex(of: rows[row]) else { return settled }
        oneAtHighlight = listed
        return settled + doOneAt(rows[row], run: true)
    }

    /// The scroll wheel over the list: the highlight moves, stopping at the first and the last. Not while a key is parked
    /// for the selection read (`parkedForSelection`): it is done on the row it was pressed on, and the list then goes.
    func scrollOneAt(by steps: Int) -> [Effect] {
        guard !oneAtRows.isEmpty, steps != 0, parkedForSelection == nil else { return [] }
        moveOneAtHighlight(by: steps, wraps: false)
        return [.showPanel]
    }

    /// The highlighted row done (`run`: ⏎ or the action key, which also runs a command that takes no text; Tab only
    /// picks it). Never while the selection is still being read (`selectionPending`): the key is parked for it.
    func doHighlightedOneAt(run: Bool) -> [Effect] {
        let rows = oneAtRows
        guard rows.indices.contains(oneAtHighlighted) else { return [] }
        return doOneAt(rows[oneAtHighlighted], run: run)
    }

    /// What a row does (`OneAt.Action`): a command is picked as the command list picks it; a value goes in place of the
    /// text; an app, a folder, a file or a web address opens; a reminder is added; a writing action does what `@name
    /// text` does, the text converted first (its pinyin, as Space would pick it).
    func doOneAt(_ action: OneAt.Action, run: Bool) -> [Effect] {
        switch action {
        case let .command(command):
            // The letters composed were its name: they go.
            if engineState.isComposing, let engine {
                engine.clearComposition()
                engineState = engine.snapshot()
            }
            draft = commandTrigger
            cursorTail = ""
            let effects = complete([command], at: 0, run: run)
            return effects
        case let .value(value):
            return finish(committing: value)
        case let .open(result):
            return finish(committing: "") + [opening(result.path), used(.open)]
        case let .reminder(reminder):
            let text = oneAt?.text.trimmingCharacters(in: .whitespaces) ?? ""
            return finish(committing: "") + [.addReminder(reminder, input: text), used(.reminder)]
        case let .write(command):
            return writeOneAt(command)
        case .edit:
            return writeOneAt(.improve)
        }
    }

    /// The text given to `command`, as `@name text` gives it: the pinyin converted, the draft "@name text", run.
    private func writeOneAt(_ command: Command) -> [Effect] {
        var effects: [Effect] = []
        if let engine, engine.snapshot().isComposing { effects += convertComposition(engine) }
        let text = String(draft.dropFirst(commandTrigger.count)).trimmingCharacters(in: .whitespaces)
        draft = "\(commandTrigger)\(command.name) " + text
        cursorTail = ""
        setLevelOnePhase()
        let started = startAction().effects
        // Refused (no AI here, secure input): the draft is the command's now, as if typed so.
        return effects + (isLevelTwo || phase == .idle ? started : [.updateMarkedText, .showPanel] + started)
    }

    /// Esc, ⇧⏎: the text goes in as typed, the magic key and any pinyin letters with it. With a selection nothing goes in,
    /// as typed elsewhere (`finishAsTyped`): no "@…" over it.
    private func finishOneAsTyped() -> [Effect] {
        var text = draft
        if let engine, engine.snapshot().isComposing { text += engine.rawInput }
        return finish(committing: text, selection: .kept)
    }

    // MARK: Spotlight's files

    /// The one @ text Spotlight's names are looked for (`SessionServices.searchFileNames`), as for `@open`: one that may
    /// name a file (two characters or more, a few words, no sum or web address), or a path ("~/Downloads/", however
    /// long: its folder is listed, off the key's thread), not while pinyin is composed nor on a selection. Nil: none.
    public var oneAtFileQuery: String? {
        guard let (text, _) = oneAt, selection == nil, !engineState.isComposing else { return nil }
        let query = text.trimmingCharacters(in: .whitespaces)
        let path = query.hasPrefix("/") || query.hasPrefix("~")
        guard FileSearchRanking.searchesAsYouType(query), path || query.count <= 40 && query.split(separator: " ").count <= 3,
              Arithmetic.value(of: query) == nil, SearchResult.web(query) == nil else { return nil }
        return query
    }

    /// The files Spotlight found for `query` (so far, unless `isFinal`): rows below what is known at once, for the text
    /// they are for; for one typed before, those that match the text now are added (`LiveRows`).
    public func receiveOneAtFiles(_ results: [SearchResult], for query: String, isFinal: Bool = true) -> [Effect] {
        let current = oneAtFileQuery
        if let current, oneAtFiles.query != current {
            let keywords = FileSearchRanking.keywords(in: current)
            oneAtFiles.show(current, fits: { Self.stillMatches($0, keywords, for: current) })
        }
        let keywords = FileSearchRanking.keywords(in: current ?? "")
        let changed = oneAtFiles.receive(results.filter { !$0.matchedContent }, for: query, current: current, isFinal: isFinal,
                                         fits: { Self.stillMatches($0, keywords, for: current ?? "") })
        return changed ? [.showPanel] : []
    }

    /// The files listed for the one @ text now: those found for it, else those for the text before that still match it.
    func showOneAtFiles() {
        guard let query = oneAtFileQuery else { return }
        let keywords = FileSearchRanking.keywords(in: query)
        oneAtFiles.show(query, fits: { Self.stillMatches($0, keywords, for: query) })
    }

    // MARK: The selection, read after the key

    /// What was taken while the selection was read after the "@" key, done once it is in (`selectionRead`).
    enum ParkedForSelection: Equatable {
        /// A key the list takes whatever the selection turns out to be (`SelectionReadKey.parks`), handled then.
        case key(KeyEvent)
        /// The action key as a tap (`ActionKey.optionTap`).
        case actionKeyTap
        /// A row clicked, done as it was shown.
        case row(OneAt.Action)
    }

    /// What a key does while the selection after the "@" key is being read (`selectionPending`).
    enum SelectionReadKey {
        /// It only edits the draft in the panel, the same with a selection or without one: handled as usual, the read
        /// still awaited.
        case edits
        /// The list takes it whatever the selection turns out to be: parked (`parkedForSelection`), and done once the
        /// read is in. The key returns at once, so the app can answer the read.
        case parks
        /// Any other key, and every key while one is parked: what is parked is done and the read settled, as if nothing
        /// were selected (its late answer is dropped), and the key is then handled at once.
        case settles
    }

    /// How `event` goes while the selection after the "@" key is being read (nil: none is). Draft edits are the letters
    /// and digits typed into it, ⌫ and ↑↓. Parked: ⏎, ⇧⏎, Esc, the action key, and Tab, each where the list takes it
    /// with a selection and without one; right after the magic key the action key or Tab may not be the list's without a
    /// selection (the key went on to the app), and then it settles the read instead.
    func whileSelectionIsRead(_ event: KeyEvent) -> SelectionReadKey? {
        guard selectionPending, draft.hasPrefix(commandTrigger) else { return nil }
        guard oneAt != nil, parkedForSelection == nil else { return .settles }
        let modifiers = event.modifiers.subtracting(.capsLock)
        let lone = draft == commandTrigger && !engineState.isComposing
        // The list's own keys, taken with nothing selected too.
        let listsKey: Bool
        switch event.key {
        case .enter, .keypadEnter: listsKey = modifiers.isEmpty || modifiers == [.shift]
        case .escape: listsKey = modifiers.isEmpty
        case .tab: listsKey = modifiers.subtracting(.shift).isEmpty && (!lone || !oneAtRows.isEmpty)
        case .arrow(.up), .arrow(.down): listsKey = modifiers.isEmpty
        default: listsKey = false
        }
        // The action key does the highlighted row, with a selection or text typed; right after the magic key with nothing
        // selected it is the list's only if it is one of its keys (⏎).
        if isActionKey(event) { return !lone || listsKey ? .parks : .settles }
        switch event.key {
        case .backspace, .arrow(.up), .arrow(.down):
            return modifiers.isEmpty ? .edits : .settles
        case .enter, .keypadEnter, .escape, .tab:
            return listsKey ? .parks : .settles
        default:
            guard modifiers.subtracting(.shift).isEmpty, let text = event.printableText, !text.isEmpty,
                  text.allSatisfy({ $0.isLetter || $0.isNumber }) else { return .settles }
            return .edits
        }
    }

    /// Before the session's own panels may take `event` (`InputSession`): a key that settles the read
    /// (`whileSelectionIsRead`) settles it now, so that whatever takes the key comes after what was parked.
    public func settleSelectionRead(before event: KeyEvent) -> [Effect] {
        whileSelectionIsRead(event) == .settles ? selectionRead(nil) : []
    }

    /// The selection the field reads after the key (`selectionPending`) arrived (nil: none, or the read gave up, or a key
    /// settled it): the list is for it from now on, and what was parked for it is done now, exactly as where the field
    /// tells the selection with the key.
    public func selectionRead(_ selected: Selection?) -> [Effect] {
        guard selectionPending else { return [] }
        selectionPending = false
        let parked = parkedForSelection
        parkedForSelection = nil
        guard draft.hasPrefix(commandTrigger) else { return [] }
        if let selected, !selected.text.isEmpty {
            selection = selected
            selectionFits = selected.text.count <= Self.maxSelectionLength
        }
        oneAtCache = nil
        let effects = forField([.updateMarkedText, .showPanel])
        switch parked {
        case let .key(event)?:
            return effects + handleKeyDown(event).effects
        case .actionKeyTap?:
            return effects + forField(actionKeyPressed() ?? [])
        case let .row(action)?:
            guard oneAt != nil else { return effects }
            oneAtHighlight = oneAtRows.firstIndex(of: action) ?? oneAtHighlighted
            return effects + forField(doOneAt(action, run: true))
        case nil:
            return effects
        }
    }
}
