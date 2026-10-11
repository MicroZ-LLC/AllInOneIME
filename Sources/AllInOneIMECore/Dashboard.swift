import Foundation

// The floating panel's logic (「悬浮面板」, off by default: notes saved with @note, reminders added with
// @reminder, @claude's background tasks). The window and its sources are in the input method.

/// The panel's own record of the notes `@note` saved, newest first: kept from launch, whether the
/// panel is on or not. Notes isn't read on a timer for this: an Apple event to Notes launches it
/// when it isn't running. Kept as JSON in the input method's defaults (`savedNotes`).
public struct SavedNotes: Codable, Equatable, Sendable {
    public struct Note: Codable, Equatable, Sendable, Identifiable {
        /// Notes' identifier (`x-coredata://…`), to show the note.
        public var id: String
        /// Its first line, at most `SavedNotes.titleLength` characters (as Notes names it).
        public var title: String
        /// When @note saved it.
        public var saved: Date

        public init(id: String, title: String, saved: Date) {
            self.id = id
            self.title = NotesFormat.title(of: title, limit: SavedNotes.titleLength)
            self.saved = saved
        }
    }

    /// How many are kept, and how long a title may be.
    public static let limit = 30
    public static let titleLength = 80

    public private(set) var notes: [Note]

    public init(_ notes: [Note] = []) {
        self.notes = Array(notes.prefix(Self.limit))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode([Note].self, forKey: .notes))
    }

    /// A note @note just saved goes first; saved before (the same id), it moves up. The oldest beyond
    /// `limit` are forgotten.
    public mutating func add(id: String, title: String, at date: Date) {
        notes.removeAll { $0.id == id }
        notes.insert(Note(id: id, title: title, saved: date), at: 0)
        if notes.count > Self.limit { notes.removeLast(notes.count - Self.limit) }
    }

    public func newest(_ count: Int) -> [Note] { Array(notes.prefix(max(count, 0))) }

    /// Takes in what Notes lists now (`NotesBridge.recent`: the folder's notes changed last, at most
    /// `limit`); nil when Notes has no such folder, in its default account (the user switched the
    /// default account, or renamed the folder): that says nothing of the notes saved, so nothing
    /// changes then. Titles follow edits made in Notes. A note it doesn't list is dropped only when
    /// it would be listed if it were still there: the list is the whole folder (shorter than
    /// `limit`), or the note was saved after the oldest listed one last changed (a minute's margin:
    /// Notes stamps it a moment before @note reports it). Moved to another folder counts as gone.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func reconcile(with listed: [(id: String, title: String, modified: Date)]?, limit: Int) -> Bool {
        guard let listed else { return false }
        var titles: [String: String] = [:]
        for note in listed where titles[note.id] == nil { titles[note.id] = NotesFormat.title(of: note.title, limit: Self.titleLength) }
        let wholeFolder = listed.count < limit
        let oldest = listed.map(\.modified).min()
        let before = notes
        notes = notes.compactMap { note in
            if let title = titles[note.id] {
                var note = note
                if !title.isEmpty { note.title = title }  // a note that starts with a picture has no name
                return note
            }
            let wouldBeListed = wholeFolder || oldest.map { note.saved.addingTimeInterval(-60) > $0 } == true
            return wouldBeListed ? nil : note
        }
        return notes != before
    }
}

/// The panel's wording made of numbers and dates, in Chinese or English: fixed wording like
/// `ReminderDraft.when`, since it sits next to the panel's own text.
public enum DashboardText {
    /// How long ago: 「刚刚」「5 分钟前」「2 小时前」「3 天前」 / "just now", "5 min ago", "2 hr ago",
    /// "3 days ago". A time ahead of `now` (another Mac's clock) is 「刚刚」.
    public static func ago(_ date: Date, now: Date, chinese: Bool) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let (minutes, hours, days) = (Int(seconds / 60), Int(seconds / 3600), Int(seconds / 86400))
        if minutes < 1 { return chinese ? "刚刚" : "just now" }
        if hours < 1 { return chinese ? "\(minutes) 分钟前" : "\(minutes) min ago" }
        if days < 1 { return chinese ? "\(hours) 小时前" : "\(hours) hr ago" }
        return chinese ? "\(days) 天前" : days == 1 ? "1 day ago" : "\(days) days ago"
    }

    /// The header's counts: 「3 个提醒 · 1 个任务进行中 · 1 个等你」 / "3 reminders · 1 task running ·
    /// 1 waiting for you" (tasks waiting for the user aren't running). A zero is left out (nothing at
    /// all: empty); `moreReminders`: more than were read ("100+").
    public static func counts(reminders: Int, moreReminders: Bool = false, running: Int, waiting: Int = 0,
                              chinese: Bool) -> String {
        var parts: [String] = []
        let shown = "\(reminders)" + (moreReminders ? "+" : "")
        if reminders > 0 {
            parts.append(chinese ? "\(shown) 个提醒" : reminders == 1 && !moreReminders ? "1 reminder" : "\(shown) reminders")
        }
        if running > 0 {
            parts.append(chinese ? "\(running) 个任务进行中" : running == 1 ? "1 task running" : "\(running) tasks running")
        }
        if waiting > 0 { parts.append(chinese ? "\(waiting) 个等你" : "\(waiting) waiting for you") }
        return parts.joined(separator: " · ")
    }

    /// The first line of `text` with something on it, as a one-line preview: without the Markdown
    /// marks a reply starts lines with (a heading's #, a list's -, a quote's >) and without bold and
    /// code marks. Nil when there is none.
    public static func firstLine(_ text: String?) -> String? {
        guard let text else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let plain = line.replacingOccurrences(of: #"^\s*((#{1,6}|[-*+>]|\d+\.)\s+)+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !plain.isEmpty { return plain }
        }
        return nil
    }
}

/// Where the panel goes on the screens. Frames are in AppKit's screen coordinates (y grows upward);
/// `visible` frames are the screens' areas below the menu bar and beside the Dock.
public enum PanelPlacement {
    /// The top-right corner of `visible`, `margin` in from both edges.
    public static func topRight(_ size: CGSize, in visible: CGRect, margin: CGFloat = 12) -> CGRect {
        CGRect(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin,
               width: size.width, height: size.height)
    }

    /// `frame` moved (never resized) to lie on a screen: where it is when it does; else into the screen
    /// it overlaps most (the top kept when it's taller); else (that screen is gone) to the top right
    /// of the first screen.
    public static func onScreen(_ frame: CGRect, visible screens: [CGRect], margin: CGFloat = 12) -> CGRect {
        guard let first = screens.first else { return frame }
        if screens.contains(where: { $0.contains(frame) }) { return frame }
        let overlaps = screens.map { screen -> CGFloat in
            let common = screen.intersection(frame)
            return common.isNull ? 0 : common.width * common.height
        }
        guard let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 else {
            return topRight(frame.size, in: first, margin: margin)
        }
        let screen = screens[best]
        var moved = frame
        moved.origin.x = frame.width > screen.width ? screen.minX : min(max(frame.minX, screen.minX), screen.maxX - frame.width)
        moved.origin.y = frame.height > screen.height ? screen.maxY - frame.height
                                                      : min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        return moved
    }
}

/// A background task as the panel lists it.
public struct AgentTaskRow: Equatable, Sendable, Identifiable {
    /// The short id, which opening it takes (`claude attach`).
    public var id: String
    /// Its name (else the prompt @claude started it with, else its id), on one line.
    public var title: String
    public var progress: AgentSession.Progress
    public var started: Date?
    /// The first line of its last reply.
    public var reply: String?

    public init(id: String, title: String, progress: AgentSession.Progress, started: Date?, reply: String?) {
        self.id = id
        self.title = title
        self.progress = progress
        self.started = started
        self.reply = reply
    }
}

public enum AgentTaskList {
    /// How many the panel shows.
    public static let limit = 6

    /// When the session started: `claude agents --json` gives milliseconds since 1970 (seconds are
    /// read too).
    public static func started(_ session: AgentSession) -> Date? {
        guard let value = session.startedAt, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }

    /// The newest `limit` sessions, newest first.
    public static func newest(_ sessions: [AgentSession], limit: Int = limit) -> [AgentSession] {
        let time = { (session: AgentSession) in started(session)?.timeIntervalSince1970 ?? 0 }
        return Array(sessions.sorted { time($0) > time($1) }.prefix(max(limit, 0)))
    }

    /// The rows of the newest sessions, with the replies read so far (session id → first line) and the
    /// prompts of the tasks @claude started (short id → prompt) for those Claude Code hasn't named yet.
    public static func rows(_ sessions: [AgentSession], replies: [String: String],
                            prompt: (String) -> String? = { _ in nil }) -> [AgentTaskRow] {
        newest(sessions).map { session in
            let title = [session.name, prompt(session.shortID)].lazy.compactMap { $0.map(oneLine) }.first { !$0.isEmpty }
            return AgentTaskRow(id: session.shortID, title: title ?? session.shortID, progress: session.progress,
                                started: started(session), reply: replies[session.sessionId])
        }
    }

    /// Runs of spaces and line breaks as one space.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}

/// The last replies the panel shows, read from the transcripts (files that grow with the session, to
/// megabytes for a long one): a transcript is read again only when its size or modification date
/// changed (a task waiting for the user doesn't change it), and then only its last `tailBytes`.
public struct AgentReplyCache: Equatable, Sendable {
    /// What was read of a session's transcript.
    public struct Read: Equatable, Sendable {
        public var file: URL
        /// The file's size and modification date when it was read.
        public var size: UInt64
        public var modified: Date
        /// The first line of the last reply (`DashboardText.firstLine`).
        public var reply: String?

        public init(file: URL, size: UInt64, modified: Date, reply: String?) {
            self.file = file
            self.size = size
            self.modified = modified
            self.reply = reply
        }
    }

    /// How much of a transcript's end is read: the last reply is near it (what may follow it, tool
    /// calls and their output, rarely runs that long).
    public static let tailBytes = 256 * 1024

    /// Session id → what was read.
    private var entries: [String: Read] = [:]

    public init() {}

    /// What was read so far (session id → read), for `readChanged(_:known:)`.
    public var known: [String: Read] { entries }

    /// Takes in what `readChanged(_:known:)` read.
    public mutating func store(_ read: [String: Read]) {
        entries.merge(read) { $1 }
    }

    /// Forgets the sessions not among `sessions` (no longer shown).
    public mutating func keep(only sessions: [AgentSession]) {
        let ids = Set(sessions.map(\.sessionId))
        entries = entries.filter { ids.contains($0.key) }
    }

    /// Session id → the reply's first line.
    public var replies: [String: String] { entries.compactMapValues(\.reply) }

    /// Reads the transcripts of `sessions` not read yet, or changed (their size or modification date)
    /// since `known`: session id → what was read. Those unchanged, and those without a transcript yet,
    /// are left out. When the tail read has no reply, the one read before stays. Reads files: off
    /// the main thread.
    public static func readChanged(_ sessions: [AgentSession], known: [String: Read], root: URL = ClaudeAgents.projectsRoot,
                                   tailBytes: Int = AgentReplyCache.tailBytes) -> [String: Read] {
        let fm = FileManager.default
        var read: [String: Read] = [:]
        for session in sessions {
            let before = known[session.sessionId]
            // Where it was before, while it's there: Claude Code's folders aren't listed again for it.
            let file = before.map(\.file).flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
                ?? ClaudeAgents.transcript(sessionId: session.sessionId, cwd: session.cwd, root: root)
            // The file's own attributes each time (URL resource values would be cached).
            guard let file, let attributes = try? fm.attributesOfItem(atPath: file.path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value,
                  let modified = attributes[.modificationDate] as? Date else { continue }
            if let before, before.file == file, before.size == size, before.modified == modified { continue }
            let reply = DashboardText.firstLine(lastReply(tailOf: file, bytes: tailBytes))
            read[session.sessionId] = Read(file: file, size: size, modified: modified, reply: reply ?? before?.reply)
        }
        return read
    }

    /// The last reply in the last `bytes` of a transcript (the line cut at its start left out).
    static func lastReply(tailOf file: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end - min(end, UInt64(max(bytes, 0)))
        guard (try? handle.seek(toOffset: start)) != nil, var tail = try? handle.readToEnd() else { return nil }
        if start > 0 {
            guard let newline = tail.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            tail = tail[tail.index(after: newline)...]
        }
        return ClaudeAgents.lastReply(in: String(decoding: tail, as: UTF8.self))
    }
}
