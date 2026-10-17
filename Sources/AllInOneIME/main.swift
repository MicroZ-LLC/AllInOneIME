import AllInOneIMECore
import AllInOneIMECore
import AllInOneIMERime
import AppKit
import Carbon
import InputMethodKit

let usage = """
    AllInOneIME input method. Launched by macOS without arguments; developer commands:
      --register        register this bundle with Text Input Sources, enable it and add it to
                        your input sources
      --disable         disable, and remove it from your input sources
      --status          show registration, process and configuration status
      --settings        run as the input method and open the settings window
      --selftest [DIR] [--rime-data DATA]
                        drive the input controller (real Rime engine on DATA, else the installed
                        Chinese pack; live Bedrock call) with a fake text field; writes panel snapshots
                        to DIR (default /tmp/allinoneime-selftest)
      --install-pack ID [--library URL] [--key BASE64] [--packs-dir DIR]
                        download and install a language pack (zh-pinyin) as Settings does; plain http
                        is allowed to this Mac only, for a test server
      --adopt-pack DATA [VERSION]
                        install the Chinese pack from a Rime data folder (ThirdParty/rime-data, or an
                        older app's Contents/SharedSupport/rime) without downloading
      --version         print this bundle's version
      --check-update [--manifest-url URL] [--key BASE64]
                        check for a new version as Settings → About does (signed update.json); plain
                        http is allowed to this Mac only, for a test server
      --install-update [--manifest-url URL] [--key BASE64] [--target-dir DIR] [--detach]
                        download, verify and install the update as About's Update button does; with
                        --target-dir, into DIR/Input Methods and DIR/Applications (a test install:
                        nothing is registered, the user's apps are left alone)
      --add-source URL [--path FOLDER] [--branch BRANCH] [--pin TAG-OR-COMMIT]
                        clone an extension source (ssh://, git@host:, https://, file://) with your
                        git, print what it holds and runs, and enable it (running this is the consent)
      --update-sources  fetch every extension source that isn't pinned, fast-forward it, print what changed
      --list-extensions list the extensions' commands (name, output, source or folder) and those left out
                        (these three also take --config FILE and --sources-dir DIR, for tests)
    """

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Where level one keeps its data: the Chinese language pack's dictionaries, learned words per user,
/// and the Lua scripts the pack's schemas use (in the bundle: packs are data only).
enum RimeDirectories {
    /// The self-test's data folder instead of the pack (`--rime-data`).
    static var override: URL?

    /// The installed Chinese pack's folder; nil until it is downloaded.
    static var shared: URL? {
        if let override { return override }
        let store = LanguagePackStore()
        return store.installed(.chinesePinyin) == nil ? nil : store.folder(.chinesePinyin)
    }
    /// The app's copy of rime-ice's Lua scripts, linked into the pack (`LanguagePackStore.linkCode`).
    static var code: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("rime-lua")
    }
    static var user: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME/Rime")
    }
    static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AllInOneIME")
    }
}

/// Fuzzy pinyin (`FuzzyPinyin`) in the Rime user folder: the patch for the pairs the config turns on.
enum RimeFuzzy {
    /// Writes (or removes) the patch; nil when it couldn't. `.written` and `.removed` need a deployment.
    @discardableResult
    static func write(_ ids: [String]) -> FuzzyPinyin.Outcome? {
        guard let shared = RimeDirectories.shared else { return nil }
        do {
            let outcome = try FuzzyPinyin.apply(ids, schema: shared.appendingPathComponent("rime_ice.schema.yaml"),
                                                userDir: RimeDirectories.user)
            if outcome == .userFile { log.notice("fuzzy pinyin not applied: the Rime folder has the user's own \(FuzzyPinyin.fileName, privacy: .public)") }
            return outcome
        } catch {
            log.error("could not write the fuzzy pinyin patch: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Changed in the settings: written, and Rime deployed again when it changed (about a second).
    @discardableResult
    static func apply(_ ids: [String]) -> FuzzyPinyin.Outcome? {
        let outcome = write(ids)
        if outcome == .written || outcome == .removed { RimeService.shared.redeploy() }
        return outcome
    }
}

/// Opens the settings window when the input method is "opened" again (the AllInOneIME Settings app does
/// that). The text input system never sends reopen events, so typing is unaffected.
final class IMEAppDelegate: NSObject, NSApplicationDelegate {
    static let shared = IMEAppDelegate()

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { SettingsWindow.shared.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        CommandRunner.stopAll()  // what script extensions started doesn't outlive the input method
    }
}

/// SIGTERM (an update, `make install`, logging out): the programs running for script extensions, and what they
/// started, are stopped first (`CommandRunner.stopAll`, at most half a second), then the input method ends, as
/// the signal's default would end it. Handled on a queue of its own, not in a signal handler and not on the main
/// thread: a main thread that hangs doesn't keep it alive, and a hard exit is armed in case stopping hangs too.
private let terminationSignal: DispatchSourceSignal = {
    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: DispatchQueue(label: "AllInOneIME.terminate"))
    source.setEventHandler {
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { _exit(0) }
        CommandRunner.stopAll()
        _exit(0)
    }
    return source
}()

func runServer(showSettings: Bool = false) -> Never {
    let app = NSApplication.shared
    app.delegate = IMEAppDelegate.shared
    guard let name = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
          let server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
    else {
        log.fault("could not start IMKServer (is the binary inside AllInOneIME.app?)")
        printError("could not start IMKServer; run from inside AllInOneIME.app")
        exit(1)
    }
    log.info("IMKServer started: \(name, privacy: .public)")
    terminationSignal.resume()
    // The login shell's PATH, read once in the background: a script extension's first run doesn't wait for it.
    DispatchQueue.global(qos: .utility).async { _ = ShellEnvironment.current }
    // Older versions kept their sentence mode switch here (first as aiEnabled); nothing reads it now.
    for key in ["sentenceMode", "aiEnabled"] { UserDefaults.standard.removeObject(forKey: key) }
    // Background @agent tasks: notifications, and tasks from before a restart watched again.
    MainActor.assumeIsolated { AgentMonitor.shared.setUp() }
    // The menu bar icon (on by default) and its panel, once the server and Rime are up. The notes @note
    // saves are recorded whether the panel is shown or not, so that it lists them when it drops down.
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            FloatingPanel.shared.recordSavedNotes()
            MenuBarIcon.shared.apply(LiveConfig.current.menuBarIcon)
        }
    }
    if showSettings {
        DispatchQueue.main.async { MainActor.assumeIsolated { SettingsWindow.shared.show() } }
    }
    // librime on the Chinese pack if it's installed; an upgraded user who had Chinese gets it downloaded.
    MainActor.assumeIsolated { LanguagePackManager.shared.launch() }
    // What the last update did, and a look for the next one if a day has passed (in the background).
    MainActor.assumeIsolated { UpdateController.shared.start() }
    // Extension sources: checked about 30 s from now, then once a day, if they check by themselves (only ever noted).
    MainActor.assumeIsolated { ExtensionSourceController.shared.start() }
    withExtendedLifetime(server) { app.run() }
    exit(0)
}

/// Logs once when librime has finished deploying after launch (keys pass through until then).
final class RimeReadinessLogger: NSObject {
    static let shared = RimeReadinessLogger()
    private let started = Date()

    func start() {
        Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(check(_:)), userInfo: nil, repeats: true)
    }

    @objc private func check(_ timer: Timer) {
        let elapsed = Date().timeIntervalSince(started)
        if RimeService.shared.isReady {
            timer.invalidate()
            log.info("Rime ready \(elapsed, format: .fixed(precision: 2))s after launch")
        } else if elapsed > 300 {
            timer.invalidate()
            log.error("Rime still deploying after 300s")
        }
    }
}

/// Deploys the Chinese pack into the user's directory now, so the first keystroke after installing
/// doesn't wait for it. Without the pack there is nothing to deploy: English needs no dictionaries.
func prepareDictionaries() {
    guard RimeDirectories.shared != nil else {
        print("dictionaries: no Chinese pack (English only; Chinese is added in Settings → Input with +)")
        return
    }
    let started = Date()
    MainActor.assumeIsolated { RimeStartup.start() }
    guard RimeService.shared.isStarted else {
        printError("could not start Rime")
        return
    }
    let ready = RimeService.shared.waitUntilReady(timeout: 120)
    print(ready
        ? String(format: "dictionaries: ready (%.1fs)", Date().timeIntervalSince(started))
        : "dictionaries: still deploying; the input method finishes it on first use")
}

func register() -> Int32 {
    let url = Bundle.main.bundleURL
    guard url.pathExtension == "app" else {
        printError("run --register from inside AllInOneIME.app")
        return 1
    }
    let status = InputSourceRegistrar.register(bundleURL: url)
    guard status == 0 else {
        printError("TISRegisterInputSource failed: \(status)")
        return 1
    }
    guard let source = InputSourceRegistrar.waitForSource() else {
        printError("registered, but input source \(InputSourceRegistrar.sourceID) did not appear")
        return 1
    }
    if !InputSourceRegistrar.bool(source, kTISPropertyInputSourceIsEnabled) {
        // Recent macOS versions don't let installers enable third-party keyboard input methods:
        // register/enable succeed, System Settings → Keyboard opens, and the user adds it there.
        let enableStatus = TISEnableInputSource(source)
        guard enableStatus == 0 else {
            printError("TISEnableInputSource failed: \(enableStatus)")
            return 1
        }
    }
    let enabled = InputSourceRegistrar.waitUntilEnabled(timeout: 2)
    if enabled {
        // Enabled by a program, it isn't in the user's input sources, which Ctrl+Space goes by:
        // keep it there as well (see InputSourceList).
        switch InputSourceRegistrar.updateUserList({ InputSourceList.adding(InputSourceRegistrar.bundleID, to: $0) }) {
        case .written: print("input list:  added to your input sources (Ctrl+Space reaches it now)")
        case .failed: printError("could not add it to your input sources (\(InputSourceList.domain))")
        case .unchanged: break
        }
    }
    prepareDictionaries()
    _ = printStatus()
    if !enabled {
        // In the interface language (the setting, else the system's): the menu names are the system's.
        UIText.choice = (try? Config.load())?.uiLanguage
        print(tr("""

            macOS 需要你手动添加一次（“键盘”设置应该已经打开）：
              系统设置 → 键盘 → 文字输入 › 输入法「编辑…」→ 左下角 + → 英语 → AllInOneIME → 添加
            之后用 Ctrl+Space 或 🌐 键切换到 AllInOneIME。
            """, """

            macOS needs you to add it once (Keyboard settings should have opened):
              System Settings → Keyboard → Text Input › Input Sources "Edit…" → + at the bottom left
              → English → AllInOneIME → Add
            Then switch to AllInOneIME with Ctrl+Space or the 🌐 key.
            """))
    }
    return 0
}

func disable() -> Int32 {
    var status: OSStatus = 0
    if let source = InputSourceRegistrar.source() {
        status = TISDisableInputSource(source)
        print(status == 0 ? "disabled \(InputSourceRegistrar.sourceID)" : "TISDisableInputSource failed: \(status)")
    } else {
        print("not registered")
    }
    switch InputSourceRegistrar.updateUserList({ InputSourceList.removing(InputSourceRegistrar.bundleID, from: $0) }) {
    case .written: print("removed from your input sources")
    case .failed: printError("could not remove it from your input sources (\(InputSourceList.domain))")
    case .unchanged: break
    }
    return status == 0 ? 0 : 1
}

func printStatus() -> Int32 {
    typealias R = InputSourceRegistrar
    print("version:     \(AppVersion.string)")
    print("bundle:      \(Bundle.main.bundlePath)")
    let others = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != getpid()
    }
    print("running:     \(others.isEmpty ? "no" : others.map { "pid \($0.processIdentifier)" }.joined(separator: ", "))")

    do {
        let config = try Config.load()
        print("config:      \(Config.defaultURL.path)")
        print("provider:    \(config.provider.displayName)")
        print("model:       \(config.settings(for: config.provider).model ?? "-")")
        if config.provider == .apple {
            print("apple model: \(AppleModel.system.availability.rawValue)")
        } else if config.provider != .bedrock {
            print("api key:     \(APIKeys.source(config.provider) == .none ? "✗ none" : "found")")  // not read: no keychain prompt
        } else {
            // Read from the files and the SSO sign-in only: no program run, nothing fetched.
            let status = AWSCredentialResolver.shared.status(profile: config.awsProfile)
            let region = config.region ?? status.region ?? "us-east-1"
            print("aws:         " + (status.isReady ? "profile \(config.awsProfile), region \(region), " : "✗ ") + status.line(chinese: false))
        }
    } catch {
        print("config:      ✗ \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
    }
    let store = LanguagePackStore()
    for pack in LanguagePack.catalog {
        let record = store.installed(pack)
        print("pack:        \(pack.id) \(record.map { "\($0.version) (\($0.source.rawValue))" } ?? "not installed") (\(store.folder(pack).path))")
    }
    print("rime:        librime \(RimeService.shared.version), data \(RimeDirectories.shared?.path ?? "none (English only)")")
    print("rime user:   \(RimeDirectories.user.path)")

    guard let source = R.source() else {
        print("registered:  no (\(R.sourceID))")
        return 1
    }
    print("registered:  yes (\(R.sourceID))")
    print("name:        \(R.string(source, kTISPropertyLocalizedName) ?? "?")")
    print("type:        \(R.string(source, kTISPropertyInputSourceType) ?? "?")")
    if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
       let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] {
        print("languages:   \(languages.joined(separator: ", "))")
    }
    print("enabled:     \(R.bool(source, kTISPropertyInputSourceIsEnabled))")
    print("listed:      \(R.isInUserList) (in your input sources, which Ctrl+Space goes through)")
    print("selectable:  \(R.bool(source, kTISPropertyInputSourceIsSelectCapable))")
    print("selected:    \(R.bool(source, kTISPropertyInputSourceIsSelected))")
    print("current:     \(R.currentSourceID() ?? "?")")
    return 0
}

/// `--install-pack ID [--library URL] [--key BASE64] [--packs-dir DIR]`: the settings' download, from a
/// terminal (and against a test library: another key, plain http to this Mac).
func installPack(_ arguments: [String]) -> Int32 {
    func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
    guard let id = arguments.first, let pack = LanguagePack.catalog.first(where: { $0.id == id }) else {
        printError("usage: --install-pack \(LanguagePack.catalog.map(\.id).joined(separator: "|")) [--library URL] [--key BASE64] [--packs-dir DIR]")
        return 2
    }
    var library = LanguagePackLibrary(allowsLocalHTTP: true)
    if let url = option("--library").flatMap(URL.init(string:)) { library = LanguagePackLibrary(baseURL: url, allowsLocalHTTP: true) }
    if let key = option("--key") {
        guard let raw = Data(base64Encoded: key) else { printError("--key: not base64"); return 2 }
        library.publicKey = raw
    }
    if let dir = option("--packs-dir") { library.store = LanguagePackStore(directory: URL(fileURLWithPath: dir)) }
    let started = Date()
    let outcome = InstallOutcome()
    Task.detached { [library] in
        do {
            let record = try await library.install(pack) { share in
                FileHandle.standardError.write(Data(String(format: "\rdownloading %3.0f%%", share * 100).utf8))
            }
            outcome.set(.success(record))
        } catch {
            outcome.set(.failure(error))
        }
    }
    while outcome.get() == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    FileHandle.standardError.write(Data("\n".utf8))
    switch outcome.get()! {
    case let .success(record):
        print(String(format: "installed %@ %@ in %.1fs: %@", pack.id, record.version, Date().timeIntervalSince(started),
                     library.store.folder(pack).path))
        return 0
    case let .failure(error):
        printError("✗ \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        return 1
    }
}

/// The outcome of a background install, polled by the main thread.
final class InstallOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<LanguagePackRecord, Error>?
    func set(_ result: Result<LanguagePackRecord, Error>) { lock.withLock { value = result } }
    func get() -> Result<LanguagePackRecord, Error>? { lock.withLock { value } }
}

/// `--adopt-pack DATA [VERSION]`: the Chinese pack from a Rime data folder, without downloading (the
/// developer's ThirdParty/rime-data, or what an older app bundled: `make install` does that).
func adoptPack(_ arguments: [String]) -> Int32 {
    guard let path = arguments.first else {
        printError("usage: --adopt-pack DATA [VERSION]")
        return 2
    }
    do {
        let record = try LanguagePackStore().adopt(.chinesePinyin, from: URL(fileURLWithPath: path),
                                                   version: arguments.count > 1 ? arguments[1] : "0.0.0")
        print("pack:        \(LanguagePack.chinesePinyin.id) \(record.version) (\(record.source.rawValue))")
        return 0
    } catch {
        printError("✗ \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        return 1
    }
}

// A command's program that exits before reading all it is sent (`@py`, a custom run command) closes its
// pipe: writing to it must fail, not end the input method (and the text being typed) with SIGPIPE.
signal(SIGPIPE, SIG_IGN)

let arguments = Array(CommandLine.arguments.dropFirst())

// A script plugin's own process (started by the input method): nothing else runs, nothing else is printed.
if arguments.first == "--run-plugin" {
    guard let invocation = PluginHost.invocation(Array(arguments.dropFirst())) else { exit(2) }
    exit(PluginHost.run(directory: invocation.directory, language: invocation.language))
}
// The same for `@js` code (`InlineCode`): the code on standard input, what it prints on standard output.
if arguments.first == InlineCode.javaScriptHostOption {
    exit(InlineCode.runJavaScriptHost())
}

// The bundle's version, and nothing else: the updater checks with it that a new input method starts.
if arguments.first == "--version" {
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? AppVersion.string)
    exit(0)
}

// Data from the AIPinyin days moves to the AllInOneIME folders before anything reads it.
for (path, outcome) in LegacyData.migrate() where outcome != .nothingToMove {
    switch outcome {
    case .moved: log.notice("moved legacy data to \(path, privacy: .public)")
    case .keptBoth: log.notice("legacy data left in place: \(path, privacy: .public) exists")
    case let .failed(error): log.error("could not move legacy data to \(path, privacy: .public): \(error, privacy: .public)")
    case .nothingToMove: break
    }
    if arguments.first?.hasPrefix("--") == true {
        switch outcome {
        case .moved: print("data:        moved from the AIPinyin folder to \(path)")
        case .keptBoth: print("data:        \(path) exists; the old AIPinyin folder was left as it is")
        case let .failed(error): printError("data:        could not move the AIPinyin folder to \(path): \(error)")
        case .nothingToMove: break
        }
    }
}

switch arguments.first {
case "--register":
    exit(register())
case "--disable":
    exit(disable())
case "--status":
    exit(printStatus())
case "--selftest":
    if let index = arguments.firstIndex(of: "--rime-data"), arguments.indices.contains(index + 1) {
        RimeDirectories.override = URL(fileURLWithPath: arguments[index + 1])
    }
    let directory = URL(fileURLWithPath: arguments.count > 1 && !arguments[1].hasPrefix("--") ? arguments[1] : "/tmp/allinoneime-selftest")
    exit(MainActor.assumeIsolated { SelfTest.run(snapshotDirectory: directory) })
case "--showcase":
    let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "/tmp/allinoneime-showcase")
    MainActor.assumeIsolated { PanelShowcase.run(output: directory, dark: arguments.contains("dark"), chinese: arguments.contains("zh")) }
case "--settings-image":
    let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "/tmp/allinoneime-settings")
    MainActor.assumeIsolated {
        // `extensions=<folder>[,<found folder>…]`: the Custom Commands page shows those folders' extensions instead of
        // the user's (the first as added, the others as found by Spotlight).
        let extensions = arguments.first { $0.hasPrefix("extensions=") }.map { String($0.dropFirst("extensions=".count)) }
        // `update=available|current|downloading|failed`: the About page's Updates card in that state.
        let update = arguments.first { $0.hasPrefix("update=") }.map { String($0.dropFirst("update=".count)) }
        // `agent=gemini|kiro|custom:<command>`: the agent `@agent` hands the text to.
        let agent = arguments.first { $0.hasPrefix("agent=") }.map { String($0.dropFirst("agent=".count)) }
        SettingsPageImages.run(output: directory, chinese: arguments.contains("zh"), dark: arguments.contains("dark"),
                               extensions: extensions, update: update, agent: agent)
    }
case "--install-pack":
    exit(installPack(Array(arguments.dropFirst())))
case "--adopt-pack":
    exit(adoptPack(Array(arguments.dropFirst())))
case "--check-update":
    exit(UpdateCommands.check(Array(arguments.dropFirst())))
case "--install-update":
    exit(UpdateCommands.install(Array(arguments.dropFirst())))
case "--add-source":
    exit(ExtensionSourceCommands.add(Array(arguments.dropFirst())))
case "--update-sources":
    exit(ExtensionSourceCommands.update(Array(arguments.dropFirst())))
case "--list-extensions":
    exit(ExtensionSourceCommands.list(Array(arguments.dropFirst())))
case "--apply-update":
    // The updater's helper (`UpdateHelper`), started by the input method on an update it staged.
    exit(UpdateHelper.run(Array(arguments.dropFirst())))
case "--settings":
    // Started by the AllInOneIME Settings app: serve as the input method and show the settings window.
    runServer(showSettings: true)
case "-h", "--help":
    print(usage)
    exit(0)
case let flag? where flag.hasPrefix("--"):
    printError("unknown option \(flag)\n\n\(usage)")
    exit(2)
default:
    // Launched by the system (possibly with -psn_… or other AppKit arguments).
    runServer()
}
