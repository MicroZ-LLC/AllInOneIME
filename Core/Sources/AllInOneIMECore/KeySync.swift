import Foundation

/// API keys and passwords through iCloud Keychain (Settings → General → Sync through iCloud → "API keys and passwords",
/// `ICloudSyncSettings.syncsKeys`). Two stores of `APIKeys.service`'s items: the login keychain (`.legacy`), where keys
/// stay while key sync is off, exactly as in 0.6.4 (and where `APIKeys.neverSynced` always stays), and the items iCloud
/// Keychain syncs (`.synced`), in the data protection keychain. The app reads and writes through one store routed over
/// them (`Keychain.routed`), chosen once at launch (`Stores`); the moves between them are here (`merge`):
///
/// - turning key sync on moves the login keychain's keys into the synced store (deleted from the login keychain once
///   their copies read back; one that would ask for the password moves at its first use, where the login keychain asks
///   anyway), and turning it off copies the synced keys back into the login keychain and leaves the synced ones alone
///   (turning sync off on one Mac never deletes keys on another);
/// - the newest wins, by when each key was saved (`ItemAttributes.saved`, carried by every copy).
///
/// A key that loses to a different one, is about to be written over by one, or moves into a synced store that had none
/// for it (another Mac may be moving a different one there before they see each other) keeps a replaced copy: in the
/// login keychain under a service of its own (`replacedService`), its label ending in " (replaced)", one per account.
/// Routed reads, merges and moves never read it, so it never comes back as the key in use; Remove… deletes it.
///
/// Moves are logged by account, never with the key.
public enum KeySync {
    /// The keychain access group the synced items are in, set on every query: an iOS app or a wrapped command line of
    /// the same team can share it later (the provisioning profile allows the team's `9SR8N3UD5Y.*`).
    public static let accessGroup = "9SR8N3UD5Y.com.aipinyin.shared"

    /// The service of the replaced copies (`Stores.replaced`, in the login keychain): a key that lost to a different
    /// one, that a newer one was written over, or that moved into a synced store that had none for it. Only a safety copy,
    /// one per account (a later one replaces it): routed reads, merges and moves never read it; Remove… deletes it.
    public static let replacedService = "AllInOneIME replaced API key"

    /// What a replaced copy's label ends with, after the label of the key it copies ("AllInOneIME: Gemini API (replaced)"),
    /// so that Keychain Access tells it from the key in use.
    public static let replacedLabelSuffix = " (replaced)"

    /// What a move did, by account.
    public struct Moves: Equatable, Sendable {
        /// Copied into the other store (and, from the login keychain, deleted there).
        public var moved: [String] = []
        /// Read nothing while asking was off (the login keychain would ask for the password): moved at its first use.
        public var waiting: [String] = []
        /// The other store's was newer (another Mac synced it first): this one was kept as a replaced copy when its key
        /// differs (or kept where it was when it couldn't be read without asking), deleted when it is the same key.
        public var superseded: [String] = []
        /// A replaced copy kept (`replacedService`).
        public var setAside: [String] = []
        /// Left as it was, to be tried again: the copy didn't read back as written (the original was kept, and the copy
        /// taken out unless it replaced an item already there), a replaced copy couldn't be kept, or the other store's
        /// item for it couldn't be read (its key not there yet, say).
        public var mismatched: [String] = []

        public init() {}

        /// Nothing left to try again: every item was moved or was already there.
        public var isComplete: Bool { waiting.isEmpty && mismatched.isEmpty }

        /// The accounts left to try again (`waiting` and `mismatched`), by name: what a retry of an incomplete copy-back
        /// handles alone (`merge(only:)`).
        public var remaining: [String] { Array(Set(waiting + mismatched)).sorted() }
    }

    /// The newest wins: `a` over `b` only when its key was set later, by when it was saved (`ItemAttributes.saved`, which
    /// copies carry), else by when its item was last changed; an item that says neither loses. A time later than a day
    /// from `now` counts as the oldest: a Mac whose clock was set far ahead doesn't win every merge after.
    static func newer(_ a: APIKeys.ItemAttributes, than b: APIKeys.ItemAttributes, now: Date = Date()) -> Bool {
        let latest = now.addingTimeInterval(clockSkew)
        func when(_ item: APIKeys.ItemAttributes) -> Date {
            let changed = item.changed ?? .distantPast
            return changed > latest ? .distantPast : changed
        }
        return when(a) > when(b)
    }

    /// How far ahead of now a save time may be before it counts as the oldest (`newer`).
    static let clockSkew: TimeInterval = 24 * 60 * 60

    /// Every item of `from` into `into`, the newest winning account by account (`APIKeys.neverSynced` left out). Turning
    /// key sync on is `merge(from: login, into: synced)`, turning it off `merge(from: synced, into: login)`. The items
    /// of `from` are deleted once their copies read back, except synced ones: a merge never deletes a synced item.
    ///
    /// Replaced copies (`aside`, the store of `replacedService`): one of `from`'s that loses to a different key is kept
    /// there, then deleted where it was (deleted when it's the same key, unless it leaves for a synced store);
    /// `into`'s different key is kept there before a newer one is written over it; and a key that moves into a synced
    /// store that had no item for it (or had the same key: an earlier attempt's) is kept there too, before it is deleted
    /// where it was. An account is left as it is and tried again (`mismatched`) when such a copy can't be kept,
    /// or when `into` has an item for it whose key can't be read: it is never written over unseen. One of `from`'s that
    /// can't be read without asking waits (`waiting`; it loses quietly when `into`'s is newer). A write that fails
    /// throws (`APIKeys.KeychainError`), what was moved before it staying moved; so does a `from` whose items can't be
    /// listed (`Keychain.listedAccounts`), which is never taken for an empty one.
    ///
    /// A key is never kept aside over its own replaced copy (the only one left of a key that lost, say): the same key
    /// isn't kept again when `aside` already has a copy for the account, except when it moves into a synced store that
    /// had none. A move into a store that had no item for the account only adds (`APIKeys.Keychain.adding`): an item
    /// that arrived meanwhile is never written over, and the account is tried again (`mismatched`).
    ///
    /// `only`: these accounts alone (an incomplete copy-back tried again: the accounts it left); nil, every one.
    @discardableResult
    public static func merge(from: APIKeys.Keychain, into: APIKeys.Keychain, aside: APIKeys.Keychain,
                             only: Set<String>? = nil) throws -> Moves {
        var moves = Moves()
        let keepsFrom = from.kind == .synced
        for account in try from.listedAccounts() where !APIKeys.neverSynced.contains(account) && only?.contains(account) != false {
            guard let theirs = from.attributes(account) else { continue }
            let ours = into.attributes(account)
            let wins = ours.map { newer(theirs, than: $0) } ?? true
            var current: String?
            if ours != nil, wins || !keepsFrom {  // (a synced item that loses changes nothing: nothing to compare)
                guard let key = into.read(account), !key.isEmpty else {
                    APIKeys.log.error("key not moved: \(account): the item it would meet can't be read; tried again later")
                    moves.mismatched.append(account)
                    continue
                }
                current = key
            }
            if !wins {
                if !keepsFrom, let key = from.read(account), !key.isEmpty {
                    if key == current, into.kind != .synced || aside.attributes(account) != nil {
                        _ = from.delete(account)  // the same key twice (and kept aside already, if it leaves for a synced store)
                    } else if setAside(account, key: key, attributes: theirs, in: aside) {
                        _ = from.delete(account)
                        moves.setAside.append(account)
                    } else {
                        moves.mismatched.append(account)
                    }
                }
                moves.superseded.append(account)
                continue
            }
            guard let key = from.read(account), !key.isEmpty else {
                moves.waiting.append(account)
                continue
            }
            if let ours, let current, current != key {
                // Written over: `into`'s kept first.
                guard setAside(account, key: current, attributes: ours, in: aside) else {
                    moves.mismatched.append(account)
                    continue
                }
                moves.setAside.append(account)
            } else if !keepsFrom, into.kind == .synced, ours == nil || aside.attributes(account) == nil {
                // Into a synced store that had none (or the same key, an earlier attempt's, unless that kept it aside
                // already): another Mac may be moving a different key there unseen.
                guard setAside(account, key: key, attributes: theirs, in: aside) else {
                    moves.mismatched.append(account)
                    continue
                }
                moves.setAside.append(account)
            }
            switch try copy(account, key: key, attributes: theirs, into: into, hadOne: ours != nil) {
            case .copied:
                if !keepsFrom {
                    let deleted = from.delete(account)
                    if deleted != .ok && deleted != .notFound {
                        APIKeys.log.error("key moved but not deleted where it was: \(account) (\(deleted.code))")
                    }
                }
                moves.moved.append(account)
            case .mismatched, .taken:
                moves.mismatched.append(account)
            }
        }
        if !moves.moved.isEmpty || !moves.waiting.isEmpty || !moves.mismatched.isEmpty || !moves.setAside.isEmpty {
            APIKeys.log.notice("keys merged from \(String(describing: from.kind)) into \(String(describing: into.kind)): \(moves.moved.joined(separator: ", ")) moved; waiting for their first use (they ask for the password): \(moves.waiting.joined(separator: ", ")); \(moves.superseded.count) newer there already, \(moves.setAside.count) replaced copies kept, \(moves.mismatched.count) tried again later")
        }
        return moves
    }

    /// How a copy went: it read back as written; it didn't (`mismatched`); or an item arrived meanwhile in the store
    /// that had none, and was left as it was (`taken`).
    enum Copy { case copied, mismatched, taken }

    /// `key` of `account` kept in `aside` (the store of `replacedService`) with its attributes, its label ending in
    /// `replacedLabelSuffix`, and read back: true when it reads back as written (the original may then go, or be written
    /// over). Logged by account.
    static func setAside(_ account: String, key: String, attributes: APIKeys.ItemAttributes, in aside: APIKeys.Keychain) -> Bool {
        let label = attributes.label ?? APIKeys.label(account: account)
        let status = aside.write(account, key, label.hasSuffix(replacedLabelSuffix) ? label : label + replacedLabelSuffix,
                                 attributes.comment ?? "", attributes.ending ?? APIKeys.ending(of: key), attributes.changed)
        guard status == .ok, aside.read(account) == key else {
            APIKeys.log.error("replaced copy not kept: \(account) (\(status.code)); the key stays where it was")
            return false
        }
        APIKeys.log.notice("replaced copy kept: \(account)")
        return true
    }

    /// `key` under `account` into `store` with the attributes it had (label, comment: the host, ending, and when it was
    /// saved: its save time, else its modification date), then read back. Into a store that had no item for `account`
    /// (`hadOne` false) it is only added: one that arrived meanwhile (another Mac's) is left as it is (`taken`). A copy
    /// that reads back otherwise is taken out of `store` again, but only when it had no item for `account` before (one
    /// that was there, another Mac's, is kept); the original is kept, and it is logged. A write that fails throws.
    static func copy(_ account: String, key: String, attributes: APIKeys.ItemAttributes, into store: APIKeys.Keychain,
                     hadOne: Bool) throws -> Copy {
        let label = attributes.label ?? APIKeys.label(account: account), comment = attributes.comment ?? ""
        let ending = attributes.ending ?? APIKeys.ending(of: key)
        let status = hadOne ? store.write(account, key, label, comment, ending, attributes.changed)
            : store.adding(account, key, label, comment, ending, attributes.changed)
        if !hadOne, status == .failed(APIKeys.Keychain.duplicateItem) {
            APIKeys.log.notice("key not moved: \(account): an item arrived there meanwhile; compared at the next merge")
            return .taken
        }
        guard status == .ok else {
            APIKeys.log.error("key not moved: \(account) (\(status.code))")
            throw APIKeys.KeychainError(status: status.code, message: store.message(status.code))
        }
        guard store.read(account) == key else {
            if hadOne {
                APIKeys.log.error("key not moved: \(account): its copy doesn't read back as written; the original is kept, and the item that was there")
            } else {
                APIKeys.log.error("key not moved: \(account): its copy doesn't read back as written; the original is kept")
                _ = store.delete(account)
            }
            return .mismatched
        }
        return .copied
    }

    // MARK: - The keys-synced marker

    /// What the keys-synced marker says (a file beside the sync record, `url(besides:)`; absent: this Mac's keys were
    /// last all in the login keychain). Account names only, never a key.
    public enum Marker: Equatable, Sendable {
        /// Turning key sync on is moving the keys into iCloud Keychain (or stopped before it was done).
        case moving
        /// Every key moved: they may be in iCloud Keychain alone.
        case done
        /// Turning key sync off is copying the synced keys back, and these are still to copy: written with every synced
        /// account before the copy-back starts (`Stores.copyBackList`), then with the ones it left. A retry copies these
        /// alone, and Remove… or a save on this Mac (key sync off) takes one off.
        case copyingBack([String])

        static let copyingBackLine = "copying back"

        /// The marker's text as written ("moving", "done", or "copying back" and an account per line); an earlier
        /// build's (empty, or anything else) is `done`.
        public init(text: String) {
            let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            switch lines.first {
            case "moving": self = .moving
            case Self.copyingBackLine: self = .copyingBack(Array(Set(lines.dropFirst())).sorted())
            default: self = .done
            }
        }

        public var text: String {
            switch self {
            case .moving: return "moving"
            case .done: return "done"
            case let .copyingBack(accounts): return ([Self.copyingBackLine] + accounts).joined(separator: "\n") + "\n"
            }
        }

        /// Whether this Mac's keys may be in iCloud Keychain while key sync is on (`moving`, `done`): the routing to keep
        /// when the config can't be read at launch.
        public var syncing: Bool {
            if case .copyingBack = self { return false }
            return true
        }

        /// The marker beside the sync record at `stateURL` (`ICloudSync.State.defaultURL` on the Mac).
        public static func url(besides stateURL: URL) -> URL {
            stateURL.deletingLastPathComponent().appendingPathComponent("keys-synced")
        }

        /// The marker at `url`; nil when there is none.
        public static func read(at url: URL) -> Marker? {
            FileManager.default.contents(atPath: url.path).map { Marker(text: String(decoding: $0, as: UTF8.self)) }
        }
    }

    // MARK: - The stores in use

    /// The stores of a build entitled to the data protection keychain (the Mac's: `KeySync.system`), and the switch the
    /// routed one follows. The switch is set at launch as the config has it (`start`); `turn` moves the keys when it
    /// changes. Tests and the self-test make their own of in-memory stores.
    public final class Stores: Sendable {
        /// The items iCloud Keychain syncs.
        public let synced: APIKeys.Keychain
        /// The login keychain: the keys while key sync is off, and `APIKeys.neverSynced` always.
        public let login: APIKeys.Keychain
        /// The replaced copies (`KeySync.replacedService`, in the login keychain): never read to be used, deleted by
        /// Remove….
        public let replaced: APIKeys.Keychain
        /// The login keychain and its replaced copies with asking turned off, for the moves (`turn`): a key that would
        /// ask for the password moves at its first use instead.
        let quietLogin: APIKeys.Keychain
        let quietReplaced: APIKeys.Keychain
        private let on: Locked<Bool>
        private let removedHere = Locked<(@Sendable (String) -> Void)?>(initialState: nil)

        public init(login: APIKeys.Keychain, synced: APIKeys.Keychain, replaced: APIKeys.Keychain,
                    quietLogin: APIKeys.Keychain? = nil, quietReplaced: APIKeys.Keychain? = nil, syncing: Bool = false) {
            self.login = login
            self.synced = synced
            self.replaced = replaced
            self.quietLogin = quietLogin ?? login
            self.quietReplaced = quietReplaced ?? replaced
            on = Locked(initialState: syncing)
        }

        /// Whether the routed store syncs keys now.
        public var syncing: Bool { on.withLock { $0 } }

        /// The store `APIKeys` uses (`Platform.secrets`): routed over the login keychain and the synced items, following
        /// the switch.
        public var store: APIKeys.Keychain {
            let on = self.on, removedHere = self.removedHere
            return .routed(login: login, synced: synced, replaced: replaced, syncs: { on.withLock { $0 } },
                           removedHere: { account in removedHere.withLock { $0 }?(account) })
        }

        /// Told of each account Remove… removed, or a save wrote, on this Mac while key sync was off (`routed`'s
        /// `removedHere`): the sync controller takes it off the accounts a copy-back still has to copy, so that the key
        /// removed isn't copied back again, nor the one saved here written over by iCloud Keychain's.
        public func whenRemovedHere(_ handler: (@Sendable (String) -> Void)?) {
            removedHere.withLock { $0 = handler }
        }

        /// What a copy-back starting from `moving` or `done` has to copy, written into the marker before it starts
        /// (`Marker.copyingBack`): every account the synced store lists, `APIKeys.neverSynced` left out. Account names
        /// only, no key read. None when the synced store can't be listed: the controller uses `listCopyBack`, which
        /// says so.
        public func copyBackList() -> [String] {
            (try? listCopyBack()) ?? []
        }

        /// `copyBackList`, throwing (`APIKeys.KeychainError`) when the synced store can't be listed: the copy-back
        /// doesn't start then, rather than count an empty list as copied.
        public func listCopyBack() throws -> [String] {
            try synced.listedAccounts().filter { !APIKeys.neverSynced.contains($0) }
        }

        /// The switch as the config has it, nothing moved: at launch, before anything reads a key.
        public func start(syncing: Bool) {
            on.withLock { $0 = syncing }
        }

        /// The switch changed (turned on: the login keychain's keys move into iCloud Keychain; off: the synced ones are
        /// copied back into the login keychain); the routed store follows it even when a move fails (the error is thrown,
        /// to be tried again). Turned on, it follows first (reads try the synced store, then the login keychain, so a key
        /// is found while it moves); turned off, once the synced keys are copied back (until then reads still find them).
        ///
        /// `only` (turned off): the copy-back of these accounts alone, the ones an incomplete one left (`Moves.remaining`).
        @discardableResult
        public func turn(syncing: Bool, only: Set<String>? = nil) throws -> Moves {
            if syncing {
                on.withLock { $0 = true }
                return try KeySync.merge(from: quietLogin, into: synced, aside: quietReplaced)
            }
            defer { on.withLock { $0 = false } }
            return try KeySync.merge(from: synced, into: quietLogin, aside: quietReplaced, only: only)
        }
    }

    /// The stores this build uses: the data protection keychain's synced items and the login keychain when the process
    /// is entitled to the access group (an app signed with the provisioning profile), else nil and the login keychain
    /// alone (`Platform.systemSecrets`), as in development and ad-hoc builds. Chosen once, at launch; never by an error at
    /// run time. The Mac only: elsewhere (iOS) there is no login keychain apart from the data protection one; a shell
    /// there brings its stores itself.
    public static var system: Stores? {
        #if os(macOS)
        return appleStores
        #else
        return nil
        #endif
    }
}

extension APIKeys {
    /// The label an item gets when the one it moves from had none.
    static func label(account: String) -> String {
        Provider(rawValue: account).map { "AllInOneIME: \($0.displayName)" } ?? "AllInOneIME: \(account)"
    }
}

extension APIKeys.Keychain {
    /// The store the app uses where the data protection keychain is there (`KeySync.Stores.store`), over the login
    /// keychain (`login`) and the synced items:
    /// - while `syncs()` is false, everything is the login keychain's, exactly as in 0.6.4: reads, writes and Remove…
    ///   never touch the synced store (its items stay for the other Macs);
    /// - while `syncs()`, reads try the synced store, then the login keychain; a key found only in the login keychain
    ///   (one the move left: it asks for the password) moves into the synced store at its first use (a replaced copy
    ///   kept first, label, comment, ending and save time kept) and is deleted from the login keychain once it reads back;
    ///   writes go to the synced store, except `APIKeys.neverSynced`, which stays in the login keychain (a write that
    ///   fails is the error, with no other store tried);
    /// - `delete` removes the login keychain's copy first (stopping there when that fails), then the replaced copy
    ///   (`replaced`, `replacedService`), and the synced one only while `syncs()`: Remove… on a Mac that doesn't sync
    ///   keys removes them from this Mac alone, never from the others (and tells `removedHere`, once the copies here are
    ///   gone); a save while `syncs()` is false tells `removedHere` too, once it is written.
    ///
    /// `replaced` is never read: a replaced copy is a safety copy, never the key in use. `syncs` is asked on every call:
    /// the switch can change while the store, chosen at launch, stays.
    public static func routed(login: Self, synced: Self, replaced: Self, syncs: @escaping @Sendable () -> Bool,
                              removedHere: @escaping @Sendable (String) -> Void = { _ in }) -> Self {
        @Sendable func syncing(_ account: String) -> Bool { syncs() && !APIKeys.neverSynced.contains(account) }
        /// The store that holds `account`'s item, in the order reads try them, and its attributes.
        @Sendable func holder(_ account: String) -> (store: Self, attributes: APIKeys.ItemAttributes, login: Bool)? {
            if syncing(account), let found = synced.attributes(account) { return (synced, found, false) }
            return login.attributes(account).map { (login, $0, true) }
        }
        return Self(
            kind: .synced,
            accounts: { syncs() ? Array(Set(synced.accounts() + login.accounts())).sorted() : login.accounts() },
            attributes: { holder($0)?.attributes },
            read: { account in
                guard let found = holder(account), let key = found.store.read(account) else { return nil }
                guard found.login, syncing(account), !key.isEmpty else { return key }
                // Left in the login keychain when key sync was turned on (it asks for the password): moved at its first
                // use, into a synced store that has no item for it (or the holder would have been that store). The read
                // may have waited for the password a long while: an item that arrived in the synced store meanwhile
                // (another Mac's) is never written over, but left to the next merge to compare; and the copy only adds.
                guard synced.attributes(account) == nil else { return key }
                guard KeySync.setAside(account, key: key, attributes: found.attributes, in: replaced) else { return key }
                if (try? KeySync.copy(account, key: key, attributes: found.attributes, into: synced, hadOne: false)) == .copied {
                    _ = login.delete(account)
                    APIKeys.log.notice("key moved from the login keychain at its first use: \(account)")
                }
                return key
            },
            write: { account, key, label, comment, ending, saved in
                guard syncs() else {
                    // Saved on this Mac while key sync is off: a copy-back still to make doesn't write over it.
                    let status = login.write(account, key, label, comment, ending, saved)
                    if status == .ok { removedHere(account) }
                    return status
                }
                return (syncing(account) ? synced : login).write(account, key, label, comment, ending, saved)
            },
            setComment: { account, comment in holder(account)?.store.setComment(account, comment) ?? .notFound },
            delete: { account in
                // The login keychain's first: a removal it refuses (the password asked for, and cancelled) stops there,
                // so that no copy left in it comes back at its next use, moved anew.
                let first = login.delete(account)
                guard first == .ok || first == .notFound else { return first }
                let everywhere = syncs()
                let statuses = [first] + (everywhere ? [replaced, synced] : [replaced]).map { $0.delete(account) }
                if let failure = statuses.first(where: { $0 != .ok && $0 != .notFound }) { return failure }
                if !everywhere { removedHere(account) }
                return statuses.contains(.ok) ? .ok : .notFound
            },
            message: { code in (syncs() ? synced.message(code) : nil) ?? login.message(code) })
    }
}
