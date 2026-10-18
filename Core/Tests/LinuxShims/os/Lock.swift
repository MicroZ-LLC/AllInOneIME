import Foundation

// Off Apple platforms only (Package.swift): the tests written against Apple's `os` find its lock here, so they build on
// Linux unchanged. The core itself uses `Locked`.

/// `OSAllocatedUnfairLock(initialState:)`, as the tests use it: an `NSLock` around the state.
public final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
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
