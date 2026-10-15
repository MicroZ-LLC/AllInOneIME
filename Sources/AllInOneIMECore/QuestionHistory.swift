import Foundation

/// The last few `@question`s asked and their answers (`Config.rememberQuestions`): "@question " with nothing after it
/// lists them, newest first, and picking one shows its answer again without asking anyone (`Composer.questionMatches`).
/// Kept only on this Mac, in a small file (`defaultURL`). Never a question asked while secure input is on, nor one asked
/// on selected text: its answer is about text that isn't part of the question (and may be someone else's document), so
/// it couldn't be asked again as it was, and the text would end up on disk.
public struct QuestionHistory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// The question as typed after "@question".
        public var question: String
        public var answer: String
        /// When it was answered.
        public var date: Date

        public init(question: String, answer: String, date: Date) {
            self.question = question
            self.answer = answer
            self.date = date
        }
    }

    /// Newest first, at most `limit`.
    public private(set) var entries: [Entry] = []

    /// How many are kept: the oldest goes when another comes (the digits 1–5 pick them).
    public static let limit = 5

    public init(entries: [Entry] = []) {
        self.entries = Array(entries.prefix(Self.limit))
    }

    /// `entry` was answered just now: it goes first, in place of the same question asked before.
    public mutating func record(_ entry: Entry) {
        let question = entry.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !entry.answer.isEmpty else { return }
        var entry = entry
        entry.question = question
        entries = Array(([entry] + entries.filter { $0.question != question }).prefix(Self.limit))
    }

    /// The questions with all of `query` in them, newest first; all of them for an empty query.
    public func matching(_ query: String) -> [Entry] {
        entries.filter { Self.matches($0.question, query) }
    }

    /// Whether `question` holds every word of `query` (split at spaces) anywhere in it, in any case, full-width or not
    /// ("ＡＩ" is "AI"). Chinese and Japanese aren't written with spaces between words, so a word is also found where the
    /// question has a space inside it ("AI芯片" in "AI 芯片").
    public static func matches(_ question: String, _ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let unspaced = question.filter { !$0.isWhitespace }
        return words.allSatisfy { question.range(of: $0, options: options) != nil || unspaced.range(of: $0, options: options) != nil }
    }

    // MARK: - The file

    /// ~/Library/Application Support/AllInOneIME/recent-questions.json
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME/recent-questions.json")
    }

    /// What `url` holds: nothing when there's no file or it can't be read (it's only a convenience).
    public static func load(from url: URL = defaultURL) -> QuestionHistory {
        guard let data = try? Data(contentsOf: url), let history = try? decoder.decode(QuestionHistory.self, from: data) else {
            return QuestionHistory()
        }
        return QuestionHistory(entries: history.entries)
    }

    /// Writes the questions to `url`, readable only by the user; none: the file goes.
    public func write(to url: URL = defaultURL) throws {
        let files = FileManager.default
        guard !entries.isEmpty else {
            if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
            return
        }
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: url, options: [.atomic])
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
