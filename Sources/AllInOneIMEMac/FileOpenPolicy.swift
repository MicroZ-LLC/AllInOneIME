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
        guard readsMetadata else { return runExtensions.contains(url.pathExtension.lowercased()) ? .reveal : .open }
        // Finder opens aliases and links at their targets, so judge what opening actually reaches.
        let linked = url.resolvingSymlinksInPath()
        let alias = (try? linked.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true
        // Never mounting its volume nor asking the user anything (a share's sign-in, "fix the alias"): this runs for the
        // rows of a search, as they are typed. An alias whose target isn't at hand is shown in Finder.
        let target = alias ? try? URL(resolvingAliasFileAt: linked, options: [.withoutUI, .withoutMounting]) : nil
        if alias && target == nil { return .reveal }
        let resolved = target?.resolvingSymlinksInPath() ?? linked
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        if attributes?[.type] as? FileAttributeType == .typeDirectory { return .open }  // folders and app bundles
        if runExtensions.contains(url.pathExtension.lowercased()) || runExtensions.contains(resolved.pathExtension.lowercased()) {
            return .reveal
        }
        guard attributes?[.type] as? FileAttributeType == .typeRegular else { return .open }
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return permissions & 0o111 != 0 ? .reveal : .open
    }

    /// What a row with `url` says ⏎ does: the row's own words (`SessionText.openAction`).
    public static func label(for url: URL) -> String {
        let result = SearchResult(name: url.lastPathComponent, path: url.path, reveals: action(for: url) == .reveal)
        return SessionText.openAction(result, UIText.words, terms: .mac)
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
