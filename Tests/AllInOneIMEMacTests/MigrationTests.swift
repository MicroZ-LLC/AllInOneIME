import AllInOneIMECore
import Foundation
import Security
import Testing

private let old = Migration.old
private let new = Migration.new
private let openAI = MigrationKeychainItem(service: "AllInOneIME API key", account: "openai", synchronizable: true)
private let gemini = MigrationKeychainItem(service: "AllInOneIME API key", account: "gemini", synchronizable: false)
/// The test's keys: never in a line logged.
private let secrets = ["sk-test-openai-1", "test-gemini-2"]

/// 0.7.1's move to the new system identity (`Migration`): each step, a failure before the switch putting everything back,
/// the cleanup only after a verified switch and left for the next run when it fails, and another run changing nothing.
/// Fakes stand for the defaults, the keychain, Text Input Sources, the leftovers and the apps' swap: nothing of this Mac's
/// is read or changed (the test install's file stores and `SystemDefaults` on domains of the test's own excepted).
struct MigrationTests {
    /// What the fakes did, in order: the cleanup's events have to come after the switch's.
    final class Events {
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
        var installed = Installed.old
        var failingSwap = false, failingLaunch = false, notRestorable = false
        var swapped = false, committed = false
        let events: Events
        init(_ events: Events) { self.events = events }

        var isSwitched: Bool { installed == .new }
        func perform() throws {
            events.list.append("switch: perform")
            guard !failingSwap else { throw MigrationError("the swap failed") }
            installed = .new
            guard !failingLaunch else {
                if notRestorable { throw BundleSwap.Failure.notRestored("doesn't start", folder: "/test/aside") }
                installed = .old
                throw MigrationError("the new input method doesn't start")
            }
            swapped = true
            events.list.append("switch: verified")
        }
        func rollBack(reason: String) throws {
            if notRestorable { throw BundleSwap.Failure.notRestored(reason, folder: "/test/aside") }
            installed = .old
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
        }

        func migration() -> Migration {
            var migration = Migration(defaults: defaults, keychain: keychain, inputSources: inputSources, leftovers: leftovers,
                                      say: { [unowned self] in self.lines.append($0) })
            migration.pause = {}
            return migration
        }

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
        #expect(mac.switcher.installed == .new && mac.switcher.committed)
        #expect(mac.inputSources.sources[new.inputSource] == MigrationInputSourceState(registered: true, enabled: true, selected: true))
        #expect(mac.inputSources.sources[old.inputSource]?.enabled == false && mac.inputSources.sources[old.inputSource]?.selected == false)
        #expect(mac.leftovers.apps.isEmpty && mac.leftovers.agents.isEmpty)

        // Logged by key name and account, never with a key.
        #expect(mac.lines.contains { $0.contains("openai") } && !mac.lines.contains { line in secrets.contains { line.contains($0) } })
    }

    @Test func theCleanupStartsOnlyOnceTheSwitchIsVerified() throws {
        let mac = Mac()
        _ = mac.run()
        let events = mac.events
        let verified = try #require(events.index("switch: verified"))
        let registered = try #require(events.index("input: registered \(new.inputSource)"))
        // Nothing of the old identity removed before the new one is in and registered; the copies all before the swap.
        for cleanup in ["input: disabled", "defaults: removed", "keychain: deleted", "leftovers:", "switch: committed"] {
            #expect(try #require(events.index(cleanup)) > max(verified, registered), "\(cleanup)")
        }
        let swap = try #require(events.index("switch: perform"))
        #expect(try #require(events.lastIndex("keychain: added")) < swap && events.lastIndex("defaults: set")! < swap)
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
        #expect(report.switched && report.copiedItems == 0 && report.pending.isEmpty)
        #expect(mac.keychain.groups[old.keychainGroup]?.count == 2 && mac.keychain.groups[new.keychainGroup] == nil)
    }

    // MARK: A failure before the switch

    enum Failure: String, CaseIterable {
        case defaultsUnwritable, defaultsReadBack, keychainAdd, keychainReadBack, noNewGroup, swap, launch, register, enable
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
        #expect(mac.switcher.installed == .old && !mac.switcher.committed)
        #expect(mac.inputSources.sources[old.inputSource] == sources[old.inputSource])
        #expect(mac.inputSources.sources[new.inputSource]?.enabled != true)
        #expect(mac.leftovers.apps.count == 1 && mac.leftovers.agents.count == 1)
        #expect(!mac.events.list.contains { $0.hasPrefix("input: disabled \(old.inputSource)") || $0.hasPrefix("switch: committed") })
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
        #expect(mac.switcher.installed == .new && mac.events.index("switch: rolled back") == nil)
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
        mac.switcher.installed = .new
        let report = mac.run()
        #expect(report.switched && report.pending.isEmpty)
        #expect(mac.defaults.domains[new.apps.inputMethod]?["recentApps"] as? [String] == ["com.apple.TextEdit"])
        #expect(mac.defaults.domains[new.apps.inputMethod]?["shared"] as? String == "new")
        #expect(mac.keychain.groups[new.keychainGroup] == [openAI: Data(secrets[0].utf8), gemini: Data(secrets[1].utf8)])
        #expect(mac.keychain.groups[old.keychainGroup]?.isEmpty == true && mac.defaults.domains[old.apps.inputMethod] == nil)
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
