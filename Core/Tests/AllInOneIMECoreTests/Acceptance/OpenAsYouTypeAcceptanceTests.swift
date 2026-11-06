import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// `@open` as you type, instant (0.6.9): what is in memory (`SessionServices.instantResults`: the app index, what `@open`
/// opened before, a path's folder) answers on the key that changed the text, from the first letter; while Spotlight
/// (`SessionServices.searchFiles`) searches the new text, the rows shown are those instant rows, then the rows shown
/// before that still match it, so the list never blinks; the full results of the last texts come back at once with
/// Backspace; Spotlight is asked after a short pause, one text at a time, and its answer for the text replaces the list
/// (an older text's removes nothing); the highlight follows the result picked with ↑↓. Point 6 (a faster Spotlight) is
/// the Mac's: not here.
///
/// Through a field's session (`FakeHost`), typed as the user types it: "@open", a space, letters, Backspace, ↓, ⏎. What
/// is in memory and Spotlight are stand-ins: Spotlight answers only when the test says so, and says what it was asked.
@Suite(.serialized)
struct OpenAsYouTypeAcceptanceTests {
    typealias Suite = OpenAsYouTypeAcceptanceTests

    // MARK: - What is found

    static let safari = SearchResult(name: "Safari", path: "/Applications/Safari.app")
    static let slack = SearchResult(name: "Slack", path: "/Applications/Slack.app")
    static let systemSettings = SearchResult(name: "System Settings", path: "/System/Applications/System Settings.app",
                                             chineseName: "系统设置")
    static let wechat = SearchResult(name: "WeChat", path: "/Applications/WeChat.app", chineseName: "微信")
    static let documents = SearchResult(name: "Documents", path: "/Users/me/Documents", isFolder: true, chineseName: "文稿")
    static let downloads = SearchResult(name: "Downloads", path: "/Users/me/Downloads", isFolder: true, chineseName: "下载")
    static let desktop = SearchResult(name: "Desktop", path: "/Users/me/Desktop", isFolder: true, chineseName: "桌面")

    /// Files only Spotlight finds.
    static let sales = SearchResult(name: "sales.xlsx", path: "/Users/me/Documents/sales.xlsx")
    static let safety = SearchResult(name: "safety.pdf", path: "/Users/me/Downloads/safety.pdf")
    static let safeguard = SearchResult(name: "safeguard.txt", path: "/Users/me/Documents/safeguard.txt")
    static let samples = SearchResult(name: "Samples", path: "/Users/me/Samples", isFolder: true)

    /// A file named after `text` ("abc.txt"), that only Spotlight finds.
    static func file(_ text: String) -> SearchResult { SearchResult(name: text + ".txt", path: "/Users/me/Notes/\(text).txt") }

    // MARK: - Stand-ins

    /// What is in memory (`SessionServices.instantResults`): the apps and places of an app index, the files `@open` opened
    /// before, and the home folder's listing for a path ("~/Doc"). A result is listed when each keyword starts one of
    /// the words of its name or other name (as the user expects of Raycast); the files opened before first. What it was
    /// asked, and the history it was given, are kept.
    final class Memory: @unchecked Sendable {
        let apps = [Suite.safari, Suite.slack, Suite.systemSettings, Suite.wechat,
                    Suite.documents, Suite.downloads, Suite.desktop]
        let home = [Suite.desktop, Suite.documents, Suite.downloads]
        private let asked = Locked<[(query: String, history: OpenHistory)]>(initialState: [])

        var queries: [String] { asked.withLock { $0.map(\.query) } }
        var histories: [OpenHistory] { asked.withLock { $0.map(\.history) } }

        func results(_ query: String, _ history: OpenHistory) -> [SearchResult] {
            asked.withLock { $0.append((query, history)) }
            if query.hasPrefix("~/") {
                let start = query.dropFirst(2).lowercased()
                return home.filter { $0.name.lowercased().hasPrefix(start) }
            }
            let keywords = FileSearchRanking.keywords(in: query).map { $0.lowercased() }
            let opened = history.entries.map { SearchResult(name: ($0.path as NSString).lastPathComponent, path: $0.path) }
            return (opened + apps).filter { result in
                let words = ([result.name] + (result.chineseName.map { [$0] } ?? []))
                    .flatMap { $0.lowercased().split(separator: " ") }
                return !keywords.isEmpty && keywords.allSatisfy { keyword in words.contains { $0.hasPrefix(keyword) } }
            }
        }
    }

    /// Spotlight (`SessionServices.searchFiles`): each search waits until the test answers it (`answer`), or until its
    /// task is cancelled (it then ends at once with nothing, as a stopped search does). What it was asked, when, which
    /// searches were stopped, and the most that ran at once are kept.
    final class Spotlight: @unchecked Sendable {
        struct Call {
            var text: String
            var asked: ContinuousClock.Instant
            var continuation: CheckedContinuation<[SearchResult], Never>?
            /// Nil while it runs.
            var answer: [SearchResult]?
            var stopped = false
        }

        struct State {
            var calls: [Call] = []
            var mostAtOnce = 0
        }

        private let state = Locked(initialState: State())

        /// The texts it was asked for, in order.
        var asked: [String] { state.withLock { $0.calls.map(\.text) } }
        /// The texts whose search was stopped before it answered.
        var stopped: [String] { state.withLock { $0.calls.filter(\.stopped).map(\.text) } }
        var mostAtOnce: Int { state.withLock { $0.mostAtOnce } }

        /// Whether a search for `text` runs (asked, not answered or stopped yet).
        func isSearching(_ text: String) -> Bool { state.withLock { $0.calls.contains { $0.text == text && $0.answer == nil } } }

        /// When it was last asked for `text`.
        func askedAt(_ text: String) -> ContinuousClock.Instant? { state.withLock { $0.calls.last { $0.text == text }?.asked } }

        func search(_ text: String) async -> [SearchResult] {
            let index = state.withLock { state in
                state.calls.append(Call(text: text, asked: .now))
                state.mostAtOnce = max(state.mostAtOnce, state.calls.filter { $0.answer == nil }.count)
                return state.calls.count - 1
            }
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let answer = state.withLock { state -> [SearchResult]? in
                        if let answer = state.calls[index].answer { return answer }
                        state.calls[index].continuation = continuation
                        return nil
                    }
                    if let answer { continuation.resume(returning: answer) }
                }
            } onCancel: {
                end(index, with: [], stopped: true)
            }
        }

        /// Answers the oldest search for `text` still running with `results`: false if none runs.
        @discardableResult
        func answer(_ text: String, with results: [SearchResult]) -> Bool {
            let running = state.withLock { $0.calls.firstIndex { $0.text == text && $0.answer == nil } }
            guard let index = running else { return false }
            end(index, with: results)
            return true
        }

        /// Every search still running ends, with nothing.
        func endAll() {
            let running = state.withLock { state in state.calls.indices.filter { state.calls[$0].answer == nil } }
            for index in running { end(index, with: []) }
        }

        private func end(_ index: Int, with results: [SearchResult], stopped: Bool = false) {
            let continuation = state.withLock { state -> CheckedContinuation<[SearchResult], Never>? in
                guard state.calls[index].answer == nil else { return nil }
                state.calls[index].answer = results
                state.calls[index].stopped = stopped
                defer { state.calls[index].continuation = nil }
                return state.calls[index].continuation
            }
            continuation?.resume(returning: results)
        }
    }

    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
        }
    }

    /// A field that has the focus with "@open " typed in it ("@open" and a space, as the user types it), what is in
    /// memory and Spotlight the stand-ins above.
    final class Field {
        let host: FakeHost
        let memory: Memory
        let spotlight: Spotlight

        init(history: OpenHistory = OpenHistory()) {
            let (settings, engine, memory, spotlight) = (Settings(), FakeEngine(), Memory(), Spotlight())
            (self.memory, self.spotlight) = (memory, spotlight)
            var services = SessionServices(loadSettings: { settings.config })
            services.levelOne = { .engine(engine) }
            services.programInstalled = { _ in true }
            services.loadOpenHistory = { history }
            services.instantResults = { query, history in memory.results(query, history) }
            services.searchFiles = { query, _ in await spotlight.search(query) }
            host = FakeHost(services: services)
            host.focus()
            host.type("@open ")
        }

        /// What is left running ends: nothing waits on this field's searches any more.
        deinit { spotlight.endAll() }

        /// The rows of the panel as shown (their text: a result's name), and the highlighted one.
        var rows: [String] { host.panel?.rows.map(\.text) ?? [] }
        var highlighted: String? {
            guard let panel = host.panel, let index = panel.highlighted, panel.rows.indices.contains(index) else { return nil }
            return panel.rows[index].text
        }

        func type(_ text: String) { host.type(text) }
        func press(_ key: KeyEvent) { host.press(key) }

        /// Hands the session what its work answered so far (nothing is waited for).
        func takeAnswers() { host.settle { true } }

        /// Waits until Spotlight is asked for `text` (and still searches it).
        func waitForSearch(_ text: String) -> Bool { host.settle { spotlight.isSearching(text) } }

        /// Spotlight answers `text` with `results` once it is asked for it, and the session takes the answer in: whether
        /// its rows replaced the list.
        func answer(_ text: String, with results: [SearchResult]) -> Bool {
            guard waitForSearch(text) else { return false }
            spotlight.answer(text, with: results)
            return host.settle { rows == results.map(\.name) }
        }

        /// `seconds` go by, the session taking in what its work answers meanwhile.
        func wait(_ seconds: TimeInterval) { host.settle(timeout: seconds) { false } }
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: - 1. Instant rows on the same key

    @Test func theFirstLetterListsWhatIsInMemoryOnTheSameKey() async {
        await inEnglish {
            let field = Field()
            field.type("s")  // the panel as the key left it: nothing that answers later handed to the session
            #expect(field.memory.queries.last == "s", "\(field.memory.queries)")
            #expect(field.rows == ["Safari", "Slack", "System Settings"], "\(field.rows)")
            #expect(field.highlighted == "Safari", "the highlight starts on the first row")
            field.type("l")
            #expect(field.rows == ["Slack"], "the next key too: \(field.rows)")
        }
    }

    /// One letter is never searched as it is typed (that takes seconds and finds files at random): ⏎ searches it.
    @Test func aSingleLetterIsSearchedOnlyWithReturn() async {
        await inEnglish {
            let field = Field()
            field.type("q")  // nothing in memory starts with it
            field.wait(0.2)  // well past the pause
            #expect(field.spotlight.asked.isEmpty, "\(field.spotlight.asked)")
            field.press(FakeHost.enter)
            #expect(field.waitForSearch("q"), "\(field.spotlight.asked)")
            field.spotlight.answer("q", with: [Self.file("q")])
            #expect(field.host.settle { field.host.composer.phase == .choosing }, "\(field.host.composer.phase)")
        }
    }

    @Test func whatOpenOpenedBeforeIsListedFromTheFirstLetter() async {
        await inEnglish {
            let plan = "/Users/me/Work/quarterly plan.key"
            let history = OpenHistory(entries: [.init(path: plan, date: Date(timeIntervalSince1970: 1_800_000_000))])
            let field = Field(history: history)
            field.type("q")
            #expect(field.rows == ["quarterly plan.key"], "\(field.rows)")
            #expect(field.memory.histories.last == history, "what was opened before is handed to what answers at once")
        }
    }

    @Test func aPathListsItsFolderOnTheSameKey() async {
        await inEnglish {
            let field = Field()
            field.type("~/D")
            #expect(field.rows == ["Desktop", "Documents", "Downloads"], "\(field.rows)")
            field.type("oc")
            #expect(field.memory.queries.last == "~/Doc" && field.rows == ["Documents"], "\(field.memory.queries) \(field.rows)")
        }
    }

    // MARK: - 2. The list never blinks

    /// While Spotlight searches the new text: what is in memory for it first, then the rows shown before that still
    /// match it, each once.
    @Test func theRowsThatStillMatchStayWhileSpotlightSearches() async {
        await inEnglish {
            let field = Field()
            field.type("sa")
            #expect(field.answer("sa", with: [Self.safari, Self.sales, Self.safety]), "\(field.rows)")
            field.type("f")
            #expect(field.rows == ["Safari", "safety.pdf"], "\(field.rows)")
            field.type("e")
            #expect(field.rows == ["safety.pdf"], "\(field.rows)")
        }
    }

    /// A keyword that is only in a row's path keeps it ("bud" in /Users/me/Budget/…).
    @Test func aRowStaysWhenTheNewWordIsInItsPath() async {
        await inEnglish {
            let report = SearchResult(name: "Q3 Report.pdf", path: "/Users/me/Budget/Q3 Report.pdf")
            let old = SearchResult(name: "report-old.txt", path: "/Users/me/Archive/report-old.txt")
            let field = Field()
            field.type("rep")
            #expect(field.answer("rep", with: [report, old]), "\(field.rows)")
            field.type(" bud")
            #expect(field.rows == ["Q3 Report.pdf"], "\(field.rows)")
        }
    }

    @Test func aRowStaysWhateverTheCaseAndAccents() async {
        await inEnglish {
            let menu = SearchResult(name: "Café Menu.pdf", path: "/Users/me/Documents/Café Menu.pdf")
            let cars = SearchResult(name: "Cars.numbers", path: "/Users/me/Documents/Cars.numbers")
            let field = Field()
            field.type("ca")
            #expect(field.answer("ca", with: [menu, cars]), "\(field.rows)")
            field.type("fe")
            #expect(field.rows == ["Café Menu.pdf"], "\(field.rows)")
            field.type(" MEN")
            #expect(field.rows == ["Café Menu.pdf"], "\(field.rows)")
        }
    }

    /// A keyword in a row's other name (an app's Chinese name) keeps it: one Spotlight found, not in memory.
    @Test func aRowStaysWhenTheNewWordIsInItsOtherName() async {
        await inEnglish {
            let preview = SearchResult(name: "Preview", path: "/System/Applications/Preview.app", chineseName: "预览")
            let prices = SearchResult(name: "prices.csv", path: "/Users/me/Documents/prices.csv")
            let field = Field()
            field.type("pr")
            #expect(field.answer("pr", with: [preview, prices]), "\(field.rows)")
            field.type(" 预")
            #expect(field.rows == ["Preview"], "\(field.host.composer.draft) \(field.rows)")
        }
    }

    @Test func thePlainOpenStateComesBackOnlyWhenNothingMatches() async {
        await inEnglish {
            let field = Field()
            field.type("sa")
            #expect(field.answer("sa", with: [Self.safari, Self.sales]), "\(field.rows)")
            field.type("l")
            #expect(field.rows == ["sales.xlsx"], "something still matches: \(field.rows)")
            field.type("x")
            #expect(field.host.panel != nil && field.rows.isEmpty, "nothing matches \"salx\": \(field.rows)")
        }
    }

    // MARK: - 3. Backspace is instant too

    @Test func backspaceShowsTheResultsOfTheTextBeforeAtOnce() async {
        await inEnglish {
            let field = Field()
            field.type("sa")
            #expect(field.answer("sa", with: [Self.sales, Self.safari, Self.samples]), "\(field.rows)")
            field.type("f")
            #expect(field.answer("saf", with: [Self.safari, Self.safety]), "\(field.rows)")
            field.press(backspaceKey)
            #expect(["sales.xlsx", "Safari", "Samples"].allSatisfy(field.rows.contains), "\(field.rows)")
        }
    }

    @Test func theResultsOfTheLastTwentyTextsAreKept() async {
        await inEnglish {
            let field = Field()
            var (text, unanswered) = ("", [String]())
            for letter in "abcdefghijklmnopqrstu" {  // twenty texts searched as typed: "ab" to all 21 letters
                field.type(String(letter))
                text.append(letter)
                if text.count > 1, !field.answer(text, with: [Self.file(text)]) { unanswered.append(text) }
            }
            #expect(unanswered.isEmpty, "\(unanswered)")
            var missing: [String] = []
            for _ in 0..<19 {  // back to "ab": each of the nineteen texts before shows its results on the key
                field.press(backspaceKey)
                text.removeLast()
                if !field.rows.contains(Self.file(text).name) { missing.append(text) }
            }
            #expect(missing.isEmpty, "\(missing)")
        }
    }

    // MARK: - 4. Spotlight joins when it answers

    /// Asked within ~60 ms of the last key: the quickest of three (a busy machine may be slow to run it).
    @Test func spotlightIsAskedSoonAfterTheLastKey() async {
        await inEnglish {
            let field = Field()
            var (text, pauses) = ("s", [Duration]())
            field.type(text)
            for letter in ["a", "f", "e"] {
                field.type(letter)
                let typed = ContinuousClock.now
                text += letter
                #expect(field.waitForSearch(text), "\(field.spotlight.asked)")
                if let asked = field.spotlight.askedAt(text) { pauses.append(asked - typed) }
            }
            #expect(pauses.count == 3 && pauses.min().map { $0 < .milliseconds(100) } == true, "\(pauses)")
        }
    }

    @Test func spotlightSearchesOneTextAtATime() async {
        await inEnglish {
            let field = Field()
            for (keys, text) in [("sa", "sa"), ("f", "saf"), ("e", "safe")] {
                field.type(keys)
                #expect(field.waitForSearch(text), "\(field.spotlight.asked)")
            }
            #expect(field.spotlight.mostAtOnce == 1, "\(field.spotlight.mostAtOnce) at once")
            #expect(field.spotlight.stopped == ["sa", "saf"], "a new text stops the search before: \(field.spotlight.stopped)")
        }
    }

    @Test func spotlightsAnswerForTheTextReplacesTheList() async {
        await inEnglish {
            let field = Field()
            field.type("sa")
            #expect(field.rows == ["Safari"], "\(field.rows)")
            #expect(field.waitForSearch("sa"))
            field.spotlight.answer("sa", with: [Self.sales, Self.safari, Self.samples])
            #expect(field.host.settle { field.rows == ["sales.xlsx", "Safari", "Samples"] }, "its order: \(field.rows)")
            #expect(field.highlighted == "sales.xlsx")
        }
    }

    /// Spotlight answers "saf" as "e" is typed: the session hears it after the key, for a text that is no longer typed.
    @Test func anAnswerForAnOlderTextRemovesNothingAndLeavesTheHighlight() async {
        await inEnglish {
            let field = Field()
            field.type("sa")
            #expect(field.answer("sa", with: [Self.safari, Self.sales, Self.safety]), "\(field.rows)")
            field.type("f")
            field.press(FakeHost.down)
            #expect(field.rows == ["Safari", "safety.pdf"] && field.highlighted == "safety.pdf", "\(field.rows)")
            #expect(field.waitForSearch("saf"))
            field.takeAnswers()
            field.spotlight.answer("saf", with: [Self.safari, Self.safeguard, Self.safety])
            field.host.waitForAnswer(timeout: 2) { if case .task = $0 { true } else { false } }
            field.type("e")
            let shown = field.rows
            #expect(shown == ["safety.pdf"] && field.highlighted == "safety.pdf", "\(shown)")
            field.takeAnswers()
            #expect(shown.allSatisfy(field.rows.contains), "nothing removed: \(field.rows)")
            #expect(field.highlighted == "safety.pdf")
            #expect(!field.rows.contains("Safari"), "only rows that match \"safe\" are added: \(field.rows)")
        }
    }

    // MARK: - 5. The highlight

    @Test func theHighlightStaysOnThePickedResultAsRowsComeAndGo() async {
        await inEnglish {
            let field = Field()
            field.type("sa")
            #expect(field.answer("sa", with: [Self.safari, Self.sales, Self.safety]), "\(field.rows)")
            field.press(FakeHost.down)
            field.press(FakeHost.down)
            #expect(field.highlighted == "safety.pdf")
            field.type("f")
            #expect(field.rows == ["Safari", "safety.pdf"] && field.highlighted == "safety.pdf", "\(field.rows)")
            #expect(field.waitForSearch("saf"))
            field.spotlight.answer("saf", with: [Self.safeguard, Self.safari, Self.safety])
            #expect(field.host.settle { field.rows == ["safeguard.txt", "Safari", "safety.pdf"] }, "\(field.rows)")
            #expect(field.highlighted == "safety.pdf")
            field.press(FakeHost.enter)
            #expect(field.host.opened == [Self.safety.path], "\(field.host.opened)")
        }
    }

    @Test func theHighlightGoesBackToTheFirstRowWhenItsResultIsGone() async {
        await inEnglish {
            let field = Field()
            field.type("sa")
            #expect(field.answer("sa", with: [Self.safari, Self.sales, Self.safety]), "\(field.rows)")
            field.press(FakeHost.down)
            #expect(field.highlighted == "sales.xlsx")
            field.type("f")
            #expect(field.rows == ["Safari", "safety.pdf"], "\(field.rows)")
            #expect(field.highlighted == "Safari", "sales.xlsx is gone: back on the first row")
        }
    }

    /// An instant row is a real result: ⏎ opens the row highlighted when it is pressed, Spotlight not answered yet.
    @Test func returnOpensTheHighlightedInstantRowBeforeSpotlightAnswers() async {
        await inEnglish {
            let first = Field()
            first.type("sl")
            first.press(FakeHost.enter)
            #expect(first.host.opened == [Self.slack.path], "\(first.host.opened)")
            let picked = Field()
            picked.type("s")
            picked.press(FakeHost.down)
            picked.press(FakeHost.enter)
            #expect(picked.host.opened == [Self.slack.path], "\(picked.host.opened)")
        }
    }

    /// Nothing is named like the text: ⏎ doesn't open the first content match, it lists them to pick from; one picked
    /// with ↓ opens.
    @Test func onlyContentMatchesAreStillListedToPickFrom() async {
        await inEnglish {
            let notes = SearchResult(name: "notes.md", path: "/Users/me/notes.md", matchedContent: true)
            let todo = SearchResult(name: "todo.txt", path: "/Users/me/todo.txt", matchedContent: true)
            let listed = Field()
            listed.type("xy")
            #expect(listed.answer("xy", with: [notes, todo]), "\(listed.rows)")
            listed.press(FakeHost.enter)
            #expect(listed.host.opened.isEmpty, "\(listed.host.opened)")
            #expect(listed.waitForSearch("xy") && listed.spotlight.asked == ["xy", "xy"], "\(listed.spotlight.asked)")
            listed.spotlight.answer("xy", with: [notes, todo])
            #expect(listed.host.settle { listed.host.composer.phase == .choosing }, "\(listed.host.composer.phase)")
            #expect(["notes.md", "todo.txt"].allSatisfy(listed.rows.contains), "\(listed.rows)")
            let picked = Field()
            picked.type("xy")
            #expect(picked.answer("xy", with: [notes, todo]), "\(picked.rows)")
            picked.press(FakeHost.down)
            picked.press(FakeHost.enter)
            #expect(picked.host.opened == [todo.path], "\(picked.host.opened)")
        }
    }
}
