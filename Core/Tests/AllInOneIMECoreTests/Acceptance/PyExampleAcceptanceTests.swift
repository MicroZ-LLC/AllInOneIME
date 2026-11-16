import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Acceptance tests for "`@py` leaves the built-ins" (0.7.5, the owner's decision of 2026-11-14), written from the spec
// only, independently of the implementation's own tests. `@py` is no longer built in: it is one of Settings' "Start from
// an Example" commands (`CommandExamples.python`), a `run` command of the user's own once added, working as the built-in
// did. Each test names the spec's point it checks:
//
//   N1  The built-ins are the spec's list, without `py`; the default catalog has no `py`.
//   N2  The name is free: a custom `py` has no problem, and isn't renamed at launch (`freeBuiltinNames`).
//   N3  Not added, `@py …` is an unknown name, as `@zzqx …` is: Esc leaves it as typed, ⏎ does what it does for that;
//       inside another command's text it stays text.
//   N4  The example's values: a run command named `py`, `python3 -X utf8 -c <one line>`, the code on standard input,
//       typed as Latin letters, 10 s, blue with the run glyph, its summary in the interface language.
//   N5  Added, "@py 23*17" ⏎ runs it with the engine in ASCII, in an app with no AI too (no refusal).
//   N6  "@" opens no command list in the text of a command that runs code (`runsCode`), and nothing in it runs first.
//   N7  Pasted, `@py` in another command's text stays text (the code-left notice); typed, it runs inside it.
//   N8  Inside another command's text a failure reads "@py：" and the message in the interface language.
//   N9  Without `python3` it isn't offered.
//   N10 With a real python3, the example works REPL style (skipped when there is none).
//   N11 In Settings, a custom `py` isn't marked "Same name as a built-in command".
//
// The commands are looked up by name: `Command.py` and `InlineCode.python` are gone after the change.

@Suite(.serialized)
struct PyExampleAcceptanceTests {
    /// The built-ins after the change, in order (§2).
    static let builtins = ["improve", "translate", "question", "agent", "open", "reply", "note", "reminder", "js", "tasks",
                           "settings", "imessage", "reportissue", "stats"]
    /// A name nothing has: what an unknown command does.
    static let unknown = "zzqx"
    static let refusal = "AI is off in this app"

    /// A run command of the user's own that may run inside a text (`@stock AAPL`).
    static let stock = CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"])
    /// Another run command of the user's own, its text on standard input.
    static let lint = CustomCommand(name: "lint", type: .run, argv: ["lint"], stdin: "{input}")

    /// The catalog with the example added (and `more` of the user's own after it).
    static func catalog(_ more: [CustomCommand] = []) -> [Command] { Command.catalog([CommandExamples.python] + more) }

    /// `name`'s command in `commands`.
    static func named(_ name: String, in commands: [Command]) throws -> Command {
        try #require(commands.first { $0.name == name }, "no @\(name) in \(commands.map(\.name))")
    }

    /// `@py` in `commands`: the example, a command of the user's own (no built-in hides it).
    static func example(in commands: [Command]) throws -> Command {
        let py = try named("py", in: commands)
        #expect(py.custom == CommandExamples.python && py.kind == .run, "@py isn't the user's own: \(py)")
        return py
    }

    // MARK: Helpers: a field

    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let pasteKey = KeyEvent(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: .command)

    /// A text field as the controller sets it up: `commands` offered, ⏎ runs, English typed (Chinese with `english`
    /// false); with `aiOff`, an app with no AI (no AI row in the one @ list, AI commands refused).
    func field(commands: [Command], english: Bool = true, aiOff: Bool = false) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.commands = commands
        c.inputLanguages = [.chinese, .english]
        c.setInputMode(english ? .english : .chinese)
        c.aiAllowed = { !aiOff }
        c.aiRefusal = { aiOff ? Self.refusal : nil }
        return (c, engine)
    }

    func key(_ ch: Character) -> KeyEvent { ch == "@" ? at : ch == " " ? spaceKey : k(String(ch)) }

    func type(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(key(ch)) }
    }

    /// Types `text` and presses ⏎: the effects of the ⏎.
    func run(_ text: String, _ c: Composer) -> [Composer.Effect] {
        type(text, c)
        return c.handleKeyDown(enterKey).effects
    }

    /// ⌘V, then the clipboard's `text` arrives.
    func paste(_ text: String, into c: Composer) {
        let asked = c.handleKeyDown(pasteKey)
        guard case let .readClipboard(id)? = asked.effects.last else {
            Issue.record("⌘V didn't ask for the clipboard: \(asked)")
            return
        }
        _ = c.pasted(.text(text), id: id)
    }

    /// Text put into the field (an empty commit is nothing inserted).
    func inserted(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { effect in
            switch effect {
            case let .commit(s), let .typeOut(s): return s.isEmpty ? Optional<String>.none : s
            case let .replaceSelection(s, _): return s
            default: return Optional<String>.none
            }
        }
    }

    func notices(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case let .notice(s) = $0 { return s } else { return nil } }
    }

    /// Whether `effects` start anything: a model request, a command, a program, a Terminal window, a plan.
    func startsAnything(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { effect in
            switch effect {
            case .startConversion, .startCommand, .startPlan, .startRun, .startScript, .startBackgroundScript, .runInTerminal,
                 .startBackgroundAgent, .launchInTerminal:
                return true
            default:
                return false
            }
        }
    }

    /// Types `text` into a field and presses `finish`, as the app sees it: what ends up in the field (text committed, and
    /// keys the composer passes on to the app, then the draft left), every effect, and that last key's own response.
    func typeIntoField(_ text: String, _ c: Composer, then finish: KeyEvent)
        -> (field: String, effects: [Composer.Effect], last: Composer.Response) {
        var field = "", effects: [Composer.Effect] = []
        for ch in text {
            let response = c.handleKeyDown(key(ch))
            effects += response.effects
            field += inserted(response.effects).joined()
            if !response.handled { field.append(ch) }
        }
        let last = c.handleKeyDown(finish)
        effects += last.effects
        field += inserted(last.effects).joined()
        return (field + c.draft, effects, last)
    }

    /// `text` with the command name `name` written as a placeholder where it is a word of its own (not inside "copy").
    func placeholder(_ text: String, _ name: String) -> String {
        text.replacingOccurrences(of: "(?<![A-Za-z])" + name + "(?![A-Za-z])", with: "NAME", options: .regularExpression)
    }

    /// What typing `@<name><rest>` and `finish` does in a fresh field with `commands`, the name as a placeholder.
    func behaviour(_ name: String, _ rest: String, commands: [Command], then finish: KeyEvent)
        -> (field: String, effects: [String], handled: Bool, draft: String, phase: String, panel: Bool) {
        let (c, _) = field(commands: commands)
        let typed = typeIntoField("@" + name + rest, c, then: finish)
        return (placeholder(typed.field, name), typed.last.effects.map { placeholder(String(describing: $0), name) },
                typed.last.handled, placeholder(c.draft, name), placeholder("\(c.phase)", name), c.wantsPanel)
    }

    // MARK: N1. Not built in

    @Test func n1_theBuiltInsAreTheSpecsListWithoutPy() {
        #expect(Command.builtins.map(\.name) == Self.builtins, "\(Command.builtins.map(\.name))")
        #expect(!Command.catalog([]).contains { $0.name == "py" }, "\(Command.catalog([]).map(\.name))")
        #expect(!Command.off.contains { $0.name == "py" })
        // Not found by name either.
        #expect(Command.parse("@py 2**100", in: Command.catalog([])) == nil)
        #expect(Command.palette("py", in: Command.catalog([]), usage: CommandUsage(), limit: 100).allSatisfy { $0.name != "py" })
    }

    // MARK: N2. The name is free

    @Test func n2_aCommandOfTheUsersOwnMayBeNamedPy() throws {
        let own = CustomCommand(name: "py", type: .run, argv: ["python3"])
        #expect(own.isValid)
        #expect(own.problem(among: []) == nil, "\(String(describing: own.problem(among: [])))")
        // At launch it keeps its name: no built-in has it any more.
        var config = Config.default
        config.customCommands = [own]
        let renamed = config.freeBuiltinNames(taken: [])
        #expect(renamed.isEmpty, "\(renamed)")
        #expect(config.customCommands.map(\.name) == ["py"])
        // And it is offered under it, as the user's own.
        let py = try Self.named("py", in: Command.catalog([own]))
        #expect(py.custom == own && py.kind == .run)
        // The example too.
        #expect(CommandExamples.python.problem(among: []) == nil)
        _ = try Self.example(in: Self.catalog())
        // An earlier `mypy` (renamed by 0.7.4 and before) stays as it is, next to a new `py`.
        var both = Config.default
        both.customCommands = [CustomCommand(name: "mypy", type: .run, argv: ["python3"]), CommandExamples.python]
        #expect(both.freeBuiltinNames(taken: []).isEmpty)
        #expect(both.customCommands.map(\.name) == ["mypy", "py"])
    }

    // MARK: N3. Not added: an unknown name

    @Test func n3_typedWithoutTheExampleItIsLikeAnUnknownName() {
        let commands = Command.catalog([])
        // Esc: nothing starts, the text stays as typed.
        let (c, _) = field(commands: commands)
        let left = typeIntoField("@py 2**100", c, then: escKey)
        #expect(!startsAnything(left.effects), "\(left.effects)")
        #expect(left.field == "@py 2**100", "\(left.field.debugDescription)")
        // ⏎ and Esc do what they do after a name no command has (one @: ⏎ the list's first row for the text).
        for finish in [enterKey, escKey] {
            let seen = behaviour("py", " 2**100", commands: commands, then: finish)
            let control = behaviour(Self.unknown, " 2**100", commands: commands, then: finish)
            #expect(seen.effects == control.effects, "\(seen.effects) vs \(control.effects)")
            #expect(seen.field == control.field && seen.handled == control.handled, "\(seen.field) vs \(control.field)")
            #expect(seen.draft == control.draft && seen.phase == control.phase && seen.panel == control.panel,
                    "\(seen.draft) \(seen.phase) vs \(control.draft) \(control.phase)")
        }
    }

    @Test func n3_insideAnotherCommandsTextItStaysText() throws {
        #expect(CommandPlan.make("x @py 1", commands: Command.catalog([])).inner.isEmpty)
        // As `@zzqx` is.
        let plan = CommandPlan.make("总结一下 @py 1+1", commands: Command.catalog([]))
        let control = CommandPlan.make("总结一下 @\(Self.unknown) 1+1", commands: Command.catalog([]))
        #expect(plan.inner.isEmpty && plan.inner == control.inner)
        #expect(plan.input(outputs: []) == "总结一下 @py 1+1")
        // Typed after a command, it is text too: "@improve x @py 1" improves the text as typed.
        let (c, _) = field(commands: Command.catalog([]))
        let effects = run("@improve x @py 1", c)
        #expect(effects.first == .startConversion(input: "x @py 1", id: 1), "\(effects)")
    }

    // MARK: N4. The example

    @Test func n4_theExamplesValues() async throws {
        let py = CommandExamples.python
        #expect(py.name == "py" && py.type == .run)
        #expect(py.argv == ["python3", "-X", "utf8", "-c", CommandExamples.pythonREPL], "\(String(describing: py.argv))")
        #expect(py.stdin == CustomCommand.placeholder)
        #expect(py.ascii == true && py.typesLatin)
        #expect(py.timeout == 10 && py.timeout == CustomCommand.defaultTimeout)
        #expect(py.isValid)
        #expect(py.color == "blue")
        // No icon of its own: the run commands' glyph (`</>`), in blue.
        #expect(py.icon == nil)
        #expect(IconToken.custom(py) == IconToken(.run, color: .blue))
        // One line: the editor's Command field is one line.
        #expect(!CommandExamples.pythonREPL.contains("\n") && !CommandExamples.pythonREPL.contains("\r"))
        #expect(!CommandExamples.pythonREPL.isEmpty)
        // Written in that field and read back, it is the same program.
        let argv = try #require(py.argv)
        let line = CustomCommand.commandLine(argv)
        #expect(CustomCommand.arguments(fromCommandLine: line) == argv, "\(line)")
        // Its summary, in the interface language.
        let english = await withInterfaceLanguage("en") { CommandExamples.python.summary }
        #expect(english == "Run Python; insert the result", "\(english ?? "none")")
        let chinese = await withInterfaceLanguage("zh-Hans") { CommandExamples.python.summary }
        #expect(chinese == "运行 Python，结果可以直接上屏", "\(chinese ?? "none")")
        // What it needs on the Mac: python3.
        #expect(try Self.example(in: Self.catalog()).program == "python3")
    }

    // MARK: N5. Added, it runs

    @Test func n5_addedItRunsWithTheEngineInASCII() throws {
        let catalog = Self.catalog()
        let py = try Self.example(in: catalog)
        for aiOff in [false, true] {
            // Typed in Chinese: picking it switches the engine to Latin letters.
            let (c, engine) = field(commands: catalog, english: false, aiOff: aiOff)
            type("@py 23*17", c)
            #expect(c.draft == "@py 23*17", "no AI \(aiOff): \(c.draft.debugDescription)")
            #expect(engine.ascii && c.engineState.isAsciiMode, "no AI \(aiOff)")
            let effects = c.handleKeyDown(enterKey).effects
            #expect(effects.first == .startRun(py, input: "23*17", id: 1), "no AI \(aiOff): \(effects)")
            #expect(!notices(effects).contains(Self.refusal), "no AI \(aiOff): \(effects)")
        }
    }

    // MARK: N6. No command list in code

    @Test(arguments: ["py", "lint"])
    func n6_noCommandListInsideTheTextOfACommandThatRunsCode(_ name: String) throws {
        let catalog = Self.catalog([Self.stock, Self.lint])
        let command = try name == "py" ? Self.example(in: catalog) : Self.named(name, in: catalog)
        #expect(command.runsCode)
        let (c, _) = field(commands: catalog)
        type("@\(name) x = \"@", c)
        #expect(c.draft == "@\(name) x = \"@", "\(c.draft.debugDescription)")
        #expect(c.paletteQuery == nil, "@\(name): the list opened (\(c.paletteMatches.map(\.name)))")
        type("st", c)
        #expect(c.paletteQuery == nil, "@\(name): the list opened (\(c.paletteMatches.map(\.name)))")
        // ⏎ runs it on the text exactly as typed: `@stock` inside it doesn't run first.
        type("ock AAPL\"; x", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.first == .startRun(command, input: "x = \"@stock AAPL\"; x", id: 1), "@\(name): \(effects)")
        #expect(!effects.contains { if case .startPlan = $0 { return true } else { return false } }, "@\(name): \(effects)")
    }

    /// The control: in a text that isn't code, "@" still opens the list, with the commands that run inside a text.
    @Test func n6_theListStillOpensInATextThatIsntCode() throws {
        let catalog = Self.catalog([Self.stock])
        let (c, _) = field(commands: catalog)
        type("@question x \"@", c)
        #expect(c.paletteQuery == "", "\(c.draft.debugDescription)")
        #expect(c.paletteMatches.contains { $0.name == "stock" } && c.paletteMatches.contains { $0.name == "py" },
                "\(c.paletteMatches.map(\.name))")
    }

    // MARK: N7. Inside other commands' text

    @Test func n7_pastedItStaysTextAndTheUserIsTold() {
        let (c, _) = field(commands: Self.catalog([Self.stock]))
        type("@improve ", c)
        #expect(c.draft == "@improve ", "\(c.draft.debugDescription)")
        paste("Bonjour @py「print(1)」 merci", into: c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.first == .startConversion(input: "Bonjour @py「print(1)」 merci", id: 1), "\(effects)")
        #expect(effects.contains(.notice(c.messages.codeNotRun)), "\(effects)")
    }

    @Test func n7_typedItRunsInsideAnotherCommandsText() throws {
        let catalog = Self.catalog()
        let py = try Self.example(in: catalog)
        #expect(CommandPlan.canBeInner(py))
        // Through the plan…
        let plan = CommandPlan.make("x @py 1", commands: catalog)
        #expect(plan.inner.map(\.command) == [py] && plan.inner.map(\.argument) == ["1"], "\(plan.inner)")
        // …and typed into a field.
        let (c, _) = field(commands: catalog)
        let effects = run("@question x @py 1", c)
        guard case let .startPlan(outer, typed, _)? = effects.first else {
            Issue.record("expected a plan: \(effects)")
            return
        }
        #expect(outer == .question)
        #expect(typed.inner.map(\.command) == [py] && typed.inner.map(\.argument) == ["1"], "\(typed.inner)")
        #expect(!effects.contains(.notice(c.messages.codeNotRun)), "\(effects)")
    }

    // MARK: N8. Failures inside a text, in the interface language

    final class Settings: @unchecked Sendable {
        var config: Config
        init(_ language: String) {
            config = .default
            config.uiLanguage = language
            config.setOrder([Language.chinese, .english])
            config.customCommands = [CommandExamples.python]
        }
    }

    /// A session in an editor that has the focus, with `settings`, python3 installed, `runProgram` as given.
    func host(_ settings: Settings,
              runProgram: @escaping @Sendable (CustomCommand, String) -> AsyncThrowingStream<ConversionUpdate, Error>,
              installed: @escaping @Sendable (String) -> Bool = { _ in true }) -> FakeHost {
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = installed
        services.runProgram = runProgram
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    /// Picks `letters`' command from the list ("@", its letters, Tab), types `input` in English and runs it (⏎): what
    /// the panel says once it failed, nil if it didn't.
    func failed(_ letters: String, _ input: String, in host: FakeHost) -> String? {
        host.composer.setInputMode(.english)
        host.press(FakeHost.at)
        host.type(letters)
        host.press(FakeHost.tab)
        host.type(input)
        host.press(FakeHost.enter)
        _ = host.settle { if case .failed = host.composer.phase { true } else { false } }
        guard case let .failed(message) = host.composer.phase else { return nil }
        return message
    }

    @Test(arguments: Issue67Tests.Failure.allCases)
    func n8_aFailureInsideATextIsInTheInterfaceLanguage(_ failure: Issue67Tests.Failure) async {
        await withInterfaceLanguage("zh-Hans") {
            let ran = Locked<[String]>(initialState: [])
            let alone = failed("py", "1", in: host(Settings("zh"), runProgram: Issue67Tests.failing(failure, ran: ran)))
            #expect(alone == failure.chinese, "on its own: \(alone ?? "no failure")")
            let inside = failed("question", "x @py 1",
                                in: host(Settings("zh"), runProgram: Issue67Tests.failing(failure, ran: ran)))
            #expect(ran.withLock { $0 } == ["py", "py"], "the code ran both times (\(ran.withLock { $0 }))")
            #expect(inside == "@py：" + failure.chinese, "inside @question's text: \(inside ?? "no failure")")
            #expect(inside?.contains(failure.english) != true, "not in English: \(inside ?? "no failure")")
        }
    }

    /// The request's stream for `@question x @py 1` whose code runs too long: in English "@py: Stopped after 10 seconds",
    /// in Simplified Chinese "@py：运行超过 10 秒，已停止".
    @Test func n8_theRequestsStreamSaysItInTheTasksLanguage() async {
        let ran = Locked<[String]>(initialState: [])
        var services = SessionServices()
        services.runProgram = Issue67Tests.failing(.timedOut, ran: ran)
        let place = SessionTasks.Place(app: nil, terminal: false, pastesInTerminal: false, improveTranslates: false,
                                       pluginLanguage: .chinese)
        let plan = CommandPlan.make("x @py 1", commands: Self.catalog())
        let request = SessionTasks.Request(input: "", command: .question, plan: plan)
        func shown(in language: String) async -> String? {
            await UIText.$scopedLanguage.withValue(language) {
                do {
                    for try await _ in SessionTasks.stream(for: request, in: place, services: services) {}
                    return nil
                } catch {
                    return (error as? DescribedError)?.message ?? UIText.describe(error)
                }
            }
        }
        let english = await shown(in: "en")
        #expect(english == "@py: Stopped after 10 seconds", "\(english ?? "no failure")")
        let chinese = await shown(in: "zh-Hans")
        #expect(chinese == "@py：运行超过 10 秒，已停止", "\(chinese ?? "no failure")")
        #expect(ran.withLock { $0 } == ["py", "py"])
    }

    // MARK: N9. Not offered without python3

    @Test func n9_withoutPython3ItIsntOffered() async {
        await withInterfaceLanguage("en") {
            let nothing: @Sendable (CustomCommand, String) -> AsyncThrowingStream<ConversionUpdate, Error> = { _, _ in
                AsyncThrowingStream { $0.finish() }
            }
            // With python3: offered, as the user's own.
            let present = host(Settings("en"), runProgram: nothing)
            let offered = { present.composer.commands.contains { $0.name == "py" && $0.custom == CommandExamples.python } }
            #expect(present.settle(until: offered), "\(present.composer.commands.map(\.name))")
            // Without: not offered, and @js (which needs no program) still is.
            let absent = host(Settings("en"), runProgram: nothing, installed: { $0 != "python3" })
            #expect(absent.settle { !absent.composer.commands.contains { $0.name == "py" } },
                    "\(absent.composer.commands.map(\.name))")
            #expect(absent.composer.commands.contains(.js))
        }
    }

    // MARK: N10. With a real python3

    /// A folder with a python3 that would run (nil: these tests are skipped).
    static let pythonFolder: String? = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return path.split(separator: ":").map(String.init).first { CommandRunner.isInstalled("python3", path: $0) }
    }()

    /// `code` through the example, as the input method runs it (`CommandRunner.run`), with the python3 in `folder`:
    /// within `timeout` seconds, by default a limit no busy test run reaches (`Timing`; a Python started for the first
    /// time on a runner takes seconds). Its result's text (the "all of it" candidate), or how it failed.
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

    /// How `result` failed, as the runner says it.
    func runError(_ result: Result<String, Error>) -> CommandRunner.RunError? {
        guard case let .failure(error) = result else { return nil }
        return error as? CommandRunner.RunError
    }

    @Test(.enabled(if: PyExampleAcceptanceTests.pythonFolder != nil)) func n10_itIsREPLStyle() async throws {
        let folder = try #require(Self.pythonFolder)
        let cases: [(code: String, result: String)] = [
            ("2**100", "1267650600228229401496703205376"),  // the value of the last expression, all of it
            ("'abc'.upper()", "ABC"),  // a str as it is
            ("print('a'); 1 + 1", "a\n2"),  // what it printed, then the value
            ("x = 5", ""),  // nothing: "No result", not a hint about code
            (#"print("  x\n  y")"#, "  x\n  y"),  // the first line's indentation stays
            ("print（“牛逼”）", "牛逼"),  // full-width punctuation from Chinese typing
        ]
        for (code, result) in cases {
            let got = await python(code, in: folder)
            #expect((try? got.get()) == result, "\(code): \(got)")
        }
    }

    @Test(.enabled(if: PyExampleAcceptanceTests.pythonFolder != nil)) func n10_anErrorIsItsLastLine() async throws {
        let folder = try #require(Self.pythonFolder)
        let cases: [(code: String, error: CommandRunner.RunError)] = [
            ("1/0", .failed(status: 1, message: "ZeroDivisionError: division by zero")),
            ("import sys; sys.exit('bad input')", .failed(status: 1, message: "bad input")),
        ]
        for (code, error) in cases {
            let got = await python(code, in: folder)
            #expect(runError(got) == error, "\(code): \(got)")
        }
        // The wording of syntax errors changes between Python versions.
        guard case let .failed(status, message)? = runError(await python("print(", in: folder)) else {
            Issue.record("print( didn't fail")
            return
        }
        #expect(status == 1 && message.hasPrefix("SyntaxError: ") && !message.contains("\n"), "\(message)")
    }

    @Test(.enabled(if: PyExampleAcceptanceTests.pythonFolder != nil)) func n10_theRunnersLimitsHold() async throws {
        let folder = try #require(Self.pythonFolder)
        let loop = await python("while True: pass", in: folder, timeout: 0.5)
        #expect(runError(loop) == .timedOut(0.5), "\(loop)")
        let much = await python("print('x'*70000)", in: folder)
        #expect(runError(much) == .tooMuchOutput, "\(much)")
    }

    /// In a working directory with an `ast.py` that raises (and a `traceback.py`), the example's own imports are the
    /// standard modules; the code still imports from the folder (`helper.py`), as with `python3 -c`.
    @Test(.enabled(if: PyExampleAcceptanceTests.pythonFolder != nil)) func n10_lookalikeModulesInTheWorkingDirectory() throws {
        let python = try #require(CommandRunner.resolve("python3", path: try #require(Self.pythonFolder)))
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("py-example-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        for name in ["ast", "traceback"] {
            try Data("raise ImportError('not the standard \(name)')\n".utf8)
                .write(to: folder.appendingPathComponent("\(name).py"))
        }
        try Data("VALUE = 42\n".utf8).write(to: folder.appendingPathComponent("helper.py"))
        let example = CommandExamples.python
        let argv = try #require(example.argv)
        // The example's program, run there (the input method runs it in the home folder), its standard input as it gives it.
        let process = Process()
        process.executableURL = python
        process.arguments = Array(argv.dropFirst())
        process.currentDirectoryURL = folder
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data((example.standardInput(for: "import helper; helper.VALUE + 1") ?? "").utf8))
        try input.fileHandleForWriting.close()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0 && text.trimmingCharacters(in: .newlines) == "43", "\(text) \(error)")
    }
}

// MARK: - N11. In Settings

/// The Mac's settings document, on a config file of its own; keys in memory (`MemorySecrets`).
@Suite(.serialized, MemorySecrets())
struct PyExampleSettingsAcceptanceTests {
    @Test(arguments: ["en", "zh-Hans"])
    func n11_aCustomPyIsntMarkedAsABuiltInsName(_ language: String) async throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("py-example-settings-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        var config = Config.default
        config.uiLanguage = language
        config.customCommands = [CommandExamples.python, CustomCommand(name: "js", type: .run, argv: ["node", "-p", "{input}"])]
        try config.write(to: url)
        let plugins = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: plugins)
        let document = await withInterfaceLanguage(language) { service.document() }
        let items = try #require(document.field("commands.custom")?.items)
        let py = try #require(items.first { $0.id == "py" }, "\(items.map(\.id))")
        #expect(py.title == "@py")
        for mark in ["Same name as a built-in command", "和内置命令重名"] {
            #expect(py.detail?.contains(mark) != true, "\(py.detail ?? "")")
        }
        // The control: a custom `js` still is (a built-in has that name).
        let js = try #require(items.first { $0.id == "js" }, "\(items.map(\.id))")
        let mark = language == "en" ? "Same name as a built-in command" : "和内置命令重名"
        #expect(js.detail?.contains(mark) == true, "\(js.detail ?? "")")
    }
}
