import Dispatch
import Foundation

/// A serial queue: one connection's work runs on one, in order (§11). The server's state for the connection, and its
/// sessions' Composers, are only touched there.
public protocol WireQueue: AnyObject, Sendable {
    /// Runs `work` on the queue, after what is queued already, and waits for it.
    func sync<T>(_ work: () throws -> T) rethrows -> T
    /// Queues `work`.
    func async(_ work: @escaping @Sendable () -> Void)
    /// Waits until nothing is queued, also what queued work queues in turn.
    func drain()
    /// How long the work running now has been running, in seconds (0: none): the engine's watchdog (§2.5).
    var busyFor: Double { get }
}

/// A timer `WireClock.after` started.
public final class WireTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() { lock.guarded { cancelled = true } }
    public var isCancelled: Bool { lock.guarded { cancelled } }
}

/// The engine's time: the system's, or a manual one that tests (and the engine's test mode) move on.
public protocol WireClock: AnyObject, Sendable {
    /// Seconds, monotonic.
    var now: Double { get }
    /// Calls `work`, on any thread, `seconds` from now, unless the timer is cancelled first.
    @discardableResult
    func after(_ seconds: Double, _ work: @escaping @Sendable () -> Void) -> WireTimer
}

// MARK: - The system's

/// A `DispatchQueue`, timed for the watchdog.
public final class DispatchWireQueue: WireQueue, @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var started: Double?
    private var pending = 0

    public init(label: String) { queue = DispatchQueue(label: label) }

    public func sync<T>(_ work: () throws -> T) rethrows -> T {
        try queue.sync { try timed(work) }
    }

    public func async(_ work: @escaping @Sendable () -> Void) {
        lock.guarded { pending += 1 }
        queue.async { [self] in
            timed(work)
            lock.guarded { pending -= 1 }
        }
    }

    public func drain() {
        repeat { queue.sync {} } while lock.guarded({ pending }) > 0
    }

    public var busyFor: Double {
        lock.guarded { started.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0 }
    }

    private func timed<T>(_ work: () throws -> T) rethrows -> T {
        lock.guarded { started = ProcessInfo.processInfo.systemUptime }
        defer { lock.guarded { started = nil } }
        return try work()
    }
}

/// The system's monotonic time.
public final class SystemClock: WireClock, @unchecked Sendable {
    public init() {}

    public var now: Double { ProcessInfo.processInfo.systemUptime }

    @discardableResult
    public func after(_ seconds: Double, _ work: @escaping @Sendable () -> Void) -> WireTimer {
        let timer = WireTimer()
        DispatchQueue.global().asyncAfter(deadline: .now() + max(seconds, 0)) {
            if !timer.isCancelled { work() }
        }
        return timer
    }
}

// MARK: - A manual clock

/// Time that only moves when told (`advance`): the goldens' clock, in the tests and in the engine's test mode, so a
/// scripted stream is exactly as far along as a transcript says.
public final class ManualClock: WireClock, @unchecked Sendable {
    private struct Entry {
        var due: Double
        var order: Int
        var timer: WireTimer
        var work: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var time: Double
    private var entries: [Entry] = []
    private var counter = 0

    public init(now: Double = 0) { time = now }

    public var now: Double { lock.guarded { time } }

    @discardableResult
    public func after(_ seconds: Double, _ work: @escaping @Sendable () -> Void) -> WireTimer {
        let timer = WireTimer()
        lock.guarded {
            counter += 1
            entries.append(Entry(due: time + max(seconds, 0), order: counter, timer: timer, work: work))
        }
        return timer
    }

    /// When the next timer that isn't cancelled is due, if any.
    public var nextDue: Double? {
        lock.guarded { entries.filter { !$0.timer.isCancelled }.map(\.due).min() }
    }

    /// Moves the time to `target` (never back), calling each timer due by then in order, on this thread.
    public func advance(to target: Double) {
        while let entry = takeNext(dueBy: target) {
            if !entry.timer.isCancelled { entry.work() }
        }
        lock.guarded { time = max(time, target) }
    }

    public func advance(by seconds: Double) { advance(to: now + seconds) }

    private func takeNext(dueBy target: Double) -> Entry? {
        lock.guarded {
            entries.removeAll { $0.timer.isCancelled }
            guard let i = entries.indices.filter({ entries[$0].due <= target })
                .min(by: { (entries[$0].due, entries[$0].order) < (entries[$1].due, entries[$1].order) })
            else { return nil }
            let entry = entries.remove(at: i)
            time = max(time, entry.due)
            return entry
        }
    }
}

extension NSLock {
    /// `body` with the lock held (`NSLocking.withLock` isn't in every Foundation this builds with).
    func guarded<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
