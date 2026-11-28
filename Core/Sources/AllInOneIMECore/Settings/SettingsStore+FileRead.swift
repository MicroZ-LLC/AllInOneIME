import Foundation

extension SettingsStore {
    /// The config file read away from the store's thread, for a store whose thread may not wait for a file (the Mac's
    /// window: the main thread, which typing in every app waits for). Made on any thread, given to the store on its own
    /// (`reloadIfChanged(_:)`).
    public struct FileRead: Sendable {
        let date: Date?
        /// The store's `fileDate` the read started from: taken only while the store's is still that one.
        let since: Date?
        let exists: Bool
        let config: Result<Config, Error>

        /// The file at `url` read now, on the caller's thread; nil: its date is still `date` (the store's `fileDate`),
        /// so nothing changed it and nothing is read.
        public init?(_ url: URL, since date: Date?) {
            let now = SettingsStore.modificationDate(url)
            guard now != date else { return nil }
            self.date = now
            since = date
            exists = FileManager.default.fileExists(atPath: url.path)
            config = Result { try Config.load(from: url) }
        }
    }

    /// `reloadIfChanged()` with the file read elsewhere (`FileRead`): shown only while the store's `fileDate` is still
    /// the one the read started from. The store read or wrote the file meanwhile (a save, another read arrived first,
    /// newer or not), the read is dropped: an older file never replaces what the store has since. Whether anything was
    /// taken.
    @discardableResult
    public func reloadIfChanged(_ read: FileRead) -> Bool {
        guard persists, read.since == fileDate, read.date != fileDate else { return false }
        // No file: a new user's settings where the store has them (`fresh`), as `reloadIfChanged()` reads one.
        took(read.exists ? read.config : fresh.map { .success($0()) } ?? read.config, dated: read.date)
        return true
    }
}
