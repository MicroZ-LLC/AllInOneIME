import AllInOneIMECore
import Foundation

/// The recent `@question`s (`QuestionHistory`), kept in ~/Library/Application Support/AllInOneIME/recent-questions.json
/// for every text field and across launches, and cleared from the settings. Main thread only. Read again only when the
/// file changed (by its modification date): deleted or put back by hand, it's as the file says.
enum QuestionHistoryStore {
    /// Where they're kept (the self-test uses its own).
    static var url = QuestionHistory.defaultURL {
        didSet { loaded = nil }
    }
    private static var loaded: (date: Date?, history: QuestionHistory)?

    static var history: QuestionHistory {
        let date = modificationDate()
        if let loaded, loaded.date == date { return loaded.history }
        let history = date == nil ? QuestionHistory() : QuestionHistory.load(from: url)
        loaded = (date, history)
        return history
    }

    /// `entry` was answered just now.
    static func record(_ entry: QuestionHistory.Entry) {
        save { $0.record(entry) }
    }

    /// Forgets them all: the file goes.
    static func clear() {
        save { $0 = QuestionHistory() }
    }

    /// `change` made to the file as it is now, under the lock the iCloud sync's merge takes too (`QuestionHistory.update`):
    /// a merge going on meanwhile never writes over the question, nor this over the merge.
    private static func save(_ change: (inout QuestionHistory) -> Void) {
        do {
            let (history, aside) = try QuestionHistory.update(at: url, change)
            if let aside { log.error("recent questions: the file couldn't be read; set aside as \(aside, privacy: .public)") }
            loaded = (modificationDate(), history)
        } catch {
            log.error("recent questions: could not save them: \(String(describing: error), privacy: .public)")
            var history = history
            change(&history)
            loaded = (modificationDate(), history)
        }
    }

    /// By `lstat` (a microsecond; the file manager's attributes take some forty): the history is asked for with each key.
    private static func modificationDate() -> Date? { FileDate.own(url.path) }
}
