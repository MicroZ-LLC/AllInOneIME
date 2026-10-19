import Foundation
import Testing
@testable import AllInOneIMECore

/// Stands in for the on-device model with a context of `contextSize` tokens, counted the way FoundationModels counts them
/// near enough (`tokens`): the instructions, the conversation, the prompt, the schema the answer is held to (as the JSON
/// schema the framework puts into the prompt) and the tools' definitions, then the answer. A request that leaves no room
/// for its answer fails with `AppleModelError.contextExceeded`, as the framework's does. `overflows`: every request
/// fails so (the model said so though the request was fitted).
final class ContextLimitedModel: AppleGuidedBackend, @unchecked Sendable {
    let availability: AppleModelAvailability = .available
    let contextSize: Int
    let supportedLanguages: Set<String> = ["en", "zh"]
    let answer: String
    let overflows: Bool
    /// Whether it counts a request's tokens when asked (macOS 26.4 and later); else the core estimates them.
    let counts: Bool
    private let lock = NSLock()
    private var _sent: [(request: AppleModelRequest, schema: GuidedSchema, tools: [String], tokens: Int)] = []
    /// What was sent, and its size in tokens without the answer.
    var sent: [(request: AppleModelRequest, schema: GuidedSchema, tools: [String], tokens: Int)] { lock.withLock { _sent } }

    init(contextSize: Int = 4096, answer: String = #"{"changes": [{"key": "candidateLayout", "value": "vertical"}], "note": "The candidates are in a column now."}"#,
         overflows: Bool = false, counts: Bool = true) {
        self.contextSize = contextSize
        self.answer = answer
        self.overflows = overflows
        self.counts = counts
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: AppleModelError.failed("plain path used")) }
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        let size = Self.tokens(request, schema: schema, tools: tools)
        lock.withLock { _sent.append((request, schema, tools.map(\.name), size)) }
        if overflows || size + Self.tokens(answer) > contextSize { throw AppleModelError.contextExceeded }
        return answer
    }

    func tokenCount(of request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async -> Int? {
        counts ? Self.tokens(request, schema: schema, tools: tools) : nil
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

/// Settings → Assistant on the on-device model, whose context (4096 tokens before macOS 27, 8192 since) holds the
/// instructions, the schema, the tools and the answer together: the request fitted to it.
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
    static func service(_ model: ContextLimitedModel) -> AIConfigService {
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

    /// The estimate is on the high side for every part of the request (where the model can count, its count decides).
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
