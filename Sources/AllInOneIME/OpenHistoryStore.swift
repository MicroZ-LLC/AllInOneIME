import AllInOneIMECore
import Foundation

/// What `@open` opened (`OpenHistory`), kept in the input method's defaults under "openHistory". Main
/// thread only: the controller reads it for each search and records what is opened (the self-test
/// supplies a history of its own instead, `loadOpenHistory` / `recordOpen`).
enum OpenHistoryStore {
    static let key = "openHistory"

    static var history: OpenHistory = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let history = try? JSONDecoder().decode(OpenHistory.self, from: data) else { return OpenHistory() }
        return history
    }()

    /// `path` was opened through `@open` just now.
    static func record(_ path: String) {
        history.record(path)
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: key) }
    }
}
