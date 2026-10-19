import Foundation
import Testing
@testable import AllInOneIMECore

/// The folder's notes from Notes' AppleScript reply (`NotesFormat.entries`, moved with it from NotesFormatTests).
struct NotesListingTests {
    func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (index, item) in items.enumerated() { list.insert(item, at: index + 1) }
        return list
    }

    @Test func theFoldersNotesNewestFirst() {
        // What the script returns: the ids, the names and the modification dates, three lists.
        let older = Date(timeIntervalSince1970: 1_790_000_000), newer = older.addingTimeInterval(3600)
        let result = list([
            list([NSAppleEventDescriptor(string: "x-coredata://1"), NSAppleEventDescriptor(string: "x-coredata://2"),
                  NSAppleEventDescriptor(string: "")]),
            list([NSAppleEventDescriptor(string: "周会要点"), NSAppleEventDescriptor(string: "买牛奶和鸡蛋")]),
            list([NSAppleEventDescriptor(date: older), NSAppleEventDescriptor(date: newer)]),
        ])
        #expect(NotesFormat.entries(from: result, limit: 10) == [
            NotesFormat.Entry(id: "x-coredata://2", title: "买牛奶和鸡蛋", modified: newer),
            NotesFormat.Entry(id: "x-coredata://1", title: "周会要点", modified: older),
        ])
        #expect(NotesFormat.entries(from: result, limit: 1)?.map(\.id) == ["x-coredata://2"])
        #expect(NotesFormat.entries(from: result, limit: 0) == [])
        // A name or date missing: kept without it (a note without an id is left out, above).
        let partial = list([list([NSAppleEventDescriptor(string: "a"), NSAppleEventDescriptor(string: "b")]),
                            list([NSAppleEventDescriptor(string: "A")]), list([])])
        #expect(NotesFormat.entries(from: partial, limit: 10) == [
            NotesFormat.Entry(id: "a", title: "A", modified: .distantPast), NotesFormat.Entry(id: "b", title: "", modified: .distantPast),
        ])
        // An empty folder: three empty lists, no notes.
        #expect(NotesFormat.entries(from: list([list([]), list([]), list([])]), limit: 10) == [])
    }

    @Test func aReplyThatIsntThreeListsListsNothing() {
        // `return missing value` (no folder), or anything else: nil, which says nothing of the notes saved (an
        // empty list would say there are none, and the floating panel would drop the ones it shows).
        let missingValue = NSAppleEventDescriptor(typeCode: 0x6D73_6E67)  // 'msng', as a script's `missing value` comes back
        #expect(NotesFormat.entries(from: missingValue, limit: 10) == nil)
        #expect(NotesFormat.entries(from: list([]), limit: 10) == nil)
        #expect(NotesFormat.entries(from: NSAppleEventDescriptor(string: "x"), limit: 10) == nil)
        #expect(NotesFormat.entries(from: list([list([]), list([])]), limit: 10) == nil)
        #expect(NotesFormat.entries(from: list([list([]), list([]), list([]), list([])]), limit: 10) == nil)
        #expect(NotesFormat.entries(from: list([NSAppleEventDescriptor(string: "x-coredata://1"), list([]), list([])]), limit: 10) == nil)
    }
}
