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
//
//   --test        test mode: Latin letters, a manual clock, level two from a golden's scripted provider, `x-test`
//                 directives accepted (`allinoneime-cli wire-replay` drives it), clients taken to own the foreground
//   --provider    test mode: level two from this scripted provider (a golden's fixture) from the start, as
//                 `#! provider` sets it
//   --clock       test mode: `manual` (the default: time moves only with `x-test advance` and `run tasks`) or
//                 `system`, so a scripted stream plays out in real time for a real app (the end-to-end test)
//   --config      the settings from FILE instead of %APPDATA%\AllInOneIME\config.json
//   --no-keychain API keys only from the environment (ANTHROPIC_API_KEY, ...), never the Credential Manager: for tests,
//                 which must neither read the user's keys nor tie them to a stub's address
//   --rime-data   rime-ice's data (default: rime-data beside the program, else ThirdParty's)
//   --rime-user   librime's user folder (default: %APPDATA%\AllInOneIME\rime): tests use their own, so that what they
//                 type isn't learned in the user's
//   --no-rime     Latin letters only
//   --no-panel    no candidate window
//   --instances   pipe instances kept waiting for a client (at least 4)
//   --quiet       log only the engine's start, its errors and its end
//
// It is also the child process `@js` code (`--run-js`) and script plugins (`--run-plugin DIR`) run in.

let usage = """
    usage: AllInOneIMEEngine [--test [--provider FILE] [--clock manual|system]] [--config FILE] [--no-keychain]
                             [--rime-data DIR] [--rime-user DIR] [--no-rime] [--no-panel] [--instances N] [--quiet]
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

func runEngine(_ options: EngineOptions) -> Never {
    let log = EngineLog(quiet: options.quiet)
    let sid: String
    do {
        sid = try Win32.currentUserSID()
    } catch {
        log("can't read the user's SID: \(error)", always: true)
        exit(1)
    }

    // One engine per user and session (§2.5).
    let mutex = PipeNames.mutex(sid: sid).withCString(encodedAs: UTF16.self) { CreateMutexW(nil, true, $0) }
    if mutex == nil || GetLastError() == Win32Code.alreadyExists {
        log("another engine is running for this user: exiting", always: true)
        exit(1)
    }

    // The candidate window is laid out per monitor, in physical pixels, as the caret reports come.
    _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
    if options.noKeychain {
        // Keys from the environment only (`APIKeys.load` falls back to it when the store has none).
        APIKeys.keychain = .inMemory()
    }

    let clock: WireClock = options.test && !options.systemClock ? ManualClock() : SystemClock()
    var hostOptions = EngineHost.Options(system: WindowsSystem())
    hostOptions.testMode = options.test
    hostOptions.foreground = { peer in peer.pid != nil && Win32.foregroundProcess() == peer.pid }
    hostOptions.settings = EngineSettings(url: options.config.map { URL(fileURLWithPath: $0) } ?? Config.userURL)
    hostOptions.executable = executablePath()
    if !options.test, !options.noRime {
        let executable = URL(fileURLWithPath: hostOptions.executable)
        let data = options.rimeData.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let location = EngineRime.locate(executable: executable, sharedData: data) {
            let userData = options.rimeUser.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? EngineRime.defaultUserData
            let rime = EngineRime(location: location, userData: userData, log: { log($0, always: true) })
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
    // Credential Manager (with --no-keychain, in memory). In test mode a golden gives its own (`#! settings`).
    if !options.test {
        let store = SettingsStore(configURL: hostOptions.settings.url, fresh: { EngineSettings.fresh })
        let service = SettingsService(store: store, platform: .windows, secrets: options.noKeychain ? .inMemory() : nil)
        // The document in the language the panel speaks: the config's, else Windows' own list.
        let engineSettings = hostOptions.settings
        service.interfaceLanguage = { engineSettings.interfaceLanguage($0) }
        server.settings = service
    }
    runningServer = server

    var listenerOptions = PipeListener.Options()
    listenerOptions.pendingInstances = options.instances
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

    // The watchdog (§2.5): a session queue stalled for more than 2 s, and the engine exits so that it is relaunched.
    // About once a second, the settings file: changed by something else (allinoneime-cli, an editor), the settings
    // windows are told (§12.6).
    var ticks = 0
    while true {
        Sleep(250)
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
runEngine(parseOptions())

#else

_ = parseOptions()
fail("the engine serves the Windows pipe: Windows only for now")

#endif
