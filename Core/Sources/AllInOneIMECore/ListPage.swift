import Foundation

/// A command's result list shown a page at a time (0.7.3, owner 2026-11-10): the rows a command lists once it is picked
/// (a script extension's or a plugin's `list`, `@open`'s results, `@tasks`, a message's recipients) and clipboard
/// history's. `size` rows show from the first shown; ↑↓ move the choice, the rows scrolling just enough to show it. With
/// more rows than a page, ← → turn the page: the choice goes to the new page's first row, and at the first page ← stays,
/// at the last → (the last row shown) stays; the footer says so ("← → page"), and its right which rows show ("6–10 / 12").
/// A list that fits on one page keeps its ← →. Not the one @ list or the command list (their own scrolling), suggestion
/// rows, pinyin candidates or an AI's results.
public enum ListPage {
    /// How many rows show at once.
    public static let size = 5

    /// Whether `count` rows take more than a page: ← → turn it.
    public static func turns(_ count: Int) -> Bool { count > size }

    /// The first row shown: `top`, where the list was left, unless `chosen` isn't on the rows from there; then moved just
    /// enough to show it, a whole page where there is one (a short last page, turned to, stays as it is while the choice
    /// is on it). 0 for a list on one page.
    public static func first(top: Int, chosen: Int, count: Int) -> Int {
        guard turns(count) else { return 0 }
        let top = min(max(top, 0), count - 1)
        if (top..<top + size).contains(chosen) { return top }
        return min(max(chosen < top ? chosen : chosen - size + 1, 0), count - size)
    }

    /// The rows shown from `first`.
    public static func window(first: Int, count: Int) -> Range<Int> {
        min(max(first, 0), count)..<min(max(first, 0) + size, count)
    }

    /// The first row of the page before (`step` below 0, ←) or after (above 0, →) the one shown from `first`. Nil: none,
    /// the list on one page, its first row shown (←) or its last (→).
    public static func turned(_ step: Int, first: Int, count: Int) -> Int? {
        guard turns(count), step != 0 else { return nil }
        if step > 0 { return first + size < count ? first + size : nil }
        return first > 0 ? max(first - size, 0) : nil
    }

    /// Which rows show, for the panel's footer ("6–10 / 12"); nil for a list on one page.
    public static func position(_ window: Range<Int>, count: Int) -> String? {
        turns(count) ? "\(window.lowerBound + 1)–\(window.upperBound) / \(count)" : nil
    }
}
