import Foundation
import Testing
@testable import AllInOneIMECore

/// Installing an update on the Mac: the archive unpacked and its apps checked (`Updater.unpack`), and the apps swapped
/// in (`BundleSwap`). Moved with them from UpdateTests.
struct UpdateInstallTests {
    /// A manifest for `version` and `build`, as UpdateTests' server signs them.
    static func manifest(version: String, build: String) throws -> UpdateManifest {
        let fields: [String: Any] = [
            "schema": 1, "version": version, "build": build, "minimumSystemVersion": "14.0",
            "url": "https://github.com/MicroZ-LLC/AllInOneIME/releases/download/v0.7.0/AllInOneIME-0.7.0-update.zip",
            "sha256": String(repeating: "a", count: 64), "size": 1000,
            "notesURL": "https://github.com/MicroZ-LLC/AllInOneIME/releases/tag/v\(version)",
            "summary": ["en": "One-click updates.", "zh": "一键更新。"]]
        return try JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    // MARK: Unpacking

    @Test func onlyTheManifestsAppsAreUnpackedAndAccepted() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("update-unpack-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let manifest = try Self.manifest(version: "0.7.0", build: "9")
        func attempt(_ name: String, version: String = "0.7.0", build: String = "9", imeID: String = Updater.bundleID,
                     sign: Bool = true, settings: Bool = true) throws -> UpdatePayload {
            let source = work.appendingPathComponent("\(name)-src", isDirectory: true)
            try FakeApp.make(source.appendingPathComponent(Updater.inputMethodName), id: imeID, version: version, build: build, sign: sign)
            if settings {
                try FakeApp.make(source.appendingPathComponent(Updater.settingsAppName), id: Updater.settingsBundleID, version: version,
                                 build: build, sign: sign)
            }
            let zip = work.appendingPathComponent("\(name).zip")
            try FakeApp.run("/usr/bin/ditto", ["-c", "-k", source.path, zip.path])
            let into = work.appendingPathComponent("\(name)-out", isDirectory: true)
            try FileManager.default.createDirectory(at: into, withIntermediateDirectories: true)
            return try Updater.unpack(zip, into: into, manifest: manifest)
        }
        let payload = try attempt("good")
        #expect(payload.inputMethod.lastPathComponent == "AllInOneIME.app" && FileManager.default.fileExists(atPath: payload.settingsApp.path))
        #expect(throws: UpdateError.invalidApp("AllInOneIME.app is version 0.6.9, not 0.7.0")) { try attempt("old", version: "0.6.9") }
        #expect(throws: UpdateError.invalidApp("AllInOneIME.app is build 8, not 9")) { try attempt("build", build: "8") }
        #expect(throws: UpdateError.invalidApp("AllInOneIME.app's bundle ID")) { try attempt("id", imeID: "com.example.other") }
        #expect(throws: UpdateError.invalidApp("AllInOneIME Settings.app is missing")) { try attempt("half", settings: false) }
        #expect(throws: (any Error).self) { try attempt("unsigned", sign: false) }
        let bad = work.appendingPathComponent("not-a.zip")
        try Data("not a zip".utf8).write(to: bad)
        #expect(throws: (any Error).self) { try Updater.unpack(bad, into: work, manifest: manifest) }
    }

    // MARK: Swapping and rolling back

    @Test func theSwapKeepsThePreviousAppsUntilCommitted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Input Methods/AllInOneIME.app"), settings = root.appendingPathComponent("Applications/AllInOneIME Settings.app")
        let newIME = root.appendingPathComponent("new/AllInOneIME.app"), newSettings = root.appendingPathComponent("new/AllInOneIME Settings.app")
        for (app, text) in [(installed, "old"), (settings, "old settings"), (newIME, "new"), (newSettings, "new settings")] {
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: app.appendingPathComponent("marker"))
        }
        func marker(_ app: URL) -> String? { (try? Data(contentsOf: app.appendingPathComponent("marker"))).map { String(decoding: $0, as: UTF8.self) } }

        // Rolled back: the previous apps are back where they were.
        var swap = try BundleSwap.perform(placing: [(newIME, installed), (newSettings, settings)], replacing: [installed, settings],
                                          aside: root.appendingPathComponent("previous"))
        #expect(marker(installed) == "new" && marker(settings) == "new settings")
        #expect(swap.movedAside.count == 2 && swap.placed == [installed, settings])
        try swap.rollBack(reason: "test")
        #expect(marker(installed) == "old" && marker(settings) == "old settings")

        // A failure half way (the second new app isn't there): nothing changed.
        try FileManager.default.createDirectory(at: newIME, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: newIME.appendingPathComponent("marker"))
        #expect(throws: (any Error).self) {
            try BundleSwap.perform(placing: [(newIME, installed), (root.appendingPathComponent("new/missing.app"), settings)],
                                   replacing: [installed, settings], aside: root.appendingPathComponent("previous2"))
        }
        #expect(marker(installed) == "old" && marker(settings) == "old settings")

        // Committed: the new apps stay, the previous ones are gone. A settings app the user deleted is installed anyway.
        // (A rollback deletes the new apps it had placed: they come again.)
        try FileManager.default.removeItem(at: settings)
        for (app, text) in [(newIME, "new"), (newSettings, "new settings")] {
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: app.appendingPathComponent("marker"))
        }
        swap = try BundleSwap.perform(placing: [(newIME, installed), (newSettings, settings)], replacing: [installed, settings],
                                      aside: root.appendingPathComponent("previous3"))
        swap.commit()
        #expect(marker(installed) == "new" && marker(settings) == "new settings")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("previous3").path))
    }

    @Test func aRollBackThatCantPutAnAppBackSaysWhereItIs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Input Methods/AllInOneIME.app"), new = root.appendingPathComponent("new/AllInOneIME.app")
        for app in [installed, new] { try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true) }
        let aside = root.appendingPathComponent("previous")
        let swap = try BundleSwap.perform(placing: [(new, installed)], replacing: [installed], aside: aside)
        // The previous app vanished from where it waited (say, the folder was cleaned up meanwhile).
        try FileManager.default.removeItem(at: aside)
        #expect(throws: BundleSwap.Failure.notRestored("test", folder: aside.path)) { try swap.rollBack(reason: "test") }
    }
}

/// Minimal signed app bundles for the unpacking test: Info.plist and a copy of /usr/bin/true, ad-hoc signed.
enum FakeApp {
    static func make(_ app: URL, id: String, version: String, build: String, sign: Bool) throws {
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = app.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "")
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleVersion": build,
                                   "CFBundleExecutable": executable, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent(executable))
        if sign { try run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", id, app.path]) }
    }

    static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
