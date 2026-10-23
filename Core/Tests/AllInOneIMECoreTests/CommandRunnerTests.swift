import Foundation
import Testing
@testable import AllInOneIMECore

struct CommandRunnerTests {
    #if os(Windows)
    // Git for Windows' tools (echo, sh, rev, sleep, yes), where the Mac has them in /usr/bin and /bin.
    let environment = ["PATH": WindowsTestTools.gitTools ?? ""]
    #else
    let environment = ["PATH": "/usr/bin:/bin"]
    #endif

    func run(_ command: CustomCommand, _ input: String) async -> Result<String, Error> {
        do {
            var text = ""
            for try await update in CommandRunner.run(command, input: input, environment: environment) where update.isFinal {
                text = update.result.versions.first?.text ?? ""
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    @Test func printsBecomeTheResult() async throws {
        let echo = CustomCommand(name: "echo", type: .run, argv: ["echo", "{input}"])
        #expect(try await run(echo, "hello; world").get() == "hello; world")  // no shell: ";" is just text
        let multi = CustomCommand(name: "sh", type: .run, argv: ["sh", "-c", "{input}"])
        #expect(try await run(multi, "printf 'a\\n\\033[31mb\\033[0m\\n\\n'").get() == "a\nb")  // colors and trailing lines dropped
    }

    /// What goes into a terminal (it runs every line): one line, nothing that would run or complete.
    @Test func oneLineForATerminal() {
        let result = ConversionResult(versions: [CandidateLine("0\n1\n2"), CandidateLine("a\tb\u{2028}c", isComplete: false),
                                                 CandidateLine("你好\n世界\nok")])
        let line = CommandRunner.oneLine(result)
        #expect(line.versions.map(\.text) == ["0 1 2", "a b c", "你好世界 ok"])
        #expect(line.versions.map(\.isComplete) == [true, false, true])
        #expect(CommandRunner.oneLine(ConversionResult(versions: [CandidateLine("391")])).versions.map(\.text) == ["391"])
    }

    @Test func standardInput() async throws {
        #if os(Windows)
        // Git for Windows has no rev: its perl reverses the line.
        let rev = CustomCommand(name: "rev", type: .run, argv: ["perl", "-nle", "print scalar reverse"], stdin: "{input}\n")
        #else
        let rev = CustomCommand(name: "rev", type: .run, argv: ["rev"], stdin: "{input}\n")
        #endif
        #expect(try await run(rev, "abc").get() == "cba")
    }

    #if canImport(Darwin)
    /// What is written to the standard input of a program that ended without reading it fails (EPIPE), and ends nothing
    /// else: no SIGPIPE for the process writing it (`CommandRunner` writes it off its queue, maybe once a quick program
    /// is over; a test run, the Settings app, don't ignore SIGPIPE as the input method does).
    @Test func writingToAProgramThatEndedFailsWithoutSIGPIPE() throws {
        let stdin = Pipe()
        let ended = DispatchSemaphore(value: 0)
        let spec = LaunchSpec(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 0"], standardInput: .pipe(stdin),
                              standardOutput: .null, standardError: .null) { _ in ended.signal() }
        _ = try FoundationProcessLauncher().launch(spec)
        #expect(ended.wait(timeout: .now() + 10) == .success)
        #expect(throws: (any Error).self) { try stdin.fileHandleForWriting.write(contentsOf: Data("unread".utf8)) }
    }
    #endif

    @Test func failuresSayWhatWentWrong() async {
        let sh = CustomCommand(name: "sh", type: .run, argv: ["sh", "-c", "{input}"])
        let failed = await run(sh, "echo first >&2; echo 'the reason' >&2; echo '  ~~^~~' >&2; exit 3")
        #expect(failed.error == .failed(status: 3, message: "the reason"))
        let missing = CustomCommand(name: "x", type: .run, argv: ["no-such-program-here"])
        #expect(await run(missing, "").error == .notFound("no-such-program-here"))
    }

    @Test func slowProgramsAreStopped() async {
        // Stopped at the 0.3 s limit, well before the minute it would sleep (`Timing`: the bound holds under load).
        let sleep = CustomCommand(name: "sleep", type: .run, argv: ["sleep", "{input}"], timeoutSeconds: 0.3)
        let started = Date()
        #expect(await run(sleep, "\(Timing.longSleep)").error == .timedOut(0.3))
        #expect(Date().timeIntervalSince(started) < Timing.wellBeforeLongSleep)
    }

    @Test func endlessOutputIsStopped() async {
        let yes = CustomCommand(name: "yes", type: .run, argv: ["yes"], timeoutSeconds: 5)
        #expect(await run(yes, "").error == .tooMuchOutput)
    }

    @Test func cancellingStopsTheProgram() async throws {
        // A minute's sleep with a limit past it: only the cancel can stop it well before.
        let sleep = CustomCommand(name: "sleep", type: .run, argv: ["sleep", "\(Timing.longSleep)"],
                                  timeoutSeconds: Double(Timing.longSleep * 2))
        let started = Date()
        let task = Task { await run(sleep, "") }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        _ = await task.value
        #expect(Date().timeIntervalSince(started) < Timing.wellBeforeLongSleep)
    }

    @Test func resolvesProgramsOnPath() {
        #if os(Windows)
        // PATH split on ";", PATHEXT's extensions added ("cmd" → cmd.exe).
        let system = WindowsTestTools.systemFolder
        let cmd = URL(fileURLWithPath: system, isDirectory: true).appendingPathComponent("cmd.exe").path
        #expect(CommandRunner.resolve("cmd", path: #"C:\nowhere;"# + system)?.path == cmd)
        #expect(CommandRunner.resolve(cmd, path: nil)?.path == cmd)
        #expect(CommandRunner.resolve("cmd", path: #"C:\nowhere"#) == nil)
        #else
        #expect(CommandRunner.resolve("sh", path: "/nowhere:/bin")?.path == "/bin/sh")
        #expect(CommandRunner.resolve("/bin/sh", path: nil)?.path == "/bin/sh")
        #expect(CommandRunner.resolve("sh", path: "/nowhere") == nil)
        #endif
    }
}

private extension Result where Failure == Error {
    var error: CommandRunner.RunError? {
        if case let .failure(error) = self { return error as? CommandRunner.RunError }
        return nil
    }
}
