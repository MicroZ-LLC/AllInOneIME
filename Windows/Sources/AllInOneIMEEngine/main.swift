import AllInOneIMECore
import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
#if os(Windows)
import AllInOneIMEWindows
import WinSDK
#endif

// The per-user engine (wire protocol v1, docs/wire-protocol-v1.md in the core): one process per user and session,
// single-instance through `Local\AllInOneIME-Engine-<SID>`, serving the TSF DLLs of every app over
// `\\.\pipe\AllInOneIME-<SID>-v1`. Each client connection gets a serial queue and its fields a Composer each: pinyin
// through librime, the candidate window, level two through the core's Converter (`EngineHost`).
//
//   AllInOneIMEEngine [--test [--provider FILE] [--clock manual|system]] [--config FILE] [--no-keychain]
//                     [--rime-data DIR] [--rime-user DIR] [--no-rime] [--no-panel] [--instances N] [--quiet]
//                     [--pipe NAME] [--settings-app FILE]
//
//   --test        test mode: Latin letters, a manual clock, level two from a golden's scripted provider, `x-test`
//                 directives accepted (`allinoneime-cli wire-replay` drives it), clients taken to own the foreground;
//                 with --config, the Settings app's settings are that file's, their keys in memory
//   --provider    test mode: level two from this scripted provider (a golden's fixture) from the start, as
//                 `#! provider` sets it
//   --clock       test mode: `manual` (the default: time moves only with `x-test advance` and `run tasks`) or
//                 `system`, so a scripted stream plays out in real time for a real app (the end-to-end test)
//   --config      the settings from FILE instead of %APPDATA%\AllInOneIME\config.json
//   --no-keychain API keys only from the environment (ANTHROPIC_API_KEY, ...) and those saved while it runs, in memory,
//                 never the Credential Manager: for tests, which must neither read the user's keys nor tie them to a
//                 stub's address
//   --rime-data   rime-ice's data (default: rime-data beside the program, else ThirdParty's); only a build (in .build)
//                 does: any other engine, the installed one first, takes librime and its data from beside itself
//   --rime-user   librime's user folder (default: %APPDATA%\AllInOneIME\rime): tests use their own, so that what they
//                 type isn't learned in the user's
//   --no-rime     Latin letters only
//   --no-panel    no candidate window
//   --instances   pipe instances kept waiting for a client (at least 4)
//   --quiet       log only the engine's start, its errors and its end
//   --pipe        for tests: this pipe (\\.\pipe\NAME) instead of the user's, with a single-instance mutex of its own,
//                 so that a test engine runs beside the installed one; @settings gives the Settings app the same pipe
//   --settings-app the Settings app @settings opens (default: Settings\AllInOneIMESettings.exe beside the program)
//
// It is also the child process `@js` code (`--run-js`) and script plugins (`--run-plugin DIR`) run in, and the process
// of each console window it opens (`--run-in-console`, `ConsoleHold`).
//
//   AllInOneIMEEngine --render-panel DIR [--dpi N]... [--image FILE]
//
// draws the candidate window's sample panels (`PanelSamples`) into PNG files in DIR, as the window draws them, light
// and dark, at each DPI (96 and 120 by default), without a window: to look at what it draws.

let usage = """
    usage: AllInOneIMEEngine [--test [--provider FILE] [--clock manual|system]] [--config FILE] [--no-keychain]
                             [--rime-data DIR] [--rime-user DIR] [--no-rime] [--no-panel] [--instances N] [--quiet]
                             [--pipe NAME] [--settings-app FILE]
    """

struct EngineOptions {
    var test = false
    var provider: String?
    var systemClock = false
    var config: String?
    var noKeychain = false
    var rimeData: String?
    var rimeUser: String?
    var noRime = false
    var noPanel = false
    var instances = 4
    var quiet = false
    var pipe: String?
    var settingsApp: String?
}

func parseOptions() -> EngineOptions {
    var options = EngineOptions()
    var args = CommandLine.arguments.dropFirst()
    func value(_ flag: String) -> String {
        guard let value = args.popFirst() else { fail("\(flag) needs a value") }
        return value
    }
    while let arg = args.popFirst() {
        switch arg {
        case "--test": options.test = true
        case "--quiet": options.quiet = true
        case "--provider": options.provider = value(arg)
        case "--clock":
            switch args.popFirst() {
            case "manual": options.systemClock = false
            case "system": options.systemClock = true
            default: fail("--clock is manual or system")
            }
        case "--config": options.config = value(arg)
        case "--no-keychain": options.noKeychain = true
        case "--rime-data": options.rimeData = value(arg)
        case "--rime-user": options.rimeUser = value(arg)
        case "--no-rime": options.noRime = true
        case "--no-panel": options.noPanel = true
        case "--pipe": options.pipe = value(arg)
        case "--settings-app": options.settingsApp = value(arg)
        case "--instances":
            guard let n = args.popFirst().flatMap(Int.init), n >= 4 else { fail("--instances needs a number, 4 or more") }
            options.instances = n
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            fail("unknown argument \(arg)\n\(usage)")
        }
    }
    if !options.test, options.provider != nil || options.systemClock {
        fail("--provider and --clock are for test mode (--test)")
    }
    return options
}

func fail(_ message: String) -> Never {
    writeStandardError("AllInOneIMEEngine: \(message)\n")
    exit(2)
}

/// Writes to stderr, or nowhere when there is none. Started at logon (the installer's Run entry) or by the DLL, the
/// engine has no console and no standard handles, and `FileHandle.standardError` traps on a write to a missing one.
func writeStandardError(_ text: String) {
    #if os(Windows)
    guard let handle = GetStdHandle(STD_ERROR_HANDLE), handle != invalidHandle else { return }
    var bytes = Array(text.utf8)
    var written: DWORD = 0
    _ = WriteFile(handle, &bytes, DWORD(bytes.count), &written, nil)
    #else
    FileHandle.standardError.write(Data(text.utf8))
    #endif
}

/// Logs to stderr: sizes and kinds, never a payload (§8).
final class EngineLog: @unchecked Sendable {
    let quiet: Bool
    let start = ProcessInfo.processInfo.systemUptime
    private let lock = NSLock()

    init(quiet: Bool) { self.quiet = quiet }

    func callAsFunction(_ message: String, always: Bool = false) {
        guard always || !quiet else { return }
        let ms = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        lock.lock()
        writeStandardError("[engine +\(ms)ms] \(message)\n")
        lock.unlock()
    }
}

#if os(Windows)

/// The server the console handler says `bye` with.
nonisolated(unsafe) var runningServer: WireServer?

/// How long since this process was created, in ms (`GetProcessTimes`): the engine's cold start, as far as it sees it.
func msSinceProcessStart() -> Double? {
    var creation = FILETIME(), exit = FILETIME(), kernel = FILETIME(), user = FILETIME(), now = FILETIME()
    guard GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user) else { return nil }
    GetSystemTimePreciseAsFileTime(&now)
    func ticks(_ t: FILETIME) -> UInt64 { UInt64(t.dwHighDateTime) << 32 | UInt64(t.dwLowDateTime) }
    return Double(ticks(now) &- ticks(creation)) / 10_000
}

/// This program's full path (GetModuleFileNameW): what `@js` and script plugins are started as.
func executablePath() -> String {
    var buffer = [WCHAR](repeating: 0, count: 32_768)
    let count = GetModuleFileNameW(nil, &buffer, DWORD(buffer.count))
    return count > 0 ? String(decoding: buffer.prefix(Int(count)), as: UTF16.self) : CommandLine.arguments[0]
}

/// `--render-panel DIR [--dpi N]... [--image FILE]`: each sample panel in DIR, "NN-name-light-96.png" …, and a line
/// each saying what was drawn. The checkout's app icon is the icons' image unless one is given.
func renderPanels(_ arguments: [String]) -> Int32 {
    guard let folder = arguments.first, !folder.hasPrefix("--") else {
        writeStandardError("usage: AllInOneIMEEngine --render-panel DIR [--dpi N]... [--image FILE]\n")
        return 2
    }
    var dpis: [Int] = []
    var image: String?
    var rest = arguments.dropFirst()
    while let option = rest.popFirst() {
        switch option {
        case "--dpi": if let value = rest.popFirst().flatMap(Int.init) { dpis.append(value) }
        case "--image": image = rest.popFirst()
        default: break
        }
    }
    if dpis.isEmpty { dpis = [96, 120] }
    if image == nil {
        // Resources/AppIcon.png, up from the program (a build in the checkout).
        var url = URL(fileURLWithPath: executablePath()).deletingLastPathComponent()
        for _ in 0..<6 {
            let icon = url.appendingPathComponent("Resources/AppIcon.png")
            if FileManager.default.fileExists(atPath: icon.path) {
                image = icon.withUnsafeFileSystemRepresentation { String(cString: $0!) }
                break
            }
            url.deleteLastPathComponent()
        }
    }
    let out = URL(fileURLWithPath: folder, isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var failures = 0
    for (index, sample) in PanelSamples.all(image: image).enumerated() {
        for dpi in dpis {
            for (theme, dark) in [("light", false), ("dark", true)] {
                let name = String(format: "%02d-", index + 1) + "\(sample.name)-\(theme)-\(dpi).png"
                let maxHeight = sample.maxHeight * dpi / 96
                guard let state = CandidateWindow.renderPNG(sample.model, dpi: dpi, dark: dark, maxHeight: maxHeight,
                                                             to: out.appendingPathComponent(name)) else {
                    print("\(name): not drawn")
                    failures += 1
                    continue
                }
                var line = "\(name): \(state.width)x\(state.height)"
                if state.caretX >= 0 { line += ", caret at \(state.caretX),\(state.caretY)" }
                if state.scrolled > 0 { line += ", rows scrolled \(state.scrolled) px" }
                if maxHeight > 0 { line += " (at most \(maxHeight) high)" }
                print(line)
            }
        }
    }
    return failures == 0 ? 0 : 1
}

func runEngine(_ options: EngineOptions) -> Never {
    let log = EngineLog(quiet: options.quiet)
    let sid: String
    do {
        sid = try Win32.currentUserSID()
    } catch {
        log("can't read the user's SID: \(error)", always: true)
        exit(1)
    }

    // The prompts an earlier run left in files for its consoles, which no console needs any more (one whose program
    // still runs holds its own), even when this engine goes again at once.
    let stale = ConsoleCommand.removeStalePrompts()
    if !stale.isEmpty { log("deleted \(stale.count) prompt files no console needs any more", always: true) }

    // One engine per user and session (§2.5); a test's on a pipe of its own, one per pipe.
    let pipe = options.pipe.map(PipeNames.full)
    let mutexName = pipe.map { PipeNames.mutex(sid: sid, pipe: $0) } ?? PipeNames.mutex(sid: sid)
    let mutex = mutexName.withCString(encodedAs: UTF16.self) { CreateMutexW(nil, true, $0) }
    if mutex == nil || GetLastError() == Win32Code.alreadyExists {
        log("another engine is running for this user: exiting", always: true)
        exit(1)
    }

    // The candidate window is laid out per monitor, in physical pixels, as the caret reports come.
    _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
    // Keys from the environment (`APIKeys.load` falls back to it when the store has none) and the ones the Settings
    // app saves meanwhile, in memory with --no-keychain and in test mode: the same store for the requests and for the
    // settings.
    let memoryKeys = EngineSettings.keyStore(test: options.test, noKeychain: options.noKeychain)

    let clock: WireClock = options.test && !options.systemClock ? ManualClock() : SystemClock()
    let shellThread = SystemThread(name: "AllInOneIME shell")
    let clipboardThread = SystemThread(name: "AllInOneIME clipboard")
    let system = WindowsSystem(clipboard: clipboardThread, shell: shellThread, holder: executablePath())
    var hostOptions = EngineHost.Options(system: system, systemQueue: shellThread, clipboardQueue: clipboardThread)
    hostOptions.testMode = options.test
    hostOptions.foreground = { peer in peer.pid.map { Foreground.isOwned(by: $0, trusted: peer.trusted) } ?? false }
    hostOptions.caretBounds = { hwnd, peer in Foreground.caretBounds(hwnd: hwnd, pid: peer.pid, trusted: peer.trusted) }
    hostOptions.terminalWindow = { hwnd, _ in Foreground.isTerminalWindow(hwnd) }
    hostOptions.settings = EngineSettings(url: options.config.map { URL(fileURLWithPath: $0) } ?? Config.userURL)
    hostOptions.executable = executablePath()
    // The interface in the settings' language, or the system's: the catalog's nine.
    let executable = URL(fileURLWithPath: hostOptions.executable)
    if let catalog = EngineLanguage.catalog(executable: executable) {
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try EngineLanguage.use(catalog: catalog)
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            log("interface text: \(UIText.shipped.count) languages, read in \(ms) ms")
        } catch {
            log("interface text: can't read \(catalog.path): \(error): Simplified Chinese and English only", always: true)
        }
    } else {
        log("interface text: no \(EngineLanguage.catalogName) beside the program: Simplified Chinese and English only", always: true)
    }
    let startConfig = hostOptions.settings.current
    EngineLanguage.apply(startConfig)
    // @settings: the Settings app, given this engine's pipe when it isn't the user's.
    let folder = executable.deletingLastPathComponent()
    let besides = [folder.appendingPathComponent("Settings/AllInOneIMESettings.exe"), folder.appendingPathComponent("AllInOneIMESettings.exe")]
    hostOptions.settingsApp = options.settingsApp
        ?? besides.first { FileManager.default.fileExists(atPath: $0.path) }.map { $0.path.replacingOccurrences(of: "/", with: "\\") }
    hostOptions.settingsAppArguments = pipe.map { ["--pipe", $0] } ?? []
    if !options.test, !options.noRime {
        let data = options.rimeData.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if data != nil, !EngineRime.isBuild(executable) {
            log("rime: an engine that isn't a build takes rime-data from beside itself only: --rime-data ignored", always: true)
        }
        if let location = EngineRime.locate(executable: executable, sharedData: data) {
            let userData = options.rimeUser.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? EngineRime.defaultUserData
            let rime = EngineRime(location: location, userData: userData, log: { log($0, always: true) })
            rime.applyFuzzyPinyin(startConfig.fuzzyPinyin)  // deployed with the rest
            do {
                try rime.start()
                hostOptions.rime = rime
            } catch {
                log("rime: can't start: \(error): Latin letters only", always: true)
            }
        } else {
            log("rime: no rime.dll and rime-data beside the program or in ThirdParty: Latin letters only", always: true)
        }
    }
    if !options.noPanel {
        if let window = CandidateWindow() {
            hostOptions.panel = window
        } else {
            log("no candidate window (no desktop in this session?): the panel isn't drawn", always: true)
        }
    }
    let host = EngineHost(clock: clock, options: hostOptions, log: { log($0) })
    if let rime = hostOptions.rime {
        // Deployed in the background (a second or so the first time): the fields focused meanwhile get it then.
        let started = ProcessInfo.processInfo.systemUptime
        Thread.detachNewThread {
            if rime.waitUntilReady(timeout: 300) {
                log("rime: ready in \(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)) ms", always: true)
                host.rimeBecameReady()
            } else {
                log("rime: not ready after 300 s: Latin letters only", always: true)
            }
        }
    }
    if let config = options.config { log("settings from \(config)", always: true) }
    if let problem = hostOptions.settings.problem { log("the settings file can't be read, defaults used: \(problem)", always: true) }
    if let file = options.provider {
        do {
            host.provider = try ScriptedProvider(contentsOf: URL(fileURLWithPath: file), clock: clock)
        } catch {
            log("can't read the provider \(file): \(error)", always: true)
            exit(2)
        }
    }
    var configuration = WireServer.Configuration()
    configuration.enginePid = GetCurrentProcessId()
    configuration.testControl = options.test
    // The pipe's reader thread writes what isn't a push: the answers go out on the queue too, in order with the pushes.
    configuration.answersThroughPush = true
    if options.test {
        // The goldens' replays connect again and again on a clock that barely moves.
        configuration.connectsPerProcessPerSecond = 1_000_000
    }
    let environment = WireEnvironment(host: host, clock: clock, makeComposer: { host.makeComposer($0, $1) }, log: { log($0) })
    let server = WireServer(configuration: configuration, environment: environment)
    server.testDirective = { host.testDirective($0, $1) }
    // The settings for a settings window (§12): the file the engine reads, through the core's rules, the keys in the
    // Credential Manager (with --no-keychain, in memory). In test mode a golden gives its own (`#! settings`), or
    // --config does: that file, its keys in memory (none from the environment), its plugins in its folder.
    if !options.test || options.config != nil {
        let store = SettingsStore(configURL: hostOptions.settings.url, fresh: { EngineSettings.fresh })
        let service: SettingsService
        if options.test, let memoryKeys {
            let plugins = hostOptions.settings.url.deletingLastPathComponent().appendingPathComponent("plugins", isDirectory: true)
            service = SettingsService(store: store, platform: .windows, library: PluginLibrary(directory: plugins), secrets: memoryKeys)
            service.keySource = { APIKeys.hasKeychainKey(account: $0.rawValue, in: memoryKeys) ? .keychain : .none }
        } else {
            service = SettingsService(store: store, platform: .windows, secrets: memoryKeys)
        }
        // The document in the language the panel speaks: the config's, else Windows' own list.
        let settings = hostOptions.settings
        service.interfaceLanguage = { settings.interfaceLanguage($0) }
        service.recentApps = { host.recentApps }
        server.settings = service
        // After each change, wherever it was made (the Settings app, another program, a hand edit): the interface
        // language, and fuzzy pinyin in librime, as the Mac's settings window and iCloud sync apply them.
        let told = service.changed
        let rime = hostOptions.rime
        let fuzzy = Locked(initialState: startConfig.fuzzyPinyin)
        service.changed = { revision in
            let config = settings.current
            EngineLanguage.apply(config)
            let changed = fuzzy.withLock { applied -> Bool in
                defer { applied = config.fuzzyPinyin }
                return applied != config.fuzzyPinyin
            }
            if changed, let rime {
                // Deployed again: the fields get their new sessions once it is done.
                rime.applyFuzzyPinyin(config.fuzzyPinyin, deployed: { host.rimeBecameReady() })
            }
            told(revision)
        }
    }
    runningServer = server

    var listenerOptions = PipeListener.Options()
    listenerOptions.pendingInstances = options.instances
    listenerOptions.pipeName = pipe
    let listener: PipeListener
    do {
        listener = try PipeListener(server: server, sid: sid, options: listenerOptions, log: { log($0) })
    } catch {
        log("can't build the pipe's security descriptor: \(error): exiting", always: true)
        exit(1)
    }
    // FILE_FLAG_FIRST_PIPE_INSTANCE fails while something else holds the pipe's name (§2.1): the engine exits. With
    // the mutex held that is no other engine, but it may be the last one's pipe, which outlives its process a little
    // (a relaunch right after an exit): tried again for 2 s first.
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while true {
        do {
            try listener.start()
            break
        } catch let error as Win32Error where error.code == Win32Code.accessDenied
            && ProcessInfo.processInfo.systemUptime < deadline {
            Sleep(10)
        } catch {
            log("can't create the pipe: \(error): exiting", always: true)
            exit(1)
        }
    }
    let ready = msSinceProcessStart().map { String(format: "%.1f", $0) } ?? "?"
    log("ready in \(ready) ms since the process started: \(listener.pipeName), \(options.instances) instances waiting, "
        + "pid \(GetCurrentProcessId())"
        + (options.test ? ", test mode (\(options.systemClock ? "system" : "manual") clock"
            + (options.provider != nil ? ", scripted provider)" : ")") : "")
        + (options.noKeychain ? ", keys from the environment only" : ""), always: true)

    // Ctrl+C, Ctrl+Break, the console closed, logoff, shutdown: tell every client first (§2.5).
    SetConsoleCtrlHandler({ _ in
        runningServer?.bye(reason: "restart", retryMs: 500)
        writeStandardError("[engine] bye sent: exiting\n")
        exit(0)
    }, true)

    // In test mode, a sign that the main queue runs (the tests read it).
    if options.test { DispatchQueue.main.async { log("the main queue runs") } }

    // The watchdog (§2.5): a session queue stalled for more than 2 s, and the engine exits so that it is relaunched.
    // About once a second, the settings file: changed by something else (allinoneime-cli, an editor), the settings
    // windows are told (§12.6). Between its ticks this thread runs the main queue (the main run loop): what the core
    // posts there (`UIText.languageChanged` as the settings change the interface language) runs instead of piling up.
    var ticks = 0
    while true {
        let tick = ProcessInfo.processInfo.systemUptime
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        // Never a busy loop, should the run loop come back at once.
        let rest = 0.25 - (ProcessInfo.processInfo.systemUptime - tick)
        if rest > 0.01 { Sleep(DWORD(rest * 1000)) }
        let busy = server.longestBusy
        if busy > 2 {
            log("a session queue has been busy for \(Int(busy * 1000)) ms: exiting", always: true)
            exit(3)
        }
        ticks += 1
        if ticks % 4 == 0 { server.checkSettings() }  // on the settings' queue: this loop never waits for it
    }
}

// The child processes this program is too: `@js` code and script plugins (the core's `InlineCode`, `PluginRunner`).
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == InlineCode.javaScriptHostOption {
    exit(InlineCode.runJavaScriptHost())
}
if arguments.first == "--run-plugin" {
    guard let invocation = PluginHost.invocation(Array(arguments.dropFirst())) else { exit(2) }
    exit(PluginHost.run(directory: invocation.directory, language: invocation.language))
}
// And the process of each console window it opens, which stays open after the program in it ends.
if arguments.first == ConsoleHold.option {
    exit(ConsoleHold.run())
}
// The candidate window's samples, drawn into files.
if arguments.first == "--render-panel" {
    exit(renderPanels(Array(arguments.dropFirst())))
}
runEngine(parseOptions())

#else

_ = parseOptions()
fail("the engine serves the Windows pipe: Windows only for now")

#endif
