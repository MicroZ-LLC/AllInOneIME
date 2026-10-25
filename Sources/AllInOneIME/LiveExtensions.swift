import AllInOneIMECore
import AllInOneIMEMac
import Foundation

/// The script extensions the command list offers (`ExtensionStore`, docs/extensions.md; only reviewed extension sources:
/// `ExtensionSourceGate`). The index is rebuilt
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
    /// What wants to know when the rebuilds under way and wanted are in.
    private static var waiting: [() -> Void] = []
    private static let cache = ExtensionCache()

    /// The index as last built. `rescan`: build it again in the background (a text field became active), its folders
    /// worked out again (`ExtensionSourceGate`'s `recheck`); it is rebuilt too when `config` names other folders. `done`
    /// runs once a rebuild it started is in.
    static func current(_ config: Config, rescan: Bool = false, done: (() -> Void)? = nil) -> ExtensionIndex {
        let folders = ExtensionSourceGate.folders(config, found: found, recheck: rescan)
        if rescan || folders != indexed { rebuild(folders, done: done) }
        return index
    }

    /// The index built now, on this thread (the settings window, which shows what is there at once).
    static func load(_ config: Config) -> ExtensionIndex {
        let folders = ExtensionSourceGate.folders(config, found: found, recheck: true)
        var built = ExtensionStore.load(folders, cache: cache)
        built.generation = built == index ? index.generation : index.generation &+ 1
        index = built
        indexed = folders
        return index
    }

    private static func rebuild(_ folders: [ExtensionStore.Folder], done: (() -> Void)?) {
        if let done { waiting.append(done) }
        guard !rebuilding else {
            rebuildAgain = true
            return
        }
        rebuilding = true
        let (cache, before) = (self.cache, index)
        DispatchQueue.global(qos: .utility).async {
            var built = ExtensionStore.load(folders, cache: cache)
            // Compared here, off the main thread: the command list is built again only for a new generation.
            let same = built == before
            built.generation = same ? before.generation : before.generation &+ 1
            DispatchQueue.main.async {
                if !same, !built.commands.isEmpty || !built.skipped.isEmpty {
                    log.notice("extensions: \(built.commands.count) commands, \(built.bundles.count) bundles, \(built.skipped.count) skipped, \(built.identical.count) identical copies left out")
                }
                // Unless the settings read the folders meanwhile (`load`): theirs is as new.
                if index.generation == before.generation { index = built }
                indexed = folders
                rebuilding = false
                if rebuildAgain {
                    rebuildAgain = false
                    rebuild(ExtensionSourceGate.folders(LiveConfig.current, found: found), done: nil)
                    return
                }
                let done = waiting
                waiting = []
                done.forEach { $0() }
            }
        }
    }

    private static let foundKey = "raycastScriptFolders"

    /// The folders Spotlight found holding Raycast scripts, last time it was asked: each search replaces the
    /// list, so a folder since removed (or no longer holding one) is dropped.
    static var found: [String] {
        get { shownFound ?? UserDefaults.standard.stringArray(forKey: foundKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: foundKey) }
    }

    /// Folders shown as found instead of the saved ones (`--settings-image … extensions=`), never saved.
    static var shownFound: [String]?

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
/// command list: run in the background when the list shows them and they're due (`StatusSchedule`), a few at a
/// time and stopped after `ScriptCommand.Status.timeout`. A slow one never holds the list up; one that ends,
/// failed or not, lets the next due one start. Main thread only.
@MainActor
final class ScriptStatus {
    static let shared = ScriptStatus()

    private var schedule = StatusSchedule()

    /// The last status line of `command`, if it has one.
    func text(for command: ScriptCommand) -> String? { schedule.text(for: command.id) }

    /// Runs the status of those of `commands` that are due (`environment` gives each its environment, nil: not
    /// now); `ended` is called when one ends, to draw it and start the next due one.
    func refresh(_ commands: [ScriptCommand], environment: @escaping (ScriptCommand) async -> [String: String]?,
                 ended: @escaping () -> Void) {
        for command in schedule.due(commands) {
            Task { @MainActor [weak self] in
                var line: String?
                if let env = await environment(command) {
                    do {
                        for try await update in CommandRunner.run(command, arguments: [], environment: env, status: true) where update.isFinal {
                            line = update.output.lines.first.map { String($0.prefix(40)) }
                        }
                    } catch {
                        line = nil  // the value before stays until its next refresh time
                    }
                }
                self?.schedule.finished(command.id, line: line)
                ended()
            }
        }
    }
}
