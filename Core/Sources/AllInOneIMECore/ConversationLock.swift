import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// An exclusive lock on one agent conversation of a question session (`flock` on `ClaudeSessionStore.lockFile`), so that
/// two processes never write the same conversation: the input method holds it while a process of its own is on the
/// conversation (`ClaudeSessionManager`), the hand-off's Terminal while the CLI it started runs (`lockf`:
/// `ClaudeSessionManager.terminalCommand`). Let go by `release`, or when the process holding it ends. Where there is no
/// `flock` (Windows), or the file can't be made, every lock is had.
public final class ConversationLock: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// The lock on `url` (made, with its folder, when missing), had now; nil while another holds it. Its descriptor is
    /// closed on exec: no program the input method starts inherits it.
    public static func take(_ url: URL) -> ConversationLock? {
        #if canImport(Darwin) || canImport(Glibc)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return ConversationLock(descriptor: -1) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return ConversationLock(descriptor: descriptor)
        #else
        return ConversationLock(descriptor: -1)
        #endif
    }

    /// Lets go of it (once).
    public func release() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            #if canImport(Darwin) || canImport(Glibc)
            close(descriptor)
            #endif
            descriptor = -1
        }
    }

    deinit { release() }

    /// The lock files in `folder` but `keeping`'s that no one holds, removed (one per conversation, left by a hand-off's
    /// `lockf -k`).
    static func prune(_ folder: URL, keeping: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "lock" && file.lastPathComponent != keeping.lastPathComponent {
            guard let held = take(file) else { continue }
            try? FileManager.default.removeItem(at: file)
            held.release()
        }
    }
}

/// The conversation locks one manager holds (`ClaudeSessionManager`): each while a process of its own is on the
/// conversation, taken by the first and let go once the last has ended, so that a process started again on the same
/// conversation before the one before it has ended shares its lock. One held by another process (the hand-off's Terminal,
/// another input method's) isn't had: ours starts without it (the hand-off moved this input method to a new conversation
/// already, `ClaudeSessionManager.handOff`).
final class ConversationLocks: @unchecked Sendable {
    private struct Entry {
        var lock: ConversationLock?
        var holders: Int
    }

    private let entries = Locked<[URL: Entry]>(initialState: [:])

    /// A process of ours is on the conversation whose lock file is `file`, until the hold ends.
    func hold(_ file: URL) -> Hold {
        entries.withLock { entries in
            if var entry = entries[file] {
                entry.holders += 1
                entries[file] = entry
            } else {
                entries[file] = Entry(lock: ConversationLock.take(file), holders: 1)
            }
        }
        return Hold { [weak self] in self?.end(file) }
    }

    private func end(_ file: URL) {
        let released = entries.withLock { entries -> ConversationLock? in
            guard var entry = entries[file] else { return nil }
            entry.holders -= 1
            guard entry.holders <= 0 else {
                entries[file] = entry
                return nil
            }
            entries[file] = nil
            return entry.lock
        }
        released?.release()
    }
}

/// One process's hold on its conversation's lock (`ConversationLocks.hold`): ended once.
final class Hold: @unchecked Sendable {
    private let ended = Locked(initialState: false)
    private let onEnd: @Sendable () -> Void

    init(_ onEnd: @escaping @Sendable () -> Void) {
        self.onEnd = onEnd
    }

    func end() {
        let first = ended.withLock { ended -> Bool in
            defer { ended = true }
            return !ended
        }
        if first { onEnd() }
    }
}

/// A running session process's hold: on the conversation it is on now (moved with it), ended when it ends.
final class HeldLock: @unchecked Sendable {
    private let held = Locked<Hold?>(initialState: nil)

    /// Holds `hold` from now on, the one before ended.
    func hold(_ hold: Hold?) {
        let before = held.withLock { held -> Hold? in
            defer { held = hold }
            return held
        }
        before?.end()
    }

    func release() { hold(nil) }
}
