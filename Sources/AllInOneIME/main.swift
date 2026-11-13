import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMERime
import AppKit
import Carbon
import InputMethodKit

let usage = """
    AllInOneIME input method. Launched by macOS without arguments; developer commands:
      --register        register this bundle with Text Input Sources; once you have added it
                        (System Settings → Keyboard), keep it in your input sources
      --disable         disable, and remove it from your input sources
      --status          show registration, process and configuration status
      --settings        run as the input method and open the settings window
      --selftest [DIR] [--rime-data DATA] [--typing-lag-only | --autocomplete-only | --settings-only |
                 --suggestions-only | --clipboard-only]
                        drive the input controller (real Rime engine on DATA, else the installed
                        Chinese pack; live Bedrock call) with a fake text field; writes panel snapshots
                        to DIR (default /tmp/allinoneime-selftest); --typing-lag-only runs just the
                        offline window reuse, config cache and rapid pinyin checks; --autocomplete-only
                        just autocomplete's (a harness window, stand-in models, no AI requests);
                        --settings-only just the settings window's (stand-ins, no AI requests);
                        --suggestions-only just suggestions' (a stand-in for api.github.com, the
                        Electron harness where ALLINONEIME_ELECTRON_HARNESS names it; no AI requests);
                        --clipboard-only just clipboard history's (a history of its own, never the
                        clipboard's; the Electron harness as for suggestions).
                        The GitHub plugin and a coding pack come from the repository's Core/: the
                        checkout this build was made from, or ALLINONEIME_SOURCE_ROOT's (skipped where
                        neither is on this Mac).
                        Exits 0 when every check ran and passed, 1 when one failed, 2 when none failed
                        but some were skipped or couldn't run (a locked screen ends it at once); the
                        last line is SELFTEST-RESULT {"passed":N,"failed":N,"skipped":N,"status":…}
      --install-pack ID [--library URL] [--key BASE64] [--packs-dir DIR]
                        download and install a language pack (zh-pinyin) as Settings does; plain http
                        is allowed to this Mac only, for a test server
      --adopt-pack DATA [VERSION]
                        install the Chinese pack from a Rime data folder (ThirdParty/rime-data, or an
                        older app's Contents/SharedSupport/rime) without downloading
      --version         print this bundle's version
      --check-update [--manifest-url URL] [--key BASE64]
                        check for a new version as Settings → About does (signed update-v2.json); plain
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

/// The value after `name` in a developer command's `arguments` (`--key BASE64`); nil when there is none.
func option(_ name: String, in arguments: [String]) -> String? {
    arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
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
    /// The app's Zhuyin data (rime-bopomofo's schema and what it needs: `PinyinScheme.zhuyinData`), linked into the pack
    /// (`LanguagePackStore.linkData`); compiled only where Zhuyin is picked (the schema list).
    static var zhuyin: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("rime-zhuyin")
    }
    /// The app's OpenCC data for Traditional characters, copied into the user folder (`RimeService.prepareOpenCC`).
    static var openCC: URL? {
        Bundle.main.sharedSupportURL?.appendingPathComponent("opencc")
    }
    static var user: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AllInOneIME/Rime")
    }
    static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AllInOneIME")
    }
}

/// Fuzzy pinyin (`FuzzyPinyin`) in the Rime user folder: the patch for the pairs the config turns on, for the
/// characters Chinese is typed in (`ChineseCharacters`, Traditional ones through OpenCC), and for the filter of the
/// candidates removed that the app's Lua has (`RemovedCandidates.luaFilter`), so written with no pairs too; for full
/// pinyin's schema and the Shuangpin scheme or Zhuyin typed with (`PinyinScheme`), whose schema is deployed beside it
/// (the schema list, `default.custom.yaml`).
enum RimeFuzzy {
    /// The characters the patch was last written for (`follow`).
    static let written = ChineseCharacters.Written()
    /// The way of typing pinyin the patch and the schema list were last written for (`follow`); nil: not written yet.
    static var writtenScheme: PinyinScheme?

    /// Writes (or removes) the patch, and the schema list; nil when it couldn't. `.written` and `.removed` need a
    /// deployment, and so does a schema list written (`schemaListWritten`).
    @discardableResult
    static func write(_ ids: [String], characters: ChineseCharacters, scheme: PinyinScheme) -> FuzzyPinyin.Outcome? {
        schemaListWritten = false
        guard let shared = RimeDirectories.shared else { return nil }
        // Whatever came of it: tried once for these characters, not again at every check (`follow`).
        defer {
            written.wrote(characters)
            writtenScheme = scheme
        }
        schemaListWritten = writeSchemaList(scheme)
        do {
            let outcome = try FuzzyPinyin.apply(ids, characters: characters, scheme: scheme,
                                                schema: shared.appendingPathComponent("rime_ice.schema.yaml"), userDir: RimeDirectories.user)
            if outcome == .userFile { log.notice("fuzzy pinyin not applied: the Rime folder has the user's own \(FuzzyPinyin.fileName, privacy: .public)") }
            return outcome
        } catch {
            log.error("could not write the fuzzy pinyin patch: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The last `write` wrote the schema list anew (another scheme picked): librime deploys it.
    private(set) static var schemaListWritten = false

    /// The schemas deployed (`PinyinScheme.applySchemaList`): full pinyin's, and the Shuangpin scheme's or Zhuyin's.
    /// Whether it was written anew.
    private static func writeSchemaList(_ scheme: PinyinScheme) -> Bool {
        do {
            switch try PinyinScheme.applySchemaList(scheme, userDir: RimeDirectories.user) {
            case .written: return true
            case .unchanged: return false
            case .userFile:
                log.notice("the schemas deployed are the user's own default.custom.yaml's: \(scheme.rawValue, privacy: .public) types only if it lists it")
                return false
            }
        } catch {
            log.error("could not write the schema list: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Changed in the settings: written, and Rime deployed again when it changed (about a second; a Shuangpin scheme
    /// deployed for the first time, its spellings too, a moment more; Zhuyin, its dictionaries, a couple of seconds).
    @discardableResult
    static func apply(_ ids: [String], characters: ChineseCharacters, scheme: PinyinScheme) -> FuzzyPinyin.Outcome? {
        let outcome = write(ids, characters: characters, scheme: scheme)
        if outcome == .written || outcome == .removed || schemaListWritten { RimeService.shared.redeploy() }
        return outcome
    }

    /// The settings read again (a text field focused) or the system's languages changed: with no characters picked they
    /// follow the system's (`Config.typedChinese`), so the candidates do too once they differ from the patch's
    /// (`ChineseCharacters.Written`): written again and deployed again, as a change in the settings is. So is another way
    /// of typing pinyin than the one written (`Config.pinyinScheme` changed in the file, or by the settings of another
    /// shell), which the next key types with once it is deployed. Nothing while the config file doesn't parse (nil): its
    /// defaults aren't the user's fuzzy pinyin. Nothing in the self-test either (`Config.selfTestURL`): its Rime has a user
    /// folder of its own, and the patch is the user's.
    @MainActor
    static func follow(_ config: Config?) {
        guard let config, Config.selfTestURL == nil, RimeService.shared.isStarted else { return }
        let characters = written.changed(config)
        let scheme = config.typedPinyin
        guard characters != nil || scheme != writtenScheme else { return }
        if let characters {
            log.notice("the system's languages changed the characters Chinese is typed in: \(characters.rawValue, privacy: .public)")
        }
        if scheme != writtenScheme { log.notice("pinyin is typed another way: \(scheme.rawValue, privacy: .public)") }
        apply(config.fuzzyPinyin, characters: characters ?? config.typedChinese, scheme: scheme)
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
        MainActor.assumeIsolated { SettingsWindow.shared.save() }  // what was typed in Settings without ⏎
        // What script extensions started, and the questions' sessions (each agent's process and what it started), don't
        // outlive the input method: stopped side by side, half a second at most.
        DispatchQueue.concurrentPerform(iterations: 2) { $0 == 0 ? CommandRunner.stopAll() : sharedConverter.stopQuestionSessions() }
        SessionServices.englishWordsWriter.drain(within: 0.5)  // the English words just learned, candidates removed, into the file
        WeekStatsShared.store.flushNow()  // this week's counts not written yet
    }
}

/// SIGTERM (an update, `make install`, logging out): what was typed in the settings window without ⏎ (a model ID, the
/// region) is saved first, as closing the window saves it (`SettingsWindow.save`, on the main thread, waited for at
/// most half a second), the programs running for script extensions and the questions' sessions' agents, and what they
/// started, are stopped (`CommandRunner.stopAll`, `Converter.stopQuestionSessions`, side by side, at most half a
/// second), the English words learned and the candidates removed not written yet go into the config file
/// (`EnglishWords.Writer.drain`, at most half a second), then the input method ends, as the signal's default would end
/// it. Handled on a queue of its own, not in a signal handler and not on the main thread: a
/// main thread that hangs doesn't keep it alive, and a hard exit is armed in case stopping hangs too.
private let terminationSignal: DispatchSourceSignal = {
    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: DispatchQueue(label: "AllInOneIME.terminate"))
    source.setEventHandler {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { _exit(0) }
        let saved = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { SettingsWindow.shared.save() }
            saved.signal()
        }
        _ = saved.wait(timeout: .now() + 0.5)
        DispatchQueue.concurrentPerform(iterations: 2) { $0 == 0 ? CommandRunner.stopAll() : sharedConverter.stopQuestionSessions() }
        SessionServices.englishWordsWriter.drain(within: 0.5)
        WeekStatsShared.store.flushNow()
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
    // A custom command a built-in now has the name of (a custom @reply): renamed in the config, said once in the next
    // text field (`BuiltinRenames`).
    BuiltinRenames.apply()
    // What 0.6.6 and earlier learned outside the one local store of what is learned (Settings v2 §3.2), moved into it.
    MainActor.assumeIsolated { LearnedShared.moveInWhatWasLearnedBefore() }
    // Older versions kept their sentence mode switch here (first as aiEnabled); nothing reads it now.
    for key in ["sentenceMode", "aiEnabled"] { UserDefaults.standard.removeObject(forKey: key) }
    // Background @agent tasks: notifications, and tasks from before a restart watched again.
    MainActor.assumeIsolated { AgentMonitor.shared.setUp() }
    // Chrome's page tree turned on by an earlier run that didn't turn it off (a crash, a reinstall): off again.
    PageContextReader.releaseLeftOver()
    // The menu bar icon (on by default) and its panel, once the server and Rime are up. The notes @note
    // saves are recorded whether the panel is shown or not, so that it lists them when it drops down.
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            FloatingPanel.shared.recordSavedNotes()
            MenuBarIcon.shared.apply(LiveConfig.current.menuBarIcon)
        }
    }
    if showSettings {
        // On About instead when the move to this identity shows the step to add the input source first (decided by
        // `UpdateController.start` below, before this runs).
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if UpdateController.shared.firstShown != .inputSourceStep { SettingsWindow.shared.show() }
            }
        }
    }
    // librime on the Chinese pack if it's installed; an upgraded user who had Chinese gets it downloaded.
    MainActor.assumeIsolated { LanguagePackManager.shared.launch() }
    // Whether the input source is enabled (the user adds a new one in System Settings): About shows the step until it is.
    MainActor.assumeIsolated { InputSourceStatus.shared.start() }
    // What the last update did, and a look for the next one if a day has passed (in the background).
    MainActor.assumeIsolated { UpdateController.shared.start() }
    // What the move to this system identity left (`IdentityFinish`): the login keychain's keys handed over imported, the
    // move's cleanup record finished; in the background, by the installed input method only.
    if UpdateLocations.runningIsInstalled {
        IdentityFinish.system(say: { line in log.notice("\(line, privacy: .public)") }).start()
    }
    // Extension sources: checked about 30 s from now, then once a day, if they check by themselves (only ever noted).
    MainActor.assumeIsolated { ExtensionSourceController.shared.start() }
    // A plugin found for the first time (installed, put in the plugins folder, or there before 0.6.7.2): its completion
    // sources on, as each scan of the plugins folder finds it.
    LivePlugins.found = { plugins in MainActor.assumeIsolated { SuggestionsShared.pluginsFound(plugins) } }
    // The extensions and plugins found in the background now, not at the first field's focus: the first "@" has them; a
    // rebuild that lands while an "@" list is open shows them there at once.
    LiveExtensions.changed = { MainActor.assumeIsolated { AllInOneIMEInputController.activeController?.commandsChanged() } }
    LivePlugins.changed = { MainActor.assumeIsolated { AllInOneIMEInputController.activeController?.commandsChanged() } }
    LiveExtensions.prepare(LiveConfig.current)
    LivePlugins.prepare()
    // The script extensions' status lines kept from the last launch, read off the main thread now, not on the key that
    // first shows one.
    MainActor.assumeIsolated { ScriptStatus.shared.prepare() }
    // English words learned (candidates removed) while the config file didn't parse (or couldn't be written): written
    // once it parses again.
    LiveConfig.parsedAnew = { SessionServices.englishWordsWriter.retry() }
    // This week's stats: the user's own commands deleted or renamed keep no name there, now and each time the config
    // file is read anew (`WeekStatsShared.keepOwnCommands`).
    // The questions' sessions follow it too: another backend picked in the file, the old one's process ends.
    let retryEnglishWords = LiveConfig.parsedAnew
    LiveConfig.parsedAnew = {
        retryEnglishWords()
        WeekStatsShared.keepOwnCommands()
        sharedConverter.questionSessionsFollow(LiveConfig.current)
    }
    WeekStatsShared.keepOwnCommands()
    // Translate as You Type goes off when another app becomes active, a text field in it or not.
    MainActor.assumeIsolated { TranslateModeShared.watchApps() }
    // Sync through iCloud, if it is on: a first run in a moment, then as files change.
    MainActor.assumeIsolated { ICloudSyncController.shared.start() }
    // Clipboard history: a look at the clipboard's change count each second (⌃V lists what was copied).
    MainActor.assumeIsolated { ClipboardHistoryShared.start() }
    // Without librime (no Chinese pack), what the first key and panel would wait for is made ready a moment after launch;
    // with it, once it is ready (`RimeReadinessLogger`).
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        MainActor.assumeIsolated { if !RimeService.shared.isStarted { LaunchWarmUp.run() } }
    }
    // The system's languages changed (System Settings → General → Language & Region): with no characters picked, the
    // candidates follow them as the rest does (a text field focused checks too).
    let localeChanged = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil,
                                                               queue: .main) { _ in
        MainActor.assumeIsolated { RimeFuzzy.follow(LiveConfig.currentIfValid) }
    }
    withExtendedLifetime((server, localeChanged)) { app.run() }
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
            MainActor.assumeIsolated { LaunchWarmUp.run() }
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
    guard InputSourceRegistrar.waitForSource() != nil else {
        printError("registered, but input source \(InputSourceRegistrar.sourceID) did not appear")
        return 1
    }
    // Registered only, never enabled or selected: macOS doesn't let a program enable a third-party input method (asked,
    // it changes nothing and opens System Settings → Keyboard by itself); the user adds it there once. Enabled already
    // (added by the user; an update of one they have), it stays so, and selected if it was: Text Input Sources keeps both.
    let enabled = InputSourceRegistrar.waitUntilEnabled(timeout: 2)
    if enabled {
        // Enabled by a program (an earlier version's install), it isn't in the user's input sources, which
        // Ctrl+Space goes by: keep it there as well (see InputSourceList).
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

            macOS 需要你手动添加一次：
              系统设置 → 键盘 → 文字输入 › 输入法「编辑…」→ 左下角 + → 简体中文 → AllInOneIME → 添加
            之后用 Ctrl+Space 或 🌐 键切换到 AllInOneIME。
            """, """

            macOS needs you to add it once:
              System Settings → Keyboard → Text Input › Input Sources "Edit…" → + at the bottom left
              → Chinese, Simplified → AllInOneIME → Add
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
            let source = APIKeys.source(config.provider).sent(by: config.provider,
                                                              to: HTTPProviders.host(of: config.settings(for: config.provider)))
            print("api key:     \(source == .none ? "✗ none" : "found")")  // not read: no keychain prompt
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
    guard let id = arguments.first, let pack = LanguagePack.catalog.first(where: { $0.id == id }) else {
        printError("usage: --install-pack \(LanguagePack.catalog.map(\.id).joined(separator: "|")) [--library URL] [--key BASE64] [--packs-dir DIR]")
        return 2
    }
    var library = LanguagePackLibrary(allowsLocalHTTP: true)
    if let url = option("--library", in: arguments).flatMap(URL.init(string:)) { library = LanguagePackLibrary(baseURL: url, allowsLocalHTTP: true) }
    if let key = option("--key", in: arguments) {
        guard let raw = Data(base64Encoded: key) else { printError("--key: not base64"); return 2 }
        library.publicKey = raw
    }
    if let dir = option("--packs-dir", in: arguments) { library.store = LanguagePackStore(directory: URL(fileURLWithPath: dir)) }
    let started = Date()
    let outcome = ResultBox<LanguagePackRecord>()
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

// What the core needs of the Mac (programs with the login shell's environment, the keychain, JavaScriptCore …),
// before anything uses it: the plugin and `@js` processes below too.
Platform.current = .mac

let arguments = Array(CommandLine.arguments.dropFirst())

// A script plugin's own process (started by the input method): nothing else runs, nothing else is printed.
if arguments.first == "--run-plugin" {
    guard let invocation = PluginHost.invocation(Array(arguments.dropFirst())) else { exit(2) }
    // A completion script's load or query (suggestions), its ctx on standard input.
    if let function = PluginHost.completionFunction(Array(arguments.dropFirst())) {
        exit(PluginHost.runCompletion(directory: invocation.directory, function: function))
    }
    exit(PluginHost.run(directory: invocation.directory, language: invocation.language, preferences: invocation.preferences))
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

// Hidden: the two-Mac check of key sync, on the self-test's own synced items only (`KeychainProbe`).
if arguments.first == "--keychain-probe" {
    exit(KeychainProbe.run(Array(arguments.dropFirst())))
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
    exit(MainActor.assumeIsolated {
        SelfTest.run(snapshotDirectory: directory, typingLagOnly: arguments.contains("--typing-lag-only"),
                     autocompleteOnly: arguments.contains("--autocomplete-only"), settingsOnly: arguments.contains("--settings-only"),
                     suggestionsOnly: arguments.contains("--suggestions-only"), clipboardOnly: arguments.contains("--clipboard-only"))
    })
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
        // `doctor=fine`: About → Troubleshoot's checks with nothing wrong (else made-up problems); `doctor=open` or
        // `doctor=fine,open`: what is fine opened (else folded); `noax` with either: Accessibility not allowed.
        let doctor = arguments.first { $0.hasPrefix("doctor=") }.map { String($0.dropFirst("doctor=".count)) }
        SettingsPageImages.run(output: directory, chinese: arguments.contains("zh"), dark: arguments.contains("dark"),
                               extensions: extensions, update: update, agent: agent, doctor: doctor)
    }
case "--week-stats-images":
    // This week's stats as the design shows them, with its sample week (`WeekStatsImages`).
    let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "/tmp/allinoneime-week-stats")
    MainActor.assumeIsolated { WeekStatsImages.run(output: directory) }
case "--page-context":
    // `--page-context [request]`: what `@agent` would take along from the Chrome page in front, printed (nothing is
    // sent). Needs Accessibility for the process that runs it.
    guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else {
        print("Google Chrome isn't running"); exit(1)
    }
    guard AXIsProcessTrusted() else { print("Accessibility isn't allowed for this process"); exit(1) }
    // As when `@agent` starts being written: the page tree is asked for (and given back after).
    PageContextReader.wake(pid: chrome.processIdentifier)
    let mouse = NSEvent.mouseLocation, height = NSScreen.screens.first?.frame.height ?? 0
    let started = Date()
    guard let context = PageContextReader.read(pid: chrome.processIdentifier, pointer: CGPoint(x: mouse.x, y: height - mouse.y)) else {
        print("no page (or a password field)")
        PageContextReader.release(pid: chrome.processIdentifier)
        Thread.sleep(forTimeInterval: 0.3)
        exit(1)
    }
    let prompt = context.prompt(request: arguments.count > 1 ? arguments[1] : "(what you typed)")
    print(prompt)
    FileHandle.standardError.write(Data(String(format: "\n— %d chars, %.0f ms\n", prompt.count, Date().timeIntervalSince(started) * 1000).utf8))
    PageContextReader.release(pid: chrome.processIdentifier)
    Thread.sleep(forTimeInterval: 0.3)  // the release runs in the background
    exit(0)
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
