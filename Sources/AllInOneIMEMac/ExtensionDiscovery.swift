import Foundation
import AllInOneIMECore

/// Raycast script folders found with Spotlight (`mdfind`): only the Mac has it.
extension ExtensionStore {
    /// The folders holding Raycast scripts on this Mac, by Spotlight: the parent folders of the files that have
    /// Raycast metadata and are scripts (not code or notes that only mention it), as "~/…", sorted. Not those
    /// in hidden folders or ~/Library (apps' caches and copies), nor templates. Slow (a Spotlight search, and
    /// the files read): never on a keystroke.
    public static func discover(spotlight: Spotlight = Spotlight(until: .now() + 20)) -> [String] {
        guard let data = spotlight.mdfind([query]) else { return [] }
        return folders(fromSpotlight: String(decoding: data, as: UTF8.self))
    }

    /// The Spotlight query for files with Raycast metadata (Raycast keeps its own list encrypted).
    static let query = "kMDItemTextContent == \"*@raycast.schemaVersion*\"c"
}
