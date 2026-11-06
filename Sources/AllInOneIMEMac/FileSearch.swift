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

    /// Files, folders and apps for `query` (`run` without the web address).
    private static func files(_ query: String, history: OpenHistory, limit: Int,
                              found: (@Sendable ([SearchResult]) -> Void)?) async -> [SearchResult] {
        let spotlight = Spotlight(until: .now() + timeLimit)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let isPath = query.hasPrefix("/") || query.hasPrefix("~")
                    let results = isPath ? complete(query, limit: limit)
                        : search(query, limit: limit, history: history, with: spotlight, found: found)
                    continuation.resume(returning: spotlight.isCancelled ? [] : results)
                }
            }
        } onCancel: {
            spotlight.cancel()
        }
    }

    /// Entries of the folder `query` points into whose names start with its last part: folders first. One read of the
    /// folder, which tells what each entry is.
    public static func complete(_ query: String, limit: Int) -> [SearchResult] {
        let expanded = (query as NSString).expandingTildeInPath
        let folder = query.hasSuffix("/") ? expanded : (expanded as NSString).deletingLastPathComponent
        let prefix = query.hasSuffix("/") ? "" : (expanded as NSString).lastPathComponent.lowercased()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder, isDirectory: true),
                                                                         includingPropertiesForKeys: Array(keys)) else { return [] }
        let results = entries
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent.lowercased().hasPrefix(prefix) }
            .map { entry -> SearchResult in
                let path = (folder as NSString).appendingPathComponent(entry.lastPathComponent)
                let values = try? entry.resourceValues(forKeys: keys)
                // A link is listed as what it leads to (a folder Tab goes into).
                let isDirectory = values?.isSymbolicLink == true ? isFolder(path) : values?.isDirectory ?? false
                return SearchResult(name: FileManager.default.displayName(atPath: path), path: path,
                                    isFolder: isDirectory && !path.hasSuffix(".app"))
            }
            .sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
        return Array(results.prefix(limit))
    }

    /// The app index, what `@open` opened before and Spotlight by name (one search per keyword, all at once), then
    /// Spotlight by content in the home folder, each file with when it was last used and changed; picked and ordered by
    /// `FileSearchRanking.search`. `found` is told the matches by name before the content search starts. Nothing once
    /// cancelled: what was found until then isn't even read.
    static func search(_ query: String, limit: Int, history: OpenHistory, with spotlight: Spotlight,
                       found: (@Sendable ([SearchResult]) -> Void)? = nil) -> [SearchResult] {
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
            byName: { keywords in
                let scopes = scopes()
                let found = spotlight.names(each: keywords, in: scopes, limit: nameLimit) ?? []
                return found.flatMap { $0 } + opened
            },
            byContent: { predicate in
                guard spotlight.hasTimeLeft,
                      let output = spotlight.mdfind(["-onlyin", home] + FileSearchRanking.attributes + [predicate]) else { return [] }
                return FileSearchRanking.parse(output)
            },
            namesFound: found.map { found in
                { listed in if !spotlight.isCancelled { found(rows(listed)) } }
            })
        guard !spotlight.isCancelled else { return [] }
        return rows(listed)
    }

    /// The most files a name search lists (`Spotlight.names`: the most recently used, then changed, first, which is what
    /// `FileSearchRanking.rank` lists first): 500 for a keyword of one or two characters (on a Mac mini some 1,500 files
    /// `@open` lists from have a word starting with "sa" in their names, 4,000 with "doc"), else 1,000. A name Spotlight
    /// hasn't been asked for lately is answered in under 150 ms then, where all its matches took up to a second.
    public static func nameLimit(_ keyword: String) -> Int {
        keyword.count <= 2 ? 500 : 1000
    }

    /// The folders Spotlight searches by name for `@open`: those `isCandidate` keeps files from (the home folder, the
    /// folders apps are installed in, the volumes mounted besides the startup disk). What it would find anywhere else
    /// is skipped, and looking there is most of its time: two letters took up to 2 s on a Mac mini, some 50 ms in these.
    public static func scopes() -> [String] {
        let volumes = ((try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? [])
            .filter { !$0.hasPrefix(".") }
            .map { "/Volumes/" + $0 }
            .filter { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) == nil }  // the startup disk's link to "/"
        return [home, "/Applications", "/System/Applications"] + volumes
    }

    /// What `@open` opened before (`history`) that `keywords` name (`FileSearchRanking.matches`) and is still there, but
    /// not an app or place of the index (`apps`: found by its names): it is found by name even where Spotlight doesn't
    /// look (a folder kept out of its index), as it is listed while the text is typed (`InstantFiles`).
    static func openedFiles(_ history: OpenHistory, keywords: [String], places: [FileSearchRanking.Found],
                            apps: [String: AppIndex.App]) -> [FileSearchRanking.Found] {
        history.entries.map(\.path).filter { path in
            apps[path] == nil && FileSearchRanking.matches(path, keywords: keywords, places: places)
                && FileManager.default.fileExists(atPath: path)
        }.map { FileSearchRanking.Found(path: $0) }
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
