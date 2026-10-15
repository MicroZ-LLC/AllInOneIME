import Foundation
import Testing
@testable import AllInOneIMECore

/// Per-app settings (`AppProfile`, `Config.appProfiles`): read from the file leniently, applied over the settings for
/// every app, and no AI in an app refused by the composer and the converter.
struct AppProfileTests {
    let slack = "com.tinyspeck.slackmacgap"
    let mail = "com.apple.mail"

    func decode(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }

    // MARK: - The config file

    @Test func decodesProfiles() throws {
        let config = try decode("""
            {"appProfiles": {
              "com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["口语"], "typeOut": false},
              "com.apple.mail": {"rewriteStyles": ["正式", "委婉"], "noAI": false},
              "com.example.secret": {"noAI": true}
            }}
            """)
        #expect(config.appProfiles.count == 3)
        #expect(config.appProfiles[slack] == AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: false))
        #expect(config.appProfiles[mail] == AppProfile(rewriteStyles: ["正式", "委婉"], noAI: false))
        #expect(config.appProfiles["com.example.secret"]?.noAI == true)
    }

    @Test func noProfilesByDefaultOrInAnOlderFile() throws {
        #expect(Config.default.appProfiles.isEmpty)
        #expect(try decode(#"{"rewriteStyles": ["润色"]}"#).appProfiles.isEmpty)
        #expect(try decode(#"{"appProfiles": null}"#).appProfiles.isEmpty)
    }

    @Test func readsLeniently() throws {
        // Unknown keys, a key of the wrong type, an unknown language code: left out, the rest kept. An entry that
        // isn't an object, or whose key is no bundle id, is left out; the file still loads.
        let config = try decode("""
            {"appProfiles": {
              "com.tinyspeck.slackmacgap": {"inputLanguage": "xx", "typeOut": "yes", "noAI": true, "color": "red"},
              "com.apple.mail": {"rewriteStyles": "正式", "inputLanguage": "zh"},
              "com.example.number": 3,
              "com.example.list": ["noAI"],
              "": {"noAI": true},
              "two words": {"noAI": true}
            }, "actionKey": "enter"}
            """)
        #expect(config.appProfiles == [slack: AppProfile(noAI: true), mail: AppProfile(inputLanguage: .chinese)])
        #expect(config.actionKey == .enter)
        // Not an object at all: none, and the rest of the file is read.
        let other = try decode(#"{"appProfiles": ["com.apple.mail"], "typeOut": true}"#)
        #expect(other.appProfiles.isEmpty && other.typeOut)
        // A style name this version doesn't know is kept (a later one may), and does nothing.
        let later = try decode(#"{"appProfiles": {"com.apple.mail": {"rewriteStyles": ["正式", "Pirate"]}}}"#)
        #expect(later.appProfiles[mail]?.rewriteStyles == ["正式", "Pirate"])
        #expect(RewriteStyle.resolve(later.applying(app: mail).rewriteStyles).map(\.tag) == ["FORMAL"])
    }

    @Test func savesAndReadsBack() throws {
        var config = Config.default
        config.appProfiles = [slack: AppProfile(inputLanguage: .english, rewriteStyles: [], typeOut: true),
                              mail: AppProfile(noAI: true)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("appprofiles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.write(to: url)
        #expect(try Config.load(from: url) == config)
        // Only what is set is written.
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let profiles = try #require(json["appProfiles"] as? [String: [String: Any]])
        #expect(Set(profiles[mail]?.keys.map { $0 } ?? []) == ["noAI"])
        #expect(Set(profiles[slack]?.keys.map { $0 } ?? []) == ["inputLanguage", "rewriteStyles", "typeOut"])
        #expect(AppProfile().isEmpty && AppProfile(noAI: false).isEmpty && !AppProfile(typeOut: false).isEmpty)
    }

    @Test func noKeyWithoutAProfileAndEmptyOnesDropped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("appprofiles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        func keys() throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        // A file from before per-app settings, saved again: no "appProfiles" in it.
        try Data(#"{"rewriteStyles": ["润色"]}"#.utf8).write(to: url)
        try Config.load(from: url).write(to: url)
        #expect(try keys()["appProfiles"] == nil)
        // Only empty profiles (an app added that sets nothing, "noAI": false): still none.
        var config = Config.default
        config.appProfiles = [slack: AppProfile(), mail: AppProfile(noAI: false)]
        try config.write(to: url)
        #expect(try keys()["appProfiles"] == nil)
        // With one that sets something, only that one is written.
        config.appProfiles["com.example.quiet"] = AppProfile(noAI: true)
        try config.write(to: url)
        let written = try #require(try keys()["appProfiles"] as? [String: Any])
        #expect(Array(written.keys) == ["com.example.quiet"])
        #expect(try Config.load(from: url).appProfiles == ["com.example.quiet": AppProfile(noAI: true)])
    }

    @Test func bundleIDsMatchIgnoringCase() throws {
        // Written by hand with Mail's name capitalized: still Mail's, kept under the key as written.
        let config = try decode(#"{"appProfiles": {"com.apple.Mail": {"noAI": true}}}"#)
        #expect(Array(config.appProfiles.keys) == ["com.apple.Mail"])
        #expect(!config.allowsAI(in: mail) && !config.allowsAI(in: "COM.APPLE.MAIL") && config.allowsAI(in: "com.apple.mailx"))
        #expect(config.profileKey(for: mail) == "com.apple.Mail" && config.profileKey(for: slack) == nil)
        // The id as given comes first.
        var both = Config.default
        both.appProfiles = ["com.apple.Mail": AppProfile(typeOut: true), mail: AppProfile(typeOut: false)]
        #expect(both.profile(for: mail)?.typeOut == false && both.profile(for: "com.apple.Mail")?.typeOut == true)
        #expect(both.profile(for: "COM.apple.mail")?.typeOut == true)  // else the first in sorted order
    }

    @Test func keysThatDifferOnlyInCaseKeepTheFirstEveryTime() throws {
        let json = #"{"appProfiles": {"com.apple.mail": {"typeOut": false}, "com.apple.Mail": {"typeOut": true}, "COM.APPLE.MAIL": {"noAI": true}}}"#
        for _ in 0..<20 {
            let config = try decode(json)
            #expect(config.appProfiles == ["COM.APPLE.MAIL": AppProfile(noAI: true)])  // first in sorted order
            #expect(!config.allowsAI(in: mail))
        }
    }

    @Test func ofKeysDifferingInCaseOneThatSetsSomethingWins() throws {
        // An empty one sorted first doesn't hide "no AI" (which the next save would then lose for good).
        let json = #"{"appProfiles": {"com.apple.Mail": {}, "com.apple.mail": {"noAI": true}, "COM.APPLE.MAIL": {"noAI": false}}}"#
        for _ in 0..<20 {
            let config = try decode(json)
            #expect(config.appProfiles == [mail: AppProfile(noAI: true)])
            #expect(!config.allowsAI(in: mail) && !config.allowsAI(in: "com.apple.Mail"))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("appprofiles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try decode(json).write(to: url)
        #expect(try Config.load(from: url).appProfiles == [mail: AppProfile(noAI: true)])
        // All empty: the first in sorted order, as before.
        #expect(try decode(#"{"appProfiles": {"com.apple.mail": {}, "com.apple.Mail": {}}}"#).appProfiles == ["com.apple.Mail": AppProfile()])
    }

    // MARK: - Resolution

    var configured: Config {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.rewriteStyles = ["润色", "简洁"]
        config.typeOut = false
        config.appProfiles = [slack: AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true),
                              mail: AppProfile(rewriteStyles: []),
                              "com.example.french": AppProfile(inputLanguage: .french),
                              "com.example.quiet": AppProfile(noAI: true)]
        return config
    }

    @Test func anAppWithoutAProfileHasTheGlobalSettings() {
        let config = configured
        for app in [nil, "", "com.example.other"] {
            #expect(config.applying(app: app) == config)
            #expect(config.startingInput(in: app, among: [.chinese, .english]) == .chinese)
            #expect(config.allowsAI(in: app))
        }
    }

    @Test func aProfileOverridesWhatItSets() {
        let config = configured
        let inSlack = config.applying(app: slack)
        #expect(inSlack.rewriteStyles == ["口语"] && inSlack.typeOut)
        // The rest as it is.
        #expect(inSlack.defaultInput == config.defaultInput && inSlack.outputLanguages == config.outputLanguages
                && inSlack.appProfiles == config.appProfiles)
        // An empty list: no rewrites there; typing out not set: the global one.
        let inMail = config.applying(app: mail)
        #expect(inMail.rewriteStyles.isEmpty && !inMail.typeOut)
        #expect(config.allowsAI(in: slack) && config.allowsAI(in: mail) && !config.allowsAI(in: "com.example.quiet"))
    }

    @Test func theStartingLanguage() {
        let config = configured
        #expect(config.startingInput(in: slack, among: [.chinese, .english]) == .english)
        #expect(config.startingInput(in: mail, among: [.chinese, .english]) == .chinese)
        // Its own language not added (or its pack not there yet): the default one; that one not usable either: the first.
        #expect(config.startingInput(in: "com.example.french", among: [.chinese, .english]) == .chinese)
        #expect(config.startingInput(in: slack, among: [.chinese]) == .chinese)
        #expect(config.startingInput(in: "com.example.french", among: [.english, .korean]) == .english)
    }

    @Test func theStylesReachThePromptAndNothingElseChanges() throws {
        let config = configured
        func system(_ config: Config) -> String { Prompt.request(for: "我今天有点不舒服", config: config).system.first?.text ?? "" }
        #expect(system(config.applying(app: slack)).contains("STYLE_CASUAL: "))
        #expect(!system(config.applying(app: slack)).contains("STYLE_POLISH: "))
        #expect(!system(config.applying(app: mail)).contains("STYLE_"))
        // Without a profile the request is the very same.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func json(_ config: Config) throws -> Data { try encoder.encode(Prompt.request(for: "hi", config: config)) }
        #expect(try json(config.applying(app: "com.example.other")) == json(config))
        let plain = try json(Config.default)
        #expect(try json(Config.default.applying(app: slack)) == plain)
    }

    // MARK: - No AI

    @Test func whichCommandsUseAI() {
        #expect([Command.improve, .translate, .question, .claude, .edit].allSatisfy { $0.usesAI })
        #expect(![Command.open, .read, .note, .reminder, .calc, .py, .js, .webSearch, .tasks, .settings, .imessage, .reportIssue]
            .contains { $0.usesAI })
        let custom = Command.catalog([CustomCommand(name: "reply", type: .prompt, prompt: "Reply."),
                                      CustomCommand(name: "shout", type: .run, argv: ["tr", "a-z", "A-Z"])])
        #expect(custom.first { $0.name == "reply" }?.usesAI == true && custom.first { $0.name == "shout" }?.usesAI == false)
    }

    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

    func typeKeys(_ text: String, _ composer: Composer) {
        for ch in text { _ = composer.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    func noAIComposer() -> Composer {
        let c = Composer(engine: FakeEngine())
        c.setInputMode(.english)
        c.aiRefusal = { "no AI here" }
        return c
    }

    func startsAnything(_ effects: [Composer.Effect]) -> Bool {
        effects.contains {
            switch $0 {
            case .startConversion, .startCommand, .startPlan, .startRun, .runInTerminal, .startBackgroundAgent: return true
            default: return false
            }
        }
    }

    @Test func aiCommandsAreRefusedWithANotice() {
        for draft in ["@improve hello there", "@translate hello", "@question why", "@claude fix it"] {
            let c = noAIComposer()
            typeKeys(draft, c)
            let effects = c.handleKeyDown(enterKey).effects
            #expect(effects.contains(.notice("no AI here")) && !startsAnything(effects), "\(draft): \(effects)")
            // The draft stays, as typed; nothing is in level two.
            #expect(c.draft == draft && !c.isLevelTwo && c.activeCommand == nil)
        }
    }

    @Test func anAICommandWithACommandInsideIsRefusedBeforeEither() {
        let c = noAIComposer()
        typeKeys("@question what is @calculate 2*3", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.contains(.notice("no AI here")) && !startsAnything(effects))
    }

    @Test func theOtherCommandsAndTypingStillWork() {
        let c = noAIComposer()
        typeKeys("@calculate 2*3", c)
        #expect(c.handleKeyDown(enterKey).effects.first == .startRun(.calc, input: "2*3", id: 1))
        let note = noAIComposer()
        typeKeys("@note buy milk", note)
        #expect(note.handleKeyDown(enterKey).effects.contains(.saveNote(text: "buy milk")))
        let open = noAIComposer()
        typeKeys("@open notes", open)
        #expect(open.handleKeyDown(enterKey).effects.first == .search(query: "notes", id: 1))
        // Plain pinyin: no AI anywhere.
        let typing = Composer(engine: FakeEngine())
        typing.aiRefusal = { "no AI here" }
        typeKeys("nihao", typing)
        #expect(commits(typing.handleKeyDown(spaceKey)) == ["你好"])
        // Allowed (nil): the request starts as before.
        let allowed = Composer(engine: FakeEngine())
        allowed.setInputMode(.english)
        typeKeys("@improve hello", allowed)
        #expect(allowed.handleKeyDown(enterKey).effects.first == .startConversion(input: "hello", id: 1))
    }

    @Test func theConverterSendsNothingFromAnAppWithNoAI() async throws {
        let config = configured
        let converter = Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { config },
                                  loadCredentials: { _ in throw AWSConfigError.profileNotFound("never asked") })
        await #expect(throws: AppProfile.Refusal.noAI) {
            for try await _ in converter.convert("hello", app: "com.example.quiet") {}
        }
        await #expect(throws: AppProfile.Refusal.noAI) {
            for try await _ in converter.generate(.question, input: "why", app: "com.example.quiet") {}
        }
        // Another app goes on to the request (the credentials, here the first thing that fails).
        await #expect(throws: AWSConfigError.profileNotFound("never asked")) {
            for try await _ in converter.convert("hello", app: slack) {}
        }
    }

    // MARK: - @reportissue

    @Test func theReportCountsProfilesOnly() {
        var config = Config.default
        func lines(_ config: Config) -> [String] {
            IssueReport(title: "", diagnostics: IssueReport.Diagnostics(config: config, macOS: "26", architecture: "arm64",
                                                                        interfaceLanguage: "en", languagePacks: [], plugins: 0, extensions: 0)).lines
        }
        #expect(!lines(config).contains { $0.hasPrefix("Apps with") })
        config.appProfiles = ["com.example.added": AppProfile()]
        #expect(!lines(config).contains { $0.hasPrefix("Apps with") })
        config.appProfiles = [slack: AppProfile(noAI: true), mail: AppProfile(typeOut: true),
                              "com.example.added": AppProfile(), "com.example.off": AppProfile(noAI: false)]
        let shown = lines(config)
        #expect(shown.last == "Apps with their own settings: 2")  // the two that set nothing aren't counted
        #expect(!shown.joined().contains("slack") && !shown.joined().contains("com.apple"))
    }
}
