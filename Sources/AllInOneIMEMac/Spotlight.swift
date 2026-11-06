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
    /// first, then the most recently changed, at most `limit`. Asked of Spotlight in this process (an MDQuery), not
    /// through an mdfind of its own: no program starts, nothing is printed and read back, and Spotlight sorts and stops at
    /// `limit` itself. What it found by the time limit; nil once the search is cancelled.
    public func names(_ keyword: String, in scopes: [String], limit: Int) -> [FileSearchRanking.Found]? {
        guard !isCancelled else { return nil }
        let predicate = "kMDItemDisplayName == \"\(FileSearchRanking.escaped(keyword))*\"cdw"
        let dates = [kMDItemLastUsedDate!, kMDItemContentModificationDate!]
        guard let made = MDQueryCreate(kCFAllocatorDefault, predicate as CFString, nil, dates as CFArray) else { return [] }
        let query = Query(made)
        let newestFirst = UInt32(kMDQueryReverseSortOrderFlag.rawValue)
        for date in dates { MDQuerySetSortOptionFlagsForAttribute(made, date, newestFirst) }
        MDQuerySetMaxCount(made, limit)
        MDQuerySetSearchScope(made, scopes as CFArray, 0)
        // A `cancel` that comes before the query is in `queries` is seen right after.
        let wanted = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            queries.append(query)
            return true
        }
        guard wanted else { return nil }
        let timer = DispatchWorkItem { query.stop() }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: timer)
        MDQueryExecute(made, CFOptionFlags(kMDQuerySynchronous.rawValue))  // until Spotlight is done, or stopped
        timer.cancel()
        lock.withLock { queries.removeAll { $0 === query } }
        guard !isCancelled else { return nil }
        MDQueryDisableUpdates(made)
        var found: [FileSearchRanking.Found] = []
        for index in 0..<MDQueryGetResultCount(made) {
            guard let item = MDQueryGetResultAtIndex(made, index),
                  let path = MDItemCopyAttribute(Unmanaged<MDItem>.fromOpaque(item).takeUnretainedValue(), kMDItemPath) as? String
            else { continue }
            // The dates Spotlight sorted by came with the results: no more is asked of it.
            func date(_ name: CFString) -> Date? {
                MDQueryGetAttributeValueOfResultAtIndex(made, name, index).map { Unmanaged<CFDate>.fromOpaque($0).takeUnretainedValue() as Date }
            }
            found.append(FileSearchRanking.Found(path: path, lastUsed: date(dates[0]), modified: date(dates[1])))
        }
        return found
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

    /// A query `names` runs. (MDQueryStop may be called from any thread, as the time limit and `cancel` do; this says
    /// so to the compiler.)
    private final class Query: @unchecked Sendable {
        let query: MDQuery
        init(_ query: MDQuery) { self.query = query }
        func stop() { MDQueryStop(query) }
    }

    /// Stops one process. (A Process may be stopped from any thread; this says so to the compiler.)
    private struct Stopper: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func run() { if process.isRunning { process.terminate() } }
    }
}
