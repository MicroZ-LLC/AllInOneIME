import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #44: what a run command or `@py` prints goes in as printed, its first line's indentation too (a table's header over
/// its columns, right-aligned numbers, an indented block); only the blank lines after it are dropped. The first line's
/// leading spaces and tabs were trimmed with them, so the header of a pandas DataFrame no longer sat over its columns.
/// Through `CommandRunner.run`, as the input method runs them (the result, the "all of it" candidate; a script
/// extension's text as it comes), and through a field's session (`FakeHost`): what Return inserts.
@Suite(.serialized)
struct Issue44Tests {
    #if os(Windows)
    // Git for Windows' tools (sh, printf, sleep), where the Mac has them in /usr/bin and /bin.
    let environment = ["PATH": WindowsTestTools.gitTools ?? ""]
    #else
    let environment = ["PATH": "/usr/bin:/bin"]
    #endif

    /// A run command that runs its text as a shell command line.
    let sh = CustomCommand(name: "sh", type: .run, argv: ["sh", "-c", "{input}"])

    /// What `command` gives for `input`, its result's text (the "all of it" candidate) once it exited.
    func run(_ command: CustomCommand, _ input: String, environment: [String: String]? = nil) async -> Result<String, Error> {
        do {
            var text = ""
            for try await update in CommandRunner.run(command, input: input, environment: environment ?? self.environment)
            where update.isFinal {
                text = update.result.versions.first?.text ?? ""
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - A run command

    @Test func aRunCommandKeepsTheFirstLinesIndentation() async throws {
        let cases: [(script: String, result: String)] = [
            ("printf '  a\\n  b\\n\\n'", "  a\n  b"),  // the issue's: the trailing blank line goes, the indentation stays
            ("printf '\\ta\\n\\tb\\n'", "\ta\n\tb"),  // tabs too
            ("printf '%4d\\n' 5 50 500", "   5\n  50\n 500"),  // right-aligned numbers
            ("printf '    let x = 1\\n    print(x)\\n'", "    let x = 1\n    print(x)"),  // an indented code block
            // A DataFrame as pandas prints it: its header over its columns.
            ("printf '   name  age\\n0   ann   31\\n1   bob    4\\n'", "   name  age\n0   ann   31\n1   bob    4"),
            ("printf '  a\\n  b'", "  a\n  b"),  // without a line break at the end
        ]
        for (script, result) in cases {
            let got = await run(sh, script)
            #expect((try? got.get()) == result, "\(script): \(got)")
        }
    }

    /// Blank lines before the first line with something on it may go or stay; that line's indentation stays.
    @Test func blankLinesFirstLeaveTheIndentationOfTheFirstLineWithText() async throws {
        let text = try await run(sh, "printf '\\n\\n  a\\n  b\\n'").get()
        #expect(String(text.drop { $0.isNewline }) == "  a\n  b", "\(text.debugDescription)")
    }

    /// Only the blank lines at the end go: what comes between the lines stays.
    @Test func onlyTheTrailingBlankLinesAreDropped() async throws {
        #expect(try await run(sh, "printf '  a\\n\\n  b\\n\\n\\n'").get() == "  a\n\n  b")
        #expect(try await run(sh, "printf 'a\\n'").get() == "a")
        #expect(try await run(sh, "printf '\\n\\n'").get() == "")
    }

    // MARK: - In a field

    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
        }
    }

    /// A session in an editor (not a terminal) that has the focus, with `settings`, its programs run for real with
    /// `environment` as their own.
    func host(_ settings: Settings, environment: [String: String]) -> FakeHost {
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.runProgram = { command, input in CommandRunner.run(command, input: input, environment: environment) }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    /// Picks `letters`' command from the list ("@", its letters, Tab), types `input` in English and runs it (⏎): whether
    /// its result came (within `timeout` seconds) and is chosen. Its result goes in with the next ⏎.
    func run(_ letters: String, _ input: String, in host: FakeHost, timeout: TimeInterval = 60) -> Bool {
        host.press(FakeHost.at)
        host.type(letters)
        host.press(FakeHost.tab)
        host.composer.setInputMode(.english)
        host.type(input)
        host.press(FakeHost.enter)
        return host.settle(timeout: timeout) { host.composer.phase == .choosing }
    }

    @Test func aRunCommandsOutputGoesInIndented() async throws {
        await withInterfaceLanguage("en") {
            let settings = Settings()
            settings.config.customCommands = [CustomCommand(name: "table", type: .run, argv: ["sh", "-c", "printf '  a\\n  b\\n\\n'"])]
            let host = host(settings, environment: environment)
            #expect(run("table", "x", in: host), "\(host.composer.phase)")
            #expect(host.composer.choices.contains { $0.text == "  a\n  b" }, "\(host.composer.choices.map(\.text))")
            host.press(FakeHost.enter)
            #expect(host.document == "  a\n  b" && host.marked.isEmpty, "\(host.document.debugDescription)")
        }
    }

    // MARK: - @py

    /// A folder with a python3 that would run (nil: the `@py` tests are skipped).
    static let pythonFolder: String? = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return path.split(separator: ":").map(String.init).first { CommandRunner.isInstalled("python3", path: $0) }
    }()

    /// `code` through `@py`'s program, as the input method runs it.
    func python(_ code: String, in folder: String) async -> Result<String, Error> {
        guard var definition = InlineCode.definition(for: .py) else { return .failure(CommandRunner.RunError.notFound("python3")) }
        // A limit no busy test run reaches (`Timing`; a Python started for the first time on a runner takes seconds).
        definition.timeoutSeconds = Double(Timing.longSleep)
        return await run(definition, code, environment: ["PATH": folder, "HOME": NSHomeDirectory()])
    }

    @Test(.enabled(if: Issue44Tests.pythonFolder != nil)) func pythonKeepsTheFirstLinesIndentation() async throws {
        let folder = try #require(Self.pythonFolder)
        let cases: [(code: String, result: String)] = [
            (#"print("  x\n  y")"#, "  x\n  y"),  // the issue's
            (#"print("\tx\n\ty")"#, "\tx\n\ty"),
            (#"for n in (5, 50, 500): print(f"{n:>4}")"#, "   5\n  50\n 500"),  // right-aligned numbers
            (#""   name  age\n0   ann   31""#, "   name  age\n0   ann   31"),  // a last expression's value: a str as it is
            (#"print("  x\n\n")"#, "  x"),  // only the blank lines at the end go
        ]
        for (code, result) in cases {
            let got = await python(code, in: folder)
            #expect((try? got.get()) == result, "\(code): \(got)")
        }
    }

    @Test(.enabled(if: Issue44Tests.pythonFolder != nil)) func pythonsOutputGoesInIndented() async throws {
        let folder = try #require(Self.pythonFolder)
        await withInterfaceLanguage("en") {
            let host = host(Settings(), environment: ["PATH": folder, "HOME": NSHomeDirectory()])
            #expect(run("py", #"print("  x\n  y")"#, in: host), "\(host.composer.phase)")
            #expect(host.composer.choices.contains { $0.text == "  x\n  y" }, "\(host.composer.choices.map(\.text))")
            host.press(FakeHost.enter)
            #expect(host.document == "  x\n  y" && host.marked.isEmpty, "\(host.document.debugDescription)")
        }
    }

    // MARK: - A script extension

    #if !os(Windows)
    /// A script extension's text, as it comes and once it exited, keeps its first line's indentation as well.
    @Test func aScriptExtensionsTextKeepsTheFirstLinesIndentation() async throws {
        let folder = ScriptFolder()
        folder.add("table.sh", script(["output show", "input none"], "printf '  step 1\\n'; sleep 0.5; printf '  step 2\\n\\n'"))
        let command = try #require(folder.load().commands.first)
        var updates: [CommandRunner.ScriptUpdate] = []
        for try await update in CommandRunner.run(command, arguments: [], environment: ["PATH": "/usr/bin:/bin"]) {
            updates.append(update)
        }
        let partial = updates.filter { !$0.isFinal }.map(\.text)
        #expect(partial.first?.hasPrefix("  step 1") == true, "\(partial)")
        #expect(updates.last?.isFinal == true && updates.last?.text == "  step 1\n  step 2", "\(updates.map(\.text))")
    }
    #endif
}
