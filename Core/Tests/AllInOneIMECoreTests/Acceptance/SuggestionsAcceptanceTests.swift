import CryptoKit
import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Suggestions v1 (.spec/spec-suggestions-v1.md, 2026-10-22, with its section 6: the decisions on the tests' questions):
// the acceptance tests, written from the spec before the implementation by an author other than the implementation's
// (whose changes don't edit them). They drive a text field's `InputSession` as a shell does (`FakeHost`): keys in, what
// the user sees (the candidate panel's rows, its footer) and what goes into the field out. The plugin's side is a fake
// runtime that answers `load` and `query` with what a script would return (the fixtures in Fixtures/Suggestions/); the
// time is a clock the test moves (and that moves on while a test waits), the session's timers fire once due on it; what
// the shell keeps (the switches, the picks, the coding packs installed, Translate as You Type, the cache's folder) is the
// test's.
// Declarations they use: Sources/AllInOneIMECore/Suggestions/SuggestionsContract.swift.
//
// Spec 4, bullet by bullet:
// - token tracking (English and pinyin, boundaries, `@`, `＃`), applicability (prefix, minChars, exact):
//   SuggestionsTokenAcceptanceTests
// - list and query merged, a query cancelled, the cache per prefix, refreshes, failures, the script's ctx, the plugin's
//   outputs (good, bad, oversized, control and bidi characters, duplicates): SuggestionsSourcesAcceptanceTests
// - at most 5 rows, their order (picked before first), the keys per app class, what is inserted with the templates per
//   class: SuggestionsRowsAcceptanceTests
// - never-run rules (secure fields, remote apps, the master, app and source switches, a plugin changed since it was
//   enabled), privacy (nothing logged, nothing learned as English words): SuggestionsSwitchesAcceptanceTests
// - Code, the input (decision 22, which replaced coding mode and decision 13's chooser): a tap of Shift through the
//   inputs, the long press toggling Translate as You Type with no chooser, an app starting in Code, the coding language's
//   pack alone, its keywords and snippets, document words, `$0`, no Translate as You Type and no English words in Code:
//   SuggestionsCodingAcceptanceTests
// - plugin.json's `completions` and `preferences` read and refused, a coding pack's format:
//   SuggestionsManifestAcceptanceTests
// - rows over ghost text (Autocomplete), none in Code: SuggestionsGhostTextAcceptanceTests
//
// Spec 6, decision by decision: 1 (digits never pick rows) Rows, Coding; 2 (the long press in the session) Coding; 3
// GhostText; 4 (when a query is asked again) Sources; 5, 6 (bad items dropped one by one, stripped first) Sources; 7
// (case, the prefix's too) Token, Rows; 8 (without prefix: digits, exact) Token, Manifest; 9 (an entry refused, the
// plugin loaded) Manifest, Sources; 10, 11 (the terminal and code editor class, the app classes) Rows, Coding; 12 (Esc
// for the token) Rows; 13 (what is offered) Rows, Coding; 14 (the command trigger) Switches; 15 (English words) Switches;
// 16 (no field text) Coding; 17 (picked order, pauses and back-off, the cache on disk) Rows, Sources, Switches; 19, 21,
// 23 (a snippet's later lines indented, its caret at its first tab stop in reading order) Coding; 20 (Return picks Code's
// rows as in an IDE) Coding; 22 (Code, an input) Coding, GhostText, Switches.
//
// This file: what they share.

// MARK: - One at a time

/// The Suggestions suites' session tests run one at a time, a test waiting its turn without holding a thread. Each holds
/// the interface language's turn (`withInterfaceLanguage`) while it waits for its session's work (the runtime's calls,
/// Autocomplete's request), which needs a thread of the concurrency pool (as many as the cores): tests that held a
/// thread while they waited for their turn could take them all, and the work waited for would never run.
struct SuggestionsOneAtATime: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> SuggestionsOneAtATime? {
        testCase == nil ? nil : self
    }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        await SuggestionsTurn.shared.take()
        do {
            try await function()
        } catch {
            await SuggestionsTurn.shared.give()
            throw error
        }
        await SuggestionsTurn.shared.give()
    }
}

/// Whose turn it is: one test's at a time, the others waiting (suspended) in order.
actor SuggestionsTurn {
    static let shared = SuggestionsTurn()
    private var taken = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func take() async {
        guard taken else {
            taken = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func give() {
        if waiting.isEmpty { taken = false } else { waiting.removeFirst().resume() }
    }
}

// MARK: - The time

/// The session's time (`SuggestionsServices.now`), moved by the test.
final class SuggestionsClock: @unchecked Sendable {
    private let value = Locked(initialState: Date(timeIntervalSince1970: 1_790_000_000))

    var now: Date { value.withLock { $0 } }
    /// The time as a modifier change's timestamp.
    var timestamp: TimeInterval { now.timeIntervalSinceReferenceDate }

    func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

// MARK: - The plugin's side

/// Stands in for the plugins' runtime: answers `load` and `query` with what a script would return (JSON), by source and
/// by query text; or holds a call until the test answers it (`holdQueries`, `holdLoads`); records every call, and
/// those cancelled.
final class FakeCompletionRuntime: CompletionRuntime, @unchecked Sendable {
    enum Answer: Sendable {
        case output(Data)
        case failure(String)
    }

    struct Call: Sendable {
        var kind: Kind
        var text: String?
        var call: CompletionCall
    }

    enum Kind: Sendable { case load, query }

    private struct State {
        var lists: [String: Answer] = [:]
        var queryAnswers: [String: Answer] = [:]
        var queryDefault: Answer = .output(Data(#"{"items":[]}"#.utf8))
        var holdQueries = false
        var holdLoads = false
        var calls: [Call] = []
        var held: [Int: CheckedContinuation<Void, Error>] = [:]
        var heldKeys: [Int: String] = [:]
        var cancelledBeforeHeld: Set<Int> = []
        var cancelled: [String] = []
        var finished: [Int] = []
        /// The calls running, by id (a call cancelled stops running then, whenever its task ends).
        var running: [Int: Kind] = [:]
        var mostInFlight = 0
        var mostQueriesInFlight = 0
        var nextID = 0
    }

    private let state = Locked(initialState: State())

    /// What `load` returns for source `source` (its name).
    func list(_ source: String, _ answer: Answer) { state.withLock { $0.lists[source] = answer } }
    func list(_ source: String, items: [CompletionItem], fetchedAt: Date? = nil) {
        list(source, .output(SuggestionsJSON.list(items, fetchedAt: fetchedAt)))
    }
    /// What `query(text)` returns (any source); others return no items.
    func query(_ text: String, _ answer: Answer) { state.withLock { $0.queryAnswers[text] = answer } }
    func query(_ text: String, items: [CompletionItem]) { query(text, .output(SuggestionsJSON.list(items))) }

    var holdQueries: Bool {
        get { state.withLock { $0.holdQueries } }
        set { state.withLock { $0.holdQueries = newValue } }
    }
    var holdLoads: Bool {
        get { state.withLock { $0.holdLoads } }
        set { state.withLock { $0.holdLoads = newValue } }
    }

    var calls: [Call] { state.withLock { $0.calls } }
    var loads: [CompletionCall] { calls.filter { $0.kind == .load }.map(\.call) }
    /// The query texts asked, in order.
    var queries: [String] { calls.filter { $0.kind == .query }.compactMap(\.text) }
    var queryCalls: [CompletionCall] { calls.filter { $0.kind == .query }.map(\.call) }
    /// The calls cancelled while they were held, by their query text ("load:<source>" for a load).
    var cancelled: [String] { state.withLock { $0.cancelled } }
    /// The most calls running at once, and of them queries.
    var mostInFlight: Int { state.withLock { $0.mostInFlight } }
    var mostQueriesInFlight: Int { state.withLock { $0.mostQueriesInFlight } }
    /// The calls held now, by their query text ("load:<source>" for a load).
    var waiting: [String] { state.withLock { state in state.held.keys.sorted().compactMap { state.heldKeys[$0] } } }

    /// Lets the held calls for `key` (a query's text, or "load:<source>") go on, to answer what they're set to answer now.
    func release(_ key: String) {
        let continuations = state.withLock { state -> [CheckedContinuation<Void, Error>] in
            let ids = state.heldKeys.filter { $0.value == key }.map(\.key)
            return ids.compactMap { state.held.removeValue(forKey: $0) }
        }
        for continuation in continuations { continuation.resume() }
    }

    /// Lets every held call go on (the end of a test that held some).
    func releaseAll() {
        let continuations = state.withLock { state -> [CheckedContinuation<Void, Error>] in
            defer { state.held = [:] }
            return Array(state.held.values)
        }
        for continuation in continuations { continuation.resume() }
    }

    func load(_ call: CompletionCall) async throws -> Data {
        try await answer(.load, text: nil, call)
    }

    func query(_ text: String, _ call: CompletionCall) async throws -> Data {
        try await answer(.query, text: text, call)
    }

    private func answer(_ kind: Kind, text: String?, _ call: CompletionCall) async throws -> Data {
        let key = text ?? "load:" + call.source.name
        let (id, hold) = state.withLock { state -> (Int, Bool) in
            state.calls.append(Call(kind: kind, text: text, call: call))
            state.nextID += 1
            state.running[state.nextID] = kind
            state.mostInFlight = max(state.mostInFlight, state.running.count)
            state.mostQueriesInFlight = max(state.mostQueriesInFlight, state.running.values.filter { $0 == .query }.count)
            state.heldKeys[state.nextID] = key
            return (state.nextID, kind == .query ? state.holdQueries : state.holdLoads)
        }
        defer { _ = state.withLock { $0.running.removeValue(forKey: id) } }
        if hold {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let cancelledAlready = state.withLock { state -> Bool in
                        if state.cancelledBeforeHeld.remove(id) != nil { return true }
                        state.held[id] = continuation
                        return false
                    }
                    if cancelledAlready { continuation.resume(throwing: CancellationError()) }
                }
            } onCancel: {
                let continuation = state.withLock { state -> CheckedContinuation<Void, Error>? in
                    state.cancelled.append(key)
                    state.running.removeValue(forKey: id)
                    guard let continuation = state.held.removeValue(forKey: id) else {
                        state.cancelledBeforeHeld.insert(id)
                        return nil
                    }
                    return continuation
                }
                continuation?.resume(throwing: CancellationError())
            }
        }
        let reply = state.withLock { state -> Answer in
            switch kind {
            case .load: return state.lists[call.source.name] ?? .failure("no list for \(call.source.name)")
            case .query: return state.queryAnswers[text ?? ""] ?? state.queryDefault
            }
        }
        switch reply {
        case let .output(data): return data
        case let .failure(message): throw SuggestionsTestError.scriptFailed(message)
        }
    }
}

enum SuggestionsTestError: Error, Equatable {
    case scriptFailed(String)
}

/// What a script returns, as JSON.
enum SuggestionsJSON {
    static func list(_ items: [CompletionItem], fetchedAt: Date? = nil) -> Data {
        let list = CompletionList(items: items, fetchedAt: fetchedAt.map { $0.timeIntervalSince1970.rounded() })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(list)) ?? Data()
    }
}

// MARK: - Fixtures

/// Fixtures/Suggestions/: plugin outputs and coding packs.
enum SuggestionsFixtures {
    static func url(_ name: String, _ ext: String = "json", in folder: String = "") throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext,
                                       subdirectory: "Fixtures/Suggestions" + (folder.isEmpty ? "" : "/" + folder)))
    }

    static func data(_ name: String, _ ext: String = "json", in folder: String = "") throws -> Data {
        try Data(contentsOf: url(name, ext, in: folder))
    }

    /// A plugin output in Fixtures/Suggestions/outputs/.
    static func output(_ name: String) throws -> Data { try data(name, in: "outputs") }

    /// More items than a list may have (20,001), each well formed.
    static func tooManyItems() -> Data {
        SuggestionsJSON.list((1...CompletionList.maxItems + 1).map { CompletionItem(match: "#\($0)") })
    }

    /// Fewer items than the most a list may have, but more than 4 MiB of them.
    static func tooManyBytes() -> Data {
        let title = String(repeating: "x", count: 1000)
        return SuggestionsJSON.list((1...4500).map { CompletionItem(match: "#\($0)", title: title) })
    }
}

// MARK: - Plugins on disk

/// Plugin folders written for a test (plugin.json and main.js), read as the app reads them (`PluginStore.load`).
enum SuggestionsPlugins {
    /// A script that exports what a completion source needs (the fake runtime answers for it in the tests).
    static let script = """
        function load(ctx) { return { items: [] }; }
        function query(text, ctx) { return { items: [] }; }
        """

    /// The spec's example, as the tests use it: GitHub issues after "#" (from `minChars` digits on), a list refreshed every
    /// 15 minutes and a live query from 2 characters on, `{arg}` inserted (with the issue's address in chat apps); `extra`:
    /// more sources after it.
    static func githubManifest(hosts: [String] = ["api.github.com"], minChars: Int = 1, query: Bool = true,
                               insert: String = #"{ "default": "{arg}", "chat": ["{arg} {url}", "{arg}"], "terminal": "{match}" }"#,
                               extra: String = "") -> String {
        """
        { "name": "github", "version": "1.0.0", "type": "script", "script": "main.js",
          "hosts": \(json(hosts)),
          "preferences": [
            { "name": "repos", "type": "text", "title": {"en": "Repositories", "zh": "仓库"},
              "placeholder": "owner/repo, owner/other", "default": "octo-org/octo-repo" },
            { "name": "token", "type": "password", "title": {"en": "Token (optional, for private repos)", "zh": "Token（可选，私有仓库用）"} } ],
          "completions": [
            { "name": "issues", "title": {"en": "GitHub issues", "zh": "GitHub issue"},
              "prefix": "#", "minChars": \(minChars), "compare": "prefix",
              "list": true, "refresh": "15m",
              "query": \(query), "queryMinChars": 2,
              "insert": \(insert) }\(extra) ] }
        """
    }

    /// Tickets of an issue tracker after "PROJ-" (a list only), `{match}` inserted.
    static let trackerManifest = """
        { "name": "tracker", "version": "1.0.0", "type": "script", "script": "main.js", "hosts": ["tracker.example.com"],
          "completions": [
            { "name": "tickets", "title": "Tickets", "prefix": "PROJ-", "list": true, "insert": { "default": "{match}" } } ] }
        """

    /// AWS accounts by their 12-digit ids: no prefix, so only an id typed in full shows its row.
    static let awsManifest = """
        { "name": "aws", "version": "1.0.0", "type": "script", "script": "main.js", "hosts": [],
          "completions": [
            { "name": "accounts", "title": "AWS accounts", "compare": "exact", "list": true, "refresh": "1h",
              "insert": { "default": "{match} ({alias})" } } ] }
        """

    static func json(_ strings: [String]) -> String {
        "[" + strings.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }

    /// Writes the plugin into `folder`/plugins/<name>/ and reads it back as the app does; nil: it wasn't usable.
    static func install(_ manifest: String, script: String = script, in folder: URL) throws -> InstalledPlugin? {
        let data = Data(manifest.utf8)
        let name = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["name"] as? String)
        let plugins = folder.appendingPathComponent("plugins", isDirectory: true)
        let directory = plugins.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("plugin.json"))
        try Data(script.utf8).write(to: directory.appendingPathComponent("main.js"))
        return PluginStore.load(from: plugins).plugins.first { $0.name == name }
    }

    /// What the user enables in Settings → Plugins: the source, with the plugin's hosts, whether it queries, its script's
    /// SHA-256 and the terms it is looked up by (prefix, queryMinChars, compare), as they are now.
    static func approval(_ plugin: InstalledPlugin, _ source: String) -> CompletionSourceApproval {
        let script = (plugin.scriptURL.flatMap { try? Data(contentsOf: $0) }) ?? Data()
        let sha = SHA256.hash(data: script).map { String(format: "%02x", $0) }.joined()
        let declared = plugin.manifest.completions.first { $0.name == source }
        return CompletionSourceApproval(plugin: plugin.name, source: source, hosts: plugin.manifest.hosts,
                                        query: declared?.query ?? false, scriptSHA256: sha,
                                        terms: declared.map(CompletionSourceApproval.Terms.init))
    }
}

// MARK: - Items

/// The items the tests' lists have: GitHub issues (generic titles), AWS accounts (AWS's documentation ids).
enum SuggestionsItems {
    static func issue(_ number: Int, _ title: String) -> CompletionItem {
        CompletionItem(match: "#\(number)", title: title, arg: "#\(number)",
                       variables: ["url": "https://github.com/octo-org/octo-repo/issues/\(number)"])
    }

    /// Issues whose numbers start with 7 or 8 (so that typing on after "#7" uses 6–9 and 0, never a row's number).
    static let issues = [
        issue(7001, "Crash when the panel opens at the screen's edge"),
        issue(7002, "Settings: a switch per app"),
        issue(7090, "Docs: how to write a plugin"),
        issue(7100, "Typing lag in long documents"),
        issue(789, "Dark mode colors"),
        issue(8001, "Release checklist"),
    ]

    static let accounts = [
        CompletionItem(match: "123456789012", title: "prod", variables: ["alias": "prod"]),
        CompletionItem(match: "111122223333", title: "staging", variables: ["alias": "staging"]),
        CompletionItem(match: "444455556666", title: "sandbox", variables: ["alias": "sandbox"]),
    ]

}

// MARK: - The world a field is in

/// Everything around the fields of a test: the settings, what the shell keeps (switches, picks, the coding packs
/// installed, Translate as You Type, the English words learned), the plugins installed, the runtime, the clock. Fields made
/// of the same world share it, as fields of one launch do.
final class SuggestionsWorld: @unchecked Sendable {
    var config: Config
    var switches = SuggestionsSettings()
    var translateAsYouType = false
    var picks: [SuggestionPick] = []
    private(set) var recordedPicks: [SuggestionPick] = []
    /// The coding language packs installed (the Code input's rows are its coding language's: `Config.codingLanguage`).
    var packs: [CodingLanguagePack] = []
    var plugins: [InstalledPlugin] = []
    var englishDictionary: EnglishDictionary?
    private(set) var learned: [String] = []
    var pointerUsed = false
    var secureInputAnywhere = false
    /// Where the lists are cached on disk (`SuggestionsServices.cacheFolder`; nil: nowhere).
    var cacheFolder: URL?
    let runtime = FakeCompletionRuntime()
    let clock = SuggestionsClock()
    /// What the core keeps for the fields of this launch: one for all of them.
    let store = SuggestionsStore()
    let preferenceValues = Locked<[String: [String: String]]>(initialState: [:])
    let statuses = Locked<[CompletionSourceStatus]>(initialState: [])
    let typedOnce = EnglishWords.TypedOnce()
    let folder: URL

    /// `input`: the language fields start in (the other one a tap of Shift away).
    init(input: Language = .english) {
        config = .default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.defaultInput = input
        config.claudeInBackground = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-\(UUID().uuidString)", isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    /// The spec's GitHub plugin installed, its issues listed (`items`) and `issues` enabled.
    @discardableResult
    func github(items: [CompletionItem] = SuggestionsItems.issues, fetchedAt: Date? = nil, enable: Bool = true,
                manifest: String = SuggestionsPlugins.githubManifest()) throws -> InstalledPlugin {
        let plugin = try #require(try SuggestionsPlugins.install(manifest, in: folder))
        plugins.removeAll { $0.name == plugin.name }
        plugins.append(plugin)
        runtime.list("issues", items: items, fetchedAt: fetchedAt)
        if enable { self.enable(plugin, "issues") }
        return plugin
    }

    /// The AWS accounts plugin installed, listed and enabled.
    @discardableResult
    func aws() throws -> InstalledPlugin {
        let plugin = try #require(try SuggestionsPlugins.install(SuggestionsPlugins.awsManifest, in: folder))
        plugins.append(plugin)
        runtime.list("accounts", items: SuggestionsItems.accounts)
        enable(plugin, "accounts")
        return plugin
    }

    func enable(_ plugin: InstalledPlugin, _ source: String) {
        switches.enabled.removeAll { $0.plugin == plugin.name && $0.source == source }
        switches.enabled.append(SuggestionsPlugins.approval(plugin, source))
    }

    func disable(_ plugin: String, _ source: String) {
        switches.enabled.removeAll { $0.plugin == plugin && $0.source == source }
    }

    var lastStatus: CompletionSourceStatus? { statuses.withLock { $0.last } }

    func services(engine: PinyinEngine) -> SessionServices {
        var services = SessionServices(loadSettings: { self.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.plugins = { _ in self.plugins }
        services.englishDictionary = { self.englishDictionary }
        services.learnEnglishWord = { self.learned.append($0) }
        services.englishTypedOnce = typedOnce
        services.pointerUsedWithin = { _ in self.pointerUsed }
        services.secureInputActive = { self.secureInputAnywhere }
        let (clock, preferences, statuses) = (clock, preferenceValues, statuses)
        services.uptime = { clock.now.timeIntervalSinceReferenceDate }
        var suggestions = SuggestionsServices()
        suggestions.store = store
        suggestions.runtime = runtime
        suggestions.settings = { self.switches }
        suggestions.now = { clock.now }
        suggestions.cacheFolder = cacheFolder
        suggestions.preferences = { plugin in preferences.withLock { $0[plugin.name] ?? [:] } }
        suggestions.codingPacks = { self.packs }
        suggestions.translateAsYouType = { self.translateAsYouType }
        suggestions.setTranslateAsYouType = { self.translateAsYouType = $0 }
        suggestions.loadPicks = { self.picks }
        suggestions.recordPick = { pick in
            self.recordedPicks.append(pick)
            self.picks.append(pick)
        }
        suggestions.reportStatus = { status in statuses.withLock { $0.append(status) } }
        services.suggestions = suggestions
        return services
    }

    /// This world with the Code input (decision 22) in coding language `language` ("python": `Config.codingLanguage`, as
    /// Settings → Input or the input menu sets it) and `packs` installed. Code is an input once `language`'s pack is
    /// among them.
    func addCode(_ language: String, packs: [CodingLanguagePack]) {
        config.codingLanguage = language
        self.packs = packs
    }

    /// A field of `app` that starts in Code: the app's starting input set to Code (Settings → Apps, the input menu's This
    /// App: `"inputLanguage": "code"` in its profile), as a user sets it; with `adjust`'s services. Other fields of `app`
    /// made after it start in Code too.
    func codeField(app: String = "com.example.editor", terminal: Bool = false,
                   _ adjust: (inout SessionServices) -> Void = { _ in }) -> SuggestionsField {
        config.changeProfile(for: app) { $0.startingInput = .code }
        return field(app: app, terminal: terminal, adjust)
    }

    /// A text field of `app` that has the focus (`terminal`: a terminal's, `passwordField`: a password field as Windows
    /// tells it), with `adjust`'s services.
    func field(app: String = "com.example.editor", terminal: Bool = false, passwordField: Bool = false,
               engine: PinyinEngine = PunctuatingEngine(), _ adjust: (inout SessionServices) -> Void = { _ in }) -> SuggestionsField {
        var services = services(engine: engine)
        adjust(&services)
        let host = FakeHost(services: services)
        host.app = app
        host.terminal = terminal
        if passwordField {
            host.send(.focus(FieldInfo(app: app, terminal: terminal, secure: true)))
        } else {
            host.focus()
        }
        return SuggestionsField(host: host, world: self)
    }
}

// MARK: - A field

/// The session's timers on the test's clock: when each was started (as the test saw it start), so that it fires once its
/// time has come on that clock.
final class SuggestionsTimers {
    var started: [TimerID: Date] = [:]
    /// The outputs looked through so far.
    var seen = 0
}

/// A text field as the user types in it: the app types the keys the session lets through (at the caret, the end), as the
/// app would; the session's outputs go in as FakeHost applies them. Its timers fire once due on the world's clock.
struct SuggestionsField {
    let host: FakeHost
    let world: SuggestionsWorld
    let timers = SuggestionsTimers()

    var document: String { host.document }

    /// A key: whether the session took it (false: the app got it, and typed it if it types).
    @discardableResult
    func press(_ key: KeyEvent) -> Bool {
        let handled = host.press(key)
        if !handled, key.key == .character || key.key == .space, let text = key.printableText {
            host.document += text
        }
        noteTimers()
        return handled
    }

    /// Picks the row at `index` as the keys do in an ordinary app (digits never do): Tab the first, else ↓ until that row
    /// is the one chosen (where none is chosen yet the first ↓ chooses the first row, spec decision 29; Code's rows are
    /// chosen from the start) and Return. Whether the session took every key.
    @discardableResult
    func pick(at index: Int) -> Bool {
        if index == 0 { return press(SuggestionKeys.tab) }
        var handled = true
        for _ in 0...(index + 1) where !(host.panel?.highlighted == index && host.panel?.highlightChosen == true) {
            handled = press(SuggestionKeys.down) && handled
        }
        return press(SuggestionKeys.enter) && handled
    }

    /// Types `text`, key by key (`SuggestionKeys.key`).
    func type(_ text: String) {
        for character in text { press(SuggestionKeys.key(character)) }
    }

    /// The candidate panel's rows now.
    var rows: [PanelModel.Row] { host.panel?.rows ?? [] }

    /// The rows shown, each as the longest of `candidates` it shows (as a whole token, in its text or its comment); "?"
    /// for a row that shows none of them.
    func shown(_ candidates: [String]) -> [String] {
        rows.map { row in
            let haystack = row.text + "\u{1}" + row.comment
            return candidates.sorted { $0.count > $1.count }.first { SuggestionsField.contains(haystack, token: $0) } ?? "?"
        }
    }

    /// The issues shown in the rows, in order: each row's first "#" and digits (a whole token, in its text or its
    /// comment); a row without one isn't counted.
    var issuesShown: [String] { rows.compactMap { SuggestionsField.firstIssue(in: $0.text + "\u{1}" + $0.comment) } }

    /// The first "#" followed by digits in `text`, as a whole token.
    static func firstIssue(in text: String) -> String? {
        let characters = Array(text)
        for (index, character) in characters.enumerated() where character == "#" {
            if index > 0, isTokenCharacter(characters[index - 1]) { continue }
            var end = index + 1
            while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
            guard end > index + 1, end == characters.count || !isTokenCharacter(characters[end]) else { continue }
            return String(characters[index..<end])
        }
        return nil
    }

    /// Whether `text` holds `token` with no token character right before or after it.
    static func contains(_ text: String, token: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before.map(isTokenCharacter) ?? false), !(after.map(isTokenCharacter) ?? false) { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "._-@#".contains(character)
    }

    /// The footer and what is on its right.
    var footer: String { (host.panel?.footer ?? "") + " " + (host.panel?.detail ?? "") }

    /// Hands the session its work's answers until `condition` holds (true) or `timeout` seconds have gone by (false). The
    /// world's clock goes on meanwhile as time does, and the timers due on it fire.
    @discardableResult
    func settle(timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last = Date()
        while true {
            fireTimers()
            if host.settle(timeout: 0.01, until: condition) { return true }
            let now = Date()
            world.clock.advance(now.timeIntervalSince(last))
            last = now
            if now >= deadline {
                fireTimers()
                return host.settle(timeout: 0, until: condition)
            }
        }
    }

    /// Hands the session what its work answers for a while (the clock going on): for what shouldn't come.
    func idle(_ seconds: TimeInterval = 0.3) { settle(timeout: seconds) { false } }

    /// Hands the session what its work answers for a while with the clock standing still: what it does at once, before
    /// any of its timers.
    func idleWithoutTime(_ seconds: TimeInterval = 0.2) { host.settle(timeout: seconds) { false } }

    /// Waits for the issues `expected` to be the rows (true), handing the session its work's answers meanwhile.
    @discardableResult
    func waitForIssues(_ expected: [String], timeout: TimeInterval = 3) -> Bool {
        settle(timeout: timeout) { issuesShown == expected }
    }

    /// Notes when the timers the session started since the last look started: now, on the world's clock.
    func noteTimers() {
        let outputs = host.outputs
        guard outputs.count > timers.seen else { return }
        for output in outputs[timers.seen...] {
            if case let .startTimer(id, _) = output { timers.started[id] = world.clock.now }
        }
        timers.seen = outputs.count
    }

    /// Fires the session's timers due on the world's clock (and those they start that are due too).
    func fireTimers() {
        for _ in 0..<10 {
            noteTimers()
            let now = world.clock.now
            let due = { (id: TimerID) -> Bool in
                (timers.started[id] ?? now).addingTimeInterval(host.timerDelays[id] ?? 0) <= now
            }
            guard host.timers.contains(where: due) else { return }
            host.fireTimers(where: due)
        }
        noteTimers()
    }

    /// `seconds` go by on the world's clock (the user pauses), the timers due then fire, and the session gets its work's
    /// answers for a moment.
    func pause(_ seconds: TimeInterval) {
        noteTimers()
        world.clock.advance(seconds)
        fireTimers()
        host.settle(timeout: 0.05) { false }
        fireTimers()
    }

    /// A long press of Shift on its own: down, held `seconds` on the session's clock (the timers due by then fired), then
    /// let go.
    func holdShift(for seconds: TimeInterval = 1.2) {
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: world.clock.timestamp))
        noteTimers()
        world.clock.advance(seconds)
        fireTimers()
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: world.clock.timestamp))
        noteTimers()
    }

    /// A tap of Shift (the next input: the input languages, then Code).
    func tapShift() {
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: world.clock.timestamp))
        noteTimers()
        world.clock.advance(0.1)
        host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: world.clock.timestamp))
        noteTimers()
    }
}

// MARK: - What a failed expectation shows of them

// A failed `#expect` shows the values in its expression, and what they hold: the field's text and rows, not the whole
// session and world behind them.

extension SuggestionsField: CustomReflectable {
    var customMirror: Mirror {
        Mirror(self, children: ["document": document, "marked": host.marked, "rows": rows.map { $0.text + " · " + $0.comment },
                                "footer": footer], displayStyle: .struct)
    }
}

extension SuggestionsWorld: CustomReflectable {
    var customMirror: Mirror {
        Mirror(self, children: ["codingLanguage": config.codingLanguage as Any, "packs": packs.map(\.language),
                                "translateAsYouType": translateAsYouType, "learned": learned,
                                "recordedPicks": recordedPicks.map(\.match), "now": clock.now], displayStyle: .class)
    }
}

extension FakeCompletionRuntime: CustomReflectable {
    var customMirror: Mirror {
        Mirror(self, children: ["calls": calls.map { $0.kind == .load ? "load(\($0.call.source.name))" : "query(\($0.text ?? ""))" },
                                "cancelled": cancelled], displayStyle: .class)
    }
}

extension FakeHost: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["document": document, "marked": marked, "rows": (panel?.rows ?? []).map(\.text)], displayStyle: .class)
    }
}

// MARK: - Keys

/// Keys as a US keyboard on the Mac sends them: their key codes, Shift where the character needs it.
enum SuggestionKeys {
    private static let codes: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
        "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22,
        "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E, ";": 0x29, "'": 0x27, ",": 0x2B, ".": 0x2F, "/": 0x2C, "`": 0x32,
    ]
    private static let shifted: [Character: Character] = [
        "#": "3", "@": "2", "!": "1", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", "_": "-",
        "+": "=", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`", "{": "[", "}": "]",
    ]

    static func key(_ character: Character) -> KeyEvent {
        switch character {
        case " ": return space
        case "\n": return enter
        case "\t": return tab
        case "＃": return KeyEvent(keyCode: 0x14, characters: "＃", charactersIgnoringModifiers: "＃", modifiers: .shift)
        default: break
        }
        let text = String(character)
        if let base = shifted[character], let code = codes[base] {
            return KeyEvent(keyCode: code, characters: text, charactersIgnoringModifiers: text, modifiers: .shift)
        }
        if character.isUppercase, let code = codes[Character(character.lowercased())] {
            return KeyEvent(keyCode: code, characters: text, charactersIgnoringModifiers: text, modifiers: .shift)
        }
        return KeyEvent(keyCode: codes[character] ?? 0, characters: text)
    }

    static let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    static let shiftTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t", modifiers: .shift)
    static let enter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")
    static let space = KeyEvent(keyCode: VirtualKey.space, characters: " ")
    static let escape = KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}")
    static let backspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")
    static let down = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
    static let up = KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}")
    static let left = KeyEvent(keyCode: 0x7B, characters: "\u{F702}")
    static let right = KeyEvent(keyCode: 0x7C, characters: "\u{F703}")
    static let home = KeyEvent(keyCode: 0x73, characters: "\u{F729}")
    static let end = KeyEvent(keyCode: 0x77, characters: "\u{F72B}")
    static let commandV = KeyEvent(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: .command)

    /// The digit key `n` (1–9).
    static func digit(_ n: Int) -> KeyEvent { key(Character(String(n))) }
}

// MARK: - Pinyin

/// Level one as librime (rime-ice) acts for these tests: letters compose pinyin, Space picks the first candidate, 1–5
/// pick one, ⏎ puts the letters in as typed; "#" (its keysym) ends the composition with the first candidate and goes in
/// after it, as "#" or, with `fullWidth`, as "＃"; with nothing composed it goes in on its own. In ASCII mode (English)
/// every key goes to the app.
final class PunctuatingEngine: PinyinEngine {
    var dictionary = ["nihao": ["你好", "拟好"], "wo": ["我", "窝"], "zai": ["在", "再"]]
    var fullWidth = false
    private var input = ""
    private var ascii = false
    private var pending: String?

    init(fullWidth: Bool = false) { self.fullWidth = fullWidth }

    private var words: [String] { input.isEmpty ? [] : dictionary[input] ?? [input] }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        if ascii { return false }
        let composing = !input.isEmpty
        switch keycode {
        case 0x61...0x7A:
            input.append(Character(Unicode.Scalar(UInt8(keycode))))
            return true
        case RimeKey.space where composing:
            emit(words[0])
            input = ""
            return true
        case 0x31...0x35 where composing:
            let index = Int(keycode - 0x31)
            if words.indices.contains(index) {
                emit(words[index])
                input = ""
            }
            return true
        case RimeKey.returnKey where composing:
            emit(input)
            input = ""
            return true
        case RimeKey.backSpace where composing:
            input.removeLast()
            return true
        case RimeKey.escape where composing:
            input = ""
            return true
        case 0x23:  // '#'
            if composing { emit(words[0]) }
            input = ""
            emit(fullWidth ? "＃" : "#")
            return true
        default:
            return composing
        }
    }

    private func emit(_ text: String) { pending = (pending ?? "") + text }

    func takeCommit() -> String? {
        defer { pending = nil }
        return pending
    }

    func snapshot() -> EngineSnapshot {
        EngineSnapshot(isComposing: !input.isEmpty, preedit: input, cursor: input.count,
                       candidates: words.enumerated().map { EngineCandidate(label: String($0.offset + 1), text: $0.element) },
                       highlighted: 0, isAsciiMode: ascii)
    }

    func selectCandidate(onPage index: Int) -> Bool {
        guard words.indices.contains(index) else { return false }
        emit(words[index])
        input = ""
        return true
    }

    func commitComposition() -> String? {
        guard !input.isEmpty else { return nil }
        emit(words[0])
        input = ""
        return takeCommit()
    }

    var rawInput: String { input }
    func clearComposition() { input = "" }
    func setAsciiMode(_ on: Bool) { ascii = on }
}

// MARK: - Apps

/// App ids the tests type in, by the class the spec puts them in (spec 1.4, 6.11): the Mac's bundle ids, Windows' app ids
/// ("win:" and the program's file name).
enum SuggestionsApps {
    /// Ordinary.
    static let editor = "com.example.editor"
    /// Chat: Slack, WeChat, and a Chromium app (Chrome).
    static let slack = "com.tinyspeck.slackmacgap"
    static let weChat = "com.tencent.xinWeChat"
    static let chrome = "com.google.Chrome"
    /// No rows: a remote desktop, a virtual machine, an SSH client.
    static let remoteDesktop = "com.microsoft.rdc.macos"
    static let virtualMachine = "com.parallels.desktop.console"
    static let sshClient = "com.termius-dmg.mac"
    /// A code editor (VS Code).
    static let vsCode = "com.microsoft.VSCode"

    /// Spec 6.11's classes. Chat: the chat apps' list (AppTone's: Slack, WeChat, Teams, Discord), the Chromium browsers
    /// (Chrome, Edge, Brave, Arc, Vivaldi, Opera), and on Windows by program.
    static let chat = [slack, weChat, "com.microsoft.teams2", "com.hnc.Discord", chrome, "com.microsoft.edgemac",
                       "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
                       "win:chrome.exe", "win:msedge.exe", "win:slack.exe"]
    /// Code editors: Xcode, VS Code, Cursor, Windsurf, Zed, Nova, Sublime Text, JetBrains' (any of com.jetbrains.), and
    /// on Windows VS Code by program. (Terminals are the field's: `FieldInfo.terminal`.)
    static let codeEditors = ["com.apple.dt.Xcode", vsCode, "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
                              "dev.zed.Zed", "com.panic.Nova", "com.sublimetext.4", "com.jetbrains.intellij",
                              "com.jetbrains.pycharm", "win:Code.exe"]
    /// No rows: the launchers (Raycast, Alfred, Spotlight, LaunchBar), and the remote desktops, virtual machines and SSH
    /// clients (Windows' Remote Desktop Connection too).
    static let noRows = ["com.raycast.macos", "com.runningwithcrayons.Alfred", "com.apple.Spotlight", "at.obdev.LaunchBar",
                         remoteDesktop, virtualMachine, sshClient, "win:mstsc.exe"]
    /// Everything else: ordinary (Mail and Notes too; Windows' Notepad).
    static let ordinary = [editor, "com.apple.TextEdit", "com.apple.mail", "com.apple.Notes", "win:notepad.exe"]
}
