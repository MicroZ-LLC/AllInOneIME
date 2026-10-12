import Foundation
import Security

/// The API keys of the Claude, Gemini and OpenAI-compatible providers, and of other services the
/// user brings a key for (the web search, `WebSearch`). They are kept in the login keychain (never in
/// the config file); a key set in the user's shell (`ANTHROPIC_API_KEY`, …) is used when the keychain
/// has none.
public enum APIKeys {
    static let service = "AllInOneIME API key"

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
        if keychainKey(account: account) != nil { return .keychain }
        if let name = variables.first(where: { ShellEnvironment.login[$0] != nil }) { return .environment(name) }
        return .none
    }

    public static func keychainKey(_ provider: Provider) -> String? {
        keychainKey(account: provider.rawValue)
    }

    public static func keychainKey(account: String) -> String? {
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

    public struct KeychainError: Error, LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }
}
