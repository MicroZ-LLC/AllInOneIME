import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// Settings' examples the core knows of (`CommandExamples`): `@py`, a line of Python run REPL style with the user's
/// `python3`, as a run command of the user's own.
struct CommandExamplesTests {
    @Test func python() throws {
        let py = CommandExamples.python
        #expect(py.argv == ["python3", "-X", "utf8", "-c", CommandExamples.pythonREPL])
        #expect(py.type == .run && py.typesLatin && py.timeout == CustomCommand.defaultTimeout && py.isValid)
        // The code goes on standard input with full-width punctuation as ASCII; the arguments never change.
        #expect(py.standardInput(for: "print（“牛逼”）") == "print(\"牛逼\")")
        #expect(py.arguments(for: "print（“牛逼”）") == py.argv && py.arguments(for: "{input}") == py.argv)
        // Saved and read back, it is the same command (the editor's Command field is one line).
        let decoded = try JSONDecoder().decode(CustomCommand.self, from: try JSONEncoder().encode(py))
        #expect(decoded == py)
        #expect(CustomCommand.arguments(fromCommandLine: CustomCommand.commandLine(try #require(py.argv))) == py.argv)
        // Once added it is the user's own: offered only where python3 runs, its text taken as typed.
        let command = try #require(Command.catalog([py]).first { $0.name == "py" })
        #expect(command.custom == py && command.program == "python3" && command.runsCode && !command.isCode)
        #expect(CommandPlan.canBeInner(command))
    }

    // MARK: - Python

    /// The folders with a python3 that would run (none: the Python tests are skipped), one per interpreter.
    static let pythons: [String] = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        var seen = Set<String>()
        return path.split(separator: ":").map(String.init).filter { folder in
            guard CommandRunner.isInstalled("python3", path: folder),
                  let url = CommandRunner.resolve("python3", path: folder) else { return false }
            return seen.insert(url.resolvingSymlinksInPath().path).inserted
        }
    }()

    /// `code` through the example's program, the way the input method runs it, with the python3 in `folder`: within
    /// `timeout` seconds, by default a limit no busy test run reaches (`Timing`; a Python started for the first time on a
    /// runner takes seconds), since what it prints is checked, not how long it takes.
    func python(_ code: String, in folder: String, timeout: Double = Double(Timing.longSleep)) async -> Result<String, Error> {
        var definition = CommandExamples.python
        definition.timeoutSeconds = timeout
        do {
            var text = ""
            let environment = ["PATH": folder, "HOME": NSHomeDirectory()]
            for try await update in CommandRunner.run(definition, input: code, environment: environment) where update.isFinal {
                text = update.result.versions.first?.text ?? ""
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    @Test(.enabled(if: !CommandExamplesTests.pythons.isEmpty)) func pythonIsREPLStyle() async throws {
        let cases: [(code: String, result: String)] = [
            ("2**100", "1267650600228229401496703205376"),  // the value of the last expression
            ("'abc'.upper()", "ABC"),  // a str as it is
            ("[1, 'a', None]", "[1, 'a', None]"),  // anything else with repr
            ("b'x'", "b'x'"),
            ("x = 6; x * 7", "42"),
            ("1; 2", "2"),  // only the last expression
            ("print('hi')", "hi"),  // its value, None, isn't printed
            ("print('a'); 1 + 1", "a\n2"),  // what it printed, then the value
            ("for i in range(3): print(i)", "0\n1\n2"),  // statements: what they print
            ("x = 5", ""),
            ("import math; math.sqrt(16)", "4.0"),
            ("import sys; print('warning', file=sys.stderr); 42", "42"),  // standard error doesn't count when it works
            ("'你好' * 2", "你好你好"),
            ("print（“牛逼”）", "牛逼"),  // full-width punctuation from Chinese typing
            ("__name__", "__main__"),
            ("[k for k in globals() if not k.startswith('__')]", "[]"),  // a namespace of its own
            ("exit()", ""),
        ]
        for folder in Self.pythons {
            for (code, result) in cases {
                let got = await python(code, in: folder)
                #expect((try? got.get()) == result, "\(code) with the python3 in \(folder): \(got)")
            }
        }
    }

    /// An error is the last line Python prints (`CommandRunner`): no line number, and of a message of several lines only
    /// its last.
    @Test(.enabled(if: !CommandExamplesTests.pythons.isEmpty)) func pythonErrorsAreTheirLastLine() async throws {
        let cases: [(code: String, error: CommandRunner.RunError)] = [
            ("1/0", .failed(status: 1, message: "ZeroDivisionError: division by zero")),
            ("raise ValueError('first line\\nsecond line')", .failed(status: 1, message: "second line")),
            ("x = 1\ny = 0\nx / y", .failed(status: 1, message: "ZeroDivisionError: division by zero")),
            ("input()", .failed(status: 1, message: "EOFError: EOF when reading a line")),  // no standard input to read
            ("import sys; sys.exit('bad input')", .failed(status: 1, message: "bad input")),
            ("import sys; sys.exit(3)", .failed(status: 3, message: "")),
        ]
        for folder in Self.pythons {
            for (code, error) in cases {
                let got = await python(code, in: folder)
                #expect(got.runError == error, "\(code) with the python3 in \(folder): \(got)")
            }
            // The wording of syntax errors changes between Python versions.
            guard case let .failed(status, message)? = await python("print(", in: folder).runError else {
                Issue.record("print( didn't fail with the python3 in \(folder)")
                continue
            }
            #expect(status == 1 && message.hasPrefix("SyntaxError: ") && !message.contains("\n"), "\(message)")
            #expect(await python("while True: pass", in: folder, timeout: 0.5).runError == .timedOut(0.5))
        }
    }

    @Test(.enabled(if: !CommandExamplesTests.pythons.isEmpty)) func pythonIgnoresLookalikeModulesInTheWorkingDirectory() throws {
        let fm = FileManager.default
        let folder = TestScratch.temporary("command-examples-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        try Data("raise ImportError('not the standard ast')\n".utf8).write(to: folder.appendingPathComponent("ast.py"))
        try Data("VALUE = 42\n".utf8).write(to: folder.appendingPathComponent("helper.py"))
        let argv = try #require(CommandExamples.python.argv)
        for python in Self.pythons {
            // Run there (the input method runs in the home folder), the code on standard input.
            let process = Process()
            process.executableURL = CommandRunner.resolve("python3", path: python)
            process.arguments = Array(argv.dropFirst())
            process.currentDirectoryURL = folder
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            input.fileHandleForWriting.write(Data("import helper; helper.VALUE + 1".utf8))
            try input.fileHandleForWriting.close()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            // Its own module is the standard one; the code still imports from the folder, as with `python3 -c`.
            #expect(process.terminationStatus == 0 && text == "43\n", "the python3 in \(python): \(text)")
        }
    }
}

private extension Result where Failure == Error {
    var runError: CommandRunner.RunError? {
        if case let .failure(error) = self { return error as? CommandRunner.RunError }
        return nil
    }
}
