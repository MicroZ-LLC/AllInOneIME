import Foundation
import AllInOneIMECore

/// A turn the tests that change something of the process's (the interface language) take one at a time, waited for
/// suspended rather than on a lock. A test whose turn it is may block its thread waiting for work that runs on the
/// concurrency pool (`FakeHost.settle`), whose threads are one a core: tests blocked on a lock for their turn would take
/// the rest, the work it waits for would never run, and the whole test run would stand still until it timed out (every
/// test timed meanwhile failing). A test waiting here holds no thread.
public final class TestTurn: Sendable {
    private struct State {
        var taken = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Locked(initialState: State())
    /// The turns the current task holds (in `run`'s body).
    @TaskLocal private static var held: Set<ObjectIdentifier> = []

    public init() {}

    /// Whether the current task holds the turn: it is in `run`'s body.
    public var isHeld: Bool { Self.held.contains(ObjectIdentifier(self)) }

    /// `body` once it is this test's turn (at once where it already holds it), then the turn goes to the next, in the
    /// order they came.
    public func run<T>(_ body: () throws -> T) async rethrows -> T {
        if isHeld { return try body() }
        await take()
        defer { pass() }
        return try Self.$held.withValue(Self.held.union([ObjectIdentifier(self)]), operation: body)
    }

    private func take() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let free = state.withLock { state -> Bool in
                guard state.taken else {
                    state.taken = true
                    return true
                }
                state.waiting.append(continuation)
                return false
            }
            if free { continuation.resume() }
        }
    }

    private func pass() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiting.isEmpty else {
                state.taken = false
                return nil
            }
            return state.waiting.removeFirst()
        }
        next?.resume()
    }
}
