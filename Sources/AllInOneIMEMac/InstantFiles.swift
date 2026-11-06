import AllInOneIMECore
import Foundation

/// What `@open` lists on the key that changed its text (`SessionServices.instantResults`), before Spotlight is asked:
/// the apps and places of the app index and what `@open` opened before, kept in memory with their rows
/// (`FileSearch.result`) and when they were last used and changed, ranked as the full search ranks them
/// (`FileSearchRanking.search`, nothing searched); a path's folder, read then (`FileSearch.complete`, on a volume of this
/// Mac only). What is kept is made off the key's thread (`prepare`): the first time, again once the app index may have
/// changed (as often as it looks, `recheckInterval`), and when a path `@open` opened isn't known yet.
public final class InstantFiles: @unchecked Sendable {
    /// An app or place of the index, or a file opened before: what ranks it, its row, and its path and names folded
    /// (`folded`), which a keyword must be in for it to match (`mayMatch`).
    struct Kept {
        var found: FileSearchRanking.Found
        var result: SearchResult
        var folded: String

        init(found: FileSearchRanking.Found, result: SearchResult) {
            self.found = found
            self.result = result
            folded = InstantFiles.folded(([found.path] + found.names).joined(separator: "\n"))
        }
    }

    public static let shared = InstantFiles()

    private let index: AppIndex
    private let recheckInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.aipinyin.inputmethod.AIPinyin.instant-files", qos: .utility)
    private let lock = NSLock()
    /// The index's apps and places, dated; what `@open` opened that is there and isn't one of them, by path; the places'
    /// names, folded; every path of the history looked at; when they were made, and whether they are being made.
    private var apps: [Kept] = []
    private var opened: [String: Kept] = [:]
    private var placeNames: Set<String> = []
    private var looked: Set<String> = []
    private var made: Date?
    private var making = false

    public init(index: AppIndex = .shared, recheckInterval: TimeInterval = 30) {
        self.index = index
        self.recheckInterval = recheckInterval
    }

    /// The rows for `query` (at most `limit`) from what is kept, at once: none before it was first made (`prepare`, which
    /// this asks for when it is out of date). A path lists its folder ("~/Doc"); a web address comes first as in the full
    /// search (`FileSearch.run`).
    public func results(_ query: String, history: OpenHistory, limit: Int = 8, now: Date = Date()) -> [SearchResult] {
        if query.hasPrefix("/") || query.hasPrefix("~") {
            let expanded = (query as NSString).expandingTildeInPath
            let folder = query.hasSuffix("/") ? expanded : (expanded as NSString).deletingLastPathComponent
            return Self.isLocal(folder) ? FileSearch.complete(query, limit: limit) : []
        }
        prepare(history: history, now: now)
        let (apps, opened, placeNames) = lock.withLock { (self.apps, self.opened, self.placeNames) }
        let rows = Self.ranked(query, limit: limit, history: history, apps: apps, opened: opened, placeNames: placeNames)
        guard let web = SearchResult.web(query) else { return rows }
        return query.contains("://") ? [web] : FileSearchRanking.placing(web, in: rows, query: query, limit: limit)
    }

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
                 result: FileSearch.result(for: app.path, app: app))
        }
        let indexed = Set(index.map(\.path))
        var opened: [String: Kept] = [:]
        for path in history.entries.map(\.path) where !indexed.contains(path) && FileManager.default.fileExists(atPath: path) {
            opened[path] = known[path] ?? Kept(found: FileSearchRanking.Found(path: path), result: FileSearch.result(for: path))
        }
        let placeNames = Set(FileSearchRanking.scopingPlaces(apps.map(\.found)).flatMap(\.names).map(Self.folded))
        lock.withLock {
            (self.apps, self.opened, self.placeNames, looked, made, making) = (apps, opened, placeNames,
                                                                                Set(history.entries.map(\.path)), now, false)
        }
    }

    /// `FileSearchRanking.search` over what is kept: the apps and places that match `query`, and what was opened before
    /// that it names (as Spotlight would find it by name, `FileSearch.openedFiles`), without the full-text search. Only
    /// what may match (`mayMatch`) is looked at closely, and the places (for what is inside them: 「下载 pdf」).
    static func ranked(_ query: String, limit: Int, history: OpenHistory, apps: [Kept], opened: [String: Kept],
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

    /// Whether `folder` is on a volume of this Mac, not a server's: as the system's list of what is mounted has it,
    /// without asking the volume (a server that doesn't answer would hold the key).
    static func isLocal(_ folder: String) -> Bool {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo_r_np(&mounts, MNT_NOWAIT)
        defer { free(mounts) }
        guard count > 0, let mounts else { return true }
        var best = (length: -1, local: true)
        for mount in UnsafeBufferPointer(start: mounts, count: Int(count)) {
            let point = withUnsafeBytes(of: mount.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let inside = point == "/" || folder == point || folder.hasPrefix(point + "/")
            guard inside, point.count > best.length else { continue }
            best = (point.count, mount.f_flags & UInt32(MNT_LOCAL) != 0)
        }
        return best.local
    }
}
