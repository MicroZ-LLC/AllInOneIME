import Foundation

/// Clipboard history in one text field's session (Session/ClipboardHistory.swift, where the seam is described): the panel
/// ⌃V shows, its rows, the row chosen and those selected with ⇧↓ ⇧↑, what goes in.
struct ClipboardHistoryField {
    /// A row of the panel.
    enum Row: Equatable {
        /// A text, copied at `copiedAt` (nil: the clipboard's, which the history doesn't have).
        case text(String, copiedAt: Date?)
        /// An image on the clipboard (a screenshot).
        case image
        /// How to keep a history (`ClipboardHistoryState.notAllowed`).
        case permission
    }

    /// The reads of the clipboard ⌃V asked for, counted (their ids are below 0), and the one awaited, with whether a
    /// command's text takes the row.
    var reads = 0
    var reading: (id: Int, command: Bool)?
    /// The rows, newest first; the chosen one (drawn selected), and where ⇧↓ ⇧↑ started (nil: the chosen row alone).
    var rows: [Row] = []
    var chosen = 0
    var anchor: Int?
    /// The first row shown (5 at a time, as suggestions' rows).
    var top = 0
    /// The panel shows the rows; a command's text takes the row (else it goes into the field); the first showing on
    /// this device (its footer says where the history is kept); ⌃V can go to the app for the image row, as the shell
    /// said when the panel opened (asked again on ⏎).
    var shown = false
    var command = false
    var first = false
    var passesPasteKey = false
}

extension InputSession {
    // MARK: - Opening

    /// Whether `event` is the paste-anywhere key (`ModifierRoles.pasteAnywhere` with V: ⌃V on the Mac), nothing else held.
    public func isPasteAnywhere(_ event: KeyEvent) -> Bool {
        guard let paste = composer.modifierRoles.pasteAnywhere else { return false }
        return event.modifiers.subtracting(.capsLock).subtracting(.sides) == Modifiers.kind(paste)
            && event.charactersIgnoringModifiers.lowercased() == "v"
    }

    /// Where ⌃V opens the panel: the history on and kept by the shell, the panel allowed in this field
    /// (`clipboardPanelAllowed`), no secure input, no voice, and a command's text that takes ⌃V (true; not while the
    /// history isn't allowed: there ⌃V is as before) or nothing composed but Code's word (false). Nil: ⌃V is as before
    /// 0.6.8.
    func clipboardOpensIn() -> Bool? {
        let state = services.clipboardHistory.state()
        guard services.loadSettings().clipboardHistoryOn, state != .unavailable, clipboardPanelAllowed, !secureInputActive(),
              composer.voice == .off
        else { return nil }
        if composer.codeWord == nil, composer.takesPasteAnywhere { return state == .notAllowed ? nil : true }
        return composesBesidesCodeWord ? nil : false
    }

    /// Before suggestions' rows and the composer have `event`: ⌃V opens the panel (the clipboard read first, once the key
    /// is done: `SessionOutput.readClipboard`), and while it shows, its keys (`clipboardKey`). Nil: the key goes on.
    func clipboardBeforeKey(_ event: KeyEvent) -> Bool? {
        if clipboard.shown { return clipboardKey(event) }
        if clipboard.reading != nil {
            // A key before the clipboard was read: the panel isn't shown for it; ⌃V again is as ⌃V again.
            let command = clipboard.reading?.command ?? false
            clipboard.reading = nil
            if isPasteAnywhere(event) { return command ? nil : false }
        }
        guard isPasteAnywhere(event), let command = clipboardOpensIn() else { return nil }
        clipboardTookKey()
        autocompleteLeft(.ignored)
        if !command {
            // Code's word goes in as typed; a paste ends the token, and suggestions' rows go (the history takes their place).
            if let word = composer.codeWord {
                perform(composer.endCodeWord())
                lastTyped.typedIn(word, at: ProcessInfo.processInfo.systemUptime)
            }
            suggestionsBoundary()
            suggestionsUpdate()
            emit(.rowsTookKey)
        }
        clipboard.reads += 1
        clipboard.reading = (-clipboard.reads, command)
        emit(.readClipboard(id: -clipboard.reads))
        return true
    }

    /// The clipboard as read for ⌃V (`id`, below 0): the panel with it and the history, unless the field changed
    /// meanwhile (a command sent, something composed); with nothing to show, the composer's notice.
    func clipboardRead(_ content: ClipboardContent, id: Int) {
        guard let reading = clipboard.reading, reading.id == id else { return }
        clipboard.reading = nil
        guard clipboardOpensIn() == reading.command else { return }
        let rows = clipboardRows(content)
        guard !rows.isEmpty else { return say(composer.messages.nothingToPaste) }
        clipboard = ClipboardHistoryField(reads: clipboard.reads, rows: rows, shown: true, command: reading.command,
                                          first: services.clipboardHistory.firstShowing(),
                                          passesPasteKey: rows.first == .image && services.clipboardHistory.canPassPasteKey())
        log.notice("clipboard history: shown (\(rows.count) rows\(reading.command ? ", in a command" : ""))")
        emit(.panel(clipboardPanel()))
    }

    /// The panel's rows, newest first: an image on the clipboard, else its text unless it is the history's newest; the
    /// history's texts (`Config.clipboardHistoryKept` at most), each once; how to keep a history, where it can't yet.
    func clipboardRows(_ content: ClipboardContent) -> [ClipboardHistoryField.Row] {
        let history = services.clipboardHistory
        let items = Array(history.items().prefix(services.loadSettings().clipboardHistoryKept))
        var rows: [ClipboardHistoryField.Row] = []
        var current: String?
        switch content {
        case .image:
            rows.append(.image)
        case let .text(text):
            // As the history would have kept it: some text, not too long.
            if text.utf16.count <= ClipboardHistoryItem.maxLength * 4, text.count <= ClipboardHistoryItem.maxLength,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, items.first?.text != text {
                rows.append(.text(text, copiedAt: nil))
                current = text
            }
        case .none:
            break
        }
        rows += items.filter { $0.text != current }.map { .text($0.text, copiedAt: $0.copiedAt) }
        if history.state() == .notAllowed { rows.append(.permission) }
        return rows
    }

    /// Whether the panel shows (from the clipboard's read for ⌃V until it is hidden or a row goes in).
    public var clipboardShown: Bool { clipboard.shown }

    // MARK: - Keys

    /// A key the panel takes: no long press of Shift with it (as every key suggestions' rows see).
    private func clipboardTookKey() {
        shiftHold.keyDown()
        suggesting.shift += 1
        holdHintEnds()
    }

    /// While the panel shows: ↓ ↑ move the choice around the ends (a selection ends), ⇧↓ ⇧↑ extend the selection from the
    /// row chosen when it started, ⏎ keypad Enter and Tab put in what is selected, → and Esc hide the panel, ⌃V again hides
    /// it and gives ⌃V as it is (outside a command the app's: false; in one the composer's: nil). Any other key hides it
    /// and goes on (nil): digits are typed, never pick.
    func clipboardKey(_ event: KeyEvent) -> Bool? {
        if isPasteAnywhere(event) {
            clipboardTookKey()
            let command = clipboard.command
            log.notice("clipboard history: ⌃V again, as it is")
            clipboardHide()
            return command ? nil : false
        }
        let modifiers = event.modifiers.subtracting(.capsLock).subtracting(.sides)
        let arrow = event.key == .arrow(.down) || event.key == .arrow(.up)
        if arrow, modifiers.isEmpty || modifiers == [.shift] {
            clipboardTookKey()
            if !clipboard.command { emit(.rowsTookKey) }
            let (down, count) = (event.key == .arrow(.down), clipboard.rows.count)
            if modifiers == [.shift] {
                if clipboard.anchor == nil { clipboard.anchor = clipboard.chosen }
                clipboard.chosen = min(max(clipboard.chosen + (down ? 1 : -1), 0), count - 1)
            } else {
                clipboard.anchor = nil
                clipboard.chosen = (clipboard.chosen + (down ? 1 : -1) + count) % count
            }
            clipboardReveal()
            emit(.panel(clipboardPanel()))
            return true
        }
        guard modifiers.isEmpty else {
            clipboardHide()
            return nil
        }
        switch event.key {
        case .enter, .keypadEnter, .tab:
            clipboardTookKey()
            clipboardPut(clipboardSelection(), key: event)
            return true
        case .arrow(.right), .escape:
            clipboardTookKey()
            if !clipboard.command { emit(.rowsTookKey) }
            clipboardHide()
            return true
        default:
            clipboardHide()
            return nil
        }
    }

    /// A row of the panel clicked (`index` among those shown): that row put in, alone (true); false: not ours.
    func clipboardPick(_ index: Int) -> Bool {
        guard clipboard.shown, index >= 0, clipboard.rows.indices.contains(clipboard.top + index) else { return false }
        clipboardPut([clipboard.top + index], key: nil)
        return true
    }

    /// The wheel or the trackpad over the panel (`steps` rows, down positive): the choice moves, stopping at the first and
    /// the last, a selection ending. True: ours.
    func clipboardScroll(_ steps: Int) -> Bool {
        guard clipboard.shown else { return false }
        let target = min(max(clipboard.chosen + steps, 0), clipboard.rows.count - 1)
        guard steps != 0, target != clipboard.chosen || clipboard.anchor != nil else { return true }
        (clipboard.chosen, clipboard.anchor) = (target, nil)
        clipboardReveal()
        emit(.panel(clipboardPanel()))
        return true
    }

    /// The rows shown moved just enough to have the chosen one among them.
    private func clipboardReveal() {
        let shown = Self.shownSuggestionRows
        if clipboard.chosen < clipboard.top {
            clipboard.top = clipboard.chosen
        } else if clipboard.chosen >= clipboard.top + shown {
            clipboard.top = clipboard.chosen - shown + 1
        }
        clipboard.top = min(max(clipboard.top, 0), max(clipboard.rows.count - shown, 0))
    }

    /// The rows selected (⇧↓ ⇧↑ from `anchor` to the chosen one), in the panel's order; else the chosen row.
    func clipboardSelection() -> [Int] {
        guard let anchor = clipboard.anchor, anchor != clipboard.chosen else { return [clipboard.chosen] }
        return Array(min(anchor, clipboard.chosen)...max(anchor, clipboard.chosen))
    }

    /// The panel hidden (→, Esc, ⌃V again, another key, the field left): the composer's panel back in a command.
    func clipboardHide() {
        let shown = clipboard.shown
        clipboard = ClipboardHistoryField(reads: clipboard.reads)
        if shown { emit(.panel(composer.wantsPanel ? panelModel() : nil)) }
    }

    /// The field was left or closed, or a click in it: no panel, no read awaited.
    func clipboardLeft() {
        clipboardHide()
    }

    // MARK: - Putting rows in

    /// `picked` (rows of the panel) put in, the panel hidden. Texts in the order they were copied, oldest first (the
    /// reverse of the rows'), one per line, each without the line breaks at its end; one alone as it was copied. Outside a
    /// command as suggestions' rows go in (`rowByKey` first for a key, then a `commit`: in a terminal that can't take a
    /// paste, on one line); in one, as ⌃V pastes into it (`Composer.pasteAnywhere`). The image row alone: outside a
    /// command ⌃V given to the app as it is where it can be (`PlatformAction.passPasteKey`), in one today's ⌃V; how to
    /// keep a history: where to allow it opens.
    func clipboardPut(_ picked: [Int], key: KeyEvent?) {
        let (rows, command) = (clipboard.rows, clipboard.command)
        let texts = picked.reversed().compactMap { index -> String? in
            guard rows.indices.contains(index), case let .text(text, _) = rows[index] else { return nil }
            return text
        }
        guard !texts.isEmpty else {
            let index = picked.count == 1 ? picked[0] : clipboard.chosen
            let row = rows.indices.contains(index) ? rows[index] : nil
            if key != nil, !command { emit(.rowsTookKey) }
            clipboard = ClipboardHistoryField(reads: clipboard.reads)
            switch row {
            case .image? where command:
                // Today's ⌃V in a command: the clipboard read, its image as `@reply` reads it.
                log.notice("clipboard history: the image, as ⌃V in a command")
                perform(composer.pasteAnywhere(nil) ?? [.showPanel])
            case .image?:
                emit(.panel(nil))
                if services.clipboardHistory.canPassPasteKey() {
                    log.notice("clipboard history: the image, ⌃V given to the app")
                    emit(.platform(.passPasteKey))
                }
            case .permission?:
                emit(.panel(composer.wantsPanel ? panelModel() : nil))
                services.clipboardHistory.openPermission()
            case .text?, nil:
                emit(.panel(composer.wantsPanel ? panelModel() : nil))
            }
            return
        }
        let text = texts.count == 1 ? texts[0] : texts.map(Self.withoutEndingLineBreaks).joined(separator: "\n")
        clipboard = ClipboardHistoryField(reads: clipboard.reads)
        log.notice("clipboard history: \(texts.count) put in (\(text.count) characters\(command ? ", into a command" : ""))")
        if command {
            perform(composer.pasteAnywhere(.text(text)) ?? [.showPanel])
            return
        }
        // Line breaks into a terminal only as a paste (a line break typed there is Return): else on one line.
        let put = terminal && text.contains(where: \.isNewline) && !services.pastesInTerminal() ? Composer.oneLine(text) : text
        if key != nil { emit(.rowByKey) }
        emit(.commit(put))
        lastTyped.forget()
        suggestionsBoundary()
        emit(.panel(nil))
    }

    /// `text` without the line breaks at its end: a line copied with its own.
    static func withoutEndingLineBreaks(_ text: String) -> String {
        var text = Substring(text)
        while text.last?.isNewline == true { text.removeLast() }
        return String(text)
    }

    // MARK: - The panel

    /// The panel while it shows: 5 rows at a time from `top`, the chosen one drawn selected, "✓" on those selected, no
    /// number on a row (digits are typed); the keys in the footer (the first showing: where it's kept, how to turn it off),
    /// on its right "Clipboard" with how many are selected and which rows show, or the notice.
    func clipboardPanel() -> PanelModel? {
        guard clipboard.shown, !clipboard.rows.isEmpty else { return nil }
        let t = InterfaceWords(language: UIText.language)
        let (all, shown) = (clipboard.rows.count, Self.shownSuggestionRows)
        let window = clipboard.top..<min(clipboard.top + shown, all)
        let selection = clipboardSelection()
        let selected = selection.count > 1 ? Set(selection) : []
        let now = services.clipboardHistory.now()
        let passes = clipboard.command || clipboard.passesPasteKey
        let rows = window.map { index in
            let (text, comment) = Self.clipboardRowText(clipboard.rows[index], now: now, passesPasteKey: passes, in: t)
            return PanelModel.Row(label: selected.contains(index) ? "✓" : "", text: text, comment: comment, kind: .candidate,
                                  pickable: clipboard.rows[index] != .permission, choice: index)
        }
        let terms = Platform.current.terms
        let enter = terms.enter
        let footer: String
        if clipboard.first {
            footer = t.tr("只存在这台 Mac 上；在设置 →「通用」→「剪贴板历史」里可以关掉",
                          "Kept on this Mac only; turn it off in Settings → General → Clipboard history")
        } else if !selected.isEmpty {
            footer = t.tr("\(enter) 一行一条插入 · ⇧↑⇧↓ 多选 · → 或 Esc 隐藏", "\(enter) inserts them, one per line · ⇧↑⇧↓ select · → or Esc hides")
        } else {
            footer = t.tr("\(enter) 插入 · ↑↓ 选择 · ⇧↓ 多选 · → 或 Esc 隐藏", "\(enter) inserts · ↑↓ to pick · ⇧↓ selects more · → or Esc hides")
        }
        var detail = t.tr("剪贴板", "Clipboard")
        if !selected.isEmpty { detail += t.tr(" · 已选 \(selected.count) 条", " · \(selected.count) selected") }
        if all > shown { detail += " · \(window.lowerBound + 1)–\(window.upperBound) / \(all)" }
        let highlighted = window.contains(clipboard.chosen) ? clipboard.chosen - window.lowerBound : nil
        return PanelModel(rows: rows, highlighted: highlighted, footer: footer, detail: notice ?? detail)
    }

    /// The most of a text's first line a row shows.
    static let clipboardRowLength = 80

    /// A row's text and comment: a text's first line that isn't blank, trimmed, with "+N lines" or its length and how
    /// long ago it was copied (or that it is on the clipboard); the image, with how ⌃V pastes it where ⏎ can't
    /// (`passesPasteKey` false); how to keep a history, and that ⏎ opens where.
    static func clipboardRowText(_ row: ClipboardHistoryField.Row, now: Date, passesPasteKey: Bool,
                                 in t: InterfaceWords) -> (text: String, comment: String) {
        let terms = Platform.current.terms
        switch row {
        case .image:
            return (t.tr("剪贴板里的图片", "Image on the clipboard"),
                    passesPasteKey ? "" : t.tr("再按 \(terms.paste) 粘贴", "\(terms.paste) again pastes it"))
        case .permission:
            return (t.tr("要记下历史，请允许「从其他App粘贴」", "To keep a history, allow Paste from Other Apps"),
                    t.tr("\(terms.enter) 打开「隐私与安全性」", "\(terms.enter) opens Privacy & Security"))
        case let .text(text, copiedAt):
            let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            let first = String(lines.first ?? "").map { $0.isWhitespace || $0.unicodeScalars.contains { $0.properties.generalCategory == .control } ? " " : String($0) }
                .joined().trimmingCharacters(in: .whitespaces)
            let shown = first.count > clipboardRowLength ? String(first.prefix(clipboardRowLength)) + "…" : first
            let more = lines.count - 1
            let size = more == 1 ? t.tr("+1 行", "+1 line") : more > 1 ? t.tr("+\(more) 行", "+\(more) lines")
                : text.count == 1 ? t.tr("1 字", "1 char") : t.tr("\(text.count) 字", "\(text.count) chars")
            let when = copiedAt.map { RelativeTime.ago($0, now: now, language: t.language, style: .short) }
                ?? t.tr("剪贴板里的", "on the clipboard")
            return (shown, size + " · " + when)
        }
    }
}
