import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// Old identifiers, as a record names them: made up (this version never names the identity before it).
private let oldIME = "com.example.before.inputmethod.App", oldSettings = "com.example.before.settings"
private let oldGroup = "TEAMID.com.example.before.shared"
private let claude = LoginKey(service: APIKeys.service, account: "claude")
private let hosted = LoginKey(service: APIKeys.service, account: "hosted")
private let replacedOpenAI = LoginKey(service: KeySync.replacedService, account: "openai")
/// The test's keys: never in a line logged.
private let secrets = ["sk-test-claude-1", "test-session-2", "sk-test-replaced-3"]
private let savedAt = Date(timeIntervalSince1970: 1_790_000_000.25)

/// What the move to this system identity left, finished at launch (`IdentityFinish`): the handover items imported into
/// the login keychain as this identity's own, the record's steps done by its identifiers alone (never anything of this
/// identity's), a record not handed over waited for. Fakes stand for the login keychain, the handover items and the
/// Mac's input sources, defaults, apps, launch agents and keychain; the record is a file of the test's own.
struct IdentityFinishTests {
    /// What the record's steps find and do.
    final class FakeActions: IdentityCleanupActions {
        var enabledSources: Set<String> = [oldIME], domains: Set<String> = [oldIME, oldSettings]
        var apps: [String: String] = [:], agents: Set<String> = [], items: Set<CleanupRecord.KeychainItem> = []
        var entitled: Set<String> = [oldGroup]
        var failing: Set<String> = []
        var calls: [String] = []

        func disableInputSource(_ id: String) -> Bool {
            calls.append("disable \(id)")
            guard !failing.contains(id) else { return false }
            enabledSources.remove(id)
            return true
        }
        func removeDefaultsDomain(_ name: String) -> Bool {
            calls.append("domain \(name)")
            domains.remove(name)
            return true
        }
        func bundleID(ofAppAt path: String) -> String? { apps[path] }
        func removeApp(at path: String) -> Bool {
            calls.append("app \(path)")
            guard !failing.contains(path) else { return false }
            apps[path] = nil
            return true
        }
        func removeLaunchAgent(_ agent: CleanupRecord.LaunchAgent) -> Bool {
            calls.append("agent \(agent.label)")
            agents.remove(agent.label)
            return true
        }
        func isEntitled(to group: String) -> Bool { entitled.contains(group) }
        func deleteKeychainItem(_ item: CleanupRecord.KeychainItem, from group: String) -> Bool {
            calls.append("keychain \(group) \(item.account)")
            items.remove(item)
            return true
        }
    }

    /// The login keychain (items this identity can't read without asking: `unreadable`, until deleted) and the handover
    /// items.
    final class Keys: @unchecked Sendable {
        var unreadable: Set<String> = [], failingDeletes: Set<String> = []
        private var logins: [String: APIKeys.Keychain] = [:], handovers: [String: APIKeys.Keychain] = [:]

        func store(_ service: String) -> APIKeys.Keychain {
            if let store = logins[service] { return store }
            let store = APIKeys.Keychain.inMemory()
            logins[service] = store
            return store
        }
        func handover(_ service: String) -> APIKeys.Keychain {
            if let store = handovers[service] { return store }
            let store = APIKeys.Keychain.inMemory()
            handovers[service] = store
            return store
        }
        func login(_ service: String) -> APIKeys.Keychain {
            var store = store(service)
            let base = store
            store.read = { [unowned self] account in self.unreadable.contains(account) ? nil : base.read(account) }
            store.delete = { [unowned self] account in
                guard !self.failingDeletes.contains(account) else { return .failed(-25293) }
                self.unreadable.remove(account)  // the item it couldn't read is gone: the next one is this identity's
                return base.delete(account)
            }
            return store
        }
        func handOver(_ key: LoginKey, _ value: String) {
            _ = handover(key.service).write(key.account, value, "AllInOneIME: \(key.account)", "api.example.com", nil, savedAt)
        }
    }

    /// A Mac after the move: three keys handed over, no record.
    final class Mac {
        let actions = FakeActions()
        let keys = Keys()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("identity-finish-\(UUID().uuidString)", isDirectory: true)
        var record: URL { folder.appendingPathComponent(CleanupRecord.fileName) }
        var available = true
        var now = Date()
        var lines: [String] = []

        init() {
            keys.handOver(claude, secrets[0])
            keys.handOver(hosted, secrets[1])
            keys.handOver(replacedOpenAI, secrets[2])
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        /// A record the move left: every step, the originals of two keys still in the login keychain.
        func leaveRecord(handedOver: Bool = true) throws {
            var record = CleanupRecord()
            record.handedOver = handedOver
            record.bundleIDs = [oldIME, oldSettings]
            record.inputSource = oldIME
            record.defaultsDomains = [oldIME, oldSettings]
            actions.apps = ["/test/aside/0-AllInOneIME.app": oldIME, "/test/Applications/AllInOneIME Settings copy.app": oldSettings]
            record.apps = actions.apps.keys.sorted()
            actions.agents = ["com.example.watch"]
            record.launchAgents = [CleanupRecord.LaunchAgent(label: "com.example.watch", plist: "/test/LaunchAgents/watch.plist")]
            record.keychainGroup = oldGroup
            actions.items = [CleanupRecord.KeychainItem(service: APIKeys.service, account: "openai", synchronizable: true)]
            record.keychainItems = Array(actions.items)
            for (key, value) in [(claude, secrets[0]), (hosted, secrets[1])] {
                _ = keys.store(key.service).write(key.account, value, "AllInOneIME: \(key.account)", "api.example.com", nil, savedAt)
            }
            keys.unreadable = [claude.account, hosted.account]  // the identity before saved them
            record.loginKeys = [claude, hosted]
            try record.write(to: self.record)
        }

        func finish() -> IdentityFinish {
            var finish = IdentityFinish(record: record, actions: actions, login: keys.login, handover: keys.handover,
                                        handoverAvailable: available, say: { [unowned self] in self.lines.append($0) })
            finish.now = { [unowned self] in self.now }
            return finish
        }

        func run() -> IdentityFinish.Outcome { finish().run() }
        func imported(_ key: LoginKey) -> String? { keys.store(key.service).read(key.account) }
        func handedOver(_ key: LoginKey) -> String? { keys.handover(key.service).read(key.account) }
        var noSecretLogged: Bool { !lines.contains { line in secrets.contains { line.contains($0) } } }
    }

    // MARK: The keys

    @Test func handoverItemsAreImportedAsThisIdentitysOwnThenDeleted() throws {
        let mac = Mac()
        #expect(mac.run() == .done(left: false))
        for (key, value) in [(claude, secrets[0]), (hosted, secrets[1]), (replacedOpenAI, secrets[2])] {
            #expect(mac.imported(key) == value && mac.handedOver(key) == nil, "\(key)")
            let attributes = try #require(mac.keys.store(key.service).attributes(key.account))
            #expect(attributes.label == "AllInOneIME: \(key.account)" && attributes.comment == "api.example.com")
            #expect(IdentityHandover.same(attributes.saved, savedAt))
        }
        #expect(mac.lines.contains { $0.contains("imported") && $0.contains("claude") } && mac.noSecretLogged)
        // Another launch: nothing left to do.
        #expect(mac.run() == .done(left: false) && mac.imported(claude) == secrets[0])
    }

    @Test func aKeySavedSinceInThisVersionIsKept() {
        let mac = Mac()
        _ = mac.keys.store(claude.service).write(claude.account, "sk-test-saved-since", "AllInOneIME: claude", "", nil, Date())
        #expect(mac.run() == .done(left: false))
        #expect(mac.imported(claude) == "sk-test-saved-since" && mac.handedOver(claude) == nil)
    }

    /// An item this identity would have to ask for is never written over: its handover item waits.
    @Test func anItemThisVersionCantReadIsNeverWrittenOver() {
        let mac = Mac()
        _ = mac.keys.store(claude.service).write(claude.account, "sk-test-someone-elses", "", "", nil, nil)
        mac.keys.unreadable = [claude.account]
        #expect(mac.run() == .done(left: true))
        mac.keys.unreadable = []
        #expect(mac.imported(claude) == "sk-test-someone-elses" && mac.handedOver(claude) == secrets[0])
        #expect(mac.imported(hosted) == secrets[1])
    }

    @Test func withoutTheAccessGroupNothingIsImported() {
        let mac = Mac()
        mac.available = false
        #expect(mac.run() == .done(left: false))
        #expect(mac.imported(claude) == nil && mac.handedOver(claude) == secrets[0])
    }

    // MARK: The record

    /// Each step done with the record's identifiers; the originals deleted first, so that their keys are imported in
    /// their place; the record deleted.
    @Test func theRecordsStepsAreDoneThenItsDeleted() throws {
        let mac = Mac()
        try mac.leaveRecord()
        #expect(mac.run() == .done(left: false))
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
        #expect(mac.actions.enabledSources.isEmpty && mac.actions.domains.isEmpty && mac.actions.apps.isEmpty)
        #expect(mac.actions.agents.isEmpty && mac.actions.items.isEmpty)
        mac.keys.unreadable = []
        for (key, value) in [(claude, secrets[0]), (hosted, secrets[1]), (replacedOpenAI, secrets[2])] {
            #expect(mac.imported(key) == value && mac.handedOver(key) == nil, "\(key)")
        }
        #expect(mac.noSecretLogged)
    }

    /// A record the version that moved hasn't handed over yet is left to it: nothing is done, and its keys wait.
    @Test func aRecordNotHandedOverYetIsWaitedFor() throws {
        let mac = Mac()
        try mac.leaveRecord(handedOver: false)
        #expect(mac.run() == .waiting)
        #expect(mac.actions.calls.isEmpty && mac.handedOver(replacedOpenAI) == secrets[2] && mac.imported(replacedOpenAI) == nil)
        // That version stopped: after a while the record is this one's.
        mac.now = Date().addingTimeInterval(CleanupRecord.staleAfter + 60)
        #expect(mac.run() == .done(left: false))
        #expect(!FileManager.default.fileExists(atPath: mac.record.path) && mac.actions.enabledSources.isEmpty)
    }

    /// A step that fails stays in the record (the others out of it) for the next launch, and a key whose original can't
    /// be deleted waits; the next launch finishes.
    @Test func aStepThatFailsStaysInTheRecordForTheNextLaunch() throws {
        let mac = Mac()
        try mac.leaveRecord()
        mac.actions.failing = [oldIME, "/test/aside/0-AllInOneIME.app"]
        mac.keys.failingDeletes = [hosted.account]
        #expect(mac.run() == .done(left: true))
        let record = try #require(try CleanupRecord.read(at: mac.record))
        #expect(record.handedOver && record.inputSource == oldIME && record.apps == ["/test/aside/0-AllInOneIME.app"])
        #expect(record.defaultsDomains.isEmpty && record.launchAgents.isEmpty && record.keychainItems.isEmpty)
        #expect(record.loginKeys == [hosted])
        #expect(try FileManager.default.attributesOfItem(atPath: mac.record.path)[.posixPermissions] as? Int == 0o600)
        // The key whose original is still there waits; the others are imported.
        #expect(mac.handedOver(hosted) == secrets[1] && mac.handedOver(claude) == nil)

        mac.actions.failing = []
        mac.keys.failingDeletes = []
        #expect(mac.run() == .done(left: false))
        #expect(!FileManager.default.fileExists(atPath: mac.record.path) && mac.actions.apps.isEmpty)
        mac.keys.unreadable = []
        #expect(mac.imported(hosted) == secrets[1] && mac.handedOver(hosted) == nil)
    }

    /// An original saved again since it was handed over (its save time isn't the handover item's) is kept: it's the
    /// newer key; its handover item goes.
    @Test func anOriginalSavedAgainSinceIsKept() throws {
        let mac = Mac()
        try mac.leaveRecord()
        _ = mac.keys.store(claude.service).write(claude.account, "sk-test-newer", "", "", nil, savedAt.addingTimeInterval(30))
        #expect(mac.run() == .done(left: false))
        mac.keys.unreadable = []
        #expect(mac.imported(claude) == "sk-test-newer" && mac.handedOver(claude) == nil)
    }

    /// Whatever a record says, nothing of this identity's is removed, an app only when it has one of the record's bundle
    /// IDs and a launch agent only under their name; keychain items of a group this version can't reach stay.
    @Test func nothingOfThisIdentitysIsEverRemoved() throws {
        let mac = Mac()
        var record = CleanupRecord()
        record.handedOver = true
        record.bundleIDs = [Updater.bundleID, Updater.settingsBundleID, oldIME]
        record.inputSource = Updater.bundleID
        record.defaultsDomains = [Updater.bundleID, "com.apple.HIToolbox"]
        mac.actions.apps = ["/test/Input Methods/AllInOneIME.app": Updater.bundleID, "/test/Applications/Other.app": "com.example.other"]
        record.apps = mac.actions.apps.keys.sorted()
        record.launchAgents = [CleanupRecord.LaunchAgent(label: "com.allinoneime.realtest-watch", plist: nil),
                               CleanupRecord.LaunchAgent(label: "org.example.agent", plist: nil)]
        record.keychainGroup = KeySync.accessGroup
        record.keychainItems = [CleanupRecord.KeychainItem(service: APIKeys.service, account: "openai", synchronizable: true)]
        try record.write(to: mac.record)
        #expect(mac.run() == .done(left: false))
        #expect(mac.actions.calls.isEmpty, "\(mac.actions.calls)")
        #expect(mac.actions.apps.count == 2 && !FileManager.default.fileExists(atPath: mac.record.path))

        // Another group, this version not entitled to it: left (only the version that moved could reach it).
        record.keychainGroup = oldGroup
        record.apps = []
        try record.write(to: mac.record)
        mac.actions.entitled = []
        #expect(mac.run() == .done(left: false))
        #expect(mac.actions.calls.isEmpty && mac.lines.contains { $0.contains("isn't entitled to \(oldGroup)") })
    }

    @Test func aRecordThatCantBeReadIsDeleted() throws {
        let mac = Mac()
        try FileManager.default.createDirectory(at: mac.folder, withIntermediateDirectories: true)
        try Data("not a record".utf8).write(to: mac.record)
        #expect(mac.run() == .done(left: false))
        #expect(!FileManager.default.fileExists(atPath: mac.record.path) && mac.imported(claude) == secrets[0])
    }

    // MARK: The Mac's, on the test's own

    /// Apps and launch agents in a folder of the test's own (Launch Services and launchd only asked about them), and a
    /// defaults domain of the test's own.
    @Test func theMacsStepsOnFilesOfTheTestsOwn() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("identity-cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let system = SystemIdentityCleanup()
        let app = folder.appendingPathComponent("Old.app")
        try FakeApp.make(app, id: oldIME, version: "0.7.1", build: "24", sign: false)
        #expect(system.bundleID(ofAppAt: app.path) == oldIME)
        #expect(system.removeApp(at: app.path) && system.bundleID(ofAppAt: app.path) == nil)

        let label = "com.example.allinoneime-tests.\(UUID().uuidString)"
        let plist = folder.appendingPathComponent("agent.plist"), other = folder.appendingPathComponent("other.plist")
        try (["Label": label] as NSDictionary).write(to: plist)
        try (["Label": "com.example.other"] as NSDictionary).write(to: other)
        #expect(system.removeLaunchAgent(CleanupRecord.LaunchAgent(label: label, plist: plist.path)))
        #expect(!FileManager.default.fileExists(atPath: plist.path))
        // A property list with another label is never deleted.
        #expect(system.removeLaunchAgent(CleanupRecord.LaunchAgent(label: label, plist: other.path)))
        #expect(FileManager.default.fileExists(atPath: other.path))

        let domain = "com.allinoneime.tests.identity-finish.\(UUID().uuidString)"
        UserDefaults(suiteName: domain)?.set("value", forKey: "key")
        CFPreferencesAppSynchronize(domain as CFString)
        #expect(system.removeDefaultsDomain(domain))
        #expect(UserDefaults.standard.persistentDomain(forName: domain)?.isEmpty ?? true)
        #expect(!FileManager.default.fileExists(atPath: system.preferences.appendingPathComponent(domain + ".plist").path))
    }
}
