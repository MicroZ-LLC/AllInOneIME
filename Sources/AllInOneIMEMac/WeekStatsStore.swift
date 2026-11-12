import AllInOneIMECore
import Foundation

/// This week's stats on this Mac (`WeekStats`): the counts every text field adds to, kept in
/// ~/Library/Application Support/AllInOneIME/usage.json (`defaultURL`), readable by the user alone (0600). A file of its
/// own: not the settings' file, nothing synced through iCloud, nothing sent anywhere. The salt the apps are hashed with
/// isn't in it: it is the input method's own keychain item, on this Mac only and never synced (`saltKeychain`); the file
/// says only which salt it was (`WeekStats.serializedData`). A count only changes memory and asks for a write
/// (`changed`); the file is written a moment later on a queue of its own, once for the counts of a while (`delay`), so
/// no key waits for it. Read once, when the store is made: a file of the first test builds is read too and written again
/// soon in this version (its salt in it until the keychain has it), one that can't be read is moved aside, never written
/// over (`setAside`). A salt the keychain has but can't read (`init`) changes none of the apps kept.
public final class WeekStatsStore: @unchecked Sendable {
    /// ~/Library/Application Support/AllInOneIME/usage.json.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME/usage.json")
    }

    /// The counts: `SessionServices.weekStats` in every field.
    public let stats: WeekStats
    public let fileURL: URL
    /// How long a write waits for more counts.
    public static let delay: TimeInterval = 2

    /// The salt's keychain item: its service and account.
    public static let saltService = "AllInOneIME week stats"
    static let saltAccount = "salt"

    /// Where this Mac's salt is kept: the input method's own item, never synced, on this Mac only. In the data protection
    /// keychain when the app is entitled to it (`APIKeys.Keychain.processIsEntitled`), else in the login keychain, never
    /// asking for the password (an item that can't be read without asking is one that can't be read: `init`).
    public static var saltKeychain: SecretStore {
        APIKeys.Keychain.processIsEntitled
            ? .dataProtection(group: KeySync.accessGroup, service: saltService, synchronizable: false)
            : .legacyKeychain(service: saltService, asking: false)
    }

    static let log = CoreLog(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")

    private let keychain: SecretStore
    /// Where the file is written, one thing at a time (internal: a test holds it, to see what waits for it).
    let writes = DispatchQueue(label: "com.allinoneime.week-stats", qos: .utility)
    /// A change not written yet, and whether a write is on its way.
    private let state = Locked(initialState: (dirty: false, scheduled: false))
    /// The salt in the keychain, as read there or last taken by it (nil: none, or one that couldn't be read); on `writes`.
    private var keptSalt: Data?
    /// The salt the keychain last refused (`keep`): logged once.
    private var refusedSalt: Data?
    /// False while usage.json is a file that couldn't be read nor moved aside (`setAside`): never written over, but by
    /// Forget All.
    private var mayWrite = true

    /// This Mac's: ~/Library/Application Support/AllInOneIME/usage.json, the salt in the keychain (`saltKeychain`).
    public convenience init() {
        self.init(applicationSupportDirectory: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support"), keychain: Self.saltKeychain)
    }

    /// A store in `applicationSupportDirectory`/AllInOneIME (tests, the self-test, the images: never the user's unless
    /// it's theirs), its days told by `now` and `calendar`, its salt kept in `keychain` (in memory by default: the user's
    /// keychain is never touched).
    public init(applicationSupportDirectory: URL, now: @escaping () -> Date = { Platform.current.clock.now },
                calendar: Calendar = WeekStats.defaultCalendar(), keychain: SecretStore = .inMemory()) {
        fileURL = applicationSupportDirectory.appendingPathComponent("AllInOneIME/usage.json")
        self.keychain = keychain
        // The salt kept, if there is one (none: a new one, and the apps counted with the one lost start again). One the
        // keychain has but couldn't read (locked, refused) isn't lost: no other is made, the apps counted with it are
        // kept as they are in the file, and none is counted this run (`WeekStats.saltUnread`).
        var salt: Data?
        var unread: Error?
        do {
            salt = try keychain.readKey(Self.saltAccount).flatMap { Data(base64Encoded: $0) }.flatMap { $0.count == 32 ? $0 : nil }
        } catch {
            unread = error
        }
        keptSalt = salt
        stats = WeekStats(now: now, calendar: calendar, salt: salt)
        if let unread {
            stats.saltUnread()
            let code = (unread as? APIKeys.KeychainError).map { "\($0.status)" } ?? String(describing: type(of: unread))
            Self.log.error("week stats: the keychain couldn't read the apps' salt (\(code)): the apps counted before are kept as they are, none is counted until the input method starts again")
        }
        // What was kept: one of an earlier version, or that carries its salt, is written again soon in this one (the
        // salt, which hashes the apps now, to the keychain first, then out of the file).
        var again = false
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                again = try stats.restore(from: Data(contentsOf: fileURL))
            } catch {
                setAside(error, day: WeekStats.key(now(), calendar: calendar))
            }
        }
        stats.changed = { [weak self] in self?.scheduleWrite() }
        if again { scheduleWrite() }
    }

    /// usage.json, which couldn't be read (`error`), moved aside as usage.json.unreadable-<day> (-2, -3 … after it when
    /// that day has one already), so that nothing is written over it: counting starts again beside it. One that can't be
    /// moved either stays as it is, and isn't written this run. Logged, nothing of what is in it.
    private func setAside(_ error: Error, day: String) {
        let folder = fileURL.deletingLastPathComponent(), name = Self.asidePrefix + day
        var (aside, number) = (folder.appendingPathComponent(name), 1)
        while FileManager.default.fileExists(atPath: aside.path) {
            number += 1
            aside = folder.appendingPathComponent("\(name)-\(number)")
        }
        let why = error is WeekStats.LaterVersion ? "a later version's" : String(describing: type(of: error))
        do {
            try FileManager.default.moveItem(at: fileURL, to: aside)
            Self.log.error("week stats: usage.json couldn't be read (\(why)): kept as \(aside.lastPathComponent), counting starts again")
        } catch {
            mayWrite = false
            Self.log.error("week stats: usage.json couldn't be read (\(why)) nor kept aside (\(String(describing: type(of: error)))): not written over, nothing counted is kept this run")
        }
    }

    /// The start of the names usage.json is kept aside as (`setAside`).
    static let asidePrefix = "usage.json.unreadable-"

    /// The counts written now if they changed (before the app quits, and for tests), on the store's queue.
    public func flush() async throws {
        try await onWrites { try self.writeIfChanged() }
    }

    /// `flush`, waiting for it (the app quitting).
    public func flushNow() {
        writes.sync { try? writeIfChanged() }
    }

    /// Everything counted forgotten (Settings → Privacy → Learned… → Forget All): in memory before this returns, so that a
    /// count after it is kept and a run that answers later isn't counted (`WeekStats.clearHistory`). Then on the store's
    /// queue, after any write before it: the file deleted, those kept aside (`setAside`) and the salt's keychain item
    /// too, or the file written with only what was counted since. What fails there is logged.
    public func forgetAll() {
        stats.clearHistory()
        writes.async { [self] in
            do {
                try writeIfChanged(forgetting: true)
            } catch {
                Self.log.error("week stats: usage.json couldn't be deleted or written after Forget All (\(String(describing: type(of: error))))")
            }
        }
    }

    /// `forgetAll`, waiting for its file: throws when it couldn't be deleted or written then.
    public func clearHistory() async throws {
        forgetAll()
        try await flush()
    }

    private func onWrites(_ body: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            writes.async {
                do {
                    try body()
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    private func scheduleWrite() {
        let start = state.withLock { state -> Bool in
            state.dirty = true
            defer { state.scheduled = true }
            return !state.scheduled
        }
        guard start else { return }
        writes.asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            guard let self else { return }
            self.state.withLock { $0.scheduled = false }
            try? self.writeIfChanged()
        }
    }

    /// On `writes`: what is counted now, if it changed since the last write (`forgetting`, Forget All's: in any case).
    /// Nothing counted: no file and no salt kept. The salt goes to the keychain before the file is written: one the file
    /// carries (a file of version 1's) leaves it once the keychain has it, not before.
    private func writeIfChanged(forgetting: Bool = false) throws {
        guard state.withLock({ state -> Bool in
            defer { state.dirty = false }
            return state.dirty
        }) || forgetting else { return }
        guard mayWrite || forgetting else { return }
        do {
            let (kept, salt) = try stats.kept()
            if forgetting {
                mayWrite = true
                removeSetAside()
            }
            guard var data = kept else {
                // The salt first: the file goes even when the keychain keeps it.
                forgetSalt(always: forgetting)
                if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
                return
            }
            if let salt {
                if keptSalt != salt { keep(salt) }
                if keptSalt == salt, stats.keptApart(salt), let without = try stats.kept().data { data = without }
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Platform.current.files.writePrivate(data, to: fileURL)
        } catch {
            state.withLock { $0.dirty = true }  // tried again with the next count, or when the app quits
            throw error
        }
    }

    /// On `writes`: `salt` given to the keychain, in place of the one there (`keptSalt` once it took it; else tried again
    /// with the next write). One it refuses is logged once, and the apps aren't counted for the rest of the run
    /// (`WeekStats.countsApps`): no later run could read their hashes back (a salt the file carries stays in it,
    /// `writeIfChanged`). The one there before hashes nothing counted now: it goes then (Forget All forgot it).
    private func keep(_ salt: Data) {
        let status = keychain.write(Self.saltAccount, salt.base64EncodedString(), Self.saltService,
                                    "The salt of this Mac's week stats (apps are counted as its hashes); never synced", nil, nil)
        guard status != .ok else {
            keptSalt = salt
            return
        }
        stats.countsApps = false
        if refusedSalt != salt {
            refusedSalt = salt
            Self.log.error("week stats: the keychain didn't keep the apps' salt (\(status.code)): the apps aren't counted until the input method starts again")
        }
        forgetSalt(always: false)
    }

    /// On `writes`: the salt's keychain item deleted (one is known to be there, or `always`: Forget All). One the keychain
    /// keeps is logged, and deleted with the next write that keeps none.
    private func forgetSalt(always: Bool) {
        guard keptSalt != nil || always else { return }
        let status = keychain.delete(Self.saltAccount)
        if status == .ok || status == .notFound {
            keptSalt = nil
        } else {
            Self.log.error("week stats: the keychain didn't delete the apps' salt (\(status.code))")
        }
    }

    /// On `writes`: the files usage.json was kept aside as (`setAside`) deleted (Forget All).
    private func removeSetAside() {
        let folder = fileURL.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix(Self.asidePrefix) {
            do {
                try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            } catch {
                Self.log.error("week stats: \(name) couldn't be deleted (\(String(describing: type(of: error))))")
            }
        }
    }
}
