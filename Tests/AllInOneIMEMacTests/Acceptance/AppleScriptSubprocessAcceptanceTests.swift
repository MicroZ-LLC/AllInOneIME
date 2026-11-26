import AllInOneIMEMac
import Foundation
import Testing

/// Reproduces item 26 for the app executable's AppleScript runners:
/// - `TerminalLauncher.osascript` calls `waitUntilExit()` before draining stdout (pipe deadlock past 64 KB)
///   and enforces no total timeout.
/// - `AppleScriptMessageSender.run` waits on `osascript` with no timeout.
/// - `NotesBridge` runs `NSAppleScript` on a serial queue with no timeout (blocking subsequent calls) and its
///   AppleScripts do not wrap `tell application "Notes"` in `with timeout of N seconds`.
///
/// Seams: the three types live in the `AllInOneIME` executable target, so this suite compiles the real
/// production files (`TerminalLauncher.swift`, `MessageSending.swift`, `NotesBridge.swift`) into an isolated
/// test child via `SourceCompiler` (exposing `private static func osascript` / `private static func run` in
/// the temporary copy). Because `TerminalLauncher.osascript`, `AppleScriptMessageSender.run`, and
/// `NotesBridge.run` currently have no timeout parameters, production fixes can honor optional positive
/// `TimeInterval` overrides in `ALLINONEIME_OSASCRIPT_TIMEOUT` (for TerminalLauncher and
/// AppleScriptMessageSender) and `ALLINONEIME_NOTES_TIMEOUT` (or wrap every script in `NotesBridge.scripts`
/// with `with timeout of N seconds ... end timeout`) so these tests stay under a few seconds.
@Suite(.serialized)
struct AppleScriptSubprocessAcceptanceTests {
    @Test func terminalOsascriptReadsMoreThan64KBWithoutDeadlock() throws {
        let result = try AppleScriptChild.run(["terminal-large"], limit: 2.5)
        #expect(!result.timedOut, "TerminalLauncher.osascript deadlocked on 100 KB stdout: \(result.output)")
        if !result.timedOut {
            #expect(result.status == 0 && result.output.contains("COUNT 100000"),
                    "TerminalLauncher.osascript did not return all 100,000 bytes: \(result.output)")
        }
    }

    @Test func terminalOsascriptStopsAnUnresponsiveScriptWithinTimeout() throws {
        let result = try AppleScriptChild.run(
            ["terminal-timeout"],
            environment: ["ALLINONEIME_OSASCRIPT_TIMEOUT": "0.3"],
            limit: 5
        )
        #expect(!result.timedOut, "TerminalLauncher.osascript hung past the harness limit: \(result.output)")
        #expect(result.elapsed < 2, "TerminalLauncher.osascript waited \(String(format: "%.2f", result.elapsed)) s with no timeout")
        if result.elapsed < 2 {
            #expect(result.output.contains("NIL"), "hanging TerminalLauncher.osascript should return nil: \(result.output)")
        }
    }

    @Test func messageSenderStopsAnUnresponsiveScriptWithinTimeout() throws {
        let result = try AppleScriptChild.run(
            ["messages-timeout"],
            environment: ["ALLINONEIME_OSASCRIPT_TIMEOUT": "0.3"],
            limit: 5
        )
        #expect(!result.timedOut, "AppleScriptMessageSender.run hung past the harness limit: \(result.output)")
        #expect(result.elapsed < 2, "AppleScriptMessageSender.run waited \(String(format: "%.2f", result.elapsed)) s with no timeout")
        if result.elapsed < 2 {
            #expect(result.output.contains("THREW"), "hanging AppleScriptMessageSender.run should throw: \(result.output)")
        }
    }

    @Test func notesBridgeEnforcesATimeoutSoOneCallCannotBlockTheQueue() throws {
        let result = try AppleScriptChild.run(
            ["notes-timeout"],
            environment: ["ALLINONEIME_NOTES_TIMEOUT": "0.3"],
            limit: 5
        )
        #expect(!result.timedOut, "NotesBridge hung past the harness limit: \(result.output)")
        #expect(result.output.contains("SCRIPTS_TIMEOUT_OK") || result.output.contains("FOLLOWUP ok"),
                "NotesBridge follow-up did not complete: \(result.output)")
        #expect(result.elapsed < 2,
                "NotesBridge has no AppleScript timeout and blocked the serial queue for \(String(format: "%.2f", result.elapsed)) s")
    }
}

private enum AppleScriptChild {
    struct RunResult {
        var status: Int32
        var output: String
        var elapsed: TimeInterval
        var timedOut: Bool
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("applescript-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let appSources = repository.appendingPathComponent("Sources/AllInOneIME")

        let terminalText = try String(contentsOf: appSources.appendingPathComponent("TerminalLauncher.swift"), encoding: .utf8)
            .replacingOccurrences(of: "private static func osascript(", with: "static func osascript(")
        let terminalFile = scratch.appendingPathComponent("TerminalLauncher.swift")
        try terminalText.write(to: terminalFile, atomically: true, encoding: .utf8)

        let messageText = try String(contentsOf: appSources.appendingPathComponent("MessageSending.swift"), encoding: .utf8)
            .replacingOccurrences(of: "private static func run(", with: "static func run(")
        let messageFile = scratch.appendingPathComponent("MessageSending.swift")
        try messageText.write(to: messageFile, atomically: true, encoding: .utf8)

        let notesFile = appSources.appendingPathComponent("NotesBridge.swift")
        let harnessFile = scratch.appendingPathComponent("main.swift")
        try harnessSource.write(to: harnessFile, atomically: true, encoding: .utf8)

        let executable = scratch.appendingPathComponent("applescript-harness")
        let swift = try SourceCompiler.compile(
            repository: repository,
            sources: [terminalFile.path, messageFile.path, notesFile.path, harnessFile.path],
            executable: executable,
            timeout: 60
        )
        guard swift.status == 0 else { throw Failure(description: swift.output) }
        return executable
    }

    static func run(_ arguments: [String], environment: [String: String] = [:], limit: TimeInterval) throws -> RunResult {
        let executable = try compiled.get()
        let out = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = out
        let started = Date()
        try process.run()
        let collected = Locked(initialState: Data())
        let readDone = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            collected.withLock { $0 = data }
            readDone.signal()
        }
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            let pid = process.processIdentifier
            _ = kill(-pid, SIGKILL)
            _ = kill(pid, SIGKILL)
            process.waitUntilExit()
        }
        _ = readDone.wait(timeout: .now() + 1)
        let elapsed = Date().timeIntervalSince(started)
        let text = String(decoding: collected.withLock { $0 }, as: UTF8.self)
        return RunResult(status: process.terminationStatus, output: text, elapsed: elapsed, timedOut: timedOut)
    }

    static let harnessSource = #"""
import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import os

let log = Logger(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "test")

enum ClaudeSessionMac {
    static func agent(program: String) -> SessionAgent? { nil }
    static func program(_ agent: SessionAgent) -> URL? { nil }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first else {
    fputs("usage: <mode>\n", stderr)
    exit(2)
}

func scriptsHaveTimeout() -> Bool {
    guard NotesBridge.scripts.count >= 3 else { return false }
    let pattern = #"with\s+timeout\s+of\s+[1-9]\d*\s+seconds"#
    for source in NotesBridge.scripts {
        var error: NSDictionary?
        guard let compiled = NSAppleScript(source: source), compiled.compileAndReturnError(&error) else {
            return false
        }
        guard source.range(of: pattern, options: .regularExpression) != nil,
              source.range(of: #"end\s+timeout"#, options: .regularExpression) != nil else {
            return false
        }
    }
    return true
}

switch mode {
case "terminal-large":
    let lines = [
        "set s to \"xxxxxxxxxx\"",
        "repeat 14 times",
        "set s to s & s",
        "end repeat",
        "return text 1 thru 100000 of s",
    ]
    if let answer = TerminalLauncher.osascript(lines) {
        print("COUNT \(answer.utf8.count)")
    } else {
        print("NIL")
    }
case "terminal-timeout":
    if let answer = TerminalLauncher.osascript(["delay 3", "return \"late\""]) {
        print("OK \(answer.utf8.count)")
    } else {
        print("NIL")
    }
case "messages-timeout":
    do {
        try AppleScriptMessageSender.run(["-e", "delay 3"])
        print("OK")
    } catch {
        print("THREW \(error)")
    }
case "notes-timeout":
    if scriptsHaveTimeout() {
        print("SCRIPTS_TIMEOUT_OK")
        exit(0)
    }
    let done = DispatchSemaphore(value: 0)
    Task {
        let hanging = Task {
            try? await NotesBridge.run("on run argv\ndelay 3\nend run", []) { _ in () }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let answer = (try? await NotesBridge.run("on run argv\nreturn \"ok\"\nend run", []) { $0.stringValue ?? "" }) ?? ""
        _ = await hanging.value
        print("FOLLOWUP \(answer)")
        done.signal()
    }
    done.wait()
default:
    fputs("unknown mode: \(mode)\n", stderr)
    exit(2)
}
"""#
}
