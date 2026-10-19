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
    public static let golden063: [String: String] = [
        "bedrock/A/writing": "9f8fd9de657ddef1b2e1368fc04c9ebbf485e40b1f46ffd6a224efd3f84bcb32",
        "bedrock/A/commands": "8e4e4b3949a9eaa7dedce9a7d8c315610de034f7cc02d6ca03d2fcfbe02885ab",
        "bedrock/B/writing": "b95312e196a7e737a5b6604e41eceec7f1190bed0f152afa5998d2feda279bf3",
        "bedrock/B/commands": "8e4e4b3949a9eaa7dedce9a7d8c315610de034f7cc02d6ca03d2fcfbe02885ab",
        "bedrock/C/writing": "c83f077cb7ea13286949a52dbe1d9637b1e41bb6ba2fb6d4f488476a22b6aa0f",
        "bedrock/C/commands": "f7130593047aa55bc8d57697bb6762c1ecbc6e7bc45e6a83e400b9351cebce11",
        "anthropic/A/writing": "01ca63f51efff3b3748c3126676ffc9f79a0832dee8a1eeaa5f7ea636400b109",
        "anthropic/A/commands": "1fc3068b8c140a43515c98c5bc149fc6e083e3452b1d55e97fdbf00f69b3761e",
        "anthropic/B/writing": "ebcb520f3e0e77be32fa60d395292fd9d993b3a76e9d5b1b90491b98ea4a613b",
        "anthropic/B/commands": "1fc3068b8c140a43515c98c5bc149fc6e083e3452b1d55e97fdbf00f69b3761e",
        "anthropic/C/writing": "b2e1ce80aee92b859604d09f15f7324f2dcc23f991a57de39a65d51f3b67d031",
        "anthropic/C/commands": "a9e1a4de8af6891a1c432af80a400ce61c20ff8072395ea3cb5539cbb2ee70f8",
        "anthropic-opus/A/writing": "7c0c4da5e66e3338a6981ef9b71cbcdd91e9e74b84de29f288d81a15e534c7ad",
        "anthropic-opus/A/commands": "07cceb4a64804114f97fc8cb5523d6eb200cd35d0c9e149cd0a3e49621eea612",
        "anthropic-opus/B/writing": "c0dea60788502dcf2cc9d9c1b71ad4ffe87b288ae89969215c5fbcdb0becbc92",
        "anthropic-opus/B/commands": "07cceb4a64804114f97fc8cb5523d6eb200cd35d0c9e149cd0a3e49621eea612",
        "anthropic-opus/C/writing": "ef1cf1c69d677af7cfd9ffa5b91a76bb1128f6e782f4ec17c0307323fab29323",
        "anthropic-opus/C/commands": "646dcd5d1a7aa187c08dcb236ab9e1f3b29b51d0e093e1a9514f2cae3be51957",
        "gemini/A/writing": "bd801c7819862b906397c53168ae155c65d266530eeae2d6e8a7cff31312f947",
        "gemini/A/commands": "b32e46c8128374e86c8f3ef47a315d8ad2e36f9e4c34d3491fcda26a5c2ae922",
        "gemini/B/writing": "c071dacc6741bd92b38f73eb59165b92f94c584d5a39f5210271ee53b32feda2",
        "gemini/B/commands": "b32e46c8128374e86c8f3ef47a315d8ad2e36f9e4c34d3491fcda26a5c2ae922",
        "gemini/C/writing": "ae42f10cc3ecee1b65263a0cbff6209aca4c4a380da2d7e0510fec3e56dbb2e0",
        "gemini/C/commands": "1d45101334c5a49d5c9a28158933e89a0da1a3dfd4a1991bd12704b453bc9f72",
        "openai/A/writing": "f153fde115c8d71b93b332dae9648bda37ee67f18f0a075f8e6c73a2492a577e",
        "openai/A/commands": "23688f2d48f6c24d7bcc04794a1422917f5763271697a87a36ccdd70912ce9b0",
        "openai/B/writing": "af4d7358490e871e5645f98914745e945a9e518975397853ba4877ec1167c28d",
        "openai/B/commands": "23688f2d48f6c24d7bcc04794a1422917f5763271697a87a36ccdd70912ce9b0",
        "openai/C/writing": "764fe29f88a37be96c0424f297abf8518df756cfa942505e2a192c336d65c1eb",
        "openai/C/commands": "b653d4e2a3536704262b453ee3728b55538598538addde8c6a44cc76d5ac2a0c",
        "ollama/A/writing": "61f9b5138f4e31f9dde6c75d79692010364a32d0a12f094bceabe443bb026dfa",
        "ollama/A/commands": "718b5ae73c43a7a517a7d6d376f0859b5732eec5a4c8439fe0b05739d8ba7e2f",
        "ollama/B/writing": "415671d79cf07476861460ddf2d8948ec62c6f89ed79ae8d24bc610625af37b9",
        "ollama/B/commands": "718b5ae73c43a7a517a7d6d376f0859b5732eec5a4c8439fe0b05739d8ba7e2f",
        "ollama/C/writing": "8178c22c9817b53334d36543e2458595f24272f69e22a72c9af32f5efcc07c61",
        "ollama/C/commands": "cb6823af8ce904c0e805b580c6eda49c4c44cc5d415085b4a53340ba519f3406",
        "deepseek/A/writing": "7def1982ac5c6bc945685818a6d0128a204be4129167d5c04f4ab59d4189fe92",
        "deepseek/A/commands": "19929644680b309c7d3703ee51303d9755edf7f1b3d373553e058fdeeb3048eb",
        "deepseek/B/writing": "a2ff7210ab5b565072fb53302241662bdd311ab71ba5e175b3504ffed1ad18d1",
        "deepseek/B/commands": "19929644680b309c7d3703ee51303d9755edf7f1b3d373553e058fdeeb3048eb",
        "deepseek/C/writing": "c507b13fd3b376325837ed648435f3b5f03ba7d4cf54150da3b01305546eb54a",
        "deepseek/C/commands": "d4c4243f1a1a296370207317d70d8fbcb3c020f0b11c24deb753e7aebc7d017e",
        "hosted/A/writing": "d1276836dca6892fc4fcf07c13a872ee80cfe6427e9aed91dbdb4a0caaad5fbc",
        "hosted/A/commands": "808767aa7250d664d6571e30f7eeab80f20c5168f40b8e2023c231b187d55a77",
        "hosted/B/writing": "f836b10a4c4caf355709a2722f33e55bab2216115bdf187cb41f7b3de8258cca",
        "hosted/B/commands": "808767aa7250d664d6571e30f7eeab80f20c5168f40b8e2023c231b187d55a77",
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
