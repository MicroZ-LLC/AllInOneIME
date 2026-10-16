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

    /// `entries` as they are, newest first (the file's order: not by their times, which a clock set back would reorder),
    /// the same question once (its first, newest, wording and answer; a hand-edited file may have it twice), at most `limit`.
    public init(entries: [Entry] = []) {
        var seen = Set<String>()
        self.entries = Array(entries.filter { seen.insert(Self.key($0.question)).inserted }.prefix(Self.limit))
    }

    /// `entry` was answered just now: it goes first, in place of the same question asked before (`key`), whose wording
    /// and answer go.
    public mutating func record(_ entry: Entry) {
        let question = entry.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !entry.answer.isEmpty else { return }
        var entry = entry
        entry.question = question
        let key = Self.key(question)
        entries = Array(([entry] + entries.filter { Self.key($0.question) != key }).prefix(Self.limit))
    }

    /// What makes two questions the same one: they differ only in case or in spaces and line breaks (at the ends, or
    /// how many between words).
    static func key(_ question: String) -> String {
        question.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
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
        let folder = url.deletingLastPathComponent()
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.replace(url, with: Self.encoder.encode(self))
    }

    /// Writes `data` to a new file in `url`'s folder that is the user's only from the start (0600), then renames it over
    /// `url` in one step: the questions are never in a file others can read, not even for a moment, and a file that was
    /// readable by others before is replaced, not reused.
    static func replace(_ url: URL, with data: Data) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temporary.path]) }
        var written = fchmod(fd, 0o600) == 0  // whatever the umask
        data.withUnsafeBytes { bytes in
            var offset = 0
            while written, offset < bytes.count {
                let n = Foundation.write(fd, bytes.baseAddress! + offset, bytes.count - offset)
                if n <= 0 { written = false } else { offset += n }
            }
        }
        written = fsync(fd) == 0 && written
        close(fd)
        guard written, rename(temporary.path, url.path) == 0 else {
            unlink(temporary.path)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
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
