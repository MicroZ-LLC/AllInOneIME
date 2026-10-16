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
public enum APIKeys {
    static let service = "AllInOneIME API key"
    static let cache = KeyCache()

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
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let host = (item as? [String: Any])?[kSecAttrComment as String] as? String, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    private static func bind(account: String, to host: String) {
        SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecAttrComment as String: host] as CFDictionary)
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
    public static func hasKeychainKey(account: String) -> Bool {
        stamp(account: account) != nil
    }

    /// The key under `account`, read from the keychain once in this process (and again only when the item
    /// changed since, here or in another app).
    public static func keychainKey(account: String) -> String? {
        cache.key(account, stamp: stamp(account: account)) { readKey(account: account) }
    }

    /// When the item under `account` was made and last changed (nil: there is none), from its attributes.
    static func stamp(account: String) -> KeyCache.Stamp? {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let attributes = item as? [String: Any]
        else { return nil }
        return KeyCache.Stamp(created: attributes[kSecAttrCreationDate as String] as? Date,
                              modified: attributes[kSecAttrModificationDate as String] as? Date)
    }

    private static func readKey(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    /// Stores `key` for `provider`, to be sent to `host` only (nil: the first host it is sent to); an empty
    /// key removes it.
    public static func save(_ key: String, for provider: Provider, host: String? = nil) throws {
        try save(key, account: provider.rawValue, label: "AllInOneIME: \(provider.displayName)", host: host)
    }

    /// Stores `key` under `account`, shown in Keychain Access as `label`; an empty key removes it. A key
    /// already there is replaced in place, so a failed save leaves it as it was.
    public static func save(_ key: String, account: String, label: String, host: String? = nil) throws {
        defer { cache.forget(account) }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrLabel as String: label,
                                     kSecAttrComment as String: host?.lowercased() ?? ""]
        var status = SecItemUpdate(baseQuery(account: account) as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery(account: account).merging(values) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
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
