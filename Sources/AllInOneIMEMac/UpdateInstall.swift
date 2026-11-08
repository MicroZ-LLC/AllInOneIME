import Foundation
import AllInOneIMECore

/// Installing an update on the Mac: its archive unpacked with ditto, its apps checked (Info.plist, code signature).
extension Updater {
    /// The Mac apps' update manifest (site/public/update-v2.json, signed). update.json, which 0.7.0 and earlier read,
    /// stays at 0.7.1: they don't install apps with the new bundle IDs (`AppIdentity`).
    public static let defaultManifestURL = URL(string: "https://allinoneime.com/update-v2.json")!

    /// Unpacks the (verified) archive into `folder` (empty) with the system's ditto, without the download's
    /// quarantine, and checks both apps: the bundle IDs (an identity that may replace `installed`'s: `accepts`), the
    /// manifest's version and build, intact code signatures (`CodeSignature`; the signed manifest and its sha256 are
    /// what vouch for who made them), by `team` when there is one: this app's own (`CodeSignature.ownTeamID`), as the
    /// installer checks them; an ad-hoc signed build (a developer's) has none.
    public static func unpack(_ archive: URL, into folder: URL, manifest: UpdateManifest,
                              team: String? = CodeSignature.ownTeamID, installed: AppIdentity = identity) throws -> UpdatePayload {
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
        let inputMethod = folder.appendingPathComponent(inputMethodName, isDirectory: true)
        let payload = UpdatePayload(inputMethod: inputMethod, settingsApp: folder.appendingPathComponent(settingsAppName, isDirectory: true),
                                    identity: try identity(of: inputMethod, over: installed))
        try check(payload.inputMethod, identifier: payload.identity.inputMethod, manifest: manifest, build: true, team: team)
        try check(payload.settingsApp, identifier: payload.identity.settings, manifest: manifest, build: false, team: team)
        return payload
    }

    /// The identity of the new input method at `inputMethod`, when it may replace `installed`'s (`accepts`); else
    /// `invalidApp`, as for any other bundle ID.
    public static func identity(of inputMethod: URL, over installed: AppIdentity) throws -> AppIdentity {
        let name = inputMethod.lastPathComponent
        guard let info = NSDictionary(contentsOf: inputMethod.appendingPathComponent("Contents/Info.plist")) else {
            throw UpdateError.invalidApp("\(name) is missing")
        }
        guard let found = AppIdentity.of(inputMethod: info["CFBundleIdentifier"] as? String), accepts(found, over: installed) else {
            throw UpdateError.invalidApp("\(name)'s bundle ID")
        }
        return found
    }

    /// `app` is a real folder (not a link) holding the bundle `identifier` at the manifest's version (and build),
    /// with an intact code signature, `team`'s when it is given (`unpack`).
    public static func check(_ app: URL, identifier: String, manifest: UpdateManifest, build: Bool,
                             team: String? = CodeSignature.ownTeamID) throws {
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
            try CodeSignature.check(app, identifier: identifier, team: team)
        } catch let failure as CodeSignature.Failure {
            throw UpdateError.invalidApp("\(name)'s code signature (\(failure.status))")
        }
    }
}
