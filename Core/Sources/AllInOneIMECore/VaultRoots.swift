import Foundation

/// Which folders of Markdown notes are in an Obsidian vault (`MarkdownFolderDestination.vaultRoot`), remembered per
/// folder, so that the main thread never walks a folder tree: on a network volume that went away while still mounted,
/// each `stat` can hang for many seconds, and every text field's switch would freeze the input method.
///
/// - The main thread only reads what is remembered (`cached`), and starts a lookup in the background when there's
///   nothing yet, or what there is is older than `retryAfter`.
/// - Elsewhere (a save, opening a saved file) `lookUp` waits for one, `timeout` at most. One that takes longer is
///   remembered as unknown and not tried again for `retryAfter`; its lookup goes on, and what it finds is kept.
/// - One lookup at a time per folder: each runs in the background, on a queue of its own.
public final class VaultRoots: Sendable {
    public static let shared = VaultRoots()

    /// What is known of a folder: in the vault at that root, in none (`noVault`), or not known (not looked up yet, or
    /// too slow).
    public enum Answer: Equatable, Sendable {
        case vault(URL)
        case noVault
        case unknown

        public var isVault: Bool {
            if case .vault = self { return true }
            return false
        }
    }

    private struct Entry {
        var answer: Answer
        var checked: Date
    }

    private struct State {
        var entries: [String: Entry] = [:]
        /// The lookups running, by folder: waited for, never started twice.
        var running: [String: DispatchGroup] = [:]
    }

    private let state = Locked(initialState: State())
    private let find: @Sendable (URL) -> URL?
    private let now: @Sendable () -> Date
    /// How long a lookup is waited for, and how long an answer (or a lookup too slow) holds before it is asked again.
    public let timeout: TimeInterval
    public let retryAfter: TimeInterval

    public init(timeout: TimeInterval = 1, retryAfter: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Platform.current.clock.now },
                find: @escaping @Sendable (URL) -> URL? = { MarkdownFolderDestination.vaultRoot(of: $0) }) {
        self.timeout = timeout
        self.retryAfter = retryAfter
        self.now = now
        self.find = find
    }

    /// What is remembered of `folder`, never waiting (for the main thread): unknown until a lookup has answered. A
    /// lookup is started in the background when nothing is remembered, or it is older than `retryAfter`.
    public func cached(_ folder: URL) -> Answer {
        let key = Self.key(folder)
        let (answer, start) = state.withLock { state -> (Answer, DispatchGroup?) in
            let entry = state.entries[key]
            guard state.running[key] == nil, entry.map({ now().timeIntervalSince($0.checked) >= retryAfter }) ?? true else {
                return (entry?.answer ?? .unknown, nil)
            }
            return (entry?.answer ?? .unknown, begin(key, in: &state))
        }
        if let start { run(folder, key: key, group: start) }
        return answer
    }

    /// `folder` looked up (not on the main thread: it may wait `timeout`): `fresh`, again even when an answer is
    /// remembered (a save, opening a file: `.obsidian` may have been made since); else a remembered answer younger than
    /// `retryAfter` does. A lookup that was too slow less than `retryAfter` ago is unknown at once; one running is waited
    /// for, not started again.
    public func lookUp(_ folder: URL, fresh: Bool = false) -> Answer {
        let key = Self.key(folder)
        let (remembered, group, started) = state.withLock { state -> (Answer?, DispatchGroup?, Bool) in
            let entry = state.entries[key]
            let young = entry.map { now().timeIntervalSince($0.checked) < retryAfter } ?? false
            if let entry, young, entry.answer == .unknown { return (.unknown, nil, false) }
            if let running = state.running[key] { return (nil, running, false) }
            if let entry, young, !fresh { return (entry.answer, nil, false) }
            return (nil, begin(key, in: &state), true)
        }
        if let remembered { return remembered }
        guard let group else { return .unknown }
        if started { run(folder, key: key, group: group) }
        guard group.wait(timeout: .now() + timeout) == .success else {
            state.withLock { state in
                if state.running[key] != nil { state.entries[key] = Entry(answer: .unknown, checked: now()) }
            }
            return .unknown
        }
        return state.withLock { $0.entries[key]?.answer } ?? .unknown
    }

    /// Forgets every answer (lookups running go on).
    public func forget() {
        state.withLock { $0.entries = [:] }
    }

    private func begin(_ key: String, in state: inout State) -> DispatchGroup {
        let group = DispatchGroup()
        group.enter()
        state.running[key] = group
        return group
    }

    private func run(_ folder: URL, key: String, group: DispatchGroup) {
        let (find, now) = (self.find, self.now)
        // A serial queue of its own, not a shared concurrent one: that waits for a thread of the shared pool, seconds
        // when they are all busy; this one gets a thread at once.
        DispatchQueue(label: "AllInOneIME.VaultRoots", qos: .utility).async { [state] in
            let root = find(folder)
            state.withLock { state in
                state.entries[key] = Entry(answer: root.map(Answer.vault) ?? .noVault, checked: now())
                state.running[key] = nil
            }
            group.leave()
        }
    }

    /// A folder as it is remembered: its path, standardized (nothing looked at on disk).
    static func key(_ folder: URL) -> String { folder.standardizedFileURL.path }
}
