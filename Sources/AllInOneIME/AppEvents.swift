import Foundation

/// What the input method tells its own parts about, within the process (the menu bar panel
/// listens). Posted on the main thread.
extension Notification.Name {
    /// @note saved a note (posted by the controller). userInfo: "id" (String: the Notes id, the file's URL or the Notion
    /// page's, `SavedNoteRef`), "title" (String, its first line).
    static let allInOneIMENoteSaved = Notification.Name("AllInOneIMENoteSaved")
    /// @reminder added a reminder. userInfo: "id" (String, the EventKit identifier).
    static let allInOneIMEReminderAdded = Notification.Name("AllInOneIMEReminderAdded")
}
