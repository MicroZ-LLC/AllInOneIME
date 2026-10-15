import CryptoKit
import Foundation
import os
import Testing
@testable import AllInOneIMECore

// Independent acceptance tests for "Per-app settings" (Config.appProfiles), written from the spec only.
//
// What the input controller does per text field (it lives in the app target, which these tests can't load) is played
// here as the controller is specified to: the starting language from `Config.startingInput`, typing out from
// `Config.applying(app:)`, and `Composer.aiRefusal` from `Config.allowsAI`. Requests go through the real `Converter`
// to a recording URL protocol, so "nothing was sent" is counted, not assumed.
//
// The golden prompts below (point 8) were produced from release-0.6.3 at 55d496e, before the feature, by compiling
// the "Shared with the golden dump" section of this file unchanged into a test there and running it.

// MARK: - Shared with the golden dump (compiled unchanged against release-0.6.3 @ 55d496e)

/// Records every request it is given (with its body), per host; answers with a short Claude-style stream.
final class PerAppAccRecorder: URLProtocol, @unchecked Sendable {
    private static let state = OSAllocatedUnfairLock(initialState: [String: [Data]]())

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PerAppAccRecorder.self]
        return URLSession(configuration: configuration)
    }

    /// The bodies of the requests sent to `host`, in order.
    static func bodies(_ host: String) -> [Data] { state.withLock { $0[host] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let sent = body
        Self.state.withLock { $0[host, default: []].append(sent) }
        let sse = [
            #"event: content_block_delta"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"EN: Fine.\nEN: Good.\nEN: OK.\n"}}"#, "",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, "",
            #"data: {"type":"message_stop"}"#, "",
        ].joined(separator: "\n")
        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(sse.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum PerAppAccGolden {
    enum Run {
        case convert(String, WritingMode)
        case generate(Command, String)
    }

    struct Case {
        var name: String
        var config: Config
        var run: Run
    }

    static let reply = Command.catalog([CustomCommand(name: "reply", type: .prompt, prompt: "Write a polite reply.")])
        .first { $0.name == "reply" }!

    static var configs: [(String, Config)] {
        var base = Config.default
        base.rewriteStyles = RewriteStyle.defaultNames
        base.outputLanguages = [.english, .chinese]
        base.improveTranslates = false
        var styles = base
        styles.rewriteStyles = ["口语", "委婉", "黑话"]
        var none = base
        none.rewriteStyles = []
        var three = base
        three.outputLanguages = [.english, .chinese, OutputLanguage("ja")]
        three.rewriteStyles = ["简洁"]
        return [("default", base), ("styles", styles), ("noStyles", none), ("threeOutputs", three)]
    }

    static let runs: [(String, Run)] = [
        ("improve-zh", .convert("今天天气很好，我们出去玩吧", .improve)),
        ("translate-zh", .convert("今天天气很好，我们出去玩吧", .translate)),
        ("both-zh", .convert("今天天气很好，我们出去玩吧", .both)),
        ("improve-en", .convert("this sentance have a error", .improve)),
        ("both-en", .convert("this sentance have a error", .both)),
        ("question", .generate(.question, "what is the capital of France")),
        ("custom-prompt", .generate(reply, "收到，谢谢")),
        ("edit-selection", .generate(.edit, Prompt.editRequest(instruction: "more formal", text: "hey can u send it"))),
        ("question-about-selection", .generate(.question, Prompt.question("summarize this", about: "Swift is a language."))),
    ]

    static var cases: [Case] {
        configs.flatMap { config in runs.map { Case(name: config.0 + "/" + $0.0, config: config.1, run: $0.1) } }
    }

    /// `config` sending to `host` through `provider` (an API-key provider).
    static func pointed(_ config: Config, at host: String, provider: Provider) -> Config {
        var config = config
        config.provider = provider
        switch provider {
        case .openai:
            config.openai.baseURL = "https://\(host)"
            config.openai.model = "gpt-test"
        default:
            config.anthropic.baseURL = "https://\(host)"
            config.anthropic.model = "claude-test"
        }
        return config
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The structure every provider's body is made from (Bedrock's and the hosted service's as they are).
    static func structure(_ c: Case) throws -> Data {
        let request: ConverseRequest
        switch c.run {
        case let .convert(text, mode): request = Prompt.request(for: text, mode: mode, config: c.config)
        case let .generate(command, input): request = Prompt.commandRequest(command, input: input, config: c.config)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(request)
    }
}

/// Per case: the structure's SHA-256, then the Claude API body's SHA-256 and length, then the OpenAI-compatible body's.
private let perAppAccGoldenTable = """
default/improve-zh	4a7f8a9294231027204254059c677a19c4feaebb8b4b80e3cc38c39016875256	1c55cb9ec04ff829f0db672180b530e729033eb6e892e63acb05734b614648e2	5245	a7b58a76e56ffc2fc6e32403dde5caa8bfcabb4ff558e38aa19c2bcae9f39566	5228
default/translate-zh	6eaa54455499cd6c6ed92e4f0b092fbd1b5db78d0f9144853f95cc4910143d2b	6222829b67470f63e10e9b8df22a023ec3cbecadfa73fe862604bda307c27666	2997	e3e4aa41cf8ea156553d5e5fb82b86d018698df6c6a3c740853a9c124558e1cf	2980
default/both-zh	e5be65b7accfe586059706d4685e52edfc40ae47f77149e67049354e0de5ea70	2f56c206f2a621f3e82dfb4360e7f78186317548e766c8feeba5b46e4a5d0a87	5545	106a882308b78e047f28b8d6a3d1ec1ec7a099bbb74bbd11a6913df20634d749	5528
default/improve-en	27a866e271190a8ab2ab3f625621cf36d43dee4d5bf2602b7e7aafc6d253f9ef	9a56827d5b07b414d66e55e4daa7f21dc722b3b394cd8a9e99f6de9672f2fdeb	5155	d23c35b8fe14ed3ccb19b46b2dac777a5227b727fc958770863da9e29b0bb625	5138
default/both-en	103caaa5ab9b161e44e0abcc834348d3ef5b46172b4c76383a25a37ec61fa86b	af6c8a55144c446bc024454173d87284874844184e75727bf4be9210b006aaa8	5521	a2cf601cb2734559c1dc69c4a89dcf09c2875b3c3f8d2a8653ef1f809a715aa9	5504
default/question	e46a2291f90514a12ef3ed3bff855d087699ff1a5e0c01404060cd7d0ec1c964	7cdb00df3537d973ae407042bfc462971443a1f416c0e12558369de8c6066771	776	ad898181694e8bf37e45f79045ca9994babc41e4e1c919204d616f3d316dc7c4	759
default/custom-prompt	e08d268a9accce54da9104debbacc38ba5a0099a4b9868eb8092ad84ea4c90d8	d6da644e4f5a4721bb81ed6981f320afb328aedec9fbe7f87b156588597686de	638	df9d6dc69cfba4753ac06f796070d3d5b3723adddd0ba1ec22f7e715ea080929	621
default/edit-selection	97113a83b92c8dd61557a3ffd69be963968d46f0c91805a3c8cef65c4b23e2eb	2dfbe988ef6cbc3d2c8db77a89fb26e12329bae9264cf0d977c5b81dad49e0b0	1121	7754cb51a741eef2c2bf869924377e51edcc29258a6c374c493449c5820cf778	1104
default/question-about-selection	bca5ab6cf6b47cdc18249fae4bee5f465d804631497d017d828c29b7aa78296a	02c158219fbdbd84c5e0ed62e5df704ff2d7e77f73cc5246d641b2de187c0bfb	820	e16cf0079e5dc7538a447d38c770d0a15826aaba938dcf1109493452c9c7f6b6	803
styles/improve-zh	7b2711dd3feaf0ad124742872acc8b35610557d8da812fd85e1413485a7a54b8	ac23d78d7b921c131fa4f5be8032567f8efe188b26afcd354ff8f644a929e6d3	5979	87ef181a71a4bd86d0f94b0ac2c28b095e10055877b2bd8284792aa73fb59c6c	5962
styles/translate-zh	6eaa54455499cd6c6ed92e4f0b092fbd1b5db78d0f9144853f95cc4910143d2b	6222829b67470f63e10e9b8df22a023ec3cbecadfa73fe862604bda307c27666	2997	e3e4aa41cf8ea156553d5e5fb82b86d018698df6c6a3c740853a9c124558e1cf	2980
styles/both-zh	fcc5891d8d1e1495b79e56cadac956463ea8c2333c084ca3375deb015d7d7d24	384cefb03d0a6b5c8b63bcdfbe566fbfab4dd08f1a162159a09c4aa996bf5cce	6279	f89677ec564339f8b08f90d0c6a1d32240c689cfd4150dbc8063a09e2594c3ab	6262
styles/improve-en	77fa9a350abccb221979179efac5795097759effdbbc9316593da845cc6ef496	913cfb0d433c7128821bf933be760ca36201d255f5e95baa4d6a57109f203323	5889	43905981e256d000848826bb6d65e3e042221487af6805746fdfeab9c61cc4c2	5872
styles/both-en	1047a46125cfcac78a68b6bfcc5b04e0cd45045e80c0f5a2e1695cc6e278c3d3	929853e2f9a52a5eb1027acc72b8ee4a43fcfc7fa2114c891fb8a4000ed0bdb8	6255	71e6a90cf3dfd9c9c86e4bd105ca12252ec9ef5e8f428acd4fb260a7bd490cc2	6238
styles/question	e46a2291f90514a12ef3ed3bff855d087699ff1a5e0c01404060cd7d0ec1c964	7cdb00df3537d973ae407042bfc462971443a1f416c0e12558369de8c6066771	776	ad898181694e8bf37e45f79045ca9994babc41e4e1c919204d616f3d316dc7c4	759
styles/custom-prompt	e08d268a9accce54da9104debbacc38ba5a0099a4b9868eb8092ad84ea4c90d8	d6da644e4f5a4721bb81ed6981f320afb328aedec9fbe7f87b156588597686de	638	df9d6dc69cfba4753ac06f796070d3d5b3723adddd0ba1ec22f7e715ea080929	621
styles/edit-selection	97113a83b92c8dd61557a3ffd69be963968d46f0c91805a3c8cef65c4b23e2eb	2dfbe988ef6cbc3d2c8db77a89fb26e12329bae9264cf0d977c5b81dad49e0b0	1121	7754cb51a741eef2c2bf869924377e51edcc29258a6c374c493449c5820cf778	1104
styles/question-about-selection	bca5ab6cf6b47cdc18249fae4bee5f465d804631497d017d828c29b7aa78296a	02c158219fbdbd84c5e0ed62e5df704ff2d7e77f73cc5246d641b2de187c0bfb	820	e16cf0079e5dc7538a447d38c770d0a15826aaba938dcf1109493452c9c7f6b6	803
noStyles/improve-zh	8d94a92481968dd33db94fe2796e6ab8af47e69b735053437386cadc50e8fe50	7b16ddd3088cba06b1ad37dfd30a5a3c4abd09dee7259b7b8bae9da380081284	2697	ae345947b1cc032e0a41e7e62ae9f67f114353510be3f106de1d839f76266b24	2680
noStyles/translate-zh	6eaa54455499cd6c6ed92e4f0b092fbd1b5db78d0f9144853f95cc4910143d2b	6222829b67470f63e10e9b8df22a023ec3cbecadfa73fe862604bda307c27666	2997	e3e4aa41cf8ea156553d5e5fb82b86d018698df6c6a3c740853a9c124558e1cf	2980
noStyles/both-zh	6eaa54455499cd6c6ed92e4f0b092fbd1b5db78d0f9144853f95cc4910143d2b	6222829b67470f63e10e9b8df22a023ec3cbecadfa73fe862604bda307c27666	2997	e3e4aa41cf8ea156553d5e5fb82b86d018698df6c6a3c740853a9c124558e1cf	2980
noStyles/improve-en	5ab229d9e0a0165899678ddf8a5b712d486e1b3400ef76c73bd95dc992649d8c	f433585e976280f4ae30895dfcaea26f8b647c3885ae3149089b7f93c35333d4	2651	43eea9df18f7ff150ed17da492d32de7a9d63d08eb1f035a0310857ee07e0a09	2634
noStyles/both-en	ad35b0f597892a4e66d1a836748047880822c509b011f407342593a3d7b0585e	a0e179722fa9e4e85d98b38b04b5633118749d1003ac8628e0108346aeefe4d9	3017	b4d82a43732cbe7888757a7d9e3ecc17be0776f48072a6e5eaf8e6cae8dab54a	3000
noStyles/question	e46a2291f90514a12ef3ed3bff855d087699ff1a5e0c01404060cd7d0ec1c964	7cdb00df3537d973ae407042bfc462971443a1f416c0e12558369de8c6066771	776	ad898181694e8bf37e45f79045ca9994babc41e4e1c919204d616f3d316dc7c4	759
noStyles/custom-prompt	e08d268a9accce54da9104debbacc38ba5a0099a4b9868eb8092ad84ea4c90d8	d6da644e4f5a4721bb81ed6981f320afb328aedec9fbe7f87b156588597686de	638	df9d6dc69cfba4753ac06f796070d3d5b3723adddd0ba1ec22f7e715ea080929	621
noStyles/edit-selection	97113a83b92c8dd61557a3ffd69be963968d46f0c91805a3c8cef65c4b23e2eb	2dfbe988ef6cbc3d2c8db77a89fb26e12329bae9264cf0d977c5b81dad49e0b0	1121	7754cb51a741eef2c2bf869924377e51edcc29258a6c374c493449c5820cf778	1104
noStyles/question-about-selection	bca5ab6cf6b47cdc18249fae4bee5f465d804631497d017d828c29b7aa78296a	02c158219fbdbd84c5e0ed62e5df704ff2d7e77f73cc5246d641b2de187c0bfb	820	e16cf0079e5dc7538a447d38c770d0a15826aaba938dcf1109493452c9c7f6b6	803
threeOutputs/improve-zh	ed392ac15271ebbe8c03853b844845f0e5a8b2944281627a675b9ad5aea83c02	066d4dc81b67f9a5648f52b1624b95518d428b5972554b88bbdadd8081c6dbd3	3926	6f959fb6f8d3702460d2e0502e7ebbe3da3e2f857b947d5c1f5f1c07a08263ca	3909
threeOutputs/translate-zh	c5be542aa250e3dc9738c3deb7b2e928e149ff2dec42c4eb9d3ae3b6539b96a7	328b1d6d200ce18bdd93a0395968f5ca3e155a2b8355206856dfc1262fd0e7a3	1130	4a463cf8ed655bc472c88e17c1380b1c63c4e0747286693f7ed9d2c4a4e86d37	1113
threeOutputs/both-zh	a255a08a1609fce75d0b81625ded672a17c74fd734ca1aea11cb529ed8e99090	ba6a74ee75c1f0b5a7094884768b65dc8ad1858a19fe2955d2e833e9ad89d16e	2065	3e0999ece30955e9728c80fbe1485728772ed4bc96c720ff70f3c4f322b64eb4	2048
threeOutputs/improve-en	b98b181fc339755dc733514c35e81264c07aae27fa2256254ce9dc11cd515e00	e0c4c4ec46f8db4263afbc5d19b583f8704d53be1d6d026844844ceea13dd46b	3858	1c81faf9884e70b9e54eb6fb0d7707bcdc0c04d2aa1090a68db6f0eb37f1f358	3841
threeOutputs/both-en	d3f0226bd2945423459aea1694b73ed79ff896965c8b05bc46300c3ad646527f	d3dfff506dfae4175b245b1b22225cdeffe596a0043ce4c8e64d27c4e151c766	2041	6a3e42f07077b15d1440231fbf843f5e9ca8c4e46cfbfe5b5b907360f566cd22	2024
threeOutputs/question	e46a2291f90514a12ef3ed3bff855d087699ff1a5e0c01404060cd7d0ec1c964	7cdb00df3537d973ae407042bfc462971443a1f416c0e12558369de8c6066771	776	ad898181694e8bf37e45f79045ca9994babc41e4e1c919204d616f3d316dc7c4	759
threeOutputs/custom-prompt	e08d268a9accce54da9104debbacc38ba5a0099a4b9868eb8092ad84ea4c90d8	d6da644e4f5a4721bb81ed6981f320afb328aedec9fbe7f87b156588597686de	638	df9d6dc69cfba4753ac06f796070d3d5b3723adddd0ba1ec22f7e715ea080929	621
threeOutputs/edit-selection	97113a83b92c8dd61557a3ffd69be963968d46f0c91805a3c8cef65c4b23e2eb	2dfbe988ef6cbc3d2c8db77a89fb26e12329bae9264cf0d977c5b81dad49e0b0	1121	7754cb51a741eef2c2bf869924377e51edcc29258a6c374c493449c5820cf778	1104
threeOutputs/question-about-selection	bca5ab6cf6b47cdc18249fae4bee5f465d804631497d017d828c29b7aa78296a	02c158219fbdbd84c5e0ed62e5df704ff2d7e77f73cc5246d641b2de187c0bfb	820	e16cf0079e5dc7538a447d38c770d0a15826aaba938dcf1109493452c9c7f6b6	803
"""

private struct PerAppAccGoldenRow {
    var structure: String
    var anthropic: (sha: String, length: Int)
    var openai: (sha: String, length: Int)
}

private let perAppAccGoldens: [String: PerAppAccGoldenRow] = {
    var rows: [String: PerAppAccGoldenRow] = [:]
    for line in perAppAccGoldenTable.split(separator: "\n") {
        let f = line.split(separator: "\t").map(String.init)
        guard f.count == 6 else { continue }
        rows[f[0]] = PerAppAccGoldenRow(structure: f[1], anthropic: (f[2], Int(f[3])!), openai: (f[4], Int(f[5])!))
    }
    return rows
}()

// MARK: - The tests

struct PerAppAcceptanceTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    static let mail = "com.apple.mail"
    static let slack = "com.tinyspeck.slackmacgap"
    static let bank = "com.example.bank"
    static let refusalNotice = "AI is off in this app"

    // MARK: Helpers

    func decode(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    func encodeObject(_ config: Config) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(config)) as? [String: Any])
    }

    /// Base settings: Chinese and English typed, Chinese first, typing out off, the default styles.
    func base(_ profiles: [String: AppProfile] = [:]) -> Config {
        var config = Config.default
        config.inputLanguages = [.chinese, .english]
        config.defaultInput = .chinese
        config.typeOut = false
        config.rewriteStyles = RewriteStyle.defaultNames
        config.outputLanguages = [.english, .chinese]
        config.improveTranslates = false
        config.appProfiles = profiles
        return config
    }

    /// A text field of `app` becoming active, as the controller sets it up for the app (`applySettings(app:)`).
    func field(_ app: String?, _ config: Config, usable: [Language] = [.chinese, .english],
               commands: [Command] = Command.builtins) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.commands = commands
        c.inputLanguages = usable
        c.setInputMode(config.startingInput(in: app, among: usable))
        c.typesResults = config.applying(app: app).typeOut
        c.aiRefusal = { config.allowsAI(in: app) ? nil : Self.refusalNotice }
        return (c, engine)
    }

    func typeKeys(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    func shiftTap(_ c: Composer, at t: Double) -> [Composer.Effect] {
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: t)
        return c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: t + 0.1)
    }

    /// Whether `effects` start anything that sends text to a model, or a Claude Code session.
    func sendsToAI(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { effect in
            switch effect {
            case .startConversion, .startCommand, .startPlan, .runInTerminal, .startBackgroundAgent: return true
            default: return false
            }
        }
    }

    func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(s) = $0 { return s } else { return nil } }
    }

    static let reply = PerAppAccGolden.reply
    static let catalog = Command.catalog([CustomCommand(name: "reply", type: .prompt, prompt: "Write a polite reply.")])

    /// Sends `run` through a real converter for `app` with `config` (pointed at a fresh recording host).
    /// The bodies sent and the error, if any.
    func send(_ run: PerAppAccGolden.Run, config: Config, app: String?, provider: Provider = .anthropic,
              converter existing: (Converter, String)? = nil) async -> (bodies: [Data], error: Error?) {
        let host = existing?.1 ?? "h\(UUID().uuidString.lowercased().prefix(12)).perapp-acc.test"
        let converter = existing?.0 ?? makeConverter(config, host: host, provider: provider)
        let stream: AsyncThrowingStream<ConversionUpdate, Error>
        switch run {
        case let .convert(text, mode): stream = converter.convert(text, mode: mode, app: app)
        case let .generate(command, input): stream = converter.generate(command, input: input, app: app)
        }
        var failure: Error?
        do { for try await _ in stream {} } catch { failure = error }
        return (PerAppAccRecorder.bodies(host), failure)
    }

    func makeConverter(_ config: Config, host: String, provider: Provider = .anthropic) -> Converter {
        let pointed = PerAppAccGolden.pointed(config, at: host, provider: provider)
        return Converter(client: BedrockClient(session: PerAppAccRecorder.session()), loadConfig: { pointed },
                         loadCredentials: { _ in throw ProviderError.missingKey(.anthropic) },
                         loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
    }

    func newHost() -> String { "h\(UUID().uuidString.lowercased().prefix(12)).perapp-acc.test" }

    // MARK: 1. Per-app overrides, each optional, falling back to the global setting

    @Test func eachOverrideIsIndependentAndUnsetOnesFallBack() throws {
        var global = base()
        global.typeOut = true
        global.defaultInput = .english
        global.rewriteStyles = ["简洁"]
        global.appProfiles = [
            "a.lang": AppProfile(inputLanguage: .chinese),
            "a.styles": AppProfile(rewriteStyles: ["口语"]),
            "a.typeout": AppProfile(typeOut: false),
            "a.noai": AppProfile(noAI: true),
            "a.empty": AppProfile(),
        ]
        let usable: [Language] = [.chinese, .english]
        // Only its language.
        #expect(global.startingInput(in: "a.lang", among: usable) == .chinese)
        #expect(global.applying(app: "a.lang").rewriteStyles == ["简洁"] && global.applying(app: "a.lang").typeOut)
        #expect(global.allowsAI(in: "a.lang"))
        // Only its styles.
        #expect(global.startingInput(in: "a.styles", among: usable) == .english)
        #expect(global.applying(app: "a.styles").rewriteStyles == ["口语"] && global.applying(app: "a.styles").typeOut)
        #expect(global.allowsAI(in: "a.styles"))
        // Only typing out.
        #expect(global.startingInput(in: "a.typeout", among: usable) == .english)
        #expect(global.applying(app: "a.typeout").rewriteStyles == ["简洁"] && !global.applying(app: "a.typeout").typeOut)
        #expect(global.allowsAI(in: "a.typeout"))
        // Only no AI.
        #expect(global.startingInput(in: "a.noai", among: usable) == .english)
        #expect(global.applying(app: "a.noai").rewriteStyles == ["简洁"] && global.applying(app: "a.noai").typeOut)
        #expect(!global.allowsAI(in: "a.noai"))
        // A profile that sets nothing, and no profile at all: exactly the global settings.
        for app in ["a.empty", "com.unknown.app", nil] as [String?] {
            #expect(global.startingInput(in: app, among: usable) == .english)
            var expected = global
            expected.appProfiles = global.appProfiles
            #expect(global.applying(app: app) == expected, "\(app ?? "nil")")
            #expect(global.allowsAI(in: app))
        }
    }

    @Test func anAppWithoutAProfileBehavesExactlyLikeTheGlobalSettings() {
        let config = base(["com.other.app": AppProfile(inputLanguage: .english, rewriteStyles: [], typeOut: true, noAI: true)])
        #expect(config.applying(app: Self.mail) == config)
        #expect(config.startingInput(in: Self.mail, among: [.chinese, .english]) == .chinese)
        #expect(config.allowsAI(in: Self.mail))
        // A field of it: Chinese, results inserted (not typed out), @improve sent.
        let (c, _) = field(Self.mail, config)
        #expect(c.inputLanguage == .chinese && !c.typesResults)
        c.setInputMode(.english)
        typeKeys("@improve hello", c)
        #expect(sendsToAI(c.handleKeyDown(enterKey).effects))
    }

    // MARK: 2. Starting language

    @Test func aFieldStartsInTheAppsLanguage() {
        let config = base([Self.slack: AppProfile(inputLanguage: .english)])
        let (slack, _) = field(Self.slack, config)
        #expect(slack.inputLanguage == .english)
        let (mail, _) = field(Self.mail, config)
        #expect(mail.inputLanguage == .chinese)  // the global default
        // Also with more input languages, and the other way round.
        var four = base([Self.mail: AppProfile(inputLanguage: .french)])
        four.inputLanguages = [.english, .chinese, .french, .korean]
        four.defaultInput = .english
        #expect(four.startingInput(in: Self.mail, among: [.english, .chinese, .french, .korean]) == .french)
        #expect(four.startingInput(in: Self.slack, among: [.english, .chinese, .french, .korean]) == .english)
    }

    @Test func aShiftSwitchInTheSameFieldSticks() {
        let config = base([Self.slack: AppProfile(inputLanguage: .english)])
        let (c, engine) = field(Self.slack, config)
        #expect(c.inputLanguage == .english)
        let effects = shiftTap(c, at: 1)
        #expect(effects.contains(.inputLanguageChanged(.chinese)) && c.inputLanguage == .chinese)
        // Typing and committing in the field doesn't take it back to the app's language.
        typeKeys("nihao", c)
        #expect(commits(c.handleKeyDown(spaceKey)) == ["你好"])
        #expect(c.inputLanguage == .chinese && !engine.ascii)
        typeKeys("wo", c)
        _ = c.handleKeyDown(spaceKey)
        #expect(c.inputLanguage == .chinese)
    }

    @Test func aLanguageThatIsNotAmongTheInputLanguagesFallsBack() {
        // Korean for the app, but only Chinese and English are typed: the global default, not Korean.
        let config = base([Self.mail: AppProfile(inputLanguage: .korean)])
        #expect(config.startingInput(in: Self.mail, among: [.chinese, .english]) == .chinese)
        let (c, _) = field(Self.mail, config)
        #expect(c.inputLanguage == .chinese)
        // Not usable now (its pack isn't there): the default.
        var withKorean = config
        withKorean.inputLanguages = [.chinese, .english, .korean]
        #expect(withKorean.startingInput(in: Self.mail, among: [.chinese, .english]) == .chinese)
        // Neither the app's nor the default usable: the first that is, never one that can't be typed.
        var englishDefault = base([Self.mail: AppProfile(inputLanguage: .hindi)])
        englishDefault.defaultInput = .french
        #expect(englishDefault.startingInput(in: Self.mail, among: [.english, .chinese]) == .english)
        #expect(englishDefault.startingInput(in: Self.slack, among: [.english, .chinese]) == .english)
        // Usable: then it's used.
        #expect(withKorean.startingInput(in: Self.mail, among: [.chinese, .english, .korean]) == .korean)
    }

    // MARK: 3. Rewrite styles

    @Test func improveInTheAppUsesItsStylesElsewhereTheGlobalOnes() async throws {
        // The app's styles are the "styles" golden config's; its prompt must be that config's, byte for byte.
        let base = PerAppAccGolden.configs.first { $0.0 == "default" }!.1
        let stylesNames = PerAppAccGolden.configs.first { $0.0 == "styles" }!.1.rewriteStyles
        var config = base
        config.appProfiles = [Self.slack: AppProfile(rewriteStyles: stylesNames), Self.bank: AppProfile(rewriteStyles: [])]
        for (runName, run) in PerAppAccGolden.runs {
            for provider in [Provider.anthropic, .openai] {
                func check(_ app: String?, _ golden: String) async throws {
                    let sent = await send(run, config: config, app: app, provider: provider)
                    #expect(sent.error == nil, "\(golden) \(app ?? "nil")")
                    let body = try #require(sent.bodies.first, "\(golden) \(app ?? "nil")")
                    let row = try #require(perAppAccGoldens[golden])
                    let want = provider == .anthropic ? row.anthropic : row.openai
                    #expect(PerAppAccGolden.sha256(body) == want.sha && body.count == want.length,
                            "\(golden) via \(provider.rawValue) for \(app ?? "nil")")
                }
                try await check(Self.slack, "styles/" + runName)
                try await check(Self.bank, "noStyles/" + runName)
                try await check(Self.mail, "default/" + runName)
                try await check(nil, "default/" + runName)
            }
        }
    }

    @Test func theAppsStylesShowInWhatImproveAsksFor() async throws {
        var config = base([Self.slack: AppProfile(rewriteStyles: ["口语"])])
        config.rewriteStyles = ["正式", "简洁"]
        let run = PerAppAccGolden.Run.convert("this sentance have a error", .improve)
        let slack = try #require(await send(run, config: config, app: Self.slack).bodies.first)
        let mail = try #require(await send(run, config: config, app: Self.mail).bodies.first)
        let slackText = String(decoding: slack, as: UTF8.self), mailText = String(decoding: mail, as: UTF8.self)
        #expect(slackText.contains("CASUAL") && !slackText.contains("FORMAL") && !slackText.contains("CONCISE"))
        #expect(mailText.contains("FORMAL") && mailText.contains("CONCISE") && !mailText.contains("CASUAL"))
    }

    // MARK: 4. Typing out

    @Test func theAppsTypeOutSettingDecides() {
        var on = base([Self.slack: AppProfile(typeOut: false), Self.mail: AppProfile(inputLanguage: .english)])
        on.typeOut = true
        #expect(!on.applying(app: Self.slack).typeOut)
        #expect(on.applying(app: Self.mail).typeOut)  // unset: global
        #expect(on.applying(app: nil).typeOut)
        var off = base([Self.slack: AppProfile(typeOut: true)])
        off.typeOut = false
        #expect(off.applying(app: Self.slack).typeOut && !off.applying(app: Self.mail).typeOut)

        // In a field: a result picked is typed out where the app says so, inserted where it says not.
        func pick(_ app: String, _ config: Config) -> [Composer.Effect] {
            let (c, _) = field(app, config)
            c.setInputMode(.english)
            typeKeys("@improve hello", c)
            let start = c.handleKeyDown(enterKey).effects
            #expect(start.contains(.startConversion(input: "hello", id: 1)))
            _ = c.receive(ConversionResult(versions: [CandidateLine("Greetings, friend.")]), isFinal: true, id: 1)
            return c.handleKeyDown(k("1")).effects  // the version, by its label
        }
        let typed = pick(Self.slack, off), inserted = pick(Self.mail, off)
        #expect(typed.contains(.typeOut("Greetings, friend.")) && commits(typed).isEmpty, "\(typed)")
        #expect(inserted.contains(.commit("Greetings, friend.")) && !inserted.contains(.typeOut("Greetings, friend.")))
        let notTyped = pick(Self.slack, on)
        #expect(notTyped.contains(.commit("Greetings, friend.")) && !notTyped.contains(.typeOut("Greetings, friend.")))
    }

    // MARK: 5. No AI

    @Test func aiCommandsAreRefusedWithANoticeNothingStartsAndTheDraftStays() {
        let config = base([Self.bank: AppProfile(noAI: true)])
        let cases: [(String, String)] = [
            ("@improve hello world", "@improve hello world"),
            ("@translate hello world", "@translate hello world"),
            ("@translate @improve hello", "@translate @improve hello"),
            ("@question what is this", "@question what is this"),
            ("@reply thanks a lot", "@reply thanks a lot"),
            ("@claude fix the bug", "@claude fix the bug"),
            ("@improve total @calculate 2*3", "@improve total @calculate 2*3"),
        ]
        for (typed, draft) in cases {
            let (c, _) = field(Self.bank, config, commands: Self.catalog)
            c.setInputMode(.english)
            typeKeys(typed, c)
            #expect(c.draft == draft, "\(typed)")
            let effects = c.handleKeyDown(enterKey).effects
            #expect(!sendsToAI(effects), "\(typed): \(effects)")
            #expect(notices(effects).contains(Self.refusalNotice), "\(typed): \(effects)")
            // The draft stays, as it was, not waiting for anything.
            #expect(c.draft == draft && !c.isLevelTwo && c.phase == .drafting, "\(typed)")
            #expect(commits(effects).isEmpty, "\(typed)")
            // And the same draft in an app with AI starts.
            let (other, _) = field(Self.mail, config, commands: Self.catalog)
            other.setInputMode(.english)
            typeKeys(typed, other)
            #expect(sendsToAI(other.handleKeyDown(enterKey).effects), "\(typed) in another app")
        }
    }

    @Test func claudeInTheBackgroundIsRefusedToo() {
        let config = base([Self.bank: AppProfile(noAI: true)])
        let (c, _) = field(Self.bank, config)
        c.claudeInBackground = true
        c.setInputMode(.english)
        typeKeys("@claude fix the bug", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(!sendsToAI(effects) && notices(effects).contains(Self.refusalNotice) && c.draft == "@claude fix the bug")
    }

    @Test func noAIRefusesCommandsOnASelection() {
        let config = base([Self.bank: AppProfile(noAI: true)])
        for instruction in ["", "more formal"] {
            for command in ["i", "t"] {
                let (c, _) = field(Self.bank, config)
                c.setInputMode(.english)
                c.readSelection = { Composer.Selection(text: "this sentance have a error", range: 11..<37) }
                _ = c.handleKeyDown(at)
                typeKeys(command, c)
                _ = c.handleKeyDown(tab)
                #expect(c.selectionInUse == "this sentance have a error")
                typeKeys(instruction, c)
                let effects = c.handleKeyDown(enterKey).effects
                #expect(!sendsToAI(effects), "\(command) \(instruction): \(effects)")
                #expect(notices(effects).contains(Self.refusalNotice), "\(command) \(instruction)")
                // Nothing replaced: the selection is as it was, the draft too.
                #expect(!effects.contains { effect in
                    switch effect {
                    case .replaceSelection, .commit, .typeOut, .updateMarkedText: return true  // the field is left alone
                    default: return false
                    }
                }, "\(effects)")
                #expect(c.selection?.text == "this sentance have a error" && c.draft.hasPrefix("@"))
            }
        }
        // A question about the selection, and a multi-line selection (an edit).
        let (q, _) = field(Self.bank, config)
        q.setInputMode(.english)
        q.readSelection = { Composer.Selection(text: "line one\nline two") }
        _ = q.handleKeyDown(at)
        typeKeys("q", q)
        _ = q.handleKeyDown(tab)
        typeKeys("summarize", q)
        let effects = q.handleKeyDown(enterKey).effects
        #expect(!sendsToAI(effects) && notices(effects).contains(Self.refusalNotice))
    }

    @Test func nonAICommandsAndPlainTypingStillWork() {
        let config = base([Self.bank: AppProfile(noAI: true)])
        // Plain typing in Chinese.
        let (typing, _) = field(Self.bank, config)
        typeKeys("nihao", typing)
        #expect(commits(typing.handleKeyDown(spaceKey)) == ["你好"])
        // @calculate.
        let (calc, _) = field(Self.bank, config)
        typeKeys("@calculate 23*17", calc)
        let calcEffects = calc.handleKeyDown(enterKey).effects
        #expect(calcEffects.first == .startRun(.calc, input: "23*17", id: 1))
        #expect(!notices(calcEffects).contains(Self.refusalNotice))
        // @open.
        let (open, _) = field(Self.bank, config)
        open.setInputMode(.english)
        typeKeys("@open notes", open)
        #expect(open.handleKeyDown(enterKey).effects.contains(.search(query: "notes", id: 1)))
        // A script extension.
        let script = ScriptCommand(file: URL(fileURLWithPath: "/x/hello.sh"), name: "hello", arguments: [.init(placeholder: "who")])
        let (s, _) = field(Self.bank, config, commands: Command.catalog([], scripts: [script]))
        s.setInputMode(.english)
        typeKeys("@hello world", s)
        #expect(s.draft == "@hello world")
        let scriptEffects = s.handleKeyDown(enterKey).effects
        #expect(scriptEffects.contains { if case .startScript = $0 { return true } else { return false } }, "\(scriptEffects)")
        #expect(!notices(scriptEffects).contains(Self.refusalNotice))
        // @note and @reportissue stay on this Mac.
        let (note, _) = field(Self.bank, config)
        note.setInputMode(.english)
        typeKeys("@note buy milk", note)
        #expect(note.handleKeyDown(enterKey).effects.contains(.saveNote(text: "buy milk")))
        let (report, _) = field(Self.bank, config)
        report.setInputMode(.english)
        typeKeys("@reportissue it broke", report)
        _ = report.handleKeyDown(enterKey)
        #expect(report.pendingIssue != nil)
        // A custom program command (not a prompt) runs.
        let run = CustomCommand(name: "upper", type: .run, argv: ["tr", "a-z", "A-Z"])
        let (r, _) = field(Self.bank, config, commands: Command.catalog([run]))
        r.setInputMode(.english)
        typeKeys("@upper hi", r)
        #expect(r.handleKeyDown(enterKey).effects.contains { if case .startRun = $0 { return true } else { return false } })
    }

    @Test func noAIDoesNotBlockTheCommandList() {
        let config = base([Self.bank: AppProfile(noAI: true)])
        let (c, _) = field(Self.bank, config, commands: Self.catalog)
        c.setInputMode(.english)
        let effects = c.handleKeyDown(at).effects
        #expect(effects.contains(.showPanel))
        #expect(!notices(effects).contains(Self.refusalNotice))
        #expect(c.paletteMatches.contains(.calc) && c.paletteMatches.contains(.open))
        // Picking an AI command only writes it: nothing is refused until it's run.
        typeKeys("i", c)
        let picked = c.handleKeyDown(tab).effects
        #expect(c.draft == "@improve " && !notices(picked).contains(Self.refusalNotice))
    }

    @Test func theConverterSendsNothingForAnAppWithNoAI() async throws {
        let config = base([Self.bank: AppProfile(noAI: true)])
        for (name, run) in PerAppAccGolden.runs {
            for provider in [Provider.anthropic, .openai] {
                let refused = await send(run, config: config, app: Self.bank, provider: provider)
                #expect(refused.bodies.isEmpty, "\(name) sent \(refused.bodies.count) request(s)")
                #expect(refused.error != nil, "\(name) wasn't refused")
                // The same request from an app with AI is sent.
                let allowed = await send(run, config: config, app: Self.mail, provider: provider)
                #expect(allowed.bodies.count == 1 && allowed.error == nil, "\(name)")
            }
        }
    }

    @Test func aCachedAnswerIsNotHandedToAnAppWithNoAI() async throws {
        let config = base([Self.bank: AppProfile(noAI: true)])
        let host = newHost()
        let converter = makeConverter(config, host: host)
        for run in [PerAppAccGolden.Run.convert("hello there", .improve), .generate(.question, "what is swift")] {
            let before = PerAppAccRecorder.bodies(host).count
            let first = await send(run, config: config, app: Self.mail, converter: (converter, host))
            #expect(first.error == nil && first.bodies.count == before + 1)
            let refused = await send(run, config: config, app: Self.bank, converter: (converter, host))
            #expect(refused.error != nil && refused.bodies.count == before + 1)
        }
    }

    // MARK: 6. Config

    @Test func appProfilesDecodeFromConfigJSON() throws {
        let config = try decode("""
        {"rewriteStyles": ["简洁"], "typeOut": true,
         "appProfiles": {
           "com.tinyspeck.slackmacgap": {"inputLanguage": "en", "rewriteStyles": ["口语", "委婉"], "typeOut": false, "noAI": false},
           "com.example.bank": {"noAI": true}
         }}
        """)
        #expect(config.rewriteStyles == ["简洁"] && config.typeOut)
        #expect(config.appProfiles[Self.slack] == AppProfile(inputLanguage: .english, rewriteStyles: ["口语", "委婉"], typeOut: false, noAI: false))
        #expect(config.appProfiles[Self.bank] == AppProfile(noAI: true))
        #expect(config.appProfiles.count == 2)
        // Without the key, and as an empty object: no profiles.
        #expect(try decode("{}").appProfiles.isEmpty)
        #expect(try decode(#"{"appProfiles": {}}"#).appProfiles.isEmpty)
    }

    @Test func garbageIsIgnoredAndNeverLosesTheRestOfTheConfig() throws {
        let rest = #""rewriteStyles": ["简洁"], "typeOut": true, "defaultInput": "en", "outputLanguages": ["en", "zh"], "useSelection": false"#
        for garbage in [#""garbage""#, "42", "null", "[]", "[{\"noAI\": true}]", "true", "{\"a\": 1}", #"{"": {"noAI": true}}"#] {
            let config = try decode("{\(rest), \"appProfiles\": \(garbage)}")
            #expect(config.appProfiles.isEmpty, "\(garbage)")
            #expect(config.rewriteStyles == ["简洁"] && config.typeOut && config.defaultInput == .english && !config.useSelection, "\(garbage)")
        }
        let config = try decode("""
        {\(rest), "appProfiles": {
          "ok.app": {"noAI": true, "colour": "red", "future": {"nested": [1, 2, 3]}},
          "string.app": "noAI",
          "number.app": 7,
          "array.app": [true],
          "null.app": null,
          "types.app": {"noAI": "yes", "typeOut": "on", "rewriteStyles": "正式", "inputLanguage": 7},
          "half.app": {"noAI": "yes", "typeOut": true, "rewriteStyles": ["正式", 3], "inputLanguage": "xx"},
          "lang.app": {"inputLanguage": "ja", "typeOut": false},
          "case.app": {"inputLanguage": "EN"}
        }}
        """)
        #expect(config.rewriteStyles == ["简洁"] && config.typeOut && config.defaultInput == .english && !config.useSelection)
        // Unknown keys ignored, the known one kept.
        #expect(config.appProfiles["ok.app"] == AppProfile(noAI: true))
        // Entries that aren't profiles left out.
        for app in ["string.app", "number.app", "array.app", "null.app"] {
            #expect(config.appProfiles[app] == nil, "\(app)")
            #expect(config.allowsAI(in: app) && config.applying(app: app) == config, "\(app)")
        }
        // Wrong types: those keys unset, the rest of the entry kept.
        let types = config.appProfiles["types.app"]
        #expect(types == nil || types == AppProfile(), "\(String(describing: types))")
        #expect(config.allowsAI(in: "types.app") && config.applying(app: "types.app").typeOut)
        #expect(config.appProfiles["half.app"]?.typeOut == true && config.appProfiles["half.app"]?.noAI == nil)
        #expect(config.appProfiles["half.app"]?.inputLanguage == nil)
        #expect(config.allowsAI(in: "half.app"))
        // An unknown language code: unset, the global default applies; the other key is kept.
        #expect(config.appProfiles["lang.app"] == AppProfile(typeOut: false))
        #expect(config.startingInput(in: "lang.app", among: [.chinese, .english]) == .english)
        #expect(config.appProfiles["case.app"]?.inputLanguage == nil)
    }

    @Test func emptyAndInvalidBundleIDsAreIgnored() throws {
        let config = try decode(#"""
        {"appProfiles": {
          "": {"noAI": true},
          " ": {"noAI": true},
          "com.example app": {"noAI": true},
          "com.example.tab\t": {"noAI": true},
          "com.example.line\n": {"noAI": true},
          "com.example.valid": {"noAI": true}
        }}
        """#)
        #expect(Array(config.appProfiles.keys) == ["com.example.valid"])
        // Asked for no app, or an empty one: the global settings, even with a profile stored under "".
        var programmatic = base(["": AppProfile(inputLanguage: .english, rewriteStyles: [], typeOut: true, noAI: true)])
        programmatic.typeOut = false
        for app in [nil, ""] as [String?] {
            #expect(programmatic.allowsAI(in: app))
            #expect(!programmatic.applying(app: app).typeOut && programmatic.applying(app: app).rewriteStyles == RewriteStyle.defaultNames)
            #expect(programmatic.startingInput(in: app, among: [.chinese, .english]) == .chinese)
        }
        // A bundle id that differs only by case or whitespace is another app.
        let exact = base([Self.mail: AppProfile(noAI: true)])
        #expect(!exact.allowsAI(in: Self.mail))
        #expect(exact.allowsAI(in: " " + Self.mail) && exact.allowsAI(in: "com.apple.mail.compose"))
    }

    @Test func hugeConfigValuesDecodeWithoutCrashing() throws {
        var entries: [String] = []
        for i in 0..<5000 { entries.append("\"com.example.app\(i)\": {\"noAI\": \(i % 2 == 0), \"typeOut\": true}") }
        let longID = "com." + String(repeating: "x", count: 100_000)
        entries.append("\"\(longID)\": {\"noAI\": true}")
        let manyStyles = (0..<10_000).map { "\"s\($0)\"" }.joined(separator: ",")
        entries.append("\"styles.app\": {\"rewriteStyles\": [\(manyStyles), \"口语\"]}")
        let longString = String(repeating: "垃", count: 50_000)
        entries.append("\"long.app\": {\"inputLanguage\": \"\(longString)\", \"rewriteStyles\": [\"\(longString)\"]}")
        entries.append("\"deep.app\": {\"noAI\": true, \"x\": " + String(repeating: "[", count: 200) + String(repeating: "]", count: 200) + "}")
        let config = try decode("{\"rewriteStyles\": [\"简洁\"], \"appProfiles\": {\(entries.joined(separator: ","))}}")
        #expect(config.rewriteStyles == ["简洁"])
        #expect(config.appProfiles.count == 5004)
        #expect(!config.allowsAI(in: "com.example.app0") && config.allowsAI(in: "com.example.app1"))
        #expect(!config.allowsAI(in: longID))
        #expect(config.appProfiles["deep.app"] == AppProfile(noAI: true))
        #expect(config.appProfiles["long.app"]?.inputLanguage == nil)
        // Unknown style names: only the known ones are asked for.
        let plan = WritingPlan.make(.improve, text: "hello", config: config.applying(app: "styles.app"))
        #expect(plan.styles.map(\.name) == ["口语"])
        let longPlan = WritingPlan.make(.improve, text: "hello", config: config.applying(app: "long.app"))
        #expect(longPlan.styles.isEmpty)
        // And it all round-trips.
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(again == config)
    }

    @Test func itRoundTripsWithoutAddingUnsetKeys() throws {
        let config = base([
            Self.bank: AppProfile(noAI: true),
            Self.slack: AppProfile(inputLanguage: .english, rewriteStyles: ["口语"]),
            Self.mail: AppProfile(typeOut: false),
            "com.example.styles": AppProfile(rewriteStyles: []),
            "com.example.allowed": AppProfile(noAI: false),
        ])
        let object = try encodeObject(config)
        let profiles = try #require(object["appProfiles"] as? [String: [String: Any]])
        // "noAI": false sets nothing (the global setting has no "no AI"): dropped on save. No rewrite styles is a setting.
        #expect(Set(profiles.keys) == [Self.bank, Self.slack, Self.mail, "com.example.styles"])
        #expect(Set(profiles[Self.bank]!.keys) == ["noAI"])
        #expect(Set(profiles[Self.slack]!.keys) == ["inputLanguage", "rewriteStyles"])
        #expect(profiles[Self.slack]!["inputLanguage"] as? String == "en")
        #expect(Set(profiles[Self.mail]!.keys) == ["typeOut"])
        #expect(Set(profiles["com.example.styles"]!.keys) == ["rewriteStyles"])
        #expect((profiles["com.example.styles"]!["rewriteStyles"] as? [Any])?.isEmpty == true)
        #expect(profiles["com.example.allowed"] == nil)
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        var expected = config
        expected.appProfiles["com.example.allowed"] = nil
        #expect(again == expected)
        // And once more: stable.
        #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(again)) == expected)
        // From a file's text, through decoding and encoding, the profiles come back as they were written.
        let written = #"{"appProfiles": {"com.example.bank": {"noAI": true}, "com.example.x": {"typeOut": true, "unknown": 1}}}"#
        let loaded = try decode(written)
        let out = try #require(try encodeObject(loaded)["appProfiles"] as? [String: [String: Any]])
        #expect(Set(out["com.example.bank"]!.keys) == ["noAI"] && Set(out["com.example.x"]!.keys) == ["typeOut"])
        // The rest of the config doesn't change for having profiles.
        var plain = config
        plain.appProfiles = [:]
        var withoutKey = try encodeObject(config), plainObject = try encodeObject(plain)
        withoutKey["appProfiles"] = nil
        plainObject["appProfiles"] = nil
        #expect(NSDictionary(dictionary: withoutKey).isEqual(to: plainObject))
    }

    // MARK: 7. @reportissue

    @Test func theIssueReportCountsProfilesButNeverNamesThem() throws {
        let apps = [Self.slack, "com.secretcompany.InternalTool", "org.example.MyDiary", "com.example.bank"]
        var config = base()
        for (i, app) in apps.enumerated() {
            config.appProfiles[app] = AppProfile(inputLanguage: i == 0 ? .english : nil, rewriteStyles: ["口语"], typeOut: true, noAI: i % 2 == 0)
        }
        let diagnostics = IssueReport.Diagnostics(config: config, appVersion: "0.6.3", macOS: "26.1", architecture: "arm64",
                                                  interfaceLanguage: "en", languagePacks: [], plugins: 0, extensions: 0)
        let report = IssueReport(title: "typing is slow", diagnostics: diagnostics)
        let everything = ([report.title, report.body(lines: report.lines), report.url.absoluteString,
                           report.url.absoluteString.removingPercentEncoding ?? ""] + report.lines).joined(separator: "\n")
        for app in apps {
            #expect(!everything.lowercased().contains(app.lowercased()), "\(app) is in the report")
            for part in app.split(separator: ".") where part.count > 3 && !["com", "org", "example"].contains(part.lowercased()) {
                #expect(!everything.lowercased().contains(part.lowercased()), "\(part) of \(app) is in the report")
            }
        }
        // The number may be there.
        #expect(report.lines.contains { $0.contains("4") && $0.lowercased().contains("app") })
        // Through the composer too.
        let (c, _) = field(Self.mail, config)
        c.issueDiagnostics = { diagnostics }
        c.setInputMode(.english)
        typeKeys("@reportissue slow", c)
        _ = c.handleKeyDown(enterKey)
        let issue = try #require(c.pendingIssue)
        for app in apps { #expect(!issue.url.absoluteString.lowercased().contains(app.lowercased())) }
    }

    // MARK: 8. Prompts byte-identical to release-0.6.3 (55d496e) without a profile

    @Test func goldensCoverEveryCase() {
        #expect(perAppAccGoldens.count == PerAppAccGolden.cases.count && PerAppAccGolden.cases.count == 36)
    }

    @Test func thePromptStructureIsByteIdenticalToBefore() throws {
        for c in PerAppAccGolden.cases {
            let row = try #require(perAppAccGoldens[c.name])
            #expect(PerAppAccGolden.sha256(try PerAppAccGolden.structure(c)) == row.structure, "\(c.name)")
            // With profiles in the config (for other apps), the same.
            var profiled = c
            profiled.config.appProfiles = [Self.slack: AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true, noAI: true)]
            #expect(PerAppAccGolden.sha256(try PerAppAccGolden.structure(profiled)) == row.structure, "\(c.name) with profiles")
        }
    }

    @Test func whatIsSentWithoutAProfileIsByteIdenticalToBefore() async throws {
        let others: [String: AppProfile] = [
            Self.slack: AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true, noAI: false),
            Self.bank: AppProfile(noAI: true),
            "com.example.empty": AppProfile(rewriteStyles: []),
        ]
        // (config's profiles, the app typed in)
        let variants: [(String, [String: AppProfile], String?)] = [
            ("no profiles, no app", [:], nil),
            ("no profiles, an app", [:], Self.mail),
            ("other apps' profiles", others, Self.mail),
            ("other apps' profiles, no app", others, nil),
            ("a profile that sets no styles", others.merging([Self.mail: AppProfile(inputLanguage: .english, typeOut: true, noAI: false)]) { $1 }, Self.mail),
            ("an empty profile", [Self.mail: AppProfile()], Self.mail),
            ("an empty bundle id", ["": AppProfile(rewriteStyles: ["口语"], noAI: true)], ""),
        ]
        for c in PerAppAccGolden.cases {
            let row = try #require(perAppAccGoldens[c.name])
            for (label, profiles, app) in variants {
                var config = c.config
                config.appProfiles = profiles
                for provider in [Provider.anthropic, .openai] {
                    let sent = await send(c.run, config: config, app: app, provider: provider)
                    #expect(sent.error == nil, "\(c.name), \(label): \(String(describing: sent.error))")
                    let body = try #require(sent.bodies.first, "\(c.name), \(label)")
                    let want = provider == .anthropic ? row.anthropic : row.openai
                    #expect(sent.bodies.count == 1)
                    #expect(PerAppAccGolden.sha256(body) == want.sha && body.count == want.length,
                            "\(c.name) via \(provider.rawValue), \(label): \(body.count) bytes, golden \(want.length)")
                }
            }
        }
    }

    // MARK: 9. Switching apps

    @Test func switchingAppsAppliesEachAppsOwnSettings() {
        var config = base([
            Self.slack: AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true),
            Self.bank: AppProfile(noAI: true),
        ])
        config.typeOut = false
        // Field after field, alternating: each app's, and the global settings for the one without a profile.
        let sequence = [Self.slack, Self.mail, Self.bank, Self.slack, Self.bank, Self.mail, Self.slack]
        for (i, app) in sequence.enumerated() {
            let (c, _) = field(app, config)
            switch app {
            case Self.slack:
                #expect(c.inputLanguage == .english && c.typesResults, "#\(i)")
                #expect(config.applying(app: app).rewriteStyles == ["口语"] && config.allowsAI(in: app))
            case Self.bank:
                #expect(c.inputLanguage == .chinese && !c.typesResults && !config.allowsAI(in: app), "#\(i)")
                #expect(config.applying(app: app).rewriteStyles == RewriteStyle.defaultNames)
            default:
                #expect(c.inputLanguage == .chinese && !c.typesResults && config.allowsAI(in: app), "#\(i)")
                #expect(config.applying(app: app) == config)
            }
            c.setInputMode(.english)
            typeKeys("@question why", c)
            let effects = c.handleKeyDown(enterKey).effects
            #expect(sendsToAI(effects) == (app != Self.bank), "#\(i) \(app)")
        }
    }

    @Test func twoAppsAlternatingThroughOneConverter() async throws {
        let golden = PerAppAccGolden.configs.first { $0.0 == "default" }!.1
        var config = golden
        config.appProfiles = [
            Self.slack: AppProfile(rewriteStyles: PerAppAccGolden.configs.first { $0.0 == "styles" }!.1.rewriteStyles),
            Self.bank: AppProfile(noAI: true),
        ]
        let host = newHost()
        let converter = makeConverter(config, host: host)
        let run = PerAppAccGolden.Run.convert("今天天气很好，我们出去玩吧", .improve)
        let stylesSha = perAppAccGoldens["styles/improve-zh"]!.anthropic.sha
        let defaultSha = perAppAccGoldens["default/improve-zh"]!.anthropic.sha
        var expected: [String] = []
        for app in [Self.slack, Self.mail, Self.bank, Self.slack, Self.mail, Self.bank, Self.mail] {
            let before = PerAppAccRecorder.bodies(host).count
            let sent = await send(run, config: config, app: app, converter: (converter, host))
            let new = sent.bodies.dropFirst(before)
            if app == Self.bank {
                #expect(sent.error != nil && new.isEmpty, "the bank app sent something")
                continue
            }
            #expect(sent.error == nil)
            // A repeat may come from the cache, but never another app's answer: what is sent is the app's own prompt.
            for body in new { expected.append(app == Self.slack ? stylesSha : defaultSha); _ = body }
        }
        let shas = PerAppAccRecorder.bodies(host).map(PerAppAccGolden.sha256)
        #expect(shas == expected)
        #expect(shas.first == stylesSha && shas.dropFirst().first == defaultSha)
    }

    @Test func aProfileWithOnlyNoAI() async throws {
        let config = try decode(#"{"rewriteStyles": ["正式"], "typeOut": true, "defaultInput": "en", "appProfiles": {"com.example.bank": {"noAI": true}}}"#)
        // Everything else is global there.
        #expect(config.startingInput(in: Self.bank, among: [.chinese, .english]) == .english)
        #expect(config.applying(app: Self.bank).typeOut && config.applying(app: Self.bank).rewriteStyles == ["正式"])
        #expect(!config.allowsAI(in: Self.bank))
        // Refused there, sent elsewhere, both through the composer and the converter.
        let (c, _) = field(Self.bank, config)
        #expect(c.inputLanguage == .english && c.typesResults)
        typeKeys("@improve hello", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(!sendsToAI(effects) && notices(effects).contains(Self.refusalNotice) && c.draft == "@improve hello")
        let run = PerAppAccGolden.Run.convert("hello", .improve)
        #expect(await send(run, config: config, app: Self.bank).bodies.isEmpty)
        #expect(await send(run, config: config, app: Self.mail).bodies.count == 1)
    }

    // MARK: Spec update (14:20): saving only what is set, bundle ids ignoring case, the report's count

    @Test func appProfilesIsWrittenOnlyWhenSomeAppSetsSomething() throws {
        // No profiles, and a file from before per-app settings: no key is added.
        #expect(try encodeObject(base())["appProfiles"] == nil)
        let old = try decode(#"{"typeOut": true, "rewriteStyles": ["简洁"]}"#)
        #expect(try encodeObject(old)["appProfiles"] == nil)
        // Only profiles that set nothing ({} and "noAI": false, which equals unset): no key either.
        let nothing = base(["com.example.empty": AppProfile(), "com.example.allowed": AppProfile(noAI: false)])
        #expect(try encodeObject(nothing)["appProfiles"] == nil)
        let reloaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(nothing))
        #expect(reloaded.appProfiles.isEmpty)
        // From a file: those dropped on save, the others kept, "rewriteStyles": [] among them (no rewrite styles).
        let file = try decode("""
        {"typeOut": false, "appProfiles": {
          "com.example.empty": {},
          "com.example.allowed": {"noAI": false},
          "com.example.unknownonly": {"noAI": false, "colour": "red", "inputLanguage": "xx"},
          "com.example.nostyles": {"rewriteStyles": []},
          "com.example.typer": {"noAI": false, "typeOut": true}
        }}
        """)
        // Before saving, a profile that sets nothing behaves exactly like none.
        for app in ["com.example.empty", "com.example.allowed", "com.example.unknownonly"] {
            #expect(file.allowsAI(in: app) && file.applying(app: app) == file, "\(app)")
            #expect(file.startingInput(in: app, among: [.chinese, .english]) == file.startingInput(in: nil, among: [.chinese, .english]))
        }
        let saved = try #require(try encodeObject(file)["appProfiles"] as? [String: [String: Any]])
        #expect(Set(saved.keys) == ["com.example.nostyles", "com.example.typer"])
        #expect((saved["com.example.nostyles"]?["rewriteStyles"] as? [Any])?.isEmpty == true)
        #expect(saved["com.example.typer"]?["typeOut"] as? Bool == true)
        // After saving and loading: the same behavior in every app, nothing set lost.
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(file))
        for app in ["com.example.empty", "com.example.allowed", "com.example.unknownonly", "com.example.nostyles", "com.example.typer",
                    Self.mail] {
            #expect(again.allowsAI(in: app) == file.allowsAI(in: app), "\(app)")
            #expect(again.applying(app: app).typeOut == file.applying(app: app).typeOut, "\(app)")
            #expect(again.applying(app: app).rewriteStyles == file.applying(app: app).rewriteStyles, "\(app)")
        }
        #expect(again.applying(app: "com.example.nostyles").rewriteStyles == [])
        #expect(again.applying(app: "com.example.typer").typeOut && !again.applying(app: Self.mail).typeOut)
    }

    @Test func noRewriteStylesSurvivesASaveAndAsksForNone() async throws {
        let golden = PerAppAccGolden.configs.first { $0.0 == "default" }!.1
        var config = golden
        config.appProfiles = [Self.slack: AppProfile(rewriteStyles: [])]
        let loaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(loaded.appProfiles[Self.slack] == AppProfile(rewriteStyles: []))
        // What @improve sends there is the golden "no styles" request; elsewhere the default one.
        for (runName, run) in PerAppAccGolden.runs where runName.hasPrefix("improve") || runName.hasPrefix("both") {
            let slack = try #require(await send(run, config: loaded, app: Self.slack).bodies.first)
            let mail = try #require(await send(run, config: loaded, app: Self.mail).bodies.first)
            #expect(PerAppAccGolden.sha256(slack) == perAppAccGoldens["noStyles/" + runName]!.anthropic.sha, "\(runName)")
            #expect(PerAppAccGolden.sha256(mail) == perAppAccGoldens["default/" + runName]!.anthropic.sha, "\(runName)")
        }
    }

    @Test func bundleIDsMatchIgnoringCase() async throws {
        // Written by hand with capitals; the app reports lowercase (and the other way round, and all capitals).
        var config = base([
            "com.apple.Mail": AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true),
            "com.example.Bank": AppProfile(noAI: true),
            "com.tinyspeck.slackmacgap": AppProfile(rewriteStyles: []),
        ])
        config.typeOut = false
        for app in ["com.apple.mail", "COM.APPLE.MAIL", "com.apple.Mail", "Com.Apple.Mail"] {
            #expect(config.profile(for: app) == AppProfile(inputLanguage: .english, rewriteStyles: ["口语"], typeOut: true), "\(app)")
            #expect(config.startingInput(in: app, among: [.chinese, .english]) == .english, "\(app)")
            #expect(config.applying(app: app).typeOut && config.applying(app: app).rewriteStyles == ["口语"], "\(app)")
        }
        for app in ["com.example.bank", "COM.EXAMPLE.BANK", "com.example.Bank"] {
            #expect(!config.allowsAI(in: app), "\(app)")
        }
        #expect(config.applying(app: "COM.TINYSPECK.SLACKMACGAP").rewriteStyles == [])
        // Only case: another id is another app.
        for app in ["com.apple.mail2", "com.apple", "com.apple.mail.compose", " com.apple.mail", "com.example.bank "] {
            #expect(config.profile(for: app) == nil && config.allowsAI(in: app), "\(app)")
        }
        // From a config file too.
        let file = try decode(#"{"appProfiles": {"COM.Example.Bank": {"noAI": true}}}"#)
        #expect(!file.allowsAI(in: "com.example.bank") && file.allowsAI(in: "com.example.bank2"))
        // In a field, and through the converter: refused, nothing sent.
        let (c, _) = field("com.example.bank", config)
        c.setInputMode(.english)
        typeKeys("@improve hello", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(!sendsToAI(effects) && notices(effects).contains(Self.refusalNotice))
        let run = PerAppAccGolden.Run.convert("hello", .improve)
        #expect(await send(run, config: config, app: "COM.EXAMPLE.BANK").bodies.isEmpty)
        // The styles of the hand-written id are the ones sent.
        var styled = PerAppAccGolden.configs.first { $0.0 == "default" }!.1
        styled.appProfiles = ["COM.TINYSPECK.SlackMacGap": AppProfile(rewriteStyles: PerAppAccGolden.configs.first { $0.0 == "styles" }!.1.rewriteStyles)]
        let zh = PerAppAccGolden.Run.convert("今天天气很好，我们出去玩吧", .improve)
        let body = try #require(await send(zh, config: styled, app: Self.slack).bodies.first)
        #expect(PerAppAccGolden.sha256(body) == perAppAccGoldens["styles/improve-zh"]!.anthropic.sha)
    }

    @Test func duplicateIDsDifferingOnlyInCaseResolveDeterministically() throws {
        let variants = ["com.apple.Mail": #"{"noAI": true}"#, "com.apple.mail": #"{"typeOut": true}"#,
                        "COM.APPLE.MAIL": #"{"inputLanguage": "en"}"#]
        // The same file written in each order of its keys: always the same single entry wins.
        let orders = [["com.apple.Mail", "com.apple.mail", "COM.APPLE.MAIL"], ["COM.APPLE.MAIL", "com.apple.mail", "com.apple.Mail"],
                      ["com.apple.mail", "COM.APPLE.MAIL", "com.apple.Mail"]]
        var winners: Set<String> = [], profiles: [AppProfile] = []
        for _ in 0..<5 {
            for order in orders {
                let entries = order.map { "\"\($0)\": \(variants[$0]!)" } + [#""com.other.app": {"noAI": true}"#]
                let config = try decode("{\"appProfiles\": {\(entries.joined(separator: ", "))}}")
                let mailKeys = config.appProfiles.keys.filter { $0.lowercased() == "com.apple.mail" }
                #expect(mailKeys.count == 1, "\(order): \(mailKeys)")
                #expect(config.appProfiles["com.other.app"] == AppProfile(noAI: true))
                winners.formUnion(mailKeys)
                let profile = try #require(config.profile(for: "com.apple.mail"))
                profiles.append(profile)
                // Every spelling gets that one profile, and every setting comes from it (not a mix).
                for app in ["com.apple.mail", "COM.APPLE.MAIL", "com.apple.Mail", "Com.apple.mail"] {
                    #expect(config.profile(for: app) == profile, "\(app)")
                    #expect(config.allowsAI(in: app) == (profile.noAI != true))
                    #expect(config.applying(app: app).typeOut == (profile.typeOut ?? config.typeOut))
                }
                // Saved and loaded: still one.
                let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
                #expect(again.appProfiles.keys.filter { $0.lowercased() == "com.apple.mail" }.count == 1)
                #expect(again.profile(for: "com.apple.mail") == profile)
            }
        }
        #expect(winners.count == 1, "\(winners)")
        #expect(Set(profiles.map { "\($0)" }).count == 1)
        // Set in code with several spellings: asking with a spelling that isn't a key gives the same answer every time,
        // however the dictionary was built.
        var answers: Set<String> = []
        for order in orders {
            var config = base()
            for key in order { config.appProfiles[key] = try JSONDecoder().decode(AppProfile.self, from: Data(variants[key]!.utf8)) }
            for _ in 0..<20 { answers.insert("\(String(describing: config.profile(for: "Com.Apple.Mail")))") }
        }
        #expect(answers.count == 1, "\(answers)")
    }

    @Test func theReportCountsOnlyProfilesThatSetSomething() throws {
        func report(_ config: Config) -> IssueReport {
            IssueReport(title: "x", diagnostics: IssueReport.Diagnostics(config: config, appVersion: "0.6.3", macOS: "26.1",
                                                                          architecture: "arm64", interfaceLanguage: "en",
                                                                          languagePacks: [], plugins: 0, extensions: 0))
        }
        let config = base([
            "com.secret.one": AppProfile(noAI: true),
            "com.secret.two": AppProfile(rewriteStyles: []),  // no rewrite styles: a setting
            "com.secret.three": AppProfile(typeOut: false),
            "com.secret.empty": AppProfile(),
            "com.secret.allowed": AppProfile(noAI: false),
        ])
        let three = report(config)
        #expect(three.diagnostics.appProfiles == 3)
        // The one line that counts apps (other lines, a model id among them, may hold digits of their own).
        let appLines = three.lines.filter { $0.lowercased().contains("app") && !$0.hasPrefix("AllInOneIME:") }
        #expect(appLines.count == 1 && appLines[0].hasSuffix("3") && !appLines[0].contains("5"), "\(three.lines)")
        #expect(!three.url.absoluteString.lowercased().contains("secret"))
        // Only profiles that set nothing: as with none at all.
        let none = report(base(["com.secret.empty": AppProfile(), "com.secret.allowed": AppProfile(noAI: false)]))
        #expect(none.diagnostics.appProfiles == 0 && none.lines == report(base()).lines)
        // From a file with spellings of one id: one app.
        let file = try decode(#"{"appProfiles": {"com.apple.Mail": {"noAI": true}, "com.apple.mail": {"noAI": true}, "x.y": {}}}"#)
        #expect(report(file).diagnostics.appProfiles == 1)
    }

    /// Point 6 ("never losing the rest of the config"): a spelling of the id that sets nothing must not shadow one that
    /// sets something, or the setting would be gone on load and from the file on the next save.
    @Test func aCaseDuplicateThatSetsNothingNeverHidesOneThatDoes() throws {
        let empties = ["{}", #"{"noAI": false}"#, #"{"noAI": false, "colour": "red", "inputLanguage": "xx"}"#, #"{"typeOut": "yes"}"#]
        let spellings = ["COM.APPLE.MAIL", "com.apple.Mail", "Com.Apple.Mail"]  // all sort before "com.apple.mail"
        for empty in empties {
            for spelling in spellings {
                for setFirst in [true, false] {
                    let entries = [(spelling, empty), ("com.apple.mail", #"{"noAI": true}"#)]
                    let ordered = setFirst ? entries.reversed() : entries
                    let text = "{\"appProfiles\": {" + ordered.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", ") + "}}"
                    let config = try decode(text)
                    let label = "\(spelling): \(empty)"
                    #expect(config.appProfiles.keys.filter { $0.lowercased() == "com.apple.mail" } == ["com.apple.mail"], "\(label)")
                    for app in ["com.apple.mail", spelling, "COM.apple.MAIL"] {
                        #expect(!config.allowsAI(in: app), "\(label), asked as \(app)")
                    }
                    // Saved and loaded: still there.
                    let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
                    #expect(!again.allowsAI(in: "com.apple.mail") && again.appProfiles.count == 1, "\(label)")
                }
            }
        }
        // Two that set something and one that doesn't: one of the two, always the same, whatever the order in the file.
        var winners: Set<String> = []
        for order in [[0, 1, 2], [2, 1, 0], [1, 2, 0]] {
            let entries = [("COM.APPLE.MAIL", "{}"), ("com.apple.Mail", #"{"typeOut": true}"#), ("com.apple.mail", #"{"noAI": true}"#)]
            let text = "{\"appProfiles\": {" + order.map { "\"\(entries[$0].0)\": \(entries[$0].1)" }.joined(separator: ", ") + "}}"
            let config = try decode(text)
            let kept = config.appProfiles.filter { $0.key.lowercased() == "com.apple.mail" }
            #expect(kept.count == 1 && kept.values.first?.isEmpty == false, "\(kept)")
            winners.formUnion(kept.keys)
        }
        #expect(winners.count == 1, "\(winners)")
        // A different app's empty profile is not touched by this (it's simply dropped on save).
        let other = try decode(#"{"appProfiles": {"com.example.empty": {}, "com.apple.mail": {"noAI": true}}}"#)
        #expect(other.appProfiles.count == 2 && !other.allowsAI(in: "COM.APPLE.MAIL"))
    }

    /// Settings → Apps through `Config`: a change under another spelling of an app's id updates its one entry (never a
    /// second), removing takes every spelling, and a lookup prefers the entry that sets something, whatever the spelling.
    @Test func addingASecondSpellingUpdatesTheExistingEntry() {
        func spellings(_ c: Config) -> [String] { c.appProfiles.keys.filter { $0.lowercased() == "com.apple.mail" }.sorted() }
        var config = base(["com.apple.Mail": AppProfile(noAI: true)])
        config.changeProfile(for: "com.apple.mail") { $0.typeOut = true }
        #expect(spellings(config) == ["com.apple.Mail"])
        #expect(config.appProfiles["com.apple.Mail"] == AppProfile(typeOut: true, noAI: true))
        config.changeProfile(for: "COM.APPLE.MAIL") { $0.inputLanguage = .english }
        #expect(spellings(config) == ["com.apple.Mail"] && config.profile(for: "com.apple.mail")?.inputLanguage == .english)
        #expect(!config.allowsAI(in: "com.apple.mail") && config.applying(app: "COM.apple.mail").typeOut)
        // A new app is added as given; other apps untouched.
        config.changeProfile(for: "com.example.New") { $0.noAI = true }
        #expect(config.appProfiles["com.example.New"] == AppProfile(noAI: true) && config.appProfiles.count == 2)
        // Two spellings already in memory (an empty one sorting first): a lookup by any spelling, the exact one too,
        // finds the one that sets something; a change leaves one entry, keeping what was set.
        var two = base(["COM.APPLE.MAIL": AppProfile(), "com.apple.mail": AppProfile(noAI: true)])
        for app in ["COM.APPLE.MAIL", "com.apple.mail", "com.apple.Mail"] {
            #expect(two.profile(for: app) == AppProfile(noAI: true) && !two.allowsAI(in: app), "\(app)")
        }
        two.changeProfile(for: "COM.APPLE.MAIL") { $0.typeOut = false }
        #expect(spellings(two).count == 1 && two.profile(for: "com.apple.mail") == AppProfile(typeOut: false, noAI: true))
        // Removing by any spelling takes every spelling, and nothing else.
        var many = base(["com.apple.Mail": AppProfile(noAI: true), "com.apple.mail": AppProfile(typeOut: true),
                         "COM.APPLE.MAIL": AppProfile(), Self.slack: AppProfile(noAI: true)])
        many.removeProfile(for: "Com.Apple.Mail")
        #expect(spellings(many).isEmpty && many.allowsAI(in: "com.apple.mail") && many.appProfiles.keys.sorted() == [Self.slack])
        // A change that leaves it setting nothing removes it when asked to (as the input menu does), every spelling too.
        var off = base(["com.apple.Mail": AppProfile(noAI: true), "com.apple.mail": AppProfile()])
        off.changeProfile(for: "com.apple.mail", dropsEmpty: true) { $0.noAI = false }
        #expect(spellings(off).isEmpty && off.allowsAI(in: "com.apple.mail"))
    }
}
