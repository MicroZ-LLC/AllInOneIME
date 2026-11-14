import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// The AI chosen in Settings → AI (`AIChoice`, `Config.ai`, the owner's design, 0.7.4): one choice, grouped by how it
/// connects; each choice's status (`AIStatus`) from what this Mac has (`AIFacts`); the config files from before read as
/// they always worked (the provider and 0.7.4's `questionBackend`), keys and settings untouched; and with a CLI chosen,
/// where what has to be fast goes (`Config.fastProvider`): through the converter too (`FastRoute`).
struct AIChoiceTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ai-choice-\(UUID().uuidString)")

    // MARK: - The choices and their groups

    @Test func theChoicesByHowTheyConnect() {
        #expect(AIChoice.all == [.cli(.claude), .cli(.codex), .cli(.antigravity), .cli(.kiro), .provider(.anthropic), .provider(.openai),
                                 .provider(.gemini), .provider(.bedrock), .provider(.hosted), .provider(.apple)])
        // Every choice once, every provider and every CLI among them.
        #expect(Set(AIChoice.all).count == AIChoice.all.count)
        #expect(Set(AIChoice.all.compactMap(\.provider)) == Set(Provider.allCases))
        #expect(AIChoice.all.compactMap(\.agent) == SessionAgent.allCases)
        // The groups, in order, each with its own.
        let groups = AIChoice.groups(hosted: true, apple: .available)
        #expect(groups.map(\.group) == [.subscription, .apiKey, .cloud, .onDevice])
        #expect(groups.map(\.choices) == [
            [.cli(.claude), .cli(.codex), .cli(.antigravity), .cli(.kiro)],
            [.provider(.anthropic), .provider(.openai), .provider(.gemini)],
            [.provider(.bedrock), .provider(.hosted)],
            [.provider(.apple)],
        ])
        for (group, choices) in groups { #expect(choices.allSatisfy { $0.group == group }) }
        // Apple's model where the system has it (greyed out with its reason otherwise: offered, its status says why);
        // AllInOneIME Cloud once it is set up; the one chosen always, whatever they say.
        #expect(AIChoice.groups(hosted: true, apple: .appleIntelligenceNotEnabled).last?.choices == [.provider(.apple)])
        let old = AIChoice.groups(hosted: false, apple: .unsupportedSystem)
        #expect(old.map(\.group) == [.subscription, .apiKey, .cloud])
        #expect(old.flatMap(\.choices).contains(.provider(.hosted)) == false)
        let kept = AIChoice.groups(hosted: false, apple: .unsupportedSystem, keeping: .provider(.apple))
        #expect(kept.last?.group == .onDevice && kept.last?.choices == [.provider(.apple)])
        #expect(AIChoice.groups(hosted: false, apple: .available, keeping: .provider(.hosted)).flatMap(\.choices).contains(.provider(.hosted)))
    }

    @Test func eachChoiceHasAnIDAsTheFileWritesIt() {
        #expect(AIChoice.all.map(\.id) == ["claudeSession", "codexSession", "antigravitySession", "kiroSession",
                                           "anthropic", "openai", "gemini", "bedrock", "hosted", "apple"])
        for choice in AIChoice.all { #expect(AIChoice(id: choice.id) == choice) }
        #expect(AIChoice(id: "provider") == nil && AIChoice(id: "") == nil && AIChoice(id: "copilotSession") == nil)
    }

    @Test func theirNamesAndGroupsInEnglishAndChinese() async {
        await withInterfaceLanguage("en") {
            #expect(AIChoice.all.map(\.name) == ["Claude Code", "Codex", "Antigravity", "Kiro CLI", "Claude API", "OpenAI-compatible",
                                                 "Gemini API", "Amazon Bedrock", "AllInOneIME Cloud", "Apple on-device"])
            #expect(AIChoice.Group.allCases.map(\.title) == ["With your subscription", "With an API key", "Cloud services", "On this Mac"])
            #expect(AIChoice.cli(.codex).detail(.signedIn) == "Through the CLI on this Mac, with your own subscription · Signed in")
            #expect(AIChoice.provider(.bedrock).detail(.aws(profile: "default", region: "us-west-2")) == "default · us-west-2")
        }
        await withInterfaceLanguage("zh") {
            #expect(AIChoice.all.map(\.name).suffix(6) == ["Claude API", "OpenAI 兼容", "Gemini API", "Amazon Bedrock", "AllInOneIME Cloud", "Apple 本机"])
            #expect(AIChoice.Group.allCases.map(\.title) == ["用你的订阅", "用 API Key", "云服务", "本机"])
            #expect(AIChoice.Group.allCases.map(\.note) == ["本机装的 CLI，不用 API Key", "按用量付费", "公司账号常用", "不出这台 Mac"])
            #expect([AIStatus.signedIn, .signedOut, .notInstalled(program: "codex"), .key(.missing), .apple(.available)].map(\.text)
                    == ["已登录", "没登录", "没装", "没填 Key", "可用"])
        }
    }

    // MARK: - Statuses

    @Test func eachChoicesStatusFromWhatThisMacHas() {
        var config = Config.default
        config.awsProfile = "work"
        let facts = AIFacts(sessions: [.claude: .ready, .codex: .signedOut, .antigravity: .notInstalled],
                            keys: [.anthropic: .saved(ending: "a1b2"), .openai: .shell("OPENAI_API_KEY"), .gemini: .missing],
                            hostedSignedIn: false,
                            awsProfiles: [AWSProfileSummary(name: "default", region: "us-east-2", kind: .staticKeys),
                                          AWSProfileSummary(name: "work", region: "us-west-2", kind: .sso),
                                          AWSProfileSummary(name: "bare", region: nil, kind: .credentialProcess),
                                          AWSProfileSummary(name: "empty", region: "us-west-2", kind: .noCredentials)],
                            apple: .appleIntelligenceNotEnabled)
        func status(_ choice: AIChoice) -> AIStatus { facts.status(choice, config: config) }
        #expect(status(.cli(.claude)) == .signedIn)
        #expect(status(.cli(.codex)) == .signedOut)
        #expect(status(.cli(.antigravity)) == .notInstalled(program: "agy"))
        #expect(status(.cli(.kiro)) == .unknown)  // not looked at yet
        #expect(status(.provider(.anthropic)) == .key(.saved(ending: "a1b2")))
        #expect(status(.provider(.openai)) == .key(.shell("OPENAI_API_KEY")))
        #expect(status(.provider(.gemini)) == .key(.missing))
        #expect(status(.provider(.hosted)) == .signedOut)
        #expect(status(.provider(.apple)) == .apple(.appleIntelligenceNotEnabled))
        // Bedrock: the profile and the region requests go to: the one set, else the profile's, else us-east-1.
        #expect(status(.provider(.bedrock)) == .aws(profile: "work", region: "us-west-2"))
        config.region = " eu-central-1 "
        #expect(status(.provider(.bedrock)) == .aws(profile: "work", region: "eu-central-1"))
        config.region = nil
        config.awsProfile = "bare"
        #expect(status(.provider(.bedrock)) == .aws(profile: "bare", region: "us-east-1"))
        config.awsProfile = "gone"
        #expect(status(.provider(.bedrock)) == .noAWSProfile("gone"))
        // A profile with a region but nothing to sign a request with can't answer; profiles not read yet are still to be
        // looked at.
        config.awsProfile = "empty"
        #expect(status(.provider(.bedrock)) == .noAWSCredentials("empty"))
        #expect(status(.provider(.bedrock)).text.hasPrefix("empty · "))
        #expect(AIFacts().status(.provider(.bedrock), config: config) == .unknown)
        // A key not looked up yet is still to be looked at, as a CLI's sign-in.
        #expect(AIFacts().status(.provider(.anthropic), config: config) == .key(.loading))

        // Ready: what can answer; a problem: what lacks something the user can give (drawn in orange); neither: not
        // looked at yet.
        let ready: [AIStatus] = [.signedIn, .key(.saved(ending: nil)), .key(.shell("X")), .aws(profile: "p", region: "r"), .apple(.available)]
        let problems: [AIStatus] = [.signedOut, .notInstalled(program: "kiro-cli"), .key(.missing), .noAWSProfile("p"), .noAWSCredentials("p"),
                                    .apple(.modelNotReady)]
        #expect(ready.allSatisfy { $0.isReady && !$0.isProblem })
        #expect(problems.allSatisfy { !$0.isReady && $0.isProblem })
        #expect([AIStatus.unknown, .key(.loading)].allSatisfy { !$0.isReady && !$0.isProblem })
        #expect(facts.isReady(.anthropic, config: config) && !facts.isReady(.gemini, config: config) && !facts.isReady(.bedrock, config: config))
    }

    // MARK: - The config: one choice, from the files of before

    /// `json` read as a config file.
    func read(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }

    @Test func filesFromBeforeAreOnTheAITheyUsed() throws {
        // 0.7.3 and before: no questionBackend, everything went to the provider. It is the AI now.
        for provider in Provider.allCases {
            #expect(try read(#"{"provider": "\#(provider.rawValue)"}"#).ai == .provider(provider))
        }
        // A file without a provider (from before providers) stays on Bedrock, as it always did.
        #expect(try read("{}").ai == .provider(.bedrock))
        // 0.7.4's builds: a session picked for @question is the CLI chosen now; the provider stays, as the fast fallback.
        let picked = try read(#"{"provider": "anthropic", "questionBackend": "kiroSession", "anthropic": {"model": "claude-sonnet-5-5"}}"#)
        #expect(picked.ai == .cli(.kiro) && picked.provider == .anthropic && picked.anthropic.model == "claude-sonnet-5-5")
        for agent in SessionAgent.allCases {
            #expect(try read(#"{"provider": "gemini", "questionBackend": "\#(QuestionBackend(agent).rawValue)"}"#).ai == .cli(agent))
        }
        // The provider picked for questions ("provider"), Automatic (no key: never shipped), and a later version's choice
        // all mean the provider.
        #expect(try read(#"{"provider": "openai", "questionBackend": "provider"}"#).ai == .provider(.openai))
        #expect(try read(#"{"provider": "openai"}"#).questionBackend == nil)
        #expect(try read(#"{"provider": "apple", "questionBackend": "copilotSession"}"#).ai == .provider(.apple))
        // Gemini CLI's session (0.7.4's earlier builds; Gemini CLI no longer serves personal Google accounts) is
        // Antigravity's, the provider kept (`Config.migrateGeminiCLISession` makes it the provider without agy).
        let gemini = try read(#"{"provider": "anthropic", "questionBackend": "geminiSession"}"#)
        #expect(gemini.ai == .cli(.antigravity) && gemini.provider == .anthropic)
    }

    @Test func choosingKeepsEveryProvidersSettings() throws {
        var config = try read(#"""
            {"provider": "bedrock", "awsProfile": "work", "region": "us-west-2", "modelId": "us.anthropic.claude-haiku-5-5",
             "anthropic": {"model": "claude-sonnet-5-5"}, "openai": {"baseURL": "https://api.deepseek.com/v1", "model": "deepseek-chat"}}
            """#)
        let before = config
        // A CLI: the provider stays as it was (what has to be fast goes there); only the CLI is written.
        config.ai = .cli(.codex)
        #expect(config.ai == .cli(.codex) && config.questionBackend == .codexSession && config.provider == .bedrock)
        var expected = before
        expected.questionBackend = .codexSession
        #expect(config == expected)
        let written = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(written.contains(#""questionBackend":"codexSession""#) && written.contains(#""provider":"bedrock""#))
        #expect(try JSONDecoder().decode(Config.self, from: Data(written.utf8)).ai == .cli(.codex))
        // Another CLI: only the CLI changes.
        config.ai = .cli(.antigravity)
        #expect(config.questionBackend == .antigravitySession && config.provider == .bedrock)
        // A provider: it is the AI, the CLI forgotten (no key in the file), every provider's settings as they were.
        config.ai = .provider(.openai)
        #expect(config.ai == .provider(.openai) && config.questionBackend == nil)
        expected = before
        expected.provider = .openai
        #expect(config == expected)
        #expect(!String(decoding: try JSONEncoder().encode(config), as: UTF8.self).contains("questionBackend"))
        // The CLI is this Mac's own: never synced (the provider is, as before).
        #expect(ICloudSync.category(of: "questionBackend") == nil && ICloudSync.category(of: "provider") == .settings)
        // Where @question goes: the CLI chosen, else the provider.
        config.ai = .cli(.kiro)
        #expect(config.questionSessionAgent == .kiro)
        config.ai = .provider(.anthropic)
        #expect(config.questionSessionAgent == nil)
    }

    // MARK: - The fast fallback

    @Test func whatHasToBeFastWithACLIChosen() {
        var config = Config.default
        config.provider = .anthropic
        // A provider chosen: that provider, set up or not (it says what's missing when asked).
        for provider in Provider.allCases {
            config.ai = .provider(provider)
            #expect(config.fastProvider(ready: { _ in false }, apple: .unsupportedSystem) == provider)
            #expect(config.fastProvider(ready: { _ in true }, apple: .available) == provider)
        }
        // A CLI chosen: the provider set up before, …
        for provider in Provider.allCases where provider != .apple {
            config.ai = .provider(provider)
            config.ai = .cli(.claude)
            #expect(config.fastProvider(ready: { $0 == provider }, apple: .available) == provider)
            #expect(config.fastProvider(ready: { $0 == provider }, apple: .unsupportedSystem) == provider)
            // … else Apple's model where it is available, …
            #expect(config.fastProvider(ready: { _ in false }, apple: .available) == .apple)
            // … else none (autocomplete off, the rest to the CLI's session).
            for apple in [AppleModelAvailability.unsupportedSystem, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady] {
                #expect(config.fastProvider(ready: { _ in false }, apple: apple) == nil)
            }
            // Another provider set up isn't the one set up before: not taken.
            #expect(config.fastProvider(ready: { $0 != provider }, apple: .unsupportedSystem) == nil)
        }
        // Apple's model as the provider before: it, where it is available.
        config.ai = .provider(.apple)
        config.ai = .cli(.kiro)
        #expect(config.fastProvider(ready: { _ in true }, apple: .available) == .apple)
        #expect(config.fastProvider(ready: { _ in true }, apple: .modelNotReady) == nil)
        // By what a Mac has (`AIFacts`): Bedrock's profile found; a key added; AllInOneIME Cloud signed in.
        config.ai = .provider(.bedrock)
        config.awsProfile = "work"
        config.ai = .cli(.codex)
        func profile(_ name: String, _ kind: AWSProfileKind) -> [AWSProfileSummary] { [AWSProfileSummary(name: name, region: nil, kind: kind)] }
        #expect(config.fastProvider(AIFacts(awsProfiles: profile("work", .staticKeys), apple: .available)) == .bedrock)
        #expect(config.fastProvider(AIFacts(awsProfiles: profile("default", .staticKeys), apple: .available)) == .apple)
        #expect(config.fastProvider(AIFacts(awsProfiles: profile("default", .staticKeys))) == nil)
        // A profile with nothing to sign a request with isn't a fallback: Apple's model then, or none.
        #expect(config.fastProvider(AIFacts(awsProfiles: profile("work", .noCredentials), apple: .available)) == .apple)
        #expect(config.fastProvider(AIFacts(awsProfiles: profile("work", .noCredentials))) == nil)
        #expect(config.fastProvider(AIFacts(apple: .available)) == .apple)  // not read yet
        // The environment's keys with no profile file: "default" can answer.
        config.awsProfile = "default"
        #expect(config.fastProvider(AIFacts(awsProfiles: profile("default", .environment))) == .bedrock)
        config.awsProfile = "work"
        config.provider = .gemini
        #expect(config.fastProvider(AIFacts(keys: [.gemini: .saved(ending: nil)])) == .gemini)
        #expect(config.fastProvider(AIFacts(keys: [.gemini: .loading], apple: .available)) == .apple)
        config.provider = .hosted
        #expect(config.fastProvider(AIFacts(hostedSignedIn: true)) == .hosted)
    }

    @Test func theNoteUnderACLISaysWhereWhatIsFastGoes() async {
        await withInterfaceLanguage("zh") {
            #expect(AIChoice.fallbackNote(.apple) == "@question 走 CLI（要 1 秒以上）；改写、翻译、续写这些要快的，自动用「Apple 本机」。")
            #expect(AIChoice.fallbackNote(nil).contains("续写关闭"))
        }
        await withInterfaceLanguage("en") {
            #expect(AIChoice.fallbackNote(.anthropic).hasSuffix("uses Claude API."))
            #expect(AIChoice.fallbackNote(nil).contains("autocomplete is off"))
        }
    }

    // MARK: - Through the converter

    func session(_ fake: FakeClaude) -> ClaudeSessionManager {
        ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder), userSettings: { nil })
    }

    /// A converter with `config`, the Claude Code session on `fake`, Apple's model `apple`, the key `key` for every
    /// provider (nil: none) and the AWS profiles `profiles`.
    func converter(_ config: Config, _ fake: FakeClaude, apple: StubAppleModel, key: String? = nil,
                   profiles: Set<String> = []) -> Converter {
        Converter(loadConfig: { config }, loadKey: { _, _ in key }, appleModel: apple, claudeSession: session(fake),
                  hasAWSProfile: { profiles.contains($0) })
    }

    func final(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> ConversionUpdate? {
        var last: ConversionUpdate?
        for try await update in stream { last = update }
        return last
    }

    @Test func theConverterSendsWhatIsFastToTheFallback() async throws {
        var config = Config.default
        config.ai = .provider(.anthropic)
        config.ai = .cli(.claude)
        let fake = FakeClaude()
        // The provider set up (its key): it.
        let keyed = converter(config, fake, apple: StubAppleModel(), key: "sk-ant-test")
        #expect(keyed.fast(config).config.provider == .anthropic && !keyed.fast(config).slow)
        // Bedrock with its profile on this Mac; without it, Apple's model.
        var bedrock = config
        bedrock.provider = .bedrock
        #expect(converter(bedrock, fake, apple: StubAppleModel(), profiles: [bedrock.awsProfile]).fast(bedrock).config.provider == .bedrock)
        #expect(converter(bedrock, fake, apple: StubAppleModel(), profiles: []).fast(bedrock).config.provider == .apple)
        // A provider chosen: as it is, nothing looked up.
        var chosen = config
        chosen.ai = .provider(.gemini)
        let asIs = converter(chosen, fake, apple: StubAppleModel(.modelNotReady))
        #expect(asIs.fast(chosen).config == chosen && !asIs.fast(chosen).slow)

        // No key: Apple's model rewrites, never the CLI.
        let apple = StubAppleModel(answer: ["1. Hello there."])
        let onDevice = converter(config, fake, apple: apple)
        let route = onDevice.fast(config)
        #expect(route.config.provider == .apple && !route.slow && route.config.questionBackend == .claudeSession)
        _ = try await final(onDevice.convert("hello there", mode: .improve))
        #expect(apple.requests.count == 1 && fake.processes.isEmpty)
        // Autocomplete too.
        _ = try? await onDevice.autocomplete(Autocomplete.Context(before: "I think we", after: ""), app: nil)
        #expect(apple.requests.count == 2 && fake.processes.isEmpty)
    }

    @Test func withNoFastAIWritingGoesToTheCLIsSessionAndAutocompleteIsOff() async throws {
        var config = Config.default
        config.ai = .provider(.openai)
        config.ai = .cli(.claude)
        let fake = FakeClaude()
        let apple = StubAppleModel(.appleIntelligenceNotEnabled, answer: ["never"])
        let converter = converter(config, fake, apple: apple)
        #expect(converter.fast(config).slow && converter.fast(config).model == "session:claude")
        // Autocomplete: off (as Apple's model unavailable says it), nothing asked.
        await #expect(throws: AppleModelError.unavailable(.appleIntelligenceNotEnabled)) {
            _ = try await converter.autocomplete(Autocomplete.Context(before: "I think we", after: ""), app: nil)
        }
        #expect(fake.processes.isEmpty && apple.requests.isEmpty)
        // Rewriting: the request to the session, as one message (its instructions, then the text), the answer read as a
        // provider's.
        let stream = converter.convert("hello there", mode: .improve)
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        let process = try #require(fake.last)
        let message = try #require(process.messages.first)
        #expect(message.hasPrefix("This is a writing task, not a question") && message.contains("<instructions>")
                && message.hasSuffix("hello there"))
        process.started()
        process.text("1. Hello there!")
        process.done("1. Hello there!")
        let last = try await final(stream)
        #expect(last?.isFinal == true && last?.result.versions.first?.text == "Hello there!" && apple.requests.isEmpty)
        // A conversation of its own, with no web tools: the text rewritten may be one the user didn't type.
        let tools = try #require(process.arguments.firstIndex(of: "--tools"))
        #expect(process.arguments[tools + 1] == "" && !process.arguments.contains("--allowedTools"))
    }

    @Test(TaskLanguage("en")) func aQuestionTheCLICantAnswerGoesToTheFallbackOrFails() async throws {
        var config = Config.default
        config.ai = .provider(.bedrock)
        config.ai = .cli(.claude)
        let fake = FakeClaude()
        fake.missing = true
        // Apple's model as the fallback: it answers, and the panel says why.
        let apple = StubAppleModel(answer: ["From Apple."])
        let last = try await final(converter(config, fake, apple: apple).generate(.question, input: "what is rust"))
        #expect(last?.result.versions.first?.text == "From Apple." && last?.note == ClaudeSessionError.notInstalled.fallbackNote(for: .claude))
        // None: the question fails, saying why for the CLI.
        let none = converter(config, fake, apple: StubAppleModel(.deviceNotEligible))
        do {
            _ = try await final(none.generate(.question, input: "what is rust"))
            Issue.record("answered")
        } catch let error as ClaudeSessionError {
            #expect(error == .failed(ClaudeSessionError.notInstalled.description(for: .claude)))
        }
    }

    // MARK: - The settings document

    func service(_ json: String, platform: SettingsPlatform) throws -> SettingsService {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config-\(platform).json")
        try Data(json.utf8).write(to: url)
        return SettingsService(store: SettingsStore(configURL: url), platform: platform,
                               library: PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true)))
    }

    @Test func theDocumentsProviderFieldIsTheAI() async throws {
        try await withInterfaceLanguage("en") {
            let mac = try service(#"{"provider": "anthropic"}"#, platform: .mac)
            let field = try #require(mac.document().field("provider"))
            #expect(field.value == .string("anthropic"))
            #expect(field.choices?.prefix(4).map(\.value) == ["claudeSession", "codexSession", "antigravitySession", "kiroSession"].map { .string($0) })
            #expect(mac.document().field("questionBackend") == nil)  // folded into it
            // A CLI chosen: its id, the provider kept, the provider's own fields and Test Connection left out.
            #expect((try? mac.set("provider", to: .string("codexSession")).get()) != nil)
            let config = try Config.load(from: folder.appendingPathComponent("config-mac.json"))
            #expect(config.ai == .cli(.codex) && config.provider == .anthropic)
            let document = mac.document()
            #expect(document.field("provider")?.value == .string("codexSession"))
            #expect(document.field("anthropic.key") == nil && document.field("provider.test") == nil)
            #expect((try? mac.set("provider", to: .string("gemini")).get()) != nil)
            #expect(try Config.load(from: folder.appendingPathComponent("config-mac.json")).ai == .provider(.gemini))
            // Windows: no CLIs.
            let windows = try service(#"{"provider": "anthropic"}"#, platform: .windows)
            #expect(windows.document().field("provider")?.choices?.contains { $0.value == .string("claudeSession") } == false)
            #expect((try? windows.set("provider", to: .string("claudeSession")).get()) == nil)
        }
    }
}
