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
        var history = history
        history.record(entry)
        save(history)
    }

    /// Forgets them all: the file goes.
    static func clear() {
        save(QuestionHistory())
    }

    private static func save(_ history: QuestionHistory) {
        do {
            if let aside = try history.write(to: url) {
                log.error("recent questions: the file couldn't be read; set aside as \(aside, privacy: .public)")
            }
        } catch {
            log.error("recent questions: could not save them: \(String(describing: error), privacy: .public)")
        }
        loaded = (modificationDate(), history)
    }

    /// By `lstat` (a microsecond; the file manager's attributes take some forty): the history is asked for with each key.
    private static func modificationDate() -> Date? { FileDate.own(url.path) }
}
