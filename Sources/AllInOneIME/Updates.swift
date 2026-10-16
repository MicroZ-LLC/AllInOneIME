import AllInOneIMECore
import AppKit
import SwiftUI

// AllInOneIME's own updates, from Settings → About (and the input menu's "Check for Updates…"):
//
// 1. Checking (`UpdateController.check`): update.json and its signature from allinoneime.com, checked with the
//    releases' key built into the app (`Updater`). By itself once a day, at launch or when a text field is
//    activated, in the background (`UpdateSchedule`; never on a keystroke); turned off in About. A newer version
//    is a quiet line on the About page and in the menu bar panel, never a dialog.
// 2. Update (`UpdateController.install`): the archive is downloaded and checked against the manifest's size and
//    sha256, unpacked into a folder of its own (`UpdateLocations.work`), and both apps are checked (bundle IDs,
//    version and build, code signatures, and the new input method has to start: `--version`) — all before
//    anything installed is touched (`UpdateStaging`).
// 3. The input method can't replace itself while macOS has it loaded: it starts its own executable as a helper
//    (`--apply-update`, in a session of its own so it outlives it) and quits. The helper (`UpdateHelper`) waits
//    for it to end, moves the installed apps aside and the new ones in (`BundleSwap`, as the installer does),
//    checks that the new input method starts and registers it; on any failure it puts the previous apps back
//    and registers those again. Then it starts the input method again (with the settings window, if it was
//    open), which reads what happened (`UpdateResult`) and says so on the About page.
//
// Only the two apps change: the settings, language packs, learned words and extensions live elsewhere
// (~/.config/allinoneime, ~/Library/Application Support/AllInOneIME) and are never touched.

/// Where an update goes: the user's own folders, or a test's (`--target-dir`), which nothing else touches.
struct UpdateLocations {
    var inputMethods: URL
    var applications: URL
    /// Where updates are downloaded, unpacked and checked, and the helper leaves its result: in the user's
    /// Application Support (the same volume as the apps, so moving them is a rename; ".noindex": Spotlight doesn't
    /// list the apps waiting there).
    var work: URL
    /// The helper's log.
    var log: URL
    var isTest: Bool

    var inputMethod: URL { inputMethods.appendingPathComponent(Updater.inputMethodName, isDirectory: true) }
    var settingsApp: URL { applications.appendingPathComponent(Updater.settingsAppName, isDirectory: true) }
    var result: URL { work.appendingPathComponent("result.json") }

    static var real: UpdateLocations {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return UpdateLocations(inputMethods: home.appendingPathComponent("Library/Input Methods", isDirectory: true),
                               applications: home.appendingPathComponent("Applications", isDirectory: true),
                               work: home.appendingPathComponent("Library/Application Support/AllInOneIME/Updates.noindex", isDirectory: true),
                               log: RimeDirectories.logs.appendingPathComponent("update.log"), isTest: false)
    }

    /// `root`/Input Methods, `root`/Applications, `root`/Updates.noindex: a test's install, not the user's.
    static func test(root: URL) -> UpdateLocations {
        UpdateLocations(inputMethods: root.appendingPathComponent("Input Methods", isDirectory: true),
                        applications: root.appendingPathComponent("Applications", isDirectory: true),
                        work: root.appendingPathComponent("Updates.noindex", isDirectory: true),
                        log: root.appendingPathComponent("update.log"), isTest: true)
    }

    /// The version of the input method installed here; nil if there's none.
    var installedVersion: String? { UpdateStaging.version(of: inputMethod) }

    /// Whether this process is the installed input method (only that one is updated in place).
    static var runningIsInstalled: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
            == real.inputMethod.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

// MARK: - Staging

/// Step 2: the update downloaded, unpacked and checked, ready for the helper. Nothing installed is touched.
enum UpdateStaging {
    struct Staged {
        var folder: URL
        var payload: UpdatePayload
    }

    static func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    /// Downloads `manifest`'s archive into a new folder under `locations.work` and unpacks and checks it there.
    /// Any failure removes the folder.
    static func stage(_ manifest: UpdateManifest, updater: Updater, locations: UpdateLocations,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> Staged {
        let manager = FileManager.default
        let folder = locations.work.appendingPathComponent("update-\(manifest.version)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let archive = folder.appendingPathComponent("update.zip")
            try await updater.download(manifest, to: archive, progress: progress)
            let apps = folder.appendingPathComponent("new", isDirectory: true)
            try manager.createDirectory(at: apps, withIntermediateDirectories: false)
            let payload = try Updater.unpack(archive, into: apps, manifest: manifest)
            try? manager.removeItem(at: archive)
            // The new input method has to start (its libraries load, its signature holds) before it goes in.
            try launchCheck(payload.inputMethod, version: manifest.version)
            return Staged(folder: folder, payload: payload)
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }

    /// `app`'s input method runs (`--version`) and says it's `version`.
    static func launchCheck(_ app: URL, version: String) throws {
        let executable = app.appendingPathComponent("Contents/MacOS/AllInOneIME")
        let result = UpdateProcess.run(executable.path, ["--version"], timeout: 30)
        guard result.status == 0, result.output == version else {
            throw UpdateError.invalidApp("\(app.lastPathComponent) doesn't start (\(result.status): \(result.output.prefix(200)))")
        }
    }

    /// Step 3: starts `executable` (this app's) as the helper, in a session of its own (it outlives this process),
    /// its output appended to the log. Returns its process ID.
    @discardableResult
    static func launchHelper(_ staged: Staged, executable: String, locations: UpdateLocations, waitPID: pid_t?,
                             reopenSettings: Bool, simulateFailure: String? = nil) throws -> pid_t {
        var arguments = [executable, "--apply-update", staged.folder.path]
        if let waitPID { arguments += ["--wait-pid", String(waitPID)] }
        if locations.isTest { arguments += ["--target-dir", locations.inputMethods.deletingLastPathComponent().path] }
        if reopenSettings { arguments.append("--reopen-settings") }
        if let simulateFailure { arguments += ["--simulate-failure", simulateFailure] }
        try FileManager.default.createDirectory(at: locations.log.deletingLastPathComponent(), withIntermediateDirectories: true)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var files: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&files)
        defer { posix_spawn_file_actions_destroy(&files) }
        posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&files, 1, locations.log.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&files, 1, 2)
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &files, &attributes, argv, environ)
        guard status == 0 else { throw UpdateError.unpack("couldn't start the update helper (\(String(cString: strerror(status))))") }
        return pid
    }
}

/// Runs a tool to its end (or kills it after `timeout`); stdout and stderr together, trimmed.
enum UpdateProcess {
    struct Result {
        var status: Int32
        var output: String
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-update-\(UUID().uuidString).out")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: output) }
        guard let handle = try? FileHandle(forWritingTo: output) else { return Result(status: -1, output: "can't write its output") }
        defer { try? handle.close() }
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Result(status: -1, output: error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return Result(status: -1, output: "timed out after \(Int(timeout)) s")
        }
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        let status = process.terminationReason == .uncaughtSignal ? -process.terminationStatus : process.terminationStatus
        return Result(status: status, output: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Helper

/// `--apply-update STAGED [--wait-pid PID] [--target-dir DIR] [--reopen-settings] [--simulate-failure STEP]`:
/// step 3, run by the input method (its own executable, as it is installed) on an update it staged.
enum UpdateHelper {
    static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static func say(_ text: String) {
        print("\(ISO8601DateFormatter().string(from: Date())) [\(getpid())] \(text)")
        fflush(stdout)
    }

    static func run(_ arguments: [String]) -> Int32 {
        func option(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let path = arguments.first, !path.hasPrefix("--") else {
            printError("usage: --apply-update STAGED [--wait-pid PID] [--target-dir DIR] [--reopen-settings] [--simulate-failure after-swap]")
            return 2
        }
        let locations = option("--target-dir").map { UpdateLocations.test(root: URL(fileURLWithPath: $0)) } ?? .real
        let staged = URL(fileURLWithPath: path).standardizedFileURL
        // Only an update staged where the input method stages them (a folder of the user's, not any folder).
        guard staged.deletingLastPathComponent().resolvingSymlinksInPath().path == locations.work.resolvingSymlinksInPath().path,
              staged.lastPathComponent.hasPrefix("update-") else {
            printError("--apply-update: \(staged.path) isn't in \(locations.work.path)")
            return 2
        }
        // A failure on purpose, for the tests' rollback: never on the user's own install.
        let simulate = locations.isTest ? option("--simulate-failure") : nil
        return apply(staged: staged, locations: locations, waitPID: option("--wait-pid").flatMap { pid_t($0) },
                     reopenSettings: arguments.contains("--reopen-settings"), simulateFailure: simulate)
    }

    static func apply(staged: URL, locations: UpdateLocations, waitPID: pid_t?, reopenSettings: Bool, simulateFailure: String?) -> Int32 {
        let manager = FileManager.default
        let new = UpdatePayload(inputMethod: staged.appendingPathComponent("new/\(Updater.inputMethodName)", isDirectory: true),
                                settingsApp: staged.appendingPathComponent("new/\(Updater.settingsAppName)", isDirectory: true))
        let from = locations.installedVersion ?? "none"
        let to = UpdateStaging.version(of: new.inputMethod) ?? "?"
        say("updating AllInOneIME \(from) → \(to) in \(locations.inputMethods.path)\(locations.isTest ? " (test)" : "")")
        var keepStaged = false

        func finish(_ error: String?) -> Int32 {
            if let error { say("✗ \(error)") } else { say("✓ AllInOneIME \(to) is installed") }
            do {
                try UpdateResult(from: from, to: to, ok: error == nil, error: error).write(to: locations.result)
            } catch {
                say("could not write \(locations.result.path): \(error)")
            }
            if !keepStaged { try? manager.removeItem(at: staged) }
            // The input method back (new or previous), with its settings window if it was open: macOS would only
            // start it on the next keystroke, and the menu bar icon is its. Already started again by macOS, it's left
            // alone unless the settings window is wanted (`open` then only shows it).
            if !locations.isTest, BundleSwap.exists(locations.inputMethod),
               reopenSettings || inputMethodPIDs(locations, staged: staged).isEmpty {
                let open = UpdateProcess.run("/usr/bin/open", [locations.inputMethod.path] + (reopenSettings ? ["--args", "--settings"] : []), timeout: 30)
                say("started the input method again (\(open.status))")
            }
            return error == nil ? 0 : 1
        }

        if let waitPID { waitForExit(waitPID) }
        if !locations.isTest { stopInputMethod(locations, staged: staged) }

        // Checked again: they waited in a folder of the user's since the input method checked them.
        do {
            for (app, id) in [(new.inputMethod, Updater.bundleID), (new.settingsApp, Updater.settingsBundleID)] {
                guard NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String == id else {
                    throw UpdateError.invalidApp("\(app.lastPathComponent) is missing")
                }
                try CodeSignature.check(app, identifier: id, team: nil)
            }
        } catch {
            return finish("the staged update doesn't check out (\(error)); nothing was changed")
        }

        let swap: BundleSwap
        do {
            swap = try BundleSwap.perform(placing: [(new.inputMethod, locations.inputMethod), (new.settingsApp, locations.settingsApp)],
                                          replacing: [locations.inputMethod, locations.settingsApp],
                                          aside: staged.appendingPathComponent("previous", isDirectory: true))
            say("moved the new apps in; the previous ones wait in \(swap.aside.path)")
        } catch let failure as BundleSwap.Failure {
            keepStaged = true
            return finish(failure.localizedDescription)
        } catch {
            return finish("couldn't move the new apps in (\(error.localizedDescription)); the previous ones are back")
        }

        do {
            if simulateFailure == "after-swap" { throw UpdateError.invalidApp("a failure simulated after the swap (--simulate-failure)") }
            // The new input method starts where it is now (its libraries load, its signature holds).
            try UpdateStaging.launchCheck(locations.inputMethod, version: to)
            if !locations.isTest {
                stopInputMethod(locations, staged: staged)  // in case macOS started the previous one again meanwhile
                _ = UpdateProcess.run(lsregister, ["-f", locations.inputMethod.path, locations.settingsApp.path], timeout: 60)
                let register = UpdateProcess.run(locations.inputMethod.appendingPathComponent("Contents/MacOS/AllInOneIME").path,
                                                 ["--register"], timeout: 300)
                say("--register (\(register.status)):\n\(register.output)")
                guard register.status == 0 else { throw UpdateError.invalidApp("registering \(to) failed (\(register.status))") }
            }
        } catch {
            // What went wrong, without the "nothing was changed" of a check before the swap: here it's the rollback's.
            var reason = error.localizedDescription
            if case let UpdateError.invalidApp(detail) = error { reason = detail }
            say("rolling back: \(reason)")
            // The new input method may have started meanwhile (registering it lets macOS start it): stopped first.
            if !locations.isTest { stopInputMethod(locations, staged: staged) }
            do {
                try swap.rollBack(reason: reason)
            } catch {
                keepStaged = true
                return finish(error.localizedDescription)
            }
            if !locations.isTest {
                _ = UpdateProcess.run(lsregister, ["-f", locations.inputMethod.path, locations.settingsApp.path], timeout: 60)
                let register = UpdateProcess.run(locations.inputMethod.appendingPathComponent("Contents/MacOS/AllInOneIME").path,
                                                 ["--register"], timeout: 300)
                say("previous version registered again (\(register.status))")
            }
            return finish("\(reason); AllInOneIME \(from) is back")
        }
        swap.commit()
        return finish(nil)
    }

    /// Waits for the input method that started this helper to quit (it does once the helper runs); ends it
    /// if it hangs.
    static func waitForExit(_ pid: pid_t) {
        func alive() -> Bool { kill(pid, 0) == 0 }
        var deadline = Date().addingTimeInterval(15)
        while alive(), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        guard alive() else { return say("the input method (\(pid)) has quit") }
        say("the input method (\(pid)) is still running: stopping it")
        kill(pid, SIGTERM)
        deadline = Date().addingTimeInterval(3)
        while alive(), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if alive() { kill(pid, SIGKILL) }
    }

    /// Stops the input method started from the installed copy (macOS may start it again at any keystroke), not
    /// this helper and not a copy elsewhere (a developer's build, a test's).
    static func stopInputMethod(_ locations: UpdateLocations, staged: URL) {
        let pids = inputMethodPIDs(locations, staged: staged)
        guard !pids.isEmpty else { return }
        say("stopping the input method (\(pids.map(String.init).joined(separator: ", ")))")
        for pid in pids { kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(2)
        while pids.contains(where: { kill($0, 0) == 0 }), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// The input method's processes started from the installed copy (or from it where it waits aside), not this one.
    static func inputMethodPIDs(_ locations: UpdateLocations, staged: URL) -> [pid_t] {
        let installed = locations.inputMethod.resolvingSymlinksInPath().path
        let aside = staged.resolvingSymlinksInPath().path + "/"
        return NSRunningApplication.runningApplications(withBundleIdentifier: Updater.bundleID).compactMap { app -> pid_t? in
            guard app.processIdentifier != getpid(), !app.isTerminated, let path = app.bundleURL?.resolvingSymlinksInPath().path,
                  path == installed || path.hasPrefix(aside) else { return nil }
            return app.processIdentifier
        }
    }
}

// MARK: - Developer commands

/// `--check-update` and `--install-update`: what About does, from a terminal, and against a test server (another
/// key, plain http to this Mac) and a test install (`--target-dir`).
enum UpdateCommands {
    static func option(_ name: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    static func updater(_ arguments: [String], currentVersion: String) -> Updater? {
        var updater = Updater(currentVersion: currentVersion, allowsLocalHTTP: true)
        if let url = option("--manifest-url", in: arguments) {
            guard let parsed = URL(string: url) else { printError("--manifest-url: not a URL"); return nil }
            updater.manifestURL = parsed
        }
        if let key = option("--key", in: arguments) {
            guard let raw = Data(base64Encoded: key) else { printError("--key: not base64"); return nil }
            updater.publicKey = raw
        }
        return updater
    }

    /// Runs `work` while the main thread waits (these commands have no run loop of their own otherwise).
    static func wait<T>(_ work: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let box = ResultBox<T>()
        Task.detached { box.set(await Result { try await work() }) }
        while box.get() == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return box.get()!
    }

    static func check(_ arguments: [String]) -> Int32 {
        guard let updater = updater(arguments, currentVersion: AppVersion.string) else { return 2 }
        switch wait({ try await updater.check() }) {
        case let .success(found):
            let m = found.manifest
            print("manifest:    \(updater.manifestURL.absoluteString) (signature checks out)")
            print("latest:      \(m.version) (build \(m.build)), macOS \(m.minimumSystemVersion) or later")
            print("download:    \(m.url) (\(m.size) bytes, sha256 \(m.sha256))")
            if let notes = m.notesURL { print("notes:       \(notes)") }
            if let summary = m.summary(chinese: false) { print("summary:     \(summary)") }
            switch found.availability {
            case .upToDate: print("this:        \(AppVersion.string), up to date")
            case .available: print("this:        \(AppVersion.string), update available")
            case .needsNewerSystem: print("this:        \(AppVersion.string); the update needs a newer macOS (this is \(updater.systemVersion))")
            }
            return 0
        case let .failure(error):
            printError("✗ \(UpdateText.describe(error))")
            return 1
        }
    }

    /// `--install-update [--manifest-url URL] [--key BASE64] [--target-dir DIR] [--detach] [--simulate-failure STEP]`.
    /// With `--target-dir`: the install in DIR/Input Methods and DIR/Applications is updated, as if it were the
    /// user's, without registering anything; the version it has is the one compared. Without: only from the
    /// installed copy itself. `--detach`: this process quits once the helper runs, as the input method does, and
    /// the helper waits for it; otherwise it waits for the helper and prints the result.
    static func install(_ arguments: [String]) -> Int32 {
        let target = option("--target-dir", in: arguments)
        let locations = target.map { UpdateLocations.test(root: URL(fileURLWithPath: $0).standardizedFileURL) } ?? .real
        guard locations.isTest || UpdateLocations.runningIsInstalled else {
            printError("✗ \(UpdateText.describe(UpdateError.notInstalled)) (or pass --target-dir for a test install)")
            return 1
        }
        guard let updater = updater(arguments, currentVersion: locations.installedVersion ?? AppVersion.string) else { return 2 }
        let detach = arguments.contains("--detach")
        let started = Date()
        let staged = wait { () async throws -> UpdateStaging.Staged in
            let found = try await updater.fetchManifest()
            print("manifest:    \(found.manifest.version) (build \(found.manifest.build)), signature checks out")
            let staged = try await UpdateStaging.stage(found.manifest, updater: updater, locations: locations) { share in
                FileHandle.standardError.write(Data(String(format: "\rdownloading %3.0f%%", share * 100).utf8))
            }
            FileHandle.standardError.write(Data("\n".utf8))
            return staged
        }
        switch staged {
        case let .failure(error):
            printError("✗ \(UpdateText.describe(error))")
            return 1
        case let .success(staged):
            print(String(format: "staged:      %@ (downloaded, size and sha256 match, apps checked, starts) in %.1fs",
                         staged.folder.path, Date().timeIntervalSince(started)))
            try? FileManager.default.removeItem(at: locations.result)
            do {
                let pid = try UpdateStaging.launchHelper(staged, executable: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                                         locations: locations, waitPID: detach ? getpid() : nil, reopenSettings: false,
                                                         simulateFailure: option("--simulate-failure", in: arguments))
                print("helper:      pid \(pid), log \(locations.log.path)")
                if detach { return 0 }
                var status: Int32 = 0
                waitpid(pid, &status, 0)
            } catch {
                printError("✗ \(UpdateText.describe(error))")
                return 1
            }
            guard let result = UpdateResult.read(locations.result) else {
                printError("✗ the helper left no result (\(locations.result.path)); see \(locations.log.path)")
                return 1
            }
            print(result.ok ? "updated:     \(result.from) → \(result.to)" : "✗ not updated (\(result.from) → \(result.to)): \(result.error ?? "?")")
            return result.ok ? 0 : 1
        }
    }
}

final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, Error>?
    func set(_ result: Result<T, Error>) { lock.withLock { value = result } }
    func get() -> Result<T, Error>? { lock.withLock { value } }
}

extension Result where Failure == Error {
    init(catching work: () async throws -> Success) async {
        do { self = .success(try await work()) } catch { self = .failure(error) }
    }
}

// MARK: - Controller

/// The updates as the settings, the input menu and the menu bar panel show them. Main thread.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    enum State: Equatable {
        /// Not checked since launch, nothing known.
        case idle
        case checking
        case upToDate
        case available(UpdateManifest)
        case needsNewerSystem(UpdateManifest)
        /// The share downloaded (nil: starting).
        case downloading(UpdateManifest, Double?)
        /// Checked and handed to the helper: the input method quits and starts again in a moment.
        case installing(UpdateManifest)
        /// A check or an update that didn't work, with the update known before, if any.
        case failed(String, UpdateManifest?)

        var manifest: UpdateManifest? {
            switch self {
            case let .available(m), let .needsNewerSystem(m), let .downloading(m, _), let .installing(m): return m
            case let .failed(_, m): return m
            case .idle, .checking, .upToDate: return nil
            }
        }
    }

    @Published var state: State = .idle
    /// When a check last got an answer.
    @Published var lastChecked: Date?
    /// What the last update did, shown on the About page after the restart.
    @Published var lastResult: UpdateResult?

    var updater = Updater()
    var locations = UpdateLocations.real
    var defaults = UserDefaults.standard
    /// Only the installed copy updates itself; any other (a developer's build) links to the download instead.
    var updatesInPlace = UpdateLocations.runningIsInstalled
    var now: () -> Date = Date.init
    private var task: Task<Void, Never>?

    static let releasesPage = URL(string: "https://github.com/MicroZ-LLC/AllInOneIME/releases/latest")!
    private static let manifestKey = "updateManifest", signatureKey = "updateManifestSignature"
    private static let successKey = "updateLastSuccess", attemptKey = "updateLastAttempt"

    private init() {}

    /// A newer version this Mac can install (the panel's and the menu's notice).
    var available: UpdateManifest? {
        if case let .available(m) = state { return m }
        return nil
    }

    /// At launch: what the last update did, the update known from the last check (its signature checked
    /// again), and a check soon if one is due.
    func start() {
        if let result = UpdateResult.read(locations.result) {
            lastResult = result
            try? FileManager.default.removeItem(at: locations.result)
            log.notice("update \(result.from, privacy: .public) → \(result.to, privacy: .public): \(result.ok ? "installed" : (result.error ?? "failed"), privacy: .public)")
        }
        clearLeftovers()
        lastChecked = defaults.object(forKey: Self.successKey) as? Date
        if let data = defaults.data(forKey: Self.manifestKey), let signature = defaults.data(forKey: Self.signatureKey),
           let manifest = try? Updater.verify(manifest: data, signature: signature, publicKey: updater.publicKey) {
            show(manifest)
        }
        // Not while the input method is still starting up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
    }

    /// Updates staged by a helper that never ran (the Mac restarted in between): not a second copy of the apps.
    /// Only those an hour old: macOS may start the input method while a helper is still at work on one.
    private func clearLeftovers() {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(at: locations.work, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for folder in folders where folder.lastPathComponent.hasPrefix("update-") {
            // One whose previous apps couldn't be put back is the user's to recover: kept (the result named it).
            guard !BundleSwap.exists(folder.appendingPathComponent("previous")),
                  let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now().timeIntervalSince(modified) > 3600 else { continue }
            try? manager.removeItem(at: folder)
        }
    }

    /// A check in the background if one is due (`UpdateSchedule`): quick enough for a text field's activation.
    func checkIfDue() {
        guard task == nil, UpdateSchedule.isDue(now: now(), lastSuccess: defaults.object(forKey: Self.successKey) as? Date,
                                                lastAttempt: defaults.object(forKey: Self.attemptKey) as? Date,
                                                enabled: LiveConfig.current.checkForUpdates) else { return }
        check(userInitiated: false)
    }

    /// Asks allinoneime.com. A check the user asked for shows its progress and its errors; one in the background
    /// changes nothing on screen unless it finds something.
    func check(userInitiated: Bool) {
        guard task == nil else { return }
        let before = state
        if userInitiated { state = .checking }
        defaults.set(now(), forKey: Self.attemptKey)
        let updater = updater
        task = Task { [weak self] in
            let result = await Result { try await updater.check() }
            guard let self else { return }
            self.task = nil
            switch result {
            case let .success(found):
                self.lastChecked = self.now()
                self.defaults.set(self.lastChecked, forKey: Self.successKey)
                self.defaults.set(found.data, forKey: Self.manifestKey)
                self.defaults.set(found.signature, forKey: Self.signatureKey)
                self.show(found.manifest)
                log.notice("update check: \(found.manifest.version, privacy: .public) (\(String(describing: found.availability), privacy: .public))")
            case let .failure(error):
                log.error("update check failed: \(String(describing: error), privacy: .public)")
                self.state = userInitiated ? .failed(UpdateText.describe(error), before.manifest) : before
            }
        }
    }

    private func show(_ manifest: UpdateManifest) {
        switch updater.availability(of: manifest) {
        case .available: state = .available(manifest)
        case .needsNewerSystem: state = .needsNewerSystem(manifest)
        case .upToDate: state = .upToDate
        }
    }

    /// The Update button: downloads, checks and stages the update, hands it to the helper and quits; the input
    /// method starts again as the new version (or, if anything fails, as this one).
    func install() {
        guard task == nil, let manifest = state.manifest, updater.availability(of: manifest) == .available else { return }
        guard updatesInPlace else {
            NSWorkspace.shared.open(Self.releasesPage)
            return
        }
        state = .downloading(manifest, nil)
        let (updater, locations) = (updater, locations)
        let reopenSettings = SettingsWindow.shared.isVisible
        task = Task { [weak self] in
            let staged = await Result {
                try await UpdateStaging.stage(manifest, updater: updater, locations: locations) { share in
                    Task { @MainActor in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(manifest, share)
                    }
                }
            }
            guard let self else { return }
            switch staged {
            case let .success(staged):
                do {
                    try UpdateStaging.launchHelper(staged, executable: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                                   locations: locations, waitPID: getpid(), reopenSettings: reopenSettings)
                    self.state = .installing(manifest)
                    log.notice("update \(manifest.version, privacy: .public) staged; quitting for the helper")
                    // A moment to say so, then quit: the helper waits for this process to end.
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    NSApp.terminate(nil)
                } catch {
                    try? FileManager.default.removeItem(at: staged.folder)
                    self.state = .failed(UpdateText.describe(error), manifest)
                    self.task = nil
                }
            case let .failure(error):
                log.error("update failed: \(String(describing: error), privacy: .public)")
                self.state = .failed(UpdateText.describe(error), manifest)
                self.task = nil
            }
        }
    }
}

// MARK: - Text

enum UpdateText {
    /// An error as the About page says it.
    static func describe(_ error: Error) -> String {
        guard let error = error as? UpdateError else { return error.localizedDescription }
        switch error {
        case let .unreachable(host): return tr("连不上 \(host)", "Can't reach \(host)")
        case let .http(status, file): return tr("更新服务器对 \(file) 返回了 HTTP \(status)", "The update server answered HTTP \(status) for \(file)")
        case .missingSignature, .badSignature:
            return tr("更新信息的签名不对，可能正在发布中，过几分钟再试。没有做任何改动。",
                      "The update information failed its signature check (it may be mid-release: try again in a few minutes). Nothing was changed.")
        case .unsupportedSchema, .malformedManifest:
            return tr("读不懂更新信息，请从网站下载新版本。", "The update information can't be read; please download the new version from the website.")
        case let .notNewer(version): return tr("\(version) 不比现在的版本新，不会安装。", "\(version) isn't newer than this version; it won't be installed.")
        case let .needsNewerSystem(version): return tr("这个更新需要 macOS \(version) 或更新。", "This update needs macOS \(version) or later.")
        case .invalidManifest, .tooLarge, .sizeMismatch, .hashMismatch:
            return tr("下载的文件和签名的更新信息对不上，没有做任何改动。", "The download doesn't match the signed update information. Nothing was changed.")
        case .unpack, .invalidApp:
            return tr("更新包检查没通过，没有做任何改动：", "The update didn't pass its checks; nothing was changed: ") + (error.errorDescription ?? "")
        case .notInstalled:
            return tr("这份 AllInOneIME 不是装在 ~/Library/Input Methods 里的那份，请下载安装程序。",
                      "This copy of AllInOneIME isn't the one in ~/Library/Input Methods; please download the installer.")
        case .cancelled: return tr("已取消", "Cancelled")
        }
    }

    static func available(_ version: String) -> String {
        tr("AllInOneIME \(version) 可以更新了", "AllInOneIME \(version) is available")
    }

    static func checked(_ date: Date?, now: Date) -> String {
        guard let date else { return tr("还没检查过", "Not checked yet") }
        return tr("上次检查：", "Last checked: ") + DashboardText.ago(date, now: now, chinese: UIText.chinese)
    }
}

// MARK: - About page

/// The About page's Updates card: what's known, the button that fits, and the switch for checking by itself.
struct UpdateSection: View {
    @ObservedObject var updates: UpdateController
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            if let result = updates.lastResult { resultRow(result) }
            status
            Toggle(isOn: Binding(get: { model.config.checkForUpdates }, set: { model.config.checkForUpdates = $0; model.save() })) {
                titled(tr("自动检查更新", "Check for updates automatically"),
                       tr("每天在后台看一次有没有新版本，有就在这里和菜单栏面板里提一句；只有你点「更新」才会安装。",
                          "Once a day, in the background; a new version is mentioned here and in the menu bar panel, and only installed when you click Update."))
            }
            .disabled(!model.canSave)
        } header: {
            Text(tr("更新", "Updates")).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).padding(.top, 6)
        }
    }

    @ViewBuilder private var status: some View {
        let now = updates.now()
        switch updates.state {
        case .idle, .upToDate:
            LabeledContent {
                Button(tr("检查更新", "Check for Updates")) { updates.check(userInitiated: true) }
            } label: {
                titled(updates.state == .upToDate ? tr("已经是最新版本", "AllInOneIME is up to date") : tr("软件更新", "Software Update"),
                       UpdateText.checked(updates.lastChecked, now: now))
            }
        case .checking:
            LabeledContent {
                ProgressView().controlSize(.small)
            } label: {
                titled(tr("正在检查更新…", "Checking for updates…"), UpdateText.checked(updates.lastChecked, now: now))
            }
        case let .available(m):
            LabeledContent {
                Button(updates.updatesInPlace ? tr("更新到 \(m.version)", "Update to \(m.version)") : tr("下载…", "Download…")) {
                    updates.install()
                }
                .buttonStyle(.borderedProminent)
            } label: {
                titled(UpdateText.available(m.version), details(m, extra: updates.updatesInPlace
                    ? tr("下载、校验后安装，输入法自动重启；设置、语言包、学到的词和扩展都保留。",
                         "Downloaded, verified and installed; the input method restarts by itself. Your settings, language packs, learned words and extensions stay.")
                    : tr("这份不是装好的那份（~/Library/Input Methods），请下载安装程序。",
                         "This copy isn't the installed one (~/Library/Input Methods); download the installer instead.")))
            }
            notesLink(m)
        case let .needsNewerSystem(m):
            LabeledContent {
                Button(tr("检查更新", "Check for Updates")) { updates.check(userInitiated: true) }
            } label: {
                titled(tr("AllInOneIME \(m.version) 需要 macOS \(m.minimumSystemVersion) 或更新", "AllInOneIME \(m.version) needs macOS \(m.minimumSystemVersion) or later"),
                       details(m, extra: UpdateText.checked(updates.lastChecked, now: now)))
            }
        case let .downloading(m, share):
            LabeledContent {
                ProgressView(value: share ?? 0).frame(width: 140)
            } label: {
                titled(tr("正在下载 \(m.version)…", "Downloading \(m.version)…"),
                       share.map { tr("已下载 \(Int($0 * 100))%", "\(Int($0 * 100))% downloaded") } ?? tr("正在连接…", "Connecting…"))
            }
        case let .installing(m):
            LabeledContent {
                ProgressView().controlSize(.small)
            } label: {
                titled(tr("正在安装 \(m.version)…", "Installing \(m.version)…"),
                       tr("AllInOneIME 马上重启，设置窗口会再打开。", "AllInOneIME restarts in a moment, and the settings window opens again."))
            }
        case let .failed(message, m):
            LabeledContent {
                Button(tr("再试一次", "Try Again")) {
                    if m != nil, case .available = updates.updater.availability(of: m!) { updates.install() } else { updates.check(userInitiated: true) }
                }
            } label: {
                titled(m.map { tr("没能更新到 \($0.version)", "Couldn't update to \($0.version)") } ?? tr("没能检查更新", "Couldn't check for updates"),
                       message)
            }
            .foregroundStyle(.primary)
            if let m { notesLink(m) }
        }
    }

    private func resultRow(_ result: UpdateResult) -> some View {
        Label {
            Text(result.ok ? tr("已从 \(result.from) 更新到 \(result.to)。", "Updated from \(result.from) to \(result.to).")
                           : tr("更新到 \(result.to) 没成功，仍是 \(result.from)：", "The update to \(result.to) didn't go in; this is still \(result.from): ")
                             + (result.error ?? ""))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.ok ? Color.green : Color.orange)
        }
    }

    private func notesLink(_ m: UpdateManifest) -> some View {
        LabeledContent(tr("更新内容", "Release notes")) {
            if let notes = m.notesURL.flatMap(URL.init(string:)), notes.scheme == "https" {
                Link(tr("在 GitHub 上看", "Read on GitHub"), destination: notes)
            }
        }
    }

    private func details(_ m: UpdateManifest, extra: String) -> String {
        [m.summary(chinese: UIText.chinese), extra].compactMap { $0 }.joined(separator: "\n")
    }

    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension UpdateManifest {
    /// A made-up release for the About page's images (`--settings-image … update=available`) and the self-test.
    static func sample(version: String = "0.7.0", minimumSystem: String = "14.0") -> UpdateManifest {
        let json = """
            {"schema":1,"version":"\(version)","build":"99","minimumSystemVersion":"\(minimumSystem)",
             "url":"https://github.com/MicroZ-LLC/AllInOneIME/releases/download/v\(version)/AllInOneIME-\(version)-update.zip",
             "sha256":"\(String(repeating: "0", count: 64))","size":1,
             "notesURL":"https://github.com/MicroZ-LLC/AllInOneIME/releases/tag/v\(version)",
             "summary":{"en":"Updates from inside the app, with one click.","zh":"在应用里一键更新。"}}
            """
        return try! JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
    }
}
