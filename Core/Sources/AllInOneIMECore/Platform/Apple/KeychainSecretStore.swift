#if canImport(Security)
import Foundation
import Security

extension APIKeys.Keychain {
    /// The user's login keychain (on the Mac, the file-based one): generic passwords of `APIKeys.service`, one per account.
    /// Where keys were kept up to 0.6.4, and still are in a build without the keychain entitlement (`processIsEntitled`).
    public static let login = legacyKeychain(asking: true)

    /// The login keychain with asking turned off, for the silent pass at launch (`KeySync.Stores.migrate`): a read that
    /// would ask for the password gives nothing instead. Both ways are used: the process's user interaction turned off for
    /// the call (`SecKeychainSetUserInteractionAllowed`, the file-based keychain's own switch) and
    /// `kSecUseAuthenticationUIFail` on the query.
    static let quietLogin = legacyKeychain(asking: false)

    /// Generic passwords of `service` in the data protection keychain, in the access group `group` (set on every query),
    /// `synchronizable` ones (the items iCloud Keychain syncs: every Mac's) or this device's own. Readable after the first
    /// unlock, so a key is there while the screen is locked; no item ever asks for the password. Items are
    /// `kSecAttrAccessibleAfterFirstUnlock` (iCloud Keychain needs it of the synced ones; this device's go to a new Mac
    /// with Migration Assistant, as the login keychain's did), except those of `APIKeys.neverSynced`, which are
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: the AllInOneIME Cloud sign-in is this Mac's, and never goes to
    /// another, not even with a backup restored there. Every query, deletes too, is of its own kind alone
    /// (`kSecAttrSynchronizable` true or false, never `kSecAttrSynchronizableAny`): taking a bad copy out of one store
    /// never takes the other's item.
    public static func dataProtection(group: String, synchronizable: Bool, service: String = APIKeys.service) -> APIKeys.Keychain {
        @Sendable func query(_ account: String?) -> [String: Any] {
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecUseDataProtectionKeychain as String: true, kSecAttrAccessGroup as String: group,
                                        kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!]
            if let account { query[kSecAttrAccount as String] = account }
            return query
        }
        return APIKeys.Keychain(
            kind: synchronizable ? .synced : .local,
            accounts: { accounts(query(nil)) },
            attributes: { account in attributes(query(account)) },
            read: { account in read(query(account)) },
            write: { account, key, label, comment, ending, saved in
                write(query(account), key: key, label: label, comment: comment, ending: ending, saved: saved,
                      adding: [kSecAttrAccessible as String: accessibility(account: account, synchronizable: synchronizable)])
            },
            setComment: { account, comment in
                keychainStatus(SecItemUpdate(query(account) as CFDictionary, [kSecAttrComment as String: comment] as CFDictionary))
            },
            delete: { account in keychainStatus(SecItemDelete(query(account) as CFDictionary)) },
            message: { code in SecCopyErrorMessageString(code, nil) as String? })
    }

    /// When the data protection keychain's item of `account` can be read (`kSecAttrAccessible`): after the first unlock,
    /// on this device alone for `APIKeys.neverSynced`.
    static func accessibility(account: String, synchronizable: Bool) -> CFString {
        !synchronizable && APIKeys.neverSynced.contains(account) ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                                                                  : kSecAttrAccessibleAfterFirstUnlock
    }

    /// Whether this process may use the shared access group (`KeySync.accessGroup`): its `keychain-access-groups`
    /// entitlement lists it, which only an app signed with the provisioning profile has. Looked up once.
    public static let processIsEntitled: Bool = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains(KeySync.accessGroup) == true
        #else
        return true  // an iOS app always has its entitlements
        #endif
    }()

    /// One item's attributes as the data protection keychain keeps them (its key not read), by their short names ("sync",
    /// "agrp", "pdmn", …), for the self-test: `eitherSync` matches synced items and this device's alike
    /// (`kSecAttrSynchronizableAny`); without it the query leaves `kSecAttrSynchronizable` out, which matches only items
    /// that don't sync.
    public static func storedAttributes(service: String, account: String, group: String, eitherSync: Bool) -> [String: Any]? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: true,
                                    kSecAttrAccessGroup as String: group, kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        if eitherSync { query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? [String: Any]
    }

    /// Deletes the data protection keychain's item of `service` and `account` in `group`, synced or not
    /// (`kSecAttrSynchronizableAny`), for the self-test.
    public static func deleteEitherSync(service: String, account: String, group: String) -> APIKeys.KeychainStatus {
        keychainStatus(SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                      kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: true,
                                      kSecAttrAccessGroup as String: group,
                                      kSecAttrSynchronizable as String: kSecAttrSynchronizableAny] as CFDictionary))
    }

    // MARK: - The calls

    /// The login keychain's generic passwords of `service` (`login`, `quietLogin`; the self-test's own service to check
    /// that these queries never reach the data protection keychain). On the Mac every query says so
    /// (`kSecUseDataProtectionKeychain` false): an item of the data protection keychain is never seen, read or deleted
    /// by them, so the moves out of the login keychain never take the new store's items.
    public static func legacyKeychain(service: String = APIKeys.service, asking: Bool) -> APIKeys.Keychain {
        @Sendable func query(_ account: String?) -> [String: Any] {
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = false  // the file-based keychain (iOS has no other than it)
            #endif
            if let account { query[kSecAttrAccount as String] = account }
            return query
        }
        return APIKeys.Keychain(
            kind: .legacy,
            accounts: { accounts(query(nil)) },
            attributes: { account in attributes(query(account)) },
            read: { account in
                guard !asking else { return read(query(account)) }
                var silent = query(account)
                silent[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
                return withoutAsking { read(silent) }
            },
            write: { account, key, label, comment, ending, saved in
                write(query(account), key: key, label: label, comment: comment, ending: ending, saved: saved, adding: [:])
            },
            setComment: { account, comment in
                keychainStatus(SecItemUpdate(query(account) as CFDictionary, [kSecAttrComment as String: comment] as CFDictionary))
            },
            delete: { account in
                asking ? keychainStatus(SecItemDelete(query(account) as CFDictionary))
                    : withoutAsking { keychainStatus(SecItemDelete(query(account) as CFDictionary)) }
            },
            message: { code in SecCopyErrorMessageString(code, nil) as String? })
    }

    /// `body` with the file-based keychain's prompts turned off for the process (on again after).
    private static func withoutAsking<T>(_ body: () -> T) -> T {
        #if os(macOS)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        #endif
        return body()
    }

    private static func accounts(_ query: [String: Any]) -> [String] {
        var query = query
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess, let found = items as? [[String: Any]] else { return [] }
        return Array(Set(found.compactMap { $0[kSecAttrAccount as String] as? String })).sorted()
    }

    private static func attributes(_ query: [String: Any]) -> APIKeys.ItemAttributes? {
        var query = query
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let found = item as? [String: Any] else { return nil }
        return APIKeys.ItemAttributes(created: found[kSecAttrCreationDate as String] as? Date,
                                      modified: found[kSecAttrModificationDate as String] as? Date,
                                      comment: found[kSecAttrComment as String] as? String,
                                      ending: APIKeys.ending(fromAttribute: found[kSecAttrGeneric as String] as? Data),
                                      label: found[kSecAttrLabel as String] as? String,
                                      saved: APIKeys.saved(fromAttribute: found[kSecAttrDescription as String] as? String))
    }

    private static func read(_ query: [String: Any]) -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// In place when there is an item, else a new one with `adding` besides. The save time goes in the description
    /// (`APIKeys.savedAttribute`), which iCloud Keychain carries with the item.
    private static func write(_ query: [String: Any], key: String, label: String, comment: String, ending: String?,
                              saved: Date?, adding: [String: Any]) -> APIKeys.KeychainStatus {
        var values: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrLabel as String: label,
                                     kSecAttrComment as String: comment,
                                     kSecAttrGeneric as String: APIKeys.endingAttribute(ending)]
        if let saved { values[kSecAttrDescription as String] = APIKeys.savedAttribute(saved) }
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        guard status == errSecItemNotFound else { return keychainStatus(status) }
        let item = query.merging(values) { $1 }.merging(adding) { $1 }
        return keychainStatus(SecItemAdd(item as CFDictionary, nil))
    }

    private static func keychainStatus(_ status: OSStatus) -> APIKeys.KeychainStatus {
        switch status {
        case errSecSuccess: return .ok
        case errSecItemNotFound: return .notFound
        default: return .failed(status)
        }
    }
}

#if os(macOS)
extension KeySync {
    /// The Mac's stores when the process is entitled (`KeySync.system`): this device's and the synced items of the shared
    /// group, and the login keychain behind them. The Mac only: on iOS the login keychain's queries would find the data
    /// protection keychain's own items (there is no other), and moving them out would delete them.
    static let appleStores: Stores? = APIKeys.Keychain.processIsEntitled
        ? Stores(local: .dataProtection(group: accessGroup, synchronizable: false),
                 synced: .dataProtection(group: accessGroup, synchronizable: true),
                 legacy: .login, quietLegacy: .quietLogin)
        : nil
}
#endif
#endif
