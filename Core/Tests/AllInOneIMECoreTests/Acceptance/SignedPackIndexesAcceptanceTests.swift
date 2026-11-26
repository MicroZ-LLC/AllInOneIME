import AllInOneIMETestSupport
import CryptoKit
import Foundation
import Testing
@testable import AllInOneIMECore

/// Refactor guard (item 4): signed-index entry checks (sha256, size, allowed URL) reject the same
/// invalid entries before any download for both language packs and coding packs.
struct SignedPackIndexesAcceptanceTests {
    @Test func languageAndCodingPackEntryChecksRejectTheSameBadEntries() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let host = "packs-\(UUID().uuidString.lowercased()).test"
        let base = "https://\(host)/"
        let baseURL = try #require(URL(string: base))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]

        let scratch = TestScratch.temporary("signed-pack-indexes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let languageLibrary = LanguagePackLibrary(
            baseURL: baseURL,
            publicKey: key.publicKey.rawRepresentation,
            configuration: configuration,
            store: LanguagePackStore(directory: scratch.appendingPathComponent("lang", isDirectory: true)),
            allowsLocalHTTP: false
        )
        let codingLibrary = CodingPackLibrary(
            baseURL: baseURL,
            publicKey: key.publicKey.rawRepresentation,
            configuration: configuration,
            store: CodingPackStore(directory: scratch.appendingPathComponent("coding", isDirectory: true)),
            allowsLocalHTTP: false
        )

        let validHash = PluginLibrary.sha256(Data("pack".utf8))
        let cases: [(url: String, sha256: String, size: Int64, error: LanguagePackError)] = [
            ("pack.bin", "bad", 16, .invalidEntry("sha256")),
            ("pack.bin", String(repeating: "g", count: 64), 16, .invalidEntry("sha256")),
            ("pack.bin", validHash, 0, .invalidEntry("size")),
            ("pack.bin", validHash, -1, .invalidEntry("size")),
            ("http://example.test/pack.bin", validHash, 16, .invalidEntry("http://example.test/pack.bin")),
            ("http://127.0.0.1/pack.bin", validHash, 16, .invalidEntry("http://127.0.0.1/pack.bin")),
            ("file:///etc/passwd", validHash, 16, .invalidEntry("file:///etc/passwd")),
        ]

        for bad in cases {
            let langJSON = try JSONSerialization.data(withJSONObject: [
                "schema": 1,
                "packs": [[
                    "id": "zh-pinyin", "version": "1.0.0",
                    "url": bad.url, "sha256": bad.sha256, "size": bad.size,
                ]],
            ], options: [.sortedKeys])
            let langSig = Data(try key.signature(for: langJSON).base64EncodedString().utf8)
            let langEntry = try #require(
                LanguagePackLibrary.verify(index: langJSON, signature: langSig, publicKey: key.publicKey.rawRepresentation).packs.first
            )
            await #expect(throws: bad.error) { try await languageLibrary.install(langEntry, pack: .chinesePinyin) }

            let codingJSON = try JSONSerialization.data(withJSONObject: [
                "schema": 1,
                "packs": [[
                    "language": "python", "title": "Python", "version": "1.0.0",
                    "url": bad.url, "sha256": bad.sha256, "size": bad.size,
                ]],
            ], options: [.sortedKeys])
            let codingSig = Data(try key.signature(for: codingJSON).base64EncodedString().utf8)
            let codingEntry = try #require(
                CodingPackLibrary.verify(index: codingJSON, signature: codingSig, publicKey: key.publicKey.rawRepresentation).packs.first
            )
            await #expect(throws: bad.error) { try await codingLibrary.install(codingEntry) }
        }

        #expect(LibraryStubProtocol.asked(host: host).isEmpty)
    }
}
