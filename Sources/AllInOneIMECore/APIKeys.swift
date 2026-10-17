import Foundation
import Security

/// The API keys of the Claude, Gemini and OpenAI-compatible providers, and of other services the
/// user brings a key for (the web search, `WebSearch`). They are kept in the login keychain (never in
/// the config file); a key set in the user's shell (`ANTHROPIC_API_KEY`, …) is used when the keychain
/// has none.
///
/// Reading a key may make macOS ask for the login password (an app signed otherwise than the one that saved
/// it), so it is read only to be used, and once per process (`KeyCache`); whether there is one is told from the
/// item's attributes, which never ask.
///
/// A key is removed only by `remove`, which Settings calls once the user confirmed "Remove Key…": saving an empty or
/// blank key never removes one (a field left empty, submitted or closed keeps the key there). Saves and removals are
/// logged by account, never with the key.
public enum APIKeys {
    static let service = "AllInOneIME API key"
    static let cache = KeyCache()
    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "keys")

    /// The items of this service: the login keychain; tests and the self-test give an in-memory one
    /// (`Keychain.inMemory`), so that nothing they do reaches the user's keychain.
    nonisolated(unsafe) public static var keychain = Keychain.login

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
        return variables.lazy.compactMap { ShellEnvironment.login[$0] }.first
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
        if let name = variables.first(where: { ShellEnvironment.login[$0] != nil }) { return .environment(name) }
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
        let status = store.write(account, key, label, host?.lowercased() ?? "", ending(of: key))
        guard status == errSecSuccess else {
            log.error("key not saved: \(account) (\(status))")
            throw KeychainError(status: status)
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
        guard status == errSecSuccess || status == errSecItemNotFound else {
            log.error("key not removed: \(account) (\(status))")
            throw KeychainError(status: status)
        }
        if status == errSecSuccess { log.notice("key removed: \(account)") }
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

    /// One item's attributes, never its key: when it was made and last changed, its comment (the host it's for) and
    /// the key's last 4 characters (`ending(of:)`), kept in its generic attribute.
    public struct ItemAttributes: Equatable, Sendable {
        public var created: Date?
        public var modified: Date?
        public var comment: String?
        public var ending: String?

        public init(created: Date?, modified: Date?, comment: String?, ending: String? = nil) {
            self.created = created
            self.modified = modified
            self.comment = comment
            self.ending = ending
        }
    }

    /// The generic attribute that holds a key's ending: "ends:a1b2" (empty: none).
    static func endingAttribute(_ ending: String?) -> Data { Data((ending.map { "ends:" + $0 } ?? "").utf8) }
    static func ending(fromAttribute data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8), text.hasPrefix("ends:") else { return nil }
        let ending = String(text.dropFirst(5))
        return ending.count == 4 ? ending : nil
    }

    /// The calls `APIKeys` makes on its service's items, by account.
    public struct Keychain: Sendable {
        /// The item's attributes (nil: there is none); its key isn't read, so nothing is asked.
        public var attributes: @Sendable (_ account: String) -> ItemAttributes?
        /// The key itself (may make macOS ask for the login password).
        public var read: @Sendable (_ account: String) -> String?
        /// Sets the key, its label, comment and ending: in place when there is an item, else a new one.
        public var write: @Sendable (_ account: String, _ key: String, _ label: String, _ comment: String, _ ending: String?) -> OSStatus
        /// Sets the comment alone.
        public var setComment: @Sendable (_ account: String, _ comment: String) -> OSStatus
        public var delete: @Sendable (_ account: String) -> OSStatus

        public init(attributes: @escaping @Sendable (String) -> ItemAttributes?, read: @escaping @Sendable (String) -> String?,
                    write: @escaping @Sendable (String, String, String, String, String?) -> OSStatus,
                    setComment: @escaping @Sendable (String, String) -> OSStatus, delete: @escaping @Sendable (String) -> OSStatus) {
            self.attributes = attributes
            self.read = read
            self.write = write
            self.setComment = setComment
            self.delete = delete
        }

        /// The user's login keychain.
        public static let login = Keychain(
            attributes: { account in
                var query = baseQuery(account: account)
                query[kSecReturnAttributes as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var item: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let found = item as? [String: Any]
                else { return nil }
                return ItemAttributes(created: found[kSecAttrCreationDate as String] as? Date,
                                      modified: found[kSecAttrModificationDate as String] as? Date,
                                      comment: found[kSecAttrComment as String] as? String,
                                      ending: APIKeys.ending(fromAttribute: found[kSecAttrGeneric as String] as? Data))
            },
            read: { account in
                var query = baseQuery(account: account)
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var item: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
                return String(data: data, encoding: .utf8)
            },
            write: { account, key, label, comment, ending in
                let values: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrLabel as String: label,
                                             kSecAttrComment as String: comment,
                                             kSecAttrGeneric as String: APIKeys.endingAttribute(ending)]
                let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, values as CFDictionary)
                guard status == errSecItemNotFound else { return status }
                return SecItemAdd(baseQuery(account: account).merging(values) { $1 } as CFDictionary, nil)
            },
            setComment: { account, comment in
                SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecAttrComment as String: comment] as CFDictionary)
            },
            delete: { account in SecItemDelete(baseQuery(account: account) as CFDictionary) })

        /// Items kept in memory, for tests and the self-test: the user's keychain is never touched.
        public static func inMemory() -> Keychain {
            final class Items: @unchecked Sendable {
                let lock = NSLock()
                var items: [String: (key: String, label: String, comment: String, ending: String?, created: Date, modified: Date)] = [:]
            }
            let store = Items()
            return Keychain(
                attributes: { account in
                    store.lock.withLock {
                        store.items[account].map {
                            ItemAttributes(created: $0.created, modified: $0.modified, comment: $0.comment, ending: $0.ending)
                        }
                    }
                },
                read: { account in store.lock.withLock { store.items[account]?.key } },
                write: { account, key, label, comment, ending in
                    store.lock.withLock {
                        let now = Date()
                        store.items[account] = (key, label, comment, ending, store.items[account]?.created ?? now, now)
                    }
                    return errSecSuccess
                },
                setComment: { account, comment in
                    store.lock.withLock {
                        guard store.items[account] != nil else { return errSecItemNotFound }
                        store.items[account]?.comment = comment
                        store.items[account]?.modified = Date()
                        return errSecSuccess
                    }
                },
                delete: { account in
                    store.lock.withLock { store.items.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess }
                })
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
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
        public let status: OSStatus
        public var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }
}
