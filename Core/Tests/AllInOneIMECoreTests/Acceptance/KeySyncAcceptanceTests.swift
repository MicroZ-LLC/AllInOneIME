import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for API key sync through iCloud Keychain (spec-key-sync.md, "Spec D", scenarios S1-S16, with its
// "Spec changes (2026-10-18, after review)"), written from the spec by an independent reviewer; the implementer may not
// edit them. Each test is named after its scenario.
//
// Nothing here touches the user's keychain: every store is an in-memory one (`APIKeys.Keychain.inMemory()`), wrapped by
// `KSStore` so that a test can see what was read, written and deleted, set an item's modification date and save time,
// make an item "need the password", garble a read-back, or make a store fail with a given status. The global key cache
// is reached only through `Platform.$override`, with no processes (so no login shell is asked for variables).
//
// ASSUMPTIONS (where the spec names an API but not its exact shape; the implementer should match these):
//  A1. `APIKeys.Keychain` gets a `kind` that is a settable stored property (`public var kind`, like its closures), of a
//      nested enum with the cases `.legacy`, `.local`, `.synced`, `.memory`. `inMemory()` has `.memory`; `.login` has
//      `.legacy`. The tests copy an in-memory store, replace its closures and set its `kind`, as `KSStore` does.
//  A2. `APIKeys.Keychain.processIsEntitled` is a static Bool (Apple platforms only); it is false in the test process,
//      which has no keychain-access-groups entitlement. `Platform.systemSecrets` stays `.login` there.
//  A3. `APIKeys.Keychain.routed(local:synced:legacy:syncs:)` is a static func returning a Keychain; `syncs` is an
//      `@escaping @Sendable () -> Bool` asked on every call (the switch can change while the store, chosen once at launch,
//      stays). While `syncs()` is false, reads use local, then legacy (S2: "reads use the local store"), never synced
//      (synced items are left behind when sync is turned off and may change on other Macs). While true, reads try synced,
//      then local, then legacy. Writes go to synced while syncing, except accounts in `APIKeys.neverSynced`, and to local
//      otherwise. `delete` removes the synced, local and legacy copies while `syncs()` is true (S9), and only the local
//      and legacy copies while it is false, never the synced one (S15, spec change 2). A read that finds the key only in
//      legacy copies it into the store writes go to (same label, comment, ending; its time as in A11) and deletes the
//      legacy item: legacy is read once.
//  A4. `APIKeys.neverSynced` is a collection of account names (Set or Array) that contains "hosted".
//  A5. `KeySync.merge(from:into:)` (may throw; its result, if any, is ignored) takes every item of `from` into `into`,
//      the newest per account winning (by A11's time), and skips `APIKeys.neverSynced` accounts. It then deletes the items
//      it copied from `from`, unless `from.kind == .synced`: a merge never deletes synced items (Decision 10: turning sync
//      off on one Mac never deletes keys on another). An item of `from` that loses to a different key in `into` is kept
//      where it was (spec change 1); whether one that loses to the same key is deleted is not checked. Turning sync on is
//      `merge(from: local, into: synced)`; turning it off is `merge(from: synced, into: local)`.
//  A6. `KeySync.migrate(legacy:into:interactive:)` (may throw) returns a value with `moved` and `waiting`, each a
//      collection of account names (Array or Set). An item whose read gives nothing while user interaction is off (it
//      would ask for the password) is `waiting`. A legacy item that loses to a different key already in the new store
//      (another Mac synced a newer one) is kept in legacy and isn't `moved` (S8, S14). The tests pass `into:` the new
//      store as a routed store over their local and synced stores with an EMPTY legacy store, so `into`'s reads never
//      fall back to the legacy store being migrated. The "user interaction off" switch itself is the Apple layer's
//      (`SecKeychainSetUserInteractionAllowed`); here the fake legacy store's `interactionAllowed` stands in for it, and
//      the tests turn it off around the silent pass.
//  A7. A migrated item keeps its label: the tests check the label `migrate` passes to the new store's `write`, so
//      `migrate` needs the legacy item's label from its attributes (e.g. a new `ItemAttributes.label`, which `inMemory()`
//      and `.login` fill). `KSStore` keeps every field `inMemory()` returns and replaces only `modified` and `saved` (A11).
//  A8. `ICloudSyncSettings.keys` is a `var` defaulting to true, encoded only when false; `syncsKeys` is `enabled && keys`.
//  A9. "the mismatch logged" (S6) is not checked: the core's log has no test seam. The tests check that the legacy item
//      is kept and the account is not reported as moved.
//  A10. S13 is checked through `APIKeys.save` (the closures' reads return no status): a write that fails with -25308 or
//      -34018 throws `APIKeys.KeychainError` with that status, and nothing is written to (or deleted from) the legacy
//      store, nor to the local store while syncing.
//  A11. The save time (spec change 1). `APIKeys.ItemAttributes` gets `public var saved: Date?`, when the key was saved
//      (nil: the item doesn't say, as for every item 0.6.4 left). `APIKeys.Keychain.write` gets a sixth, last parameter
//      `_ saved: Date?` (nil: an item's save time is left as it is), stored with the item as an attribute that copies
//      carry (on Apple, e.g. kSecAttrDescription; the "ends:" generic attribute is unchanged) and returned by `attributes`
//      as `saved`. `APIKeys.save` passes the current
//      time. Every copy (merge, migrate, the routed store's first-use move) passes the source item's time, which is its
//      `saved ?? modified`: a copy made today of a key saved a year ago still says a year ago. "Newest" compares each
//      item's `saved ?? modified`. In the fake, `KSStore` keeps the save time per account: `seed(saved:)` sets it, each
//      `write` with a non-nil `saved` sets it, `setComment` leaves it, `delete` drops it, and `attributes` returns it
//      (over whatever `inMemory()` keeps). `seed(modified:)` sets the modification date; any write or comment change
//      resets it to the current time (as the real keychain does), which is later than every `KS.t(_)` date, so a test
//      that compares by modification date where a save time exists gets the wrong winner.

// MARK: - The rig

enum KS {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    static func t(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    static let openAILabel = "AllInOneIME: OpenAI-compatible API"

    /// Runs `body` with `store` as the platform's secret store and no processes (no login shell is read).
    static func with<T>(_ store: APIKeys.Keychain, _ body: () throws -> T) rethrows -> T {
        var platform = Platform.current
        platform.secrets = store
        platform.processes = NoProcessLauncher()
        return try Platform.$override.withValue(platform) { try body() }
    }

    /// The routed store over the three fakes.
    static func routed(local: KSStore, synced: KSStore, legacy: KSStore,
                       syncs: @escaping @Sendable () -> Bool) -> APIKeys.Keychain {
        .routed(local: local.keychain, synced: synced.keychain, legacy: legacy.keychain, syncs: syncs)
    }

    /// The new store a migration goes into: routed over `local` and `synced`, with nothing behind it (A6).
    static func newStore(local: KSStore, synced: KSStore, syncs: @escaping @Sendable () -> Bool) -> APIKeys.Keychain {
        .routed(local: local.keychain, synced: synced.keychain, legacy: KSStore(.legacy, "empty").keychain, syncs: syncs)
    }

    static func keychainError(_ body: () throws -> Void) -> APIKeys.KeychainError? {
        do {
            try body()
            return nil
        } catch let error as APIKeys.KeychainError {
            return error
        } catch {
            return nil
        }
    }
}

/// What the fakes did, in order, across stores: "synced.read:openai", "legacy.delete:openai", …
final class KSLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func add(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
    func index(of entry: String) -> Int? { all.firstIndex(of: entry) }
}

/// An in-memory store that records what is done to it (A1, A7, A11).
final class KSStore: @unchecked Sendable {
    enum Role { case legacy, local, synced }
    struct Write: Equatable {
        var account: String
        var key: String
        var label: String
        var comment: String
        var ending: String?
    }

    let role: Role
    let name: String
    let log: KSLog
    private let inner = APIKeys.Keychain.inMemory()
    private let lock = NSLock()
    private var dates: [String: Date] = [:]
    private var savedTimes: [String: Date] = [:]
    private var recordedWrites: [Write] = []
    private var recordedDeletes: [String] = []
    private var promptingReads: [String: Int] = [:]
    private var passwordAccounts: Set<String> = []
    private var interaction = true
    private var garbledAccounts: Set<String> = []
    private var failingStatus: Int32?

    init(_ role: Role, _ name: String? = nil, log: KSLog = KSLog()) {
        self.role = role
        self.name = name ?? "\(role)"
        self.log = log
    }

    // Set-up.

    /// An item already there, last changed at `modified` (as another Mac or an earlier version left it), saved at
    /// `saved` (nil: it doesn't say when, as 0.6.4's items don't). `modified` may be later than `saved`: a copy or a
    /// comment change since (A11).
    func seed(_ account: String, _ key: String, label: String = "AllInOneIME: test", host: String = "", modified: Date,
              saved: Date? = nil) {
        _ = inner.write(account, key, label, host, APIKeys.ending(of: key), saved)
        lock.withLock {
            dates[account] = modified
            savedTimes[account] = saved
        }
    }

    /// Reading these asks for the password: while interaction is off, the read gives nothing.
    func needPassword(_ accounts: Set<String>) { lock.withLock { passwordAccounts = accounts } }
    var interactionAllowed: Bool {
        get { lock.withLock { interaction } }
        set { lock.withLock { interaction = newValue } }
    }
    /// A read-back of these gives something else than was written.
    func garble(_ accounts: Set<String>) { lock.withLock { garbledAccounts = accounts } }
    /// Every write, comment change and delete fails with `status`.
    func fail(with status: Int32?) { lock.withLock { failingStatus = status } }

    // What is there, and what was done (bypassing the counters).

    func value(_ account: String) -> String? { inner.read(account) }
    func has(_ account: String) -> Bool { inner.attributes(account) != nil }
    func comment(_ account: String) -> String? { inner.attributes(account)?.comment }
    func modified(_ account: String) -> Date? { attributes(account)?.modified }
    func saved(_ account: String) -> Date? { attributes(account)?.saved }
    var writes: [Write] { lock.withLock { recordedWrites } }
    var deletes: [String] { lock.withLock { recordedDeletes } }
    /// Reads that gave the key (that would have asked, for an item that needs the password).
    func reads(_ account: String) -> Int { lock.withLock { promptingReads[account, default: 0] } }

    private func attributes(_ account: String) -> APIKeys.ItemAttributes? {
        guard var found = inner.attributes(account) else { return nil }
        let (date, saved) = lock.withLock { (dates[account], savedTimes[account]) }
        if let date { found.modified = date }
        found.saved = saved
        return found
    }

    private func changed(_ account: String) { lock.withLock { dates[account] = nil } }

    var keychain: APIKeys.Keychain {
        let inner = self.inner
        var store = inner
        store.attributes = { [self] account in attributes(account) }
        store.read = { [self] account in
            log.add("\(name).read:\(account)")
            guard inner.attributes(account) != nil else { return nil }
            let (needs, allowed, garbled) = lock.withLock {
                (passwordAccounts.contains(account), interaction, garbledAccounts.contains(account))
            }
            if needs && !allowed { return nil }
            lock.withLock { promptingReads[account, default: 0] += 1 }
            return garbled ? "garbled-read-back" : inner.read(account)
        }
        store.write = { [self] account, key, label, comment, ending, saved in
            log.add("\(name).write:\(account)")
            if let status = lock.withLock({ failingStatus }) { return .failed(status) }
            lock.withLock {
                recordedWrites.append(Write(account: account, key: key, label: label, comment: comment, ending: ending))
                if let saved { savedTimes[account] = saved }  // nil: left as it is (A11)
            }
            changed(account)
            return inner.write(account, key, label, comment, ending, saved)
        }
        store.setComment = { [self] account, comment in
            log.add("\(name).setComment:\(account)")
            if let status = lock.withLock({ failingStatus }) { return .failed(status) }
            changed(account)
            return inner.setComment(account, comment)
        }
        store.delete = { [self] account in
            log.add("\(name).delete:\(account)")
            if let status = lock.withLock({ failingStatus }) { return .failed(status) }
            lock.withLock {
                recordedDeletes.append(account)
                savedTimes[account] = nil
            }
            changed(account)
            return inner.delete(account)
        }
        switch role {
        case .legacy: store.kind = .legacy
        case .local: store.kind = .local
        case .synced: store.kind = .synced
        }
        return store
    }
}

// MARK: - The scenarios

@Suite(.serialized)
struct KeySyncAcceptanceTests {
    /// S1: without the entitlement the store is today's login keychain (`.legacy`), as in 0.6.4.
    @Test func s1_withoutTheEntitlementTheStoreIsTheLoginKeychain() {
        #expect(APIKeys.Keychain.inMemory().kind == .memory)
        #if canImport(Security)
        #expect(APIKeys.Keychain.processIsEntitled == false)  // the test process has no keychain-access-groups
        #expect(APIKeys.Keychain.login.kind == .legacy)
        #expect(Platform.systemSecrets.kind == .legacy)
        #endif
    }

    /// S2: sync off (the main switch off, or the keys row off): saves and reads use the local store.
    @Test func s2_syncOffSavesAndReadsUseTheLocalStore() throws {
        #expect(ICloudSyncSettings().syncsKeys == false)  // sync is off by default
        var rowOff = ICloudSyncSettings(enabled: true)
        rowOff.keys = false
        #expect(rowOff.syncsKeys == false)

        for settings in [ICloudSyncSettings(), rowOff] {
            let log = KSLog()
            let local = KSStore(.local, log: log), synced = KSStore(.synced, log: log), legacy = KSStore(.legacy, log: log)
            // Left behind in iCloud Keychain when sync was turned off (and changed since on another Mac).
            synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(500))
            let store = KS.routed(local: local, synced: synced, legacy: legacy, syncs: { settings.syncsKeys })

            try APIKeys.save("sk-test-local-openai-0001", account: "openai", label: KS.openAILabel, in: store)
            #expect(local.value("openai") == "sk-test-local-openai-0001")
            #expect(!synced.has("openai") && !legacy.has("openai"))
            #expect(store.read("openai") == "sk-test-local-openai-0001")

            try APIKeys.save("token-test-hosted-0001", account: "hosted", label: "AllInOneIME: AllInOneIME Cloud", in: store)
            #expect(local.value("hosted") == "token-test-hosted-0001" && !synced.has("hosted"))

            try APIKeys.save("sk-test-local-gemini-0001", account: "gemini", label: "AllInOneIME: Gemini API", in: store)
            #expect(local.value("gemini") == "sk-test-local-gemini-0001")
            #expect(store.read("gemini") == "sk-test-local-gemini-0001", "a read while sync is off used the synced store")
            #expect(synced.value("gemini") == "sk-test-synced-gemini-0001" && synced.writes.isEmpty && synced.deletes.isEmpty)
        }
    }

    /// S3: sync on: `openai` goes to the synced store; `hosted` (never synced) goes to the local one.
    @Test func s3_syncOnOpenAIGoesToSyncedHostedToLocal() throws {
        // The settings: `keys` defaults to true, is encoded only when it differs, and counts only with the main switch.
        #expect(ICloudSyncSettings().keys == true)
        let on = ICloudSyncSettings(enabled: true)
        #expect(on.syncsKeys == true)
        let encodedOn = String(decoding: try JSONEncoder().encode(on), as: UTF8.self)
        #expect(!encodedOn.contains("\"keys\""), "\(encodedOn)")
        var rowOff = on
        rowOff.keys = false
        let encodedOff = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(rowOff)) as? [String: Any]
        #expect(encodedOff?["keys"] as? Bool == false)
        let decoded = try JSONDecoder().decode(ICloudSyncSettings.self, from: Data(#"{"enabled": true}"#.utf8))
        #expect(decoded.keys == true && decoded.syncsKeys == true)
        let decodedOff = try JSONDecoder().decode(ICloudSyncSettings.self, from: Data(#"{"enabled": true, "keys": false}"#.utf8))
        #expect(decodedOff.keys == false && decodedOff.syncsKeys == false)

        #expect(APIKeys.neverSynced.contains("hosted"))
        #expect(!APIKeys.neverSynced.contains("openai"))

        let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy)
        let store = KS.routed(local: local, synced: synced, legacy: legacy, syncs: { on.syncsKeys })
        try APIKeys.save("sk-test-synced-openai-0001", account: "openai", label: KS.openAILabel, in: store)
        #expect(synced.value("openai") == "sk-test-synced-openai-0001")
        #expect(!local.has("openai") && !legacy.has("openai"))
        #expect(store.read("openai") == "sk-test-synced-openai-0001")

        try APIKeys.save("token-test-hosted-0001", account: "hosted", label: "AllInOneIME: AllInOneIME Cloud", in: store)
        #expect(local.value("hosted") == "token-test-hosted-0001")
        #expect(!synced.has("hosted") && !legacy.has("hosted"))
        #expect(store.read("hosted") == "token-test-hosted-0001")
    }

    /// S4: turning sync on moves the local items into the synced store, newest winning by the time each key was saved
    /// (A11), and removes the local copies it moved. A local key that loses to a different synced one stays where it was.
    @Test func s4_turningOnNewestWinsAndTheLocalCopyIsRemoved() throws {
        let local = KSStore(.local), synced = KSStore(.synced)
        // Saved later here than the synced one, though another Mac's comment change restamped the synced item since:
        // the local value wins.
        local.seed("openai", "sk-test-local-newer-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200),
                   saved: KS.t(200))
        synced.seed("openai", "sk-test-synced-older-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300),
                    saved: KS.t(100))
        // Saved earlier here, though a host bound here since restamped it: the synced value is kept, and so is this one.
        local.seed("gemini", "sk-test-local-older-0001", host: "generativelanguage.googleapis.com", modified: KS.t(500),
                   saved: KS.t(100))
        synced.seed("gemini", "sk-test-synced-newer-0001", modified: KS.t(200), saved: KS.t(200))
        // Neither says when it was saved: the modification dates decide, and the local value wins.
        let toolAccount = "extension.com.example.tool.token"
        local.seed(toolAccount, "tok-test-local-newer-0001", modified: KS.t(200))
        synced.seed(toolAccount, "tok-test-synced-older-0001", modified: KS.t(100))
        // Only here: it moves.
        local.seed("anthropic", "sk-test-local-only-0001", modified: KS.t(100), saved: KS.t(100))
        // Never synced: it stays here, and isn't put in iCloud Keychain.
        local.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))

        _ = try KeySync.merge(from: local.keychain, into: synced.keychain)

        #expect(synced.value("openai") == "sk-test-local-newer-0001", "the modification date won over the save time")
        #expect(synced.saved("openai") == KS.t(200), "the copy doesn't carry the time its key was saved")
        #expect(synced.value("gemini") == "sk-test-synced-newer-0001", "the modification date won over the save time")
        #expect(synced.value(toolAccount) == "tok-test-local-newer-0001")
        #expect(synced.value("anthropic") == "sk-test-local-only-0001")
        #expect(!local.has("openai") && !local.has(toolAccount) && !local.has("anthropic"), "local copies left: \(local.deletes)")
        // The loser's key differs from the winner's: it is never deleted (spec change 1).
        #expect(local.value("gemini") == "sk-test-local-older-0001", "a local key that lost was deleted")
        #expect(local.value("hosted") == "token-test-hosted-0001")
        #expect(!synced.has("hosted"), "the AllInOneIME Cloud sign-in was synced")
    }

    /// S5: turning sync off copies the synced items into local items (newest winning, A11) and leaves the synced store
    /// as it was.
    @Test func s5_turningOffCopiesSyncedIntoLocalAndLeavesSyncedAlone() throws {
        let local = KSStore(.local), synced = KSStore(.synced)
        synced.seed("openai", "sk-test-synced-openai-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200),
                    saved: KS.t(200))
        synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(300), saved: KS.t(300))
        // Saved before the synced one, though a host bound here since restamped it: the synced value wins.
        local.seed("gemini", "sk-test-local-gemini-older1", modified: KS.t(400), saved: KS.t(100))
        local.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))
        let syncedOpenAIStamp = synced.modified("openai"), syncedGeminiStamp = synced.modified("gemini")

        _ = try KeySync.merge(from: synced.keychain, into: local.keychain)

        #expect(local.value("openai") == "sk-test-synced-openai-0001")
        #expect(local.comment("openai") == "api.openai.com")
        #expect(local.saved("openai") == KS.t(200), "the copy doesn't carry the time its key was saved")
        #expect(local.value("gemini") == "sk-test-synced-gemini-0001", "the modification date won over the save time")
        #expect(local.saved("gemini") == KS.t(300))
        #expect(local.value("hosted") == "token-test-hosted-0001")
        // The synced store is unchanged: nothing written to or deleted from it (other Macs keep their keys).
        #expect(synced.writes.isEmpty && synced.deletes.isEmpty)
        #expect(synced.value("openai") == "sk-test-synced-openai-0001" && synced.value("gemini") == "sk-test-synced-gemini-0001")
        #expect(synced.modified("openai") == syncedOpenAIStamp && synced.modified("gemini") == syncedGeminiStamp)
        #expect(synced.saved("openai") == KS.t(200) && synced.saved("gemini") == KS.t(300))
    }

    /// S6: the silent pass copies each readable legacy item (label, host, ending kept), reads the copy back, and deletes the
    /// legacy item only after an equal read-back; on a mismatch the legacy item is kept.
    @Test func s6_migrationCopiesReadsBackThenDeletesTheLegacyItem() throws {
        let log = KSLog()
        let legacy = KSStore(.legacy, log: log), local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
        legacy.seed("openai", "sk-test-legacy-openai-a1b2", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        let extensionAccount = "extension.com.example.tool.token"
        legacy.seed(extensionAccount, "tok-test-extension-c3d4", label: "AllInOneIME: Example Tool token", modified: KS.t(100))
        legacy.seed("hosted", "token-test-hosted-e5f6", label: "AllInOneIME: AllInOneIME Cloud", host: "cloud.example.com",
                    modified: KS.t(100))
        let into = KS.newStore(local: local, synced: synced, syncs: { true })

        legacy.interactionAllowed = false  // the silent pass
        let result = try KeySync.migrate(legacy: legacy.keychain, into: into, interactive: false)
        legacy.interactionAllowed = true

        #expect(Set(result.moved) == ["openai", extensionAccount, "hosted"])
        #expect(Set(result.waiting).isEmpty)

        // Landed in the new store, label, comment (host) and ending kept; the never-synced one locally.
        let openAI = synced.writes.last { $0.account == "openai" }
        #expect(openAI == KSStore.Write(account: "openai", key: "sk-test-legacy-openai-a1b2", label: KS.openAILabel,
                                       comment: "api.openai.com", ending: "a1b2"))
        #expect(synced.value("openai") == "sk-test-legacy-openai-a1b2" && synced.comment("openai") == "api.openai.com")
        let tool = synced.writes.last { $0.account == extensionAccount }
        #expect(tool?.label == "AllInOneIME: Example Tool token" && tool?.ending == "c3d4" && tool?.comment == "")
        let hosted = local.writes.last { $0.account == "hosted" }
        #expect(hosted == KSStore.Write(account: "hosted", key: "token-test-hosted-e5f6", label: "AllInOneIME: AllInOneIME Cloud",
                                        comment: "cloud.example.com", ending: "e5f6"))
        #expect(!synced.has("hosted"))
        // 0.6.4's items don't say when they were saved: each copy says when its legacy item was last changed (A11).
        #expect(synced.saved("openai") == KS.t(100) && synced.saved(extensionAccount) == KS.t(100))
        #expect(local.saved("hosted") == KS.t(100))

        // The legacy items are gone, each deleted only after its copy was read back.
        for (account, store) in [("openai", "synced"), (extensionAccount, "synced"), ("hosted", "local")] {
            #expect(!legacy.has(account), "\(account) left in the legacy store")
            let readBack = log.all.lastIndex(of: "\(store).read:\(account)")
            let deleted = log.index(of: "legacy.delete:\(account)")
            let readBackFirst = readBack.flatMap { read in deleted.map { read < $0 } } ?? false
            #expect(readBackFirst, "\(account): \(log.all)")
        }

        // A read-back that doesn't match: the legacy item is kept, and it isn't reported as moved. The bad copy is taken
        // out of the store it was written to, which didn't hold the account before, and from nowhere else (spec change 3).
        let legacy2 = KSStore(.legacy), local2 = KSStore(.local), synced2 = KSStore(.synced)
        legacy2.seed("openai", "sk-test-legacy-openai-a1b2", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        synced2.garble(["openai"])
        legacy2.interactionAllowed = false
        let mismatch = try KeySync.migrate(legacy: legacy2.keychain, into: KS.newStore(local: local2, synced: synced2, syncs: { true }),
                                           interactive: false)
        legacy2.interactionAllowed = true
        #expect(!Set(mismatch.moved).contains("openai"))
        #expect(legacy2.value("openai") == "sk-test-legacy-openai-a1b2")
        #expect(legacy2.deletes.isEmpty)
        #expect(!synced2.has("openai"), "the copy that didn't read back was left in the synced store")
        #expect(local2.deletes.isEmpty, "the clean-up went through the routed store: \(local2.deletes)")
    }

    /// S7: an item that needs the password is skipped by the silent pass, and migrates at its first `load`, with one read.
    @Test func s7_anItemThatNeedsThePasswordMigratesAtItsFirstLoad() throws {
        let legacy = KSStore(.legacy), local = KSStore(.local), synced = KSStore(.synced)
        legacy.seed("gemini", "sk-test-legacy-gemini-g7h8", label: "AllInOneIME: Gemini API", modified: KS.t(100))
        legacy.needPassword(["gemini"])

        legacy.interactionAllowed = false
        let result = try KeySync.migrate(legacy: legacy.keychain, into: KS.newStore(local: local, synced: synced, syncs: { true }),
                                         interactive: false)
        legacy.interactionAllowed = true
        #expect(Set(result.waiting) == ["gemini"])
        #expect(!Set(result.moved).contains("gemini"))
        #expect(legacy.has("gemini") && legacy.deletes.isEmpty)
        #expect(!synced.has("gemini") && !local.has("gemini"))
        #expect(legacy.reads("gemini") == 0)  // the silent pass asked nothing

        let store = KS.routed(local: local, synced: synced, legacy: legacy, syncs: { true })
        let first = KS.with(store) { APIKeys.load(.gemini) }
        #expect(first == "sk-test-legacy-gemini-g7h8")
        #expect(legacy.reads("gemini") == 1)
        #expect(synced.value("gemini") == "sk-test-legacy-gemini-g7h8", "not migrated at its first load")
        #expect(synced.saved("gemini") == KS.t(100), "the copy doesn't say when its key was saved")
        #expect(!legacy.has("gemini"))
        let again = KS.with(store) { APIKeys.load(.gemini) }
        #expect(again == "sk-test-legacy-gemini-g7h8")
        #expect(legacy.reads("gemini") == 1, "the password was asked for again")
    }

    /// S8: a duplicate during migration (another Mac synced first): the newer one wins, by the time each key was saved
    /// (A11). A legacy key that loses to a different one is kept in the login keychain.
    @Test func s8_aDuplicateDuringMigrationTheNewerWins() throws {
        let legacy = KSStore(.legacy), local = KSStore(.local), synced = KSStore(.synced)
        // Another Mac saved a newer openai key: it stays, and the older legacy one isn't deleted.
        legacy.seed("openai", "sk-test-legacy-older-0001", label: KS.openAILabel, modified: KS.t(200))
        synced.seed("openai", "sk-test-synced-newer-0001", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
        // The legacy gemini key was saved after the synced one, though the synced item was restamped since (a copy or a
        // comment change): the legacy key wins.
        legacy.seed("gemini", "sk-test-legacy-newer-0001", label: "AllInOneIME: Gemini API", modified: KS.t(300))
        synced.seed("gemini", "sk-test-synced-older-0001", label: "AllInOneIME: Gemini API", modified: KS.t(400),
                    saved: KS.t(200))
        let into = KS.newStore(local: local, synced: synced, syncs: { true })

        legacy.interactionAllowed = false
        let result = try KeySync.migrate(legacy: legacy.keychain, into: into, interactive: false)
        legacy.interactionAllowed = true

        #expect(synced.value("openai") == "sk-test-synced-newer-0001")
        #expect(!Set(result.moved).contains("openai"))
        #expect(legacy.value("openai") == "sk-test-legacy-older-0001", "a legacy key that lost was deleted")
        #expect(synced.value("gemini") == "sk-test-legacy-newer-0001", "the modification date won over the save time")
        #expect(synced.saved("gemini") == KS.t(300))
        #expect(Set(result.moved).contains("gemini"))
        #expect(!legacy.has("gemini"))
        #expect(into.read("openai") == "sk-test-synced-newer-0001" && into.read("gemini") == "sk-test-legacy-newer-0001")
    }

    /// S9: Remove Key… while syncing deletes the synced, local and legacy copies.
    @Test func s9_removeWhileSyncingDeletesEveryCopy() throws {
        let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy)
        synced.seed("openai", "sk-test-synced-openai-0001", modified: KS.t(300))
        local.seed("openai", "sk-test-local-openai-0001", modified: KS.t(200))
        legacy.seed("openai", "sk-test-legacy-openai-0001", modified: KS.t(100))
        synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(300))
        let store = KS.routed(local: local, synced: synced, legacy: legacy, syncs: { true })

        try APIKeys.remove(account: "openai", in: store)

        #expect(!synced.has("openai") && !local.has("openai") && !legacy.has("openai"))
        #expect(!APIKeys.hasKeychainKey(account: "openai", in: store) && store.read("openai") == nil)
        #expect(synced.value("gemini") == "sk-test-synced-gemini-0001")  // only that key
    }

    /// S10: an empty save never removes a key, in any of the stores.
    @Test func s10_anEmptySaveNeverRemovesAKey() throws {
        let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy)
        let store = KS.routed(local: local, synced: synced, legacy: legacy, syncs: { true })
        try APIKeys.save("sk-test-synced-openai-0001", account: "openai", label: KS.openAILabel, in: store)
        local.seed("hosted", "token-test-hosted-0001", modified: KS.t(100))
        legacy.seed("gemini", "sk-test-legacy-gemini-0001", modified: KS.t(100))
        for (account, empty) in [("openai", ""), ("openai", "  \n"), ("hosted", ""), ("gemini", "\t")] {
            #expect(throws: APIKeys.EmptyKey.self) { try APIKeys.save(empty, account: account, label: "AllInOneIME: test", in: store) }
        }
        #expect(synced.value("openai") == "sk-test-synced-openai-0001")
        #expect(local.value("hosted") == "token-test-hosted-0001")
        #expect(legacy.value("gemini") == "sk-test-legacy-gemini-0001")
        #expect(synced.deletes.isEmpty && local.deletes.isEmpty && legacy.deletes.isEmpty)
        #expect(store.read("openai") == "sk-test-synced-openai-0001")
    }

    /// S11: the host binding travels with the synced item: on another Mac the key still goes only to its host.
    @Test func s11_theHostBindingTravelsWithTheSyncedItem() throws {
        let synced = KSStore(.synced)  // iCloud Keychain, shared by both Macs
        let macA = KS.routed(local: KSStore(.local), synced: synced, legacy: KSStore(.legacy), syncs: { true })
        let macB = KS.routed(local: KSStore(.local), synced: synced, legacy: KSStore(.legacy), syncs: { true })

        try APIKeys.save("sk-test-synced-openai-0001", account: "openai", label: KS.openAILabel, host: "API.OpenAI.example",
                         in: macA)
        #expect(synced.comment("openai") == "api.openai.example")

        for mac in [macA, macB] {
            let sent = try KS.with(mac) { try APIKeys.load(.openai, for: "api.openai.example") }
            #expect(sent == "sk-test-synced-openai-0001")
            var saved: String?
            do {
                _ = try KS.with(mac) { try APIKeys.load(.openai, for: "relay.other.example") }
            } catch let ProviderError.keyForAnotherHost(provider, host) where provider == .openai {
                saved = host
            }
            #expect(saved == "api.openai.example", "the key went to another host")
        }
    }

    /// S12: the key cache picks up a key another Mac changed (a new modification stamp), without a restart, reading it
    /// once per change. (An account of its own: other suites' saves of "openai" reset the shared cache's entry.)
    @Test func s12_theKeyCachePicksUpAChangeFromAnotherMac() throws {
        let account = "extension.com.example.keysync-s12.token"
        let synced = KSStore(.synced)
        let store = KS.routed(local: KSStore(.local), synced: synced, legacy: KSStore(.legacy), syncs: { true })
        try APIKeys.save("tok-test-first-0001", account: account, label: "AllInOneIME: test", in: store)
        #expect(KS.with(store) { APIKeys.keychainKey(account: account) } == "tok-test-first-0001")
        #expect(KS.with(store) { APIKeys.keychainKey(account: account) } == "tok-test-first-0001")
        #expect(synced.reads(account) == 1)

        // Another Mac saves a new key: iCloud Keychain brings it with a newer modification date.
        synced.seed(account, "tok-test-second-0002", label: "AllInOneIME: test", modified: Date().addingTimeInterval(60))
        #expect(KS.with(store) { APIKeys.keychainKey(account: account) } == "tok-test-second-0002")
        #expect(KS.with(store) { APIKeys.keychainKey(account: account) } == "tok-test-second-0002")
        #expect(synced.reads(account) == 2)
    }

    /// S13: a locked keychain (-25308) and a missing entitlement (-34018) come out as a `KeychainError`, and never fall
    /// back to the legacy store (nor, while syncing, to the local one).
    @Test func s13_lockedOrUnentitledIsAKeychainErrorNeverAFallback() throws {
        for status: Int32 in [-25308, -34018] {
            for syncing in [true, false] {
                let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy)
                (syncing ? synced : local).fail(with: status)
                let store = KS.routed(local: local, synced: synced, legacy: legacy, syncs: { syncing })
                let error = KS.keychainError {
                    try APIKeys.save("sk-test-openai-0001", account: "openai", label: KS.openAILabel, in: store)
                }
                #expect(error?.status == status, "status \(status), syncing \(syncing): \(String(describing: error))")
                #expect(legacy.writes.isEmpty && legacy.deletes.isEmpty && !legacy.has("openai"),
                        "status \(status), syncing \(syncing): fell back to the legacy store")
                if syncing { #expect(local.writes.isEmpty && !local.has("openai"), "status \(status): fell back to local") }
            }
        }
    }

    /// S14: two Macs migrate one after the other. Mac A has an older key, Mac B a newer one. Whichever migrates first,
    /// B's newer key wins; when A migrates second, A's key isn't deleted from its login keychain.
    @Test func s14_twoMacsMigrateOneAfterTheOtherTheNewerKeyWins() throws {
        // A key saved by this version says when (A11).
        let savedHere = KSStore(.synced)
        let before = Date()
        try APIKeys.save("sk-test-saved-now-0001", account: "openai", label: KS.openAILabel,
                         in: KS.routed(local: KSStore(.local), synced: savedHere, legacy: KSStore(.legacy), syncs: { true }))
        let savedAt = try #require(savedHere.saved("openai"), "APIKeys.save didn't record when the key was saved")
        #expect(savedAt >= before.addingTimeInterval(-2) && savedAt <= Date().addingTimeInterval(2), "\(savedAt)")

        for aFirst in [true, false] {
            let log = KSLog()
            let synced = KSStore(.synced, log: log)  // iCloud Keychain, both Macs'
            let legacyA = KSStore(.legacy, "legacyA", log: log), localA = KSStore(.local, "localA", log: log)
            let legacyB = KSStore(.legacy, "legacyB", log: log), localB = KSStore(.local, "localB", log: log)
            // As 0.6.4 left them: no save time. A's is a year old, B's from last week.
            legacyA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
            legacyB.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200))
            let macA = KS.routed(local: localA, synced: synced, legacy: legacyA, syncs: { true })
            let macB = KS.routed(local: localB, synced: synced, legacy: legacyB, syncs: { true })
            func migrate(_ legacy: KSStore, _ local: KSStore) throws -> [String] {
                legacy.interactionAllowed = false
                defer { legacy.interactionAllowed = true }
                let moves = try KeySync.migrate(legacy: legacy.keychain, into: KS.newStore(local: local, synced: synced, syncs: { true }),
                                                interactive: false)
                return Array(moves.moved)
            }
            let order = aFirst ? "A first" : "B first"

            if aFirst {
                #expect(try migrate(legacyA, localA).contains("openai"), "\(order)")
                // Mac A uses the key: binding its host is a comment change, which restamps the synced item.
                #expect(macA.setComment("openai", "api.openai.com") == .ok)
                #expect(try migrate(legacyB, localB).contains("openai"), "\(order): B's newer key lost: \(log.all)")
                #expect(!legacyB.has("openai"), "\(order): B's key, moved, was left in its login keychain")
            } else {
                #expect(try migrate(legacyB, localB).contains("openai"), "\(order)")
                #expect(macB.setComment("openai", "api.openai.com") == .ok)
                #expect(try !migrate(legacyA, localA).contains("openai"), "\(order): A's older key won: \(log.all)")
                // A's key differs from the winner: it survives in A's login keychain (spec change 1).
                #expect(legacyA.value("openai") == "sk-test-macA-older-a111", "\(order): A's key was deleted: \(log.all)")
                #expect(legacyA.deletes.isEmpty, "\(order): \(log.all)")
            }

            #expect(synced.value("openai") == "sk-test-macB-newer-b222", "\(order): \(log.all)")
            #expect(synced.saved("openai") == KS.t(200), "\(order): the synced copy doesn't say when B's key was saved")
            #expect(synced.comment("openai") == "api.openai.com")
            #expect(APIKeys.keyEnding(account: "openai", in: macA) == "b222")
            // Both Macs use B's key (A's, when kept, is behind it and harmless).
            #expect(macA.read("openai") == "sk-test-macB-newer-b222" && macB.read("openai") == "sk-test-macB-newer-b222", "\(order)")
            #expect(!localA.has("openai") && !localB.has("openai"), "\(order)")
            if !aFirst { #expect(legacyA.has("openai"), "\(order): a routed read deleted A's kept key") }
        }
    }

    /// S15: Remove Key… while this Mac doesn't sync keys deletes this Mac's local and legacy copies, and leaves the
    /// synced copy (the one other Macs use) alone.
    @Test func s15_removeWithKeySyncOffLeavesTheSyncedCopy() throws {
        var rowOff = ICloudSyncSettings(enabled: true)
        rowOff.keys = false
        for settings in [ICloudSyncSettings(), rowOff] {
            let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy)
            synced.seed("openai", "sk-test-synced-openai-0001", modified: KS.t(300), saved: KS.t(300))
            local.seed("openai", "sk-test-local-openai-0001", modified: KS.t(200), saved: KS.t(200))
            legacy.seed("openai", "sk-test-legacy-openai-0001", modified: KS.t(100))
            local.seed("gemini", "sk-test-local-gemini-0001", modified: KS.t(200), saved: KS.t(200))
            let store = KS.routed(local: local, synced: synced, legacy: legacy, syncs: { settings.syncsKeys })

            try APIKeys.remove(account: "openai", in: store)

            let which = settings.enabled ? "keys row off" : "sync off"
            #expect(!local.has("openai") && !legacy.has("openai"), "\(which): this Mac's copies left")
            #expect(synced.value("openai") == "sk-test-synced-openai-0001", "\(which): removed from all Macs")
            #expect(synced.deletes.isEmpty && synced.writes.isEmpty, "\(which): \(synced.deletes)")
            #expect(!APIKeys.hasKeychainKey(account: "openai", in: store) && store.read("openai") == nil, "\(which)")
            #expect(local.value("gemini") == "sk-test-local-gemini-0001")  // only that key
        }
    }

    /// S16: a copy that doesn't read back, into a store that already held the account, keeps that store's item: the
    /// clean-up deletes only a copy it just made in a store that didn't hold the account (spec change 3).
    @Test func s16_aMismatchWhereTheStoreHeldTheAccountKeepsItsItem() throws {
        // Migration: the login keychain's key is newer than the synced one (another Mac's); its copy doesn't read back.
        do {
            let log = KSLog()
            let legacy = KSStore(.legacy, log: log), local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
            synced.seed("openai", "sk-test-synced-other-mac-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            legacy.seed("openai", "sk-test-legacy-newer-0002", label: KS.openAILabel, modified: KS.t(300))
            synced.garble(["openai"])
            legacy.interactionAllowed = false
            let result = try KeySync.migrate(legacy: legacy.keychain, into: KS.newStore(local: local, synced: synced, syncs: { true }),
                                             interactive: false)
            legacy.interactionAllowed = true
            #expect(!Set(result.moved).contains("openai"))
            #expect(synced.has("openai") && synced.deletes.isEmpty, "the synced item other Macs use was deleted: \(log.all)")
            #expect(local.deletes.isEmpty, "the clean-up went through the routed store: \(log.all)")
            #expect(legacy.value("openai") == "sk-test-legacy-newer-0002" && legacy.deletes.isEmpty, "\(log.all)")
        }
        // Turning sync on: this Mac's key is newer; its copy into the synced store doesn't read back.
        do {
            let log = KSLog()
            let local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
            local.seed("openai", "sk-test-local-newer-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            synced.seed("openai", "sk-test-synced-older-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            synced.garble(["openai"])
            _ = try KeySync.merge(from: local.keychain, into: synced.keychain)
            #expect(synced.has("openai") && synced.deletes.isEmpty, "the synced item other Macs use was deleted: \(log.all)")
            #expect(local.value("openai") == "sk-test-local-newer-0002", "this Mac's key was lost: \(log.all)")
        }
        // Turning sync off: the synced key is newer; its copy into this Mac's store, which held one, doesn't read back.
        do {
            let log = KSLog()
            let local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
            synced.seed("openai", "sk-test-synced-newer-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            local.seed("openai", "sk-test-local-older-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            local.garble(["openai"])
            _ = try KeySync.merge(from: synced.keychain, into: local.keychain)
            #expect(local.has("openai") && local.deletes.isEmpty, "this Mac's item was deleted: \(log.all)")
            #expect(synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
            #expect(synced.value("openai") == "sk-test-synced-newer-0002")
        }
    }
}
