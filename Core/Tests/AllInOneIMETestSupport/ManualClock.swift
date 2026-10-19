import Foundation
import AllInOneIMECore

/// A clock that moves only when the test moves it (`advance(by:)`), for code that takes one (`AppleModel.stream`'s
/// timeout). What sleeps on it wakes when the test says, however busy the test run is: the test waits for the code to
/// be asleep on it (`sleepers`), not for time to pass, and a timeout is tested without a wall-clock budget (`Timing`).
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol, CustomStringConvertible {
        /// The time since the clock was made.
        public var offset: Duration

        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
        public var description: String { "\(offset)" }
    }

    private struct Sleeper {
        var deadline: Instant
        var continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Int: Sleeper] = [:]
        var nextID = 0
        /// Sleeps cancelled before they started.
        var cancelled: Set<Int> = []
    }

    private let state = Locked(initialState: State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }
    public var minimumResolution: Duration { .zero }

    /// How many sleep on the clock now.
    public var sleeping: Int { state.withLock { $0.sleepers.count } }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let now: Result<Void, Error>? = state.withLock { state in
                    if state.cancelled.remove(id) != nil { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(()) }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                if let now { continuation.resume(with: now) }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                guard let sleeper = state.sleepers.removeValue(forKey: id) else {
                    state.cancelled.insert(id)
                    return Sleeper?.none
                }
                return sleeper
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the time on by `duration`, waking what sleeps until then (the earliest deadline first).
    public func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys { state.sleepers[id] = nil }
            return due.values.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Whether `count` tasks sleep on the clock, waited for up to `timeout` seconds: the code is asleep on it at once
    /// unless it is wrong (or the test run very busy, which the limit leaves room for).
    public func sleepers(_ count: Int = 1, within timeout: TimeInterval = 20) async -> Bool {
        await Timing.eventually(within: timeout) { sleeping >= count }
    }
}
