import AllInOneIMECore
import AppKit

/// The on-device model with the context it reports set (`contextSize`: macOS 26's 4096 on a Mac with macOS 27's 8192), and
/// what Settings → Assistant sent it: the model's own count of each request, and the answer's limit.
final class CappedGuidedModel: AppleGuidedBackend, @unchecked Sendable {
    let model: any AppleGuidedBackend
    let contextSize: Int
    private(set) var sent: [(tokens: Int?, maximumResponseTokens: Int)] = []

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
        await MainActor.run { sent.append((tokens, request.maximumResponseTokens)) }
        return try await model.respond(to: request, schema: schema, tools: tools)
    }
}

extension SelfTest {
    /// Settings → Assistant on Apple Intelligence on this Mac with a long-time user's config (many apps with settings of
    /// their own, five languages each way, every style): with the context macOS 26 has (4096 tokens) and this Mac's own,
    /// the request is fitted to it and answered, in English and Chinese, through the page too; a request too long for any
    /// fit says what to do, in the interface language, and isn't sent to the model. Only where the model is available;
    /// no provider is asked (none has credentials here), the user's config file is never touched.
    static func testAssistantOnDevice(snapshotDirectory: URL) {
        let real = AppleModel.system
        section("Settings → Assistant on Apple Intelligence on this Mac: a large config fitted to its context (\(real.availability.rawValue))")
        guard real.availability == .available, let guided = real as? any AppleGuidedBackend else {
            print("  skipped: the on-device model isn't available here")
            return
        }
        let realBefore = try? Data(contentsOf: Config.userURL)
        defer { check((try? Data(contentsOf: Config.userURL)) == realBefore, "Assistant on device: the user's config file was not touched") }
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
            config.appProfiles[id] = AppProfile(inputLanguage: Language.allCases[index % Language.allCases.count],
                                                rewriteStyles: Array(styles.prefix(1 + index % 3)), typeOut: index % 2 == 0)
        }
        config.redaction = RedactionSettings(enabled: true, customWords: (0..<50).map { "SelfTestWord\($0)" })
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
            for sentence in ["candidates in a column", "微信里用英文输入"] {
                let model = CappedGuidedModel(guided, contextSize: contextSize)
                let result = ask(model, sentence)
                let sent = model.sent.last
                let fits = sent.map { ($0.tokens ?? 0) + $0.maximumResponseTokens <= contextSize } ?? false
                switch result {
                case let .success(answer):
                    check(answer.onDevice && fits && (try? AIConfig.parse(answer.text)) != nil,
                          "\(contextSize) tokens, “\(sentence)”: answered on the device within its context (\(sent?.tokens ?? -1) + "
                              + "\(sent?.maximumResponseTokens ?? -1) for the answer): \(answer.text.prefix(160))")
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
        let lines = [AIConfig.Failure.notUnderstood, .notAllowed, .alreadySet].map(text.failure)
        check(capped.sent.count == 1 && (assistant.preview != nil || assistant.message.map(lines.contains) == true),
              "the page with a 4096-token context: \(assistant.preview != nil ? "a preview (\(assistant.lines.joined(separator: "; ")))" : assistant.message ?? "nothing")")

        // Too long for any fit: not sent to the model; the line says what to do, in the interface language.
        let long = CappedGuidedModel(guided, contextSize: 4096)
        AIConfigSession.service = service(long)
        assistant.request = String(repeating: "请把候选改成竖排，", count: 500)
        assistant.sendRequest()
        _ = pump(timeout: 60) { !assistant.working }
        check(long.sent.isEmpty && assistant.message == text.tooLong(notSetUp: .bedrock),
              "a request too long for the context isn't sent to the model, and says what to do: \(assistant.message ?? "-")")
    }
}
