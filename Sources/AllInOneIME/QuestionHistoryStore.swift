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
            try history.write(to: url)
        } catch {
            log.error("recent questions: could not save them: \(String(describing: error), privacy: .public)")
        }
        loaded = (modificationDate(), history)
    }

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

extension UIText {
    /// How long ago `date` was, in the interface language: "刚刚" / "just now", "3 小时前" / "3 hours ago" …
    static func ago(_ date: Date, now: Date = Date()) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return tr("刚刚", "just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
