import AllInOneIMECore
import Carbon
import Foundation
import Security

// What the move to this system identity left for the input method to finish (`IdentityHandover`), at each launch:
//
// 1. the cleanup record (`CleanupRecord`), once the version that moved has handed it over (or stopped): each step it
//    lists done with the identifiers it lists, those that succeed taken out of it, the record deleted once it is empty.
//    The login keychain's originals first (each only when its handover item is there and it is the key handed over),
//    then the input source, the defaults domains, the apps, the launch agents and the old group's keychain items;
//    nothing of this identity's is ever touched (`ownBundleIDs`, `KeySync.accessGroup`), an app only when its bundle ID
//    is one of the record's, a launch agent only when its label is under theirs;
// 2. the login keychain's keys handed over: each handover item imported into the login keychain, where the item is
//    created by this identity (its own access list: macOS never asks for it), read back, then the handover item deleted.
//    A key whose original the record still lists waits for it to go; an item there already that this identity reads is
//    its own (a key saved since, or an earlier import), kept, and the handover item deleted.
//
// While the version that moved is still at it (the record not handed over), nothing is done: tried again shortly. The
// code never names the identity before: everything it removes is the record's. Logged by service and account, never
// with a key.

/// What the record's steps do on this Mac (`SystemIdentityCleanup`; tests have their own), by the record's identifiers.
public protocol IdentityCleanupActions {
    /// `id` disabled and out of the user's input sources; true when it is neither afterwards.
    func disableInputSource(_ id: String) -> Bool
    /// The domain removed, and its file deleted once cfprefsd has emptied it; true when nothing is left in it.
    func removeDefaultsDomain(_ name: String) -> Bool
    /// The bundle ID of the app at `path`; nil when there is none there (or it doesn't say).
    func bundleID(ofAppAt path: String) -> String?
    /// The app at `path` unregistered from Launch Services and deleted; true when it is gone.
    func removeApp(at path: String) -> Bool
    /// The launch agent unloaded, and its property list deleted when its label is the agent's; true when both are gone.
    func removeLaunchAgent(_ agent: CleanupRecord.LaunchAgent) -> Bool
    /// Whether this process may use the keychain access group `group`.
    func isEntitled(to group: String) -> Bool
    /// The item deleted from `group`; true when it is gone.
    func deleteKeychainItem(_ item: CleanupRecord.KeychainItem, from group: String) -> Bool
}

/// The move's leftovers finished at launch (see above): `run`, or `start` in the background.
public struct IdentityFinish {
    public var record: URL
    public var actions: any IdentityCleanupActions
    /// The login keychain's keys of a service (`IdentityHandover.loginServices`), nothing asked.
    public var login: (String) -> APIKeys.Keychain
    /// The handover items of a service's keys, in this identity's access group.
    public var handover: (String) -> APIKeys.Keychain
    /// Whether this build can read the handover items (entitled to its access group): without, none is imported.
    public var handoverAvailable: Bool
    /// This identity's bundle IDs and keychain access group: never removed, whatever a record says.
    public var ownBundleIDs = [Updater.bundleID, Updater.settingsBundleID]
    public var ownKeychainGroup = KeySync.accessGroup
    public var say: (String) -> Void
    public var now: () -> Date = { Date() }

    public init(record: URL, actions: any IdentityCleanupActions, login: @escaping (String) -> APIKeys.Keychain,
                handover: @escaping (String) -> APIKeys.Keychain, handoverAvailable: Bool, say: @escaping (String) -> Void) {
        self.record = record
        self.actions = actions
        self.login = login
        self.handover = handover
        self.handoverAvailable = handoverAvailable
        self.say = say
    }

    /// The Mac's: the record in Application Support, the user's defaults, Text Input Sources, Launch Services, launchd,
    /// the login keychain and this identity's access group.
    public static func system(say: @escaping (String) -> Void) -> IdentityFinish {
        IdentityFinish(record: CleanupRecord.defaultURL, actions: SystemIdentityCleanup(), login: IdentityHandover.loginStore(service:),
                       handover: { IdentityHandover.handoverStore(group: KeySync.accessGroup, service: $0) },
                       handoverAvailable: APIKeys.Keychain.processIsEntitled, say: say)
    }

    public enum Outcome: Equatable, Sendable {
        /// The version that moved is still at it (the record isn't handed over): nothing done, tried again shortly.
        case waiting
        /// Done for this launch; `left`: something waits for the next (a step that failed, a key not imported).
        case done(left: Bool)
    }

    /// The record's steps, then the keys' import (see above).
    public func run() -> Outcome {
        var waiting: Set<LoginKey> = []
        var left = false
        switch readRecord() {
        case .absent:
            break
        case let .notYet(record):
            say("identity: the move's record isn't handed over yet (\(record.updated)); waiting")
            return .waiting
        case let .handedOver(record):
            if let remaining = finish(record) {
                waiting = Set(remaining.loginKeys)
                left = true
            }
        case .unknownFormat:
            left = true
        }
        if !importKeys(waiting: waiting) { left = true }
        return .done(left: left)
    }

    /// At launch, in the background: `run`, and while it is `waiting`, again every `interval` seconds, `attempts` times
    /// at most; then it waits for the next launch.
    public func start(queue: DispatchQueue = .global(qos: .utility), attempts: Int = 18, interval: TimeInterval = 10) {
        queue.async {
            for attempt in 1...max(attempts, 1) {
                guard run() == .waiting, attempt < attempts else { return }
                Thread.sleep(forTimeInterval: interval)
            }
        }
    }

    // MARK: - The record

    enum Found {
        case absent, unknownFormat
        case notYet(CleanupRecord)
        case handedOver(CleanupRecord)
    }

    /// The record, if there is one: one that can't be read is deleted (logged), one of a later layout left alone.
    func readRecord() -> Found {
        let found: CleanupRecord?
        do {
            found = try CleanupRecord.read(at: record)
        } catch {
            say("identity: \(record.path) can't be read (\(error)); deleted")
            CleanupRecord.remove(at: record)
            return .absent
        }
        guard let found else { return .absent }
        guard found.format == CleanupRecord.currentFormat else {
            say("identity: \(record.path) has another layout (\(found.format)); left as it is")
            return .unknownFormat
        }
        return found.isHandedOver(now: now()) ? .handedOver(found) : .notYet(found)
    }

    /// The record's steps (see above), each that succeeds taken out of it; the record deleted once it is empty, else
    /// written with what is left (returned).
    func finish(_ found: CleanupRecord) -> CleanupRecord? {
        var record = found
        let ids = Set(record.bundleIDs).subtracting(ownBundleIDs)
        // The reverse-DNS name the old identity's IDs share ("com.example." of "com.example.app"): its launch agents' labels.
        let prefixes = Set(ids.map { $0.split(separator: ".").prefix(2).joined(separator: ".") + "." }).filter { $0.count > 2 }
        let ours = Set(ownBundleIDs.map { $0.split(separator: ".").prefix(2).joined(separator: ".") + "." })

        record.loginKeys = record.loginKeys.filter { !removeOriginal($0) }

        if let id = record.inputSource {
            if !ids.contains(id) {
                say("cleanup: the input source \(id) isn't one of the record's apps; left")
                record.inputSource = nil
            } else if actions.disableInputSource(id) {
                say("cleanup: \(id) disabled and out of the input sources")
                record.inputSource = nil
            }
        }

        record.defaultsDomains = record.defaultsDomains.filter { domain in
            guard ids.contains(domain) else {
                say("cleanup: the defaults domain \(domain) isn't one of the record's apps; left")
                return false
            }
            guard actions.removeDefaultsDomain(domain) else { return true }
            say("cleanup: \(domain) removed")
            return false
        }

        record.apps = record.apps.filter { path in
            guard let id = actions.bundleID(ofAppAt: path) else { return false }  // gone
            guard ids.contains(id) else {
                say("cleanup: \(path) is \(id), not one of the record's apps; left")
                return false
            }
            guard actions.removeApp(at: path) else { return true }
            say("cleanup: removed \(path)")
            return false
        }

        record.launchAgents = record.launchAgents.filter { agent in
            guard prefixes.contains(where: { agent.label.hasPrefix($0) }), !ours.contains(where: { agent.label.hasPrefix($0) }) else {
                say("cleanup: the launch agent \(agent.label) isn't under the record's apps' names; left")
                return false
            }
            guard actions.removeLaunchAgent(agent) else { return true }
            say("cleanup: removed the launch agent \(agent.label)")
            return false
        }

        if let group = record.keychainGroup, !record.keychainItems.isEmpty {
            if group == ownKeychainGroup {
                say("cleanup: \(group) is this version's own keychain group; its items are left")
                record.keychainItems = []
            } else if !actions.isEntitled(to: group) {
                // Only the version that moved could reach them: they stay, unused (synced ones on every Mac).
                say("cleanup: this version isn't entitled to \(group): its \(record.keychainItems.count) item(s) stay there, unused")
                record.keychainItems = []
            } else {
                record.keychainItems = record.keychainItems.filter { item in
                    guard actions.deleteKeychainItem(item, from: group) else { return true }
                    say("cleanup: deleted from \(group): \(item.service)/\(item.account)\(item.synchronizable ? " (synced)" : "")")
                    return false
                }
            }
        }

        guard !record.isEmpty else {
            if CleanupRecord.remove(at: self.record) {
                say("cleanup: done; the move's record is deleted")
            } else {
                say("cleanup: done, but \(self.record.path) can't be deleted")
            }
            return nil
        }
        do {
            try record.write(to: self.record)
        } catch {
            say("cleanup: \(self.record.path) can't be written (\(error.localizedDescription))")
        }
        say("cleanup: left for the next launch: " + [record.inputSource.map { "input source \($0)" }, record.defaultsDomains.isEmpty ? nil : "\(record.defaultsDomains.count) defaults domain(s)",
                                                      record.apps.isEmpty ? nil : "\(record.apps.count) app(s)",
                                                      record.launchAgents.isEmpty ? nil : "\(record.launchAgents.count) launch agent(s)",
                                                      record.keychainItems.isEmpty ? nil : "\(record.keychainItems.count) keychain item(s)",
                                                      record.loginKeys.isEmpty ? nil : "\(record.loginKeys.count) login keychain key(s)"]
            .compactMap { $0 }.joined(separator: ", "))
        return record
    }

    /// A login keychain original the record lists: deleted when its handover item is there and it is still the key handed
    /// over (its save time the handover item's), so that the handover item can be imported in its place. True when it is
    /// out of the record: deleted, gone already, or kept (no handover item for it, or a key saved again since, whose
    /// handover item is deleted then).
    func removeOriginal(_ key: LoginKey) -> Bool {
        guard IdentityHandover.loginServices.contains(key.service) else { return true }
        let (login, handover) = (self.login(key.service), self.handover(key.service))
        guard let original = login.attributes(key.account) else { return true }
        guard handoverAvailable, let handed = handover.attributes(key.account) else {
            say("cleanup: \(key) has no handover item: left where it is")
            return true
        }
        guard IdentityHandover.same(original.changed, handed.saved) else {
            say("cleanup: \(key) was saved again since it was handed over: kept, its handover item deleted")
            _ = handover.delete(key.account)
            return true
        }
        let status = login.delete(key.account)
        guard status == .ok || status == .notFound else {
            say("cleanup: \(key) can't be deleted from the login keychain (\(status.code)); tried again at the next launch")
            return false
        }
        say("cleanup: \(key) deleted from the login keychain (its handover item takes its place)")
        return true
    }

    // MARK: - The keys

    /// Each handover item imported into the login keychain (see above), except those of `waiting` (their originals are
    /// still there). False when one is left for the next launch.
    func importKeys(waiting: Set<LoginKey>) -> Bool {
        guard handoverAvailable else { return true }
        var imported: [LoginKey] = [], kept: [LoginKey] = []
        var complete = true
        for service in IdentityHandover.loginServices {
            let (login, handover) = (self.login(service), self.handover(service))
            let accounts: [String]
            do {
                accounts = try handover.listedAccounts()
            } catch {
                say("keys: the handover items of \(service) can't be listed (\(error)); tried again at the next launch")
                complete = false
                continue
            }
            for account in accounts {
                let key = LoginKey(service: service, account: account)
                guard !waiting.contains(key) else {
                    say("keys: \(key) waits for its original to be deleted")
                    complete = false
                    continue
                }
                guard let attributes = handover.attributes(account), let value = handover.read(account), !value.isEmpty else {
                    say("keys: \(key)'s handover item can't be read; tried again at the next launch")
                    complete = false
                    continue
                }
                if login.attributes(account) != nil {
                    // An item there already: this identity's own if it reads it without asking (a key saved since, or an
                    // earlier import), else one it would have to ask for, which it never writes over.
                    guard let ours = login.read(account) else {
                        say("keys: the login keychain has an item for \(key) this version can't read without asking; its handover item waits")
                        complete = false
                        continue
                    }
                    if ours != value { kept.append(key) }
                } else {
                    let status = login.adding(account, value, attributes.label ?? APIKeys.label(account: account),
                                              attributes.comment ?? "", attributes.ending ?? APIKeys.ending(of: value), attributes.saved)
                    guard status == .ok, login.read(account) == value else {
                        if status == .ok { _ = login.delete(account) }
                        say("keys: \(key) not imported (\(status.code)); tried again at the next launch")
                        complete = false
                        continue
                    }
                    imported.append(key)
                }
                _ = handover.delete(account)
            }
        }
        if !imported.isEmpty { say("keys: imported into the login keychain: \(imported.map(\.description).joined(separator: ", "))") }
        if !kept.isEmpty { say("keys: a key saved since is kept: \(kept.map(\.description).joined(separator: ", "))") }
        return complete
    }
}

// MARK: - The Mac's

/// The record's steps on this Mac: Text Input Sources (on the main thread), the user's defaults, Launch Services and
/// launchd, the data protection keychain.
public struct SystemIdentityCleanup: IdentityCleanupActions, Sendable {
    public var preferences = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences", isDirectory: true)

    public init() {}

    static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public func disableInputSource(_ id: String) -> Bool {
        guard Thread.isMainThread else { return DispatchQueue.main.sync { disableInputSource(id) } }
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        var done = true
        for source in (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? [] {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()) else { continue }
            done = TISDisableInputSource(source) == noErr && done
        }
        let domain = InputSourceList.domain as CFString
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let list = CFPreferencesCopyValue(InputSourceList.key as CFString, domain, kCFPreferencesCurrentUser,
                                          kCFPreferencesAnyHost) as? [[String: Any]]
        if let updated = InputSourceList.removing(id, from: list) {
            CFPreferencesSetValue(InputSourceList.key as CFString, updated as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            done = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) && done
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, userInfo: nil, deliverImmediately: true)
        }
        return done
    }

    /// Removed with `removePersistentDomain`; its file, which cfprefsd empties a few seconds later, deleted once it is
    /// empty (15 seconds at most), never one with anything in it.
    public func removeDefaultsDomain(_ name: String) -> Bool {
        UserDefaults.standard.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        CFPreferencesAppSynchronize(name as CFString)
        guard UserDefaults.standard.persistentDomain(forName: name)?.isEmpty ?? true else { return false }
        let file = preferences.appendingPathComponent(name + ".plist")
        let deadline = Date().addingTimeInterval(15)
        while FileManager.default.fileExists(atPath: file.path) {
            if (NSDictionary(contentsOf: file) as? [String: Any])?.isEmpty == true { try? FileManager.default.removeItem(at: file) }
            guard FileManager.default.fileExists(atPath: file.path), Date() < deadline else { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return true
    }

    public func bundleID(ofAppAt path: String) -> String? {
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
        return NSDictionary(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String ?? ""
    }

    public func removeApp(at path: String) -> Bool {
        _ = Self.run(Self.lsregister, ["-u", path])
        try? FileManager.default.removeItem(atPath: path)
        return (try? FileManager.default.attributesOfItem(atPath: path)) == nil
    }

    public func removeLaunchAgent(_ agent: CleanupRecord.LaunchAgent) -> Bool {
        let target = "gui/\(getuid())/\(agent.label)"
        if Self.run("/bin/launchctl", ["print", target]) == 0 { _ = Self.run("/bin/launchctl", ["bootout", target]) }
        if let plist = agent.plist, NSDictionary(contentsOfFile: plist)?["Label"] as? String == agent.label {
            try? FileManager.default.removeItem(atPath: plist)
        }
        let plistGone = agent.plist.map { NSDictionary(contentsOfFile: $0)?["Label"] as? String != agent.label } ?? true
        return plistGone && Self.run("/bin/launchctl", ["print", target]) != 0
    }

    public func isEntitled(to group: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) else { return false }
        return (value as? [String])?.contains(group) == true
    }

    public func deleteKeychainItem(_ item: CleanupRecord.KeychainItem, from group: String) -> Bool {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecUseDataProtectionKeychain as String: true,
                                    kSecAttrAccessGroup as String: group, kSecAttrService as String: item.service,
                                    kSecAttrAccount as String: item.account,
                                    kSecAttrSynchronizable as String: item.synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!] as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// A tool's exit status (its output dropped); -1 when it can't be started.
    static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
