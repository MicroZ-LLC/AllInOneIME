import AllInOneIMEWire
import Foundation
#if os(Windows)
import AllInOneIMEWindows
import WinSDK
#endif

/// `allinoneime-cli wire-replay [options] <file.jsonl>…`: replays golden transcripts (docs/wire-protocol-v1.md §10)
/// over the real pipe against a running engine in test mode (`AllInOneIMEEngine --test`), as a DLL would send them:
/// each `>` frame is written, then an `x-test idle` directive, and what the engine sent before the directive's answer
/// must be the `<` lines that follow, in order, and nothing else. The other directives go to the engine the same way
/// (`provider` with its fixture's contents); `connect`, `disconnect` and `closed` are the replay's own. It reports each
/// file, the round trip of every key (`keyDown`, `keyUp`: written to its `result` read) and, with `--cold-starts`, the
/// engine's start.
enum WireReplay {
    static let usage = """
        usage: allinoneime-cli wire-replay [options] <file.jsonl>...

        Replays wire-protocol goldens over the engine's pipe (the engine runs with --test).

        options:
          --launch EXE       start EXE --test for the replay (else one must be running), and stop it after
          --cold-starts N    first start EXE (--launch) N times, each until its welcome, and report the times
          --repeat N         replay the files N times (more key round trips to measure)
          --timeout MS       the longest to wait for a frame (default 5000)
          --no-server-check  skip the DLL's server check (§2.1)
        """

    static func main(_ arguments: [String]) -> Int32 {
        #if os(Windows)
        return Runner.run(arguments)
        #else
        FileHandle.standardError.write(Data("wire-replay: the engine's pipe is Windows only\n".utf8))
        return 1
        #endif
    }
}

#if os(Windows)
extension WireReplay {
    struct Failure: Error, CustomStringConvertible {
        var line: Int
        var message: String
        var description: String { "line \(line): \(message)" }
    }

    struct Options {
        var files: [String] = []
        var launch: String?
        var coldStarts = 0
        var repeatCount = 1
        var timeout: DWORD = 5000
        var serverCheck = true
    }

    final class Runner {
        let options: Options
        let sid: String
        let pipe: String
        /// Key round trips, in ms.
        var keyTimes: [Double] = []
        var checkedServer = false

        init(options: Options, sid: String) {
            self.options = options
            self.sid = sid
            pipe = PipeNames.pipe(sid: sid)
        }

        static func run(_ arguments: [String]) -> Int32 {
            guard let options = parse(arguments) else { return 2 }
            let sid: String
            do {
                sid = try Win32.currentUserSID()
            } catch {
                say("can't read the user's SID: \(error)")
                return 1
            }
            return Runner(options: options, sid: sid).run()
        }

        static func parse(_ arguments: [String]) -> Options? {
            var options = Options()
            var args = arguments[...]
            func number(_ flag: String) -> Int? {
                guard let n = args.popFirst().flatMap(Int.init), n >= 0 else {
                    say("\(flag) needs a number")
                    return nil
                }
                return n
            }
            while let arg = args.popFirst() {
                switch arg {
                case "--launch":
                    guard let path = args.popFirst() else { say("--launch needs the engine's path"); return nil }
                    options.launch = path
                case "--cold-starts": guard let n = number(arg) else { return nil }; options.coldStarts = n
                case "--repeat": guard let n = number(arg), n > 0 else { return nil }; options.repeatCount = n
                case "--timeout": guard let n = number(arg) else { return nil }; options.timeout = DWORD(n)
                case "--no-server-check": options.serverCheck = false
                case "--help", "-h":
                    print(WireReplay.usage)
                    exit(0)
                default:
                    guard !arg.hasPrefix("--") else { say("unknown option \(arg)\n\(WireReplay.usage)"); return nil }
                    options.files.append(arg)
                }
            }
            guard !options.files.isEmpty else { say(WireReplay.usage); return nil }
            if options.coldStarts > 0, options.launch == nil { say("--cold-starts needs --launch"); return nil }
            return options
        }

        static func say(_ text: String) { FileHandle.standardError.write(Data("wire-replay: \(text)\n".utf8)) }

        func run() -> Int32 {
            if options.coldStarts > 0, let launch = options.launch {
                guard measureColdStarts(launch, runs: options.coldStarts) else { return 1 }
            }
            var engine: Process?
            if let launch = options.launch {
                do {
                    engine = try start(launch)
                } catch {
                    Self.say("can't start \(launch): \(error)")
                    return 1
                }
            }
            defer { stop(engine) }

            var failures = 0
            for round in 1...options.repeatCount {
                for file in options.files {
                    let name = URL(fileURLWithPath: file).lastPathComponent
                    let started = Win32.preciseNow()
                    do {
                        let frames = try replay(URL(fileURLWithPath: file))
                        if round == 1 || options.repeatCount <= 3 {
                            let ms = (Win32.preciseNow() - started) * 1000
                            print("ok    \(name) (\(frames) frames from the engine, \(String(format: "%.0f", ms)) ms)")
                        }
                    } catch {
                        failures += 1
                        print("FAIL  \(name) (run \(round)): \(error)")
                    }
                }
            }
            let runs = options.files.count * options.repeatCount
            print(failures == 0 ? "all \(runs) replays passed (\(options.files.count) files × \(options.repeatCount))"
                : "\(failures) of \(runs) replays failed")
            if !keyTimes.isEmpty {
                // The engine's first key pays for what the core sets up once (the command catalog, the Composer's
                // tables): shown apart.
                print(String(format: "the engine's first key: %.3f ms", keyTimes[0]))
                print("key round trips: \(keyTimes.count), " + Self.percentiles(keyTimes))
                if keyTimes.count > 1 { print("  without the first: " + Self.percentiles(Array(keyTimes.dropFirst()))) }
            }
            return failures == 0 ? 0 : 1
        }

        static func percentiles(_ values: [Double]) -> String {
            let sorted = values.sorted()
            func at(_ p: Double) -> String {
                String(format: "%.3f", sorted[min(sorted.count - 1, Int((p * Double(sorted.count - 1)).rounded()))])
            }
            return "p50 \(at(0.5)) ms, p90 \(at(0.9)) ms, p99 \(at(0.99)) ms, max \(String(format: "%.3f", sorted.last!)) ms"
        }

        // MARK: - The engine

        func start(_ path: String, quiet: Bool = true) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--test"] + (quiet ? ["--quiet"] : [])
            try process.run()
            return process
        }

        func stop(_ process: Process?) {
            guard let process, process.isRunning else { return }
            process.terminate()
            process.waitUntilExit()
            // Its pipe outlives it a little: wait until it is gone, so that the next engine's first instance is its own.
            let deadline = Win32.preciseNow() + 2
            while Win32.preciseNow() < deadline {
                let gone = pipe.withCString(encodedAs: UTF16.self) { WaitNamedPipeW($0, 1) } == false
                    && GetLastError() == Win32Code.fileNotFound
                if gone { break }
                Sleep(1)
            }
        }

        /// Starts the engine `runs` times, each until its `welcome`: the cold start as a DLL sees it.
        func measureColdStarts(_ path: String, runs: Int) -> Bool {
            var opened: [Double] = []
            var welcomed: [Double] = []
            for _ in 0..<runs {
                let t0 = Win32.preciseNow()
                let process: Process
                do {
                    process = try start(path)
                } catch {
                    Self.say("can't start \(path): \(error)")
                    return false
                }
                defer { stop(process) }
                do {
                    let client = try PipeClient.connect(name: pipe, timeout: 10)
                    defer { client.close() }
                    let t1 = Win32.preciseNow()
                    let hello = ClientFrame(id: 1, .hello(Hello(client: "wire-replay", pid: GetCurrentProcessId(),
                                                                tid: GetCurrentThreadId())))
                    try client.send(WireJSON.encode(hello))
                    let answer = try WireJSON.decode(EngineFrame.self, from: client.receive(timeout: options.timeout))
                    guard case .welcome = answer.message else {
                        Self.say("cold start: the engine answered hello with \(answer.message.type)")
                        return false
                    }
                    let t2 = Win32.preciseNow()
                    opened.append((t1 - t0) * 1000)
                    welcomed.append((t2 - t0) * 1000)
                } catch {
                    Self.say("cold start: \(error)")
                    return false
                }
            }
            print("cold start, \(runs) runs: launch to pipe open: " + Self.percentiles(opened))
            print("cold start, \(runs) runs: launch to welcome:   " + Self.percentiles(welcomed))
            print("  each, in order: " + welcomed.map { String(format: "%.1f", $0) }.joined(separator: " ") + " ms")
            return true
        }

        // MARK: - Replaying

        func connect() throws -> PipeClient {
            let client = try PipeClient.connect(name: pipe, timeout: 10)
            if options.serverCheck {
                let problems = client.checkServer(sid: sid)
                guard problems.isEmpty else {
                    client.close()
                    throw Failure(line: 0, message: "the server check failed: " + problems.joined(separator: "; "))
                }
                if !checkedServer {
                    checkedServer = true
                    let facts = client.serverFacts()
                    print("server check passed: engine pid \(facts.pid ?? 0), session \(facts.session ?? 0), integrity RID 0x"
                        + String(facts.token?.integrityRID ?? 0, radix: 16) + ", pipe label RID 0x"
                        + String(facts.labelRID ?? 0, radix: 16))
                }
            }
            return client
        }

        /// One golden over the pipe; the number of frames the engine sent.
        func replay(_ url: URL) throws -> Int {
            let transcript = try WireTranscript(contentsOf: url)
            let directory = url.deletingLastPathComponent()
            var client: PipeClient? = try connect()
            defer { client?.close() }
            var pending: [(body: Data, after: Int)] = []
            var closedByEngine = false
            var received = 0
            var lastLine = 0

            func unexpected(_ line: Int) throws {
                guard let first = pending.first else { return }
                throw Failure(line: line, message: "the engine sent a frame no line expects (after line \(first.after)): "
                    + String(decoding: first.body, as: UTF8.self))
            }

            /// Sends an `x-test` directive and reads up to its answer: what came before it, and whether it was done.
            func direct(_ directive: String, fixture: ScriptedProvider.Fixture? = nil, line: Int,
                        keyID: UInt32? = nil, sent: Double = 0) throws -> (frames: [Data], ok: Bool) {
                guard let connection = client else { throw Failure(line: line, message: "not connected") }
                if !closedByEngine {
                    do {
                        try connection.send(WireJSON.encode(TestFrame(directive: directive, fixture: fixture)))
                    } catch PipeChannel.Failure.closed {
                        closedByEngine = true
                    }
                }
                var frames: [Data] = []
                while !closedByEngine {
                    let body: Data
                    do {
                        body = try connection.receive(timeout: options.timeout)
                    } catch PipeChannel.Failure.closed {
                        closedByEngine = true
                        break
                    } catch PipeChannel.Failure.timeout {
                        throw Failure(line: line, message: "no answer to x-test \(directive) within \(options.timeout) ms")
                    }
                    let value = try JSONValue(parsing: String(decoding: body, as: UTF8.self))
                    if value["type"]?.stringValue == TestFrame.type {
                        return (frames, value["ok"] == .bool(true))
                    }
                    if let keyID, value["re"]?.intValue == Int(keyID) {
                        keyTimes.append((Win32.preciseNow() - sent) * 1000)
                    }
                    frames.append(body)
                }
                return (frames, false)
            }

            for step in transcript.steps {
                lastLine = step.line
                switch step {
                case let .send(value, line):
                    try unexpected(line)
                    guard let connection = client else { throw Failure(line: line, message: "not connected") }
                    let body = try WireJSON.encode(WireTranscript.sendable(value))
                    let type = value["type"]?.stringValue
                    let keyID = type == "keyDown" || type == "keyUp" ? value["id"]?.intValue.map(UInt32.init) : nil
                    let sent = Win32.preciseNow()
                    do {
                        try connection.send(body)
                    } catch PipeChannel.Failure.closed {
                        throw Failure(line: line, message: "the engine closed the connection")
                    }
                    let (frames, _) = try direct("idle", line: line, keyID: keyID, sent: sent)
                    received += frames.count
                    pending += frames.map { ($0, line) }

                case let .expect(expected, line):
                    guard !pending.isEmpty else { throw Failure(line: line, message: "the engine sent nothing") }
                    let body = pending.removeFirst().body
                    let actual = try JSONValue(parsing: String(decoding: body, as: UTF8.self))
                    if let mismatch = WireTranscript.mismatch(expected: expected, actual: actual) {
                        throw Failure(line: line, message: "\(mismatch)\n  got: \(actual.compact)")
                    }

                case let .directive(text, line):
                    let words = text.split(separator: " ").map(String.init)
                    switch words.first {
                    case "keys":
                        continue  // typed in a field the client sends nothing from
                    case "connect":
                        try unexpected(line)
                        client?.close()
                        client = try connect()
                        closedByEngine = false
                    case "disconnect":
                        try unexpected(line)
                        client?.close()
                        client = nil
                    case "closed":
                        try unexpected(line)
                        guard let connection = client else { throw Failure(line: line, message: "not connected") }
                        if !closedByEngine {
                            do {
                                let body = try connection.receive(timeout: 2000)
                                throw Failure(line: line, message: "the engine sent a frame instead of closing: "
                                    + String(decoding: body, as: UTF8.self))
                            } catch PipeChannel.Failure.closed {
                                closedByEngine = true
                            } catch PipeChannel.Failure.timeout {
                                throw Failure(line: line, message: "the engine didn't close the connection")
                            }
                        }
                        connection.close()
                        client = nil
                    default:
                        try unexpected(line)
                        var fixture: ScriptedProvider.Fixture?
                        if words.first == "provider", words.count == 2 {
                            fixture = try WireJSON.decode(ScriptedProvider.Fixture.self,
                                                          from: Data(contentsOf: directory.appendingPathComponent(words[1])))
                        }
                        let (frames, ok) = try direct(text, fixture: fixture, line: line)
                        guard ok else {
                            throw Failure(line: line, message: "the engine didn't do \"\(text)\" (is it in test mode?)")
                        }
                        received += frames.count
                        pending += frames.map { ($0, line) }
                    }
                }
            }
            try unexpected(lastLine + 1)
            return received
        }
    }
}
#endif
