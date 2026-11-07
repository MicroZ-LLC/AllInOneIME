import AllInOneIMECore
import AllInOneIMEMac
import Foundation

/// The script extensions the command list offers (`ExtensionStore`, docs/extensions.md; only reviewed extension sources:
/// `ExtensionSourceGate`). The index is built in the background at launch (`prepare`), and rebuilt
/// in the background, when a text field becomes active and when the settings name other folders, reading only
/// the files that changed (`ExtensionCache`); a keystroke only ever reads the last one, and a rebuild that changed it
/// is told (`changed`: an "@" list open then shows it at once). The folders Spotlight
/// finds holding Raycast scripts are looked for in the background too, at most every few minutes
/// (`discoverIfDue`), and kept across launches. Main thread only.
enum LiveExtensions {
    private static var index = ExtensionIndex.empty
    /// The folders `index` was built from, and whether a rebuild is under way (another one wanted after it).
    private static var indexed: [ExtensionStore.Folder]?
    private static var rebuilding = false
    private static var rebuildAgain = false
    private static let cache = ExtensionCache()
    /// Told on the main thread when a rebuild in the background changed the index: the input method's field (its "@"
    /// list, if one is open, shows the commands at once).
    static var changed: () -> Void = {}

    /// The index built in the background now, at launch: the first "@" has the extensions.
    static func prepare(_ config: Config) {
        _ = current(config)
    }

    /// The index as last built. `rescan`: build it again in the background (a text field became active), its folders
    /// worked out again (`ExtensionSourceGate`'s `recheck`); it is rebuilt too when `config` names other folders.
    static func current(_ config: Config, rescan: Bool = false) -> ExtensionIndex {
        let folders = ExtensionSourceGate.folders(config, found: found, recheck: rescan)
        if rescan || folders != indexed { rebuild(folders) }
        return index
    }

    /// The index built now, on this thread (the settings window, which shows what is there at once).
    static func load(_ config: Config) -> ExtensionIndex {
        let folders = ExtensionSourceGate.folders(config, found: found, recheck: true)
        let built = ExtensionStore.load(folders, cache: cache).numbered(after: index)
        index = built
        indexed = folders
        return index
    }

    private static func rebuild(_ folders: [ExtensionStore.Folder]) {
        guard !rebuilding else {
            rebuildAgain = true
            return
        }
        rebuilding = true
        let (cache, before) = (self.cache, index)
        DispatchQueue.global(qos: .utility).async {
            // Compared here, off the main thread: the command list is built again only for a new generation.
            let built = ExtensionStore.load(folders, cache: cache).numbered(after: before)
            DispatchQueue.main.async {
                if built.generation != before.generation, !built.commands.isEmpty || !built.skipped.isEmpty {
                    log.notice("extensions: \(built.commands.count) commands, \(built.bundles.count) bundles, \(built.skipped.count) skipped, \(built.identical.count) identical copies left out")
                }
                // Unless the settings read the folders meanwhile (`load`): theirs is as new.
                let (taken, landed) = built.lands(on: index, builtFrom: before)
                if taken { index = built }
                indexed = folders
                rebuilding = false
                if landed { changed() }
                if rebuildAgain {
                    rebuildAgain = false
                    rebuild(ExtensionSourceGate.folders(LiveConfig.current, found: found))
                }
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

    /// `load`, the folders read off the main thread: `done` gets the index on the main thread once it is built (the
    /// settings window shown, which shows the one it had meanwhile). Like a rebuild, one that changed the index is told
    /// (`changed`: an "@" list open then shows it).
    static func loadInBackground(_ config: Config, done: @escaping @MainActor (ExtensionIndex) -> Void) {
        let folders = ExtensionSourceGate.folders(config, found: found, recheck: true)
        let (cache, before) = (self.cache, index)
        DispatchQueue.global(qos: .userInitiated).async {
            let built = ExtensionStore.load(folders, cache: cache).numbered(after: before)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Another read meanwhile (`load`, a rebuild) is as new: its index stays.
                    let (taken, landed) = built.lands(on: index, builtFrom: before)
                    if taken {
                        index = built
                        indexed = folders
                    }
                    done(built)
                    if landed { changed() }
                }
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
