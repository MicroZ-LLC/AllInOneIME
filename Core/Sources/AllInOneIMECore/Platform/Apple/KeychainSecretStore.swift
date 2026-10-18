#if canImport(Security)
import Foundation
import Security

/// `kSecUseAuthenticationUIFail`, deprecated for `kSecUseAuthenticationContext` with an `LAContext`, which is the data
/// protection keychain's: the file-based one is what the moves read (`APIKeys.Keychain.quietLogin`), so the constant
/// stays. Reached through a protocol so that the deprecation isn't warned of at every build; the value is the same.
private protocol AuthenticationUIFail { static var fail: CFString { get } }
private enum DeprecatedKeychainConstants: AuthenticationUIFail {
    @available(macOS, deprecated: 11) @available(iOS, deprecated: 14)
    static var fail: CFString { kSecUseAuthenticationUIFail }
}

extension APIKeys.Keychain {
    /// The user's login keychain (on the Mac, the file-based one): generic passwords of `APIKeys.service`, one per account.
    /// Where keys are kept as in 0.6.4 while key sync is off, and always in a build without the keychain entitlement
    /// (`processIsEntitled`).
    public static let login = legacyKeychain(asking: true)

    /// The login keychain with asking turned off, for the moves when key sync is turned on or off (`KeySync.Stores.turn`):
    /// a read that would ask for the password gives nothing instead, and a write or delete that would ask fails. Both
    /// ways are used: the process's user interaction turned off for the call (`SecKeychainSetUserInteractionAllowed`, the
    /// file-based keychain's own switch) and `kSecUseAuthenticationUIFail` on the reads.
    static let quietLogin = legacyKeychain(asking: false)

    /// The items iCloud Keychain syncs (every Mac's): synchronizable generic passwords of `service` in the data protection
    /// keychain, in the access group `group` (set on every query), `kSecAttrAccessibleAfterFirstUnlock` (as iCloud
    /// Keychain needs; a key is there while the screen is locked), never asking for the password. Only synced items are
    /// kept there: keys that don't sync stay in the login keychain. Every query, deletes too, says
    /// `kSecAttrSynchronizable` true (never `kSecAttrSynchronizableAny`).
    public static func dataProtection(group: String, service: String = APIKeys.service) -> APIKeys.Keychain {
        @Sendable func query(_ account: String?) -> [String: Any] {
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecUseDataProtectionKeychain as String: true, kSecAttrAccessGroup as String: group,
                                        kSecAttrSynchronizable as String: kCFBooleanTrue!]
            if let account { query[kSecAttrAccount as String] = account }
            return query
        }
        return APIKeys.Keychain(
            kind: .synced,
            accounts: { accounts(query(nil)) },
            attributes: { account in attributes(query(account)) },
            read: { account in read(query(account)) },
            write: { account, key, label, comment, ending, saved in
                write(query(account), key: key, label: label, comment: comment, ending: ending, saved: saved,
                      adding: [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock])
            },
            setComment: { account, comment in
                keychainStatus(SecItemUpdate(query(account) as CFDictionary, [kSecAttrComment as String: comment] as CFDictionary))
            },
            delete: { account in keychainStatus(SecItemDelete(query(account) as CFDictionary)) },
            message: { code in SecCopyErrorMessageString(code, nil) as String? })
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
    /// "agrp", "pdmn", …), for the self-test: `eitherSync` matches items synced or not
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

    /// The login keychain's generic passwords of `service` (`login`, `quietLogin`; the replaced copies under
    /// `KeySync.replacedService`; the self-test's own service to check that these queries never reach the data
    /// protection keychain). On the Mac every query says so (`kSecUseDataProtectionKeychain` false): an item of the data
    /// protection keychain is never seen, read or deleted by them, so the moves out of the login keychain never take the
    /// synced items. With `asking` false, nothing it does asks for the password (`withoutAsking`).
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
                silent[kSecUseAuthenticationUI as String] = (DeprecatedKeychainConstants.self as any AuthenticationUIFail.Type).fail
                return withoutAsking { read(silent) }
            },
            write: { account, key, label, comment, ending, saved in
                let set = { write(query(account), key: key, label: label, comment: comment, ending: ending, saved: saved, adding: [:]) }
                return asking ? set() : withoutAsking(set)
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
    /// The Mac's stores when the process is entitled (`KeySync.system`): the synced items of the shared group, and the
    /// login keychain, with the replaced copies in it. The Mac only: on iOS the login keychain's queries would find the
    /// data protection keychain's own items (there is no other), and moving them out would delete them.
    static let appleStores: Stores? = APIKeys.Keychain.processIsEntitled
        ? Stores(login: .login, synced: .dataProtection(group: accessGroup),
                 replaced: .legacyKeychain(service: replacedService, asking: true), quietLogin: .quietLogin,
                 quietReplaced: .legacyKeychain(service: replacedService, asking: false))
        : nil
}
#endif
#endif
