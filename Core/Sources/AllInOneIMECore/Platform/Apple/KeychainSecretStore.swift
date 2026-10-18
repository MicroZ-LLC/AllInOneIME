#if canImport(Security)
import Foundation
import Security

extension APIKeys.Keychain {
    /// The user's login keychain: generic passwords of `APIKeys.service`, one per account.
    public static let login = APIKeys.Keychain(
        attributes: { account in
            var query = baseQuery(account: account)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let found = item as? [String: Any]
            else { return nil }
            return APIKeys.ItemAttributes(created: found[kSecAttrCreationDate as String] as? Date,
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
            guard status == errSecItemNotFound else { return keychainStatus(status) }
            return keychainStatus(SecItemAdd(baseQuery(account: account).merging(values) { $1 } as CFDictionary, nil))
        },
        setComment: { account, comment in
            keychainStatus(SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecAttrComment as String: comment] as CFDictionary))
        },
        delete: { account in keychainStatus(SecItemDelete(baseQuery(account: account) as CFDictionary)) },
        message: { code in SecCopyErrorMessageString(code, nil) as String? })

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: APIKeys.service,
         kSecAttrAccount as String: account]
    }

    private static func keychainStatus(_ status: OSStatus) -> APIKeys.KeychainStatus {
        switch status {
        case errSecSuccess: return .ok
        case errSecItemNotFound: return .notFound
        default: return .failed(status)
        }
    }
}
#endif
