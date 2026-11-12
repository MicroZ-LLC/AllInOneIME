import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac

/// What `WeekStatsStore` keeps where: the salt in the keychain (here one in memory), never in usage.json, Forget All
/// ordered with the counts around it (none lost, none left unwritten), a file of an earlier version read with every count
/// and one that can't be read kept aside, and a keychain that won't keep or delete the salt.
@Suite(.serialized)
struct WeekStatsStoreKeepingTests {
    private static func calendar() -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        result.firstWeekday = 2
        return result
    }

    private static let instant = calendar().date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!

    private static func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("week-stats-keeping-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func store(_ root: URL, _ keychain: SecretStore) -> WeekStatsStore {
        WeekStatsStore(applicationSupportDirectory: root, now: { instant }, calendar: calendar(), keychain: keychain)
    }

    /// A keychain in memory that refuses to write (`refusesWrites`) or delete (`refusesDeletes`) while told to.
    private final class Refusing: @unchecked Sendable {
        var refusesWrites = false
        var refusesDeletes = false
        private(set) var keychain = APIKeys.Keychain.inMemory()

        init() {
            let (write, delete) = (keychain.write, keychain.delete)
            keychain.write = { [unowned self] account, key, label, comment, ending, saved in
                refusesWrites ? .failed(-25308) : write(account, key, label, comment, ending, saved)
            }
            keychain.delete = { [unowned self] account in refusesDeletes ? .failed(-25244) : delete(account) }
        }
    }

    /// The week stats' log lines `body` makes.
    private static func logged(_ body: () async throws -> Void) async rethrows -> [String] {
        let heard = Locked<[String]>(initialState: [])
        let stop = CoreLog.listen { message in
            if message.hasPrefix("week stats:") { heard.withLock { $0.append(message) } }
        }
        defer { stop() }
        try await body()
        return heard.withLock { $0 }
    }

    /// The salt goes to the keychain (its own item), the file has only the hashes; a store made again with the keychain
    /// counts the same apps as before, one whose salt is gone starts the apps again and keeps the rest. Forget All deletes
    /// the file and the salt.
    @Test func theSaltIsInTheKeychainNeverInTheFile() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = APIKeys.Keychain.inMemory()
        let store = Self.store(root, keychain)
        store.stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.private.editor", usedAI: true)
        try await store.flush()

        let kept = try #require(keychain.read(WeekStatsStore.saltAccount))
        #expect(Data(base64Encoded: kept) == store.stats.salt)
        let file = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!file.contains(kept))
        #expect(!file.contains("\"salt\""))
        #expect(!file.contains("com.private.editor"))

        let again = Self.store(root, keychain)
        #expect(again.stats.salt == store.stats.salt)
        #expect(again.stats.snapshot(for: .current).distinctAppCount == 1, "the apps' hashes read back, by the same salt")

        let lost = Self.store(root, .inMemory())
        #expect(lost.stats.snapshot(for: .current).distinctAppCount == 0, "the salt gone: the apps start again")
        #expect(lost.stats.snapshot(for: .current).commandCount == 1)

        try await store.clearHistory()
        #expect(keychain.read(WeekStatsStore.saltAccount) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    /// Forget All while the store's queue is busy: it forgets at once, so a count made just after it (another field) is
    /// kept, and written with the clearing's own write, without waiting for another count.
    @Test func aCountJustAfterForgetAllIsKeptAndWritten() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = APIKeys.Keychain.inMemory()
        let store = Self.store(root, keychain)
        store.stats.recordCommand(id: "before", source: .builtIn, bundleID: "com.example.a", usedAI: false)
        try await store.flush()

        store.writes.suspend()  // a write under way
        let clearing = Task { try await store.clearHistory() }
        let deadline = Date().addingTimeInterval(5)
        while store.stats.snapshot(for: .current).commandCount > 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(store.stats.snapshot(for: .current).commandCount == 0, "forgotten when asked, not when the queue gets to it")
        store.stats.recordCommand(id: "after", source: .builtIn, bundleID: "com.example.b", usedAI: false)
        store.writes.resume()
        try await clearing.value

        #expect(store.stats.snapshot(for: .current).topCommands.map(\.id) == ["after"])
        let file = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(file.contains("after") && !file.contains("before"), "written by the clearing, no other count needed")
        #expect(Self.store(root, keychain).stats.snapshot(for: .current).topCommands.map(\.id) == ["after"])
        #expect(Self.store(root, keychain).stats.snapshot(for: .current).distinctAppCount == 1)
    }

    // MARK: Forget All at the click

    /// Forget All forgets in memory before it returns (the click), and queues the file: a count between the click and
    /// that work (the queue busy) is kept, and written by it under the new salt; the one before is gone.
    @Test func forgetAllForgetsAtTheClickAndACountBeforeItsFileIsKept() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = APIKeys.Keychain.inMemory()
        let store = Self.store(root, keychain)
        store.stats.recordCommand(id: "before", source: .builtIn, bundleID: "com.example.a", usedAI: false)
        try await store.flush()
        let oldSalt = store.stats.salt

        store.writes.suspend()  // a write under way
        store.forgetAll()
        #expect(store.stats.snapshot(for: .current).commandCount == 0, "forgotten at the click, nothing awaited")
        #expect(store.stats.salt != oldSalt)
        store.stats.recordCommand(id: "after", source: .builtIn, bundleID: "com.example.b", usedAI: false)
        store.writes.resume()
        try await store.flush()

        let file = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(file.contains("after") && !file.contains("before"))
        #expect(keychain.read(WeekStatsStore.saltAccount).flatMap { Data(base64Encoded: $0) } == store.stats.salt)
        let again = Self.store(root, keychain).stats.snapshot(for: .current)
        #expect(again.topCommands.map(\.id) == ["after"])
        #expect(again.distinctAppCount == 1)
    }

    // MARK: Files of other versions, and those that can't be read

    /// usage.json of 0.7.4's first builds (each command's source with its runs, the salt in the file): every count is
    /// read, the apps by its salt; written again soon in this version, the salt goes to the keychain and leaves the file,
    /// and a store made again reads the same.
    @Test func aFileOfTheFirstBuildsKeepsItsCountsAndItsSaltMovesToTheKeychain() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let salt = Data((0..<32).map { UInt8(255 - $0) })
        let probe = WeekStats(now: { Self.instant }, calendar: Self.calendar(), salt: salt)
        probe.recordCommand(id: "x", source: .builtIn, bundleID: "com.example.editor", usedAI: false)
        let probed = try #require(JSONSerialization.jsonObject(with: probe.serializedData()) as? [String: Any])
        let app = try #require(((probed["days"] as? [String: [String: Any]])?["2026-11-10"]?["apps"] as? [String])?.first)
        let file = root.appendingPathComponent("AllInOneIME/usage.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"days":{"2026-11-09":{"apps":["\(app)"],"charactersTyped":40,"clipboardPastes":2,\
        "commands":{"bar":{"ai":0,"runs":1,"source":"plugin"},"foo":{"ai":1,"runs":3,"source":"own"}}}},\
        "salt":"\(salt.base64EncodedString())","since":"2026-11-09","version":1}
        """.utf8).write(to: file)

        let keychain = APIKeys.Keychain.inMemory()
        let store = Self.store(root, keychain)
        let week = store.stats.snapshot(for: .current)
        #expect(week.commandCount == 4)
        #expect(week.topCommands.map { "\($0.id)/\($0.source)/\($0.count)" } == ["foo/own/3", "bar/plugin/1"])
        #expect(week.aiCommandCount == 1)
        #expect(week.distinctAppCount == 1)
        #expect(week.clipboardPasteCount == 2 && week.charactersTyped == 40)
        #expect(store.stats.salt == salt)

        try await store.flush()  // written again, without waiting for a count
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(!written.contains("\"salt\"") && !written.contains(salt.base64EncodedString()))
        #expect(written.contains("\"version\":2"))
        #expect(keychain.read(WeekStatsStore.saltAccount).flatMap { Data(base64Encoded: $0) } == salt)
        let again = Self.store(root, keychain)
        #expect(again.stats.snapshot(for: .current) == week)
        again.stats.recordCommand(id: "foo", source: .own, bundleID: "com.example.editor", usedAI: false)
        #expect(again.stats.snapshot(for: .current).distinctAppCount == 1, "the same app")
    }

    /// usage.json that can't be read (broken, or a later version's) is moved aside as usage.json.unreadable-<day>, as it
    /// was, and the log says so; counting starts again in a new usage.json, never over it. Forget All deletes those too.
    @Test func aFileThatCantBeReadIsKeptAsideNeverWrittenOver() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("AllInOneIME")
        let file = folder.appendingPathComponent("usage.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let broken = Data(#"{"version":2,"days":{"2026-11-10":{"commands":7}}}"#.utf8)
        let later = Data(#"{"version":3,"days":{"2026-11-10":{"commands":{"own":{"sig":{"runs":5,"ai":0}}}}}}"#.utf8)
        let keychain = APIKeys.Keychain.inMemory()

        try broken.write(to: file)
        var store: WeekStatsStore?
        let heard = await Self.logged { store = Self.store(root, keychain) }
        let first = folder.appendingPathComponent("usage.json.unreadable-2026-11-10")
        #expect(try Data(contentsOf: first) == broken)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(heard.contains { $0.contains("couldn't be read") && $0.contains("usage.json.unreadable-2026-11-10") }, "\(heard)")
        let counting = try #require(store)
        #expect(counting.stats.snapshot(for: .current).commandCount == 0)
        counting.stats.recordCommand(id: "improve", source: .builtIn, bundleID: nil, usedAI: true)
        try await counting.flush()
        #expect(try String(contentsOf: file, encoding: .utf8).contains("improve"))
        #expect(try Data(contentsOf: first) == broken)

        try later.write(to: file)
        let heardLater = await Self.logged { store = Self.store(root, keychain) }
        let second = folder.appendingPathComponent("usage.json.unreadable-2026-11-10-2")
        #expect(try Data(contentsOf: second) == later)
        #expect(heardLater.contains { $0.contains("a later version's") && $0.contains("usage.json.unreadable-2026-11-10-2") }, "\(heardLater)")

        try await #require(store).clearHistory()
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left.isEmpty, "\(left)")
    }

    // MARK: A keychain that won't keep or delete the salt

    /// The keychain refuses the salt: the log says so, the apps aren't counted for the rest of the run (no later run could
    /// read their hashes), the commands are, and the file is written. The salt isn't taken as kept: the next write gives
    /// it again, and once the keychain takes it, a store made again reads the apps counted before.
    @Test func aSaltTheKeychainRefusesCountsNoMoreAppsAndIsTriedAgain() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let refusing = Refusing()
        refusing.refusesWrites = true
        let store = Self.store(root, refusing.keychain)
        store.stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.a", usedAI: true)
        let heard = try await Self.logged { try await store.flush() }
        #expect(heard.contains { $0.contains("didn't keep the apps' salt") && $0.contains("-25308") }, "\(heard)")
        #expect(refusing.keychain.read(WeekStatsStore.saltAccount) == nil)
        #expect(!store.stats.countsApps)
        store.stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.b", usedAI: true)
        #expect(store.stats.snapshot(for: .current).distinctAppCount == 1, "no app counted once the salt can't be kept")
        #expect(store.stats.snapshot(for: .current).commandCount == 2)
        let heardAgain = try await Self.logged { try await store.flush() }
        #expect(heardAgain.isEmpty, "logged once: \(heardAgain)")
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8).contains("improve"))

        refusing.refusesWrites = false
        store.stats.recordCommand(id: "sig", source: .own, bundleID: "com.example.c", usedAI: false)
        try await store.flush()
        #expect(refusing.keychain.read(WeekStatsStore.saltAccount).flatMap { Data(base64Encoded: $0) } == store.stats.salt)
        #expect(!store.stats.countsApps, "for the rest of the run")
        let again = Self.store(root, refusing.keychain).stats.snapshot(for: .current)
        #expect(again.commandCount == 3)
        #expect(again.distinctAppCount == 1)
    }

    /// Forget All, then a count before its file work, and the keychain refuses the new salt: the old one is deleted all
    /// the same (it hashes nothing kept), and the log says so.
    @Test func forgetAllLeavesNoOldSaltWhenTheNewOneIsRefused() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let refusing = Refusing()
        let store = Self.store(root, refusing.keychain)
        store.stats.recordCommand(id: "before", source: .builtIn, bundleID: "com.example.a", usedAI: false)
        try await store.flush()
        #expect(refusing.keychain.read(WeekStatsStore.saltAccount) != nil)

        refusing.refusesWrites = true
        store.writes.suspend()
        store.forgetAll()
        store.stats.recordCommand(id: "after", source: .builtIn, bundleID: "com.example.b", usedAI: false)
        store.writes.resume()
        let heard = try await Self.logged { try await store.flush() }
        #expect(heard.contains { $0.contains("didn't keep the apps' salt") }, "\(heard)")
        #expect(refusing.keychain.read(WeekStatsStore.saltAccount) == nil, "the old salt is gone")
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8).contains("after"))
    }

    /// The keychain won't delete the salt at Forget All: usage.json is deleted all the same, the log says so, and the
    /// next Forget All deletes the salt once the keychain lets it.
    @Test func aSaltTheKeychainWontDeleteIsLoggedAndTheFileGoesAllTheSame() async throws {
        let root = try Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let refusing = Refusing()
        let store = Self.store(root, refusing.keychain)
        store.stats.recordCommand(id: "improve", source: .builtIn, bundleID: "com.example.a", usedAI: true)
        try await store.flush()

        refusing.refusesDeletes = true
        let heard = try await Self.logged { try await store.clearHistory() }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(heard.contains { $0.contains("didn't delete the apps' salt") && $0.contains("-25244") }, "\(heard)")
        #expect(refusing.keychain.read(WeekStatsStore.saltAccount) != nil)

        refusing.refusesDeletes = false
        try await store.clearHistory()
        #expect(refusing.keychain.read(WeekStatsStore.saltAccount) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
