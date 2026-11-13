#if canImport(Security)
import Foundation
import Security

extension AntigravityBackend {
    /// Whether the login keychain has agy's Google sign-in (service "gemini", account "antigravity"): its attributes
    /// only, the token isn't read, nothing asks (`AntigravityBackend.keychainSignIn`).
    static func loginKeychainHasSignIn() -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "gemini",
                                    kSecAttrAccount as String: "antigravity", kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
#endif
