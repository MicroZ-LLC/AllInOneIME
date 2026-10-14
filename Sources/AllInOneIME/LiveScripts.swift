import AllInOneIMECore
import Foundation

/// The Raycast scripts the command list offers (`RaycastScriptStore`). Their folders are listed again when a
/// text field becomes active (a script added, removed or edited shows up there), and read again only when
/// something in them changed or the settings name other folders. The folders Spotlight finds are looked for
/// in the background, at most every few minutes (`discoverIfDue`), and kept across launches. Main thread only.
enum LiveScripts {
    private static var cached: (folders: [RaycastScriptStore.Folder], signature: [String: Date],
                                result: (scripts: [RaycastScript], skipped: [RaycastScriptStore.Skipped]))?

    static func current(_ config: Config, rescan: Bool = false) -> [RaycastScript] { load(config, rescan: rescan).scripts }

    /// The scripts of `config`'s folders, and the files skipped. `rescan`: the folders are listed to see
    /// whether anything changed (otherwise only other folders read them again).
    static func load(_ config: Config, rescan: Bool = false)
        -> (scripts: [RaycastScript], skipped: [RaycastScriptStore.Skipped]) {
        let folders = RaycastScriptStore.folders(config, found: found)
        if let cached, cached.folders == folders, !rescan { return cached.result }
        let signature = RaycastScriptStore.signature(folders)
        if let cached, cached.folders == folders, cached.signature == signature { return cached.result }
        let result = RaycastScriptStore.load(folders)
        cached = (folders, signature, result)
        if !result.scripts.isEmpty || !result.skipped.isEmpty {
            log.notice("Raycast scripts: \(result.scripts.count) commands, \(result.skipped.count) skipped")
        }
        return result
    }

    private static let foundKey = "raycastScriptFolders"

    /// The folders Spotlight found holding scripts, last time it was asked.
    static var found: [String] {
        get { UserDefaults.standard.stringArray(forKey: foundKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: foundKey) }
    }

    private static var lastDiscovery: Date?
    private static var discovering = false
    /// A Spotlight search takes a moment: not more often than this, unless asked (the settings page).
    static let discoveryInterval: TimeInterval = 5 * 60

    /// Asks Spotlight for the folders holding scripts in the background (`RaycastScriptStore.discover`),
    /// unless that was done in the last few minutes; `force`: anyway (the settings page opened). `done`
    /// runs on the main thread once they're known.
    static func discoverIfDue(_ config: Config, force: Bool = false, done: (() -> Void)? = nil) {
        guard config.findRaycastScripts, !discovering else { return }
        if !force, let lastDiscovery, Date().timeIntervalSince(lastDiscovery) < discoveryInterval { return }
        discovering = true
        lastDiscovery = Date()
        DispatchQueue.global(qos: .utility).async {
            let folders = RaycastScriptStore.discover()
            DispatchQueue.main.async {
                discovering = false
                if folders != found {
                    found = folders
                    log.notice("Raycast scripts: \(folders.count) folders found by Spotlight")
                }
                done?()
            }
        }
    }
}
