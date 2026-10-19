import AllInOneIMECore
import Foundation

/// The installed plugins (`PluginStore.load`: each plugin's manifest read, the files of a library plugin hashed) as the
/// sessions take them each time a field takes the focus, which on Windows is often: read again only when the plugins
/// folder changed (its modification date, one look at it: a plugin installed, removed or renamed), as `EngineSettings`
/// reads `config.json`; and, in the background, once what was read is `maxAge` old (a plugin's files edited where they
/// are, which leaves the folder's date as it was), as the Mac's `LivePlugins` does every 30 seconds. So a focus reads
/// no plugin's files on the session's queue, but the first and those after a change.
public final class PluginCatalog: @unchecked Sendable {
    public let directory: URL
    public let maxAge: TimeInterval
    /// How long after its last change the folder's date is trusted: it moves with the system's clock, in steps of up to
    /// 16 ms on Windows, so a change in the same step as a read leaves it as it was. A folder read sooner after a change
    /// is read again the next time (git's "racily clean" files).
    public let settleTime: TimeInterval
    private let load: @Sendable () -> [InstalledPlugin]
    private let lock = NSLock()
    private var cached: (date: Date?, settled: Bool, at: Date, plugins: [InstalledPlugin])?
    private var refreshing = false

    public init(directory: URL = PluginStore.directory, maxAge: TimeInterval = 30, settleTime: TimeInterval = 1,
                load: (@Sendable () -> [InstalledPlugin])? = nil) {
        self.directory = directory
        self.maxAge = maxAge
        self.settleTime = settleTime
        self.load = load ?? { PluginStore.load(from: directory).plugins }
    }

    /// The plugins as of the folder's last change.
    public var current: [InstalledPlugin] {
        let date = modificationDate
        lock.lock()
        if let cached, cached.settled, cached.date == date {
            if Date().timeIntervalSince(cached.at) >= maxAge, !refreshing {
                refreshing = true
                DispatchQueue.global(qos: .utility).async { [self] in
                    let date = modificationDate
                    let plugins = load()
                    lock.lock()
                    keep(plugins, date: date)
                    refreshing = false
                    lock.unlock()
                }
            }
            lock.unlock()
            return cached.plugins
        }
        lock.unlock()
        let plugins = load()
        lock.lock()
        keep(plugins, date: date)
        lock.unlock()
        return plugins
    }

    /// `plugins`, read when the folder's date was `date`. With the lock held.
    private func keep(_ plugins: [InstalledPlugin], date: Date?) {
        let now = Date()
        cached = (date, date.map { now.timeIntervalSince($0) >= settleTime } ?? true, now, plugins)
    }

    /// The folder's modification date; nil while there is none.
    private var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: directory.path))?[.modificationDate] as? Date
    }
}
