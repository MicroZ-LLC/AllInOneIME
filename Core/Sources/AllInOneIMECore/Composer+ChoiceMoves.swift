import Foundation

/// ↑↓, Tab, Page Up/Down and ← → among level two's rows.
extension Composer {
    /// Whether the highlight may rest on `choice`: not a script list's row of information (`valid: false`), which ⏎
    /// can't pick. The same rows the list skips while its text is typed (`moveListHighlight`), so one list moves one way.
    static func movesOnto(_ choice: Choice) -> Bool {
        if case let .item(item) = choice.kind { return item.valid }
        return true
    }

    /// ↑ (-1) or ↓ (1) among the rows (`movesOnto`; any, where none is), round the ends.
    func moveHighlight(by delta: Int) -> [Effect] {
        let all = choices, count = all.count
        guard count > 0 else { return [] }
        let anyRow = !all.contains(where: Self.movesOnto)
        var index = min(highlighted(in: all), count - 1)
        repeat { index = (index + delta + count) % count } while !anyRow && !Self.movesOnto(all[index])
        highlightOverride = index
        choicesTop = choicesFirstShown  // a list a page at a time scrolls with it
        return [.showPanel]
    }

    /// ← (-1) or → (1) on a list in level two on more than a page: the page before or after, its first row the highlight
    /// may rest on highlighted (else its first); nothing at the first or the last.
    func turnChoicesPage(by step: Int) -> [Effect] {
        let all = choices
        guard let next = ListPage.turned(step, first: choicesFirstShown, count: all.count) else { return [] }
        highlightOverride = ListPage.window(first: next, count: all.count).first { Self.movesOnto(all[$0]) } ?? next
        choicesTop = next
        return [.showPanel]
    }
}
