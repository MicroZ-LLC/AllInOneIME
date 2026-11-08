import AllInOneIMECore
import Foundation

// What the move to AllInOneIME's own system identity hands to the version that has it (0.7.2 on), which never names
// the identity before it:
//
// - the keys in the login keychain (API keys and passwords while key sync is off, the Cloud session, the replaced
//   copies), which the new identity could read only with macOS asking once for each: the version that moves (0.7.1, in
//   those items' access lists) copies each into the new identity's access group as a handover item before the apps are
//   swapped (`handoverService`: never synced, readable by the new identity without asking), and the new version imports
//   each into the login keychain at launch, creating the item itself (its own access list: nothing asked later), then
//   deletes the handover item. The originals are deleted by the cleanup, once the switch is verified;
// - what that cleanup still has to remove (`CleanupRecord`, a file in Application Support): written before the swap,
//   updated as its steps succeed, deleted once all have. The new version does what is left at launch, by the
//   identifiers the record lists alone.
//
// Logged by service and account, never with a key.

public enum IdentityHandover {
    /// The login keychain's services of AllInOneIME's keys: the API keys and passwords (and the Cloud session), and their
    /// replaced copies.
    public static let loginServices = [APIKeys.service, KeySync.replacedService]

    /// The service of the handover item of a key kept under `service`.
    public static func handoverService(for service: String) -> String { service + " (handed over)" }

    /// The handover items of the keys of `service`, in `group` (the new identity's access group): the data protection
    /// keychain's, never synced.
    public static func handoverStore(group: String, service: String) -> APIKeys.Keychain {
        .dataProtection(group: group, service: handoverService(for: service), synchronizable: false)
    }

    /// The login keychain's items of `service`, nothing asked: a read that would ask gives nothing, a delete that would
    /// ask fails.
    public static func loginStore(service: String) -> APIKeys.Keychain {
        .legacyKeychain(service: service, asking: false)
    }

    /// Two save times alike (`ItemAttributes.changed`; a handover item carries its key's, to the millisecond).
    public static func same(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 0.001
    }

    /// A test install's store (`--target-dir`): `service`'s items in a property list of items (service, account,
    /// synchronizable, data, attributes), as the migration's test keychain keeps them; nothing of the user's.
    public static func fileStore(_ file: URL, service: String) -> APIKeys.Keychain {
        @Sendable func entries() -> [[String: Any]] { NSArray(contentsOf: file) as? [[String: Any]] ?? [] }
        @Sendable func save(_ entries: [[String: Any]]) -> APIKeys.KeychainStatus {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (entries as NSArray).write(to: file)
                return .ok
            } catch {
                return .failed(-36)  // errSecIO
            }
        }
        @Sendable func index(_ entries: [[String: Any]], _ account: String) -> Int? {
            entries.firstIndex { $0["service"] as? String == service && $0["account"] as? String == account }
        }
        @Sendable func attributes(_ entry: [String: Any]) -> APIKeys.ItemAttributes {
            let values = entry["attributes"] as? [String: Any] ?? [:]
            return APIKeys.ItemAttributes(created: values["cdat"] as? Date, modified: values["mdat"] as? Date,
                                          comment: values["icmt"] as? String, ending: values["ending"] as? String,
                                          label: values["labl"] as? String,
                                          saved: (values["saved"] as? Double).map { Date(timeIntervalSince1970: $0) })
        }
        @Sendable func write(_ account: String, _ key: String, _ label: String, _ comment: String, _ ending: String?,
                             _ saved: Date?, adding: Bool) -> APIKeys.KeychainStatus {
            var all = entries()
            let found = index(all, account)
            if adding, found != nil { return .failed(APIKeys.Keychain.duplicateItem) }
            let now = Date()
            var values = found.flatMap { all[$0]["attributes"] as? [String: Any] } ?? ["cdat": now]
            values["labl"] = label
            values["icmt"] = comment
            values["ending"] = ending
            values["mdat"] = now
            if let saved { values["saved"] = saved.timeIntervalSince1970 }  // to the millisecond (a property list's date: the second)
            let entry: [String: Any] = ["service": service, "account": account, "synchronizable": false,
                                        "data": Data(key.utf8), "attributes": values]
            if let found { all[found] = entry } else { all.append(entry) }
            return save(all)
        }
        return APIKeys.Keychain(
            kind: .memory,
            accounts: { entries().filter { $0["service"] as? String == service }.compactMap { $0["account"] as? String }.sorted() },
            attributes: { account in
                let all = entries()
                return index(all, account).map { attributes(all[$0]) }
            },
            read: { account in
                let all = entries()
                return index(all, account).flatMap { (all[$0]["data"] as? Data).map { String(decoding: $0, as: UTF8.self) } }
            },
            write: { write($0, $1, $2, $3, $4, $5, adding: false) },
            setComment: { account, comment in
                var all = entries()
                guard let found = index(all, account) else { return .notFound }
                var values = all[found]["attributes"] as? [String: Any] ?? [:]
                values["icmt"] = comment
                all[found]["attributes"] = values
                return save(all)
            },
            delete: { account in
                var all = entries()
                guard let found = index(all, account) else { return .notFound }
                all.remove(at: found)
                return save(all)
            },
            add: { write($0, $1, $2, $3, $4, $5, adding: true) })
    }
}

/// A key in the login keychain, by its service and account.
public struct LoginKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var service: String
    public var account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public static func < (a: Self, b: Self) -> Bool { (a.service, a.account) < (b.service, b.account) }

    public var description: String { "\(service)/\(account)" }
}

/// What the move to AllInOneIME's own system identity still has to remove of the identity before it, as data: written by
/// the version that moves before it swaps the apps, updated as each cleanup step succeeds, deleted once all have. The
/// version after reads it at launch and does what is left with these identifiers alone (it knows no other).
public struct CleanupRecord: Codable, Equatable, Sendable {
    /// A launch agent: its label, and its property list (nil: loaded without one).
    public struct LaunchAgent: Codable, Hashable, Sendable {
        public var label: String
        public var plist: String?

        public init(label: String, plist: String?) {
            self.label = label
            self.plist = plist
        }
    }

    /// An item of `CleanupRecord.keychainGroup` (the data protection keychain's).
    public struct KeychainItem: Codable, Hashable, Sendable {
        public var service: String
        public var account: String
        public var synchronizable: Bool

        public init(service: String, account: String, synchronizable: Bool) {
            self.service = service
            self.account = account
            self.synchronizable = synchronizable
        }
    }

    /// This layout's number: a later one is left alone.
    public static let currentFormat = 1
    public var format = currentFormat
    /// False while the version that moves is at it (from before the swap to the end of its own cleanup); true once it
    /// left the rest to the next version. One not handed over that hasn't changed for `staleAfter` counts as handed over:
    /// that version stopped before it could say.
    public var handedOver = false
    /// When it was last written.
    public var updated = Date()
    /// The bundle IDs of the identity before: an app among `apps` is deleted only when it has one of them.
    public var bundleIDs: [String] = []
    /// The input source to disable and take out of the user's input sources.
    public var inputSource: String?
    /// The user defaults domains to remove (their files too, once emptied).
    public var defaultsDomains: [String] = []
    /// The apps to unregister and delete: the previous apps where the swap left them, and other copies.
    public var apps: [String] = []
    public var launchAgents: [LaunchAgent] = []
    /// The access group of `keychainItems`, the items to delete (their copies are in the new group).
    public var keychainGroup: String?
    public var keychainItems: [KeychainItem] = []
    /// The login keychain's originals of the keys handed over, to delete before their handover items are imported.
    public var loginKeys: [LoginKey] = []

    public init() {}

    /// The record's name, in ~/Library/Application Support/AllInOneIME.
    public static let fileName = "identity-cleanup.json"

    /// Where it is: ~/Library/Application Support/AllInOneIME/identity-cleanup.json.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME", isDirectory: true).appendingPathComponent(fileName)
    }

    /// How long a record not handed over is left to the version that moves.
    public static let staleAfter: TimeInterval = 10 * 60

    /// Nothing left to remove.
    public var isEmpty: Bool {
        inputSource == nil && defaultsDomains.isEmpty && apps.isEmpty && launchAgents.isEmpty && keychainItems.isEmpty
            && loginKeys.isEmpty
    }

    /// Whether what it lists is the next version's to do now (`handedOver`, or stale).
    public func isHandedOver(now: Date = Date()) -> Bool {
        handedOver || now.timeIntervalSince(updated) > Self.staleAfter
    }

    /// The record at `url`; nil when there is none. Throws when it can't be read as one.
    public static func read(at url: URL) throws -> CleanupRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CleanupRecord.self, from: Data(contentsOf: url))
    }

    /// Written to `url` in one go (a file of the user's alone, 0600), `updated` set to now.
    public mutating func write(to url: URL) throws {
        updated = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        guard rename(temporary.path, url.path) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    /// The record at `url` deleted (none: nothing to do); false when it is still there.
    @discardableResult
    public static func remove(at url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        return !FileManager.default.fileExists(atPath: url.path)
    }
}
