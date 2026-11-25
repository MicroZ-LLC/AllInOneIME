import AllInOneIMECore
import AppKit

/// How `@open` opens a file on the Mac: most as Finder's double-click would, but a script or a program that opening would
/// run (a shell script, a `.command`, `.tool` or `.terminal` file, a file with an execute bit) is shown in Finder instead,
/// selected, so one ⏎ on a row never runs anything (the user can still open it from there). Folders and app bundles open.
public enum FileOpenPolicy {
    public enum Action: Equatable, Sendable {
        case open
        /// Shown in Finder, selected (`NSWorkspace.activateFileViewerSelecting`).
        case reveal
    }

    /// What Terminal runs when they're opened, whatever their permissions.
    static let runExtensions: Set<String> = ["command", "tool", "sh", "terminal"]

    /// What ⏎ does to `url`. Reads its metadata (`readsMetadata` false: by its name only, for a file on a server that
    /// mustn't be asked anything): off the main thread.
    public static func action(for url: URL, readsMetadata: Bool = true) -> Action {
        if runExtensions.contains(url.pathExtension.lowercased()) { return .reveal }
        guard readsMetadata else { return .open }
        let resolved = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return .open }  // a folder, an app bundle
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return permissions & 0o111 != 0 ? .reveal : .open
    }

    /// What a row with `url` says ⏎ does.
    public static func label(for url: URL) -> String {
        action(for: url) == .reveal ? tr("在访达中显示", "Show in Finder") : tr("打开", "Open")
    }

    /// Opens an `@open` result (`path`): a web address in the default browser; a file as `action` says, its metadata read
    /// off the main thread, then opened or shown in Finder back on it.
    @MainActor
    public static func open(_ path: String) {
        if let web = SearchResult(name: "", path: path).webURL {
            NSWorkspace.shared.open(web)
            return
        }
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .userInitiated).async {
            let action = action(for: url)
            DispatchQueue.main.async {
                if action == .reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { _ = NSWorkspace.shared.open(url) }
            }
        }
    }
}
