#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing

/// The API keys of this test process: in memory, never the user's Credential Manager.
let memoryKeychain: Void = { APIKeys.keychain = .inMemory() }()

/// Level two through the engine (M7): `@improve` goes to the provider the settings name, through the core's
/// `Converter`, over HTTP to the stub provider on localhost (Scripts/stub-provider.py), which answers in that API's own
/// streaming format; the versions come into the panel, and a digit commits one. Never a paid API.
@Suite(.serialized)
struct AITests {
    /// The settings for `provider` at the stub's address: English in and out, no rewrite styles.
    static func settings(_ provider: String, base: String, in folder: URL) throws -> EngineSettings {
        try settingsFile("""
            {"provider": "\(provider)", "\(provider)": {"baseURL": "\(base)", "model": "stub-model"},
             "outputLanguages": ["en"], "outputLanguage": "en", "inputLanguages": ["en"], "rewriteStyles": [],
             "timeoutSeconds": 10}
            """, in: folder)
    }

    /// "@improve hello", Return, the versions streamed in, "1": what goes in.
    func improve(through provider: Provider, path: String = "", key: String? = "stub-key") throws
        -> (client: EngineClient, stub: StubProvider, folder: URL) {
        _ = memoryKeychain
        let folder = try temporaryFolder("ai-\(provider.rawValue)")
        let stub = try StubProvider(folder: folder)
        let settings = try Self.settings(provider.rawValue, base: stub.baseURL + path, in: folder)
        if let key { try APIKeys.save(key, for: provider, host: "127.0.0.1") } else { try? APIKeys.remove(provider) }
        let client = EngineClient(settings: settings, rime: nil)
        client.type("@improve hello")
        client.enter()
        return (client, stub, folder)
    }

    @Test(arguments: [(Provider.anthropic, ""), (.openai, "/v1"), (.gemini, "")])
    func improveStreamsFromTheProviderAndOneCommits(provider: Provider, path: String) throws {
        let (client, stub, folder) = try improve(through: provider, path: path)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The three versions stream in: row 0 is "hello" as typed, then the stub's.
        #expect(client.wait { client.composer.phase == .choosing })
        let model = try #require(client.panel.model)
        #expect(model.rows.map(\.text) == ["hello", "Hello there.", "Hi!", "Greetings."])
        #expect(model.rows.map(\.label) == ["0", "1", "2", "3"])
        #expect(model.detail?.hasSuffix("s") == true)  // how long it took
        client.type("1")
        #expect(client.committed == "Hello there.")
        #expect(client.panel.model == nil)
        let requests = stub.requests
        #expect(requests.count == 1)
        #expect(requests.first?["keyOk"] as? Bool == true)
        #expect(requests.first?["kind"] as? String == provider.rawValue)
        if provider != .gemini { #expect(requests.first?["model"] as? String == "stub-model") }
    }

    @Test func aKeyTheProviderRefusesShowsItsError() throws {
        let (client, stub, folder) = try improve(through: .anthropic, key: "not-the-stubs-key")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(client.wait {
            if case .failed = client.composer.phase { return true }
            return false
        })
        guard case let .error(message)? = client.panel.model?.status else {
            Issue.record("no error in the panel: \(String(describing: client.panel.model))")
            return
        }
        #expect(message.contains("authentication_error"))
        #expect(stub.requests.first?["keyOk"] as? Bool == false)
        // Esc gives the draft back; nothing went in.
        client.escape()
        #expect(client.committed == "")
    }

    @Test func noKeyAsksForOne() throws {
        let (client, stub, folder) = try improve(through: .anthropic, key: nil)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(client.wait {
            if case .failed = client.composer.phase { return true }
            return false
        })
        guard case let .error(message)? = client.panel.model?.status else {
            Issue.record("no error in the panel")
            return
        }
        #expect(message == ProviderError.missingKey(.anthropic).errorDescription)
        #expect(stub.requests.isEmpty)  // nothing was sent without a key
    }

    @Test func aNewInstallIsOnAllInOneIMECloudWhichNeedsASignIn() throws {
        _ = memoryKeychain
        let folder = try temporaryFolder("ai-hosted")
        defer { try? FileManager.default.removeItem(at: folder) }
        // No settings file: the Mac's default for a new install. No session token: nothing is sent anywhere.
        try? APIKeys.remove(account: "hosted")
        let client = EngineClient(settings: EngineSettings(url: folder.appendingPathComponent("config.json")), rime: nil)
        #expect(client.host.settings.current.provider == .hosted)
        client.type("@improve hello")
        client.enter()
        #expect(client.wait {
            if case .failed = client.composer.phase { return true }
            return false
        })
        guard case let .error(message)? = client.panel.model?.status else {
            Issue.record("no error in the panel")
            return
        }
        #expect(message == ProviderError.signedOut.errorDescription)
    }

    @Test func escapeDuringTheStreamStopsIt() throws {
        let (client, _, folder) = try improve(through: .anthropic)
        defer { try? FileManager.default.removeItem(at: folder) }
        client.escape()
        #expect(client.composer.phase != .choosing)
        Thread.sleep(forTimeInterval: 0.5)
        client.runQueues()
        client.applyPushes()
        // The stream's later updates went nowhere: still the draft, nothing committed.
        #expect(client.committed == "")
        #expect(client.composer.phase == .drafting)
    }
}
#endif
