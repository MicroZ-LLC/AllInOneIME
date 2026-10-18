import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Where `@note` saves (`Config.notes`): Apple Notes (the shell's own destination, by AppleScript on the Mac), a folder of
// Markdown files (`MarkdownFolderDestination`), or Notion (`NotionDestination`). The composer hands the text over
// (`Composer.Effect.saveNote`); the shell makes the destination (`NoteDestinations.make`), saves, and says where the note
// went. A failed save loses nothing: the shell puts the text back in the draft or on the clipboard. There is no outbox
// and no retry.

/// A place `@note` saves to.
public protocol NoteDestination: Sendable {
    /// Its name in the notices ("Saved to Notion"): "Notion", "Obsidian", a folder's name in quotes (“Inbox”), the
    /// shell's name for Apple Notes.
    var name: String { get }
    /// Whether the note leaves this device (Notion): such a save is refused while secure input is on.
    var leavesDevice: Bool { get }
    /// Saves `draft` as a new note: never half of it, never over another note.
    func save(_ draft: NoteDraft) async throws -> SavedNoteRef
    /// Checks that saving can work (Settings' Test): what it found, to show after a ✓.
    func check() async throws -> String
}

/// A note to save: the text as typed, and when it was written (in its time zone, for a file's front matter and a name
/// made of the time).
public struct NoteDraft: Equatable, Sendable {
    public var text: String
    public var created: Date
    public var timeZone: TimeZone

    public init(text: String, created: Date = Date(), timeZone: TimeZone = .current) {
        self.text = text
        self.created = created
        self.timeZone = timeZone
    }

    /// The first line exactly (Notion's title).
    public var title: String {
        String(text[..<(text.firstIndex(where: \.isNewline) ?? text.endIndex)])
    }

    /// Everything after the first line break ("\r\n" is one).
    public var body: String {
        guard let end = text.firstIndex(where: \.isNewline) else { return "" }
        return String(text[text.index(after: end)...])
    }
}

/// What a save made: its id, which the menu bar panel keeps and opens (`x-coredata:` a note in Notes, `file:` a file,
/// `https:` a Notion page), and its title. Nil: a note the panel doesn't list.
public struct SavedNoteRef: Equatable, Sendable {
    public var id: String?
    public var title: String
    /// Where it went, as the "Saved to …" notice says it, when the save found out better than `NoteDestination.name`
    /// could before (a folder found to be in an Obsidian vault: "Obsidian"); nil: the destination's name.
    public var destinationName: String?

    public init(id: String?, title: String, destinationName: String? = nil) {
        self.id = id
        self.title = title
        self.destinationName = destinationName
    }
}

/// Why a note wasn't saved to a folder or to Notion; each says what to do (`message(language:)`, which the shell shows).
public enum NoteError: Error, LocalizedError, Equatable, Sendable {
    /// The folder isn't there (an unmounted volume, a moved vault): it is never made.
    case folderMissing(path: String)
    /// 401: the token was revoked, or is no token.
    case notionUnauthorized
    /// 403, or 404: the page or database isn't shared with the integration.
    case notionNotShared
    /// 429.
    case notionBusy
    /// 400 (or another 4xx): Notion's error code.
    case notionRefused(code: String)
    /// 5xx, or an answer that can't be read.
    case notionTrouble(status: Int)
    /// Not connected, the connection lost, the host not found.
    case offline
    /// No answer within `seconds`.
    case notionTimedOut(seconds: Int)
    /// No token, or no page or database.
    case notionNotSetUp
    /// A link to check (Settings) that isn't one to a Notion page or database.
    case notNotionLink

    public var errorDescription: String? { message(language: "en") }

    /// What the notices and Settings say.
    public func message(language: String) -> String {
        let t = InterfaceWords(language: language)
        switch self {
        case .folderMissing:
            return t.tr("笔记文件夹不在了：在设置里重新选择", "The notes folder is gone: choose it again in Settings")
        case .notionUnauthorized:
            return t.tr("Notion 令牌无效：在设置 → 插件里粘贴新的", "The Notion token isn't valid: paste a new one in Settings → Plugins")
        case .notionNotShared:
            return t.tr("这个 Notion 页面没有分享给你的集成：··· → 连接",
                        "The Notion page isn't shared with your integration: ··· → Connections")
        case .notionBusy:
            return t.tr("Notion 正忙：稍后再试", "Notion is busy: try again in a moment")
        case let .notionRefused(code):
            return t.tr("Notion 没有接受这条笔记（\(code)）", "Notion refused the note (\(code))")
        case let .notionTrouble(status):
            return t.tr("Notion 出了问题（HTTP \(status)）", "Notion is having trouble (HTTP \(status))")
        case .offline:
            return t.tr("没有联网：没有存到 Notion", "Offline: not saved to Notion")
        case let .notionTimedOut(seconds):
            return t.tr("Notion \(seconds) 秒内没有回应", "Notion didn't answer within \(seconds) s")
        case .notionNotSetUp:
            return t.tr("Notion 还没设置好：设置 → 插件 → 笔记", "Notion isn't set up: Settings → Plugins → Notes")
        case .notNotionLink:
            return t.tr("不是 Notion 链接", "Not a Notion link")
        }
    }

    /// Only the user can fix it, in Settings (the notice stays up longer, the text goes on the clipboard too).
    public var needsTheUser: Bool {
        switch self {
        case .folderMissing, .notionUnauthorized, .notionNotShared, .notionNotSetUp, .notNotionLink: return true
        case .notionBusy, .notionRefused, .notionTrouble, .offline, .notionTimedOut: return false
        }
    }
}

/// Where `@note` saves (`Config.notes`): Notes by default.
public struct NoteSettings: Codable, Equatable, Sendable {
    public enum Destination: String, Codable, CaseIterable, Sendable {
        case notes, folder, notion
    }

    public var destination: Destination
    /// The folder of Markdown files, as "~/…" when it is in the home folder.
    public var folder: String?
    /// The Notion page or database, as Test resolved it (`NotionAPI.resolve`).
    public var notion: NotionTarget?

    public init(destination: Destination = .notes, folder: String? = nil, notion: NotionTarget? = nil) {
        self.destination = destination
        self.folder = folder
        self.notion = notion
    }

    /// `folder` with "~" expanded; nil when there is none.
    public var folderURL: URL? {
        guard let path = folder?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    enum CodingKeys: String, CodingKey { case destination, folder, notion }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One this version doesn't know (a later one's): Notes.
        destination = (try? c.decodeIfPresent(String.self, forKey: .destination)).flatMap { $0 }.flatMap(Destination.init(rawValue:))
            ?? .notes
        folder = (try? c.decodeIfPresent(String.self, forKey: .folder)).flatMap { $0 }
        notion = (try? c.decodeIfPresent(NotionTarget.self, forKey: .notion)).flatMap { $0 }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(destination, forKey: .destination)
        try c.encodeIfPresent(folder, forKey: .folder)
        try c.encodeIfPresent(notion, forKey: .notion)
    }
}

/// Makes the destination `Config.notes` names.
public enum NoteDestinations {
    /// `system` (the shell's Apple Notes) for Notes, and for a folder destination without a folder; a folder of Markdown
    /// files; Notion, its token read from the keychain only when a note is saved (`NotionAPI.loadToken`).
    public static func make(_ settings: NoteSettings, system: any NoteDestination,
                            session: URLSession = NotionAPI.session,
                            token: @escaping @Sendable () -> String? = { NotionAPI.loadToken() }) -> any NoteDestination {
        switch settings.destination {
        case .notes:
            return system
        case .folder:
            guard let folder = settings.folderURL else { return system }
            return MarkdownFolderDestination(folder: folder)
        case .notion:
            return NotionDestination(target: settings.notion, token: token, session: session)
        }
    }

    /// What opens a saved note (the menu bar panel), by its id's scheme: a file in an Obsidian vault in Obsidian, another
    /// file in its default app (`MarkdownFolderDestination.openURL`), a Notion page by its address. Nil for a note in
    /// Notes (`x-coredata:`, which only Notes shows) and anything else.
    public static func openURL(forSaved id: String) -> URL? {
        guard let url = URL(string: id), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "file": return MarkdownFolderDestination.openURL(for: url)
        case "https": return url
        default: return nil
        }
    }
}
