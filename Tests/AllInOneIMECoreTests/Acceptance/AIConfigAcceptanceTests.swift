import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for `@config` (spec-ai-config.md, with its CHANGE 1, and the coordinator's decisions), written from
// the spec by an independent reviewer; the implementer may not edit them. Each test names what it enforces:
// "allow" the allowlist, "valid" validation, "prov" provider setup (CHANGE 1), "prompt" the request, "parse" the answer,
// "flow" the panel and undo, "device" on-device first, "noai" apps with no AI.
//
// Nothing here touches the network, the keychain, ~/.aws or ~/.config/allinoneime/config.json: the on-device model is a
// stub (`AICAppleStub`), the configured provider a URLProtocol stub (`AICHTTPStub`), and every config file is a
// temporary one. The input controller is stood in for by `AICRig`, which does with the composer's effects what
// AIConfigController does (`startConfigRequest`, `showConfigAnswer`, `applyConfig`, `undoConfig`); what only the app
// target can do (opening Settings at the key field, running Test Connection) is recorded by the rig instead.

// MARK: - Stubs

/// What a stub model was asked: the request, whether held to a schema, the tools offered and what they returned.
struct AICCall: Sendable {
    var request: AppleModelRequest
    var guided: Bool
    var schema: GuidedSchema?
    var toolNames: [String]
    var toolOutputs: [String]

    /// Everything the model was given, as one text.
    var text: String {
        ([request.instructions] + request.examples.flatMap { [$0.prompt, $0.response] } + [request.prompt] + toolOutputs)
            .joined(separator: "\n")
    }
}

/// Apple's on-device model, scripted: answers the queued texts in order (the last again when they run out), held to
/// the schema it is given (guided generation); calls every tool it is offered once, so what the tools return is
/// recorded as sent to the model.
final class AICAppleStub: AppleGuidedBackend, Sendable {
    let availability: AppleModelAvailability
    var contextSize: Int { 4096 }
    var supportedLanguages: Set<String> { ["en", "zh", "fr", "de", "ja"] }
    private let state: OSAllocatedUnfairLock<(answers: [String], calls: [AICCall])>

    init(_ answers: [String] = [], availability: AppleModelAvailability = .available) {
        self.availability = availability
        state = OSAllocatedUnfairLock(initialState: (answers, []))
    }

    var calls: [AICCall] { state.withLock { $0.calls } }

    func enqueue(_ answer: String) { state.withLock { $0.answers.append(answer) } }

    private func next() -> String {
        state.withLock { s in
            guard let first = s.answers.first else { return #"{"changes": []}"# }
            if s.answers.count > 1 { s.answers.removeFirst() }
            return first
        }
    }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        state.withLock { $0.calls.append(AICCall(request: request, guided: false, schema: nil, toolNames: [], toolOutputs: [])) }
        let text = next()
        return AsyncThrowingStream { continuation in
            continuation.yield(AppleModelSnapshot(text: text))
            continuation.finish()
        }
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        var outputs: [String] = []
        for tool in tools {
            outputs.append(await tool.call(Dictionary(uniqueKeysWithValues: tool.arguments.map { ($0.name, "WeChat") })))
        }
        let call = AICCall(request: request, guided: true, schema: schema, toolNames: tools.map(\.name), toolOutputs: outputs)
        state.withLock { $0.calls.append(call) }
        return next()
    }
}

/// A Claude-API-shaped provider at a test host: replies with queued answers (599 when none), keeps every body.
final class AICHTTPStub: URLProtocol, @unchecked Sendable {
    private static let state = OSAllocatedUnfairLock(initialState: (replies: [String: [String]](), bodies: [String: [Data]]()))

    static func enqueue(_ host: String, _ answer: String) { state.withLock { $0.replies[host, default: []].append(answer) } }
    static func bodies(_ host: String) -> [Data] { state.withLock { $0.bodies[host] ?? [] } }

    /// What the provider was sent, as text: the system prompt and each message's text (JSON escapes undone).
    static func sentTexts(_ host: String) -> [String] {
        bodies(host).map { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return String(decoding: data, as: UTF8.self)
            }
            func text(_ any: Any?) -> String {
                if let s = any as? String { return s }
                if let list = any as? [[String: Any]] { return list.map { text($0["text"] ?? $0["content"]) }.joined(separator: "\n") }
                return ""
            }
            let messages = (json["messages"] as? [[String: Any]] ?? []).map { text($0["content"]) }
            return ([text(json["system"])] + messages).joined(separator: "\n")
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AICHTTPStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    static func sse(_ text: String) -> Data {
        let delta = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text],
        ] as [String: Any])
        return Data([
            "event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1"}}"#, "",
            "event: content_block_delta", "data: " + String(decoding: delta, as: UTF8.self), "",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, "",
            #"data: {"type":"message_stop"}"#, "", "",
        ].joined(separator: "\n").utf8)
    }

    override func startLoading() {
        let request = self.request
        let host = request.url?.host ?? ""
        let body = Self.body(of: request)
        let answer = Self.state.withLock { s -> String? in
            s.bodies[host, default: []].append(body)
            guard var queue = s.replies[host], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            s.replies[host] = queue
            return next
        }
        guard let url = request.url else { return }
        if let answer {
            let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.sse(answer))
        } else {
            let http = HTTPURLResponse(url: url, statusCode: 599, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"type":"error","error":{"type":"api_error","message":"boom"}}"#.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Credentials and keys asked for (the on-device model needs neither).
final class AICSecrets: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)
    func asked() { state.withLock { $0 += 1 } }
    var count: Int { state.withLock { $0 } }
}

struct AICNoCredentials: Error {}

// MARK: - Fixtures

enum AIC {
    /// Keys as a user might paste them (detected by Redaction's key detection: checked in `keysAreKeys`).
    static let claudeKey = "sk-ant-" + "api03-Zx8Qw2Lm4Np6Rt0Vb3Yc5Hd7Jf9Kg1Ms2Pu4Wx6Ab8Cd"
    static let geminiKey = "AIzaSyD3x9Qw2Lm4Np6Rt0Vb3Yc5Hd7Jf9Kg1M"
    static let awsKey = "AKIA" + "ZX8QW2LM4NP6RT0V"

    static let bedrockModels = ["us.anthropic.claude-haiku-4-5-20251001-v1:0", "us.anthropic.claude-opus-5-5-v1:0"]
    static let models: [Provider: [String]] = [
        .bedrock: bedrockModels,
        .anthropic: ["claude-haiku-5-5", "claude-opus-5-5"],
        .gemini: ["gemini-3.8-flash", "gemini-3.8-pro"],
        .openai: ["gpt-6-luna", "gpt-6"],
    ]

    static let wechat = AIConfig.AppCatalog.App(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"])
    static let mail = AIConfig.AppCatalog.App(bundleID: "com.apple.mail", names: ["Mail", "邮件"])
    static let word = AIConfig.AppCatalog.App(bundleID: "com.microsoft.Word", names: ["Microsoft Word"])
    /// Two apps called "Notes": a name that can't be resolved.
    static let notesA = AIConfig.AppCatalog.App(bundleID: "com.apple.Notes", names: ["Notes", "备忘录"])
    static let notesB = AIConfig.AppCatalog.App(bundleID: "com.example.notes", names: ["Notes"])
    static let apps = AIConfig.AppCatalog(apps: [wechat, mail, word, notesA, notesB])

    /// The settings the tests start from: Bedrock, translating into English, Japanese and Chinese, typing Chinese and
    /// English, the 0.6.3 defaults otherwise.
    static var base: Config {
        var config = Config.default
        config.provider = .bedrock
        config.awsProfile = "default"
        config.region = nil
        config.setOrder([OutputLanguage.english, OutputLanguage("ja"), .chinese])
        config.setOrder([Language.chinese, .english])
        return config
    }

    static func env(chinese: Bool = false, missingPacks: Set<Language> = [], hasKey: Set<Provider> = [],
                    offered: [Provider] = [.bedrock, .anthropic, .gemini, .openai],
                    profiles: [String] = ["default", "work"], typed: String = "") -> AIConfig.Environment {
        AIConfig.Environment(
            packInstalled: { !missingPacks.contains($0) }, apps: apps, awsProfiles: { profiles },
            knownModels: { models[$0] ?? [] }, offeredProviders: offered,
            hasKey: { hasKey.contains($0) }, chinese: chinese, typedText: typed)
    }

    /// A sentence naming a base URL's host (a new one must have been typed, or be a known service's).
    static let typedURL = "use my own server at https://api.example.com/v1"

    static func context(_ config: Config, env: AIConfig.Environment = env()) -> AIConfigPrompt.Context {
        AIConfigPrompt.Context(config: config, knownModels: models, awsProfiles: env.awsProfiles(),
                               offeredProviders: env.offeredProviders,
                               installedPacks: Set(Language.allCases.filter(env.packInstalled)))
    }

    /// An answer as the model writes it.
    static func answer(_ changes: [(String, Any)], note: String? = nil) -> String {
        var object: [String: Any] = ["changes": changes.map { ["key": $0.0, "value": $0.1] }]
        if let note { object["note"] = note }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func preview(_ changes: [(String, Any)], config: Config = base, env: AIConfig.Environment = env())
        throws -> Result<AIConfig.Preview, AIConfig.Failure> {
        AIConfig.preview(try AIConfig.parse(answer(changes)), config: config, environment: env)
    }

    /// A config file of its own in a temporary folder, written as Settings writes it; never the user's.
    static func tempConfig(_ config: Config = base) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aic-acceptance-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        precondition(url.standardizedFileURL != Config.defaultURL.standardizedFileURL)
        try config.write(to: url)
        return url
    }

    static func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    /// `config` as it reads back from a file Settings wrote.
    static func roundTrip(_ config: Config) throws -> Config { try Config.load(from: tempConfig(config)) }

    /// The service with the stub as the on-device model and the HTTP stub behind every provider.
    static func service(_ apple: AICAppleStub, secrets: AICSecrets = AICSecrets(), keys: Bool = true) -> AIConfigService {
        AIConfigService(client: ChatClient(bedrock: BedrockClient(session: AICHTTPStub.session()), apple: apple),
                        loadCredentials: { _ in
                            secrets.asked()
                            throw AICNoCredentials()
                        },
                        loadKey: { _, _ in
                            secrets.asked()
                            return keys ? "sk-test-not-a-real-key" : nil
                        })
    }

    static func host() -> String { "aic-\(UUID().uuidString.lowercased()).test" }

    /// `config` on the Claude API at the stub's `host`.
    static func onClaude(_ config: Config, host: String) -> Config {
        var config = config
        config.provider = .anthropic
        config.anthropic.baseURL = "https://\(host)"
        return config
    }
}

private let aicAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
private let aicTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
private let aicCommandZ = KeyEvent(keyCode: 0x06, characters: "z", charactersIgnoringModifiers: "z", modifiers: .command)

/// Nothing went into the text field: no text committed, typed out or put over a selection.
func aicInsertsNothing(_ effects: [Composer.Effect]) -> Bool {
    !effects.contains { effect in
        switch effect {
        case let .commit(text): return !text.isEmpty
        case .typeOut, .replaceSelection: return true
        default: return false
        }
    }
}

// MARK: - The input controller, stood in for

/// A composer and what AIConfigController does with its effects, on a temporary config file.
final class AICRig {
    let composer = Composer(engine: FakeEngine(), actionKey: .enter)
    let url: URL
    var env: AIConfig.Environment
    let apple: AICAppleStub
    let service: AIConfigService
    let secrets = AICSecrets()
    /// What undoes the last changes (kept across panels, like `AIConfigSession.lastApplied`).
    var lastApplied: AIConfig.Applied?
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Settings opened at the key field for these providers.
    var openedKeyField: [Provider] = []
    var testConnections = 0
    var notices: [String] = []
    var effects: [Composer.Effect] = []
    /// The answers the composer was given, and the previews.
    var previews: [AIConfig.Preview] = []

    init(_ config: Config = AIC.base, env: AIConfig.Environment = AIC.env(), apple: AICAppleStub = AICAppleStub(), keys: Bool = true) throws {
        url = try AIC.tempConfig(config)
        self.env = env
        self.apple = apple
        service = AIC.service(apple, secrets: secrets, keys: keys)
        composer.setInputMode(.english)
    }

    var c: Composer { composer }
    var config: Config { (try? Config.load(from: url)) ?? .default }

    @discardableResult
    func key(_ event: KeyEvent) async -> [Composer.Effect] {
        let out = composer.handleKeyDown(event).effects
        effects += out
        await perform(out)
        return out
    }

    func type(_ text: String) async {
        for ch in text {
            if ch == " " {
                await key(spaceKey)
            } else {
                await key(KeyEvent(keyCode: 0, characters: String(ch), modifiers: ch.isUppercase ? .shift : []))
            }
        }
    }

    /// "@config " from the command list, then `text`.
    func draft(_ text: String, command: String = "config") async {
        await key(aicAt)
        await type(command)
        await key(aicTab)
        await type(text)
    }

    /// "@config <text>" and ⏎.
    @discardableResult
    func run(_ text: String) async -> [Composer.Effect] {
        await draft(text)
        return await key(enterKey)
    }

    func perform(_ effects: [Composer.Effect]) async {
        for effect in effects {
            switch effect {
            case let .startCommand(command, input, id) where command.kind == .config:
                await request(input, turns: [], id: id)
            case let .startRefine(refinement, id):
                if case let .command(command, input) = refinement.request, command.kind == .config {
                    await request(input, turns: refinement.turns, id: id)
                }
            case let .applyConfig(preview):
                await apply(preview)
            case .undoConfig:
                undo()
            default:
                break
            }
        }
    }

    /// As `startConfigRequest` and `showConfigAnswer`.
    func request(_ input: String, turns: [Refinement.Turn], id: Int) async {
        let keys = AIConfig.droppingKeys(input)
        if keys.dropped, keys.text.filter(\.isLetter).count < 2 {
            effects += composer.endConfig()
            openedKeyField.append(keys.provider ?? config.provider)
            notices.append(AIConfig.Text(chinese: env.chinese).droppedKey)
            return
        }
        let config = self.config
        var env = self.env
        env.typedText = ([keys.text] + turns.map { AIConfig.droppingKeys($0.instruction).text }).joined(separator: "\n")
        do {
            let tools = AIConfigService.Tools(
                findApps: { [apps = env.apps] in apps.search($0).map { "\($0.name): \($0.bundleID)" }.joined(separator: "\n") },
                awsProfiles: { [profiles = env.awsProfiles()] in profiles.joined(separator: "\n") },
                languagePacks: { "zh: installed" })
            let answer = try await service.ask(keys.text, turns: turns, context: AIC.context(config, env: env), tools: tools)
            let proposal = try? AIConfig.parse(answer.text)
            let outcome = proposal.map { AIConfig.preview($0, config: config, environment: env, droppedKey: (keys.dropped, keys.provider)) }
                ?? .failure(.notUnderstood)
            switch outcome {
            case let .success(preview):
                previews.append(preview)
                effects += composer.receiveConfig(preview, lines: preview.rows.map { $0.text(chinese: env.chinese) },
                                                  answer: answer.text, id: id)
            case let .failure(failure):
                effects += composer.fail(AIConfig.failureLine(failure, proposal: proposal, config: config, environment: env), id: id)
            }
        } catch {
            effects += composer.fail("\(error) (try @doctor)", id: id)
        }
    }

    /// As `applyConfig`.
    func apply(_ preview: AIConfig.Preview) async {
        let text = AIConfig.Text(chinese: env.chinese)
        if !preview.edits.isEmpty {
            do {
                lastApplied = try AIConfig.applying(preview.edits, at: url, now: now)
            } catch {
                effects += composer.configNotApplied("Not saved: \(error)")
                return
            }
        }
        if let provider = preview.needsKey {
            effects += composer.endConfig()
            openedKeyField.append(provider)
            return
        }
        effects += composer.configApplied(text.applied(preview.edits.count))
        guard preview.changesProvider else { return }
        testConnections += 1
        effects += composer.configStatus("✓ Connection works: test")
    }

    /// As `undoConfig`.
    func undo() {
        let text = AIConfig.Text(chinese: env.chinese)
        guard let applied = lastApplied, let report = try? AIConfig.undoing(applied, at: url, now: now) else {
            lastApplied = nil
            notices.append(text.nothingToUndo)
            return
        }
        lastApplied = nil
        notices.append(text.undone(skipped: report.skipped))
    }

    /// The rows shown.
    var rows: [String] { composer.choices.map(\.text) }
}

// MARK: - The tests

struct AIConfigAcceptanceTests {
    // MARK: Allowlist

    /// Every allowed setting (and every app field) can be changed, and applying it changes exactly that setting.
    @Test func allow_everyAllowedSettingWorks() throws {
        let env = AIC.env(hasKey: Set(Provider.allCases), typed: AIC.typedURL)
        typealias Case = (key: String, value: Any, check: (Config) -> Bool)
        let cases: [Case] = [
            ("outputLanguages", ["en", "fr"], { $0.outputLanguages == [.english, OutputLanguage("fr")] }),
            ("inputLanguages", ["en", "zh"], { $0.inputLanguages == [.english, .chinese] }),
            ("defaultInput", "en", { $0.defaultInput == .english }),
            ("rewriteStyles", ["简洁", "口语"], { $0.rewriteStyles == ["简洁", "口语"] }),
            ("candidateLayout", "vertical", { $0.candidateLayout == .vertical }),
            ("typeOut", true, { $0.typeOut }),
            ("typeOutRate", 8, { $0.typeOutRate == 8 }),
            ("typeOutVaries", true, { $0.typeOutVaries }),
            ("typeOutMistakes", true, { $0.typeOutMistakes }),
            ("useSelection", false, { !$0.useSelection }),
            ("rememberQuestions", false, { !$0.rememberQuestions }),
            ("redaction.enabled", true, { $0.redaction.enabled }),
            ("redaction.emails", false, { !$0.redaction.emails }),
            ("redaction.phones", false, { !$0.redaction.phones }),
            ("redaction.cards", false, { !$0.redaction.cards }),
            ("redaction.keys", false, { !$0.redaction.keys }),
            ("redaction.ips", false, { !$0.redaction.ips }),
            ("redaction.customWords.add", ["Nightingale"], { $0.redaction.customWords == ["Nightingale"] }),
            ("checkForUpdates", false, { !$0.checkForUpdates }),
            ("provider", "anthropic", { $0.provider == .anthropic }),
            ("awsProfile", "work", { $0.awsProfile == "work" }),
            ("region", "eu-west-1", { $0.region == "eu-west-1" }),
            ("modelId", AIC.bedrockModels[1], { $0.modelId == AIC.bedrockModels[1] }),
            ("anthropic.model", "claude-opus-5-5", { $0.anthropic.model == "claude-opus-5-5" }),
            ("gemini.model", "gemini-3.8-pro", { $0.gemini.model == "gemini-3.8-pro" }),
            ("openai.model", "gpt-6", { $0.openai.model == "gpt-6" }),
            ("openai.baseURL", "https://api.example.com/v1", { $0.openai.baseURL == "https://api.example.com/v1" }),
            ("appProfiles.WeChat.inputLanguage", "en", { $0.profile(for: AIC.wechat.bundleID)?.inputLanguage == .english }),
            ("appProfiles.WeChat.rewriteStyles", ["正式"], { $0.profile(for: AIC.wechat.bundleID)?.rewriteStyles == ["正式"] }),
            ("appProfiles.WeChat.typeOut", true, { $0.profile(for: AIC.wechat.bundleID)?.typeOut == true }),
            ("appProfiles.WeChat.noAI", true, { $0.profile(for: AIC.wechat.bundleID)?.noAI == true }),
        ]
        // The table covers the whole allowlist.
        let covered = Set(cases.map(\.key))
        for setting in AIConfig.Setting.allCases { #expect(covered.contains(setting.path), "no case for \(setting.path)") }
        for field in AIConfig.AppField.allCases { #expect(covered.contains("appProfiles.WeChat.\(field.rawValue)")) }

        for item in cases {
            let preview = try #require(try? AIC.preview([(item.key, item.value)], env: env).get(), "\(item.key) not previewed")
            let changes = preview.rows.filter { $0.status == .change }
            #expect(changes.count == 1 && preview.edits.count == 1, "\(item.key): \(preview.rows)")
            #expect(!preview.rows.contains { $0.isRefused }, "\(item.key) refused: \(preview.rows)")
            var config = AIC.base
            AIConfig.apply(preview.edits, to: &config)
            #expect(item.check(config), "\(item.key) not applied")
            #expect(!item.check(AIC.base), "\(item.key): the base already has it")
        }
    }

    /// Each kind on the "Never" list is refused in its own row, with a reason, while the allowed part still applies;
    /// only the allowed part is written.
    @Test func allow_forbiddenKindsRefusedPerRowRestApplies() throws {
        let forbidden: [(String, Any)] = [
            // the provider's credentials and API keys
            ("anthropic.apiKey", "x"), ("openai.apiKey", "x"), ("gemini.apiKey", "x"), ("apiKey", "x"),
            ("hosted.token", "x"), ("bedrock.secretAccessKey", "x"),
            // custom commands, extension folders and sources, plugins, jargon paths
            ("customCommands", [["name": "rm", "type": "run", "command": "rm -rf ~"]]),
            ("extensionFolders", ["~/Downloads"]), ("hiddenExtensionFolders", ["~/x"]), ("disabledExtensions", ["x"]),
            ("extensionSources", ["https://example.com/ext.git"]), ("extensionPreferences", ["a": ["b": "c"]]),
            ("plugins", ["evil"]), ("jargonFile", "/etc/passwd"),
            // keys of the config that aren't on the allowlist
            ("voiceInput", false), ("actionKey", "space"), ("maxTokens", 99999), ("claudeInBackground", false),
        ]
        let url = try AIC.tempConfig()
        let before = try AIC.bytes(url)
        let preview = try #require(try AIC.preview([("candidateLayout", "vertical")] + forbidden).get())
        #expect(preview.edits == [.candidateLayout(.vertical)])
        #expect(preview.canApply)
        for (key, _) in forbidden {
            let row = preview.rows.first { $0.key == key }
            #expect(row?.isRefused == true, "\(key) not refused: \(String(describing: row))")
            if case let .refused(reason)? = row?.status { #expect(!reason.isEmpty) }
            #expect(row?.edit == nil && row?.action == nil)
        }
        let applied = try AIConfig.applying(preview.edits, at: url)
        #expect(applied.count == 1)
        var expected = AIC.base
        expected.candidateLayout = .vertical
        #expect(try Config.load(from: url) == AIC.roundTrip(expected))
        #expect(try AIC.bytes(url) != before)
    }

    /// A key that isn't a setting of the config at all makes the answer unreadable (strict parsing): nothing applies.
    @Test func allow_unknownKeyMakesTheAnswerUnreadable() throws {
        #expect(throws: AIConfig.ParseError.unknownKey("fooBar")) {
            try AIConfig.parse(AIC.answer([("candidateLayout", "vertical"), ("fooBar", 1)]))
        }
        #expect(throws: (any Error).self) { try AIConfig.parse(AIC.answer([("aws.secretAccessKey", "x")])) }
    }

    /// A secret-looking key is refused without showing its value, in either language, or in the one failure line.
    @Test func allow_secretKeyValueNeverDisplayed() throws {
        let changes: [(String, Any)] = [("anthropic.apiKey", AIC.claudeKey), ("gemini.apiKey", AIC.geminiKey),
                                        ("awsSecretToken", AIC.awsKey)]
        for chinese in [false, true] {
            let env = AIC.env(chinese: chinese)
            let proposal = try AIConfig.parse(AIC.answer(changes))
            let rows = AIConfig.check(proposal, config: AIC.base, environment: env).rows
            #expect(rows.count == 3 && rows.allSatisfy { $0.isRefused })
            let result = AIConfig.preview(proposal, config: AIC.base, environment: env)
            #expect(result == .failure(.notAllowed))
            let shown = rows.map { $0.text(chinese: chinese) }
                + [AIConfig.failureLine(.notAllowed, proposal: proposal, config: AIC.base, environment: env)]
            for line in shown {
                for secret in [AIC.claudeKey, AIC.geminiKey, AIC.awsKey] { #expect(!line.contains(secret), "shown: \(line)") }
            }
        }
    }

    /// A secret-looking value given for an allowed key (a language, a style, an app, a profile, a region, a URL) is
    /// refused without being shown either.
    @Test func allow_secretValueInAllowedKeyNeverDisplayed() throws {
        let k = AIC.claudeKey
        let changes: [(String, Any)] = [
            ("outputLanguages", [k]), ("inputLanguages", [k]), ("defaultInput", k), ("rewriteStyles", [k]),
            ("awsProfile", k), ("region", k), ("anthropic.model", k), ("openai.baseURL", "https://\(k)@example.com"),
            ("appProfiles.\(k).typeOut", true), ("appProfiles.WeChat.rewriteStyles", [k]),
        ]
        for chinese in [false, true] {
            let env = AIC.env(chinese: chinese)
            let proposal = try AIConfig.parse(AIC.answer(changes))
            let rows = AIConfig.check(proposal, config: AIC.base, environment: env).rows
            #expect(rows.allSatisfy { $0.isRefused })
            for row in rows {
                let line = row.text(chinese: chinese)
                #expect(!line.contains(k), "\(row.key) shows the key: \(line)")
            }
            let line = AIConfig.failureLine(.notAllowed, proposal: proposal, config: AIC.base, environment: env)
            #expect(!line.contains(k))
        }
    }

    /// The model's note is shown over the preview: a key in it isn't.
    @Test func allow_secretInTheNoteNeverDisplayed() throws {
        let proposal = try AIConfig.parse(AIC.answer([("candidateLayout", "vertical")], note: "Saved your key \(AIC.claudeKey)"))
        let preview = try AIConfig.preview(proposal, config: AIC.base, environment: AIC.env()).get()
        let note = preview.note ?? ""
        #expect(!note.contains(AIC.claudeKey))
    }

    // MARK: Validation

    @Test func valid_outputLanguages() throws {
        func reason(_ value: Any) throws -> String? {
            let rows = AIConfig.check(try AIConfig.parse(AIC.answer([("outputLanguages", value)])), config: AIC.base,
                                      environment: AIC.env()).rows
            if case let .refused(reason)? = rows.first?.status { return reason }
            return nil
        }
        #expect(try reason(["en", "xx"]) != nil)  // a language the app doesn't know
        #expect(try reason(["en", "Klingon"]) != nil)
        #expect(try reason(["en", "fr", "de", "es", "it", "pt"]) != nil)  // six: more than 5
        #expect(try reason([String]()) != nil)  // none
        #expect(try reason("en") != nil)  // not a list
        #expect(try reason(["en", "fr", "de", "es", "it"]) == nil)  // five is fine
        let five = try AIC.preview([("outputLanguages", ["en", "fr", "de", "es", "it"])]).get()
        #expect(five.edits == [.outputLanguages(["en", "fr", "de", "es", "it"].map(OutputLanguage.init))])
        #expect(try AIC.preview([("outputLanguages", ["en", "fr", "de", "es", "it", "pt"])]) == .failure(.notAllowed))
    }

    @Test func valid_rangesAndTypes() throws {
        for bad: Any in [41, 1000, 0.1, 0, -3, "fast", true] {
            let result = try AIC.preview([("typeOutRate", bad)])
            #expect(result == .failure(.notAllowed), "typeOutRate \(bad)")
        }
        for good: Any in [40, 1.0 / 6, 1, 25] {
            #expect((try? AIC.preview([("typeOutRate", good)]).get()) != nil, "typeOutRate \(good)")
        }
        #expect(try AIC.preview([("candidateLayout", "diagonal")]) == .failure(.notAllowed))
        #expect(try AIC.preview([("typeOut", "yes")]) == .failure(.notAllowed))
        #expect(try AIC.preview([("rewriteStyles", ["Shakespearean"])]) == .failure(.notAllowed))
        #expect(try AIC.preview([("defaultInput", "fr")]) == .failure(.notAllowed))  // not one of the input languages
        #expect(try AIC.preview([("inputLanguages", ["zh", "en", "fr", "ko", "hi", "de"])]) == .failure(.notAllowed))
    }

    /// Coordinator: a language whose pack isn't installed is refused in its row, pointing to Settings → Input; nothing
    /// is downloaded.
    @Test func valid_missingPackRefusedPointingToSettings() throws {
        for chinese in [false, true] {
            let env = AIC.env(chinese: chinese, missingPacks: [.korean])
            let proposal = try AIConfig.parse(AIC.answer([("inputLanguages", ["zh", "en", "ko"]), ("candidateLayout", "vertical")]))
            let preview = try AIConfig.preview(proposal, config: AIC.base, environment: env).get()
            let row = try #require(preview.rows.first { $0.key == "inputLanguages" })
            #expect(row.isRefused && row.edit == nil)
            let line = row.text(chinese: chinese)
            #expect(chinese ? line.contains("设置") && line.contains("输入") : line.contains("Settings") && line.contains("Input"), "\(line)")
            #expect(preview.actions.isEmpty)  // no download
            #expect(preview.edits == [.candidateLayout(.vertical)])
        }
        // With the pack there, the same change is fine.
        #expect((try? AIC.preview([("inputLanguages", ["zh", "en", "ko"])]).get())?.edits == [.inputLanguages([.chinese, .english, .korean])])
    }

    /// An app named in the answer is resolved to its bundle id: found (by name, by its Chinese name, by bundle id),
    /// none, or ambiguous; never a guess.
    @Test func valid_perAppResolution() throws {
        #expect(AIC.apps.resolve("WeChat") == .found(bundleID: AIC.wechat.bundleID, name: "WeChat"))
        #expect(AIC.apps.resolve("微信") == .found(bundleID: AIC.wechat.bundleID, name: "WeChat"))
        #expect(AIC.apps.resolve("com.tencent.xinwechat") == .found(bundleID: AIC.wechat.bundleID, name: "WeChat"))
        #expect(AIC.apps.resolve("Frobnicator") == .none)
        if case .ambiguous = AIC.apps.resolve("Notes") {} else { Issue.record("Notes should be ambiguous") }

        let found = try AIC.preview([("appProfiles.微信.inputLanguage", "zh")]).get()
        #expect(found.rows.map(\.key) == ["appProfiles.com.tencent.xinWeChat.inputLanguage"])
        #expect(found.edits.count == 1)
        var config = AIC.base
        AIConfig.apply(found.edits, to: &config)
        #expect(config.appProfiles.keys.sorted() == ["com.tencent.xinWeChat"])
        #expect(config.profile(for: "com.tencent.xinWeChat")?.inputLanguage == .chinese)

        for name in ["Frobnicator", "Notes"] {
            let proposal = try AIConfig.parse(AIC.answer([("appProfiles.\(name).typeOut", true), ("typeOut", true)]))
            let preview = try AIConfig.preview(proposal, config: AIC.base, environment: AIC.env()).get()
            let row = try #require(preview.rows.first { $0.key.hasPrefix("appProfiles.") })
            #expect(row.isRefused, "\(name)")
            #expect(preview.edits == [.flag(.typeOut, true)])
        }
        // An app's input language must be one of the input languages, as in Settings → Apps.
        #expect(try AIC.preview([("appProfiles.WeChat.inputLanguage", "fr")]) == .failure(.notAllowed))
    }

    /// Whatever the answer asks for, what is written is a config Settings would write: it loads, and @doctor's config
    /// checks find no problem in it; when nothing can be applied, nothing is written.
    @Test func valid_invalidConfigNeverWritten() async throws {
        let url = try AIC.tempConfig()
        let answers: [[(String, Any)]] = [
            [("outputLanguages", ["en", "fr", "de", "es", "it", "pt"]), ("typeOutRate", 500), ("candidateLayout", "vertical")],
            [("inputLanguages", ["zh", "en", "fr", "ko", "hi", "de"]), ("defaultInput", "de"), ("typeOut", true)],
            [("region", "mars-1"), ("openai.baseURL", "http://insecure.example.com"), ("useSelection", false)],
        ]
        for changes in answers {
            let preview = try AIC.preview(changes).get()
            #expect(preview.edits.count == 1, "\(preview.rows)")
            _ = try AIConfig.applying(preview.edits, at: url)
            let data = try AIC.bytes(url)
            let config = try Config.load(from: url)
            let problems = Doctor.configFindings(data: data, error: nil, config: config, chinese: false).filter { $0.status != .ok }
            #expect(problems.isEmpty, "\(problems)")
            #expect(config.outputLanguages.count <= 5 && config.inputLanguages.count <= 5)
            #expect(config.typeOutRate <= TypeOut.fastestRate && config.typeOutRate >= TypeOut.slowestRate * 0.999)
            #expect(config.region == nil && config.openai.baseURL == nil)
        }
        // Nothing allowed: no preview, and the rig writes nothing.
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("outputLanguages", ["xx"]), ("customCommands", [])])]))
        let original = try AIC.bytes(rig.url)
        await rig.run("translate into Klingon")
        guard case let .failed(line) = rig.c.phase else { Issue.record("no failure line: \(rig.c.phase)"); return }
        #expect(!line.contains("\n"))
        let back = await rig.key(enterKey)
        #expect(!back.contains { if case .applyConfig = $0 { return true } else { return false } })
        #expect(try AIC.bytes(rig.url) == original)
    }

    // MARK: Provider setup (CHANGE 1)

    @Test func prov_providerMustBeOffered() throws {
        let env = AIC.env(offered: [.bedrock, .anthropic, .gemini, .openai])
        #expect(try AIC.preview([("provider", "anthropic")], env: env).get().edits == [.provider(.anthropic)])
        #expect(try AIC.preview([("provider", "hosted")], env: env) == .failure(.notAllowed))
        #expect(try AIC.preview([("provider", "apple")], env: env) == .failure(.notAllowed))
        #expect(try AIC.preview([("provider", "martian")], env: env) == .failure(.notAllowed))
        let withApple = AIC.env(offered: [.bedrock, .apple])
        #expect(try AIC.preview([("provider", "apple")], env: withApple).get().edits == [.provider(.apple)])
    }

    /// The AWS profile must exist (the profiles are injected, never read from ~/.aws here); the region must be valid.
    @Test func prov_awsProfileAndRegion() throws {
        let env = AIC.env(profiles: ["default", "work"])
        #expect(try AIC.preview([("awsProfile", "work")], env: env).get().edits == [.awsProfile("work")])
        #expect(try AIC.preview([("awsProfile", "personal")], env: env) == .failure(.notAllowed))
        #expect(try AIC.preview([("awsProfile", "work")], env: AIC.env(profiles: [])) == .failure(.notAllowed))
        #expect(try AIC.preview([("region", "eu-west-1")]).get().edits == [.region("eu-west-1")])
        #expect(try AIC.preview([("region", "mars-north-1")]) == .failure(.notAllowed))
        #expect(try AIC.preview([("region", "us-west-2; rm -rf")]) == .failure(.notAllowed))
        var inRegion = AIC.base
        inRegion.region = "us-west-2"
        #expect(try AIC.preview([("region", NSNull())], config: inRegion).get().edits == [.region(nil)])
    }

    @Test func prov_modelsFromTheKnownList() throws {
        #expect(try AIC.preview([("anthropic.model", "claude-opus-5-5")]).get().edits == [.model(.anthropic, "claude-opus-5-5")])
        #expect(try AIC.preview([("anthropic.model", "claude-made-up-9")]) == .failure(.notAllowed))
        #expect(try AIC.preview([("modelId", "us.anthropic.claude-made-up")]) == .failure(.notAllowed))
        #expect(try AIC.preview([("gemini.model", "gpt-6")]) == .failure(.notAllowed))  // another provider's model
        #expect(try AIC.preview([("openai.model", "gpt-6")]).get().edits == [.model(.openai, "gpt-6")])
    }

    @Test func prov_baseURLMustBeHTTPS() throws {
        #expect(try AIC.preview([("openai.baseURL", "https://api.deepseek.com/v1")]).get().edits == [.baseURL("https://api.deepseek.com/v1")])
        for bad in ["http://api.deepseek.com/v1", "ftp://example.com", "file:///etc/passwd", "https://", "api.deepseek.com",
                    "javascript:alert(1)"] {
            #expect(try AIC.preview([("openai.baseURL", bad)]) == .failure(.notAllowed), "\(bad)")
        }
    }

    /// Sign-off rule: a new base URL whose host the user never typed (and that isn't a known service) is refused with
    /// "type the address yourself": the model can't send the key-bearing requests somewhere the user didn't name.
    @Test func prov_baseURLUnknownHostNotTypedRefused() throws {
        for chinese in [false, true] {
            for typed in ["", "use an OpenAI-compatible service", "use my server at https://other.example.org/v1"] {
                let env = AIC.env(chinese: chinese, typed: typed)
                let proposal = try AIConfig.parse(AIC.answer([("openai.baseURL", "https://llm.attacker.example/v1"), ("typeOut", true)]))
                let preview = try AIConfig.preview(proposal, config: AIC.base, environment: env).get()
                let row = try #require(preview.rows.first { $0.key == "openai.baseURL" })
                #expect(row.isRefused && row.edit == nil, "typed: \(typed)")
                let line = row.text(chinese: chinese)
                #expect(chinese ? line.contains("请自己输入这个地址") : line.contains("type the address yourself"), "\(line)")
                #expect(preview.edits == [.flag(.typeOut, true)])
            }
        }
    }

    /// Edge: the host must be the one typed, not a part of it ("llm.example.com" inside "myllm.example.com").
    @Test func prov_baseURLHostOnlyInsideATypedHostRefused() throws {
        let env = AIC.env(typed: "use my server at https://myllm.example.com/v1")
        #expect(try AIC.preview([("openai.baseURL", "https://llm.example.com/v1")], env: env) == .failure(.notAllowed))
        let other = AIC.env(typed: "point it at https://api.example.com.mine.dev/v1")
        #expect(try AIC.preview([("openai.baseURL", "https://api.example.com/v1")], env: other) == .failure(.notAllowed))
    }

    /// A host the user typed (in the sentence, or a refine's line) is accepted.
    @Test func prov_baseURLTypedHostAccepted() async throws {
        let url = "https://llm.mycompany.example/v1"
        let env = AIC.env(typed: "point it at \(url) please")
        #expect(try AIC.preview([("openai.baseURL", url)], env: env).get().edits == [.baseURL(url)])
        #expect(try AIC.preview([("openai.baseURL", "https://LLM.MyCompany.example/v1")], env: env).get().edits.count == 1)
        // Through the panel: typed in the sentence, then in a refine's line.
        let answer = AIC.answer([("openai.baseURL", url)])
        let rig = try AICRig(apple: AICAppleStub([answer]))
        await rig.run("use llm.mycompany.example as the base URL")
        #expect(rig.previews.last?.edits == [.baseURL(url)], "\(rig.rows)")
        await rig.key(enterKey)
        #expect(rig.config.openai.baseURL == url)
        let refined = try AICRig(apple: AICAppleStub([AIC.answer([("typeOut", true)]), answer]))
        await refined.run("type results out")
        await refined.type("and use llm.mycompany.example")
        await refined.key(acceptanceShiftReturn)
        #expect(refined.previews.last?.edits == [.baseURL(url)], "\(refined.rows)")
    }

    /// A known service's host (Settings' list) needs no typing.
    @Test func prov_baseURLKnownServiceAccepted() throws {
        for url in ["https://api.deepseek.com/v1", "https://openrouter.ai/api/v1", "https://api.moonshot.cn/v1"] {
            #expect(try AIC.preview([("openai.baseURL", url)], env: AIC.env(typed: "")).get().edits == [.baseURL(url)], "\(url)")
        }
        #expect(AIConfig.compatibleHosts.contains("api.deepseek.com"))
    }

    /// Credentials or a key in the URL are refused, as before, even with the host typed or known; the key isn't shown.
    @Test func prov_baseURLWithCredentialsOrAQueryKeyRefused() throws {
        let urls = ["https://user:hunter2@api.deepseek.com/v1", "https://user@api.deepseek.com/v1",
                    "https://api.deepseek.com/v1?api_key=\(AIC.claudeKey)", "https://api.deepseek.com/v1?key=\(AIC.geminiKey)",
                    "https://llm.mycompany.example/v1?token=\(AIC.claudeKey)"]
        for url in urls {
            let env = AIC.env(typed: "use \(url)")
            let proposal = try AIConfig.parse(AIC.answer([("openai.baseURL", url)]))
            #expect(AIConfig.preview(proposal, config: AIC.base, environment: env) == .failure(.notAllowed), "\(url)")
            for row in AIConfig.check(proposal, config: AIC.base, environment: env).rows {
                let line = row.text(chinese: false)
                #expect(!line.contains(AIC.claudeKey) && !line.contains(AIC.geminiKey) && !line.contains("hunter2"), "\(line)")
            }
        }
    }

    /// Sign-off: at most 20 words are added at a time, each one line of at most 64 characters; the rest is refused on
    /// its own row, and the words already hidden stay.
    @Test func valid_customWordsCapped() throws {
        var config = AIC.base
        config.redaction.customWords = ["Alpha"]
        let many = (1...25).map { "Word\($0)" }
        let preview = try AIC.preview([("redaction.customWords.add", many)], config: config).get()
        #expect(preview.edits == [.addWords(Array(many.prefix(20)))])
        let refused = preview.rows.filter { $0.isRefused }
        #expect(refused.count == 1 && refused[0].text(chinese: false).contains("5"), "\(preview.rows)")
        var after = config
        AIConfig.apply(preview.edits, to: &after)
        #expect(after.redaction.customWords == ["Alpha"] + many.prefix(20))

        // Ordinary words (a run of one letter would look like a key, refused for that instead).
        let fits = String(repeating: "word ", count: 12) + "abcd", long = fits + "e"
        #expect(fits.count == 64 && long.count == 65 && !AIConfig.looksLikeKey(long))
        let shaped = try AIC.preview([("redaction.customWords.add", ["ok", "two\nlines", long, fits])], config: config).get()
        #expect(shaped.edits == [.addWords(["ok", fits])])
        #expect(shaped.rows.contains { $0.isRefused })
        #expect(try AIC.preview([("redaction.customWords.add", [long, "a\nb"])], config: config) == .failure(.notAllowed))
        #expect(AIConfig.maxWordsAdded == 20 && AIConfig.maxWordLength == 64)
    }

    /// Sign-off: keys this version doesn't know, and the known ones @config didn't change, survive an apply and an undo
    /// as they were in the file.
    @Test func flow_unknownKeysSurviveApplyAndUndo() throws {
        let url = try AIC.tempConfig()
        let extra: [String: AIConfig.JSONValue] = [
            "futureSetting": .object(["nested": .array([.number(1), .string("two")])]), "zzFromANewerVersion": .string("keep me"),
            "questionRounds": .number(3),
        ]
        try AIConfig.patchingFile(at: url) { file in for (key, value) in extra { file[key] = value } }
        func object() throws -> [String: AIConfig.JSONValue] {
            let any = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard case let .object(file)? = AIConfig.JSONValue(any) else { return [:] }
            return file
        }
        let before = try object()
        let applied = try AIConfig.applying([.outputLanguages([.english, OutputLanguage("fr")]), .candidateLayout(.vertical)], at: url)
        let after = try object()
        for (key, value) in extra { #expect(after[key] == value, "\(key) after apply") }
        #expect(try Config.load(from: url).outputLanguages == [.english, OutputLanguage("fr")])
        #expect(try AIConfig.undo(applied, at: url))
        let undone = try object()
        #expect(undone == before)
    }

    /// Sign-off: undo leaves a key changed since (in Settings, by hand) as it is, puts back the others, and says which
    /// it left.
    @Test func flow_undoSkipsKeysChangedSinceAndSaysSo() async throws {
        let url = try AIC.tempConfig()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let applied = try AIConfig.applying([.outputLanguages([.english, OutputLanguage("fr")]), .candidateLayout(.vertical)], at: url, now: t)
        var changed = try Config.load(from: url)
        changed.setOrder([OutputLanguage("de")])
        try changed.write(to: url)
        let report = try #require(try AIConfig.undoing(applied, at: url, now: t.addingTimeInterval(60)))
        #expect(report.undone == 1 && report.skipped.count == 1)
        let config = try Config.load(from: url)
        #expect(config.outputLanguages == [OutputLanguage("de")])
        #expect(config.candidateLayout == .horizontal)
        let line = AIConfig.Text(chinese: false).undone(skipped: report.skipped)
        #expect(line.contains("Translation languages") && line != AIConfig.Text(chinese: false).undone, "\(line)")
        #expect(AIConfig.Text(chinese: true).undone(skipped: report.skipped).contains("翻译语言"))

        // Through the panel: `@config undo` says so.
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("outputLanguages", ["en", "fr"]), ("candidateLayout", "vertical")])]))
        await rig.run("English and French, candidates in a column")
        await rig.key(enterKey)
        await rig.key(escKey)
        var edited = rig.config
        edited.candidateLayout = .horizontal
        edited.typeOut = true
        try edited.write(to: rig.url)
        await rig.run("undo")
        #expect(rig.config.outputLanguages == AIC.base.outputLanguages)
        #expect(rig.config.candidateLayout == .horizontal && rig.config.typeOut)
        #expect(rig.notices.last?.contains("Candidate layout") == true, "\(rig.notices)")
    }

    /// Sign-off: `questionRounds` and `questionContinueIn` are the config's own keys: refused here like any key off the
    /// allowlist, not an unreadable answer.
    @Test func allow_questionKeysAreKnownConfigKeys() throws {
        for key in ["questionRounds", "questionContinueIn"] {
            guard case .forbidden? = AIConfig.Key.parse(key) else { Issue.record("\(key): \(String(describing: AIConfig.Key.parse(key)))"); continue }
            #expect(Config.allKeys.contains(key))
        }
        let preview = try AIC.preview([("questionRounds", 9), ("typeOut", true)]).get()
        #expect(preview.rows.first { $0.key == "questionRounds" }?.isRefused == true)
        #expect(preview.edits == [.flag(.typeOut, true)])
    }

    /// Sign-off: what @config may know of the AWS profiles is their names and regions, read from the files the
    /// environment names (never a key, a token or another setting).
    @Test func prov_awsProfilesHoldNamesAndRegionsOnly() throws {
        let secrets = [AIC.awsKey, "wJalrXUtnFEMI/K7MDENG" + "/bPxRfiCYEXAMPLEKEY", "IQoJb3JpZ2luX2VjEXAMPLETOKEN",
                       "https://my-sso-portal.awsapps.com/start", "arn:aws:iam::123456789012:role/Admin", "/usr/local/bin/get-creds"]
        let config = """
            [default]
            region = us-west-2
            output = json

            [profile work]
            region=eu-west-1
            role_arn = \(secrets[4])
            source_profile = default

            [profile sso]
            sso_start_url = \(secrets[3])
            sso_region = us-east-1

            [profile scripted]
            credential_process = \(secrets[5])
            region = ap-northeast-1

            [sso-session corp]
            sso_start_url = \(secrets[3])
            """
        let credentials = """
            [default]
            aws_access_key_id = \(secrets[0])
            aws_secret_access_key = \(secrets[1])
            aws_session_token = \(secrets[2])

            [personal]
            aws_access_key_id = \(secrets[0])
            aws_secret_access_key = \(secrets[1])
            region = us-east-2
            """
        let expected = [AIConfig.AWSProfile(name: "default", region: "us-west-2"), AIConfig.AWSProfile(name: "personal", region: "us-east-2"),
                        AIConfig.AWSProfile(name: "scripted", region: "ap-northeast-1"), AIConfig.AWSProfile(name: "sso", region: nil),
                        AIConfig.AWSProfile(name: "work", region: "eu-west-1")]
        let profiles = AIConfig.awsProfiles(config: config, credentials: credentials)
        #expect(Set(profiles.map(\.name)) == Set(expected.map(\.name)))
        #expect(profiles.first?.name == "default")
        for profile in expected { #expect(profiles.contains(profile), "\(profile)") }
        let dump = String(describing: profiles) + String(reflecting: profiles)
        for secret in secrets { #expect(!dump.contains(secret), "\(secret)") }
        #expect(Mirror(reflecting: profiles[0]).children.compactMap(\.label).sorted() == ["name", "region"])
        // The files the environment names, never ~/.aws here.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aic-aws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try config.write(to: folder.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try credentials.write(to: folder.appendingPathComponent("credentials"), atomically: true, encoding: .utf8)
        let fromFiles = AIConfig.awsProfiles(environment: ["AWS_CONFIG_FILE": folder.appendingPathComponent("config").path,
                                                           "AWS_SHARED_CREDENTIALS_FILE": folder.appendingPathComponent("credentials").path])
        #expect(fromFiles == profiles)
    }

    /// A provider that needs a key it hasn't got: a row says the key is entered in Settings (never sent to the AI),
    /// and applying opens the key field; with the key saved, no such row.
    @Test func prov_needsKeyRowOpensTheKeyField() async throws {
        let preview = try AIC.preview([("provider", "anthropic")], env: AIC.env(hasKey: [])).get()
        #expect(preview.needsKey == .anthropic)
        let row = try #require(preview.rows.first { if case .needsKey = $0.status { return true } else { return false } })
        #expect(row.text(chinese: false).contains("Settings") && row.text(chinese: false).contains("never sent"))
        #expect(row.edit == nil)
        let zh = try AIC.preview([("provider", "anthropic")], env: AIC.env(chinese: true, hasKey: [])).get()
        #expect(zh.rows.last?.text(chinese: true).contains("设置") == true)
        #expect(try AIC.preview([("provider", "anthropic")], env: AIC.env(hasKey: [.anthropic])).get().needsKey == nil)
        #expect(try AIC.preview([("awsProfile", "work")], env: AIC.env(hasKey: [])).get().needsKey == nil)

        // Through the panel: ⏎ applies the provider, then the key field opens; nothing is inserted.
        let rig = try AICRig(env: AIC.env(hasKey: []), apple: AICAppleStub([AIC.answer([("provider", "gemini")])]))
        await rig.run("switch to Gemini")
        #expect(rig.rows.contains { $0.contains("API key") })
        let applied = await rig.key(enterKey)
        #expect(rig.openedKeyField == [.gemini])
        #expect(rig.config.provider == .gemini)
        #expect(aicInsertsNothing(rig.effects) && aicInsertsNothing(applied))
    }

    /// Redaction's key detection finds the keys these tests type.
    @Test func prov_keysAreKeys() {
        for key in [AIC.claudeKey, AIC.geminiKey, AIC.awsKey] { #expect(AIConfig.droppingKeys(key).dropped, "\(key)") }
        #expect(AIConfig.droppingKeys(AIC.claudeKey).provider == .anthropic)
        #expect(AIConfig.droppingKeys(AIC.geminiKey).provider == .gemini)
    }

    /// A key typed as the whole sentence: nothing is sent, the key field opens, nothing is inserted.
    @Test func prov_keyAloneIsNeverSent() async throws {
        let host = AIC.host()
        let unavailable = AICAppleStub(availability: .appleIntelligenceNotEnabled)
        for apple in [AICAppleStub(), unavailable] {
            let rig = try AICRig(AIC.onClaude(AIC.base, host: host), apple: apple)
            await rig.run(AIC.claudeKey)
            #expect(apple.calls.isEmpty)
            #expect(rig.openedKeyField == [.anthropic])
            #expect(rig.notices.contains(AIConfig.Text(chinese: false).droppedKey))
            #expect(aicInsertsNothing(rig.effects))
        }
        #expect(AICHTTPStub.bodies(host).isEmpty)
    }

    /// A key typed among other words is dropped before the request, on the device and on the configured provider;
    /// the preview warns and offers the key field.
    @Test func prov_keyMixedWithTextIsDroppedBeforeTheRequest() async throws {
        let sentence = "use Claude with my key \(AIC.claudeKey) please"
        let answer = AIC.answer([("provider", "anthropic")])
        // On the device.
        let apple = AICAppleStub([answer])
        let rig = try AICRig(env: AIC.env(hasKey: [.anthropic]), apple: apple)
        await rig.run(sentence)
        let call = try #require(apple.calls.first)
        #expect(!call.text.contains(AIC.claudeKey) && !call.text.contains("sk-ant-api03"))
        #expect(call.text.contains("use Claude with my key"))
        let preview = try #require(rig.previews.last)
        #expect(preview.droppedKey)
        #expect(preview.needsKey == .anthropic)  // the key field, even though one is saved: the user meant to give one

        // On the configured provider (Apple Intelligence off).
        let host = AIC.host()
        AICHTTPStub.enqueue(host, answer)
        let cloud = try AICRig(AIC.onClaude(AIC.base, host: host), apple: AICAppleStub(availability: .deviceNotEligible))
        await cloud.run(sentence)
        let sent = AICHTTPStub.sentTexts(host)
        #expect(sent.count == 1)
        #expect(sent.allSatisfy { !$0.contains(AIC.claudeKey) && !$0.contains("sk-ant-api03") })
        #expect(sent.first?.contains("use Claude with my key") == true)
        #expect(AICHTTPStub.bodies(host).allSatisfy { !String(decoding: $0, as: UTF8.self).contains(AIC.claudeKey) })
    }

    /// Edge: a key typed into the refine line ("also use this key …") is typed into the @config sentence too: it
    /// mustn't reach the model either.
    @Test func prov_keyTypedWhileRefiningIsNotSent() async throws {
        let apple = AICAppleStub([AIC.answer([("candidateLayout", "vertical")]), AIC.answer([("provider", "anthropic")])])
        let rig = try AICRig(apple: apple)
        await rig.run("candidates in a column")
        #expect(rig.c.phase == .choosing)
        await rig.type("also use Claude with \(AIC.claudeKey)")
        await rig.key(acceptanceShiftReturn)  // ⇧⏎ sends the refine (CHANGE 2)
        #expect(apple.calls.count == 2)
        for call in apple.calls { #expect(!call.text.contains(AIC.claudeKey), "the refine sent the key") }
    }

    /// Test Connection runs once a provider change is applied, and its line shows under the confirmation; not after
    /// other changes.
    @Test func prov_testConnectionAfterAProviderChange() async throws {
        for (key, value) in [("provider", "openai"), ("awsProfile", "work"), ("region", "eu-west-1"),
                             ("modelId", AIC.bedrockModels[1]), ("openai.baseURL", "https://api.deepseek.com/v1")] as [(String, Any)] {
            #expect(try AIC.preview([(key, value)], env: AIC.env(hasKey: [.openai])).get().changesProvider, "\(key)")
        }
        #expect(try AIC.preview([("candidateLayout", "vertical")]).get().changesProvider == false)

        let rig = try AICRig(env: AIC.env(hasKey: [.anthropic]), apple: AICAppleStub([AIC.answer([("provider", "anthropic")])]))
        await rig.run("use Claude")
        await rig.key(enterKey)
        #expect(rig.testConnections == 1)
        #expect(rig.rows.count == 2 && rig.rows.last?.contains("Connection") == true)

        let other = try AICRig(apple: AICAppleStub([AIC.answer([("candidateLayout", "vertical")])]))
        await other.run("candidates in a column")
        await other.key(enterKey)
        #expect(other.testConnections == 0)
    }

    // MARK: The prompt

    /// The settings with values nothing may send: other keys of the config, words hidden from the AI, paths.
    static var loaded: Config {
        var config = AIC.base
        config.jargonFile = "/Users/someone/SENTINEL-JARGON.txt"
        config.customCommands = [CustomCommand(name: "sentinelcmd", type: .prompt, prompt: "SENTINEL-PROMPT-TEXT")]
        config.extensionFolders = ["~/SENTINEL-EXT-FOLDER"]
        config.hiddenExtensionFolders = ["~/SENTINEL-HIDDEN-FOLDER"]
        config.disabledExtensions = ["SENTINEL-DISABLED"]
        config.extensionPreferences = ["bundle": ["token": "SENTINEL-PREF-VALUE"]]
        config.keyboardLayouts = ["fr": "com.apple.keylayout.SENTINEL"]
        config.anthropic.baseURL = "https://sentinel-anthropic.example"
        config.gemini.baseURL = "https://sentinel-gemini.example"
        config.redaction.customWords = ["Nightingale-Sentinel", "Project Bluebird"]
        config.maxTokens = 4321
        config.timeoutSeconds = 77
        config.appProfiles = ["com.tencent.xinWeChat": AppProfile(inputLanguage: .chinese)]
        return config
    }

    static let sentinels = ["SENTINEL", "Nightingale", "Bluebird", "sentinelcmd", "/Users/someone", "4321"]
    static let otherKeys = ["customCommands", "jargonFile", "extensionFolders", "hiddenExtensionFolders", "disabledExtensions",
                            "extensionPreferences", "keyboardLayouts", "maxTokens", "timeoutSeconds", "claudeInBackground",
                            "menuBarIcon", "fuzzyPinyin", "voiceInput", "actionKey", "uiLanguage", "improveTranslates",
                            "customWords\"", "apiKey"]

    @Test func prompt_onlyAllowlistedCurrentValues() throws {
        for compact in [false, true] {
            let request = AIConfigPrompt.request("candidates in a column", context: AIC.context(Self.loaded), compact: compact)
            let text = (request.system.map(\.text) + request.messages.map { $0.content.map(\.text).joined() }).joined(separator: "\n")
            for sentinel in Self.sentinels { #expect(!text.contains(sentinel), "compact \(compact): \(sentinel) sent") }
            for key in Self.otherKeys { #expect(!text.contains(key), "compact \(compact): \(key) sent") }
            // The allowlisted values as they are now.
            #expect(text.contains(#"["en","ja","zh"]"#), "the output languages now")
            #expect(text.contains(#"["zh","en"]"#), "the input languages now")
            #expect(text.contains("horizontal"))
            #expect(text.contains("com.tencent.xinWeChat"))
            #expect(text.contains("candidates in a column"))
            for setting in AIConfig.Setting.allCases { #expect(text.contains(setting.path), "\(setting.path) not offered") }
        }
        // The on-device schema doesn't carry them either.
        let schema = String(describing: AIConfigPrompt.schema(AIC.context(Self.loaded)))
        for sentinel in Self.sentinels { #expect(!schema.contains(sentinel)) }
    }

    /// The allowlist comes with its types and allowed values: the languages and styles the app knows.
    @Test func prompt_listsAllowedValues() {
        let request = AIConfigPrompt.request("x", context: AIC.context(AIC.base))
        let system = request.system.map(\.text).joined()
        for code in ["en", "fr", "de", "zh-Hant", "ja"] { #expect(system.contains(code)) }
        for style in RewriteStyle.catalog { #expect(system.contains(style.name)) }
        #expect(system.contains("vertical") && system.contains("horizontal"))
        #expect(system.contains("5"))  // at most five languages
        #expect(system.contains("https"))
    }

    /// End to end: what the service sends on the device holds nothing beyond the allowlist, and asks for no key.
    @Test func prompt_serviceSendsNothingElse() async throws {
        let apple = AICAppleStub([AIC.answer([("candidateLayout", "vertical")])])
        let secrets = AICSecrets()
        let answer = try await AIC.service(apple, secrets: secrets).ask("candidates in a column", context: AIC.context(Self.loaded))
        #expect(answer.onDevice)
        let call = try #require(apple.calls.first)
        for sentinel in Self.sentinels { #expect(!call.text.contains(sentinel), "\(sentinel) sent") }
        for key in Self.otherKeys { #expect(!call.text.contains(key), "\(key) sent") }
        #expect(secrets.count == 0)
    }

    /// The other prompts are byte-identical to release-0.6.3's (the goldens the other acceptance tests use).
    @Test func prompt_existingPromptsByteIdentical() throws {
        let groups = AcceptanceGolden.groups()
        #expect(groups.count == AppleModelAcceptanceTests.golden063.count)
        for (name, text) in groups {
            let golden = try #require(AppleModelAcceptanceTests.golden063[name], "no golden for \(name)")
            // 0.6.4's live-data rule is in @question's requests only, once each (`AcceptanceLiveRule`); in any other
            // request it would make it differ.
            var compared = text
            if name.hasSuffix("/commands") {
                let questions = AcceptanceGolden.commands().map { $0.1 == .question }
                let requests = text.components(separatedBy: "\n----\n")
                #expect(requests.count == questions.count, "\(name)")
                compared = zip(requests, questions).map { AcceptanceLiveRule.strip($0, question: $1) }.joined(separator: "\n----\n")
            }
            for added in AppleModelAcceptanceTests.addedSince063[name] ?? [] {
                #expect(text.components(separatedBy: added).count == 2, "\(name) lacks \(added)")
                compared = compared.replacingOccurrences(of: added, with: "")
            }
            #expect(AcceptanceGolden.sha256(compared) == golden, "\(name) differs from 0.6.3")
        }
        // @config's own prompt isn't one of them.
        let config = AIConfigPrompt.request("x", context: AIC.context(AIC.base)).system.map(\.text).joined()
        let writing = Prompt.request(for: "x", mode: .improve, config: AIC.base).system.map(\.text).joined()
        #expect(config != writing && !config.contains(writing))
    }

    /// Redaction applies as for other requests: values the user hides don't reach the model.
    @Test func prompt_redactionApplies() async throws {
        var config = AIC.base
        config.redaction = RedactionSettings(enabled: true, emails: true, phones: true, cards: true, keys: true, ips: true,
                                             customWords: ["Bluebird"])
        let apple = AICAppleStub([AIC.answer([("redaction.customWords.add", ["x"])])])
        let answer = try await AIC.service(apple).ask("also hide bob.smith@example.com and Bluebird", context: AIC.context(config))
        let call = try #require(apple.calls.first)
        #expect(!call.text.contains("bob.smith@example.com"))
        #expect(!call.text.contains("Bluebird"))
        #expect(answer.hidden >= 2)
    }

    /// Answers are kept like other conversions: the same request again comes from the cache.
    @Test func prompt_cachedLikeOtherConversions() async throws {
        let apple = AICAppleStub([AIC.answer([("candidateLayout", "vertical")])])
        let service = AIC.service(apple)
        let first = try await service.ask("candidates in a column", context: AIC.context(AIC.base))
        let second = try await service.ask("candidates in a column", context: AIC.context(AIC.base))
        #expect(!first.fromCache && second.fromCache && first.text == second.text)
        #expect(apple.calls.count == 1)
    }

    // MARK: Parsing

    @Test func parse_strict() throws {
        let plain = #"{"changes": [{"key": "candidateLayout", "value": "vertical"}], "note": "Done"}"#
        let ok = try AIConfig.parse(plain)
        #expect(ok.changes == [AIConfig.Change(key: .setting(.candidateLayout), value: .string("vertical"))] && ok.note == "Done")
        #expect(try AIConfig.parse(#"{"changes": [{"key": "typeOut", "value": true}]}"#).note == nil)
        // One Markdown fence is tolerated (coordinator).
        #expect(try AIConfig.parse("```json\n\(plain)\n```") == ok)
        #expect(try AIConfig.parse("```\n\(plain)\n```") == ok)
        #expect(try AIConfig.parse("  \n```json\n\(plain)\n```\n ") == ok)
        let unreadable = [
            "Sure! Here you go: \(plain)",
            "\(plain)\nHope that helps.",
            "```json\n```json\n\(plain)\n```\n```",
            "\(plain)\(plain)",
            #"{"changes": [{"key": "typeOut", "value": true}], "extra": 1}"#,
            #"{"changes": [{"key": "typeOut", "value": true, "why": "asked"}]}"#,
            #"{"changes": [{"key": "typeOut"}]}"#,
            #"{"changes": [{"value": true}]}"#,
            #"{"changes": {"key": "typeOut", "value": true}}"#,
            #"[{"key": "typeOut", "value": true}]"#,
            #"{"changes": [{"key": "typeOut", "value": true}], "note": 3}"#,
            #"{"note": "nothing"}"#,
            "",
            "I couldn't do that.",
        ]
        for text in unreadable { #expect(throws: (any Error).self, "\(text)") { try AIConfig.parse(text) } }
    }

    /// Coordinator: the same key twice keeps the last.
    @Test func parse_lastDuplicateWins() throws {
        let text = #"{"changes": [{"key": "candidateLayout", "value": "vertical"}, {"key": "typeOut", "value": true}, {"key": "candidateLayout", "value": "horizontal"}]}"#
        let proposal = try AIConfig.parse(text)
        #expect(proposal.changes.filter { $0.key == .setting(.candidateLayout) } == [.init(key: .setting(.candidateLayout), value: .string("horizontal"))])
        var config = AIC.base
        config.candidateLayout = .vertical
        let preview = try AIConfig.preview(proposal, config: config, environment: AIC.env()).get()
        #expect(preview.edits.contains(.candidateLayout(.horizontal)) && !preview.edits.contains(.candidateLayout(.vertical)))
    }

    /// Unknown keys make the answer unreadable: one line, nothing applied, nothing inserted.
    @Test func parse_unknownKeyIsTheOneLineFailure() async throws {
        let rig = try AICRig(apple: AICAppleStub([#"{"changes": [{"key": "candidateLayout", "value": "vertical"}, {"key": "colour", "value": "pink"}]}"#]))
        let before = try AIC.bytes(rig.url)
        await rig.run("make it pink")
        #expect(rig.c.phase == .failed(AIConfig.Text(chinese: false).failure(.notUnderstood)))
        #expect(rig.c.phase == .failed("Couldn't turn that into a setting"))
        await rig.key(enterKey)
        #expect(try AIC.bytes(rig.url) == before)
        #expect(aicInsertsNothing(rig.effects))
    }

    // MARK: The flow

    @Test func flow_previewRowsOldToNewInBothLanguages() throws {
        let changes: [(String, Any)] = [("outputLanguages", ["en", "fr"]), ("appProfiles.WeChat.inputLanguage", "zh")]
        let en = try AIC.preview(changes, env: AIC.env(chinese: false)).get().rows.map { $0.text(chinese: false) }
        #expect(en.count == 2)
        #expect(en[0].contains("English, Japanese, Chinese → English, French"), "\(en[0])")
        #expect(en[1].contains("WeChat") && en[1].contains("→ Chinese"), "\(en[1])")
        let zh = try AIC.preview(changes, env: AIC.env(chinese: true)).get().rows.map { $0.text(chinese: true) }
        #expect(zh[0].contains("：") && zh[0].contains("→") && zh[0].contains("法语") && zh[0].contains("日语"), "\(zh[0])")
        #expect(zh[1].contains("按 App") && zh[1].contains("→ 中文"), "\(zh[1])")
        // The labels are the interface language's.
        #expect(!zh[0].contains("English") && !en[0].contains("英"))
    }

    /// With nothing after it, ⏎ does nothing and nothing is sent.
    @Test func flow_emptyEnterDoesNothing() async throws {
        let rig = try AICRig()
        let effects = await rig.run("")
        #expect(rig.apple.calls.isEmpty)
        #expect(!effects.contains { if case .startCommand = $0 { return true } else { return false } })
        #expect(aicInsertsNothing(effects))
    }

    /// ⏎ applies every change shown, through the config file; nothing is inserted; a confirmation line is shown.
    @Test func flow_enterApplies() async throws {
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("outputLanguages", ["en", "fr"]), ("candidateLayout", "vertical")])]))
        await rig.run("output languages English and French, candidates in a column")
        #expect(rig.c.phase == .choosing && rig.rows.count == 2)
        await rig.key(enterKey)
        #expect(rig.config.outputLanguages == [.english, OutputLanguage("fr")] && rig.config.candidateLayout == .vertical)
        #expect(rig.rows == [AIConfig.Text(chinese: false).applied(2)])
        await rig.key(enterKey)  // closes the confirmation
        #expect(rig.c.phase == .idle)
        #expect(aicInsertsNothing(rig.effects))
    }

    @Test func flow_oneApplies() async throws {
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("candidateLayout", "vertical")])]))
        await rig.run("candidates in a column")
        await rig.key(KeyEvent(keyCode: 0x12, characters: "1"))
        #expect(rig.config.candidateLayout == .vertical)
        #expect(aicInsertsNothing(rig.effects))
    }

    /// Esc cancels: nothing applied, nothing inserted.
    @Test func flow_escCancels() async throws {
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("candidateLayout", "vertical")])]))
        let before = try AIC.bytes(rig.url)
        await rig.run("candidates in a column")
        await rig.key(escKey)
        #expect(rig.c.phase != .choosing)
        await rig.key(escKey)
        #expect(!rig.effects.contains { if case .applyConfig = $0 { return true } else { return false } })
        #expect(try AIC.bytes(rig.url) == before)
        #expect(aicInsertsNothing(rig.effects))
    }

    /// Typing more refines the proposal: ⇧⏎ sends it (CHANGE 2 of spec-question-chat.md), the model gets its answer and
    /// the instruction, the new preview replaces the old one, and ⏎ applies the refined one.
    @Test func flow_typingRefines() async throws {
        let first = AIC.answer([("outputLanguages", ["en", "fr"])])
        let second = AIC.answer([("outputLanguages", ["en", "fr", "de"])])
        let apple = AICAppleStub([first, second])
        let rig = try AICRig(apple: apple)
        await rig.run("output languages English and French")
        #expect(rig.rows.count == 1 && rig.rows[0].contains("English, French"))
        await rig.type("also German")
        await rig.key(acceptanceShiftReturn)
        #expect(apple.calls.count == 2)
        let refine = try #require(apple.calls.last)
        #expect(refine.text.contains("also German") && refine.text.contains(#"["en","fr"]"#))
        #expect(rig.rows.count == 1 && rig.rows[0].contains("English, French, German"), "\(rig.rows)")
        await rig.key(enterKey)
        #expect(rig.config.outputLanguages == ["en", "fr", "de"].map(OutputLanguage.init))
        #expect(aicInsertsNothing(rig.effects))
    }

    /// CHANGE 2: ⏎ with a refine line typed applies the proposal shown and drops the line; nothing more is asked.
    @Test func flow_enterWithARefineLineAppliesTheProposalShown() async throws {
        let apple = AICAppleStub([AIC.answer([("outputLanguages", ["en", "fr"])]), AIC.answer([("outputLanguages", ["en", "fr", "de"])])])
        let rig = try AICRig(apple: apple)
        await rig.run("output languages English and French")
        let shown = try #require(rig.previews.last)
        await rig.type("also German")
        #expect(rig.c.refineLine == "also German")
        let effects = await rig.key(enterKey)
        #expect(effects.contains(.applyConfig(shown)))
        #expect(!effects.contains { if case .startRefine = $0 { return true } else { return false } })
        #expect(apple.calls.count == 1)
        #expect(rig.config.outputLanguages == [.english, OutputLanguage("fr")])
        #expect(rig.c.refineLine == nil && rig.c.refineText.isEmpty)
        #expect(rig.rows == [AIConfig.Text(chinese: false).applied(1)])
        #expect(aicInsertsNothing(rig.effects))
    }

    /// CHANGE 2: on @config's results, ⇧⏎ with nothing typed does nothing: nothing applied, sent or inserted.
    @Test func flow_shiftEnterWithNothingTypedDoesNothing() async throws {
        let apple = AICAppleStub([AIC.answer([("candidateLayout", "vertical")])])
        let rig = try AICRig(apple: apple)
        await rig.run("candidates in a column")
        let before = try AIC.bytes(rig.url)
        let rows = rig.rows
        let effects = await rig.key(acceptanceShiftReturn)
        #expect(!effects.contains { if case .applyConfig = $0 { return true } else { return false } })
        #expect(!effects.contains { if case .startRefine = $0 { return true } else { return false } })
        #expect(aicInsertsNothing(effects))
        #expect(rig.c.phase == .choosing && rig.rows == rows)
        #expect(apple.calls.count == 1)
        #expect(try AIC.bytes(rig.url) == before)
    }

    /// ⌘Z on the confirmation undoes exactly what was applied: the file is as it was, byte for byte.
    @Test func flow_commandZUndoes() async throws {
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("outputLanguages", ["en", "fr"]), ("typeOut", true),
                                                              ("appProfiles.WeChat.inputLanguage", "en"),
                                                              ("redaction.customWords.add", ["Bluebird"])])]))
        let before = try AIC.bytes(rig.url)
        await rig.run("English and French, type out, English in WeChat, hide Bluebird")
        await rig.key(enterKey)
        #expect(try AIC.bytes(rig.url) != before)
        let undo = await rig.key(aicCommandZ)
        #expect(undo.contains(.undoConfig))
        #expect(try AIC.bytes(rig.url) == before)
        #expect(rig.c.phase == .idle && aicInsertsNothing(rig.effects))
    }

    /// `@config undo` within 10 minutes puts back the changed keys only: a setting changed since elsewhere stays.
    @Test func flow_configUndoWithinTenMinutesRestoresChangedKeysOnly() async throws {
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("outputLanguages", ["en", "fr"])])]))
        await rig.run("output languages English and French")
        await rig.key(enterKey)
        await rig.key(escKey)
        // Meanwhile Settings changed another key.
        var changed = rig.config
        changed.candidateLayout = .vertical
        try changed.write(to: rig.url)
        rig.now = rig.now.addingTimeInterval(9 * 60 + 59)
        let effects = await rig.run("undo")
        #expect(effects.contains(.undoConfig))
        #expect(rig.apple.calls.count == 1)  // undo asks no AI
        #expect(rig.config.outputLanguages == AIC.base.outputLanguages)
        #expect(rig.config.candidateLayout == .vertical)
        var expected = AIC.base
        expected.candidateLayout = .vertical
        #expect(try rig.config == AIC.roundTrip(expected))
        #expect(rig.notices.last == AIConfig.Text(chinese: false).undone)
        #expect(aicInsertsNothing(rig.effects))
    }

    @Test func flow_undoRefusedAfterTheWindow() async throws {
        #expect(AIConfig.undoWindow == 600)
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("candidateLayout", "vertical")])]))
        await rig.run("candidates in a column")
        await rig.key(enterKey)
        await rig.key(escKey)
        let after = try AIC.bytes(rig.url)
        rig.now = rig.now.addingTimeInterval(10 * 60 + 1)
        await rig.run("undo")
        #expect(try AIC.bytes(rig.url) == after)
        #expect(rig.config.candidateLayout == .vertical)
        #expect(rig.notices.last == AIConfig.Text(chinese: false).nothingToUndo)
        // The API too.
        let url = try AIC.tempConfig()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let applied = try AIConfig.applying([.candidateLayout(.vertical)], at: url, now: t)
        #expect(try AIConfig.undo(applied, at: url, now: t.addingTimeInterval(601)) == false)
        #expect(try Config.load(from: url).candidateLayout == .vertical)
        #expect(try AIConfig.undo(applied, at: url, now: t.addingTimeInterval(600)) == true)
        #expect(try Config.load(from: url).candidateLayout == .horizontal)
    }

    /// Every kind of change undoes exactly: the file comes back byte for byte.
    @Test func flow_undoIsExactForEveryKindOfChange() throws {
        var start = AIC.base
        start.appProfiles = ["com.apple.mail": AppProfile(rewriteStyles: ["正式"])]
        start.redaction.customWords = ["Alpha"]
        let env = AIC.env(hasKey: Set(Provider.allCases), typed: AIC.typedURL)
        let changes: [(String, Any)] = [
            ("outputLanguages", ["fr"]), ("inputLanguages", ["en", "zh", "fr"]), ("defaultInput", "fr"),
            ("rewriteStyles", []), ("candidateLayout", "vertical"), ("typeOut", true), ("typeOutRate", 0.5),
            ("typeOutVaries", true), ("rememberQuestions", false), ("redaction.enabled", true),
            ("redaction.customWords.add", ["Beta", "alpha"]), ("checkForUpdates", false), ("provider", "openai"),
            ("awsProfile", "work"), ("region", "ap-northeast-1"), ("openai.model", "gpt-6"),
            ("openai.baseURL", "https://api.example.com/v1"), ("appProfiles.WeChat.noAI", true),
            ("appProfiles.Mail.rewriteStyles", NSNull()), ("appProfiles.Microsoft Word.typeOut", false),
        ]
        let preview = try AIC.preview(changes, config: start, env: env).get()
        #expect(!preview.rows.contains { $0.isRefused }, "\(preview.rows.filter { $0.isRefused })")
        let url = try AIC.tempConfig(start)
        let before = try AIC.bytes(url)
        let t = Date()
        let applied = try AIConfig.applying(preview.edits, at: url, now: t)
        #expect(try AIC.bytes(url) != before)
        #expect(try AIConfig.undo(applied, at: url, now: t.addingTimeInterval(1)))
        #expect(try AIC.bytes(url) == before)
    }

    /// Coordinator: turning off rememberQuestions changes that switch only (saved questions aren't deleted), so undo
    /// puts it back exactly.
    @Test func flow_rememberQuestionsOffDeletesNothing() throws {
        let preview = try AIC.preview([("rememberQuestions", false)]).get()
        #expect(preview.edits == [.flag(.rememberQuestions, false)])
        #expect(preview.actions.isEmpty)
        let url = try AIC.tempConfig()
        let history = url.deletingLastPathComponent().appendingPathComponent("questions.json")
        let saved = Data(#"[{"question":"q","answer":"a"}]"#.utf8)
        try saved.write(to: history)
        let before = try AIC.bytes(url)
        let applied = try AIConfig.applying(preview.edits, at: url)
        #expect(try Data(contentsOf: history) == saved)
        #expect(try AIConfig.undo(applied, at: url))
        #expect(try AIC.bytes(url) == before)
    }

    // MARK: On-device first

    /// Whatever provider is chosen (or set up at all), the request goes to Apple's model when it is available: no
    /// network, no key, no credentials.
    @Test func device_onDeviceFirstWhateverTheProvider() async throws {
        for provider in [Provider.bedrock, .anthropic, .gemini, .openai, .hosted, .apple] {
            let host = AIC.host()
            var config = AIC.onClaude(AIC.base, host: host)
            config.provider = provider
            let apple = AICAppleStub([AIC.answer([("candidateLayout", "vertical")])])
            let secrets = AICSecrets()
            let answer = try await AIC.service(apple, secrets: secrets, keys: false)
                .ask("candidates in a column", context: AIC.context(config))
            #expect(answer.onDevice, "\(provider)")
            #expect(apple.calls.count == 1 && apple.calls[0].guided, "\(provider)")
            #expect(AICHTTPStub.bodies(host).isEmpty, "\(provider)")
            #expect(secrets.count == 0, "\(provider)")
        }
    }

    /// With Apple Intelligence unavailable, the configured provider is used.
    @Test func device_unavailableUsesTheConfiguredProvider() async throws {
        for availability in [AppleModelAvailability.appleIntelligenceNotEnabled, .deviceNotEligible, .modelNotReady, .unsupportedSystem] {
            let host = AIC.host()
            AICHTTPStub.enqueue(host, AIC.answer([("candidateLayout", "vertical")]))
            let apple = AICAppleStub(availability: availability)
            let answer = try await AIC.service(apple).ask("candidates in a column", context: AIC.context(AIC.onClaude(AIC.base, host: host)))
            #expect(!answer.onDevice)
            #expect(apple.calls.isEmpty, "\(availability)")
            #expect(AICHTTPStub.bodies(host).count == 1)
            #expect(try AIConfig.parse(answer.text).changes.count == 1)
        }
    }

    /// Neither: one line in the panel, nothing applied.
    @Test func device_neitherIsOneLineFailure() async throws {
        // The provider is the on-device model, which is off.
        var onApple = AIC.base
        onApple.provider = .apple
        let off = AICAppleStub(availability: .appleIntelligenceNotEnabled)
        await #expect(throws: (any Error).self) { _ = try await AIC.service(off).ask("x", context: AIC.context(onApple)) }
        // A provider without a key.
        let host = AIC.host()
        await #expect(throws: (any Error).self) {
            _ = try await AIC.service(AICAppleStub(availability: .deviceNotEligible), keys: false)
                .ask("x", context: AIC.context(AIC.onClaude(AIC.base, host: host)))
        }
        // In the panel.
        let rig = try AICRig(onApple, apple: off)
        let before = try AIC.bytes(rig.url)
        await rig.run("candidates in a column")
        guard case let .failed(line) = rig.c.phase else { Issue.record("\(rig.c.phase)"); return }
        #expect(!line.isEmpty && !line.contains("\n"))
        await rig.key(enterKey)
        #expect(try AIC.bytes(rig.url) == before)
        #expect(aicInsertsNothing(rig.effects))
    }

    // MARK: Apps with no AI

    /// Coordinator: @config is refused in an app with no AI: nothing is sent, the draft stays.
    @Test func noai_configRefused() async throws {
        let rig = try AICRig(apple: AICAppleStub([AIC.answer([("candidateLayout", "vertical")])]))
        rig.c.aiRefusal = { "AI is off in this app" }
        let effects = await rig.run("candidates in a column")
        #expect(effects.contains(.notice("AI is off in this app")))
        #expect(!effects.contains { if case .startCommand = $0 { return true } else { return false } })
        #expect(rig.apple.calls.isEmpty)
        #expect(rig.c.draft == "@config candidates in a column")
        #expect(aicInsertsNothing(effects))
    }
}
