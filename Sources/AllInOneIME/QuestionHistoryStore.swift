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
    /// Changes handed to the file's queue and not written yet (`save`): the list as changed here stands meanwhile.
    private static var pending = 0

    static var history: QuestionHistory {
        if pending > 0, let loaded { return loaded.history }
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

    /// `change` made at once to the list shown, and to the file as it is then off the main thread, under the lock the iCloud
    /// sync's merge takes too (`QuestionHistory.updateLater`): a merge going on meanwhile never writes over the question,
    /// nor this over the merge, and typing never waits for it. Once all are written, the file is read again (with what a
    /// merge brought).
    private static func save(_ change: @escaping @Sendable (inout QuestionHistory) -> Void) {
        var shown = history
        change(&shown)
        loaded = (modificationDate(), shown)
        pending += 1
        QuestionHistory.updateLater(at: url, change) { outcome in
            DispatchQueue.main.async {
                pending -= 1
                if pending == 0 { loaded = nil }
            }
            switch outcome {
            case let .success((_, aside?)):
                log.error("recent questions: the file couldn't be read; set aside as \(aside, privacy: .public)")
            case .success:
                break  // written
            case let .failure(error):
                log.error("recent questions: could not save them: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// By `lstat` (a microsecond; the file manager's attributes take some forty): the history is asked for with each key.
    private static func modificationDate() -> Date? { FileDate.own(url.path) }
}
