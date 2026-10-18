import Foundation

/// The API keys of the Claude, Gemini and OpenAI-compatible providers, and of other services the
/// user brings a key for (the web search, `WebSearch`). They are kept in the keychain (never in the config file); a key
/// set in the user's shell (`ANTHROPIC_API_KEY`, …) is used when the keychain has none. Which keychain is the platform's
/// (`Platform.secrets`): on the Mac, the data protection keychain, synced through iCloud Keychain while that is on
/// (`Keychain.routed`, `KeySync`), when the build is entitled to it; the login keychain when it isn't.
///
/// Reading a key from the login keychain may make macOS ask for the login password (an app signed otherwise than the
/// one that saved it), so it is read only to be used, and once per process (`KeyCache`); whether there is one is told
/// from the item's attributes, which never ask.
///
/// A key is removed only by `remove`, which Settings calls once the user confirmed "Remove Key…": saving an empty or
/// blank key never removes one (a field left empty, submitted or closed keeps the key there). Saves and removals are
/// logged by account, never with the key.
public enum APIKeys {
    /// The keychain service every key is kept under, by account.
    public static let service = "AllInOneIME API key"
    /// The service of the keys set aside (`KeySync.Stores.replaced`): a key that lost to a different one in a merge or a
    /// migration, or that a newer one was written over. Only a safety copy, in this device's store: routed reads, merges
    /// and migrations never read it; Remove… deletes the account's copy.
    public static let replacedService = "AllInOneIME replaced API key"
    /// Accounts whose key never goes to iCloud Keychain, whatever the switches: the AllInOneIME Cloud session belongs to
    /// one Mac (signing out on one would sign out all). AWS credentials are never stored at all.
    public static let neverSynced: Set<String> = ["hosted"]
    static let cache = KeyCache()
    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "keys")

    /// The items of this service: the platform's secret store (`Platform.secrets`: on the Mac the routed store of
    /// `KeySync.system`, or the login keychain in a build without the entitlement), read
    /// through `Platform.current` each time; tests and the self-test give an in-memory one (`Keychain.inMemory`), so that
    /// nothing they do reaches the user's keychain. Setting it installs it in the platform.
    public static var keychain: Keychain {
        get { Platform.current.secrets }
        set { Platform.installed.withLock { $0.secrets = newValue } }
    }

    /// The key for `provider`: the keychain's, else the login shell's.
    public static func load(_ provider: Provider) -> String? {
        load(account: provider.rawValue, variables: provider.keyVariables)
    }

    /// The key for `provider` to send to `host`. A key in the keychain goes only to the host it was saved
    /// for (one saved before keys were tied to a host is tied to the first it is sent to): a base URL
    /// changed to another service (a relay) doesn't get the key of the one before.
    public static func load(_ provider: Provider, for host: String) throws -> String? {
        let host = host.lowercased()
        let account = provider.rawValue
        guard let key = keychainKey(account: account) else { return load(provider) }
        guard let saved = savedHost(account: account) else {
            bind(account: account, to: host)
            return key
        }
        guard saved == host else { throw ProviderError.keyForAnotherHost(provider, saved: saved) }
        return key
    }

    /// The host the key under `account` was saved for (nil: not tied to one).
    static func savedHost(account: String) -> String? {
        guard let host = keychain.attributes(account)?.comment, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    private static func bind(account: String, to host: String) {
        _ = keychain.setComment(account, host)
        cache.restamp(account, stamp(account: account))  // the key is as it was: not read (asked for) again
    }

    /// The key kept under `account`: the keychain's, else the first of `variables` the login shell sets.
    public static func load(account: String, variables: [String]) -> String? {
        if let key = keychainKey(account: account) { return key }
        return variables.lazy.compactMap { Platform.current.processes.loginEnvironment[$0] }.first
    }

    /// Where the key comes from, for the settings window.
    public enum Source: Equatable, Sendable {
        case keychain
        case environment(String)
        case none
    }

    public static func source(_ provider: Provider) -> Source {
        source(account: provider.rawValue, variables: provider.keyVariables)
    }

    public static func source(account: String, variables: [String]) -> Source {
        if hasKeychainKey(account: account) { return .keychain }
        if let name = variables.first(where: { Platform.current.processes.loginEnvironment[$0] != nil }) { return .environment(name) }
        return .none
    }

    public static func keychainKey(_ provider: Provider) -> String? {
        keychainKey(account: provider.rawValue)
    }

    /// Whether the keychain has a key under `account`, from the item's attributes: the key isn't read, so
    /// the user is never asked for it.
    public static func hasKeychainKey(account: String, in store: Keychain = keychain) -> Bool {
        stamp(account: account, in: store) != nil
    }

    /// The key under `account`, read from the keychain once in this process (and again only when the item
    /// changed since, here or in another app).
    public static func keychainKey(account: String) -> String? {
        cache.key(account, stamp: stamp(account: account)) { readKey(account: account) }
    }

    /// When the item under `account` was made and last changed (nil: there is none), from its attributes.
    static func stamp(account: String, in store: Keychain = keychain) -> KeyCache.Stamp? {
        store.attributes(account).map { KeyCache.Stamp(created: $0.created, modified: $0.modified) }
    }

    private static func readKey(account: String) -> String? {
        guard let key = keychain.read(account), !key.isEmpty else { return nil }
        return key
    }

    /// Stores `key` for `provider`, to be sent to `host` only (nil: the first host it is sent to).
    public static func save(_ key: String, for provider: Provider, host: String? = nil) throws {
        try save(key, account: provider.rawValue, label: "AllInOneIME: \(provider.displayName)", host: host)
    }

    /// Stores `key` under `account`, shown in Keychain Access as `label`. A key already there is replaced in place, so
    /// a failed save leaves it as it was. An empty or blank key is refused (`EmptyKey`) and never removes the one there:
    /// that is `remove`.
    public static func save(_ key: String, account: String, label: String, host: String? = nil,
                            in store: Keychain = keychain) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw EmptyKey() }
        defer { cache.forget(account) }
        let status = store.write(account, key, label, host?.lowercased() ?? "", ending(of: key), Date())
        guard status == .ok else {
            log.error("key not saved: \(account) (\(status.code))")
            throw KeychainError(status: status.code, message: store.message(status.code))
        }
        log.notice("key saved: \(account)")
    }

    /// Removes the key of `provider`: only ever on the user's say-so (Settings → Remove Key…, confirmed; signing out).
    public static func remove(_ provider: Provider) throws {
        try remove(account: provider.rawValue)
    }

    /// Removes the key under `account` (none there: nothing to do).
    public static func remove(account: String, in store: Keychain = keychain) throws {
        defer { cache.forget(account) }
        let status = store.delete(account)
        guard status == .ok || status == .notFound else {
            log.error("key not removed: \(account) (\(status.code))")
            throw KeychainError(status: status.code, message: store.message(status.code))
        }
        if status == .ok { log.notice("key removed: \(account)") }
    }

    /// The last 4 characters of `key`, kept with it as an attribute (not secret) so that Settings can say which key is
    /// saved ("ends in a1b2") without reading it; none for a key shorter than 12 characters.
    public static func ending(of key: String) -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.count >= 12 ? String(key.suffix(4)) : nil
    }

    /// The ending kept with the key under `account` (`ending(of:)`), from its attributes: the key isn't read. Nil when
    /// there is no key, or it was saved before endings were kept, or it is short.
    public static func keyEnding(account: String, in store: Keychain = keychain) -> String? {
        store.attributes(account)?.ending
    }

    /// A save with nothing to save: an empty field is never a way to remove a key.
    public struct EmptyKey: Error, LocalizedError {
        public init() {}
        public var errorDescription: String? { "Nothing to save: the key is empty" }
    }

    /// One item's attributes, never its key: when it was made and last changed, its comment (the host it's for), the
    /// key's last 4 characters (`ending(of:)`), kept in its generic attribute, its label (as Keychain Access shows it:
    /// "AllInOneIME: Gemini API"), and when the key was saved (`saved`).
    public struct ItemAttributes: Equatable, Sendable {
        public var created: Date?
        public var modified: Date?
        public var comment: String?
        public var ending: String?
        public var label: String?
        /// When the key was saved (`APIKeys.save`), carried by every copy of it (iCloud Keychain's, the moves of
        /// `KeySync`), unlike `modified`, which the keychain sets to now on every write, a copy's or a comment's. Nil:
        /// the item doesn't say (every item 0.6.4 left).
        public var saved: Date?

        public init(created: Date?, modified: Date?, comment: String?, ending: String? = nil, label: String? = nil,
                    saved: Date? = nil) {
            self.created = created
            self.modified = modified
            self.comment = comment
            self.ending = ending
            self.label = label
            self.saved = saved
        }

        /// When this key was last set, as the newest-wins of `KeySync` compares it: its save time, else (an item that
        /// doesn't say) its modification date.
        public var changed: Date? { saved ?? modified }
    }

    /// The generic attribute that holds a key's ending: "ends:a1b2" (empty: none).
    static func endingAttribute(_ ending: String?) -> Data { Data((ending.map { "ends:" + $0 } ?? "").utf8) }
    static func ending(fromAttribute data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8), text.hasPrefix("ends:") else { return nil }
        let ending = String(text.dropFirst(5))
        return ending.count == 4 ? ending : nil
    }

    /// The attribute that holds when a key was saved (`ItemAttributes.saved`; on Apple platforms its description,
    /// which Keychain Access shows as its kind): "saved:2026-10-18T07:52:01.250Z".
    static func savedAttribute(_ saved: Date) -> String { "saved:" + savedFormat().string(from: saved) }
    static func saved(fromAttribute text: String?) -> Date? {
        guard let text, text.hasPrefix("saved:") else { return nil }
        return savedFormat().date(from: String(text.dropFirst(6)))
    }
    private static func savedFormat() -> ISO8601DateFormatter {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format
    }

    /// How a change to an item went: the platform's own status codes are kept for the message (`KeychainError`).
    public enum KeychainStatus: Equatable, Sendable {
        case ok
        case notFound
        case failed(Int32)

        /// The platform's code for it (the keychain's `OSStatus` on Apple platforms).
        public var code: Int32 {
            switch self {
            case .ok: return 0
            case .notFound: return -25300  // errSecItemNotFound
            case let .failed(code): return code
            }
        }
    }

    /// The calls `APIKeys` makes on its service's items, by account (`SecretStore`, `Platform.secrets`).
    public struct Keychain: Sendable {
        /// Which keychain a store is, for the moves between them (`KeySync`).
        public enum Kind: Sendable {
            /// The login keychain (the file-based one on the Mac), where keys were kept up to 0.6.4: read once to move
            /// them out (`KeySync.migrate`), and where they stay in a build that isn't entitled to the others.
            case legacy
            /// This device's items in the data protection keychain (never synced).
            case local
            /// The items iCloud Keychain syncs: every Mac's. Never deleted from by a merge (`KeySync.merge`); the routed
            /// store counts as this too, since it holds them.
            case synced
            /// Kept in memory (tests, the self-test).
            case memory
        }

        public var kind: Kind
        /// The accounts that have an item, from their attributes: nothing is read, so nothing is asked.
        public var accounts: @Sendable () -> [String]
        /// The item's attributes (nil: there is none); its key isn't read, so nothing is asked.
        public var attributes: @Sendable (_ account: String) -> ItemAttributes?
        /// The key itself (may make macOS ask for the login password).
        public var read: @Sendable (_ account: String) -> String?
        /// Sets the key, its label, comment, ending and save time (`ItemAttributes.saved`; nil: left as it is): in place
        /// when there is an item, else a new one.
        public var write: @Sendable (_ account: String, _ key: String, _ label: String, _ comment: String, _ ending: String?,
                                     _ saved: Date?) -> KeychainStatus
        /// Sets the comment alone.
        public var setComment: @Sendable (_ account: String, _ comment: String) -> KeychainStatus
        public var delete: @Sendable (_ account: String) -> KeychainStatus
        /// What a failure's code means, in words (nil: the code is all there is).
        public var message: @Sendable (_ code: Int32) -> String?
        /// For a store routed over others (`routed`): the one a write of `account` goes to. Nil: this store itself.
        /// `KeySync`'s moves read a copy back from, and take a bad one out of, that store alone.
        public var target: (@Sendable (_ account: String) -> Keychain)? = nil

        public init(kind: Kind = .memory, accounts: @escaping @Sendable () -> [String] = { [] },
                    attributes: @escaping @Sendable (String) -> ItemAttributes?, read: @escaping @Sendable (String) -> String?,
                    write: @escaping @Sendable (String, String, String, String, String?, Date?) -> KeychainStatus,
                    setComment: @escaping @Sendable (String, String) -> KeychainStatus,
                    delete: @escaping @Sendable (String) -> KeychainStatus,
                    message: @escaping @Sendable (Int32) -> String? = { _ in nil }) {
            self.kind = kind
            self.accounts = accounts
            self.attributes = attributes
            self.read = read
            self.write = write
            self.setComment = setComment
            self.delete = delete
            self.message = message
        }

        /// No secret store on this platform (until its shell brings one): nothing is kept, a save fails.
        public static let unavailable = Keychain(
            kind: .local, attributes: { _ in nil }, read: { _ in nil }, write: { _, _, _, _, _, _ in .failed(-4) }, setComment: { _, _ in .notFound },
            delete: { _ in .notFound }, message: { _ in "No secret store on this platform" })

        /// Items kept in memory, for tests and the self-test: the user's keychain is never touched.
        public static func inMemory() -> Keychain {
            final class Items: @unchecked Sendable {
                let lock = NSLock()
                var items: [String: (key: String, label: String, comment: String, ending: String?, created: Date, modified: Date,
                                     saved: Date?)] = [:]
            }
            let store = Items()
            return Keychain(
                kind: .memory,
                accounts: { store.lock.withLock { store.items.keys.sorted() } },
                attributes: { account in
                    store.lock.withLock {
                        store.items[account].map {
                            ItemAttributes(created: $0.created, modified: $0.modified, comment: $0.comment, ending: $0.ending,
                                           label: $0.label, saved: $0.saved)
                        }
                    }
                },
                read: { account in store.lock.withLock { store.items[account]?.key } },
                write: { account, key, label, comment, ending, saved in
                    store.lock.withLock {
                        let now = Date(), old = store.items[account]
                        store.items[account] = (key, label, comment, ending, old?.created ?? now, now, saved ?? old?.saved)
                    }
                    return .ok
                },
                setComment: { account, comment in
                    store.lock.withLock {
                        guard store.items[account] != nil else { return .notFound }
                        store.items[account]?.comment = comment
                        store.items[account]?.modified = Date()
                        return .ok
                    }
                },
                delete: { account in
                    store.lock.withLock { store.items.removeValue(forKey: account) == nil ? .notFound : .ok }
                })
        }
    }

    /// The keys read from the keychain in this process, each with its item's stamp: one is read again only when
    /// its item changed (saved again or removed, here or in another app), so a user who allowed the read once
    /// isn't asked on every request. An account's reads are one at a time (requests made together ask once);
    /// another account's never wait for them (a prompt that is up holds up only its own key).
    final class KeyCache: @unchecked Sendable {
        struct Stamp: Equatable {
            var created: Date?
            var modified: Date?
        }

        private var keys: [String: (stamp: Stamp, key: String)] = [:]
        /// Bumped by `forget`: a read that started before isn't kept (the key may have been saved meanwhile,
        /// within the second the stamp tells apart).
        private var generations: [String: Int] = [:]
        private var readers: [String: NSLock] = [:]
        private let lock = NSLock()

        /// The key under `account` when its item is still `stamp`, else what `read` reads (kept unless nil);
        /// nil with no item (`stamp` nil).
        func key(_ account: String, stamp: Stamp?, read: () -> String?) -> String? {
            guard let stamp else {
                forget(account)
                return nil
            }
            if let key = kept(account, stamp) { return key }
            let reader = lock.withLock {
                if let reader = readers[account] { return reader }
                let reader = NSLock()
                readers[account] = reader
                return reader
            }
            reader.lock()
            defer { reader.unlock() }
            if let key = kept(account, stamp) { return key }  // read meanwhile
            let generation = lock.withLock { generations[account, default: 0] }
            guard let key = read() else { return nil }
            lock.withLock { if generations[account, default: 0] == generation { keys[account] = (stamp, key) } }
            return key
        }

        /// The kept key is still the item's, now `stamp` (only its attributes changed).
        func restamp(_ account: String, _ stamp: Stamp?) {
            lock.withLock { keys[account] = stamp.flatMap { stamp in keys[account].map { (stamp, $0.key) } } }
        }

        func forget(_ account: String) {
            lock.withLock {
                keys[account] = nil
                generations[account, default: 0] += 1
            }
        }

        private func kept(_ account: String, _ stamp: Stamp) -> String? {
            lock.withLock { keys[account].flatMap { $0.stamp == stamp ? $0.key : nil } }
        }
    }

    public struct KeychainError: Error, LocalizedError {
        public let status: Int32
        /// The store's words for it.
        public let message: String?

        public init(status: Int32, message: String? = nil) {
            self.status = status
            self.message = message
        }

        public var errorDescription: String? { message ?? "Keychain error \(status)" }
    }
}
