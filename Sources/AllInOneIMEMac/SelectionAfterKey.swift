import AllInOneIMECore
import Foundation

/// The selection read after the "@" key (`SessionOutput.readSelection`), as the thread that reads it hands it over: what a
/// key that acts on the draft waits for on its own thread (`SessionServices.awaitSelection`), until it lands or the wait's
/// time is up. Neither side needs the other's thread, nor the main one: the answer goes into a box behind a lock, and a
/// semaphore wakes the key waiting for it. One read at a time (a newer one takes the place of the one before); one for
/// each field's session.
public final class SelectionAfterKey: @unchecked Sendable {
    /// The read in flight: its id, whether it landed and what it found, and what wakes a key waiting for it.
    private struct Read {
        let id: Int
        let landed = DispatchSemaphore(value: 0)
        var found: Composer.Selection?
        var isIn = false
    }

    private let lock = NSLock()
    private var read: Read?

    public init() {}

    /// Read `id` started: nothing of the one before counts any more.
    public func started(_ id: Int) {
        lock.withLock { read = Read(id: id) }
    }

    /// Read `id` found `selection` (nil: nothing selected), on the thread that read it: a key waiting for it goes on. One
    /// no longer waited for (given up, or another read started) is dropped.
    public func landed(_ id: Int, _ selection: Composer.Selection?) {
        let waking = lock.withLock { () -> DispatchSemaphore? in
            guard read?.id == id, read?.isIn == false else { return nil }
            read?.found = selection
            read?.isIn = true
            return read?.landed
        }
        waking?.signal()
    }

    /// What read `id` found, waited for on this thread until it lands or `timeout` seconds have gone by: nil if it found
    /// nothing, or didn't land in time; either way it is waited for no more, and what it finds later is dropped.
    public func wait(for id: Int, timeout: TimeInterval) -> Composer.Selection? {
        guard let landed = lock.withLock({ read?.id == id ? read?.landed : nil }) else { return nil }
        let inTime = landed.wait(timeout: .now() + timeout) == .success
        return lock.withLock {
            guard let current = read, current.id == id else { return nil }
            read = nil
            return inTime && current.isIn ? current.found : nil
        }
    }
}
