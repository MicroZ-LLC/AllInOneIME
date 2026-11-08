import AllInOneIMECore
import Foundation
import Security
import Testing

private let old = Migration.old
private let new = Migration.new
private let openAI = MigrationKeychainItem(service: "AllInOneIME API key", account: "openai", synchronizable: true)
private let gemini = MigrationKeychainItem(service: "AllInOneIME API key", account: "gemini", synchronizable: false)
/// The login keychain's keys (key sync off): an API key, the Cloud session, and a replaced copy.
private let claude = LoginKey(service: APIKeys.service, account: "claude")
private let hosted = LoginKey(service: APIKeys.service, account: "hosted")
private let replacedOpenAI = LoginKey(service: KeySync.replacedService, account: "openai")
/// The test's keys: never in a line logged.
private let secrets = ["sk-test-openai-1", "test-gemini-2", "sk-test-claude-3", "test-session-4", "sk-test-replaced-5"]
private let savedAt = Date(timeIntervalSince1970: 1_790_000_000.25)

/// 0.7.1's move to the new system identity (`Migration`): each step, a failure before the switch putting everything back,
/// the cleanup only after a verified switch and left for the next run when it fails, and another run changing nothing.
/// Fakes stand for the defaults, the keychain, Text Input Sources, the leftovers and the apps' swap: nothing of this Mac's
/// is read or changed (the test install's file stores and `SystemDefaults` on domains of the test's own excepted).
struct MigrationTests {
    /// What the fakes did, in order: the cleanup's events have to come after the switch's.
    final class Events: @unchecked Sendable {
        var list: [String] = []
        func index(_ prefix: String) -> Int? { list.firstIndex { $0.hasPrefix(prefix) } }
        func lastIndex(_ prefix: String) -> Int? { list.lastIndex { $0.hasPrefix(prefix) } }
    }

    final class FakeDefaults: MigrationDefaults {
        var domains: [String: [String: Any]] = [:]
        var unwritable: Set<String> = []
        /// Keys whose value reads back otherwise than written.
        var garbled: Set<String> = []
        var removable = true
        let events: Events
        init(_ events: Events) { self.events = events }

        func domain(_ name: String) -> [String: Any]? { domains[name] }
        func set(_ value: Any, forKey key: String, in domain: String) -> Bool {
            guard !unwritable.contains(domain) else { return false }
            domains[domain, default: [:]][key] = garbled.contains(key) ? "garbled" : value
            events.list.append("defaults: set \(domain) \(key)")
            return true
        }
        func remove(_ key: String, from domain: String) { domains[domain]?[key] = nil }
        func flush(_ domain: String) {}
        func removeDomain(_ name: String) {
            guard removable else { return }
            domains[name] = nil
            events.list.append("defaults: removed \(name)")
        }
        func deleteEmptiedFiles(of domains: [String]) -> [String] { [] }
    }

    final class FakeKeychain: MigrationKeychain {
        var groups: [String: [MigrationKeychainItem: Data]] = [:]
        var entitled: Set<String> = [old.keychainGroup, new.keychainGroup]
        /// Accounts whose add fails, whose copy reads back otherwise, whose delete fails.
        var failingAdds: Set<String> = [], garbled: Set<String> = [], failingDeletes: Set<String> = []
        let events: Events
        init(_ events: Events) { self.events = events }

        func isEntitled(to group: String) -> Bool { entitled.contains(group) }
        func items(in group: String) throws -> [MigrationKeychainItem] {
            guard entitled.contains(group) else { throw MigrationError("missing entitlement") }
            return (groups[group] ?? [:]).keys.sorted()
        }
        func value(of item: MigrationKeychainItem, in group: String) -> MigrationKeychainValue? {
            groups[group]?[item].map { MigrationKeychainValue(data: $0, attributes: ["labl": "AllInOneIME: \(item.account)"]) }
        }
        func add(_ item: MigrationKeychainItem, _ value: MigrationKeychainValue, to group: String) -> OSStatus {
            guard !failingAdds.contains(item.account) else { return errSecIO }
            guard groups[group]?[item] == nil else { return errSecDuplicateItem }
            groups[group, default: [:]][item] = garbled.contains(item.account) ? Data("garbled".utf8) : value.data
            events.list.append("keychain: added \(group) \(item)")
            return errSecSuccess
        }
        func delete(_ item: MigrationKeychainItem, from group: String) -> OSStatus {
            guard !failingDeletes.contains(item.account) else { return errSecIO }
            guard groups[group]?.removeValue(forKey: item) != nil else { return errSecItemNotFound }
            events.list.append("keychain: deleted \(group) \(item)")
            return errSecSuccess
        }
    }

    /// The login keychain's stores and the handover items' (in-memory, one per service), as `Migration.login` and
    /// `Migration.handover` give them: keys that can't be read without asking, deletes and handover writes that fail,
    /// handover items that read back otherwise.
    final class FakeLogin: @unchecked Sendable {
        var unreadable: Set<String> = [], failingDeletes: Set<String> = [], failingHandovers: Set<String> = []
        var garbledHandovers: Set<String> = []
        private var logins: [String: APIKeys.Keychain] = [:], handovers: [String: APIKeys.Keychain] = [:]
        let events: Events
        init(_ events: Events) { self.events = events }

        /// The store itself, without the failures (to set up and look).
        func store(_ service: String) -> APIKeys.Keychain {
            if let store = logins[service] { return store }
            let store = APIKeys.Keychain.inMemory()
            logins[service] = store
            return store
        }
        func handoverStore(_ service: String) -> APIKeys.Keychain {
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
                let status = base.delete(account)
                if status == .ok { self.events.list.append("login: deleted \(service)/\(account)") }
                return status
            }
            return store
        }
        func handover(_ service: String) -> APIKeys.Keychain {
            var store = handoverStore(service)
            let base = store
            store.add = { [unowned self] account, key, label, comment, ending, saved in
                guard !self.failingHandovers.contains(account) else { return .failed(-34018) }
                let status = base.adding(account, self.garbledHandovers.contains(account) ? "garbled" : key, label, comment, ending, saved)
                if status == .ok { self.events.list.append("handover: added \(service)/\(account)") }
                return status
            }
            return store
        }
    }

    final class FakeInputSources: MigrationInputSources {
        var sources: [String: MigrationInputSourceState] = [:]
        var failingRegister = false, failingEnable = false, failingDisable = false
        let events: Events
        init(_ events: Events) { self.events = events }

        func state(of id: String) -> MigrationInputSourceState { sources[id] ?? MigrationInputSourceState() }
        func register(_ bundle: URL, id: String) -> Bool {
            guard !failingRegister else { return false }
            sources[id, default: MigrationInputSourceState()].registered = true
            events.list.append("input: registered \(id)")
            return true
        }
        func enable(_ id: String) -> Bool {
            guard !failingEnable, sources[id]?.registered == true else { return false }
            sources[id]?.enabled = true
            return true
        }
        func select(_ id: String) -> Bool {
            guard sources[id]?.enabled == true else { return false }
            for key in sources.keys { sources[key]?.selected = key == id }
            return true
        }
        func disable(_ id: String) -> Bool {
            guard !failingDisable else { return false }
            guard let source = sources[id], source.enabled || source.selected else { return true }
            sources[id]?.enabled = false
            sources[id]?.selected = false
            events.list.append("input: disabled \(id)")
            return true
        }
    }

    final class FakeLeftovers: MigrationLeftovers {
        var apps: [URL] = [], agents: [MigrationLaunchAgent] = []
        let events: Events
        init(_ events: Events) { self.events = events }

        func oldApps() -> [URL] { apps }
        func remove(app: URL) -> Bool {
            apps.removeAll { $0 == app }
            events.list.append("leftovers: removed \(app.lastPathComponent)")
            return true
        }
        func oldLaunchAgents() -> [MigrationLaunchAgent] { agents }
        func remove(agent: MigrationLaunchAgent) -> Bool {
            agents.removeAll { $0 == agent }
            events.list.append("leftovers: removed \(agent.label)")
            return true
        }
    }

    final class FakeSwitch: MigrationSwitch {
        enum Installed { case old, new }
        let inputMethod = URL(fileURLWithPath: "/test/Input Methods/AllInOneIME.app")
        var installed: [URL] { [inputMethod, URL(fileURLWithPath: "/test/Applications/AllInOneIME Settings.app")] }
        let previousApps = [URL(fileURLWithPath: "/test/aside/0-AllInOneIME.app"), URL(fileURLWithPath: "/test/aside/1-AllInOneIME Settings.app")]
        /// Run as the swap starts (what the record says then).
        var onPerform: () -> Void = {}
        var state = Installed.old
        var failingSwap = false, failingLaunch = false, notRestorable = false
        var swapped = false, committed = false
        let events: Events
        init(_ events: Events) { self.events = events }

        var isSwitched: Bool { state == .new }
        func perform() throws {
            events.list.append("switch: perform")
            onPerform()
            guard !failingSwap else { throw MigrationError("the swap failed") }
            state = .new
            guard !failingLaunch else {
                if notRestorable { throw BundleSwap.Failure.notRestored("doesn't start", folder: "/test/aside") }
                state = .old
                throw MigrationError("the new input method doesn't start")
            }
            swapped = true
            events.list.append("switch: verified")
        }
        func rollBack(reason: String) throws {
            if notRestorable { throw BundleSwap.Failure.notRestored(reason, folder: "/test/aside") }
            state = .old
            swapped = false
            events.list.append("switch: rolled back")
        }
        func commit() {
            guard swapped else { return }
            swapped = false
            committed = true
            events.list.append("switch: committed")
        }
    }

    /// A Mac with the old identity: its two domains (the new input method's domain has a key of its own already), two keys
    /// in the old group (one synced), its input source enabled and selected, a stray copy of the old Settings app and a
    /// launch agent with an old label.
    final class Mac {
        let events = Events()
        lazy var defaults = FakeDefaults(events)
        lazy var keychain = FakeKeychain(events)
        lazy var inputSources = FakeInputSources(events)
        lazy var leftovers = FakeLeftovers(events)
        lazy var switcher = FakeSwitch(events)
        lazy var login = FakeLogin(events)
        /// Where the cleanup record goes (a folder of the test's own; `deleteRecord` removes it).
        let record = FileManager.default.temporaryDirectory.appendingPathComponent("migration-record-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(CleanupRecord.fileName)
        var lines: [String] = []

        init() {
            defaults.domains[old.apps.inputMethod] = ["recentApps": ["com.apple.TextEdit"], "updateLastSuccess": Date(timeIntervalSince1970: 1),
                                                      "shared": "old"]
            defaults.domains[old.apps.settings] = ["NSWindow Frame Settings": "0 0 100 100"]
            defaults.domains[new.apps.inputMethod] = ["shared": "new"]
            keychain.groups[old.keychainGroup] = [openAI: Data(secrets[0].utf8), gemini: Data(secrets[1].utf8)]
            inputSources.sources[old.inputSource] = MigrationInputSourceState(registered: true, enabled: true, selected: true)
            leftovers.apps = [URL(fileURLWithPath: "/test/Applications/AllInOneIME Settings copy.app")]
            leftovers.agents = [MigrationLaunchAgent(label: Migration.oldLabelPrefix + "realtest-watch", plist: nil)]
            for (key, value) in [(claude, secrets[2]), (hosted, secrets[3]), (replacedOpenAI, secrets[4])] {
                _ = login.store(key.service).write(key.account, value, "AllInOneIME: \(key.account)", "api.example.com", nil, savedAt)
            }
        }

        deinit { try? FileManager.default.removeItem(at: record.deletingLastPathComponent()) }

        func migration() -> Migration {
            var migration = Migration(defaults: defaults, keychain: keychain, login: login.login, handover: login.handover,
                                      inputSources: inputSources, leftovers: leftovers, record: record,
                                      say: { [unowned self] in self.lines.append($0) })
            migration.pause = {}
            return migration
        }

        /// The login keychain's key, and the handover item's, for `key`.
        func original(_ key: LoginKey) -> String? { login.store(key.service).read(key.account) }
        func handedOver(_ key: LoginKey) -> String? { login.handoverStore(key.service).read(key.account) }
        func savedRecord() throws -> CleanupRecord? { try CleanupRecord.read(at: record) }

        func run() -> Migration.Report { migration().run(switcher) }
    }

    // MARK: Each step

    @Test func theSettingsAndKeysMoveAndTheOldIdentityIsCleanedUp() throws {
        let mac = Mac()
        let report = mac.run()
        #expect(report.switched && report.error == nil && report.pending.isEmpty)

        // a. The keys the new domains lacked, the new one's own kept; the old domains gone.
        #expect(report.copiedKeys == 3)
        let ime = try #require(mac.defaults.domains[new.apps.inputMethod])
        #expect(ime["shared"] as? String == "new" && ime["recentApps"] as? [String] == ["com.apple.TextEdit"]
                && ime["updateLastSuccess"] as? Date == Date(timeIntervalSince1970: 1))
        #expect(mac.defaults.domains[new.apps.settings]?["NSWindow Frame Settings"] as? String == "0 0 100 100")
        #expect(mac.defaults.domains[old.apps.inputMethod] == nil && mac.defaults.domains[old.apps.settings] == nil)

        // b. Every item into the new group, synced or not as it was; the old group empty.
        #expect(report.copiedItems == 2)
        #expect(mac.keychain.groups[new.keychainGroup] == [openAI: Data(secrets[0].utf8), gemini: Data(secrets[1].utf8)])
        #expect(mac.keychain.groups[old.keychainGroup]?.isEmpty == true)

        // c. The new input source registered, enabled and selected as the old one was; d. the old one disabled.
        #expect(mac.switcher.state == .new && mac.switcher.committed)
        #expect(mac.inputSources.sources[new.inputSource] == MigrationInputSourceState(registered: true, enabled: true, selected: true))
        #expect(mac.inputSources.sources[old.inputSource]?.enabled == false && mac.inputSources.sources[old.inputSource]?.selected == false)
        #expect(mac.leftovers.apps.isEmpty && mac.leftovers.agents.isEmpty)

        // b. The login keychain's keys handed over (never synced, label, comment and save time kept), then deleted there.
        #expect(report.handedOver == 3)
        for (key, value) in [(claude, secrets[2]), (hosted, secrets[3]), (replacedOpenAI, secrets[4])] {
            #expect(mac.handedOver(key) == value && mac.original(key) == nil, "\(key)")
            let attributes = try #require(mac.login.handoverStore(key.service).attributes(key.account))
            #expect(attributes.label == "AllInOneIME: \(key.account)" && attributes.comment == "api.example.com")
            #expect(IdentityHandover.same(attributes.saved, savedAt))
        }
        // All done: no record left.
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))

        // Logged by key name and account, never with a key.
        #expect(mac.lines.contains { $0.contains("openai") } && mac.lines.contains { $0.contains("claude") })
        #expect(!mac.lines.contains { line in secrets.contains { line.contains($0) } })
    }

    @Test func theCleanupStartsOnlyOnceTheSwitchIsVerified() throws {
        let mac = Mac()
        _ = mac.run()
        let events = mac.events
        let verified = try #require(events.index("switch: verified"))
        let registered = try #require(events.index("input: registered \(new.inputSource)"))
        // Nothing of the old identity removed before the new one is in and registered; the copies all before the swap.
        for cleanup in ["input: disabled", "defaults: removed", "keychain: deleted", "login: deleted", "leftovers:", "switch: committed"] {
            #expect(try #require(events.index(cleanup)) > max(verified, registered), "\(cleanup)")
        }
        let swap = try #require(events.index("switch: perform"))
        #expect(try #require(events.lastIndex("keychain: added")) < swap && events.lastIndex("defaults: set")! < swap)
        #expect(try #require(events.lastIndex("handover: added")) < swap)
    }

    /// A key the login keychain would ask for (another build saved it) is left where it is: not handed over, not deleted,
    /// and not in the record; the rest moves.
    @Test func aLoginKeyThatWouldAskIsLeftWhereItIs() {
        let mac = Mac()
        mac.login.unreadable = [claude.account]
        let report = mac.run()
        #expect(report.switched && report.pending.isEmpty && report.handedOver == 2)
        #expect(mac.original(claude) == secrets[2] && mac.handedOver(claude) == nil)
        #expect(mac.original(hosted) == nil && mac.handedOver(hosted) == secrets[3])
        #expect(mac.lines.contains { $0.contains("claude") && $0.contains("without asking") })
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
    }

    /// A handover item an earlier run left (its key saved again since) is replaced by the key as it is now.
    @Test func anOutOfDateHandoverItemIsReplaced() {
        let mac = Mac()
        _ = mac.login.handoverStore(claude.service).write(claude.account, "sk-test-earlier", "AllInOneIME: claude", "", nil, nil)
        #expect(mac.run().switched)
        #expect(mac.handedOver(claude) == secrets[2] && mac.original(claude) == nil)
    }

    // MARK: The cleanup record

    /// Before the swap, the record lists what the cleanup will remove, not handed over yet (the bridge is at it); 0600.
    /// Once all is done it is gone.
    @Test func theRecordListsTheCleanupBeforeTheSwapAndGoesOnceItIsDone() throws {
        let mac = Mac()
        var atSwap: CleanupRecord?
        var mode: Int?
        var text = ""
        mac.switcher.onPerform = { [unowned mac] in
            atSwap = try? mac.savedRecord()
            mode = (try? FileManager.default.attributesOfItem(atPath: mac.record.path))?[.posixPermissions] as? Int
            text = (try? String(contentsOf: mac.record, encoding: .utf8)) ?? ""
        }
        #expect(mac.run().switched)
        let record = try #require(atSwap)
        #expect(mode == 0o600)
        #expect(!record.handedOver && !record.isHandedOver(now: record.updated.addingTimeInterval(60)))
        #expect(record.bundleIDs == [old.apps.inputMethod, old.apps.settings] && record.inputSource == old.inputSource)
        #expect(record.defaultsDomains == old.domains)
        #expect(record.apps == mac.switcher.previousApps.map(\.path) + ["/test/Applications/AllInOneIME Settings copy.app"])
        #expect(record.launchAgents == [CleanupRecord.LaunchAgent(label: Migration.oldLabelPrefix + "realtest-watch", plist: nil)])
        #expect(record.keychainGroup == old.keychainGroup)
        #expect(Set(record.keychainItems) == [CleanupRecord.KeychainItem(service: openAI.service, account: "openai", synchronizable: true),
                                              CleanupRecord.KeychainItem(service: gemini.service, account: "gemini", synchronizable: false)])
        #expect(Set(record.loginKeys) == [claude, hosted, replacedOpenAI])
        // Identifiers only: no key in it.
        #expect(text.contains("claude") && !secrets.contains { text.contains($0) })
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
    }

    /// A step left is kept in the record, handed over to the new version (and only it: the steps done are out of it);
    /// another run finishes it and deletes the record.
    @Test func aStepLeftStaysInTheRecordForTheNewVersion() throws {
        let mac = Mac()
        mac.keychain.failingDeletes = ["openai"]
        mac.inputSources.failingDisable = true
        mac.login.failingDeletes = [hosted.account]
        let report = mac.run()
        #expect(report.switched && report.pending == [.inputSource, .keychain, .loginKeys])
        let record = try #require(try mac.savedRecord())
        #expect(record.handedOver && record.isHandedOver())
        #expect(record.inputSource == old.inputSource && record.defaultsDomains.isEmpty && record.apps.isEmpty && record.launchAgents.isEmpty)
        #expect(record.keychainItems == [CleanupRecord.KeychainItem(service: openAI.service, account: "openai", synchronizable: true)])
        #expect(record.loginKeys == [hosted])
        // The handover item stays, and so does the original, until it is deleted.
        #expect(mac.original(hosted) == secrets[3] && mac.handedOver(hosted) == secrets[3])

        mac.keychain.failingDeletes = []
        mac.inputSources.failingDisable = false
        mac.login.failingDeletes = []
        #expect(mac.run().pending.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: mac.record.path) && mac.original(hosted) == nil)
    }

    // MARK: The downgrade guard

    /// The installer and `make install` never put this version over one with the new identity.
    @Test func anInstalledNewIdentityIsNewer() {
        #expect(Migration.newIdentityInstalled(info: ["CFBundleIdentifier": new.apps.inputMethod, "CFBundleShortVersionString": "0.7.2"]))
        #expect(!Migration.newIdentityInstalled(info: ["CFBundleIdentifier": old.apps.inputMethod]))
        #expect(!Migration.newIdentityInstalled(info: nil) && !Migration.newIdentityInstalled(info: [:]))
    }

    @Test func anOldInputSourceThatWasOffLeavesTheNewOneOff() {
        let mac = Mac()
        mac.inputSources.sources[old.inputSource] = MigrationInputSourceState(registered: true, enabled: false, selected: false)
        #expect(mac.run().switched)
        #expect(mac.inputSources.sources[new.inputSource] == MigrationInputSourceState(registered: true, enabled: false, selected: false))
    }

    @Test func anotherKeyTheNewGroupHasIsKeptAndTheOldOneLeft() {
        let mac = Mac()
        // Another Mac moved first: its key for OpenAI synced into the new group here.
        mac.keychain.groups[new.keychainGroup] = [openAI: Data("sk-test-other-mac".utf8)]
        let report = mac.run()
        #expect(report.switched && report.pending.isEmpty && report.copiedItems == 1)
        #expect(mac.keychain.groups[new.keychainGroup]?[openAI] == Data("sk-test-other-mac".utf8))
        #expect(mac.keychain.groups[new.keychainGroup]?[gemini] == Data(secrets[1].utf8))
        // Never deleted: the only copy of that key.
        #expect(mac.keychain.groups[old.keychainGroup] == [openAI: Data(secrets[0].utf8)])
        #expect(mac.lines.contains { $0.contains("kept") && $0.contains("openai") })
    }

    @Test func aBuildWithoutTheKeychainEntitlementLeavesTheKeychainAlone() {
        let mac = Mac()
        mac.keychain.entitled = []
        let report = mac.run()
        #expect(report.switched && report.copiedItems == 0 && report.handedOver == 0 && report.pending.isEmpty)
        #expect(mac.keychain.groups[old.keychainGroup]?.count == 2 && mac.keychain.groups[new.keychainGroup] == nil)
        // The login keychain's keys stay (the new identity asks once for each): nothing handed over.
        #expect(mac.original(claude) == secrets[2] && mac.handedOver(claude) == nil && mac.original(hosted) == secrets[3])
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
    }

    // MARK: A failure before the switch

    enum Failure: String, CaseIterable {
        case defaultsUnwritable, defaultsReadBack, keychainAdd, keychainReadBack, noNewGroup, handoverAdd, handoverReadBack
        case swap, launch, register, enable
    }

    @Test(arguments: Failure.allCases)
    func aFailureBeforeTheSwitchPutsEverythingBack(_ failure: Failure) throws {
        let mac = Mac()
        let (defaults, items, sources) = (mac.defaults.domains, mac.keychain.groups, mac.inputSources.sources)
        switch failure {
        case .defaultsUnwritable: mac.defaults.unwritable = [new.apps.settings]
        case .defaultsReadBack: mac.defaults.garbled = ["NSWindow Frame Settings"]
        case .keychainAdd: mac.keychain.failingAdds = ["openai"]  // the second item: the first was copied
        case .keychainReadBack: mac.keychain.garbled = ["openai"]
        case .noNewGroup: mac.keychain.entitled = [old.keychainGroup]
        case .handoverAdd: mac.login.failingHandovers = [hosted.account]  // the second: the first was handed over
        case .handoverReadBack: mac.login.garbledHandovers = [replacedOpenAI.account]
        case .swap: mac.switcher.failingSwap = true
        case .launch: mac.switcher.failingLaunch = true
        case .register: mac.inputSources.failingRegister = true
        case .enable: mac.inputSources.failingEnable = true
        }
        let report = mac.run()
        #expect(!report.switched && report.error != nil && !report.notRestored)
        // The new domains and group as they were (the new input method's own key kept), the old ones untouched.
        #expect(NSDictionary(dictionary: mac.defaults.domains).isEqual(to: defaults))
        #expect(mac.keychain.groups[old.keychainGroup] == items[old.keychainGroup])
        #expect(mac.keychain.groups[new.keychainGroup]?.isEmpty ?? true)
        // The previous apps, and the old input source enabled and selected again; the new one not left enabled.
        #expect(mac.switcher.state == .old && !mac.switcher.committed)
        #expect(mac.inputSources.sources[old.inputSource] == sources[old.inputSource])
        #expect(mac.inputSources.sources[new.inputSource]?.enabled != true)
        #expect(mac.leftovers.apps.count == 1 && mac.leftovers.agents.count == 1)
        #expect(!mac.events.list.contains { $0.hasPrefix("input: disabled \(old.inputSource)") || $0.hasPrefix("switch: committed") })
        // The login keychain's keys where they were, no handover item left, and no record.
        for (key, value) in [(claude, secrets[2]), (hosted, secrets[3]), (replacedOpenAI, secrets[4])] {
            #expect(mac.original(key) == value && mac.handedOver(key) == nil, "\(key)")
        }
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
    }

    @Test func previousAppsThatCantBePutBackAreSaidSo() {
        let mac = Mac()
        mac.switcher.failingLaunch = true
        mac.switcher.notRestorable = true
        let report = mac.run()
        #expect(!report.switched && report.notRestored)
        #expect(report.error?.contains("/test/aside") == true)
        // The copies are taken out anyway: the old identity is the one to recover.
        #expect(mac.keychain.groups[new.keychainGroup]?.isEmpty ?? true)
        #expect(mac.defaults.domains[new.apps.settings] == nil)
    }

    // MARK: The cleanup, and another run

    @Test func aCleanupStepThatFailsIsLeftForTheNextRunAndNeverUndoesTheSwitch() {
        let mac = Mac()
        mac.keychain.failingDeletes = ["openai"]
        mac.inputSources.failingDisable = true
        var report = mac.run()
        #expect(report.switched && report.error == nil)
        #expect(report.pending == [.inputSource, .keychain])
        #expect(mac.switcher.state == .new && mac.events.index("switch: rolled back") == nil)
        // The copies stay; the rest of the cleanup was done.
        #expect(mac.keychain.groups[new.keychainGroup]?.count == 2 && mac.keychain.groups[old.keychainGroup] == [openAI: Data(secrets[0].utf8)])
        #expect(mac.defaults.domains[old.apps.inputMethod] == nil && mac.leftovers.apps.isEmpty)

        // The next run (the new identity installed now) does what was left.
        mac.keychain.failingDeletes = []
        mac.inputSources.failingDisable = false
        report = mac.run()
        #expect(report.switched && report.pending.isEmpty && report.copiedItems == 0)
        #expect(mac.keychain.groups[old.keychainGroup]?.isEmpty == true && mac.keychain.groups[new.keychainGroup]?.count == 2)
        #expect(mac.inputSources.sources[old.inputSource]?.enabled == false)
    }

    @Test func anotherRunChangesNothing() {
        let mac = Mac()
        #expect(mac.run().switched)
        let (defaults, items, sources) = (mac.defaults.domains, mac.keychain.groups, mac.inputSources.sources)
        let events = mac.events.list.count
        let report = mac.run()
        #expect(report.switched && report.pending.isEmpty && report.copiedKeys == 0 && report.copiedItems == 0)
        #expect(NSDictionary(dictionary: mac.defaults.domains).isEqual(to: defaults))
        #expect(mac.keychain.groups == items && mac.inputSources.sources == sources)
        #expect(mac.events.list.count == events)
    }

    @Test func aNewIdentityInstalledWithoutTheMoveGetsTheCopiesBeforeTheOldGoes() {
        // The new identity installed some other way (its installer's "install anyway"): the old one's keys and items are
        // copied first, then deleted.
        let mac = Mac()
        mac.switcher.state = .new
        let report = mac.run()
        #expect(report.switched && report.pending.isEmpty)
        #expect(mac.defaults.domains[new.apps.inputMethod]?["recentApps"] as? [String] == ["com.apple.TextEdit"])
        #expect(mac.defaults.domains[new.apps.inputMethod]?["shared"] as? String == "new")
        #expect(mac.keychain.groups[new.keychainGroup] == [openAI: Data(secrets[0].utf8), gemini: Data(secrets[1].utf8)])
        #expect(mac.keychain.groups[old.keychainGroup]?.isEmpty == true && mac.defaults.domains[old.apps.inputMethod] == nil)
        // The login keychain's keys handed over first, then deleted.
        #expect(mac.handedOver(claude) == secrets[2] && mac.original(claude) == nil && mac.handedOver(replacedOpenAI) == secrets[4])
    }

    /// Keys the new identity imported already (it can't be read without asking by this one) are never deleted.
    @Test func aKeyTheNewIdentityImportedIsNeverDeleted() {
        let mac = Mac()
        #expect(mac.run().switched)
        // The new identity imported the key: its own item, which this identity would have to ask for.
        _ = mac.login.store(claude.service).write(claude.account, "sk-test-imported", "AllInOneIME: claude", "", nil, savedAt)
        mac.login.unreadable = [claude.account]
        let report = mac.run()
        #expect(report.switched && report.pending.isEmpty)
        #expect(mac.original(claude) == "sk-test-imported")
    }

    // MARK: The real pieces, on the test's own

    /// `AppsSwitch` with the test install's stores (`Migration.test`, as `make update-test` uses them): real app bundles
    /// swapped in a folder of the test's own, the stores' files written as the migration goes.
    @Test func aTestInstallMovesWithItsOwnFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inputMethods = root.appendingPathComponent("Input Methods"), applications = root.appendingPathComponent("Applications")
        let installed = inputMethods.appendingPathComponent(Updater.inputMethodName), settings = applications.appendingPathComponent(Updater.settingsAppName)
        let staged = root.appendingPathComponent("staged")
        try FakeApp.make(installed, id: old.apps.inputMethod, version: "0.7.1", build: "24", sign: false)
        try FakeApp.make(settings, id: old.apps.settings, version: "0.7.1", build: "24", sign: false)
        try FakeApp.make(applications.appendingPathComponent("AllInOneIME Settings 2.app"), id: old.apps.settings, version: "0.7.0", build: "23", sign: false)
        try FakeApp.make(staged.appendingPathComponent(Updater.inputMethodName), id: new.apps.inputMethod, version: "0.7.2", build: "25", sign: false)
        try FakeApp.make(staged.appendingPathComponent(Updater.settingsAppName), id: new.apps.settings, version: "0.7.2", build: "25", sign: false)
        let defaults = FileDefaults(folder: root.appendingPathComponent("Preferences"))
        #expect(defaults.set("old value", forKey: "recentApps", in: old.apps.inputMethod))
        let keychain = FileKeychain(folder: root.appendingPathComponent("Keychain"))
        #expect(keychain.add(openAI, MigrationKeychainValue(data: Data(secrets[0].utf8), attributes: ["labl": "AllInOneIME: OpenAI"]),
                             to: old.keychainGroup) == errSecSuccess)
        let login = IdentityHandover.fileStore(root.appendingPathComponent("Keychain/login.plist"), service: APIKeys.service)
        #expect(login.write("claude", secrets[2], "AllInOneIME: Claude", "api.anthropic.com", nil, savedAt) == .ok)
        let sources = FileInputSources(file: root.appendingPathComponent("InputSources.plist"))
        #expect(sources.register(installed, id: old.inputSource) && sources.enable(old.inputSource) && sources.select(old.inputSource))
        let agents = root.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try (["Label": Migration.oldLabelPrefix + "realtest-watch"] as NSDictionary).write(to: agents.appendingPathComponent("watch.plist"))
        try (["Label": "com.example.other"] as NSDictionary).write(to: agents.appendingPathComponent("other.plist"))

        func version(_ app: URL) -> String? { NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String }
        let switcher = AppsSwitch(placing: [(staged.appendingPathComponent(Updater.inputMethodName), installed),
                                            (staged.appendingPathComponent(Updater.settingsAppName), settings)],
                                  replacing: [installed, settings], aside: root.appendingPathComponent("previous"),
                                  inputMethod: installed, version: "0.7.2", stop: {},
                                  launchCheck: { app, wanted in guard version(app) == wanted else { throw MigrationError("doesn't start") } })
        let report = Migration.test(root: root, say: { _ in }).run(switcher)
        #expect(report.switched && report.pending.isEmpty, "\(report.lines)")
        #expect(NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String == new.apps.inputMethod)
        #expect(version(settings) == "0.7.2" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("previous").path))
        #expect(defaults.domain(new.apps.inputMethod)?["recentApps"] as? String == "old value" && defaults.domain(old.apps.inputMethod) == nil)
        #expect(keychain.value(of: openAI, in: new.keychainGroup)?.data == Data(secrets[0].utf8))
        #expect(keychain.value(of: openAI, in: new.keychainGroup)?.attributes["labl"] as? String == "AllInOneIME: OpenAI")
        #expect(try keychain.items(in: old.keychainGroup).isEmpty)
        // The login keychain's key handed over into the new group's file (beside the copied items), then deleted.
        let handover = IdentityHandover.fileStore(root.appendingPathComponent("Keychain/\(new.keychainGroup).plist"),
                                                  service: IdentityHandover.handoverService(for: APIKeys.service))
        #expect(handover.read("claude") == secrets[2] && handover.attributes("claude")?.comment == "api.anthropic.com")
        #expect(login.accounts().isEmpty && !FileManager.default.fileExists(atPath: root.appendingPathComponent(CleanupRecord.fileName).path))
        #expect(sources.state(of: new.inputSource) == MigrationInputSourceState(registered: true, enabled: true, selected: true))
        #expect(sources.state(of: old.inputSource).enabled == false)
        // The stray old Settings app and the old label's agent are gone; another app's agent stays.
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == [Updater.settingsAppName])
        #expect(try FileManager.default.contentsOfDirectory(atPath: agents.path) == ["other.plist"])
    }

    /// The user's defaults as the migration reads and writes them (`UserDefaults(suiteName:)`, `persistentDomain`,
    /// `removePersistentDomain`), on domains of the test's own.
    @Test func systemDefaultsReadWriteAndRemoveADomain() throws {
        let domain = "com.allinoneime.tests.migration.\(UUID().uuidString)"
        let defaults = SystemDefaults()
        #expect(defaults.domain(domain) == nil)
        #expect(defaults.set(["a", "b"], forKey: "list", in: domain) && defaults.set(Data([1, 2]), forKey: "data", in: domain))
        defaults.flush(domain)
        #expect(defaults.domain(domain)?["list"] as? [String] == ["a", "b"] && defaults.domain(domain)?["data"] as? Data == Data([1, 2]))
        defaults.remove("data", from: domain)
        #expect(defaults.domain(domain)?.keys.sorted() == ["list"])
        defaults.removeDomain(domain)
        #expect(defaults.domain(domain)?.isEmpty ?? true)
        // No file left under the domain's name, once cfprefsd has emptied it.
        #expect(defaults.deleteEmptiedFiles(of: [domain]) == [domain])
        #expect(!FileManager.default.fileExists(atPath: defaults.preferences.appendingPathComponent(domain + ".plist").path))
    }
}
