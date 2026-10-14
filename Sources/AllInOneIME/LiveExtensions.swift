import AllInOneIMECore
import Foundation

/// The script extensions the command list offers (`ExtensionStore`, docs/extensions.md). The index is rebuilt
/// in the background, when a text field becomes active and when the settings name other folders, reading only
/// the files that changed (`ExtensionCache`); a keystroke only ever reads the last one. The folders Spotlight
/// finds holding Raycast scripts are looked for in the background too, at most every few minutes
/// (`discoverIfDue`), and kept across launches. Main thread only.
enum LiveExtensions {
    private static var index = ExtensionIndex.empty
    /// The folders `index` was built from, and whether a rebuild is under way (another one wanted after it).
    private static var indexed: [ExtensionStore.Folder]?
    private static var rebuilding = false
    private static var rebuildAgain = false
    private static let cache = ExtensionCache()

    /// The index as last built. `rescan`: build it again in the background (a text field became active);
    /// it is rebuilt too when `config` names other folders. `done` runs once a rebuild it started is in.
    static func current(_ config: Config, rescan: Bool = false, done: (() -> Void)? = nil) -> ExtensionIndex {
        let folders = ExtensionStore.folders(config, found: found)
        if rescan || folders != indexed { rebuild(folders, done: done) }
        return index
    }

    /// The index built now, on this thread (the settings window, which shows what is there at once).
    static func load(_ config: Config) -> ExtensionIndex {
        let folders = ExtensionStore.folders(config, found: found)
        index = ExtensionStore.load(folders, cache: cache)
        indexed = folders
        return index
    }

    private static func rebuild(_ folders: [ExtensionStore.Folder], done: (() -> Void)?) {
        guard !rebuilding else {
            rebuildAgain = true
            return
        }
        rebuilding = true
        let cache = self.cache
        DispatchQueue.global(qos: .utility).async {
            let built = ExtensionStore.load(folders, cache: cache)
            DispatchQueue.main.async {
                if built != index, !built.commands.isEmpty || !built.skipped.isEmpty {
                    log.notice("extensions: \(built.commands.count) commands, \(built.bundles.count) bundles, \(built.skipped.count) skipped")
                }
                index = built
                indexed = folders
                rebuilding = false
                if rebuildAgain {
                    rebuildAgain = false
                    rebuild(ExtensionStore.folders(LiveConfig.current, found: found), done: nil)
                }
                done?()
            }
        }
    }

    private static let foundKey = "raycastScriptFolders"

    /// The folders Spotlight found holding Raycast scripts, last time it was asked.
    static var found: [String] {
        get { UserDefaults.standard.stringArray(forKey: foundKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: foundKey) }
    }

    private static var lastDiscovery: Date?
    private static var discovering = false
    /// A Spotlight search takes a moment: not more often than this, unless asked (the settings page).
    static let discoveryInterval: TimeInterval = 5 * 60

    /// Asks Spotlight for the folders holding Raycast scripts in the background (`ExtensionStore.discover`),
    /// unless that was done in the last few minutes; `force`: anyway (the settings page opened). `done` runs on
    /// the main thread once they're known.
    static func discoverIfDue(_ config: Config, force: Bool = false, done: (() -> Void)? = nil) {
        guard config.findRaycastScripts, !discovering else { return }
        if !force, let lastDiscovery, Date().timeIntervalSince(lastDiscovery) < discoveryInterval { return }
        discovering = true
        lastDiscovery = Date()
        DispatchQueue.global(qos: .utility).async {
            let folders = ExtensionStore.discover()
            DispatchQueue.main.async {
                discovering = false
                if folders != found {
                    found = folders
                    log.notice("extensions: \(folders.count) Raycast script folders found by Spotlight")
                }
                done?()
            }
        }
    }

    /// The values `bundle`'s commands get: what the settings saved, passwords from the keychain, else the defaults.
    static func preferences(of bundle: ExtensionBundle, config: Config) -> [String: String] {
        var stored = config.extensionPreferences[bundle.name] ?? [:]
        for preference in bundle.preferences where preference.kind == .password {
            stored[preference.name] = APIKeys.keychainKey(account: ExtensionBundle.Preference.keychainAccount(bundle: bundle.name,
                                                                                                             name: preference.name))
        }
        return bundle.values(stored)
    }
}

/// The status lines of the commands that have one (`ScriptCommand.status`), shown beside their names in the
/// command list. Each is run in the background when the list shows it and its value is older than its refresh
/// time, a few at a time and stopped after `ScriptCommand.Status.timeout`: a slow one never holds the list up,
/// its value shows when it comes. Main thread only.
@MainActor
final class ScriptStatus {
    static let shared = ScriptStatus()

    private var values: [String: (text: String?, at: Date)] = [:]
    private var running: Set<String> = []
    static let maxRunning = 2

    /// The last status line of `command`, if it has one.
    func text(for command: ScriptCommand) -> String? { values[command.id]?.text }

    /// Runs the status of those of `commands` whose value is due (`environment` gives each its environment);
    /// `changed` is called when one arrives.
    func refresh(_ commands: [ScriptCommand], environment: (ScriptCommand) -> [String: String], changed: @escaping () -> Void) {
        let now = Date()
        for command in commands {
            guard let status = command.status, running.count < Self.maxRunning, !running.contains(command.id) else { continue }
            if let value = values[command.id], now.timeIntervalSince(value.at) < status.refresh { continue }
            running.insert(command.id)
            let stream = CommandRunner.run(command, arguments: [], environment: environment(command), status: true)
            let id = command.id
            Task { @MainActor [weak self] in
                var line: String?
                do {
                    for try await update in stream where update.isFinal {
                        line = update.output.lines.first.map { String($0.prefix(40)) }
                    }
                } catch {
                    line = nil  // its value stays empty until it works; tried again after its refresh time
                }
                guard let self else { return }
                self.running.remove(id)
                let old = self.values[id]?.text
                self.values[id] = (line ?? old, Date())
                if line != old { changed() }
            }
        }
    }
}
