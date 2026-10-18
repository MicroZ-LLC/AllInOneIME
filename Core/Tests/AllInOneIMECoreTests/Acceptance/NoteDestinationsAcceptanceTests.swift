#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation
import Testing
import AllInOneIMETestSupport
@testable import AllInOneIMECore

// Acceptance tests for "where @note saves: Notes, a folder, Notion" (0.6.5/note-destinations), written from the spec
// only (spec C, "Acceptance scenarios (Core)" S1–S14), independently of the implementation's own tests. Each test is
// named after the scenario it checks. Apple Notes stays in the app (`AppleNotesDestination`), so here the system's
// destination is a fake (`NDFakeSystemNotes`). Notion is never reached: every Notion call goes through `NDNotionStub`, a
// URLProtocol that serves canned answers in Notion's shapes; it routes by the bearer token, a fresh one per test, so the
// tests can run in parallel. Folders are fresh temporary ones.
//
// ASSUMPTIONS (where the spec names a thing but not its exact shape; the narrowest reading, for the implementer to match):
//  A1. `Config.notes` is a `NoteSettings` with `destination` (an enum with cases `.notes`, `.folder`, `.notion`, coded as
//      "notes" / "folder" / "notion"), `folder` (a String, or String?) and `notion` (optional; the type `NotionAPI.resolve`
//      returns, with `id`, `kind` (`.page` / `.database`), `dataSource`, `titleProperty`, `title`, coded with the spec's
//      JSON keys). The tests build a Notion target only by decoding the spec's config JSON, so its type name is free.
//  A2. `protocol NoteDestination` requires exactly: `var name: String { get }`, `var leavesDevice: Bool { get }`,
//      `func save(_ draft: NoteDraft) async throws -> SavedNoteRef`, `func check() async throws -> String`.
//  A3. `NoteDraft(text: String, created: Date, timeZone: TimeZone)`, with `title` (the first line exactly) and `body`
//      (everything after the first line break).
//  A4. `SavedNoteRef` has `id: String?` and `title: String`, and `init(id:title:)`. A Folder save's id is the new file's
//      `file:` URL string; a Notion save's id is the page's `url` from Notion's answer (`https:`).
//  A5. `NoteError` is an Error with a case `.folderMissing` (matched by pattern, associated values allowed) and
//      `message(language: String) -> String` (as `AWSCredentialError` has), which `UIText.describe` shows. The tests read
//      its English (`language: "en"`), which must be the spec's table text exactly.
//  A6. `NoteDestinations.make(_ settings: NoteSettings, system: any NoteDestination) -> any NoteDestination`, not
//      throwing: `system` is the shell's Apple Notes destination, returned for `.notes`.
//  A7. `MarkdownFolderDestination(folder: URL)`; static `fileName(for: NoteDraft, existing:)` (existing: the folder's file
//      names with their extension, passed as an array literal, so `Set<String>` or `[String]` both fit) returning the
//      name with ".md"; static `document(for: NoteDraft) -> String`; static `vaultRoot(of folder: URL) -> URL?` (the
//      folder holding `.obsidian`); and static `openURL(for file: URL) -> URL`: `obsidian://open?path=<the file's
//      absolute path>` inside a vault, else the file's own URL (opened in the default app). Its `name` is "Obsidian" in
//      a vault, else the folder's name (bare, or in curly quotes as the notice shows it: “Inbox”).
//  A8. The front matter is "---\n" … "\n---\n" and holds a line `created: <ISO 8601 with its offset>`; the text as typed
//      follows (one blank line between them is allowed).
//  A9. `NotionDestination(target: <Config.notes.notion>, token: String?, session: URLSession)`, name "Notion". A save is
//      one `POST https://api.notion.com/v1/pages` with the body Notion documents: `parent` {"page_id": id} or
//      {"data_source_id": dataSource} (a "type" key beside it is fine), `properties` with one title property ("title" for
//      a page, `titleProperty` for a database row) holding rich text, and `children`: paragraph blocks
//      (`{"type":"paragraph","paragraph":{"rich_text":[{"type":"text","text":{"content":…}}]}}`). Packing several
//      paragraphs into one block (past 100) may join them any way: "nothing lost" is checked on the text without
//      whitespace, in order.
//  A10. `NotionAPI.resolve(_ id: String, token: String, session: URLSession) async throws` returns the stored target; its
//       requests time out at 10 s (Test), a save's at 15 s. `NotionAPI.error(status: Int, body: Data) -> NoteError`.
//  A11. `NotionLink.id(from: String) -> String?`: lowercase hex, dashed 8-4-4-4-12.
//  A12. `Composer.noteLeavesDevice` is a settable `Bool` (the controller sets it from the destination's `leavesDevice`),
//       and `Composer.Messages.secureInputNote` is the notice: English "Secure input is on: not saved to Notion".
//  A13. `SavedNotes.dropMissingFiles(exists:)` is mutating and takes a closure over a file entry (its URL or path; the
//       tests' closure works for either). `reconcile(with:limit:)` keeps its signature.

// MARK: - Helpers

/// "@" as AppKit delivers it (⇧2).
fileprivate let ndAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

fileprivate enum ND {
    static let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    /// 2026-10-17 14:03:00 in Shanghai (+08:00).
    static var created: Date {
        var parts = DateComponents(year: 2026, month: 10, day: 17, hour: 14, minute: 3, second: 0)
        parts.timeZone = shanghai
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        return calendar.date(from: parts)!
    }

    static func draft(_ text: String) -> NoteDraft { NoteDraft(text: text, created: created, timeZone: shanghai) }

    /// A fresh, empty temporary folder (never the user's).
    static func tempFolder(_ name: String = "Inbox") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-dest-acceptance-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func files(_ folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    static func samePath(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func english(_ error: Error) -> String? { (error as? NoteError)?.message(language: "en") }

    static func decode(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }

    static let pageID = "0123456789abcdef0123456789abcdef"
    static let pageUUID = "01234567-89ab-cdef-0123-456789abcdef"
    static let databaseUUID = "fedcba98-7654-3210-fedc-ba9876543210"
    static let dataSourceUUID = "11112222-3333-4444-5555-666677778888"

    /// Config.notes for a Notion page, as the config file holds it.
    static func pageSettings() throws -> NoteSettings {
        try decode(#"{"notes":{"destination":"notion","notion":{"id":"\#(pageUUID)","kind":"page","title":"Journal"}}}"#).notes
    }

    /// Config.notes for a Notion database (its data source and title property), as the config file holds it.
    static func databaseSettings() throws -> NoteSettings {
        try decode(#"""
            {"notes":{"destination":"notion","notion":{"id":"\#(databaseUUID)","kind":"database","dataSource":"\#(dataSourceUUID)",
            "titleProperty":"Task name","title":"Inbox"}}}
            """#).notes
    }

    /// A composer in English mode with `text` typed after "@note ", as a text field has it.
    static func noteComposer(_ text: String) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.messages = .english
        c.setInputMode(.english)
        for ch in "@note " + text {
            _ = c.handleKeyDown(ch == "@" ? ndAt : ch == " " ? spaceKey : k(String(ch)))
        }
        return c
    }

    static func saves(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .saveNote(text) = $0 { return text } else { return nil } }
    }

    static func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(text) = $0 { return text } else { return nil } }
    }

    // Reading Notion request bodies.

    static func json(_ data: Data?) -> [String: Any] {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    /// The `text.content` of each rich-text piece.
    static func contents(_ richText: Any?) -> [String] {
        ((richText as? [[String: Any]]) ?? []).compactMap { ($0["text"] as? [String: Any])?["content"] as? String }
    }

    /// The paragraph blocks of a page request: each block's pieces.
    static func paragraphs(_ body: [String: Any]) -> [[String]] {
        ((body["children"] as? [[String: Any]]) ?? []).map { block in
            #expect(block["type"] as? String == "paragraph", "a block that isn't a paragraph: \(block)")
            return contents((block["paragraph"] as? [String: Any])?["rich_text"])
        }
    }

    /// The title property of a page request: its name and its text.
    static func titleProperty(_ body: [String: Any]) -> (name: String, text: String)? {
        guard let properties = body["properties"] as? [String: Any], properties.count == 1,
              let (name, value) = properties.first, let property = value as? [String: Any] else { return nil }
        return (name, contents(property["title"]).joined())
    }

    static func noWhitespace(_ text: String) -> String { String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init)) }
}

/// A stand-in for the shell's Apple Notes destination: records what it is asked to save, or fails.
fileprivate final class NDFakeSystemNotes: NoteDestination, @unchecked Sendable {
    struct Failed: Error {}
    let name = "Notes"
    let leavesDevice = false
    private let lock = NSLock()
    private var drafts: [String] = []
    let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    var saved: [String] { lock.lock(); defer { lock.unlock() }; return drafts }

    func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
        if fails { throw Failed() }
        let count = record(draft.text)
        return SavedNoteRef(id: "x-coredata://FAKE/ICNote/p\(count)", title: NotesFormat.title(of: draft.text))
    }

    /// Keeps `text`; how many are kept now.
    private func record(_ text: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        drafts.append(text)
        return drafts.count
    }

    func check() async throws -> String { "✓" }
}

// MARK: - Notion, stubbed

fileprivate enum NDReply: Sendable {
    case json(Int, String)
    case fail(URLError.Code)
}

/// What a stubbed request was.
fileprivate struct NDSeen: Sendable {
    var method: String
    var url: String
    var path: String
    var authorization: String?
    var version: String?
    var timeout: TimeInterval
    var body: Data?
}

fileprivate final class NDRoutes: @unchecked Sendable {
    static let shared = NDRoutes()
    private let lock = NSLock()
    private var handlers: [String: @Sendable (NDSeen) -> NDReply] = [:]
    private var seen: [String: [NDSeen]] = [:]

    func serve(_ token: String, _ handler: @escaping @Sendable (NDSeen) -> NDReply) {
        lock.lock(); defer { lock.unlock() }
        handlers[token] = handler
        seen[token] = []
    }

    func take(_ request: NDSeen) -> NDReply {
        let token = request.authorization.map { $0.hasPrefix("Bearer ") ? String($0.dropFirst(7)) : $0 } ?? "(none)"
        lock.lock(); defer { lock.unlock() }
        seen[token, default: []].append(request)
        return handlers[token]?(request) ?? .fail(.cannotFindHost)
    }

    func requests(_ token: String) -> [NDSeen] {
        lock.lock(); defer { lock.unlock() }
        return seen[token] ?? []
    }
}

/// Notion's API, never reached: answers by the bearer token.
fileprivate final class NDNotionStub: URLProtocol, @unchecked Sendable {
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NDNotionStub.self]
        return URLSession(configuration: configuration)
    }

    /// A fresh token, served by `handler`.
    static func token(_ handler: @escaping @Sendable (NDSeen) -> NDReply) -> String {
        let token = "secret_nd_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        NDRoutes.shared.serve(token, handler)
        return token
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    override func startLoading() {
        let request = self.request
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let seen = NDSeen(method: request.httpMethod ?? "GET", url: url.absoluteString, path: url.path,
                          authorization: request.value(forHTTPHeaderField: "Authorization"),
                          version: request.value(forHTTPHeaderField: "Notion-Version"),
                          timeout: request.timeoutInterval, body: Self.body(of: request))
        switch NDRoutes.shared.take(seen) {
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .json(status, text):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Answers in Notion's shapes.
fileprivate enum NDNotion {
    static func error(_ status: Int, _ code: String) -> NDReply {
        .json(status, #"{"object":"error","status":\#(status),"code":"\#(code)","message":"stubbed"}"#)
    }

    static let createdURL = "https://www.notion.so/Groceries-99998888777766665555444433332222"

    /// What `POST /v1/pages` answers.
    static let created = NDReply.json(200, #"""
        {"object":"page","id":"99998888-7777-6666-5555-444433332222","url":"\#(createdURL)",
         "parent":{"type":"page_id","page_id":"\#(ND.pageUUID)"},"properties":{}}
        """#)

    static let page = NDReply.json(200, #"""
        {"object":"page","id":"\#(ND.pageUUID)","url":"https://www.notion.so/Journal-\#(ND.pageID)",
         "parent":{"type":"workspace","workspace":true},
         "properties":{"title":{"id":"title","type":"title","title":[{"type":"text","text":{"content":"Journal"},"plain_text":"Journal"}]}}}
        """#)

    static let database = NDReply.json(200, #"""
        {"object":"database","id":"\#(ND.databaseUUID)",
         "title":[{"type":"text","text":{"content":"Inbox"},"plain_text":"Inbox"}],
         "data_sources":[{"id":"\#(ND.dataSourceUUID)","name":"Inbox"}]}
        """#)

    static let dataSource = NDReply.json(200, #"""
        {"object":"data_source","id":"\#(ND.dataSourceUUID)",
         "title":[{"type":"text","text":{"content":"Inbox"},"plain_text":"Inbox"}],
         "properties":{"Status":{"id":"a%3Ab","name":"Status","type":"select","select":{"options":[]}},
                       "Task name":{"id":"title","name":"Task name","type":"title","title":{}},
                       "Due":{"id":"c%3Ad","name":"Due","type":"date","date":{}}}}
        """#)
}

// MARK: - The scenarios

struct NoteDestinationsAcceptanceTests {

    // MARK: S1 — the default is Notes, an unknown destination is Notes

    @Test func s1_defaultSavesToNotesAndUnknownFallsBack() async throws {
        #expect(Config.default.notes.destination == .notes)
        #expect(try ND.decode("{}").notes.destination == .notes)
        #expect(try ND.decode(#"{"notes":{"destination":"evernote","folder":"~/Vault/Inbox"}}"#).notes.destination == .notes)
        let folder = try ND.decode(#"{"notes":{"destination":"folder","folder":"~/Vault/Inbox"}}"#).notes
        #expect(folder.destination == .folder && folder.folder == "~/Vault/Inbox")
        #expect(try ND.pageSettings().destination == .notion)

        // Encoded only when it differs from the default.
        let encoder = JSONEncoder()
        let plain = ND.json(try encoder.encode(Config.default))
        #expect(plain["notes"] == nil, "the default notes setting was written: \(String(describing: plain["notes"]))")
        var changed = Config.default
        changed.notes.destination = .folder
        changed.notes.folder = "~/Vault/Inbox"
        let written = ND.json(try encoder.encode(changed))["notes"] as? [String: Any]
        #expect(written?["destination"] as? String == "folder" && written?["folder"] as? String == "~/Vault/Inbox")
        let back = try JSONDecoder().decode(Config.self, from: try encoder.encode(changed)).notes
        #expect(back.destination == .folder && back.folder == "~/Vault/Inbox")

        // Both the default and an unknown destination save through the system's Notes.
        let unknown = try ND.decode(#"{"notes":{"destination":"evernote"}}"#).notes
        for settings in [Config.default.notes, unknown] {
            let system = NDFakeSystemNotes()
            let destination = NoteDestinations.make(settings, system: system)
            #expect(destination.name == "Notes" && !destination.leavesDevice)
            let ref = try await destination.save(ND.draft("Buy milk\nand eggs"))
            #expect(system.saved == ["Buy milk\nand eggs"])
            #expect(ref.id?.hasPrefix("x-coredata:") == true)
        }
    }

    // MARK: S2 — the id in a Notion link

    @Test func s2_notionLinkID() {
        let id = ND.pageUUID
        // A slugged URL.
        #expect(NotionLink.id(from: "https://www.notion.so/myteam/Inbox-\(ND.pageID)") == id)
        #expect(NotionLink.id(from: "https://www.notion.so/Inbox-\(ND.pageID)") == id)
        // A database's view (?v=) and a page peeked from a database (?p=): the path wins.
        #expect(NotionLink.id(from: "https://www.notion.so/myteam/\(ND.pageID)?v=fedcba9876543210fedcba9876543210") == id)
        #expect(NotionLink.id(from: "https://www.notion.so/myteam/Tasks-\(ND.pageID)?v=aaaabbbbccccddddeeeeffff00001111&p=fedcba9876543210fedcba9876543210&pm=s") == id)
        #expect(NotionLink.id(from: "https://www.notion.so/\(ND.pageID)?p=fedcba9876543210fedcba9876543210") == id)
        // A dashed UUID in the path.
        #expect(NotionLink.id(from: "https://www.notion.so/myteam/Inbox-\(ND.pageUUID)") == id)
        #expect(NotionLink.id(from: "https://www.notion.so/\(ND.pageUUID)") == id)
        // A public notion.site page.
        #expect(NotionLink.id(from: "https://myteam.notion.site/Inbox-\(ND.pageID)") == id)
        // Not Notion, or no id.
        #expect(NotionLink.id(from: "https://example.com/Inbox-\(ND.pageID)") == nil)
        #expect(NotionLink.id(from: "https://notion.so.example.com/Inbox-\(ND.pageID)") == nil)
        #expect(NotionLink.id(from: "https://www.notion.so/myteam/Inbox") == nil)
        #expect(NotionLink.id(from: "not a link") == nil)
        #expect(NotionLink.id(from: "") == nil)
    }

    // MARK: S3 — file names

    @Test func s3_fileNames() {
        typealias M = MarkdownFolderDestination
        #expect(M.fileName(for: ND.draft("Meeting: Q3/plan\nagenda"), existing: []) == "Meeting- Q3-plan.md")
        #expect(M.fileName(for: ND.draft("CON"), existing: []) == "CON_.md")
        // Each of / \ : * ? " < > | # ^ [ ] becomes "-".
        #expect(M.fileName(for: ND.draft(#"a/b\c:d*e?f"g<h>i|j#k^l[m]n"#), existing: []) == "a-b-c-d-e-f-g-h-i-j-k-l-m-n.md")
        // Control characters too; dots and spaces trimmed at either end.
        #expect(M.fileName(for: ND.draft("tab\there"), existing: []) == "tab-here.md")
        #expect(M.fileName(for: ND.draft(". hidden note. "), existing: []) == "hidden note.md")
        // Nothing left: named by when it was written, in its time zone.
        #expect(M.fileName(for: ND.draft("..."), existing: []) == "Note 2026-10-17 1403.md")

        // 80 Chinese characters (the title's limit; 100 typed) stay within 255 UTF-8 bytes.
        let chinese = M.fileName(for: ND.draft(String(repeating: "笔记", count: 50)), existing: [])
        #expect(chinese.utf8.count <= 255, "\(chinese.utf8.count) bytes")
        #expect(chinese.hasSuffix(".md") && chinese.hasPrefix(String(repeating: "笔记", count: 20)))

        // Taken: " 2", then " 3".
        let draft = ND.draft("Meeting: Q3/plan")
        #expect(M.fileName(for: draft, existing: ["Meeting- Q3-plan.md"]) == "Meeting- Q3-plan 2.md")
        #expect(M.fileName(for: draft, existing: ["Meeting- Q3-plan.md", "Meeting- Q3-plan 2.md"]) == "Meeting- Q3-plan 3.md")
        #expect(M.fileName(for: draft, existing: ["Other.md", "Meeting- Q3-plan 2.md"]) == "Meeting- Q3-plan.md")
        let taken = M.fileName(for: ND.draft(String(repeating: "笔记", count: 50)), existing: [chinese])
        #expect(taken != chinese && taken.utf8.count <= 255 && taken.hasSuffix(" 2.md"))
    }

    // MARK: S4 — the document

    @Test func s4_documentIsFrontMatterThenTheTextAsTyped() throws {
        let text = "Groceries: #weekly\r\nmilk  and [eggs]\r\n\r\n  bread\r\n"
        let document = MarkdownFolderDestination.document(for: ND.draft(text))
        #expect(!document.unicodeScalars.contains("\r"))
        #expect(document.hasPrefix("---\n"), "\(document)")
        let afterOpening = document.dropFirst(4)
        let close = try #require(afterOpening.range(of: "\n---\n"), "no closing --- line: \(document)")
        let front = afterOpening[..<close.lowerBound]
        var rest = String(afterOpening[close.upperBound...])
        if rest.hasPrefix("\n") { rest.removeFirst() }
        #expect(rest == "Groceries: #weekly\nmilk  and [eggs]\n\n  bread\n")

        let created = try #require(front.split(separator: "\n").first { $0.hasPrefix("created:") }, "no created: line in \(front)")
        let value = created.dropFirst("created:".count).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        #expect(value.hasSuffix("+08:00"), "\(value)")
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = try #require(plain.date(from: value) ?? fractional.date(from: value), "not ISO 8601: \(value)")
        #expect(abs(date.timeIntervalSince(ND.created)) < 1)

        // A lone line ending stays as it is; nothing else is changed.
        let lf = MarkdownFolderDestination.document(for: ND.draft("one\ntwo"))
        #expect(lf.hasSuffix("\n---\none\ntwo") || lf.hasSuffix("\n---\n\none\ntwo"), "\(lf)")
    }

    // MARK: S5 — one new file, never an overwrite; a missing folder

    @Test func s5_saveWritesOneNewFileAndNeverOverwrites() async throws {
        let folder = try ND.tempFolder()
        let old = folder.appendingPathComponent("Hello.md")
        try Data("old content".utf8).write(to: old)
        let destination = MarkdownFolderDestination(folder: folder)
        #expect(!destination.leavesDevice)

        let before = ND.files(folder)
        let draft = ND.draft("Hello\nworld")
        let ref = try await destination.save(draft)
        let added = ND.files(folder).subtracting(before)
        #expect(added == ["Hello 2.md"], "\(added)")
        #expect(try String(contentsOf: old, encoding: .utf8) == "old content")
        let new = folder.appendingPathComponent("Hello 2.md")
        let bytes = try Data(contentsOf: new)
        let content = try #require(String(data: bytes, encoding: .utf8))
        #expect(content == MarkdownFolderDestination.document(for: draft))
        #expect(!content.unicodeScalars.contains("\r"))
        let id = try #require(ref.id)
        #expect(id.hasPrefix("file:"), "\(id)")
        #expect(URL(string: id).map { ND.samePath($0, new) } == true, "\(id)")
        #expect(ref.title == "Hello")

        // The same note again: another new file.
        _ = try await destination.save(draft)
        #expect(ND.files(folder).subtracting(before) == ["Hello 2.md", "Hello 3.md"])
        #expect(try String(contentsOf: new, encoding: .utf8) == content)
    }

    @Test func s5_missingFolderIsAnErrorAndCreatesNothing() async throws {
        let parent = try ND.tempFolder("Vault")
        let missing = parent.appendingPathComponent("Inbox", isDirectory: true)
        let destination = MarkdownFolderDestination(folder: missing)
        do {
            _ = try await destination.save(ND.draft("Hello\nworld"))
            Issue.record("a save into a missing folder went through")
        } catch {
            guard case .folderMissing? = error as? NoteError else {
                Issue.record("not .folderMissing: \(error)")
                return
            }
            #expect(ND.english(error) == "The notes folder is gone: choose it again in Settings")
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(ND.files(parent).isEmpty)
    }

    // MARK: S6 — Obsidian

    @Test func s6_obsidianVaultNameAndOpenURL() async throws {
        let fm = FileManager.default
        let vault = try ND.tempFolder("Vault")
        try fm.createDirectory(at: vault.appendingPathComponent(".obsidian", isDirectory: true), withIntermediateDirectories: true)
        let inbox = vault.appendingPathComponent("Daily Notes/Inbox", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let plain = try ND.tempFolder("Inbox")

        // .obsidian in the folder itself, or in a parent.
        #expect(MarkdownFolderDestination.vaultRoot(of: vault).map { ND.samePath($0, vault) } == true)
        #expect(MarkdownFolderDestination.vaultRoot(of: inbox).map { ND.samePath($0, vault) } == true)
        #expect(MarkdownFolderDestination.vaultRoot(of: plain) == nil)

        #expect(MarkdownFolderDestination(folder: inbox).name == "Obsidian")
        #expect(MarkdownFolderDestination(folder: vault).name == "Obsidian")
        let plainName = MarkdownFolderDestination(folder: plain).name
        #expect(plainName.trimmingCharacters(in: CharacterSet(charactersIn: "“”")) == "Inbox", "\(plainName)")

        // Through the settings as well.
        var settings = Config.default.notes
        settings.destination = .folder
        settings.folder = inbox.path
        #expect(NoteDestinations.make(settings, system: NDFakeSystemNotes()).name == "Obsidian")
        settings.folder = plain.path
        let made = NoteDestinations.make(settings, system: NDFakeSystemNotes())
        #expect(made.name.trimmingCharacters(in: CharacterSet(charactersIn: "“”")) == "Inbox" && !made.leavesDevice)

        // A note saved in the vault opens in Obsidian, by its path; elsewhere, as the file.
        let ref = try await MarkdownFolderDestination(folder: inbox).save(ND.draft("Plan & ideas\nsoon"))
        let file = try #require(ref.id.flatMap(URL.init(string:)))
        let open = MarkdownFolderDestination.openURL(for: file)
        #expect(open.absoluteString.hasPrefix("obsidian://open?path="), "\(open)")
        let path = URLComponents(url: open, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
        #expect(path.map { ND.samePath(URL(fileURLWithPath: $0), file) } == true, "\(String(describing: path))")
        let elsewhere = try await MarkdownFolderDestination(folder: plain).save(ND.draft("Plan & ideas"))
        let plainFile = try #require(elsewhere.id.flatMap(URL.init(string:)))
        let plainOpen = MarkdownFolderDestination.openURL(for: plainFile)
        #expect(plainOpen.isFileURL && ND.samePath(plainOpen, plainFile), "\(plainOpen)")
    }

    // MARK: S7 — the title and the body blocks

    @Test func s7_titleAndBlocks() async throws {
        // The split: the first line exactly, then the rest.
        let split = ND.draft("Meeting: Q3/plan #1\nmilk\neggs\n\nbread")
        #expect(split.title == "Meeting: Q3/plan #1")
        #expect(split.body == "milk\neggs\n\nbread")

        // A paragraph per blank-line-separated paragraph, its line breaks kept.
        let short = try await sentPage(split.text)
        #expect(ND.titleProperty(short)?.text == "Meeting: Q3/plan #1")
        #expect(ND.paragraphs(short).map { $0.joined() } == ["milk\neggs", "bread"])

        // A 20 000-character line: pieces of at most 2000, all of it, in one request.
        let line = (0..<4000).map { String(format: "w%04d", $0) + " " }.joined().prefix(20_000)
        #expect(line.count == 20_000)
        let long = try await sentPage("Long one\n" + line)
        let pieces = ND.paragraphs(long).flatMap { $0 }
        #expect(!pieces.isEmpty && pieces.allSatisfy { $0.count <= 2000 }, "\(pieces.map(\.count))")
        #expect(pieces.joined() == String(line))
        #expect(ND.paragraphs(long).count <= 100)

        // 300 paragraphs: at most 100 blocks, nothing lost, in order.
        let paragraphs = (1...300).map { "Paragraph \($0) of the long note." }
        let many = try await sentPage("Many\n" + paragraphs.joined(separator: "\n\n"))
        let blocks = ND.paragraphs(many)
        #expect(!blocks.isEmpty && blocks.count <= 100, "\(blocks.count) blocks")
        #expect(blocks.allSatisfy { $0.allSatisfy { $0.count <= 2000 } })
        #expect(ND.noWhitespace(blocks.map { $0.joined() }.joined()) == ND.noWhitespace(paragraphs.joined()))
        #expect(ND.titleProperty(many)?.text == "Many")
    }

    /// The body of the one request a save of `text` to a Notion page sends.
    private func sentPage(_ text: String) async throws -> [String: Any] {
        let token = NDNotionStub.token { _ in NDNotion.created }
        let destination = NotionDestination(target: try ND.pageSettings().notion, token: token, session: NDNotionStub.session())
        _ = try await destination.save(ND.draft(text))
        let requests = NDRoutes.shared.requests(token)
        #expect(requests.count == 1, "\(requests.count) requests for one note")
        return ND.json(requests.first?.body)
    }

    // MARK: S8 — the request

    @Test func s8_requestToAPageAndToADatabase() async throws {
        let session = NDNotionStub.session()
        // A page: a child page, titled by "title".
        let pageToken = NDNotionStub.token { _ in NDNotion.created }
        let page = NotionDestination(target: try ND.pageSettings().notion, token: pageToken, session: session)
        #expect(page.name == "Notion" && page.leavesDevice)
        let ref = try await page.save(ND.draft("Groceries\nmilk"))
        #expect(ref.id == NDNotion.createdURL)
        #expect(ref.title == "Groceries")
        let sent = NDRoutes.shared.requests(pageToken)
        try #require(sent.count == 1)
        #expect(sent[0].method == "POST")
        #expect(sent[0].url == "https://api.notion.com/v1/pages")
        #expect(sent[0].authorization == "Bearer \(pageToken)")
        #expect(sent[0].version == "2025-09-03")
        #expect(sent[0].timeout == 15)
        let body = ND.json(sent[0].body)
        let parent = body["parent"] as? [String: Any]
        #expect(parent?["page_id"] as? String == ND.pageUUID, "\(String(describing: parent))")
        #expect(parent?["data_source_id"] == nil)
        let title = ND.titleProperty(body)
        #expect(title?.name == "title" && title?.text == "Groceries")
        #expect(ND.paragraphs(body).map { $0.joined() } == ["milk"])

        // A database: a row under its data source, titled by its title property.
        let rowToken = NDNotionStub.token { _ in NDNotion.created }
        let database = NotionDestination(target: try ND.databaseSettings().notion, token: rowToken, session: session)
        _ = try await database.save(ND.draft("Call the bank\nabout the card"))
        let row = NDRoutes.shared.requests(rowToken)
        try #require(row.count == 1)
        #expect(row[0].method == "POST" && row[0].url == "https://api.notion.com/v1/pages")
        #expect(row[0].authorization == "Bearer \(rowToken)" && row[0].version == "2025-09-03")
        let rowBody = ND.json(row[0].body)
        let rowParent = rowBody["parent"] as? [String: Any]
        #expect(rowParent?["data_source_id"] as? String == ND.dataSourceUUID, "\(String(describing: rowParent))")
        #expect(rowParent?["page_id"] == nil && rowParent?["database_id"] == nil)
        let rowTitle = ND.titleProperty(rowBody)
        #expect(rowTitle?.name == "Task name" && rowTitle?.text == "Call the bank")
        #expect(ND.paragraphs(rowBody).map { $0.joined() } == ["about the card"])
    }

    // MARK: S9 — resolving a link

    @Test func s9_resolvingPageDatabaseAndNotShared() async throws {
        let session = NDNotionStub.session()
        // A page.
        let pageToken = NDNotionStub.token { seen in
            seen.path == "/v1/pages/\(ND.pageUUID)" || seen.path == "/v1/pages/\(ND.pageID)" ? NDNotion.page : NDNotion.error(404, "object_not_found")
        }
        let page = try await NotionAPI.resolve(ND.pageUUID, token: pageToken, session: session)
        #expect(page.kind == .page && page.id == ND.pageUUID && page.title == "Journal")
        let pageRequests = NDRoutes.shared.requests(pageToken)
        #expect(pageRequests.count == 1)
        #expect(pageRequests.allSatisfy {
            $0.method == "GET" && $0.version == "2025-09-03" && $0.authorization == "Bearer \(pageToken)" && $0.timeout == 10
        })

        // A database: its first data source, and the property whose type is title.
        let databaseToken = NDNotionStub.token { seen in
            switch seen.path {
            case "/v1/databases/\(ND.databaseUUID)": return NDNotion.database
            case "/v1/data_sources/\(ND.dataSourceUUID)": return NDNotion.dataSource
            default: return NDNotion.error(404, "object_not_found")
            }
        }
        let database = try await NotionAPI.resolve(ND.databaseUUID, token: databaseToken, session: session)
        #expect(database.kind == .database && database.id == ND.databaseUUID)
        #expect(database.dataSource == ND.dataSourceUUID)
        #expect(database.titleProperty == "Task name")
        #expect(database.title == "Inbox")
        let databaseRequests = NDRoutes.shared.requests(databaseToken)
        #expect(databaseRequests.map(\.path) == ["/v1/pages/\(ND.databaseUUID)", "/v1/databases/\(ND.databaseUUID)",
                                                 "/v1/data_sources/\(ND.dataSourceUUID)"])
        #expect(databaseRequests.allSatisfy { $0.method == "GET" && $0.version == "2025-09-03" && $0.timeout == 10 })

        // What it resolved to is what the config keeps.
        var config = Config.default
        config.notes.destination = .notion
        config.notes.notion = database
        let stored = try JSONDecoder().decode(Config.self, from: try JSONEncoder().encode(config)).notes
        #expect(stored.destination == .notion && stored.notion?.dataSource == ND.dataSourceUUID
                && stored.notion?.titleProperty == "Task name" && stored.notion?.kind == .database)

        // 404 for both: not shared with the integration.
        let hiddenToken = NDNotionStub.token { _ in NDNotion.error(404, "object_not_found") }
        do {
            _ = try await NotionAPI.resolve(ND.pageUUID, token: hiddenToken, session: session)
            Issue.record("a page and database Notion doesn't show resolved")
        } catch {
            #expect(ND.english(error) == "The Notion page isn't shared with your integration: ··· → Connections", "\(error)")
        }
        #expect(NDRoutes.shared.requests(hiddenToken).map(\.path) == ["/v1/pages/\(ND.pageUUID)", "/v1/databases/\(ND.pageUUID)"])
    }

    // MARK: S10 — errors

    @Test func s10_errorsMapAsInTheTable() async throws {
        func text(_ status: Int, _ code: String) -> String {
            NotionAPI.error(status: status, body: Data(#"{"object":"error","status":\#(status),"code":"\#(code)","message":"x"}"#.utf8))
                .message(language: "en")
        }
        #expect(text(401, "unauthorized") == "The Notion token isn't valid: paste a new one in Settings → Plugins")
        #expect(text(403, "restricted_resource") == "The Notion page isn't shared with your integration: ··· → Connections")
        #expect(text(404, "object_not_found") == "The Notion page isn't shared with your integration: ··· → Connections")
        #expect(text(429, "rate_limited") == "Notion is busy: try again in a moment")
        #expect(text(400, "validation_error") == "Notion refused the note (validation_error)")
        #expect(text(503, "service_unavailable") == "Notion is having trouble (HTTP 503)")
        #expect(text(500, "internal_server_error") == "Notion is having trouble (HTTP 500)")

        // Through a save: each answer, once (no retries), the note not saved.
        let target = try ND.pageSettings().notion
        let session = NDNotionStub.session()
        let answers: [(NDReply, String)] = [
            (NDNotion.error(401, "unauthorized"), "The Notion token isn't valid: paste a new one in Settings → Plugins"),
            (NDNotion.error(403, "restricted_resource"), "The Notion page isn't shared with your integration: ··· → Connections"),
            (NDNotion.error(404, "object_not_found"), "The Notion page isn't shared with your integration: ··· → Connections"),
            (NDNotion.error(429, "rate_limited"), "Notion is busy: try again in a moment"),
            (NDNotion.error(400, "validation_error"), "Notion refused the note (validation_error)"),
            (NDNotion.error(503, "service_unavailable"), "Notion is having trouble (HTTP 503)"),
            (.fail(.notConnectedToInternet), "Offline: not saved to Notion"),
            (.fail(.networkConnectionLost), "Offline: not saved to Notion"),
            (.fail(.cannotFindHost), "Offline: not saved to Notion"),
            (.fail(.timedOut), "Notion didn't answer within 15 s"),
        ]
        for (reply, expected) in answers {
            let token = NDNotionStub.token { _ in reply }
            do {
                _ = try await NotionDestination(target: target, token: token, session: session).save(ND.draft("Groceries\nmilk"))
                Issue.record("saved despite \(reply)")
            } catch {
                #expect(ND.english(error) == expected, "\(reply): \(error)")
            }
            let sent = NDRoutes.shared.requests(token)
            #expect(sent.count == 1, "\(reply): \(sent.count) requests")
            #expect(sent.first?.timeout == 15)
        }

        // No token, or no page or database: not set up, and nothing is sent.
        let unused = NDNotionStub.token { _ in NDNotion.created }
        for destination in [NotionDestination(target: target, token: nil, session: session),
                            NotionDestination(target: Config.default.notes.notion, token: unused, session: session)] {
            do {
                _ = try await destination.save(ND.draft("Groceries\nmilk"))
                Issue.record("saved without a token or a target")
            } catch {
                #expect(ND.english(error) == "Notion isn't set up: Settings → Plugins → Notes", "\(error)")
            }
        }
        #expect(NDRoutes.shared.requests(unused).isEmpty)
        #expect(NDRoutes.shared.requests("(none)").isEmpty)
    }

    // MARK: S11 — secure input

    @Test func s11_secureInputRefusesNotionNotFolder() async throws {
        #expect(Composer.Messages.english.secureInputNote == "Secure input is on: not saved to Notion")

        // To Notion: nothing is saved, a notice says why.
        let notion = ND.noteComposer("hello")
        notion.noteLeavesDevice = true
        notion.secureInputActive = { true }
        let refused = notion.handleKeyDown(enterKey).effects
        #expect(ND.saves(refused).isEmpty, "\(refused)")
        #expect(ND.notices(refused).contains(Composer.Messages.english.secureInputNote), "\(refused)")
        #expect(commits(refused).isEmpty)

        // To Notion without secure input: saved.
        let open = ND.noteComposer("hello")
        open.noteLeavesDevice = true
        #expect(ND.saves(open.handleKeyDown(enterKey).effects) == ["hello"])

        // To a folder (or Notes): secure input doesn't hold it back.
        let local = ND.noteComposer("hello")
        local.noteLeavesDevice = false
        local.secureInputActive = { true }
        #expect(ND.saves(local.handleKeyDown(enterKey).effects) == ["hello"])

        // What tells the composer: the destination.
        let folder = try ND.tempFolder()
        let folderDestination = MarkdownFolderDestination(folder: folder)
        #expect(!folderDestination.leavesDevice)
        _ = try await folderDestination.save(ND.draft("hello"))
        #expect(ND.files(folder) == ["hello.md"])
        #expect(NotionDestination(target: try ND.pageSettings().notion, token: "t", session: NDNotionStub.session()).leavesDevice)
        #expect(!NoteDestinations.make(Config.default.notes, system: NDFakeSystemNotes()).leavesDevice)
    }

    // MARK: S12 — the panel's list

    @Test func s12_reconcileLeavesFilesAndNotionPagesAlone() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let notesID = "x-coredata://ABCD-1234/ICNote/p42"
        let gone = "x-coredata://ABCD-1234/ICNote/p43"
        let kept = URL(fileURLWithPath: "/Users/someone/Vault/Inbox/kept.md").absoluteString
        let missing = URL(fileURLWithPath: "/Users/someone/Vault/Inbox/missing.md").absoluteString
        let page = "https://www.notion.so/Groceries-99998888777766665555444433332222"
        var notes = SavedNotes()
        notes.add(id: gone, title: "Gone from Notes", at: start)
        notes.add(id: page, title: "Groceries", at: start.addingTimeInterval(1))
        notes.add(id: missing, title: "Missing", at: start.addingTimeInterval(2))
        notes.add(id: kept, title: "Kept", at: start.addingTimeInterval(3))
        notes.add(id: notesID, title: "Old title", at: start.addingTimeInterval(4))

        // Notes lists its whole folder: only p42, renamed. The note it doesn't list goes; files and pages stay.
        notes.reconcile(with: [(id: notesID, title: "New title", modified: start.addingTimeInterval(5))], limit: SavedNotes.limit)
        #expect(notes.notes.map(\.id) == [notesID, kept, missing, page], "\(notes.notes.map(\.id))")
        #expect(notes.notes.first?.title == "New title")
        #expect(notes.notes.first { $0.id == kept }?.title == "Kept")
        // Notes empty (all moved away): still only Notes' own entries go.
        var empty = notes
        empty.reconcile(with: [], limit: SavedNotes.limit)
        #expect(empty.notes.map(\.id) == [kept, missing, page])

        // A file that's gone is dropped; a Notes entry and a Notion page are never checked as files.
        notes.dropMissingFiles(exists: { "\($0)".contains("kept.md") })
        #expect(notes.notes.map(\.id) == [notesID, kept, page], "\(notes.notes.map(\.id))")
        notes.dropMissingFiles(exists: { _ in true })
        #expect(notes.notes.map(\.id) == [notesID, kept, page])
    }

    // MARK: S13 — never synced, not the Assistant's

    @Test func s13_notesNeverSyncedAndAssistantCantChangeIt() throws {
        #expect(ICloudSync.neverSynced.contains("notes"))
        #expect(ICloudSync.category(of: "notes") == nil)
        #expect(Config.allKeys.contains("notes"))
        for key in ["notes", "notes.destination", "notes.folder", "notes.notion", "notes.notion.id"] {
            guard case .forbidden(_, false)? = AIConfig.Key.parse(key) else {
                Issue.record("\(key): \(String(describing: AIConfig.Key.parse(key)))")
                continue
            }
        }
        let preview = try AIC.preview([("notes.destination", "folder"), ("candidateLayout", "vertical")]).get()
        #expect(preview.rows.first { $0.key == "notes.destination" }?.isRefused == true)
        #expect(preview.edits == [.candidateLayout(.vertical)], "\(preview.edits)")
    }

    // MARK: S14 — a failed save comes back, whatever the destination

    @Test func s14_failedSaveComesBackForEveryDestination() async throws {
        let text = "Groceries\nmilk\n\neggs"
        let parent = try ND.tempFolder("Vault")
        var folderSettings = Config.default.notes
        folderSettings.destination = .folder
        folderSettings.folder = parent.appendingPathComponent("Moved away").path
        let token = NDNotionStub.token { _ in .fail(.notConnectedToInternet) }
        let page = try ND.pageSettings().notion
        let destinations: [any NoteDestination] = [
            NoteDestinations.make(Config.default.notes, system: NDFakeSystemNotes(fails: true)),
            NoteDestinations.make(folderSettings, system: NDFakeSystemNotes()),
            NotionDestination(target: page, token: token, session: NDNotionStub.session()),
        ]
        for destination in destinations {
            // ⏎ hands the text over and clears the draft…
            let c = ND.noteComposer("x")
            let sent = c.handleKeyDown(enterKey).effects
            #expect(ND.saves(sent) == ["x"])
            #expect(c.draft.isEmpty)
            // …the save fails…
            var failed = false
            do { _ = try await destination.save(ND.draft(text)) } catch { failed = true }
            #expect(failed, "\(destination.name) saved")
            // …and the text comes back to the draft, whole.
            #expect(c.restoreDraft(.note, text: text) == [.updateMarkedText, .showPanel], "\(destination.name)")
            #expect(c.draft == "@note " + text)
            // Something else typed meanwhile: not put back (the shell puts it on the clipboard).
            let busy = ND.noteComposer("other")
            #expect(busy.restoreDraft(.note, text: text) == nil && busy.draft == "@note other")
        }
        // Nothing half done: no folder made, one request to Notion (no outbox, no retry).
        #expect(ND.files(parent).isEmpty)
        #expect(NDRoutes.shared.requests(token).count == 1)
    }
}
