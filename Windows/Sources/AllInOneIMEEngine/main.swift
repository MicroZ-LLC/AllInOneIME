import AllInOneIMECore
import AllInOneIMEWire
import Foundation
#if os(Windows)
import AllInOneIMEWindows
import WinSDK
#endif

// The per-user engine (wire protocol v1, docs/wire-protocol-v1.md in the core): one process per user and session,
// single-instance through `Local\AllInOneIME-Engine-<SID>`, serving the TSF DLLs of every app over
// `\\.\pipe\AllInOneIME-<SID>-v1`. Each client connection gets a serial queue and its fields a Composer each.
//
//   AllInOneIMEEngine [--test] [--instances N] [--quiet]
//
//   --test        test mode: a manual clock, level two from a golden's scripted provider, `x-test` directives
//                 accepted (`allinoneime-cli wire-replay` drives it), clients taken to own the foreground
//   --instances   pipe instances kept waiting for a client (at least 4)
//   --quiet       log only the engine's start, its errors and its end

let usage = "usage: AllInOneIMEEngine [--test] [--instances N] [--quiet]"

struct EngineOptions {
    var test = false
    var instances = 4
    var quiet = false
}

func parseOptions() -> EngineOptions {
    var options = EngineOptions()
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.popFirst() {
        switch arg {
        case "--test": options.test = true
        case "--quiet": options.quiet = true
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
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("AllInOneIMEEngine: \(message)\n".utf8))
    exit(2)
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
        FileHandle.standardError.write(Data("[engine +\(ms)ms] \(message)\n".utf8))
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

    let clock: WireClock = options.test ? ManualClock() : SystemClock()
    let host = EngineHost(testMode: options.test, clock: clock,
                          foreground: { peer in peer.pid != nil && Win32.foregroundProcess() == peer.pid },
                          log: { log($0) })
    var configuration = WireServer.Configuration()
    configuration.enginePid = GetCurrentProcessId()
    configuration.testControl = options.test
    if options.test {
        // The goldens' replays connect again and again on a clock that barely moves.
        configuration.connectsPerProcessPerSecond = 1_000_000
    }
    let environment = WireEnvironment(host: host, clock: clock, makeComposer: { host.makeComposer($0, $1) }, log: { log($0) })
    let server = WireServer(configuration: configuration, environment: environment)
    server.testDirective = { host.testDirective($0, $1) }
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
        + "pid \(GetCurrentProcessId())\(options.test ? ", test mode" : "")", always: true)

    // Ctrl+C, Ctrl+Break, the console closed, logoff, shutdown: tell every client first (§2.5).
    SetConsoleCtrlHandler({ _ in
        runningServer?.bye(reason: "restart", retryMs: 500)
        FileHandle.standardError.write(Data("[engine] bye sent: exiting\n".utf8))
        exit(0)
    }, true)

    // The watchdog (§2.5): a session queue stalled for more than 2 s, and the engine exits so that it is relaunched.
    while true {
        Sleep(250)
        let busy = server.longestBusy
        if busy > 2 {
            log("a session queue has been busy for \(Int(busy * 1000)) ms: exiting", always: true)
            exit(3)
        }
    }
}

runEngine(parseOptions())

#else

_ = parseOptions()
fail("the engine serves the Windows pipe: Windows only for now")

#endif
