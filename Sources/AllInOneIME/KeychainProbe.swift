import AllInOneIMECore
import CryptoKit
import Foundation
import Security

/// `AllInOneIME --keychain-probe write|read|delete|list [ACCOUNT] [--service NAME]`, hidden (not in the usage): the
/// two-Mac check of key sync. It acts on the synced items of the self-test's own service, "AllInOneIME self-test key",
/// in the shared access group (`KeySync.accessGroup`) of the data protection keychain, never on the user's keys: any
/// other `--service` is refused. `write` stores a random test token (never given on the command line) with a random
/// comment and the save time; every command prints one JSON line, the token only as the first 12 hex digits of its
/// SHA-256, so the other Mac's `read` can be compared with it.
enum KeychainProbe {
    static let service = "AllInOneIME self-test key"

    static func run(_ arguments: [String]) -> Int32 {
        var arguments = arguments
        if let index = arguments.firstIndex(of: "--service") {
            let named = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
            guard named == service else {
                return emit(["ok": false, "error": "refused: only the service \"\(service)\" can be probed"], code: 2)
            }
            arguments.removeSubrange(index...min(index + 1, arguments.count - 1))
        }
        guard let command = arguments.first, ["write", "read", "delete", "list"].contains(command) else {
            return emit(["ok": false, "error": "usage: --keychain-probe write|read|delete|list [ACCOUNT]"], code: 2)
        }
        let group = KeySync.accessGroup
        var base: [String: Any] = ["command": command, "service": service, "group": group,
                                   "entitled": APIKeys.Keychain.processIsEntitled, "host": ProcessInfo.processInfo.hostName]
        guard APIKeys.Keychain.processIsEntitled else {
            base["ok"] = false
            base["error"] = "this build has no keychain-access-groups entitlement for \(group)"
            return emit(base, code: 1)
        }
        let store = APIKeys.Keychain.dataProtection(group: group, service: service)
        if command == "list" {
            do {
                base["accounts"] = try store.listing?() ?? store.accounts()
                base["ok"] = true
                return emit(base, code: 0)
            } catch let error as APIKeys.KeychainError {
                base["ok"] = false
                base["status"] = Int(error.status)
                base["error"] = error.localizedDescription
                return emit(base, code: 1)
            } catch {
                base["ok"] = false
                base["error"] = "\(error)"
                return emit(base, code: 1)
            }
        }
        guard arguments.count >= 2, !arguments[1].isEmpty else {
            return emit(["ok": false, "error": "\(command) needs an account"], code: 2)
        }
        let account = arguments[1]
        base["account"] = account
        switch command {
        case "write":
            var bytes = [UInt8](repeating: 0, count: 24)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let token = "probe-" + Data(bytes).base64EncodedString()
            let comment = "probe-" + UUID().uuidString.prefix(8).lowercased() + ".example"
            let saved = Date()
            let status = store.write(account, token, "AllInOneIME: keychain probe", comment, APIKeys.ending(of: token), saved)
            base["ok"] = status == .ok
            base["status"] = Int(status.code)
            base["hash"] = hash(token)
            base["comment"] = comment
            base["saved"] = timestamp(saved)
            base["wroteAt"] = timestamp(Date())
            return emit(base.merging(stored(account, group: group)) { $1 }, code: status == .ok ? 0 : 1)
        case "read":
            let key = store.read(account)
            let attributes = store.attributes(account)
            base["ok"] = true
            base["found"] = key != nil
            base["readAt"] = timestamp(Date())
            if let key { base["hash"] = hash(key) }
            if let attributes {
                base["comment"] = attributes.comment ?? NSNull()
                base["saved"] = attributes.saved.map(timestamp) ?? NSNull()
                base["modified"] = attributes.modified.map(timestamp) ?? NSNull()
                base["label"] = attributes.label ?? NSNull()
            }
            return emit(base.merging(stored(account, group: group)) { $1 }, code: 0)
        default:  // delete: the synced item only (the store's own query says kSecAttrSynchronizable true)
            let status = store.delete(account)
            base["ok"] = status == .ok || status == .notFound
            base["status"] = Int(status.code)
            base["deleted"] = status == .ok
            base["deletedAt"] = timestamp(Date())
            return emit(base, code: base["ok"] as? Bool == true ? 0 : 1)
        }
    }

    /// The item's sync, access group and accessibility as the keychain keeps them (`sync`, `agrp`, `pdmn`).
    private static func stored(_ account: String, group: String) -> [String: Any] {
        guard let stored = APIKeys.Keychain.storedAttributes(service: service, account: account, group: group, eitherSync: true)
        else { return ["stored": NSNull()] }
        let sync = (stored[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue
        return ["stored": ["sync": sync.map { $0 ? 1 : 0 } ?? -1,
                           "agrp": stored[kSecAttrAccessGroup as String] as? String ?? "",
                           "pdmn": stored[kSecAttrAccessible as String] as? String ?? ""]]
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    private static func timestamp(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }

    private static func emit(_ object: [String: Any], code: Int32) -> Int32 {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        print(String(decoding: data, as: UTF8.self))
        return code
    }
}
