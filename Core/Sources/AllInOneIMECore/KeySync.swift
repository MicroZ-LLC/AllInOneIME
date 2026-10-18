import Foundation

/// API keys and passwords through iCloud Keychain (Settings → General → Sync through iCloud → "API keys and passwords",
/// `ICloudSyncSettings.syncsKeys`). Three stores of `APIKeys.service`'s items: this device's own (`.local`), the ones iCloud
/// Keychain syncs (`.synced`), both in the data protection keychain, and the login keychain where 0.6.4 kept them
/// (`.legacy`). The app reads and writes through one store routed over the three (`Keychain.routed`), chosen once at
/// launch (`Stores`); the moves between them are here:
///
/// - turning sync on moves this device's items into the synced ones and turning it off copies the synced ones into this
///   device's (`merge`): the newest wins, by when each key was saved (`ItemAttributes.saved`, carried by every copy), and
///   the synced items are never deleted by it (turning sync off on one Mac never deletes keys on another); a key that
///   loses to a different one is kept where it was, never deleted;
/// - the keys of the login keychain move once (`migrate`): a silent pass at launch, and an item that would ask for the
///   password at its first use (`Keychain.routed`'s read), where the login keychain asks anyway.
///
/// `APIKeys.neverSynced` (the AllInOneIME Cloud sign-in) stays on this device whatever the switch. Moves are logged by
/// account, never with the key.
public enum KeySync {
    /// The keychain access group every item is in, set on every query: an iOS app or a wrapped command line of the same
    /// team can share it later (the provisioning profile allows the team's `9SR8N3UD5Y.*`).
    public static let accessGroup = "9SR8N3UD5Y.com.aipinyin.shared"

    /// What a move did, by account.
    public struct Moves: Equatable, Sendable {
        /// Copied into the other store (and, from the login keychain or this device's store, deleted there).
        public var moved: [String] = []
        /// Read nothing while asking was off (the login keychain would ask for the password): moved at its first use.
        public var waiting: [String] = []
        /// The other store's was newer (another Mac synced it first): this one was kept where it was when its key
        /// differs (reads find the newer one first; Remove… takes it too), deleted when it is the same key.
        public var superseded: [String] = []
        /// The copy didn't read back as written: the original was kept, and the copy taken out (unless it replaced an
        /// item already there, which is kept).
        public var mismatched: [String] = []

        public init() {}

        /// Nothing left to try again: every item was moved or was already there.
        public var isComplete: Bool { waiting.isEmpty && mismatched.isEmpty }
    }

    /// The newest wins: `a` over `b` only when its key was set later, by when it was saved (`ItemAttributes.saved`, which
    /// copies carry), else by when its item was last changed; an item that says neither loses. A time later than a day
    /// from `now` counts as `now`: a Mac whose clock was set far ahead doesn't win every merge after.
    static func newer(_ a: APIKeys.ItemAttributes, than b: APIKeys.ItemAttributes, now: Date = Date()) -> Bool {
        let latest = now.addingTimeInterval(clockSkew)
        func when(_ item: APIKeys.ItemAttributes) -> Date {
            let changed = item.changed ?? .distantPast
            return changed > latest ? now : changed
        }
        return when(a) > when(b)
    }

    /// How far ahead of now a save time may be before it counts as now (`newer`).
    static let clockSkew: TimeInterval = 24 * 60 * 60

    /// Every item of `from` into `into`, the newest winning account by account (`APIKeys.neverSynced` left out). Turning
    /// sync on is `merge(from: local, into: synced)`, turning it off `merge(from: synced, into: local)`. The items of `from`
    /// are deleted once copied, except synced ones: a merge never deletes a synced item. One that loses to `into`'s is
    /// kept where it was when its key differs (never lost on a guess of which is newer), deleted when it's the same. A
    /// write that fails throws (`APIKeys.KeychainError`), what was moved before it staying moved.
    @discardableResult
    public static func merge(from: APIKeys.Keychain, into: APIKeys.Keychain) throws -> Moves {
        var moves = Moves()
        let keepsFrom = from.kind == .synced
        for account in from.accounts() where !APIKeys.neverSynced.contains(account) {
            guard let theirs = from.attributes(account) else { continue }
            if let ours = into.attributes(account), !newer(theirs, than: ours) {
                if !keepsFrom, let key = from.read(account), !key.isEmpty, key == into.read(account) {
                    _ = from.delete(account)  // the same key twice
                }
                moves.superseded.append(account)
                continue
            }
            guard let key = from.read(account), !key.isEmpty else {
                moves.waiting.append(account)
                continue
            }
            switch try copy(account, key: key, attributes: theirs, into: into) {
            case .copied:
                if !keepsFrom { _ = from.delete(account) }
                moves.moved.append(account)
            case .mismatched:
                moves.mismatched.append(account)
            }
        }
        if !moves.moved.isEmpty || !moves.mismatched.isEmpty {
            APIKeys.log.notice("keys merged from \(String(describing: from.kind)) into \(String(describing: into.kind)): \(moves.moved.joined(separator: ", ")) moved, \(moves.superseded.count) kept as they were, \(moves.mismatched.count) not moved")
        }
        return moves
    }

    /// The silent pass at launch: each item of the login keychain (`legacy`) copied into the new store (`into`, the routed
    /// store with nothing behind it: never the login keychain itself), read back, and deleted from the login keychain only
    /// when the copy reads back as written. A newer copy already there (another Mac synced it first) wins; the login
    /// keychain's is then kept when its key differs (or can't be read without asking), deleted when it's the same. With
    /// `interactive` false the caller has turned asking off: an item whose read gives nothing would ask for the password,
    /// and waits for its first use (`waiting`). A write that fails throws.
    @discardableResult
    public static func migrate(legacy: APIKeys.Keychain, into: APIKeys.Keychain, interactive: Bool) throws -> Moves {
        var moves = Moves()
        for account in legacy.accounts() {
            guard let old = legacy.attributes(account) else { continue }
            if let new = into.attributes(account), !newer(old, than: new) {
                if let key = legacy.read(account), !key.isEmpty, key == into.read(account) {
                    _ = legacy.delete(account)  // the same key twice
                }
                moves.superseded.append(account)
                continue
            }
            guard let key = legacy.read(account), !key.isEmpty else {
                moves.waiting.append(account)
                continue
            }
            switch try copy(account, key: key, attributes: old, into: into) {
            case .copied:
                let deleted = legacy.delete(account)
                if deleted != .ok && deleted != .notFound {
                    APIKeys.log.error("key moved but not deleted from the login keychain: \(account) (\(deleted.code))")
                }
                moves.moved.append(account)
            case .mismatched:
                moves.mismatched.append(account)
            }
        }
        if !moves.moved.isEmpty || !moves.waiting.isEmpty || !moves.mismatched.isEmpty {
            APIKeys.log.notice("keys moved from the login keychain: \(moves.moved.joined(separator: ", ")); waiting for their first use\(interactive ? "" : " (they ask for the password)"): \(moves.waiting.joined(separator: ", ")); \(moves.superseded.count) newer already; \(moves.mismatched.count) not moved")
        }
        return moves
    }

    enum Copy { case copied, mismatched }

    /// `key` under `account` into `store` with the attributes it had (label, comment: the host, ending, and when it was
    /// saved: its save time, else its modification date), then read back. Through a routed store, all of it is done in
    /// the one store the write goes to (`Keychain.target`). A copy that reads back otherwise is taken out of that store
    /// again, but only when the store had no item for `account` before (one that was there, another Mac's, is kept); the
    /// original is kept, and it is logged. A write that fails throws.
    static func copy(_ account: String, key: String, attributes: APIKeys.ItemAttributes,
                     into store: APIKeys.Keychain) throws -> Copy {
        let target = store.target?(account) ?? store
        let hadOne = target.attributes(account) != nil
        let status = target.write(account, key, attributes.label ?? APIKeys.label(account: account), attributes.comment ?? "",
                                  attributes.ending ?? APIKeys.ending(of: key), attributes.changed)
        guard status == .ok else {
            APIKeys.log.error("key not moved: \(account) (\(status.code))")
            throw APIKeys.KeychainError(status: status.code, message: target.message(status.code))
        }
        guard target.read(account) == key else {
            if hadOne {
                APIKeys.log.error("key not moved: \(account): its copy doesn't read back as written; the original is kept, and the item that was there")
            } else {
                APIKeys.log.error("key not moved: \(account): its copy doesn't read back as written; the original is kept")
                _ = target.delete(account)
            }
            return .mismatched
        }
        return .copied
    }

    // MARK: - The stores in use

    /// The three stores of a build entitled to the data protection keychain (the Mac's: `KeySync.system`), and the switch
    /// the routed one follows. The switch is set at launch as the config has it (`start`); `turn` moves the keys when it
    /// changes. Tests and the self-test make their own of in-memory stores.
    public final class Stores: Sendable {
        public let local: APIKeys.Keychain
        public let synced: APIKeys.Keychain
        public let legacy: APIKeys.Keychain
        /// The login keychain with asking turned off, for the silent pass (`migrate()`).
        let quietLegacy: APIKeys.Keychain
        private let on: Locked<Bool>

        public init(local: APIKeys.Keychain, synced: APIKeys.Keychain, legacy: APIKeys.Keychain,
                    quietLegacy: APIKeys.Keychain? = nil, syncing: Bool = false) {
            self.local = local
            self.synced = synced
            self.legacy = legacy
            self.quietLegacy = quietLegacy ?? legacy
            on = Locked(initialState: syncing)
        }

        /// Whether the routed store syncs keys now.
        public var syncing: Bool { on.withLock { $0 } }

        /// The store `APIKeys` uses (`Platform.secrets`): routed over the three, following the switch.
        public var store: APIKeys.Keychain {
            let on = self.on
            return .routed(local: local, synced: synced, legacy: legacy, syncs: { on.withLock { $0 } })
        }

        /// The store the login keychain's items move into: the routed one with nothing behind it.
        var newStore: APIKeys.Keychain {
            let on = self.on
            return .routed(local: local, synced: synced, legacy: .unavailable, syncs: { on.withLock { $0 } })
        }

        /// The switch as the config has it, nothing moved: at launch, before anything reads a key.
        public func start(syncing: Bool) {
            on.withLock { $0 = syncing }
        }

        /// The switch changed (turned on: this device's keys go to iCloud Keychain; off: the synced ones are copied here);
        /// the routed store follows it even when a move fails (the error is thrown, to be tried again). Turned on, it
        /// follows first (reads try the synced store, then this device's, so a key is found while it moves); turned off,
        /// once the synced keys are copied here (until then reads still find them there).
        @discardableResult
        public func turn(syncing: Bool) throws -> Moves {
            if syncing {
                on.withLock { $0 = true }
                return try KeySync.merge(from: local, into: synced)
            }
            defer { on.withLock { $0 = false } }
            return try KeySync.merge(from: synced, into: local)
        }

        /// The silent pass at launch (`KeySync.migrate`), asking turned off.
        @discardableResult
        public func migrate() throws -> Moves {
            try KeySync.migrate(legacy: quietLegacy, into: newStore, interactive: false)
        }
    }

    /// The stores this build uses: the data protection keychain's when the process is entitled to its access group (an
    /// app signed with the provisioning profile), else nil and the login keychain alone (`Platform.systemSecrets`), as in
    /// development and ad-hoc builds. Chosen once, at launch; never by an error at run time. The Mac only: elsewhere
    /// (iOS) there is no login keychain apart from the data protection one, so the moves out of it would take this
    /// device's own items; a shell there brings its stores itself.
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
    /// The store the app uses where the data protection keychain is there (`KeySync.Stores.store`), over three:
    /// - reads try the synced store (while `syncs()`), then `local`, then `legacy`; a key found only in `legacy` is copied
    ///   into the store writes go to (label, comment, ending and save time kept) and deleted there once it reads back:
    ///   the login keychain is read once, at the key's first use (and asks for the password there, as it did);
    /// - writes go to `synced` while `syncs()`, except `APIKeys.neverSynced`, and to `local` otherwise, never anywhere
    ///   else (a write that fails is the error, with no other store tried);
    /// - `delete` removes the legacy copy first (stopping there when that fails), then the local one, and the synced one
    ///   only while `syncs()`: Remove… on a Mac that doesn't sync keys removes them from this Mac alone, never from the
    ///   others (iCloud Keychain brings the key back if sync is turned on again).
    ///
    /// `syncs` is asked on every call: the switch can change while the store, chosen at launch, stays.
    public static func routed(local: Self, synced: Self, legacy: Self, syncs: @escaping @Sendable () -> Bool) -> Self {
        @Sendable func syncing(_ account: String) -> Bool { syncs() && !APIKeys.neverSynced.contains(account) }
        /// The store that holds `account`'s item, in the order reads try them, and its attributes.
        @Sendable func holder(_ account: String) -> (store: Self, attributes: APIKeys.ItemAttributes, legacy: Bool)? {
            for store in syncing(account) ? [synced, local] : [local] {
                if let found = store.attributes(account) { return (store, found, false) }
            }
            return legacy.attributes(account).map { (legacy, $0, true) }
        }
        @Sendable func target(_ account: String) -> Self { syncing(account) ? synced : local }
        var store = Self(
            kind: .synced,
            accounts: { Array(Set((syncs() ? synced.accounts() : []) + local.accounts() + legacy.accounts())).sorted() },
            attributes: { holder($0)?.attributes },
            read: { account in
                guard let found = holder(account), let key = found.store.read(account) else { return nil }
                guard found.legacy, !key.isEmpty else { return key }
                // Its first use since the update: moved out of the login keychain (into a store that has no item for it,
                // or the holder would have been that store).
                let moved = (try? KeySync.copy(account, key: key, attributes: found.attributes, into: target(account)))
                if moved == .copied {
                    _ = legacy.delete(account)
                    APIKeys.log.notice("key moved from the login keychain at its first use: \(account)")
                }
                return key
            },
            write: { account, key, label, comment, ending, saved in
                target(account).write(account, key, label, comment, ending, saved)
            },
            setComment: { account, comment in holder(account)?.store.setComment(account, comment) ?? .notFound },
            delete: { account in
                // The login keychain's first: a removal it refuses (the password asked for, and cancelled) stops there,
                // so that no copy left in it comes back at its next use, moved anew.
                let first = legacy.delete(account)
                guard first == .ok || first == .notFound else { return first }
                let statuses = [first] + (syncs() ? [local, synced] : [local]).map { $0.delete(account) }
                if let failure = statuses.first(where: { $0 != .ok && $0 != .notFound }) { return failure }
                return statuses.contains(.ok) ? .ok : .notFound
            },
            message: { code in synced.message(code) ?? local.message(code) })
        store.target = { target($0) }
        return store
    }
}
