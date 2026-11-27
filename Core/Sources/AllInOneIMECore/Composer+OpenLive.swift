import Foundation

/// `@open` as you type: the rows for the text (`liveQuery`), what the search answers for it, and Tab completing a path.
extension Composer {
    /// The `@open` text while it is typed, for results as you type (`receiveLive`).
    public var liveQuery: String? {
        guard !isLevelTwo, voice == .off, !engineState.isComposing, draftCommand == .open else { return nil }
        let query = sentText
        return query.isEmpty ? nil : query
    }

    /// The rows for the current `liveQuery`: worked out the first time they are asked for once the text changed
    /// (`LiveRows.show`: what its full search found last time in this field's session, else what is known at once,
    /// `instantResults`, then the rows listed until now that still match it), then as the search answers (`receiveLive`).
    public var currentLiveResults: [SearchResult] {
        guard let query = liveQuery else { return [] }
        if live.query != query {
            let keywords = FileSearchRanking.keywords(in: query)
            live.show(query, instant: live.knows(query) ? [] : folderFirst(instantResults(query), for: query),
                      fits: { Self.stillMatches($0, keywords, for: query) })
            // What its search found before, from before Tab completed it: the folder first all the same.
            if let completed = completedFolder, completed.query == query, live.rows.first?.path != completed.folder.path {
                live.list(folderFirst(live.rows, for: query))
            }
        }
        return live.rows
    }

    /// Whether the action key opens the highlighted result as you type. Not the first when every row is a
    /// content match: nothing is named like the text, so the first may have little to do with it, and the
    /// key lists them to choose from instead, as before the results arrive. One picked with ↑↓ opens, the
    /// first too (↓ then ↑, or round from the last): what the user moved to, not where the highlight started.
    public var opensLiveResult: Bool {
        let live = currentLiveResults
        return live.indices.contains(liveHighlight) && (self.live.highlightMoved || !live.allSatisfy(\.matchedContent))
    }

    /// Files and apps the full search found for `query`: all of them, or (`isFinal` false) those it found so far (the
    /// names, before what the files contain). For the text as it is now (`liveQuery`) they are its rows, in place of those
    /// listed: ↑↓ pick, Tab completes the path, the action key opens (`opensLiveResult`). For a text typed before, those
    /// that match the current one too (`stillMatches`) are added after the rows listed, which stay as they are. All of
    /// them are kept for coming back to the text (`LiveRows`).
    public func receiveLive(_ results: [SearchResult], for query: String, isFinal: Bool = true) -> [Effect] {
        let current = liveQuery
        if let current, query != current { _ = currentLiveResults }  // the rows for the text now, before any are added
        let keywords = FileSearchRanking.keywords(in: current ?? "")
        let changed = live.receive(results, for: query, current: current, isFinal: isFinal,
                                   fits: { Self.stillMatches($0, keywords, for: current ?? "") })
        if query == current, completedFolder?.query == query { live.list(folderFirst(live.rows, for: query)) }
        return changed ? [.showPanel] : []
    }

    /// The field's session is over (or a new one starts): what the full search found for its `@open` texts is forgotten,
    /// the rows listed too, and so are those of the other lists as you type (one @'s files, a list command's).
    public func forgetRecentLive() {
        live.clear(everything: true)
        oneAtFiles.clear(everything: true)
        lists.clear(everything: true)
        completedFolder = nil
    }

    /// `rows` for `query`, the folder Tab completed it to first (`completedFolder`), once: ⏎ with the highlight where it
    /// starts opens the folder itself, its entries below it.
    func folderFirst(_ rows: [SearchResult], for query: String) -> [SearchResult] {
        guard let completed = completedFolder, completed.query == query else { return rows }
        return [completed.folder] + rows.filter { $0.path != completed.folder.path }
    }

    /// Whether a row listed for one `@open` text matches `keywords`, another's, as the full search would list it
    /// (`FileSearchRanking.matches`): one of them at least in its name or its other name (`chineseName`), the others there
    /// or in its folders, case and accents aside. A keyword only in its path ("wei" of /Users/weijianz/) is no match.
    /// Never for a path being typed (`text` "~/Doc", "/Applications/"): its folder's listing alone, no row of another
    /// folder.
    static func stillMatches(_ result: SearchResult, _ keywords: [String], for text: String = "") -> Bool {
        guard !keywords.isEmpty, !text.hasPrefix("/"), !text.hasPrefix("~") else { return false }
        return FileSearchRanking.matches(result.path, names: [result.name] + (result.chineseName.map { [$0] } ?? []), keywords: keywords)
    }

    /// Opens `path` (`Effect.open`): what `@open` opened before ranks first from now on, so what was found for its texts
    /// in this field's session (`live`, one @'s files) is forgotten, not listed again in the order from before.
    func opening(_ path: String) -> Effect {
        completedFolder = nil
        live.clear(everything: true)
        oneAtFiles.clear(everything: true)
        return .open(path: path)
    }

    /// Tab on an `@open` result: its path replaces what was typed (a folder's ends in "/", which lists it).
    func completeLivePath() -> [Effect] {
        let rows = currentLiveResults
        guard rows.indices.contains(liveHighlight) else { return [] }
        let result = rows[liveHighlight]
        draft = commandTrigger + "open " + Self.abbreviatingHome(result.path) + (result.isFolder ? "/" : "")
        completedFolder = result.isFolder ? liveQuery.map { ($0, result) } : nil
        live.clear()
        return [.updateMarkedText, .showPanel]
    }
}
