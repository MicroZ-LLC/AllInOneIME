import Foundation
import AllInOneIMECore

/// The folder's notes as Notes' AppleScript reply has them (Apple events: the Mac's alone).
extension NotesFormat {
    /// What the script listing the folder returns (three lists, one Apple event each: the ids, the names and
    /// the modification dates) as entries, the newest first, at most `limit`. A note without an id is left out;
    /// one without a name or date gets none. Nil for any other reply (`missing value` when there is no folder,
    /// or one this doesn't know): it says nothing of the notes, unlike an empty folder's three empty lists.
    public static func entries(from result: NSAppleEventDescriptor, limit: Int) -> [Entry]? {
        let columns = items(result)
        guard columns.count == 3, columns.allSatisfy({ $0.descriptorType == listType }) else { return nil }
        let (ids, names, dates) = (items(columns[0]), items(columns[1]), items(columns[2]))
        let all = ids.indices.compactMap { i -> Entry? in
            guard let id = ids[i].stringValue, !id.isEmpty else { return nil }
            return Entry(id: id, title: i < names.count ? names[i].stringValue ?? "" : "",
                         modified: i < dates.count ? dates[i].dateValue ?? .distantPast : .distantPast)
        }
        return Array(all.sorted { $0.modified > $1.modified }.prefix(max(limit, 0)))
    }

    /// AppleScript's list type ('list').
    private static let listType: FourCharCode = 0x6C69_7374

    /// The items of an AppleScript list (none for anything else).
    private static func items(_ list: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard list.descriptorType == listType else { return [] }
        return (0..<list.numberOfItems).compactMap { list.atIndex($0 + 1) }
    }
}
