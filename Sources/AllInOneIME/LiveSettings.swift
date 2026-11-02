import AllInOneIMECore
import Foundation

/// The installed plugins, scanned again when a text field becomes active (installing or removing one
/// shows up there: `rescan(scanned:)`) and at most every 30 seconds otherwise: then in the background, never
/// while a key is handled or a field takes the focus (they get the plugins as last scanned). Main thread only.
enum LivePlugins {
    private static var cached: (at: Date, result: (plugins: [InstalledPlugin], skipped: [PluginStore.Skipped]))?
    private static var scanning = false
    /// A scan wanted while one goes on (it may have started before what changed): one more after it; and what waits for
    /// the scans wanted to be in.
    private static var scanAgain = false
    private static var waiting: [() -> Void] = []

    /// The plugins as last scanned (none scanned yet: none, until the scan started then is in). `rescan`: scanned now,
    /// on this thread (the settings window, which shows what is there at once).
    static func current(rescan: Bool = false) -> [InstalledPlugin] {
        guard rescan else {
            if cached.map({ Date().timeIntervalSince($0.at) >= 30 }) ?? true { scanInBackground() }
            return cached?.result.plugins ?? []
        }
        let result = PluginStore.load()
        cached = (Date(), result)
        found(result.plugins)
        return result.plugins
    }

    /// Scanned again in the background (a text field became active): `scanned`, on the main thread, once a scan that
    /// started after this is in (`current()` gives what it found).
    static func rescan(scanned: @escaping () -> Void) {
        waiting.append(scanned)
        if scanning { scanAgain = true } else { scanInBackground() }
    }

    private static func scanInBackground() {
        guard !scanning else { return }
        scanning = true
        let started = Date()
        DispatchQueue.global(qos: .utility).async {
            let result = PluginStore.load()
            DispatchQueue.main.async {
                // Unless the settings scanned meanwhile (`current(rescan: true)`): theirs is as new.
                if (cached?.at ?? .distantPast) < started {
                    cached = (Date(), result)
                    found(result.plugins)
                }
                scanning = false
                if scanAgain {
                    scanAgain = false
                    scanInBackground()
                    return
                }
                let done = waiting
                waiting = []
                done.forEach { $0() }
            }
        }
    }

    /// Told the plugins each scan finds, on the main thread: the input method's `SuggestionsShared.pluginsFound` (one
    /// found here for the first time has its completion sources turned on); nothing by default.
    static var found: ([InstalledPlugin]) -> Void = { _ in }
}

/// How much each @ command is used (the order of the command list), shared by every text field and kept
/// across launches.
enum CommandUsageStore {
    private static let key = "commandUsage"
    static var usage: CommandUsage = {
        // 0.6.4: @claude is @agent now. Once (also with nothing kept yet): a command of the user's own may be named
        // "claude" afterwards.
        let renamed = UserDefaults.standard.bool(forKey: renamedKey)
        UserDefaults.standard.set(true, forKey: renamedKey)
        guard let data = UserDefaults.standard.data(forKey: key),
              var usage = try? JSONDecoder().decode(CommandUsage.self, from: data) else { return CommandUsage() }
        if !renamed {
            usage.migrateRenamed(from: "claude", to: "agent")
            if let data = try? JSONEncoder().encode(usage) { UserDefaults.standard.set(data, forKey: key) }
        }
        return usage
    }()
    private static let renamedKey = "commandUsageRenamedClaudeToAgent"

    static func save(_ new: CommandUsage) {
        usage = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// The config file as of now, re-read only when it changed (checked by modification date).
/// A file that doesn't parse reads as the defaults here; conversions report the error.
enum LiveConfig {
    private static var cached: (url: URL, date: Date?, config: Config?)?

    /// The config, or the defaults while the file doesn't parse (a comma left in TextEdit): what typing goes by, which a
    /// broken file mustn't stop. Never what deletes, trims or starts recording anything (clipboard history, the cached
    /// lists of suggestions): the defaults aren't the user's settings (a limit of 20 would drop the rest of a history of
    /// 100, a history turned off would record again). That goes by `currentIfValid`, and does nothing while it is nil.
    static var current: Config { currentIfValid ?? .default }

    /// The config as the file has it; nil while it doesn't parse. The input menu must still report a broken file and
    /// disable actions that would overwrite it; what deletes, trims or records anything waits for the file to parse.
    /// Read anew and parsing (fixed in an editor, say), it says so (`parsedAnew`).
    static var currentIfValid: Config? {
        let url = Config.defaultURL
        let date = modificationDate(url)
        if let cached, cached.url == url, cached.date == date { return cached.config }
        let config = try? Config.load(from: url)
        cached = (url, date, config)
        if config != nil { parsedAnew() }
        return config
    }

    /// Told on the main thread each time the file is read anew and parses: the input method's English words whose
    /// write failed are tried again (`EnglishWords.Writer.retry`, set in `runServer`); nothing by default.
    static var parsedAnew: () -> Void = {}

    /// The file at `url` read now, off the main thread, with its modification date (nil: it changed while it was read,
    /// or doesn't parse): what `take` makes the settings, an English word learned (`EnglishWords.Writer`).
    static func read(_ url: URL) -> (url: URL, date: Date?, config: Config)? {
        let date = modificationDate(url)
        guard let config = try? Config.load(from: url), modificationDate(url) == date else { return nil }
        return (url, date, config)
    }

    /// What `read` read, as the settings now, unless the file changed since: the next key doesn't parse it again.
    static func take(_ read: (url: URL, date: Date?, config: Config)) {
        guard read.url == Config.defaultURL, modificationDate(read.url) == read.date else { return }
        cached = (read.url, read.date, read.config)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// The user's jargon list (for explaining the terms a jargon (黑话) line uses), re-read when the file changes.
enum LiveJargon {
    private static var cached: (url: URL, date: Date?, entries: [JargonEntry])?

    static func entries(for config: Config) -> [JargonEntry] {
        let url = config.jargonURL
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let cached, cached.url == url, cached.date == date { return cached.entries }
        let entries = date == nil ? [] : JargonLibrary.load(from: url)
        cached = (url, date, entries)
        return entries
    }
}

/// IMK creates one controller per client text session. All IMK callbacks arrive on the main
/// thread, so entry points hop into main-actor code with `MainActor.assumeIsolated`.
