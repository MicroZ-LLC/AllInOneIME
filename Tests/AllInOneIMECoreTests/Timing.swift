import Foundation

/// Time in tests that run alongside more than a thousand others, many starting git and other programs in parallel:
/// there, starting a process or getting a turn on a core can take seconds. So a bound on how long something took is
/// set against what it would take if the code were wrong (a program that sleeps a minute), not against how fast this
/// Mac is; what is timed for speed is the CPU time of the thread doing the work, which waiting for a turn doesn't add
/// to; and what should happen soon is waited for, up to a generous limit.
enum Timing {
    /// How long a program in a test sleeps when the test checks that it is stopped before it ends by itself.
    static let longSleep = 60
    /// Stopped "well before" `longSleep` seconds: whatever the load, far more than stopping takes.
    static let wellBeforeLongSleep: TimeInterval = 30

    /// The CPU time this thread spends in `body` (as `ContinuousClock.measure`, without the time spent waiting).
    static func cpuTime(_ body: () throws -> Void) rethrows -> Duration {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        try body()
        return .nanoseconds(Int64(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start))
    }

    /// What `body` returns, and the CPU time this thread spent in it in seconds.
    static func cpuSeconds<T>(_ body: () throws -> T) rethrows -> (value: T, seconds: Double) {
        var value: T?
        let time = try cpuTime { value = try body() }
        return (value!, Double(time.components.seconds) + Double(time.components.attoseconds) / 1e18)
    }

    /// Whether `condition` holds within `timeout` seconds, asked every 20 ms.
    static func eventually(within timeout: TimeInterval = 20, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
