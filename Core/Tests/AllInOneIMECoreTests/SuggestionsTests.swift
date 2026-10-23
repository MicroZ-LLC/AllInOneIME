import CryptoKit
import Foundation
import Testing
@testable import AllInOneIMECore

/// The pieces of Suggestions (Suggestions/) on their own: what a script returns, read; templates; a snippet's body; the
/// rows picked first; the app classes; the declaration written back; coding packs from their library; the GitHub
/// plugin (Plugins/github) and the completion run of a script, on both engines. The session's side is in the acceptance
/// tests (Acceptance/Suggestions*).
struct SuggestionsTests {
    // MARK: - What a script returns

    @Test func anOutputIsReadItemByItem() throws {
        let data = Data(#"""
            { "fetchedAt": 1790000000, "items": [
              { "match": "#1", "title": "One\u0007", "arg": "#1 one", "variables": { "url": "https://x.example/1", "n": 7 } },
              { "match": "#1", "title": "again" },
              { "match": "#2 x" },
              { "match": "＃3" },
              { "match": "PROJ-12", "subtitle": "‮open" } ] }
            """#.utf8)
        let list = try CompletionOutput.read(data).get()
        #expect(list.fetchedAt == 1_790_000_000)
        // The same match again, a space, a full-width mark (not one of the five): dropped, each on its own.
        #expect(list.items.map(\.match) == ["#1", "PROJ-12"], "\(list.items)")
        #expect(list.items[0].title == "One" && list.items[0].variables == ["url": "https://x.example/1"])
        #expect(list.items[1].subtitle == "open")
        #expect(try CompletionOutput.read(data, digitsOnly: true).get().items.isEmpty)
        #expect(CompletionOutput.read(Data("[]".utf8)) == .failure(.notAList))
        #expect(CompletionOutput.read(Data(#"{"items": {}}"#.utf8)) == .failure(.notAList))
    }

    @Test func aMatchIsLettersDigitsAndFiveMarks() {
        for good in ["#12", "PROJ-1201", "a.b_c-d@e#f", "é1", String(repeating: "x", count: 64)] {
            #expect(CompletionOutput.isMatch(good), "\(good)")
        }
        for bad in ["", "#1 2", "a/b", "a\"", "#6006😀", String(repeating: "x", count: 65)] {
            #expect(!CompletionOutput.isMatch(bad), "\(bad)")
        }
    }

    // MARK: - Templates and tokens

    @Test func templatesFillWithTheFirstWhoseVariablesAllExist() {
        let item = CompletionItem(match: "#7", arg: "#7 (seven)", variables: ["url": "https://x.example/7"])
        #expect(CompletionTemplate.fill(["{arg} {url}"], with: item) == "#7 (seven) https://x.example/7")
        #expect(CompletionTemplate.fill(["{match} {alias}", "{match}"], with: item) == "#7")
        #expect(CompletionTemplate.fill(["{alias}"], with: item) == nil)
        #expect(CompletionTemplate.parts("{a}b{c_1}") == [.variable("a"), .text("b"), .variable("c_1")])
        for bad in ["{", "}", "{}", "{a b}", "a}"] { #expect(CompletionTemplate.parts(bad) == nil, "\(bad)") }
    }

    @Test func fullWidthFormsAreTyped() {
        #expect(SuggestionsToken.normalized("＃１２ａ") == "#12a")
        #expect(SuggestionsToken.isTokenCharacter("#") && SuggestionsToken.isTokenCharacter("é") && !SuggestionsToken.isTokenCharacter("你"))
        #expect(SuggestionsToken.identifier(endingAt: "self.compute_to") == "compute_to")
    }

    @Test func aSourceAppliesByItsPrefixAndMinChars() {
        let issues = CompletionSource(name: "issues", title: LocalizedText(en: "Issues"), prefix: "#", minChars: 2)
        #expect(PluginRows.afterPrefix("#1", issues) == nil)
        #expect(PluginRows.afterPrefix("＃12", issues) == "12")
        let tickets = CompletionSource(name: "tickets", title: LocalizedText(en: "Tickets"), prefix: "PROJ-")
        #expect(PluginRows.afterPrefix("proj-7", tickets) == "7")
        let accounts = CompletionSource(name: "accounts", title: LocalizedText(en: "Accounts"))
        #expect(PluginRows.afterPrefix("12", accounts) == nil && PluginRows.afterPrefix("123", accounts) == "123")
        #expect(PluginRows.afterPrefix("12a", accounts) == nil)
    }

    /// The items a token's start is looked for in (`CompletionItems`, their bytes) answer it as `hasPrefix` does, letters
    /// with marks too; compared whole, as the whole.
    @Test func theItemsAnswerATokenAsItsStart() {
        let matches = ["#12", "#1234", "PROJ-12", "proj-120", "#é1", "#e1", "#ÉTÉ", "Ai", "AİX", "#1", "#12"]
        let items = CompletionItems(matches.map { CompletionItem(match: $0) })
        #expect(items.positions["#12"] == 0 && items.positions["proj-12"] == 2, "the first of each, in small letters")
        let prefix = CompletionSource(name: "s", title: LocalizedText(en: "S"), prefix: "#")
        let exact = CompletionSource(name: "s", title: LocalizedText(en: "S"), prefix: "#", compare: .exact)
        for source in [prefix, exact] {
            for token in ["#", "#1", "#12", "proj-12", "#é", "#e", "#ét", "ai", "aİ".lowercased(), "x", ""] {
                var found: [Int] = []
                var start = 0
                while let index = items.next(answering: token, source, from: start) {
                    found.append(index)
                    start = index + 1
                }
                let expected = items.lowered.indices.filter { PluginRows.matches(items.lowered[$0], token, source) }
                #expect(found == expected, "\(source.compare) \(token): \(found.map { matches[$0] })")
                #expect(PluginRows.count(items, answering: token, source, upTo: 2) == min(expected.count, 2), "\(token)")
            }
        }
    }

    // MARK: - Coding

    @Test func aSnippetsBodyGoesInAsText() {
        #expect(CodingRows.expand("def ${1:name}(${2}):\n    $0") == ("def name():\n    ", 0))
        #expect(CodingRows.expand("print($0)") == ("print()", 1))
        #expect(CodingRows.expand("for (const ${1:x} of $2) {\n  $0\n}") == ("for (const x of ) {\n  \n}", 2))
        #expect(CodingRows.expand("cost: $5") == ("cost: ", 0))
        #expect(CodingRows.expand("a $ b ${x}") == ("a $ b ${x}", 0))
    }

    @Test func theFieldsWordsByFrequencyThenNearness() {
        let words = CodingRows.words(FieldText(before: "alpha_one beta_two alpha_one gamma_x\nbeta_t", after: "wo delta_four beta_two"))
        #expect(Array(words.prefix(2)) == ["beta_two", "alpha_one"], "\(words)")
        #expect(!words.contains("beta_two".prefix(6).description) && words.contains("delta_four") && words.contains("gamma_x"))
    }

    // MARK: - Rows picked before

    @Test func frecencyCountsHowOftenAndHowRecently() {
        let (a, b, c) = (SuggestionPick(plugin: "p", source: "s", match: "a"), SuggestionPick(plugin: "p", source: "s", match: "b"),
                         SuggestionPick(plugin: "p", source: "s", match: "c"))
        let rows = ["a", "b", "c", "d"].map {
            SuggestionRow(text: $0, comment: "", insertion: $0, completion: $0, typed: "", pick: SuggestionPick(plugin: "p", source: "s", match: $0),
                          source: "")
        }
        #expect(Frecency.ordered(rows, picks: [a, b]).map(\.text) == ["b", "a", "c", "d"])
        #expect(Frecency.ordered(rows, picks: [a, a, a, b]).map(\.text) == ["a", "b", "c", "d"], "three picks outweigh one later")
        #expect(Frecency.ordered(rows, picks: [c]).map(\.text) == ["c", "a", "b", "d"])
        #expect(Frecency.ordered(rows, picks: []).map(\.text) == ["a", "b", "c", "d"])
    }

    // MARK: - App classes

    @Test func appsHaveTheirClass() {
        #expect(SuggestionsAppClass(app: "com.google.Chrome.canary", terminal: false) == .chat)
        #expect(SuggestionsAppClass(app: "com.google.chromeX", terminal: false) == .ordinary)
        #expect(SuggestionsAppClass(app: "com.jetbrains.goland", terminal: false) == .codeEditor)
        #expect(SuggestionsAppClass(app: "com.example.editor", terminal: true) == .codeEditor)
        #expect(SuggestionsAppClass(app: "win:Code.exe", terminal: false) == .codeEditor)
        #expect(SuggestionsAppClass(app: "com.apple.ScreenSharing", terminal: false) == .none)
        #expect(SuggestionsAppClass(app: nil, terminal: false) == .ordinary)
    }

    // MARK: - The declaration, written back

    @Test func aManifestWithCompletionsReadsBackAsWritten() throws {
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: Self.github.appendingPathComponent("plugin.json")))
        let again = try JSONDecoder().decode(PluginManifest.self, from: JSONEncoder().encode(manifest))
        #expect(again == manifest)
        #expect(CompletionDeclaration.duration("90m") == 5400 && CompletionDeclaration.durationText(5400) == "90m")
    }

    /// A source without a prefix may not look up what is typed (v1): any number typed in any field (a card's, in a
    /// browser) would go to the plugin's hosts as it grows. Refused, saying why; its list alone, or a lookup after a
    /// prefix, is fine.
    @Test func aSourceWithoutAPrefixCantLookUpWhatIsTyped() throws {
        func read(_ entry: String) throws -> PluginManifest {
            try JSONDecoder().decode(PluginManifest.self, from: Data(#"""
                { "name": "aws", "version": "1.0.0", "type": "script", "script": "main.js", "hosts": ["api.example.com"],
                  "completions": [\#(entry)] }
                """#.utf8))
        }
        let querying = try read(#"{ "name": "accounts", "title": "Accounts", "compare": "exact", "list": true, "query": true }"#)
        #expect(querying.completions.isEmpty && querying.refusedCompletions.map(\.name) == ["accounts"], "\(querying.completions)")
        #expect(querying.refusedCompletions.first?.reason.contains("prefix") == true, "\(querying.refusedCompletions)")
        let listing = try read(#"{ "name": "accounts", "title": "Accounts", "compare": "exact", "list": true }"#)
        #expect(listing.completions.map(\.name) == ["accounts"] && listing.refusedCompletions.isEmpty)
        let prefixed = try read(#"{ "name": "accounts", "title": "Accounts", "prefix": "acct-", "query": true }"#)
        #expect(prefixed.completions.first?.query == true && prefixed.refusedCompletions.isEmpty)
    }

    @Test func approvalsHoldUntilThePluginChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-approval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.github, to: folder.appendingPathComponent("github"))
        let plugin = try #require(PluginStore.load(from: folder).plugins.first)
        let source = try #require(plugin.manifest.completions.first)
        var config = Config.default
        config.setCompletionSource(source, of: plugin, enabled: true)
        let approval = try #require(config.approval(of: source, in: plugin))
        #expect(approval.holds(for: source, of: plugin) && approval.query && approval.hosts == ["api.github.com"])
        #expect(config.suggestionsSettings().enabled == [approval])
        try Data("function load(ctx) { return { items: [] }; }".utf8).write(to: folder.appendingPathComponent("github/main.js"))
        #expect(!approval.holds(for: source, of: plugin), "the script changed")
        config.setCompletionSource(source, of: plugin, enabled: false)
        #expect(config.completionSources.isEmpty)
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.completionSources.isEmpty && decoded.suggestions == nil)
    }

    @Test func theNewKeysRoundTrip() throws {
        var config = Config.default
        config.suggestions = false
        config.pluginPreferences = ["github": ["repos": "octo-org/octo-repo"]]
        config.completionSources = [CompletionSourceApproval(plugin: "github", source: "issues", hosts: ["api.github.com"], query: true,
                                                             scriptSHA256: String(repeating: "a", count: 64))]
        config.appProfiles = ["com.example.app": AppProfile(suggestions: false)]
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.suggestions == false && decoded.pluginPreferences == config.pluginPreferences)
        #expect(decoded.completionSources == config.completionSources && decoded.profile(for: "com.example.app")?.suggestions == false)
        #expect(decoded.suggestionsSettings().apps == ["com.example.app": false] && decoded.suggestionsSettings().master == false)
    }

    // MARK: - The GitHub plugin (Plugins/github)

    static let github = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Plugins/github")

    static func issuesJSON(_ issues: [(Int, String)]) -> String {
        "[" + issues.map { number, title in
            #"{"number":\#(number),"title":"\#(title)","state":"open","updated_at":"2026-10-20T08:00:00Z","html_url":"https://github.com/octo-org/octo-repo/issues/\#(number)"}"#
        }.joined(separator: ",") + "]"
    }

    @Test(.enabled(if: Available.javaScript), arguments: TestEngine.all)
    func theGitHubPluginLoadsAndQueries(_ engine: TestEngine) throws {
        let script = try String(contentsOf: Self.github.appendingPathComponent("main.js"), encoding: .utf8)
        let base = "https://api.github.com/repos/octo-org/octo-repo/issues"
        let fetcher = StubFetcher([
            base + "?state=all&sort=updated&per_page=100": (200, Self.issuesJSON([(1234, "Fix login"), (12, "Panel position")])),
            base + "/12": (200, String(Self.issuesJSON([(12, "Panel position")]).dropFirst().dropLast())),
        ])
        let context = CompletionContext(source: "issues", preferences: ["repos": "octo-org/octo-repo", "token": "t0ken"], language: .english)
        let loaded = try PluginScript.evaluateCompletion(source: script, function: .load, context: context, fetcher: fetcher, engine: engine.engine)
        let list = try CompletionOutput.read(Data(loaded.utf8)).get()
        #expect(list.items.map(\.match) == ["#1234", "#12"] && list.fetchedAt != nil, "\(engine.name): \(loaded)")
        #expect(list.items.first?.variables?["url"] == "https://github.com/octo-org/octo-repo/issues/1234")
        #expect(fetcher.asked.first?.headers["Authorization"] == "Bearer t0ken")
        let queried = try PluginScript.evaluateCompletion(source: script, function: .query, text: "12", context: context, fetcher: fetcher,
                                                          engine: engine.engine)
        #expect(try CompletionOutput.read(Data(queried.utf8)).get().items.map(\.match) == ["#12"], "\(engine.name): \(queried)")
        // Not a host it lists: refused by fetch, the load fails.
        #expect(throws: PluginScriptError.self) {
            try PluginScript.evaluateCompletion(source: script, function: .load, context: context, fetcher: StubFetcher(), engine: engine.engine)
        }
        // Words after "#" ("#general" in a chat) could never be a row ("#1234" is a match): nothing asked, nothing sent.
        let asked = fetcher.asked.count
        for words in ["general", "fix", "12a"] {
            let none = try PluginScript.evaluateCompletion(source: script, function: .query, text: words, context: context, fetcher: fetcher,
                                                           engine: engine.engine)
            #expect(try CompletionOutput.read(Data(none.utf8)).get().items.isEmpty, "\(engine.name) \(words): \(none)")
        }
        #expect(fetcher.asked.count == asked, "\(engine.name): \(fetcher.asked.dropFirst(asked).map(\.url))")
    }

    /// `@github <words>` searches the titles of the repositories the user set, with their token, as `load` and `query`
    /// do (`run` gets the plugin's preferences in its context too); `@github 12` looks that issue up.
    @Test(.enabled(if: Available.javaScript), arguments: TestEngine.all)
    func theGitHubCommandSearchesTheRepositoriesSet(_ engine: TestEngine) throws {
        let script = try String(contentsOf: Self.github.appendingPathComponent("main.js"), encoding: .utf8)
        let search = "https://api.github.com/search/issues?per_page=10&q=repo%3Aocto-org%2Focto-repo%20in%3Atitle%20login"
        let fetcher = StubFetcher([
            search: (200, #"{"items": [{"number": 7, "title": "Login fails", "state": "open", "repository_url": "https://api.github.com/repos/octo-org/octo-repo", "html_url": "https://github.com/octo-org/octo-repo/issues/7"}]}"#),
            "https://api.github.com/repos/octo-org/octo-repo/issues/12": (200, String(Self.issuesJSON([(12, "Panel position")]).dropFirst().dropLast())),
        ])
        let preferences = ["repos": "octo-org/octo-repo", "token": "t0ken"]
        let found = try PluginScript.evaluate(source: script, input: "login", language: .english, preferences: preferences, fetcher: fetcher,
                                              engine: engine.engine)
        #expect(found == "#7 Login fails  https://github.com/octo-org/octo-repo/issues/7", "\(engine.name): \(found)")
        #expect(fetcher.asked.first?.headers["Authorization"] == "Bearer t0ken", "\(engine.name): \(fetcher.asked)")
        let issue = try PluginScript.evaluate(source: script, input: "#12", language: .english, preferences: preferences, fetcher: fetcher,
                                              engine: engine.engine)
        #expect(issue == "#12 Panel position  https://github.com/octo-org/octo-repo/issues/12", "\(engine.name): \(issue)")
    }

    /// A script plugin with preferences is told so after its folder (`--with-preferences`) and gets the text and its
    /// preferences as JSON on standard input, never on the command line; one without is run as before (the text alone).
    @Test func aPluginWithPreferencesGetsThemOnStandardInput() throws {
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: Self.github.appendingPathComponent("plugin.json")))
        let github = InstalledPlugin(manifest: manifest, directory: Self.github, isLocal: true)
        let command = PluginRunner.command(for: github, executable: "/Apps/AllInOneIME", language: .english)
        #expect(command.argv == ["/Apps/AllInOneIME", "--run-plugin", Self.github.path, "--language", "en", "--with-preferences"])
        let input = PluginRunner.standardInput("login", preferences: ["repos": "octo-org/octo-repo", "token": "t0ken"])
        #expect(try JSONDecoder().decode(PluginHost.RunInput.self, from: Data(input.utf8))
                == PluginHost.RunInput(input: "login", preferences: ["repos": "octo-org/octo-repo", "token": "t0ken"]))
        #expect(PluginHost.invocation([Self.github.path, "--language", "en", "--with-preferences"])
                == PluginHost.Invocation(directory: Self.github.path, language: .english, preferences: true))
        #expect(PluginHost.invocation([Self.github.path, "--language", "en"])?.preferences == false)
        // What a script gets: those set, else the manifest's defaults; only those it declares.
        #expect(PluginPreference.values(for: github, set: ["token": "t0ken", "other": "x"])
                == ["repos": "MicroZ-LLC/AllInOneIME", "token": "t0ken"])
        #expect(PluginPreference.values(for: github, set: ["repos": "", "token": ""]) == ["repos": "MicroZ-LLC/AllInOneIME"])
    }

    #if os(macOS)  // Package.swift leaves PlugLangCLI's file out elsewhere (it runs the app as a child process)
    /// The app's own child process (`--run-plugin <folder> --with-preferences`) reads them back: `run(input, ctx)` gets
    /// `ctx.preferences`, the defaults filled in.
    @Test(.enabled(if: PlugLangCLI.available, "build the app first: swift build at the repo root, or set ALLINONEIME_TEST_BINARY"))
    func theChildProcessGivesRunThePreferences() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-run-\(UUID().uuidString)/probe", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"""
            { "name": "probe", "version": "1.0.0", "type": "script", "script": "main.js",
              "preferences": [ { "name": "repos", "type": "text", "title": "Repositories", "default": "octo-org/octo-repo" },
                               { "name": "token", "type": "password", "title": "Token" } ] }
            """#.utf8).write(to: folder.appendingPathComponent("plugin.json"))
        try Data("""
            function run(input, ctx) {
              const p = ctx.preferences;
              return [input, ctx.language].concat(Object.keys(p).sort().map(k => k + "=" + p[k])).join(" ");
            }
            """.utf8).write(to: folder.appendingPathComponent("main.js"))
        let plugin = try #require(PluginStore.load(from: folder.deletingLastPathComponent()).plugins.first)
        var text = ""
        for try await update in PluginRunner.run(plugin, input: "hi", language: .english, preferences: { ["token": "t0ken"] },
                                                 executable: try #require(PlugLangCLI.binary)) where update.isFinal {
            text = update.result.versions.first?.text ?? ""
        }
        #expect(text == "hi en repos=octo-org/octo-repo token=t0ken", "\(text)")
    }
    #endif

    @Test(.enabled(if: Available.javaScript), arguments: TestEngine.all)
    func aScriptWithoutTheFunctionFails(_ engine: TestEngine) {
        let context = CompletionContext(source: "s", preferences: [:], language: .chinese)
        #expect(throws: PluginScriptError.failed("The plugin has no query(text, ctx) function")) {
            try PluginScript.evaluateCompletion(source: "function load(ctx) { return { items: [] }; }", function: .query, context: context,
                                                fetcher: StubFetcher(), engine: engine.engine)
        }
        let echoed = try? PluginScript.evaluateCompletion(source: "function load(ctx) { return { items: [], ctx: ctx }; }", function: .load,
                                                          context: context, fetcher: StubFetcher(), engine: engine.engine)
        #expect(echoed?.contains(#""language":"zh""#) == true && echoed?.contains(#""source":"s""#) == true, "\(echoed ?? "-")")
    }

    @Test func theCompletionsInputCarriesTheContext() throws {
        let input = PluginHost.CompletionInput(CompletionContext(source: "issues", preferences: ["k": "v"], language: .english), text: "12")
        let again = try JSONDecoder().decode(PluginHost.CompletionInput.self, from: JSONEncoder().encode(input))
        #expect(again == input && again.text == "12")
        #expect(PluginHost.completionFunction(["/p", "--completion", "query"]) == .query)
        #expect(PluginHost.completionFunction(["/p", "--language", "en"]) == nil)
    }

    /// The child process reads plugin.json again, which may have changed since the source was enabled (the session's
    /// plugins may be a little older): it may fetch only from the hosts the user approved (on standard input) that
    /// plugin.json still lists; none approved, none.
    @Test(.enabled(if: Available.javaScript)) func theChildProcessFetchesOnlyFromApprovedHosts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-hosts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"""
            { "name": "tracker", "version": "1.1.0", "type": "script", "script": "main.js",
              "hosts": ["api.github.com", "collector.example.com", "API.EXAMPLE.ORG"],
              "completions": [ { "name": "issues", "title": "Issues", "prefix": "#", "list": true } ] }
            """#.utf8).write(to: folder.appendingPathComponent("plugin.json"))
        try Data(#"function load(ctx) { fetch("https://api.github.com/x"); return { items: [] }; }"#.utf8)
            .write(to: folder.appendingPathComponent("main.js"))
        let context = CompletionContext(source: "issues", preferences: [:], language: .english)
        for (approved, allowed) in [(["api.github.com", "api.example.org"], ["api.github.com", "API.EXAMPLE.ORG"]), ([], [])] {
            let given = Locked<[String]?>(initialState: nil)
            let input = try JSONEncoder().encode(PluginHost.CompletionInput(context, text: nil, hosts: approved))
            let result = PluginHost.completion(directory: folder.path, function: .load, input: input) { hosts in
                given.withLock { $0 = hosts }
                return StubFetcher(["https://api.github.com/x": (200, "{}")])
            }
            #expect(given.withLock { $0 } == allowed, "approved \(approved): \(String(describing: given.withLock { $0 }))")
            #expect(result == .success(#"{"items":[]}"#), "\(result)")
        }
        #expect(PluginHost.completion(directory: folder.path, function: .load, input: Data("{}".utf8)) { _ in StubFetcher() }
                == .failure("No completion context on standard input"))
    }

    // MARK: - The list cached on disk

    /// A list is written to its cache file in one step, the file new and the user's only from the start, by way of a
    /// file outside the cache folder (beside it, on the same volume): what lists the folder meanwhile finds only the
    /// sources' files, never one half written.
    @Test func aCachedListIsWrittenFromOutsideItsFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("suggestions", isDirectory: true)
        let key = CompletionSourceKey(plugin: "github", source: "issues")
        var source = SuggestionsStore.Source()
        source.list = CompletionItems((1...2000).map { CompletionItem(match: "#\($0)", title: "Issue \($0)") })
        source.loadedAt = Date()
        let writing = Locked(initialState: true)
        let seen = Locked<Set<String>>(initialState: [])
        let lister = Thread {
            while writing.withLock({ $0 }) {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
                seen.withLock { $0.formUnion(names) }
            }
        }
        lister.start()
        for _ in 0..<40 { SuggestionsStore.write(source, of: key, in: cache) }
        SuggestionsStore.disk.sync {}
        writing.withLock { $0 = false }
        let others = seen.withLock { $0 }.subtracting([key.fileName])
        #expect(others.isEmpty, "\(others.count) other files, such as \(others.first ?? "")")
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path) == [key.fileName])
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.appendingPathComponent(key.fileName).path)[.posixPermissions]
        #expect(permissions as? Int == 0o600)
    }

    // MARK: - The settings document

    /// Windows' settings document: under the GitHub plugin its source's switch (saying what it sends where) and its
    /// preferences; the switch enables it as it is now, the text preference is kept in the config; Coding Languages has
    /// Suggestions' switch and no packs.
    @Test func thePluginsCompletionsAreInTheSettingsDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugins = folder.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.github, to: plugins.appendingPathComponent("github"))
        let url = folder.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: PluginLibrary(directory: plugins))
        let source = try #require(service.document().field("plugins.completion.github.issues"))
        #expect(source.kind == .toggle && source.value == .bool(false) && source.help?.contains("api.github.com") == true, "\(source)")
        #expect(service.document().field("plugins.preference.github.repos")?.kind == .text)
        #expect(service.document().field("plugins.preference.github.token")?.kind == .secret)
        #expect((try? service.set("plugins.completion.github.issues", to: .bool(true)).get()) != nil)
        let enabled = try Config.load(from: url).completionSources
        #expect(enabled.map(\.source) == ["issues"] && enabled.first?.query == true, "\(enabled)")
        #expect(service.document().field("plugins.completion.github.issues")?.value == .bool(true))
        #expect((try? service.set("plugins.preference.github.repos", to: .string("octo-org/octo-repo")).get()) != nil)
        #expect(try Config.load(from: url).pluginPreferences == ["github": ["repos": "octo-org/octo-repo"]])
        #expect(service.document().field("suggestions")?.value == .bool(true))
        #expect(service.document().field("codingLanguages.installed")?.items?.isEmpty == true)
    }

    /// Removing a plugin (Settings → Plugins, the Mac's or the settings document's) forgets what was enabled of it, and
    /// saves that: installed again, its sources are off until enabled again. Other plugins' stay.
    @Test func uninstallingAPluginForgetsWhatWasEnabledOfIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugins = folder.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.github, to: plugins.appendingPathComponent("github"))
        let url = folder.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: url)
        let store = SettingsStore(configURL: url)
        let plugin = try #require(PluginStore.load(from: plugins).plugins.first)
        store.config.setCompletionSource(try #require(plugin.manifest.completions.first), of: plugin, enabled: true)
        let other = CompletionSourceApproval(plugin: "aws", source: "accounts", hosts: [], query: false, scriptSHA256: String(repeating: "b", count: 64))
        store.config.completionSources.append(other)
        store.save()
        #expect(try Config.load(from: url).completionSources.count == 2)
        #expect(store.uninstall(plugin) == nil)
        #expect(store.config.completionSources == [other], "\(store.config.completionSources)")
        #expect(try Config.load(from: url).completionSources == [other], "saved")
        #expect(PluginStore.load(from: plugins).plugins.isEmpty)
    }

    // MARK: - Coding packs from the library

    static func pack(_ language: String = "python", version: String = "1.0.0") -> Data {
        Data(#"{ "language": "\#(language)", "title": "Python", "version": "\#(version)", "keywords": ["def", "class"], "snippets": [ { "trigger": "def", "body": "def ${1:f}():\n    $0" } ] }"#.utf8)
    }

    @Test func codingPacksInstallOnceVerified() async throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        let store = CodingPackStore(directory: lib.root.appendingPathComponent("coding", isDirectory: true))
        let library = CodingPackLibrary(baseURL: URL(string: lib.base)!, publicKey: lib.key.publicKey.rawRepresentation,
                                        configuration: configuration, appVersion: "0.6.7", store: store)
        let data = Self.pack()
        let name = "python-\(UUID().uuidString.prefix(6)).json"
        LibraryStubProtocol.serve(lib.base + "assets/" + name, data)
        let entry: [String: Any] = ["language": "python", "title": "Python", "version": "1.0.0", "url": "assets/" + name,
                                    "sha256": PluginLibrary.sha256(data), "size": data.count]
        let later: [String: Any] = ["language": "python", "title": "Python", "version": "2.0.0", "minAppVersion": "9.0.0", "url": "assets/x",
                                    "sha256": PluginLibrary.sha256(data), "size": data.count]
        let index = try JSONSerialization.data(withJSONObject: ["schema": 1, "packs": [entry, later]], options: [.sortedKeys])
        LibraryStubProtocol.serve(lib.base + "coding-packs.json", index)
        LibraryStubProtocol.serve(lib.base + "coding-packs.json.sig", Data(try lib.key.signature(for: index).base64EncodedString().utf8))
        let offered = library.offered(in: try await library.fetchIndex())
        #expect(offered.map(\.version) == ["1.0.0"], "the newest this app can use")
        let pack = try await library.install(try #require(offered.first))
        #expect(pack.language == "python" && store.installed().map(\.language) == ["python"])
        try store.remove("python")
        #expect(store.installed().isEmpty)

        // A pack that isn't what the index says: refused, nothing kept.
        var wrong = try #require(offered.first)
        wrong.sha256 = String(repeating: "0", count: 64)
        await #expect(throws: LanguagePackError.hashMismatch) { try await library.install(wrong) }
        #expect(throws: LanguagePackError.self) { try store.keep(Self.pack("ruby"), language: "python") }
        #expect(store.installed().isEmpty)
        // A signature by another key: the index isn't read.
        LibraryStubProtocol.serve(lib.base + "coding-packs.json.sig",
                                  Data(try Curve25519.Signing.PrivateKey().signature(for: index).base64EncodedString().utf8))
        await #expect(throws: LanguagePackError.badSignature) { try await library.fetchIndex() }
    }
}
