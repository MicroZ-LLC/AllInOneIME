import CryptoKit
import Foundation
import os
import Testing
@testable import AllInOneIMECore

/// A pack library served from https://<host>/lib/ (LibraryStubProtocol), signed with a key made for the
/// test, installing into a temporary packs folder.
struct TestPackLibrary {
    let host = "packs-\(UUID().uuidString.prefix(8).lowercased()).test"
    let key = Curve25519.Signing.PrivateKey()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("packs-\(UUID().uuidString)", isDirectory: true)
    var base: String { "https://\(host)/lib/" }
    var store: LanguagePackStore { LanguagePackStore(directory: root.appendingPathComponent("packs", isDirectory: true)) }

    func library(appVersion: String = "0.6.2", allowsLocalHTTP: Bool = false) -> LanguagePackLibrary {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        return LanguagePackLibrary(baseURL: URL(string: base)!, publicKey: key.publicKey.rawRepresentation,
                                   configuration: configuration, appVersion: appVersion, store: store, allowsLocalHTTP: allowsLocalHTTP)
    }

    /// A Chinese pack's archive: `files` (path → text) plus pack.json, packed with the system's tar.
    /// `link` adds a symbolic link at that path.
    func archive(version: String = "1.0.0", files: [String: String]? = nil, link: String? = nil) throws -> Data {
        let folder = root.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        let files = files ?? ["default.yaml": "config_version: 1", "rime_ice.schema.yaml": "schema: {}",
                              "build/rime_ice.table.bin": "table", "cn_dicts/8105.dict.yaml": "dict"]
        var all = files
        all["pack.json"] = #"{"id":"zh-pinyin","version":"\#(version)"}"#
        for (path, text) in all {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        if let link { try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent(link).path, withDestinationPath: "/etc") }
        let out = root.appendingPathComponent("\(UUID().uuidString).tar.xz")
        #if os(Windows)
        // Started as the core starts it: Foundation's `Process` hands the program every inheritable handle the tests
        // have open (another test's half-written config.json), which then can't be renamed over while tar runs.
        let tar = try WindowsProcessLauncher().launch(LaunchSpec(executable: LanguagePackLibrary.systemTar,
                                                                 arguments: ["-C", folder.path, "-cJf", out.path, "."],
                                                                 standardInput: .null, standardOutput: .null, standardError: .null))
        #else
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-C", folder.path, "-cJf", out.path, "."]
        tar.environment = ["COPYFILE_DISABLE": "1"]
        try tar.run()
        #endif
        tar.waitUntilExit()
        return try Data(contentsOf: out)
    }

    /// Serves `archive` and returns its index entry.
    func publish(_ archive: Data, version: String = "1.0.0", minAppVersion: String = "0.6.2", size: Int? = nil,
                 sha256: String? = nil, url: String? = nil) -> [String: Any] {
        let name = "zh-pinyin-\(version)-\(UUID().uuidString.prefix(4)).tar.xz"
        LibraryStubProtocol.serve(base + "assets/" + name, archive)
        return ["id": "zh-pinyin", "version": version, "minAppVersion": minAppVersion, "url": url ?? "assets/" + name,
                "sha256": sha256 ?? PluginLibrary.sha256(archive), "size": size ?? archive.count, "installedSize": 100]
    }

    @discardableResult
    func serveIndex(_ packs: [[String: Any]], schema: Int = 1, signer: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: ["schema": schema, "packs": packs], options: [.sortedKeys])
        LibraryStubProtocol.serve(base + "packs.json", data)
        LibraryStubProtocol.serve(base + "packs.json.sig", Data(try (signer ?? key).signature(for: data).base64EncodedString().utf8))
        return data
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

/// Collects progress reports from the download's thread.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.withLock { values.append(value) } }
    var all: [Double] { lock.withLock { values } }
}

struct LanguagePackTests {
    @Test func catalog() {
        #expect(LanguagePack.for(.chinese) == .chinesePinyin)
        #expect(LanguagePack.for(.english) == nil)
    }

    // MARK: Index

    @Test func theIndexIsReadOnlyWhenSigned() async throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        let entry = lib.publish(Data("x".utf8))
        try lib.serveIndex([entry])
        let index = try await lib.library().fetchIndex()
        #expect(index.packs.map(\.id) == ["zh-pinyin"])

        try lib.serveIndex([entry], signer: Curve25519.Signing.PrivateKey())
        await #expect(throws: LanguagePackError.badSignature) { try await lib.library().fetchIndex() }
        // The app's own key doesn't accept the test key's signature either.
        #expect(throws: LanguagePackError.badSignature) {
            try LanguagePackLibrary.verify(index: Data("{}".utf8), signature: Data("AAAA".utf8), publicKey: PluginLibrary.publicKey)
        }
        #expect(throws: LanguagePackError.missingSignature) {
            try LanguagePackLibrary.verify(index: Data("{}".utf8), signature: Data(), publicKey: PluginLibrary.publicKey)
        }
        try lib.serveIndex([entry], schema: 2)
        await #expect(throws: LanguagePackError.unsupportedSchema(2)) { try await lib.library().fetchIndex() }
    }

    @Test func theNewestVersionThisAppCanUseIsPicked() throws {
        let lib = TestPackLibrary()
        let data = try JSONSerialization.data(withJSONObject: ["schema": 1, "packs": [
            ["id": "zh-pinyin", "version": "1.0.0", "url": "a", "sha256": String(repeating: "0", count: 64), "size": 1],
            ["id": "zh-pinyin", "version": "1.2.0", "url": "b", "sha256": String(repeating: "0", count: 64), "size": 1],
            ["id": "zh-pinyin", "version": "2.0.0", "minAppVersion": "0.9.0", "url": "c", "sha256": String(repeating: "0", count: 64), "size": 1],
            ["id": "ja-romaji", "version": "9.0.0", "url": "d", "sha256": String(repeating: "0", count: 64), "size": 1],
            ["id": "zh-pinyin", "version": "3.0.0"],  // unreadable: left out, not the whole index
        ]])
        let index = try LanguagePackLibrary.verify(index: data, signature: Data(try lib.key.signature(for: data).base64EncodedString().utf8),
                                                   publicKey: lib.key.publicKey.rawRepresentation)
        #expect(index.packs.count == 4)
        #expect(lib.library(appVersion: "0.6.2").newest(.chinesePinyin, in: index)?.version == "1.2.0")
        #expect(lib.library(appVersion: "0.9.0").newest(.chinesePinyin, in: index)?.version == "2.0.0")
    }

    // MARK: Installing

    @Test func installsWithProgressThenUpdatesInPlace() async throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        try lib.serveIndex([lib.publish(try lib.archive())])
        let progress = ProgressLog()
        let record = try await lib.library().install(.chinesePinyin) { progress.add($0) }
        #expect(record == LanguagePackRecord(id: "zh-pinyin", version: "1.0.0", source: .library, sha256: record.sha256))
        #expect(lib.store.installed(.chinesePinyin) == record)
        #expect(progress.all.last == 1)
        let folder = lib.store.folder(.chinesePinyin)
        #expect(try String(contentsOf: folder.appendingPathComponent("cn_dicts/8105.dict.yaml"), encoding: .utf8) == "dict")

        // A newer version replaces it; no temporary folders are left.
        try lib.serveIndex([lib.publish(try lib.archive(version: "1.1.0", files: [
            "default.yaml": "2", "rime_ice.schema.yaml": "2", "build/rime_ice.table.bin": "2"]), version: "1.1.0")])
        #expect(try await lib.library().install(.chinesePinyin).version == "1.1.0")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("cn_dicts").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: lib.store.directory.path) == ["zh-pinyin"])

        try lib.store.remove(.chinesePinyin)
        #expect(lib.store.installed(.chinesePinyin) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: lib.store.directory.path).isEmpty)
    }

    @Test func aDownloadThatDoesntMatchTheIndexChangesNothing() async throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        try lib.serveIndex([lib.publish(try lib.archive())])
        try await lib.library().install(.chinesePinyin)
        let installed = lib.store.installed(.chinesePinyin)

        let other = try lib.archive(version: "1.1.0")
        // Another archive than the one signed for.
        try lib.serveIndex([lib.publish(other, version: "1.1.0", sha256: String(repeating: "a", count: 64))])
        await #expect(throws: LanguagePackError.hashMismatch) { try await lib.library().install(.chinesePinyin) }
        // Larger than the index says: stopped.
        try lib.serveIndex([lib.publish(other, version: "1.1.0", size: other.count - 10)])
        await #expect(throws: LanguagePackError.self) { try await lib.library().install(.chinesePinyin) }
        // Shorter than the index says.
        try lib.serveIndex([lib.publish(other, version: "1.1.0", size: other.count + 10)])
        await #expect(throws: LanguagePackError.hashMismatch) { try await lib.library().install(.chinesePinyin) }
        // pack.json says another version than the index.
        try lib.serveIndex([lib.publish(other, version: "1.2.0")])
        await #expect(throws: LanguagePackError.invalidContent("pack.json doesn't match the index")) {
            try await lib.library().install(.chinesePinyin)
        }
        #expect(lib.store.installed(.chinesePinyin) == installed)
        #expect(try FileManager.default.contentsOfDirectory(atPath: lib.store.directory.path) == ["zh-pinyin"])
    }

    @Test func aPackIsDataOnly() async throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        let base = ["default.yaml": "1", "rime_ice.schema.yaml": "1", "build/rime_ice.table.bin": "1"]
        for (files, link) in [(base.merging(["lua/date.lua": "os.execute('x')"]) { $1 }, nil),
                              (base.merging(["opencc/x.dylib": "MZ"]) { $1 }, nil),
                              (base, "build/escape"),
                              (base.filter { $0.key != "build/rime_ice.table.bin" }, nil)] as [([String: String], String?)] {
            try lib.serveIndex([lib.publish(try lib.archive(files: files, link: link))])
            await #expect(throws: LanguagePackError.self) { try await lib.library().install(.chinesePinyin) }
            #expect(lib.store.installed(.chinesePinyin) == nil)
        }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: lib.store.directory.path)) ?? []).isEmpty)
    }

    @Test func onlyHTTPSOrThisMac() async throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        let archive = try lib.archive()
        try lib.serveIndex([lib.publish(archive, url: "http://example.com/zh.tar.xz")])
        await #expect(throws: LanguagePackError.invalidEntry("http://example.com/zh.tar.xz")) {
            try await lib.library(allowsLocalHTTP: true).install(.chinesePinyin)
        }
        #expect(lib.library().isAllowed(URL(string: "https://github.com/x")!))
        #expect(!lib.library().isAllowed(URL(string: "http://127.0.0.1:8000/x")!))
        #expect(lib.library(allowsLocalHTTP: true).isAllowed(URL(string: "http://127.0.0.1:8000/x")!))
        #expect(!lib.library(allowsLocalHTTP: true).isAllowed(URL(string: "file:///etc/passwd")!))
    }

    // MARK: Upgrades

    @Test func anOlderAppsDataIsAdoptedWithoutItsCode() throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        let old = lib.root.appendingPathComponent("Old.app/Contents/SharedSupport/rime", isDirectory: true)
        for (path, text) in ["default.yaml": "1", "rime_ice.schema.yaml": "1", "build/rime_ice.table.bin": "1", "lua/date.lua": "code"] {
            let url = old.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let record = try lib.store.adopt(.chinesePinyin, from: old, version: "1.0.0")
        #expect(record.source == .app && lib.store.installed(.chinesePinyin) == record)
        let folder = lib.store.folder(.chinesePinyin)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("lua").path))
        #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("lua/date.lua").path))  // the source is left as it was

        // The app's Lua is linked in, and followed when the app moves. (On Windows a link's target reads back with "\".)
        func target() throws -> String {
            let link = try FileManager.default.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("lua").path)
            return CorePaths.isSeparator("\\") ? link.replacingOccurrences(of: "\\", with: "/") : link
        }
        let code = lib.root.appendingPathComponent("App.app/Contents/SharedSupport/rime-lua", isDirectory: true)
        try lib.store.linkCode(.chinesePinyin, from: code)
        #expect(try target() == code.path)
        let moved = lib.root.appendingPathComponent("Moved.app/Contents/SharedSupport/rime-lua", isDirectory: true)
        try lib.store.linkCode(.chinesePinyin, from: moved)
        #expect(try target() == moved.path)
        try lib.store.linkCode(.chinesePinyin, from: nil)
        #expect((try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("lua").path)) == nil)
    }

    @Test func whoKeepsChinese() throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        let config = lib.root.appendingPathComponent("config.json")
        let rime = lib.root.appendingPathComponent("Rime", isDirectory: true)
        try FileManager.default.createDirectory(at: lib.root, withIntermediateDirectories: true)
        // A new install: no settings, librime never deployed.
        #expect(!LanguagePackMigration.wantsChinese(configFile: config, rimeUserFolder: rime))
        // No settings file, but librime deployed: the old default had Chinese.
        try FileManager.default.createDirectory(at: rime.appendingPathComponent("build"), withIntermediateDirectories: true)
        #expect(LanguagePackMigration.wantsChinese(configFile: config, rimeUserFolder: rime))
        // The settings decide when there are some.
        try Data(#"{"inputLanguages": ["en"]}"#.utf8).write(to: config)
        #expect(!LanguagePackMigration.wantsChinese(configFile: config, rimeUserFolder: rime))
        try Data(#"{"inputLanguages": ["en", "zh"]}"#.utf8).write(to: config)
        #expect(LanguagePackMigration.wantsChinese(configFile: config, rimeUserFolder: rime))
        // From before input languages: it had Chinese.
        try Data(#"{"awsProfile": "default"}"#.utf8).write(to: config)
        #expect(LanguagePackMigration.wantsChinese(configFile: config, rimeUserFolder: rime))
    }

    // MARK: Without a pack

    @Test func englishWithoutAPackTypesAndRunsCommands() {
        let composer = Composer(engine: LatinEngine())
        composer.inputLanguages = [.english]
        composer.commands = Command.builtins
        composer.setInputMode(.chinese)  // there is no Chinese: it stays in English
        #expect(composer.engineState.isAsciiMode)
        #expect(composer.handleKeyDown(k("a")) == .passThrough)
        let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
        #expect(composer.handleKeyDown(at).handled)
        _ = composer.handleKeyDown(k("t"))
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        for ch in "hi" { _ = composer.handleKeyDown(k(String(ch))) }
        #expect(composer.draft == "@translate hi")
    }
}
