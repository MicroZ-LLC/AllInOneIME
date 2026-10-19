import AllInOneIMECore
import Foundation

/// Apple Notes as a place `@note` saves to (`NotesBridge.save`: the folder "AllInOneIME", made when missing). Nothing
/// leaves the Mac. The name, as the notices say it ("Saved to Notes"), is taken in the interface language when it is made.
struct AppleNotesDestination: NoteDestination {
    let name: String
    var leavesDevice: Bool { false }

    @MainActor init() {
        name = tr("备忘录", "Notes")
    }

    func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
        let id = try await NotesBridge.save(draft.text)
        return SavedNoteRef(id: id.isEmpty ? nil : id, title: NotesFormat.title(of: draft.text))
    }

    func check() async throws -> String { name }
}

/// Where `@note` saves now (`Config.notes`): made for each save, by the controller and Settings alike.
enum NoteSaving {
    /// The session Notion's requests go on: the core's (no cache, no cookies); the self-test's stub, while it runs.
    @MainActor static var notionSession: URLSession = NotionAPI.session

    /// The destination `settings` names, Apple Notes for Notes.
    @MainActor static func destination(_ settings: NoteSettings) -> any NoteDestination {
        NoteDestinations.make(settings, system: AppleNotesDestination(), session: notionSession)
    }
}
