import Foundation

/// ← and → on the clipboard history's rows (`clipboardKey`), and the footer that names the panel's keys. One rule for →
/// on every list (#178): on more than a page with nothing typed it turns the page (← back); with text typed (here the
/// filter) it puts that text in as typed and gives the keys back; on one page with nothing typed it gives the keys back.
extension InputSession {
    /// ← or → with no modifier while the panel shows. No filter typed and more rows than a page: the page before or
    /// after, its first row chosen (a selection ends); at the first ← and at the last → stay. A filter typed: → puts it
    /// in as it was typed (no row, whichever is chosen), the panel hidden and the next keys the app's. Nil: not handled
    /// here (→ on one page hides the panel, ← hides it and goes on, as before).
    func clipboardSideArrow(_ event: KeyEvent) -> Bool? {
        guard event.key == .arrow(.left) || event.key == .arrow(.right) else { return nil }
        if clipboard.filter.isEmpty {
            guard ListPage.turns(clipboard.rows.count) else { return nil }
            clipboardTookKey()
            if !clipboard.command { emit(.rowsTookKey) }
            if let next = ListPage.turned(event.key == .arrow(.left) ? -1 : 1, first: clipboard.top, count: clipboard.rows.count) {
                (clipboard.top, clipboard.chosen, clipboard.anchor) = (next, next, nil)
            }
            emit(.panel(clipboardPanel()))
            return true
        }
        guard event.key == .arrow(.right) else { return nil }
        clipboardTookKey()
        let typed = clipboard.filter
        clipboardForget()
        // The count of characters only: nothing typed is logged.
        log.notice("clipboard history: the filter put in as typed (\(typed.count) characters)")
        emit(.rowByKey)
        emit(.commit(typed))
        lastTyped.forget()
        suggestionsBoundary()
        emit(.panel(composer.wantsPanel ? panelModel() : nil))
        return true
    }

    /// The panel's keys, for `rows` rows the filter keeps: the first showing says where the history is kept; no row,
    /// how to widen the filter; else what ⏎ puts in (`selecting`: several rows), and what → does: the page with
    /// nothing typed and more rows than one, the filter as typed with one, else it hides as Esc does.
    func clipboardFooter(rows: Int, selecting: Bool, in t: InterfaceWords) -> String {
        let terms = Platform.current.terms
        let (enter, backspace) = (terms.enter, terms.backspace)
        let filtered = !clipboard.filter.isEmpty, paged = ListPage.turns(rows)
        if clipboard.first {
            return t.tr("只存在这台 Mac 上；在设置 →「常用」→「剪贴板历史」里可以关掉",
                        "Kept on this Mac only; turn it off in Settings → Common → Clipboard history")
        }
        if rows == 0 { return t.tr("\(backspace) 删字 · Esc 隐藏", "\(backspace) deletes · Esc hides") }
        if selecting {
            if filtered {
                return t.tr("\(enter) 一行一条插入 · ⇧↑⇧↓ 多选 · → 输入筛选的字 · Esc 隐藏",
                            "\(enter) inserts them, one per line · ⇧↑⇧↓ select · → types the filter · Esc hides")
            }
            return paged
                ? t.tr("\(enter) 一行一条插入 · ⇧↑⇧↓ 多选 · ← → 翻页 · Esc 隐藏", "\(enter) inserts them, one per line · ⇧↑⇧↓ select · ← → page · Esc hides")
                : t.tr("\(enter) 一行一条插入 · ⇧↑⇧↓ 多选 · → 或 Esc 隐藏", "\(enter) inserts them, one per line · ⇧↑⇧↓ select · → or Esc hides")
        }
        if filtered {
            return t.tr("\(enter) 插入 · ↑↓ 选择 · ⇧↓ 多选 · → 输入筛选的字 · Esc 隐藏",
                        "\(enter) inserts · ↑↓ to pick · ⇧↓ selects more · → types the filter · Esc hides")
        }
        // Typing filters the rows: said, before ⇧↓ (not in a command, where what is typed is the command's text).
        guard clipboardFilters else {
            return paged
                ? t.tr("\(enter) 插入 · ↑↓ 选择 · ← → 翻页 · ⇧↓ 多选 · Esc 隐藏", "\(enter) inserts · ↑↓ to pick · ← → page · ⇧↓ selects more · Esc hides")
                : t.tr("\(enter) 插入 · ↑↓ 选择 · ⇧↓ 多选 · → 或 Esc 隐藏", "\(enter) inserts · ↑↓ to pick · ⇧↓ selects more · → or Esc hides")
        }
        return paged
            ? t.tr("\(enter) 插入 · ↑↓ 选择 · ← → 翻页 · 打字筛选 · ⇧↓ 多选 · Esc 隐藏",
                   "\(enter) inserts · ↑↓ to pick · ← → page · type to filter · ⇧↓ selects more · Esc hides")
            : t.tr("\(enter) 插入 · ↑↓ 选择 · 打字筛选 · ⇧↓ 多选 · → 或 Esc 隐藏",
                   "\(enter) inserts · ↑↓ to pick · type to filter · ⇧↓ selects more · → or Esc hides")
    }
}
