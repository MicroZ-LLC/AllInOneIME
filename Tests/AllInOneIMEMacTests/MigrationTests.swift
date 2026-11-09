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
        /// The files asked to be deleted once emptied (each call's domains).
        var emptied: [[String]] = []
        func deleteEmptiedFiles(of domains: [String]) -> [String] {
            emptied.append(domains)
            return domains
        }
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

    /// Text Input Sources as this macOS has them: a new input method is the user's to add (the move never asks; a test
    /// adds it as the user would, setting it enabled). The user's keyboard layout is selected apart from the
    /// sources (`layoutSelected`); an input source's entries in the user's input sources are its enabled, listed and
    /// selected. `filedUnder`: the bundle ID Text Input Sources files the new input source under (another than its own
    /// had it taken the old one's path).
    final class FakeInputSources: MigrationInputSources {
        var sources: [String: MigrationInputSourceState] = [:]
        var failingRegister = false, failingDisable = false, failingRemove = false
        var filedUnder: String?
        var layoutSelected = false
        /// Run as an input source's state is asked (what the record says then).
        var onState: (String) -> Void = { _ in }
        let events: Events
        init(_ events: Events) { self.events = events }

        func state(of id: String) -> MigrationInputSourceState {
            onState(id)
            var state = sources[id] ?? MigrationInputSourceState()
            if let filedUnder, id == new.inputSource, state.registered { state.bundleID = filedUnder }
            return state
        }
        func register(_ bundle: URL, id: String) -> Bool {
            guard !failingRegister else { return false }
            sources[id, default: MigrationInputSourceState()].registered = true
            events.list.append("input: registered \(id) at \(bundle.lastPathComponent)")
            return true
        }
        func select(_ id: String) -> Bool {
            guard state(of: id).enabled else { return false }
            for key in sources.keys { sources[key]?.selected = key == id }
            layoutSelected = false
            events.list.append("input: selected \(id)")
            return true
        }
        func selectKeyboardLayout() -> Bool {
            for key in sources.keys { sources[key]?.selected = false }
            layoutSelected = true
            events.list.append("input: selected the keyboard layout")
            return true
        }
        func removeEntries(of id: String) -> InputSourceEntries? {
            guard !failingRemove else { return nil }
            guard let source = sources[id], source.added || source.selected else { return InputSourceEntries([:]) }
            sources[id]?.enabled = false
            sources[id]?.listed = false
            sources[id]?.selected = false
            events.list.append("input: entries out \(id)")
            return InputSourceEntries([id: ["enabled": source.enabled, "listed": source.listed, "selected": source.selected]])
        }
        func restore(_ entries: InputSourceEntries) -> Bool {
            for (id, flags) in entries.values {
                let flags = flags as? [String: Bool] ?? [:]
                sources[id, default: MigrationInputSourceState()].enabled = flags["enabled"] ?? false
                sources[id]?.listed = flags["listed"] ?? false
                sources[id]?.selected = flags["selected"] ?? false
            }
            events.list.append("input: entries back")
            return true
        }
        func disable(_ id: String) -> Bool {
            guard !failingDisable else { return false }
            guard let source = sources[id], source.added || source.selected else { return true }
            sources[id]?.enabled = false
            sources[id]?.listed = false
            sources[id]?.selected = false
            events.list.append("input: disabled \(id)")
            return true
        }
    }

    final class FakeLeftovers: MigrationLeftovers {
        var apps: [URL] = [], agents: [MigrationLaunchAgent] = [], caches: [URL] = []
        let events: Events
        init(_ events: Events) { self.events = events }

        func oldCaches() -> [URL] { caches }
        func remove(cache: URL) -> Bool {
            caches.removeAll { $0 == cache }
            events.list.append("leftovers: removed \(cache.lastPathComponent)")
            return true
        }

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
        let inputMethod = URL(fileURLWithPath: "/test/Input Methods/AllInOneIME Input.app")
        let oldInputMethod = URL(fileURLWithPath: "/test/Input Methods/AllInOneIME.app")
        var installed: [URL] { [oldInputMethod, URL(fileURLWithPath: "/test/Applications/AllInOneIME Settings.app")] }
        let previousApps = [URL(fileURLWithPath: "/test/aside/0-AllInOneIME.app"), URL(fileURLWithPath: "/test/aside/1-AllInOneIME Settings.app")]
        /// Run as the swap starts (what the record says then).
        var onPerform: () -> Void = {}
        var state = Installed.old
        var failingSwap = false, failingLaunch = false, notRestorable = false
        /// The launch's failure as an update's check says it (`UpdateStaging.launchCheck`).
        var launchFailure: any Error = MigrationError("the new input method doesn't start")
        var swapped = false, committed = false
        let events: Events
        init(_ events: Events) { self.events = events }

        var isSwitched: Bool { state == .new }
        /// As `AppsSwitch` does it, and logs it.
        func perform(log: (String) -> Void) throws {
            events.list.append("switch: perform")
            onPerform()
            guard !failingSwap else { throw MigrationError("the swap failed") }
            state = .new
            log("apps: swapped")
            guard !failingLaunch else {
                var reason = (launchFailure as? LocalizedError)?.errorDescription ?? "\(launchFailure)"
                if case let UpdateError.invalidApp(detail) = launchFailure { reason = detail }
                log("rolling back: \(reason)")
                if notRestorable { throw BundleSwap.Failure.notRestored("doesn't start", folder: "/test/aside") }
                state = .old
                log("apps: the previous ones are back")
                throw launchFailure
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
            inputSources.sources[old.inputSource] = MigrationInputSourceState(registered: true, enabled: true, listed: true, selected: true)
            leftovers.apps = [URL(fileURLWithPath: "/test/Applications/AllInOneIME Settings copy.app")]
            leftovers.caches = [URL(fileURLWithPath: "/test/Caches/\(old.apps.inputMethod)")]
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

        /// Switched and all done: the old input source's entries out of the user's input sources (the new one left to the
        /// user to add), every cleanup step done, the record gone.
        func done(_ report: Migration.Report) -> Bool {
            report.switched && report.error == nil && report.pending.isEmpty && !report.inputSourceEnabled
                && inputSources.sources[old.inputSource]?.added == false && inputSources.sources[old.inputSource]?.selected == false
                && !FileManager.default.fileExists(atPath: record.path)
        }
    }

    // MARK: Each step

    @Test func theSettingsAndKeysMoveAndTheOldIdentityIsCleanedUp() throws {
        let mac = Mac()
        let report = mac.run()
        #expect(mac.done(report))

        // a. The keys the new domains lacked, the new one's own kept; the old domains gone.
        #expect(report.copiedKeys == 3)
        let ime = try #require(mac.defaults.domains[new.apps.inputMethod])
        #expect(ime["shared"] as? String == "new" && ime["recentApps"] as? [String] == ["com.apple.TextEdit"]
                && ime["updateLastSuccess"] as? Date == Date(timeIntervalSince1970: 1))
        #expect(mac.defaults.domains[new.apps.settings]?["NSWindow Frame Settings"] as? String == "0 0 100 100")
        #expect(mac.defaults.domains[old.apps.inputMethod] == nil && mac.defaults.domains[old.apps.settings] == nil)
        #expect(mac.defaults.emptied == [old.domains])

        // b. Every item into the new group, synced or not as it was; the old group empty.
        #expect(report.copiedItems == 2)
        #expect(mac.keychain.groups[new.keychainGroup] == [openAI: Data(secrets[0].utf8), gemini: Data(secrets[1].utf8)])
        #expect(mac.keychain.groups[old.keychainGroup]?.isEmpty == true)

        // c. The new input source registered at its own path, never asked to be enabled (only the user can add it); the
        // keyboard layout selected, the old one's entries out at once; d. the rest cleaned up.
        #expect(mac.switcher.state == .new && mac.switcher.committed)
        #expect(mac.inputSources.sources[new.inputSource] == MigrationInputSourceState(registered: true))
        #expect(mac.events.index("input: registered \(new.inputSource) at AllInOneIME Input.app") != nil)
        #expect(mac.inputSources.layoutSelected && mac.inputSources.sources[old.inputSource]?.added == false)
        #expect(mac.leftovers.apps.isEmpty && mac.leftovers.agents.isEmpty && mac.leftovers.caches.isEmpty)

        // b. The login keychain's keys handed over (never synced, label, comment and save time kept), then deleted there.
        #expect(report.handedOver == 3)
        for (key, value) in [(claude, secrets[2]), (hosted, secrets[3]), (replacedOpenAI, secrets[4])] {
            #expect(mac.handedOver(key) == value && mac.original(key) == nil, "\(key)")
            let attributes = try #require(mac.login.handoverStore(key.service).attributes(key.account))
            #expect(attributes.label == "AllInOneIME: \(key.account)" && attributes.comment == "api.example.com")
            #expect(IdentityHandover.same(attributes.saved, savedAt))
        }
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
        for cleanup in ["defaults: removed", "keychain: deleted", "login: deleted", "leftovers:", "switch: committed"] {
            #expect(try #require(events.index(cleanup)) > max(verified, registered), "\(cleanup)")
        }
        let swap = try #require(events.index("switch: perform"))
        #expect(try #require(events.lastIndex("keychain: added")) < swap && events.lastIndex("defaults: set")! < swap)
        #expect(try #require(events.lastIndex("handover: added")) < swap)
        // The keyboard layout selected before the swap, while the old input method is still there; the old one's entries
        // out right after the new one is registered, before the cleanup (which finds none left), never one by one.
        #expect(try #require(events.index("input: selected the keyboard layout")) < swap)
        let entries = try #require(events.index("input: entries out \(old.inputSource)"))
        #expect(registered < entries && entries < events.index("defaults: removed")!)
        #expect(events.index("input: disabled") == nil && events.list.filter { $0.hasPrefix("input: entries out") }.count == 1)
    }

    /// A key the login keychain would ask for (another build saved it) is left where it is: not handed over, not deleted,
    /// and not in the record; the rest moves.
    @Test func aLoginKeyThatWouldAskIsLeftWhereItIs() throws {
        let mac = Mac()
        mac.login.unreadable = [claude.account]
        let report = mac.run()
        #expect(mac.done(report) && report.handedOver == 2)
        #expect(mac.original(claude) == secrets[2] && mac.handedOver(claude) == nil)
        #expect(mac.original(hosted) == nil && mac.handedOver(hosted) == secrets[3])
        #expect(mac.lines.contains { $0.contains("claude") && $0.contains("without asking") })
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
    /// Once the old input source's entries are out, it keeps a copy of them (to put back on a rollback). Once all is done
    /// it is gone.
    @Test func theRecordListsTheCleanupBeforeTheSwapAndGoesOnceItIsDone() throws {
        let mac = Mac()
        var atSwap: CleanupRecord?, afterEntries: CleanupRecord?
        var mode: Int?
        var text = ""
        mac.switcher.onPerform = { [unowned mac] in
            atSwap = try? mac.savedRecord()
            mode = (try? FileManager.default.attributesOfItem(atPath: mac.record.path))?[.posixPermissions] as? Int
            text = (try? String(contentsOf: mac.record, encoding: .utf8)) ?? ""
        }
        mac.inputSources.onState = { [unowned mac] id in
            if id == new.inputSource, afterEntries == nil, mac.events.index("input: entries out") != nil { afterEntries = try? mac.savedRecord() }
        }
        #expect(mac.done(mac.run()))
        let record = try #require(atSwap)
        #expect(mode == 0o600)
        #expect(!record.handedOver && !record.isHandedOver(now: record.updated.addingTimeInterval(60)))
        #expect(record.bundleIDs == [old.apps.inputMethod, old.apps.settings] && record.inputSource == old.inputSource)
        #expect(record.inputSourceEntries == nil)
        #expect(record.defaultsDomains == old.domains)
        #expect(record.apps == mac.switcher.previousApps.map(\.path) + ["/test/Applications/AllInOneIME Settings copy.app"])
        #expect(record.launchAgents == [CleanupRecord.LaunchAgent(label: Migration.oldLabelPrefix + "realtest-watch", plist: nil)])
        #expect(record.keychainGroup == old.keychainGroup)
        #expect(Set(record.keychainItems) == [CleanupRecord.KeychainItem(service: openAI.service, account: "openai", synchronizable: true),
                                              CleanupRecord.KeychainItem(service: gemini.service, account: "gemini", synchronizable: false)])
        #expect(Set(record.loginKeys) == [claude, hosted, replacedOpenAI])
        #expect(record.caches == ["/test/Caches/\(old.apps.inputMethod)"])
        // Identifiers only: no key in it.
        #expect(text.contains("claude") && !secrets.contains { text.contains($0) })
        // The copy of the old input source's entries, as they were (enabled, in the input sources, selected), not a step.
        let entries = try #require(afterEntries?.inputSourceEntries)
        #expect(entries.values[old.inputSource] as? [String: Bool] == ["enabled": true, "listed": true, "selected": false])
        #expect(afterEntries?.handedOver == false)
    }

    /// A step left is kept in the record, handed over to the new version (and only it: the steps done are out of it);
    /// another run finishes it and deletes the record.
    @Test func aStepLeftStaysInTheRecordForTheNewVersion() throws {
        let mac = Mac()
        mac.keychain.failingDeletes = ["openai"]
        mac.login.failingDeletes = [hosted.account]
        let report = mac.run()
        #expect(report.switched && report.pending == [.keychain, .loginKeys])
        let record = try #require(try mac.savedRecord())
        #expect(record.handedOver && record.isHandedOver())
        #expect(record.inputSource == nil && record.defaultsDomains.isEmpty && record.apps.isEmpty && record.launchAgents.isEmpty)
        #expect(record.keychainItems == [CleanupRecord.KeychainItem(service: openAI.service, account: "openai", synchronizable: true)])
        #expect(record.loginKeys == [hosted])
        // The handover item stays, and so does the original, until it is deleted.
        #expect(mac.original(hosted) == secrets[3] && mac.handedOver(hosted) == secrets[3])

        mac.keychain.failingDeletes = []
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
        let report = mac.run()
        #expect(report.switched && !report.inputSourceEnabled)
        #expect(mac.inputSources.sources[new.inputSource] == MigrationInputSourceState(registered: true, enabled: false, selected: false))
        // Only registered: no keyboard layout to select, no entry of the old one to take out.
        #expect(mac.events.list.filter { $0.hasPrefix("input: ") } == ["input: registered \(new.inputSource) at AllInOneIME Input.app"])
        #expect(report.pending.isEmpty && !FileManager.default.fileExists(atPath: mac.record.path))
    }

    // MARK: The new input source left to the user

    /// macOS lets only the user add a new input method (asked to enable one, it says it did, leaves it off and opens
    /// System Settings by itself): the move only registers it, goes on (nothing is rolled back) and says so as Text Input
    /// Sources has it. The old input source's entries go at once: from the swap on it can't be used, and macOS's consent to
    /// it doesn't carry over to the new one.
    @Test func theNewInputSourceIsLeftToTheUserAndTheOldOnesEntriesGoAtOnce() throws {
        let mac = Mac()
        let report = mac.run()
        #expect(mac.done(report))
        #expect(mac.switcher.state == .new && mac.switcher.committed && mac.events.index("switch: rolled back") == nil)
        // The keyboard layout selected before the swap; the new one registered, nothing else asked of it (never selected
        // while it isn't enabled as itself); the old one's entries out once.
        #expect(mac.events.list.filter { $0.hasPrefix("input: ") } == ["input: selected the keyboard layout",
                                                                        "input: registered \(new.inputSource) at AllInOneIME Input.app",
                                                                        "input: entries out \(old.inputSource)"])
        #expect(mac.inputSources.layoutSelected && !mac.inputSources.state(of: new.inputSource).enabled)
        // The truth logged: not enabled (not "enabled, selected"), the step, and that nothing of AllInOneIME works until
        // then.
        #expect(!mac.lines.contains { $0.contains("registered, enabled") })
        let line = try #require(mac.lines.first { $0.contains("\(new.inputSource) registered, not enabled") })
        #expect(line.contains("System Settings → Keyboard → Input Sources → + → English → AllInOneIME"))
        #expect(line.contains("until then no AllInOneIME input source works") && !line.contains("kept"))
        #expect(mac.lines.contains("input source: the keyboard layout selected while the old input method is still there"))
        #expect(mac.lines.contains { $0.hasPrefix("input source: \(old.inputSource)'s entries are out of the input sources") })
        #expect(mac.defaults.domains[old.apps.inputMethod] == nil && mac.leftovers.caches.isEmpty && mac.original(claude) == nil)

        // The user adds it (System Settings): another run changes nothing of it, and nothing else.
        mac.inputSources.sources[new.inputSource]?.enabled = true
        mac.inputSources.sources[new.inputSource]?.listed = true
        let again = mac.run()
        #expect(again.switched && again.pending.isEmpty && again.inputSourceEnabled)
        #expect(mac.inputSources.sources[old.inputSource]?.added == false && mac.inputSources.sources[new.inputSource]?.enabled == true)
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
    }

    /// Text Input Sources files the new input source under another bundle ID (as at the old one's path): the move is
    /// undone, the old input source's entries put back from the copy and the old one selected again.
    @Test func aNewInputSourceFiledUnderAnotherBundleIDPutsEverythingBack() throws {
        let mac = Mac()
        let sources = mac.inputSources.sources
        mac.inputSources.filedUnder = old.inputSource
        let report = mac.run()
        #expect(!report.switched && report.error == "input source: Text Input Sources files \(new.inputSource) under \(old.inputSource)")
        #expect(mac.switcher.state == .old && !mac.switcher.committed)
        #expect(mac.inputSources.sources[old.inputSource] == sources[old.inputSource] && !mac.inputSources.layoutSelected)
        let events = mac.events
        #expect(try #require(events.index("input: entries out")) < events.index("switch: rolled back")!)
        #expect(try #require(events.index("switch: rolled back")) < events.index("input: entries back")!)
        #expect(try #require(events.index("input: entries back")) < events.lastIndex("input: selected \(old.inputSource)")!)
        #expect(events.index("input: registered \(old.inputSource) at AllInOneIME.app") != nil)
        #expect(mac.lines.contains("input source: \(old.inputSource)'s entries are back in the input sources"))
        #expect(!FileManager.default.fileExists(atPath: mac.record.path) && mac.defaults.domains[new.apps.settings] == nil)
    }

    /// Entries that can't be taken out at the switch (the user's preferences can't be written) don't stop it: the cleanup
    /// tries again, and leaves the step to the new version when it can't either.
    @Test func oldEntriesThatCantBeTakenOutAreLeftToTheCleanup() throws {
        let mac = Mac()
        mac.inputSources.failingRemove = true
        mac.inputSources.failingDisable = true
        var report = mac.run()
        #expect(report.switched && report.pending == [.inputSource])
        #expect(mac.lines.contains("input source: \(old.inputSource)'s entries can't be taken out of the input sources now; the cleanup does it"))
        #expect(try mac.savedRecord()?.inputSource == old.inputSource)
        mac.inputSources.failingRemove = false
        mac.inputSources.failingDisable = false
        report = mac.run()
        #expect(mac.done(report))
    }

    /// A new input source the user has enabled already (an earlier run of theirs): selected as the old one was, and the old
    /// one taken out at once.
    @Test func aNewInputSourceEnabledAlreadyIsSelectedAndTheOldOneGoes() {
        let mac = Mac()
        mac.inputSources.sources[new.inputSource] = MigrationInputSourceState(registered: true, enabled: true, listed: true)
        let report = mac.run()
        #expect(report.switched && report.pending.isEmpty && report.inputSourceEnabled)
        #expect(mac.inputSources.sources[new.inputSource]?.selected == true && mac.inputSources.sources[old.inputSource]?.added == false)
        #expect(!mac.inputSources.layoutSelected)
        #expect(mac.lines.contains("input source: \(new.inputSource) registered, enabled, selected"))
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
    }

    @Test func anotherKeyTheNewGroupHasIsKeptAndTheOldOneLeft() throws {
        let mac = Mac()
        // Another Mac moved first: its key for OpenAI synced into the new group here.
        mac.keychain.groups[new.keychainGroup] = [openAI: Data("sk-test-other-mac".utf8)]
        let report = mac.run()
        #expect(mac.done(report) && report.copiedItems == 1)
        #expect(mac.keychain.groups[new.keychainGroup]?[openAI] == Data("sk-test-other-mac".utf8))
        #expect(mac.keychain.groups[new.keychainGroup]?[gemini] == Data(secrets[1].utf8))
        // Never deleted: the only copy of that key.
        #expect(mac.keychain.groups[old.keychainGroup] == [openAI: Data(secrets[0].utf8)])
        #expect(mac.lines.contains { $0.contains("kept") && $0.contains("openai") })
    }

    @Test func aBuildWithoutTheKeychainEntitlementLeavesTheKeychainAlone() throws {
        let mac = Mac()
        mac.keychain.entitled = []
        let report = mac.run()
        #expect(mac.done(report) && report.copiedItems == 0 && report.handedOver == 0)
        #expect(mac.keychain.groups[old.keychainGroup]?.count == 2 && mac.keychain.groups[new.keychainGroup] == nil)
        // The login keychain's keys stay (the new identity asks once for each): nothing handed over.
        #expect(mac.original(claude) == secrets[2] && mac.handedOver(claude) == nil && mac.original(hosted) == secrets[3])
    }

    // MARK: A failure before the switch

    enum Failure: String, CaseIterable {
        case defaultsUnwritable, defaultsReadBack, keychainAdd, keychainReadBack, noNewGroup, handoverAdd, handoverReadBack
        case swap, launch, register, filedUnderAnother
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
        case .filedUnderAnother: mac.inputSources.filedUnder = old.inputSource
        }
        let report = mac.run()
        #expect(!report.switched && report.error != nil && !report.notRestored)
        // The new domains and group as they were (the new input method's own key kept), the old ones untouched.
        #expect(NSDictionary(dictionary: mac.defaults.domains).isEqual(to: defaults))
        #expect(mac.keychain.groups[old.keychainGroup] == items[old.keychainGroup])
        #expect(mac.keychain.groups[new.keychainGroup]?.isEmpty ?? true)
        // The previous apps, and the old input source's entries as they were, selected again; the new one not left enabled.
        #expect(mac.switcher.state == .old && !mac.switcher.committed)
        #expect(mac.inputSources.sources[old.inputSource] == sources[old.inputSource] && !mac.inputSources.layoutSelected)
        #expect(mac.inputSources.sources[new.inputSource]?.enabled != true)
        #expect(mac.leftovers.apps.count == 1 && mac.leftovers.agents.count == 1 && mac.leftovers.caches.count == 1)
        #expect(!mac.events.list.contains { $0.hasPrefix("input: disabled \(old.inputSource)") || $0.hasPrefix("switch: committed") })
        // A domain the copies created is removed with its file, once emptied (none of them when no key was written).
        let created = mac.events.index("defaults: set \(new.apps.settings)") != nil
        #expect(mac.defaults.emptied == (created ? [[new.apps.settings]] : []))
        // The login keychain's keys where they were, no handover item left, and no record.
        for (key, value) in [(claude, secrets[2]), (hosted, secrets[3]), (replacedOpenAI, secrets[4])] {
            #expect(mac.original(key) == value && mac.handedOver(key) == nil, "\(key)")
        }
        #expect(!FileManager.default.fileExists(atPath: mac.record.path))
    }

    /// A new input method that doesn't start once swapped in: what is said is that, and that the previous version is back,
    /// never an update check's "nothing was changed" (the copies and the swap were made, then taken back).
    @Test func aLaunchThatFailsAfterTheSwapIsSaidWithoutNothingWasChanged() throws {
        let mac = Mac()
        mac.switcher.failingLaunch = true
        mac.switcher.launchFailure = UpdateError.invalidApp("AllInOneIME.app doesn't start (-1: not executable)")
        let report = mac.run()
        #expect(!report.switched && report.error == "AllInOneIME.app doesn't start (-1: not executable)")
        #expect(!mac.lines.contains { $0.contains("nothing was changed") })
        #expect(mac.lines.contains { $0.hasPrefix("undone: ") && $0.contains("taken out again") })
        #expect(mac.lines.contains("rolling back: AllInOneIME.app doesn't start (-1: not executable)"))
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
        var report = mac.run()
        #expect(report.switched && report.error == nil)
        #expect(report.pending == [.keychain])
        #expect(mac.switcher.state == .new && mac.events.index("switch: rolled back") == nil)
        // The copies stay; the rest of the cleanup was done.
        #expect(mac.keychain.groups[new.keychainGroup]?.count == 2 && mac.keychain.groups[old.keychainGroup] == [openAI: Data(secrets[0].utf8)])
        #expect(mac.defaults.domains[old.apps.inputMethod] == nil && mac.leftovers.apps.isEmpty)
        #expect(mac.lines.contains { $0.contains("old keychain items not done; left for") })

        // The next run (the new identity installed now) does what was left.
        mac.keychain.failingDeletes = []
        report = mac.run()
        #expect(mac.done(report) && report.copiedItems == 0)
        #expect(mac.keychain.groups[old.keychainGroup]?.isEmpty == true && mac.keychain.groups[new.keychainGroup]?.count == 2)
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
        // Its input source not added yet: the old one goes anyway (it can't be used).
        #expect(mac.done(report))
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

    // MARK: Text Input Sources in a process of its own

    /// The update helper asks Text Input Sources through this executable's `--input-source` (one call each, one line of
    /// JSON back), never itself; a call that fails, or prints no answer, is taken for nothing done.
    @Test func textInputSourcesAreAskedInAProcessOfTheirOwn() throws {
        let events = Events()
        let fake = FakeInputSources(events)
        var calls: [[String]] = []
        // The child: the fake's answers, as `InputSourceCommand` prints them (after whatever else it printed).
        let child = ChildInputSources(executable: { "/aside/0-AllInOneIME.app/Contents/MacOS/AllInOneIME" }, run: { path, arguments in
            calls.append([path] + arguments)
            guard arguments.first == InputSourceCommand.option, arguments.count >= 3 else { return (2, "") }
            let (call, id) = (arguments[1], arguments[2])
            let done: Bool
            var entries: InputSourceEntries?
            switch call {
            case "state": done = true
            case "register": done = fake.register(URL(fileURLWithPath: arguments[3]), id: id)
            case "select": done = fake.select(id)
            case "select-layout": done = fake.selectKeyboardLayout()
            case "remove-entries":
                entries = fake.removeEntries(of: id)
                done = entries != nil
            case "restore-entries": done = fake.restore(InputSourceEntries(plist: Data(base64Encoded: arguments[3])!))
            case "disable": done = fake.disable(id)
            default: return (2, "")
            }
            let answer = InputSourceCommand.Answer(done: done, state: fake.state(of: id), entries: entries)
            return (0, "dictionaries: ready\n" + String(decoding: try! JSONEncoder().encode(answer), as: UTF8.self) + "\n")
        })
        #expect(child.register(URL(fileURLWithPath: "/test/Input Methods/AllInOneIME.app"), id: new.inputSource))
        #expect(calls.last == ["/aside/0-AllInOneIME.app/Contents/MacOS/AllInOneIME", "--input-source", "register", new.inputSource,
                               "/test/Input Methods/AllInOneIME.app"])
        #expect(child.state(of: new.inputSource) == MigrationInputSourceState(registered: true))
        // Not enabled (only the user adds it): it can't be selected, and the state is as Text Input Sources has it.
        #expect(!child.select(new.inputSource) && !child.state(of: new.inputSource).enabled)
        fake.sources[new.inputSource]?.enabled = true
        #expect(child.select(new.inputSource) && child.state(of: new.inputSource).selected)
        #expect(child.disable(new.inputSource) && !child.state(of: new.inputSource).added)
        // The keyboard layout; the entries out, a copy back, and put back from it.
        #expect(child.selectKeyboardLayout() && fake.layoutSelected && calls.last?.suffix(2) == ["select-layout", "-"])
        fake.sources[old.inputSource] = MigrationInputSourceState(registered: true, enabled: true, listed: true)
        let copy = try #require(child.removeEntries(of: old.inputSource))
        #expect(!copy.isEmpty && !child.state(of: old.inputSource).added)
        #expect(child.restore(copy) && calls.last?[2] == "restore-entries" && child.state(of: old.inputSource).listed)
        #expect(child.removeEntries(of: "com.example.none")?.isEmpty == true)

        // No executable, a failed run, or no answer: nothing done, nothing known.
        let failing = ChildInputSources(executable: { "/nowhere" }, run: { _, _ in (1, "{\"done\":true}") })
        #expect(!failing.select(new.inputSource) && failing.state(of: new.inputSource) == MigrationInputSourceState())
        let mute = ChildInputSources(executable: { "/nowhere" }, run: { _, _ in (0, "no answer") })
        #expect(!mute.disable(old.inputSource) && mute.removeEntries(of: old.inputSource) == nil && !mute.selectKeyboardLayout())
        let none = ChildInputSources(executable: { nil }, run: { _, _ in Issue.record("run without an executable"); return (0, "") })
        #expect(!none.register(URL(fileURLWithPath: "/x.app"), id: new.inputSource))
    }

    /// `--input-source`'s answer: the input source as it is after the call, read from its last line that is one.
    @Test func anInputSourceAnswerReadsBack() throws {
        let answer = InputSourceCommand.Answer(done: false, state: MigrationInputSourceState(registered: true, enabled: true, listed: false,
                                                                                            selected: false, bundleID: old.inputSource))
        let line = String(decoding: try JSONEncoder().encode(answer), as: UTF8.self)
        #expect(InputSourceCommand.answer(from: "{not json\n" + line + "\n\n") == answer)
        #expect(InputSourceCommand.answer(from: "") == nil && InputSourceCommand.answer(from: "{\"done\": 1}") == nil)
        // Filed under the old bundle ID: enabled, but not as itself.
        #expect(answer.state.added && !answer.state.isEnabled(as: new.inputSource) && answer.state.isEnabled(as: old.inputSource))
        #expect(MigrationInputSourceState(registered: true, enabled: true).isEnabled(as: new.inputSource))
        #expect(!MigrationInputSourceState(registered: false, enabled: true).isEnabled(as: new.inputSource))
        // A bad call is refused before anything is asked; there is none to enable one (only the user adds it).
        let fake = FakeInputSources(Events())
        #expect(InputSourceCommand.run(["state"], sources: fake) == 2 && InputSourceCommand.run(["unknown", "x"], sources: fake) == 2)
        #expect(InputSourceCommand.run(["enable", new.inputSource], sources: fake) == 2)
        #expect(InputSourceCommand.run(["register", new.inputSource], sources: fake) == 2 && fake.sources.isEmpty)
        #expect(InputSourceCommand.run(["restore-entries", "-", "not base64!"], sources: fake) == 2)
        // The copy `remove-entries` made goes back with the answer.
        let entries = InputSourceEntries([old.inputSource: ["enabled": true]])
        let withCopy = InputSourceCommand.Answer(done: true, state: MigrationInputSourceState(), entries: entries)
        #expect(InputSourceCommand.answer(from: String(decoding: try JSONEncoder().encode(withCopy), as: UTF8.self)) == withCopy)
    }

    // MARK: The real pieces, on the test's own

    /// `AppsSwitch` with the test install's stores (`Migration.test`, as `make update-test` uses them): real app bundles
    /// swapped in a folder of the test's own, the stores' files written as the migration goes.
    @Test func aTestInstallMovesWithItsOwnFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inputMethods = root.appendingPathComponent("Input Methods"), applications = root.appendingPathComponent("Applications")
        let installed = inputMethods.appendingPathComponent(Updater.inputMethodName), settings = applications.appendingPathComponent(Updater.settingsAppName)
        let moved = inputMethods.appendingPathComponent(Migration.newInputMethodName)
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
        try ([old.inputSource: ["registered": true, "enabled": true, "selected": true]] as NSDictionary).write(to: sources.file)
        let agents = root.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try (["Label": Migration.oldLabelPrefix + "realtest-watch"] as NSDictionary).write(to: agents.appendingPathComponent("watch.plist"))
        try (["Label": "com.example.other"] as NSDictionary).write(to: agents.appendingPathComponent("other.plist"))
        let caches = root.appendingPathComponent("Caches")
        for name in [old.apps.inputMethod, "com.example.other"] {
            try FileManager.default.createDirectory(at: caches.appendingPathComponent("\(name)/e5bundlecache"), withIntermediateDirectories: true)
        }

        func version(_ app: URL) -> String? { NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String }
        let switcher = AppsSwitch(placing: [(staged.appendingPathComponent(Updater.inputMethodName), moved),
                                            (staged.appendingPathComponent(Updater.settingsAppName), settings)],
                                  replacing: [installed, settings, moved], aside: root.appendingPathComponent("previous"),
                                  inputMethod: moved, oldInputMethod: installed, version: "0.7.2", stop: {},
                                  launchCheck: { app, wanted in guard version(app) == wanted else { throw MigrationError("doesn't start") } })
        let report = Migration.test(root: root, say: { _ in }).run(switcher)
        #expect(report.switched && report.pending.isEmpty, "\(report.lines)")
        // The new input method at its own path, the old one's gone from Input Methods.
        #expect(NSDictionary(contentsOf: moved.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String == new.apps.inputMethod)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inputMethods.path) == [Migration.newInputMethodName])
        #expect(version(settings) == "0.7.2" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("previous").path))
        #expect(defaults.domain(new.apps.inputMethod)?["recentApps"] as? String == "old value" && defaults.domain(old.apps.inputMethod) == nil)
        #expect(keychain.value(of: openAI, in: new.keychainGroup)?.data == Data(secrets[0].utf8))
        #expect(keychain.value(of: openAI, in: new.keychainGroup)?.attributes["labl"] as? String == "AllInOneIME: OpenAI")
        #expect(try keychain.items(in: old.keychainGroup).isEmpty)
        // The login keychain's key handed over into the new group's file (beside the copied items), then deleted.
        let handover = IdentityHandover.fileStore(root.appendingPathComponent("Keychain/\(new.keychainGroup).plist"),
                                                  service: IdentityHandover.handoverService(for: APIKeys.service))
        #expect(handover.read("claude") == secrets[2] && handover.attributes("claude")?.comment == "api.anthropic.com")
        #expect(login.accounts().isEmpty)
        // The new input source registered, left to the user; the keyboard layout selected, the old one's entries out, and
        // the record gone.
        let record = root.appendingPathComponent(CleanupRecord.fileName)
        #expect(sources.state(of: new.inputSource) == MigrationInputSourceState(registered: true))
        #expect(sources.state(of: FileInputSources.keyboardLayout).selected)
        #expect(!sources.state(of: old.inputSource).enabled && !sources.state(of: old.inputSource).selected)
        #expect(!FileManager.default.fileExists(atPath: record.path))
        // The stray old Settings app and the old label's agent are gone; another app's agent stays.
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == [Updater.settingsAppName])
        #expect(try FileManager.default.contentsOfDirectory(atPath: agents.path) == ["other.plist"])
        // The old input method's caches go; another app's stay.
        #expect(try FileManager.default.contentsOfDirectory(atPath: caches.path) == ["com.example.other"])

        // Another run: switched already (the new identity at its own path), nothing left to do.
        #expect(switcher.isSwitched && Migration.test(root: root, say: { _ in }).run(switcher).pending.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: record.path))
    }

    /// A failure during or right after the swap (`AppsSwitch`, real bundles in a folder of the test's own) is logged as it
    /// goes: the swap, the rollback and the previous apps back, before what went wrong; never "the new input method starts".
    @Test(arguments: [false, true])
    func aFailureAtTheSwapIsLogged(duringTheSwap: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Input Methods/\(Updater.inputMethodName)")
        let settings = root.appendingPathComponent("Applications/\(Updater.settingsAppName)")
        let staged = root.appendingPathComponent("staged")
        try FakeApp.make(installed, id: old.apps.inputMethod, version: "0.7.1", build: "24", sign: false)
        try FakeApp.make(settings, id: old.apps.settings, version: "0.7.1", build: "24", sign: false)
        try FakeApp.make(staged.appendingPathComponent(Updater.inputMethodName), id: new.apps.inputMethod, version: "0.7.2", build: "25", sign: false)
        // During: the new Settings app missing, so the swap stops halfway; after: the new input method doesn't start.
        if !duringTheSwap {
            try FakeApp.make(staged.appendingPathComponent(Updater.settingsAppName), id: new.apps.settings, version: "0.7.2", build: "25", sign: false)
        }
        #expect(FileDefaults(folder: root.appendingPathComponent("Preferences")).set("old value", forKey: "recentApps", in: old.apps.inputMethod))
        let moved = root.appendingPathComponent("Input Methods/\(Migration.newInputMethodName)")
        let switcher = AppsSwitch(placing: [(staged.appendingPathComponent(Updater.inputMethodName), moved),
                                            (staged.appendingPathComponent(Updater.settingsAppName), settings)],
                                  replacing: [installed, settings, moved], aside: root.appendingPathComponent("previous"),
                                  inputMethod: moved, oldInputMethod: installed, version: "0.7.2", stop: {},
                                  launchCheck: { _, _ in throw UpdateError.invalidApp("AllInOneIME.app doesn't start (-1: not executable)") })
        let report = Migration.test(root: root, say: { _ in }).run(switcher)
        #expect(!report.switched && !report.notRestored)
        #expect(NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
                == old.apps.inputMethod)
        let lines = report.lines
        let failed = try #require(lines.firstIndex { $0.hasPrefix("✗ ") })
        if duringTheSwap {
            let back = try #require(lines.firstIndex(of: "apps: the new ones couldn't be moved in; the previous ones are back"))
            #expect(back < failed && !lines.contains("apps: swapped"))
        } else {
            let swapped = try #require(lines.firstIndex(of: "apps: swapped"))
            let rolling = try #require(lines.firstIndex(of: "rolling back: AllInOneIME.app doesn't start (-1: not executable)"))
            let back = try #require(lines.firstIndex(of: "apps: the previous ones are back"))
            #expect(swapped < rolling && rolling < back && back < failed)
            #expect(lines[failed] == "✗ AllInOneIME.app doesn't start (-1: not executable)")
        }
        #expect(!lines.contains { $0.hasPrefix("apps: the new input method starts") } && lines.contains { $0.hasPrefix("undone: ") })
        #expect(!FileManager.default.fileExists(atPath: moved.path))
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
