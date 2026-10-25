import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, spec 1.5: where completions never run (secure input and password fields, the switches: the input
/// menu's, the app's, the source's; a plugin changed since it was enabled; a prefix the command trigger has: spec 6.14),
/// and what is never done with what is typed and listed (logged, learned as English words: spec 6.15). The rig:
/// SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsSwitchesAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static let allRows = ["#7001", "#7002", "#7090", "#7100", "#789"]

    // MARK: - Secure input

    enum Secure: String, CaseIterable, Sendable {
        /// Secure input on in the field's app (the Mac tells it with each key).
        case secureInput
        /// A password field (Windows tells it with the focus).
        case passwordField
        /// Secure input on anywhere (a password prompt, the lock screen).
        case anywhere
    }

    /// In secure input and password fields: no rows, no query (what is typed there goes nowhere), every key the app's.
    @Test(arguments: Secure.allCases)
    func neverInSecureInputOrPasswordFields(_ secure: Secure) async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.secureInputAnywhere = secure == .anywhere
            let field = world.field(passwordField: secure == .passwordField)
            field.host.secure = secure == .secureInput
            field.type("#70")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(secure): \(field.issuesShown)")
            #expect(world.runtime.queries.isEmpty, "\(secure): nothing typed is queried (\(world.runtime.queries))")
            #expect(!field.press(SuggestionKeys.tab), "\(secure): Tab is the app's")

            world.secureInputAnywhere = false
            let open = world.field(app: "com.apple.TextEdit")
            open.type("#7")
            #expect(open.waitForIssues(Self.allRows), "\(secure) off, the same source: \(open.issuesShown)")
        }
    }

    // MARK: - The switches

    /// The input menu's "Suggestions" off: no rows anywhere. On by default once a source is enabled.
    @Test func theMasterSwitchOffMeansNoRows() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.switches.master = false
            let off = world.field()
            off.type("#70")
            off.idle()
            #expect(off.issuesShown.isEmpty, "\(off.issuesShown)")
            #expect(world.runtime.queries.isEmpty)
            world.switches.master = nil
            let byDefault = world.field()
            byDefault.type("#7")
            #expect(byDefault.waitForIssues(Self.allRows), "on by default with a source enabled: \(byDefault.issuesShown)")
        }
    }

    /// An app's "Suggestions" off (Settings → Apps): no rows there; other apps as before.
    @Test func anAppsSwitchOffMeansNoRowsThere() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.switches.apps[SuggestionsApps.editor] = false
            let off = world.field()
            off.type("#70")
            off.idle()
            #expect(off.issuesShown.isEmpty, "\(off.issuesShown)")
            #expect(!off.press(SuggestionKeys.tab))
            let other = world.field(app: "com.apple.TextEdit")
            other.type("#7")
            #expect(other.waitForIssues(Self.allRows), "\(other.issuesShown)")
        }
    }

    /// An app with no AI still has completions: no AI is involved.
    @Test func noAIInAnAppDoesntTurnCompletionsOff() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.config.appProfiles = [SuggestionsApps.editor: AppProfile(noAI: true)]
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows), "\(field.issuesShown)")
        }
    }

    /// A source runs only once approved: without an approval its plugin's script isn't run at all, no rows; approved as
    /// its plugin is installed (owner 2026-10-25, 0.6.7.2: on by default, `Config.approveNewPlugins`; before, off until
    /// enabled), its rows.
    @Test func aSourceRunsOnceApprovedAsItsPluginIsInstalled() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            let plugin = try world.github(enable: false)
            let field = world.field()
            field.type("#70")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
            #expect(world.runtime.calls.isEmpty, "nothing run: \(world.runtime.calls.map(\.kind))")
            var installed = Config.default
            installed.approveNewPlugins([plugin])
            world.switches.enabled = installed.completionSources
            field.host.send(.configChanged)
            field.type(" #7")
            #expect(field.waitForIssues(Self.allRows), "approved as it was installed: \(field.issuesShown)")
        }
    }

    /// A source disabled again: no rows, no more calls.
    @Test func aSourceDisabledAgainShowsNothing() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows))
            world.disable("github", "issues")
            field.host.send(.configChanged)
            let calls = world.runtime.calls.count
            field.type(" #70")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
            #expect(world.runtime.calls.count == calls, "no more calls")
        }
    }

    enum Update: String, CaseIterable, Sendable {
        case hosts, query, script, versionOnly
    }

    /// A plugin update that changes its hosts, the source's query or the script needs enabling again: until then, no rows
    /// and nothing run. One that changes only its version keeps it on.
    @Test(arguments: Update.allCases)
    func aPluginChangedSinceItWasEnabledNeedsEnablingAgain(_ update: Update) async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let warm = world.field()
            warm.type("#7")
            #expect(warm.waitForIssues(Self.allRows))
            let approved = world.switches.enabled

            var manifest = SuggestionsPlugins.githubManifest()
            var script = SuggestionsPlugins.script
            switch update {
            case .hosts: manifest = SuggestionsPlugins.githubManifest(hosts: ["api.github.com", "collector.example.com"])
            case .query: manifest = SuggestionsPlugins.githubManifest(query: false)
            case .script: script += "\nfunction extra() { return 1; }\n"
            case .versionOnly: break
            }
            manifest = manifest.replacingOccurrences(of: #""version": "1.0.0""#, with: #""version": "1.1.0""#)
            let updated = try #require(try SuggestionsPlugins.install(manifest, script: script, in: world.folder))
            world.plugins = [updated]
            world.switches.enabled = approved  // what the user enabled, before the update
            let calls = world.runtime.calls.count

            let field = world.field(app: "com.apple.TextEdit")
            field.type("#7")
            if update == .versionOnly {
                #expect(field.waitForIssues(Self.allRows), "only the version changed: still on (\(field.issuesShown))")
            } else {
                field.type("0")
                field.idle()
                #expect(field.issuesShown.isEmpty, "\(update) changed: off until enabled again (\(field.issuesShown))")
                #expect(world.runtime.calls.count == calls, "\(update) changed: nothing run")
                world.enable(updated, "issues")
                field.host.send(.configChanged)
                field.type(" #7")
                #expect(field.waitForIssues(Self.allRows), "enabled again: \(field.issuesShown)")
            }
        }
    }

    // MARK: - Privacy

    /// Nothing typed, listed or queried, nor a password preference, is ever in a log line (counts only).
    @Test func nothingTypedOrListedIsLogged() async throws {
        try await inEnglish {
            let heard = Locked<[String]>(initialState: [])
            let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
            defer { stop() }
            let world = SuggestionsWorld()
            try world.github(items: [CompletionItem(match: "#qzxv-7001", title: "Quokka zebra banner",
                                                    variables: ["url": "https://github.com/octo-org/octo-repo/issues/7001"])])
            world.preferenceValues.withLock { $0["github"] = ["token": "ghp_exampletoken0000"] }
            for text in ["qz", "qzx", "qzxv"] {
                world.runtime.query(text, items: [CompletionItem(match: "#qzxv-7090", title: "Wombat yak lantern")])
            }
            let field = world.field()
            field.type("#qzxv")
            #expect(field.settle { field.shown(["#qzxv-7001", "#qzxv-7090"]) == ["#qzxv-7001", "#qzxv-7090"] },
                    "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#qzxv-7001")
            world.runtime.list("issues", .failure("GitHub said 401 for qzxv"))
            world.clock.advance(24 * 3600)
            field.fireTimers()
            field.type(" #qzxv")
            field.settle(timeout: 1) { world.runtime.loads.count == 2 }
            field.idle()
            let lines = heard.withLock { $0 }
            for secret in ["qzxv", "Quokka", "zebra", "Wombat", "lantern", "octo-org", "exampletoken", "ghp_"] {
                #expect(!lines.contains { $0.contains(secret) }, "\"\(secret)\" logged: \(lines.filter { $0.contains(secret) })")
            }
        }
    }

    /// Never learned as English words (spec 6.15): what a row inserts, typed in pinyin mode or English mode; a token that
    /// made rows appear (in Code, a word of the field's own, typed twice). Other words learn as before: one typed twice in
    /// English mode, which made no rows.
    @Test func neitherRowsNorTokensThatShowedRowsAreLearnedAsEnglishWords() async throws {
        try await inEnglish {
            for input in [Language.chinese, .english] {
                let world = SuggestionsWorld(input: input)
                world.englishDictionary = EnglishDictionary(["hello", "world"])
                try world.github(items: [CompletionItem(match: "#7001", title: "Crash", arg: "#7001 frobnicate")])
                for _ in 1...2 {
                    let field = world.field()
                    field.type("#7")
                    #expect(field.settle { field.shown(["#7001"]) == ["#7001"] }, "\(input): \(field.rows.map(\.text))")
                    #expect(field.press(SuggestionKeys.tab))
                    #expect(field.document == "#7001 frobnicate", "\(input): \(field.document)")
                    field.type(" ok. ")
                }
                #expect(!world.learned.contains { EnglishWords.key($0) == "frobnicate" }, "\(input): \(world.learned)")
            }

            let coding = SuggestionsWorld()
            coding.addCode("python", packs: [try SuggestionsCodingAcceptanceTests.pack("python")])
            coding.englishDictionary = EnglishDictionary(["hello", "world"])
            let field = coding.codeField()
            #expect(field.host.composer.input == .code)
            field.host.document = "quuxify(items)\n"
            for _ in 1...2 {
                field.type("quux")
                #expect(field.settle { field.shown(["quuxify"]) == ["quuxify"] }, "a word of the field's: \(field.rows.map(\.text))")
                field.type("ify ok ")
            }
            #expect(!coding.learned.contains { EnglishWords.key($0) == "quuxify" }, "\(coding.learned)")

            let english = SuggestionsWorld()
            english.englishDictionary = EnglishDictionary(["hello", "world"])
            try english.github()
            let prose = english.field()
            prose.type("zorblax ok zorblax ok ")
            #expect(english.learned.map(EnglishWords.key) == ["zorblax"], "no rows, typed twice: learned (\(english.learned))")
        }
    }

    // MARK: - The command trigger

    /// The command trigger set to a source's prefix wins (spec 6.14): "#" opens the command list, the "#" source shows no
    /// rows and isn't run; Settings says why it is inactive. Other sources as before.
    @Test func aSourceWhosePrefixIsTheCommandTriggerIsInactive() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            let github = try world.github()
            try world.aws()
            world.config.commandTrigger = "#"
            defer { UIText.commandTrigger = "@" }  // the process's, which the session sets: as other tests have it
            let field = world.field()
            field.press(SuggestionKeys.key("#"))
            #expect(field.host.composer.draft == "#", "the command list opened (\(field.host.composer.draft))")
            field.type("7")
            field.idle()
            #expect(field.issuesShown.isEmpty, "\(field.issuesShown)")
            #expect(!world.runtime.calls.contains { $0.call.source.name == "issues" }, "\(world.runtime.calls.map(\.call.source.name))")

            let other = world.field(app: "com.apple.TextEdit")
            other.type("123456789012")
            #expect(other.settle { other.shown(["123456789012"]) == ["123456789012"] }, "another source: \(other.rows.map(\.text))")

            let issues = try #require(github.manifest.completions.first)
            #expect(issues.inactiveReason(world.config)?.isEmpty == false, "Settings says why")
            var at = world.config
            at.commandTrigger = "@"
            #expect(issues.inactiveReason(at) == nil, "with @, active")
            let accounts = try #require(world.plugins.first { $0.name == "aws" }?.manifest.completions.first)
            #expect(accounts.inactiveReason(world.config) == nil, "without a prefix, active")
        }
    }
}
