import CryptoKit
import Foundation
import Testing
@testable import AllInOneIMECore

/// An update server on "this Mac" (http://127.0.0.1/<test>/, answered by LibraryStubProtocol), signed with a key
/// made for the test.
struct TestUpdateServer {
    let base = "http://127.0.0.1/update-\(UUID().uuidString.prefix(8).lowercased())/"
    let key = Curve25519.Signing.PrivateKey()
    var manifestURL: URL { URL(string: base + "update.json")! }

    func updater(current: String = "0.6.3", system: String = "15.0.0") -> Updater {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        return Updater(manifestURL: manifestURL, publicKey: key.publicKey.rawRepresentation, configuration: configuration,
                       currentVersion: current, systemVersion: system, allowsLocalHTTP: true)
    }

    /// Serves `archive` as the download and returns the manifest's fields for it.
    func publish(_ archive: Data, version: String = "0.7.0", size: Int? = nil, sha256: String? = nil) -> [String: Any] {
        let url = base + "AllInOneIME-\(version)-update.zip"
        LibraryStubProtocol.serve(url, archive)
        return manifest(version: version, url: url, sha256: sha256 ?? PluginLibrary.sha256(archive), size: size ?? archive.count)
    }

    func manifest(version: String = "0.7.0", build: String = "9", minimumSystem: String = "14.0",
                  url: String = "https://github.com/MicroZ-LLC/AllInOneIME/releases/download/v0.7.0/AllInOneIME-0.7.0-update.zip",
                  sha256: String = String(repeating: "a", count: 64), size: Int = 1000) -> [String: Any] {
        ["schema": 1, "version": version, "build": build, "minimumSystemVersion": minimumSystem, "url": url,
         "sha256": sha256, "size": size, "notesURL": "https://github.com/MicroZ-LLC/AllInOneIME/releases/tag/v\(version)",
         "summary": ["en": "One-click updates.", "zh": "一键更新。"]]
    }

    /// Serves `fields` as update.json, signed (by `signer`, else the test key).
    @discardableResult
    func serve(_ fields: [String: Any], signer: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        LibraryStubProtocol.serve(base + "update.json", data)
        LibraryStubProtocol.serve(base + "update.json.sig", Data(try (signer ?? key).signature(for: data).base64EncodedString().utf8))
        return data
    }

    func decoded(_ fields: [String: Any]) throws -> UpdateManifest {
        try JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}

struct UpdateTests {
    // MARK: Manifest and signature

    @Test func theManifestIsReadOnlyWhenSigned() async throws {
        let server = TestUpdateServer()
        try server.serve(server.manifest())
        let found = try await server.updater().check()
        #expect(found.manifest.version == "0.7.0" && found.manifest.build == "9" && found.manifest.minimumSystemVersion == "14.0")
        #expect(found.manifest.size == 1000 && found.manifest.sha256.count == 64)
        #expect(found.availability == .available)
        #expect(found.manifest.summary(chinese: true) == "一键更新。" && found.manifest.summary(chinese: false) == "One-click updates.")
        // What's kept for after a restart checks out again on its own.
        #expect(try Updater.verify(manifest: found.data, signature: found.signature, publicKey: server.key.publicKey.rawRepresentation)
                == found.manifest)
    }

    @Test func aTamperedOrUnsignedManifestIsRefused() async throws {
        let server = TestUpdateServer()
        let key = server.key.publicKey.rawRepresentation
        let data = try server.serve(server.manifest())
        let signature = Data(try server.key.signature(for: data).base64EncodedString().utf8)
        // One byte changed: the version, say.
        let tampered = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "0.7.0", with: "9.7.0").utf8)
        #expect(throws: UpdateError.badSignature) { try Updater.verify(manifest: tampered, signature: signature, publicKey: key) }
        // Signed with another key (not the releases').
        let other = Data(try Curve25519.Signing.PrivateKey().signature(for: data).base64EncodedString().utf8)
        #expect(throws: UpdateError.badSignature) { try Updater.verify(manifest: data, signature: other, publicKey: key) }
        #expect(throws: UpdateError.badSignature) { try Updater.verify(manifest: data, signature: Data("not base64!".utf8), publicKey: key) }
        #expect(throws: UpdateError.missingSignature) { try Updater.verify(manifest: data, signature: Data("\n".utf8), publicKey: key) }
        // No signature on the server at all.
        LibraryStubProtocol.serve(server.base + "update.json.sig", Data(), status: 404)
        await #expect(throws: UpdateError.missingSignature) { try await server.updater().check() }
        LibraryStubProtocol.serve(server.base + "update.json", Data(), status: 404)
        await #expect(throws: UpdateError.http(status: 404, file: "update.json")) { try await server.updater().check() }
    }

    @Test func unknownSchemasAndUnreadableManifestsAreRefused() throws {
        let server = TestUpdateServer()
        let key = server.key.publicKey.rawRepresentation
        func signed(_ fields: [String: Any]) throws -> (Data, Data) {
            let data = try JSONSerialization.data(withJSONObject: fields)
            return (data, Data(try server.key.signature(for: data).base64EncodedString().utf8))
        }
        var fields = server.manifest()
        fields["schema"] = 2
        var (data, signature) = try signed(fields)
        #expect(throws: UpdateError.unsupportedSchema(2)) { try Updater.verify(manifest: data, signature: signature, publicKey: key) }
        fields = server.manifest()
        fields["size"] = "large"
        (data, signature) = try signed(fields)
        #expect(throws: UpdateError.malformedManifest) { try Updater.verify(manifest: data, signature: signature, publicKey: key) }
        (data, signature) = (Data("[1]".utf8), Data(try server.key.signature(for: Data("[1]".utf8)).base64EncodedString().utf8))
        #expect(throws: UpdateError.malformedManifest) { try Updater.verify(manifest: data, signature: signature, publicKey: key) }
        // Without a summary or notes: still an update.
        fields = server.manifest()
        fields["summary"] = nil
        fields["notesURL"] = nil
        (data, signature) = try signed(fields)
        let manifest = try Updater.verify(manifest: data, signature: signature, publicKey: key)
        #expect(manifest.summary(chinese: true) == nil && manifest.notesURL == nil)
    }

    @Test func theBuiltInKeyIsTheReleasesOwn() {
        #expect(Updater.publicKey.count == 32)
        #expect(Updater.publicKey != PluginLibrary.publicKey && Updater.publicKey != LanguagePackLibrary.publicKey)
    }

    // MARK: Versions

    @Test func onlyANewerVersionIsAnUpdate() throws {
        let server = TestUpdateServer()
        let updater = server.updater(current: "0.6.3")
        #expect(updater.availability(of: try server.decoded(server.manifest(version: "0.7.0"))) == .available)
        #expect(updater.availability(of: try server.decoded(server.manifest(version: "0.6.10"))) == .available)
        #expect(updater.availability(of: try server.decoded(server.manifest(version: "0.6.3"))) == .upToDate)
        #expect(updater.availability(of: try server.decoded(server.manifest(version: "0.6.2"))) == .upToDate)
        #expect(updater.availability(of: try server.decoded(server.manifest(version: "0.5.9"))) == .upToDate)
        // For a newer macOS than this one: said so, never installed.
        let later = try server.decoded(server.manifest(version: "0.7.0", minimumSystem: "26.0"))
        #expect(updater.availability(of: later) == .needsNewerSystem)
        #expect(server.updater(system: "26.0.1").availability(of: later) == .available)
        #expect(throws: UpdateError.needsNewerSystem("26.0")) { try updater.archiveURL(later) }
    }

    @Test func aDowngradeOrTheSameVersionIsNeverInstalled() async throws {
        let server = TestUpdateServer()
        for version in ["0.6.3", "0.6.2", "0.1.0"] {
            let manifest = try server.decoded(server.publish(Data("archive".utf8), version: version))
            #expect(throws: UpdateError.notNewer(version)) { try server.updater(current: "0.6.3").archiveURL(manifest) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString).zip")
            await #expect(throws: UpdateError.notNewer(version)) { try await server.updater(current: "0.6.3").download(manifest, to: file) }
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
        // Nothing was asked of the server for the archive.
        #expect(!LibraryStubProtocol.asked(host: "127.0.0.1").contains { $0.hasPrefix(server.base) && $0.hasSuffix(".zip") })
    }

    // MARK: Download

    @Test func theDownloadIsCheckedAgainstItsSizeAndHash() async throws {
        let server = TestUpdateServer()
        let archive = Data((0..<50_000).map { UInt8($0 % 251) })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let updater = server.updater()

        let good = try server.decoded(server.publish(archive))
        let file = folder.appendingPathComponent("good.zip")
        let progress = ProgressLog()
        try await updater.download(good, to: file) { progress.add($0) }
        #expect(try Data(contentsOf: file) == archive)
        #expect(progress.all.last == 1)

        // Another archive's hash: refused, and the download deleted.
        let wrongHash = try server.decoded(server.publish(archive, sha256: String(repeating: "b", count: 64)))
        let bad = folder.appendingPathComponent("bad.zip")
        await #expect(throws: UpdateError.hashMismatch) { try await updater.download(wrongHash, to: bad) }
        #expect(!FileManager.default.fileExists(atPath: bad.path))
        // Larger, or smaller, than the manifest says.
        let tooBig = try server.decoded(server.publish(archive, size: archive.count - 1))
        await #expect(throws: UpdateError.sizeMismatch) { try await updater.download(tooBig, to: bad) }
        let tooSmall = try server.decoded(server.publish(archive, size: archive.count + 1))
        await #expect(throws: UpdateError.sizeMismatch) { try await updater.download(tooSmall, to: bad) }
        #expect(!FileManager.default.fileExists(atPath: bad.path))
        // Gone from the server.
        var missing = server.manifest(url: server.base + "gone.zip", sha256: PluginLibrary.sha256(archive), size: archive.count)
        missing["version"] = "0.7.0"
        await #expect(throws: UpdateError.http(status: 404, file: "gone.zip")) { try await updater.download(try server.decoded(missing), to: bad) }
    }

    @Test func aManifestEntryThatCantBeRightIsRefusedBeforeAnyDownload() throws {
        let server = TestUpdateServer()
        let updater = server.updater()
        let refused: [([String: Any], String)] = [
            (server.manifest(sha256: "abc"), "sha256"),
            (server.manifest(sha256: String(repeating: "z", count: 64)), "sha256"),
            (server.manifest(size: 0), "size"),
            (server.manifest(size: Int(Updater.maxArchiveBytes) + 1), "size"),
            (server.manifest(url: "http://github.com/MicroZ-LLC/AllInOneIME/releases/download/v0.7.0/a.zip"), "http://github.com/MicroZ-LLC/AllInOneIME/releases/download/v0.7.0/a.zip"),
            (server.manifest(url: "https://example.com/AllInOneIME-0.7.0-update.zip"), "https://example.com/AllInOneIME-0.7.0-update.zip"),
            (server.manifest(url: "https://github.com/someone/else/releases/download/v1/a.zip"), "https://github.com/someone/else/releases/download/v1/a.zip"),
        ]
        for (fields, detail) in refused {
            #expect(throws: UpdateError.invalidManifest(detail)) { try updater.archiveURL(try server.decoded(fields)) }
        }
        #expect(try updater.archiveURL(try server.decoded(server.manifest())).host == "github.com")
    }

    // MARK: Where from

    @Test func downloadsComeOnlyFromTheSiteOrGitHubReleases() {
        func allows(_ url: String, local: Bool = false) -> Bool { UpdateURLPolicy.allowsDownload(URL(string: url)!, allowsLocalHTTP: local) }
        #expect(allows("https://github.com/MicroZ-LLC/AllInOneIME/releases/download/v0.7.0/AllInOneIME-0.7.0-update.zip"))
        #expect(allows("https://GitHub.com/MicroZ-LLC/AllInOneIME/releases/download/v0.7.0/AllInOneIME-0.7.0.dmg"))
        #expect(allows("https://allinoneime.com/downloads/AllInOneIME-0.7.0-update.zip"))
        #expect(!allows("http://allinoneime.com/AllInOneIME-0.7.0-update.zip"))
        #expect(!allows("https://allinoneime.com:8443/AllInOneIME-0.7.0-update.zip"))
        #expect(!allows("https://user:secret@allinoneime.com/AllInOneIME-0.7.0-update.zip"))
        #expect(!allows("https://plugins.allinoneime.com/a.zip"))
        #expect(!allows("https://allinoneime.com.evil.example/a.zip"))
        #expect(!allows("https://github.com/MicroZ-LLC/AllInOneIME/archive/refs/heads/main.zip"))
        #expect(!allows("https://github.com/MicroZ-LLC/AllInOneIME-plugins/releases/download/v1/a.zip"))
        #expect(!allows("https://github.com/MicroZ-LLC/AllInOneIME/releases/download/../../../evil/a.zip"))
        #expect(!allows("https://objects.githubusercontent.com/release-asset/a.zip"))  // only as a redirect
        #expect(!allows("file:///tmp/a.zip"))
        // A test server on this Mac, only when allowed.
        #expect(!allows("http://127.0.0.1:8123/a.zip"))
        #expect(allows("http://127.0.0.1:8123/a.zip", local: true) && allows("http://localhost/a.zip", local: true))
        #expect(!allows("http://192.168.1.2/a.zip", local: true))

        func redirect(_ url: String) -> Bool { UpdateURLPolicy.allowsRedirect(to: URL(string: url)!, allowsLocalHTTP: false) }
        #expect(redirect("https://objects.githubusercontent.com/github-production-release-asset/123?sig=x"))
        #expect(redirect("https://release-assets.githubusercontent.com/github-production-release-asset/123?sig=x"))
        #expect(redirect("https://github.com/MicroZ-LLC/AllInOneIME/releases/download/v0.7.0/AllInOneIME-0.7.0-update.zip"))
        #expect(!redirect("http://objects.githubusercontent.com/a"))
        #expect(!redirect("https://raw.githubusercontent.com/MicroZ-LLC/AllInOneIME/main/a.zip"))
        #expect(!redirect("https://evil.example/a.zip"))

        func manifest(_ url: String, local: Bool = false) -> Bool { UpdateURLPolicy.allowsManifest(URL(string: url)!, allowsLocalHTTP: local) }
        #expect(manifest("https://allinoneime.com/update.json"))
        #expect(!manifest("http://allinoneime.com/update.json") && !manifest("https://evil.example/update.json"))
        #expect(manifest("http://127.0.0.1:8123/update.json", local: true))
    }

    @Test func theManifestRedirectsOnlyToItsHostOrTheSite() {
        let origin = URL(string: "https://allinoneime.com/update.json")!
        func redirect(_ url: String) -> Bool {
            UpdateURLPolicy.allowsManifestRedirect(to: URL(string: url)!, from: origin, allowsLocalHTTP: false)
        }
        #expect(redirect("https://allinoneime.com/v2/update.json") && redirect("https://ALLINONEIME.com/update.json"))
        #expect(!redirect("https://evil.example/update.json") && !redirect("http://allinoneime.com/update.json"))
        #expect(!redirect("https://allinoneime.com.evil.example/update.json") && !redirect("https://user@allinoneime.com/x"))
        #expect(!redirect("https://objects.githubusercontent.com/update.json"))
        let mirror = URL(string: "https://updates.example.org/update.json")!
        #expect(UpdateURLPolicy.allowsManifestRedirect(to: URL(string: "https://updates.example.org/b.json")!, from: mirror, allowsLocalHTTP: false))
        #expect(UpdateURLPolicy.allowsManifestRedirect(to: origin, from: mirror, allowsLocalHTTP: false))
    }

    @Test func aManifestLargerThanAllowedIsRefusedAsItComes() async throws {
        let server = TestUpdateServer()
        LibraryStubProtocol.serve(server.base + "update.json", Data(repeating: 0x20, count: Updater.maxManifestBytes + 1))
        await #expect(throws: UpdateError.tooLarge("update.json")) { try await server.updater().check() }
        // Exactly the limit is read (and then refused for its signature, not its size).
        LibraryStubProtocol.serve(server.base + "update.json", Data(repeating: 0x20, count: Updater.maxManifestBytes))
        await #expect(throws: UpdateError.missingSignature) { try await server.updater().check() }
    }

    @Test func aManifestFromElsewhereIsntAskedFor() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        let updater = Updater(manifestURL: URL(string: "https://evil-\(UUID().uuidString.prefix(6)).test/update.json")!,
                              configuration: configuration)
        await #expect(throws: UpdateError.invalidManifest(updater.manifestURL.absoluteString)) { try await updater.check() }
        #expect(LibraryStubProtocol.asked(host: updater.manifestURL.host!).isEmpty)
    }

    // MARK: Once a day

    @Test func checksOnceADayAndRetriesAnHourAfterAFailure() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func due(success: TimeInterval?, attempt: TimeInterval?, enabled: Bool = true) -> Bool {
            UpdateSchedule.isDue(now: now, lastSuccess: success.map { now.addingTimeInterval(-$0) },
                                 lastAttempt: attempt.map { now.addingTimeInterval(-$0) }, enabled: enabled)
        }
        let hour: TimeInterval = 3600
        #expect(due(success: nil, attempt: nil))                    // never checked
        #expect(!due(success: nil, attempt: nil, enabled: false))   // turned off
        #expect(!due(success: 2 * hour, attempt: 2 * hour))        // checked today
        #expect(!due(success: 23.9 * hour, attempt: 23.9 * hour))
        #expect(due(success: 24 * hour, attempt: 24 * hour))        // a day later
        #expect(!due(success: 30 * hour, attempt: 0.5 * hour))      // a failed check half an hour ago: not yet
        #expect(due(success: 30 * hour, attempt: 1 * hour))         // …an hour later, again
        #expect(!due(success: nil, attempt: 10))                    // never got an answer, tried just now
        #expect(due(success: -48 * hour, attempt: -48 * hour))      // the clock went back: as if long ago
    }

    @Test func theHelpersResultReadsBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("update-result-\(UUID().uuidString)/result.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let result = UpdateResult(from: "0.6.3", to: "0.7.0", ok: false, error: "it didn't start", date: Date(timeIntervalSince1970: 1_800_000_000))
        try result.write(to: url)
        #expect(UpdateResult.read(url) == result)
        #expect(UpdateResult.read(url.appendingPathExtension("missing")) == nil)
    }

    @Test func checkingByItselfIsOnUnlessTurnedOff() throws {
        #expect(Config.default.checkForUpdates)
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).checkForUpdates)  // a file from before the switch
        var config = Config.default
        config.checkForUpdates = false
        let saved = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(!saved.checkForUpdates && saved == config)
    }

    @Test func errorsReadInEnglish() {
        #expect(UpdateError.hashMismatch.errorDescription == "The download doesn't match the signed manifest; nothing was changed")
        #expect(UpdateError.notNewer("0.6.2").errorDescription == "Version 0.6.2 isn't newer than this one; nothing was changed")
    }
}
