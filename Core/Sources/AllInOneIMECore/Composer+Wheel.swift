import Foundation

/// The scroll wheel (or the trackpad) over the candidate panel (`SessionEvent.scroll`): in a list that scrolls a row at a
/// time (the command list, one @) the highlight moves a row per step; in a list shown a page at a time (the engine's
/// candidates, a command's list in level two, `@open`'s results and a script's list as they're typed, `@imessage`'s
/// recipients) it turns the page, as that list's page keys do (owner, 2026-11-14). Clipboard history's rows and
/// suggestions' are the session's (`clipboardScroll`, `suggestionsScroll`).
extension Composer {
    /// `steps` rows of the wheel (down > 0): what moves. One page per event, whatever its steps (a fast spin turns one).
    public func wheel(by steps: Int) -> [Effect] {
        guard steps != 0 else { return [] }
        if oneAt != nil || paletteQuery != nil && !paletteMatches.isEmpty { return scrollPalette(by: steps) }
        let page = steps > 0 ? 1 : -1
        if engineState.isComposing, !engineState.candidates.isEmpty { return turnCandidatesPage(by: page) }
        if recipientQuery != nil, !currentRecipients.isEmpty {
            guard ListPage.turns(currentRecipients.count) else { return [] }
            return recipients.turnPage(by: page) ? [.showPanel] : []
        }
        if let items = currentList?.items, !items.isEmpty {
            guard ListPage.turns(items.count) else { return [] }
            return lists.turnPage(by: page, allowed: \.valid) ? [.showPanel] : []
        }
        let live = currentLiveResults
        if !live.isEmpty {
            guard ListPage.turns(live.count) else { return [] }
            return self.live.turnPage(by: page) ? [.showPanel] : []
        }
        if choicesArePaged { return turnChoicesPage(by: page) }
        return []
    }

    /// The scroll wheel over the command list or one @'s rows: the highlight moves (the list scrolls with it).
    public func scrollPalette(by steps: Int) -> [Effect] {
        if oneAt != nil { return scrollOneAt(by: steps) }
        guard paletteQuery != nil, steps != 0, !paletteMatches.isEmpty else { return [] }
        let count = paletteMatches.count
        // Not around the ends: the wheel stops at the first and the last.
        let target = min(max(paletteHighlighted + steps, 0), count - 1)
        movePaletteHighlight(by: target - paletteHighlighted)
        return [.showPanel]
    }

    /// The engine's candidates a page on (1) or back (-1), as Page Down / Page Up (- =) turn them: nothing on the first page
    /// back, on the last on, or for Hindi's spellings (one page).
    private func turnCandidatesPage(by page: Int) -> [Effect] {
        guard let engine, engine.language != .hindi,
              page > 0 ? !engineState.isLastPage : engineState.pageNumber > 0 else { return [] }
        _ = engine.processKey(page > 0 ? RimeKey.pageDown : RimeKey.pageUp, mask: 0)
        engineState = engine.snapshot()
        return [.updateMarkedText, .showPanel]
    }
}
