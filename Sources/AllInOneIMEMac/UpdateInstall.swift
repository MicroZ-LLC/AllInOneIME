import Foundation
import AllInOneIMECore

/// Installing an update on the Mac: its archive unpacked with ditto, its apps checked (Info.plist, code signature).
extension Updater {
    /// The Mac apps' update manifest (site/public/update-v2.json, signed). update.json, which versions before 0.7.1 read,
    /// stays at 0.7.1: they don't install apps with this version's bundle IDs.
    public static let defaultManifestURL = URL(string: "https://allinoneime.com/update-v2.json")!

    /// Unpacks the (verified) archive into `folder` (empty) with the system's ditto, without the download's
    /// quarantine, and checks both apps: the bundle IDs, the manifest's version and build, intact code
    /// signatures (`CodeSignature`; the signed manifest and its sha256 are what vouch for who made them), by `team`
    /// when there is one: this app's own (`CodeSignature.ownTeamID`), as the installer checks them; an ad-hoc signed
    /// build (a developer's) has none.
    public static func unpack(_ archive: URL, into folder: URL, manifest: UpdateManifest,
                              team: String? = CodeSignature.ownTeamID) throws -> UpdatePayload {
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
        try check(payload.inputMethod, identifier: bundleID, manifest: manifest, build: true, team: team)
        try check(payload.settingsApp, identifier: settingsBundleID, manifest: manifest, build: false, team: team)
        return payload
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

/// The input method started again by the update helper once the apps are in (or back): with `open`, as a new instance
/// when none is running (Launch Services may take the helper itself for the app at that path, the helper having
/// started from it, and then start nothing: `open` returned -600 after the move to the new identity), then looked for
/// until it runs.
public enum UpdateRelaunch {
    /// `open`'s arguments: a new instance of `app` when none runs (else the one running is brought forward), the
    /// settings window opened when `settings`.
    public static func openArguments(_ app: URL, newInstance: Bool, settings: Bool) -> [String] {
        (newInstance ? ["-n"] : []) + [app.path] + (settings ? ["--args", "--settings"] : [])
    }

    /// `app` started (`open`, run with `openArguments`) and looked for (`running`) for `wait` seconds: nil once it runs,
    /// else why it doesn't.
    public static func start(_ app: URL, newInstance: Bool, settings: Bool, open: ([String]) -> (status: Int32, output: String),
                             running: () -> Bool, wait: TimeInterval = 10,
                             pause: () -> Void = { Thread.sleep(forTimeInterval: 0.25) }, now: () -> Date = Date.init) -> String? {
        let opened = open(openArguments(app, newInstance: newInstance, settings: settings))
        let deadline = now().addingTimeInterval(wait)
        while !running() {
            guard now() < deadline else {
                let said = opened.output.split(whereSeparator: \.isNewline).last.map { ": \($0.prefix(200))" } ?? ""
                return opened.status == 0 ? "it isn't running \(Int(wait)) s after open" : "open exited \(opened.status)\(said)"
            }
            pause()
        }
        return nil
    }

    /// The processes, this one excepted, whose executable is `executable` (by its path, links resolved): the kernel's
    /// list, not Launch Services'.
    public static func processes(running executable: URL) -> [pid_t] {
        let wanted = executable.resolvingSymlinksInPath().standardizedFileURL.path
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { pid in
            guard pid > 0, pid != getpid(), let path = executablePath(of: pid) else { return false }
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path == wanted
        }
    }

    /// The path of `pid`'s executable as it is now (the kernel's: it follows a rename of its bundle); nil when it can't
    /// be had.
    public static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
