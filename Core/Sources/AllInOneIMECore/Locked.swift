import Foundation

/// A value behind a lock, like `OSAllocatedUnfairLock(initialState:)` (Apple-only) or `Mutex` (macOS 15): an `NSLock`,
/// which every Foundation has. A class, so copies share the value.
public final class Locked<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    public init(initialState: State) {
        state = initialState
    }

    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
