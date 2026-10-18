import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Security

extension SelfTest {
    /// API keys and passwords through iCloud Keychain (`KeySync`). A build signed with the provisioning profile (entitled
    /// to the shared access group) adds, reads and deletes a synced item of a service of its own, "AllInOneIME self-test
    /// key": never the user's keys. Every build checks the store it chose and the Settings row, and the sync controller's
    /// moves (key sync turned on and off: the login keychain's keys into iCloud Keychain and back) with stores in memory
    /// and the self-test's config.
    static func testKeychainSync() {
        section("API keys through iCloud Keychain")
        let entitled = APIKeys.Keychain.processIsEntitled
        let row = ICloudSyncSection.keysRow(entitled: entitled)
        if entitled {
            check(KeySync.system != nil, "entitled to \(KeySync.accessGroup): iCloud Keychain's store and the login keychain")
            check(row.enabled, "the \"API keys and passwords\" row can be turned on")
            probeSyncedItem()
        } else {
            print("  this build has no keychain entitlement (no provisioning profile): the iCloud Keychain items aren't tried")
            check(KeySync.system == nil && Platform.mac.secrets.kind == .legacy,
                  "not entitled: keys stay in the login keychain (store \(Platform.mac.secrets.kind))")
            check(!row.enabled && row.note == tr("这个版本不能同步密钥（没有描述文件）", "This build can't sync keys (no provisioning profile)"),
                  "the \"API keys and passwords\" row is off and greyed, saying why (\(row.note))")
        }
        testKeySyncMoves()
    }

    /// Steps 1–4 of the spec's self-test, under the self-test's own service: a synced item added (`sync=1`, the shared
    /// group, readable after the first unlock: `ck`), read back, not found by a query without `kSecAttrSynchronizable`,
    /// neither seen nor deleted by the login keychain's queries (asking and not), and deleted with
    /// `kSecAttrSynchronizableAny`.
    private static func probeSyncedItem() {
        let service = "AllInOneIME self-test key", group = KeySync.accessGroup, account = "selftest"
        let store = APIKeys.Keychain.dataProtection(group: group, service: service)
        _ = APIKeys.Keychain.deleteEitherSync(service: service, account: account, group: group)  // left over from a run before
        let key = "selftest-" + UUID().uuidString
        let saved = Date(timeIntervalSince1970: 1_790_000_000.5)
        check(store.write(account, key, "AllInOneIME: self-test", "selftest.example", APIKeys.ending(of: key), saved) == .ok,
              "a synced item added under \"\(service)\"")
        let stored = APIKeys.Keychain.storedAttributes(service: service, account: account, group: group, eitherSync: true)
        let sync = (stored?[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue
        let accessGroup = stored?[kSecAttrAccessGroup as String] as? String
        let accessible = stored?[kSecAttrAccessible as String] as? String
        let wanted = kSecAttrAccessibleAfterFirstUnlock as String
        check(sync == true && accessGroup == group && accessible == wanted,
              "the synced item: sync=\(sync.map { $0 ? 1 : 0 } ?? -1), agrp=\(accessGroup ?? "none"), pdmn=\(accessible ?? "none") (\(wanted))")
        check(store.read(account) == key && store.attributes(account)?.comment == "selftest.example"
              && abs((store.attributes(account)?.saved ?? .distantPast).timeIntervalSince(saved)) < 0.001,
              "the synced item reads back, with its comment and its save time")
        check(APIKeys.Keychain.storedAttributes(service: service, account: account, group: group, eitherSync: false) == nil,
              "a query without kSecAttrSynchronizable doesn't find the synced item")
        for asking in [true, false] {
            let login = APIKeys.Keychain.legacyKeychain(service: service, asking: asking)
            let unseen = login.attributes(account) == nil && login.read(account) == nil && !login.accounts().contains(account)
            let kept = login.delete(account) == .notFound && store.read(account) == key
            check(unseen && kept, "the login keychain's queries (\(asking ? "asking" : "silent")) don't see the synced item (\(unseen)) or delete it (\(kept))")
        }
        check(APIKeys.Keychain.deleteEitherSync(service: service, account: account, group: group) == .ok
              && APIKeys.Keychain.storedAttributes(service: service, account: account, group: group, eitherSync: true) == nil,
              "the synced item deleted with kSecAttrSynchronizableAny: gone")
    }

    /// The controller's moves, with stores in memory: key sync off (nothing moves), turned on and off, the keys-synced
    /// marker through a turn on that stops halfway (acceptance S21's controller half), and a replaced copy that can't be
    /// kept (S23's).
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
        let login = store(.legacy)
        // The replaced copies, which can be made to fail.
        let replacedFails = Locked<Bool>(initialState: false)
        var replaced = store(.legacy)
        let replacedItems = replaced
        replaced.write = { account, key, label, comment, ending, saved in
            replacedFails.withLock { $0 } ? .failed(-25293) : replacedItems.write(account, key, label, comment, ending, saved)
        }
        // iCloud Keychain, with keys that can be made unreadable (not there yet, say) or read back garbled once written,
        // and the marker as it was when each key was written there.
        let unreadable = Locked<Set<String>>(initialState: []), garbled = Locked<Set<String>>(initialState: [])
        let markerURL = sync.keysSyncedURL
        let markerAtWrites = Locked<[String?]>(initialState: [])
        var synced = store(.synced)
        let syncedItems = synced
        synced.read = { account in
            if unreadable.withLock({ $0.contains(account) }) { return nil }
            return garbled.withLock { $0.contains(account) } ? "garbled" : syncedItems.read(account)
        }
        synced.write = { account, key, label, comment, ending, saved in
            let marker = (try? Data(contentsOf: markerURL)).map { String(decoding: $0, as: UTF8.self) }
            markerAtWrites.withLock { $0.append(marker) }
            return syncedItems.write(account, key, label, comment, ending, saved)
        }
        let stores = KeySync.Stores(login: login, synced: synced, replaced: replaced)
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
        _ = login.write("openai", openAI, "AllInOneIME: OpenAI-compatible API", "api.openai.com", APIKeys.ending(of: openAI), Date())
        _ = login.write("hosted", hosted, "AllInOneIME: AllInOneIME Cloud", "", APIKeys.ending(of: hosted), Date())
        _ = login.write("gemini", gemini, "AllInOneIME: Gemini API", "", APIKeys.ending(of: gemini), nil)  // 0.6.4's
        edit { $0.enabled = false }
        sync.applyKeySync()
        check(!stores.syncing && login.read("openai") == openAI && login.read("gemini") == gemini
              && syncedItems.accounts().isEmpty && replacedItems.accounts().isEmpty && sync.keysSynced == nil
              && stores.store.read("gemini") == gemini,
              "key sync off: the keys stay in the login keychain, nothing moved")

        edit { $0.enabled = true }
        sync.applyKeySync()
        check(stores.syncing && synced.read("openai") == openAI && synced.read("gemini") == gemini
              && login.attributes("openai") == nil && login.attributes("gemini") == nil
              && synced.attributes("openai")?.comment == "api.openai.com"
              && synced.attributes("gemini")?.label == "AllInOneIME: Gemini API",
              "sync turned on: the login keychain's keys moved into iCloud Keychain, with their hosts and labels")
        check(replacedItems.read("openai") == openAI && replacedItems.attributes("gemini")?.label == "AllInOneIME: Gemini API (replaced)",
              "each key that went into iCloud Keychain also kept as a replaced copy, named so (\(replacedItems.attributes("gemini")?.label ?? "none"))")
        check(login.read("hosted") == hosted && synced.attributes("hosted") == nil,
              "the AllInOneIME Cloud sign-in stays in the login keychain")
        check(sync.keysSynced == .done && stores.store.read("openai") == openAI,
              "keys are read from iCloud Keychain, and that's remembered")

        edit { $0.keys = false }
        unreadable.withLock { $0 = ["gemini"] }
        sync.applyKeySync()
        check(!stores.syncing && login.read("openai") == openAI && login.attributes("gemini") == nil
              && fm.fileExists(atPath: sync.keysSyncedURL.path),
              "turned off with a synced key unreadable: the others copied back, and it isn't marked done (tried again)")
        unreadable.withLock { $0 = [] }
        sync.applyKeySync()
        check(!stores.syncing && login.read("openai") == openAI && login.read("gemini") == gemini
              && synced.read("openai") == openAI && synced.read("gemini") == gemini && !fm.fileExists(atPath: sync.keysSyncedURL.path),
              "\"API keys and passwords\" turned off: the synced keys copied back into the login keychain and left in iCloud Keychain for the others")

        // Turned on, one key's copy reads back garbled: the marker says "moving" before the first key moves, and still
        // does after (never "done").
        let anthropic = "sk-selftest-anthropic-0004"
        _ = login.write("anthropic", anthropic, "AllInOneIME: Claude API", "", APIKeys.ending(of: anthropic), Date())
        _ = synced.delete("openai")
        _ = synced.delete("gemini")
        markerAtWrites.withLock { $0 = [] }
        garbled.withLock { $0 = ["gemini"] }
        edit { $0.keys = true }
        sync.applyKeySync()
        let firstWrite = markerAtWrites.withLock { $0.first ?? nil }
        check(firstWrite == "moving" && sync.keysSynced == .moving && stores.syncing,
              "turned on: the marker says moving before the first key moves (\(firstWrite ?? "none")), and after a copy that didn't read back (\(sync.keysSynced.map(\.rawValue) ?? "none"))")
        check(syncedItems.read("openai") == openAI && login.attributes("openai") == nil && login.read("gemini") == gemini,
              "the keys that moved are in iCloud Keychain alone; the one whose copy was garbled stays in the login keychain")

        // Turned off before the turn on was done: the synced keys come back all the same, and the marker goes.
        edit { $0.keys = false }
        sync.applyKeySync()
        check(!stores.syncing && sync.keysSynced == nil && stores.store.read("openai") == openAI
              && stores.store.read("anthropic") == anthropic && stores.store.read("gemini") == gemini,
              "turned off after a turn on that stopped halfway: every key that moved is in the login keychain again, and the marker is gone")

        // Turned on again, nothing garbled: moving, then done.
        garbled.withLock { $0 = [] }
        markerAtWrites.withLock { $0 = [] }
        edit { $0.keys = true }
        sync.applyKeySync()
        let onAgain = markerAtWrites.withLock { $0.first ?? nil }
        check(onAgain == "moving" && sync.keysSynced == .done && syncedItems.read("gemini") == gemini && login.attributes("gemini") == nil,
              "turned on again: moving (\(onAgain ?? "none")), then done once every key moved")

        // Key sync on and done: a run moves nothing; a launch moves what the login keychain has (the silent pass).
        let since = "sk-selftest-since-0006"
        _ = login.write("mistral", since, "AllInOneIME: test", "", APIKeys.ending(of: since), Date())
        sync.applyKeySync()
        check(login.read("mistral") == since && syncedItems.attributes("mistral") == nil, "key sync on and done: a run moves nothing")
        sync.applyKeySync(atLaunch: true)
        check(sync.keysSynced == .done && syncedItems.read("mistral") == since && login.attributes("mistral") == nil,
              "at launch with key sync on: the login keychain's keys move into iCloud Keychain, as turning it on does")

        // At launch with the marker left "moving" and key sync on: the turn on is tried again; a replaced copy that
        // can't be kept leaves the key where it was and the marker "moving", until it can.
        try? Data("moving".utf8).write(to: markerURL)
        let late = "sk-selftest-late-0005"
        _ = login.write("perplexity", late, "AllInOneIME: test", "", APIKeys.ending(of: late), Date())
        stores.start(syncing: true)
        replacedFails.withLock { $0 = true }
        sync.applyKeySync()
        check(sync.keysSynced == .moving && login.read("perplexity") == late && syncedItems.attributes("perplexity") == nil,
              "a replaced copy that can't be kept: the key stays in the login keychain, and the marker says moving")
        replacedFails.withLock { $0 = false }
        sync.applyKeySync()
        check(sync.keysSynced == .done && syncedItems.read("perplexity") == late && login.attributes("perplexity") == nil,
              "a marker left moving with key sync on: the turn on is tried again, then done")
        // A marker from an earlier build (empty) is done.
        try? Data().write(to: markerURL)
        check(sync.keysSynced == .done, "an empty marker (an earlier build's) counts as done")
    }
}
