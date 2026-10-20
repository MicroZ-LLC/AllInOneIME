#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing

/// `allinoneime-cli set-provider`, `set-key` and friends: the settings without a settings window. The keys go to the
/// platform's secret store (in memory here, never the user's Credential Manager), tied to the provider's host.
extension WithKeys {
    @Suite(.serialized)
    struct SettingsCommandsTests {
        final class Output: @unchecked Sendable {
            var printed: [String] = []
            var failed: [String] = []
        }

        func run(_ arguments: [String], config: URL, key: String? = nil) -> (Int32, Output) {
            _ = memoryKeychain
            let output = Output()
            let io = SettingsCommands.IO(readKey: { key }, print: { output.printed.append($0) }, fail: { output.failed.append($0) })
            return (SettingsCommands.run(arguments + ["--config", config.path], io: io), output)
        }

        @Test func setProviderWritesTheConfigAndSetKeyKeepsTheKeyForItsHost() throws {
            let folder = try temporaryFolder("commands")
            defer { try? FileManager.default.removeItem(at: folder) }
            let config = folder.appendingPathComponent("config.json")
            try? APIKeys.remove(.anthropic)
            let (rc, out) = run(["set-provider", "anthropic", "--model", "claude-haiku-5-5", "--base-url", "http://127.0.0.1:9"], config: config)
            #expect(rc == 0, "\(out.failed)")
            let written = try Config.load(from: config)
            #expect(written.provider == .anthropic)
            #expect(written.anthropic.model == "claude-haiku-5-5")
            #expect(written.anthropic.baseURL == "http://127.0.0.1:9")
            // A new user's other settings, as the engine has them: Chinese beside English.
            #expect(written.inputLanguages == [.english, .chinese])
            #expect(out.printed.contains { $0.contains("set-key anthropic") })

            let (keyRC, keyOut) = run(["set-key", "anthropic"], config: config, key: "sk-ant-test-1234\r\n")
            #expect(keyRC == 0, "\(keyOut.failed)")
            #expect(APIKeys.keychainKey(.anthropic) == "sk-ant-test-1234")
            #expect(try APIKeys.load(.anthropic, for: "127.0.0.1") == "sk-ant-test-1234")
            // Not sent to another host.
            #expect(throws: ProviderError.self) { try APIKeys.load(.anthropic, for: "api.anthropic.com") }
            // Never the key itself in what is printed: its ending at most.
            let shown = run(["show-config"], config: config).1.printed.joined(separator: "\n")
            #expect(!shown.contains("sk-ant-test-1234"))
            #expect(shown.contains("key anthropic: saved (…"))
            #expect(shown.contains("provider: anthropic"))
            #expect(run(["remove-key", "anthropic"], config: config).0 == 0)
            #expect(APIKeys.keychainKey(.anthropic) == nil)
        }

        @Test func theKeyIsNeverAnArgument() throws {
            let folder = try temporaryFolder("commands-arg")
            defer { try? FileManager.default.removeItem(at: folder) }
            let config = folder.appendingPathComponent("config.json")
            try? APIKeys.remove(.openai)
            let (rc, out) = run(["set-key", "openai", "sk-from-the-command-line"], config: config, key: "sk-on-stdin")
            #expect(rc == 2)
            #expect(out.failed.first?.contains("standard input") == true)
            #expect(APIKeys.keychainKey(.openai) == nil)
            // Nothing on standard input: nothing saved.
            #expect(run(["set-key", "openai"], config: config, key: "  \n").0 == 1)
            #expect(APIKeys.keychainKey(.openai) == nil)
            #expect(!FileManager.default.fileExists(atPath: config.path))
        }

        @Test func aConfigThatDoesntParseIsLeftAlone() throws {
            let folder = try temporaryFolder("commands-broken")
            defer { try? FileManager.default.removeItem(at: folder) }
            let config = folder.appendingPathComponent("config.json")
            try Data("{ broken".utf8).write(to: config)
            #expect(run(["set-provider", "openai"], config: config).0 == 1)
            #expect(try String(contentsOf: config, encoding: .utf8) == "{ broken")
        }

        @Test func setInputPutsTheDefaultFirst() throws {
            let folder = try temporaryFolder("commands-input")
            defer { try? FileManager.default.removeItem(at: folder) }
            let config = folder.appendingPathComponent("config.json")
            #expect(run(["set-input", "zh,en"], config: config).0 == 0)
            let written = try Config.load(from: config)
            #expect(written.inputLanguages == [.chinese, .english])
            #expect(written.defaultInput == .chinese)
            #expect(run(["set-input", "klingon"], config: config).0 == 2)
        }

        /// The whole way: set up with the commands as the owner would, then "@improve hello" in a field goes to that
        /// provider (the stub) with that key, and 1 commits its first version.
        @Test func whatTheCommandsSetIsWhatTheEngineUses() throws {
            let folder = try temporaryFolder("commands-engine")
            defer { try? FileManager.default.removeItem(at: folder) }
            let stub = try StubProvider(folder: folder, key: "sk-from-set-key")
            let config = folder.appendingPathComponent("config.json")
            #expect(run(["set-provider", "openai", "--model", "stub-model", "--base-url", stub.baseURL + "/v1"], config: config).0 == 0)
            #expect(run(["set-input", "en"], config: config).0 == 0)
            try? APIKeys.remove(.openai)
            #expect(run(["set-key", "openai"], config: config, key: "sk-from-set-key\n").0 == 0)
            let client = EngineClient(settings: EngineSettings(url: config), rime: nil)
            client.type("@improve hello")
            client.enter()
            #expect(client.wait { client.composer.phase == .choosing })
            client.type("1")
            #expect(client.committed == "Hello there.")
            #expect(stub.requests.first?["keyOk"] as? Bool == true)
            #expect(stub.requests.first?["kind"] as? String == "openai")
            try? APIKeys.remove(.openai)
        }
    }
}
#endif
