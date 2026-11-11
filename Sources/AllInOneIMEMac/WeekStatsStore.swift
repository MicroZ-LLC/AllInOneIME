import AllInOneIMECore
import Foundation

/// This week's stats on this Mac (`WeekStats`): the counts every text field adds to, kept in
/// ~/Library/Application Support/AllInOneIME/usage.json (`defaultURL`), readable by the user alone (0600). A file of its
/// own: not the settings' file, nothing synced through iCloud, nothing sent anywhere. A count only changes memory and
/// asks for a write (`changed`); the file is written a moment later on a queue of its own, once for the counts of a
/// while (`delay`), so no key waits for it. Read once, when the store is made.
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

    private let writes = DispatchQueue(label: "com.allinoneime.week-stats", qos: .utility)
    /// A change not written yet, and whether a write is on its way.
    private let state = Locked(initialState: (dirty: false, scheduled: false))

    /// The store in `applicationSupportDirectory`/AllInOneIME (the user's Application Support by default), its days told
    /// by `now` and `calendar`.
    public init(applicationSupportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support"),
                now: @escaping () -> Date = { Platform.current.clock.now },
                calendar: Calendar = WeekStats.defaultCalendar()) {
        fileURL = applicationSupportDirectory.appendingPathComponent("AllInOneIME/usage.json")
        stats = WeekStats(now: now, calendar: calendar)
        // What was kept (its salt with it); a file that doesn't read starts again (it's only counts).
        if let data = try? Data(contentsOf: fileURL) { try? stats.restore(from: data) }
        state.withLock { $0.dirty = false }
        stats.changed = { [weak self] in self?.scheduleWrite() }
    }

    /// The counts written now if they changed (before the app quits, and for tests), on the store's queue.
    public func flush() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            writes.async {
                do {
                    try self.writeIfChanged()
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    /// `flush`, waiting for it (the app quitting).
    public func flushNow() {
        writes.sync { try? writeIfChanged() }
    }

    /// Everything counted forgotten and the file deleted (Settings → Privacy → Learned… → Forget All).
    public func clearHistory() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            writes.async {
                self.stats.clearHistory()
                self.state.withLock { $0.dirty = false }
                do {
                    if FileManager.default.fileExists(atPath: self.fileURL.path) {
                        try FileManager.default.removeItem(at: self.fileURL)
                    }
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

    /// On `writes`.
    private func writeIfChanged() throws {
        guard state.withLock({ state -> Bool in
            defer { state.dirty = false }
            return state.dirty
        }) else { return }
        do {
            let data = try stats.serializedData()
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Platform.current.files.writePrivate(data, to: fileURL)
        } catch {
            state.withLock { $0.dirty = true }  // tried again with the next count, or when the app quits
            throw error
        }
    }
}
