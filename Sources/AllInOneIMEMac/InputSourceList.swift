/// The input sources the user has added: `AppleEnabledInputSources` in `com.apple.HIToolbox`
/// (what System Settings → Keyboard → Input Sources edits).
///
/// Ctrl+Space goes by this list. `TISEnableInputSource` from an installer files a third-party
/// input method in a separate record (`com.apple.inputsources`) instead: it counts as enabled and
/// types while selected, but Ctrl+Space doesn't reach it and macOS soon switches back to a source
/// from this list. The installer therefore keeps it in this list too.
public enum InputSourceList {
    public static let domain = "com.apple.HIToolbox"
    public static let key = "AppleEnabledInputSources"

    static let bundleIDKey = "Bundle ID"

    /// An entry for a keyboard input method without input modes (the shape the third-party
    /// record uses too).
    public static func entry(bundleID: String) -> [String: String] {
        [bundleIDKey: bundleID, "InputSourceKind": "Keyboard Input Method"]
    }

    public static func contains(_ list: [[String: Any]], bundleID: String) -> Bool {
        list.contains { $0[bundleIDKey] as? String == bundleID }
    }

    /// The list with an entry for `bundleID` at the end, or nil when nothing should be written:
    /// it is listed already, or there is no list at all (writing one would drop the system's
    /// defaults, such as the keyboard layout).
    public static func adding(_ bundleID: String, to list: [[String: Any]]?) -> [[String: Any]]? {
        guard let list, !contains(list, bundleID: bundleID) else { return nil }
        return list + [entry(bundleID: bundleID)]
    }

    /// The list without the entries for `bundleID` (all others kept as they are), or nil when it
    /// has none.
    public static func removing(_ bundleID: String, from list: [[String: Any]]?) -> [[String: Any]]? {
        guard let list, contains(list, bundleID: bundleID) else { return nil }
        return list.filter { $0[bundleIDKey] as? String != bundleID }
    }

    /// An input source as Text Input Sources files it: its ID, and the bundle ID it has for it.
    public struct Filed: Equatable, Sendable {
        public var id: String
        public var bundleID: String?

        public init(id: String, bundleID: String?) {
            self.id = id
            self.bundleID = bundleID
        }
    }

    public enum Removal {
        /// Nothing listed for it (or no list).
        case unlisted
        /// The list without its entries.
        case removed([[String: Any]])
        /// Text Input Sources files this other input source under its entry's bundle ID: left.
        case filedUnder(String)
    }

    /// The list without the entries of the input source `id` (an input method without input modes, listed by its bundle
    /// ID, which is its input source ID). Unless Text Input Sources (`filed`: every input source installed) files another
    /// one under that bundle ID: its cache can keep the bundle ID an app had for its path after another app took that
    /// path (AllInOneIME's new identity in place of the old one), and then that entry is what the other one is enabled
    /// by.
    public static func removingSource(_ id: String, from list: [[String: Any]]?, filed: [Filed]) -> Removal {
        guard let updated = removing(id, from: list) else { return .unlisted }
        if let other = filed.first(where: { $0.id != id && $0.bundleID == id }) { return .filedUnder(other.id) }
        return .removed(updated)
    }
}
