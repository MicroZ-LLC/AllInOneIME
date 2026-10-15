import CryptoKit
import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Acceptance tests for "Hide sensitive information before sending to the AI", written from the spec (not from the
// implementation's own tests). Every provider is stubbed by a URLProtocol that records the raw request (URL, headers,
// body bytes) and answers in that provider's own wire format, echoing what it was sent so the restore path is real.

// MARK: - Harness (shared with the golden generator run against release-0.6.3, 55d496e)

/// The providers a request can go to, as their wire formats differ.
enum LeakWire: String, CaseIterable, Sendable {
    case bedrock, anthropic, gemini, openai, ollama, hosted
}

/// Records every request (by host) and answers with a reply built from the user's last message as it was sent.
final class LeakRecorder: URLProtocol, @unchecked Sendable {
    struct Captured: Sendable {
        var method: String
        var url: String
        var headers: [String: String]
        var body: Data
    }

    typealias Reply = @Sendable (_ sent: String) -> [String]

    private struct Route {
        var wire: LeakWire
        var reply: Reply
    }

    private struct State {
        var routes: [String: Route] = [:]
        var requests: [String: [Captured]] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func route(host: String, wire: LeakWire, reply: @escaping Reply) {
        state.withLock {
            $0.routes[host] = Route(wire: wire, reply: reply)
            $0.requests[host] = []
        }
    }

    static func captured(host: String) -> [Captured] { state.withLock { $0.requests[host] ?? [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LeakRecorder.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let host = request.url?.host ?? ""
        let captured = Captured(method: request.httpMethod ?? "", url: request.url?.absoluteString ?? "",
                                headers: request.allHTTPHeaderFields ?? [:], body: body)
        let route = Self.state.withLock { state -> Route? in
            state.requests[host, default: []].append(captured)
            return state.routes[host]
        }
        guard let route, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                  "Content-Type": route.wire == .bedrock ? "application/vnd.amazon.eventstream" : "text/event-stream",
              ])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let sent = LeakWire.lastUserText(route.wire, body: body) ?? ""
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        for chunk in route.wire.encode(route.reply(sent)) {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension LeakWire {
    /// The user's last message as the provider received it.
    static func lastUserText(_ wire: LeakWire, body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        switch wire {
        case .bedrock, .hosted:
            let last = (json["messages"] as? [[String: Any]])?.last
            return ((last?["content"] as? [[String: Any]])?.first?["text"]) as? String
        case .anthropic, .openai, .ollama:
            return (json["messages"] as? [[String: Any]])?.last?["content"] as? String
        case .gemini:
            let last = (json["contents"] as? [[String: Any]])?.last
            return ((last?["parts"] as? [[String: Any]])?.first?["text"]) as? String
        }
    }

    /// `deltas` as this provider streams them, each one its own event, then the end of the answer.
    func encode(_ deltas: [String]) -> [Data] {
        func json(_ object: Any) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]), as: UTF8.self)
        }
        func sse(_ object: Any) -> Data { Data(("data: " + json(object) + "\n\n").utf8) }
        switch self {
        case .bedrock:
            return deltas.map { Self.eventMessage("contentBlockDelta", Data(json(["contentBlockIndex": 0, "delta": ["text": $0]]).utf8)) }
                + [Self.eventMessage("messageStop", Data(json(["stopReason": "end_turn"]).utf8))]
        case .anthropic:
            return deltas.map {
                Data(("event: content_block_delta\n").utf8)
                    + sse(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": $0]])
            } + [sse(["type": "message_delta", "delta": ["stop_reason": "end_turn"]]), sse(["type": "message_stop"])]
        case .gemini:
            return deltas.map { sse(["candidates": [["content": ["parts": [["text": $0]], "role": "model"]]]]) }
                + [sse(["candidates": [["content": ["parts": [["text": ""]]], "finishReason": "STOP"]]])]
        case .openai, .ollama:
            return deltas.map { sse(["choices": [["index": 0, "delta": ["content": $0]]]]) }
                + [sse(["choices": [["index": 0, "delta": [:], "finish_reason": "stop"]]]), Data("data: [DONE]\n\n".utf8)]
        case .hosted:
            return deltas.map { sse(["text": $0]) } + [sse(["stop": "end_turn"])]
        }
    }

    /// One AWS event-stream message with string headers.
    static func eventMessage(_ type: String, _ payload: Data) -> Data {
        var headers = Data()
        for (name, value) in [(":event-type", type), (":content-type", "application/json"), (":message-type", "event")] {
            headers.append(UInt8(name.utf8.count))
            headers.append(contentsOf: Array(name.utf8))
            headers.append(7)
            let bytes = Array(value.utf8)
            headers.append(UInt8(bytes.count >> 8))
            headers.append(UInt8(bytes.count & 0xFF))
            headers.append(contentsOf: bytes)
        }
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        var message = Data(be(UInt32(12 + headers.count + payload.count + 4)) + be(UInt32(headers.count)))
        message.append(contentsOf: be(CRC32.checksum(Array(message))))
        message.append(headers)
        message.append(payload)
        message.append(contentsOf: be(CRC32.checksum(Array(message))))
        return message
    }
}

/// A converter wired to one stubbed provider at a host of its own (`tag`: lowercase letters and digits).
struct LeakRig: Sendable {
    let wire: LeakWire
    let tag: String

    var region: String { "us-\(tag)-1" }

    var host: String {
        switch wire {
        case .bedrock: return "bedrock-runtime.\(region).amazonaws.com"
        case .anthropic: return "claude-\(tag).test"
        case .gemini: return "gemini-\(tag).test"
        case .openai: return "openai-\(tag).test"
        case .ollama: return "ollama-\(tag).local"
        case .hosted: return URL(string: HostedService.baseURL)!.host!
        }
    }

    /// `base` sent to this rig's provider.
    func configure(_ base: Config) -> Config {
        var config = base
        switch wire {
        case .bedrock:
            config.provider = .bedrock
            config.region = region
            config.awsProfile = "test"
        case .anthropic:
            config.provider = .anthropic
            config.anthropic.baseURL = "https://\(host)"
        case .gemini:
            config.provider = .gemini
            config.gemini.baseURL = "https://\(host)"
        case .openai:
            config.provider = .openai
            config.openai.baseURL = "https://\(host)/v1"
            config.openai.model = "gpt-test"
        case .ollama:
            config.provider = .openai
            config.openai.baseURL = "http://\(host):11434/v1"
            config.openai.model = "llama3.2"
        case .hosted:
            config.provider = .hosted
        }
        return config
    }

    func converter(_ config: Config, jargon: [JargonEntry] = []) -> Converter {
        let fixed = configure(config)
        return Converter(
            client: BedrockClient(session: LeakRecorder.session()),
            loadConfig: { fixed },
            loadCredentials: { _ in
                AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIDTEST", secretAccessKey: "secret"), region: nil)
            },
            loadKey: { provider, _ in provider == .hosted ? "v1.session" : "test-key" },
            loadJargon: { _ in jargon })
    }

    func reply(_ make: @escaping LeakRecorder.Reply) { LeakRecorder.route(host: host, wire: wire, reply: make) }

    var requests: [LeakRecorder.Captured] { LeakRecorder.captured(host: host) }
}

/// The final update of a stream, and all of them.
func leakCollect(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> [ConversionUpdate] {
    var updates: [ConversionUpdate] = []
    for try await update in stream { updates.append(update) }
    return updates
}

/// The request as sent, as one digest: method, URL, the headers the app sets (not the signature's date-bound ones),
/// and the body bytes.
func leakDigest(_ request: LeakRecorder.Captured) -> String {
    let skipped: Set<String> = ["authorization", "x-amz-date", "user-agent", "accept-language"]
    let headers = request.headers.filter { !skipped.contains($0.key.lowercased()) }
        .map { "\($0.key.lowercased()): \($0.value)" }.sorted().joined(separator: "\n")
    var data = Data((request.method + " " + request.url + "\n" + headers + "\n\n").utf8)
    // Bedrock's body comes from JSONEncoder, whose key order changes from run to run (release-0.6.3 too): its keys
    // are put in order. The other providers' bodies are compared byte for byte as sent.
    if request.url.contains(".amazonaws.com/"), let object = try? JSONSerialization.jsonObject(with: request.body),
       let sorted = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) {
        data.append(sorted)
    } else {
        data.append(request.body)
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// The requests compared byte for byte with release-0.6.3: one per provider and kind of request.
struct GoldenScenario: Sendable {
    let name: String
    let wire: LeakWire
    let jargon: [JargonEntry]
    let base: @Sendable () -> Config
    let run: @Sendable (Converter) -> AsyncThrowingStream<ConversionUpdate, Error>

    static let ordinary = "Meeting moved to 2026-10-14 at 14:30, release v1.2.3, order #A-10023, total $19.99, "
        + "see https://example.com/docs/a and /usr/local/bin/tool"

    static let all: [GoldenScenario] = [
        GoldenScenario(name: "bedrock-convert-zh", wire: .bedrock, jargon: [], base: { Config.default },
                       run: { $0.convert("我今天有点不舒服") }),
        GoldenScenario(name: "anthropic-improve-en", wire: .anthropic, jargon: [], base: {
            var c = Config.default
            c.setOrder([OutputLanguage.english, .chinese])
            return c
        }, run: { $0.convert(ordinary, mode: .improve) }),
        GoldenScenario(name: "gemini-translate-zh", wire: .gemini, jargon: [], base: {
            var c = Config.default
            c.setOrder([OutputLanguage.english, .chinese])
            return c
        }, run: { $0.convert("明天下午三点开会，版本 2.0.1，订单号 20261014", mode: .translate) }),
        GoldenScenario(name: "openai-both-jargon", wire: .openai,
                       jargon: [JargonEntry(term: "对齐", meaning: "align"), JargonEntry(term: "抓手", meaning: "lever")], base: {
            var c = Config.default
            c.rewriteStyles = ["黑话", "润色"]
            return c
        }, run: { $0.convert("我们需要先统一一下目标再开始做", mode: .both) }),
        GoldenScenario(name: "ollama-question", wire: .ollama, jargon: [], base: { Config.default },
                       run: { $0.generate(.question, input: "What is the capital of France? Answer by 10:30.") }),
        GoldenScenario(name: "hosted-custom-prompt", wire: .hosted, jargon: [], base: { Config.default }, run: {
            $0.generate(Command.catalog([CustomCommand(name: "formal", type: .prompt, prompt: "Rewrite it formally, in English.")])
                .first { $0.name == "formal" }!, input: "pls send the deck by friday, v2 is fine")
        }),
        GoldenScenario(name: "anthropic-edit-selection", wire: .anthropic, jargon: [], base: { Config.default }, run: {
            $0.generate(.edit, input: Prompt.editRequest(instruction: "improve", text: "teh quick brown fox\njumps over 3 dogs"))
        }),
        GoldenScenario(name: "bedrock-question-selection", wire: .bedrock, jargon: [], base: { Config.default }, run: {
            $0.generate(.question, input: Prompt.question("what does this mean?", about: "Error 404 at /api/v2/users on 2026-10-14"))
        }),
    ]

    /// Runs the scenario once against a fresh rig and returns the digest of the one request it made.
    func digest(tag: String, configure: (inout Config) -> Void) async throws -> String {
        let rig = LeakRig(wire: wire, tag: tag)
        rig.reply { _ in ["EN: Fine.\n"] }
        var config = base()
        configure(&config)
        _ = try await leakCollect(run(rig.converter(config, jargon: jargon)))
        let requests = rig.requests
        guard requests.count == 1 else { throw GoldenError.requests(requests.count) }
        return leakDigest(requests[0])
    }

    enum GoldenError: Error { case requests(Int) }
}

// MARK: - Tests

/// The digests of `GoldenScenario.all` as release-0.6.3 (55d496e) sends them, generated from a worktree of it.
let goldenDigests: [String: String] = [
    "bedrock-convert-zh": "9cf3f2c5f5bf11e5c728d0531cc92b614f1c4af8142905672edc038e84c43bb7",
    "anthropic-improve-en": "69c2f332f70381d20cee04c84d83989d9ddab487d0ea6b7a98bfeede095cdcbd",
    "gemini-translate-zh": "f573e94ad11c1a634557388fb85f95daa5366f61f39826d36efedda3479fc246",
    "openai-both-jargon": "de7ecefb5c65f5d8c406171b2df09cba00dad1d9322f6cc563dda907bdb6266d",
    "ollama-question": "a66f7ea623c2bb1c580d69390d23692da82c023b468730cd7e417852118f6852",
    "hosted-custom-prompt": "351a521ad4407a5e3bbdecea83a43735dd76cc8399dfe9504818346c4868a7c2",
    "anthropic-edit-selection": "f2099dce68fc901e6149c7283b55e39636234f7331bd65e1208c80855a0b3cfe",
    "bedrock-question-selection": "d6b9626576f1db4eb1622dddb2793eeebf2fc5ff8c80131368ec86b0903e4d7c",
]

/// Real values used throughout: none of them may reach a provider while hiding is on.
enum Secret {
    static let email = "zhang.san+work@example-corp.com"
    static let phone = "+86 138 0013 8000"
    static let card = "4111 1111 1111 1111"
    static let claudeKey = "sk-\u{61}nt-api03-Zx9Qw7Er5Ty3Ui1Op8As6Df4Gh2Jk0LzXcVbNm"
    static let awsKey = "AK\u{49}AIOSFODNN7EXAMPL3"
    static let ghToken = "gh\u{70}_1a2B3c4D5e6F7g8H9i0JkLmNoPqRsTuVwXyZ"
    static let ipv4 = "203.0.113.42"
    static let ipv6 = "2001:db8:85a3::8a2e:370:7334"
    static let word = "Phoenix"

    /// One of each kind, in one line.
    static let sentence = "Mail \(email) or call \(phone), card \(card), keys \(claudeKey) \(awsKey) \(ghToken), "
        + "hosts \(ipv4) and \(ipv6), about \(word)."
    /// The distinct values in `sentence`.
    static let all = [email, phone, card, claudeKey, awsKey, ghToken, ipv4, ipv6, word]
    /// The values and other ways of reading them (a card's or a phone's digits alone).
    static let forms = all + ["4111111111111111", "13800138000", "8613800138000", "zhang.san+work@"]

    static let settings = RedactionSettings(enabled: true, customWords: ["Phoenix", "Project Atlas"])
}

/// Where in `requests` any of `secrets` appears: the URL, the headers, the raw body bytes, or the body's JSON strings
/// once decoded (so an escaped form is found too). `anyCase` values are looked for in any case.
func leaked(_ requests: [LeakRecorder.Captured], _ secrets: [String], anyCase: [String] = []) -> [String] {
    var found: [String] = []
    for (index, request) in requests.enumerated() {
        let header = request.headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        var strings: [String] = []
        func walk(_ value: Any) {
            if let s = value as? String { strings.append(s) }
            else if let a = value as? [Any] { a.forEach(walk) }
            else if let d = value as? [String: Any] { for (k, v) in d { strings.append(k); walk(v) } }
        }
        if let object = try? JSONSerialization.jsonObject(with: request.body) { walk(object) }
        let decoded = strings.joined(separator: "\n")
        let places: [(String, Data, String)] = [
            ("url", Data(request.url.utf8), request.url), ("headers", Data(header.utf8), header), ("body", request.body, decoded),
        ]
        for secret in secrets {
            for (place, bytes, text) in places where bytes.range(of: Data(secret.utf8)) != nil || text.contains(secret) {
                found.append("request \(index) \(place): \(secret)")
            }
        }
        for secret in anyCase {
            for (place, bytes, text) in places
            where String(decoding: bytes, as: UTF8.self).range(of: secret, options: .caseInsensitive) != nil
                || text.range(of: secret, options: .caseInsensitive) != nil {
                found.append("request \(index) \(place) (any case): \(secret)")
            }
        }
    }
    return found
}

/// Every row of a result.
func leakRows(_ result: ConversionResult) -> [String] {
    result.versions.map(\.text) + result.translations.map(\.line.text) + result.rewrites.map(\.line.text)
}

/// A reply for a conversion: one line per tag the plan asks for, each the text as it was sent.
func echoLines(_ tags: [String]) -> LeakRecorder.Reply {
    { sent in tags.map { "\($0): \(sent)\n" } }
}

/// A command's reply: the text as it was sent, in a few pieces.
let echoAnswer: LeakRecorder.Reply = { sent in
    let chars = Array("Re: " + sent)
    let cut = [0, 3, chars.count / 3, chars.count / 2, chars.count]
    return zip(cut, cut.dropFirst()).map { String(chars[$0..<$1]) }.filter { !$0.isEmpty }
}

func onConfig(_ settings: RedactionSettings = Secret.settings, _ edit: (inout Config) -> Void = { _ in }) -> Config {
    var config = Config.default
    config.redaction = settings
    edit(&config)
    return config
}

func customCommand(_ name: String, prompt: String) -> Command {
    Command.catalog([CustomCommand(name: name, type: .prompt, prompt: prompt)]).first { $0.name == name }!
}

/// Placeholders in a text as they are sent ("[EMAIL_1]").
func placeholders(in text: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"\[(EMAIL|PHONE|CARD|KEY|IP|ITEM)_[0-9]+\]"#)
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
}

/// The user's last message as the provider got it.
func sentText(_ request: LeakRecorder.Captured, _ wire: LeakWire) -> String {
    LeakWire.lastUserText(wire, body: request.body) ?? ""
}

/// The system prompt as the provider got it (every provider's own field).
func systemText(_ request: LeakRecorder.Captured) -> String {
    guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else { return "" }
    if let s = json["system"] as? String { return s }
    if let s = json["system"] as? [[String: Any]] { return s.compactMap { $0["text"] as? String }.joined(separator: "\n\n") }
    if let s = (json["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]] {
        return s.compactMap { $0["text"] as? String }.joined()
    }
    if let m = json["messages"] as? [[String: Any]], m.first?["role"] as? String == "system" { return m.first?["content"] as? String ?? "" }
    return ""
}

@Suite(.serialized)
struct RedactionAcceptanceTests {
    // MARK: 1. Replacement, on every provider and every way to the AI

    /// @question with one value of each kind, on every provider: nothing real is sent, and the answer has them back.
    @Test(arguments: LeakWire.allCases)
    func questionOnEveryProviderHidesEveryKind(_ wire: LeakWire) async throws {
        let rig = LeakRig(wire: wire, tag: "q")
        rig.reply(echoAnswer)
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: Secret.sentence))
        let requests = rig.requests
        #expect(requests.count == 1)
        #expect(leaked(requests, Secret.forms, anyCase: [Secret.word]).isEmpty, "\(leaked(requests, Secret.forms, anyCase: [Secret.word]))")
        let sent = sentText(try #require(requests.first), wire)
        for kind in ["EMAIL", "PHONE", "CARD", "KEY", "IP", "ITEM"] {
            #expect(placeholders(in: sent).contains { $0.hasPrefix("[\(kind)_") }, "\(wire): no \(kind) placeholder in \(sent)")
        }
        let final = try #require(updates.last)
        #expect(final.isFinal)
        #expect(final.result.versions.first?.text == "Re: " + Secret.sentence)
        #expect(final.hidden == Secret.all.count)
    }

    /// The improve conversion (versions and rewrites) on every provider.
    @Test(arguments: LeakWire.allCases)
    func conversionOnEveryProviderHidesEveryKind(_ wire: LeakWire) async throws {
        let rig = LeakRig(wire: wire, tag: "conv")
        let config = onConfig()
        rig.reply(echoLines(WritingPlan.make(.both, text: Secret.sentence, config: config).lineTags))
        let updates = try await leakCollect(rig.converter(config).convert(Secret.sentence))
        #expect(rig.requests.count == 1)
        #expect(leaked(rig.requests, Secret.forms, anyCase: [Secret.word]).isEmpty, "\(leaked(rig.requests, Secret.forms, anyCase: [Secret.word]))")
        let final = try #require(updates.last)
        let rows = leakRows(final.result)
        #expect(rows.count >= 3)
        #expect(rows.allSatisfy { $0 == Secret.sentence }, "\(rows)")
        #expect(final.hidden == Secret.all.count)
    }

    /// @improve, @translate and both together, with translations into two languages.
    @Test(arguments: [WritingMode.improve, .translate, .both])
    func improveAndTranslateModes(_ mode: WritingMode) async throws {
        let rig = LeakRig(wire: .anthropic, tag: "mode\(mode == .improve ? "i" : mode == .translate ? "t" : "b")")
        let input = "请把合同发到 \(Secret.email)，有问题打 \(Secret.phone)，Phoenix 项目"
        let config = onConfig { $0.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja")]) }
        rig.reply(echoLines(WritingPlan.make(mode, text: input, config: config).lineTags))
        let updates = try await leakCollect(rig.converter(config).convert(input, mode: mode))
        #expect(leaked(rig.requests, Secret.forms, anyCase: [Secret.word]).isEmpty, "\(leaked(rig.requests, Secret.forms, anyCase: [Secret.word]))")
        let rows = leakRows(try #require(updates.last).result)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0 == input }, "\(rows)")
    }

    /// A custom prompt command and a prompt plugin: values in the text and in the command's own prompt are hidden.
    @Test func customPromptCommandsAndPromptPlugins() async throws {
        let prompt = "Sign as Phoenix. Reply-to ceo@corp-secret.com, phone +44 20 7946 0958, deploy token \(Secret.ghToken), "
            + "server 198.51.100.7."
        let plugin = InstalledPlugin(manifest: PluginManifest(name: "sig", version: "1.0.0", type: .prompt, prompt: prompt),
                                     directory: URL(fileURLWithPath: "/nonexistent/sig"), isLocal: true)
        let pluginCommand = try #require(Command.catalog([], plugins: [plugin]).first { $0.name == "sig" })
        for (index, command) in [customCommand("sign", prompt: prompt), pluginCommand].enumerated() {
            let rig = LeakRig(wire: .openai, tag: "custom\(index)")
            rig.reply(echoAnswer)
            let updates = try await leakCollect(rig.converter(onConfig()).generate(command, input: "Write to \(Secret.email) about \(Secret.card)"))
            let secrets = Secret.forms + ["ceo@corp-secret.com", "+44 20 7946 0958", "198.51.100.7"]
            #expect(leaked(rig.requests, secrets, anyCase: [Secret.word]).isEmpty, "\(command.name): \(leaked(rig.requests, secrets, anyCase: [Secret.word]))")
            #expect(try #require(updates.last).result.versions.first?.text == "Re: Write to \(Secret.email) about \(Secret.card)")
            // The prompt's own values count as hidden too.
            #expect(try #require(updates.last).hidden == 7)
        }
    }

    /// A US phone number with an extension ("x89") in a custom command's prompt.
    @Test func customPromptPhoneWithExtension() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "ext")
        rig.reply(echoAnswer)
        let command = customCommand("callme", prompt: "End every answer with: call 555-123-4567x89 or mail help@corp-secret.com_ops.")
        _ = try await leakCollect(rig.converter(onConfig()).generate(command, input: "draft a reply"))
        let found = leaked(rig.requests, ["555-123-4567", "help@corp-secret.com"])
        let system = systemText(try #require(rig.requests.first))
        #expect(found.isEmpty, "\(found)\nsystem: \(system)")
    }

    /// The text selected in the field: a question about it, and an instruction for it (`@improve` on a selection).
    @Test func selectedTextCommands() async throws {
        let rig = LeakRig(wire: .bedrock, tag: "sel")
        rig.reply(echoAnswer)
        let converter = rig.converter(onConfig())
        let selection = "Owner: \(Secret.email)\nKey: \(Secret.claudeKey)\nProject Atlas on \(Secret.ipv4)"
        let question = try await leakCollect(converter.generate(.question, input: Prompt.question("who owns this?", about: selection)))
        let edit = try await leakCollect(converter.generate(.edit, input: Prompt.editRequest(
            instruction: "translate: ja, and add cc \(Secret.email)", text: "Call \(Secret.phone) or pay with \(Secret.card)")))
        #expect(rig.requests.count == 2)
        #expect(leaked(rig.requests, Secret.forms + ["Project Atlas"]).isEmpty, "\(leaked(rig.requests, Secret.forms + ["Project Atlas"]))")
        #expect(question.last?.result.versions.first?.text == "Re: " + Prompt.question("who owns this?", about: selection))
        #expect(edit.last?.result.versions.first?.text.contains(Secret.card) == true)
    }

    /// An inner command's output (a plugin that fetched a contact) goes into the text sent to the AI: hidden there too.
    /// And `@translate @question …` (the text after @translate is sent as written).
    @Test func innerCommandsAndCommandsInTheText() async throws {
        let rig = LeakRig(wire: .gemini, tag: "inner")
        rig.reply(echoAnswer)
        let converter = rig.converter(onConfig())
        let stock = try #require(Command.catalog([CustomCommand(name: "desk", type: .run, argv: ["echo", "{input}"])]).first { $0.name == "desk" })
        let plan = CommandPlan.make("Who handles @desk AAPL orders?", commands: [stock])
        #expect(plan.inner.count == 1)
        let output = "AAPL desk: \(Secret.email), \(Secret.phone)"
        let stream = CommandPipeline.run(plan, inner: { _, _ in
            AsyncThrowingStream { c in
                c.yield(ConversionUpdate(result: ConversionResult(versions: [CandidateLine(output)]), rawText: output, isFinal: true,
                                         elapsed: 0, firstTokenLatency: nil, fromCache: false))
                c.finish()
            }
        }, outer: { converter.generate(.question, input: $0) })
        let updates = try await leakCollect(stream)
        #expect(updates.last?.result.versions.first?.text == "Re: Who handles \(output) orders?")

        let rigT = LeakRig(wire: .gemini, tag: "innert")
        let config = onConfig { $0.setOrder([OutputLanguage.english, .chinese]) }
        let (mode, text) = WritingMode.parse(.translate, "@question 谁的邮箱是 \(Secret.email)？key \(Secret.awsKey)")
        rigT.reply(echoLines(WritingPlan.make(mode, text: text, config: config).lineTags))
        _ = try await leakCollect(rigT.converter(config).convert(text, mode: mode))
        let all = rig.requests + rigT.requests
        #expect(all.count == 2)
        #expect(leaked(all, Secret.forms).isEmpty, "\(leaked(all, Secret.forms))")
    }

    // MARK: 2. Detectors, each on its own switch

    static let emails = [
        "a@b.co", "john.doe@example.com", "John.Doe+tag@Sub.Example.co.uk", "x_y-z%1@my-domain.io", "ops@公司.com.cn"
            .replacingOccurrences(of: "公司", with: "corp"),
    ]
    static let phones = [
        "13800138000", "138 0013 8000", "138-0013-8000", "+86 138 0013 8000", "+86-138-0013-8000", "+8613800138000",
        "010-12345678", "0755-8888 6666", "(555) 123-4567", "555-123-4567", "555.123.4567", "+1 (555) 123-4567",
        "+1 555 123 4567", "+44 20 7946 0958", "+49 30 12345678", "+81 3-1234-5678", "+33 1 23 45 67 89",
        "+33 6 12 34 56 78", "+852 2123 4567",
    ]
    static let cards = [
        "4111111111111111", "4111 1111 1111 1111", "4111-1111-1111-1111", "5555 5555 5555 4444", "3782 822463 10005",
        "6011 1111 1111 1117", "3530 1113 3330 0000", "6212 3456 7890 1232",
    ]
    static let keys = [
        Secret.claudeKey, "sk-\u{70}roj-4fT9xQ2mLp8Rz7Wv3Ks6Hn1Yb5Jd0Gc", "s\u{6B}-1a2b3c4d5e6f7g8h9i0jKLMNOPqrst", Secret.awsKey,
        Secret.ghToken, "xo\u{78}b-123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx", "AI\u{7A}aSyD4f8G2h6J9kL1mN3pQ5rS7tU9vW0xY2zA",
        "gl\u{70}at-a1B2c3D4e5F6g7H8i9J0", "ey\u{4A}hbGciOiJIUzI1NiJ9.ey\u{4A}zdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        // Long random strings without a known prefix: a hex secret, a base64 secret, an AWS secret access key.
        "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", "Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MGFiY2RlZg==",
        "wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY", "Rk3/9Qb+Lm2Zp7Rt8Vw/Ys4Nd6Hf1Gc5Ke0Ua2Bx7Y",
    ]
    static let ips = ["192.168.1.10", "8.8.8.8", "10.0.0.1:8080", Secret.ipv6, "2001:db8::1", "fe80::1ff:fe23:4567:890a", "::ffff:192.0.2.1"]

    /// What `value` looks like once its separators are gone (a number's digits).
    static func digits(_ value: String) -> String { value.filter(\.isNumber) }

    func expectHidden(_ value: String, kind: String, settings: RedactionSettings = Secret.settings) throws {
        for context in ["Contact: \(value) — thanks", "联系\(value)谢谢", "(\(value))"] {
            var r = try #require(Redaction(settings))
            let out = r.hide(context)
            let numberLike = kind == "PHONE" || kind == "CARD"
            let readable = out.contains(value) || (numberLike && Self.digits(out).contains(Self.digits(value).suffix(8)))
            #expect(!readable, "\(kind) \(value) not hidden in \(context): \(out)")
            #expect(r.restore(out) == context, "\(kind) \(value) not restored in \(context): \(r.restore(out))")
        }
    }

    @Test(arguments: emails) func detectsEmail(_ value: String) throws { try expectHidden(value, kind: "EMAIL") }
    @Test(arguments: phones) func detectsPhone(_ value: String) throws { try expectHidden(value, kind: "PHONE") }
    @Test(arguments: cards) func detectsCard(_ value: String) throws { try expectHidden(value, kind: "CARD") }
    @Test(arguments: keys) func detectsKey(_ value: String) throws { try expectHidden(value, kind: "KEY") }
    @Test(arguments: ips) func detectsIP(_ value: String) throws { try expectHidden(value, kind: "IP") }

    /// A number that isn't a card (fails the Luhn check) is left alone.
    @Test func luhnInvalidNumbersStay() throws {
        var r = try #require(Redaction(Secret.settings))
        for number in ["4111 1111 1111 1112", "4111111111111112", "5555 5555 5555 4440"] {
            #expect(r.hide("ref \(number) ok") == "ref \(number) ok")
        }
    }

    /// Emails next to Chinese text, keys in a code block, values on separate lines.
    @Test func valuesInContext() throws {
        var r = try #require(Redaction(Secret.settings))
        let cjk = r.hide("张三abc@x.com你好")
        #expect(!cjk.contains("abc@x.com") && cjk.hasPrefix("张三") && cjk.hasSuffix("你好"), "\(cjk)")
        let code = """
            ```bash
            export ANTHROPIC_API_KEY="\(Secret.claudeKey)"
            export AWS_ACCESS_KEY_ID=\(Secret.awsKey)
            curl -H "Authorization: Bearer \(Secret.ghToken)" https://\(Secret.ipv4)/api
            ```
            config = {"api_key": "sk-\u{70}roj-4fT9xQ2mLp8Rz7Wv3Ks6Hn1Yb5Jd0Gc", "host": "\(Secret.ipv6)"}
            """
        let out = r.hide(code)
        for value in [Secret.claudeKey, Secret.awsKey, Secret.ghToken, Secret.ipv4, Secret.ipv6, "sk-\u{70}roj-4fT9xQ2mLp8Rz7Wv3Ks6Hn1Yb5Jd0Gc"] {
            #expect(!out.contains(value), "\(value) in \(out)")
        }
        #expect(out.contains("export ANTHROPIC_API_KEY=\"[KEY_") && out.contains("```bash"), "\(out)")
        #expect(r.restore(out) == code)
    }

    /// The user's own words: any case, regular-expression characters taken literally, whole words only.
    @Test func customWords() throws {
        let settings = RedactionSettings(enabled: true, customWords: ["Phoenix", "C++", "a.b", "(beta)", "$HOME", "[x]", "a|b", #"\d+"#,
                                                                       "凤凰计划", "Project Atlas"])
        var r = try #require(Redaction(settings))
        let text = #"phoenix PHOENIX pHoEnIx Phoenix; C++ and a.b (beta) at $HOME with [x], a|b, \d+, 凤凰计划上线, project atlas"#
        let out = r.hide(text)
        for word in ["phoenix", "C++", "a.b", "(beta)", "$HOME", "[x]", "a|b", #"\d+"#, "凤凰计划", "atlas"] {
            #expect(out.range(of: word, options: .caseInsensitive) == nil, "\(word) in \(out)")
        }
        #expect(r.restore(out) == text, "\(r.restore(out))")
        // Taken literally, and as whole words.
        var plain = try #require(Redaction(settings))
        for text in ["axb", "C# and C", "123", "ab", "Phoenixes and APhoenix", "Atlas alone"] {
            #expect(plain.hide(text) == text, "\(text) -> \(plain.hide(text))")
        }
    }

    /// Each switch off: that kind is sent as typed, the others are still hidden.
    @Test(arguments: ["emails", "phones", "cards", "keys", "ips", "customWords"])
    func eachDetectorSwitchesOff(_ off: String) async throws {
        var settings = Secret.settings
        switch off {
        case "emails": settings.emails = false
        case "phones": settings.phones = false
        case "cards": settings.cards = false
        case "keys": settings.keys = false
        case "ips": settings.ips = false
        default: settings.customWords = []
        }
        let kept: [String: [String]] = [
            "emails": [Secret.email], "phones": [Secret.phone], "cards": [Secret.card],
            "keys": [Secret.claudeKey, Secret.awsKey, Secret.ghToken], "ips": [Secret.ipv4, Secret.ipv6], "customWords": [Secret.word],
        ]
        let rig = LeakRig(wire: .anthropic, tag: "off\(off.lowercased())")
        rig.reply(echoAnswer)
        _ = try await leakCollect(rig.converter(onConfig(settings)).generate(.question, input: Secret.sentence))
        let sent = sentText(try #require(rig.requests.first), .anthropic)
        for (name, values) in kept {
            for value in values {
                if name == off { #expect(sent.contains(value), "\(off) off, yet \(value) hidden: \(sent)") }
                else { #expect(!sent.contains(value), "\(off) off, and \(value) (\(name)) sent: \(sent)") }
            }
        }
    }

    // MARK: 3. Ordinary text isn't redacted

    static let ordinary = [
        "2026-10-14", "10/14/2026", "14.10.2026", "2026年10月14日", "2026-10-14 14:30:00", "14:30", "14:30:45", "2:30 PM", "UTC+08:00",
        "v1.2.3", "1.2.3", "version 10.15.7", "macOS 26.1", "Swift 6.2", "release-0.6.3", "build 2026.10.14",
        "order #123456789", "Order No. A-10023-77", "订单号 20261014123456", "invoice INV-2026-000123", "tracking 1Z999AA10123456784",
        "$19.99", "$1,299.99", "¥1999", "€12.50", "1,000,000", "3.14159", "50%", "100-200 items",
        "https://example.com/path?q=1&page=2", "https://github.com/MicroZ-LLC/AllInOneIME/issues/42", "www.apple.com",
        "getUserById(userId)", "snake_case_identifier_name", "com.apple.inputmethod.AllInOneIME", "XCTAssertEqualWithAccuracy",
        "UIApplicationDidFinishLaunchingNotification", "kCFStreamPropertySSLSettings", "AVCaptureVideoDataOutputSampleBufferDelegate",
        "my-feature-branch-2024", "QuarterlyReview2024Q3", "test_user_profile_image_upload_2",
        "/Users/imac/workspace/AllInOneIME/Sources/main.swift", "~/Library/Application Support/AllInOneIME/config.json",
        #"C:\Users\me\Documents\report-2026.docx"#, "./Scripts/build.sh", "src/components/Button.tsx:42",
        "ISBN 978-3-16-148410-0", "room 1203", "page 12 of 30", "3 x 4 = 12", "@improve", "#hashtag",
    ]

    @Test(arguments: ordinary) func ordinaryTextStays(_ text: String) throws {
        var r = try #require(Redaction(Secret.settings))
        let line = "See \(text) here"
        #expect(r.hide(line) == line, "over-matched: \(r.hide(line))")
    }

    /// Text that looks like a value and may be hidden (over-cautious, tolerated): printed for the report, not failed.
    @Test func toleratedOverCaution() throws {
        let cases = [
            "git@github.com:org/repo.git", "https://user@example.com/x", "550e8400-e29b-41d4-a716-446655440000",
            "a3f5c9e1b7d2468f0a1b2c3d4e5f60718293a4b5", "1.0.0.1", "123-456-7890", "Order 4000000000000002",
            "MAC 00:1A:2B:3C:4D:5E", "dead::beef", "user@localhost", "A1B2-C3D4-E5F6-G7H8-I9J0",
        ]
        for text in cases {
            var r = try #require(Redaction(Secret.settings))
            let out = r.hide(text)
            print("TOLERATED \(out == text ? "kept  " : "HIDDEN") \(text) -> \(out)")
        }
    }

    // MARK: 4. Restoring

    static let variants: [String] = [
        "[K_N]", "[ K_N ]", "[k_n]", "[K n]", "[K-N]", "[KN]", "(K_N)", "（K_N）", "【K_N】", "［K_N］", "K_N", "k_n",
        "[电子邮件_N]", "[邮箱_N]", "【邮箱_N】", "[メール_N]", "[correo_N]", "[courriel_N]", "[E-Mail_N]", "[Email N]",
    ]

    /// A placeholder the model changed (spacing, case, brackets, a translated label) still gets the real value.
    @Test(arguments: variants) func restoresAlteredPlaceholder(_ variant: String) throws {
        var r = try #require(Redaction(Secret.settings))
        let sent = r.hide("Write to \(Secret.email) today")
        let placeholder = try #require(placeholders(in: sent).first)
        let number = String(placeholder.dropFirst("[EMAIL_".count).dropLast())
        let written = variant.replacingOccurrences(of: "K", with: "EMAIL").replacingOccurrences(of: "k", with: "email")
            .replacingOccurrences(of: "N", with: number).replacingOccurrences(of: "n", with: number)
        let line = "Bitte an \(written) schreiben, again \(written)."
        let restored = r.restore(line)
        #expect(restored == "Bitte an \(Secret.email) schreiben, again \(Secret.email).", "\(written) -> \(restored)")
        #expect(!Redaction.isAltered(restored))
    }

    /// A placeholder past telling stays as written and the row is marked; no other value is put in its place.
    @Test func unrestorablePlaceholderIsMarked() throws {
        var r = try #require(Redaction(Secret.settings))
        _ = r.hide("Mail \(Secret.email) or \(Secret.phone), card \(Secret.card)")
        for line in ["Mail [EMAIL_9] now", "Call [PHONE_7]", "Pay with [CARD_4]", "Use [KEY_1]", "Write [Adresse_2] here"] {
            let out = r.restore(line)
            #expect(Redaction.isAltered(out), "not marked: \(out)")
            #expect(!Secret.forms.contains { out.contains($0) }, "a wrong value shown: \(line) -> \(out)")
        }
        // Dropped: the row simply lacks it, nothing marked, nothing else put in.
        #expect(r.restore("Mail them now") == "Mail them now")
        #expect(!Redaction.isAltered("Mail them now"))
    }

    /// Words of the user's own that look like placeholders are not values: never replaced by one.
    @Test func identifiersLikePlaceholdersStayAsWritten() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "ident")
        rig.reply(echoAnswer)
        let input = "Why does ip_1 = '10.0.0.1' and ip_2 = '10.0.0.2' fail? email_1 = '\(Secret.email)'"
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        #expect(updates.last?.result.versions.first?.text == "Re: " + input, "\(updates.last?.result.versions.first?.text ?? "")")
    }

    /// Bracketed words of the user's own ("[Item 1]", "[TODO_1]") are left alone when values were hidden.
    @Test func bracketedWordsInTheTextStayAsWritten() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "brack")
        rig.reply(echoAnswer)
        let input = "Checklist: [Item 1] ask Phoenix, [TODO_1] mail \(Secret.email)"
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        #expect(updates.last?.result.versions.first?.text == "Re: " + input, "\(updates.last?.result.versions.first?.text ?? "")")
    }

    /// Every row (versions, translations, rewrites) gets its values back; a row with a placeholder changed past telling
    /// is the only one marked.
    @Test func everyRowIsRestored() async throws {
        let rig = LeakRig(wire: .openai, tag: "rows")
        let input = "请联系 \(Secret.email) 或 Phoenix 团队"
        let config = onConfig { $0.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja")]) }
        let tags = WritingPlan.make(.both, text: input, config: config).lineTags
        #expect(tags.count >= 5)
        rig.reply { sent in
            tags.enumerated().map { index, tag in
                index == 1 ? "\(tag): \(sent.replacingOccurrences(of: "[EMAIL_1]", with: "[EMAIL_5]"))\n"
                    : index == 2 ? "\(tag): \(sent.replacingOccurrences(of: "[EMAIL_1]", with: "【邮箱 1】"))\n" : "\(tag): \(sent)\n"
            }
        }
        let final = try #require(try await leakCollect(rig.converter(config).convert(input)).last)
        let rows = leakRows(final.result)
        #expect(rows.count == tags.count)
        for (index, row) in rows.enumerated() {
            if index == 1 {
                #expect(Redaction.isAltered(row) && !row.contains(Secret.email), "row 1: \(row)")
            } else {
                #expect(row == input, "row \(index): \(row)")
                #expect(!Redaction.isAltered(row))
            }
        }
    }

    // MARK: 5. Consistency

    @Test func sameValueSamePlaceholderDifferentValuesDifferent() async throws {
        var r = try #require(Redaction(Secret.settings))
        let other = "li.si@example-corp.com"
        let out = r.hide("\(Secret.email), \(other), again \(Secret.email) and \(Secret.email); \(other)")
        let found = placeholders(in: out)
        #expect(found.count == 5)
        #expect(found[0] == found[2] && found[2] == found[3] && found[1] == found[4] && found[0] != found[1], "\(out)")
        #expect(r.count == 2)

        // Within one request, a value in the custom prompt and in the text gets one placeholder in both.
        let rig = LeakRig(wire: .anthropic, tag: "same")
        rig.reply(echoAnswer)
        let command = customCommand("cc", prompt: "Always cc \(Secret.email) and \(other).")
        _ = try await leakCollect(rig.converter(onConfig()).generate(command, input: "write to \(Secret.email)"))
        let request = try #require(rig.requests.first)
        let inText = placeholders(in: sentText(request, .anthropic))
        let inPrompt = placeholders(in: systemText(request))
        #expect(inText.count == 1 && inPrompt.count >= 2 && inPrompt.contains(inText[0]), "\(inText) \(inPrompt)")
        #expect(Set(inPrompt).count == 2)
    }

    /// Many values: each its own number, each put back where it belongs, in whatever order the model writes them.
    @Test func manyDistinctValues() throws {
        var r = try #require(Redaction(Secret.settings))
        let emails = (1...15).map { "user\($0)@corp\($0).com" }
        let text = emails.joined(separator: ", ")
        let out = r.hide(text)
        let found = placeholders(in: out)
        #expect(found.count == 15 && Set(found).count == 15, "\(out)")
        #expect(r.restore(out) == text)
        let reversed = found.reversed().joined(separator: " | ")
        #expect(r.restore(reversed) == emails.reversed().joined(separator: " | "))
    }

    /// A value inside another (an email in a longer one, a word in a phrase and in an email).
    @Test func valuesInsideOthers() async throws {
        let settings = RedactionSettings(enabled: true, customWords: ["Atlas", "Atlas Prime"])
        var r = try #require(Redaction(settings))
        let text = "bob@x.io, jimbob@x.io, Atlas Prime, Atlas, atlas@corp.io"
        let out = r.hide(text)
        for value in ["bob@x.io", "Atlas", "atlas@"] { #expect(out.range(of: value, options: .caseInsensitive) == nil, "\(value) in \(out)") }
        #expect(r.restore(out) == text)

        let rig = LeakRig(wire: .ollama, tag: "inside")
        rig.reply(echoAnswer)
        let command = customCommand("route", prompt: "Route to jimbob@x.io, bob@x.io or Atlas Prime.")
        _ = try await leakCollect(rig.converter(onConfig(settings)).generate(command, input: "ask bob@x.io about Atlas"))
        #expect(leaked(rig.requests, ["bob@x.io"], anyCase: ["atlas"]).isEmpty, "\(leaked(rig.requests, ["bob@x.io"], anyCase: ["atlas"]))")
    }

    // MARK: 6. No change when nothing is hidden

    @Test func requestsUnchangedWhenOff() async throws {
        for (index, scenario) in GoldenScenario.all.enumerated() {
            let digest = try await scenario.digest(tag: "gold\(index)") { $0.redaction = RedactionSettings(enabled: false, customWords: ["Phoenix"]) }
            #expect(digest == goldenDigests[scenario.name], "\(scenario.name) differs from release-0.6.3 with hiding off")
        }
    }

    @Test func requestsUnchangedWhenOnAndNothingFound() async throws {
        for (index, scenario) in GoldenScenario.all.enumerated() {
            let digest = try await scenario.digest(tag: "gold\(index)") { $0.redaction = RedactionSettings(enabled: true, customWords: ["Zanzibar"]) }
            #expect(digest == goldenDigests[scenario.name], "\(scenario.name) differs from release-0.6.3 with hiding on, nothing found")
        }
    }

    /// With something hidden the request is what it was for the text with the placeholder typed in, and a short note.
    @Test func somethingHiddenAddsOnlyTheNote() async throws {
        let input = "请把报告发到 \(Secret.email)"
        let typed = "请把报告发到 [EMAIL_1]"
        func request(_ text: String, on: Bool, tag: String) async throws -> [String: Any] {
            let rig = LeakRig(wire: .anthropic, tag: tag)
            rig.reply { _ in ["EN: ok\n"] }
            _ = try await leakCollect(rig.converter(onConfig(RedactionSettings(enabled: on))).convert(text))
            let body = try #require(rig.requests.first).body
            let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            return try #require(object)
        }
        let hidden = try await request(input, on: true, tag: "noteon")
        let plain = try await request(typed, on: false, tag: "noteoff")
        func json(_ v: Any?) throws -> Data { try JSONSerialization.data(withJSONObject: v ?? [], options: [.sortedKeys]) }
        #expect(try json(hidden["messages"]) == json(plain["messages"]))
        let system = try #require(hidden["system"] as? String), before = try #require(plain["system"] as? String)
        #expect(system.hasPrefix(before))
        let note = system.dropFirst(before.count)
        #expect(!note.isEmpty && note.count < 400 && note.localizedCaseInsensitiveContains("placeholder"), "\(note)")
    }

    // MARK: 7. @reportissue

    @Test func reportSaysOnOrOffOnly() throws {
        for on in [true, false] {
            var config = Config.default
            config.redaction = RedactionSettings(enabled: on, customWords: ["Phoenix", "凤凰计划", "ceo@corp-secret.com"])
            let diagnostics = IssueReport.Diagnostics(config: config, macOS: "26.1", architecture: "arm64", interfaceLanguage: "en",
                                                      languagePacks: [], plugins: 0, extensions: 0)
            let report = IssueReport(title: "Crash", diagnostics: diagnostics)
            let everything = report.lines.joined(separator: "\n") + report.body(lines: report.lines) + report.url.absoluteString
            #expect(report.lines.contains { $0.contains(on ? "on" : "off") && $0.localizedCaseInsensitiveContains("sensitive") }, "\(report.lines)")
            for word in ["Phoenix", "凤凰计划", "%E5%87%A4", "ceo@corp-secret.com", "ceo%40corp"] {
                #expect(!everything.localizedCaseInsensitiveContains(word), "\(word) in the report")
            }
        }
    }

    // MARK: 8. What the panel is told

    @Test func hiddenCountForThePanel() async throws {
        let rig = LeakRig(wire: .hosted, tag: "count")
        rig.reply(echoAnswer)
        let input = "mail \(Secret.email) twice \(Secret.email), call \(Secret.phone), about Phoenix"
        let on = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        #expect(on.allSatisfy { $0.hidden == 3 }, "\(on.map(\.hidden))")
        let off = try await leakCollect(rig.converter(onConfig(RedactionSettings(enabled: false))).generate(.question, input: input))
        #expect(off.allSatisfy { $0.hidden == 0 })
        let nothing = try await leakCollect(rig.converter(onConfig()).generate(.question, input: "nothing to hide here"))
        #expect(nothing.allSatisfy { $0.hidden == 0 })
    }

    // MARK: Leak hunting

    /// Values each on a line of their own, in a multi-line question.
    @Test func valuesOnSeparateLines() async throws {
        let rig = LeakRig(wire: .bedrock, tag: "lines")
        rig.reply(echoAnswer)
        let input = Secret.all.joined(separator: "\n")
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        #expect(leaked(rig.requests, Secret.forms).isEmpty, "\(leaked(rig.requests, Secret.forms))")
        #expect(updates.last?.result.versions.first?.text == "Re: " + input)
    }

    /// A value broken by a line break (a card number wrapped in a pasted text, a phrase of the user's on two lines).
    @Test func valueSplitAcrossLines() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "split")
        rig.reply(echoAnswer)
        let input = "card 4111 1111\n1111 1111, phone 138 0013\n8000, about Project\nAtlas"
        _ = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        let sent = sentText(try #require(rig.requests.first), .anthropic)
        #expect(!Self.digits(sent).contains("4111111111111111"), "card readable across the line break: \(sent)")
        #expect(!Self.digits(sent).contains("13800138000"), "phone readable across the line break: \(sent)")
        #expect(!sent.contains("Project\nAtlas"), "phrase readable across the line break: \(sent)")
    }

    /// The jargon list: an entry with a value (one in the sentence, or another kind anywhere) is never sent.
    @Test func jargonListNeverCarriesValues() async throws {
        let rig = LeakRig(wire: .gemini, tag: "jargon")
        let jargon = [JargonEntry(term: "Phoenix", meaning: "our launch codename"),
                      JargonEntry(term: "ping ops", meaning: "mail ops@corp-secret.com or call 555-123-4567"),
                      JargonEntry(term: "对齐", meaning: "align")]
        let input = "Phoenix 上线前要先和 \(Secret.email) 对齐"
        let config = onConfig { $0.rewriteStyles = ["黑话", "润色"] }
        rig.reply(echoLines(WritingPlan.make(.both, text: input, config: config).lineTags))
        let updates = try await leakCollect(rig.converter(config, jargon: jargon).convert(input))
        let found = leaked(rig.requests, [Secret.email, "ops@corp-secret.com", "555-123-4567"], anyCase: ["phoenix"])
        #expect(found.isEmpty, "\(found)")
        #expect(systemText(try #require(rig.requests.first)).contains("对齐"))  // the harmless entry still goes
        #expect(leakRows(try #require(updates.last).result).allSatisfy { $0 == input })
    }

    /// Full-width characters typed in a Chinese input mode, and look-alike letters.
    static let lookalikes: [(text: String, readable: String)] = [
        ("zhang＠example.com", "zhang@example.com"),
        ("ｚｈａｎｇ@ｅｘａｍｐｌｅ.ｃｏｍ", "zhang@example.com"),
        ("１３８００１３８０００", "13800138000"),
        ("４１１１ １１１１ １１１１ １１１１", "4111111111111111"),
        ("２０３.０.１１３.４２", "203.0.113.42"),
        ("Ｐｈｏｅｎｉｘ", "phoenix"),
        ("ｓｋ－ａｎｔ－ａｐｉ０３－Ｚｘ９Ｑｗ７Ｅｒ５Ｔｙ３Ｕｉ１Ｏｐ８Ａｓ６Ｄｆ４", "sk-\u{61}nt-api03-zx9qw7er5ty3ui1op8as6df4"),
    ]

    @Test(arguments: lookalikes.indices) func lookalikesAreHidden(_ index: Int) throws {
        let (text, readable) = Self.lookalikes[index]
        var r = try #require(Redaction(Secret.settings))
        let out = r.hide("联系 \(text) 谢谢")
        // As a reader (or a model) folds it: compatibility forms to plain ones, Cyrillic о to o, spaces gone.
        let folded = out.precomposedStringWithCompatibilityMapping.lowercased().replacingOccurrences(of: "о", with: "o")
            .replacingOccurrences(of: " ", with: "")
        #expect(!folded.contains(readable.replacingOccurrences(of: " ", with: "")), "\(text) sent readable: \(out)")
    }

    /// Look-alike letters from another script (a Cyrillic о in "Phoenix"): a known limit, the feature guards against
    /// accidental leaks, not someone disguising a word on purpose.
    @Test func homoglyphsAreAKnownLimit() throws {
        withKnownIssue("Cyrillic and Greek look-alikes aren't folded (documented known limit)") {
            var r = try #require(Redaction(Secret.settings))
            let out = r.hide("联系 Phоenix 谢谢")
            #expect(!out.lowercased().replacingOccurrences(of: "о", with: "o").contains("phoenix"), "sent readable: \(out)")
        }
    }

    /// Precomposed and decomposed accents are the same word.
    @Test func customWordInAnotherNormalization() throws {
        var r = try #require(Redaction(RedactionSettings(enabled: true, customWords: ["Café Zürich"])))
        let out = r.hide("meet at Cafe\u{301} Zu\u{308}rich")
        #expect(!out.precomposedStringWithCanonicalMapping.contains("Café Zürich"), "\(out)")
    }

    /// The provider's own settings: a model id or address that holds a word of the user's. The conversation itself must
    /// stay clean; the model id and address can't be hidden (printed for the report).
    @Test func configTextHoldingAWord() async throws {
        let rig = LeakRig(wire: .openai, tag: "phoenixgw")
        rig.reply(echoAnswer)
        var config = rig.configure(onConfig())
        config.openai.model = "phoenix-chat-7b"
        let fixed = config
        let converter = Converter(client: BedrockClient(session: LeakRecorder.session()), loadConfig: { fixed },
                                  loadKey: { _, _ in "test-key" })
        _ = try await leakCollect(converter.generate(.question, input: "Is Phoenix ready? mail \(Secret.email)"))
        let request = try #require(rig.requests.first)
        let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let conversation = try #require(json["messages"] as? [[String: Any]]).compactMap { $0["content"] as? String }.joined(separator: "\n")
        #expect(conversation.range(of: "phoenix", options: .caseInsensitive) == nil && !conversation.contains(Secret.email), "\(conversation)")
        print("CONFIGTEXT model=\(json["model"] ?? "-") url=\(request.url)")
    }

    /// The cache: a hit restores the values without a request; another value is another request (keyed by the real
    /// text, not by the placeholders).
    @Test func cacheKeyedByRealTextAndRestoredOnHit() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "cache")
        rig.reply(echoAnswer)
        let converter = rig.converter(onConfig())
        let first = try await leakCollect(converter.generate(.question, input: "mail \(Secret.email)"))
        let again = try await leakCollect(converter.generate(.question, input: "mail \(Secret.email)"))
        #expect(rig.requests.count == 1)
        #expect(again.count == 1 && again[0].fromCache)
        #expect(again[0].result == first.last?.result && again[0].result.versions.first?.text == "Re: mail \(Secret.email)")
        let other = try await leakCollect(converter.generate(.question, input: "mail li.si@example-corp.com"))
        #expect(rig.requests.count == 2 && other.last?.fromCache == false)
        #expect(other.last?.result.versions.first?.text == "Re: mail li.si@example-corp.com")

        let commandRequests = rig.requests
        let config = onConfig()
        rig.reply(echoLines(WritingPlan.make(.both, text: "mail \(Secret.email)", config: config).lineTags))  // starts a new log
        let c1 = try await leakCollect(converter.convert("mail \(Secret.email)"))
        let c2 = try await leakCollect(converter.convert("mail \(Secret.email)"))
        let c3 = try await leakCollect(converter.convert("mail li.si@example-corp.com"))
        #expect(rig.requests.count == 2)
        #expect(c2.count == 1 && c2.first?.fromCache == true && c2.first?.result == c1.last?.result)
        #expect(leakRows(try #require(c1.last).result).allSatisfy { $0 == "mail \(Secret.email)" })
        #expect(leakRows(try #require(c3.last).result).allSatisfy { $0 == "mail li.si@example-corp.com" })
        #expect(leaked(commandRequests + rig.requests, [Secret.email, "li.si@example-corp.com"]).isEmpty)
    }

    /// Streaming one character at a time: what is shown is always the start of the final, restored text (no piece of
    /// a placeholder shown raw), for a command's answer and for the conversion's rows.
    @Test(arguments: [LeakWire.anthropic, .bedrock])
    func streamingNeverShowsAPartialPlaceholder(_ wire: LeakWire) async throws {
        let rig = LeakRig(wire: wire, tag: "stream")
        rig.reply { sent in ("Re: " + sent).map(String.init) }
        let input = "mail \(Secret.email) and \(Secret.claudeKey) now"
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        let final = try #require(updates.last?.result.versions.first?.text)
        #expect(final == "Re: " + input)
        for update in updates.dropLast() {
            let shown = update.result.versions.first?.text ?? ""
            #expect(final.hasPrefix(shown), "shown mid-stream: \(shown)")
        }

        let rigC = LeakRig(wire: wire, tag: "streamc")
        let config = onConfig()
        let tags = WritingPlan.make(.both, text: input, config: config).lineTags
        rigC.reply { sent in tags.map { "\($0): \(sent)\n" }.joined().map(String.init) }
        let rows = try await leakCollect(rigC.converter(config).convert(input))
        let finalRows = leakRows(try #require(rows.last).result)
        #expect(finalRows.allSatisfy { $0 == input })
        for update in rows.dropLast() {
            for (index, row) in leakRows(update.result).enumerated() where index < finalRows.count {
                #expect(finalRows[index].hasPrefix(row), "row \(index) mid-stream: \(row)")
            }
        }
    }

    /// Ten or more values of a kind: while "[EMAIL_1" has arrived of "[EMAIL_10]", no other value is shown.
    @Test func streamingManyValuesNeverShowsAnotherValue() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "streamn")
        rig.reply { sent in ("Re: " + sent).map(String.init) }
        let input = (1...12).map { "user\($0)@corp\($0).com" }.joined(separator: " ")
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        let final = try #require(updates.last?.result.versions.first?.text)
        #expect(final == "Re: " + input)
        for update in updates.dropLast() {
            let shown = update.result.versions.first?.text ?? ""
            #expect(final.hasPrefix(shown), "shown mid-stream: \(shown)")
        }
    }

    /// The same when the model wrote the placeholder without its square brackets or with round ones.
    @Test(arguments: ["EMAIL_1", "(EMAIL_1)", "【邮箱_1】"])
    func streamingAlteredPlaceholder(_ written: String) async throws {
        let rig = LeakRig(wire: .openai, tag: "streama\(written.count)")
        rig.reply { sent in ("Re: " + sent.replacingOccurrences(of: "[EMAIL_1]", with: written)).map(String.init) }
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: "mail \(Secret.email) now"))
        let final = try #require(updates.last?.result.versions.first?.text)
        #expect(final.contains(Secret.email), "\(final)")
        for update in updates.dropLast() {
            let shown = update.result.versions.first?.text ?? ""
            #expect(final.hasPrefix(shown), "\(written) shown mid-stream: \(shown)")
        }
    }
    // MARK: Leak hunting, second round (after the fixes)

    /// Values after characters that change length when folded (emoji, combining marks, ligatures, full-width forms):
    /// what is hidden and put back is exactly the text as typed.
    static let foldingContexts = [
        "👨‍👩‍👧‍👦🇨🇳 mail zhang@example.com now", "e\u{301}e\u{301}e\u{301} zhang＠example.com ok", "ﬁle ﬂow: zhang@example.com",
        "㈱会社 ① ② ｚｈａｎｇ＠ｅｘａｍｐｌｅ.ｃｏｍ 谢谢", "Ａ１ 😀 13800138000 😀 ４１１１ １１１１ １１１１ １１１１",
        "café Zu\u{308}rich 🙂 Phoenix 🙂 \(Secret.claudeKey)", "ｓｋ－ａｎｔ－ａｐｉ０３－Ｚｘ９Ｑｗ７Ｅｒ５Ｔｙ３Ｕｉ１Ｏｐ８ＡｓＸ and ＰＨＯＥＮＩＸ",
        "👍🏽e\u{301}\u{302}２０３.０.１１３.４２🔥",
    ]

    @Test(arguments: foldingContexts.indices) func foldedOffsetsMapBack(_ index: Int) throws {
        let text = Self.foldingContexts[index]
        var r = try #require(Redaction(Secret.settings))
        let out = r.hide(text)
        #expect(r.count >= 1, "nothing hidden in \(text)")
        let folded = out.precomposedStringWithCompatibilityMapping.lowercased()
        for readable in ["zhang@example.com", "13800138000", "4111 1111 1111 1111", "phoenix", "203.0.113.42", "sk-\u{61}nt-api03-zx9qw7"] {
            #expect(!folded.contains(readable), "\(readable) readable in \(out)")
        }
        // Nothing around a value is eaten or doubled, and each value comes back as typed.
        #expect(r.restore(out) == text, "\(text) -> \(out) -> \(r.restore(out))")
        for entry in r.hidden { #expect(text.contains(entry.value), "\(entry.value) isn't a piece of \(text)") }
    }

    /// A custom command's prompt with emoji and full-width values that the text doesn't hold.
    @Test func foldedValuesInACustomPrompt() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "foldprompt")
        rig.reply(echoAnswer)
        let command = customCommand("sig", prompt: "🙂 Sign as ｃｅｏ＠ｃｏｒｐ－ｓｅｃｒｅｔ.ｃｏｍ, phone １３８ ００１３ ８０００ 🙂")
        _ = try await leakCollect(rig.converter(onConfig()).generate(command, input: "e\u{301} write to \(Secret.email)"))
        let system = systemText(try #require(rig.requests.first)).precomposedStringWithCompatibilityMapping
        #expect(!system.contains("ceo@corp-secret.com") && !system.contains("138 0013 8000"), "\(system)")
        #expect(leaked(rig.requests, [Secret.email]).isEmpty)
    }

    /// Placeholder-shaped words of the user's own reserve their numbers: whatever the model echoes, they stay as
    /// written and the values come back where they were.
    @Test func reservedNumbers() async throws {
        let rig = LeakRig(wire: .anthropic, tag: "reserved")
        rig.reply(echoAnswer)
        let input = "ip_1 = '10.0.0.1'; IP_2 = '10.0.0.2'; see [EMAIL_1], email 2 and item1; mail \(Secret.email) or li@x.io; ask Phoenix"
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        let sent = sentText(try #require(rig.requests.first), .anthropic)
        #expect(leaked(rig.requests, ["10.0.0.1", "10.0.0.2", Secret.email, "li@x.io"], anyCase: ["phoenix"]).isEmpty)
        for taken in ["[IP_1]", "[IP_2]", "[EMAIL_1]", "[EMAIL_2]", "[ITEM_1]"] {
            #expect(placeholders(in: sent).filter { $0 == taken }.count == (taken == "[EMAIL_1]" ? 1 : 0), "\(taken) issued: \(sent)")
        }
        #expect(updates.last?.result.versions.first?.text == "Re: " + input, "\(updates.last?.result.versions.first?.text ?? "")")

        // The model changing the case of the user's own identifiers doesn't bring in a value either.
        var r = try #require(Redaction(Secret.settings))
        _ = r.hide(input)
        let changed = r.restore("IP_1 = '[IP_3]'; Ip_2 = '[IP_4]'; EMAIL_1, [Email 2], ITEM1")
        #expect(changed.hasPrefix("IP_1 = '10.0.0.1'; Ip_2 = '10.0.0.2'; EMAIL_1, [Email 2], ITEM1"), "\(changed)")
    }

    /// What a line ends with when the stream is over is never held back: words that start like a placeholder, an
    /// open bracket, a placeholder without brackets.
    static let endings = ["send it by email", "and so do I", "pay by card", "use the key", "it", "see [", "(see note", "Item 1",
                          "【备注", "the IP", "a WORD", "Card_12", "mail EMAIL_1"]

    @Test(arguments: endings) func streamEndIsNeverHeldBack(_ ending: String) async throws {
        let rig = LeakRig(wire: .openai, tag: "end\(Self.endings.firstIndex(of: ending)!)")
        rig.reply { sent in ("Re: " + sent + " " + ending).map(String.init) }
        let input = "mail \(Secret.email)"
        let expected = "Re: " + input + " " + ending.replacingOccurrences(of: "EMAIL_1", with: Secret.email)
        let updates = try await leakCollect(rig.converter(onConfig()).generate(.question, input: input))
        #expect(updates.last?.result.versions.first?.text == expected, "\(updates.last?.result.versions.first?.text ?? "")")
        for update in updates.dropLast() {
            #expect(expected.hasPrefix(update.result.versions.first?.text ?? ""), "mid-stream: \(update.result.versions.first?.text ?? "")")
        }

        let rigC = LeakRig(wire: .openai, tag: "endc\(Self.endings.firstIndex(of: ending)!)")
        let config = onConfig { $0.rewriteStyles = [] }
        rigC.reply { sent in ("EN: \(sent) \(ending)\nEN: \(sent) \(ending)\nEN: \(sent) \(ending)").map(String.init) }
        let rows = leakRows(try #require(try await leakCollect(rigC.converter(config).convert(input)).last).result)
        // (Identical versions are shown once.)
        #expect(!rows.isEmpty && Set(rows) == [input + " " + ending.replacingOccurrences(of: "EMAIL_1", with: Secret.email)], "\(rows)")
    }

    /// A placeholder whose closing bracket the model dropped, at the end of the answer: restored, or else marked.
    @Test func unclosedPlaceholderAtTheEnd() throws {
        var r = try #require(Redaction(Secret.settings))
        _ = r.hide("mail \(Secret.email)")
        for line in ["mail [EMAIL_1", "mail [EMAIL_1 today", "mail (EMAIL_1"] {
            let out = r.restore(line)
            #expect(out.contains(Secret.email) || Redaction.isAltered(out, original: "mail \(Secret.email)"), "neither restored nor marked: \(out)")
        }
    }

    /// Two emails joined by a slash, an email after a path-like word.
    @Test(arguments: ["cc: support@corp.com/sales@corp.com", "电话 13800138000/zhang@example.com", "Email/zhang@example.com",
                      "zhang@example.com／li@example.com"])
    func emailsAfterASlash(_ text: String) throws {
        var r = try #require(Redaction(Secret.settings))
        let out = r.hide(text)
        #expect(!out.contains("@"), "an email sent: \(out)")
    }

    /// Ordinary text the widened key pattern (base64's "/" and "+") must leave alone: identifiers, paths, URLs,
    /// long words, pinyin.
    static let notKeys = [
        "convertUTF8ToUTF16AndBack42", "getHTTP2ResponseForURLv3Id", "XMLHttpRequest2EventTarget", "base64EncodedStringWithOptions",
        "AVCaptureVideoDataOutputSampleBufferDelegate", "kCFStreamPropertySSLSettings", "NSLayoutConstraint2DAnchorX",
        "src/components/Button2Primary/index", "/Users/imac/workspace/AllInOneIME/Sources", "/var/log/2026/10/14/app-01",
        "Tests/AllInOneIMECoreTests/Acceptance", "github.com/MicroZ-LLC/AllInOneIME/issues/42", "C++/CLI/WinRT/Win32/x64/Release",
        "en.wikipedia.org/wiki/Pneumonoultramicroscopicsilicovolcanoconiosis", "antidisestablishmentarianism",
        "Supercalifragilisticexpialidocious", "woxiangmingtianqukaihuiyinweijiaoyoushi", "wo3xiang3ming2tian1qu4kai1hui4",
        "ni3hao3ma5wo3hen3hao3xie4xie4ni3", "ISO-8601-2026-10-14-report-v2", "release/0.6.3/redact-sensitive-v2",
        "feature/AIO-1234-hide-sensitive-info", "x86_64-apple-darwin25.0.0", "arm64-apple-macosx26.0",
        "1920x1080/2560x1440/3840x2160",
    ]

    @Test(arguments: notKeys) func widenedKeyPatternLeavesOrdinaryTextAlone(_ text: String) throws {
        var r = try #require(Redaction(Secret.settings))
        let line = "see \(text) here"
        #expect(r.hide(line) == line, "over-matched: \(r.hide(line))")
    }
    // MARK: Leak hunting, third round (the loosened key rule)

    /// Deterministic random strings (SplitMix64), so a failure always reproduces.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let alphabets: [(name: String, chars: String, length: Int)] = [
        ("base64 (AWS secret key)", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", 40),
        ("base64url", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", 43),
        ("letters and digits", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", 32),
        ("small letters and digits", "abcdefghijklmnopqrstuvwxyz0123456789", 32),
        ("hex", "0123456789abcdef", 40),
    ]

    /// Random secrets of the common shapes, 500 each: every one must be hidden (a miss is a leak).
    @Test(arguments: alphabets.indices) func randomSecretsAreAllHidden(_ index: Int) throws {
        let (name, chars, length) = Self.alphabets[index]
        let pool = Array(chars)
        var rng = SplitMix(state: UInt64(1000 + index))
        var missed: [String] = []
        for _ in 0..<500 {
            let secret = String((0..<length).map { _ in pool[Int(rng.next() % UInt64(pool.count))] })
            var r = try #require(Redaction(Secret.settings))
            if r.hide("secret = \(secret)").contains(secret) { missed.append(secret) }
        }
        print("RANDOM \(name): \(missed.count) of 500 sent, e.g. \(missed.prefix(3))")
        #expect(missed.isEmpty, "\(name): \(missed.count) of 500 sent as typed, e.g. \(missed.prefix(5))")
    }

    /// Real-looking secrets the word and path rules might now let through.
    static let secretShapes = [
        "wJalrXUtnF/EMIK7MDEN/GbPxRfiCYE/XAMPLEKEY12",  // a 40-character AWS secret with its "/" pieces under 12
        "\u{77}JalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "sk_\u{6C}ive_AbCdEfGhIjKlMnOpQrStUvWx",  // a Stripe key that happens to have no digit
        "rk_\u{6C}ive_51HxYzAbCdEfGhIjKlMnOpQrSt",
        "ey\u{4A}hbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.ey\u{4A}zdWIiOiJhZG1pbiIsIm5hbWUiOiJKb2huIn0.c2lnbmF0dXJlLXZhbHVlLWhlcmU",
        "AI\u{7A}aSyD4f8G2h6J9kL1mN3pQ5rS7tU9vW0xY2zA", "xo\u{78}b-1234567890-0987654321-AbCdEfGhIjKlMnOpQrStUvWx",
        "T0123ABCD/B0456EFGH/8Fz3kQpL0vX2mN7rT4wY9bHc",  // a Slack webhook's path
        "dGhpcyBpcyBhIHZlcnkgc2VjcmV0IHBhc3N3b3JkIGZvciB0aGUgYWRtaW4=",  // base64 of a sentence

    ]

    @Test(arguments: secretShapes) func secretShapesAreHidden(_ secret: String) throws {
        var r = try #require(Redaction(Secret.settings))
        for context in ["key: \(secret)", "https://hooks.slack.com/services/\(secret)", "\"\(secret)\""] {
            let out = r.hide(context)
            #expect(!out.contains(secret), "sent as typed: \(out)")
        }
    }

    /// A private key pasted in a PEM block: no line of it goes out as typed.
    @Test func privateKeyPEMBlock() throws {
        var rng = SplitMix(state: 42)
        let bytes = (0..<1190).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
        let body = Data(bytes).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let pem = "-----B\u{45}GIN PRIVATE KEY-----\n\(body)\n-----END PRIVATE KEY-----"
        var r = try #require(Redaction(Secret.settings))
        let out = r.hide("@question is this key valid?\n\(pem)")
        let lines = body.split(separator: "\n").map(String.init)
        let sent = lines.filter { out.contains($0) }
        #expect(sent.isEmpty, "\(sent.count) of \(lines.count) key lines sent as typed: \(sent.map { $0.count })")
    }
    // MARK: Final probe (the redesigned key check). Secret-like values are made at run time from a seeded generator.

    /// A random string of `length` from `chars`, with at least one character of each of `musts` when given.
    static func randomString(_ chars: String, _ length: Int, _ rng: inout SplitMix, musts: [String] = []) -> String {
        let pool = Array(chars)
        var out = (0..<length).map { _ in pool[Int(rng.next() % UInt64(pool.count))] }
        for (i, must) in musts.enumerated() where !out.contains(where: { must.contains($0) }) {
            let m = Array(must)
            out[(Int(rng.next() % UInt64(length)) + i) % length] = m[Int(rng.next() % UInt64(m.count))]
        }
        return String(out)
    }

    static let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ", lower = "abcdefghijklmnopqrstuvwxyz", digitChars = "0123456789"

    /// The shapes of secrets: a generic body, or a known prefix with a random body.
    static let shapes: [(name: String, make: @Sendable (inout SplitMix) -> String)] = [
        ("base64 40", { randomString(upper + lower + digitChars + "+/", 40, &$0) }),
        ("base64url 43", { randomString(upper + lower + digitChars + "-_", 43, &$0) }),
        ("letters and digits 32", { randomString(upper + lower + digitChars, 32, &$0) }),
        ("small letters and digits 32", { randomString(lower + digitChars, 32, &$0) }),
        ("small letters and digits 24", { randomString(lower + digitChars, 24, &$0, musts: [digitChars]) }),
        ("hex 32", { randomString("0123456789abcdef", 32, &$0) }),
        ("hex 64", { randomString("0123456789abcdef", 64, &$0) }),
        ("capitals and digits 20", { randomString(upper + digitChars, 20, &$0, musts: [digitChars]) }),
        ("prefix sk-", { "s" + "k-" + randomString(upper + lower + digitChars, 48, &$0) }),
        ("prefix sk_live_", { "sk" + "_live_" + randomString(upper + lower + digitChars, 24, &$0) }),
        ("prefix ghp_", { "gh" + "p_" + randomString(upper + lower + digitChars, 36, &$0) }),
        ("prefix AIza", { "AI" + "za" + randomString(upper + lower + digitChars + "-_", 35, &$0) }),
        ("prefix xoxb-", { "xo" + "xb-" + randomString(digitChars, 12, &$0) + "-" + randomString(upper + lower + digitChars, 24, &$0) }),
    ]

    static let seeds: [UInt64] = [7, 2026, 90_210]

    /// 500 secrets of each shape for each seed, on their own: every one hidden.
    @Test(arguments: shapes.indices, seeds) func seededSecretsAreAllHidden(_ shape: Int, _ seed: UInt64) throws {
        var rng = SplitMix(state: seed &+ UInt64(shape) &* 7919)
        var missed: [String] = []
        for _ in 0..<500 {
            let secret = Self.shapes[shape].make(&rng)
            var r = try #require(Redaction(Secret.settings))
            if r.hide("secret = \(secret)").contains(secret) { missed.append(secret) }
        }
        print("SEEDED \(Self.shapes[shape].name) seed \(seed): \(missed.count) of 500 sent")
        #expect(missed.isEmpty, "\(Self.shapes[shape].name), seed \(seed): \(missed.count) of 500 sent as typed")
    }

    /// Where a secret is pasted: a URL's query, JSON, an env line, a shell export, next to Chinese.
    static let placements: [String] = [
        "https://api.example.com/v1/items?token=SECRET&format=json", "https://example.com/cb?state=ok&key=SECRET",
        "https://example.com/download/files/SECRET/report.pdf", #"{"api_key": "SECRET", "region": "us-west-2"}"#,
        #"{"auth":{"token":"SECRET"}}"#, "OPENAI_API_KEY=SECRET", "export ANTHROPIC_API_KEY='SECRET'", "Authorization: Bearer SECRET",
        "密钥SECRET请保管好", "这是令牌：SECRET。", "SECRET是测试环境的密钥", "「SECRET」", "token=SECRET;path=/",
        "curl -u admin:SECRET https://example.com", "password: SECRET\nuser: admin",
    ]

    @Test(arguments: placements) func secretsInPlaceAreHidden(_ placement: String) throws {
        var rng = SplitMix(state: UInt64(placement.utf8.count) &* 31 &+ 5)
        var missed: [String] = []
        for shape in Self.shapes.indices {
            for _ in 0..<40 {
                let secret = Self.shapes[shape].make(&rng)
                var r = try #require(Redaction(Secret.settings))
                let text = placement.replacingOccurrences(of: "SECRET", with: secret)
                let out = r.hide(text)
                if out.contains(secret) { missed.append(Self.shapes[shape].name) }
                // Nothing around it eaten: what is put back is the text as typed.
                #expect(r.restore(out) == text)
            }
        }
        let summary = Dictionary(grouping: missed, by: { $0 }).mapValues(\.count)
        print("PLACED \(placement.prefix(30)): \(summary)")
        #expect(missed.isEmpty, "\(placement): sent as typed \(summary)")
    }

    /// Ordinary prose, code and Chinese with pinyin: nothing hidden.
    static let plainTexts: [String] = [
        "The quarterly report is attached; please review the internationalization and localization sections before Friday.",
        "Notwithstanding the aforementioned considerations, the counterrevolutionaries' uncharacteristically straightforward proposal passed.",
        "In 2026 we shipped 3 releases, fixed 142 bugs and closed issue #4821 after 17 reviews.",
        "func testRedactionHidesEmailsInCustomPrompts() throws { XCTAssertEqualWithAccuracy(value, 0.5, accuracy: 0.01) }",
        "let options = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; let d = UIViewControllerTransitioningDelegate.self",
        "NSPersistentCloudKitContainerOptions and AVCaptureMultiCamSession and kCGImagePropertyExifDictionary",
        "def calculate_monthly_revenue_2026(dataframe): return dataframe.groupby('customer_segment_name').sum()",
        "GL_COLOR_ATTACHMENT0 VK_KHR_SWAPCHAIN_EXTENSION_NAME CONFIG_DEBUG_INFO_BTF_MODULES kAudioUnitSubType_HRTFPanner",
        "docker pull nginx:1.25.3-alpine3.18 && brew install python@3.12 && npm i @babel/preset-env@7.24.0",
        "build/Release-iphoneos/AllInOneIME.app/Contents/MacOS and Sources/AllInOneIMECore/RedactionWords.swift",
        "MTLPixelFormatBGRA8Unorm_sRGB AbstractSingletonProxyFactoryBean getHTTP2ResponseForURLv3Id convertUTF8ToUTF16AndBack42",
        "我想明天去开会 woxiangmingtianqukaihui，wo3xiang3ming2tian1qu4kai1hui4，nihaowoshizhangsanhengaoxingrenshini",
        "北京大学 Beijing Daxue, zhongguorenminyinhang 中国人民银行, Shanghai Jiaotong University",
        "https://en.wikipedia.org/wiki/Internationalization_and_localization#Software_development",
        "https://github.com/MicroZ-LLC/AllInOneIME/blob/release-0.6.3/Sources/AllInOneIMECore/Redaction.swift#L421",
        "C++/CLI/WinRT/Win32/x64/Release and /usr/local/lib/python3.12/site-packages/numpy/core/multiarray.py",
    ]

    @Test(arguments: plainTexts) func plainTextIsNotHidden(_ text: String) throws {
        var r = try #require(Redaction(Secret.settings))
        let out = r.hide(text)
        #expect(out == text, "over-matched: \(out)")
    }
}

