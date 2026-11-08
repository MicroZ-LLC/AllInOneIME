import AllInOneIMECore
import AppKit
import Carbon
import Foundation
import Security

// 0.7.1, the bridge: AllInOneIME moves from its old system identity (`AppIdentity.legacy`: the bundle IDs it has had
// since its first name, their UserDefaults domains, the keychain access group, the input source) to its own
// (`AppIdentity.allInOneIME`, 0.7.2 on). 0.7.1 is the one version whose code knows both: 0.7.2 knows only its own and
// relies on this having been done. It runs when the update helper installs an update with the new identity
// (`--apply-update`), and as `--migrate-identity APP`, which the 0.7.2 installer calls on an installed 0.7.1. In order:
//
// a. the keys of the old UserDefaults domains (the input method's, AllInOneIME Settings') that the new domains lack are
//    copied into them and read back;
// b. the items of the old keychain access group (synced through iCloud Keychain or not) are copied into the new group
//    and read back (the bridge's entitlements list both groups); and each key of the login keychain (key sync off, the
//    Cloud session, the replaced copies: in no access group, readable without asking only by the identity that saved
//    it) is copied into the new group as a handover item (`IdentityHandover`), read back: the new identity imports it
//    at launch, so that macOS never asks it to allow one;
// c. what the cleanup (d) will remove is written down (`CleanupRecord`, ~/Library/Application Support/AllInOneIME), then
//    the apps are swapped as an update swaps them (`MigrationSwitch`), the new input method has to start (`--version`),
//    and its input source is registered, enabled if the old one was and selected if the old one was;
// d. only then is the old identity cleaned up: its input source disabled and taken out of the user's input sources, the
//    previous apps deleted, its domains and keychain items deleted (synced ones too: another Mac reads its keys once it
//    has updated as well), the login keychain's originals of the keys handed over deleted, and any other copy of the old
//    apps and any launch agent with an old label removed. The record follows each step, and goes once all are done.
//
// A failure up to the end of c puts everything back: the keys and items it copied (handover items too) are taken out of
// the new domains and group again, the record deleted, the previous apps go back (`MigrationSwitch.rollBack`), and the
// old input source is selected again if it was. A cleanup step that fails is tried again a few times, then logged and
// left (`Report.pending`); it never undoes the switch, and the record keeps it, handed over: the new version does it at
// its next launch, by the identifiers the record lists (it can't name the old identity), as another run of this one
// would, found by looking (it copies what the new identity still lacks, then cleans up what is still there). Logged by
// key name, service and account, never with a value or a key.

/// One identity's names, as the migration uses them.
public struct MigrationNames: Equatable, Sendable {
    public var apps: AppIdentity
    public var keychainGroup: String

    public init(apps: AppIdentity, keychainGroup: String) {
        self.apps = apps
        self.keychainGroup = keychainGroup
    }

    /// Its preferences: the input method's domain and AllInOneIME Settings'.
    public var domains: [String] { [apps.inputMethod, apps.settings] }
    /// Its input source's ID: the input method's bundle ID.
    public var inputSource: String { apps.inputMethod }
}

/// The user defaults domains, by name.
public protocol MigrationDefaults {
    /// `name`'s keys and values; nil when there is no such domain.
    func domain(_ name: String) -> [String: Any]?
    /// `value` under `key` in `domain`; false when the domain can't be written.
    func set(_ value: Any, forKey key: String, in domain: String) -> Bool
    func remove(_ key: String, from domain: String)
    /// What was written to `domain` saved, before the apps change.
    func flush(_ domain: String)
    func removeDomain(_ name: String)
    /// The files `domains` left once removed, deleted once cfprefsd has emptied them (never one with anything in it):
    /// the names whose file went.
    func deleteEmptiedFiles(of domains: [String]) -> [String]
}

/// A keychain item, by what tells it apart in its access group. Logged as it is: never its key.
public struct MigrationKeychainItem: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var service: String
    public var account: String
    /// Synced through iCloud Keychain.
    public var synchronizable: Bool

    public init(service: String, account: String, synchronizable: Bool) {
        self.service = service
        self.account = account
        self.synchronizable = synchronizable
    }

    public static func < (a: Self, b: Self) -> Bool {
        (a.service, a.account, a.synchronizable ? 1 : 0) < (b.service, b.account, b.synchronizable ? 1 : 0)
    }

    public var description: String { "\(service)/\(account)\(synchronizable ? " (synced)" : "")" }
}

/// An item's key and the attributes copied with it (label, comment, description, …: `SystemKeychain.copied`). Never
/// logged.
public struct MigrationKeychainValue {
    public var data: Data
    public var attributes: [String: Any]

    public init(data: Data, attributes: [String: Any] = [:]) {
        self.data = data
        self.attributes = attributes
    }
}

/// The data protection keychain's generic passwords, by access group.
public protocol MigrationKeychain {
    /// Whether this process may use `group`: its `keychain-access-groups` entitlement lists it.
    func isEntitled(to group: String) -> Bool
    /// Every item of `group`, synced or not; throws when they can't be listed (never taken for none).
    func items(in group: String) throws -> [MigrationKeychainItem]
    /// `item`'s key and attributes in `group`; nil when there is no such item or it can't be read.
    func value(of item: MigrationKeychainItem, in group: String) -> MigrationKeychainValue?
    /// A new item in `group` (never one written over: `errSecDuplicateItem`).
    func add(_ item: MigrationKeychainItem, _ value: MigrationKeychainValue, to group: String) -> OSStatus
    func delete(_ item: MigrationKeychainItem, from group: String) -> OSStatus
}

public struct MigrationInputSourceState: Equatable, Sendable {
    public var registered = false
    /// Enabled, or in the user's input sources (`InputSourceList`).
    public var enabled = false
    public var selected = false

    public init(registered: Bool = false, enabled: Bool = false, selected: Bool = false) {
        self.registered = registered
        self.enabled = enabled
        self.selected = selected
    }
}

/// Text Input Sources, by input source ID.
public protocol MigrationInputSources {
    func state(of id: String) -> MigrationInputSourceState
    /// Registers the input method at `bundle`; true once `id` is listed.
    func register(_ bundle: URL, id: String) -> Bool
    /// Enabled and in the user's input sources (which Ctrl+Space goes through).
    func enable(_ id: String) -> Bool
    func select(_ id: String) -> Bool
    /// Disabled and out of the user's input sources; true when it is neither afterwards.
    func disable(_ id: String) -> Bool
}

/// A launch agent with an old label: loaded, or its property list (or both).
public struct MigrationLaunchAgent: Hashable, Sendable, CustomStringConvertible {
    public var label: String
    public var plist: URL?

    public init(label: String, plist: URL?) {
        self.label = label
        self.plist = plist
    }

    public var description: String { label }
}

/// What else the old identity left: copies of its apps besides the installed ones, and launch agents.
public protocol MigrationLeftovers {
    func oldApps() -> [URL]
    /// Unregistered and deleted; true when it is gone.
    func remove(app: URL) -> Bool
    func oldLaunchAgents() -> [MigrationLaunchAgent]
    /// Unloaded and its property list deleted; true when both are gone.
    func remove(agent: MigrationLaunchAgent) -> Bool
}

/// Step c's apps: the installed ones swapped for the new ones (`AppsSwitch`; tests have their own).
public protocol MigrationSwitch: AnyObject {
    /// Where the input method is installed: the new one is registered there after the swap, the old one again after a
    /// rollback.
    var inputMethod: URL { get }
    /// Where the installed apps are (the input method's and AllInOneIME Settings').
    var installed: [URL] { get }
    /// Where the previous apps wait once swapped, until `commit` deletes them (before the swap: where they will).
    var previousApps: [URL] { get }
    /// The installed input method has the new identity already and starts: an earlier run switched.
    var isSwitched: Bool { get }
    /// The new apps in place of the installed ones, and the new input method starts; throws once the previous apps are
    /// back (or `BundleSwap.Failure.notRestored`).
    func perform() throws
    /// After `perform`: the previous apps back. Throws when they can't be put back.
    func rollBack(reason: String) throws
    /// The previous apps deleted: the switch stays.
    func commit()
}

public struct MigrationError: Error, LocalizedError, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The move itself (see above): `run`.
public struct Migration {
    public static let old = MigrationNames(apps: .legacy, keychainGroup: KeySync.accessGroup)
    public static let new = MigrationNames(apps: .allInOneIME, keychainGroup: "9SR8N3UD5Y.com.allinoneime.shared")
    /// What the old identity's other labels start with (launch agents: `make realtest-when-unlocked`'s).
    public static let oldLabelPrefix = "com.aipinyin."
    /// What `--migrate-identity --check` prints: the 0.7.2 installer asks an installed AllInOneIME with it whether it can
    /// move itself (0.7.0 and earlier answer that the option is unknown).
    public static let checkLine = "migrate-identity: 1"

    /// The cleanup's steps (d), in order.
    public enum Cleanup: String, CaseIterable, Sendable {
        case inputSource = "old input source"
        case previousApps = "previous apps"
        case defaults = "old defaults domains"
        case keychain = "old keychain items"
        case loginKeys = "login keychain keys handed over"
        case otherApps = "other copies of the old apps"
        case launchAgents = "launch agents with an old label"
    }

    /// Whether the input method whose Info.plist is `info` (the one installed) has the new identity: a version newer than
    /// this one, which the installer and `make install` of this one never replace (that would go back to the old
    /// identity, its keys and settings left with the new one).
    public static func newIdentityInstalled(info: [String: Any]?) -> Bool {
        info?["CFBundleIdentifier"] as? String == new.apps.inputMethod
    }

    public struct Report: Sendable {
        /// The new identity is installed (by this run or an earlier one).
        public var switched = false
        /// Why it wasn't, everything put back; nil once switched.
        public var error: String?
        /// The previous apps couldn't be put back (`BundleSwap.Failure.notRestored`): they wait where the error says.
        public var notRestored = false
        public var copiedKeys = 0
        public var copiedItems = 0
        /// Login keychain keys handed over (`IdentityHandover`).
        public var handedOver = 0
        /// Cleanup steps left for the next run.
        public var pending: [Cleanup] = []
        public var lines: [String] = []
    }

    public var defaults: any MigrationDefaults
    public var keychain: any MigrationKeychain
    /// The login keychain's keys of a service (`IdentityHandover.loginServices`), read and deleted without asking.
    public var login: (String) -> APIKeys.Keychain
    /// The handover items, in the new group, of the keys of a service (`IdentityHandover.handoverStore`).
    public var handover: (String) -> APIKeys.Keychain
    public var inputSources: any MigrationInputSources
    public var leftovers: any MigrationLeftovers
    /// Where the cleanup record goes (`CleanupRecord`); nil: none.
    public var record: URL?
    /// Each line as it's logged (the update helper's log, the command's output).
    public var say: (String) -> Void
    /// How often a cleanup step is tried, and the wait between two tries.
    public var attempts = 3
    public var pause: () -> Void = { Thread.sleep(forTimeInterval: 0.5) }

    public init(defaults: any MigrationDefaults, keychain: any MigrationKeychain, login: @escaping (String) -> APIKeys.Keychain,
                handover: @escaping (String) -> APIKeys.Keychain, inputSources: any MigrationInputSources,
                leftovers: any MigrationLeftovers, record: URL?, say: @escaping (String) -> Void) {
        self.defaults = defaults
        self.keychain = keychain
        self.login = login
        self.handover = handover
        self.inputSources = inputSources
        self.leftovers = leftovers
        self.record = record
        self.say = say
    }

    /// The Mac's own: the user's defaults, the data protection keychain, Text Input Sources, ~/Applications,
    /// ~/Library/Input Methods and the user's launch agents. Main thread (Text Input Sources).
    public static func system(say: @escaping (String) -> Void) -> Migration {
        // Bundle.main as this process started: after the swap, the path it started from holds the new app.
        _ = Bundle.main.bundleIdentifier
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Migration(defaults: SystemDefaults(), keychain: SystemKeychain(), login: IdentityHandover.loginStore(service:),
                         handover: { IdentityHandover.handoverStore(group: new.keychainGroup, service: $0) },
                         inputSources: SystemInputSources(),
                         leftovers: FolderLeftovers(apps: [home.appendingPathComponent("Library/Input Methods", isDirectory: true),
                                                           home.appendingPathComponent("Applications", isDirectory: true)],
                                                    launchAgents: home.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
                                                    otherPlists: [home.appendingPathComponent("Library/Logs/AllInOneIME/realtest-watch.plist")],
                                                    system: true),
                         record: CleanupRecord.defaultURL, say: say)
    }

    /// A test install's (`--target-dir ROOT`, `make update-test`): files in `root` stand for the defaults
    /// (Preferences/<domain>.plist), the keychain (Keychain/<group>.plist, the login keychain Keychain/login.plist), the
    /// input sources (InputSources.plist) and the launch agents (LaunchAgents/), and the record is ROOT/identity-cleanup.json;
    /// nothing of the user's is read or changed.
    public static func test(root: URL, say: @escaping (String) -> Void) -> Migration {
        let keychain = root.appendingPathComponent("Keychain", isDirectory: true)
        var migration = Migration(defaults: FileDefaults(folder: root.appendingPathComponent("Preferences", isDirectory: true)),
                                  keychain: FileKeychain(folder: keychain),
                                  login: { IdentityHandover.fileStore(keychain.appendingPathComponent("login.plist"), service: $0) },
                                  handover: {
                                      IdentityHandover.fileStore(keychain.appendingPathComponent(new.keychainGroup + ".plist"),
                                                                 service: IdentityHandover.handoverService(for: $0))
                                  },
                                  inputSources: FileInputSources(file: root.appendingPathComponent("InputSources.plist")),
                                  leftovers: FolderLeftovers(apps: [root.appendingPathComponent("Input Methods", isDirectory: true),
                                                                    root.appendingPathComponent("Applications", isDirectory: true)],
                                                             launchAgents: root.appendingPathComponent("LaunchAgents", isDirectory: true),
                                                             otherPlists: [], system: false),
                                  record: root.appendingPathComponent(CleanupRecord.fileName), say: say)
        migration.pause = {}
        return migration
    }

    // MARK: - The run

    /// What a run copied before its switch: taken out again if the switch doesn't happen.
    struct Added {
        var keys: [String: [String]] = [:]
        var items: [MigrationKeychainItem] = []
        var handedOver: [LoginKey] = []
    }

    /// a–d with `switcher`'s apps (see above). Never throws: the report says how it went.
    public func run(_ switcher: any MigrationSwitch) -> Report {
        var report = Report()
        func log(_ line: String) {
            report.lines.append(line)
            say(line)
        }
        let (old, new) = (Self.old, Self.new)
        log("identity: \(old.apps.inputMethod) → \(new.apps.inputMethod)")

        if switcher.isSwitched {
            // An earlier run switched: what the new identity still lacks is copied (in the cleanup's own steps), and what
            // is left of the old one cleaned up.
            log("identity: the input method installed has the new identity already; cleaning up what is left of the old one")
            report.switched = true
            report.pending = cleanUp(switcher, log: log)
            return report
        }

        var added = Added()
        var notRestored = false
        do {
            report.copiedKeys = try copyDefaults(&added, log: log)
            report.copiedItems = try copyKeychain(&added, log: log)
            report.handedOver = try handOverLoginKeys(&added, log: log)
            // What the cleanup will remove, written down before anything is: what the new version does if it can't.
            write(plan(switcher), log: log)
            try switchApps(switcher, log: log, notRestored: &notRestored)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            log("✗ \(reason)")
            undo(added, log: log)
            report.error = reason
            report.notRestored = notRestored
            return report
        }
        report.switched = true
        log("identity: switched; \(report.copiedKeys) defaults keys and \(report.copiedItems) keychain items carried over, "
            + "\(report.handedOver) login keychain keys handed over")
        report.pending = cleanUp(switcher, log: log)
        return report
    }

    // MARK: a. Defaults

    /// The keys of the old domains the new ones lack, copied and read back; each one recorded in `added` as it is written.
    func copyDefaults(_ added: inout Added, log: (String) -> Void) throws -> Int {
        var copied = 0
        for (from, to) in zip(Self.old.domains, Self.new.domains) {
            guard let values = defaults.domain(from), !values.isEmpty else {
                log("defaults: nothing in \(from)")
                continue
            }
            let there = defaults.domain(to) ?? [:]
            let missing = values.keys.filter { there[$0] == nil }.sorted()
            for key in missing {
                guard defaults.set(values[key]!, forKey: key, in: to) else { throw MigrationError("defaults: \(to) can't be written") }
                added.keys[to, default: []].append(key)
            }
            if !missing.isEmpty { defaults.flush(to) }
            let now = defaults.domain(to) ?? [:]
            if let wrong = missing.first(where: { !Self.same(now[$0], values[$0]) }) {
                throw MigrationError("defaults: \(wrong) doesn't read back from \(to) as written")
            }
            copied += missing.count
            log("defaults: \(missing.count) of \(values.count) keys copied from \(from) to \(to)"
                + (missing.isEmpty ? "" : ": \(missing.joined(separator: ", "))"))
        }
        return copied
    }

    /// Two property list values alike.
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return (a as AnyObject).isEqual(b as AnyObject)
    }

    // MARK: b. Keychain

    /// Every item of the old group copied into the new one and read back; each one recorded in `added` once written. An
    /// item the new group has already is left: the same key counts as copied; another one (another Mac moved first, its
    /// key synced here) is kept, and the old item stays where it is (never deleted by the cleanup), logged.
    func copyKeychain(_ added: inout Added, log: (String) -> Void) throws -> Int {
        let (from, to) = (Self.old.keychainGroup, Self.new.keychainGroup)
        guard keychain.isEntitled(to: from) else {
            log("keychain: this build isn't entitled to \(from) (no provisioning profile): no items of it to copy")
            return 0
        }
        let items: [MigrationKeychainItem]
        do {
            items = try keychain.items(in: from)
        } catch {
            throw MigrationError("keychain: the items of \(from) can't be listed (\(error))")
        }
        guard !items.isEmpty else {
            log("keychain: no items in \(from)")
            return 0
        }
        guard keychain.isEntitled(to: to) else {
            throw MigrationError("keychain: this build isn't entitled to \(to): the \(items.count) items of \(from) can't be carried over")
        }
        var copied = 0, there = 0
        for item in items {
            guard let value = keychain.value(of: item, in: from) else { throw MigrationError("keychain: \(item) can't be read") }
            if let theirs = keychain.value(of: item, in: to) {
                if theirs.data == value.data {
                    there += 1
                } else {
                    log("keychain: \(item): the new group has another key for it already; that one is kept, and the old one left")
                }
                continue
            }
            let status = keychain.add(item, value, to: to)
            guard status == errSecSuccess else { throw MigrationError("keychain: \(item) not copied (\(status))") }
            added.items.append(item)
            guard keychain.value(of: item, in: to)?.data == value.data else {
                throw MigrationError("keychain: \(item)'s copy doesn't read back as written")
            }
            copied += 1
        }
        log("keychain: \(copied) of \(items.count) items copied from \(from) to \(to)"
            + (there > 0 ? " (\(there) there already)" : "") + ": \(items.map(\.description).joined(separator: ", "))")
        return copied
    }

    /// The login keychain's keys (`IdentityHandover.loginServices`), each read without asking (this identity saved them)
    /// and copied into the new group as a handover item with its label, comment, ending and save time (`changed`), then
    /// read back; each recorded in `added` once written. A handover item there already for the same key counts as
    /// handed over; another one (an earlier run's that didn't get taken out, the key saved again since) is replaced. A
    /// key that can't be read without asking (another build saved it) is left where it is: the new identity asks once
    /// for it. Without the new group's entitlement (a build without the profile) nothing is handed over.
    func handOverLoginKeys(_ added: inout Added, log: (String) -> Void) throws -> Int {
        let group = Self.new.keychainGroup
        guard keychain.isEntitled(to: group) else {
            log("login keychain: this build isn't entitled to \(group): its keys stay where they are (the new identity asks once for each)")
            return 0
        }
        var handed: [LoginKey] = [], there = 0
        for service in IdentityHandover.loginServices {
            let (login, handover) = (self.login(service), self.handover(service))
            let accounts: [String]
            do {
                accounts = try login.listedAccounts()
            } catch {
                throw MigrationError("login keychain: the keys of \(service) can't be listed (\(error))")
            }
            for account in accounts {
                let key = LoginKey(service: service, account: account)
                guard let attributes = login.attributes(account) else { continue }  // gone meanwhile
                guard let value = login.read(account), !value.isEmpty else {
                    log("login keychain: \(key) can't be read without asking: left where it is (the new identity asks once for it)")
                    continue
                }
                if handover.read(account) == value,
                   IdentityHandover.same(handover.attributes(account)?.saved, attributes.changed) {
                    there += 1
                    continue
                }
                if handover.attributes(account) != nil { _ = handover.delete(account) }  // an earlier run's, out of date
                let status = handover.adding(account, value, attributes.label ?? APIKeys.label(account: account),
                                             attributes.comment ?? "", attributes.ending ?? APIKeys.ending(of: value),
                                             attributes.changed)
                guard status == .ok else { throw MigrationError("login keychain: \(key) not handed over (\(status.code))") }
                added.handedOver.append(key)
                guard handover.read(account) == value else {
                    throw MigrationError("login keychain: \(key)'s handover item doesn't read back as written")
                }
                handed.append(key)
            }
        }
        log("login keychain: \(handed.count) keys handed over to \(group)" + (there > 0 ? " (\(there) there already)" : "")
            + (handed.isEmpty ? "" : ": \(handed.map(\.description).joined(separator: ", "))"))
        return handed.count
    }

    // MARK: c. The record and the switch

    /// What the cleanup (d) would remove now, found by looking (its steps' own lists, `planned`), handed over or not.
    func plan(_ switcher: any MigrationSwitch, handedOver: Bool = false) -> CleanupRecord {
        var record = CleanupRecord()
        record.handedOver = handedOver
        record.bundleIDs = [Self.old.apps.inputMethod, Self.old.apps.settings]
        record.keychainGroup = Self.old.keychainGroup
        for step in Cleanup.allCases { planned(step, switcher, into: &record) }
        return record
    }

    /// `step`'s part of the record, as it is now (found by looking): what the step would remove.
    func planned(_ step: Cleanup, _ switcher: any MigrationSwitch, into record: inout CleanupRecord) {
        let (old, new) = (Self.old, Self.new)
        switch step {
        case .inputSource:
            record.inputSource = old.inputSource
        case .previousApps:
            let paths = Set(switcher.previousApps.map(\.path))
            record.apps = record.apps.filter { !paths.contains($0) } + switcher.previousApps.map(\.path)
        case .defaults:
            record.defaultsDomains = old.domains.filter { defaults.domain($0) != nil }
        case .keychain:
            // The items the step deletes: all but those the new group has another key for (kept).
            let items = keychain.isEntitled(to: old.keychainGroup) ? ((try? keychain.items(in: old.keychainGroup)) ?? []) : []
            record.keychainItems = items.filter { item in
                guard let theirs = keychain.value(of: item, in: new.keychainGroup) else { return true }
                return theirs.data == keychain.value(of: item, in: old.keychainGroup)?.data
            }.map { CleanupRecord.KeychainItem(service: $0.service, account: $0.account, synchronizable: $0.synchronizable) }
        case .loginKeys:
            // The originals whose handover item holds the same key.
            record.loginKeys = IdentityHandover.loginServices.flatMap { service -> [LoginKey] in
                let (login, handover) = (self.login(service), self.handover(service))
                return ((try? login.listedAccounts()) ?? []).filter { account in
                    guard let value = login.read(account), !value.isEmpty else { return false }
                    return handover.read(account) == value
                }.map { LoginKey(service: service, account: $0) }
            }
        case .otherApps:
            let installed = Set(switcher.installed.map { $0.standardizedFileURL.path })
            let previous = Set(switcher.previousApps.map(\.path))
            let others = leftovers.oldApps().map { $0.standardizedFileURL.path }.filter { !installed.contains($0) }
            record.apps = record.apps.filter { previous.contains($0) } + others
        case .launchAgents:
            record.launchAgents = leftovers.oldLaunchAgents().map { CleanupRecord.LaunchAgent(label: $0.label, plist: $0.plist?.path) }
        }
    }

    /// `step` done: its part of the record emptied.
    static func cleared(_ step: Cleanup, _ switcher: any MigrationSwitch, in record: inout CleanupRecord) {
        switch step {
        case .inputSource: record.inputSource = nil
        case .previousApps:
            let paths = Set(switcher.previousApps.map(\.path))
            record.apps.removeAll { paths.contains($0) }
        case .defaults: record.defaultsDomains = []
        case .keychain: record.keychainItems = []
        case .loginKeys: record.loginKeys = []
        case .otherApps:
            let previous = Set(switcher.previousApps.map(\.path))
            record.apps.removeAll { !previous.contains($0) }
        case .launchAgents: record.launchAgents = []
        }
    }

    /// The record written (`record`), or deleted when there is nothing left in it and it is handed over (all done).
    /// A record that can't be written is logged: the cleanup goes on (only a step it leaves would need it).
    func write(_ value: CleanupRecord, log: (String) -> Void) {
        guard let url = record else { return }
        if value.isEmpty && value.handedOver {
            if !CleanupRecord.remove(at: url) { log("cleanup record: \(url.path) can't be deleted") }
            return
        }
        var value = value
        do {
            try value.write(to: url)
        } catch {
            log("cleanup record: \(url.path) can't be written (\(error.localizedDescription))")
        }
    }

    /// The record deleted: the switch didn't happen, nothing of the old identity is to go.
    func removeRecord(log: (String) -> Void) {
        guard let url = record, FileManager.default.fileExists(atPath: url.path) else { return }
        if !CleanupRecord.remove(at: url) { log("cleanup record: \(url.path) can't be deleted") }
    }

    /// The apps swapped and the new input method started (`switcher`), then its input source registered, enabled if the
    /// old one was and selected if it was. A failure after the swap puts the previous apps back and the old input source
    /// as it was, then throws.
    func switchApps(_ switcher: any MigrationSwitch, log: (String) -> Void, notRestored: inout Bool) throws {
        let (old, new) = (Self.old.inputSource, Self.new.inputSource)
        let before = inputSources.state(of: old)
        log("input source: \(old) registered \(before.registered), enabled \(before.enabled), selected \(before.selected)")
        do {
            try switcher.perform()
        } catch {
            if error is BundleSwap.Failure { notRestored = true }
            throw error
        }
        log("apps: swapped; the new input method starts")
        do {
            guard inputSources.register(switcher.inputMethod, id: new) else {
                throw MigrationError("input source: \(new) didn't appear once registered")
            }
            if before.enabled, !inputSources.enable(new) { throw MigrationError("input source: \(new) couldn't be enabled") }
            if before.selected, !inputSources.select(new) {
                log("input source: \(new) couldn't be selected; Ctrl+Space or the input menu switches to it")
            }
            log("input source: \(new) registered" + (before.enabled ? ", enabled" : "") + (before.selected ? ", selected" : ""))
        } catch {
            log("rolling back: \((error as? LocalizedError)?.errorDescription ?? String(describing: error))")
            _ = inputSources.disable(new)
            do {
                try switcher.rollBack(reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
            } catch let failure {
                notRestored = true
                throw failure
            }
            _ = inputSources.register(switcher.inputMethod, id: old)
            if before.selected { _ = inputSources.select(old) }
            log("apps: the previous ones are back")
            throw error
        }
    }

    /// The copies of a run whose switch didn't happen taken out again: the keys it added to the new domains (a domain
    /// left empty removed), the items it added to the new group and the handover items it wrote; and the record deleted.
    func undo(_ added: Added, log: (String) -> Void) {
        for (domain, keys) in added.keys {
            for key in keys { defaults.remove(key, from: domain) }
            if defaults.domain(domain)?.isEmpty ?? false { defaults.removeDomain(domain) } else { defaults.flush(domain) }
        }
        var left: [String] = []
        for item in added.items {
            let status = keychain.delete(item, from: Self.new.keychainGroup)
            if status != errSecSuccess && status != errSecItemNotFound { left.append(item.description) }
        }
        for key in added.handedOver {
            let status = handover(key.service).delete(key.account)
            if status != .ok && status != .notFound { left.append(IdentityHandover.handoverService(for: key.service) + "/" + key.account) }
        }
        let keys = added.keys.values.reduce(0) { $0 + $1.count }
        let items = added.items.count + added.handedOver.count
        if keys > 0 || items > 0 {
            log("undone: \(keys) defaults keys and \(items - left.count) keychain items copied are taken out again"
                + (left.isEmpty ? "" : "; not taken out: \(left.joined(separator: ", "))"))
        }
        removeRecord(log: log)
    }

    // MARK: d. Cleanup

    /// Each step (`Cleanup`) tried until it's done, `attempts` times at most; those left (logged) are returned. The
    /// record follows: written with what is left before the first step (found by looking), each step's part emptied once
    /// it is done (found by looking again when it isn't); deleted at the end when nothing is left, else handed over to the
    /// new version.
    func cleanUp(_ switcher: any MigrationSwitch, log: (String) -> Void) -> [Cleanup] {
        var pending: [Cleanup] = []
        var record = plan(switcher)
        write(record, log: log)
        for step in Cleanup.allCases {
            var done = false
            for attempt in 1...max(attempts, 1) where !done {
                if attempt > 1 { pause() }
                done = cleanUp(step, switcher, log: log)
            }
            if done {
                Self.cleared(step, switcher, in: &record)
            } else {
                pending.append(step)
                planned(step, switcher, into: &record)
                log("cleanup: \(step.rawValue) not done; left for the new version's next launch (or the next run of --migrate-identity)")
            }
            write(record, log: log)
        }
        if !pending.contains(.defaults) {
            // The removed domains' files, once cfprefsd has emptied them (a few seconds): nothing named after them is left.
            let deleted = defaults.deleteEmptiedFiles(of: Self.old.domains)
            if !deleted.isEmpty { log("cleanup: the emptied files of \(deleted.joined(separator: ", ")) deleted") }
        }
        record.handedOver = true
        write(record, log: log)
        log(pending.isEmpty ? "cleanup: done; nothing of the old identity is left"
            : "cleanup: \(pending.count) step(s) left, in \(self.record?.path ?? "no record") for the new version")
        return pending
    }

    func cleanUp(_ step: Cleanup, _ switcher: any MigrationSwitch, log: (String) -> Void) -> Bool {
        let (old, new) = (Self.old, Self.new)
        switch step {
        case .inputSource:
            guard inputSources.disable(old.inputSource) else { return false }
            log("cleanup: \(old.inputSource) disabled and out of the input sources")
            return true

        case .previousApps:
            switcher.commit()
            return !switcher.previousApps.contains { BundleSwap.exists($0) }

        case .defaults:
            for (from, to) in zip(old.domains, new.domains) {
                guard let values = defaults.domain(from) else { continue }
                // What the new domain still lacks first (an earlier switch, or the new identity installed without this).
                let there = defaults.domain(to) ?? [:]
                let missing = values.keys.filter { there[$0] == nil }
                guard missing.allSatisfy({ defaults.set(values[$0]!, forKey: $0, in: to) }) else { return false }
                if !missing.isEmpty {
                    defaults.flush(to)
                    let now = defaults.domain(to) ?? [:]
                    guard missing.allSatisfy({ Self.same(now[$0], values[$0]) }) else { return false }
                    log("cleanup: \(missing.count) keys copied from \(from) to \(to) first")
                }
                defaults.removeDomain(from)
                guard defaults.domain(from)?.isEmpty ?? true else { return false }
                log("cleanup: \(from) removed")
            }
            return true

        case .keychain:
            let (from, to) = (old.keychainGroup, new.keychainGroup)
            guard keychain.isEntitled(to: from) else { return true }  // none this build can see
            guard let items = try? keychain.items(in: from) else { return false }
            var done = true
            var deleted: [MigrationKeychainItem] = [], kept: [MigrationKeychainItem] = []
            for item in items {
                guard let value = keychain.value(of: item, in: from) else {
                    done = false
                    continue
                }
                if let theirs = keychain.value(of: item, in: to) {
                    guard theirs.data == value.data else {
                        kept.append(item)  // another key in the new group: the old one is never deleted
                        continue
                    }
                } else {
                    // Not copied yet (an earlier switch, or the new identity installed without this): copied first.
                    guard keychain.isEntitled(to: to), keychain.add(item, value, to: to) == errSecSuccess,
                          keychain.value(of: item, in: to)?.data == value.data else {
                        done = false
                        continue
                    }
                }
                let status = keychain.delete(item, from: from)
                if status == errSecSuccess || status == errSecItemNotFound { deleted.append(item) } else { done = false }
            }
            if !deleted.isEmpty { log("cleanup: deleted from \(from): \(deleted.map(\.description).joined(separator: ", "))") }
            if !kept.isEmpty { log("cleanup: kept in \(from) (the new group has another key): \(kept.map(\.description).joined(separator: ", "))") }
            return done

        case .loginKeys:
            // A key this identity reads without asking, its handover item holding the same key (written first if it isn't:
            // an earlier switch), is deleted. One it can't read is the new identity's own (imported already) or one it
            // couldn't hand over: left. Without the new group's entitlement none is handed over, so none deleted.
            var done = true
            var deleted: [LoginKey] = []
            for service in IdentityHandover.loginServices {
                let (login, handover) = (self.login(service), self.handover(service))
                guard let accounts = try? login.listedAccounts() else {
                    done = false
                    continue
                }
                for account in accounts {
                    guard let attributes = login.attributes(account), let value = login.read(account), !value.isEmpty else { continue }
                    if handover.read(account) != value {
                        guard keychain.isEntitled(to: new.keychainGroup) else { continue }
                        if handover.attributes(account) != nil { _ = handover.delete(account) }
                        guard handover.adding(account, value, attributes.label ?? APIKeys.label(account: account),
                                              attributes.comment ?? "", attributes.ending ?? APIKeys.ending(of: value),
                                              attributes.changed) == .ok,
                              handover.read(account) == value else {
                            done = false
                            continue
                        }
                    }
                    let status = login.delete(account)
                    if status == .ok || status == .notFound {
                        deleted.append(LoginKey(service: service, account: account))
                    } else {
                        done = false
                    }
                }
            }
            if !deleted.isEmpty {
                log("cleanup: deleted from the login keychain (handed over): \(deleted.map(\.description).joined(separator: ", "))")
            }
            return done

        case .otherApps:
            var done = true
            for app in leftovers.oldApps() {
                if leftovers.remove(app: app) { log("cleanup: removed \(app.path)") } else { done = false }
            }
            return done

        case .launchAgents:
            var done = true
            for agent in leftovers.oldLaunchAgents() {
                if leftovers.remove(agent: agent) { log("cleanup: removed the launch agent \(agent.label)") } else { done = false }
            }
            return done
        }
    }
}

// MARK: - The switch

/// The installed apps swapped for the new ones the way an update swaps them (`BundleSwap`): the update helper's
/// (`--apply-update`) and `--migrate-identity`'s.
public final class AppsSwitch: MigrationSwitch {
    public let inputMethod: URL
    let placing: [(new: URL, destination: URL)]
    let replacing: [URL]
    public var installed: [URL] { replacing }
    let aside: URL
    let version: String
    /// Stops the input method running from the installed copy (or from where it waits aside).
    let stop: () -> Void
    /// `app`'s input method runs (`--version`) and says it's `version`.
    let launchCheck: (_ app: URL, _ version: String) throws -> Void
    /// Apps placed (or put back), for Launch Services: registered (`lsregister -f`); apps moved aside before they are
    /// deleted: unregistered (`-u`).
    let registered: ([URL]) -> Void
    let unregistered: ([URL]) -> Void
    /// "after-swap": a failure on purpose right after the swap (a test install's rollback).
    let simulateFailure: String?
    private var swap: BundleSwap?
    private var parked: [URL]?

    public init(placing: [(new: URL, destination: URL)], replacing: [URL], aside: URL, inputMethod: URL, version: String,
                stop: @escaping () -> Void, launchCheck: @escaping (URL, String) throws -> Void,
                registered: @escaping ([URL]) -> Void = { _ in }, unregistered: @escaping ([URL]) -> Void = { _ in },
                simulateFailure: String? = nil) {
        self.placing = placing
        self.replacing = replacing
        self.aside = aside
        self.inputMethod = inputMethod
        self.version = version
        self.stop = stop
        self.launchCheck = launchCheck
        self.registered = registered
        self.unregistered = unregistered
        self.simulateFailure = simulateFailure
    }

    /// Where `BundleSwap` parked them (kept after `commit`); before the swap, where it will (`aside`/<index>-<name>, for
    /// those of `replacing` that are there).
    public var previousApps: [URL] {
        parked ?? replacing.enumerated().filter { BundleSwap.exists($0.element) }
            .map { aside.appendingPathComponent("\($0.offset)-\($0.element.lastPathComponent)") }
    }

    public var isSwitched: Bool {
        let info = NSDictionary(contentsOf: inputMethod.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Migration.new.apps.inputMethod,
              let version = info?["CFBundleShortVersionString"] as? String else { return false }
        return (try? launchCheck(inputMethod, version)) != nil
    }

    public func perform() throws {
        stop()
        let swap = try BundleSwap.perform(placing: placing, replacing: replacing, aside: aside)
        do {
            if simulateFailure == "after-swap" { throw MigrationError("a failure simulated after the swap (--simulate-failure)") }
            try launchCheck(inputMethod, version)
        } catch {
            stop()
            try swap.rollBack(reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
            throw error
        }
        self.swap = swap
        parked = swap.movedAside.map(\.to)
        stop()  // in case macOS started the previous one again meanwhile
        registered(swap.placed)
    }

    public func rollBack(reason: String) throws {
        guard let swap else { return }
        stop()
        try swap.rollBack(reason: reason)
        self.swap = nil
        parked = nil
        registered(swap.movedAside.map(\.from))
    }

    public func commit() {
        guard let swap else { return }
        unregistered(swap.movedAside.map(\.to))
        swap.commit()
        self.swap = nil
    }
}

// MARK: - The Mac's

/// The user's defaults: the old domains read with `persistentDomain(forName:)` and removed with
/// `removePersistentDomain(forName:)`, the new ones written through `UserDefaults(suiteName:)`. A domain removed leaves its
/// file in ~/Library/Preferences, which cfprefsd empties a few seconds later (and writes again, empty, when it's deleted
/// before): `deleteEmptiedFiles` waits for that, then deletes it.
public struct SystemDefaults: MigrationDefaults {
    public var preferences = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences", isDirectory: true)

    public init() {}

    public func domain(_ name: String) -> [String: Any]? {
        CFPreferencesAppSynchronize(name as CFString)
        return UserDefaults.standard.persistentDomain(forName: name)
    }

    public func set(_ value: Any, forKey key: String, in domain: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: domain) else { return false }
        defaults.set(value, forKey: key)
        return true
    }

    public func remove(_ key: String, from domain: String) {
        UserDefaults(suiteName: domain)?.removeObject(forKey: key)
    }

    public func flush(_ domain: String) {
        CFPreferencesAppSynchronize(domain as CFString)
    }

    public func removeDomain(_ name: String) {
        UserDefaults.standard.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
    }

    /// Up to 15 seconds in all: cfprefsd took up to 8 to write a removed domain's file.
    public func deleteEmptiedFiles(of domains: [String]) -> [String] {
        var left = domains.map { preferences.appendingPathComponent($0 + ".plist") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        var deleted: [String] = []
        let deadline = Date().addingTimeInterval(15)
        while !left.isEmpty {
            for file in left where (NSDictionary(contentsOf: file) as? [String: Any])?.isEmpty == true {
                try? FileManager.default.removeItem(at: file)
                deleted.append(file.deletingPathExtension().lastPathComponent)
            }
            left.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
            guard !left.isEmpty, Date() < deadline else { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return deleted
    }
}

/// The data protection keychain: generic passwords of an access group, synced or not, every query naming the group.
public struct SystemKeychain: MigrationKeychain {
    /// The attributes an item's copy keeps (its service, account and synchronizable are the item's own).
    static let copied = Set([kSecAttrLabel, kSecAttrComment, kSecAttrDescription, kSecAttrGeneric, kSecAttrAccessible,
                             kSecAttrCreator, kSecAttrType, kSecAttrIsInvisible, kSecAttrIsNegative].map { $0 as String })

    public init() {}

    public func isEntitled(to group: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) else { return false }
        return (value as? [String])?.contains(group) == true
    }

    private func query(_ group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecUseDataProtectionKeychain as String: true,
         kSecAttrAccessGroup as String: group]
    }

    private func query(_ item: MigrationKeychainItem, _ group: String) -> [String: Any] {
        var query = query(group)
        query[kSecAttrService as String] = item.service
        query[kSecAttrAccount as String] = item.account
        query[kSecAttrSynchronizable as String] = item.synchronizable ? kCFBooleanTrue : kCFBooleanFalse
        return query
    }

    public func items(in group: String) throws -> [MigrationKeychainItem] {
        var query = query(group)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = found as? [[String: Any]] else {
            throw MigrationError(SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)")
        }
        return Set(items.map { attributes in
            MigrationKeychainItem(service: attributes[kSecAttrService as String] as? String ?? "",
                                  account: attributes[kSecAttrAccount as String] as? String ?? "",
                                  synchronizable: (attributes[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false)
        }).sorted()
    }

    public func value(of item: MigrationKeychainItem, in group: String) -> MigrationKeychainValue? {
        var query = query(item, group)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let attributes = found as? [String: Any],
              let data = attributes[kSecValueData as String] as? Data else { return nil }
        return MigrationKeychainValue(data: data, attributes: attributes.filter { Self.copied.contains($0.key) })
    }

    public func add(_ item: MigrationKeychainItem, _ value: MigrationKeychainValue, to group: String) -> OSStatus {
        var query = query(item, group)
        for (key, attribute) in value.attributes where Self.copied.contains(key) { query[key] = attribute }
        query[kSecValueData as String] = value.data
        return SecItemAdd(query as CFDictionary, nil)
    }

    public func delete(_ item: MigrationKeychainItem, from group: String) -> OSStatus {
        SecItemDelete(query(item, group) as CFDictionary)
    }
}

/// Text Input Sources and the user's input sources (`InputSourceList`), as `--register` and `--disable` use them. Main
/// thread. Text Input Sources has no call to unregister one: an input source goes once its bundle does (the previous
/// apps deleted, and unregistered from Launch Services first).
public struct SystemInputSources: MigrationInputSources {
    public init() {}

    func source(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
    }

    func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    func userList() -> [[String: Any]]? {
        let domain = InputSourceList.domain as CFString
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyValue(InputSourceList.key as CFString, domain, kCFPreferencesCurrentUser,
                                      kCFPreferencesAnyHost) as? [[String: Any]]
    }

    /// The user's input sources written back, and the text input agents (Input menu, Ctrl+Space) told.
    func write(_ list: [[String: Any]]) -> Bool {
        let domain = InputSourceList.domain as CFString
        CFPreferencesSetValue(InputSourceList.key as CFString, list as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, userInfo: nil, deliverImmediately: true)
        return true
    }

    public func state(of id: String) -> MigrationInputSourceState {
        let source = source(id)
        let listed = userList().map { InputSourceList.contains($0, bundleID: id) } ?? false
        return MigrationInputSourceState(registered: source != nil,
                                         enabled: listed || source.map { bool($0, kTISPropertyInputSourceIsEnabled) } == true,
                                         selected: source.map { bool($0, kTISPropertyInputSourceIsSelected) } == true)
    }

    public func register(_ bundle: URL, id: String) -> Bool {
        guard TISRegisterInputSource(bundle as CFURL) == noErr else { return false }
        // Registration is asynchronous inside the text input server.
        let deadline = Date().addingTimeInterval(5)
        while source(id) == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        return source(id) != nil
    }

    public func enable(_ id: String) -> Bool {
        guard let source = source(id) else { return false }
        if !bool(source, kTISPropertyInputSourceIsEnabled), TISEnableInputSource(source) != noErr { return false }
        // Where the old one is in the user's input sources (the order Ctrl+Space goes in), else at the end.
        guard let list = userList(), !InputSourceList.contains(list, bundleID: id) else { return true }
        var updated = list
        let after = list.firstIndex { $0[InputSourceList.bundleIDKey] as? String == Migration.old.inputSource }
        updated.insert(InputSourceList.entry(bundleID: id), at: after.map { $0 + 1 } ?? list.count)
        return write(updated)
    }

    public func select(_ id: String) -> Bool {
        source(id).map { TISSelectInputSource($0) == noErr } ?? false
    }

    public func disable(_ id: String) -> Bool {
        var done = true
        if let source = source(id), bool(source, kTISPropertyInputSourceIsEnabled) {
            done = TISDisableInputSource(source) == noErr
        }
        if let updated = InputSourceList.removing(id, from: userList()) { done = write(updated) && done }
        return done
    }
}

/// Copies of the old apps in `apps` (the folders apps are installed in: their bundle ID, whatever their name) and launch
/// agents with an old label (property lists in `launchAgents` and `otherPlists`; with `system`, those loaded too, unloaded
/// with launchctl, and apps unregistered from Launch Services before they go).
public struct FolderLeftovers: MigrationLeftovers {
    public var apps: [URL]
    public var launchAgents: URL
    public var otherPlists: [URL]
    public var system: Bool

    public init(apps: [URL], launchAgents: URL, otherPlists: [URL], system: Bool) {
        self.apps = apps
        self.launchAgents = launchAgents
        self.otherPlists = otherPlists
        self.system = system
    }

    static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public func oldApps() -> [URL] {
        let ids = Set([Migration.old.apps.inputMethod, Migration.old.apps.settings])
        return apps.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { app in
                app.pathExtension == "app"
                    && ids.contains(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String ?? "")
            }
        }.sorted { $0.path < $1.path }
    }

    public func remove(app: URL) -> Bool {
        if system { _ = Self.run(Self.lsregister, ["-u", app.path]) }
        try? FileManager.default.removeItem(at: app)
        return (try? FileManager.default.attributesOfItem(atPath: app.path)) == nil
    }

    public func oldLaunchAgents() -> [MigrationLaunchAgent] {
        let plists = ((try? FileManager.default.contentsOfDirectory(at: launchAgents, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "plist" } + otherPlists
        var agents: [String: MigrationLaunchAgent] = [:]
        for plist in plists {
            guard let label = NSDictionary(contentsOf: plist)?["Label"] as? String, label.hasPrefix(Migration.oldLabelPrefix) else { continue }
            agents[label] = MigrationLaunchAgent(label: label, plist: plist)
        }
        // Loaded without a property list where one would be found (`make realtest-when-unlocked`'s, its plist gone).
        if system {
            for label in [Migration.oldLabelPrefix + "realtest-watch"] where agents[label] == nil && Self.loaded(label) {
                agents[label] = MigrationLaunchAgent(label: label, plist: nil)
            }
        }
        return agents.values.sorted { $0.label < $1.label }
    }

    public func remove(agent: MigrationLaunchAgent) -> Bool {
        if system, Self.loaded(agent.label) { _ = Self.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agent.label)"]) }
        if let plist = agent.plist { try? FileManager.default.removeItem(at: plist) }
        let plistGone = agent.plist.map { (try? FileManager.default.attributesOfItem(atPath: $0.path)) == nil } ?? true
        return plistGone && !(system && Self.loaded(agent.label))
    }

    static func loaded(_ label: String) -> Bool {
        run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]) == 0
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

// MARK: - A test install's (`--target-dir`)

/// Property lists in a folder of a test install's, one per domain.
public struct FileDefaults: MigrationDefaults {
    public var folder: URL

    public init(folder: URL) { self.folder = folder }

    func file(_ name: String) -> URL { folder.appendingPathComponent(name + ".plist") }

    public func domain(_ name: String) -> [String: Any]? {
        NSDictionary(contentsOf: file(name)) as? [String: Any]
    }

    func write(_ values: [String: Any], _ name: String) -> Bool {
        (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
            && (try? (values as NSDictionary).write(to: file(name))) != nil
    }

    public func set(_ value: Any, forKey key: String, in domain: String) -> Bool {
        var values = self.domain(domain) ?? [:]
        values[key] = value
        return write(values, domain)
    }

    public func remove(_ key: String, from domain: String) {
        guard var values = self.domain(domain) else { return }
        values[key] = nil
        _ = write(values, domain)
    }

    public func flush(_ domain: String) {}

    public func removeDomain(_ name: String) {
        try? FileManager.default.removeItem(at: file(name))
    }

    public func deleteEmptiedFiles(of domains: [String]) -> [String] { [] }
}

/// A test install's keychain: one property list per access group, an array of items (service, account, synchronizable,
/// data, attributes). Every group is "entitled".
public struct FileKeychain: MigrationKeychain {
    public var folder: URL

    public init(folder: URL) { self.folder = folder }

    func file(_ group: String) -> URL { folder.appendingPathComponent(group + ".plist") }

    func entries(_ group: String) -> [[String: Any]] {
        NSArray(contentsOf: file(group)) as? [[String: Any]] ?? []
    }

    func write(_ entries: [[String: Any]], _ group: String) -> Bool {
        (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
            && (try? (entries as NSArray).write(to: file(group))) != nil
    }

    static func item(_ entry: [String: Any]) -> MigrationKeychainItem {
        MigrationKeychainItem(service: entry["service"] as? String ?? "", account: entry["account"] as? String ?? "",
                              synchronizable: entry["synchronizable"] as? Bool ?? false)
    }

    public func isEntitled(to group: String) -> Bool { true }

    public func items(in group: String) throws -> [MigrationKeychainItem] {
        entries(group).map(Self.item).sorted()
    }

    public func value(of item: MigrationKeychainItem, in group: String) -> MigrationKeychainValue? {
        entries(group).first { Self.item($0) == item }.flatMap { entry in
            (entry["data"] as? Data).map { MigrationKeychainValue(data: $0, attributes: entry["attributes"] as? [String: Any] ?? [:]) }
        }
    }

    public func add(_ item: MigrationKeychainItem, _ value: MigrationKeychainValue, to group: String) -> OSStatus {
        var entries = entries(group)
        guard !entries.contains(where: { Self.item($0) == item }) else { return errSecDuplicateItem }
        entries.append(["service": item.service, "account": item.account, "synchronizable": item.synchronizable,
                        "data": value.data, "attributes": value.attributes])
        return write(entries, group) ? errSecSuccess : errSecIO
    }

    public func delete(_ item: MigrationKeychainItem, from group: String) -> OSStatus {
        let entries = entries(group)
        let left = entries.filter { Self.item($0) != item }
        guard left.count < entries.count else { return errSecItemNotFound }
        return write(left, group) ? errSecSuccess : errSecIO
    }
}

/// A test install's input sources: a property list of input source IDs, each with registered, enabled and selected.
public struct FileInputSources: MigrationInputSources {
    public var file: URL

    public init(file: URL) { self.file = file }

    func sources() -> [String: [String: Bool]] {
        NSDictionary(contentsOf: file) as? [String: [String: Bool]] ?? [:]
    }

    func write(_ sources: [String: [String: Bool]]) -> Bool {
        (try? (sources as NSDictionary).write(to: file)) != nil
    }

    public func state(of id: String) -> MigrationInputSourceState {
        let source = sources()[id] ?? [:]
        return MigrationInputSourceState(registered: source["registered"] ?? false, enabled: source["enabled"] ?? false,
                                         selected: source["selected"] ?? false)
    }

    public func register(_ bundle: URL, id: String) -> Bool {
        var sources = sources()
        sources[id, default: [:]]["registered"] = true
        return write(sources)
    }

    public func enable(_ id: String) -> Bool {
        var sources = sources()
        guard sources[id]?["registered"] == true else { return false }
        sources[id]?["enabled"] = true
        return write(sources)
    }

    public func select(_ id: String) -> Bool {
        var sources = sources()
        guard sources[id]?["enabled"] == true else { return false }
        for other in sources.keys { sources[other]?["selected"] = other == id }
        return write(sources)
    }

    public func disable(_ id: String) -> Bool {
        var sources = sources()
        guard sources[id]?["enabled"] == true || sources[id]?["selected"] == true else { return true }
        sources[id]?["enabled"] = false
        sources[id]?["selected"] = false
        return write(sources)
    }
}
