#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Crypto
import Foundation
import Testing
import AllInOneIMECore

// What the acceptance tests share, the core's (Core/Tests/AllInOneIMECoreTests/Acceptance/) and the macOS shell's
// (Tests/AllInOneIMEMacTests/Acceptance/): the keys and the live-data rule they use, and the golden requests of release
// 0.6.3. One copy, here, for both test targets. Written by the acceptance tests' author, like the tests themselves: the
// implementation's changes don't edit it. (Crypto: swift-crypto, which the core depends on; on Apple platforms it is
// CryptoKit.)

/// ⇧⏎: sends a follow-up (an @question conversation's next question, or a refine) once one is typed (0.6.4).
public let acceptanceShiftReturn = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)

/// 0.6.4 added a rule about live data (the weather, news, prices …) at the end of @question's system prompt, and only
/// there. The 0.6.3 goldens are what release 0.6.3 sent, without it. For an @question request `strip` takes it out
/// (it must be there exactly once) so that everything else is still compared byte for byte; any other request is left
/// as it is, so the rule leaking into another command's prompt makes it differ from its golden.
public enum AcceptanceLiveRule {
    public static let added = " " + Prompt.liveDataRule

    public static func strip(_ text: String, question: Bool, sourceLocation: SourceLocation = #_sourceLocation) -> String {
        guard question else { return text }
        let found = text.components(separatedBy: added).count - 1
        #expect(found == 1, "an @question request should have the live-data rule once, has it \(found) times",
                sourceLocation: sourceLocation)
        return text.replacingOccurrences(of: added, with: "")
    }

    public static func strip(_ data: Data, question: Bool, sourceLocation: SourceLocation = #_sourceLocation) -> Data {
        guard question else { return data }
        return Data(strip(String(decoding: data, as: UTF8.self), question: true, sourceLocation: sourceLocation).utf8)
    }
}

// MARK: - Golden requests (spec 4): the same code runs against release-0.6.3 (55d496e) to make the goldens.

public enum AcceptanceGolden {
    public static let inputs = [
        "我今天有点不舒服",
        "i dont feel so good today",
        "这个PR我review一下明天给你反馈",
        "오늘 몸이 좀 안 좋아요",
        "आज मेरी तबीयत ठीक नहीं है",
        "je me sens pas tres bien aujourdhui",
        String(repeating: "今天开会讨论了下个季度的计划，大家意见不太一致。", count: 60),
        "great job 👍🏽 team 🎉",
    ]

    public static func configs(_ provider: Provider) -> [(String, Config)] {
        var a = Config.default
        a.provider = provider
        a.region = "us-west-2"
        var b = a
        b.setOrder([OutputLanguage.chinese, .english])
        b.setOrder([Language.chinese, .english])
        var c = a
        c.setOrder([OutputLanguage.english, .chinese, OutputLanguage("ja")])
        c.setOrder([Language.chinese, .english, .french, .korean, .hindi])
        c.rewriteStyles = []
        c.maxTokens = 700
        c.temperature = nil
        c.timeoutSeconds = 30
        return [("A", a), ("B", b), ("C", c)]
    }

    /// The provider variants: (name, provider, settings applied to the config).
    public static var variants: [(String, Provider, @Sendable (inout Config) -> Void)] { [
        ("bedrock", .bedrock, { _ in }),
        ("anthropic", .anthropic, { _ in }),
        ("anthropic-opus", .anthropic, { $0.anthropic = ProviderSettings(model: "claude-opus-5-5", effort: "medium") }),
        ("gemini", .gemini, { _ in }),
        ("openai", .openai, { _ in }),
        ("ollama", .openai, { $0.openai = ProviderSettings(model: "llama3.1:8b", baseURL: "http://localhost:11434/v1") }),
        ("deepseek", .openai, { $0.openai = ProviderSettings(model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1", temperature: 0.7) }),
        ("hosted", .hosted, { _ in }),
    ] }

    /// What goes on the wire for `body`, as `ChatClient.stream` makes it for `config.provider`.
    public static func wire(_ body: ConverseRequest, _ config: Config) -> String {
        do {
            let request: URLRequest
            if config.provider == .bedrock {
                request = try BedrockClient.makeRequest(
                    body, modelId: config.modelId, region: config.region ?? "us-east-1",
                    credentials: AWSCredentials(accessKeyId: "AKIDGOLDEN", secretAccessKey: "golden-secret"),
                    timeout: config.timeoutSeconds, date: Date(timeIntervalSince1970: 1_790_000_000))
            } else {
                request = try HTTPProviders.makeRequest(
                    body, provider: config.provider, settings: config.settings(for: config.provider), key: "sk-golden",
                    maxTokens: body.inferenceConfig.maxTokens ?? config.maxTokens, timeout: config.timeoutSeconds)
            }
            var body = request.httpBody ?? Data()
            var headers = request.allHTTPHeaderFields ?? [:]
            if config.provider == .bedrock {
                // JSONEncoder's key order changes from run to run (in both versions): compare the JSON, sorted, and
                // the signature's scope (the signature itself signs those unsorted bytes).
                let object = try JSONSerialization.jsonObject(with: body)
                body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                headers["Authorization"] = headers["Authorization"].map { String($0.prefix { $0 != "," }) + ", <signature>" }
            }
            let lines = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            return ([request.httpMethod ?? "", request.url?.absoluteString ?? "", "timeout \(request.timeoutInterval)"]
                + lines + [String(decoding: body, as: UTF8.self)]).joined(separator: "\n")
        } catch {
            return "error: \(error)"
        }
    }

    public static func commands() -> [(String, Command, String)] {
        let tweet = CustomCommand(name: "tweetit", type: .prompt, prompt: "Rewrite this as a short, upbeat tweet.")
        let custom = Command.catalog([tweet]).first { $0.name == "tweetit" }!
        return [
            ("question", .question, "什么是量子计算？"),
            ("question-selection", .question, Prompt.question("总结一下", about: "The meeting moved to Friday at 3pm.")),
            ("edit-translate", .edit, Prompt.editRequest(instruction: "translate: ja", text: "我今天有点不舒服")),
            ("edit-improve", .edit, Prompt.editRequest(instruction: "improve", text: "i dont feel so good today")),
            ("custom", custom, "we shipped the new release today"),
        ]
    }

    /// Group name → every request of the group, in order.
    public static func groups() -> [(String, String)] {
        var out: [(String, String)] = []
        for (name, provider, apply) in variants {
            for (configName, base) in configs(provider) {
                var config = base
                apply(&config)
                var all: [String] = []
                for input in inputs {
                    for mode in [WritingMode.improve, .translate, .both] {
                        all.append(wire(Prompt.request(for: input, mode: mode, config: config), config))
                    }
                }
                out.append(("\(name)/\(configName)/writing", all.joined(separator: "\n----\n")))
                let commands = commands().map { wire(Prompt.commandRequest($0.1, input: $0.2, config: config), config) }
                out.append(("\(name)/\(configName)/commands", commands.joined(separator: "\n----\n")))
            }
        }
        // The config file: an old one without "provider", and one with a provider this version doesn't know.
        let old = #"{"awsProfile":"work","region":"eu-west-1","maxTokens":900,"rewriteStyles":["润色"]}"#
        let unknown = #"{"provider":"martian","maxTokens":900}"#
        for (name, json) in [("config/old", old), ("config/unknown", unknown)] {
            let text: String
            do {
                let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                text = String(decoding: try encoder.encode(config), as: UTF8.self)
            } catch {
                text = "throws"
            }
            out.append((name, text))
        }
        return out
    }

    public static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AcceptanceGolden {
    /// `AcceptanceGolden.groups()` at release-0.6.3 (55d496e), made by running the same code in a worktree of it.
    // 0.6.7: maxTokens' default went from 1000 to 2000 (the owner's decision); the 32 digests were made again, checked to
    // differ from 0.6.3's only by the request's token count (hashed with it put back, they matched the old ones).
    public static let golden063: [String: String] = [
        "bedrock/A/writing": "715d284666a1af7aa3c2c40f841f4792beb93652c30b460cd2aaa96ae087c978",
        "bedrock/A/commands": "dae868f6fc35a51d1cb0cf7c887db8ddace8ff2b7c6f5918ad66919273f5b6a7",
        "bedrock/B/writing": "750931b6c0dfff2338a1555af029c396b29f652f8a533cb88decd6909d58e5f7",
        "bedrock/B/commands": "dae868f6fc35a51d1cb0cf7c887db8ddace8ff2b7c6f5918ad66919273f5b6a7",
        "bedrock/C/writing": "c83f077cb7ea13286949a52dbe1d9637b1e41bb6ba2fb6d4f488476a22b6aa0f",
        "bedrock/C/commands": "f7130593047aa55bc8d57697bb6762c1ecbc6e7bc45e6a83e400b9351cebce11",
        "anthropic/A/writing": "58e8b4249e2b6674c3a7315541194b2b10de27900c5cca87b313d88533f3e550",
        "anthropic/A/commands": "5e91cd71b38a108daee7016b7fc463e73f74e23837ff35ef9cf64361190e415f",
        "anthropic/B/writing": "c641dc6be2bf42905e5d55a0e25cc1a38a3b96d8445d7e6d91e7309f397e2fda",
        "anthropic/B/commands": "5e91cd71b38a108daee7016b7fc463e73f74e23837ff35ef9cf64361190e415f",
        "anthropic/C/writing": "b2e1ce80aee92b859604d09f15f7324f2dcc23f991a57de39a65d51f3b67d031",
        "anthropic/C/commands": "a9e1a4de8af6891a1c432af80a400ce61c20ff8072395ea3cb5539cbb2ee70f8",
        "anthropic-opus/A/writing": "080d18df3b61d7de08ccd1711fa01809f4ae41b0018f0374ded0e613265dabb5",
        "anthropic-opus/A/commands": "bca0b918b792c1e35c956b949e93b91ec7f629ed875b806b5f745f8838b216a2",
        "anthropic-opus/B/writing": "1d60861c9e0e41f2cd43ed0f6bdcabc23df588cc9a7b907f031c6034b9a42e67",
        "anthropic-opus/B/commands": "bca0b918b792c1e35c956b949e93b91ec7f629ed875b806b5f745f8838b216a2",
        "anthropic-opus/C/writing": "ef1cf1c69d677af7cfd9ffa5b91a76bb1128f6e782f4ec17c0307323fab29323",
        "anthropic-opus/C/commands": "646dcd5d1a7aa187c08dcb236ab9e1f3b29b51d0e093e1a9514f2cae3be51957",
        "gemini/A/writing": "88283edd8963befd0a9e74d1ceb7635b27993faec389a400903bc293fd86968d",
        "gemini/A/commands": "acccb9d3aab228f790f8cb3c932a27df6a2f0f7074bcb2265149a50a6d6f0622",
        "gemini/B/writing": "9d268b508296160bf3f4306be0ead577f790694a6a440a985a8d66b934c69e7c",
        "gemini/B/commands": "acccb9d3aab228f790f8cb3c932a27df6a2f0f7074bcb2265149a50a6d6f0622",
        "gemini/C/writing": "ae42f10cc3ecee1b65263a0cbff6209aca4c4a380da2d7e0510fec3e56dbb2e0",
        "gemini/C/commands": "1d45101334c5a49d5c9a28158933e89a0da1a3dfd4a1991bd12704b453bc9f72",
        "openai/A/writing": "dfbd1607633cf9a739a45999bcc46a10fe42318b5025a8e387e1111b352b1fa3",
        "openai/A/commands": "659c9f5bf1c39a4c323265e1a6b60852e84d006eff4aa517b80b1e5d7191515f",
        "openai/B/writing": "9a1a0f9cf942cac7d0b3bdf4af5fee3a434988a76a66d6e961ef25e4f0ec208c",
        "openai/B/commands": "659c9f5bf1c39a4c323265e1a6b60852e84d006eff4aa517b80b1e5d7191515f",
        "openai/C/writing": "764fe29f88a37be96c0424f297abf8518df756cfa942505e2a192c336d65c1eb",
        "openai/C/commands": "b653d4e2a3536704262b453ee3728b55538598538addde8c6a44cc76d5ac2a0c",
        "ollama/A/writing": "aed5b2fd98ff4d650f7ae766c54cfb21c6635bc9735b7ecbc3ae769f57b965dd",
        "ollama/A/commands": "9e0f7e200d446ba551c3defd0e530eeb9037c1f5dcc3acfb0b0bd032b53a5194",
        "ollama/B/writing": "11880986994dffdc5837fdaaf36fb251b0f8e5419e4d42f5de581cd9d7c61131",
        "ollama/B/commands": "9e0f7e200d446ba551c3defd0e530eeb9037c1f5dcc3acfb0b0bd032b53a5194",
        "ollama/C/writing": "8178c22c9817b53334d36543e2458595f24272f69e22a72c9af32f5efcc07c61",
        "ollama/C/commands": "cb6823af8ce904c0e805b580c6eda49c4c44cc5d415085b4a53340ba519f3406",
        "deepseek/A/writing": "040ea36169addfde2d2ce4b8fafb040248a0d67f91445b366c8e99df50c49f8d",
        "deepseek/A/commands": "51fa120bbe3bf1562fc75b8e4ca629c0adb8ee5b7cd4615eb7ecf4fd51a2c6cf",
        "deepseek/B/writing": "380062a5b1bd630ff8be2bb0d4f4a2d9bc47d4375117457407cf0306ceb1822f",
        "deepseek/B/commands": "51fa120bbe3bf1562fc75b8e4ca629c0adb8ee5b7cd4615eb7ecf4fd51a2c6cf",
        "deepseek/C/writing": "c507b13fd3b376325837ed648435f3b5f03ba7d4cf54150da3b01305546eb54a",
        "deepseek/C/commands": "d4c4243f1a1a296370207317d70d8fbcb3c020f0b11c24deb753e7aebc7d017e",
        "hosted/A/writing": "30efc91b5545e9ae51ede508d0b1b7f303b358bfa658da9d948fa5de6ed7e2e5",
        "hosted/A/commands": "6304ffa58a24ec0cc22851d10287f1248808d86662dc21172d3928b1260c6cc9",
        "hosted/B/writing": "364aee396afbd4b53130bcd04d0d756e6701f2550c0ee778a42aa291c32982bc",
        "hosted/B/commands": "6304ffa58a24ec0cc22851d10287f1248808d86662dc21172d3928b1260c6cc9",
        "hosted/C/writing": "5e063ccc41332eacab162050cc5e9ff0f2ce491c76ab14559eddaad8bdf59ce1",
        "hosted/C/commands": "5c2486b6205a7f0875386c4b0a56ec37eec8e1418a114b20feafb396f131428a",
        "config/old": "2b4fc5fdbb1891ecb393c708ca70319d0c93434f924f2091bd272a0c3e28211a",
        "config/unknown": "754c93cbd85e6d1a2f5a4828bce4dd088feb87552cadf6c28a08580c4b0eec67",
    ]
}

extension AcceptanceGolden {
    /// What later features add on purpose to a group's output, which 55d496e didn't write. `config/old` re-encodes an
    /// old config, so a setting added since is written back with its default:
    /// - the question history (0.6.3/question-history): `rememberQuestions`, on by default;
    /// - hiding sensitive values (the redaction feature): `redaction`, off, with every kind of value picked and no words
    ///   of the user's own;
    /// - `@claude` becoming `@agent` (0.6.5/agent): `agent`, Claude Code, and `agentCommand`, no custom agent's command;
    /// - `@agent` taking the Chrome page along (0.6.5/page-context): `agentPageContext`, on by default (written right
    ///   after the agent keys, so it's one string with them).
    public static let addedSince063: [String: [String]] = [
        "config/old": [
            #","agent":"claude","agentCommand":[],"agentPageContext":true"#,
            #","rememberQuestions":true"#,
            #","redaction":{"cards":true,"customWords":[],"emails":true,"enabled":false,"ips":true,"keys":true,"phones":true}"#,
        ],
    ]
}
