import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// What the move to AllInOneIME's own system identity hands to the next version (`IdentityHandover`, `CleanupRecord`):
/// the record as a file (identifiers only, the user's alone), when it is the next version's, and a test install's key
/// store. Files in a folder of the test's own.
struct IdentityHandoverTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("identity-handover-\(UUID().uuidString)", isDirectory: true)

    func sample() -> CleanupRecord {
        var record = CleanupRecord()
        record.bundleIDs = ["com.example.before.inputmethod", "com.example.before.settings"]
        record.inputSource = "com.example.before.inputmethod"
        record.defaultsDomains = ["com.example.before.inputmethod", "com.example.before.settings"]
        record.apps = ["/tmp/aside/0-AllInOneIME.app"]
        record.launchAgents = [CleanupRecord.LaunchAgent(label: "com.example.before.watch", plist: "/tmp/watch.plist"),
                               CleanupRecord.LaunchAgent(label: "com.example.before.loaded", plist: nil)]
        record.keychainGroup = "TEAM.com.example.before.shared"
        record.keychainItems = [CleanupRecord.KeychainItem(service: APIKeys.service, account: "openai", synchronizable: true)]
        record.loginKeys = [LoginKey(service: APIKeys.service, account: "claude")]
        record.caches = ["/tmp/Caches/com.example.before.inputmethod"]
        return record
    }

    @Test func aRecordIsWrittenForTheUserAloneAndReadBack() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Application Support/AllInOneIME").appendingPathComponent(CleanupRecord.fileName)
        #expect(try CleanupRecord.read(at: url) == nil)
        var record = sample()
        try record.write(to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let read = try #require(try CleanupRecord.read(at: url))
        #expect(read.bundleIDs == record.bundleIDs && read.inputSource == record.inputSource && read.apps == record.apps)
        #expect(read.launchAgents == record.launchAgents && read.keychainItems == record.keychainItems && read.loginKeys == record.loginKeys)
        #expect(read.caches == record.caches)
        #expect(abs(read.updated.timeIntervalSince(record.updated)) < 1 && read.format == CleanupRecord.currentFormat)
        // Written again in one go: still the user's alone, nothing else left in the folder.
        record.loginKeys = []
        try record.write(to: url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == [CleanupRecord.fileName])
        #expect(try CleanupRecord.read(at: url)?.loginKeys.isEmpty == true)
        #expect(CleanupRecord.remove(at: url) && CleanupRecord.remove(at: url))
        #expect(try CleanupRecord.read(at: url) == nil)
    }

    /// A record without a list added since (the caches) reads with that list empty; one without its layout's number isn't
    /// one.
    @Test func aListMissingFromTheFileIsEmpty() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(CleanupRecord.fileName)
        try Data(#"{"format": 1, "handedOver": true, "updated": "2026-11-07T06:10:31Z", "inputSource": "com.example.before.inputmethod"}"#.utf8)
            .write(to: url)
        let read = try #require(try CleanupRecord.read(at: url))
        #expect(read.handedOver && read.inputSource == "com.example.before.inputmethod" && read.caches.isEmpty && read.apps.isEmpty)
        #expect(!read.isEmpty)
        try Data(#"{"handedOver": true}"#.utf8).write(to: url)
        #expect(throws: (any Error).self) { try CleanupRecord.read(at: url) }
        var caches = CleanupRecord()
        caches.caches = ["/tmp/Caches/com.example.before.inputmethod"]
        #expect(!caches.isEmpty && CleanupRecord().isEmpty)
    }

    @Test func aRecordThatIsntOneThrows() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(CleanupRecord.fileName)
        try Data("{\"handedOver\": tr".utf8).write(to: url)
        #expect(throws: (any Error).self) { try CleanupRecord.read(at: url) }
    }

    /// The next version's once handed over, or once it hasn't changed for a while (the version that moved stopped).
    @Test func aRecordIsTheNextVersionsOnceHandedOverOrStale() {
        var record = sample()
        let now = record.updated
        #expect(!record.isHandedOver(now: now.addingTimeInterval(60)))
        #expect(record.isHandedOver(now: now.addingTimeInterval(CleanupRecord.staleAfter + 1)))
        record.handedOver = true
        #expect(record.isHandedOver(now: now))
        #expect(!record.isEmpty && CleanupRecord().isEmpty)
    }

    /// The test install's store: items by service and account, added only where there is none, read back with their
    /// attributes; another service's items in the same file left alone.
    @Test func aTestInstallsStoreKeepsEachServiceApart() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("login.plist")
        let keys = IdentityHandover.fileStore(file, service: APIKeys.service)
        let replaced = IdentityHandover.fileStore(file, service: KeySync.replacedService)
        let saved = Date(timeIntervalSince1970: 1_790_000_000.5)
        #expect(keys.adding("claude", "sk-test-1", "AllInOneIME: Claude", "api.anthropic.com", "st-1", saved) == .ok)
        #expect(keys.adding("claude", "sk-test-2", "", "", nil, nil) == .failed(APIKeys.Keychain.duplicateItem))
        #expect(replaced.adding("claude", "sk-test-old", "AllInOneIME: Claude (replaced)", "", nil, nil) == .ok)
        #expect(keys.read("claude") == "sk-test-1" && replaced.read("claude") == "sk-test-old")
        let attributes = try #require(keys.attributes("claude"))
        #expect(attributes.label == "AllInOneIME: Claude" && attributes.comment == "api.anthropic.com" && attributes.ending == "st-1")
        #expect(IdentityHandover.same(attributes.saved, saved) && attributes.modified != nil)
        #expect(keys.delete("claude") == .ok && keys.delete("claude") == .notFound)
        #expect(keys.accounts().isEmpty && replaced.accounts() == ["claude"])
        #expect(IdentityHandover.handoverService(for: APIKeys.service) != APIKeys.service)
    }
}
