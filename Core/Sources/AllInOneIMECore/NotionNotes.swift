import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Notion page or database `@note` saves under (`Config.notes.notion`), as Settings' Test resolved it from a link
/// (`NotionAPI.resolve`): a page gets a new child page; a database gets a new row, under its (first) data source, titled
/// by its title property.
public struct NotionTarget: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case page, database
    }

    /// The page's or database's id, a dashed UUID.
    public var id: String
    public var kind: Kind
    /// A database's first data source, and its title property ("Name").
    public var dataSource: String?
    public var titleProperty: String?
    /// The page's or database's title, for Settings.
    public var title: String?

    public init(id: String, kind: Kind, dataSource: String? = nil, titleProperty: String? = nil, title: String? = nil) {
        self.id = id
        self.kind = kind
        self.dataSource = dataSource
        self.titleProperty = titleProperty
        self.title = title
    }

    /// As Test shows it: "“Inbox” (database)".
    public func label(language: String) -> String {
        let t = InterfaceWords(language: language)
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? String(id.prefix(8))
        return "“" + name + "”" + (kind == .database ? t.tr("（数据库）", " (database)") : t.tr("（页面）", " (page)"))
    }
}

/// `@note` into Notion, with the user's internal integration token (`NotionAPI.loadToken`): one `POST /v1/pages` for
/// the whole note (`NotionFormat.request`), within 15 s, never retried. The note leaves the device: refused while secure
/// input is on (`Composer.noteLeavesDevice`).
public struct NotionDestination: NoteDestination {
    public let target: NotionTarget?
    private let token: @Sendable () -> String?
    private let session: URLSession

    public init(target: NotionTarget?, token: String?, session: URLSession = NotionAPI.session) {
        self.init(target: target, token: { token }, session: session)
    }

    /// `token` is read when a note is saved (from the keychain, off the main thread).
    public init(target: NotionTarget?, token: @escaping @Sendable () -> String?, session: URLSession = NotionAPI.session) {
        self.target = target
        self.token = token
        self.session = session
    }

    public var name: String { "Notion" }
    public var leavesDevice: Bool { true }

    private func setUp() throws -> (NotionTarget, String) {
        let token = token()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let target, !token.isEmpty else { throw NoteError.notionNotSetUp }
        return (target, token)
    }

    public func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
        let (target, token) = try setUp()
        let request = try NotionFormat.request(for: draft, to: target, token: token)
        let (status, body) = try await NotionAPI.send(request, session: session)
        guard (200..<300).contains(status) else { throw NotionAPI.error(status: status, body: body) }
        let page = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let url = (page?["url"] as? String).flatMap { $0.lowercased().hasPrefix("https:") ? $0 : nil }
        return SavedNoteRef(id: url, title: draft.title)
    }

    /// The page or database resolved again: "“Inbox” (database)".
    public func check() async throws -> String {
        let (target, token) = try setUp()
        return try await NotionAPI.resolve(target.id, token: token, session: session).label(language: "en")
    }
}

/// The id in a Notion link.
public enum NotionLink {
    /// The page's or database's id in a notion.so or notion.site link: the last run of 32 hex digits in its path (dashes
    /// allowed; the query, `?v=` a database's view and `?p=` a page peeked at, is ignored), as a dashed lowercase UUID.
    /// Nil for anything else.
    public static func id(from link: String) -> String? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = components.host?.lowercased(),
              ["notion.so", "notion.site"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        var runs: [String] = [], run = ""
        for character in components.path {
            if isHex(character) || character == "-" {
                run.append(character)
            } else if !run.isEmpty {
                runs.append(run)
                run = ""
            }
        }
        if !run.isEmpty { runs.append(run) }
        for run in runs.reversed() {
            let hex = run.filter(isHex)
            guard hex.count >= 32 else { continue }
            return dashed(String(hex.suffix(32)).lowercased())
        }
        return nil
    }

    private static func isHex(_ c: Character) -> Bool { c.isASCII && c.isHexDigit }

    /// 32 hex digits as 8-4-4-4-12.
    static func dashed(_ hex: String) -> String {
        let h = Array(hex)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(h[$0]) }.joined(separator: "-")
    }
}

/// A note as Notion's API takes it.
public enum NotionFormat {
    /// Notion's limits: characters of one rich-text piece (counted as JavaScript counts them, UTF-16), pieces in one
    /// rich-text array, blocks in one request.
    public static let maxText = 2000
    public static let maxPieces = 100
    public static let maxBlocks = 100

    /// `text` in pieces of at most `maxText` (never a character cut in two), nothing lost.
    public static func pieces(_ text: String) -> [String] {
        var out: [String] = [], piece = "", units = 0
        for character in text {
            let size = character.utf16.count
            if units + size > maxText, !piece.isEmpty {
                out.append(piece)
                (piece, units) = ("", 0)
            }
            piece.append(character)
            units += size
        }
        if !piece.isEmpty { out.append(piece) }
        return out
    }

    /// The body's paragraphs: its blank-line-separated runs of lines, line breaks ("\n") kept inside them.
    public static func paragraphs(_ body: String) -> [String] {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        var out: [String] = [], current: [Substring] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { out.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { out.append(current.joined(separator: "\n")) }
        return out
    }

    /// The body as paragraph blocks, each block's text pieces: a block per paragraph; more than `maxBlocks` paragraphs
    /// share blocks (joined by a blank line), so that one request holds the whole note.
    public static func blocks(_ body: String) -> [[String]] {
        let paragraphs = paragraphs(body)
        guard !paragraphs.isEmpty else { return [] }
        let size = (paragraphs.count + maxBlocks - 1) / maxBlocks
        let grouped = stride(from: 0, to: paragraphs.count, by: size).map {
            paragraphs[$0..<min($0 + size, paragraphs.count)].joined(separator: "\n\n")
        }
        let blocks = grouped.flatMap { chunked(pieces($0)) }
        if blocks.count <= maxBlocks { return blocks }
        // Very long paragraphs: the pieces spread evenly over the blocks.
        let all = grouped.flatMap(pieces)
        let perBlock = (all.count + maxBlocks - 1) / maxBlocks
        return stride(from: 0, to: all.count, by: perBlock).map { Array(all[$0..<min($0 + perBlock, all.count)]) }
    }

    private static func chunked(_ pieces: [String]) -> [[String]] {
        stride(from: 0, to: pieces.count, by: maxPieces).map { Array(pieces[$0..<min($0 + maxPieces, pieces.count)]) }
    }

    /// `POST /v1/pages`: a child page of a page, or a row of a database's data source; the title is the first line
    /// exactly, the body the rest (`blocks`). A database without its data source or title property isn't set up.
    public static func request(for draft: NoteDraft, to target: NotionTarget, token: String,
                               timeout: TimeInterval = NotionAPI.saveTimeout) throws -> URLRequest {
        let parent: [String: String]
        let titleName: String
        switch target.kind {
        case .page:
            parent = ["type": "page_id", "page_id": target.id]
            titleName = "title"
        case .database:
            guard let source = target.dataSource, !source.isEmpty, let property = target.titleProperty, !property.isEmpty else {
                throw NoteError.notionNotSetUp
            }
            parent = ["type": "data_source_id", "data_source_id": source]
            titleName = property
        }
        let children = blocks(draft.body).map { Block(paragraph: Paragraph(richText: $0.map(RichText.init))) }
        let page = PageRequest(parent: parent, properties: [titleName: TitleProperty(title: pieces(draft.title).map(RichText.init))],
                               children: children.isEmpty ? nil : children)
        var request = NotionAPI.request("POST", "pages", token: token, timeout: timeout)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        request.httpBody = try encoder.encode(page)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private struct PageRequest: Encodable {
        var parent: [String: String]
        var properties: [String: TitleProperty]
        var children: [Block]?
    }

    private struct TitleProperty: Encodable {
        var title: [RichText]
    }

    private struct RichText: Encodable {
        struct Content: Encodable { var content: String }
        var type = "text"
        var text: Content

        init(_ content: String) { text = Content(content: content) }
    }

    private struct Paragraph: Encodable {
        var richText: [RichText]
        enum CodingKeys: String, CodingKey { case richText = "rich_text" }
    }

    private struct Block: Encodable {
        var object = "block"
        var type = "paragraph"
        var paragraph: Paragraph
    }
}

/// Notion's API, version pinned (`version`): saving a page, resolving a link's id, reading its errors. Requests go to
/// `host` over HTTPS and nowhere else (redirects aren't followed), with the token in a header.
public enum NotionAPI {
    public static let version = "2025-09-03"
    public static let host = "api.notion.com"
    /// Where an internal integration (and its token) is made.
    public static let integrationsPage = URL(string: "https://www.notion.so/profile/integrations")!
    /// A save's time, and Test's.
    public static let saveTimeout: TimeInterval = 15
    public static let checkTimeout: TimeInterval = 10
    /// Of an answer (a data source with many properties is some tens of KB).
    static let maxBytes = 4 << 20

    /// The token's keychain item (`APIKeys`): sent to `host` only.
    public static let keyAccount = "notion"
    public static let keyLabel = "AllInOneIME: Notion"

    /// The token in the keychain (it may ask for the login password: not on the main thread).
    public static func loadToken() -> String? { APIKeys.load(account: keyAccount, variables: []) }

    public static func saveToken(_ token: String) throws {
        try APIKeys.save(token, account: keyAccount, label: keyLabel, host: host)
    }

    public static func removeToken() throws { try APIKeys.remove(account: keyAccount) }

    /// No cache, no cookies, nothing kept on disk.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// A request to `https://api.notion.com/v1/<path>`, with the token and the version.
    static func request(_ method: String, _ path: String, token: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(host)/v1/\(path)")!, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(version, forHTTPHeaderField: "Notion-Version")
        return request
    }

    /// Sends `request` (to `host` only) and reads the answer: its status and body. Offline and a timeout are `NoteError`s.
    static func send(_ request: URLRequest, session: URLSession) async throws -> (status: Int, body: Data) {
        guard let url = request.url, url.scheme == "https", url.host == host else { throw URLError(.badURL) }
        do {
            let (bytes, response) = try await HTTPStream.bytes(for: request, session: session, redirect: { _ in nil })
            guard let http = response as? HTTPURLResponse else { throw NoteError.notionTrouble(status: 0) }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > maxBytes { throw NoteError.notionTrouble(status: http.statusCode) }
            }
            return (http.statusCode, body)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .dataNotAllowed, .internationalRoamingOff:
                throw NoteError.offline
            case .timedOut:
                throw NoteError.notionTimedOut(seconds: Int(request.timeoutInterval.rounded()))
            default:
                throw error
            }
        }
    }

    /// What an unsuccessful answer means.
    public static func error(status: Int, body: Data) -> NoteError {
        switch status {
        case 401: return .notionUnauthorized
        case 403, 404: return .notionNotShared
        case 429: return .notionBusy
        case 400..<500:
            let answer = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let code = (answer?["code"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
            return .notionRefused(code: code ?? "HTTP \(status)")
        default: return .notionTrouble(status: status)
        }
    }

    /// What a link's id is (`NotionLink.id`): a page (`GET /v1/pages/{id}`), else a database (`GET /v1/databases/{id}`),
    /// its first data source and that one's title property (`GET /v1/data_sources/{id}`). Within `checkTimeout` each.
    public static func resolve(_ id: String, token: String, session: URLSession = NotionAPI.session) async throws -> NotionTarget {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        func get(_ path: String) async throws -> (status: Int, object: [String: Any]?, body: Data) {
            let (status, body) = try await send(request("GET", path, token: token, timeout: checkTimeout), session: session)
            return (status, (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], body)
        }
        let page = try await get("pages/\(id)")
        if page.status == 200 {
            let properties = page.object?["properties"] as? [String: Any] ?? [:]
            let title = properties.values.lazy.compactMap { $0 as? [String: Any] }.first { $0["type"] as? String == "title" }
                .map { plainText($0["title"]) }
            return NotionTarget(id: page.object?["id"] as? String ?? id, kind: .page, title: title)
        }
        // A database isn't a page: 404 (or a validation error, as some versions answer).
        guard page.status == 404 || page.status == 400 else { throw error(status: page.status, body: page.body) }
        let database = try await get("databases/\(id)")
        guard database.status == 200 else { throw error(status: database.status, body: database.body) }
        let sources = database.object?["data_sources"] as? [[String: Any]] ?? []
        guard let source = sources.first?["id"] as? String else { throw NoteError.notionTrouble(status: database.status) }
        let dataSource = try await get("data_sources/\(source)")
        guard dataSource.status == 200 else { throw error(status: dataSource.status, body: dataSource.body) }
        let properties = dataSource.object?["properties"] as? [String: Any] ?? [:]
        guard let (name, property) = properties.first(where: { ($0.value as? [String: Any])?["type"] as? String == "title" })
        else { throw NoteError.notionTrouble(status: dataSource.status) }
        let titleProperty = ((property as? [String: Any])?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
        return NotionTarget(id: database.object?["id"] as? String ?? id, kind: .database, dataSource: source,
                            titleProperty: titleProperty, title: plainText(database.object?["title"]))
    }

    /// A rich-text array's text.
    static func plainText(_ value: Any?) -> String {
        ((value as? [[String: Any]]) ?? []).map { piece in
            piece["plain_text"] as? String ?? ((piece["text"] as? [String: Any])?["content"] as? String ?? "")
        }.joined()
    }
}
