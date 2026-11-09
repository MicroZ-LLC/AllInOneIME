import Foundation

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

    /// The keys of `domain` that name the input sources the user has had: those enabled (`key`), the one selected, the
    /// recent ones (Ctrl+Space's order) and the one saved as current. An input method without input modes is named by its
    /// bundle ID (`Bundle ID`, its input source ID) in each.
    public static let entryKeys = [key, "AppleSelectedInputSources", "AppleInputSourceHistory", "AppleSavedCurrentInputSource"]

    /// `values` (`entryKeys`' as `domain` has them) without any entry of `bundleID`: `before`, the values of the keys that
    /// had one, and `after`, what they become (a list without those entries; a key whose value was such an entry alone,
    /// the saved current one, is absent: it goes). Both empty when none has one.
    public static func removingEntries(of bundleID: String, from values: [String: Any]) -> (before: [String: Any], after: [String: Any]) {
        var before: [String: Any] = [:], after: [String: Any] = [:]
        for key in entryKeys {
            if let list = values[key] as? [[String: Any]], contains(list, bundleID: bundleID) {
                before[key] = list
                after[key] = list.filter { $0[bundleIDKey] as? String != bundleID }
            } else if let entry = values[key] as? [String: Any], entry[bundleIDKey] as? String == bundleID {
                before[key] = entry
            }
        }
        return (before, after)
    }
}

/// Some of `com.apple.HIToolbox`'s keys (`InputSourceList.entryKeys`) as they were before an input source's entries were
/// taken out of them: a copy to put back. A property list, so that it can be written down and passed between processes.
public struct InputSourceEntries: Codable, Equatable, Sendable {
    /// The keys' values (a binary property list of a dictionary).
    public var plist: Data

    public init(_ values: [String: Any]) {
        plist = (try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)) ?? Data()
    }

    public init(plist: Data) { self.plist = plist }

    public var values: [String: Any] {
        (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any] ?? [:]
    }

    /// No key had an entry of it.
    public var isEmpty: Bool { values.isEmpty }
}
