import Foundation

/// A list that fills as you type, the same for every list a text is typed for (0.7.0): `@open`'s files and apps, a
/// script extension's `list`, a send command's recipients, the files one @ finds. Its rows are those of the text as it is
/// now, never blinking: on the key that changed the text, what is known at once and the rows listed until then that still
/// fit the new text (`show`); then what the text's source answers takes their place (`receive`); an answer for a text
/// typed before only adds the rows that fit the text now. What the source answered for the last texts (`limit`) comes
/// back at once with them. A highlight moved with ↑↓ stays on its row while that is listed, else it is on the first.
public struct LiveRows<Row> {
    /// The rows listed, the text they are for (nil: none yet), and the highlighted one.
    public private(set) var rows: [Row] = []
    public private(set) var query: String?
    public private(set) var highlight = 0
    /// ↑↓ moved the highlight (back to the first counts too): it stays on its row as rows come and go. Reset when the
    /// text changes.
    public private(set) var highlightMoved = false
    /// What the source answered for the texts typed last, the latest last.
    private var recent: [(query: String, rows: [Row])] = []
    /// How many texts' answers are kept.
    public let limit: Int
    /// What tells a row apart from another.
    private let id: (Row) -> String

    public init(limit: Int, id: @escaping (Row) -> String) {
        self.limit = limit
        self.id = id
    }

    /// The text is now `query`: its rows at once. What its source answered last time (`recent`); else `instant`, then
    /// those of the rows listed until now that still fit it (`fits`), each once. Nothing to do for the text listed.
    public mutating func show(_ query: String, instant: [Row] = [], fits: (Row) -> Bool) {
        guard query != self.query else { return }
        let listed = rows
        self.query = query
        highlightMoved = false
        if let known = recent.last(where: { $0.query == query }) {
            list(known.rows)
            return
        }
        var seen = Set(instant.map(id))
        list(instant + listed.filter { fits($0) && seen.insert(id($0)).inserted })
    }

    /// The source answered `answer` for `query` (`isFinal` false: what it found so far, not kept). For the text listed
    /// (`current`) it takes the rows' place; for one typed before, the rows that fit the text now (`fits`) are added after
    /// those listed. Whether the rows changed.
    @discardableResult
    public mutating func receive(_ answer: [Row], for query: String, current: String?, isFinal: Bool = true,
                                 fits: (Row) -> Bool) -> Bool {
        if isFinal { remember(answer, for: query) }
        guard let current else { return false }
        if query == current {
            self.query = query
            list(answer)
            return true
        }
        let listed = Set(rows.map(id))
        let added = answer.filter { fits($0) && !listed.contains(id($0)) }
        guard !added.isEmpty else { return false }
        rows += added
        return true
    }

    /// `rows` listed: a highlight moved with ↑↓ stays on its row while it is there, else it's on the first.
    public mutating func list(_ new: [Row]) {
        let picked = highlightMoved && rows.indices.contains(highlight) ? id(rows[highlight]) : nil
        rows = new
        if let picked, let index = new.firstIndex(where: { id($0) == picked }) {
            highlight = index
        } else {
            highlight = 0
            highlightMoved = false
        }
    }

    /// ↑ (-1) or ↓ (1) among the rows, round the ends; `allowed` the rows it may stop on (all by default).
    public mutating func move(by step: Int, allowed: (Row) -> Bool = { _ in true }) {
        guard rows.contains(where: allowed) else { return }
        var index = highlight
        repeat { index = (index + step + rows.count) % rows.count } while !allowed(rows[index])
        highlight = index
        highlightMoved = true
    }

    /// The highlight on `index` (a row picked otherwise: a click, the first that can be picked).
    public mutating func highlight(_ index: Int, moved: Bool = false) {
        guard rows.indices.contains(index) else { return }
        highlight = index
        highlightMoved = moved
    }

    /// The highlight back on the first row, where it starts rather than moved to.
    public mutating func resetHighlight() {
        highlight = 0
        highlightMoved = false
    }

    /// The rows listed go (the draft is done, or the text is no longer one this list is for); what the source answered
    /// for the texts typed before stays, unless `everything`.
    public mutating func clear(everything: Bool = false) {
        rows = []
        query = nil
        resetHighlight()
        if everything { recent = [] }
    }

    /// Whether the source answered `query` before: its answer is kept.
    public func knows(_ query: String) -> Bool { recent.contains { $0.query == query } }

    /// Keeps what the source answered for `query`, the latest last.
    private mutating func remember(_ answer: [Row], for query: String) {
        recent.removeAll { $0.query == query }
        recent.append((query, answer))
        if recent.count > limit { recent.removeFirst(recent.count - limit) }
    }
}
