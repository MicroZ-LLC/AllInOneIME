import Crypto
import Foundation

/// A completion source of a plugin, by their names; a custom command's under `customCommands` (`init(command:)`).
public struct CompletionSourceKey: Hashable, Sendable {
    public var plugin: String
    public var source: String

    public init(plugin: String, source: String) {
        self.plugin = plugin
        self.source = source
    }

    /// Its file in the cache folder: "<plugin>.<source>.json" (names of small letters and digits), a custom command's
    /// "custom-commands.<name>.json"; a script extension's "script-extensions.<16 hex digits>.json", from its command's
    /// id (a path, or a bundle's name and the command's), which a file's name can't hold as it is.
    var fileName: String {
        guard isScriptExtension else { return "\(plugin).\(source).json" }
        let digest = SHA256.hash(data: Data(source.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(plugin).\(digest).json"
    }

    /// The source a cache file is of, by its name; nil for any other file, and for a script extension's (its name is its
    /// id's digest: `isCacheFile`).
    init?(fileName: String) {
        let parts = fileName.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "json", CompletionDeclaration.isName(String(parts[1])),
              parts[0] == Self.customCommands
                || (1...24).contains(parts[0].count) && parts[0].allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter })
        else { return nil }
        self.init(plugin: String(parts[0]), source: String(parts[1]))
    }

    /// Whether `name` is a source's cache file (`fileName`): a plugin's, a custom command's, a script extension's.
    static func isCacheFile(_ name: String) -> Bool {
        if CompletionSourceKey(fileName: name) != nil { return true }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == Self.scriptExtensions && parts[2] == "json" && parts[1].count == 16
            && parts[1].allSatisfy(\.isHexDigit)
    }
}

/// What the core keeps in memory for the fields of one launch (spec 1.2, 1.3, 6.4, 6.17): each completion source's last
/// good list (and when it was made and loaded), its failures in a row and pause, when it was last used, its queries'
/// answers by text and the one in flight; the results its loads and queries came back with, until a session takes them
/// in (`commit`, on its thread: the time then is when they count). The lists are also cached on disk, readable by the
/// user only, when the shell gives a folder (`SuggestionsServices.cacheFolder`).
public final class SuggestionsStore: @unchecked Sendable {
    /// How long after each failure in a row the next load waits (spec 6.17): the fifth pauses the source.
    static let backOff: [TimeInterval] = [60, 5 * 60, 30 * 60, 2 * 3600]
    static let failuresToPause = 5
    /// A paused source loads again a day later (or on "Refresh now", or an update of its plugin).
    static let pause: TimeInterval = 24 * 3600
    /// A source unused this long stops refreshing (spec 1.1).
    static let unusedAfter: TimeInterval = 7 * 24 * 3600
    /// A query's answer is kept this long for its text.
    static let answerLife: TimeInterval = 10 * 60
    static let maxAnswers = 64
    /// After this many failed queries in a row, none for `queryRest`.
    static let queryFailuresToRest = 3
    static let queryRest: TimeInterval = 60

    struct Answer {
        var items: CompletionItems
        var at: Date
    }

    /// A list as a load left it: its items ready to be matched, and when it was made (`CompletionList.fetchedAt`).
    struct LoadedList: Sendable {
        var items: CompletionItems
        var fetchedAt: Double?

        init(_ list: CompletionList) {
            items = CompletionItems(list.items)
            fetchedAt = list.fetchedAt
        }
    }

    /// Why a load failed, as Settings says it.
    struct LoadFailure: Error {
        var message: String
    }

    /// A load's or a query's result, as its task left it; the list cached on disk, as reading it left it.
    enum Pending {
        case load(id: Int, Result<LoadedList, LoadFailure>)
        /// nil: it failed (or was cancelled: `cancelled`).
        case query(id: Int, text: String, items: CompletionItems?, cancelled: Bool)
        /// nil: none there, or not one.
        case cache(CachedLoad?)
    }

    /// Whether a source's list cached on disk was looked at this launch.
    enum CacheState {
        case unread, reading, read
    }

    /// A list cached on disk, read (`CachedList`), its items ready to be matched.
    struct CachedLoad: Sendable {
        var items: CompletionItems
        var fetchedAt: Double?
        var loadedAt: Double
        var lastUsed: Double?
    }

    struct Source {
        /// The last good list, when it was made (`fetchedAt`, else when it was loaded) and loaded.
        var list: CompletionItems?
        var madeAt: Date?
        var loadedAt: Date?
        /// When the last load started, and the one in flight.
        var attemptAt: Date?
        var loading: (id: Int, since: Date)?
        var failures = 0
        var failedAt: Date?
        var error: String?
        var pausedAt: Date?
        /// Its plugin's version when it paused (a custom command's definition): another one (an update, an edit)
        /// resumes it.
        var pausedVersion: String?
        /// The latest "Refresh now" acted on.
        var refreshDone: Date?
        var lastUsed: Date?
        /// The disk cache: looked at this launch, or being read.
        var cache = CacheState.unread
        var answers: [String: Answer] = [:]
        var query: (id: Int, text: String, since: Date, task: Task<Void, Never>?)?
        var queryFailures = 0
        var queryRestUntil: Date?
        var pending: [Pending] = []
    }

    struct State {
        var sources: [CompletionSourceKey: Source] = [:]
        var serial = 0
        /// The sessions of the fields that have the focus, told when a result came back (`answered`).
        var listeners: [ObjectIdentifier: @Sendable (SessionEvent) -> Void] = [:]
    }

    let state = Locked(initialState: State())
    /// The files' SHA-256s it read (plugins' scripts, script extensions' files), by their size and date.
    let hashes = FileHashes()
    /// Where the cache files are written and deleted, in order.
    static let disk = DispatchQueue(label: "com.aipinyin.inputmethod.suggestions.cache")

    public init() {}

    func with<R>(_ key: CompletionSourceKey, _ body: (inout Source) -> R) -> R {
        state.withLock { state in body(&state.sources[key, default: Source()]) }
    }

    func nextID() -> Int {
        state.withLock { state in
            state.serial += 1
            return state.serial
        }
    }

    // MARK: - For Settings

    /// How each source known this launch is doing (Settings → Plugins).
    public func statuses() -> [CompletionSourceStatus] {
        state.withLock { state in
            state.sources.map { key, source in Self.status(key, source) }.sorted { ($0.plugin, $0.source) < ($1.plugin, $1.source) }
        }
    }

    /// How `key` is doing (nil: nothing known this launch).
    public func status(_ key: CompletionSourceKey) -> CompletionSourceStatus? { status(plugin: key.plugin, source: key.source) }

    public func status(plugin: String, source: String) -> CompletionSourceStatus? {
        state.withLock { state in state.sources[CompletionSourceKey(plugin: plugin, source: source)].map {
            Self.status(CompletionSourceKey(plugin: plugin, source: source), $0)
        } }
    }

    static func status(_ key: CompletionSourceKey, _ source: Source) -> CompletionSourceStatus {
        CompletionSourceStatus(plugin: key.plugin, source: key.source, items: source.list?.count ?? 0, refreshed: source.loadedAt,
                               error: source.error, paused: source.pausedAt != nil)
    }

    // MARK: - The script's hash

    /// The SHA-256 (lowercase hex) of the file at `url`, read again when it changed (its size or date); nil: none.
    public func sha256(of url: URL) -> String? { hashes.sha256(of: url) }

    // MARK: - Results

    /// A load's or query's result, from its task (any thread): taken in by the next `commit`; the sessions of the fields
    /// with the focus (and `starter`, the one that asked) are told.
    func deposit(_ key: CompletionSourceKey, _ result: Pending, from session: ObjectIdentifier,
                 starter: @escaping @Sendable (SessionEvent) -> Void) {
        let listeners = state.withLock { state -> [@Sendable (SessionEvent) -> Void] in
            state.sources[key, default: Source()].pending.append(result)
            return Array(state.listeners.values) + (state.listeners[session] == nil ? [starter] : [])
        }
        let event = SessionEvent.task(TaskID(slot: nil, serial: 0), .completionsAnswered)
        for listener in listeners { listener(event) }
    }

    /// A field's session took the focus (`deliver`, how it is told), or left it (nil).
    func listen(_ session: ObjectIdentifier, _ deliver: (@Sendable (SessionEvent) -> Void)?) {
        state.withLock { $0.listeners[session] = deliver }
    }

    /// What changed with a commit: the sources whose list or status changed (`statusChanged`), those a query answered,
    /// and those whose list came from the disk cache (`cached`).
    struct Committed {
        var statusChanged: [CompletionSourceKey] = []
        var listsChanged: [CompletionSourceKey] = []
        var answered: [CompletionSourceKey] = []
        var cached: [CompletionSourceKey] = []
        var isEmpty: Bool { statusChanged.isEmpty && answered.isEmpty && cached.isEmpty }
    }

    /// The results the tasks left, taken in at `now` (the session's thread): a good list replaces the old one (and is
    /// cached in `folder`), a failure keeps it and backs off (the fifth in a row pauses the source, `versions` its
    /// version then: its plugin's, a custom command's definition); a query's answer is kept for its text.
    func commit(now: Date, folder: URL?, versions: [CompletionSourceKey: String]) -> Committed {
        var committed = Committed()
        var writes: [(CompletionSourceKey, Source)] = []
        state.withLock { state in
            for key in state.sources.compactMap({ $0.value.pending.isEmpty ? nil : $0.key }) {
                guard var source = state.sources[key] else { continue }
                let pending = source.pending
                source.pending = []
                for result in pending {
                    switch result {
                    case let .load(id, outcome):
                        guard source.loading?.id == id else { continue }
                        source.loading = nil
                        switch outcome {
                        case let .success(list):
                            source.list = list.items
                            source.loadedAt = now
                            source.madeAt = list.fetchedAt.map { Date(timeIntervalSince1970: $0) }.map { min($0, now) } ?? now
                            (source.failures, source.failedAt, source.error, source.pausedAt) = (0, nil, nil, nil)
                            committed.listsChanged.append(key)
                            writes.append((key, source))
                        case let .failure(failure):
                            source.failures += 1
                            source.failedAt = now
                            source.error = failure.message
                            if source.failures >= Self.failuresToPause {
                                source.pausedAt = now
                                source.pausedVersion = versions[key]
                            }
                        }
                        committed.statusChanged.append(key)
                    case let .query(id, text, items, cancelled):
                        guard source.query?.id == id else { continue }
                        source.query = nil
                        if cancelled { continue }
                        if let items {
                            source.queryFailures = 0
                            source.answers[text] = Answer(items: items, at: now)
                        } else {
                            source.queryFailures += 1
                            // Not asked again for this text a while.
                            source.answers[text] = Answer(items: CompletionItems([]), at: now)
                            if source.queryFailures >= Self.queryFailuresToRest { source.queryRestUntil = now.addingTimeInterval(Self.queryRest) }
                        }
                        if source.answers.count > Self.maxAnswers,
                           let oldest = source.answers.min(by: { $0.value.at < $1.value.at })?.key {
                            source.answers[oldest] = nil
                        }
                        committed.answered.append(key)
                    case let .cache(cached):
                        // Read for this source as it is (not one forgotten meanwhile, a disabled one's), and still none
                        // loaded.
                        guard source.cache == .reading else { continue }
                        source.cache = .read
                        guard let cached, source.list == nil else { continue }
                        source.list = cached.items
                        source.loadedAt = Date(timeIntervalSince1970: cached.loadedAt)
                        source.madeAt = Date(timeIntervalSince1970: cached.fetchedAt ?? cached.loadedAt)
                        if let used = cached.lastUsed {
                            source.lastUsed = max(source.lastUsed ?? .distantPast, Date(timeIntervalSince1970: used))
                        }
                        committed.cached.append(key)
                    }
                }
                state.sources[key] = source
            }
        }
        if let folder {
            for (key, source) in writes { Self.write(source, of: key, in: folder) }
        }
        return committed
    }

    // MARK: - Loads

    /// What a source's load is to do now (`loadDue`).
    struct Plan {
        var load: Bool
        /// A pause or failures were forgotten ("Refresh now", an update, a day later): the status changed.
        var resumed: Bool
    }

    /// Whether `key`'s list is to be loaded at `now`: "Refresh now" pressed since its last load (`refresh`), paused or not;
    /// none while one is in flight (within `timeout`), it is paused (until an update of its plugin or an edit of its
    /// command, `version`, or a day later) or backing off; else when it has none, or it is past its `refresh` interval and
    /// was used in the last 7 days.
    func plan(_ key: CompletionSourceKey, refresh interval: TimeInterval, timeout: TimeInterval, version: String,
              request: CompletionSourceRefresh?, now: Date) -> Plan {
        with(key) { source in
            // Its cache on disk being read: what is due is known once it is.
            guard source.cache != .reading else { return Plan(load: false, resumed: false) }
            if let loading = source.loading {
                guard now.timeIntervalSince(loading.since) > timeout + 10 else { return Plan(load: false, resumed: false) }
                source.loading = nil  // its task never answered
            }
            var resumed = false
            if let request, request.requested != source.refreshDone,
               source.attemptAt.map({ request.requested > $0 }) ?? true {
                source.refreshDone = request.requested
                resumed = source.pausedAt != nil || source.failures > 0
                (source.failures, source.failedAt, source.pausedAt) = (0, nil, nil)
                return Plan(load: true, resumed: resumed)
            }
            if let pausedAt = source.pausedAt {
                guard version != source.pausedVersion || now.timeIntervalSince(pausedAt) >= Self.pause else {
                    return Plan(load: false, resumed: false)
                }
                (source.failures, source.failedAt, source.pausedAt) = (0, nil, nil)
                return Plan(load: true, resumed: true)
            }
            if source.failures > 0, let failedAt = source.failedAt,
               now.timeIntervalSince(failedAt) < Self.backOff[min(source.failures, Self.backOff.count) - 1] {
                return Plan(load: false, resumed: false)
            }
            if source.list == nil { return Plan(load: true, resumed: resumed) }
            guard let loadedAt = source.loadedAt, now.timeIntervalSince(loadedAt) >= interval,
                  let used = source.lastUsed, now.timeIntervalSince(used) < Self.unusedAfter else { return Plan(load: false, resumed: false) }
            return Plan(load: true, resumed: false)
        }
    }

    /// A load of `key` starts at `now`: its id.
    func startLoad(_ key: CompletionSourceKey, now: Date) -> Int {
        let id = nextID()
        with(key) { source in
            source.loading = (id, now)
            source.attemptAt = now
        }
        return id
    }

    /// When `key`'s last load started (nil: none this launch). A session starts a load as it handles an event, or not
    /// then: the tests see at once that it didn't.
    func lastLoadStarted(_ key: CompletionSourceKey) -> Date? {
        state.withLock { $0.sources[key]?.attemptAt }
    }

    /// When a source of `keys` may be due next after `now` (a refresh, a back-off or a pause ending), for a timer: nil,
    /// none is.
    func nextDue(_ keys: [(key: CompletionSourceKey, refresh: TimeInterval)], now: Date) -> Date? {
        state.withLock { state in
            keys.compactMap { key, refresh -> Date? in
                guard let source = state.sources[key], source.loading == nil, source.cache != .reading else { return nil }
                if let pausedAt = source.pausedAt { return pausedAt.addingTimeInterval(Self.pause) }
                if source.failures > 0, let failedAt = source.failedAt {
                    return failedAt.addingTimeInterval(Self.backOff[min(source.failures, Self.backOff.count) - 1])
                }
                guard let loadedAt = source.loadedAt, let used = source.lastUsed else { return nil }
                let due = loadedAt.addingTimeInterval(refresh)
                return due.timeIntervalSince(used) < Self.unusedAfter ? due : nil
            }.filter { $0 > now }.min()
        }
    }

    // MARK: - Use

    func markUsed(_ key: CompletionSourceKey, now: Date) {
        with(key) { $0.lastUsed = now }
    }

    /// The list of `key` (nil: none yet), and its age's start.
    func list(_ key: CompletionSourceKey) -> (items: CompletionItems, madeAt: Date?)? {
        state.withLock { state in
            state.sources[key].flatMap { source in source.list.map { ($0, source.madeAt) } }
        }
    }

    // MARK: - Queries

    /// The answers kept for `key`'s texts that `text` (in small letters) starts with, the longest first, as of `now`.
    func answers(_ key: CompletionSourceKey, for text: String, now: Date) -> [(text: String, items: CompletionItems)] {
        state.withLock { state in
            guard let source = state.sources[key] else { return [] }
            return source.answers.filter { text.hasPrefix($0.key) && now.timeIntervalSince($0.value.at) < Self.answerLife }
                .sorted { $0.key.count > $1.key.count }.map { ($0.key, $0.value.items) }
        }
    }

    /// The query in flight for `key`: its text (in small letters), if one is (within `timeout`).
    func queryInFlight(_ key: CompletionSourceKey, timeout: TimeInterval, now: Date) -> String? {
        with(key) { source in
            guard let query = source.query else { return nil }
            guard now.timeIntervalSince(query.since) <= timeout + 2 else {
                query.task?.cancel()
                source.query = nil
                return nil
            }
            return query.text
        }
    }

    /// Whether `key` rests from queries now (they failed in a row).
    func queriesRest(_ key: CompletionSourceKey, now: Date) -> Bool {
        with(key) { source in source.queryRestUntil.map { now < $0 } ?? false }
    }

    /// A query of `key` for `text` (in small letters) starts: the one in flight is cancelled; its id.
    func startQuery(_ key: CompletionSourceKey, text: String, now: Date) -> Int {
        let id = nextID()
        with(key) { source in
            source.query?.task?.cancel()
            source.query = (id, text, now, nil)
        }
        return id
    }

    /// The task running query `id` of `key`, to cancel it with.
    func setQueryTask(_ key: CompletionSourceKey, id: Int, task: Task<Void, Never>) {
        let stale = with(key) { source -> Bool in
            guard source.query?.id == id else { return true }
            source.query?.task = task
            return false
        }
        if stale { task.cancel() }
    }

    // MARK: - The cache on disk

    /// The list cached for `key` in `folder`, read once a launch into a source that has none yet: off the caller's thread
    /// (it may be 4 MB of JSON, behind a write), taken in by the next `commit` (the sessions told as of a load); meanwhile
    /// no load is planned for it. True when a read started.
    func readCache(_ key: CompletionSourceKey, in folder: URL, from session: ObjectIdentifier,
                   starter: @escaping @Sendable (SessionEvent) -> Void) -> Bool {
        guard with(key, { source -> Bool in
            guard source.cache == .unread else { return false }
            source.cache = source.list == nil ? .reading : .read
            return source.list == nil
        }) else { return false }
        let url = folder.appendingPathComponent(key.fileName)
        Self.disk.async {
            let cached = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CachedList.self, from: $0) }
            self.deposit(key, .cache(cached.map {
                CachedLoad(items: CompletionItems($0.items), fetchedAt: $0.fetchedAt, loadedAt: $0.loadedAt, lastUsed: $0.lastUsed)
            }), from: session, starter: starter)
        }
        return true
    }

    /// The cache file's contents.
    struct CachedList: Codable {
        var items: [CompletionItem]
        var fetchedAt: Double?
        var loadedAt: Double
        var lastUsed: Double?
    }

    /// Where a list is written before it is renamed into `folder`: a hidden folder beside it, on its volume (what lists
    /// `folder` never finds a file half written).
    static func staging(for folder: URL) -> URL {
        folder.deletingLastPathComponent().appendingPathComponent(".\(folder.lastPathComponent).staging", isDirectory: true)
    }

    /// `source`'s list written to its file in `folder` (readable by the user only), off the session's thread.
    static func write(_ source: Source, of key: CompletionSourceKey, in folder: URL) {
        guard let items = source.list, let loadedAt = source.loadedAt else { return }
        let cached = CachedList(items: items.items, fetchedAt: source.madeAt?.timeIntervalSince1970, loadedAt: loadedAt.timeIntervalSince1970,
                                lastUsed: source.lastUsed?.timeIntervalSince1970)
        disk.async {
            guard let data = try? JSONEncoder().encode(cached) else { return }
            do {
                #if os(Windows)
                // The file is the user's alone (`writePrivate`); the folder as the user's folders are.
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                #else
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                #endif
                try Platform.current.files.writePrivate(data, to: folder.appendingPathComponent(key.fileName), stagingIn: staging(for: folder))
            } catch {
                SuggestionsStore.log.error("suggestions: a list couldn't be cached (\(type(of: error)))")
            }
        }
    }

    /// Forgets the sources not in `enabled` (disabled, their plugin removed, a custom command deleted:
    /// `SuggestionsSettings.sourceKeys`), and deletes their files in `folder`, and what a write stopped half way left
    /// beside it (none is under way: the writes are on the same queue).
    public func prune(keeping enabled: Set<CompletionSourceKey>, folder: URL?) {
        state.withLock { state in
            for key in state.sources.keys.filter({ !enabled.contains($0) }) {
                state.sources[key]?.query?.task?.cancel()
                state.sources[key] = nil
            }
        }
        guard let folder else { return }
        Self.disk.async {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            let kept = Set(enabled.map(\.fileName))
            for name in names where CompletionSourceKey.isCacheFile(name) && !kept.contains(name) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            let staging = Self.staging(for: folder)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? [] where name.hasSuffix(".tmp") {
                try? FileManager.default.removeItem(at: staging.appendingPathComponent(name))
            }
        }
    }

    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")
}

/// Where completion scripts' calls (`CompletionRuntime`) run: threads of their own, not the concurrency pool's, which
/// other work can hold (a call waited for while the pool's threads all wait on something else would never start).
enum SuggestionsWork {
    /// Runs `operation` off the caller's thread; the task, to cancel it with.
    @discardableResult
    static func start(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) {
            return Task.detached(executorPreference: SuggestionsExecutor.shared, operation: operation)
        }
        return Task.detached(operation: operation)
    }
}

/// A task executor on Dispatch's threads (`SuggestionsWork`).
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
final class SuggestionsExecutor: TaskExecutor {
    static let shared = SuggestionsExecutor()
    private let queue = DispatchQueue(label: "com.aipinyin.inputmethod.suggestions.work", qos: .userInitiated, attributes: .concurrent)

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}

/// Files' SHA-256s (lowercase hex), each read again only when its size or date changed: what pins a plugin's script or
/// a script extension (`ExtensionDigest`), read as a field takes the focus and before each run, without reading every
/// file each time.
public final class FileHashes: @unchecked Sendable {
    /// A file's size and date as the file system has them (to the nanosecond where it says).
    struct Stamp: Equatable {
        var size: Int
        var seconds: Int
        var nanoseconds: Int
    }

    private let kept = Locked<[String: (stamp: Stamp, sha: String)]>(initialState: [:])

    public init() {}

    /// The SHA-256 of the file at `url` (nil: none, or it can't be read).
    public func sha256(of url: URL) -> String? {
        guard let stamp = Self.stamp(url.path) else { return nil }
        if let had = kept.withLock({ $0[url.path] }), had.stamp == stamp { return had.sha }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        kept.withLock { $0[url.path] = (stamp, sha) }
        return sha
    }

    /// `path`'s size and date now, never a value kept (a URL keeps those it read): the item itself, a link not followed.
    /// Where there is `lstat`, by it (a few microseconds; the file manager's attributes take ten times as long, which a
    /// repository of 2,000 files read as a field takes the focus would feel).
    static func stamp(_ path: String) -> Stamp? {
        #if canImport(Darwin)
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Stamp(size: Int(info.st_size), seconds: Int(info.st_mtimespec.tv_sec), nanoseconds: Int(info.st_mtimespec.tv_nsec))
        #else
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let size = (attributes?[.size] as? NSNumber)?.intValue else { return nil }
        let time = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return Stamp(size: size, seconds: Int(time.rounded(.down)), nanoseconds: Int((time - time.rounded(.down)) * 1_000_000_000))
        #endif
    }
}
