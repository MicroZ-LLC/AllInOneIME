import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing

/// The Settings app from the engine: `@settings` starts AllInOneIMESettings.exe (with a test engine's pipe), the apps
/// typed in are offered to its per-app settings, and the String Catalog of the interface text is found. (The interface
/// language itself is global to the process: the Settings app's end-to-end test checks it, on an engine of its own.)
@Suite(.serialized)
struct SettingsAppTests {
    func client(_ json: String = #"{"inputLanguages": ["en"]}"#) throws -> (EngineClient, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("engine-settings-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (EngineClient(settings: try settingsFile(json, in: folder), rime: nil), folder)
    }

    @Test func settingsStartsTheSettingsApp() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = #"C:\Program Files\AllInOneIME\0.6.6\Settings\AllInOneIMESettings.exe"#
        client.host.settingsApp = app
        client.host.settingsAppArguments = ["--pipe", #"\.\pipe\test"#]
        let session = try #require(client.host.liveSessions.first)
        client.host.perform(.openSettings, in: session)
        #expect(client.system.opened == [app])
        #expect(client.panel.notices.isEmpty)
    }

    @Test func theAppsTypedInAreOffered() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(client.host.recentApps == ["win:notepad.exe"])
    }

    @Test func theCatalogIsFoundBesideTheProgramOrInTheCheckout() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("engine-catalog-\(UUID().uuidString)", isDirectory: true)
        let build = folder.appendingPathComponent("Windows/.build/release", isDirectory: true)
        let resources = folder.appendingPathComponent("Core/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = build.appendingPathComponent("AllInOneIMEEngine.exe")
        #expect(EngineLanguage.catalog(executable: executable) == nil)
        try Data("{}".utf8).write(to: resources.appendingPathComponent(EngineLanguage.catalogName))
        #expect(EngineLanguage.catalog(executable: executable)?.lastPathComponent == EngineLanguage.catalogName)
        try Data("{}".utf8).write(to: build.appendingPathComponent(EngineLanguage.catalogName))
        #expect(EngineLanguage.catalog(executable: executable)?.deletingLastPathComponent().lastPathComponent == "release")
    }
}
