import Foundation
import AllInOneIMECore

/// Installing an update on the Mac: its archive unpacked with ditto, its apps checked (Info.plist, code signature).
extension Updater {
    /// The Mac apps' update manifest (site/public/update.json, signed).
    public static let defaultManifestURL = URL(string: "https://allinoneime.com/update.json")!

    /// Unpacks the (verified) archive into `folder` (empty) with the system's ditto, without the download's
    /// quarantine, and checks both apps: the bundle IDs, the manifest's version and build, intact code
    /// signatures (`CodeSignature`; the signed manifest and its sha256 are what vouch for who made them).
    public static func unpack(_ archive: URL, into folder: URL, manifest: UpdateManifest) throws -> UpdatePayload {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", "--noqtn", archive.path, folder.path]
        let errors = Pipe()
        ditto.standardError = errors
        ditto.standardOutput = FileHandle.nullDevice
        do { try ditto.run() } catch { throw UpdateError.unpack(error.localizedDescription) }
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.unpack(String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let payload = UpdatePayload(inputMethod: folder.appendingPathComponent(inputMethodName, isDirectory: true),
                                    settingsApp: folder.appendingPathComponent(settingsAppName, isDirectory: true))
        try check(payload.inputMethod, identifier: bundleID, manifest: manifest, build: true)
        try check(payload.settingsApp, identifier: settingsBundleID, manifest: manifest, build: false)
        return payload
    }

    /// `app` is a real folder (not a link) holding the bundle `identifier` at the manifest's version (and build),
    /// with an intact code signature.
    public static func check(_ app: URL, identifier: String, manifest: UpdateManifest, build: Bool) throws {
        let name = app.lastPathComponent
        guard (try? FileManager.default.attributesOfItem(atPath: app.path))?[.type] as? FileAttributeType == .typeDirectory,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
            throw UpdateError.invalidApp("\(name) is missing")
        }
        guard info["CFBundleIdentifier"] as? String == identifier else { throw UpdateError.invalidApp("\(name)'s bundle ID") }
        guard info["CFBundleShortVersionString"] as? String == manifest.version else {
            throw UpdateError.invalidApp("\(name) is version \(info["CFBundleShortVersionString"] as? String ?? "?"), not \(manifest.version)")
        }
        if build, info["CFBundleVersion"] as? String != manifest.build {
            throw UpdateError.invalidApp("\(name) is build \(info["CFBundleVersion"] as? String ?? "?"), not \(manifest.build)")
        }
        CodeSignature.removeQuarantine(app)
        do {
            try CodeSignature.check(app, identifier: identifier, team: nil)
        } catch let failure as CodeSignature.Failure {
            throw UpdateError.invalidApp("\(name)'s code signature (\(failure.status))")
        }
    }
}
