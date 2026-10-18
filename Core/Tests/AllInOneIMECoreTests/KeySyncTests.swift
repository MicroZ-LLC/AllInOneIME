import Foundation
import Testing
@testable import AllInOneIMECore

/// The stores the app uses (`KeySync.Stores`), beyond the acceptance tests' scenarios: the switch, the silent pass's store
/// and the label a moved item gets. All in memory.
struct KeySyncTests {
    static func store(_ kind: APIKeys.Keychain.Kind) -> APIKeys.Keychain {
        var store = APIKeys.Keychain.inMemory()
        store.kind = kind
        return store
    }

    @Test func theRoutedStoreFollowsTheSwitch() throws {
        let local = Self.store(.local), synced = Self.store(.synced), legacy = Self.store(.legacy)
        let stores = KeySync.Stores(local: local, synced: synced, legacy: legacy)
        #expect(!stores.syncing && stores.store.kind == .synced)
        try APIKeys.save("sk-test-local-0001-abcd", account: "openai", label: "AllInOneIME: test", in: stores.store)
        #expect(local.read("openai") != nil && synced.read("openai") == nil)

        try stores.turn(syncing: true)
        #expect(stores.syncing && synced.read("openai") == "sk-test-local-0001-abcd" && local.read("openai") == nil)
        try APIKeys.save("sk-test-synced-0002-abcd", account: "gemini", label: "AllInOneIME: test", in: stores.store)
        #expect(synced.read("gemini") != nil && local.read("gemini") == nil)

        try stores.turn(syncing: false)
        #expect(!stores.syncing && local.read("gemini") == "sk-test-synced-0002-abcd" && synced.read("gemini") != nil)
        stores.start(syncing: true)  // as the config says at launch: nothing moved
        #expect(stores.syncing && local.read("gemini") != nil)
    }

    /// A move that fails still leaves the store following the switch (the move is tried again later).
    @Test func aFailedMoveStillTurnsTheSwitch() {
        var synced = Self.store(.synced)
        synced.write = { _, _, _, _, _, _ in .failed(-34018) }
        let local = Self.store(.local)
        _ = local.write("openai", "sk-test-local-0001-abcd", "AllInOneIME: test", "", nil, nil)
        let stores = KeySync.Stores(local: local, synced: synced, legacy: Self.store(.legacy))
        #expect(throws: APIKeys.KeychainError.self) { try stores.turn(syncing: true) }
        #expect(stores.syncing && local.read("openai") != nil)
    }

    /// The silent pass goes through the quiet login keychain into a store with nothing behind it; a moved item without
    /// a label of its own gets the provider's.
    @Test func theSilentPassUsesTheQuietLegacyStore() throws {
        let local = Self.store(.local), synced = Self.store(.synced), legacy = Self.store(.legacy)
        var quiet = legacy
        quiet.read = { _ in nil }  // every item would ask
        quiet.attributes = { account in
            legacy.attributes(account).map { var found = $0; found.label = nil; return found }
        }
        _ = legacy.write("gemini", "sk-test-legacy-0001-wxyz", "", "", nil, nil)
        _ = legacy.write("openai", "sk-test-legacy-0002-wxyz", "", "", nil, nil)
        let stores = KeySync.Stores(local: local, synced: synced, legacy: legacy, quietLegacy: quiet)
        let moves = try stores.migrate()
        #expect(Set(moves.waiting) == ["gemini", "openai"] && moves.moved.isEmpty)

        let loud = KeySync.Stores(local: local, synced: synced, legacy: quiet.withRead(legacy.read))
        let moved = try loud.migrate()
        #expect(Set(moved.moved) == ["gemini", "openai"] && legacy.attributes("gemini") == nil)
        #expect(local.attributes("openai")?.label == "AllInOneIME: \(Provider.openai.displayName)")
        #expect(local.attributes("openai")?.ending == "wxyz")
    }
}

private extension APIKeys.Keychain {
    func withRead(_ read: @escaping @Sendable (String) -> String?) -> Self {
        var store = self
        store.read = read
        return store
    }
}

/// A copy that reads back otherwise is taken out of the one store it was written to, and only when that store had no item
/// for the account before: never this device's original, never an item another Mac synced.
struct KeySyncMismatchTests {
    @Test func aBadCopyNeverCostsTheOriginal() throws {
        let local = KeySyncTests.store(.local)
        var synced = KeySyncTests.store(.synced)
        let inner = synced
        synced.read = { _ in "garbled" }
        _ = local.write("openai", "sk-test-local-0001-abcd", "AllInOneIME: test", "api.openai.com", "abcd", nil)
        let moves = try KeySync.merge(from: local, into: synced)
        #expect(moves.mismatched == ["openai"] && moves.moved.isEmpty && !moves.isComplete)
        #expect(local.read("openai") == "sk-test-local-0001-abcd" && local.attributes("openai")?.comment == "api.openai.com")
        #expect(inner.attributes("openai") == nil)
    }

    /// Through the routed store (the silent pass's), the bad copy is taken out of the store written to alone: this
    /// device's item of the same account stays.
    @Test func throughTheRoutedStoreOnlyTheStoreWrittenTo() throws {
        let local = KeySyncTests.store(.local), legacy = KeySyncTests.store(.legacy)
        var synced = KeySyncTests.store(.synced)
        let inner = synced
        synced.read = { _ in "garbled" }
        _ = local.write("gemini", "sk-test-local-0001-abcd", "AllInOneIME: test", "", "abcd", Date(timeIntervalSince1970: 100))
        _ = legacy.write("openai", "sk-test-legacy-0001-wxyz", "AllInOneIME: test", "", "wxyz", nil)
        let into = APIKeys.Keychain.routed(local: local, synced: synced, legacy: .unavailable, syncs: { true })
        let moves = try KeySync.migrate(legacy: legacy, into: into, interactive: false)
        #expect(moves.mismatched == ["openai"] && inner.attributes("openai") == nil)
        #expect(legacy.read("openai") == "sk-test-legacy-0001-wxyz" && local.read("gemini") == "sk-test-local-0001-abcd")
    }
}

/// Newest wins by when a key was saved, which every copy carries; the modification date only for an item that doesn't
/// say (0.6.4's). A key that loses to a different one is never deleted.
struct KeySyncSaveTimeTests {
    static let year = Date(timeIntervalSince1970: 1_760_000_000), week = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theSaveTimeAttributeRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let text = APIKeys.savedAttribute(date)
        #expect(text == "saved:2026-09-21T14:13:20.250Z")
        #expect(abs((APIKeys.saved(fromAttribute: text) ?? .distantPast).timeIntervalSince(date)) < 0.001)
        #expect(APIKeys.saved(fromAttribute: nil) == nil && APIKeys.saved(fromAttribute: "application password") == nil)
        #expect(APIKeys.endingAttribute("a1b2") == Data("ends:a1b2".utf8))  // the ending's attribute is as it was
    }

    @Test func saveRecordsTheTimeAndCopiesCarryIt() throws {
        let local = KeySyncTests.store(.local), synced = KeySyncTests.store(.synced)
        let before = Date()
        try APIKeys.save("sk-test-local-0001-abcd", account: "openai", label: "AllInOneIME: test", in: local)
        let saved = try #require(local.attributes("openai")?.saved)
        #expect(saved >= before.addingTimeInterval(-1) && saved <= Date())
        try KeySync.merge(from: local, into: synced)
        #expect(synced.attributes("openai")?.saved == saved)
    }

    /// Two Macs, each with its own key in the login keychain (0.6.4's: no save time), the older one migrating first: the
    /// copy it makes says when that key was last changed, not when it was copied, so the newer one wins on the second
    /// Mac; and a Mac whose key loses keeps it in its login keychain.
    @Test func twoMacsMigrateOneAfterTheOther() throws {
        let synced = KeySyncTests.store(.synced)
        func mac(_ key: String, changed: Date) -> (legacy: APIKeys.Keychain, into: APIKeys.Keychain) {
            let local = KeySyncTests.store(.local)
            var legacy = KeySyncTests.store(.legacy)
            let inner = legacy
            _ = inner.write("openai", key, "AllInOneIME: test", "", APIKeys.ending(of: key), nil)
            legacy.attributes = { inner.attributes($0).map { var found = $0; found.modified = changed; return found } }
            return (legacy, .routed(local: local, synced: synced, legacy: .unavailable, syncs: { true }))
        }
        let a = mac("sk-test-mac-a-old-0001", changed: Self.year), b = mac("sk-test-mac-b-new-0002", changed: Self.week)
        #expect(try KeySync.migrate(legacy: a.legacy, into: a.into, interactive: false).moved == ["openai"])
        #expect(synced.attributes("openai")?.saved == Self.year)
        #expect(try KeySync.migrate(legacy: b.legacy, into: b.into, interactive: false).moved == ["openai"])
        #expect(synced.read("openai") == "sk-test-mac-b-new-0002" && synced.attributes("openai")?.saved == Self.week)

        // The other way round: the newer one first; the older one is kept where it was, unread by anyone but the move.
        let synced2 = KeySyncTests.store(.synced)
        _ = synced2.write("openai", "sk-test-mac-b-new-0002", "AllInOneIME: test", "", nil, Self.week)
        let c = mac("sk-test-mac-a-old-0001", changed: Self.year)
        let into = APIKeys.Keychain.routed(local: KeySyncTests.store(.local), synced: synced2, legacy: .unavailable,
                                           syncs: { true })
        let moves = try KeySync.migrate(legacy: c.legacy, into: into, interactive: false)
        #expect(moves.superseded == ["openai"] && c.legacy.read("openai") == "sk-test-mac-a-old-0001")
        #expect(synced2.read("openai") == "sk-test-mac-b-new-0002")
    }

    /// Turning sync on: a local key that loses to a different synced one stays; the same key twice goes.
    @Test func aLosingLocalKeyIsKeptUnlessItIsTheSame() throws {
        let local = KeySyncTests.store(.local), synced = KeySyncTests.store(.synced)
        _ = local.write("openai", "sk-test-local-older-0001", "AllInOneIME: test", "", nil, Self.year)
        _ = synced.write("openai", "sk-test-synced-newer-0002", "AllInOneIME: test", "", nil, Self.week)
        _ = local.write("gemini", "sk-test-same-key-0003", "AllInOneIME: test", "", nil, Self.year)
        _ = synced.write("gemini", "sk-test-same-key-0003", "AllInOneIME: test", "", nil, Self.week)
        let moves = try KeySync.merge(from: local, into: synced)
        #expect(Set(moves.superseded) == ["openai", "gemini"] && moves.moved.isEmpty)
        #expect(local.read("openai") == "sk-test-local-older-0001" && synced.read("openai") == "sk-test-synced-newer-0002")
        #expect(local.attributes("gemini") == nil && synced.read("gemini") == "sk-test-same-key-0003")
    }
}

/// Keys that lose, or are written over, set aside under `KeySync.replacedService` (`Stores.replaced`): never read back
/// as the key in use, so a removed key never comes back; Remove… takes them too.
struct KeySyncSetAsideTests {
    static let old = Date(timeIntervalSince1970: 1_760_000_000), new = Date(timeIntervalSince1970: 1_790_000_000)
    static func stores(syncing: Bool) -> KeySync.Stores {
        KeySync.Stores(local: KeySyncTests.store(.local), synced: KeySyncTests.store(.synced),
                       legacy: KeySyncTests.store(.legacy), syncing: syncing)
    }
    static func write(_ store: APIKeys.Keychain, _ key: String, saved: Date?, account: String = "openai") {
        _ = store.write(account, key, "AllInOneIME: test", "api.openai.com", APIKeys.ending(of: key), saved)
    }

    /// Review case A: the login keychain's older key, set aside at the silent pass, doesn't come back after another
    /// Mac removed the synced one (not at its first use, not at the next silent pass).
    @Test func aLegacyLoserNeverComesBack() throws {
        let mac = Self.stores(syncing: true), legacy = mac.legacy
        Self.write(legacy, "sk-test-legacy-older-0001", saved: Self.old)
        Self.write(mac.synced, "sk-test-synced-newer-0002", saved: Self.new)
        let moves = try mac.migrate()
        #expect(moves.superseded == ["openai"] && moves.setAside == ["openai"])
        #expect(legacy.attributes("openai") == nil && mac.replaced.read("openai") == "sk-test-legacy-older-0001")
        #expect(mac.replaced.attributes("openai")?.saved == Self.old && mac.replaced.attributes("openai")?.comment == "api.openai.com")
        #expect(mac.store.read("openai") == "sk-test-synced-newer-0002")

        _ = mac.synced.delete("openai")  // removed on another Mac
        #expect(mac.store.read("openai") == nil && mac.store.attributes("openai") == nil)
        #expect(try mac.migrate().moved.isEmpty && mac.synced.attributes("openai") == nil)
    }

    /// Review case B: this Mac's older key, set aside when sync is turned on, doesn't go back to iCloud Keychain when it
    /// is turned off and on again after another Mac removed the key.
    @Test func aLocalLoserNeverReturnsToICloud() throws {
        let stores = Self.stores(syncing: false)
        Self.write(stores.local, "sk-test-local-older-0001", saved: Self.old)
        Self.write(stores.synced, "sk-test-synced-newer-0002", saved: Self.new)
        let on = try stores.turn(syncing: true)
        #expect(on.setAside == ["openai"] && on.isComplete)
        #expect(stores.local.attributes("openai") == nil && stores.replaced.read("openai") == "sk-test-local-older-0001")
        _ = stores.synced.delete("openai")  // removed on another Mac
        try stores.turn(syncing: false)
        try stores.turn(syncing: true)
        #expect(stores.synced.attributes("openai") == nil && stores.store.read("openai") == nil)
        #expect(stores.replaced.read("openai") == "sk-test-local-older-0001")  // only the safety copy
    }

    /// Review case D: a newer key written over another Mac's in iCloud Keychain: that one is set aside first.
    @Test func aKeyWrittenOverIsSetAside() throws {
        let stores = Self.stores(syncing: false)
        Self.write(stores.local, "sk-test-local-newer-0001", saved: Self.new)
        Self.write(stores.synced, "sk-test-synced-older-0002", saved: Self.old)
        let moves = try stores.turn(syncing: true)
        #expect(moves.moved == ["openai"] && moves.setAside == ["openai"])
        #expect(stores.synced.read("openai") == "sk-test-local-newer-0001")
        #expect(stores.replaced.read("openai") == "sk-test-synced-older-0002" && stores.replaced.attributes("openai")?.saved == Self.old)

        // The same key twice: nothing to set aside.
        let same = Self.stores(syncing: false)
        Self.write(same.local, "sk-test-same-key-0003", saved: Self.new)
        Self.write(same.synced, "sk-test-same-key-0003", saved: Self.old)
        #expect(try same.turn(syncing: true).setAside.isEmpty && same.replaced.attributes("openai") == nil)
    }

    /// The silent pass writing a newer login keychain key over an older one: the older one is set aside.
    @Test func migratingOverAnOlderKeySetsItAside() throws {
        let stores = Self.stores(syncing: true)
        Self.write(stores.legacy, "sk-test-legacy-newer-0001", saved: Self.new)
        Self.write(stores.synced, "sk-test-synced-older-0002", saved: Self.old)
        let moves = try stores.migrate()
        #expect(moves.moved == ["openai"] && moves.setAside == ["openai"])
        #expect(stores.synced.read("openai") == "sk-test-legacy-newer-0001" && stores.legacy.attributes("openai") == nil)
        #expect(stores.replaced.read("openai") == "sk-test-synced-older-0002")
    }

    /// A key that can't be set aside is never written over, nor deleted where it was: tried again later.
    @Test func whatCantBeSetAsideStays() throws {
        var replaced = KeySyncTests.store(.local)
        replaced.write = { _, _, _, _, _, _ in .failed(-34018) }
        let local = KeySyncTests.store(.local), synced = KeySyncTests.store(.synced)
        let stores = KeySync.Stores(local: local, synced: synced, legacy: KeySyncTests.store(.legacy), replaced: replaced)
        Self.write(local, "sk-test-local-newer-0001", saved: Self.new)
        Self.write(synced, "sk-test-synced-older-0002", saved: Self.old)
        Self.write(local, "sk-test-local-older-0003", saved: Self.old, account: "gemini")
        Self.write(synced, "sk-test-synced-newer-0004", saved: Self.new, account: "gemini")
        let moves = try stores.turn(syncing: true)
        #expect(moves.mismatched == ["openai"] && !moves.isComplete && moves.setAside.isEmpty)
        #expect(synced.read("openai") == "sk-test-synced-older-0002" && local.read("openai") == "sk-test-local-newer-0001")
        #expect(local.read("gemini") == "sk-test-local-older-0003" && synced.read("gemini") == "sk-test-synced-newer-0004")
    }

    /// Remove… takes the key set aside too, whether this Mac syncs keys or not; nothing else reads it.
    @Test func removeTakesTheKeySetAside() throws {
        for syncing in [false, true] {
            let stores = Self.stores(syncing: syncing)
            Self.write(stores.replaced, "sk-test-replaced-0001", saved: Self.old)
            #expect(stores.store.attributes("openai") == nil && stores.store.read("openai") == nil)
            #expect(!stores.store.accounts().contains("openai"))
            Self.write(stores.local, "sk-test-local-0002", saved: Self.new)
            try APIKeys.remove(account: "openai", in: stores.store)
            #expect(stores.replaced.attributes("openai") == nil && stores.local.attributes("openai") == nil)
        }
    }
}

#if canImport(Security)
import Security

/// When the data protection keychain's items can be read: after the first unlock, so that this Mac's keys go to a new Mac
/// with Migration Assistant; the never-synced AllInOneIME Cloud sign-in on this device only.
struct KeychainAccessibilityTests {
    @Test func onlyNeverSyncedItemsStayOnThisDevice() {
        let firstUnlock = kSecAttrAccessibleAfterFirstUnlock as String
        #expect(APIKeys.Keychain.accessibility(account: "openai", synchronizable: false) as String == firstUnlock)
        #expect(APIKeys.Keychain.accessibility(account: "openai", synchronizable: true) as String == firstUnlock)
        #expect(APIKeys.Keychain.accessibility(account: "hosted", synchronizable: false) as String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
}
#endif

/// A Mac whose clock was set far ahead: its save times count as now, so they don't win every merge after.
struct KeySyncClockTests {
    static func item(_ saved: Date) -> APIKeys.ItemAttributes {
        APIKeys.ItemAttributes(created: nil, modified: nil, comment: nil, saved: saved)
    }

    @Test func aSaveTimeFarAheadCountsAsNow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let ahead = Self.item(now.addingTimeInterval(400 * 86_400)), hourAgo = Self.item(now.addingTimeInterval(-3_600))
        let minuteAgo = Self.item(now.addingTimeInterval(-60)), soon = Self.item(now.addingTimeInterval(3_600))
        #expect(KeySync.newer(ahead, than: hourAgo, now: now))  // as now: still later than an hour ago
        #expect(!KeySync.newer(ahead, than: soon, now: now))  // within a day ahead: as it says, later than now
        #expect(KeySync.newer(soon, than: ahead, now: now))
        #expect(KeySync.newer(minuteAgo, than: hourAgo, now: now) && !KeySync.newer(hourAgo, than: minuteAgo, now: now))
        #expect(!KeySync.newer(ahead, than: Self.item(now.addingTimeInterval(500 * 86_400)), now: now))  // both now: neither
    }
}
