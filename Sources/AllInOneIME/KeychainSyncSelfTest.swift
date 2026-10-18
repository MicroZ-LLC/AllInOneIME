import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Security

extension SelfTest {
    /// API keys and passwords through iCloud Keychain (`KeySync`). A build signed with the provisioning profile (entitled
    /// to the shared access group) adds, reads and deletes items of a service of its own, "AllInOneIME self-test key",
    /// synced and not: never the user's keys. Every build checks the store it chose and the Settings row, and the sync
    /// controller's moves (the login keychain's keys moved at launch, sync turned on and off) with stores in memory and
    /// the self-test's config.
    static func testKeychainSync() {
        section("API keys through iCloud Keychain")
        let entitled = APIKeys.Keychain.processIsEntitled
        let row = ICloudSyncSection.keysRow(entitled: entitled)
        if entitled {
            check(KeySync.system != nil, "entitled to \(KeySync.accessGroup): the data protection keychain's stores")
            check(row.enabled, "the \"API keys and passwords\" row can be turned on")
            for synchronizable in [true, false] { probeDataProtection(synchronizable: synchronizable) }
        } else {
            print("  this build has no keychain entitlement (no provisioning profile): the iCloud Keychain items aren't tried")
            check(KeySync.system == nil && Platform.mac.secrets.kind == .legacy,
                  "not entitled: keys stay in the login keychain (store \(Platform.mac.secrets.kind))")
            check(!row.enabled && row.note == tr("这个版本不能同步密钥（没有描述文件）", "This build can't sync keys (no provisioning profile)"),
                  "the \"API keys and passwords\" row is off and greyed, saying why (\(row.note))")
        }
        testKeySyncMoves()
    }

    /// Steps 1–4 of the spec's self-test for one kind of item, under the self-test's own service; and the login keychain's
    /// queries (`legacyKeychain`, asking and not) neither see nor delete it.
    private static func probeDataProtection(synchronizable: Bool) {
        let service = "AllInOneIME self-test key", account = "selftest", group = KeySync.accessGroup
        let what = synchronizable ? "a synced item" : "an item of this Mac's"
        let store = APIKeys.Keychain.dataProtection(group: group, synchronizable: synchronizable, service: service)
        _ = APIKeys.Keychain.deleteEitherSync(service: service, account: account, group: group)  // left over from a run before
        let key = "selftest-" + UUID().uuidString
        let saved = Date(timeIntervalSince1970: 1_790_000_000.5)
        check(store.write(account, key, "AllInOneIME: self-test", "selftest.example", APIKeys.ending(of: key), saved) == .ok,
              "\(what) added under \"\(service)\"")
        let stored = APIKeys.Keychain.storedAttributes(service: service, account: account, group: group, eitherSync: true)
        let sync = (stored?[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue
        let accessGroup = stored?[kSecAttrAccessGroup as String] as? String
        let accessible = stored?[kSecAttrAccessible as String] as? String
        let wanted = (synchronizable ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) as String
        check(sync == synchronizable && accessGroup == group && accessible == wanted,
              "\(what): sync=\(sync.map { $0 ? 1 : 0 } ?? -1), agrp=\(accessGroup ?? "none"), pdmn=\(accessible ?? "none") (\(wanted))")
        check(store.read(account) == key && store.attributes(account)?.comment == "selftest.example"
              && abs((store.attributes(account)?.saved ?? .distantPast).timeIntervalSince(saved)) < 0.001,
              "\(what) reads back, with its comment and its save time")
        let plain = APIKeys.Keychain.storedAttributes(service: service, account: account, group: group, eitherSync: false)
        check((plain != nil) == !synchronizable,
              synchronizable ? "a query without kSecAttrSynchronizable doesn't find the synced item"
                             : "a query without kSecAttrSynchronizable finds this Mac's item")
        for asking in [true, false] {
            let legacy = APIKeys.Keychain.legacyKeychain(service: service, asking: asking)
            let unseen = legacy.attributes(account) == nil && legacy.read(account) == nil && !legacy.accounts().contains(account)
            let kept = legacy.delete(account) == .notFound && store.read(account) == key
            check(unseen && kept, "\(what): the login keychain's queries (\(asking ? "asking" : "silent")) don't see it (\(unseen)) or delete it (\(kept))")
        }
        let other = APIKeys.Keychain.dataProtection(group: group, synchronizable: !synchronizable, service: service)
        check(other.attributes(account) == nil && other.delete(account) == .notFound && store.read(account) == key,
              "\(what): the other kind's store neither sees nor deletes it")
        check(APIKeys.Keychain.deleteEitherSync(service: service, account: account, group: group) == .ok
              && APIKeys.Keychain.storedAttributes(service: service, account: account, group: group, eitherSync: true) == nil,
              "\(what) deleted with kSecAttrSynchronizableAny: gone")
    }

    /// The controller's moves, with stores in memory: the silent pass at launch, then the switch turned on and off.
    private static func testKeySyncMoves() {
        let sync = ICloudSyncController.shared
        let fm = FileManager.default
        let configURL = Config.defaultURL
        let configBefore = try? Data(contentsOf: configURL)
        let keysBefore = sync.keys
        func store(_ kind: APIKeys.Keychain.Kind) -> APIKeys.Keychain {
            var store = APIKeys.Keychain.inMemory()
            store.kind = kind
            return store
        }
        let local = store(.local), synced = store(.synced), legacy = store(.legacy)
        let stores = KeySync.Stores(local: local, synced: synced, legacy: legacy)
        sync.keys = stores
        try? fm.removeItem(at: sync.keysSyncedURL)
        defer {
            sync.keys = keysBefore
            try? fm.removeItem(at: sync.keysSyncedURL)
            if let configBefore { try? configBefore.write(to: configURL) }
        }
        func edit(_ change: (inout ICloudSyncSettings) -> Void) {
            guard var config = try? Config.load(from: configURL) else { return }
            change(&config.iCloudSync)
            try? config.write(to: configURL)
        }

        let openAI = "sk-selftest-openai-0001", gemini = "sk-selftest-gemini-0002", hosted = "token-selftest-hosted-0003"
        _ = local.write("openai", openAI, "AllInOneIME: OpenAI-compatible API", "api.openai.com", APIKeys.ending(of: openAI), Date())
        _ = local.write("hosted", hosted, "AllInOneIME: AllInOneIME Cloud", "", APIKeys.ending(of: hosted), Date())
        _ = legacy.write("gemini", gemini, "AllInOneIME: Gemini API", "", APIKeys.ending(of: gemini), nil)
        edit { $0.enabled = false }
        let moves = try? stores.migrate()
        check(moves?.moved == ["gemini"] && local.read("gemini") == gemini && legacy.attributes("gemini") == nil
              && local.attributes("gemini")?.label == "AllInOneIME: Gemini API",
              "the login keychain's key moved at launch, label kept, and deleted there (\(moves?.moved ?? []))")

        edit { $0.enabled = true }
        sync.applyKeySync()
        check(stores.syncing && synced.read("openai") == openAI && synced.read("gemini") == gemini
              && local.attributes("openai") == nil && local.attributes("gemini") == nil
              && synced.attributes("openai")?.comment == "api.openai.com",
              "sync turned on: this Mac's keys moved into iCloud Keychain, with their hosts")
        check(local.read("hosted") == hosted && synced.attributes("hosted") == nil,
              "the AllInOneIME Cloud sign-in stays on this Mac")
        check(fm.fileExists(atPath: sync.keysSyncedURL.path) && stores.store.read("openai") == openAI,
              "keys are read from iCloud Keychain, and that's remembered")

        edit { $0.keys = false }
        sync.applyKeySync()
        check(!stores.syncing && local.read("openai") == openAI && local.read("gemini") == gemini
              && synced.read("openai") == openAI && synced.read("gemini") == gemini && !fm.fileExists(atPath: sync.keysSyncedURL.path),
              "\"API keys and passwords\" turned off: the synced keys copied to this Mac and left in iCloud Keychain for the others")
    }
}
