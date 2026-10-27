import AllInOneIMECore
import AppKit

/// The on-device model with the context it reports set (`contextSize`: macOS 26's 4096 on a Mac with macOS 27's 8192), and
/// what Settings → Assistant sent it: the model's own count of each request, the answer's limit, and what the answer
/// took of the context as the framework counted it while answering (`usage`, macOS 27), apart from the plan's count.
final class CappedGuidedModel: AppleGuidedBackend, @unchecked Sendable {
    let model: any AppleGuidedBackend
    let contextSize: Int
    private(set) var sent: [(tokens: Int?, maximumResponseTokens: Int, usage: GuidedUsage?)] = []

    init(_ model: any AppleGuidedBackend, contextSize: Int) {
        self.model = model
        self.contextSize = contextSize
    }

    var availability: AppleModelAvailability { model.availability }
    var supportedLanguages: Set<String> { model.supportedLanguages }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> { model.respond(to: request) }

    func tokenCount(of request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async -> Int? {
        await model.tokenCount(of: request, schema: schema, tools: tools)
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        let tokens = await model.tokenCount(of: request, schema: schema, tools: tools)
        let index = await MainActor.run {
            sent.append((tokens, request.maximumResponseTokens, nil))
            return sent.count - 1
        }
        let (json, usage) = try await model.respondWithUsage(to: request, schema: schema, tools: tools)
        await MainActor.run { sent[index].usage = usage }
        return json
    }

    /// The last answer's use of the context fits `contextSize` as the framework counted it: the whole transcript after
    /// the answer (its tools' calls too), else what it read and wrote. Before macOS 27, which doesn't say, true.
    var lastFits: Bool {
        guard #available(macOS 27, *) else { return true }
        guard let usage = sent.last?.usage else { return false }
        return (usage.transcript ?? usage.input + usage.output) <= contextSize
    }

    /// The last request as the plan counted it and as the framework did: "3067 + 779 planned; 2990 read, 41 written, 3031 in all".
    var lastLine: String {
        guard let last = sent.last else { return "nothing sent" }
        let planned = "\(last.tokens ?? -1) + \(last.maximumResponseTokens) planned"
        guard let usage = last.usage else { return planned }
        return planned + "; \(usage.input) read, \(usage.output) written, \(usage.transcript.map(String.init) ?? "?") in all"
    }
}

extension SelfTest {
    /// Settings → Assistant on Apple Intelligence on this Mac with a long-time user's config (many apps with settings of
    /// their own, five languages each way, every style): with the context macOS 26 has (4096 tokens) and this Mac's own,
    /// the request is fitted to it and answered, in English and Chinese, through the page too, within the context as the
    /// plan counted it and (macOS 27) as the framework counted the answer; a request too long for any fit says what to
    /// do, in the interface language, and isn't sent to the model. Only where the model is available; no provider is
    /// asked (none has credentials here), the user's config file is never touched.
    static func testAssistantOnDevice(snapshotDirectory: URL) {
        let real = AppleModel.system
        section("Settings → Assistant on Apple Intelligence on this Mac: a large config fitted to its context (\(real.availability.rawValue))")
        guard real.availability == .available, let guided = real as? any AppleGuidedBackend else {
            print("  skipped: the on-device model isn't available here")
            return
        }
        let realBefore = try? Data(contentsOf: Config.userURL)
        defer { check((try? Data(contentsOf: Config.userURL)) == realBefore, "Assistant on device: the user's config file was not touched") }
        let config = longTimeUsersConfig()
        let apps = AIConfig.AppCatalog(apps: [.init(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"])])
        let context = AIConfigPrompt.Context(config: config, knownModels: AIConfigSession.knownModels(), awsProfiles: ["default"],
                                             offeredProviders: Provider.offered, installedPacks: [.chinese], apps: apps)
        let tools = AIConfigService.Tools(findApps: { query in apps.search(query).map { "\($0.name): \($0.bundleID)" }.joined(separator: "\n") },
                                          awsProfiles: { "default (region us-east-1)" }, languagePacks: { "zh (Chinese): installed" })
        // No provider is ever asked: none has credentials or a key here.
        func service(_ model: CappedGuidedModel) -> AIConfigService {
            AIConfigService(client: ChatClient(apple: model), loadCredentials: { _ in throw AWSConfigError.profileNotFound("selftest") },
                            loadKey: { _, _ in nil })
        }
        func ask(_ model: CappedGuidedModel, _ sentence: String) -> Result<AIConfigService.Answer, Error>? {
            var result: Result<AIConfigService.Answer, Error>?
            let service = service(model)
            Task { @MainActor in result = await Result { try await service.ask(sentence, context: context, tools: tools) } }
            _ = pump(timeout: 120) { result != nil }
            return result
        }

        for contextSize in [4096, guided.contextSize] {
            for sentence in ["candidates in a column", "微信里用英文输入", "use Bedrock"] {
                let model = CappedGuidedModel(guided, contextSize: contextSize)
                let result = ask(model, sentence)
                let sent = model.sent.last
                // Planned within the context by the plan's count; and within it as the framework counted the answer, where
                // it says (macOS 27): the context the request and the answer took, the tools' calls too.
                let planned = sent.map { ($0.tokens ?? 0) + $0.maximumResponseTokens <= contextSize } ?? false
                switch result {
                case let .success(answer):
                    check(answer.onDevice && planned && model.lastFits && (try? AIConfig.parse(answer.text)) != nil,
                          "\(contextSize) tokens, “\(sentence)”: answered on the device within its context (\(model.lastLine)): "
                              + "\(answer.text.prefix(160))")
                case let .failure(error):
                    check(false, "\(contextSize) tokens, “\(sentence)”: failed: \(error)")
                case nil:
                    check(false, "\(contextSize) tokens, “\(sentence)”: no answer in 2 minutes")
                }
            }
        }

        // Through the page with macOS 26's context: a preview (or the line that says why there is none), never an error.
        let rig = AssistantRig(snapshotDirectory, name: "assistant-on-device.json", config: config)
        let pickedBefore = UIText.choice
        UIText.choice = "zh"
        defer {
            rig.restore()
            UIText.choice = pickedBefore
        }
        let capped = CappedGuidedModel(guided, contextSize: 4096)
        AIConfigSession.service = service(capped)
        let models = AIConfigSession.knownModels()
        AIConfigSession.environment = { typed in
            AIConfig.Environment(apps: apps, awsProfiles: { ["default"] }, knownModels: { models[$0] ?? [] },
                                 hasKey: { _ in false }, chinese: true, typedText: typed)
        }
        let assistant = AssistantModel()
        assistant.request = "候选竖排"
        assistant.sendRequest()
        _ = pump(timeout: 120) { !assistant.working }
        let text = AIConfig.Text(language: "zh-Hans")
        let lines = [AIConfig.Failure.notUnderstood, .notAllowed, .alreadySet, .unclearSetting].map(text.failure)
        check(capped.sent.count == 1 && capped.lastFits && (assistant.preview != nil || assistant.message.map(lines.contains) == true),
              "the page with a 4096-token context (\(capped.lastLine)): "
                  + (assistant.preview != nil ? "a preview (\(assistant.lines.joined(separator: "; ")))" : assistant.message ?? "nothing"))

        // Too long for any fit: not sent to the model; the line says what to do, in the interface language.
        let long = CappedGuidedModel(guided, contextSize: 4096)
        AIConfigSession.service = service(long)
        assistant.request = String(repeating: "请把候选改成竖排，", count: 500)
        assistant.sendRequest()
        _ = pump(timeout: 60) { !assistant.working }
        check(long.sent.isEmpty && assistant.message == text.tooLong(notSetUp: .bedrock),
              "a request too long for the context isn't sent to the model, and says what to do: \(assistant.message ?? "-")")
    }

    /// A long-time user's config: many apps with settings of their own, five languages each way, every style, hidden words.
    private static func longTimeUsersConfig() -> Config {
        var config = settings
        config.provider = .bedrock
        config.candidateLayout = .horizontal
        config.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja"), OutputLanguage("fr"), OutputLanguage("de")])
        config.setOrder([Language.chinese, .english, .french, .korean, .hindi])
        config.rewriteStyles = RewriteStyle.catalog.map(\.name)
        let styles = RewriteStyle.catalog.map(\.name)
        config.appProfiles = [:]
        for index in 0..<250 {
            let id = index == 0 ? "com.tencent.xinWeChat" : "com.example.selftest.app\(index)"
            // What an earlier version set (never shown to the model) and what can be set here (shown).
            config.appProfiles[id] = AppProfile(inputLanguage: Language.allCases[index % Language.allCases.count],
                                                rewriteStyles: Array(styles.prefix(1 + index % 3)), typeOut: index % 2 == 0,
                                                suggestionsInsert: index % 2 == 0 ? .title : .titleAndLink)
        }
        config.redaction = RedactionSettings(enabled: true, customWords: (0..<50).map { "SelfTestWord\($0)" })
        return config
    }

    /// Autocomplete turned on and off in a sentence on Settings → Assistant's page, on Apple Intelligence on this Mac, in
    /// the Chinese interface, with the self-test's config and a long-time user's, autocomplete on and off: the bug as
    /// reported ("我要把 auto complete 关闭" and "… 打开" both said "Already set that way": the model answered with the
    /// setting as it was). A sentence that only turns it is done as it says without the model; one that says more is
    /// answered by the model, Autocomplete as it says whatever the model wrote for it. Only where the model is available;
    /// the page writes the self-test's own config file, never the user's.
    static func testAssistantAutocompleteOnDevice(snapshotDirectory: URL) {
        let real = AppleModel.system
        section("Settings → Assistant on Apple Intelligence on this Mac: Autocomplete on and off in a sentence (\(real.availability.rawValue))")
        guard real.availability == .available, let guided = real as? any AppleGuidedBackend else {
            print("  skipped: the on-device model isn't available here")
            return
        }
        let realBefore = try? Data(contentsOf: Config.userURL)
        defer { check((try? Data(contentsOf: Config.userURL)) == realBefore, "Assistant Autocomplete: the user's config file was not touched") }
        var small = settings
        small.candidateLayout = .horizontal
        let rig = AssistantRig(snapshotDirectory, name: "assistant-autocomplete.json", config: small)
        let pickedBefore = UIText.choice
        UIText.choice = "zh"
        defer {
            rig.restore()
            UIText.choice = pickedBefore
        }
        let text = AIConfig.Text(language: "zh-Hans")
        let assistant = AssistantModel()
        func send(_ sentence: String, config: Config) -> CappedGuidedModel {
            try? config.write(to: rig.url)
            let model = CappedGuidedModel(guided, contextSize: guided.contextSize)
            AIConfigSession.service = AIConfigService(client: ChatClient(apple: model),
                                                      loadCredentials: { _ in throw AWSConfigError.profileNotFound("selftest") },
                                                      loadKey: { _, _ in nil })
            assistant.reset()
            assistant.request = sentence
            assistant.sendRequest()
            _ = pump(timeout: 120) { !assistant.working }
            return model
        }
        let shown = { assistant.preview != nil ? "a preview (\(assistant.lines.joined(separator: "; ")))" : assistant.message ?? "nothing" }
        for (name, base) in [("the self-test's config", small), ("a long-time user's config", longTimeUsersConfig())] {
            for now in [false, true] {
                var config = base
                config.autocomplete = now
                for (sentence, on) in [("我要把 auto complete 打开", true), ("我要把 auto complete 关闭", false), ("打开续写", true),
                                       ("关掉自动补全", false), ("turn on autocomplete", true), ("disable auto-complete", false)] {
                    let model = send(sentence, config: config)
                    let done = on == now ? assistant.preview == nil && assistant.message == text.failure(.alreadySet)
                        : assistant.preview?.edits == [.autocomplete(on)]
                    check(done && model.sent.isEmpty, "\(name), autocomplete \(now ? "on" : "off"), “\(sentence)”: "
                              + (on == now ? "already so" : "turned \(on ? "on" : "off")") + " without the model: \(shown())")
                }
                // Saying more: the model answers; Autocomplete as the sentence says, whatever it wrote for it.
                let sentence = now ? "关闭续写，候选竖排" : "打开续写，候选竖排"
                let model = send(sentence, config: config)
                let edits = assistant.preview?.edits ?? []
                check(model.sent.count == 1 && edits.contains(.autocomplete(!now)) && !edits.contains(.autocomplete(now)),
                      "\(name), autocomplete \(now ? "on" : "off"), “\(sentence)”: answered on the device (\(model.lastLine)), "
                          + "Autocomplete turned \(now ? "off" : "on"): \(shown())")
                if !edits.contains(.candidateLayout(.vertical)) {
                    print("  ⚠︎ the model left out the candidates in a column for “\(sentence)”: its slip, not checked")
                }
            }
        }
    }
}
