import AllInOneIMECore
import Foundation

/// The notes @note saved (`SavedNotes`), as JSON under `savedNotes`, in what the panel remembers between launches
/// (`DashboardSources.defaults`).
enum SavedNotesStore {
    static let key = "savedNotes"

    static func load(_ defaults: any KeyValueStore) -> SavedNotes {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedNotes.self, from: $0) } ?? SavedNotes()
    }

    static func save(_ notes: SavedNotes, to defaults: any KeyValueStore) {
        if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: key) }
    }
}
