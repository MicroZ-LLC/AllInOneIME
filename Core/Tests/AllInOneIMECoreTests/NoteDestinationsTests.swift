#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation
import Testing
@testable import AllInOneIMECore

/// What the acceptance tests leave to the implementation: iCloud placeholders and case when a name is taken, long
/// emoji titles, a paragraph past Notion's pieces per block, the other 4xx answers, the settings' coding.
struct NoteDestinationsTests {
    private func draft(_ text: String) -> NoteDraft {
        NoteDraft(text: text, created: Date(timeIntervalSince1970: 1_792_000_000), timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func aNameIsTakenInAnyCaseAndByAnICloudPlaceholder() {
        typealias M = MarkdownFolderDestination
        #expect(M.fileName(for: draft("Hello"), existing: ["hello.md"]) == "Hello 2.md")
        #expect(M.fileName(for: draft("Hello"), existing: [".Hello.md.icloud"]) == "Hello 2.md")
        #expect(M.fileName(for: draft("con.notes"), existing: []) == "con_.notes.md")
        #expect(M.fileName(for: draft("  \n  "), existing: []) == "Note 2026-10-14 1746.md")
        // 80 emoji of 4 bytes each: cut by whole characters to fit 255 bytes.
        let emoji = M.fileName(for: draft(String(repeating: "😀", count: 80)), existing: [])
        #expect(emoji.utf8.count <= 255 && emoji.hasSuffix(".md") && emoji.dropLast(3).allSatisfy { $0 == "😀" })
    }

    @Test func aVaultIsFoundUpTheTreeAndTheOpenURLEscapesThePath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("note-dest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("a/b c/d", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(MarkdownFolderDestination.vaultRoot(of: deep) == nil)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/.obsidian"), withIntermediateDirectories: true)
        #expect(MarkdownFolderDestination.vaultRoot(of: deep)?.lastPathComponent == "a")
        let file = deep.appendingPathComponent("Plan & ideas #1.md")
        let open = MarkdownFolderDestination.openURL(for: file).absoluteString
        #expect(open.hasPrefix("obsidian://open?path=%2F") && open.contains("%26") && open.contains("%20") && open.contains("%23"))
    }

    @Test func aHugeParagraphSpreadsOverBlocksWithinNotionsLimits() {
        let paragraph = String(repeating: "x", count: 250_000)  // 125 pieces: more than one block holds
        let blocks = NotionFormat.blocks(paragraph)
        #expect(blocks.count == 2 && blocks.allSatisfy { $0.count <= NotionFormat.maxPieces })
        #expect(blocks.flatMap { $0 }.joined() == paragraph)
        // A character is never cut in two (UTF-16 counted as Notion counts it).
        let pieces = NotionFormat.pieces(String(repeating: "😀", count: 1500))
        #expect(pieces.allSatisfy { $0.utf16.count <= NotionFormat.maxText } && pieces.joined() == String(repeating: "😀", count: 1500))
    }

    @Test func otherAnswersMapToWhatTheyMean() {
        #expect(NotionAPI.error(status: 409, body: Data(#"{"code":"conflict_error"}"#.utf8)) == .notionRefused(code: "conflict_error"))
        #expect(NotionAPI.error(status: 400, body: Data("not json".utf8)) == .notionRefused(code: "HTTP 400"))
        #expect(NotionAPI.error(status: 502, body: Data()) == .notionTrouble(status: 502))
        #expect(NoteError.notionNotSetUp.needsTheUser && !NoteError.offline.needsTheUser)
        #expect(NoteError.notionTimedOut(seconds: 10).message(language: "en") == "Notion didn't answer within 10 s")
    }

    @Test func theSettingsCodeAsTheSpecSays() throws {
        let target = NotionTarget(id: "01234567-89ab-cdef-0123-456789abcdef", kind: .page, title: "Journal")
        let settings = NoteSettings(destination: .notion, notion: target)
        let json = try #require(String(data: JSONEncoder().encode(settings), encoding: .utf8))
        #expect(json.contains(#""destination":"notion""#) && !json.contains("folder"))
        #expect(try JSONDecoder().decode(NoteSettings.self, from: Data(json.utf8)) == settings)
        // A broken target is no target; the rest still reads.
        let odd = try JSONDecoder().decode(NoteSettings.self, from: Data(#"{"destination":"folder","folder":"~/x","notion":{"kind":"wiki"}}"#.utf8))
        #expect(odd.destination == .folder && odd.notion == nil && odd.folderURL?.path.hasSuffix("/x") == true)
        // Without a folder, a folder destination saves to Notes.
        struct System: NoteDestination {
            var name: String { "Notes" }
            var leavesDevice: Bool { false }
            func save(_ draft: NoteDraft) async throws -> SavedNoteRef { SavedNoteRef(id: nil, title: "") }
            func check() async throws -> String { "" }
        }
        #expect(NoteDestinations.make(NoteSettings(destination: .folder), system: System()).name == "Notes")
        #expect(NoteDestinations.openURL(forSaved: "x-coredata://A/ICNote/p1", folder: nil) == nil)
        #expect(NoteDestinations.openURL(forSaved: "https://www.notion.so/x", folder: nil)?.absoluteString == "https://www.notion.so/x")
    }

    // MARK: - Writing a file: never half of one, nothing left behind

    private func tempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("note-dest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func names(_ folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    @Test func aWriteThatFailsHalfWayLeavesNoFileBehind() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("old".utf8).write(to: folder.appendingPathComponent("Big note.md"))
        // The disk fills up half way: some of it written, then an error (not "the name is taken").
        let destination = MarkdownFolderDestination(folder: folder) { data, file in
            try data.prefix(10).write(to: file, options: .withoutOverwriting)
            throw CocoaError(.fileWriteOutOfSpace)
        }
        await #expect(throws: CocoaError.self) { _ = try await destination.save(draft("Big note\n" + String(repeating: "x", count: 5000))) }
        #expect(names(folder) == ["Big note.md"], "\(names(folder))")
        #expect(try String(contentsOf: folder.appendingPathComponent("Big note.md"), encoding: .utf8) == "old")
    }

    @Test func aFolderThatGoesAwayDuringTheWriteIsMissingAndNothingIsLeft() async throws {
        let parent = try tempFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = MarkdownFolderDestination(folder: folder) { _, _ in
            try FileManager.default.removeItem(at: folder)
            throw CocoaError(.fileNoSuchFile)
        }
        do {
            _ = try await destination.save(draft("Hello"))
            Issue.record("saved into a folder that went away")
        } catch {
            #expect(error as? NoteError == .folderMissing(path: folder.path), "\(error)")
        }
        #expect(names(parent).isEmpty)
    }

    @Test func aNameTakenWhileWritingGetsTheNextAndNothingIsOverwritten() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Another app makes "Hello.md" between the listing and the rename.
        let destination = MarkdownFolderDestination(folder: folder) { data, file in
            try data.write(to: file, options: .withoutOverwriting)
            try Data("theirs".utf8).write(to: folder.appendingPathComponent("Hello.md"), options: .withoutOverwriting)
        }
        let ref = try await destination.save(draft("Hello\nworld"))
        #expect(names(folder) == ["Hello.md", "Hello 2.md"], "\(names(folder))")
        #expect(try String(contentsOf: folder.appendingPathComponent("Hello.md"), encoding: .utf8) == "theirs")
        #expect(ref.id.flatMap(URL.init(string:))?.lastPathComponent == "Hello 2.md")
        #expect(try String(contentsOf: folder.appendingPathComponent("Hello 2.md"), encoding: .utf8)
                == MarkdownFolderDestination.document(for: draft("Hello\nworld")))
        #expect(ref.destinationName == "“\(folder.lastPathComponent)”")
    }

    @Test func onlyTheNameTakenCountsAsTaken() {
        #expect(MarkdownFolderDestination.isTaken(POSIXError(.EEXIST)))
        #expect(MarkdownFolderDestination.isTaken(CocoaError(.fileWriteFileExists)))
        #expect(!MarkdownFolderDestination.isTaken(CocoaError(.fileWriteOutOfSpace)))
        #expect(!MarkdownFolderDestination.isTaken(POSIXError(.EIO)))
    }

    // MARK: - Vaults, looked up off the main thread

    @Test func aSlowLookupIsUnknownAndNotTriedAgainForAMinute() async throws {
        let calls = Locked(initialState: 0)
        let clock = Locked(initialState: Date(timeIntervalSince1970: 1_792_000_000))
        let release = DispatchSemaphore(value: 0)
        let roots = VaultRoots(timeout: 0.5, retryAfter: 60, now: { clock.withLock { $0 } }) { _ in
            calls.withLock { $0 += 1 }
            release.wait()
            return nil
        }
        let folder = URL(fileURLWithPath: "/Volumes/Gone NAS/Vault/Inbox", isDirectory: true)
        #expect(roots.lookUp(folder) == .unknown)  // waited half a second at most
        #expect(roots.lookUp(folder, fresh: true) == .unknown)  // at once: not tried again
        #expect(roots.cached(folder) == .unknown)
        #expect(calls.withLock { $0 } == 1, "one lookup at a time")
        release.signal()
        for _ in 0..<200 where roots.cached(folder) == .unknown { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(roots.cached(folder) == VaultRoots.Answer.noVault, "what the slow lookup found is kept")
        // A minute later it may be asked again.
        clock.withLock { $0 += 61 }
        release.signal()
        #expect(roots.lookUp(folder, fresh: true) == VaultRoots.Answer.noVault)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func theCacheIsOnlyReadAndALookupStartsInTheBackground() async throws {
        let root = try tempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let roots = VaultRoots()
        #expect(roots.cached(inbox) == .unknown)  // nothing yet: a lookup started
        for _ in 0..<200 where roots.cached(inbox) == .unknown { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(roots.cached(inbox).isVault)
        #expect(MarkdownFolderDestination(folder: inbox, roots: roots).name == "Obsidian")
        let saved = try await MarkdownFolderDestination(folder: inbox, roots: roots).save(draft("Hi"))
        #expect(saved.destinationName == "Obsidian")
    }

    // MARK: - Opening what was saved, and nothing else

    @Test func onlyMarkdownFilesInTheFolderAndNotionPagesOpen() throws {
        let fm = FileManager.default
        let folder = try tempFolder()
        let elsewhere = try tempFolder()
        defer {
            try? fm.removeItem(at: folder)
            try? fm.removeItem(at: elsewhere)
        }
        let note = folder.appendingPathComponent("Note.md")
        try Data("x".utf8).write(to: note)
        let script = elsewhere.appendingPathComponent("x.command")
        try Data("#!/bin/sh".utf8).write(to: script)
        let outside = elsewhere.appendingPathComponent("Other.md")
        try Data("x".utf8).write(to: outside)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Trap.md"), withDestinationURL: script)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Away.md"), withDestinationURL: outside)
        try fm.createDirectory(at: folder.appendingPathComponent("Dir.md"), withIntermediateDirectories: true)

        func open(_ id: String, _ folder: URL? = folder) -> URL? { NoteDestinations.openURL(forSaved: id, folder: folder) }
        #expect(open(note.absoluteString).map { $0.resolvingSymlinksInPath().path == note.resolvingSymlinksInPath().path } == true)
        #expect(open(note.absoluteString, nil) == nil)
        #expect(open(folder.appendingPathComponent("Trap.md").absoluteString) == nil)
        #expect(open(folder.appendingPathComponent("Away.md").absoluteString) == nil)
        #expect(open(folder.appendingPathComponent("Dir.md").absoluteString) == nil)
        #expect(open(outside.absoluteString) == nil)
        #expect(open(script.absoluteString) == nil)
        #expect(open("file:///Applications/Calculator.app") == nil)
        #expect(open("https://www.notion.so/Page-0123456789abcdef0123456789abcdef") != nil)
        #expect(open("https://notion.so/x") != nil && open("https://team.notion.site/x") != nil)
        #expect(open("https://evil.example/x") == nil)
        #expect(open("https://notion.so.evil.example/x") == nil)
        #expect(open("https://user@www.notion.so/x") == nil)
        #expect(open("http://www.notion.so/x") == nil)
        #expect(open("obsidian://open?path=%2Ftmp%2Fx.md") == nil)
        #expect(open("javascript:alert(1)") == nil)
    }

    // MARK: - Notion

    @Test func notionComLinksAndUUIDs() {
        let id = "01234567-89ab-cdef-0123-456789abcdef"
        for link in ["https://www.notion.com/team/Inbox-0123456789abcdef0123456789abcdef",
                     "https://app.notion.com/p/0123456789abcdef0123456789abcdef",
                     "https://notion.com/Inbox-0123456789abcdef0123456789abcdef"] {
            #expect(NotionLink.id(from: link) == id, "\(link)")
        }
        #expect(NotionLink.id(from: "https://evil.notion.com/Inbox-0123456789abcdef0123456789abcdef") == nil)
        #expect(NotionLink.uuid("0123456789ABCDEF0123456789abcdef") == id)
        #expect(NotionLink.uuid(id.uppercased()) == id)
        #expect(NotionLink.uuid("0123-456789abcdef0123456789abcdef") == nil)
        #expect(NotionLink.uuid("../../v1/users") == nil)
        #expect(NotionLink.uuid("") == nil)
    }

    @Test func aTargetFromTheConfigIsCheckedAsUUIDs() throws {
        func notes(_ json: String) throws -> NoteSettings { try JSONDecoder().decode(NoteSettings.self, from: Data(json.utf8)) }
        #expect(try notes(#"{"destination":"notion","notion":{"id":"../users/me","kind":"page"}}"#).notion == nil)
        let row = try notes(#"{"destination":"notion","notion":{"id":"FEDCBA98-7654-3210-FEDC-BA9876543210","kind":"database","dataSource":"x/../y","titleProperty":"Name"}}"#).notion
        #expect(row?.id == "fedcba98-7654-3210-fedc-ba9876543210" && row?.dataSource == nil)
        let broken = NotionTarget(id: "../users", kind: .page)
        #expect(throws: NoteError.notionNotSetUp) { _ = try NotionFormat.request(for: draft("x"), to: broken, token: "t") }
    }

    @Test func aRowIsTitledByThePropertysIDWhenItIsKnown() throws {
        func titleKeys(_ target: NotionTarget) throws -> [String] {
            let request = try NotionFormat.request(for: draft("Call the bank"), to: target, token: "t")
            let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            return Array((body["properties"] as? [String: Any] ?? [:]).keys)
        }
        let source = "11112222-3333-4444-5555-666677778888"
        let database = "fedcba98-7654-3210-fedc-ba9876543210"
        #expect(try titleKeys(NotionTarget(id: database, kind: .database, dataSource: source, titleProperty: "Task name",
                                           titlePropertyID: "title")) == ["title"])
        // A config from before the id was kept: the name.
        #expect(try titleKeys(NotionTarget(id: database, kind: .database, dataSource: source, titleProperty: "Task name")) == ["Task name"])
        let coded = try JSONDecoder().decode(NotionTarget.self, from: JSONEncoder().encode(
            NotionTarget(id: database, kind: .database, dataSource: source, titleProperty: "Name", titlePropertyID: "title")))
        #expect(coded.titlePropertyID == "title")
    }

    @Test func aRefusedRowSaysToTestAgainAndAnswersAreChecked() async throws {
        let session = NoteTestStub.session()
        let database = "fedcba98-7654-3210-fedc-ba9876543210"
        let source = "11112222-3333-4444-5555-666677778888"
        let row = NotionTarget(id: database, kind: .database, dataSource: source, titleProperty: "Name", titlePropertyID: "title")
        let refusing = NoteTestStub.serve { _ in (400, #"{"object":"error","status":400,"code":"validation_error"}"#) }
        do {
            _ = try await NotionDestination(target: row, token: refusing, session: session).save(draft("x"))
            Issue.record("saved")
        } catch {
            #expect(error as? NoteError == .notionDatabaseRefused)
            #expect((error as? NoteError)?.message(language: "en") == "Notion refused the note: open Settings → Plugins → Notes and press Test")
            #expect((error as? NoteError)?.needsTheUser == true)
        }
        // A page answer's URL elsewhere isn't kept for the panel.
        let elsewhere = NoteTestStub.serve { _ in (200, #"{"object":"page","id":"99998888-7777-6666-5555-444433332222","url":"https://evil.example/x"}"#) }
        let page = NotionTarget(id: database, kind: .page)
        #expect(try await NotionDestination(target: page, token: elsewhere, session: session).save(draft("x")).id == nil)
        // A database whose data source id isn't a UUID: not looked up.
        let odd = NoteTestStub.serve { path in
            path.hasPrefix("/v1/databases/")
                ? (200, #"{"object":"database","id":"\#(database)","data_sources":[{"id":"../../users/me"}]}"#)
                : (404, #"{"object":"error","status":404,"code":"object_not_found"}"#)
        }
        await #expect(throws: NoteError.self) { _ = try await NotionAPI.resolve(database, token: odd, session: session) }
        #expect(NoteTestStub.paths(odd) == ["/v1/pages/\(database)", "/v1/databases/\(database)"])
        // The title property's id is kept.
        let good = NoteTestStub.serve { path in
            switch path {
            case "/v1/databases/\(database)":
                return (200, #"{"object":"database","id":"\#(database)","title":[{"plain_text":"Inbox"}],"data_sources":[{"id":"\#(source)"}]}"#)
            case "/v1/data_sources/\(source)":
                return (200, #"{"object":"data_source","id":"\#(source)","properties":{"Task":{"id":"title","name":"Task","type":"title","title":{}}}}"#)
            default:
                return (404, #"{"object":"error","status":404,"code":"object_not_found"}"#)
            }
        }
        let resolved = try await NotionAPI.resolve(database, token: good, session: session)
        #expect(resolved.titleProperty == "Task" && resolved.titlePropertyID == "title" && resolved.dataSource == source)
        await #expect(throws: NoteError.notNotionLink) { _ = try await NotionAPI.resolve("../users", token: good, session: session) }
    }

    @Test func aSaveTakesTwentySecondsAtMostInAll() {
        #expect(NotionAPI.session.configuration.timeoutIntervalForResource == 20)
    }
}

/// Notion's API, never reached: answers by the bearer token (a fresh one per test).
private final class NoteTestStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (_ path: String) -> (Int, String)
    private static let routes = Locked(initialState: [String: (handler: Handler, paths: [String])]())

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoteTestStub.self]
        return URLSession(configuration: configuration)
    }

    static func serve(_ handler: @escaping Handler) -> String {
        let token = "secret_test_" + UUID().uuidString
        routes.withLock { $0[token] = (handler, []) }
        return token
    }

    static func paths(_ token: String) -> [String] { routes.withLock { $0[token]?.paths ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return client!.urlProtocol(self, didFailWithError: URLError(.badURL)) }
        let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
        let handler = Self.routes.withLock { routes -> Handler? in
            routes[token]?.paths.append(url.path)
            return routes[token]?.handler
        }
        guard let handler else { return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)) }
        let (status, body) = handler(url.path)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
