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
    /// and accents aside), inside `scopes` only, each with when it was last used and changed: the most recently used
    /// first, then the most recently changed, at most `limit`. Asked of Spotlight in this process (an MDQuery, `Query`),
    /// not through an mdfind of its own: no program starts, nothing is printed and read back, and Spotlight sorts and
    /// stops at `limit` itself. What it found by the time limit; nil once the search is cancelled.
    public func names(_ keyword: String, in scopes: [String], limit: Int) -> [FileSearchRanking.Found]? {
        guard hasTimeLeft else { return isCancelled ? nil : [] }
        let predicate = "kMDItemDisplayName == \"\(FileSearchRanking.escaped(keyword))*\"cdw"
        // The dates Spotlight sorts by come with the results (`MDQueryGetAttributeValueOfResultAtIndex`). The path can't
        // (asked for with them, no value comes at all), so each result is asked for it: some 3 µs each.
        guard let made = MDQueryCreate(kCFAllocatorDefault, predicate as CFString, nil, Query.dates as CFArray) else { return [] }
        let newestFirst = UInt32(kMDQueryReverseSortOrderFlag.rawValue)
        for date in Query.dates { MDQuerySetSortOptionFlagsForAttribute(made, date, newestFirst) }
        MDQuerySetMaxCount(made, limit)
        MDQuerySetSearchScope(made, scopes as CFArray, 0)
        let query = Query(made)
        // A `cancel` that comes before the query is in `queries` is seen right after.
        let wanted = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            queries.append(query)
            return true
        }
        guard wanted else { return nil }
        let found = query.run(until: deadline)
        lock.withLock { queries.removeAll { $0 === query } }
        return isCancelled ? nil : found
    }

    /// What `names` found for each keyword, all of them asked at once; nil once the search is cancelled.
    public func names(each keywords: [String], in scopes: [String], limit: (String) -> Int) -> [[FileSearchRanking.Found]]? {
        let outputs = Locked(initialState: [[FileSearchRanking.Found]](repeating: [], count: keywords.count))
        DispatchQueue.concurrentPerform(iterations: keywords.count) { index in
            let found = names(keywords[index], in: scopes, limit: limit(keywords[index])) ?? []
            outputs.withLock { $0[index] = found }
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
    /// everything else done with it is done there too (it is run, stopped and read), since nothing says an MDQuery may be
    /// used from several threads at once. Whoever waits for it (`run`) waits on a semaphore, not in a run loop.
    private final class Query: @unchecked Sendable {
        /// What each result comes with.
        static var dates: [CFString] { [kMDItemLastUsedDate!, kMDItemContentModificationDate!] }

        private let query: MDQuery
        private let queue = DispatchQueue(label: "com.aipinyin.inputmethod.spotlight-names", qos: .userInitiated)
        /// Signalled when Spotlight is done, and by `stop`.
        private let ended = DispatchSemaphore(value: 0)
        /// Whether `stop` came (on `queue`): a query it comes before is never run.
        private var stopped = false

        init(_ query: MDQuery) {
            self.query = query
            MDQuerySetDispatchQueue(query, queue)
        }

        /// What Spotlight found until it was done, `deadline` passed or `stop` came, whichever was first; it is stopped
        /// then, and let go of on return.
        func run(until deadline: DispatchTime) -> [FileSearchRanking.Found] {
            let center = CFNotificationCenterGetLocalCenter()
            let observer = Unmanaged.passRetained(ended).toOpaque()
            let object = UnsafeRawPointer(Unmanaged.passUnretained(query).toOpaque())
            let started = queue.sync { () -> Bool in
                guard !stopped else { return false }
                // Posted on `queue`, where the query runs.
                CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<DispatchSemaphore>.fromOpaque(observer).takeUnretainedValue().signal()
                }, kMDQueryDidFinishNotification, object, .deliverImmediately)
                return MDQueryExecute(query, 0)
            }
            if started { _ = ended.wait(timeout: deadline) }
            return queue.sync {
                stopped = true
                MDQueryStop(query)
                CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(kMDQueryDidFinishNotification), object)
                Unmanaged<DispatchSemaphore>.fromOpaque(observer).release()
                return results()
            }
        }

        /// Ends the query where it is, from any thread; one that hasn't run yet never runs.
        func stop() {
            queue.async { [self] in
                stopped = true
                MDQueryStop(query)
            }
            ended.signal()
        }

        /// What the query found (on `queue`, once it is stopped).
        private func results() -> [FileSearchRanking.Found] {
            MDQueryDisableUpdates(query)
            func date(_ name: CFString, _ index: CFIndex) -> Date? {
                guard let value = MDQueryGetAttributeValueOfResultAtIndex(query, name, index) else { return nil }
                let object = Unmanaged<CFTypeRef>.fromOpaque(value).takeUnretainedValue()
                return CFGetTypeID(object) == CFDateGetTypeID() ? unsafeDowncast(object, to: CFDate.self) as Date : nil
            }
            let (lastUsed, modified) = (Self.dates[0], Self.dates[1])
            var found: [FileSearchRanking.Found] = []
            for index in 0..<MDQueryGetResultCount(query) {
                guard let item = MDQueryGetResultAtIndex(query, index),
                      let path = MDItemCopyAttribute(Unmanaged<MDItem>.fromOpaque(item).takeUnretainedValue(), kMDItemPath) as? String
                else { continue }
                found.append(FileSearchRanking.Found(path: path, lastUsed: date(lastUsed, index), modified: date(modified, index)))
            }
            return found
        }
    }

    /// Stops one process. (A Process may be stopped from any thread; this says so to the compiler.)
    private struct Stopper: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func run() { if process.isRunning { process.terminate() } }
    }
}
