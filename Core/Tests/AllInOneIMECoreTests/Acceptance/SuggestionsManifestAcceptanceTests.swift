import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, spec 1.1 and 2: a script plugin's `completions` and `preferences` in its plugin.json, as the app reads
/// them (`PluginManifest`, `PluginStore`): the spec's example, the defaults (without a prefix, `exact`: spec 6.9), what
/// is refused: a completion entry on its own, with its reason, the rest of the plugin loaded (spec 6.8, 6.9); a coding
/// language pack's format (`CodingLanguagePack`). The fixtures: Fixtures/Suggestions/plugins/ and packs/.
struct SuggestionsManifestAcceptanceTests {
    /// A script plugin's manifest with `completions` (and `preferences`, `extra` keys) as given.
    static func manifest(completions: String, preferences: String? = nil, type: String = "script", extra: String = "") -> String {
        """
        { "name": "example", "version": "1.0.0", "type": "\(type)", "script": "main.js", "prompt": "Rewrite it",
          "url": "https://www.example.com/search?q={input}", "hosts": ["api.github.com"]\(extra)\(preferences.map { ", \"preferences\": " + $0 } ?? ""),
          "completions": \(completions) }
        """
    }

    /// Why the app refuses `json` as a plugin.json: unreadable, or the manifest's problem; nil: it doesn't.
    static func refusal(_ json: String) -> String? {
        do {
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
            return manifest.problem(appVersion: AppVersion.string)
        } catch {
            return "unreadable: \(error)"
        }
    }

    static func read(_ json: String) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    static let issues = ##"{ "name": "issues", "title": "Issues", "prefix": "#", "list": true }"##
    /// A good entry, beside the one a test refuses.
    static let pulls = ##"{ "name": "pulls", "title": "Pull requests", "prefix": "PR-", "list": true }"##

    // MARK: - Read

    /// The spec's example (Fixtures/Suggestions/plugins/github/plugin.json): one source, two preferences, api 1.
    @Test func theSpecsExampleIsRead() throws {
        let data = try SuggestionsFixtures.data("plugin", in: "plugins/github")
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        #expect(manifest.problem(appVersion: AppVersion.string) == nil)
        #expect(manifest.api == 1)
        #expect(manifest.completions == [
            CompletionSource(name: "issues", title: LocalizedText(en: "GitHub issues", zh: "GitHub issue"), prefix: "#",
                             minChars: 1, compare: .prefix, list: true, refresh: 15 * 60, query: true, queryMinChars: 2,
                             insert: CompletionInsert(default: .templates(["{arg}"]), chat: .templates(["{arg} {url}"]),
                                                      terminal: .templates(["{match}"]))),
        ], "\(manifest.completions)")
        #expect(manifest.preferences == [
            PluginPreference(name: "repos", kind: .text, title: LocalizedText(en: "Repositories", zh: "仓库"),
                             placeholder: "owner/repo, owner/other", defaultValue: "octo-org/octo-repo"),
            PluginPreference(name: "token", kind: .password,
                             title: LocalizedText(en: "Token (optional, for private repos)", zh: "Token（可选，私有仓库用）")),
        ], "\(manifest.preferences)")
    }

    /// What a source leaves out: `minChars` 1 with a prefix (3 without), `compare` prefix, `list` and `query` false,
    /// `refresh` 1 h, `queryMinChars` 3, `insert` `{"default": "{arg}"}`.
    @Test func theDefaults() throws {
        let withPrefix = try Self.read(Self.manifest(completions: ##"[{ "name": "issues", "title": "Issues", "prefix": "#" }]"##))
        #expect(withPrefix.completions == [CompletionSource(name: "issues", title: LocalizedText(en: "Issues"), prefix: "#")])
        let source = try #require(withPrefix.completions.first)
        #expect(source.minChars == 1 && source.compare == .prefix && !source.list && !source.query)
        #expect(source.refresh == 3600 && source.queryMinChars == 3 && source.insert == CompletionInsert(default: .templates(["{arg}"])))

        let exact = try Self.read(Self.manifest(completions: ##"[{ "name": "accounts", "title": "Accounts", "compare": "exact", "list": true }]"##))
        #expect(exact.completions.first?.minChars == 3 && exact.completions.first?.prefix == nil, "\(exact.completions)")
        #expect(exact.problem(appVersion: AppVersion.string) == nil)
    }

    /// Without a prefix, a `compare` left out is `exact` (spec 6.9), and the entry is taken.
    @Test func withoutAPrefixCompareIsExact() throws {
        let manifest = try Self.read(Self.manifest(completions: ##"[{ "name": "accounts", "title": "Accounts", "list": true }]"##))
        #expect(manifest.completions == [CompletionSource(name: "accounts", title: LocalizedText(en: "Accounts"), compare: .exact, list: true)],
                "\(manifest.completions)")
        #expect(manifest.completions.first?.compare == .exact)
        #expect(manifest.refusedCompletions.isEmpty, "\(manifest.refusedCompletions)")
        #expect(CompletionSource(name: "accounts", title: LocalizedText(en: "Accounts")).compare == .exact, "the declaration's default too")
    }

    /// `refresh` in minutes, hours or days, from 5 minutes to 7 days.
    @Test(arguments: [("5m", 300.0), ("15m", 900), ("90m", 5400), ("1h", 3600), ("12h", 43200), ("1d", 86400), ("7d", 604_800)])
    func refreshIsReadInMinutesHoursAndDays(_ value: String, _ seconds: TimeInterval) throws {
        let manifest = try Self.read(Self.manifest(completions: ##"[{ "name": "issues", "title": "Issues", "prefix": "#", "list": true, "refresh": "\##(value)" }]"##))
        #expect(manifest.problem(appVersion: AppVersion.string) == nil, "\(value)")
        #expect(manifest.completions.first?.refresh == seconds, "\(value): \(manifest.completions)")
    }

    /// `insert`: a template, a list tried in turn, or `null` (no completions in that class); a class left out is
    /// `default`'s.
    @Test func insertTakesATemplateAListOrNull() throws {
        let manifest = try Self.read(Self.manifest(completions: """
            [{ "name": "accounts", "title": "AWS accounts", "compare": "exact", "list": true,
               "insert": { "default": ["{match} ({alias})", "{match}"], "terminal": null } }]
            """))
        #expect(manifest.problem(appVersion: AppVersion.string) == nil)
        #expect(manifest.completions.first?.insert == CompletionInsert(default: .templates(["{match} ({alias})", "{match}"]),
                                                                        chat: nil, terminal: .off), "\(manifest.completions)")
    }

    /// Several sources, each with its own name; a name of digits and small letters.
    @Test func severalSourcesInOnePlugin() throws {
        let manifest = try Self.read(Self.manifest(completions: """
            [{ "name": "issues", "title": "Issues", "prefix": "#", "list": true },
             { "name": "pr2", "title": "Pull requests", "prefix": "PR-", "query": true, "queryMinChars": 1 }]
            """))
        #expect(manifest.problem(appVersion: AppVersion.string) == nil)
        #expect(manifest.completions.map(\.name) == ["issues", "pr2"])
        #expect(manifest.completions.last?.queryMinChars == 1 && manifest.completions.last?.prefix == "PR-")
    }

    /// `completions` is optional: a plugin without it (Fixtures/plugins/stock) is as before, with none.
    @Test func aPluginWithoutCompletionsIsAsBefore() throws {
        let url = try #require(Bundle.module.url(forResource: "plugin", withExtension: "json", subdirectory: "Fixtures/plugins/stock"))
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        #expect(manifest.problem(appVersion: AppVersion.string) == nil)
        #expect(manifest.completions.isEmpty && manifest.preferences.isEmpty)
    }

    /// The fixture plugins load from their folders as the app loads plugins.
    @Test func thePluginsLoadFromTheirFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-manifest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["github", "aws"] {
            let source = try SuggestionsFixtures.url("plugin", in: "plugins/\(name)").deletingLastPathComponent()
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
        }
        let (plugins, skipped) = PluginStore.load(from: folder)
        #expect(skipped.isEmpty, "\(skipped)")
        #expect(plugins.map(\.name) == ["aws", "github"])
        let aws = try #require(plugins.first { $0.name == "aws" })
        #expect(aws.manifest.completions.first?.compare == .exact && aws.manifest.completions.first?.refresh == 86400,
                "\(aws.manifest.completions)")
        #expect(aws.manifest.completions.first?.insert.terminal == .off)
        #expect(plugins.first { $0.name == "github" }?.manifest.completions.first?.query == true)
    }

    // MARK: - Refused

    /// Checks that `json` is read with the completion entry `refused` (its name, nil: none) refused with a reason, the
    /// others (`kept`) taken, and the plugin itself usable.
    static func expectRefused(_ json: String, _ what: String, refused: String?, kept: [String] = ["pulls"]) throws {
        let manifest = try read(json)
        #expect(manifest.problem(appVersion: AppVersion.string) == nil, "\(what): the plugin still loads")
        #expect(manifest.completions.map(\.name) == kept, "\(what): \(manifest.completions.map(\.name))")
        #expect(manifest.refusedCompletions.count == 1, "\(what): \(manifest.refusedCompletions)")
        let refusal = try #require(manifest.refusedCompletions.first, "\(what)")
        #expect(refusal.name == refused, "\(what): \(refusal)")
        #expect(!refusal.reason.trimmingCharacters(in: .whitespaces).isEmpty, "\(what): Settings says why")
    }

    /// An entry that breaks the spec's rules is refused on its own, with a reason shown in Settings; the other entries and
    /// the rest of the plugin load (spec 6.8, 6.9).
    @Test(arguments: [
        ("a name with a capital", ##"{ "name": "Issues", "title": "Issues", "prefix": "#", "list": true }"##, "Issues"),
        ("a name with a dash", ##"{ "name": "my-issues", "title": "Issues", "prefix": "#", "list": true }"##, "my-issues"),
        ("a name of 25 characters", ##"{ "name": "abcdefghijklmnopqrstuvwxy", "title": "Issues", "prefix": "#", "list": true }"##,
         "abcdefghijklmnopqrstuvwxy"),
        ("an empty name", ##"{ "name": "", "title": "Issues", "prefix": "#", "list": true }"##, ""),
        ("no title", ##"{ "name": "issues", "prefix": "#", "list": true }"##, "issues"),
        ("another compare", ##"{ "name": "issues", "title": "Issues", "prefix": "#", "compare": "fuzzy", "list": true }"##, "issues"),
        ("prefix compare without a prefix", ##"{ "name": "accounts", "title": "Accounts", "compare": "prefix", "list": true }"##, "accounts"),
        ("queryMinChars 0", ##"{ "name": "issues", "title": "Issues", "prefix": "#", "query": true, "queryMinChars": 0 }"##, "issues"),
        ("a refresh under 5 minutes", ##"{ "name": "issues", "title": "Issues", "prefix": "#", "list": true, "refresh": "1m" }"##, "issues"),
        ("a refresh over 7 days", ##"{ "name": "issues", "title": "Issues", "prefix": "#", "list": true, "refresh": "8d" }"##, "issues"),
        ("a refresh that isn't a duration", ##"{ "name": "issues", "title": "Issues", "prefix": "#", "list": true, "refresh": "soon" }"##, "issues"),
        ("a template that isn't text", ##"{ "name": "issues", "title": "Issues", "prefix": "#", "list": true, "insert": { "default": 42 } }"##, "issues"),
        ("a template list with one that isn't text",
         ##"{ "name": "issues", "title": "Issues", "prefix": "#", "list": true, "insert": { "default": ["{arg}", 7] } }"##, "issues"),
    ])
    func anEntryThatBreaksTheRulesIsRefusedOnItsOwn(_ what: String, _ entry: String, _ name: String) throws {
        try Self.expectRefused(Self.manifest(completions: "[\(entry), \(Self.pulls)]"), what, refused: name)
    }

    /// An entry without a name: refused, and said so (with no name).
    @Test func anEntryWithoutANameIsRefusedOnItsOwn() throws {
        try Self.expectRefused(Self.manifest(completions: ##"[{ "title": "Issues", "prefix": "#", "list": true }, \##(Self.pulls)]"##),
                               "no name", refused: nil)
    }

    /// A name twice: the second entry is refused, the first taken.
    @Test func aNameTwiceRefusesTheSecond() throws {
        try Self.expectRefused(Self.manifest(completions: "[\(Self.issues), \(Self.issues), \(Self.pulls)]"), "a name twice",
                               refused: "issues", kept: ["issues", "pulls"])
    }

    /// `completions` that aren't a list: none of them, said so; the plugin still loads.
    @Test func completionsThatArentAListAreRefused() throws {
        let manifest = try Self.read(Self.manifest(completions: Self.issues))
        #expect(manifest.problem(appVersion: AppVersion.string) == nil)
        #expect(manifest.completions.isEmpty)
        #expect(!manifest.refusedCompletions.isEmpty && manifest.refusedCompletions.allSatisfy { !$0.reason.isEmpty },
                "\(manifest.refusedCompletions)")
    }

    /// A plugin `timeoutSeconds` over 20 s: its completion entries are refused (a load may take 20 s at most, spec 1.2,
    /// 6.9); the plugin (its command) loads, with the timeout it has had.
    @Test func aTimeoutOverTwentySecondsRefusesTheEntries() throws {
        let manifest = try Self.read(Self.manifest(completions: "[\(Self.issues)]", extra: #", "timeoutSeconds": 30"#))
        #expect(manifest.problem(appVersion: AppVersion.string) == nil)
        #expect(manifest.completions.isEmpty, "\(manifest.completions)")
        #expect(manifest.refusedCompletions.map(\.name) == ["issues"], "\(manifest.refusedCompletions)")
        #expect(manifest.timeout == 20)
        let within = try Self.read(Self.manifest(completions: "[\(Self.issues)]", extra: #", "timeoutSeconds": 20"#))
        #expect(within.completions.map(\.name) == ["issues"] && within.refusedCompletions.isEmpty, "20 s: \(within.refusedCompletions)")
    }

    /// Preferences are `text` or `password`, each with a name: another is a problem of the plugin's.
    @Test(arguments: [
        ("another type", ##"[{ "name": "repos", "type": "checkbox", "title": "Repositories" }]"##),
        ("no name", ##"[{ "type": "text", "title": "Repositories" }]"##),
    ])
    func aPreferenceThatBreaksTheRulesIsRefused(_ what: String, _ preferences: String) {
        #expect(Self.refusal(Self.manifest(completions: "[\(Self.issues)]", preferences: preferences)) != nil, "\(what)")
    }

    /// Completions are a script plugin's: a `prompt` or `link` plugin declaring them has them refused (each, with its
    /// reason), and loads as the command it is (spec 6.9).
    @Test(arguments: ["prompt", "link"])
    func completionsOnAPromptOrLinkPluginAreRefused(_ type: String) throws {
        let manifest = try Self.read(Self.manifest(completions: "[\(Self.issues), \(Self.pulls)]", type: type))
        #expect(manifest.problem(appVersion: AppVersion.string) == nil, "\(type): it loads")
        #expect(manifest.completions.isEmpty, "\(type): \(manifest.completions)")
        #expect(manifest.refusedCompletions.map(\.name) == ["issues", "pulls"], "\(type): \(manifest.refusedCompletions)")
        let empty = try Self.read(Self.manifest(completions: "[]", type: type))
        #expect(empty.problem(appVersion: AppVersion.string) == nil && empty.refusedCompletions.isEmpty, "\(type): an empty list is no declaration")
    }

    /// A plugin with a refused entry loads from its folder (not skipped), its command with it; the entry's reason is there
    /// for Settings.
    @Test func aPluginWithARefusedEntryStillLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-refused-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = folder.appendingPathComponent("example")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(Self.manifest(completions: ##"[{ "name": "Issues!", "title": "Issues", "prefix": "#", "list": true }, \##(Self.pulls)]"##).utf8)
            .write(to: directory.appendingPathComponent("plugin.json"))
        try Data(SuggestionsPlugins.script.utf8).write(to: directory.appendingPathComponent("main.js"))
        let (plugins, skipped) = PluginStore.load(from: folder)
        #expect(skipped.isEmpty && plugins.map(\.name) == ["example"], "\(plugins.map(\.name)) \(skipped)")
        let plugin = try #require(plugins.first)
        #expect(plugin.manifest.completions.map(\.name) == ["pulls"], "\(plugin.manifest.completions)")
        #expect(plugin.manifest.refusedCompletions.map(\.name) == ["Issues!"], "\(plugin.manifest.refusedCompletions)")
        #expect(plugin.manifest.refusedCompletions.first?.reason.isEmpty == false)
    }

    // MARK: - Coding language packs

    /// The spec's pack format: language, title, version, keywords, snippets (trigger, body, title).
    @Test func theSpecsPackFormatIsRead() throws {
        let json = #"""
            { "language": "python", "title": "Python", "version": "1.0.0",
              "keywords": ["def", "class", "return"],
              "snippets": [ { "trigger": "def", "body": "def ${1:name}(${2}):\n    $0", "title": "function" } ] }
            """#
        let pack = try JSONDecoder().decode(CodingLanguagePack.self, from: Data(json.utf8))
        #expect(pack == CodingLanguagePack(language: "python", title: "Python", version: "1.0.0", keywords: ["def", "class", "return"],
                                           snippets: [.init(trigger: "def", body: "def ${1:name}(${2}):\n    $0", title: "function")]))
        let again = try JSONDecoder().decode(CodingLanguagePack.self, from: JSONEncoder().encode(pack))
        #expect(again == pack)
    }

    /// The fixture packs (Fixtures/Suggestions/packs/): a snippet's title is optional.
    @Test func theFixturePacksAreRead() throws {
        let python = try JSONDecoder().decode(CodingLanguagePack.self, from: SuggestionsFixtures.data("python", in: "packs"))
        #expect(python.language == "python" && python.keywords.contains("lambda") && python.snippets.count == 4)
        let java = try JSONDecoder().decode(CodingLanguagePack.self, from: SuggestionsFixtures.data("java", in: "packs"))
        #expect(java.language == "java" && java.snippets.first?.trigger == "if")
        let javascript = try JSONDecoder().decode(CodingLanguagePack.self, from: SuggestionsFixtures.data("javascript", in: "packs"))
        #expect(javascript.snippets.last == .init(trigger: "console", body: "console.log($0);", title: nil))
    }

    /// A pack without its language isn't one.
    @Test func aPackWithoutItsLanguageIsRefused() {
        let json = ##"{ "title": "Python", "version": "1.0.0", "keywords": [], "snippets": [] }"##
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CodingLanguagePack.self, from: Data(json.utf8)) }
    }
}
