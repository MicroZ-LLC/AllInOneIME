import AllInOneIMECore
import Foundation

extension ICloudSyncController {
    /// Marks that this Mac's keys may be in iCloud Keychain (absent: they were last all in the login keychain), beside
    /// the sync record, so the self-test's is its own: written "moving" before turning key sync on moves anything, "done"
    /// once every key moved, and the accounts left when turning it off didn't copy every key back (`KeySync.Marker`).
    var keysSyncedURL: URL { KeySync.Marker.url(besides: engine.stateURL) }

    /// What the keys-synced marker says: nil when there is none. A marker of an earlier build (empty) is `done`.
    typealias KeysSynced = KeySync.Marker

    var keysSynced: KeysSynced? { KeySync.Marker.read(at: keysSyncedURL) }

    /// The marker's file changed only under this lock: Remove… (`dropFromCopyBack`) may come from any thread.
    private nonisolated static let markerLock = NSLock()

    /// The marker at `url` set (nil: removed); false when it couldn't be written.
    @discardableResult
    private nonisolated static func markKeysSynced(_ state: KeysSynced?, at url: URL) -> Bool {
        markerLock.withLock { writeMarker(state, at: url) }
    }

    private nonisolated static func writeMarker(_ state: KeysSynced?, at url: URL) -> Bool {
        let fm = FileManager.default
        guard let state else {
            try? fm.removeItem(at: url)
            return true
        }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(state.text.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            log.error("keys-synced marker not written: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// A copy-back that left `remaining`: the marker (the list it started from) lists those alone, but never one taken
    /// off the list meanwhile (`dropFromCopyBack`; the marker gone: all of them were). When this can't be written, the
    /// list before stays: it has these accounts too.
    nonisolated static func narrowCopyBack(to remaining: [String], at url: URL) {
        markerLock.withLock {
            guard case let .copyingBack(listed)? = KeySync.Marker.read(at: url) else { return }
            let left = remaining.filter(listed.contains)
            _ = writeMarker(left.isEmpty ? nil : .copyingBack(left), at: url)
        }
    }

    /// Remove… took `account` off this Mac, or a save wrote it here, while key sync was off: off the accounts the
    /// copy-back still has to copy, so that the retry doesn't bring the removed key back, nor write iCloud Keychain's
    /// over the one saved here (the marker goes with the last one).
    nonisolated static func dropFromCopyBack(_ account: String, at url: URL) {
        markerLock.withLock {
            guard case let .copyingBack(accounts)? = KeySync.Marker.read(at: url), accounts.contains(account) else { return }
            let left = accounts.filter { $0 != account }
            _ = writeMarker(left.isEmpty ? nil : .copyingBack(left), at: url)
        }
    }

    /// API keys and passwords through iCloud Keychain as the config says (`ICloudSyncSettings.syncsKeys`), when it changed
    /// (in Settings, through the Assistant, while the input method wasn't running): turned on, the login keychain's keys
    /// move into iCloud Keychain; turned off, the synced ones are copied back into the login keychain and left in iCloud
    /// Keychain for the other Macs (`KeySync.Stores.turn`). The marker (`keysSynced`) says "moving" before turning on
    /// moves a key (nothing moves when it can't be written), and "done" once every key moved; turning off copies the
    /// synced keys back whenever there is a marker, even one left "moving" (keys moved before a move stopped are in iCloud
    /// Keychain alone), and removes it only once every key is copied. Before a copy-back that starts from "moving" or
    /// "done" copies a key, the marker lists every synced account ("copying back", `KeySync.Stores.listCopyBack`); when
    /// that list can't be made or written, nothing is copied back (the routing as it was), to be tried again on the next
    /// run. A move that failed, or left a key behind (one that couldn't be read, whose copy didn't read back as written,
    /// whose replaced copy couldn't be kept, or that would have gone over a key that couldn't be read), is tried again on
    /// the next run; a copy-back that throws midway keeps its list, and one that left keys behind lists their accounts:
    /// it is tried again for the listed accounts alone (Remove… or a save on this Mac takes one off the list). At launch
    /// (`atLaunch`) with key sync on, the move is made even when the marker says "done": a key left behind for its first
    /// use, or one an earlier version saved in the login keychain since, moves then. When the config can't be read (a
    /// typo while editing it by hand), nothing changes: no move, no copy-back, the routing as it was.
    func applyKeySync(atLaunch: Bool = false) {
        guard let keys else { return }
        Self.applyKeySync(keys, configURL: engine.configURL, markerURL: keysSyncedURL, atLaunch: atLaunch)
    }

    /// `applyKeySync` on the sync queue (`queue`), ahead of the run it is asked with: the keychain and the config file are
    /// never waited on on the main thread, where typing is.
    func keySyncOnQueue(atLaunch: Bool = false) {
        guard let keys else { return }
        let (configURL, markerURL) = (engine.configURL, keysSyncedURL)
        queue.async { Self.applyKeySync(keys, configURL: configURL, markerURL: markerURL, atLaunch: atLaunch) }
    }

    /// `applyKeySync` with `keys`, the config file at `configURL` and the marker at `markerURL`: any thread.
    private nonisolated static func applyKeySync(_ keys: KeySync.Stores, configURL: URL, markerURL url: URL, atLaunch: Bool) {
        keys.whenRemovedHere { account in Self.dropFromCopyBack(account, at: url) }
        guard let config = try? Config.load(from: configURL) else {
            log.error("keys left as they are: the config can't be read")
            return
        }
        let wanted = config.iCloudSync.syncsKeys
        let marker = KeySync.Marker.read(at: url)
        guard wanted ? marker != .done || atLaunch : marker != nil else {
            if keys.syncing != wanted { keys.start(syncing: wanted) }
            return
        }
        if wanted, !markKeysSynced(.moving, at: url) { return }
        var only: Set<String>?
        if !wanted {
            if case let .copyingBack(accounts)? = marker {
                only = Set(accounts)
            } else {
                // From "moving" or "done": every synced account listed before any is copied back, so that one copied
                // before the copy-back throws, then removed here, isn't copied back again by the retry.
                let accounts: [String]
                do {
                    accounts = try keys.listCopyBack()
                } catch {
                    log.error("keys not copied back out of iCloud Keychain, tried again later: its keys can't be listed: \(String(describing: error), privacy: .public)")
                    return
                }
                guard markKeysSynced(.copyingBack(accounts), at: url) else { return }
                only = Set(accounts)
            }
        }
        do {
            let moves = try keys.turn(syncing: wanted, only: only)
            guard moves.isComplete else {
                if !wanted { Self.narrowCopyBack(to: moves.remaining, at: url) }
                log.error("keys not all moved \(wanted ? "into" : "out of", privacy: .public) iCloud Keychain, tried again later: \(moves.waiting.count) unreadable, \(moves.mismatched.count) left as they were")
                return
            }
            markKeysSynced(wanted ? .done : nil, at: url)
            log.notice("keys \(wanted ? "sync through iCloud Keychain" : "stay in the login keychain", privacy: .public): \(moves.moved.count) moved, \(moves.superseded.count) newer already, \(moves.setAside.count) replaced copies kept")
        } catch {
            log.error("keys not moved \(wanted ? "into" : "out of", privacy: .public) iCloud Keychain: \(String(describing: error), privacy: .public)")
        }
    }
}
