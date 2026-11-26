import Foundation

extension InputSession {
    /// Clipboard history changed while its panel shows (`SessionEvent.clipboardHistoryChanged`: a copy made just before ⌃V,
    /// kept after the panel opened, now has its kept row, an image its thumbnail and preview): its rows anew from what ⌃V
    /// read of the clipboard (the first row's, where the history didn't have it), the row chosen kept where it still is;
    /// whether ⌃V goes to the app for an image row asked again, as when the panel opens (a panel opened with texts only
    /// has an image row now), and a longer history's filter work for the rows before stopped. Not while a filter is
    /// typed, rows for one are on their way, or rows are being selected: those go by the rows shown.
    func clipboardHistoryChanged() {
        guard clipboard.shown, clipboard.filter.isEmpty, !clipboard.putOnFound, clipboard.anchor == nil,
              clipboard.rows.indices.contains(clipboard.chosen) else { return }
        let content: ClipboardContent
        switch clipboard.all.first {
        case .image?: content = .image(Data())  // the panel looks at the types only
        case let .text(text, nil)?: content = .text(text)
        default: content = .none
        }
        let rows = clipboardRows(content)
        guard !rows.isEmpty, rows != clipboard.all else { return }
        let chosen = clipboard.rows[clipboard.chosen]
        clipboard.chosen = rows.firstIndex(of: chosen) ?? min(clipboard.chosen, rows.count - 1)
        (clipboard.rows, clipboard.all, clipboard.keys) = (rows, rows, nil)
        clipboard.passesPasteKey = rows.contains(where: \.isImage) && services.clipboardHistory.canPassPasteKey()
        clipboard.index?.stop()
        clipboard.index = clipboardFilters && !ClipboardFilter.filtersAtOnce(rows) ? ClipboardFilter.Index(rows, language: UIText.language) : nil
        log.notice("clipboard history: shown anew (\(rows.count) rows)")
        emit(.panel(clipboardPanel()))
    }
}
