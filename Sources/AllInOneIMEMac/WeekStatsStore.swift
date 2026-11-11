import AllInOneIMECore
import Foundation

/// This week's stats on this Mac (`WeekStats`): the counts every text field adds to, kept in
/// ~/Library/Application Support/AllInOneIME/usage.json (`defaultURL`), readable by the user alone (0600). A file of its
/// own: not the settings' file, nothing synced through iCloud, nothing sent anywhere. The salt the apps are hashed with
/// isn't in it: it is the input method's own keychain item, on this Mac only and never synced (`saltKeychain`); the file
/// says only which salt it was (`WeekStats.serializedData`). A count only changes memory and asks for a write
/// (`changed`); the file is written a moment later on a queue of its own, once for the counts of a while (`delay`), so
/// no key waits for it. Read once, when the store is made.
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
    /// asking for the password (an item that can't be read without asking is as none: a new salt then).
    public static var saltKeychain: SecretStore {
        APIKeys.Keychain.processIsEntitled
            ? .dataProtection(group: KeySync.accessGroup, service: saltService, synchronizable: false)
            : .legacyKeychain(service: saltService, asking: false)
    }

    private let keychain: SecretStore
    /// Where the file is written, one thing at a time (internal: a test holds it, to see what waits for it).
    let writes = DispatchQueue(label: "com.allinoneime.week-stats", qos: .utility)
    /// A change not written yet, and whether a write is on its way.
    private let state = Locked(initialState: (dirty: false, scheduled: false))
    /// The salt last given to the keychain (nil: none there); on `writes`.
    private var keptSalt: Data?

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
        // The salt kept, if there is one (none: a new one, and the apps counted with the one lost start again).
        let salt = keychain.read(Self.saltAccount).flatMap { Data(base64Encoded: $0) }.flatMap { $0.count == 32 ? $0 : nil }
        keptSalt = salt
        stats = WeekStats(now: now, calendar: calendar, salt: salt)
        // What was kept; a file that doesn't read starts again (it's only counts).
        if let data = try? Data(contentsOf: fileURL) { try? stats.restore(from: data) }
        stats.changed = { [weak self] in self?.scheduleWrite() }
    }

    /// The counts written now if they changed (before the app quits, and for tests), on the store's queue.
    public func flush() async throws {
        try await onWrites { try self.writeIfChanged() }
    }

    /// `flush`, waiting for it (the app quitting).
    public func flushNow() {
        writes.sync { try? writeIfChanged() }
    }

    /// Everything counted forgotten (Settings → Privacy → Learned… → Forget All): in memory at once, so that a count
    /// after it is kept and a run that answers later isn't counted (`WeekStats.clearHistory`); then, after any write
    /// before it, the file and the salt's keychain item deleted (or the file written with only what was counted since).
    public func clearHistory() async throws {
        stats.clearHistory()
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

    /// On `writes`: what is counted now, if it changed since the last write. Nothing counted: no file and no salt kept.
    private func writeIfChanged() throws {
        guard state.withLock({ state -> Bool in
            defer { state.dirty = false }
            return state.dirty
        }) else { return }
        do {
            let (data, salt) = try stats.kept()
            guard let data else {
                if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
                if keptSalt != nil {
                    _ = keychain.delete(Self.saltAccount)
                    keptSalt = nil
                }
                return
            }
            if keptSalt != salt {
                // Tried once for each salt: one that can't be kept is this run's alone.
                keptSalt = salt
                _ = keychain.write(Self.saltAccount, salt.base64EncodedString(), Self.saltService,
                                   "The salt of this Mac's week stats (apps are counted as its hashes); never synced", nil, nil)
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Platform.current.files.writePrivate(data, to: fileURL)
        } catch {
            state.withLock { $0.dirty = true }  // tried again with the next count, or when the app quits
            throw error
        }
    }
}
