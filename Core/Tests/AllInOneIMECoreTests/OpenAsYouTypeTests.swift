import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// `@open` as its text is typed, through a field's session (`InputSession`, `FakeHost`): what is known at once is listed
/// on the key that changed the text (`SessionServices.instantResults`), the rows don't go while the full search runs
/// (`searchFiles`), a text typed before comes back with what its search found, and a highlight moved with ↑↓ stays on its
/// result. The searches are the tests' own; what they answer reaches the session only when the test settles.
@Suite(.serialized)
struct OpenAsYouTypeTests {
    static let safari = SearchResult(name: "Safari", path: "/Applications/Safari.app")
    static let slack = SearchResult(name: "Slack", path: "/Applications/Slack.app")
    static let settings = SearchResult(name: "System Settings", path: "/System/Applications/System Settings.app",
                                       chineseName: "系统设置")
    static let notesApp = SearchResult(name: "Notes", path: "/System/Applications/Notes.app")
    static let notesFile = SearchResult(name: "notes.md", path: "/Users/me/notes.md")
    static let nomad = SearchResult(name: "nomad.txt", path: "/Users/me/nomad.txt")
    static let notebook = SearchResult(name: "notebook.pdf", path: "/Users/me/notebook.pdf")

    /// What is known at once, by text (else nothing); what the full search finds, by text (else nothing), and the texts it
    /// was asked for.
    final class Stand: @unchecked Sendable {
        let instant: [String: [SearchResult]]
        let full: [String: [SearchResult]]
        let searched = Locked<[String]>(initialState: [])
        let asked = Locked<[String]>(initialState: [])
        init(instant: [String: [SearchResult]], full: [String: [SearchResult]] = [:]) {
            self.instant = instant
            self.full = full
        }
    }

    /// A session in a field with the focus, letters typed as they are (English), `@open` picked.
    func open(_ stand: Stand) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        var services = SessionServices(loadSettings: { config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.instantResults = { query, _ in
            stand.asked.withLock { $0.append(query) }
            return stand.instant[query] ?? []
        }
        services.searchFiles = { query, _ in
            stand.searched.withLock { $0.append(query) }
            return stand.full[query] ?? []
        }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        host.press(FakeHost.at)
        host.type("ope")
        host.press(FakeHost.tab)
        // What one @ asked for its letters before @open was picked isn't @open's.
        stand.asked.withLock { $0 = [] }
        return host
    }

    func rows(_ host: FakeHost) -> [String] { host.panel?.rows.map(\.text) ?? [] }

    /// The panels shown since output `from`, by their rows.
    func panelsShown(_ host: FakeHost, since from: Int) -> [[String]] {
        host.outputs.dropFirst(from).compactMap { if case let .panel(model) = $0 { model?.rows.map(\.text) ?? [] } else { nil } }
    }

    @Test func theFirstLetterListsWhatIsKnownAtOnceAndReturnOpensIt() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["s": [Self.safari, Self.slack, Self.settings]])
            let host = open(stand)
            host.type("s")
            // On the key itself: no search answered (none runs for one letter).
            #expect(rows(host) == ["Safari", "Slack", "System Settings"] && host.composer.liveHighlight == 0, "\(rows(host))")
            #expect(stand.asked.withLock { $0 } == ["s"], "asked once for the text")
            host.press(FakeHost.down)
            host.press(FakeHost.enter)
            #expect(host.opened == [Self.slack.path] && stand.searched.withLock { $0 }.isEmpty, "\(host.opened)")
        }
    }

    @Test func theRowsStayWhileTheSearchRunsAndItsRowsReplaceThem() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["no": [Self.notesApp], "not": [Self.notesApp]],
                              full: ["no": [Self.notesApp, Self.notesFile, Self.nomad], "not": [Self.notesApp, Self.notebook, Self.notesFile]])
            let host = open(stand)
            host.type("no")
            #expect(rows(host) == ["Notes"])
            #expect(host.settle { rows(host).count == 3 }, "the search for \"no\" answered (\(rows(host)))")
            let before = host.outputs.count
            host.type("t")
            // What is known for "not", then the rows of "no" that still have it, each once: nomad.txt doesn't.
            #expect(rows(host) == ["Notes", "notes.md"], "\(rows(host))")
            #expect(host.settle { rows(host) == ["Notes", "notebook.pdf", "notes.md"] }, "its search's rows, ranked (\(rows(host)))")
            #expect(!panelsShown(host, since: before).contains { $0.isEmpty }, "never without rows: \(panelsShown(host, since: before))")
            #expect(stand.searched.withLock { $0 } == ["no", "not"])
        }
    }

    @Test func nothingMatchingFallsBackToThePlainPanel() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["no": [Self.notesApp]])
            let host = open(stand)
            host.type("no")
            #expect(rows(host) == ["Notes"])
            host.type("x")
            #expect(rows(host).isEmpty && host.panel != nil && host.composer.currentLiveResults.isEmpty, "\(rows(host))")
        }
    }

    @Test func aTextTypedBeforeComesBackWithWhatItsSearchFound() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["no": [Self.notesApp], "not": [Self.notesApp]],
                              full: ["no": [Self.notesApp, Self.notesFile, Self.nomad], "not": [Self.notebook]])
            let host = open(stand)
            host.type("no")
            #expect(host.settle { rows(host).count == 3 })
            host.type("t")
            #expect(host.settle { rows(host) == ["notebook.pdf"] }, "\(rows(host))")
            host.press(backspaceKey)
            // On the key: all "no" found, not what is known at once for it (that isn't asked again).
            #expect(rows(host) == ["Notes", "notes.md", "nomad.txt"], "\(rows(host))")
            #expect(stand.asked.withLock { $0 } == ["n", "no", "not"])
            // Its search runs again; what it finds takes the rows' place.
            #expect(host.settle { stand.searched.withLock { $0 } == ["no", "not", "no"] })
        }
    }

    @Test func theTextsKeptGoWithTheFieldsSession() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["no": [Self.notesApp]], full: ["no": [Self.notesApp, Self.notesFile]])
            let host = open(stand)
            host.type("no")
            #expect(host.settle { rows(host).count == 2 })
            host.press(FakeHost.escape)
            host.send(.close)
            host.focus()
            host.composer.setInputMode(.english)
            host.press(FakeHost.at)
            host.type("ope")
            host.press(FakeHost.tab)
            host.type("no")
            #expect(rows(host) == ["Notes"], "what is known at once, not what was kept (\(rows(host)) \(host.composer.draft))")
        }
    }

    @Test func aHighlightMovedStaysOnItsResultAsTheRowsChange() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["no": [Self.notesApp, Self.notesFile]],
                              full: ["no": [Self.nomad, Self.notesApp, Self.notesFile]])
            let host = open(stand)
            host.type("no")
            host.press(FakeHost.down)
            #expect(host.composer.liveHighlight == 1)
            #expect(host.settle { rows(host).count == 3 })
            #expect(host.composer.liveHighlight == 2 && host.panel?.highlighted == 2, "still on notes.md")
            host.press(FakeHost.enter)
            #expect(host.opened == [Self.notesFile.path], "\(host.opened)")
        }
    }

    @Test func aHighlightNotMovedIsOnTheFirstOfTheNewRows() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["no": [Self.notesApp]], full: ["no": [Self.nomad, Self.notesApp]])
            let host = open(stand)
            host.type("no")
            #expect(host.settle { rows(host).count == 2 })
            #expect(host.composer.liveHighlight == 0)
            host.press(FakeHost.enter)
            #expect(host.opened == [Self.nomad.path], "\(host.opened)")
        }
    }

    @Test func returnOpensTheRowHighlightedBeforeTheSearchAnswers() async {
        await withInterfaceLanguage("en") {
            let stand = Stand(instant: ["safari": [Self.safari]], full: ["safari": [Self.notebook]])
            let host = open(stand)
            host.type("safari")
            host.press(FakeHost.enter)
            #expect(host.opened == [Self.safari.path] && host.composer.draft.isEmpty, "\(host.opened)")
        }
    }

    // MARK: - The composer's side

    /// A session with `@open text` typed and what is known at once for each text, and its composer.
    func composer(typing text: String, instant: [String: [SearchResult]] = [:]) -> (FakeHost, Composer) {
        let host = open(Stand(instant: instant))
        host.type(text)
        return (host, host.composer)
    }

    @Test func anAnswerForATextTypedBeforeOnlyAddsWhatMatchesTheTextNow() {
        let (_, c) = composer(typing: "not", instant: ["not": [Self.notesApp, Self.notesFile]])
        _ = c.handleKeyDown(downKey)
        #expect(c.liveHighlight == 1)
        // "no" found nomad.txt (not "not"), notes.md again (listed already) and notebook.pdf: only that one is added, after.
        #expect(c.receiveLive([Self.nomad, Self.notesFile, Self.notebook], for: "no") == [.showPanel])
        #expect(c.currentLiveResults == [Self.notesApp, Self.notesFile, Self.notebook] && c.liveHighlight == 1)
        #expect(c.receiveLive([Self.nomad], for: "no").isEmpty, "nothing to add: nothing changes")
        #expect(c.currentLiveResults.count == 3 && c.liveHighlight == 1)
    }

    @Test func whatIsFoundSoFarIsListedButNotKept() {
        let (_, c) = composer(typing: "not")
        _ = c.receiveLive([Self.notesFile], for: "not", isFinal: false)
        #expect(c.currentLiveResults == [Self.notesFile])
        _ = c.receiveLive([Self.notesFile, Self.notebook], for: "not")
        #expect(c.currentLiveResults == [Self.notesFile, Self.notebook])
        // A text found so far only isn't one to come back to: "no" lists what is known at once.
        _ = c.receiveLive([Self.nomad], for: "no", isFinal: false)
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.liveQuery == "no" && c.currentLiveResults == [Self.notesFile, Self.notebook], "the rows of \"not\" match \"no\" too")
    }

    @Test func rowsStillMatchByNameOtherNameOrPathCaseAndAccentsAside() {
        let keywords = { FileSearchRanking.keywords(in: $0) }
        #expect(Composer.stillMatches(Self.settings, keywords("SYS set")))
        #expect(Composer.stillMatches(Self.settings, keywords("系统")), "its Chinese name")
        #expect(Composer.stillMatches(Self.notesFile, keywords("me note")), "a folder of its path")
        #expect(Composer.stillMatches(SearchResult(name: "Café.txt", path: "/tmp/Café.txt"), keywords("cafe")))
        #expect(!Composer.stillMatches(Self.notesFile, keywords("note x")) && !Composer.stillMatches(Self.notesFile, []))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Composer.stillMatches(SearchResult(name: "Documents", path: home + "/Documents", isFolder: true), keywords("~/Doc")),
                "a path as typed, with the home folder as ~")
    }

    @Test func atLeastTheLastThirtyTwoTextsAreKept() {
        let (host, c) = composer(typing: "a")
        for n in 0..<33 { _ = c.receiveLive([SearchResult(name: "f\(n)", path: "/f\(n)")], for: "t\(n)") }
        func comingBack(to text: String) -> [String] {
            while c.draft != "@open " { host.press(backspaceKey) }
            host.type(text)
            return rows(host)
        }
        #expect(comingBack(to: "t32") == ["f32"] && comingBack(to: "t1") == ["f1"])
        #expect(comingBack(to: "t0").isEmpty, "the oldest is forgotten")
        #expect(Composer.recentLiveLimit >= 20)
    }

    // MARK: - The full search

    @Test func theFullSearchStartsAfterAShortPauseAndTellsWhatItFoundSoFar() async {
        #expect(SessionTasks.liveSearchPause <= 60_000_000)
        let events = Locked<[SessionEvent]>(initialState: [])
        let tasks = SessionTasks(deliver: { event in events.withLock { $0.append(event) } })
        tasks.searchAsTyped("not", history: { OpenHistory() }, with: { query, _ in
            FileSearchProgress.found?([Self.notesFile])
            return [Self.notesFile, Self.notebook]
        })
        #expect(await Timing.eventually { events.withLock { $0.count } == 2 })
        let updates = events.withLock { $0 }.compactMap { event -> String? in
            guard case let .task(id, update) = event, tasks.isCurrent(id) else { return nil }
            switch update {
            case let .liveSoFar(results, query): return "so far \(query): \(results.map(\.name))"
            case let .live(results, query): return "all \(query): \(results.map(\.name))"
            default: return nil
            }
        }
        #expect(updates == ["so far not: [\"notes.md\"]", "all not: [\"notes.md\", \"notebook.pdf\"]"], "\(updates)")
        #expect(FileSearchProgress.found == nil, "only while the search as you type runs")
    }
}
