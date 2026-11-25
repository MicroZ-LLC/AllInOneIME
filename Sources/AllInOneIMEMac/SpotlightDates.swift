import AllInOneIMECore
import Foundation

/// When apps (and places) were last used and changed, as Spotlight keeps them, for ranking (`FileSearchRanking`); its
/// name search knows an app by its file name and its name in the system language only. Asked one at a time on a queue
/// of its own and waited for `budget` in all: an answer that never comes (a stuck Spotlight: `MDItemCreateWithURL` was
/// seen to wait for good on the Mac mini, 2026-11-25, holding @'s apps and files) leaves the rest undated, ranked as if
/// Spotlight knew no dates, and holds nothing up. While a lookup from before is still waiting, none is started: the apps
/// go undated until it returns. Never called on the main thread (`InstantFiles`' queue, `FileSearch.files`' global one).
public final class SpotlightDates: @unchecked Sendable {
    public typealias Dates = (lastUsed: Date?, modified: Date?)

    public static let shared = SpotlightDates()

    /// One app's dates (nil: Spotlight knows nothing of it).
    let lookup: @Sendable (String) -> Dates?
    /// How long `dated` waits for all of its lookups.
    let budget: TimeInterval
    private let queue = DispatchQueue(label: "allinoneime.spotlight-dates", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false

    init(budget: TimeInterval = 1.5, lookup: @escaping @Sendable (String) -> Dates? = SpotlightDates.spotlight) {
        (self.budget, self.lookup) = (budget, lookup)
    }

    static func spotlight(_ path: String) -> Dates? {
        guard let item = NSMetadataItem(url: URL(fileURLWithPath: path)) else { return nil }
        return (item.value(forAttribute: "kMDItemLastUsedDate") as? Date, item.value(forAttribute: "kMDItemContentModificationDate") as? Date)
    }

    /// `apps` with their dates, those that came within `budget`; the others as they were.
    func dated(_ apps: [FileSearchRanking.Found]) -> [FileSearchRanking.Found] {
        let started = lock.withLock { () -> Bool in
            guard !busy, !apps.isEmpty else { return false }
            busy = true
            return true
        }
        guard started else { return apps }
        let answers = Answers(), done = DispatchSemaphore(value: 0), paths = apps.map(\.path), lookup = lookup
        queue.async { [self] in
            for (index, path) in paths.enumerated() where !answers.stopped {
                answers.set(index, lookup(path))
            }
            lock.withLock { busy = false }
            done.signal()
        }
        // Off the main thread (see above), and bounded: what isn't in by then is left undated.
        _ = done.wait(timeout: .now() + budget)
        let dates = answers.stop()
        return apps.enumerated().map { index, app in
            guard let found = dates[index] else { return app }
            var app = app
            (app.lastUsed, app.modified) = (found.lastUsed, found.modified)
            return app
        }
    }

    /// The dates come in on the lookups' queue; read once the wait is over, after which no more are taken.
    private final class Answers: @unchecked Sendable {
        private let lock = NSLock()
        private var dates: [Int: Dates] = [:]
        private var done = false
        var stopped: Bool { lock.withLock { done } }
        func set(_ index: Int, _ found: Dates?) { lock.withLock { if !done, let found { dates[index] = found } } }
        func stop() -> [Int: Dates] { lock.withLock { done = true; return dates } }
    }
}
