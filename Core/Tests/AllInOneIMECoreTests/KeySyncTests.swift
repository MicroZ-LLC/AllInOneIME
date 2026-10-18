import Foundation
import Testing
@testable import AllInOneIMECore

/// The stores the app uses (`KeySync.Stores`), beyond the acceptance tests' scenarios: the switch, the quiet login
/// keychain the moves use and the label a moved item gets. All in memory.
struct KeySyncTests {
    static func store(_ kind: APIKeys.Keychain.Kind) -> APIKeys.Keychain {
        var store = APIKeys.Keychain.inMemory()
        store.kind = kind
        return store
    }
    static func stores(syncing: Bool = false) -> KeySync.Stores {
        KeySync.Stores(login: store(.legacy), synced: store(.synced), replaced: store(.legacy), syncing: syncing)
    }

    @Test func theRoutedStoreFollowsTheSwitch() throws {
        let stores = Self.stores(), synced = stores.synced, legacy = stores.login
        #expect(!stores.syncing && stores.store.kind == .synced)
        try APIKeys.save("sk-test-legacy-0001-abcd", account: "openai", label: "AllInOneIME: test", in: stores.store)
        #expect(legacy.read("openai") != nil && synced.read("openai") == nil)

        try stores.turn(syncing: true)
        #expect(stores.syncing && synced.read("openai") == "sk-test-legacy-0001-abcd" && legacy.read("openai") == nil)
        try APIKeys.save("sk-test-synced-0002-abcd", account: "gemini", label: "AllInOneIME: test", in: stores.store)
        try APIKeys.save("token-test-hosted-0003", account: "hosted", label: "AllInOneIME: test", in: stores.store)
        #expect(synced.read("gemini") != nil && legacy.read("gemini") == nil)
        #expect(legacy.read("hosted") != nil && synced.read("hosted") == nil)

        try stores.turn(syncing: false)
        #expect(!stores.syncing && legacy.read("gemini") == "sk-test-synced-0002-abcd" && synced.read("gemini") != nil)
        stores.start(syncing: true)  // as the config says at launch: nothing moved
        #expect(stores.syncing && legacy.read("gemini") != nil)
    }

    /// A move that fails still leaves the store following the switch (the move is tried again later).
    @Test func aFailedMoveStillTurnsTheSwitch() {
        var synced = Self.store(.synced)
        synced.write = { _, _, _, _, _, _ in .failed(-34018) }
        let legacy = Self.store(.legacy)
        _ = legacy.write("openai", "sk-test-legacy-0001-abcd", "AllInOneIME: test", "", nil, nil)
        let stores = KeySync.Stores(login: legacy, synced: synced, replaced: Self.store(.legacy))
        #expect(throws: APIKeys.KeychainError.self) { try stores.turn(syncing: true) }
        #expect(stores.syncing && legacy.read("openai") != nil)
    }

    /// The moves go through the quiet login keychain and its quiet replaced copies; a moved item without a label of its
    /// own gets the provider's.
    @Test func theMovesUseTheQuietStores() throws {
        let synced = Self.store(.synced), legacy = Self.store(.legacy), replaced = Self.store(.legacy)
        var quiet = legacy
        quiet.read = { _ in nil }  // every item would ask
        quiet.attributes = { account in
            legacy.attributes(account).map { var found = $0; found.label = nil; return found }
        }
        _ = legacy.write("gemini", "sk-test-legacy-0001-wxyz", "", "", nil, nil)
        _ = legacy.write("openai", "sk-test-legacy-0002-wxyz", "", "", nil, nil)
        let stores = KeySync.Stores(login: legacy, synced: synced, replaced: replaced, quietLogin: quiet,
                                    quietReplaced: Self.store(.legacy))
        let moves = try stores.turn(syncing: true)
        #expect(Set(moves.waiting) == ["gemini", "openai"] && moves.moved.isEmpty && !moves.isComplete)

        let quietReplaced = Self.store(.legacy)
        let loud = KeySync.Stores(login: legacy, synced: synced, replaced: replaced, quietLogin: quiet.withRead(legacy.read),
                                  quietReplaced: quietReplaced)
        let moved = try loud.turn(syncing: true)
        #expect(Set(moved.moved) == ["gemini", "openai"] && legacy.attributes("gemini") == nil && moved.isComplete)
        #expect(synced.attributes("openai")?.label == "AllInOneIME: \(Provider.openai.displayName)")
        #expect(synced.attributes("openai")?.ending == "wxyz")
        #expect(quietReplaced.read("openai") == "sk-test-legacy-0002-wxyz" && replaced.accounts().isEmpty)
    }

    /// A key left in the login keychain when key sync was turned on (it asked for the password) moves at its first use,
    /// a replaced copy kept first; with key sync off, a read never moves anything.
    @Test func aKeyLeftBehindMovesAtItsFirstUse() throws {
        let off = Self.stores()
        _ = off.login.write("openai", "sk-test-legacy-0001-abcd", "AllInOneIME: test", "api.openai.com", "abcd", nil)
        #expect(off.store.read("openai") == "sk-test-legacy-0001-abcd")
        #expect(off.login.read("openai") != nil && off.synced.accounts().isEmpty && off.replaced.accounts().isEmpty)

        let on = Self.stores(syncing: true)
        _ = on.login.write("openai", "sk-test-legacy-0001-abcd", "AllInOneIME: test", "api.openai.com", "abcd", nil)
        _ = on.login.write("hosted", "token-test-hosted-0002", "AllInOneIME: test", "", nil, nil)
        #expect(on.store.read("openai") == "sk-test-legacy-0001-abcd" && on.store.read("hosted") == "token-test-hosted-0002")
        #expect(on.synced.read("openai") == "sk-test-legacy-0001-abcd" && on.login.attributes("openai") == nil)
        #expect(on.synced.attributes("openai")?.comment == "api.openai.com")
        #expect(on.replaced.read("openai") == "sk-test-legacy-0001-abcd")
        #expect(on.login.read("hosted") != nil && on.synced.attributes("hosted") == nil)
    }
}

private extension APIKeys.Keychain {
    func withRead(_ read: @escaping @Sendable (String) -> String?) -> Self {
        var store = self
        store.read = read
        return store
    }
}

/// A copy that reads back otherwise is taken out of the store it was written to, and only when that store had no item for
/// the account before: never the original, never an item another Mac synced.
struct KeySyncMismatchTests {
    @Test func aBadCopyNeverCostsTheOriginal() throws {
        let legacy = KeySyncTests.store(.legacy)
        var synced = KeySyncTests.store(.synced)
        let inner = synced
        synced.read = { _ in "garbled" }
        _ = legacy.write("openai", "sk-test-legacy-0001-abcd", "AllInOneIME: test", "api.openai.com", "abcd", nil)
        let moves = try KeySync.merge(from: legacy, into: synced, aside: KeySyncTests.store(.legacy))
        #expect(moves.mismatched == ["openai"] && moves.moved.isEmpty && !moves.isComplete)
        #expect(legacy.read("openai") == "sk-test-legacy-0001-abcd" && legacy.attributes("openai")?.comment == "api.openai.com")
        #expect(inner.attributes("openai") == nil)
    }
}

/// Newest wins by when a key was saved, which every copy carries; the modification date only for an item that doesn't
/// say (0.6.4's). A key that loses to a different one is never lost: a replaced copy is kept.
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
        let legacy = KeySyncTests.store(.legacy), synced = KeySyncTests.store(.synced), replaced = KeySyncTests.store(.legacy)
        let before = Date()
        try APIKeys.save("sk-test-legacy-0001-abcd", account: "openai", label: "AllInOneIME: test", in: legacy)
        let saved = try #require(legacy.attributes("openai")?.saved)
        #expect(saved >= before.addingTimeInterval(-1) && saved <= Date())
        try KeySync.merge(from: legacy, into: synced, aside: replaced)
        #expect(synced.attributes("openai")?.saved == saved && replaced.attributes("openai")?.saved == saved)
    }

    /// Two Macs, each with its own key in the login keychain (0.6.4's: no save time), the older one moving first: the
    /// copy it makes says when that key was last changed, not when it was copied, so the newer one wins on the second
    /// Mac, and the first one's is kept as a replaced copy on each Mac.
    @Test func twoMacsMoveOneAfterTheOther() throws {
        let synced = KeySyncTests.store(.synced)
        func mac(_ key: String, changed: Date) -> APIKeys.Keychain {
            var legacy = KeySyncTests.store(.legacy)
            let inner = legacy
            _ = inner.write("openai", key, "AllInOneIME: test", "", APIKeys.ending(of: key), nil)
            legacy.attributes = { inner.attributes($0).map { var found = $0; found.modified = changed; return found } }
            return legacy
        }
        let a = mac("sk-test-mac-a-old-0001", changed: Self.year), b = mac("sk-test-mac-b-new-0002", changed: Self.week)
        let asideA = KeySyncTests.store(.legacy), asideB = KeySyncTests.store(.legacy)
        #expect(try KeySync.merge(from: a, into: synced, aside: asideA).moved == ["openai"])
        #expect(synced.attributes("openai")?.saved == Self.year && asideA.read("openai") == "sk-test-mac-a-old-0001")
        #expect(try KeySync.merge(from: b, into: synced, aside: asideB).moved == ["openai"])
        #expect(synced.read("openai") == "sk-test-mac-b-new-0002" && synced.attributes("openai")?.saved == Self.week)
        #expect(asideB.read("openai") == "sk-test-mac-a-old-0001")  // A's, written over

        // The other way round: the newer one first; the older one is kept as a replaced copy, where nothing reads it.
        let synced2 = KeySyncTests.store(.synced), replaced = KeySyncTests.store(.legacy)
        _ = synced2.write("openai", "sk-test-mac-b-new-0002", "AllInOneIME: test", "", nil, Self.week)
        let c = mac("sk-test-mac-a-old-0001", changed: Self.year)
        let moves = try KeySync.merge(from: c, into: synced2, aside: replaced)
        #expect(moves.superseded == ["openai"] && moves.setAside == ["openai"] && c.attributes("openai") == nil)
        #expect(replaced.read("openai") == "sk-test-mac-a-old-0001" && replaced.attributes("openai")?.saved == Self.year)
        #expect(synced2.read("openai") == "sk-test-mac-b-new-0002")
    }

    /// Turning sync on: a login keychain key that loses to a synced one is kept as a replaced copy before it goes, the
    /// same key too (it leaves for iCloud Keychain); turning it off, the same key twice is only refreshed.
    @Test func aLosingKeyIsKeptAsReplaced() throws {
        let legacy = KeySyncTests.store(.legacy), synced = KeySyncTests.store(.synced), replaced = KeySyncTests.store(.legacy)
        _ = legacy.write("openai", "sk-test-legacy-older-0001", "AllInOneIME: test", "", nil, Self.year)
        _ = synced.write("openai", "sk-test-synced-newer-0002", "AllInOneIME: test", "", nil, Self.week)
        _ = legacy.write("gemini", "sk-test-same-key-0003", "AllInOneIME: test", "", nil, Self.year)
        _ = synced.write("gemini", "sk-test-same-key-0003", "AllInOneIME: test", "", nil, Self.week)
        let moves = try KeySync.merge(from: legacy, into: synced, aside: replaced)
        #expect(Set(moves.superseded) == ["openai", "gemini"] && moves.moved.isEmpty && Set(moves.setAside) == ["openai", "gemini"])
        #expect(legacy.attributes("openai") == nil && replaced.read("openai") == "sk-test-legacy-older-0001")
        #expect(replaced.attributes("openai")?.saved == Self.year && synced.read("openai") == "sk-test-synced-newer-0002")
        #expect(replaced.read("gemini") == "sk-test-same-key-0003")
        #expect(legacy.attributes("gemini") == nil && synced.read("gemini") == "sk-test-same-key-0003")

        let back = KeySyncTests.store(.legacy), aside = KeySyncTests.store(.legacy)
        _ = back.write("gemini", "sk-test-same-key-0003", "AllInOneIME: test", "", nil, Self.year)
        let off = try KeySync.merge(from: synced, into: back, aside: aside)
        #expect(off.moved.contains("gemini") && aside.accounts().isEmpty && back.attributes("gemini")?.saved == Self.week)
    }
}

/// Replaced copies (`KeySync.replacedService`, `Stores.replaced`): never read back as the key in use; Remove… takes
/// them too; and an account whose copy can't be kept, or whose key in the other store can't be read, is left as it is.
struct KeySyncSetAsideTests {
    static let old = Date(timeIntervalSince1970: 1_760_000_000), new = Date(timeIntervalSince1970: 1_790_000_000)
    static func write(_ store: APIKeys.Keychain, _ key: String, saved: Date?, account: String = "openai",
                      label: String = "AllInOneIME: test") {
        _ = store.write(account, key, label, "api.openai.com", APIKeys.ending(of: key), saved)
    }

    /// A key written over in iCloud Keychain is kept first; the label of a replaced copy says so, once.
    @Test func aKeyWrittenOverIsKept() throws {
        let stores = KeySyncTests.stores()
        Self.write(stores.login, "sk-test-legacy-newer-0001", saved: Self.new)
        Self.write(stores.synced, "sk-test-synced-older-0002", saved: Self.old, label: "AllInOneIME: test (replaced)")
        let moves = try stores.turn(syncing: true)
        #expect(moves.moved == ["openai"] && moves.setAside == ["openai"] && moves.isComplete)
        #expect(stores.synced.read("openai") == "sk-test-legacy-newer-0001" && stores.login.attributes("openai") == nil)
        #expect(stores.replaced.read("openai") == "sk-test-synced-older-0002" && stores.replaced.attributes("openai")?.saved == Self.old)
        #expect(stores.replaced.attributes("openai")?.label == "AllInOneIME: test (replaced)")

        // The same key twice: the one leaving the login keychain is kept (as it would be into an empty synced store).
        let same = KeySyncTests.stores()
        Self.write(same.login, "sk-test-same-key-0003", saved: Self.new)
        Self.write(same.synced, "sk-test-same-key-0003", saved: Self.old)
        #expect(try same.turn(syncing: true).setAside == ["openai"] && same.replaced.read("openai") == "sk-test-same-key-0003")
        #expect(same.login.attributes("openai") == nil && same.synced.attributes("openai")?.saved == Self.new)
    }

    /// Two Macs turn key sync on with different keys before seeing each other: each keeps its own as a replaced copy, so
    /// whichever iCloud Keychain keeps, the other survives.
    @Test func twoMacsMovingUnseenBothSurvive() throws {
        let a = KeySyncTests.stores(), b = KeySyncTests.stores()
        Self.write(a.login, "sk-test-mac-a-0001", saved: Self.old)
        Self.write(b.login, "sk-test-mac-b-0002", saved: Self.new)
        #expect(try a.turn(syncing: true).setAside == ["openai"])
        #expect(try b.turn(syncing: true).setAside == ["openai"])
        #expect(a.replaced.read("openai") == "sk-test-mac-a-0001" && b.replaced.read("openai") == "sk-test-mac-b-0002")
        #expect(a.login.attributes("openai") == nil && b.login.attributes("openai") == nil)
    }

    /// A replaced copy that can't be kept: nothing is written over or deleted, tried again later.
    @Test func whatCantBeKeptStays() throws {
        var replaced = KeySyncTests.store(.legacy)
        replaced.write = { _, _, _, _, _, _ in .failed(-25293) }
        let legacy = KeySyncTests.store(.legacy), synced = KeySyncTests.store(.synced)
        let stores = KeySync.Stores(login: legacy, synced: synced, replaced: replaced)
        Self.write(legacy, "sk-test-legacy-newer-0001", saved: Self.new)
        Self.write(synced, "sk-test-synced-older-0002", saved: Self.old)
        Self.write(legacy, "sk-test-legacy-older-0003", saved: Self.old, account: "gemini")
        Self.write(synced, "sk-test-synced-newer-0004", saved: Self.new, account: "gemini")
        Self.write(legacy, "sk-test-legacy-alone-0005", saved: Self.new, account: "anthropic")
        let moves = try stores.turn(syncing: true)
        #expect(Set(moves.mismatched) == ["openai", "gemini", "anthropic"] && !moves.isComplete && moves.setAside.isEmpty)
        #expect(synced.read("openai") == "sk-test-synced-older-0002" && legacy.read("openai") == "sk-test-legacy-newer-0001")
        #expect(legacy.read("gemini") == "sk-test-legacy-older-0003" && synced.read("gemini") == "sk-test-synced-newer-0004")
        #expect(legacy.read("anthropic") != nil && synced.attributes("anthropic") == nil)
    }

    /// The other store's item there but its key unreadable (not arrived yet, say): never written over, tried again.
    @Test func anUnreadableTargetIsNeverWrittenOver() throws {
        let unreadable = Locked(initialState: true)
        var synced = KeySyncTests.store(.synced)
        let inner = synced
        synced.read = { unreadable.withLock { $0 } ? nil : inner.read($0) }
        let stores = KeySync.Stores(login: KeySyncTests.store(.legacy), synced: synced, replaced: KeySyncTests.store(.legacy))
        Self.write(stores.login, "sk-test-legacy-newer-0001", saved: Self.new)
        Self.write(inner, "sk-test-synced-older-0002", saved: Self.old)
        let first = try stores.turn(syncing: true)
        #expect(first.mismatched == ["openai"] && !first.isComplete)
        #expect(inner.read("openai") == "sk-test-synced-older-0002" && stores.login.read("openai") != nil)
        unreadable.withLock { $0 = false }
        let again = try stores.turn(syncing: true)
        #expect(again.moved == ["openai"] && again.isComplete && inner.read("openai") == "sk-test-legacy-newer-0001")
        #expect(stores.replaced.read("openai") == "sk-test-synced-older-0002")
    }

    /// Remove… takes the replaced copy too, whether this Mac syncs keys or not; nothing else reads it.
    @Test func removeTakesTheReplacedCopy() throws {
        for syncing in [false, true] {
            let stores = KeySyncTests.stores(syncing: syncing)
            Self.write(stores.replaced, "sk-test-replaced-0001", saved: Self.old)
            #expect(stores.store.attributes("openai") == nil && stores.store.read("openai") == nil)
            #expect(!stores.store.accounts().contains("openai"))
            Self.write(stores.login, "sk-test-legacy-0002", saved: Self.new)
            try APIKeys.remove(account: "openai", in: stores.store)
            #expect(stores.replaced.attributes("openai") == nil && stores.login.attributes("openai") == nil)
        }
    }
}

/// A Mac whose clock was set far ahead: its save times count as the oldest, so they never win a merge.
struct KeySyncClockTests {
    static func item(_ saved: Date) -> APIKeys.ItemAttributes {
        APIKeys.ItemAttributes(created: nil, modified: nil, comment: nil, saved: saved)
    }

    @Test func aSaveTimeFarAheadCountsAsTheOldest() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let ahead = Self.item(now.addingTimeInterval(400 * 86_400)), yearAgo = Self.item(now.addingTimeInterval(-365 * 86_400))
        let minuteAgo = Self.item(now.addingTimeInterval(-60)), soon = Self.item(now.addingTimeInterval(3_600))
        #expect(!KeySync.newer(ahead, than: yearAgo, now: now) && KeySync.newer(yearAgo, than: ahead, now: now))
        #expect(KeySync.newer(soon, than: ahead, now: now) && KeySync.newer(soon, than: minuteAgo, now: now))  // within a day
        #expect(KeySync.newer(minuteAgo, than: yearAgo, now: now) && !KeySync.newer(yearAgo, than: minuteAgo, now: now))
        #expect(!KeySync.newer(ahead, than: Self.item(now.addingTimeInterval(500 * 86_400)), now: now))  // both the oldest
    }
}
