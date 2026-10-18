import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for API key sync through iCloud Keychain (spec-key-sync.md, "Spec D", scenarios S1-S21, with its
// "Spec changes (2026-10-18, after review)" and "Spec changes, round 2"), written from the spec by an independent
// reviewer; the implementer may not edit them. Each test is named after its scenario.
//
// Nothing here touches the user's keychain: every store is an in-memory one (`APIKeys.Keychain.inMemory()`), wrapped by
// `KSStore` so that a test can see what was read, written and deleted, set an item's modification date and save time,
// change its modification date later (`touch`, as a 0.6.4 `setComment` does), make an item "need the password", garble
// a read-back, or make a store fail with a given status. The global key cache is reached only through
// `Platform.$override`, with no processes (so no login shell is asked for variables).
//
// ASSUMPTIONS (where the spec names an API but not its exact shape; the implementer should match these):
//  A1. `APIKeys.Keychain` gets a `kind` that is a settable stored property (`public var kind`, like its closures), of a
//      nested enum with the cases `.legacy`, `.local`, `.synced`, `.memory`. `inMemory()` has `.memory`; `.login` has
//      `.legacy`. The tests copy an in-memory store, replace its closures and set its `kind`, as `KSStore` does. The
//      replaced store (A12) is `.local`: it is in the local data protection store, under its own service.
//  A2. `APIKeys.Keychain.processIsEntitled` is a static Bool (Apple platforms only); it is false in the test process,
//      which has no keychain-access-groups entitlement. `Platform.systemSecrets` stays `.login` there.
//  A3. `APIKeys.Keychain.routed(local:synced:legacy:replaced:syncs:)` is a static func returning a Keychain; `replaced`
//      is the replaced store (A12); `syncs` is an `@escaping @Sendable () -> Bool` asked on every call (the switch can
//      change while the store, chosen once at launch, stays). While `syncs()` is false, reads use local, then legacy
//      (S2: "reads use the local store"), never synced (synced items are left behind when sync is turned off and may
//      change on other Macs). While true, reads try synced, then local, then legacy. Reads, `attributes` and `accounts`
//      never look at the replaced store. Writes go to synced while syncing, except accounts in `APIKeys.neverSynced`,
//      and to local otherwise. `delete` removes the synced, local, legacy and replaced copies while `syncs()` is true
//      (S9), and only the local, legacy and replaced copies while it is false, never the synced one (S15, spec change
//      2; round 2, 2: "Remove… on this Mac also deletes the account's replaced copy"). A read that finds the key only in
//      legacy copies it into the store writes go to (same label, comment, ending; its time as in A11) and deletes the
//      legacy item: legacy is read once.
//  A4. `APIKeys.neverSynced` is a collection of account names (Set or Array) that contains "hosted".
//  A5. `KeySync.merge(from:into:aside:)` (may throw; its result, if any, is ignored except in S21) takes every item
//      of `from` into `into`, the newest per account winning (by A11's time, A16), and skips `APIKeys.neverSynced`
//      accounts. It then deletes the items it copied from `from`, unless `from.kind == .synced`: a merge never deletes
//      synced items (Decision 10: turning sync off on one Mac never deletes keys on another). Round 2, 2: an item of
//      `from` that loses to a different key in `into` is moved into `aside`, the replaced store (copied, read back,
//      then deleted from `from`), unless `from` is synced (it stays; what else a synced loser does is not checked); and
//      an item of `into` whose different key is about to be overwritten is first copied into `aside`. Whether a loser
//      with the same key is deleted is not checked. Turning sync on is `merge(from: local, into: synced, aside:)`;
//      turning it off is `merge(from: synced, into: local, aside:)`.
//  A6. `KeySync.migrate(legacy:into:interactive:aside:)` (may throw) returns a value with `moved` and `waiting`,
//      each a collection of account names (Array or Set). An item whose read gives nothing while user interaction is off
//      (it would ask for the password) is `waiting`. A legacy item that loses to a different key already in the new
//      store (another Mac synced a newer one) is not `moved` (S8, S14): when it can be read silently it goes into
//      `aside` (copied, read back, then deleted from legacy); when it can't, it stays in legacy (round 2, 2). A newer
//      legacy key that overwrites a different one in the new store first copies that one into `aside` (S20). The
//      tests pass `into:` the new store as a routed store over their local and synced stores with an EMPTY legacy store
//      (and an empty replaced store of its own), so `into`'s reads never fall back to the legacy store being migrated.
//      The "user interaction off" switch itself is the Apple layer's (`SecKeychainSetUserInteractionAllowed`); here the
//      fake legacy store's `interactionAllowed` stands in for it, and the tests turn it off around the silent pass.
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
//      as `saved`. `APIKeys.save` passes the current time. Every copy (merge, migrate, the routed store's first-use move,
//      a copy into the replaced store) passes the source item's time, which is its `saved ?? modified`: a copy made
//      today of a key saved a year ago still says a year ago. "Newest" compares each item's `saved ?? modified`. In the
//      fake, `KSStore` keeps the save time per account: `seed(saved:)` sets it, each `write` with a non-nil `saved` sets
//      it, `setComment` and `touch` leave it, `delete` drops it, and `attributes` returns it (over whatever `inMemory()`
//      keeps). `seed(modified:)` and `touch(modified:)` set the modification date; any write or comment change through
//      the store resets it to the current time (as the real keychain does), which is later than every `KS.t(_)` date,
//      so a test that compares by modification date where a save time exists gets the wrong winner.
//  A12. The replaced store (round 2, 2). `KeySync.replacedService` is "AllInOneIME replaced API key"; on the Mac the
//      replaced store is `.dataProtection(group: KeySync.accessGroup, synchronizable: false, service:
//      KeySync.replacedService)`. In the core it is an ordinary `APIKeys.Keychain` passed explicitly (`replaced:` to
//      `routed` and `Stores`, A3 and A15; `aside:` to `merge` and `migrate`, A5 and A6), one item per account (a later
//      loser of the same account may replace an earlier one: no test has two). It is only a safety copy: nothing moves
//      out of it, and only the read-back of a copy just written may read it.
//  A13. `KSStore.garble(_:)`: a read of a garbled account gives something else than was written, but only once the
//      code under test wrote that account in that store (a seeded item, another Mac's, reads back fine; a copy made from
//      it into the replaced store is good).
//  A14. `KSStore.touch(_:comment:modified:)` changes an existing item's modification date (and comment) without going
//      through its closures and without changing its save time, as 0.6.4 (a downgrade), a development build or
//      `allinoneime-cli` binding a host to a login keychain item does. On a missing item it does nothing.
//  A15. `KeySync.Stores` gets the replaced store: `init(local:synced:legacy:replaced:quietLegacy:syncing:)`, with
//      `quietLegacy` still optional; `turn(syncing:)` passes it to `merge`, `migrate()` to `migrate`, and `store` to
//      `routed`. `turn(syncing:)` returns a value with `isComplete` (false when a key was left behind: unreadable, or a
//      copy that didn't read back). S21 drives the core through it; its controller half (the `keys-synced` marker) is a
//      self-test case for the implementer, described there.
//  A16. Clock skew (round 2, 4): when comparing, a save time later than now + 1 day counts as now.
//  A17. Accessibility (round 2, 1: local items `AfterFirstUnlock`, only `hosted` `AfterFirstUnlockThisDeviceOnly`) is
//      the Apple layer's and not checked here: the entitled self-test's `pdmn` checks cover it.

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

    /// The routed store over the fakes (A3); a test that doesn't look at the replaced store gets an empty one.
    static func routed(local: KSStore, synced: KSStore, legacy: KSStore, replaced: KSStore = KSStore(.replaced),
                       syncs: @escaping @Sendable () -> Bool) -> APIKeys.Keychain {
        .routed(local: local.keychain, synced: synced.keychain, legacy: legacy.keychain, replaced: replaced.keychain,
                syncs: syncs)
    }

    /// The new store a migration goes into: routed over `local` and `synced`, with nothing behind it (A6).
    static func newStore(local: KSStore, synced: KSStore, syncs: @escaping @Sendable () -> Bool) -> APIKeys.Keychain {
        .routed(local: local.keychain, synced: synced.keychain, legacy: KSStore(.legacy, "empty").keychain,
                replaced: KSStore(.replaced, "empty-replaced").keychain, syncs: syncs)
    }

    /// The silent pass at launch over the fakes: `legacy`'s items into the new store over `local` and `synced`, losers
    /// into `replaced`, with asking turned off around it.
    static func silentPass(_ legacy: KSStore, local: KSStore, synced: KSStore, replaced: KSStore,
                           syncs: @escaping @Sendable () -> Bool = { true }) throws -> (moved: Set<String>, waiting: Set<String>) {
        legacy.interactionAllowed = false
        defer { legacy.interactionAllowed = true }
        let moves = try KeySync.migrate(legacy: legacy.keychain, into: newStore(local: local, synced: synced, syncs: syncs),
                                        interactive: false, aside: replaced.keychain)
        return (Set(moves.moved), Set(moves.waiting))
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
    func lastIndex(of entry: String) -> Int? { all.lastIndex(of: entry) }
    /// Whether `first` happened, and before `second`'s last time.
    func happened(_ first: String, before second: String) -> Bool {
        guard let a = index(of: first), let b = lastIndex(of: second) else { return false }
        return a < b
    }
}

/// An in-memory store that records what is done to it (A1, A7, A11, A13, A14).
final class KSStore: @unchecked Sendable {
    enum Role { case legacy, local, synced, replaced }
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
    private var garbledWritten: Set<String> = []
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

    /// Another program changed the item since (0.6.4 binding a host with `setComment`): its modification date is now
    /// `modified`, its save time as it was (A14). Nothing there: nothing happens.
    func touch(_ account: String, comment: String? = nil, modified: Date) {
        guard inner.attributes(account) != nil else { return }
        if let comment { _ = inner.setComment(account, comment) }
        lock.withLock { dates[account] = modified }
    }

    /// Reading these asks for the password: while interaction is off, the read gives nothing.
    func needPassword(_ accounts: Set<String>) { lock.withLock { passwordAccounts = accounts } }
    var interactionAllowed: Bool {
        get { lock.withLock { interaction } }
        set { lock.withLock { interaction = newValue } }
    }
    /// A read-back of these, once written through this store, gives something else than was written (A13).
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
                (passwordAccounts.contains(account), interaction, garbledWritten.contains(account))
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
                if garbledAccounts.contains(account) { garbledWritten.insert(account) }
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
                garbledWritten.remove(account)
            }
            changed(account)
            return inner.delete(account)
        }
        switch role {
        case .legacy: store.kind = .legacy
        case .local, .replaced: store.kind = .local
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

        let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy), replaced = KSStore(.replaced)
        let store = KS.routed(local: local, synced: synced, legacy: legacy, replaced: replaced, syncs: { on.syncsKeys })
        try APIKeys.save("sk-test-synced-openai-0001", account: "openai", label: KS.openAILabel, in: store)
        #expect(synced.value("openai") == "sk-test-synced-openai-0001")
        #expect(!local.has("openai") && !legacy.has("openai") && !replaced.has("openai"))
        #expect(store.read("openai") == "sk-test-synced-openai-0001")

        try APIKeys.save("token-test-hosted-0001", account: "hosted", label: "AllInOneIME: AllInOneIME Cloud", in: store)
        #expect(local.value("hosted") == "token-test-hosted-0001")
        #expect(!synced.has("hosted") && !legacy.has("hosted") && !replaced.has("hosted"))
        #expect(store.read("hosted") == "token-test-hosted-0001")
    }

    /// S4: turning sync on moves the local items into the synced store, newest winning by the time each key was saved
    /// (A11, A16), and removes the local copies it moved. A local key that loses to a different synced one is kept aside
    /// under the replaced service, and so is a synced key a newer local one overwrites (round 2, 2).
    @Test func s4_turningOnNewestWinsAndTheLocalCopyIsRemoved() throws {
        let local = KSStore(.local), synced = KSStore(.synced), replaced = KSStore(.replaced)
        // Saved later here than the synced one, though another Mac's comment change restamped the synced item since:
        // the local value wins, and the synced one is kept aside.
        local.seed("openai", "sk-test-local-newer-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200),
                   saved: KS.t(200))
        synced.seed("openai", "sk-test-synced-older-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300),
                    saved: KS.t(100))
        // Saved earlier here, though a host bound here since restamped it: the synced value is kept, this one put aside.
        local.seed("gemini", "sk-test-local-older-0001", host: "generativelanguage.googleapis.com", modified: KS.t(500),
                   saved: KS.t(100))
        synced.seed("gemini", "sk-test-synced-newer-0001", modified: KS.t(200), saved: KS.t(200))
        // Neither says when it was saved: the modification dates decide, and the local value wins.
        let toolAccount = "extension.com.example.tool.token"
        local.seed(toolAccount, "tok-test-local-newer-0001", modified: KS.t(200))
        synced.seed(toolAccount, "tok-test-synced-older-0001", modified: KS.t(100))
        // Another Mac's clock is ten days ahead (A16): its save time counts as now, so a key saved here an hour "from
        // now" (within a day) still wins.
        let skewAccount = "extension.com.example.skew.token"
        local.seed(skewAccount, "tok-test-local-skew-0001", modified: KS.t(100), saved: Date().addingTimeInterval(3600))
        synced.seed(skewAccount, "tok-test-synced-skew-0001", modified: KS.t(100), saved: Date().addingTimeInterval(10 * 86400))
        // Only here: it moves.
        local.seed("anthropic", "sk-test-local-only-0001", modified: KS.t(100), saved: KS.t(100))
        // Never synced: it stays here, and isn't put in iCloud Keychain.
        local.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))

        _ = try KeySync.merge(from: local.keychain, into: synced.keychain, aside: replaced.keychain)

        #expect(synced.value("openai") == "sk-test-local-newer-0001", "the modification date won over the save time")
        #expect(synced.saved("openai") == KS.t(200), "the copy doesn't carry the time its key was saved")
        #expect(synced.value("gemini") == "sk-test-synced-newer-0001", "the modification date won over the save time")
        #expect(synced.value(toolAccount) == "tok-test-local-newer-0001")
        #expect(synced.value(skewAccount) == "tok-test-local-skew-0001", "a save time ten days ahead won")
        #expect(synced.value("anthropic") == "sk-test-local-only-0001")
        #expect(!local.has("openai") && !local.has(toolAccount) && !local.has("anthropic"), "local copies left: \(local.deletes)")
        // The loser's key differs from the winner's: it is kept aside, not where it was (round 2, 2).
        #expect(replaced.value("gemini") == "sk-test-local-older-0001", "a local key that lost isn't kept aside")
        #expect(!local.has("gemini"), "a local key that lost was left where routed reads and merges find it")
        // The synced keys a newer local one overwrote are kept aside too.
        #expect(replaced.value("openai") == "sk-test-synced-older-0001", "the overwritten synced key is nowhere")
        #expect(replaced.value(toolAccount) == "tok-test-synced-older-0001", "the overwritten synced key is nowhere")
        #expect(replaced.value(skewAccount) == "tok-test-synced-skew-0001", "the overwritten synced key is nowhere")
        #expect(!replaced.has("anthropic") && !replaced.has("hosted"))
        #expect(local.value("hosted") == "token-test-hosted-0001")
        #expect(!synced.has("hosted"), "the AllInOneIME Cloud sign-in was synced")
    }

    /// S5: turning sync off copies the synced items into local items (newest winning, A11) and leaves the synced store
    /// as it was. A local key the synced one overwrites is kept aside under the replaced service (round 2, 2).
    @Test func s5_turningOffCopiesSyncedIntoLocalAndLeavesSyncedAlone() throws {
        let local = KSStore(.local), synced = KSStore(.synced), replaced = KSStore(.replaced)
        synced.seed("openai", "sk-test-synced-openai-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200),
                    saved: KS.t(200))
        synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(300), saved: KS.t(300))
        // Saved before the synced one, though a host bound here since restamped it: the synced value wins.
        local.seed("gemini", "sk-test-local-gemini-older1", modified: KS.t(400), saved: KS.t(100))
        local.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))
        let syncedOpenAIStamp = synced.modified("openai"), syncedGeminiStamp = synced.modified("gemini")

        _ = try KeySync.merge(from: synced.keychain, into: local.keychain, aside: replaced.keychain)

        #expect(local.value("openai") == "sk-test-synced-openai-0001")
        #expect(local.comment("openai") == "api.openai.com")
        #expect(local.saved("openai") == KS.t(200), "the copy doesn't carry the time its key was saved")
        #expect(local.value("gemini") == "sk-test-synced-gemini-0001", "the modification date won over the save time")
        #expect(local.saved("gemini") == KS.t(300))
        #expect(replaced.value("gemini") == "sk-test-local-gemini-older1", "the overwritten local key is nowhere")
        #expect(!replaced.has("openai") && !replaced.has("hosted"))
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
        let replaced = KSStore(.replaced, log: log)
        legacy.seed("openai", "sk-test-legacy-openai-a1b2", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        let extensionAccount = "extension.com.example.tool.token"
        legacy.seed(extensionAccount, "tok-test-extension-c3d4", label: "AllInOneIME: Example Tool token", modified: KS.t(100))
        legacy.seed("hosted", "token-test-hosted-e5f6", label: "AllInOneIME: AllInOneIME Cloud", host: "cloud.example.com",
                    modified: KS.t(100))

        let result = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)

        #expect(result.moved == ["openai", extensionAccount, "hosted"])
        #expect(result.waiting.isEmpty)
        #expect(replaced.writes.isEmpty, "nothing lost, yet something was put aside: \(log.all)")

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
        let mismatch = try KS.silentPass(legacy2, local: local2, synced: synced2, replaced: KSStore(.replaced))
        #expect(!mismatch.moved.contains("openai"))
        #expect(legacy2.value("openai") == "sk-test-legacy-openai-a1b2")
        #expect(legacy2.deletes.isEmpty)
        #expect(!synced2.has("openai"), "the copy that didn't read back was left in the synced store")
        #expect(local2.deletes.isEmpty, "the clean-up went through the routed store: \(local2.deletes)")
    }

    /// S7: an item that needs the password is skipped by the silent pass, and migrates at its first `load`, with one read.
    @Test func s7_anItemThatNeedsThePasswordMigratesAtItsFirstLoad() throws {
        let legacy = KSStore(.legacy), local = KSStore(.local), synced = KSStore(.synced), replaced = KSStore(.replaced)
        legacy.seed("gemini", "sk-test-legacy-gemini-g7h8", label: "AllInOneIME: Gemini API", modified: KS.t(100))
        legacy.needPassword(["gemini"])

        let result = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)
        #expect(result.waiting == ["gemini"])
        #expect(!result.moved.contains("gemini"))
        #expect(legacy.has("gemini") && legacy.deletes.isEmpty)
        #expect(!synced.has("gemini") && !local.has("gemini") && !replaced.has("gemini"))
        #expect(legacy.reads("gemini") == 0)  // the silent pass asked nothing

        let store = KS.routed(local: local, synced: synced, legacy: legacy, replaced: replaced, syncs: { true })
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
    /// (A11). A legacy key that loses to a different one is kept aside under the replaced service, and so is a synced
    /// key a newer legacy one overwrites (round 2, 2).
    @Test func s8_aDuplicateDuringMigrationTheNewerWins() throws {
        let log = KSLog()
        let legacy = KSStore(.legacy, log: log), local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
        let replaced = KSStore(.replaced, log: log)
        // Another Mac saved a newer openai key: it stays, and the older legacy one is put aside, not deleted.
        legacy.seed("openai", "sk-test-legacy-older-0001", label: KS.openAILabel, modified: KS.t(200))
        synced.seed("openai", "sk-test-synced-newer-0001", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
        // The legacy gemini key was saved after the synced one, though the synced item was restamped since (a copy or a
        // comment change): the legacy key wins.
        legacy.seed("gemini", "sk-test-legacy-newer-0001", label: "AllInOneIME: Gemini API", modified: KS.t(300))
        synced.seed("gemini", "sk-test-synced-older-0001", label: "AllInOneIME: Gemini API", modified: KS.t(400),
                    saved: KS.t(200))
        let into = KS.newStore(local: local, synced: synced, syncs: { true })

        let result = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)

        #expect(synced.value("openai") == "sk-test-synced-newer-0001")
        #expect(!result.moved.contains("openai"))
        #expect(replaced.value("openai") == "sk-test-legacy-older-0001", "a legacy key that lost isn't kept aside: \(log.all)")
        #expect(!legacy.has("openai"), "a legacy key that lost was left where routed reads and migrations find it")
        #expect(log.happened("replaced.read:openai", before: "legacy.delete:openai"),
                "the legacy key was deleted before its kept copy was read back: \(log.all)")
        #expect(synced.value("gemini") == "sk-test-legacy-newer-0001", "the modification date won over the save time")
        #expect(synced.saved("gemini") == KS.t(300))
        #expect(result.moved.contains("gemini"))
        #expect(!legacy.has("gemini"))
        #expect(replaced.value("gemini") == "sk-test-synced-older-0001", "the overwritten synced key is nowhere")
        #expect(into.read("openai") == "sk-test-synced-newer-0001" && into.read("gemini") == "sk-test-legacy-newer-0001")
    }

    /// S9: Remove Key… while syncing deletes the synced, local, legacy and replaced copies.
    @Test func s9_removeWhileSyncingDeletesEveryCopy() throws {
        let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy), replaced = KSStore(.replaced)
        synced.seed("openai", "sk-test-synced-openai-0001", modified: KS.t(300))
        local.seed("openai", "sk-test-local-openai-0001", modified: KS.t(200))
        legacy.seed("openai", "sk-test-legacy-openai-0001", modified: KS.t(100))
        replaced.seed("openai", "sk-test-replaced-openai-0001", modified: KS.t(50))
        synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(300))
        replaced.seed("gemini", "sk-test-replaced-gemini-0001", modified: KS.t(50))
        let store = KS.routed(local: local, synced: synced, legacy: legacy, replaced: replaced, syncs: { true })

        try APIKeys.remove(account: "openai", in: store)

        #expect(!synced.has("openai") && !local.has("openai") && !legacy.has("openai"))
        #expect(!replaced.has("openai"), "the key's replaced copy was left")
        #expect(!APIKeys.hasKeychainKey(account: "openai", in: store) && store.read("openai") == nil)
        #expect(synced.value("gemini") == "sk-test-synced-gemini-0001")  // only that key
        #expect(replaced.value("gemini") == "sk-test-replaced-gemini-0001")
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
    /// B's newer key wins; A's key is kept aside under the replaced service, never lost: on A when A migrates second, on
    /// B (the synced copy B overwrites) when A migrates first (round 2, 2).
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
            let replacedA = KSStore(.replaced, "replacedA", log: log), replacedB = KSStore(.replaced, "replacedB", log: log)
            // As 0.6.4 left them: no save time. A's is a year old, B's from last week.
            legacyA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
            legacyB.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200))
            let macA = KS.routed(local: localA, synced: synced, legacy: legacyA, replaced: replacedA, syncs: { true })
            let macB = KS.routed(local: localB, synced: synced, legacy: legacyB, replaced: replacedB, syncs: { true })
            func migrate(_ legacy: KSStore, _ local: KSStore, _ replaced: KSStore) throws -> Set<String> {
                try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced).moved
            }
            let order = aFirst ? "A first" : "B first"

            if aFirst {
                #expect(try migrate(legacyA, localA, replacedA).contains("openai"), "\(order)")
                // Mac A uses the key: binding its host is a comment change, which restamps the synced item.
                #expect(macA.setComment("openai", "api.openai.com") == .ok)
                #expect(try migrate(legacyB, localB, replacedB).contains("openai"), "\(order): B's newer key lost: \(log.all)")
                #expect(!legacyB.has("openai"), "\(order): B's key, moved, was left in its login keychain")
                // A's key, overwritten in iCloud Keychain, is kept aside on B.
                #expect(replacedB.value("openai") == "sk-test-macA-older-a111", "\(order): A's key is nowhere: \(log.all)")
            } else {
                #expect(try migrate(legacyB, localB, replacedB).contains("openai"), "\(order)")
                #expect(macB.setComment("openai", "api.openai.com") == .ok)
                #expect(try !migrate(legacyA, localA, replacedA).contains("openai"), "\(order): A's older key won: \(log.all)")
                // A's key differs from the winner: it is kept aside on A, not in its login keychain.
                #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "\(order): A's key is nowhere: \(log.all)")
                #expect(!legacyA.has("openai"), "\(order): A's losing key was left in its login keychain: \(log.all)")
            }

            #expect(synced.value("openai") == "sk-test-macB-newer-b222", "\(order): \(log.all)")
            #expect(synced.saved("openai") == KS.t(200), "\(order): the synced copy doesn't say when B's key was saved")
            #expect(synced.comment("openai") == "api.openai.com")
            #expect(APIKeys.keyEnding(account: "openai", in: macA) == "b222")
            // Both Macs use B's key.
            #expect(macA.read("openai") == "sk-test-macB-newer-b222" && macB.read("openai") == "sk-test-macB-newer-b222", "\(order)")
            #expect(!localA.has("openai") && !localB.has("openai"), "\(order)")
            if !aFirst { #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "\(order): a routed read took A's kept key") }
        }
    }

    /// S15: Remove Key… while this Mac doesn't sync keys deletes this Mac's local, legacy and replaced copies, and leaves
    /// the synced copy (the one other Macs use) alone.
    @Test func s15_removeWithKeySyncOffLeavesTheSyncedCopy() throws {
        var rowOff = ICloudSyncSettings(enabled: true)
        rowOff.keys = false
        for settings in [ICloudSyncSettings(), rowOff] {
            let local = KSStore(.local), synced = KSStore(.synced), legacy = KSStore(.legacy), replaced = KSStore(.replaced)
            synced.seed("openai", "sk-test-synced-openai-0001", modified: KS.t(300), saved: KS.t(300))
            local.seed("openai", "sk-test-local-openai-0001", modified: KS.t(200), saved: KS.t(200))
            legacy.seed("openai", "sk-test-legacy-openai-0001", modified: KS.t(100))
            replaced.seed("openai", "sk-test-replaced-openai-0001", modified: KS.t(50), saved: KS.t(50))
            local.seed("gemini", "sk-test-local-gemini-0001", modified: KS.t(200), saved: KS.t(200))
            replaced.seed("gemini", "sk-test-replaced-gemini-0001", modified: KS.t(50), saved: KS.t(50))
            let store = KS.routed(local: local, synced: synced, legacy: legacy, replaced: replaced, syncs: { settings.syncsKeys })

            try APIKeys.remove(account: "openai", in: store)

            let which = settings.enabled ? "keys row off" : "sync off"
            #expect(!local.has("openai") && !legacy.has("openai"), "\(which): this Mac's copies left")
            #expect(!replaced.has("openai"), "\(which): the key's replaced copy was left")
            #expect(synced.value("openai") == "sk-test-synced-openai-0001", "\(which): removed from all Macs")
            #expect(synced.deletes.isEmpty && synced.writes.isEmpty, "\(which): \(synced.deletes)")
            #expect(!APIKeys.hasKeychainKey(account: "openai", in: store) && store.read("openai") == nil, "\(which)")
            #expect(local.value("gemini") == "sk-test-local-gemini-0001")  // only that key
            #expect(replaced.value("gemini") == "sk-test-replaced-gemini-0001")
        }
    }

    /// S16: a copy that doesn't read back, into a store that already held the account, keeps that store's item: the
    /// clean-up deletes only a copy it just made in a store that didn't hold the account (spec change 3). The item it
    /// overwrote was kept aside first (round 2, 2).
    @Test func s16_aMismatchWhereTheStoreHeldTheAccountKeepsItsItem() throws {
        // Migration: the login keychain's key is newer than the synced one (another Mac's); its copy doesn't read back.
        do {
            let log = KSLog()
            let legacy = KSStore(.legacy, log: log), local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
            let replaced = KSStore(.replaced, log: log)
            synced.seed("openai", "sk-test-synced-other-mac-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            legacy.seed("openai", "sk-test-legacy-newer-0002", label: KS.openAILabel, modified: KS.t(300))
            synced.garble(["openai"])
            let result = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)
            #expect(!result.moved.contains("openai"))
            #expect(synced.has("openai") && synced.deletes.isEmpty, "the synced item other Macs use was deleted: \(log.all)")
            #expect(local.deletes.isEmpty, "the clean-up went through the routed store: \(log.all)")
            #expect(legacy.value("openai") == "sk-test-legacy-newer-0002" && legacy.deletes.isEmpty, "\(log.all)")
            #expect(replaced.value("openai") == "sk-test-synced-other-mac-0001", "the overwritten synced key is nowhere: \(log.all)")
        }
        // Turning sync on: this Mac's key is newer; its copy into the synced store doesn't read back.
        do {
            let log = KSLog()
            let local = KSStore(.local, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            local.seed("openai", "sk-test-local-newer-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            synced.seed("openai", "sk-test-synced-older-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            synced.garble(["openai"])
            _ = try KeySync.merge(from: local.keychain, into: synced.keychain, aside: replaced.keychain)
            #expect(synced.has("openai") && synced.deletes.isEmpty, "the synced item other Macs use was deleted: \(log.all)")
            #expect(local.value("openai") == "sk-test-local-newer-0002", "this Mac's key was lost: \(log.all)")
            #expect(replaced.value("openai") == "sk-test-synced-older-0001", "the overwritten synced key is nowhere: \(log.all)")
        }
        // Turning sync off: the synced key is newer; its copy into this Mac's store, which held one, doesn't read back.
        do {
            let log = KSLog()
            let local = KSStore(.local, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", "sk-test-synced-newer-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            local.seed("openai", "sk-test-local-older-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            local.garble(["openai"])
            _ = try KeySync.merge(from: synced.keychain, into: local.keychain, aside: replaced.keychain)
            #expect(local.has("openai") && local.deletes.isEmpty, "this Mac's item was deleted: \(log.all)")
            #expect(synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
            #expect(synced.value("openai") == "sk-test-synced-newer-0002")
            #expect(replaced.value("openai") == "sk-test-local-older-0001", "the overwritten local key is nowhere: \(log.all)")
        }
    }

    /// S17 (review case A): a loser kept aside never comes back after "remove from all your Macs", neither at its next
    /// use (the routed store's lazy migration) nor at the next launch's silent pass. One that can't be read silently
    /// stays in the login keychain, and the silent pass doesn't bring it back either (only a password prompt could).
    @Test func s17_aKeptLoserNeverComesBackAfterRemoveFromAllMacs() throws {
        #expect(KeySync.replacedService == "AllInOneIME replaced API key")
        #expect(KeySync.replacedService != APIKeys.service)

        let log = KSLog()
        let synced = KSStore(.synced, log: log)  // iCloud Keychain, both Macs'
        let legacyA = KSStore(.legacy, "legacyA", log: log), localA = KSStore(.local, "localA", log: log)
        let replacedA = KSStore(.replaced, "replacedA", log: log)
        let localB = KSStore(.local, "localB", log: log), replacedB = KSStore(.replaced, "replacedB", log: log)
        // Mac B synced newer keys first.
        synced.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300),
                    saved: KS.t(300))
        synced.seed("gemini", "sk-test-macB-newer-g222", label: "AllInOneIME: Gemini API", modified: KS.t(300), saved: KS.t(300))
        // Mac A's 0.6.4 keys are older: openai reads silently, gemini asks for the password.
        legacyA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        legacyA.seed("gemini", "sk-test-macA-older-g111", label: "AllInOneIME: Gemini API", modified: KS.t(100))
        legacyA.needPassword(["gemini"])
        let macA = KS.routed(local: localA, synced: synced, legacy: legacyA, replaced: replacedA, syncs: { true })
        let macB = KS.routed(local: localB, synced: synced, legacy: KSStore(.legacy, "legacyB", log: log), replaced: replacedB,
                             syncs: { true })

        // A's silent pass: the readable loser is put aside (copied, read back, then deleted from the login keychain);
        // the one that would ask stays where it is.
        let first = try KS.silentPass(legacyA, local: localA, synced: synced, replaced: replacedA)
        #expect(!first.moved.contains("openai") && !first.moved.contains("gemini"), "\(first)")
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "A's losing key isn't kept aside: \(log.all)")
        #expect(!legacyA.has("openai"), "A's losing key was left in its login keychain: \(log.all)")
        #expect(log.happened("replacedA.write:openai", before: "legacyA.delete:openai")
                && log.happened("replacedA.read:openai", before: "legacyA.delete:openai"),
                "the login keychain's item was deleted before its kept copy was read back: \(log.all)")
        #expect(legacyA.value("gemini") == "sk-test-macA-older-g111" && legacyA.reads("gemini") == 0)
        #expect(!replacedA.has("gemini"))
        #expect(synced.value("openai") == "sk-test-macB-newer-b222" && synced.value("gemini") == "sk-test-macB-newer-g222")
        #expect(synced.writes.isEmpty, "\(log.all)")
        #expect(macA.read("openai") == "sk-test-macB-newer-b222")

        // On Mac B: Remove… from all your Macs.
        try APIKeys.remove(account: "openai", in: macB)
        try APIKeys.remove(account: "gemini", in: macB)
        #expect(!synced.has("openai") && !synced.has("gemini"))
        let removed = log.all.count

        // Mac A's next use of the key: there is none.
        #expect(macA.read("openai") == nil, "a kept loser came back: \(log.all)")
        #expect(KS.with(macA) { APIKeys.keychainKey(account: "openai") } == nil)
        #expect(!APIKeys.hasKeychainKey(account: "openai", in: macA) && APIKeys.keyEnding(account: "openai", in: macA) == nil)
        #expect(!macA.accounts().contains("openai"), "\(macA.accounts())")
        // Mac A's next launch: the silent pass brings back neither.
        let second = try KS.silentPass(legacyA, local: localA, synced: synced, replaced: replacedA)
        #expect(!second.moved.contains("openai") && !second.moved.contains("gemini"), "\(second)")
        #expect(!synced.has("openai") && !synced.has("gemini"), "a kept loser went back to iCloud Keychain: \(log.all)")
        #expect(!localA.has("openai") && !localA.has("gemini"))
        #expect(!log.all.dropFirst(removed).contains(where: { $0.hasPrefix("synced.write:") }), "\(log.all)")
        #expect(legacyA.reads("gemini") == 0, "the silent pass asked for the password")
        #expect(macA.read("openai") == nil)
        // The safety copy is still there, on A alone.
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111")

        // Remove… on Mac A takes this Mac's kept copy too.
        try APIKeys.remove(account: "openai", in: macA)
        #expect(!replacedA.has("openai"), "Remove… left the key's replaced copy")
    }

    /// S18 (review case B): a local key that lost when sync was turned on, kept aside, never returns to iCloud Keychain
    /// when sync is turned off and on again after another Mac removed the key from all Macs.
    @Test func s18_aLoserKeptByTurningOnNeverReturnsWhenTurnedOffAndOn() throws {
        let log = KSLog()
        let synced = KSStore(.synced, log: log)
        let localA = KSStore(.local, "localA", log: log), legacyA = KSStore(.legacy, "legacyA", log: log)
        let replacedA = KSStore(.replaced, "replacedA", log: log)
        synced.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
        localA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, modified: KS.t(400), saved: KS.t(100))
        let macB = KS.routed(local: KSStore(.local, "localB", log: log), synced: synced, legacy: KSStore(.legacy, "legacyB", log: log),
                             syncs: { true })

        // Mac A turns sync on: B's key wins, A's is put aside.
        _ = try KeySync.merge(from: localA.keychain, into: synced.keychain, aside: replacedA.keychain)
        #expect(synced.value("openai") == "sk-test-macB-newer-b222")
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "A's losing key isn't kept aside: \(log.all)")
        #expect(!localA.has("openai"), "A's losing key was left where routed reads and merges find it: \(log.all)")

        // Mac B removes the key from all Macs.
        try APIKeys.remove(account: "openai", in: macB)
        #expect(!synced.has("openai"))
        let removed = log.all.count

        // Mac A turns sync off, then on again.
        _ = try KeySync.merge(from: synced.keychain, into: localA.keychain, aside: replacedA.keychain)
        #expect(!localA.has("openai"), "\(log.all)")
        _ = try KeySync.merge(from: localA.keychain, into: synced.keychain, aside: replacedA.keychain)
        #expect(!synced.has("openai"), "a kept loser went back to iCloud Keychain: \(log.all)")
        #expect(!log.all.dropFirst(removed).contains(where: { $0.hasPrefix("synced.write:") }), "\(log.all)")
        for syncing in [true, false] {
            let macA = KS.routed(local: localA, synced: synced, legacy: legacyA, replaced: replacedA, syncs: { syncing })
            #expect(macA.read("openai") == nil && !APIKeys.hasKeychainKey(account: "openai", in: macA), "syncing \(syncing)")
        }
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111")
    }

    /// S19 (review case C): a 0.6.4 item without a save time, whose modification date changes later (0.6.4 after a
    /// downgrade, a development build or the CLI binding a host), never overwrites a newer synced key; the synced key
    /// survives.
    @Test func s19_aRestampedOldItemNeverOverwritesANewerSyncedKey() throws {
        let newer = "sk-test-synced-newer-b222", older = "sk-test-legacy-older-a111"
        // It reads silently: the first pass puts it aside, so nothing is left for 0.6.4 to restamp; and a kept copy whose
        // modification date changes is never compared.
        do {
            let log = KSLog()
            let legacy = KSStore(.legacy, log: log), local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
            let replaced = KSStore(.replaced, log: log)
            synced.seed("openai", newer, label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
            legacy.seed("openai", older, label: KS.openAILabel, modified: KS.t(100))  // no host bound yet
            _ = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)
            #expect(!legacy.has("openai"), "the losing key was left for 0.6.4 to restamp: \(log.all)")
            legacy.touch("openai", comment: "api.openai.com", modified: Date())
            replaced.touch("openai", comment: "api.openai.com", modified: Date())
            _ = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)
            _ = try KeySync.merge(from: local.keychain, into: synced.keychain, aside: replaced.keychain)
            let store = KS.routed(local: local, synced: synced, legacy: legacy, replaced: replaced, syncs: { true })
            #expect(store.read("openai") == newer, "\(log.all)")
            #expect(synced.value("openai") == newer && synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
        }
        // It asks for the password: it stays in the login keychain, where 0.6.4 restamps it. The silent pass can't read
        // it, and reads find the synced key first: it doesn't come back.
        do {
            let log = KSLog()
            let legacy = KSStore(.legacy, log: log), local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
            let replaced = KSStore(.replaced, log: log)
            synced.seed("openai", newer, label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
            legacy.seed("openai", older, label: KS.openAILabel, modified: KS.t(100))
            legacy.needPassword(["openai"])
            _ = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)
            #expect(legacy.value("openai") == older, "a key that can't be read silently was lost: \(log.all)")
            legacy.touch("openai", comment: "api.openai.com", modified: Date())
            _ = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)
            let store = KS.routed(local: local, synced: synced, legacy: legacy, replaced: replaced, syncs: { true })
            #expect(store.read("openai") == newer, "\(log.all)")
            #expect(KS.with(store) { APIKeys.keychainKey(account: "openai") } == newer)
            #expect(synced.value("openai") == newer && synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
            #expect(legacy.reads("openai") == 0, "the password was asked for: \(log.all)")
            #expect(legacy.value("openai") == older)
        }
        // It asked once in 0.6.4 and the user allowed it always, so it now reads silently, restamped: whichever wins,
        // neither key is lost (the synced one kept aside before being overwritten).
        do {
            let log = KSLog()
            let legacy = KSStore(.legacy, log: log), local = KSStore(.local, log: log), synced = KSStore(.synced, log: log)
            let replaced = KSStore(.replaced, log: log)
            synced.seed("openai", newer, label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
            legacy.seed("openai", older, label: KS.openAILabel, host: "api.openai.com", modified: Date())
            _ = try KS.silentPass(legacy, local: local, synced: synced, replaced: replaced)
            let kept = [synced, local, legacy, replaced].compactMap { $0.value("openai") }
            #expect(kept.contains(newer), "the newer synced key is nowhere: \(log.all)")
            #expect(kept.contains(older), "the login keychain's key is nowhere: \(log.all)")
        }
    }

    /// S20 (review case D): an older Mac migrates first; the newer Mac's migration overwrites its key in iCloud Keychain,
    /// and that overwritten value is kept aside (on the Mac that overwrote it) before the write, not lost.
    @Test func s20_anOlderMacMigratingFirstItsOverwrittenSyncedValueIsKeptAside() throws {
        let log = KSLog()
        let synced = KSStore(.synced, log: log)
        let legacyA = KSStore(.legacy, "legacyA", log: log), localA = KSStore(.local, "localA", log: log)
        let replacedA = KSStore(.replaced, "replacedA", log: log)
        let legacyB = KSStore(.legacy, "legacyB", log: log), localB = KSStore(.local, "localB", log: log)
        let replacedB = KSStore(.replaced, "replacedB", log: log)
        legacyA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        legacyB.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200))

        #expect(try KS.silentPass(legacyA, local: localA, synced: synced, replaced: replacedA).moved.contains("openai"))
        #expect(synced.value("openai") == "sk-test-macA-older-a111")
        let aMoved = log.all.count
        #expect(try KS.silentPass(legacyB, local: localB, synced: synced, replaced: replacedB).moved.contains("openai"))

        #expect(synced.value("openai") == "sk-test-macB-newer-b222", "\(log.all)")
        #expect(replacedB.value("openai") == "sk-test-macA-older-a111", "A's key, overwritten in iCloud Keychain, is nowhere: \(log.all)")
        let afterA = log.all.dropFirst(aMoved)
        let aside = afterA.firstIndex(of: "replacedB.write:openai"), overwritten = afterA.lastIndex(of: "synced.write:openai")
        let asideFirst = aside.flatMap { a in overwritten.map { a < $0 } } ?? false
        #expect(asideFirst, "not kept aside before it was overwritten: \(log.all)")
        #expect(!legacyA.has("openai") && !legacyB.has("openai"))
        #expect(!replacedA.has("openai"))
    }

    /// S21 (review case E): turning key sync on is interrupted (a copy doesn't read back), then key sync is turned off:
    /// every key that had moved is readable on this Mac again.
    ///
    /// The core half, through `KeySync.Stores` (A15). The controller half (`ICloudSyncController.applyKeySync` and its
    /// `keys-synced` marker beside the sync record) lives in the app and can't be driven here; it is a self-test case
    /// for the implementer, on in-memory stores and the self-test's own state directory:
    ///   1. Key sync off, no marker. Turn it on with one account garbled in the synced store. The marker exists before
    ///      the first key moves (watch for it from the synced store's write closure) with the content `moving`; after
    ///      the incomplete turn it is still `moving`, never `done`.
    ///   2. Turn key sync off in the config and apply. Because the marker exists (`moving` or `done`), the copy-back
    ///      (`turn(syncing: false)`) runs even though the last turn on never completed. Every key that moved is in the
    ///      local store; the marker is removed once the copy-back completes, and kept (to retry) when it doesn't.
    ///   3. Turn it on again with nothing garbled: the marker goes `moving`, then `done` when the turn completes.
    ///   4. With the marker `moving` at launch and key sync on in the config, the turn on is retried.
    @Test func s21_anInterruptedTurnOnThenOffLeavesEveryMovedKeyReadableHere() throws {
        let log = KSLog()
        let local = KSStore(.local, log: log), synced = KSStore(.synced, log: log), legacy = KSStore(.legacy, log: log)
        let replaced = KSStore(.replaced, log: log)
        let keys = ["openai": "sk-test-local-openai-0001", "gemini": "sk-test-local-gemini-0001",
                    "anthropic": "sk-test-local-anthropic-0001"]
        for (account, key) in keys { local.seed(account, key, modified: KS.t(100), saved: KS.t(100)) }
        local.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))
        synced.garble(["gemini"])
        let stores = KeySync.Stores(local: local.keychain, synced: synced.keychain, legacy: legacy.keychain,
                                    replaced: replaced.keychain, syncing: false)

        let on = try stores.turn(syncing: true)
        #expect(!on.isComplete, "a copy that didn't read back counted as moved: \(log.all)")
        #expect(stores.syncing)
        #expect(synced.value("openai") == keys["openai"] && !local.has("openai"), "\(log.all)")
        #expect(local.value("gemini") == keys["gemini"], "the key whose copy didn't read back was lost: \(log.all)")
        for (account, key) in keys { #expect(stores.store.read(account) == key, "\(account) unreadable while on: \(log.all)") }
        let syncedDeletes = synced.deletes.count, syncedWrites = synced.writes.count

        // Interrupted: the user turns key sync off.
        _ = try stores.turn(syncing: false)
        #expect(!stores.syncing)
        for (account, key) in keys {
            #expect(local.value(account) == key, "\(account) isn't on this Mac again: \(log.all)")
            #expect(stores.store.read(account) == key, "\(account) unreadable once sync is off: \(log.all)")
            #expect(KS.with(stores.store) { APIKeys.hasKeychainKey(account: account) }, "\(account)")
        }
        #expect(stores.store.read("hosted") == "token-test-hosted-0001")
        // Turning off left iCloud Keychain as it was, for the other Macs.
        #expect(synced.deletes.count == syncedDeletes && synced.writes.count == syncedWrites, "\(log.all)")
        #expect(synced.value("openai") == keys["openai"] && synced.value("anthropic") == keys["anthropic"])
    }
}
