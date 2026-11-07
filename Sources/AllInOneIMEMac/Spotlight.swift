import AllInOneIMECore
import CoreServices
import Foundation

/// The Spotlight searches of one `@open` search, mdfind processes and queries in this process (`names`): each is
/// stopped at the search's time limit, and all of them as soon as the search is cancelled. None starts after that, and
/// what they found is dropped.
public final class Spotlight: @unchecked Sendable {
    public let deadline: DispatchTime
    private let executable: URL
    private let lock = NSLock()
    private var running: [Process] = []
    private var queries: [Query] = []
    private var cancelled = false

    /// `executable` runs instead of mdfind (the tests use a shell).
    public init(until deadline: DispatchTime, executable: URL = URL(fileURLWithPath: "/usr/bin/mdfind")) {
        self.deadline = deadline
        self.executable = executable
    }

    public var isCancelled: Bool { lock.withLock { cancelled } }

    /// Whether a search started now still has time, and is still wanted.
    public var hasTimeLeft: Bool { DispatchTime.now() < deadline && !isCancelled }

    /// Whether a query of `names` is running (the tests wait for one).
    var isAsking: Bool { lock.withLock { !queries.isEmpty } }
    /// Told each query of `names` once it runs, on the thread waiting for it (the tests hold its queue up, as Spotlight's
    /// own deliveries do under load).
    var queryRuns: (@Sendable (Query) -> Void)?

    /// What `mdfind arguments` printed by the time limit (its notes on stderr are dropped); nil once
    /// the search is cancelled, even if it printed something before.
    public func mdfind(_ arguments: [String]) -> Data? {
        guard !isCancelled else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Launched outside the lock: `cancel` runs on the main thread, which must not wait for a launch.
        // A `cancel` that comes before the process is in `running` is seen right after.
        guard (try? process.run()) != nil else { return isCancelled ? nil : Data() }
        let wanted = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            running.append(process)
            return true
        }
        let stop = Stopper(process)
        if !wanted { stop.run() }
        let timer = DispatchWorkItem { stop.run() }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: timer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        lock.withLock { running.removeAll { $0 === process } }
        return isCancelled ? nil : data
    }

    /// What each search printed, all of them run at once; nil once the search is cancelled.
    public func mdfind(each searches: [[String]]) -> [Data]? {
        let outputs = Locked(initialState: [Data](repeating: Data(), count: searches.count))
        DispatchQueue.concurrentPerform(iterations: searches.count) { index in
            let printed = mdfind(searches[index]) ?? Data()
            outputs.withLock { $0[index] = printed }
        }
        return isCancelled ? nil : outputs.withLock { $0 }
    }

    /// The files `keyword` names as `mdfind -name` finds them (a word of the name Finder shows starting with it, case
    /// and accents aside), inside `scopes` only, each with when it was last used and changed; with `days`, only the apps
    /// and what was used or changed since the start of the day that many days ago. All of them, in no particular order
    /// (`FileSearchRanking.rank` orders them): Spotlight's own limit (`MDQuerySetMaxCount`) keeps an arbitrary few, not
    /// the newest, and fewer than it is given where the scopes leave out much of a volume ("pl" kept 3 of 552 on a Mac
    /// mini). Asked of Spotlight in this process (an MDQuery, `Query`), not through an mdfind of its own: no program
    /// starts, nothing is printed and read back. What it found by the time limit; nil once the search is cancelled.
    public func names(_ keyword: String, in scopes: [String], within days: Int? = nil) -> [FileSearchRanking.Found]? {
        guard hasTimeLeft else { return isCancelled ? nil : [] }
        let named = "kMDItemDisplayName == \"\(FileSearchRanking.escaped(keyword))*\"cdw"
        let predicate = days.map { days in
            ["kMDItemLastUsedDate >= $time.today(-\(days))", "kMDItemContentModificationDate >= $time.today(-\(days))",
             "kMDItemContentType == \"com.apple.application-bundle\""].joined(separator: " || ")
        }.map { "(\(named)) && (\($0))" } ?? named
        // The dates come with the results (`MDQueryGetAttributeValueOfResultAtIndex`). The path can't (asked for with
        // them, no value comes at all), so each result is asked for it: some 3 µs each.
        guard let made = MDQueryCreate(kCFAllocatorDefault, predicate as CFString, Query.dates as CFArray, nil) else { return [] }
        MDQuerySetSearchScope(made, scopes as CFArray, 0)
        let query = Query(made)
        // A `cancel` that comes before the query is in `queries` is seen right after.
        let wanted = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            queries.append(query)
            return true
        }
        guard wanted else { return nil }
        let found = query.run(until: deadline, runs: queryRuns)
        lock.withLock { queries.removeAll { $0 === query } }
        return isCancelled ? nil : found
    }

    /// What `names` found for each keyword, all of them asked at once; nil once the search is cancelled. Each is asked
    /// for what was used or changed in the last `recentFirst[0]` days first (`names`' `within`), then in the last
    /// `recentFirst[1]` and so on, and for all its matches last, each only while `enough` says what was found so far
    /// isn't enough: it has what all of those found.
    public func names(each keywords: [String], in scopes: [String], recentFirst days: [Int] = [],
                      enough: @Sendable ([FileSearchRanking.Found]) -> Bool = { _ in true }) -> [[FileSearchRanking.Found]]? {
        let outputs = Locked(initialState: [[FileSearchRanking.Found]](repeating: [], count: keywords.count))
        DispatchQueue.concurrentPerform(iterations: keywords.count) { index in
            var found: [FileSearchRanking.Found] = []
            for days in days.map(Optional.some) + [nil] {
                guard let more = names(keywords[index], in: scopes, within: days) else { break }
                found += more
                if enough(found) { break }
            }
            outputs.withLock { [found] in $0[index] = found }
        }
        return isCancelled ? nil : outputs.withLock { $0 }
    }

    /// Stops what is running, and keeps what would come next from starting. Called on the main thread
    /// (a task's cancellation handler runs where the task is cancelled): the lock is only held to take
    /// the list, never while a process starts or stops.
    public func cancel() {
        let (processes, queries) = lock.withLock { () -> ([Process], [Query]) in
            cancelled = true
            return (running, self.queries)
        }
        for process in processes { Stopper(process).run() }
        for query in queries { query.stop() }
    }

    /// A query `names` runs, on a queue of its own: Spotlight delivers its results there (`MDQuerySetDispatchQueue`), and
    /// everything done with the MDQuery is done there too (it is run, read and stopped), since nothing says an MDQuery
    /// may be used from several threads at once. Its results are read there as Spotlight says it found more (its
    /// progress), into a list of their own; whoever waits for it (`run`) waits on a semaphore, never on the queue, and
    /// takes that list: under load Spotlight's own deliveries back the queue up, and a time limit or a cancel would wait
    /// behind all of them (12 s for everything on the disk). The query is stopped and let go of on its queue after that,
    /// kept until then; nothing more is read once its waiter is gone, and nothing is returned of a cancelled one.
    final class Query: @unchecked Sendable {
        /// What each result comes with.
        static var dates: [CFString] { [kMDItemLastUsedDate!, kMDItemContentModificationDate!] }

        private let query: MDQuery
        let queue = DispatchQueue(label: "com.aipinyin.inputmethod.spotlight-names", qos: .userInitiated)
        /// Signalled when Spotlight is done, and by `stop`.
        private let ended = DispatchSemaphore(value: 0)
        /// What was read of the results so far (on `queue`); whether the query is over for its waiter (`run` returned, or
        /// `stop` came: nothing more is read) and whether it was cancelled (`stop`: nothing is returned).
        private let state = Locked(initialState: (found: [FileSearchRanking.Found](), over: false, cancelled: false))
        /// How many of the query's results were read (on `queue`): Spotlight adds those it gathers after them.
        private(set) var read = 0

        init(_ query: MDQuery) {
            self.query = query
            MDQuerySetDispatchQueue(query, queue)
            // Progress told often (Spotlight's own batches are larger and less often, and what came in since the last is
            // only handed over then): what it found by a time limit is read by then.
            var batches = MDQueryGetBatchingParameters(query)
            (batches.first_max_num, batches.first_max_ms) = (100, 20)
            (batches.progress_max_num, batches.progress_max_ms) = (2000, 50)
            MDQuerySetBatchingParameters(query, batches)
        }

        /// What Spotlight found until it was done, `deadline` passed or `stop` came, whichever was first (nil: stopped);
        /// it is stopped then, on its queue, after what Spotlight delivered there meanwhile, and let go of. `runs` is told
        /// once it is started there.
        func run(until deadline: DispatchTime, runs: (@Sendable (Query) -> Void)? = nil) -> [FileSearchRanking.Found]? {
            let center = CFNotificationCenterGetLocalCenter()
            let observer = Unmanaged.passRetained(self).toOpaque()
            let object = UnsafeRawPointer(Unmanaged.passUnretained(query).toOpaque())
            // Started on the queue, not waited for: under load Spotlight can take seconds to start a query, and a cancel
            // meanwhile returns at once all the same (the query is stopped after, on the queue).
            queue.async { [self] in
                guard !state.withLock({ $0.over }) else { return }
                // Posted on `queue`, where the query runs.
                for name in [kMDQueryProgressNotification, kMDQueryDidFinishNotification] {
                    CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
                        guard let observer else { return }
                        let done = (name?.rawValue as String?) == (kMDQueryDidFinishNotification as String)
                        Unmanaged<Query>.fromOpaque(observer).takeUnretainedValue().gather(done: done)
                    }, name, object, .deliverImmediately)
                }
                if !MDQueryExecute(query, 0) { ended.signal() }
            }
            runs?(self)
            _ = ended.wait(timeout: deadline)
            let found = state.withLock { state -> [FileSearchRanking.Found]? in
                state.over = true
                return state.cancelled ? nil : state.found
            }
            let query = self.query
            queue.async {
                MDQueryStop(query)
                CFNotificationCenterRemoveEveryObserver(center, observer)
                Unmanaged<Query>.fromOpaque(observer).release()
            }
            return found
        }

        /// Ends the query where it is, from any thread: its waiter returns at once, with nothing; one that hasn't run yet
        /// never runs.
        func stop() {
            state.withLock {
                $0.over = true
                $0.cancelled = true
            }
            ended.signal()
        }

        /// The results Spotlight added since the last read (on `queue`, as it tells it found more), unless the query is
        /// over for its waiter; `done`: that was all, and the waiter is told.
        private func gather(done: Bool) {
            guard !state.withLock({ $0.over }) else { return }
            MDQueryDisableUpdates(query)
            let count = MDQueryGetResultCount(query)
            func date(_ name: CFString, _ index: CFIndex) -> Date? {
                guard let value = MDQueryGetAttributeValueOfResultAtIndex(query, name, index) else { return nil }
                let object = Unmanaged<CFTypeRef>.fromOpaque(value).takeUnretainedValue()
                return CFGetTypeID(object) == CFDateGetTypeID() ? unsafeDowncast(object, to: CFDate.self) as Date : nil
            }
            let (lastUsed, modified) = (Self.dates[0], Self.dates[1])
            var found: [FileSearchRanking.Found] = []
            for index in read..<max(read, count) {
                guard let item = MDQueryGetResultAtIndex(query, index),
                      let path = MDItemCopyAttribute(Unmanaged<MDItem>.fromOpaque(item).takeUnretainedValue(), kMDItemPath) as? String
                else { continue }
                found.append(FileSearchRanking.Found(path: path, lastUsed: date(lastUsed, index), modified: date(modified, index)))
            }
            read = max(read, count)
            MDQueryEnableUpdates(query)
            state.withLock { state in
                if !state.over { state.found += found }
            }
            if done { ended.signal() }
        }
    }

    /// Stops one process. (A Process may be stopped from any thread; this says so to the compiler.)
    private struct Stopper: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func run() { if process.isRunning { process.terminate() } }
    }
}
