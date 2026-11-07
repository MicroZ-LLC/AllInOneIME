import AllInOneIMECore
import Foundation

/// `@open`: files, folders and apps. A path ("~/Doc", "/Applications/") lists what is in that
/// folder; anything else is looked for by name: in the app index (`AppIndex`: every name an app goes
/// by, 计算器 too, and Finder's names for the standard folders, 下载 too), in what `@open` opened before, and with
/// Spotlight (`Spotlight.names`, as `mdfind -name` finds them, in the folders `@open` lists from: every keyword somewhere
/// in the path, a standard folder's Finder name for what is in it: 「下载 pdf」); then, when that finds hardly anything
/// and no app or folder of the index, in what the files of the home folder contain (not for a web address), the names
/// told first (`run`'s `found`). What is known without searching is listed as the text is typed (`InstantFiles`). Runs
/// on this Mac only.
public enum FileSearch {
    /// All the Spotlight searches for one query end by then (seconds).
    static let timeLimit = 3.0

    /// The best `limit` matches for `query`, off the main thread; what `@open` opened (`history`) first. `found` is told
    /// the matches by name before the full-text search starts, when one does (it takes longer). Cancelling the task stops
    /// the search and the Spotlight queries it started; it then returns nothing.
    public static func run(_ query: String, history: OpenHistory, limit: Int = 8,
                           found: (@Sendable ([SearchResult]) -> Void)? = nil) async -> [SearchResult] {
        // A web address comes first (opened in the browser), after a file named exactly like it
        // (`FileSearchRanking.placing`); "https://…" is nothing else. (No full-text search follows one.)
        if let web = SearchResult.web(query) {
            if query.contains("://") { return [web] }
            let found = await files(query, history: history, limit: limit, found: nil)
            return FileSearchRanking.placing(web, in: found, query: query, limit: limit)
        }
        return await files(query, history: history, limit: limit, found: found)
    }

    /// One @'s files (`SessionServices.searchFileNames`): what `run` finds by name for `query`, without what the files
    /// contain, nor a web address (one @ lists that itself). Off the main thread; cancelling the task stops it.
    public static func names(_ query: String, history: OpenHistory, limit: Int = 8) async -> [SearchResult] {
        guard SearchResult.web(query) == nil, !query.hasPrefix("/"), !query.hasPrefix("~") else { return [] }
        return await files(query, history: history, limit: limit, found: nil, content: false)
    }

    /// Files, folders and apps for `query` (`run` without the web address); by name only without `content`.
    private static func files(_ query: String, history: OpenHistory, limit: Int,
                              found: (@Sendable ([SearchResult]) -> Void)?, content: Bool = true) async -> [SearchResult] {
        let spotlight = Spotlight(until: .now() + timeLimit)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let isPath = query.hasPrefix("/") || query.hasPrefix("~")
                    let results = isPath ? complete(query, limit: limit)
                        : search(query, limit: limit, history: history, with: spotlight, found: found, content: content)
                    continuation.resume(returning: spotlight.isCancelled ? [] : results)
                }
            }
        } onCancel: {
            spotlight.cancel()
        }
    }

    /// Entries of the folder `query` points into whose names start with its last part: folders first, then by file name;
    /// at most `limit`. One read of the folder, which tells what each entry is (its own records of them: a volume mounted
    /// in it isn't asked), and only the first `limit` picked out and named as Finder names them (`displayName`, which reads
    /// an app's bundle). In a folder of this Mac (`Mounts.isLocal`) what is on a server is never asked anything: a link to
    /// it isn't followed (it is listed as a file), and it is named as it is called here. (Such a folder is read on the
    /// key's thread, `InstantFiles`, and again by the search, which lists it the same way.)
    public static func complete(_ query: String, limit: Int, mounts: Mounts = Mounts()) -> [SearchResult] {
        let expanded = (query as NSString).expandingTildeInPath
        let folder = query.hasSuffix("/") ? expanded : (expanded as NSString).deletingLastPathComponent
        let prefix = query.hasSuffix("/") ? "" : (expanded as NSString).lastPathComponent.lowercased()
        let onThisMac = mounts.isLocal(folder)
        func asked(_ path: String) -> Bool { !onThisMac || mounts.isLocal(path) }
        func path(_ name: String) -> String { (folder as NSString).appendingPathComponent(name) }
        guard limit > 0, let directory = opendir(folder) else { return [] }
        defer { closedir(directory) }
        typealias Entry = (isFolder: Bool, key: String, name: String)
        func precedes(_ a: Entry, _ b: Entry) -> Bool { (a.isFolder ? 0 : 1, a.key, a.name) < (b.isFolder ? 0 : 1, b.key, b.name) }
        // The first `limit` so far, in order: most entries of a large folder are dropped after one comparison.
        var first: [Entry] = []
        while let entry = readdir(directory) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                String(decoding: UnsafeRawBufferPointer(start: $0, count: length), as: UTF8.self)
            }
            let key = name.lowercased()
            guard !name.hasPrefix("."), key.hasPrefix(prefix) else { continue }
            var type = Int32(entry.pointee.d_type)
            if type == DT_UNKNOWN {
                var info = stat()
                let format = lstat(path(name), &info) == 0 ? info.st_mode & S_IFMT : 0
                type = format == S_IFDIR ? DT_DIR : format == S_IFLNK ? DT_LNK : DT_REG
            }
            // A link is listed as what it leads to (a folder Tab goes into).
            let isDirectory = type == DT_DIR || type == DT_LNK && asked(path(name)) && isFolder(path(name))
            let listed = (isDirectory && !name.hasSuffix(".app"), key, name)
            if first.count == limit, !precedes(listed, first[limit - 1]) { continue }
            first.insert(listed, at: first.firstIndex { precedes(listed, $0) } ?? first.count)
            if first.count > limit { first.removeLast() }
        }
        return first.map { entry in
            let path = path(entry.name)
            return SearchResult(name: asked(path) ? FileManager.default.displayName(atPath: path) : entry.name, path: path,
                                isFolder: entry.isFolder)
        }
    }

    /// The app index, what `@open` opened before and Spotlight by name (one search per keyword, all at once), then
    /// Spotlight by content in the home folder, each file with when it was last used and changed; picked and ordered by
    /// `FileSearchRanking.search`. `found` is told the matches by name before the content search starts. Nothing once
    /// cancelled: what was found until then isn't even read.
    static func search(_ query: String, limit: Int, history: OpenHistory, with spotlight: Spotlight,
                       found: (@Sendable ([SearchResult]) -> Void)? = nil, content: Bool = true) -> [SearchResult] {
        let index = AppIndex.shared.apps()
        let keywords = FileSearchRanking.keywords(in: query)
        let entries = index.map { FileSearchRanking.Found(path: $0.path, names: $0.names, isPlace: $0.isPlace) }
        let places = FileSearchRanking.scopingPlaces(entries)
        let apps = entries.map { found in
            FileSearchRanking.matches(found.path, names: found.names, keywords: keywords, places: places) ? dated(found) : found
        }
        let byPath = Dictionary(index.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        func rows(_ listed: [(path: String, matchedContent: Bool)]) -> [SearchResult] {
            listed.map { result(for: $0.path, matchedContent: $0.matchedContent, app: byPath[$0.path]) }
        }
        let opened = openedFiles(history, keywords: keywords, places: places, apps: byPath)
        let listed = FileSearchRanking.search(
            query, limit: limit, history: history, apps: apps, isCandidate: isCandidate,
            byName: { searched in
                let found = spotlight.names(each: searched, in: scopes(), recentFirst: recentDays, enough: { found in
                    fillsRows(found, limit: limit, keywords: keywords, places: places)
                }) ?? []
                return found.flatMap { $0 } + opened
            },
            byContent: { predicate in
                guard content, spotlight.hasTimeLeft,
                      let output = spotlight.mdfind(["-onlyin", home] + FileSearchRanking.attributes + [predicate]) else { return [] }
                return FileSearchRanking.parse(output)
            },
            namesFound: found.map { found in
                { listed in if !spotlight.isCancelled { found(rows(listed)) } }
            })
        guard !spotlight.isCancelled else { return [] }
        return rows(listed)
    }

    /// The days a name search looks back over first (`Spotlight.names(each:)`' `recentFirst`): the apps and the files used
    /// or changed since the start of yesterday, then in the last 30 days, then all its matches, each only when what was
    /// found before doesn't fill the rows (`fillsRows`). What was used or changed later is listed first
    /// (`FileSearchRanking.rank`), so the rows are those all the matches give; and a keyword many files match is answered
    /// from the few of the last days. (Spotlight's own limit isn't that: it keeps an arbitrary few, `Spotlight.names`.)
    public static let recentDays = [1, 30]

    /// Whether the files a name search found (`found`) fill `limit` rows for a query of `keywords` by themselves: so many
    /// of them are where `@open` lists files from, not noise, and named by the query (`FileSearchRanking.matches`, which
    /// `FileSearchRanking.search` keeps). No file used or changed earlier than all of them can be listed then.
    static func fillsRows(_ found: [FileSearchRanking.Found], limit: Int, keywords: [String],
                          places: [FileSearchRanking.Found]) -> Bool {
        var rows = 0
        for file in found where isCandidate(file.path) && !FileSearchRanking.isNoise(file.path)
            && FileSearchRanking.matches(file.path, keywords: keywords, places: places) {
            rows += 1
            if rows >= limit { return true }
        }
        return false
    }

    /// The folders Spotlight searches by name for `@open`: those `isCandidate` keeps files from (the home folder, the
    /// folders apps are installed in, this Mac's volumes mounted besides the startup disk, not a server's: `mdfind -name`
    /// didn't look there either, and a server would make every search wait for it). What it would find anywhere else is
    /// skipped, and looking there is most of its time: two letters took up to 2 s on a Mac mini, some 50 ms in these.
    public static func scopes(mounts: Mounts = Mounts()) -> [String] {
        let volumes = ((try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? [])
            .filter { !$0.hasPrefix(".") }
            .map { "/Volumes/" + $0 }
            .filter { mounts.isLocal($0) && (try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) == nil }  // the startup disk's link to "/"
        return [home, "/Applications", "/System/Applications"] + volumes
    }

    /// What `@open` opened before (`history`) that `keywords` name (`FileSearchRanking.matches`) and is still there
    /// (`isThere`), but not an app or place of the index (`apps`: found by its names): it is found by name even where
    /// Spotlight doesn't look (a folder kept out of its index), as it is listed while the text is typed (`InstantFiles`).
    static func openedFiles(_ history: OpenHistory, keywords: [String], places: [FileSearchRanking.Found],
                            apps: [String: AppIndex.App], mounts: Mounts = Mounts()) -> [FileSearchRanking.Found] {
        history.entries.map(\.path).filter { path in
            apps[path] == nil && FileSearchRanking.matches(path, keywords: keywords, places: places) && isThere(path, mounts: mounts)
        }.map { FileSearchRanking.Found(path: $0) }
    }

    /// Whether `path` is still there, asked of this Mac's volumes only (`Mounts.isLocal`): what is on a server isn't
    /// looked for, and counts as gone (one that doesn't answer would hold the search until the system gives up on it).
    static func isThere(_ path: String, mounts: Mounts) -> Bool {
        mounts.isLocal(path) && FileManager.default.fileExists(atPath: path)
    }

    /// `app` (or a place) with when it was last used and changed, as Spotlight keeps them. Its name search
    /// knows an app by its file name and its name in the system language only: an app matched by another of
    /// its names (计算器 on an English system) gets no dates from there.
    static func dated(_ app: FileSearchRanking.Found) -> FileSearchRanking.Found {
        guard let item = NSMetadataItem(url: URL(fileURLWithPath: app.path)) else { return app }
        var app = app
        app.lastUsed = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
        app.modified = item.value(forAttribute: "kMDItemContentModificationDate") as? Date
        return app
    }

    /// Shown as Finder names it (`FileManager.displayName`, in the system language: Image Playground, not
    /// its bundle's English "Playground"); an app or place of the index under its Chinese name in a Chinese
    /// interface (`SearchResult.chineseName`).
    static func result(for path: String, matchedContent: Bool = false, app: AppIndex.App? = nil) -> SearchResult {
        SearchResult(name: FileManager.default.displayName(atPath: path), path: path,
                     isFolder: isFolder(path) && !path.hasSuffix(".app"), matchedContent: matchedContent, chineseName: app?.chinese)
    }

    static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Where users keep things they open by name; everything else (system and library folders,
    /// hidden folders, the inside of bundles, build output) is skipped. (Finder and the home folder itself
    /// come from the app index, which isn't filtered.)
    public static func isCandidate(_ path: String) -> Bool {
        // Cheapest first: a one-letter name finds some 66,000 files.
        guard path.hasPrefix(homePrefix) || path.hasPrefix("/Applications/") || path.hasPrefix("/System/Applications/")
            || path.hasPrefix("/Volumes/") else { return false }
        return !skipped.contains { path.range(of: $0, options: .literal) != nil }
    }

    private static let skipped = ["/Library/", "/.", ".app/", "/node_modules/", "/DerivedData/", "/.build/"]
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let homePrefix = home + "/"
}
