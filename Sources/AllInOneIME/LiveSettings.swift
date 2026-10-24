import AllInOneIMECore
import Foundation

/// The installed plugins, scanned again when a text field becomes active (installing or removing one
/// shows up there) and at most every 30 seconds otherwise: then in the background, never while a key is
/// handled (the key gets the plugins as last scanned). Main thread only.
enum LivePlugins {
    private static var cached: (at: Date, result: (plugins: [InstalledPlugin], skipped: [PluginStore.Skipped]))?
    private static var scanning = false

    static func current(rescan: Bool = false) -> [InstalledPlugin] {
        guard rescan || cached == nil else {
            if let cached, Date().timeIntervalSince(cached.at) >= 30, !scanning {
                scanning = true
                DispatchQueue.global(qos: .utility).async {
                    let result = PluginStore.load()
                    DispatchQueue.main.async {
                        self.cached = (Date(), result)
                        scanning = false
                    }
                }
            }
            return cached?.result.plugins ?? []
        }
        let result = PluginStore.load()
        cached = (Date(), result)
        return result.plugins
    }
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

    static var current: Config { currentIfValid ?? .default }

    /// The input menu must still report a broken file and disable actions that would overwrite it.
    static var currentIfValid: Config? {
        let url = Config.defaultURL
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let cached, cached.url == url, cached.date == date { return cached.config }
        let config = try? Config.load(from: url)
        cached = (url, date, config)
        return config
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
