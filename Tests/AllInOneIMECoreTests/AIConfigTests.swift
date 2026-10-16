import Foundation
import Testing
@testable import AllInOneIMECore

/// `@config`: the answer read strictly, each change checked as Settings checks it and shown old → new, refused parts with
/// their reason, apply and undo through the config file, the prompt (its own, the others unchanged), the on-device model
/// first, and the keys in the panel.
struct AIConfigTests {
    var config: Config {
        var config = Config.default
        config.setOrder([OutputLanguage.english, OutputLanguage("ja"), .chinese])
        config.setOrder([Language.chinese, .english])
        config.redaction.customWords = ["Falcon"]
        return config
    }

    let apps = AIConfig.AppCatalog(apps: [
        .init(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"]),
        .init(bundleID: "com.apple.mail", names: ["Mail", "邮件"]),
        .init(bundleID: "com.microsoft.Word", names: ["Microsoft Word"]),
        .init(bundleID: "com.example.notes", names: ["Notes Pro"]),
        .init(bundleID: "com.apple.Notes", names: ["Notes", "备忘录"]),
        .init(bundleID: "com.other.Notes", names: ["Notes"]),
    ])

    func env(chinese: Bool = false, packs: Set<Language> = [.chinese], keys: Set<Provider> = []) -> AIConfig.Environment {
        AIConfig.Environment(packInstalled: { packs.contains($0) }, apps: apps, awsProfiles: { ["default", "work"] },
                             knownModels: { $0 == .anthropic ? ["claude-haiku-5-5", "claude-sonnet-5-5"] : $0 == .bedrock ? ["us.anthropic.claude-haiku-4-5-20251001-v1:0"] : [] },
                             offeredProviders: [.bedrock, .anthropic, .gemini, .openai], hasKey: { keys.contains($0) }, chinese: chinese)
    }

    func preview(_ json: String, _ config: Config? = nil, env: AIConfig.Environment? = nil) throws -> Result<AIConfig.Preview, AIConfig.Failure> {
        AIConfig.preview(try AIConfig.parse(json), config: config ?? self.config, environment: env ?? self.env())
    }

    /// Every row, refused ones too (a preview of refused rows only is no preview: one line).
    func rows(_ json: String, _ config: Config? = nil, env: AIConfig.Environment? = nil) throws -> [AIConfig.Row] {
        AIConfig.check(try AIConfig.parse(json), config: config ?? self.config, environment: env ?? self.env()).rows
    }

    // MARK: - Reading the answer

    @Test func theAnswerIsReadStrictly() throws {
        let proposal = try AIConfig.parse(#"{"changes": [{"key": "candidateLayout", "value": "vertical"}], "note": "ok"}"#)
        #expect(proposal == AIConfig.Proposal(changes: [.init(key: .setting(.candidateLayout), value: .string("vertical"))], note: "ok"))
        // A code fence around it is fine; nothing else is.
        #expect(try AIConfig.parse("```json\n{\"changes\": []}\n```").changes.isEmpty)
        for bad in ["", "sure!", "{\"changes\": []} thanks", #"{"changes": {}}"#, #"{"change": []}"#, #"{"changes": [], "extra": 1}"#,
                    #"{"changes": [{"key": "typeOut"}]}"#, #"{"changes": [{"key": "typeOut", "value": true, "why": "x"}]}"#,
                    #"{"changes": [{"key": 3, "value": true}]}"#, #"{"changes": [], "note": 3}"#, "[]"] {
            #expect(throws: AIConfig.ParseError.unreadable, "\(bad)") { try AIConfig.parse(bad) }
        }
        // A key that is no setting at all: the whole answer is refused.
        #expect(throws: AIConfig.ParseError.unknownKey("fontSize")) { try AIConfig.parse(#"{"changes": [{"key": "fontSize", "value": 3}]}"#) }
    }

    @Test func keysAreAllowedForbiddenOrSecret() {
        #expect(AIConfig.Key.parse("outputLanguages") == .setting(.outputLanguages))
        #expect(AIConfig.Key.parse("redaction.keys") == .setting(.redactionKeys))
        #expect(AIConfig.Key.parse("appProfiles.WeChat.inputLanguage") == .app("WeChat", .inputLanguage))
        #expect(AIConfig.Key.parse("appProfiles.com.tencent.xinWeChat.noAI") == .app("com.tencent.xinWeChat", .noAI))
        #expect(AIConfig.Key.parse("appProfiles.WeChat.fontSize") == .forbidden("appProfiles.WeChat.fontSize", secret: false))
        for key in ["customCommands", "extensionFolders", "plugins", "jargonFile", "maxTokens", "actionKey", "anthropic.effort", "extensionSources"] {
            #expect(AIConfig.Key.parse(key) == .forbidden(key, secret: false), "\(key)")
        }
        for key in ["apiKey", "anthropic.apiKey", "openai.key", "aws_secret_access_key", "hosted.token", "keychain"] {
            #expect(AIConfig.Key.parse(key) == .forbidden(key, secret: true), "\(key)")
        }
        #expect(AIConfig.Key.parse("colorScheme") == nil)
    }

    @Test func theSameKeyTwiceKeepsTheLast() throws {
        let proposal = try AIConfig.parse(#"{"changes": [{"key": "typeOut", "value": true}, {"key": "typeOut", "value": false}]}"#)
        #expect(proposal.changes == [.init(key: .setting(.typeOut), value: .bool(false))])
    }

    // MARK: - The preview

    @Test func outputLanguagesShowOldAndNew() throws {
        let rows = try rows(#"{"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}]}"#, env: env(chinese: true))
        #expect(rows.map { $0.text(chinese: true) } == ["翻译语言：英文、日语、中文 → 英文、法语"])
        #expect(rows.first?.edit == .outputLanguages([.english, OutputLanguage("fr")]))
        let english = try self.rows(#"{"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}]}"#)
        #expect(english.map { $0.text(chinese: false) } == ["Translation languages: English, Japanese, Chinese → English, French"])
    }

    @Test func languagesAreChecked() throws {
        func reason(_ json: String) throws -> String? {
            if case let .refused(reason)? = try self.rows(json, env: env(chinese: false)).first?.status { return reason }
            return nil
        }
        #expect(try reason(#"{"changes": [{"key": "outputLanguages", "value": ["en", "xx"]}]}"#) == "unknown language “xx”")
        #expect(try reason(#"{"changes": [{"key": "outputLanguages", "value": ["en", "fr", "de", "es", "it", "ja"]}]}"#) == "at most 5")
        #expect(try reason(#"{"changes": [{"key": "outputLanguages", "value": []}]}"#) == "at least one is needed")
        #expect(try reason(#"{"changes": [{"key": "outputLanguages", "value": "en"}]}"#) == "not a valid value")
        // A language whose pack isn't installed: refused, pointing to Settings, where it downloads.
        #expect(try reason(#"{"changes": [{"key": "inputLanguages", "value": ["zh", "en", "ko"]}]}"#)
                == "needs the Korean language pack (download it in Settings → Input)")
        #expect(try reason(#"{"changes": [{"key": "defaultInput", "value": "fr"}]}"#) == "French isn't one of your input languages")
        // French needs no pack; added, it can be the default in the same answer.
        let rows = try self.rows(#"{"changes": [{"key": "defaultInput", "value": "fr"}, {"key": "inputLanguages", "value": ["zh", "en", "fr"]}]}"#)
        #expect(rows.map(\.edit) == [.inputLanguages([.chinese, .english, .french]), .defaultInput(.french)])
    }

    @Test func valuesAreChecked() throws {
        let rows = try rows("""
            {"changes": [{"key": "typeOutRate", "value": 100}, {"key": "typeOut", "value": "yes"},
                         {"key": "candidateLayout", "value": "diagonal"}, {"key": "rewriteStyles", "value": ["简洁", "Shouty"]},
                         {"key": "region", "value": "mars-1"}, {"key": "awsProfile", "value": "nobody"},
                         {"key": "anthropic.model", "value": "claude-9"}, {"key": "openai.baseURL", "value": "http://example.com/v1"},
                         {"key": "useSelection", "value": false}]}
            """)
        #expect(rows.filter(\.isRefused).count == 8)
        #expect(rows.filter { !$0.isRefused }.map(\.edit) == [.flag(.useSelection, false)])
        #expect(rows.compactMap { if case let .refused(r) = $0.status { return r } else { return nil } }.contains("https:// addresses only"))
    }

    @Test func stylesTakeNamesTagsOrEnglishNames() throws {
        let rows = try rows(#"{"changes": [{"key": "rewriteStyles", "value": ["Casual", "FORMAL", "简洁", "casual"]}]}"#)
        #expect(rows.first?.edit == .rewriteStyles(["口语", "正式", "简洁"]))
        #expect(rows.first?.new == "Casual, Formal, Concise")
    }

    @Test func aRateIsRoundedAsTheSliderDoes() throws {
        #expect(try rows(#"{"changes": [{"key": "typeOutRate", "value": 7.6}]}"#).first?.edit == .typeOutRate(8))
        #expect(try rows(#"{"changes": [{"key": "typeOutRate", "value": 0.17}]}"#).first?.new == "6 s each")
    }

    @Test func whatIsAlreadySetIsLeftOut() throws {
        #expect(try preview(#"{"changes": [{"key": "candidateLayout", "value": "horizontal"}]}"#) == .failure(.alreadySet))
        #expect(try preview(#"{"changes": []}"#) == .failure(.notUnderstood))
        #expect(try preview(#"{"changes": [{"key": "customCommands", "value": []}]}"#) == .failure(.notAllowed))
        // One part refused, the rest applies.
        let mixed = try preview(#"{"changes": [{"key": "customCommands", "value": []}, {"key": "typeOut", "value": true}]}"#).get()
        #expect(mixed.rows.map(\.isRefused) == [false, true] && mixed.edits == [.flag(.typeOut, true)] && mixed.canApply)
    }

    @Test func aSecretIsNeverShown() throws {
        let found = try rows(#"{"changes": [{"key": "anthropic.apiKey", "value": "sk-ant-api03-SECRETSECRETSECRET"}, {"key": "typeOut", "value": true}]}"#)
        let refused = try #require(found.first { $0.isRefused })
        #expect(refused.label == "API key" && !refused.text(chinese: false).contains("SECRET") && refused.old == nil && refused.new == nil)
    }

    @Test func customWordsAreOnlyAdded() throws {
        let rows = try rows(#"{"changes": [{"key": "redaction.customWords.add", "value": ["falcon", "Osprey", " "]}]}"#)
        #expect(rows.first?.edit == .addWords(["Osprey"]) && rows.first?.text(chinese: false) == "Also hide these words: 1 word → + Osprey")
        // Setting the list as a whole (and so clearing it) is not on the allowlist.
        #expect(try preview(#"{"changes": [{"key": "redaction.customWords", "value": []}]}"#) == .failure(.notAllowed))
    }

    // MARK: - Apps

    @Test func appsAreFoundByNameOrBundleID() {
        #expect(apps.resolve("WeChat") == .found(bundleID: "com.tencent.xinWeChat", name: "WeChat"))
        #expect(apps.resolve("微信") == .found(bundleID: "com.tencent.xinWeChat", name: "WeChat"))
        #expect(apps.resolve("com.apple.MAIL") == .found(bundleID: "com.apple.mail", name: "Mail"))
        #expect(apps.resolve("Mail.app") == .found(bundleID: "com.apple.mail", name: "Mail"))
        #expect(apps.resolve("word") == .found(bundleID: "com.microsoft.Word", name: "Microsoft Word"))
        #expect(apps.resolve("Notes") == .ambiguous(["Notes", "Notes"]))
        #expect(apps.resolve("Photoshop") == .none)
        #expect(apps.search("note").map(\.bundleID) == ["com.example.notes", "com.apple.Notes", "com.other.Notes"])
    }

    @Test func anAppsSettingsGoUnderItsBundleID() throws {
        let rows = try rows(#"{"changes": [{"key": "appProfiles.微信.inputLanguage", "value": "zh"}, {"key": "appProfiles.Mail.rewriteStyles", "value": ["正式"]}]}"#,
                            env: env(chinese: true))
        #expect(rows.map { $0.text(chinese: true) } == ["按 App · WeChat · 开始的输入语言：跟全局一样 → 中文",
                                                        "按 App · Mail · 改写风格：跟全局一样 → 正式"])
        #expect(rows.map(\.edit) == [.app("com.tencent.xinWeChat", .inputLanguage(.chinese)), .app("com.apple.mail", .rewriteStyles(["正式"]))])
        // An app it can't tell, or two with that name: refused.
        let unknown = try self.rows(#"{"changes": [{"key": "appProfiles.Photoshop.typeOut", "value": true}, {"key": "appProfiles.Notes.noAI", "value": true}]}"#)
        #expect(unknown.allSatisfy { $0.isRefused })
        // Its starting language must be an input language, as in Settings → Apps.
        #expect(try self.rows(#"{"changes": [{"key": "appProfiles.Mail.inputLanguage", "value": "fr"}]}"#).first?.isRefused == true)
    }

    @Test func anAppWithSettingsKeepsItsKey() throws {
        var config = self.config
        config.appProfiles["com.Tencent.XinWeChat"] = AppProfile(typeOut: true)
        let found = try rows(#"{"changes": [{"key": "appProfiles.WeChat.typeOut", "value": null}]}"#, config)
        let row = try #require(found.first)
        #expect(row.edit == .app("com.Tencent.XinWeChat", .typeOut(nil)) && row.new == "Same as everywhere")
        AIConfig.apply([row.edit!], to: &config)
        #expect(config.appProfiles.isEmpty)  // left setting nothing: removed, as the menu does
    }

    // MARK: - Providers

    @Test func aProviderThatNeedsAKeyOpensItsField() throws {
        let preview = try preview(#"{"changes": [{"key": "provider", "value": "anthropic"}, {"key": "anthropic.model", "value": "claude-sonnet-5-5"}]}"#).get()
        #expect(preview.edits == [.provider(.anthropic), .model(.anthropic, "claude-sonnet-5-5")] && preview.needsKey == .anthropic)
        #expect(preview.rows.last?.text(chinese: false) == "API key (Claude API): enter it in Settings (never sent to the AI)")
        #expect(preview.changesProvider)
        // With a key saved: no key row.
        let keyed = try self.preview(#"{"changes": [{"key": "provider", "value": "anthropic"}]}"#, env: env(keys: [.anthropic])).get()
        #expect(keyed.needsKey == nil)
        // Bedrock: the profile must exist, the region be one.
        let bedrock = try self.rows(#"{"changes": [{"key": "awsProfile", "value": "work"}, {"key": "region", "value": "us-west-2"}]}"#)
        #expect(bedrock.map(\.edit) == [.awsProfile("work"), .region("us-west-2")])
        #expect(try self.preview(#"{"changes": [{"key": "provider", "value": "hosted"}]}"#) == .failure(.notAllowed))  // not offered here
    }

    @Test func keysTypedIntoTheSentenceAreDropped() {
        let dropped = AIConfig.droppingKeys("use claude with sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 please")
        #expect(dropped.dropped && dropped.provider == .anthropic && dropped.text == "use claude with please")
        #expect(!AIConfig.droppingKeys("output languages English and French").dropped)
        // The preview then has the key row, whatever the answer said.
        let preview = try? AIConfig.preview(AIConfig.Proposal(changes: [.init(key: .setting(.typeOut), value: .bool(true))]),
                                            config: config, environment: env(), droppedKey: (true, .anthropic)).get()
        #expect(preview?.needsKey == .anthropic && preview?.droppedKey == true)
    }

    // MARK: - Apply and undo

    @Test func applyThenUndoRestoresExactlyTheChangedKeys() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiconfig-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var before = config
        before.appProfiles["com.apple.mail"] = AppProfile(rewriteStyles: ["正式"])
        try before.write(to: url)
        let edits: [AIConfig.Edit] = [.outputLanguages([.english, OutputLanguage("fr")]), .defaultInput(.english), .flag(.typeOut, true),
                                      .typeOutRate(8), .addWords(["Osprey"]), .app("com.tencent.xinWeChat", .inputLanguage(.chinese)),
                                      .app("com.apple.mail", .rewriteStyles(nil)), .provider(.anthropic), .model(.anthropic, "claude-sonnet-5-5")]
        let now = Date()
        let applied = try AIConfig.applying(edits, at: url, now: now)
        let after = try Config.load(from: url)
        #expect(after.outputLanguages == [.english, OutputLanguage("fr")] && after.outputLanguage == .english)
        #expect(after.inputLanguages == [.english, .chinese] && after.defaultInput == .english)
        #expect(after.typeOut && after.typeOutRate == 8 && after.redaction.customWords == ["Falcon", "Osprey"])
        #expect(after.profile(for: "com.tencent.xinWeChat")?.inputLanguage == .chinese && after.profile(for: "com.apple.mail") == nil)
        #expect(after.provider == .anthropic && after.anthropic.model == "claude-sonnet-5-5")
        // Another change meanwhile (not @config's) stays.
        var meanwhile = after
        meanwhile.useSelection = false
        try meanwhile.write(to: url)
        let undone = try AIConfig.undo(applied, at: url, now: now.addingTimeInterval(60))
        #expect(undone)
        let restored = try Config.load(from: url)
        var wanted = before
        wanted.useSelection = false
        #expect(restored == wanted)
    }

    @Test func undoIsForTenMinutes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiconfig-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.write(to: url)
        let now = Date()
        let applied = try AIConfig.applying([.flag(.typeOut, true)], at: url, now: now)
        let late = try AIConfig.undo(applied, at: url, now: now.addingTimeInterval(AIConfig.undoWindow + 1))
        let stillOn = try Config.load(from: url).typeOut
        #expect(!late && stillOn)
        let inTime = try AIConfig.undo(applied, at: url, now: now.addingTimeInterval(AIConfig.undoWindow - 1))
        let off = try !Config.load(from: url).typeOut
        #expect(inTime && off)
    }

    @Test func neverAnInvalidConfig() throws {
        // Whatever passes the checks, applied, gives a config that reads back the same and stays in its limits.
        let preview = try preview("""
            {"changes": [{"key": "outputLanguages", "value": ["fr", "fr", "de"]}, {"key": "inputLanguages", "value": ["en", "en"]},
                         {"key": "rewriteStyles", "value": []}, {"key": "typeOutRate", "value": 40}]}
            """).get()
        var config = self.config
        AIConfig.apply(preview.edits, to: &config)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
        #expect(config.outputLanguages == [OutputLanguage("fr"), OutputLanguage("de")] && config.inputLanguages == [.english])
        #expect(config.rewriteStyles.isEmpty && config.typeOutRate == 40)
    }

    // MARK: - The prompt

    @Test func thePromptHoldsTheAllowlistAndCurrentValuesOnly() {
        var config = self.config
        config.awsProfile = "work"
        config.jargonFile = "~/secret/jargon.txt"
        config.customCommands = [CustomCommand(name: "deploy", type: .run, argv: ["./deploy.sh"])]
        let request = AIConfigPrompt.request("candidates in a column", context: .init(config: config, knownModels: [.anthropic: ["claude-haiku-5-5"]],
                                                                                     awsProfiles: ["default", "work"]))
        let system = request.system.map(\.text).joined()
        #expect(request.messages.map(\.content.first?.text) == ["candidates in a column"])
        #expect(system.contains("outputLanguages:") && system.contains(#"now ["en","ja","zh"]"#) && system.contains("candidateLayout"))
        #expect(system.contains("\"claude-haiku-5-5\"") && system.contains("\"work\""))
        // Never the hidden words, nor anything off the allowlist.
        #expect(!system.contains("Falcon") && system.contains("1 words (not shown)"))
        #expect(!system.contains("deploy") && !system.contains("jargon.txt") && !system.contains("maxTokens"))
        // A refine: the answer and the instruction after it.
        let refine = AIConfigPrompt.request("x", context: .init(config: config),
                                            turns: [.init(answer: ConversionResult(versions: [CandidateLine("{\"changes\": []}")]), instruction: "also German")])
        #expect(refine.messages.map(\.role) == ["user", "assistant", "user"] && refine.messages.last?.content.first?.text == "<refine>also German</refine>")
    }

    @Test func theOtherPromptsAreUnchanged() throws {
        // `RefineTests` checks every normal request against release 0.6.3's; @config's own is none of them.
        let url = try #require(Bundle.module.url(forResource: "prompts-release-0.6.3", withExtension: "json", subdirectory: "Fixtures"))
        let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        // @question's gained the live-data rule since (`RefineTests`); without it, every request is as 0.6.3 built it.
        let now = try JSONSerialization.jsonObject(with: PromptGolden.json(withoutLiveDataRule: true)) as? [String: Any]
        #expect(golden.map { NSDictionary(dictionary: $0) } == now.map { NSDictionary(dictionary: $0) })
        let all = String(decoding: try PromptGolden.json(), as: UTF8.self)
        #expect(!all.contains("AllInOneIME, an input method on a Mac, as the user describes"))
    }

    @Test func theOnDeviceSchemaMatchesTheAllowlist() {
        let schema = AIConfigPrompt.schema(.init(config: config, knownModels: [.anthropic: ["claude-haiku-5-5"]], awsProfiles: ["default"]))
        guard case let .object(_, properties) = schema, case let .array(.choice(_, choices), _, _)? = properties.first?.schema else {
            Issue.record("not a list of choices")
            return
        }
        var keys: [String] = []
        for case let .object(_, fields) in choices {
            if case let .strings(_, names)? = fields.first?.schema { keys += names }
        }
        // Every key it can write is one the strict reader takes.
        #expect(!keys.isEmpty && keys.allSatisfy { AIConfig.Key.parse($0.replacingOccurrences(of: ".*.", with: ".WeChat.")) != nil })
        #expect(Set(keys).isSuperset(of: ["outputLanguages", "typeOut", "provider", "awsProfile", "anthropic.model", "appProfiles.*.inputLanguage"]))
        // An app's setting comes back into its key.
        let canonical = AIConfigPrompt.canonical(#"{"changes": [{"key": "appProfiles.*.inputLanguage", "app": "WeChat", "value": "zh"}]}"#)
        #expect((try? AIConfig.parse(canonical))?.changes == [.init(key: .app("WeChat", .inputLanguage), value: .string("zh"))])
    }

    // MARK: - The request

    final class GuidedStub: AppleGuidedBackend, @unchecked Sendable {
        let availability: AppleModelAvailability
        let contextSize = 8192
        let supportedLanguages: Set<String> = ["en", "zh"]
        let answer: String
        var schemas: [GuidedSchema] = []
        var tools: [String] = []
        var prompts: [String] = []

        init(_ availability: AppleModelAvailability = .available, answer: String) {
            self.availability = availability
            self.answer = answer
        }

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { $0.finish(throwing: AppleModelError.failed("plain path used")) }
        }

        func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
            schemas.append(schema)
            self.tools = tools.map(\.name)
            prompts.append(request.prompt)
            return answer
        }
    }

    @Test func onDeviceFirstWhateverTheProvider() async throws {
        let stub = GuidedStub(answer: #"{"changes": [{"key": "appProfiles.*.typeOut", "app": "WeChat", "value": true}]}"#)
        let service = AIConfigService(client: ChatClient(apple: stub))
        var config = self.config
        config.provider = .anthropic  // no key anywhere: never asked
        let tools = AIConfigService.Tools(findApps: { _ in "" }, awsProfiles: { "" }, languagePacks: { "" })
        let answer = try await service.ask("type out in WeChat", context: .init(config: config), tools: tools)
        #expect(answer.onDevice && !answer.fromCache && stub.schemas.count == 1 && stub.tools == ["findApps", "awsProfiles", "languagePacks"])
        #expect(try AIConfig.parse(answer.text).changes == [.init(key: .app("WeChat", .typeOut), value: .bool(true))])
        // Asked again: kept, like other conversions.
        let again = try await service.ask("type out in WeChat", context: .init(config: config), tools: tools)
        #expect(again.fromCache && stub.schemas.count == 1)
    }

    @Test func theUsersHiddenWordsAreHiddenHereToo() async throws {
        let stub = GuidedStub(answer: #"{"changes": [{"key": "redaction.customWords.add", "value": ["[ITEM_1]"]}]}"#)
        let service = AIConfigService(client: ChatClient(apple: stub))
        var config = self.config
        config.redaction = RedactionSettings(enabled: true, customWords: ["Falcon"])
        let answer = try await service.ask("hide Falcon from the AI", context: .init(config: config))
        #expect(stub.prompts.first?.contains("Falcon") == false && answer.hidden == 1 && answer.text.contains("Falcon"))
    }

    @Test func withoutTheOnDeviceModelTheChosenProvider() async throws {
        let stub = GuidedStub(.appleIntelligenceNotEnabled, answer: "")
        var config = self.config
        config.provider = .apple
        let service = AIConfigService(client: ChatClient(apple: stub))
        await #expect(throws: AppleModelError.unavailable(.appleIntelligenceNotEnabled)) {
            try await service.ask("candidates in a column", context: .init(config: config))
        }
        #expect(!service.onDevice && stub.schemas.isEmpty)
    }

    // MARK: - Keys in the panel

    func drafted(_ text: String) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        for ch in "config" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        for ch in text { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
        return c
    }

    let answer = #"{"changes": [{"key": "candidateLayout", "value": "vertical"}]}"#

    func previewed() throws -> (Composer, AIConfig.Preview) {
        let c = drafted("column")
        #expect(c.draft == "@config column")
        let started = c.handleKeyDown(enterKey).effects
        #expect(started.first == .startCommand(.config, input: "column", id: 1))
        let preview = try preview(answer).get()
        _ = c.receiveConfig(preview, lines: preview.rows.map { $0.text(chinese: false) }, answer: answer, id: 1)
        return (c, preview)
    }

    @Test func nothingAfterItDoesNothing() {
        let c = drafted("")
        #expect(c.handleKeyDown(enterKey).effects.isEmpty && c.phase == .drafting)
    }

    @Test func enterOrOneAppliesAndNothingIsInserted() throws {
        let (c, preview) = try previewed()
        #expect(c.phase == .choosing && c.choices.map(\.text) == ["Candidate layout: Horizontal → Vertical"])
        #expect(c.handleKeyDown(spaceKey).effects.isEmpty)  // Space doesn't apply (⏎ is the action key)
        #expect(c.handleKeyDown(enterKey).effects == [.applyConfig(preview), .showPanel])
        _ = c.configApplied("Changed 1 setting")
        #expect(c.choices.map(\.text) == ["Changed 1 setting"])
        _ = c.configStatus("✓ Connection works")
        #expect(c.choices.map(\.text) == ["Changed 1 setting", "✓ Connection works"])
        // ⌘Z undoes it and closes; nothing was ever inserted.
        let undo = c.handleKeyDown(k("z", mods: .command)).effects
        #expect(undo.last == .undoConfig && commits(undo).isEmpty && c.phase == .idle)
        let (d, p) = try previewed()
        #expect(d.handleKeyDown(k("1")).effects == [.applyConfig(p), .showPanel])
    }

    let shiftEnter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)

    @Test func escCancelsAndTypingRefines() throws {
        let (c, _) = try previewed()
        #expect(commits(c.handleKeyDown(escKey)).isEmpty && c.phase == .drafting && c.draft == "@config column")
        let (d, _) = try previewed()
        for ch in "also" { _ = d.handleKeyDown(k(String(ch))) }
        #expect(d.refineText == "also" && d.phase == .choosing)
        // ⇧⏎ sends the line (⏎ would apply the proposal, the line going with it).
        let effects = d.handleKeyDown(shiftEnter).effects
        let refine = effects.compactMap { if case let .startRefine(r, _) = $0 { return r } else { return nil } }.first
        #expect(refine?.request == .command(.config, input: "column") && refine?.turns.first?.answer.versions.first?.text == answer)
        // Its answer replaces the preview; Esc goes back to the one before.
        let next = #"{"changes": [{"key": "typeOut", "value": true}]}"#
        let p2 = try preview(next).get()
        _ = d.receiveConfig(p2, lines: ["Type results out: off → on"], answer: next, id: 2)
        #expect(d.choices.map(\.text) == ["Type results out: off → on"])
        _ = d.handleKeyDown(escKey)
        #expect(d.choices.map(\.text) == ["Candidate layout: Horizontal → Vertical"])
    }

    @Test func aFailureIsOneLineAndNothingGoesIn() throws {
        let c = drafted("make it pink")
        _ = c.handleKeyDown(enterKey)
        _ = c.fail("Couldn't turn that into a setting", id: 1)
        #expect(c.phase == .failed("Couldn't turn that into a setting"))
        let back = c.handleKeyDown(enterKey).effects
        #expect(commits(back).isEmpty && c.phase == .drafting)
    }

    @Test func undoIsTypedToo() {
        let c = drafted("undo")
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.contains(.undoConfig) && commits(effects).isEmpty && c.phase == .idle)
    }

    @Test func notInAnAppWithNoAI() {
        let c = drafted("column")
        c.aiRefusal = { "AI is off in this app" }
        #expect(c.handleKeyDown(enterKey).effects.contains(.notice("AI is off in this app")) && c.phase == .drafting)
    }

    // MARK: - Secrets and the ⇧⏎ rule

    let key = "sk-ant-api03-Zx8Qw2Lm4Np6Rt0Vb3Yc5Hd7Jf9Kg1Ms2Pu4Wx6Ab8Cd"

    @Test func aValueThatLooksLikeAKeyIsNeverQuoted() throws {
        let json = """
            {"changes": [{"key": "outputLanguages", "value": ["\(key)"]}, {"key": "rewriteStyles", "value": ["\(key)"]},
                         {"key": "appProfiles.\(key).typeOut", "value": true}, {"key": "openai.baseURL", "value": "https://example.com/v1?k=\(key)"},
                         {"key": "redaction.customWords.add", "value": ["\(key)"]}, {"key": "typeOut", "value": true}],
             "note": "your key \(key) is set"}
            """
        for chinese in [false, true] {
            let all = try rows(json, env: env(chinese: chinese))
            let lines = all.map { $0.text(chinese: chinese) }
            #expect(lines.allSatisfy { !$0.contains(key) } && all.filter(\.isRefused).count == 5, "\(lines)")
            #expect(lines.contains(chinese ? "✕ 翻译语言：看起来像密钥的值被拒绝了（不显示）" : "✕ Translation languages: a value that looks like a key was refused"))
            #expect(all.allSatisfy { !$0.key.contains(key) })
        }
        // The rest still applies; the note shows without the key.
        let preview = try preview(json).get()
        #expect(preview.edits == [.flag(.typeOut, true)] && preview.note == "your key ••• is set")
    }

    @Test func keysInARefinesLineNeverGoOut() async throws {
        let stub = GuidedStub(answer: #"{"changes": []}"#)
        let service = AIConfigService(client: ChatClient(apple: stub))
        let turns = [Refinement.Turn(answer: ConversionResult(versions: [CandidateLine("{\"changes\": []}")]), instruction: "use Claude with \(key)")]
        _ = try await service.ask("candidates in a column \(key)", turns: turns, context: .init(config: config))
        #expect(stub.prompts.allSatisfy { !$0.contains(key) } && stub.prompts.first == "<refine>use Claude with</refine>")
    }

    @Test func shiftReturnRefinesOnlyWithALine() throws {
        // Nothing typed: ⇧⏎ does nothing (never "@config …" as typed), on the preview and on a failure.
        let (c, _) = try previewed()
        #expect(c.handleKeyDown(shiftEnter).effects.isEmpty && c.phase == .choosing)
        let failed = drafted("pink")
        _ = failed.handleKeyDown(enterKey)
        _ = failed.fail("Couldn't turn that into a setting", id: 1)
        #expect(commits(failed.handleKeyDown(shiftEnter).effects).isEmpty)
        // A line typed: ⏎ applies the proposal (the line goes with it); ⇧⏎ refines (above).
        let (d, preview) = try previewed()
        for ch in "also" { _ = d.handleKeyDown(k(String(ch))) }
        #expect(d.handleKeyDown(enterKey).effects == [.applyConfig(preview), .showPanel])
    }

    // MARK: - Sign-off review fixes

    func tempFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiconfig-\(UUID().uuidString).json")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func applyAndUndoKeepUnknownKeys() throws {
        // A key this version doesn't know (a later version's, another branch's) survives apply and undo.
        var base = config
        base.typeOut = false
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        var file = encoded
        file["futureKey"] = ["nested": [1, 2], "on": true]
        let url = try tempFile(String(decoding: try JSONSerialization.data(withJSONObject: file), as: UTF8.self))
        defer { try? FileManager.default.removeItem(at: url) }
        func object() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any] }
        let applied = try AIConfig.applying([.flag(.typeOut, true), .outputLanguages([OutputLanguage("fr")])], at: url)
        var now = try object()
        #expect((now["futureKey"] as? [String: Any])?["on"] as? Bool == true && now["typeOut"] as? Bool == true)
        // The one in use goes with its list.
        #expect(now["outputLanguages"] as? [String] == ["fr"] && now["outputLanguage"] as? String == "fr")
        _ = try AIConfig.undo(applied, at: url)
        now = try object()
        #expect((now["futureKey"] as? [String: Any])?["nested"] as? [Int] == [1, 2] && now["typeOut"] as? Bool == false)
        #expect(now["outputLanguages"] as? [String] == ["en", "ja", "zh"])
        // Only the keys that changed are written: the others stay as the file had them.
        #expect(AIConfig.changedKeys(base, { var c = base; c.typeOut = true; return c }()) == ["typeOut"])
    }

    @Test func undoLeavesAKeyChangedSince() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiconfig-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.write(to: url)
        let applied = try AIConfig.applying([.flag(.typeOut, true), .candidateLayout(.vertical)], at: url)
        // Settings changed the layout back meanwhile.
        var changed = try Config.load(from: url)
        changed.candidateLayout = .horizontal
        try changed.write(to: url)
        let report = try #require(try AIConfig.undoing(applied, at: url))
        #expect(report.undone == 1 && report.skipped == [.candidateLayout(.horizontal)])
        let after = try Config.load(from: url)
        #expect(!after.typeOut && after.candidateLayout == .horizontal)
        #expect(AIConfig.Text(chinese: false).undone(skipped: report.skipped) == "Undone; changed since, left as is: Candidate layout")
    }

    @Test func awsProfilesAreNamesAndRegionsOnly() {
        let config = """
            [default]
            region = us-east-1
            [profile sso-dev]
            sso_session = corp
            sso_account_id = 123456789012
            region = eu-west-1
            [profile assumed]
            role_arn = arn:aws:iam::123:role/x
            source_profile = default
            region = ap-northeast-1
            [profile tool]
            credential_process = /usr/local/bin/creds --secret
            region = us-west-2
            [sso-session corp]
            sso_region = us-east-1
            """
        let credentials = """
            [default]
            aws_access_key_id = AKIAZX8QW2LM4NP6RT0V
            aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            [static]
            aws_access_key_id = AKIAZX8QW2LM4NP6RT0X
            region = sa-east-1
            """
        let profiles = AIConfig.awsProfiles(config: config, credentials: credentials)
        #expect(profiles == [.init(name: "default", region: "us-east-1"), .init(name: "assumed", region: "ap-northeast-1"),
                             .init(name: "sso-dev", region: "eu-west-1"), .init(name: "static", region: "sa-east-1"),
                             .init(name: "tool", region: "us-west-2")])
        let described = "\(profiles)"
        #expect(!described.contains("AKIA") && !described.contains("wJalr") && !described.contains("creds") && !described.contains("corp"))
    }

    @Test func profileNamesGoToACloudProviderOnlyForAWS() {
        var config = self.config
        config.awsProfile = "work-account"
        let hidden = AIConfigPrompt.request("candidates in a column", context: .init(config: config, awsProfiles: ["default", "work-account"],
                                                                                    showsAWSProfile: false)).system.map(\.text).joined()
        #expect(!hidden.contains("work-account") && !hidden.contains("\"default\""))
        let shown = AIConfigPrompt.request("use bedrock with my work profile", context: .init(config: config, awsProfiles: ["default", "work-account"]))
            .system.map(\.text).joined()
        #expect(shown.contains("\"work-account\""))
        #expect(AIConfig.mentionsAWS("use Bedrock") && AIConfig.mentionsAWS("switch my AWS profile") && !AIConfig.mentionsAWS("candidates in a column"))
    }

    @Test func theBaseURLIsShownWithoutSecrets() {
        var config = self.config
        config.openai.baseURL = "https://user:pass@api.example.com/v1?api_key=abc&x=1#frag"
        let system = AIConfigPrompt.request("x", context: .init(config: config)).system.map(\.text).joined()
        #expect(system.contains(#"now "https://api.example.com/v1""#) && !system.contains("user:pass") && !system.contains("api_key"))
        #expect(!AIConfigPrompt.shownURL("https://api.example.com/\(key)/v1").contains(key))
    }

    @Test func wordsAddedAreLimited() throws {
        let many = (1...25).map { "word\($0)" } + ["two\nlines", String(repeating: "ab ", count: 22)]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["changes": [["key": "redaction.customWords.add", "value": many]]]),
                          as: UTF8.self)
        let all = try rows(json)
        #expect(all.count == 2 && all[0].edit == .addWords((1...20).map { "word\($0)" }))
        #expect(all[1].text(chinese: false)
                == "✕ Also hide these words: 7 more not added: at most 20 at a time, each one line of at most 64 characters")
    }

    @Test func aBaseURLOnlyFromTheUserOrAKnownService() throws {
        let made = #"{"changes": [{"key": "openai.baseURL", "value": "https://evil.example.net/v1"}]}"#
        #expect(try rows(made).first?.text(chinese: false) == "✕ Base URL: type the address yourself")
        var typed = env()
        typed.typedText = "use my server https://evil.example.net/v1"
        #expect(try rows(made, env: typed).first?.edit == .baseURL("https://evil.example.net/v1"))
        let known = #"{"changes": [{"key": "openai.baseURL", "value": "https://api.deepseek.com/v1"}]}"#
        #expect(try rows(known).first?.edit == .baseURL("https://api.deepseek.com/v1"))
    }

    @Test func theRefineFooterSaysWhatTheKeysDo() throws {
        // ⏎ applies the proposal shown even with a refine line typed; ⇧⏎ sends the line (`shiftReturnRefinesOnlyWithALine`).
        let (d, preview) = try previewed()
        for ch in "also" { _ = d.handleKeyDown(k(String(ch))) }
        #expect(d.refineLine == "also")
        #expect(d.handleKeyDown(enterKey).effects == [.applyConfig(preview), .showPanel])
    }
}
