import Foundation
import Testing
@testable import AllInOneIMECore

/// Stands in for the on-device model with a context of `contextSize` tokens, counted the way FoundationModels counts them
/// near enough (`tokens`): the instructions, the conversation, the prompt, the schema the answer is held to (as the JSON
/// schema the framework puts into the prompt) and the tools' definitions, then the answer. A request that leaves no room
/// for its answer fails with `AppleModelError.contextExceeded`, as the framework's does. `overflows`: every request
/// fails so (the model said so though the request was fitted). `weight`: its tokens are that many times those (a
/// tokenizer the estimate falls short of).
final class ContextLimitedModel: AppleGuidedBackend, @unchecked Sendable {
    let availability: AppleModelAvailability = .available
    let contextSize: Int
    let supportedLanguages: Set<String> = ["en", "zh"]
    let answer: String
    let overflows: Bool
    /// Whether it counts a request's tokens when asked (macOS 26.4 and later); else the core estimates them.
    let counts: Bool
    let weight: Double
    private let lock = NSLock()
    private var _sent: [(request: AppleModelRequest, schema: GuidedSchema, tools: [String], tokens: Int)] = []
    /// What was sent, and its size in tokens without the answer.
    var sent: [(request: AppleModelRequest, schema: GuidedSchema, tools: [String], tokens: Int)] { lock.withLock { _sent } }

    init(contextSize: Int = 4096, answer: String = #"{"changes": [{"key": "candidateLayout", "value": "vertical"}], "note": "The candidates are in a column now."}"#,
         overflows: Bool = false, counts: Bool = true, weight: Double = 1) {
        self.contextSize = contextSize
        self.answer = answer
        self.overflows = overflows
        self.counts = counts
        self.weight = weight
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: AppleModelError.failed("plain path used")) }
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        let size = weighed(request, schema: schema, tools: tools)
        lock.withLock { _sent.append((request, schema, tools.map(\.name), size)) }
        if overflows || size + Self.tokens(answer) > contextSize { throw AppleModelError.contextExceeded }
        return answer
    }

    func tokenCount(of request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async -> Int? {
        counts ? weighed(request, schema: schema, tools: tools) : nil
    }

    private func weighed(_ request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) -> Int {
        Int((Double(Self.tokens(request, schema: schema, tools: tools)) * weight).rounded(.up))
    }

    // MARK: Counting

    /// About what the system's tokenizer gives (measured on macOS 27.2: the Assistant's instructions, schema and tools
    /// within 1%): text at about 3.7 ASCII characters a token, this rendering of the schema at 2.8 and of the tools at 4,
    /// each other character (CJK, …) a token; a few tokens for each turn's markers.
    static func tokens(_ request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) -> Int {
        let texts = [request.instructions, request.prompt] + request.examples.flatMap { [$0.prompt, $0.response] }
        return texts.map { tokens($0) }.reduce(0, +) + 6 * (request.examples.count * 2 + 2)
            + tokens(json(schema), perToken: 2.8) + tools.map { tokens(json($0), perToken: 4) }.reduce(0, +)
    }

    static func tokens(_ text: String, perToken: Double = 3.7) -> Int {
        let ascii = text.unicodeScalars.filter(\.isASCII).count
        return Int((Double(ascii) / perToken).rounded(.up)) + text.unicodeScalars.count - ascii
    }

    /// The schema as the JSON schema the framework writes into the prompt (`GenerationSchema`'s encoding).
    static func json(_ schema: GuidedSchema) -> String {
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        switch schema {
        case let .object(name, properties):
            let fields = properties.map { property -> String in
                var item = json(property.schema)
                if let description = property.description { item = "{\"description\":\(quoted(description)),\(item.dropFirst())" }
                return quoted(property.name) + ":" + item
            }
            let required = properties.filter { !$0.optional }.map { quoted($0.name) }
            return "{\"title\":\(quoted(name)),\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\(fields.joined(separator: ","))},"
                + "\"required\":[\(required.joined(separator: ","))],\"x-order\":[\(properties.map { quoted($0.name) }.joined(separator: ","))]}"
        case let .choice(name, choices):
            return "{\"title\":\(quoted(name)),\"anyOf\":[\(choices.map(json).joined(separator: ","))]}"
        case let .strings(_, values):
            return "{\"type\":\"string\",\"enum\":[\(values.map(quoted).joined(separator: ","))]}"
        case let .array(item, min, max):
            return "{\"type\":\"array\",\"items\":\(json(item))" + (min.map { ",\"minItems\":\($0)" } ?? "") + (max.map { ",\"maxItems\":\($0)" } ?? "") + "}"
        case .string: return "{\"type\":\"string\"}"
        case .bool: return "{\"type\":\"boolean\"}"
        case let .number(min, max): return "{\"type\":\"number\",\"minimum\":\(min),\"maximum\":\(max)}"
        case let .optional(inner): return "{\"title\":\"Optional\",\"anyOf\":[\(json(inner)),{\"type\":\"null\"}]}"
        }
    }

    static func json(_ tool: GuidedTool) -> String {
        let arguments = tool.arguments.map { "\"\($0.name)\":{\"type\":\"string\",\"description\":\"\($0.description)\"}" }.joined(separator: ",")
        return "{\"type\":\"function\",\"function\":{\"name\":\"\(tool.name)\",\"description\":\"\(tool.description)\",\"parameters\":"
            + "{\"title\":\"\(tool.name)Arguments\",\"type\":\"object\",\"properties\":{\(arguments)},\"required\":[],\"x-order\":[]}}}"
    }
}

/// Stands in for an on-device model that calls its tools over and over (the same app, again and again): the tools named
/// in `calls`, in that order, whatever they return; what each call returned. Then it answers.
final class LoopingToolsModel: AppleGuidedBackend, @unchecked Sendable {
    let availability: AppleModelAvailability = .available
    let contextSize = 8192
    let supportedLanguages: Set<String> = ["en", "zh"]
    let calls: [String]
    private let lock = NSLock()
    private var _returned: [String] = []
    var returned: [String] { lock.withLock { _returned } }

    init(calls: [String]) { self.calls = calls }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: AppleModelError.failed("plain path used")) }
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        for name in calls {
            guard let tool = tools.first(where: { $0.name == name }) else { continue }
            let output = await tool.call(["name": "WeChat"])
            lock.withLock { _returned.append(output) }
        }
        return #"{"changes": [{"key": "appProfiles.*.inputLanguage", "app": "WeChat", "value": "zh"}]}"#
    }
}

/// The system's model where this Mac has it and it can count tokens (Apple Intelligence on, macOS 26.4 and later): its
/// tokenizer, which the estimate and the plan are held to; nil elsewhere (the tests that need it are skipped).
enum RealTokenizer {
    static let model: (any AppleGuidedBackend)? = {
        guard AppleModel.system.availability == .available, let model = AppleModel.system as? any AppleGuidedBackend else { return nil }
        return model
    }()
}

/// The system's tokenizer (`RealTokenizer`) with macOS 26's context (4096 tokens): counts as the system does when
/// `counts` (else the core estimates), answers `answer` without the model, and fails as the framework does when the
/// request by the system's count leaves no room for it. What was sent, with its size by the system's count.
final class RealTokenizerModel: AppleGuidedBackend, @unchecked Sendable {
    let real: any AppleGuidedBackend
    let availability: AppleModelAvailability = .available
    let contextSize = 4096
    let supportedLanguages: Set<String> = ["en", "zh"]
    let counts: Bool
    let answer = #"{"changes": [], "note": "-"}"#
    private let lock = NSLock()
    private var _sent: [(request: AppleModelRequest, schema: GuidedSchema, tokens: Int)] = []
    var sent: [(request: AppleModelRequest, schema: GuidedSchema, tokens: Int)] { lock.withLock { _sent } }

    init(_ real: any AppleGuidedBackend, counts: Bool) {
        self.real = real
        self.counts = counts
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: AppleModelError.failed("plain path used")) }
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        let size = await real.tokenCount(of: request, schema: schema, tools: tools) ?? .max
        lock.withLock { _sent.append((request, schema, size)) }
        if size > contextSize - 20 { throw AppleModelError.contextExceeded }
        return answer
    }

    func tokenCount(of request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async -> Int? {
        counts ? await real.tokenCount(of: request, schema: schema, tools: tools) : nil
    }
}

/// Settings → Assistant on the on-device model, whose context (4096 tokens before macOS 27, 8192 since) holds the
/// instructions, the schema, the tools and the answer together: the request fitted to it, and when it can't be, the
/// user's own provider, or a line that says what to do.
struct AIConfigContextTests {
    /// A config as a long-time user's: five languages each way, every style, many apps with settings of their own,
    /// custom commands, hidden words.
    static func bigConfig(apps: Int = 60) -> Config {
        var config = Config.default
        config.provider = .anthropic
        config.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja"), OutputLanguage("fr"), OutputLanguage("de")])
        config.setOrder([Language.chinese, .english, .french, .korean, .hindi])
        config.rewriteStyles = RewriteStyle.catalog.map(\.name)
        let styles = RewriteStyle.catalog.map(\.name)
        let known = ["com.tencent.xinWeChat", "com.tinyspeck.slackmacgap", "com.apple.mail", "com.apple.Notes", "com.microsoft.VSCode"]
        for index in 0..<apps {
            let id = index < known.count ? known[index] : "com.example.someapp\(index)"
            config.appProfiles[id] = AppProfile(inputLanguage: Language.allCases[index % Language.allCases.count],
                                                rewriteStyles: Array(styles.prefix(1 + index % 3)), typeOut: index % 2 == 0,
                                                noAI: index % 7 == 0 ? true : nil)
        }
        config.customCommands = (0..<30).map { CustomCommand(name: "cmd\($0)", type: .prompt, summary: "Command \($0)", prompt: "Rewrite the text.") }
        config.redaction = RedactionSettings(enabled: true, customWords: (0..<50).map { "Secret\($0)" })
        return config
    }

    static let knownModels: [Provider: [String]] = [
        .bedrock: ["us.anthropic.claude-haiku-4-5-20251001-v1:0", "us.anthropic.claude-sonnet-4-6", "us.amazon.nova-2-lite-v1:0"],
        .anthropic: ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"],
        .gemini: ["gemini-3.8-flash"],
        .openai: ["gpt-6-luna", "gpt-5.4-mini", "deepseek-chat"],
    ]

    static let apps = AIConfig.AppCatalog(apps: [
        .init(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"]),
        .init(bundleID: "com.tinyspeck.slackmacgap", names: ["Slack"]),
        .init(bundleID: "com.apple.mail", names: ["Mail", "邮件"]),
    ])

    static func context(_ config: Config) -> AIConfigPrompt.Context {
        AIConfigPrompt.Context(config: config, knownModels: knownModels, awsProfiles: ["default", "work", "personal", "dev"],
                               offeredProviders: [.bedrock, .anthropic, .gemini, .openai, .apple], installedPacks: [.chinese, .korean], apps: apps)
    }

    static let tools = AIConfigService.Tools(findApps: { "WeChat: com.tencent.xinWeChat (\($0))" }, awsProfiles: { "default (region us-east-1)" },
                                             languagePacks: { "zh (Chinese): installed" })

    /// The provider's request never goes anywhere: there is none to go to.
    static func service(_ model: any AppleGuidedBackend) -> AIConfigService {
        AIConfigService(client: ChatClient(apple: model), loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                        loadKey: { _, _ in nil })
    }

    // MARK: - Fitted to the context

    /// The bug as reported: on a 4096-token model the whole request (the schema alone is about 2400 tokens) leaves no
    /// room for the answer, whatever the config; with a large one it doesn't even fit. Fitted, it is answered.
    @Test(arguments: [0, 60], ["candidates in a column", "竖排候选"])
    func aLargeConfigIsAnsweredOnA4KModel(apps: Int, sentence: String) async throws {
        let model = ContextLimitedModel(contextSize: 4096)
        let answer = try await Self.service(model).ask(sentence, context: Self.context(Self.bigConfig(apps: apps)), tools: Self.tools)
        #expect(answer.onDevice)
        #expect(try AIConfig.parse(answer.text).changes == [.init(key: .setting(.candidateLayout), value: .string("vertical"))])
        let sent = try #require(model.sent.last)
        #expect(sent.tokens + sent.request.maximumResponseTokens <= 4096, "\(sent.tokens) + \(sent.request.maximumResponseTokens)")
    }

    /// Where the whole request fits (a 8192-token model, an everyday config) it goes as before: every setting, every
    /// tool, the answer's limit the user's.
    @Test func theWholeRequestWhenItFits() async throws {
        let model = ContextLimitedModel(contextSize: 8192)
        var config = Config.default
        config.provider = .anthropic
        let context = Self.context(config)
        _ = try await Self.service(model).ask("candidates in a column", context: context, tools: Self.tools)
        let sent = try #require(model.sent.last)
        #expect(sent.request.instructions == AIConfigPrompt.system(context, compact: true, refining: false))
        #expect(sent.schema == AIConfigPrompt.schema(context) && sent.tools == ["findApps", "awsProfiles", "languagePacks"])
        #expect(sent.request.maximumResponseTokens == 1000)
    }

    /// Where it doesn't, the settings the sentence is about go first, with the apps it names (their current values) and the
    /// tools they need; the rest only while there is room.
    @Test func theSettingsTheSentenceIsAboutFirst() async throws {
        let model = ContextLimitedModel(contextSize: 4096, answer: #"{"changes": [{"key": "appProfiles.*.inputLanguage", "app": "微信", "value": "zh"}]}"#)
        var config = Self.bigConfig(apps: 80)
        config.appProfiles["com.tencent.xinWeChat"] = AppProfile(inputLanguage: .english)
        let answer = try await Self.service(model).ask("微信里用中文", context: Self.context(config), tools: Self.tools)
        #expect(try AIConfig.parse(answer.text).changes == [.init(key: .app("微信", .inputLanguage), value: .string("zh"))])
        let sent = try #require(model.sent.last)
        #expect(sent.tokens + sent.request.maximumResponseTokens <= 4096)
        let choices = Self.choices(sent.schema)
        #expect(choices.contains("AppInput") && choices.contains("InputLanguages") && !choices.contains("Region"), "\(choices)")
        #expect(sent.tools.contains("findApps") && !sent.tools.contains("awsProfiles"))
        // WeChat's current values are shown; most of the other 79 apps' aren't, and the model is told so.
        let apps = try #require(sent.request.instructions.split(separator: "\n").first { $0.hasPrefix("- appProfiles.<app>.inputLanguage") })
        #expect(apps.contains(#""com.tencent.xinWeChat":{"inputLanguage":"en"}"#) && apps.contains("other apps, not shown"), "\(apps)")
    }

    /// "use Bedrock" chooses the provider as much as Bedrock's own settings: on a 4096-token model (macOS 26) the schema
    /// has the provider's choices with Bedrock's, whatever the config, counted by the model or estimated.
    @Test(arguments: [0, 60, 250], [true, false])
    func useBedrockKeepsTheProvider(apps: Int, counts: Bool) async throws {
        // Latin words written against Chinese, Japanese or Korean without a space too.
        for sentence in ["use Bedrock", "switch to Amazon Nova", "use the AWS profile work", "改用Bedrock", "用AWS的profile work",
                         "AWS로 바꿔 줘", "AWSのプロファイルをworkにして"] {
            let model = ContextLimitedModel(contextSize: 4096, answer: #"{"changes": [{"key": "provider", "value": "bedrock"}]}"#, counts: counts)
            let answer = try await Self.service(model).ask(sentence, context: Self.context(Self.bigConfig(apps: apps)), tools: Self.tools)
            #expect(answer.onDevice)
            #expect(try AIConfig.parse(answer.text).changes == [.init(key: .setting(.provider), value: .string("bedrock"))])
            let sent = try #require(model.sent.last)
            #expect(sent.tokens + sent.request.maximumResponseTokens <= 4096)
            let choices = Self.choices(sent.schema)
            #expect(["Provider", "Region", "AWSProfile", "ModelBedrock"].allSatisfy(choices.contains), "\(sentence), \(apps) apps: \(choices)")
            #expect(sent.tools.contains("awsProfiles"))
        }
    }

    /// Portuguese "nova" (new) is no Amazon Nova: a sentence with it is about what else it names, and fits a 4096-token
    /// context without the model's count (macOS 26.0 to 26.3) as its English one does, whatever the config.
    @Test(arguments: [0, 60, 250])
    func portugueseNovaIsNotAmazonNova(apps: Int) async throws {
        let context = Self.context(Self.bigConfig(apps: apps))
        for sentence in ["use inglês no WeChat para uma nova conversa", "nova regra: inglês no Slack e candidatos em coluna"] {
            let parts = AIConfigFit.relevance([sentence], context: context).parts
            #expect(!parts.contains(.provider) && !parts.contains(.aws), "\(sentence): \(parts)")
            let model = ContextLimitedModel(contextSize: 4096, counts: false)
            let outcome = await Result { try await Self.service(model).ask(sentence, context: context, tools: Self.tools) }
            #expect((try? outcome.get())?.onDevice == true, "\(sentence), \(apps) apps: \(outcome)")
        }
    }

    /// A model that calls its tools over and over gets each one's lookup three times at most in a request, and six in all;
    /// past that, it is told to answer without them, and does: its context (room for a call or two) isn't filled with
    /// what they return until the request is too long. A request after it has its own calls.
    @Test func theToolsAreLookedUpAFewTimesAtMost() async throws {
        let looked = Locked(initialState: [String: Int]())
        let tools = AIConfigService.Tools(
            findApps: { _ in looked.withLock { $0["findApps", default: 0] += 1 }; return "WeChat: com.tencent.xinWeChat" },
            awsProfiles: { looked.withLock { $0["awsProfiles", default: 0] += 1 }; return "default (region us-east-1)" },
            languagePacks: { looked.withLock { $0["languagePacks", default: 0] += 1 }; return "zh (Chinese): installed" })
        var config = Config.default
        config.provider = .anthropic
        // The same app, again and again.
        let again = LoopingToolsModel(calls: Array(repeating: "findApps", count: 20))
        let answer = try await Self.service(again).ask("微信里用中文", context: Self.context(config), tools: tools)
        #expect(answer.onDevice && looked.withLock { $0 } == ["findApps": 3])
        #expect(again.returned.count == 20 && again.returned.prefix(3).allSatisfy { $0 == "WeChat: com.tencent.xinWeChat" }
                && again.returned.dropFirst(3).allSatisfy { $0 == GuidedTool.enough }, "\(again.returned)")
        #expect(GuidedTool.enough.contains("answer now") && GuidedTool.enough.contains("without calling a tool"))
        // Each of them: six in all, the seventh call told to answer whichever tool it is.
        looked.withLock { $0 = [:] }
        let all = LoopingToolsModel(calls: ["findApps", "awsProfiles"].flatMap { Array(repeating: $0, count: 4) } + ["languagePacks"])
        _ = try await Self.service(all).ask("微信里用中文", context: Self.context(config), tools: tools)
        #expect(looked.withLock { $0 } == ["findApps": 3, "awsProfiles": 3] && all.returned.last == GuidedTool.enough)
        // The next request: its own.
        looked.withLock { $0 = [:] }
        _ = try await Self.service(again).ask("Slack 里用英文", context: Self.context(config), tools: tools)
        #expect(looked.withLock { $0 } == ["findApps": 3])
    }

    /// A refine's conversation: its latest turn always (the last answer holds what the earlier instructions asked for),
    /// older ones while there is room, the oldest left out first.
    @Test func olderTurnsGoFirst() async throws {
        let model = ContextLimitedModel(contextSize: 4096)
        let long = #"{"changes": ["# + (0..<12).map { #"{"key": "appProfiles.com.example.someapp\#($0).typeOut", "value": true}"# }.joined(separator: ", ") + "]}"
        let turns = (1...8).map { Refinement.Turn(answer: ConversionResult(versions: [CandidateLine(long)]), instruction: "change number \($0)") }
        _ = try await Self.service(model).ask("type out in every app", turns: turns, context: Self.context(Self.bigConfig()), tools: Self.tools)
        let sent = try #require(model.sent.last)
        #expect(sent.tokens + sent.request.maximumResponseTokens <= 4096)
        #expect(sent.request.prompt == "<refine>change number 8</refine>")
        let kept = sent.request.examples.count
        #expect(kept >= 1 && kept < 9, "\(kept) turns kept")
        // The sentence first, then the latest instructions (the older ones went).
        #expect(sent.request.examples.first?.prompt == "type out in every app")
        #expect(sent.request.examples.dropFirst().map(\.prompt) == (9 - kept..<8).map { "<refine>change number \($0)</refine>" })
    }

    /// macOS 26.0 to 26.3 can't count tokens: the estimate (on the high side) fits the request all the same.
    @Test func withoutTheModelsCountTheEstimateFits() async throws {
        for sentence in ["candidates in a column", "竖排候选，微信里用中文，翻译成日文和法文，打字慢一点"] {
            let model = ContextLimitedModel(contextSize: 4096, counts: false)
            let answer = try await Self.service(model).ask(sentence, context: Self.context(Self.bigConfig(apps: 120)), tools: Self.tools)
            #expect(answer.onDevice)
            let sent = try #require(model.sent.last)
            #expect(sent.tokens + sent.request.maximumResponseTokens <= 4096, "\(sent.tokens) + \(sent.request.maximumResponseTokens)")
        }
    }

    /// macOS 26.0 to 26.3, where the model can't count: should it find a request fitted by the estimate too long all the
    /// same (a tokenizer heavier than the estimate has it), the request is fitted once more with the estimate ×1.3 and
    /// answered on the device; too long again, the user's own provider (here it has no key: the line says so).
    @Test func withoutTheModelsCountTooLongIsFittedOnceMore() async throws {
        let context = Self.context(Self.bigConfig(apps: 120))
        let heavy = ContextLimitedModel(contextSize: 4096, counts: false, weight: 1.6)
        let answer = try await Self.service(heavy).ask("candidates in a column", context: context, tools: Self.tools)
        #expect(answer.onDevice && heavy.sent.count == 2)
        let (first, second) = (heavy.sent[0], heavy.sent[1])
        #expect(first.tokens > 4096 - 30 && second.tokens + second.request.maximumResponseTokens <= 4096, "\(first.tokens), \(second.tokens)")
        #expect(Self.choices(second.schema).contains("CandidateLayout"))

        let heavier = ContextLimitedModel(contextSize: 4096, counts: false, weight: 2.5)
        await #expect(throws: AIConfigService.TooLong.self) {
            _ = try await Self.service(heavier).ask("candidates in a column", context: context, tools: Self.tools)
        }
        #expect(heavier.sent.count == 2)
        // The same request once more would be too long again: the user's provider at once. And where the model counts,
        // its count decides: no second try (`tooLongAllTheSameGoesToTheUsersProvider`).
        var small = Config.default
        small.provider = .anthropic
        let whole = ContextLimitedModel(contextSize: 8192, overflows: true, counts: false)
        await #expect(throws: AIConfigService.TooLong.self) {
            _ = try await Self.service(whole).ask("candidates in a column", context: Self.context(small), tools: Self.tools)
        }
        #expect(whole.sent.count == 1)
    }

    /// The estimate is on the high side of the stand-in's count (the system's own: `theEstimateIsOnTheHighSideOfTheSystemsCount`).
    @Test func theEstimateIsOnTheHighSide() {
        for apps in [0, 60, 200] {
            for sentence in ["candidates in a column", "微信里用中文输入，候选横排，翻译成英文和日文"] {
                let context = Self.context(Self.bigConfig(apps: apps))
                let body = AIConfigPrompt.request(sentence, context: context, compact: true)
                let request = AppleModel.request(from: body, maxTokens: 1000, contextSize: 8192)
                let schema = AIConfigPrompt.schema(context)
                let tools = Self.tools.guided
                #expect(AIConfigFit.estimatedTokens(request, schema: schema, tools: tools) >= ContextLimitedModel.tokens(request, schema: schema, tools: tools))
            }
        }
    }

    /// The estimate is on the high side of the system's own count (where this Mac has its model) for requests of every
    /// size: an empty one, a sentence alone, each part of the settings alone (where the schema's enums weigh most) with its
    /// tools and without, a refine's long answers, the whole of it; in English and Chinese, with no apps of their own and
    /// with 250. And not so high that it wastes the context where there is no count: under 1.5 times it from 1000 tokens.
    @Test(.enabled(if: RealTokenizer.model != nil)) func theEstimateIsOnTheHighSideOfTheSystemsCount() async throws {
        let real = try #require(RealTokenizer.model)
        func request(_ instructions: String, prompt: String, examples: [AppleModelRequest.Turn] = []) -> AppleModelRequest {
            AppleModelRequest(instructions: instructions, examples: examples, prompt: prompt, temperature: 0, maximumResponseTokens: 1000)
        }
        var cases: [(String, AppleModelRequest, GuidedSchema, [GuidedTool])] = [
            ("empty", request("", prompt: ""), .object(name: "A", properties: []), []),
            ("a sentence", request("", prompt: "candidates in a column"), .object(name: "A", properties: []), []),
        ]
        let long = #"{"changes": ["# + (0..<12).map { #"{"key": "appProfiles.com.example.someapp\#($0).typeOut", "value": true}"# }.joined(separator: ", ") + "]}"
        let turns = (1...8).map { Refinement.Turn(answer: ConversionResult(versions: [CandidateLine(long)]), instruction: "change number \($0)") }
        for apps in [0, 250] {
            let context = Self.context(Self.bigConfig(apps: apps))
            for sentence in ["candidates in a column", "微信里用中文输入，候选横排，翻译成英文和日文"] {
                var scopes = AIConfigPrompt.Part.allCases.map { (String(describing: $0), AIConfigPrompt.Scope(parts: [$0], apps: [])) }
                scopes.append(("everything", .everything))
                for (name, scope) in scopes {
                    let body = AIConfigPrompt.request(sentence, context: context, compact: true, scope: scope)
                    let schema = AIConfigPrompt.schema(context, scope: scope)
                    let sent = AppleModel.request(from: body, maxTokens: 1000, contextSize: 8192)
                    cases.append(("\(apps) apps, \(name), \(sentence)", sent, schema, AIConfigFit.tools(Self.tools.guided, for: scope)))
                    if apps == 0, sentence.first == "c" { cases.append(("\(apps) apps, \(name), no tools, \(sentence)", sent, schema, [])) }
                }
                let refine = AIConfigPrompt.request(sentence, context: context, turns: turns, compact: true, scope: AIConfigPrompt.Scope(parts: [.typing], apps: []))
                cases.append(("\(apps) apps, a refine's 8 answers, \(sentence)", AppleModel.request(from: refine, maxTokens: 1000, contextSize: 8192),
                              AIConfigPrompt.schema(context, scope: AIConfigPrompt.Scope(parts: [.typing])), []))
            }
        }
        for (name, sent, schema, tools) in cases {
            guard let counted = await real.tokenCount(of: sent, schema: schema, tools: tools) else { return }  // before macOS 26.4
            let estimate = AIConfigFit.estimatedTokens(sent, schema: schema, tools: tools)
            #expect(estimate >= counted, "\(name): \(estimate) estimated, \(counted) counted")
            if counted >= 1000 { #expect(Double(estimate) < 1.5 * Double(counted), "\(name): \(estimate) estimated, \(counted) counted") }
        }
    }

    /// On the system's own tokenizer (where this Mac has it) with macOS 26's context, counted by the model or estimated:
    /// each request goes within the context by the system's count, with every setting the sentence is about and room for
    /// the answer; or, about more settings than fit (or than fit by the estimate), not at all.
    @Test(.enabled(if: RealTokenizer.model != nil), arguments: [0, 60, 250], [true, false])
    func fittedByTheSystemsCount(apps: Int, counts: Bool) async throws {
        let real = try #require(RealTokenizer.model)
        guard await real.tokenCount(of: AppleModelRequest(instructions: "", examples: [], prompt: "", temperature: 0, maximumResponseTokens: 1),
                                    schema: .string, tools: []) != nil else { return }  // before macOS 26.4
        let context = Self.context(Self.bigConfig(apps: apps))
        let small = ["candidates in a column", "use Bedrock", "switch to Amazon Nova", "微信里用英文输入", "隐藏电话号码"]
        for sentence in small + ["translate into Japanese, type out slower, hide phone numbers, use Bedrock", Self.nineSettings] {
            let model = RealTokenizerModel(real, counts: counts)
            let outcome = await Result { try await Self.service(model).ask(sentence, context: context, tools: Self.tools) }
            guard case let .success(answer) = outcome else {
                // Not sent at all; never for a sentence about a setting or two.
                #expect(model.sent.isEmpty && !small.contains(sentence), "\(sentence): \(outcome)")
                continue
            }
            let sent = try #require(model.sent.last)
            #expect(answer.onDevice && model.sent.count == 1)
            #expect(sent.tokens + sent.request.maximumResponseTokens <= 4096 && sent.request.maximumResponseTokens >= AIConfigFit.answerRoom,
                    "\(sentence): \(sent.tokens) + \(sent.request.maximumResponseTokens)")
            for part in AIConfigFit.relevance([sentence], context: context).parts {
                let line = try #require(AIConfigPrompt.settings(context, compact: true, scope: AIConfigPrompt.Scope(parts: [part])).first)
                let key = line.prefix { $0 != ":" }
                #expect(sent.request.instructions.contains("\n- \(key):"), "\(sentence): \(part) left out")
            }
        }
    }

    // MARK: - Too long all the same

    /// The model says it's too long though it was fitted: the user's own provider answers instead, with every setting in
    /// the instructions as when the on-device model isn't there, and the answer says so.
    @Test func tooLongAllTheSameGoesToTheUsersProvider() async throws {
        let host = "assistant-fallback.test"
        let answer = #"{"changes": [{"key": "candidateLayout", "value": "vertical"}]}"#
        let model = ContextLimitedModel(overflows: true)
        let (service, config) = try Self.openAIService(model, host: host, answer: answer)
        // Where it goes is said before it goes.
        let told = Locked<[(Provider, sentYet: Bool)]>(initialState: [])
        let got = try await service.ask("candidates in a column", context: Self.context(config), tools: Self.tools) { provider in
            let sentYet = StubURLProtocol.lastRequest(host: host) != nil
            told.withLock { $0.append((provider, sentYet)) }
        }
        #expect(got.text == answer && !got.onDevice && got.instead == .openai && !got.fromCache)
        #expect(told.withLock { $0.map(\.0) } == [.openai] && told.withLock { $0.first?.sentYet } == false)
        #expect(model.sent.count == 1)
        let body = RedactionTests.body(StubURLProtocol.lastRequest(host: host))
        // The instructions as the providers get them (the allowed values); no AWS profile named: the sentence isn't about AWS.
        #expect(body.contains("allowed values") && !body.contains("personal"), "\(body.prefix(300))")
        // Asked again: kept, still said to be the provider's.
        let again = try await service.ask("candidates in a column", context: Self.context(config), tools: Self.tools)
        #expect(again.fromCache && again.instead == .openai && model.sent.count == 2)
        #expect(AIConfig.Text(language: "en").sentInstead(.openai) == "Too long for Apple Intelligence on this Mac: sent to OpenAI-compatible API instead")
        #expect(AIConfig.Text(language: "zh-Hans").sentInstead(.anthropic) == "这句话对本机的 Apple Intelligence 来说太长了，已改发给 Claude API")
        // Answered on the device: nothing said.
        let onDevice = ContextLimitedModel(contextSize: 8192)
        var small = Config.default
        small.provider = .openai
        _ = try await Self.service(onDevice).ask("candidates in a column", context: Self.context(small), tools: Self.tools) { _ in
            Issue.record("said to go elsewhere")
        }
    }

    /// A setting the sentence is about is never left out to fit: a sentence about nine of them doesn't fit a 4096-token
    /// context whatever else is left out, so the user's own provider gets it whole, and the on-device model nothing.
    @Test(arguments: [true, false])
    func aSettingTheSentenceIsAboutIsNeverLeftOut(counts: Bool) async throws {
        let host = "assistant-whole-\(counts).test"
        let model = ContextLimitedModel(contextSize: 4096, counts: counts)
        let (service, config) = try Self.openAIService(model, host: host, answer: #"{"changes": []}"#)
        let got = try await service.ask(Self.nineSettings, context: Self.context(config), tools: Self.tools)
        #expect(model.sent.isEmpty && !got.onDevice && got.instead == .openai)
        let body = RedactionTests.body(StubURLProtocol.lastRequest(host: host))
        for key in ["candidateLayout", "outputLanguages", "typeOutRate", "redaction.phones", "iCloudSync.enabled", "region", "checkForUpdates",
                    "rememberQuestions", "com.tencent.xinWeChat"] {
            #expect(body.contains(key), "\(key)")
        }
    }

    /// Where the model counts, the settings the sentence is about go to the device when they fit by its count, every
    /// one of them, though the estimate (on the high side) says they don't; without its count the estimate decides,
    /// and the user's own provider is asked (here it has no key: the line says so).
    @Test func whatFitsByTheModelsCountGoesToTheDevice() async throws {
        let sentence = "translate into Japanese, type out slower, hide phone numbers, use Bedrock"
        let context = Self.context(Self.bigConfig())
        let counted = ContextLimitedModel(contextSize: 4096)
        let answer = try await Self.service(counted).ask(sentence, context: context, tools: Self.tools)
        #expect(answer.onDevice)
        let sent = try #require(counted.sent.last)
        #expect(sent.tokens + sent.request.maximumResponseTokens <= 4096)
        let choices = Self.choices(sent.schema)
        #expect(["OutputLanguages", "InputLanguages", "TypeOutRate", "HideWords", "Provider", "Region"].allSatisfy(choices.contains), "\(choices)")

        let estimated = ContextLimitedModel(contextSize: 4096, counts: false)
        await #expect(throws: AIConfigService.TooLong.self) {
            _ = try await Self.service(estimated).ask(sentence, context: context, tools: Self.tools)
        }
        #expect(estimated.sent.isEmpty)
    }

    /// Too long for the on-device model, the user's own provider is asked with the AWS profiles named (the list and the
    /// one in use) only when the sentence is about AWS or Bedrock: by its words, not by letters inside others.
    @Test func theAWSProfilesAreNamedToTheProviderOnlyOnAWSSentences() async throws {
        let sentences = [("use the AWS profile personal", true), ("switch to Bedrock in us-west-2", true), ("改用亚马逊的模型", true),
                         ("アマゾンの Bedrock にして", true), ("改用AWS的模型", true), ("AWSのプロファイル", true), ("AWS로 바꿔 줘", true),
                         ("candidates in a column when it draws", false), ("hide the laws' names", false), ("候选竖排", false),
                         ("用Laws的说法", false)]
        for (index, (sentence, aws)) in sentences.enumerated() {
            let host = "assistant-aws-\(index).test"
            let (service, config) = try Self.openAIService(ContextLimitedModel(overflows: true), host: host, answer: #"{"changes": []}"#)
            let got = try await service.ask(sentence, context: Self.context(config), tools: Self.tools)
            #expect(got.instead == .openai)
            let body = RedactionTests.body(StubURLProtocol.lastRequest(host: host))
            #expect(body.contains("personal") == aws && body.contains("names not shown") == !aws, "\(sentence)")
            #expect(AIConfig.mentionsAWS(sentence) == aws, "\(sentence)")
        }
    }

    /// A Bedrock model that names the AWS account (an inference profile's ARN, an account ID in it) goes to no provider
    /// but Amazon Bedrock: not to the user's provider answering instead of the on-device model, even on a sentence about
    /// AWS, nor to it without Apple Intelligence; the on-device model (nothing leaves this Mac) has it.
    @Test func aBedrockModelThatNamesTheAccountGoesToNoOtherProvider() async throws {
        let account = "123456789012"
        for (index, modelId) in ["arn:aws:bedrock:us-east-1:\(account):application-inference-profile/abc123",
                                 "\(account).custom-model"].enumerated() {
            #expect(AIConfig.namesAWSAccount(modelId))
            for (turn, sentence) in ["use the AWS profile personal", "candidates in a column"].enumerated() {
                let host = "assistant-account-\(index)-\(turn).test"
                let (service, chosen) = try Self.openAIService(ContextLimitedModel(overflows: true), host: host, answer: #"{"changes": []}"#)
                var config = chosen
                config.modelId = modelId
                _ = try await service.ask(sentence, context: Self.context(config), tools: Self.tools)
                let body = RedactionTests.body(StubURLProtocol.lastRequest(host: host))
                #expect(!body.contains(account) && body.contains("not shown: it names the AWS account"), "\(sentence)")
            }
            // Without Apple Intelligence.
            let host = "assistant-account-\(index)-cloud.test"
            let (_, chosen) = try Self.openAIService(ContextLimitedModel(), host: host, answer: #"{"changes": []}"#)
            var config = chosen
            config.modelId = modelId
            let cloud = AIConfigService(client: ChatClient(bedrock: BedrockClient(session: StubURLProtocol.session()),
                                                           apple: AIConfigTests.GuidedStub(.deviceNotEligible, answer: "")),
                                        loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                                        loadKey: { provider, keyHost in provider == .openai && keyHost == host ? "sk-test" : nil })
            _ = try await cloud.ask("use the AWS profile personal", context: Self.context(config), tools: Self.tools)
            #expect(!RedactionTests.body(StubURLProtocol.lastRequest(host: host)).contains(account))
            // On the device.
            let model = ContextLimitedModel(contextSize: 8192)
            var small = Config.default
            small.provider = .anthropic
            small.modelId = modelId
            _ = try await Self.service(model).ask("use Bedrock", context: Self.context(small), tools: Self.tools)
            #expect(try #require(model.sent.last).request.instructions.contains(modelId))
        }
        #expect(!AIConfig.namesAWSAccount("us.anthropic.claude-haiku-4-5-20251001-v1:0") && !AIConfig.namesAWSAccount("us.amazon.nova-2-lite-v1:0"))
    }

    /// An account ID in an AWS profile's name (an SSO profile's "AdministratorAccess-123456789012") goes to no provider but
    /// Amazon Bedrock either: the user's provider asked instead of the on-device model, or without Apple Intelligence, gets
    /// the rest of the name with "[account 1]" for the ID (the same account, the same number), and an answer that names a
    /// profile so is read with its real name; the on-device model has the names as they are.
    @Test func anAccountIDInAProfilesNameGoesToNoOtherProvider() async throws {
        let profiles = ["default", "AdministratorAccess-123456789012", "ReadOnly-123456789012", "AdministratorAccess-210987654321"]
        let answer = #"{"changes": [{"key": "awsProfile", "value": "AdministratorAccess-[account 2]"}]}"#
        let sentence = "use the AWS profile AdministratorAccess of the other account"
        func context(_ config: Config) -> AIConfigPrompt.Context {
            var context = Self.context(config)
            context.awsProfiles = profiles
            return context
        }
        for onDevice in [true, false] {
            let host = "assistant-sso-\(onDevice).test"
            let (_, chosen) = try Self.openAIService(ContextLimitedModel(overflows: true), host: host, answer: answer)
            var config = chosen
            config.awsProfile = "ReadOnly-123456789012"
            // Too long for the on-device model, or no Apple Intelligence: the user's provider either way.
            let apple: any AppleModelBackend = onDevice ? ContextLimitedModel(overflows: true) : AIConfigTests.GuidedStub(.deviceNotEligible, answer: "")
            let service = AIConfigService(client: ChatClient(bedrock: BedrockClient(session: StubURLProtocol.session()), apple: apple),
                                          loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                                          loadKey: { provider, keyHost in provider == .openai && keyHost == host ? "sk-test" : nil })
            let got = try await service.ask(sentence, context: context(config), tools: Self.tools)
            let body = RedactionTests.body(StubURLProtocol.lastRequest(host: host))
            #expect(!body.contains("123456789012") && !body.contains("210987654321"), "\(body.prefix(200))")
            #expect(["AdministratorAccess-[account 1]", "ReadOnly-[account 1]", "AdministratorAccess-[account 2]"].allSatisfy(body.contains)
                    && body.contains("now \\\"ReadOnly-[account 1]\\\"") && body.contains("default"), "\(onDevice)")
            #expect(try AIConfig.parse(got.text).changes == [.init(key: .setting(.awsProfile), value: .string("AdministratorAccess-210987654321"))])
        }
        // On the device: the names as they are.
        let model = ContextLimitedModel(contextSize: 8192)
        var small = Config.default
        small.provider = .anthropic
        small.awsProfile = "ReadOnly-123456789012"
        _ = try await Self.service(model).ask(sentence, context: context(small), tools: Self.tools)
        let sent = try #require(model.sent.last)
        #expect(sent.request.instructions.contains(#"now "ReadOnly-123456789012""#)
                && profiles.allSatisfy(ContextLimitedModel.json(sent.schema).contains) && !sent.request.instructions.contains("[account"))
        // A name without one, or with a number of another length, as it is.
        let accounts = AIConfig.AWSAccounts(["dev-1234567890123", "prod-12345678901", "x123456789012y"])
        #expect(accounts.hiding("dev-1234567890123") == "dev-1234567890123" && accounts.hiding("x123456789012y") == "x[account 1]y")
    }

    /// With the on-device model as the provider chosen there is nothing else to ask: the line says what to do, in the
    /// interface language; never the model's own error.
    @Test func tooLongWithoutAProviderSaysWhatToDo() async throws {
        let model = ContextLimitedModel(overflows: true)
        var config = Self.bigConfig()
        config.provider = .apple
        do {
            _ = try await Self.service(model).ask("candidates in a column", context: Self.context(config), tools: Self.tools)
            Issue.record("no error")
        } catch let error as AIConfigService.TooLong {
            #expect(error.provider == nil && error.providerNotSetUp)
            #expect(error.line(language: "en", describe: { _ in "" })
                == "Too long for Apple Intelligence on this Mac: try a shorter request, or choose another AI provider in Settings → AI Provider")
            #expect(error.line(language: "zh-Hans", describe: { _ in "" })
                == "这句话对本机的 Apple Intelligence 来说太长了：请说得短一些，或者在设置 → AI 服务里换一个 AI 服务")
        }
    }

    /// The user's provider isn't set up (no key here): what to set up, and where; a provider that fails otherwise, what it said.
    @Test func tooLongAndTheProviderIsNotSetUp() async throws {
        let model = ContextLimitedModel(overflows: true)
        do {
            _ = try await Self.service(model).ask("candidates in a column", context: Self.context(Self.bigConfig()), tools: Self.tools)
            Issue.record("no error")
        } catch let error as AIConfigService.TooLong {
            #expect(error.provider == .anthropic && error.providerError as? ProviderError == .missingKey(.anthropic) && error.providerNotSetUp)
            #expect(error.line(language: "en", describe: { _ in "unused" })
                == "Too long for Apple Intelligence on this Mac, and Claude API isn't set up: try a shorter request, or set up Claude API in Settings → AI Provider")
        }
        let failed = AIConfigService.TooLong(provider: .gemini, providerError: URLError(.notConnectedToInternet))
        #expect(!failed.providerNotSetUp)
        #expect(failed.line(language: "en", describe: { _ in "No network connection" })
            == "Too long for Apple Intelligence on this Mac, and Gemini API couldn't answer instead: No network connection")
        #expect(failed.line(language: "zh-Hans", describe: { _ in "没有网络连接" })
            == "这句话对本机的 Apple Intelligence 来说太长了，改问 Gemini API 也没成功：没有网络连接")
    }

    /// A sentence too long to fit with any of the settings never goes to the on-device model at all.
    @Test func aSentenceTooLongForTheContextIsNotSentToTheModel() async throws {
        let model = ContextLimitedModel(contextSize: 4096)
        let sentence = String(repeating: "Please make the candidates vertical. ", count: 400)
        await #expect(throws: AIConfigService.TooLong.self) {
            _ = try await Self.service(model).ask(sentence, context: Self.context(Self.bigConfig()), tools: Self.tools)
        }
        #expect(model.sent.isEmpty)
    }

    // MARK: - What the sentence is about

    @Test func whatTheSentenceIsAbout() {
        let context = Self.context(Self.bigConfig())
        func parts(_ text: String, answers: [String] = []) -> [AIConfigPrompt.Part] {
            AIConfigFit.relevance([text], answers: answers, context: context).parts
        }
        #expect(parts("竖排候选") == [.candidateLayout])
        #expect(parts("candidates in a row") == [.candidateLayout])
        #expect(parts("translate into Japanese and French").contains(.outputLanguages))
        #expect(parts("use Claude Sonnet") == [.provider])
        #expect(parts("Bedrock in us-west-2").contains(.aws))
        // Bedrock, Amazon, AWS, Nova: the provider with AWS's settings, in the interface's languages.
        for sentence in ["use Bedrock", "switch to Amazon Nova", "use the AWS profile work", "Bedrock in us-west-2", "改用亚马逊的模型",
                         "改用亞馬遜", "アマゾンの Bedrock を使う", "아마존 Bedrock으로 바꿔 줘", "nimm Amazon Nova",
                         // A Latin word against Chinese, Japanese or Korean is a word of its own.
                         "改用Bedrock", "用AWS的profile work", "AWS로 바꿔 줘", "AWSのプロファイル", "改成us-west-2"] {
            #expect(parts(sentence).contains(.provider) && parts(sentence).contains(.aws), "\(sentence)")
        }
        #expect(parts("用English").contains(.inputLanguages) && parts("改成vertical") == [.candidateLayout])
        // Nova as Amazon's models' name: with Amazon, or a model's ("Nova Lite", "nova-2-lite-v1"); not Portuguese's "new".
        for sentence in ["use Nova Pro", "switch to nova-2-lite-v1", "Nova Liteにして", "us.amazon.nova-2-lite-v1:0", "usar o Nova Micro"] {
            #expect(parts(sentence).contains(.provider) && parts(sentence).contains(.aws), "\(sentence)")
        }
        for sentence in ["uma nova conversa", "novamente em coluna", "nova proposta", "a nova programação", "nova versão 2026"] {
            #expect(!parts(sentence).contains(.provider) && !parts(sentence).contains(.aws), "\(sentence): \(parts(sentence))")
        }
        #expect(AIConfigFit.relevance(["在Slack里用中文"], context: context).apps == ["com.tinyspeck.slackmacgap"])
        for sentence in ["用谷歌的模型", "グーグルに切り替えて", "클로드로 바꿔", "ジェミニを使う", "제미나이로", "用深度求索"] {
            #expect(parts(sentence).contains(.provider), "\(sentence)")
        }
        #expect(parts("hide phone numbers") == [.privacy])
        #expect(parts("打开 iCloud 同步") == [.iCloudSync])
        #expect(parts("关闭自动检查更新") == [.updates])
        #expect(parts("type out slower").contains(.typing))
        // Not a word inside another ("throw" isn't "row", "tip" isn't "ip").
        #expect(parts("throw a tip").isEmpty)
        // An app by any of its names, or its settings' key; what an earlier answer changed.
        let wechat = AIConfigFit.relevance(["微信里用中文"], context: context)
        #expect(wechat.parts.contains(.apps) && wechat.apps == ["com.tencent.xinWeChat"])
        #expect(AIConfigFit.relevance(["com.apple.mail too"], context: context).apps == ["com.apple.mail"])
        #expect(parts("and French", answers: [#"{"changes": [{"key": "appProfiles.*.typeOut", "app": "Slack", "value": true}]}"#])
            .contains(.apps))
    }

    /// Each part's choices in the schema are settings its lines list: the model is never offered a key it isn't told about.
    @Test func eachPartsSchemaMatchesItsLines() {
        let context = Self.context(Self.bigConfig())
        for part in AIConfigPrompt.Part.allCases {
            let scope = AIConfigPrompt.Scope(parts: [part])
            let lines = AIConfigPrompt.settings(context, compact: true, scope: scope)
            #expect(!lines.isEmpty, "\(part)")
            for key in Self.keys(AIConfigPrompt.schema(context, scope: scope)) {
                let listed = key.replacingOccurrences(of: ".*.", with: ".<app>.")
                #expect(lines.contains { $0.hasPrefix(listed + ":") }, "\(part): \(key)")
            }
        }
        // All of them: the request as before.
        #expect(AIConfigPrompt.schema(context, scope: AIConfigPrompt.Scope(parts: Set(AIConfigPrompt.Part.allCases))) == AIConfigPrompt.schema(context))
    }

    // MARK: - Helpers

    /// A sentence about nine of the settings and an app.
    static let nineSettings = "竖排候选，微信里用中文，翻译成日文和法文，打字慢一点，隐藏电话号码，打开 iCloud 同步，用 Bedrock 的 us-west-2，关闭自动更新，记住我的问题"

    /// A service whose user's provider is an OpenAI-compatible one at `host` (a stub that streams `answer`, no network),
    /// with its key; the config that chooses it.
    static func openAIService(_ model: ContextLimitedModel, host: String, answer: String) throws -> (AIConfigService, Config) {
        let chunk = "data: " + String(decoding: try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": answer]]]]), as: UTF8.self)
            + "\n\ndata: [DONE]\n\n"
        StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [Data(chunk.utf8)]))
        let service = AIConfigService(client: ChatClient(bedrock: BedrockClient(session: StubURLProtocol.session()), apple: model),
                                      loadCredentials: { _ in throw AWSConfigError.profileNotFound("none") },
                                      loadKey: { provider, keyHost in provider == .openai && keyHost == host ? "sk-test" : nil })
        var config = bigConfig()
        config.provider = .openai
        config.openai = ProviderSettings(model: "some-model", baseURL: "https://\(host)/v1")
        return (service, config)
    }

    /// The names of the changes a schema allows.
    static func choices(_ schema: GuidedSchema) -> [String] {
        guard case let .object(_, properties) = schema, case let .array(.choice(_, choices), _, _) = properties[0].schema else { return [] }
        return choices.compactMap { if case let .object(name, _) = $0 { return name } else { return nil } }
    }

    /// The keys a schema allows.
    static func keys(_ schema: GuidedSchema) -> [String] {
        guard case let .object(_, properties) = schema, case let .array(.choice(_, choices), _, _) = properties[0].schema else { return [] }
        return choices.flatMap { choice -> [String] in
            guard case let .object(_, fields) = choice, case let .strings(_, keys) = fields[0].schema else { return [] }
            return keys
        }
    }
}
