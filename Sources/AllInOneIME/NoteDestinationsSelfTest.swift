import AllInOneIMECore
import AppKit

/// A stand-in for Apple Notes: what `save` is given goes to `saveText` (nothing reaches Notes), and the menu bar panel
/// isn't told of it (no id).
final class StandInNotes: NoteDestination, @unchecked Sendable {
    let name: String
    var leavesDevice: Bool { false }
    private let saveText: @MainActor (String) async throws -> Void

    @MainActor init(_ saveText: @escaping @MainActor (String) async throws -> Void) {
        name = tr("备忘录", "Notes")
        self.saveText = saveText
    }

    func save(_ draft: NoteDraft) async throws -> SavedNoteRef {
        try await saveText(draft.text)
        return SavedNoteRef(id: nil, title: NotesFormat.title(of: draft.text))
    }

    func check() async throws -> String { name }
}

/// Notion's API as the self-test has it: canned answers in Notion's shapes for one database (its id in a page lookup is
/// 404, as Notion answers), and a page made for each `POST /v1/pages`. Nothing reaches Notion.
final class NotionSelfTestStub: URLProtocol {
    struct Seen {
        var method: String
        var path: String
        var version: String?
        var authorization: String?
    }

    static let databaseHex = "fedcba9876543210fedcba9876543210"
    static let databaseID = "fedcba98-7654-3210-fedc-ba9876543210"
    static let dataSourceID = "11112222-3333-4444-5555-666677778888"
    static let pageURL = "https://www.notion.so/Selftest-99998888777766665555444433332222"

    private static let lock = NSLock()
    private static var _seen: [Seen] = []
    static var seen: [Seen] { lock.withLock { _seen } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotionSelfTestStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return client!.urlProtocol(self, didFailWithError: URLError(.badURL)) }
        let seen = Seen(method: request.httpMethod ?? "GET", path: url.path, version: request.value(forHTTPHeaderField: "Notion-Version"),
                        authorization: request.value(forHTTPHeaderField: "Authorization"))
        Self.lock.withLock { Self._seen.append(seen) }
        let (status, body) = Self.answer(seen)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func answer(_ seen: Seen) -> (Int, String) {
        let notFound = (404, #"{"object":"error","status":404,"code":"object_not_found","message":"stubbed"}"#)
        guard seen.authorization?.hasPrefix("Bearer secret_selftest_") == true else {
            return (401, #"{"object":"error","status":401,"code":"unauthorized","message":"stubbed"}"#)
        }
        switch (seen.method, seen.path) {
        case ("GET", "/v1/databases/\(databaseID)"):
            return (200, #"{"object":"database","id":"\#(databaseID)","title":[{"type":"text","text":{"content":"Inbox"},"plain_text":"Inbox"}],"data_sources":[{"id":"\#(dataSourceID)","name":"Inbox"}]}"#)
        case ("GET", "/v1/data_sources/\(dataSourceID)"):
            return (200, #"{"object":"data_source","id":"\#(dataSourceID)","properties":{"Tags":{"id":"a","name":"Tags","type":"multi_select","multi_select":{}},"Name":{"id":"title","name":"Name","type":"title","title":{}}}}"#)
        case ("POST", "/v1/pages"):
            return (200, #"{"object":"page","id":"99998888-7777-6666-5555-444433332222","url":"\#(pageURL)"}"#)
        default:
            return notFound
        }
    }
}

extension SelfTest {
    /// Where @note saves (`Config.notes`): Settings → Plugins → Notes rendered for each destination in both languages;
    /// the folder picker (answered here) keeps a folder in the home folder as "~/…"; a save to a folder of the
    /// self-test's own, which the menu bar panel lists and would open (the URL built, nothing opened), and drops once the
    /// file is gone; Notion with a stubbed session (nothing reaches Notion): the token only in the keychain in memory,
    /// Test's ✓, a save that tells the panel the page's URL, and nothing sent during secure input. Notes is never reached.
    static func testNoteDestinations(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("where @note saves: a folder of the self-test's own, Notion stubbed (Notes and Notion never reached)")
        let fm = FileManager.default
        let root = snapshotDirectory.appendingPathComponent("note-destinations", isDirectory: true)
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let (settingsBefore, destinationBefore, secureBefore, copyBefore) =
            (settings, controller.services.noteDestination, controller.services.secureInputActive, controller.copyText)
        let sessionBefore = NoteSaving.notionSession
        let chosen = UIText.choice
        defer {
            (settings, controller.services.noteDestination, controller.services.secureInputActive, controller.copyText) =
                (settingsBefore, destinationBefore, secureBefore, copyBefore)
            NoteSaving.notionSession = sessionBefore
            UIText.choice = chosen
            controller.applySettings()
            try? fm.removeItem(at: root)
        }
        var copied: [String] = []
        controller.copyText = { copied.append($0) }  // never the user's clipboard
        let stub = NotionSelfTestStub.session()
        NoteSaving.notionSession = stub
        // Notes is a stand-in that fails: a save that reached it would show.
        var reachedNotes = 0
        struct NotesReached: Error {}
        controller.services.noteDestination = { notes in
            NoteDestinations.make(notes, system: StandInNotes { _ in
                reachedNotes += 1
                throw NotesReached()
            }, session: stub)
        }
        let token = "secret_selftest_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")

        // Settings → Plugins → Notes, each destination in both languages (previews: nothing saved, no keychain asked).
        needing([])
        let samples: [NoteSettings.Destination: NoteSettings] = [
            .notes: NoteSettings(),
            .folder: NoteSettings(destination: .folder, folder: "~/Vault/Inbox"),
            .notion: NoteSettings(destination: .notion, notion: NotionTarget(id: NotionSelfTestStub.databaseID, kind: .database,
                                                                             dataSource: NotionSelfTestStub.dataSourceID,
                                                                             titleProperty: "Name", title: "Inbox")),
        ]
        for language in ["zh", "en"] {
            for destination in NoteSettings.Destination.allCases {
                UIText.choice = language
                let preview = SettingsModel(configURL: Config.defaultURL, persists: false)
                preview.config.notes = samples[destination] ?? NoteSettings()
                let url = snapshotDirectory.appendingPathComponent("settings-notes-\(destination.rawValue)-\(language).png")
                try? fm.removeItem(at: url)
                SettingsImage.render(preview, page: .commands, to: url) { seconds in _ = pump(timeout: seconds) { false } }
                check(fm.fileExists(atPath: url.path), "Settings → Commands → Notes rendered: \(destination.rawValue), \(language)")
            }
        }
        UIText.choice = chosen
        check(["notion", "obsidian", "笔记"].allSatisfy { SettingsSpot.search($0, trigger: "@", config: .default).first == .notes },
              "the search finds Settings → Commands → Notes")

        // The folder picker (answered here, nothing made): a folder in the home folder is kept as "~/…"; cancelled, as it was.
        let configURL = root.appendingPathComponent("config.json")
        try? Config.default.write(to: configURL)
        let model = SettingsModel(configURL: configURL)
        let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Notes Vault (self-test)", isDirectory: true)
        var asked = 0
        model.pickNotesFolder = { _ in
            asked += 1
            return home
        }
        model.setNotesDestination(.folder)
        var stored = (try? Config.load(from: configURL))?.notes
        check(asked == 1 && stored?.destination == .folder && stored?.folder == "~/Notes Vault (self-test)" && !fm.fileExists(atPath: home.path),
              "the folder picker keeps the folder as a ~ path (\(stored?.folder ?? "-"))")
        model.pickNotesFolder = { _ in nil }
        model.setNotesDestination(.notes)
        model.chooseNotesFolder()
        stored = (try? Config.load(from: configURL))?.notes
        check(stored?.destination == .notes && stored?.folder == "~/Notes Vault (self-test)",
              "back to Notes, and Choose Folder… cancelled changes nothing (\(stored?.destination.rawValue ?? "-"))")

        // Notion's token: in the keychain (the self-test's, in memory), never in the config.
        model.saveNotionToken(token)
        let configText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        check(APIKeys.hasKeychainKey(account: NotionAPI.keyAccount) && !configText.contains(token) && !configText.contains("secret_"),
              "the Notion token goes into the keychain (the self-test's, in memory), never into the config")
        // Test: a database's link (its view in the query) resolved through the stub, kept in the config.
        model.setNotesDestination(.notion)
        model.notionLink = "https://www.notion.so/selftest/Inbox-\(NotionSelfTestStub.databaseHex)?v=aaaabbbbccccddddeeeeffff00001111"
        let lookups = NotionSelfTestStub.seen.count
        model.testNotes()
        _ = pump(timeout: 5) { model.notesTestStatus != .running }
        stored = (try? Config.load(from: configURL))?.notes
        let looked = Array(NotionSelfTestStub.seen.dropFirst(lookups))
        let label = "“Inbox”" + tr("（数据库）", " (database)")
        check(model.notesTestStatus == .passed(label) && stored?.destination == .notion && stored?.notion?.kind == .database
              && stored?.notion?.dataSource == NotionSelfTestStub.dataSourceID && stored?.notion?.titleProperty == "Name"
              && looked.map(\.path) == ["/v1/pages/\(NotionSelfTestStub.databaseID)", "/v1/databases/\(NotionSelfTestStub.databaseID)",
                                         "/v1/data_sources/\(NotionSelfTestStub.dataSourceID)"]
              && looked.allSatisfy { $0.version == NotionAPI.version && $0.method == "GET" },
              "Notion's Test shows ✓ \(label) and keeps the database's data source (\(model.notesTestStatus))")
        model.notionLink = "https://example.com/Inbox-\(NotionSelfTestStub.databaseHex)"
        model.testNotes()
        _ = pump(timeout: 2) { model.notesTestStatus != .running }
        check(model.notesTestStatus == .failed(tr("不是 Notion 链接", "Not a Notion link")), "…and a link elsewhere isn't one (\(model.notesTestStatus))")
        let notion = stored ?? NoteSettings()

        // Through the controller.
        needing(.composing)
        func notice() -> String? { controller.panelModel().detail }
        func settle() { _ = pump(timeout: 6) { notice() == nil } }
        func note(_ pinyin: String) {
            _ = press(controller, client, "@", code: 0x13, flags: .shift)
            type("n", controller, client)
            _ = press(controller, client, "\t", code: VirtualKey.tab)
            type(pinyin, controller, client)
        }
        @MainActor final class Posted { var ids: [String] = [] }
        let posted = Posted()
        let observer = NotificationCenter.default.addObserver(forName: .allInOneIMENoteSaved, object: nil, queue: .main) { info in
            MainActor.assumeIsolated { posted.ids.append(info.userInfo?["id"] as? String ?? "") }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        // The menu bar panel, with stand-ins (nothing is opened), invisible.
        let stand = PanelStandIns()
        let panel = FloatingPanel(sources: stand.sources)
        panel.prepareWindow = { window in
            window.alphaValue = 0
            window.ignoresMouseEvents = true
        }
        panel.checksOcclusion = false
        panel.recordSavedNotes()
        defer {
            panel.closeDropDown()
            panel.stopRecordingSavedNotes()
        }
        let screen = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
        let anchor = CGRect(x: screen.maxX - 200, y: screen.maxY, width: 22, height: 24)

        // A folder of the self-test's own: one new file, the notice names the folder.
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        settings.notes = NoteSettings(destination: .folder, folder: inbox.path)
        controller.applySettings()
        let folderName = "“Inbox”"
        stand.notesFolder = inbox
        check(UIText.summary(.note) == tr("存一条笔记到\(folderName)", "Save a note to \(folderName)") && !controller.composer.noteLeavesDevice,
              "the command list says where @note saves (\(UIText.summary(.note)))")
        settle()
        note("nihao")
        _ = enter(controller, client)
        let file = inbox.appendingPathComponent("你好.md")
        let savedToFolder = pump(timeout: 3) { notice() == tr("已存到\(folderName)", "Saved to \(folderName)") }
        let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check(savedToFolder
              && (try? fm.contentsOfDirectory(atPath: inbox.path)) == ["你好.md"]
              && content.hasPrefix("---\ncreated: ") && content.hasSuffix("\n---\n你好"),
              "a folder save writes one file, named after the note, and says where (\(notice() ?? "no notice"))")
        let saved = SavedNotesStore.load(stand.defaults).notes.first
        check(saved?.id == file.absoluteString && posted.ids == [file.absoluteString] && saved?.title == "你好",
              "the menu bar panel is told of the file (\(saved?.id ?? "-"))")
        panel.toggleDropDown(below: anchor)
        check(pump(timeout: 2) { panel.notes.first?.id == file.absoluteString }, "…and lists it")
        // Looked at off the main thread, then opened: only a Markdown file in the notes folder.
        func opened(_ row: SavedNotes.Note?) -> URL? {
            let count = stand.openedURLs.count
            if let row { panel.open(row) }
            return pump(timeout: 3) { stand.openedURLs.count > count } ? stand.openedURLs.last : nil
        }
        let plainOpen = opened(panel.notes.first)
        check(plainOpen.map { $0.isFileURL && $0.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path } == true
              && stand.shownNotes.isEmpty,
              "a file opens in its default app (the URL built, not opened)")
        // In an Obsidian vault (`.obsidian` in a parent): opened in Obsidian, by its path.
        try? fm.createDirectory(at: root.appendingPathComponent(".obsidian", isDirectory: true), withIntermediateDirectories: true)
        let obsidian = opened(panel.notes.first).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        check(obsidian?.scheme == "obsidian" && obsidian?.host == "open"
              && obsidian?.queryItems?.first { $0.name == "path" }?.value.map {
                  URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path
              } == true,
              "…in a vault it opens in Obsidian (\(stand.openedURLs.last?.absoluteString ?? "-"))")
        check(MarkdownFolderDestination(folder: inbox).name == "Obsidian", "…and its notices say Obsidian (remembered, not looked up here)")
        // Outside the notes folder: not opened.
        stand.notesFolder = root.appendingPathComponent("Elsewhere", isDirectory: true)
        let openedBefore = stand.openedURLs.count
        if let row = panel.notes.first { panel.open(row) }
        check(pump(timeout: 3) { panel.message == tr("打不开这条笔记", "Couldn't open this note") } && stand.openedURLs.count == openedBefore,
              "a file outside the notes folder isn't opened (\(panel.message ?? "no message"))")
        stand.notesFolder = inbox
        // Gone (deleted, moved): no longer listed.
        try? fm.removeItem(at: file)
        panel.refresh()
        check(pump(timeout: 2) { panel.notes.isEmpty } && SavedNotesStore.load(stand.defaults).notes.isEmpty,
              "a file that's gone is dropped from the panel")
        // A folder that's gone: not made, the text back in the draft.
        settings.notes = NoteSettings(destination: .folder, folder: root.appendingPathComponent("Moved away").path)
        controller.applySettings()
        settle()
        note("nihao")
        _ = enter(controller, client)
        let gone = NoteError.folderMissing(path: "").message(language: UIText.language)
        check(pump(timeout: 3) { client.marked == "note › 你好" && notice()?.hasSuffix(gone) == true } && copied.last == "你好"
              && !fm.fileExists(atPath: root.appendingPathComponent("Moved away").path),
              "a folder that's gone isn't made; the note comes back into the draft, and onto the clipboard (\(notice() ?? "no notice"))")
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)

        // Notion, stubbed: the save posts the page's URL, which the panel opens.
        settings.notes = notion
        controller.applySettings()
        check(controller.composer.noteLeavesDevice && UIText.summary(.note) == tr("存一条笔记到 Notion", "Save a note to Notion"),
              "to Notion, the note leaves the Mac (\(UIText.summary(.note)))")
        let before = NotionSelfTestStub.seen.count
        settle()
        note("nihao")
        _ = enter(controller, client)
        let savedToNotion = pump(timeout: 5) { notice() == tr("已存到 Notion", "Saved to Notion") }
        let sent = Array(NotionSelfTestStub.seen.dropFirst(before))
        check(savedToNotion && posted.ids.last == NotionSelfTestStub.pageURL
              && sent.map(\.method) == ["POST"] && sent.first?.path == "/v1/pages" && sent.first?.version == NotionAPI.version,
              "a save to Notion is one POST, and the panel is told of the page's URL (\(notice() ?? "no notice"))")
        let page = opened(panel.notes.first(where: { $0.id == NotionSelfTestStub.pageURL }))
        check(page?.absoluteString == NotionSelfTestStub.pageURL, "…which opens by its URL (not opened here)")
        // Secure input on: nothing goes to Notion, the draft stays, a notice says why.
        controller.services.secureInputActive = { true }
        let sentBefore = NotionSelfTestStub.seen.count
        settle()
        note("nihao")
        _ = enter(controller, client)
        check(notice() == controller.composer.messages.secureInputNote && client.marked.hasPrefix("note › ")
              && NotionSelfTestStub.seen.count == sentBefore,
              "during secure input nothing is sent to Notion: \(notice() ?? "no notice")")
        controller.services.secureInputActive = secureBefore
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)
        check(reachedNotes == 0, "Notes was never reached")
        panel.closeDropDown()
    }
}
