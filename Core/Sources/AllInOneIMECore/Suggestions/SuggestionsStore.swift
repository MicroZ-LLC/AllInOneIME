import Crypto
import Foundation

/// A completion source of a plugin, by their names.
public struct CompletionSourceKey: Hashable, Sendable {
    public var plugin: String
    public var source: String

    public init(plugin: String, source: String) {
        self.plugin = plugin
        self.source = source
    }

    /// Its file in the cache folder: "<plugin>.<source>.json" (names of small letters and digits).
    var fileName: String { "\(plugin).\(source).json" }

    /// The source a cache file is of, by its name; nil for any other file.
    init?(fileName: String) {
        let parts = fileName.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "json", CompletionDeclaration.isName(String(parts[1])),
              (1...24).contains(parts[0].count), parts[0].allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) else { return nil }
        self.init(plugin: String(parts[0]), source: String(parts[1]))
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

    /// A load's or a query's result, as its task left it.
    enum Pending {
        case load(id: Int, Result<LoadedList, LoadFailure>)
        /// nil: it failed (or was cancelled: `cancelled`).
        case query(id: Int, text: String, items: CompletionItems?, cancelled: Bool)
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
        /// The plugin's version when it paused: another one (an update) resumes it.
        var pausedVersion: String?
        /// The latest "Refresh now" acted on.
        var refreshDone: Date?
        var lastUsed: Date?
        /// The disk cache was looked at this launch.
        var cacheRead = false
        var answers: [String: Answer] = [:]
        var query: (id: Int, text: String, since: Date, task: Task<Void, Never>?)?
        var queryFailures = 0
        var queryRestUntil: Date?
        var pending: [Pending] = []
    }

    struct State {
        var sources: [CompletionSourceKey: Source] = [:]
        var serial = 0
        var hashes: [String: (modified: Date?, size: Int, sha: String)] = [:]
        /// The sessions of the fields that have the focus, told when a result came back (`answered`).
        var listeners: [ObjectIdentifier: @Sendable (SessionEvent) -> Void] = [:]
    }

    let state = Locked(initialState: State())
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
    func sha256(of url: URL) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes?[.size] as? NSNumber)?.intValue else { return nil }
        let modified = attributes?[.modificationDate] as? Date
        if let kept = state.withLock({ $0.hashes[url.path] }), kept.size == size, kept.modified == modified { return kept.sha }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        state.withLock { $0.hashes[url.path] = (modified, size, sha) }
        return sha
    }

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

    /// What changed with a commit: the sources whose list or status changed (`statusChanged`), and those a query answered.
    struct Committed {
        var statusChanged: [CompletionSourceKey] = []
        var listsChanged: [CompletionSourceKey] = []
        var answered: [CompletionSourceKey] = []
        var isEmpty: Bool { statusChanged.isEmpty && answered.isEmpty }
    }

    /// The results the tasks left, taken in at `now` (the session's thread): a good list replaces the old one (and is
    /// cached in `folder`), a failure keeps it and backs off (the fifth in a row pauses the source, `version` its
    /// plugin's then); a query's answer is kept for its text.
    func commit(now: Date, folder: URL?, versions: [String: String]) -> Committed {
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
                                source.pausedVersion = versions[key.plugin]
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
    /// none while one is in flight (within `timeout`), it is paused (until an update of its plugin, `version`, or a day
    /// later) or backing off; else when it has none, or it is past its `refresh` interval and was used in the last 7 days.
    func plan(_ key: CompletionSourceKey, refresh interval: TimeInterval, timeout: TimeInterval, version: String,
              request: CompletionSourceRefresh?, now: Date) -> Plan {
        with(key) { source in
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

    /// When a source of `keys` may be due next after `now` (a refresh, a back-off or a pause ending), for a timer: nil,
    /// none is.
    func nextDue(_ keys: [(key: CompletionSourceKey, refresh: TimeInterval)], now: Date) -> Date? {
        state.withLock { state in
            keys.compactMap { key, refresh -> Date? in
                guard let source = state.sources[key], source.loading == nil else { return nil }
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

    /// The list cached for `key` in `folder`, read once a launch into a source that has none yet: true when one was.
    func readCache(_ key: CompletionSourceKey, in folder: URL) -> Bool {
        guard with(key, { source -> Bool in
            defer { source.cacheRead = true }
            return !source.cacheRead && source.list == nil
        }) else { return false }
        let url = folder.appendingPathComponent(key.fileName)
        guard let data = Self.disk.sync(execute: { try? Data(contentsOf: url) }),
              let cached = try? JSONDecoder().decode(CachedList.self, from: data) else { return false }
        let items = CompletionItems(cached.items)
        return with(key) { source in
            guard source.list == nil else { return false }
            source.list = items
            source.loadedAt = Date(timeIntervalSince1970: cached.loadedAt)
            source.madeAt = Date(timeIntervalSince1970: cached.fetchedAt ?? cached.loadedAt)
            if let used = cached.lastUsed { source.lastUsed = max(source.lastUsed ?? .distantPast, Date(timeIntervalSince1970: used)) }
            return true
        }
    }

    /// The cache file's contents.
    struct CachedList: Codable {
        var items: [CompletionItem]
        var fetchedAt: Double?
        var loadedAt: Double
        var lastUsed: Double?
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
                try Platform.current.files.writePrivate(data, to: folder.appendingPathComponent(key.fileName))
            } catch {
                SuggestionsStore.log.error("suggestions: a list couldn't be cached (\(type(of: error)))")
            }
        }
    }

    /// Forgets the sources not in `enabled` (disabled, or their plugin removed), and deletes their files in `folder`.
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
            for name in names {
                guard let key = CompletionSourceKey(fileName: name), !enabled.contains(key) else { continue }
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
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
