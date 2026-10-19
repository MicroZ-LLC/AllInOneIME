import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for API key sync through iCloud Keychain (spec-key-sync.md, "Spec D", scenarios S1-S29, with its
// "Spec changes (2026-10-18, after review)", "Spec changes, round 2", "Spec changes, round 3" and "Spec changes, round
// 4"), written from the spec
// by an independent reviewer; the implementer may not edit them. Each test is named after its scenario.
//
// Round 3's model: with key sync off, keys stay in the login keychain, as in 0.6.4; only turning key sync on moves them,
// from the login keychain into the synced store (the data protection keychain is used for synced items alone); turning
// it off copies them back. There is no local data protection store for keys. Replaced copies live in the login keychain
// under their own service.
//
// Nothing here touches the user's keychain: every store is an in-memory one (`APIKeys.Keychain.inMemory()`), wrapped by
// `KSStore` so that a test can see what was looked at, read, written and deleted, set an item's modification date and
// save time, change its modification date later (`touch`, as a 0.6.4 `setComment` does), make an item "need the
// password" or unreadable, garble a read-back, make a store fail with a given status (every change, or its deletes alone),
// or deliver another Mac's change while a read waits for the password (`whileAsking`). The global key cache is reached
// only through `Platform.$override`, with no processes (so no login shell is asked for variables).
//
// ASSUMPTIONS (where the spec names an API but not its exact shape; the implementer should match these):
//  A1. `APIKeys.Keychain` has a `kind` that is a settable stored property, of a nested enum with at least `.legacy` (the
//      login keychain), `.synced` and `.memory`. `inMemory()` has `.memory`; `.login` has `.legacy`. The tests copy an
//      in-memory store, replace its closures and set its `kind`, as `KSStore` does: the login keychain and the replaced
//      store (A11) are `.legacy`, the synced store `.synced`.
//  A2. `APIKeys.Keychain.processIsEntitled` is a static Bool (Apple platforms only); it is false in the test process,
//      which has no keychain-access-groups entitlement. `Platform.systemSecrets` stays `.login` there.
//  A3. `APIKeys.Keychain.routed(login:synced:replaced:syncs:)` is a static func returning a Keychain; `syncs` is an
//      `@escaping @Sendable () -> Bool` asked on every call (the switch can change while the store, chosen once at launch,
//      stays). `replaced` is the replaced store (A11); `accounts`, `attributes` and reads never look at it.
//      - While `syncs()` is false, every call (`accounts`, `attributes`, `read`, `write`, `setComment`, `delete`) goes to
//        the login keychain and never touches the synced store, not even its attributes (round 3, 1; S25). `delete`
//        also removes the account's replaced copy, and never the synced one (spec change 2, S15).
//      - While true, `attributes` and reads try synced, then the login keychain, except for `APIKeys.neverSynced`
//        accounts, which use the login keychain alone. Writes go to synced, except `neverSynced` accounts (the login
//        keychain). A read that finds the key only in the login keychain moves it into synced as A5 moves one (copied,
//        read back, also kept as a replaced copy, then deleted from the login keychain): the login keychain is read
//        once. `delete` removes the login, replaced and synced copies (S9).
//  A4. `APIKeys.neverSynced` is a collection of account names (Set or Array) that contains "hosted".
//  A5. `KeySync.merge(from:into:aside:)` (may throw) returns a value with `moved` and `waiting`, each a collection of
//      account names (Array or Set), and `isComplete`. It takes every item of `from` into `into`, the newest per account
//      winning (A10, A15), and skips `neverSynced` accounts. Turning key sync on, and the silent pass at launch while key
//      sync is on, is `merge(from: login, into: synced, aside: replaced)` (the silent pass with asking turned off: the
//      fake login keychain's `interactionAllowed` stands in for `SecKeychainSetUserInteractionAllowed`); turning it off
//      is `merge(from: synced, into: login, aside: replaced)`. The tests don't call `KeySync.migrate`.
//      - An item of `from` whose read gives nothing (it would ask for the password) is `waiting`.
//      - Items copied are deleted from `from` once the copy reads back, unless `from.kind == .synced`: a merge never
//        deletes synced items (Decision 10).
//      - An item of `from` that loses to a different key in `into` isn't `moved`: it is copied into `aside`, read back,
//        then deleted from `from` (unless synced); one that can't be read silently stays where it is (round 2, 2).
//      - An item of `into` whose different key is about to be overwritten is first copied into `aside` (S20).
//      - Round 3, 3: a key moved into a synced store that had no item for its account is also copied into `aside`, and
//        read back, before it is deleted from `from`. This holds on a retry too, when an earlier, incomplete attempt
//        already left the same key in the synced store (S23).
//      - Round 3, 4: the result is not `isComplete` (or merge throws; the tests take either) when a set-aside fails
//        (S23), when an `into` item whose attributes exist can't be read (it is never overwritten, S24), and when a copy
//        doesn't read back (S6, S16, S21). Calling merge again retries what was left.
//  A6. Copies keep the label, comment (host) and ending: the tests check the label passed to the store's `write`, so
//      merges need the item's label from its attributes (`ItemAttributes.label`, which `inMemory()` and `.login` fill).
//      A copy into the replaced store has " (replaced)" added to its label (round 3, 2). `KSStore` keeps every field
//      `inMemory()` returns and replaces only `modified` and `saved` (A10).
//  A7. `ICloudSyncSettings.keys` is a `var` defaulting to true, encoded only when false; `syncsKeys` is `enabled && keys`.
//  A8. "the mismatch logged" (S6) is not checked: the core's log has no test seam.
//  A9. S13 is checked through `APIKeys.save` (the closures' reads return no status): a write that fails with -25308 or
//      -34018 throws `APIKeys.KeychainError` with that status, and nothing is written to the other store.
//  A10. The save time. `APIKeys.ItemAttributes.saved: Date?` is when the key was saved (nil: the item doesn't say, as for
//      every item 0.6.4 left). `APIKeys.Keychain.write`'s sixth, last parameter `_ saved: Date?` (nil: left as it is)
//      is stored with the item, carried by copies and returned by `attributes`. `APIKeys.save` passes the current time.
//      Every copy (merges, the routed store's first-use move, a copy into the replaced store) passes the source item's
//      `saved ?? modified`, and "newest" compares each item's `saved ?? modified`. In the fake, `seed(saved:)` sets it,
//      a `write` with a non-nil `saved` sets it, `setComment` and `touch` leave it, `delete` drops it. `seed(modified:)`
//      and `touch(modified:)` set the modification date; any write or comment change through the store resets it to the
//      current time, later than every `KS.t(_)` date, so comparing by modification date where a save time exists picks
//      the wrong winner.
//  A11. The replaced store. `KeySync.replacedService` is "AllInOneIME replaced API key"; on the Mac it is the login
//      keychain under that service (round 3, 2). In the core it is an ordinary `APIKeys.Keychain` passed explicitly
//      (`replaced:` to `routed` and `Stores`, `aside:` to `merge`), one item per account (no test has two losers of one
//      account on one Mac). It is only a safety copy: nothing moves out of it, and only the read-back of a copy just
//      written may read it.
//  A12. `KSStore.garble(_:)`: a read of a garbled account gives something else than was written, but only once the code
//      under test wrote that account in that store (a seeded item reads back fine). `KSStore.unreadable(_:)`: reads of
//      those accounts give nothing while their attributes stay (an item not arrived yet, or one that can't be read).
//  A13. `KSStore.touch(_:comment:modified:)` changes an existing item's modification date (and comment) without going
//      through its closures and without changing its save time, as 0.6.4 (a downgrade), a development build or
//      `allinoneime-cli` binding a host does. On a missing item it does nothing.
//  A14. `KeySync.Stores` is `init(login:synced:replaced:quietLogin:syncing:)`, `quietLogin` optional; `turn(syncing:)`
//      passes the stores to `merge` and returns its result; `store` is `routed` over them, following `syncing`. The
//      controller half (the `keys-synced` marker) is a self-test case for the implementer, described at S21.
//  A15. Clock skew (round 3, 5): when comparing, a save time later than now + 1 day counts as the oldest possible;
//      one within a day ahead counts as itself.
//  A16. Where the items live on the Mac (the login keychain, the data protection keychain's synced items, their
//      accessibility) is the Apple layer's and not checked here; so is round 4, 3's "a move into an empty slot only adds,
//      never updates" (SecItemAdd alone: the in-memory stores' `write` always updates).
//  A17. Round 4, 1: a key is never set aside over its own replaced copy. When `from`'s key is the same as `into`'s and
//      `aside` already holds a copy for the account, merge sets nothing aside (it deletes `from`'s copy, unless synced);
//      a move into an empty synced slot still keeps one (S22). "Copying back into the login keychain sets nothing aside"
//      is read as: the key copied back is never set aside (the login keychain had none, or the same key). A different
//      login key about to be overwritten by the copy-back is still kept aside first, as S16 and S24 have it. A login
//      keychain delete that fails after a copy doesn't lose the replaced copy at the next pass (S27).
//  A18. Round 4, 2: `KeySync.Stores.turn(syncing:only:)`, `only: Set<String>?` defaulting to nil (every account): the
//      merge handles only the accounts named, and looks at no other account's key. The accounts left after an
//      incomplete move are its result's `waiting` and `mismatched`; the controller writes them into the marker (names
//      only), takes an account off when Remove… runs on this Mac with key sync off, and retries with `only:` (S28).
//  A19. Round 4, 3: the routed store's first-use move checks the synced store's attributes again after reading the login
//      keychain (which may have asked for the password, for seconds or minutes); when an item arrived meanwhile it writes
//      nothing into the synced store and deletes nothing from the login keychain, leaving both to the next merge. What
//      that read gives (the login keychain's key, or the one that arrived) isn't checked (S29).
//  A20. Round 4, 4 (config.json can't be read: key sync does nothing) is the controller's, a self-test case at S28.

// MARK: - The rig

enum KS {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    static func t(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    static let openAILabel = "AllInOneIME: OpenAI-compatible API"
    static func replacedLabel(_ label: String) -> String { label + " (replaced)" }

    /// Runs `body` with `store` as the platform's secret store and no processes (no login shell is read).
    static func with<T>(_ store: APIKeys.Keychain, _ body: () throws -> T) rethrows -> T {
        var platform = Platform.current
        platform.secrets = store
        platform.processes = NoProcessLauncher()
        return try Platform.$override.withValue(platform) { try body() }
    }

    /// The routed store over the fakes (A3); a test that doesn't look at the replaced store gets an empty one.
    static func routed(login: KSStore, synced: KSStore, replaced: KSStore = KSStore(.replaced),
                       syncs: @escaping @Sendable () -> Bool) -> APIKeys.Keychain {
        .routed(login: login.keychain, synced: synced.keychain, replaced: replaced.keychain, syncs: syncs)
    }

    typealias Result = (moved: Set<String>, waiting: Set<String>, complete: Bool)

    /// Turning key sync on: the login keychain's items into the synced store, losers into `replaced` (A5).
    static func turnOn(_ login: KSStore, synced: KSStore, replaced: KSStore) throws -> Result {
        let moves = try KeySync.merge(from: login.keychain, into: synced.keychain, aside: replaced.keychain)
        return (Set(moves.moved), Set(moves.waiting), moves.isComplete)
    }

    /// The silent pass at launch while key sync is on: turning on with asking turned off.
    static func silentPass(_ login: KSStore, synced: KSStore, replaced: KSStore) throws -> Result {
        login.interactionAllowed = false
        defer { login.interactionAllowed = true }
        return try turnOn(login, synced: synced, replaced: replaced)
    }

    /// Turning key sync off: the synced items copied into the login keychain (A5).
    static func turnOff(_ synced: KSStore, into login: KSStore, replaced: KSStore) throws -> Result {
        let moves = try KeySync.merge(from: synced.keychain, into: login.keychain, aside: replaced.keychain)
        return (Set(moves.moved), Set(moves.waiting), moves.isComplete)
    }

    /// Whether a move completed: an error counts as incomplete (A5).
    static func completes(_ body: () throws -> Result) -> Bool { (try? body())?.complete ?? false }

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

/// What the fakes did, in order, across stores: "synced.read:openai", "login.delete:openai", "synced.attributes:openai", …
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

/// An in-memory store that records what is done to it (A1, A6, A10, A12, A13).
final class KSStore: @unchecked Sendable {
    enum Role { case login, synced, replaced }
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
    private var unreadableAccounts: Set<String> = []
    private var interaction = true
    private var garbledAccounts: Set<String> = []
    private var garbledWritten: Set<String> = []
    private var failingStatus: Int32?
    private var failingDeleteStatus: Int32?
    private var askingActions: [String: () -> Void] = [:]

    init(_ role: Role, _ name: String? = nil, log: KSLog = KSLog()) {
        self.role = role
        self.name = name ?? "\(role)"
        self.log = log
    }

    // Set-up.

    /// An item already there, last changed at `modified` (as another Mac or an earlier version left it), saved at
    /// `saved` (nil: it doesn't say when, as 0.6.4's items don't). `modified` may be later than `saved`: a copy or a
    /// comment change since (A10).
    func seed(_ account: String, _ key: String, label: String = "AllInOneIME: test", host: String = "", modified: Date,
              saved: Date? = nil) {
        _ = inner.write(account, key, label, host, APIKeys.ending(of: key), saved)
        lock.withLock {
            dates[account] = modified
            savedTimes[account] = saved
        }
    }

    /// Another program changed the item since (0.6.4 binding a host with `setComment`): its modification date is now
    /// `modified`, its save time as it was (A13). Nothing there: nothing happens.
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
    /// Reading these gives nothing, though their attributes are there (A12).
    func unreadable(_ accounts: Set<String>) { lock.withLock { unreadableAccounts = accounts } }
    /// A read-back of these, once written through this store, gives something else than was written (A12).
    func garble(_ accounts: Set<String>) { lock.withLock { garbledAccounts = accounts } }
    /// Every write, comment change and delete fails with `status` (nil: none fails).
    func fail(with status: Int32?) { lock.withLock { failingStatus = status } }
    /// Deletes alone fail with `status` (nil: none fails): a removal the login keychain refused, or one cancelled at its
    /// password prompt. Writes and comment changes work.
    func failDeletes(with status: Int32?) { lock.withLock { failingDeleteStatus = status } }
    /// While a read of `account` waits for the password (it needs it, and asking is allowed), `action` runs, once,
    /// before the read gives the key: another Mac's change arriving while the prompt is up.
    func whileAsking(_ account: String, _ action: @escaping () -> Void) { lock.withLock { askingActions[account] = action } }

    // What is there, and what was done (bypassing the counters).

    func value(_ account: String) -> String? { inner.read(account) }
    func has(_ account: String) -> Bool { inner.attributes(account) != nil }
    func comment(_ account: String) -> String? { inner.attributes(account)?.comment }
    func modified(_ account: String) -> Date? { attributes(account)?.modified }
    func saved(_ account: String) -> Date? { attributes(account)?.saved }
    var writes: [Write] { lock.withLock { recordedWrites } }
    func lastWrite(_ account: String) -> Write? { writes.last { $0.account == account } }
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
        store.accounts = { [self] in
            log.add("\(name).accounts")
            return inner.accounts()
        }
        store.attributes = { [self] account in
            log.add("\(name).attributes:\(account)")
            return attributes(account)
        }
        store.read = { [self] account in
            log.add("\(name).read:\(account)")
            guard inner.attributes(account) != nil else { return nil }
            let (needs, allowed, unreadable, garbled) = lock.withLock {
                (passwordAccounts.contains(account), interaction, unreadableAccounts.contains(account),
                 garbledWritten.contains(account))
            }
            if unreadable || (needs && !allowed) { return nil }
            if needs, let action = lock.withLock({ askingActions.removeValue(forKey: account) }) { action() }
            lock.withLock { promptingReads[account, default: 0] += 1 }
            return garbled ? "garbled-read-back" : inner.read(account)
        }
        store.write = { [self] account, key, label, comment, ending, saved in
            log.add("\(name).write:\(account)")
            if let status = lock.withLock({ failingStatus }) { return .failed(status) }
            lock.withLock {
                recordedWrites.append(Write(account: account, key: key, label: label, comment: comment, ending: ending))
                if let saved { savedTimes[account] = saved }  // nil: left as it is (A10)
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
            if let status = lock.withLock({ failingStatus ?? failingDeleteStatus }) { return .failed(status) }
            lock.withLock {
                recordedDeletes.append(account)
                savedTimes[account] = nil
                garbledWritten.remove(account)
            }
            changed(account)
            return inner.delete(account)
        }
        switch role {
        case .login, .replaced: store.kind = .legacy
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

    /// S2: key sync off (the main switch off, or the keys row off): saves and reads use the login keychain, as in 0.6.4
    /// (round 3, 1); a key left in iCloud Keychain isn't seen.
    @Test func s2_syncOffSavesAndReadsUseTheLoginKeychain() throws {
        #expect(ICloudSyncSettings().syncsKeys == false)  // sync is off by default
        var rowOff = ICloudSyncSettings(enabled: true)
        rowOff.keys = false
        #expect(rowOff.syncsKeys == false)

        for settings in [ICloudSyncSettings(), rowOff] {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log)
            // Left behind in iCloud Keychain when sync was turned off (and changed since on another Mac).
            synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(500), saved: KS.t(500))
            let store = KS.routed(login: login, synced: synced, syncs: { settings.syncsKeys })

            #expect(store.read("gemini") == nil && !APIKeys.hasKeychainKey(account: "gemini", in: store),
                    "a read while key sync is off used the synced store")

            try APIKeys.save("sk-test-login-openai-0001", account: "openai", label: KS.openAILabel, in: store)
            #expect(login.value("openai") == "sk-test-login-openai-0001")
            #expect(login.lastWrite("openai")?.label == KS.openAILabel)
            #expect(!synced.has("openai"))
            #expect(store.read("openai") == "sk-test-login-openai-0001")

            try APIKeys.save("token-test-hosted-0001", account: "hosted", label: "AllInOneIME: AllInOneIME Cloud", in: store)
            #expect(login.value("hosted") == "token-test-hosted-0001" && !synced.has("hosted"))

            try APIKeys.save("sk-test-login-gemini-0001", account: "gemini", label: "AllInOneIME: Gemini API", in: store)
            #expect(login.value("gemini") == "sk-test-login-gemini-0001")
            #expect(store.read("gemini") == "sk-test-login-gemini-0001", "a read while key sync is off used the synced store")
            #expect(synced.value("gemini") == "sk-test-synced-gemini-0001" && synced.writes.isEmpty && synced.deletes.isEmpty)
        }
    }

    /// S3: key sync on: `openai` goes to the synced store; `hosted` (never synced) stays in the login keychain.
    @Test func s3_syncOnOpenAIGoesToSyncedHostedToTheLoginKeychain() throws {
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

        let login = KSStore(.login), synced = KSStore(.synced), replaced = KSStore(.replaced)
        let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { on.syncsKeys })
        try APIKeys.save("sk-test-synced-openai-0001", account: "openai", label: KS.openAILabel, in: store)
        #expect(synced.value("openai") == "sk-test-synced-openai-0001")
        #expect(!login.has("openai") && !replaced.has("openai"))
        #expect(store.read("openai") == "sk-test-synced-openai-0001")

        try APIKeys.save("token-test-hosted-0001", account: "hosted", label: "AllInOneIME: AllInOneIME Cloud", in: store)
        #expect(login.value("hosted") == "token-test-hosted-0001")
        #expect(!synced.has("hosted") && !replaced.has("hosted"))
        #expect(store.read("hosted") == "token-test-hosted-0001")
    }

    /// S4: turning key sync on moves the login keychain's items into the synced store, newest winning by the time each
    /// key was saved (A10, A15), and removes the login copies it moved. Every key that leaves the login keychain, or is
    /// overwritten in the synced store, without being the one that stays there is kept as a replaced copy (round 2, 2);
    /// so is a key moved into a synced store that had none for its account (round 3, 3).
    @Test func s4_turningOnNewestWinsAndTheLoginCopyIsRemoved() throws {
        let login = KSStore(.login), synced = KSStore(.synced), replaced = KSStore(.replaced)
        // Saved later here than the synced one, though another Mac's comment change restamped the synced item since:
        // this Mac's value wins, and the synced one is kept aside.
        login.seed("openai", "sk-test-login-newer-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200),
                   saved: KS.t(200))
        synced.seed("openai", "sk-test-synced-older-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300),
                    saved: KS.t(100))
        // Saved earlier here, though a host bound here since restamped it: the synced value is kept, this one put aside.
        login.seed("gemini", "sk-test-login-older-0001", host: "generativelanguage.googleapis.com", modified: KS.t(500),
                   saved: KS.t(100))
        synced.seed("gemini", "sk-test-synced-newer-0001", modified: KS.t(200), saved: KS.t(200))
        // Neither says when it was saved: the modification dates decide, and this Mac's value wins.
        let toolAccount = "extension.com.example.tool.token"
        login.seed(toolAccount, "tok-test-login-newer-0001", modified: KS.t(200))
        synced.seed(toolAccount, "tok-test-synced-older-0001", modified: KS.t(100))
        // Another Mac's clock is ten days ahead (A15): its save time counts as the oldest possible, so a key saved here
        // weeks ago still wins.
        let skewAccount = "extension.com.example.skew.token"
        login.seed(skewAccount, "tok-test-login-skew-0001", modified: KS.t(100), saved: KS.t(100))
        synced.seed(skewAccount, "tok-test-synced-skew-0001", modified: KS.t(100), saved: Date().addingTimeInterval(10 * 86400))
        // An hour ahead is within a day: it counts as itself, and wins over a key saved a minute ago.
        let nearAccount = "extension.com.example.near.token"
        login.seed(nearAccount, "tok-test-login-near-0001", modified: KS.t(100), saved: Date().addingTimeInterval(-60))
        synced.seed(nearAccount, "tok-test-synced-near-0001", modified: KS.t(100), saved: Date().addingTimeInterval(3600))
        // Only here: it moves, and is kept as a replaced copy too (round 3, 3).
        login.seed("anthropic", "sk-test-login-only-0001", label: "AllInOneIME: Claude API", modified: KS.t(100),
                   saved: KS.t(100))
        // Never synced: it stays here, and isn't put in iCloud Keychain.
        login.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))

        let result = try KS.turnOn(login, synced: synced, replaced: replaced)

        #expect(result.complete)
        #expect(synced.value("openai") == "sk-test-login-newer-0001", "the modification date won over the save time")
        #expect(synced.saved("openai") == KS.t(200), "the copy doesn't carry the time its key was saved")
        #expect(synced.value("gemini") == "sk-test-synced-newer-0001", "the modification date won over the save time")
        #expect(synced.value(toolAccount) == "tok-test-login-newer-0001")
        #expect(synced.value(skewAccount) == "tok-test-login-skew-0001", "a save time ten days ahead won")
        #expect(synced.value(nearAccount) == "tok-test-synced-near-0001", "a save time an hour ahead didn't count as itself")
        #expect(synced.value("anthropic") == "sk-test-login-only-0001")
        for account in ["openai", "gemini", toolAccount, skewAccount, nearAccount, "anthropic"] {
            #expect(!login.has(account), "\(account) left in the login keychain: \(login.deletes)")
        }
        // The keys that lost here are kept aside, not where they were (round 2, 2).
        #expect(replaced.value("gemini") == "sk-test-login-older-0001", "a login key that lost isn't kept aside")
        #expect(replaced.value(nearAccount) == "tok-test-login-near-0001", "a login key that lost isn't kept aside")
        // The synced keys a newer one from here overwrote are kept aside too.
        #expect(replaced.value("openai") == "sk-test-synced-older-0001", "the overwritten synced key is nowhere")
        #expect(replaced.value(toolAccount) == "tok-test-synced-older-0001", "the overwritten synced key is nowhere")
        #expect(replaced.value(skewAccount) == "tok-test-synced-skew-0001", "the overwritten synced key is nowhere")
        // A key moved where the synced store had none (round 3, 3), labelled as a replaced copy (round 3, 2).
        #expect(replaced.value("anthropic") == "sk-test-login-only-0001", "a key moved into an empty slot isn't kept aside")
        #expect(replaced.lastWrite("anthropic")?.label == KS.replacedLabel("AllInOneIME: Claude API"))
        #expect(synced.lastWrite("anthropic")?.label == "AllInOneIME: Claude API")
        #expect(login.value("hosted") == "token-test-hosted-0001")
        #expect(!synced.has("hosted") && !replaced.has("hosted"), "the AllInOneIME Cloud sign-in was synced")
    }

    /// S5: turning key sync off copies the synced items into the login keychain (newest winning, A10) and leaves the
    /// synced store as it was. A login key the synced one overwrites is kept aside as a replaced copy (round 2, 2).
    @Test func s5_turningOffCopiesSyncedIntoTheLoginKeychainAndLeavesSyncedAlone() throws {
        let login = KSStore(.login), synced = KSStore(.synced), replaced = KSStore(.replaced)
        synced.seed("openai", "sk-test-synced-openai-0001", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200),
                    saved: KS.t(200))
        synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(300), saved: KS.t(300))
        // Saved before the synced one, though a host bound here since restamped it: the synced value wins.
        login.seed("gemini", "sk-test-login-gemini-older1", modified: KS.t(400), saved: KS.t(100))
        login.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))
        let syncedOpenAIStamp = synced.modified("openai"), syncedGeminiStamp = synced.modified("gemini")

        let result = try KS.turnOff(synced, into: login, replaced: replaced)

        #expect(result.complete)
        #expect(login.value("openai") == "sk-test-synced-openai-0001")
        #expect(login.comment("openai") == "api.openai.com")
        #expect(login.lastWrite("openai")?.label == KS.openAILabel)
        #expect(login.saved("openai") == KS.t(200), "the copy doesn't carry the time its key was saved")
        #expect(login.value("gemini") == "sk-test-synced-gemini-0001", "the modification date won over the save time")
        #expect(login.saved("gemini") == KS.t(300))
        #expect(replaced.value("gemini") == "sk-test-login-gemini-older1", "the overwritten login key is nowhere")
        #expect(!replaced.has("hosted"))
        #expect(login.value("hosted") == "token-test-hosted-0001")
        // The synced store is unchanged: nothing written to or deleted from it (other Macs keep their keys).
        #expect(synced.writes.isEmpty && synced.deletes.isEmpty)
        #expect(synced.value("openai") == "sk-test-synced-openai-0001" && synced.value("gemini") == "sk-test-synced-gemini-0001")
        #expect(synced.modified("openai") == syncedOpenAIStamp && synced.modified("gemini") == syncedGeminiStamp)
        #expect(synced.saved("openai") == KS.t(200) && synced.saved("gemini") == KS.t(300))
    }

    /// S6: the silent pass while key sync is on copies each readable login keychain item into the synced store (label,
    /// host, ending kept), reads the copy back, keeps a replaced copy (the synced store had none, round 3, 3), and
    /// deletes the login item only after both read back; on a mismatch the login item is kept. `hosted` stays put.
    @Test func s6_theMoveCopiesReadsBackThenDeletesTheLoginItem() throws {
        let log = KSLog()
        let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
        login.seed("openai", "sk-test-login-openai-a1b2", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        let extensionAccount = "extension.com.example.tool.token"
        login.seed(extensionAccount, "tok-test-extension-c3d4", label: "AllInOneIME: Example Tool token", modified: KS.t(100))
        login.seed("hosted", "token-test-hosted-e5f6", label: "AllInOneIME: AllInOneIME Cloud", host: "cloud.example.com",
                   modified: KS.t(100))

        let result = try KS.silentPass(login, synced: synced, replaced: replaced)

        #expect(result.moved == ["openai", extensionAccount])
        #expect(result.waiting.isEmpty && result.complete)

        // Landed in the synced store, label, comment (host) and ending kept.
        #expect(synced.lastWrite("openai") == KSStore.Write(account: "openai", key: "sk-test-login-openai-a1b2",
                                                           label: KS.openAILabel, comment: "api.openai.com", ending: "a1b2"))
        #expect(synced.value("openai") == "sk-test-login-openai-a1b2" && synced.comment("openai") == "api.openai.com")
        let tool = synced.lastWrite(extensionAccount)
        #expect(tool?.label == "AllInOneIME: Example Tool token" && tool?.ending == "c3d4" && tool?.comment == "")
        // 0.6.4's items don't say when they were saved: each copy says when its login item was last changed (A10).
        #expect(synced.saved("openai") == KS.t(100) && synced.saved(extensionAccount) == KS.t(100))
        // And kept as replaced copies, labelled so (round 3, 2 and 3).
        #expect(replaced.lastWrite("openai") == KSStore.Write(account: "openai", key: "sk-test-login-openai-a1b2",
                                                             label: KS.replacedLabel(KS.openAILabel), comment: "api.openai.com",
                                                             ending: "a1b2"), "\(log.all)")
        #expect(replaced.value(extensionAccount) == "tok-test-extension-c3d4")
        #expect(replaced.lastWrite(extensionAccount)?.label == KS.replacedLabel("AllInOneIME: Example Tool token"))
        #expect(replaced.saved("openai") == KS.t(100))

        // The login items are gone, each deleted only after its copies were read back.
        for account in ["openai", extensionAccount] {
            #expect(!login.has(account), "\(account) left in the login keychain")
            #expect(log.happened("synced.read:\(account)", before: "login.delete:\(account)"), "\(account): \(log.all)")
            #expect(log.happened("replaced.read:\(account)", before: "login.delete:\(account)"), "\(account): \(log.all)")
        }
        // The never-synced one stays in the login keychain, untouched.
        #expect(!result.moved.contains("hosted"))
        #expect(login.value("hosted") == "token-test-hosted-e5f6" && !login.deletes.contains("hosted"))
        #expect(!synced.has("hosted") && !replaced.has("hosted"))

        // A read-back that doesn't match: the login item is kept, and it isn't reported as moved. The bad copy is taken
        // out of the synced store, which didn't hold the account before (spec change 3).
        let login2 = KSStore(.login), synced2 = KSStore(.synced)
        login2.seed("openai", "sk-test-login-openai-a1b2", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        synced2.garble(["openai"])
        let mismatch = try KS.silentPass(login2, synced: synced2, replaced: KSStore(.replaced))
        #expect(!mismatch.moved.contains("openai") && !mismatch.complete)
        #expect(login2.value("openai") == "sk-test-login-openai-a1b2")
        #expect(login2.deletes.isEmpty)
        #expect(!synced2.has("openai"), "the copy that didn't read back was left in the synced store")
    }

    /// S7: an item that needs the password is skipped by the silent pass, and moves at its first `load`, with one read.
    @Test func s7_anItemThatNeedsThePasswordMovesAtItsFirstLoad() throws {
        let login = KSStore(.login), synced = KSStore(.synced), replaced = KSStore(.replaced)
        login.seed("gemini", "sk-test-login-gemini-g7h8", label: "AllInOneIME: Gemini API", modified: KS.t(100))
        login.needPassword(["gemini"])

        let result = try KS.silentPass(login, synced: synced, replaced: replaced)
        #expect(result.waiting == ["gemini"])
        #expect(!result.moved.contains("gemini"))
        #expect(login.has("gemini") && login.deletes.isEmpty)
        #expect(!synced.has("gemini") && !replaced.has("gemini"))
        #expect(login.reads("gemini") == 0)  // the silent pass asked nothing

        let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { true })
        let first = KS.with(store) { APIKeys.load(.gemini) }
        #expect(first == "sk-test-login-gemini-g7h8")
        #expect(login.reads("gemini") == 1)
        #expect(synced.value("gemini") == "sk-test-login-gemini-g7h8", "not moved at its first load")
        #expect(synced.saved("gemini") == KS.t(100), "the copy doesn't say when its key was saved")
        #expect(replaced.value("gemini") == "sk-test-login-gemini-g7h8", "moved into an empty slot, yet not kept aside")
        #expect(!login.has("gemini"))
        let again = KS.with(store) { APIKeys.load(.gemini) }
        #expect(again == "sk-test-login-gemini-g7h8")
        #expect(login.reads("gemini") == 1, "the password was asked for again")
    }

    /// S8: a duplicate when the keys move (another Mac synced first): the newer one wins, by the time each key was saved
    /// (A10). A login key that loses to a different one is kept aside as a replaced copy, and so is a synced key a newer
    /// login one overwrites (round 2, 2).
    @Test func s8_aDuplicateWhenTheKeysMoveTheNewerWins() throws {
        let log = KSLog()
        let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
        // Another Mac saved a newer openai key: it stays, and the older login one is put aside, not deleted.
        login.seed("openai", "sk-test-login-older-0001", label: KS.openAILabel, modified: KS.t(200))
        synced.seed("openai", "sk-test-synced-newer-0001", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
        // The login gemini key was saved after the synced one, though the synced item was restamped since (a copy or a
        // comment change): the login key wins.
        login.seed("gemini", "sk-test-login-newer-0001", label: "AllInOneIME: Gemini API", modified: KS.t(300))
        synced.seed("gemini", "sk-test-synced-older-0001", label: "AllInOneIME: Gemini API", modified: KS.t(400),
                    saved: KS.t(200))

        let result = try KS.silentPass(login, synced: synced, replaced: replaced)

        #expect(synced.value("openai") == "sk-test-synced-newer-0001")
        #expect(!result.moved.contains("openai"))
        #expect(replaced.value("openai") == "sk-test-login-older-0001", "a login key that lost isn't kept aside: \(log.all)")
        #expect(replaced.lastWrite("openai")?.label == KS.replacedLabel(KS.openAILabel))
        #expect(!login.has("openai"), "a login key that lost was left where routed reads and merges find it")
        #expect(log.happened("replaced.read:openai", before: "login.delete:openai"),
                "the login key was deleted before its kept copy was read back: \(log.all)")
        #expect(synced.value("gemini") == "sk-test-login-newer-0001", "the modification date won over the save time")
        #expect(synced.saved("gemini") == KS.t(300))
        #expect(result.moved.contains("gemini"))
        #expect(!login.has("gemini"))
        #expect(replaced.value("gemini") == "sk-test-synced-older-0001", "the overwritten synced key is nowhere")
        let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { true })
        #expect(store.read("openai") == "sk-test-synced-newer-0001" && store.read("gemini") == "sk-test-login-newer-0001")
    }

    /// S9: Remove Key… while syncing deletes the synced, login and replaced copies.
    @Test func s9_removeWhileSyncingDeletesEveryCopy() throws {
        let login = KSStore(.login), synced = KSStore(.synced), replaced = KSStore(.replaced)
        synced.seed("openai", "sk-test-synced-openai-0001", modified: KS.t(300))
        login.seed("openai", "sk-test-login-openai-0001", modified: KS.t(100))
        replaced.seed("openai", "sk-test-replaced-openai-0001", modified: KS.t(50))
        synced.seed("gemini", "sk-test-synced-gemini-0001", modified: KS.t(300))
        replaced.seed("gemini", "sk-test-replaced-gemini-0001", modified: KS.t(50))
        let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { true })

        try APIKeys.remove(account: "openai", in: store)

        #expect(!synced.has("openai") && !login.has("openai"))
        #expect(!replaced.has("openai"), "the key's replaced copy was left")
        #expect(!APIKeys.hasKeychainKey(account: "openai", in: store) && store.read("openai") == nil)
        #expect(synced.value("gemini") == "sk-test-synced-gemini-0001")  // only that key
        #expect(replaced.value("gemini") == "sk-test-replaced-gemini-0001")
    }

    /// S10: an empty save never removes a key, in any of the stores, with key sync on or off.
    @Test func s10_anEmptySaveNeverRemovesAKey() throws {
        for syncing in [true, false] {
            let login = KSStore(.login), synced = KSStore(.synced)
            let store = KS.routed(login: login, synced: synced, syncs: { syncing })
            try APIKeys.save("sk-test-saved-openai-0001", account: "openai", label: KS.openAILabel, in: store)
            #expect((syncing ? synced : login).value("openai") == "sk-test-saved-openai-0001")
            login.seed("hosted", "token-test-hosted-0001", modified: KS.t(100))
            login.seed("gemini", "sk-test-login-gemini-0001", modified: KS.t(100))
            for (account, empty) in [("openai", ""), ("openai", "  \n"), ("hosted", ""), ("gemini", "\t")] {
                #expect(throws: APIKeys.EmptyKey.self) {
                    try APIKeys.save(empty, account: account, label: "AllInOneIME: test", in: store)
                }
            }
            #expect((syncing ? synced : login).value("openai") == "sk-test-saved-openai-0001", "syncing \(syncing)")
            #expect(login.value("hosted") == "token-test-hosted-0001")
            #expect(login.value("gemini") == "sk-test-login-gemini-0001")
            #expect(synced.deletes.isEmpty && login.deletes.isEmpty, "syncing \(syncing)")
            #expect(store.read("openai") == "sk-test-saved-openai-0001")
        }
    }

    /// S11: the host binding travels with the synced item: on another Mac the key still goes only to its host.
    @Test func s11_theHostBindingTravelsWithTheSyncedItem() throws {
        let synced = KSStore(.synced)  // iCloud Keychain, shared by both Macs
        let macA = KS.routed(login: KSStore(.login), synced: synced, syncs: { true })
        let macB = KS.routed(login: KSStore(.login), synced: synced, syncs: { true })

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
        let store = KS.routed(login: KSStore(.login), synced: synced, syncs: { true })
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
    /// back to the other store: while syncing, not to the login keychain; while not, not to the synced store.
    @Test func s13_lockedOrUnentitledIsAKeychainErrorNeverAFallback() throws {
        for status: Int32 in [-25308, -34018] {
            for syncing in [true, false] {
                let login = KSStore(.login), synced = KSStore(.synced)
                let (failing, other) = syncing ? (synced, login) : (login, synced)
                failing.fail(with: status)
                let store = KS.routed(login: login, synced: synced, syncs: { syncing })
                let error = KS.keychainError {
                    try APIKeys.save("sk-test-openai-0001", account: "openai", label: KS.openAILabel, in: store)
                }
                #expect(error?.status == status, "status \(status), syncing \(syncing): \(String(describing: error))")
                #expect(other.writes.isEmpty && other.deletes.isEmpty && !other.has("openai"),
                        "status \(status), syncing \(syncing): fell back to the other store")
            }
        }
    }

    /// S14: two Macs move their keys one after the other. Mac A has an older key, Mac B a newer one. Whichever moves
    /// first, B's newer key wins; A's key is kept as a replaced copy, never lost: on A when A moves second, on B (the
    /// synced copy B overwrites) when A moves first, and on A anyway, since it moved into an empty slot (round 3, 3).
    @Test func s14_twoMacsMoveOneAfterTheOtherTheNewerKeyWins() throws {
        // A key saved by this version says when (A10).
        let savedHere = KSStore(.synced)
        let before = Date()
        try APIKeys.save("sk-test-saved-now-0001", account: "openai", label: KS.openAILabel,
                         in: KS.routed(login: KSStore(.login), synced: savedHere, syncs: { true }))
        let savedAt = try #require(savedHere.saved("openai"), "APIKeys.save didn't record when the key was saved")
        #expect(savedAt >= before.addingTimeInterval(-2) && savedAt <= Date().addingTimeInterval(2), "\(savedAt)")

        for aFirst in [true, false] {
            let log = KSLog()
            let synced = KSStore(.synced, log: log)  // iCloud Keychain, both Macs'
            let loginA = KSStore(.login, "loginA", log: log), replacedA = KSStore(.replaced, "replacedA", log: log)
            let loginB = KSStore(.login, "loginB", log: log), replacedB = KSStore(.replaced, "replacedB", log: log)
            // As 0.6.4 left them: no save time. A's is a year old, B's from last week.
            loginA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
            loginB.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200))
            let macA = KS.routed(login: loginA, synced: synced, replaced: replacedA, syncs: { true })
            let macB = KS.routed(login: loginB, synced: synced, replaced: replacedB, syncs: { true })
            func move(_ login: KSStore, _ replaced: KSStore) throws -> Set<String> {
                try KS.silentPass(login, synced: synced, replaced: replaced).moved
            }
            let order = aFirst ? "A first" : "B first"

            if aFirst {
                #expect(try move(loginA, replacedA).contains("openai"), "\(order)")
                // Mac A uses the key: binding its host is a comment change, which restamps the synced item.
                #expect(macA.setComment("openai", "api.openai.com") == .ok)
                #expect(try move(loginB, replacedB).contains("openai"), "\(order): B's newer key lost: \(log.all)")
                #expect(!loginB.has("openai"), "\(order): B's key, moved, was left in its login keychain")
                // A's key, overwritten in iCloud Keychain, is kept aside on B.
                #expect(replacedB.value("openai") == "sk-test-macA-older-a111", "\(order): A's key is nowhere: \(log.all)")
            } else {
                #expect(try move(loginB, replacedB).contains("openai"), "\(order)")
                #expect(macB.setComment("openai", "api.openai.com") == .ok)
                #expect(try !move(loginA, replacedA).contains("openai"), "\(order): A's older key won: \(log.all)")
                #expect(!loginA.has("openai"), "\(order): A's losing key was left in its login keychain: \(log.all)")
                #expect(replacedB.value("openai") == "sk-test-macB-newer-b222", "\(order): B's move into an empty slot isn't kept")
            }
            // A's key is kept aside on A either way: it lost there, or it moved into an empty slot.
            #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "\(order): A's key isn't kept on A: \(log.all)")

            #expect(synced.value("openai") == "sk-test-macB-newer-b222", "\(order): \(log.all)")
            #expect(synced.saved("openai") == KS.t(200), "\(order): the synced copy doesn't say when B's key was saved")
            #expect(synced.comment("openai") == "api.openai.com")
            #expect(APIKeys.keyEnding(account: "openai", in: macA) == "b222")
            // Both Macs use B's key.
            #expect(macA.read("openai") == "sk-test-macB-newer-b222" && macB.read("openai") == "sk-test-macB-newer-b222", "\(order)")
            #expect(!loginA.has("openai") && !loginB.has("openai"), "\(order)")
            #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "\(order): a routed read took A's kept key")
        }
    }

    /// S15: Remove Key… while this Mac doesn't sync keys deletes this Mac's login keychain and replaced copies, and leaves
    /// the synced copy (the one other Macs use) alone.
    @Test func s15_removeWithKeySyncOffLeavesTheSyncedCopy() throws {
        var rowOff = ICloudSyncSettings(enabled: true)
        rowOff.keys = false
        for settings in [ICloudSyncSettings(), rowOff] {
            let login = KSStore(.login), synced = KSStore(.synced), replaced = KSStore(.replaced)
            synced.seed("openai", "sk-test-synced-openai-0001", modified: KS.t(300), saved: KS.t(300))
            login.seed("openai", "sk-test-login-openai-0001", modified: KS.t(200), saved: KS.t(200))
            replaced.seed("openai", "sk-test-replaced-openai-0001", modified: KS.t(50), saved: KS.t(50))
            login.seed("gemini", "sk-test-login-gemini-0001", modified: KS.t(200), saved: KS.t(200))
            replaced.seed("gemini", "sk-test-replaced-gemini-0001", modified: KS.t(50), saved: KS.t(50))
            let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { settings.syncsKeys })

            try APIKeys.remove(account: "openai", in: store)

            let which = settings.enabled ? "keys row off" : "sync off"
            #expect(!login.has("openai"), "\(which): this Mac's copy left")
            #expect(!replaced.has("openai"), "\(which): the key's replaced copy was left")
            #expect(synced.value("openai") == "sk-test-synced-openai-0001", "\(which): removed from all Macs")
            #expect(synced.deletes.isEmpty && synced.writes.isEmpty, "\(which): \(synced.deletes)")
            #expect(!APIKeys.hasKeychainKey(account: "openai", in: store) && store.read("openai") == nil, "\(which)")
            #expect(login.value("gemini") == "sk-test-login-gemini-0001")  // only that key
            #expect(replaced.value("gemini") == "sk-test-replaced-gemini-0001")
        }
    }

    /// S16: a copy that doesn't read back, into a store that already held the account, keeps that store's item: the
    /// clean-up deletes only a copy it just made in a store that didn't hold the account (spec change 3). The item it
    /// overwrote was kept aside first (round 2, 2), and the move counts as incomplete.
    @Test func s16_aMismatchWhereTheStoreHeldTheAccountKeepsItsItem() throws {
        // Moving into the synced store: the login keychain's key is newer than the synced one (another Mac's); its copy
        // doesn't read back.
        do {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", "sk-test-synced-other-mac-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            login.seed("openai", "sk-test-login-newer-0002", label: KS.openAILabel, modified: KS.t(300))
            synced.garble(["openai"])
            let result = try KS.silentPass(login, synced: synced, replaced: replaced)
            #expect(!result.moved.contains("openai") && !result.complete)
            #expect(synced.has("openai") && synced.deletes.isEmpty, "the synced item other Macs use was deleted: \(log.all)")
            #expect(login.value("openai") == "sk-test-login-newer-0002" && login.deletes.isEmpty, "\(log.all)")
            #expect(replaced.value("openai") == "sk-test-synced-other-mac-0001", "the overwritten synced key is nowhere: \(log.all)")
        }
        // Turning key sync off: the synced key is newer; its copy into the login keychain, which held one, doesn't read
        // back.
        do {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", "sk-test-synced-newer-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            login.seed("openai", "sk-test-login-older-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            login.garble(["openai"])
            let result = try KS.turnOff(synced, into: login, replaced: replaced)
            #expect(!result.complete)
            #expect(login.has("openai") && login.deletes.isEmpty, "this Mac's item was deleted: \(log.all)")
            #expect(synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
            #expect(synced.value("openai") == "sk-test-synced-newer-0002")
            #expect(replaced.value("openai") == "sk-test-login-older-0001", "the overwritten login key is nowhere: \(log.all)")
        }
    }

    /// S17 (review case A): a loser kept aside never comes back after "remove from all your Macs", neither at its next
    /// use (the routed store's first-use move) nor at the next launch's silent pass. One that can't be read silently
    /// stays in the login keychain, and the silent pass doesn't bring it back either (only a password prompt the user
    /// allows could: round 3, 6).
    @Test func s17_aKeptLoserNeverComesBackAfterRemoveFromAllMacs() throws {
        #expect(KeySync.replacedService == "AllInOneIME replaced API key")
        #expect(KeySync.replacedService != APIKeys.service)

        let log = KSLog()
        let synced = KSStore(.synced, log: log)  // iCloud Keychain, both Macs'
        let loginA = KSStore(.login, "loginA", log: log), replacedA = KSStore(.replaced, "replacedA", log: log)
        let loginB = KSStore(.login, "loginB", log: log), replacedB = KSStore(.replaced, "replacedB", log: log)
        // Mac B synced newer keys first.
        synced.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300),
                    saved: KS.t(300))
        synced.seed("gemini", "sk-test-macB-newer-g222", label: "AllInOneIME: Gemini API", modified: KS.t(300), saved: KS.t(300))
        // Mac A's 0.6.4 keys are older: openai reads silently, gemini asks for the password.
        loginA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        loginA.seed("gemini", "sk-test-macA-older-g111", label: "AllInOneIME: Gemini API", modified: KS.t(100))
        loginA.needPassword(["gemini"])
        let macA = KS.routed(login: loginA, synced: synced, replaced: replacedA, syncs: { true })
        let macB = KS.routed(login: loginB, synced: synced, replaced: replacedB, syncs: { true })

        // A's silent pass: the readable loser is put aside (copied, read back, then deleted from the login keychain);
        // the one that would ask stays where it is.
        let first = try KS.silentPass(loginA, synced: synced, replaced: replacedA)
        #expect(!first.moved.contains("openai") && !first.moved.contains("gemini"), "\(first)")
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "A's losing key isn't kept aside: \(log.all)")
        #expect(!loginA.has("openai"), "A's losing key was left in its login keychain: \(log.all)")
        #expect(log.happened("replacedA.write:openai", before: "loginA.delete:openai")
                && log.happened("replacedA.read:openai", before: "loginA.delete:openai"),
                "the login keychain's item was deleted before its kept copy was read back: \(log.all)")
        #expect(loginA.value("gemini") == "sk-test-macA-older-g111" && loginA.reads("gemini") == 0)
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
        let second = try KS.silentPass(loginA, synced: synced, replaced: replacedA)
        #expect(!second.moved.contains("openai") && !second.moved.contains("gemini"), "\(second)")
        #expect(!synced.has("openai") && !synced.has("gemini"), "a kept loser went back to iCloud Keychain: \(log.all)")
        #expect(!log.all.dropFirst(removed).contains(where: { $0.hasPrefix("synced.write:") }), "\(log.all)")
        #expect(loginA.reads("gemini") == 0, "the silent pass asked for the password")
        #expect(macA.read("openai") == nil)
        // The safety copy is still there, on A alone.
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111")

        // Remove… on Mac A takes this Mac's kept copy too.
        try APIKeys.remove(account: "openai", in: macA)
        #expect(!replacedA.has("openai"), "Remove… left the key's replaced copy")
    }

    /// S18 (review case B): a login key that lost when key sync was turned on, kept aside, never returns to iCloud
    /// Keychain when key sync is turned off and on again after another Mac removed the key from all Macs.
    @Test func s18_aLoserKeptByTurningOnNeverReturnsWhenTurnedOffAndOn() throws {
        let log = KSLog()
        let synced = KSStore(.synced, log: log)
        let loginA = KSStore(.login, "loginA", log: log), replacedA = KSStore(.replaced, "replacedA", log: log)
        synced.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
        loginA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, modified: KS.t(400), saved: KS.t(100))
        let macB = KS.routed(login: KSStore(.login, "loginB", log: log), synced: synced, syncs: { true })

        // Mac A turns key sync on: B's key wins, A's is put aside.
        _ = try KS.turnOn(loginA, synced: synced, replaced: replacedA)
        #expect(synced.value("openai") == "sk-test-macB-newer-b222")
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "A's losing key isn't kept aside: \(log.all)")
        #expect(!loginA.has("openai"), "A's losing key was left where routed reads and merges find it: \(log.all)")

        // Mac B removes the key from all Macs.
        try APIKeys.remove(account: "openai", in: macB)
        #expect(!synced.has("openai"))
        let removed = log.all.count

        // Mac A turns key sync off, then on again.
        _ = try KS.turnOff(synced, into: loginA, replaced: replacedA)
        #expect(!loginA.has("openai"), "\(log.all)")
        _ = try KS.turnOn(loginA, synced: synced, replaced: replacedA)
        #expect(!synced.has("openai"), "a kept loser went back to iCloud Keychain: \(log.all)")
        #expect(!log.all.dropFirst(removed).contains(where: { $0.hasPrefix("synced.write:") }), "\(log.all)")
        for syncing in [true, false] {
            let macA = KS.routed(login: loginA, synced: synced, replaced: replacedA, syncs: { syncing })
            #expect(macA.read("openai") == nil && !APIKeys.hasKeychainKey(account: "openai", in: macA), "syncing \(syncing)")
        }
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111")
    }

    /// S19 (review case C): a 0.6.4 item without a save time, whose modification date changes later (0.6.4 after a
    /// downgrade, a development build or the CLI binding a host), never overwrites a newer synced key; the synced key
    /// survives.
    @Test func s19_aRestampedOldItemNeverOverwritesANewerSyncedKey() throws {
        let newer = "sk-test-synced-newer-b222", older = "sk-test-login-older-a111"
        // It reads silently: the first pass puts it aside, so nothing is left for 0.6.4 to restamp; and a kept copy whose
        // modification date changes is never compared.
        do {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", newer, label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
            login.seed("openai", older, label: KS.openAILabel, modified: KS.t(100))  // no host bound yet
            _ = try KS.silentPass(login, synced: synced, replaced: replaced)
            #expect(!login.has("openai"), "the losing key was left for 0.6.4 to restamp: \(log.all)")
            login.touch("openai", comment: "api.openai.com", modified: Date())
            replaced.touch("openai", comment: "api.openai.com", modified: Date())
            _ = try KS.silentPass(login, synced: synced, replaced: replaced)
            _ = try KS.turnOn(login, synced: synced, replaced: replaced)
            let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { true })
            #expect(store.read("openai") == newer, "\(log.all)")
            #expect(synced.value("openai") == newer && synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
        }
        // It asks for the password: it stays in the login keychain, where 0.6.4 restamps it. The silent pass can't read
        // it, and reads find the synced key first: it doesn't come back.
        do {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", newer, label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
            login.seed("openai", older, label: KS.openAILabel, modified: KS.t(100))
            login.needPassword(["openai"])
            _ = try KS.silentPass(login, synced: synced, replaced: replaced)
            #expect(login.value("openai") == older, "a key that can't be read silently was lost: \(log.all)")
            login.touch("openai", comment: "api.openai.com", modified: Date())
            _ = try KS.silentPass(login, synced: synced, replaced: replaced)
            let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { true })
            #expect(store.read("openai") == newer, "\(log.all)")
            #expect(KS.with(store) { APIKeys.keychainKey(account: "openai") } == newer)
            #expect(synced.value("openai") == newer && synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
            #expect(login.reads("openai") == 0, "the password was asked for: \(log.all)")
            #expect(login.value("openai") == older)
        }
        // It asked once in 0.6.4 and the user allowed it always, so it now reads silently, restamped: whichever wins,
        // neither key is lost (the synced one kept aside before being overwritten).
        do {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", newer, label: KS.openAILabel, modified: KS.t(200), saved: KS.t(200))
            login.seed("openai", older, label: KS.openAILabel, host: "api.openai.com", modified: Date())
            _ = try KS.silentPass(login, synced: synced, replaced: replaced)
            let kept = [synced, login, replaced].compactMap { $0.value("openai") }
            #expect(kept.contains(newer), "the newer synced key is nowhere: \(log.all)")
            #expect(kept.contains(older), "the login keychain's key is nowhere: \(log.all)")
        }
    }

    /// S20 (review case D): an older Mac moves its keys first; the newer Mac's move overwrites its key in iCloud Keychain,
    /// and that overwritten value is kept aside (on the Mac that overwrote it) before the write, not lost. The older Mac
    /// kept its own key aside too, having moved it into an empty slot (round 3, 3).
    @Test func s20_anOlderMacMovingFirstItsOverwrittenSyncedValueIsKeptAside() throws {
        let log = KSLog()
        let synced = KSStore(.synced, log: log)
        let loginA = KSStore(.login, "loginA", log: log), replacedA = KSStore(.replaced, "replacedA", log: log)
        let loginB = KSStore(.login, "loginB", log: log), replacedB = KSStore(.replaced, "replacedB", log: log)
        loginA.seed("openai", "sk-test-macA-older-a111", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100))
        loginB.seed("openai", "sk-test-macB-newer-b222", label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200))

        #expect(try KS.silentPass(loginA, synced: synced, replaced: replacedA).moved.contains("openai"))
        #expect(synced.value("openai") == "sk-test-macA-older-a111")
        #expect(replacedA.value("openai") == "sk-test-macA-older-a111", "A's key moved into an empty slot isn't kept aside")
        let aMoved = log.all.count
        #expect(try KS.silentPass(loginB, synced: synced, replaced: replacedB).moved.contains("openai"))

        #expect(synced.value("openai") == "sk-test-macB-newer-b222", "\(log.all)")
        #expect(replacedB.value("openai") == "sk-test-macA-older-a111", "A's key, overwritten in iCloud Keychain, is nowhere: \(log.all)")
        let afterA = log.all.dropFirst(aMoved)
        let aside = afterA.firstIndex(of: "replacedB.write:openai"), overwritten = afterA.lastIndex(of: "synced.write:openai")
        let asideFirst = aside.flatMap { a in overwritten.map { a < $0 } } ?? false
        #expect(asideFirst, "not kept aside before it was overwritten: \(log.all)")
        #expect(!loginA.has("openai") && !loginB.has("openai"))
    }

    /// S21 (review case E): turning key sync on is interrupted (a copy doesn't read back), then key sync is turned off:
    /// every key that had moved is readable on this Mac again, in the login keychain.
    ///
    /// The core half, through `KeySync.Stores` (A14). The controller half (`ICloudSyncController` and its `keys-synced`
    /// marker beside the sync record) lives in the app and can't be driven here; it is a self-test case for the
    /// implementer, on in-memory stores and the self-test's own state directory:
    ///   1. Key sync off, no marker. Turn it on with one account garbled in the synced store. The marker exists before
    ///      the first key moves (watch for it from the synced store's write closure) with the content `moving`; after
    ///      the incomplete turn it is still `moving`, never `done`.
    ///   2. Turn key sync off in the config and apply. Because the marker exists (`moving` or `done`), the copy-back
    ///      (`turn(syncing: false)`) runs even though the last turn on never completed. Every key that moved is in the
    ///      login keychain; the marker is removed once the copy-back completes, and kept (to retry) when it doesn't.
    ///   3. Turn it on again with nothing garbled: the marker goes `moving`, then `done` when the turn completes.
    ///   4. With the marker `moving` at launch and key sync on in the config, the turn on is retried.
    ///   5. (S23, S24) The same as 1 and 4 with the replaced store failing its writes, or with an unreadable synced item
    ///      the turn would overwrite, instead of a garbled account: the marker stays `moving`, and the retry, once the
    ///      store works again, makes it `done`.
    @Test func s21_anInterruptedTurnOnThenOffLeavesEveryMovedKeyReadableHere() throws {
        let log = KSLog()
        let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
        let keys = ["openai": "sk-test-login-openai-0001", "gemini": "sk-test-login-gemini-0001",
                    "anthropic": "sk-test-login-anthropic-0001"]
        for (account, key) in keys { login.seed(account, key, modified: KS.t(100), saved: KS.t(100)) }
        login.seed("hosted", "token-test-hosted-0001", modified: KS.t(100), saved: KS.t(100))
        synced.garble(["gemini"])
        let stores = KeySync.Stores(login: login.keychain, synced: synced.keychain, replaced: replaced.keychain,
                                    syncing: false)

        let on = try stores.turn(syncing: true)
        #expect(!on.isComplete, "a copy that didn't read back counted as moved: \(log.all)")
        #expect(stores.syncing)
        #expect(synced.value("openai") == keys["openai"] && !login.has("openai"), "\(log.all)")
        #expect(login.value("gemini") == keys["gemini"], "the key whose copy didn't read back was lost: \(log.all)")
        for (account, key) in keys { #expect(stores.store.read(account) == key, "\(account) unreadable while on: \(log.all)") }
        let syncedDeletes = synced.deletes.count, syncedWrites = synced.writes.count

        // Interrupted: the user turns key sync off.
        _ = try stores.turn(syncing: false)
        #expect(!stores.syncing)
        for (account, key) in keys {
            #expect(login.value(account) == key, "\(account) isn't in this Mac's login keychain again: \(log.all)")
            #expect(stores.store.read(account) == key, "\(account) unreadable once key sync is off: \(log.all)")
            #expect(KS.with(stores.store) { APIKeys.hasKeychainKey(account: account) }, "\(account)")
        }
        #expect(stores.store.read("hosted") == "token-test-hosted-0001")
        // Turning off left iCloud Keychain as it was, for the other Macs.
        #expect(synced.deletes.count == syncedDeletes && synced.writes.count == syncedWrites, "\(log.all)")
        #expect(synced.value("openai") == keys["openai"] && synced.value("anthropic") == keys["anthropic"])
    }

    /// S22 (review SF1): two Macs turn on key sync with different keys before they see each other. Each moves its key
    /// into what it sees as an empty slot; iCloud Keychain then keeps one value for the account on both. Both keys
    /// survive: one synced, the other as a replaced copy on its own Mac (round 3, 3).
    @Test func s22_twoMacsTurningOnBeforeSeeingEachOtherBothKeysSurvive() throws {
        let keyA = "sk-test-macA-key-a111", keyB = "sk-test-macB-key-b222"
        for bWins in [true, false] {
            let which = bWins ? "iCloud kept B's" : "iCloud kept A's"
            let log = KSLog()
            // Each Mac's view of iCloud Keychain, before the other's change arrives.
            let syncedA = KSStore(.synced, "syncedA", log: log), syncedB = KSStore(.synced, "syncedB", log: log)
            let loginA = KSStore(.login, "loginA", log: log), replacedA = KSStore(.replaced, "replacedA", log: log)
            let loginB = KSStore(.login, "loginB", log: log), replacedB = KSStore(.replaced, "replacedB", log: log)
            loginA.seed("openai", keyA, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100), saved: KS.t(100))
            loginB.seed("openai", keyB, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200), saved: KS.t(200))

            let a = try KS.turnOn(loginA, synced: syncedA, replaced: replacedA)
            let b = try KS.turnOn(loginB, synced: syncedB, replaced: replacedB)
            #expect(a.moved.contains("openai") && b.moved.contains("openai") && a.complete && b.complete, "\(which): \(log.all)")
            #expect(!loginA.has("openai") && !loginB.has("openai"), "\(which)")

            // iCloud Keychain resolves the conflict itself, without asking AllInOneIME: one value on both Macs.
            let (winner, winnerSaved) = bWins ? (keyB, KS.t(200)) : (keyA, KS.t(100))
            for view in [syncedA, syncedB] {
                view.seed("openai", winner, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300), saved: winnerSaved)
            }

            // Both keys survive, each Mac's own kept on it as a replaced copy.
            #expect(replacedA.value("openai") == keyA, "\(which): A's key is nowhere on A: \(log.all)")
            #expect(replacedB.value("openai") == keyB, "\(which): B's key is nowhere on B: \(log.all)")
            #expect(replacedA.lastWrite("openai")?.label == KS.replacedLabel(KS.openAILabel))
            let everywhere = [syncedA, syncedB, loginA, loginB, replacedA, replacedB].compactMap { $0.value("openai") }
            #expect(everywhere.contains(keyA) && everywhere.contains(keyB), "\(which): \(everywhere)")
            // The replaced copies are never used: both Macs use the synced value.
            let macA = KS.routed(login: loginA, synced: syncedA, replaced: replacedA, syncs: { true })
            let macB = KS.routed(login: loginB, synced: syncedB, replaced: replacedB, syncs: { true })
            #expect(macA.read("openai") == winner && macB.read("openai") == winner, "\(which)")
        }
    }

    /// S23 (review SF2): a set-aside that fails leaves the move incomplete (the marker stays `moving`, S21's step 5)
    /// and deletes nothing it would have kept aside; the retry, once the replaced store works, completes, with every
    /// replaced copy made.
    @Test func s23_aSetAsideFailureKeepsTheMoveIncompleteAndTheRetryCompletes() throws {
        let log = KSLog()
        let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
        // Only here: moved into an empty slot, so kept aside too (round 3, 3).
        login.seed("openai", "sk-test-login-only-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
        // Newer here: the synced key it overwrites must be kept aside first.
        login.seed("gemini", "sk-test-login-newer-0002", modified: KS.t(300), saved: KS.t(300))
        synced.seed("gemini", "sk-test-synced-older-0001", modified: KS.t(200), saved: KS.t(200))
        // Older here: this key must be kept aside before it leaves the login keychain.
        login.seed("anthropic", "sk-test-login-older-0001", modified: KS.t(100), saved: KS.t(100))
        synced.seed("anthropic", "sk-test-synced-newer-0002", modified: KS.t(300), saved: KS.t(300))
        replaced.fail(with: -61)
        let stores = KeySync.Stores(login: login.keychain, synced: synced.keychain, replaced: replaced.keychain,
                                    syncing: false)
        func turnOn() -> Bool { (try? stores.turn(syncing: true))?.isComplete ?? false }

        #expect(!turnOn(), "a set-aside that failed counted as complete: \(log.all)")
        #expect(stores.syncing)
        // Nothing left the login keychain without its replaced copy, and nothing was overwritten without one.
        #expect(login.value("openai") == "sk-test-login-only-0001", "a key moved without its replaced copy left: \(log.all)")
        #expect(login.value("gemini") == "sk-test-login-newer-0002", "\(log.all)")
        #expect(login.value("anthropic") == "sk-test-login-older-0001", "a losing key left without its replaced copy: \(log.all)")
        #expect(synced.value("gemini") == "sk-test-synced-older-0001", "a synced key was overwritten without its replaced copy")
        #expect(synced.value("anthropic") == "sk-test-synced-newer-0002")
        #expect(stores.store.read("openai") == "sk-test-login-only-0001")

        // Launched again with the marker `moving`: the turn on is retried, and the replaced store works now.
        replaced.fail(with: nil)
        #expect(turnOn(), "the retry didn't complete: \(log.all)")
        #expect(synced.value("openai") == "sk-test-login-only-0001")
        #expect(synced.value("gemini") == "sk-test-login-newer-0002")
        #expect(synced.value("anthropic") == "sk-test-synced-newer-0002")
        #expect(replaced.value("openai") == "sk-test-login-only-0001", "the moved key's replaced copy wasn't made: \(log.all)")
        #expect(replaced.value("gemini") == "sk-test-synced-older-0001", "the overwritten synced key is nowhere: \(log.all)")
        #expect(replaced.value("anthropic") == "sk-test-login-older-0001", "the losing login key is nowhere: \(log.all)")
        for account in ["openai", "gemini", "anthropic"] {
            #expect(!login.has(account), "\(account) left in the login keychain after the retry: \(log.all)")
        }
    }

    /// S24 (review SF3): a target item whose attributes are there but whose key can't be read is never overwritten; the
    /// move is incomplete, and the retry, once it reads, keeps it aside and completes.
    @Test func s24_anUnreadableTargetIsNeverOverwrittenAndTheMoveIsRetried() throws {
        // Turning on: another Mac's synced key hasn't arrived yet (its attributes have).
        do {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", "sk-test-synced-other-mac-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            login.seed("openai", "sk-test-login-newer-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            synced.unreadable(["openai"])

            #expect(!KS.completes { try KS.turnOn(login, synced: synced, replaced: replaced) }, "\(log.all)")
            #expect(synced.lastWrite("openai") == nil, "an item that couldn't be read was overwritten: \(log.all)")
            #expect(synced.value("openai") == "sk-test-synced-other-mac-0001")
            #expect(login.value("openai") == "sk-test-login-newer-0002" && login.deletes.isEmpty, "\(log.all)")

            synced.unreadable([])
            #expect(KS.completes { try KS.turnOn(login, synced: synced, replaced: replaced) }, "the retry didn't complete: \(log.all)")
            #expect(synced.value("openai") == "sk-test-login-newer-0002")
            #expect(replaced.value("openai") == "sk-test-synced-other-mac-0001", "the overwritten synced key is nowhere: \(log.all)")
            #expect(!login.has("openai"))
        }
        // Turning off: this Mac's login item would ask for the password, and asking is off.
        do {
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            synced.seed("openai", "sk-test-synced-newer-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            login.seed("openai", "sk-test-login-older-0001", label: KS.openAILabel, modified: KS.t(100), saved: KS.t(100))
            login.needPassword(["openai"])
            login.interactionAllowed = false

            #expect(!KS.completes { try KS.turnOff(synced, into: login, replaced: replaced) }, "\(log.all)")
            #expect(login.lastWrite("openai") == nil, "an item that couldn't be read was overwritten: \(log.all)")
            #expect(login.value("openai") == "sk-test-login-older-0001")
            #expect(synced.writes.isEmpty && synced.deletes.isEmpty)

            login.interactionAllowed = true
            #expect(KS.completes { try KS.turnOff(synced, into: login, replaced: replaced) }, "the retry didn't complete: \(log.all)")
            #expect(login.value("openai") == "sk-test-synced-newer-0002")
            #expect(replaced.value("openai") == "sk-test-login-older-0001", "the overwritten login key is nowhere: \(log.all)")
            #expect(synced.value("openai") == "sk-test-synced-newer-0002" && synced.writes.isEmpty && synced.deletes.isEmpty)
        }
    }

    /// S25: with key sync off, saving, reading, binding a host and removing a key touch only the login keychain (its
    /// API key service and its replaced copies), never the synced store, not even its attributes (round 3, 1).
    @Test func s25_withKeySyncOffKeysTouchOnlyTheLoginKeychain() throws {
        var rowOff = ICloudSyncSettings(enabled: true)
        rowOff.keys = false
        for settings in [ICloudSyncSettings(), rowOff] {
            let which = settings.enabled ? "keys row off" : "sync off"
            let log = KSLog()
            let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
            // Left in iCloud Keychain from when this Mac synced keys.
            synced.seed("openai", "sk-test-synced-left-0001", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
            synced.seed("gemini", "sk-test-synced-left-0002", modified: KS.t(300), saved: KS.t(300))
            replaced.seed("openai", "sk-test-replaced-openai-0001", modified: KS.t(50), saved: KS.t(50))
            let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { settings.syncsKeys })

            try APIKeys.save("sk-test-login-openai-0001", account: "openai", label: KS.openAILabel, host: "api.openai.com",
                             in: store)
            try APIKeys.save("sk-test-login-claude-0001", account: "anthropic", label: "AllInOneIME: Claude API", in: store)
            #expect(login.value("openai") == "sk-test-login-openai-0001" && login.value("anthropic") == "sk-test-login-claude-0001")
            #expect(try KS.with(store) { try APIKeys.load(.openai, for: "api.openai.com") } == "sk-test-login-openai-0001")
            #expect(try KS.with(store) { try APIKeys.load(.anthropic, for: "api.anthropic.com") } == "sk-test-login-claude-0001")
            #expect(login.comment("anthropic") == "api.anthropic.com", "\(which): the host wasn't bound in the login keychain")
            #expect(KS.with(store) { APIKeys.source(.openai) } == APIKeys.Source.keychain)
            #expect(KS.with(store) { APIKeys.source(.gemini) } == APIKeys.Source.none, "\(which): the synced store's key was seen")
            #expect(KS.with(store) { APIKeys.keychainKey(account: "gemini") } == nil)
            #expect(APIKeys.keyEnding(account: "openai", in: store) == "0001")
            #expect(Set(store.accounts()) == ["openai", "anthropic"], "\(which): \(store.accounts())")

            try APIKeys.remove(account: "openai", in: store)
            #expect(!login.has("openai") && !replaced.has("openai"), "\(which)")
            #expect(store.read("openai") == nil)

            let touched = log.all.filter { !$0.hasPrefix("login.") && !$0.hasPrefix("replaced.") }
            #expect(touched.isEmpty, "\(which): with key sync off, the synced store was touched: \(touched)")
            #expect(synced.value("openai") == "sk-test-synced-left-0001" && synced.value("gemini") == "sk-test-synced-left-0002")
        }
    }

    /// S26 (review 4, M1a): after S22, each Mac turns key sync off and on again. The Mac whose key lost in iCloud Keychain
    /// had it only as a replaced copy: copying the winner back (round 4, 1: nothing set aside) and moving it into the
    /// synced store again (the same key, its replaced copy already there) must not write over that copy. Its key still
    /// exists, synced or replaced, and so does the other Mac's.
    @Test func s26_theLoserOfS22TurnsKeySyncOffAndOnAndItsKeyStillExists() throws {
        let keyA = "sk-test-macA-key-a111", keyB = "sk-test-macB-key-b222"
        for bWins in [true, false] {
            let which = bWins ? "iCloud kept B's" : "iCloud kept A's"
            let log = KSLog()
            let syncedA = KSStore(.synced, "syncedA", log: log), syncedB = KSStore(.synced, "syncedB", log: log)
            let loginA = KSStore(.login, "loginA", log: log), replacedA = KSStore(.replaced, "replacedA", log: log)
            let loginB = KSStore(.login, "loginB", log: log), replacedB = KSStore(.replaced, "replacedB", log: log)
            loginA.seed("openai", keyA, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100), saved: KS.t(100))
            loginB.seed("openai", keyB, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(200), saved: KS.t(200))
            _ = try KS.turnOn(loginA, synced: syncedA, replaced: replacedA)
            _ = try KS.turnOn(loginB, synced: syncedB, replaced: replacedB)
            let (winner, winnerSaved) = bWins ? (keyB, KS.t(200)) : (keyA, KS.t(100))
            for view in [syncedA, syncedB] {
                view.seed("openai", winner, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300), saved: winnerSaved)
            }
            #expect(replacedA.value("openai") == keyA && replacedB.value("openai") == keyB, "\(which): S22 didn't hold: \(log.all)")

            for (mac, own, login, synced, replaced) in [("A", keyA, loginA, syncedA, replacedA), ("B", keyB, loginB, syncedB, replacedB)] {
                // Off: the synced key copied back into the login keychain, which has none: nothing is set aside.
                let beforeOff = log.all.count
                let off = try KS.turnOff(synced, into: login, replaced: replaced)
                #expect(off.complete, "\(which), Mac \(mac): \(log.all)")
                #expect(login.value("openai") == winner, "\(which), Mac \(mac): \(log.all)")
                let offAside = log.all.dropFirst(beforeOff).filter { $0.hasPrefix("\(replaced.name).write:") }
                #expect(offAside.isEmpty, "\(which), Mac \(mac): copying back set a key aside: \(offAside)")
                #expect(replaced.value("openai") == own, "\(which), Mac \(mac): turning off wrote over its own key's copy")

                // On again: the same key as the synced one, and its replaced copy is there: the login copy just goes.
                let on = try KS.turnOn(login, synced: synced, replaced: replaced)
                #expect(on.complete, "\(which), Mac \(mac): \(log.all)")
                #expect(!login.has("openai"), "\(which), Mac \(mac): \(log.all)")
                #expect(synced.value("openai") == winner, "\(which), Mac \(mac): \(log.all)")
                #expect(replaced.value("openai") == own,
                        "\(which), Mac \(mac): its own key's replaced copy was written over by the winner: \(log.all)")
                #expect([synced, replaced].compactMap { $0.value("openai") }.contains(own),
                        "\(which), Mac \(mac): its key is nowhere on it: \(log.all)")
            }
            let everywhere = [syncedA, syncedB, loginA, loginB, replacedA, replacedB].compactMap { $0.value("openai") }
            #expect(everywhere.contains(keyA) && everywhere.contains(keyB), "\(which): \(everywhere)")
            // Turning off and on again never changed iCloud Keychain.
            #expect(syncedA.value("openai") == winner && syncedB.value("openai") == winner)
        }
    }

    /// S27 (review 4, M1b): turning key sync on writes this Mac's newer key over an older synced one, which is kept aside
    /// first; then deleting the login keychain's copy fails (the same as stopping between the copy and the delete). At
    /// the next launch's pass the login keychain still holds the key now in the synced store: the same key, its loser's
    /// replaced copy already there. That copy must survive, whether the delete still fails or now works.
    @Test func s27_aFailedLoginDeleteAfterAMoveDoesntLoseTheOldReplacedCopy() throws {
        let older = "sk-test-synced-older-0001", newer = "sk-test-login-newer-0002"
        let log = KSLog()
        let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
        synced.seed("openai", older, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(100), saved: KS.t(100))
        login.seed("openai", newer, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300), saved: KS.t(300))
        login.failDeletes(with: -25293)

        // Turning on: the newer key is written over the older one, kept aside first; the login copy can't be deleted.
        _ = try? KS.turnOn(login, synced: synced, replaced: replaced)
        #expect(synced.value("openai") == newer, "\(log.all)")
        #expect(replaced.value("openai") == older, "the overwritten synced key isn't kept aside: \(log.all)")
        #expect(login.value("openai") == newer, "the fake's delete didn't fail: \(log.all)")

        // Relaunched, the delete still failing, then working: the old replaced copy stays.
        for deleteWorks in [false, true] {
            if deleteWorks { login.failDeletes(with: nil) }
            _ = try? KS.silentPass(login, synced: synced, replaced: replaced)
            #expect(replaced.value("openai") == older,
                    "delete works \(deleteWorks): the old key's only copy was written over by the same key again: \(log.all)")
            #expect(synced.value("openai") == newer, "delete works \(deleteWorks): \(log.all)")
            let kept = [synced, login, replaced].compactMap { $0.value("openai") }
            #expect(kept.contains(older) && kept.contains(newer), "delete works \(deleteWorks): \(kept)")
        }
        #expect(!login.has("openai"), "the login copy of a moved key stayed once its delete worked: \(log.all)")
        let store = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { true })
        #expect(store.read("openai") == newer)
    }

    /// S28 (review 4, SF1): an incomplete copy-back retries only the accounts left, and a key removed on this Mac with key
    /// sync off doesn't come back, nor does another Mac's change flow into this Mac while it doesn't sync keys.
    ///
    /// The core half, through `KeySync.Stores.turn(syncing:only:)` (A18). The controller half (the `keys-synced` marker)
    /// lives in the app; it is a self-test case for the implementer, on in-memory stores and the self-test's own state
    /// directory:
    ///   1. Key sync on, the marker `done`. The synced store has openai, gemini and anthropic; the login keychain has older
    ///      gemini and anthropic that can't be read silently. Turn key sync off and apply: the copy-back is incomplete;
    ///      the marker stays and lists exactly the accounts left ("gemini", "anthropic"), by name only: no key, no ending,
    ///      no label.
    ///   2. Remove… anthropic and openai on this Mac (key sync off): anthropic is taken off the marker's list (openai
    ///      wasn't on it). Another Mac changes openai and adds a key in the synced store.
    ///   3. Apply again (a config save, a relaunch) with gemini still unreadable: the copy-back runs for the listed
    ///      accounts alone (`only: ["gemini"]`): openai, anthropic and the new key don't appear in the login keychain,
    ///      and the routed store reads none of them. The list stays "gemini".
    ///   4. Once gemini reads, apply: the retry completes and the marker is removed. Remove… of the last listed account
    ///      instead empties the list, and the marker goes too (nothing left to copy back).
    ///   5. Turning key sync on while the marker lists accounts: it becomes `moving`, and the turn on runs over every
    ///      account, as in S21.
    ///   6. Round 4, 4: with config.json unreadable (a JSON syntax error), applying does nothing: no copy-back, no move,
    ///      the routed store's switch and the marker as they were, both with key sync on and with a marker listing
    ///      accounts. Once the file reads again, it applies as the config says.
    @Test func s28_anIncompleteCopyBackRetriesOnlyTheAccountsLeft() throws {
        let log = KSLog()
        let login = KSStore(.login, log: log), synced = KSStore(.synced, log: log), replaced = KSStore(.replaced, log: log)
        synced.seed("openai", "sk-test-synced-openai-0002", label: KS.openAILabel, modified: KS.t(300), saved: KS.t(300))
        synced.seed("gemini", "sk-test-synced-gemini-0002", modified: KS.t(300), saved: KS.t(300))
        synced.seed("anthropic", "sk-test-synced-claude-0002", modified: KS.t(300), saved: KS.t(300))
        // 0.6.4 items that asked for the password and lost to another Mac's newer keys when key sync was turned on.
        login.seed("gemini", "sk-test-login-gemini-0001", modified: KS.t(100))
        login.seed("anthropic", "sk-test-login-claude-0001", modified: KS.t(100))
        login.needPassword(["gemini", "anthropic"])
        login.interactionAllowed = false  // the moves ask nothing (`quietLogin` is this same store)
        let stores = KeySync.Stores(login: login.keychain, synced: synced.keychain, replaced: replaced.keychain,
                                    syncing: true)

        // Turning key sync off: openai is copied back; gemini and anthropic can't be read, so they are left.
        let off = try stores.turn(syncing: false)
        #expect(!off.isComplete && !stores.syncing, "\(log.all)")
        #expect(login.value("openai") == "sk-test-synced-openai-0002", "\(log.all)")
        let left = Set(off.waiting).union(off.mismatched)
        #expect(left == ["gemini", "anthropic"], "the accounts left aren't the marker's list: \(off)")

        // Remove… on this Mac, key sync off: from this Mac alone (S15); the controller takes anthropic off the list.
        try APIKeys.remove(account: "openai", in: stores.store)
        try APIKeys.remove(account: "anthropic", in: stores.store)
        #expect(!login.has("openai") && !login.has("anthropic"))
        #expect(synced.has("openai") && synced.has("anthropic"), "Remove… with key sync off touched iCloud Keychain")
        let list = left.subtracting(["anthropic"])
        // Another Mac, still syncing, changes openai and adds a key.
        synced.seed("openai", "sk-test-macB-changed-0003", label: KS.openAILabel, modified: KS.t(500), saved: KS.t(500))
        let toolAccount = "extension.com.example.tool.token"
        synced.seed(toolAccount, "tok-test-macB-new-0001", modified: KS.t(500), saved: KS.t(500))

        // The retry, gemini still unreadable: only gemini is tried, and it's still left.
        let mark = log.all.count
        let still = try stores.turn(syncing: false, only: list)
        #expect(!still.isComplete && Set(still.waiting).union(still.mismatched) == ["gemini"], "\(still)")
        // The retry, gemini readable now: it completes, and only gemini was copied.
        login.needPassword(["anthropic"])
        let retry = try stores.turn(syncing: false, only: list)
        #expect(retry.isComplete, "the retry didn't complete: \(log.all)")
        #expect(login.value("gemini") == "sk-test-synced-gemini-0002", "\(log.all)")
        #expect([login, replaced].compactMap { $0.value("gemini") }.contains("sk-test-login-gemini-0001"),
                "the login keychain's older gemini key is nowhere: \(log.all)")

        let since = log.all.dropFirst(mark)
        let loginWrites = since.filter { $0.hasPrefix("login.write:") }
        #expect(loginWrites.allSatisfy { $0 == "login.write:gemini" }, "the retry copied other accounts: \(loginWrites)")
        let looked = since.filter { $0.hasPrefix("synced.read:") && $0 != "synced.read:gemini" }
        #expect(looked.isEmpty, "the retry read other accounts' synced keys: \(looked)")
        for account in ["openai", "anthropic", toolAccount] {
            #expect(!login.has(account), "\(account) came back into this Mac's login keychain: \(log.all)")
            #expect(stores.store.read(account) == nil && !APIKeys.hasKeychainKey(account: account, in: stores.store),
                    "\(account) readable on this Mac with key sync off")
        }
        // iCloud Keychain, for the other Macs, as they left it.
        #expect(synced.value("openai") == "sk-test-macB-changed-0003" && synced.value("anthropic") == "sk-test-synced-claude-0002")
        #expect(synced.writes.isEmpty && synced.deletes.isEmpty, "\(log.all)")
    }

    /// S29 (review 4, SF2): a key found only in the login keychain moves into the synced store at its first use (A3),
    /// after a read that may wait at the password prompt. Another Mac's key that arrives in the synced store meanwhile is
    /// never written over, and the login keychain's key isn't lost: both are left to the next merge, where the newest
    /// wins and the other is kept aside (A19).
    @Test func s29_aSyncedItemArrivingDuringTheFirstUseReadIsntOverwritten() throws {
        let keyA = "sk-test-macA-login-a111", keyB = "sk-test-macB-synced-b222"
        for aNewer in [false, true] {
            let which = aNewer ? "A's key newer" : "B's key newer"
            let log = KSLog()
            let login = KSStore(.login, "loginA", log: log), synced = KSStore(.synced, log: log)
            let replaced = KSStore(.replaced, "replacedA", log: log)
            // Left behind when key sync was turned on on Mac A: it asks for the password.
            login.seed("openai", keyA, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(aNewer ? 400 : 100),
                       saved: KS.t(aNewer ? 400 : 100))
            login.needPassword(["openai"])
            // While the prompt is up, Mac B's key, saved there with key sync on (B keeps no copy of it), arrives.
            login.whileAsking("openai") {
                synced.seed("openai", keyB, label: KS.openAILabel, host: "api.openai.com", modified: KS.t(300), saved: KS.t(300))
            }
            let macA = KS.routed(login: login, synced: synced, replaced: replaced, syncs: { true })

            let key = macA.read("openai")
            #expect(login.reads("openai") == 1, "\(which): the fake's prompt didn't run: \(log.all)")
            #expect(key == keyA || key == keyB, "\(which): \(String(describing: key))")
            #expect(synced.value("openai") == keyB, "\(which): the key that arrived during the prompt was written over: \(log.all)")
            #expect(synced.writes.isEmpty, "\(which): the first-use move wrote into a slot no longer empty: \(log.all)")
            #expect(login.value("openai") == keyA && login.deletes.isEmpty, "\(which): the login keychain's key is gone: \(log.all)")
            #expect(macA.read("openai") == keyB, "\(which): reads don't find the synced key first")

            // The next merge (the login item reads silently now): the newest stays synced, the other is kept aside.
            login.needPassword([])
            _ = try KS.silentPass(login, synced: synced, replaced: replaced)
            let (winner, loser) = aNewer ? (keyA, keyB) : (keyB, keyA)
            #expect(synced.value("openai") == winner, "\(which): \(log.all)")
            #expect(replaced.value("openai") == loser, "\(which): the losing key is nowhere: \(log.all)")
            #expect(!login.has("openai"), "\(which): \(log.all)")
        }
    }
}
