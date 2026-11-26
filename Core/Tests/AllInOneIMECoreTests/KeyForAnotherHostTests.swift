import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A key saved for one host isn't sent to another (`APIKeys.load(_:for:)`: `keyForAnotherHost`), so nothing says it is
/// set once the base URL names another host: the settings' key row and iCloud sync's check, as Settings' own rows and
/// the fast fallback have it.
@Suite("A key saved for another host is not set anywhere", .serialized)
struct KeyForAnotherHostTests {
    private static let relayed = #"{"provider": "openai", "openai": {"baseURL": "https://relay.example.com/v1"}}"#

    /// `body` with a keychain in memory holding OpenAI's key, saved for api.openai.com.
    private func withOpenAIKey<T>(_ body: () throws -> T) rethrows -> T {
        var platform = Platform.current
        platform.secrets = .inMemory()
        _ = platform.secrets.write(Provider.openai.rawValue, "sk-test-openai-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
        return try Platform.$override.withValue(platform, operation: body)
    }

    private func config(_ text: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(text.utf8))
    }

    @Test func theSourceIsNoneForAnotherHostsBaseURL() throws {
        try withOpenAIKey {
            #expect(APIKeys.source(.openai) == .keychain)
            let (relayed, own) = (try config(Self.relayed), try config(#"{"provider": "openai"}"#))
            #expect(APIKeys.Source.keychain.sent(by: .openai, in: relayed) == .none)
            #expect(APIKeys.Source.keychain.sent(by: .openai, in: own) == .keychain)
        }
    }

    @Test func theSettingsKeyRowIsNotSet() throws {
        try withOpenAIKey {
            let folder = TestScratch.temporary("key-other-host-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appendingPathComponent("config.json")
            try Data(Self.relayed.utf8).write(to: url)
            let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
            let service = SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library)
            let key = try #require(service.document().field("openai.key"))
            #expect(key.isSet == false, "the row says a key saved for api.openai.com is set for relay.example.com")
        }
    }

    @Test func iCloudSyncRefusesTheProviderAsWithoutAKey() throws {
        try withOpenAIKey {
            let environment = ICloudSync.Environment(hasKey: { _ in true })
            let (relayed, own) = (try config(Self.relayed), try config(#"{"provider": "anthropic"}"#))
            #expect(ICloudSync.problem("provider", .string("openai"), environment: environment, in: relayed) == .noKey)
            #expect(ICloudSync.problem("provider", .string("openai"), environment: environment, in: own) == nil)
        }
    }
}
