import AllInOneIMECore
import Foundation

/// What `@open` lists on the key that changed its text (`SessionServices.instantResults`), before Spotlight is asked:
/// the apps and places of the app index and what `@open` opened before, kept in memory with their rows
/// (`FileSearch.result`) and when they were last used and changed, ranked as the full search ranks them
/// (`FileSearchRanking.search`, nothing searched); a path's folder as it was listed a moment ago (`list`, by the search,
/// off the key's thread: nothing is read from the disk on the key). What is kept is made off the key's thread
/// (`prepare`): the first time, again once the app index may have changed (as often as it looks, `recheckInterval`), and
/// when a path `@open` opened isn't known yet.
public final class InstantFiles: @unchecked Sendable {
    /// An app or place of the index, or a file opened before: what ranks it, its row, and its path and names folded
    /// (`folded`), which a keyword must be in for it to match (`mayMatch`).
    struct Kept {
        var found: FileSearchRanking.Found
        var result: SearchResult
        var folded: String
        /// Its Chinese names in pinyin and by their initials (`AppIndex.App.spelled`).
        var spelled: [String]

        init(found: FileSearchRanking.Found, result: SearchResult, spelled: [String] = []) {
            self.found = found
            self.result = result
            self.spelled = spelled
            folded = InstantFiles.folded(([found.path] + found.names).joined(separator: "\n"))
        }
    }

    /// A folder's entries as they were listed (`list`): those whose names start with `prefix` (lowercased), the first
    /// `rows` of them, and when.
    struct Listing {
        var prefix: String
        var rows: [SearchResult]
        var listed: Date
    }

    public static let shared = InstantFiles()

    /// How long a folder's listing is shown at once after it was read (seconds).
    static let listingKept: TimeInterval = 10
    /// How many of a folder's entries a listing keeps (more than a list shows: the next keys narrow them).
    static let listingRows = 40

    private let index: AppIndex
    private let recheckInterval: TimeInterval
    /// Reads a path's folder (`FileSearch.complete`): only ever off the key's thread (`list`).
    private let lister: @Sendable (_ query: String, _ limit: Int) -> [SearchResult]
    /// The folders listed lately, by their path (expanded, as `FileSearch.complete` reads it).
    private var listings: [String: Listing] = [:]
    private let queue = DispatchQueue(label: "com.allinoneime.inputmethod.instant-files", qos: .utility)
    private let lock = NSLock()
    /// The index's apps and places, dated; what `@open` opened that is there and isn't one of them, by path; the places'
    /// names, folded; every path of the history looked at; when they were made, and whether they are being made.
    private var apps: [Kept] = []
    private var opened: [String: Kept] = [:]
    private var placeNames: Set<String> = []
    private var looked: Set<String> = []
    private var made: Date?
    private var making = false
    private var keptHook: (@Sendable ([String]) -> Void)?

    /// Told the paths of what is kept, on the thread that keeps it, never the key's: what `@open` opened before and the
    /// index's apps and places (`make`), a folder's entries (`list`). The Mac loads their icons then, off the main thread,
    /// as they are found (`ItemIcons.prefetch`).
    public var onKept: (@Sendable ([String]) -> Void)? {
        get { lock.withLock { keptHook } }
        set { lock.withLock { keptHook = newValue } }
    }

    public init(index: AppIndex = .shared, recheckInterval: TimeInterval = 30,
                list: @escaping @Sendable (_ query: String, _ limit: Int) -> [SearchResult] = { FileSearch.complete($0, limit: $1) }) {
        self.index = index
        self.recheckInterval = recheckInterval
        lister = list
    }

    /// The rows for `query` (at most `limit`) from what is kept, at once: none before it was first made (`prepare`, which
    /// this asks for when it is out of date). A path ("~/Doc") lists its folder's entries as a listing a moment ago had
    /// them (`listed`), nothing read now; a web address comes first as in the full search (`FileSearch.run`).
    public func results(_ query: String, history: OpenHistory, limit: Int = 8, now: Date = Date()) -> [SearchResult] {
        if Self.isPath(query) { return listed(query, limit: limit, now: now) }
        prepare(history: history, now: now)
        let (apps, opened, placeNames) = lock.withLock { (self.apps, self.opened, self.placeNames) }
        let rows = Self.ranked(query, limit: limit, history: history, apps: apps, opened: opened, placeNames: placeNames)
        guard let web = SearchResult.web(query) else { return rows }
        return query.contains("://") ? [web] : FileSearchRanking.placing(web, in: rows, query: query, limit: limit)
    }

    // MARK: A path's folder

    /// Whether `query` is a path ("/…", "~/…"): its folder is listed, nothing else.
    static func isPath(_ query: String) -> Bool { query.hasPrefix("/") || query.hasPrefix("~") }

    /// The folder `query` points into (expanded) and the start of a name after it (lowercased), as `FileSearch.complete`
    /// reads them.
    static func folder(of query: String) -> (folder: String, prefix: String) {
        let expanded = (query as NSString).expandingTildeInPath
        if query.hasSuffix("/") { return (expanded, "") }
        return ((expanded as NSString).deletingLastPathComponent, (expanded as NSString).lastPathComponent.lowercased())
    }

    /// A path's folder read now (`FileSearch.complete`, its entries named), at most `limit` of its entries, and kept a
    /// moment for the keys after (`listed`). Disk: only ever off the key's thread (the search reads it: `FileSearch.run`,
    /// `names`).
    public func list(_ query: String, limit: Int, now: Date = Date()) -> [SearchResult] {
        let rows = lister(query, max(limit, Self.listingRows))
        let (folder, prefix) = Self.folder(of: query)
        lock.withLock {
            listings = listings.filter { now.timeIntervalSince($0.value.listed) < Self.listingKept }
            listings[folder] = Listing(prefix: prefix, rows: rows, listed: now)
        }
        onKept?(rows.map(\.path))
        return Array(rows.prefix(limit))
    }

    /// A path's rows from its folder's listing kept from a moment ago (`list`, `listingKept`), in memory: those whose
    /// names start as the path's last part does, in the listing's order, folders first (the first of them all: a listing
    /// for "~/D" has every name "~/Do" starts first). None where its folder wasn't listed lately, or for another start.
    func listed(_ query: String, limit: Int, now: Date) -> [SearchResult] {
        let (folder, prefix) = Self.folder(of: query)
        guard let kept = lock.withLock({ listings[folder] }), now.timeIntervalSince(kept.listed) < Self.listingKept,
              prefix.hasPrefix(kept.prefix) else { return [] }
        return Array(kept.rows.lazy.filter { ($0.path as NSString).lastPathComponent.lowercased().hasPrefix(prefix) }.prefix(limit))
    }

    // MARK: What is kept

    /// What is kept made again off the caller's thread, when it is out of date (never made, made `recheckInterval` ago,
    /// or `history` has a path not looked at yet) and not being made already.
    public func prepare(history: OpenHistory, now: Date = Date()) {
        let due = lock.withLock { () -> Bool in
            guard !making else { return false }
            let stale = made.map { now.timeIntervalSince($0) >= recheckInterval } ?? true
            guard stale || history.entries.contains(where: { !looked.contains($0.path) }) else { return false }
            making = true
            return true
        }
        guard due else { return }
        queue.async { self.make(history: history, now: now) }
    }

    /// What is kept made now, on the caller's thread: the app index as of `now` (`AppIndex.apps`), each app's and
    /// place's row and dates (Spotlight's, asked again each time), and the rows of what `history` opened that is still
    /// there (those known already kept as they were).
    public func make(history: OpenHistory, now: Date = Date()) {
        let index = self.index.apps(now: now)
        let known = lock.withLock { opened }
        let apps = index.map { app in
            Kept(found: FileSearch.dated(FileSearchRanking.Found(path: app.path, names: app.names, isPlace: app.isPlace)),
                 result: FileSearch.result(for: app.path, app: app), spelled: app.spelled)
        }
        let indexed = Set(index.map(\.path))
        var opened: [String: Kept] = [:]
        let mounts = Mounts()
        for path in history.entries.map(\.path) where !indexed.contains(path) && FileSearch.isThere(path, mounts: mounts) {
            opened[path] = known[path] ?? Kept(found: FileSearchRanking.Found(path: path), result: FileSearch.result(for: path))
        }
        let placeNames = Set(FileSearchRanking.scopingPlaces(apps.map(\.found)).flatMap(\.names).map(Self.folded))
        lock.withLock {
            (self.apps, self.opened, self.placeNames, looked, made, making) = (apps, opened, placeNames,
                                                                                Set(history.entries.map(\.path)), now, false)
        }
        // What was opened before first: it is likelier to be opened again.
        onKept?(history.entries.map(\.path).filter { indexed.contains($0) || opened[$0] != nil } + apps.map(\.found.path))
    }

    /// `FileSearchRanking.search` over what is kept: the apps and places that match `query`, and what was opened before
    /// that it names (as Spotlight would find it by name, `FileSearch.openedFiles`), without the full-text search. Only
    /// what may match (`mayMatch`) is looked at closely, and the places (for what is inside them: 「下载 pdf」). Those a
    /// keyword starts a word of the name of come first ("set" finds System Settings before Reset), then the others as
    /// ranked; then, for letters typed as one word, the apps and places whose Chinese name they start the pinyin or the
    /// initials of ("wx" 微信, "xtsz" 系统设置).
    static func ranked(_ query: String, limit: Int, history: OpenHistory, apps: [Kept], opened: [String: Kept],
                       placeNames: Set<String>) -> [SearchResult] {
        let keywords = FileSearchRanking.keywords(in: query)
        var rows = byName(query, limit: limit, history: history, apps: apps, opened: opened, placeNames: placeNames)
        let words = Set(rows.filter { startsAWord($0, keywords) }.map(\.path))
        rows = rows.filter { words.contains($0.path) } + rows.filter { !words.contains($0.path) }
        guard rows.count < limit, keywords.count == 1, let letters = keywords.first?.lowercased(),
              letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return rows }
        let listed = Set(rows.map(\.path))
        let spelled = apps.filter { kept in !listed.contains(kept.found.path) && kept.spelled.contains { $0.hasPrefix(letters) } }
        let ranked = FileSearchRanking.rank(spelled.map(\.found), keywords: [], history: history, limit: limit - rows.count)
        let byPath = Dictionary(spelled.map { ($0.found.path, $0.result) }, uniquingKeysWith: { first, _ in first })
        return rows + ranked.compactMap { byPath[$0.path] }
    }

    /// Whether every keyword starts a word of `result`'s name, its other name or its file name (case and accents aside).
    static func startsAWord(_ result: SearchResult, _ keywords: [String]) -> Bool {
        let names = [result.name, (result.path as NSString).lastPathComponent] + (result.chineseName.map { [$0] } ?? [])
        let words = names.flatMap { name in folded(name).split { !($0.isLetter || $0.isNumber) }.map(String.init) }
        return !keywords.isEmpty && keywords.map(folded).allSatisfy { keyword in
            keyword.containsHan ? names.contains { folded($0).contains(keyword) } : words.contains { $0.hasPrefix(keyword) }
        }
    }

    /// The rows `FileSearchRanking.search` lists for `query` from what is kept (`ranked`), by name.
    private static func byName(_ query: String, limit: Int, history: OpenHistory, apps: [Kept], opened: [String: Kept],
                               placeNames: Set<String>) -> [SearchResult] {
        let keywords = FileSearchRanking.keywords(in: query)
        let folded = keywords.map(Self.folded)
        let candidates = apps.filter { $0.found.isPlace || mayMatch($0, folded, placeNames: placeNames) }
        let entries = candidates.map(\.found)
        let places = FileSearchRanking.scopingPlaces(entries)
        let named = history.entries.compactMap { opened[$0.path] }.filter { kept in
            mayMatch(kept, folded, placeNames: placeNames) && FileSearchRanking.matches(kept.found.path, keywords: keywords, places: places)
        }
        let listed = FileSearchRanking.search(query, limit: limit, history: history, apps: entries, isCandidate: FileSearch.isCandidate,
                                              byName: { _ in named.map(\.found) }, byContent: { _ in [] })
        guard !listed.isEmpty else { return [] }
        let rows = Dictionary((candidates + named).map { ($0.found.path, $0.result) }, uniquingKeysWith: { first, _ in first })
        return listed.compactMap { rows[$0.path] }
    }

    /// Whether every keyword (`folded`) is in what `kept` is called or its path, as `FileSearchRanking.matches` needs it to
    /// be, or names a place (what is inside matches it). A quick look, byte for byte: what fails it can't match.
    static func mayMatch(_ kept: Kept, _ folded: [String], placeNames: Set<String>) -> Bool {
        folded.allSatisfy { placeNames.contains($0) || contains(kept.folded, $0) }
    }

    /// `text` as it is compared: case, accents and how a character is encoded aside.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).precomposedStringWithCanonicalMapping
    }

    /// Whether `part` is in `text`, byte for byte.
    static func contains(_ text: String, _ part: String) -> Bool {
        var (text, part) = (text, part)
        return text.withUTF8 { text in
            part.withUTF8 { part in part.isEmpty || memmem(text.baseAddress, text.count, part.baseAddress, part.count) != nil }
        }
    }
}
