import AllInOneIMECore
import AllInOneIMEMac
import Carbon
import Foundation
import Security

/// Installs AllInOneIME for the current user the way `make install` does, and removes it the way
/// `make uninstall` does: the input method in ~/Library/Input Methods, 「AllInOneIME 设置」 in
/// ~/Applications, registered and added to the user's input sources. No administrator password.
enum Installer {
    static let bundleID = "com.aipinyin.inputmethod.AIPinyin"
    static let settingsBundleID = "com.aipinyin.settings"
    /// The input method's process names, now and in the AIPinyin days (same bundle ID).
    static let processNames = ["AllInOneIME", "AIPinyin"]
    static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let inputMethods = home.appendingPathComponent("Library/Input Methods", isDirectory: true)
    static let applications = home.appendingPathComponent("Applications", isDirectory: true)
    static let inputMethod = inputMethods.appendingPathComponent("AllInOneIME.app")
    static let settingsApp = applications.appendingPathComponent("AllInOneIME Settings.app")
    static let executable = inputMethod.appendingPathComponent("Contents/MacOS/AllInOneIME")
    /// Installed under the old name by earlier versions; removed on install and uninstall.
    static let legacyApps = [inputMethods.appendingPathComponent("AIPinyin.app"),
                             applications.appendingPathComponent("AI 拼音设置.app")]

    /// Both apps, zipped by `make installer-app`. An archive rather than the apps themselves: a
    /// second AllInOneIME.app (same bundle ID) on the disk image is one macOS might launch instead
    /// of the installed one.
    static var payload: URL? { Bundle.main.url(forResource: "Payload", withExtension: "zip") }

    /// The version this installer carries (the apps in the payload are built from the same tree).
    static let version = AppVersion.string

    /// The installed input method's version; nil if it isn't installed or doesn't say.
    static func installedVersion() -> String? {
        NSDictionary(contentsOf: inputMethod.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    static var hasLegacyInstall: Bool { legacyApps.contains(where: exists) }

    /// Doesn't follow a symbolic link at the end, so a dangling one counts as well.
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// A real folder, not a symbolic link to one.
    static func isFolder(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeDirectory
    }

    enum Failure: LocalizedError {
        case payloadMissing
        case unpack(String)
        case signature(String, OSStatus)
        case register(Int32, String)
        /// The new input method doesn't start (`AllInOneIME --version`); the previous apps were put back.
        case launch(String)
        /// Installing failed and an old app couldn't be moved back either; it was kept in `folder`.
        case notRestored(String, folder: String)

        var errorDescription: String? {
            switch self {
            case .payloadMissing:
                return tr("安装程序不完整，请从 Releases 重新下载。",
                          "The installer is incomplete. Please download it again from Releases.")
            case let .unpack(output):
                return tr("解压失败：", "Couldn't unpack the apps: ") + output
            case let .signature(name, status):
                return tr("\(name) 的签名不对（\(status)），下载的文件可能已损坏或被改过，请从 Releases 重新下载。",
                          "The code signature of \(name) doesn't check out (\(status)); the download may be damaged or altered. Please download it again from Releases.")
            case let .register(status, output):
                return tr("注册输入法失败（退出码 \(status)）：", "Registering the input method failed (exit status \(status)):")
                    + "\n\n" + output
            case let .launch(output):
                return tr("新的输入法启动不了，所以没有装上（原来的保持不变）。请从 Releases 重新下载。",
                          "The new input method doesn't start, so it wasn't installed (what was there before is as it was). Please download it again from Releases.")
                    + (output.isEmpty ? "" : "\n\n" + output)
            case let .notRestored(reason, folder):
                return tr("安装失败（\(reason)），原来的 App 也没能放回原处，现在在：\(folder)",
                          "Installing failed (\(reason)), and the previous apps couldn't be put back; they're in: \(folder)")
            }
        }
    }

    // MARK: Install and uninstall

    /// Replaces the installed apps (and the AIPinyin ones) with those in the payload, then registers
    /// the input method, which also adds it to the input sources and deploys the dictionaries.
    /// Returns what `AllInOneIME --register` printed; `step` reports progress.
    static func install(step: (String) -> Void = { _ in }) throws -> String {
        guard let payload else { throw Failure.payloadMissing }
        let manager = FileManager.default
        try manager.createDirectory(at: inputMethods, withIntermediateDirectories: true)
        try manager.createDirectory(at: applications, withIntermediateDirectories: true)
        // On the same volume, so moving apps in and out of it is a rename.
        let staging = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                      appropriateFor: inputMethods, create: true)
        // Kept when it holds an old app that couldn't be put back.
        var keepStaging = false
        defer { if !keepStaging { try? manager.removeItem(at: staging) } }

        step(tr("正在解压…", "Unpacking…"))
        // --noqtn: the apps don't inherit the download's quarantine from the archive. macOS starts
        // input methods by itself, with no way to confirm a quarantined one; opening this installer
        // was that confirmation.
        let unzip = try run("/usr/bin/ditto", ["-x", "-k", "--noqtn", payload.path, staging.path])
        guard unzip.status == 0 else { throw Failure.unpack(unzip.output) }
        let incoming = [(app: staging.appendingPathComponent(inputMethod.lastPathComponent), to: inputMethod, id: bundleID),
                        (app: staging.appendingPathComponent(settingsApp.lastPathComponent), to: settingsApp, id: settingsBundleID)]
        for item in incoming {
            guard isFolder(item.app) else { throw Failure.payloadMissing }
            removeQuarantine(item.app)
            try checkSignature(item.app, identifier: item.id)
        }

        step(tr("正在安装…", "Installing…"))
        stopInputMethod()
        let legacy = legacyApps.filter(exists)
        if !legacy.isEmpty { _ = try? run(lsregister, ["-u"] + legacy.map(\.path)) }
        // The old apps are moved aside first, so a failure on the way puts them back instead of
        // leaving no input method at all (the in-app updater swaps them the same way).
        let swap: BundleSwap
        do {
            swap = try BundleSwap.perform(placing: incoming.map { ($0.app, $0.to) }, replacing: [inputMethod, settingsApp] + legacy,
                                          aside: staging.appendingPathComponent("previous", isDirectory: true))
        } catch let BundleSwap.Failure.notRestored(reason, folder) {
            keepStaging = true
            throw Failure.notRestored(reason, folder: folder)
        }
        adoptChinesePack(from: swap.movedAside.map(\.to))
        // The new input method has to start before the old one goes: one macOS won't run (a provisioning profile that
        // doesn't match its signature or entitlements) would leave no input method at all.
        let started = try? run(executable.path, ["--version"], timeout: 30)  // as the updater's launch check
        guard let started, started.status == 0, started.output == installedVersion() else {
            let output = started.map { "\($0.status): \($0.output.prefix(200))" } ?? ""
            do {
                try swap.rollBack(reason: "the new input method doesn't start (\(output))")
            } catch let BundleSwap.Failure.notRestored(reason, folder) {
                keepStaging = true
                throw Failure.notRestored(reason, folder: folder)
            }
            throw Failure.launch(output)
        }
        // No second copy (same bundle ID) for macOS to find while the new one registers.
        swap.commit()
        // In case macOS started the old copy again in between: from now on it starts the new one.
        stopInputMethod()
        _ = try? run(lsregister, ["-f", inputMethod.path, settingsApp.path])

        step(tr("正在注册输入法、部署词库…", "Registering the input method and deploying the dictionaries…"))
        let register = try run(executable.path, ["--register"])
        guard register.status == 0 else { throw Failure.register(register.status, register.output) }
        return register.output
    }

    /// Versions up to 0.6.1 bundled the Chinese data; the app now downloads it as a language pack. A user
    /// who typed Chinese keeps it without a download: the old app's copy (moved aside, among `previous`)
    /// becomes the pack, the same rime-ice data as its first version. Nothing for an English-only user,
    /// and a failure only means the input method downloads the pack at launch instead.
    static func adoptChinesePack(from previous: [URL]) {
        let store = LanguagePackStore()
        let rimeUser = home.appendingPathComponent("Library/Application Support/AllInOneIME/Rime", isDirectory: true)
        guard store.installed(.chinesePinyin) == nil,
              LanguagePackMigration.wantsChinese(rimeUserFolder: rimeUser) else { return }
        for app in previous {
            let data = app.appendingPathComponent("Contents/SharedSupport/rime", isDirectory: true)
            guard isFolder(data) else { continue }
            do {
                try store.adopt(.chinesePinyin, from: data, version: "1.0.0")
                return
            } catch {
                NSLog("AllInOneIME installer: could not keep the Chinese data: %@", String(describing: error))
            }
        }
    }

    /// Disables the input method and removes it from the input sources, stops it, and deletes both
    /// apps (and the AIPinyin ones). Settings, the jargon list and learned words stay. Returns what
    /// was done to the input source.
    static func uninstall() throws -> String {
        var output = ""
        var disabled = false
        if FileManager.default.isExecutableFile(atPath: executable.path),
           let result = try? run(executable.path, ["--disable"]) {
            output = result.output
            disabled = result.status == 0
        }
        if !disabled {
            // Only the AIPinyin apps are left, or AllInOneIME couldn't do it: same bundle ID, so
            // the same input source to take out.
            let here = onMain(disableInputSource)
            output = [output, here].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        stopInputMethod()
        let apps = ([inputMethod, settingsApp] + legacyApps).filter(exists)
        if !apps.isEmpty { _ = try? run(lsregister, ["-u"] + apps.map(\.path)) }
        for app in apps { try FileManager.default.removeItem(at: app) }
        return output
    }

    // MARK: Input source (main thread only: Text Input Sources)

    static func inputSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceID as String: bundleID] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    /// The user's input sources (see `InputSourceList`), read afresh: the input method's process
    /// may have just written them.
    static func userList() -> [[String: Any]]? {
        let domain = InputSourceList.domain as CFString
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyValue(InputSourceList.key as CFString, domain,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [[String: Any]]
    }

    /// Whether the input source is enabled, and whether it's in the user's input sources (the list
    /// Ctrl+Space goes through).
    static func inputSourceState() -> (enabled: Bool, listed: Bool) {
        let enabled = inputSources().contains { source in
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
        }
        return (enabled, userList().map { InputSourceList.contains($0, bundleID: bundleID) } ?? false)
    }

    /// What `AllInOneIME --disable` does (InputSourceRegistrar in the input method), for when there
    /// is no AllInOneIME to run it.
    static func disableInputSource() -> String {
        var lines = inputSources().map { source in
            let status = TISDisableInputSource(source)
            return status == 0 ? "disabled \(bundleID)" : "TISDisableInputSource failed: \(status)"
        }
        if let updated = InputSourceList.removing(bundleID, from: userList()) {
            let domain = InputSourceList.domain as CFString
            CFPreferencesSetValue(InputSourceList.key as CFString, updated as CFArray, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            if CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                    object: nil, userInfo: nil, deliverImmediately: true)
                lines.append("removed from your input sources")
            } else {
                lines.append("could not remove it from your input sources (\(InputSourceList.domain))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    // MARK: Helpers

    static func removeQuarantine(_ app: URL) { CodeSignature.removeQuarantine(app) }

    /// The unpacked app is intact (every architecture, nested code included) and is the expected
    /// one: its bundle ID, and when this installer is signed by a team, signed by the same team.
    /// Who made an ad-hoc signed app can't be checked; that's what notarization is for.
    static func checkSignature(_ app: URL, identifier: String) throws {
        do {
            try CodeSignature.check(app, identifier: identifier, team: CodeSignature.ownTeamID)
        } catch let failure as CodeSignature.Failure {
            throw Failure.signature(failure.app, failure.status)
        }
    }

    static let uid = String(getuid())

    /// This user's input method processes (`make install` uses `pkill` for the same).
    static func inputMethodPIDs() -> [pid_t] {
        processNames.flatMap { name -> [pid_t] in
            guard let result = try? run("/usr/bin/pgrep", ["-x", "-U", uid, name]), result.status == 0 else { return [] }
            return result.output.split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
        }
    }

    /// Stops the input method; macOS starts it again, from the installed copy, when it's needed.
    static func stopInputMethod() {
        let pids = inputMethodPIDs()
        for pid in pids { kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(2)
        while pids.contains(where: { kill($0, 0) == 0 }), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        // Only those still there under the same name (not a new process that got the number).
        let left = Set(inputMethodPIDs())
        for pid in pids where left.contains(pid) { kill(pid, SIGKILL) }
    }

    struct ProcessResult {
        var status: Int32
        var output: String
    }

    /// Runs a tool to the end; stdout and stderr together.
    /// With a `timeout`, a program still running after it is stopped (SIGTERM, then SIGKILL a second later), and the
    /// result is status -1, "timed out after … s".
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        guard let timeout else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return ProcessResult(status: process.terminationStatus, output: output)
        }
        // Its output read meanwhile, so that a full pipe never holds it up.
        let read = DispatchGroup()
        var data = Data()
        read.enter()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            _ = read.wait(timeout: .now() + 1)  // a program it started may hold the pipe: not waited for
            return ProcessResult(status: -1, output: "timed out after \(Int(timeout)) s")
        }
        process.waitUntilExit()
        read.wait()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessResult(status: process.terminationStatus, output: output)
    }
}
