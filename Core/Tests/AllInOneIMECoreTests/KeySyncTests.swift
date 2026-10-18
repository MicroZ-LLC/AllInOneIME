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
        synced.write = { _, _, _, _, _ in .failed(-34018) }
        let local = Self.store(.local)
        _ = local.write("openai", "sk-test-local-0001-abcd", "AllInOneIME: test", "", nil)
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
        _ = legacy.write("gemini", "sk-test-legacy-0001-wxyz", "", "", nil)
        _ = legacy.write("openai", "sk-test-legacy-0002-wxyz", "", "", nil)
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
