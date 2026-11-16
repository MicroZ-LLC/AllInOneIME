import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMEQuickJS

/// `@js` (`InlineCode`): a line of code run in a child process, REPL style. Python, `@py`, is Settings' example run
/// command (`CommandExamplesTests`); in the composer it works the same way.
struct InlineCodeTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    /// Types `text` key by key ("@" with Shift, spaces as the space bar).
    func typeKeys(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    // MARK: - The programs

    @Test func definitions() throws {
        // This app's own executable as the child process; the code on standard input with full-width punctuation as ASCII.
        let js = try #require(InlineCode.definition(for: .js, executable: "/Apps/AllInOneIME.app/Contents/MacOS/AllInOneIME"))
        #expect(js.argv == ["/Apps/AllInOneIME.app/Contents/MacOS/AllInOneIME", "--run-js"])
        #expect(js.arguments(for: "{input}") == js.argv && js.standardInput(for: "[1，2].map(x => x * 2)") == "[1,2].map(x => x * 2)")
        #expect(js.timeout == CustomCommand.defaultTimeout && js.typesLatin)
        // Nothing else is code: not the other built-in commands, not a custom one running python3 (Settings' @py).
        for command in Command.builtins where !command.isCode { #expect(InlineCode.definition(for: command) == nil) }
        let custom = Command.catalog([CustomCommand(name: "python", type: .run, argv: ["python3", "-c", "{input}"])])
        #expect(InlineCode.definition(for: try #require(custom.last)) == nil)
        #expect(InlineCode.definition(for: try #require(Command.catalog([CommandExamples.python]).last)) == nil)
    }

    @Test func builtInCommands() {
        #expect(Command.builtins.contains(.js) && Command.js.kind == .run && !Command.builtins.contains { $0.name == "py" })
        #expect(Command.js.isCode && !Command.open.isCode && !Command.question.isCode)
        #expect(Command.js.typesLatin && Command.js.runsCode)
        // @js needs nothing but this app.
        #expect(Command.js.program == nil)
        // A built-in name: the editor refuses it, and a custom command of that name gives way.
        let node = CustomCommand(name: "js", type: .run, argv: ["node", "-p", "{input}"])
        #expect(node.problem(among: []) == .nameTaken)
        #expect(Command.catalog([node]).filter { $0.name == "js" } == [.js])
        #expect(CommandPlan.canBeInner(.js))
    }

    // MARK: - In the composer

    @Test func pickedFromTheListAndRun() throws {
        let c = Composer(engine: FakeEngine())  // ⏎ is the action key
        c.commands = Command.catalog([CommandExamples.python])  // @py: Settings' example, added
        let py = try #require(c.commands.first { $0.name == "py" })
        _ = c.handleKeyDown(at)
        typeKeys("p", c)
        #expect(c.paletteMatches.first == py)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@py " && c.engineState.isAsciiMode)  // code is typed as letters
        typeKeys("2**100", c)
        #expect(c.markedText == "py › 2**100")
        let effects = c.handleKeyDown(enterKey).effects
        // A run like a custom program's (the controller refuses `.startRun` during secure input).
        #expect(effects.first == .startRun(py, input: "2**100", id: 1))
        #expect(effects.contains(.commandUsed("py")) && c.activeCommand == py && c.phase == .translating(id: 1))
        _ = c.receive(ConversionResult(versions: [CandidateLine("1267650600228229401496703205376")]), isFinal: true, id: 1)
        #expect(c.choices.map(\.kind) == [.original, .answer] && c.highlighted == 1)
        #expect(c.choices.first?.text == "2**100")  // 0: the code as typed
        #expect(commits(c.handleKeyDown(enterKey)) == ["1267650600228229401496703205376"])
        #expect(!c.engineState.isAsciiMode)  // Chinese is back

        let j = Composer(engine: FakeEngine())
        _ = j.handleKeyDown(at)
        typeKeys("j", j)
        #expect(j.paletteMatches == [.js])
        _ = j.handleKeyDown(tab)
        typeKeys("[1,2].map(x => x * 2)", j)
        #expect(j.handleKeyDown(enterKey).effects.first == .startRun(.js, input: "[1,2].map(x => x * 2)", id: 1))
        // Esc while it runs stops it and goes back to the code.
        #expect(j.handleKeyDown(escKey).effects.first == .cancelConversion && j.draft == "@js [1,2].map(x => x * 2)")
    }

    @Test func insideAnotherCommandsText() throws {
        let catalog = Command.catalog([CustomCommand(name: "respond", type: .prompt, prompt: "Reply."), CommandExamples.python])
        let py = try #require(catalog.first { $0.name == "py" })
        let engine = FakeEngine()
        let c = Composer(engine: engine)
        c.commands = catalog
        _ = c.handleKeyDown(at)
        typeKeys("resp", c)
        _ = c.handleKeyDown(tab)
        typeKeys("nihao", c)
        _ = c.handleKeyDown(spaceKey)
        _ = c.handleKeyDown(at)
        #expect(c.paletteMatches.map(\.name) == ["js", "py"])  // the commands that run inside a text
        typeKeys("p", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@respond 你好@py " && engine.ascii)
        typeKeys("2**100", c)
        let effects = c.handleKeyDown(enterKey).effects
        guard case let .startPlan(outer, plan, _)? = effects.first else {
            Issue.record("expected a plan, got \(effects)")
            return
        }
        #expect(outer?.name == "respond" && plan.inner.map(\.command) == [py] && plan.inner.map(\.argument) == ["2**100"])
        #expect(plan.input(outputs: ["1267650600228229401496703205376"]) == "你好1267650600228229401496703205376")
        #expect(effects.contains(.commandUsed("respond")) && effects.contains(.commandUsed("py")))
        // Code with spaces in it is quoted.
        let quoted = CommandPlan.make("答案是 @py「sum(x * x for x in range(4))」吧，还有 @js \"[1, 2].map(x => x * 2)\"", commands: catalog)
        #expect(quoted.inner.map(\.argument) == ["sum(x * x for x in range(4))", "[1, 2].map(x => x * 2)"])
    }

    @Test func codeRunsExactlyAsTyped() throws {
        let catalog = Command.catalog([CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"]), CommandExamples.python])
        let py = try #require(catalog.first { $0.name == "py" })
        let c = Composer(engine: FakeEngine())
        c.commands = catalog
        c.setInputMode(.english)
        typeKeys("@py x = \"@", c)
        #expect(c.draft == "@py x = \"@" && c.paletteQuery == nil)  // no command list inside code
        typeKeys("stock AAPL\"; x", c)
        #expect(c.markedText == "py › x = \"＠stock AAPL\"; x")  // not shown as a command either
        // No other command runs first: nothing they return (a web page, a program's output) is executed.
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.first == .startRun(py, input: "x = \"@stock AAPL\"; x", id: 1))
        #expect(!effects.contains(.commandUsed("stock")))
        let inner = Composer(engine: FakeEngine())
        inner.commands = catalog
        inner.setInputMode(.english)
        typeKeys("@js \"@py 1\"", inner)
        #expect(inner.handleKeyDown(enterKey).effects.first == .startRun(.js, input: "\"@py 1\"", id: 1))
    }

    @Test func codeThatPrintsNothing() {
        func ran(_ code: String, messages: Composer.Messages = .chinese, commands: [Command] = Command.builtins) -> Composer {
            let c = Composer(engine: FakeEngine())
            c.commands = commands
            c.messages = messages
            c.setInputMode(.english)
            typeKeys(code, c)
            _ = c.handleKeyDown(enterKey)
            _ = c.receive(.empty, isFinal: true, id: 1)
            return c
        }
        #expect(ran("@js let y = 1").phase == .failed("代码没有输出：最后写一个表达式，或者把结果打印出来"))
        #expect(ran("@js let y = 1", messages: .english).phase
            == .failed("The code printed nothing: end it with an expression, or print the result"))
        // Other commands as before: the user's own run commands, Settings' example @py among them.
        let custom = Command.catalog([CustomCommand(name: "upper", type: .run, argv: ["tr", "a-z", "A-Z"]), CommandExamples.python])
        #expect(ran("@upper example", commands: custom).phase == .failed("没有得到结果"))
        #expect(ran("@py x = 5", commands: custom).phase == .failed("没有得到结果"))
    }

    /// (@imessage's program is Messages.app, which only a Mac has.)
    @Test(.enabled(if: Available.messagesApp)) func hiddenWithoutTheirProgram() {
        // The controller leaves out the commands whose program isn't installed (`setCommands`)…
        let catalog = Command.catalog([CommandExamples.python])  // @py: Settings' example, added
        let missing = Set(catalog.compactMap { command in
            command.program.flatMap { CommandRunner.isInstalled($0, path: "/nowhere") ? nil : command.name }
        })
        #expect(missing == ["agent", "py"])  // @js needs no program
        let c = Composer(engine: FakeEngine())
        c.commands = catalog.filter { !missing.contains($0.name) }
        // …so the list doesn't offer @py, and "@py …" is plain text.
        _ = c.handleKeyDown(at)
        typeKeys("p", c)
        #expect(!c.paletteMatches.contains { $0.name == "py" } && !c.paletteMatches.isEmpty)
        #expect(Command.parse("@py 1+1", in: c.commands) == nil && Command.parse("@js 1+1", in: c.commands)?.command == .js)
    }

    // MARK: - JavaScript

    @Test(.enabled(if: Available.javaScript)) func javaScriptIsREPLStyle() throws {
        let cases: [(code: String, result: String)] = [
            ("1 + 1", "2"),  // the value of the last statement
            ("'abc'.toUpperCase()", "ABC"),  // text as it is
            ("[1, 'a', [2, null]]", "[1, \"a\", [2, null]]"),  // anything else as a literal
            ("{a: 1, 'b-c': [true]}", "{a: 1, \"b-c\": [true]}"),  // braces: an object when they can be one…
            ("{ let x = 2; x * 3 }", "6"),  // …a block otherwise
            ("var x = 6; x * 7", "42"),
            ("let y = 1", ""),  // no value
            ("for (let i = 0; i < 3; i++) console.log(i)", "0\n1\n2"),
            ("console.log('hi', [1], {b: 2}); 42", "hi [1] {b: 2}\n42"),  // what it logged, then the value
            ("console.warn('w'); console.error('e'); 'ok'", "ok"),  // warnings aren't the result
            ("2n ** 100n", "1267650600228229401496703205376"),
            ("[1n, -0, NaN, undefined]", "[1n, -0, NaN, undefined]"),
            ("new Map([['k', 1]])", "Map {\"k\" => 1}"),
            ("new Set([1, 'a'])", "Set {1, \"a\"}"),
            ("new Date(0)", "1970-01-01T00:00:00.000Z"),
            ("var o = {}; o.self = o; o", "{self: [Circular]}"),
            ("class Point { constructor() { this.x = 1 } }; new Point()", "Point {x: 1}"),
            ("function f() {}; f", "[Function: f]"),
            ("'你好'.repeat(2)", "你好你好"),
        ]
        for (code, result) in cases {
            #expect(try InlineCode.evaluateJavaScript(code) == result, "\(code)")
        }
    }

    @Test(.enabled(if: Available.javaScript)) func javaScriptHasNothingButTheLanguage() throws {
        let globals = "[typeof require, typeof process, typeof fetch, typeof XMLHttpRequest, typeof setTimeout, typeof importScripts].join()"
        #expect(try InlineCode.evaluateJavaScript(globals) == Array(repeating: "undefined", count: 6).joined(separator: ","))
        // Warnings go their own way (to standard error in the child process).
        var printed: [String] = [], warned: [String] = []
        try InlineCode.runJavaScript("console.log('a'); console.error('b', 1); 'c'", print: { printed.append($0) }, warn: { warned.append($0) })
        #expect(printed == ["a", "c"] && warned == ["b 1"])
        // Every run starts afresh.
        _ = try InlineCode.evaluateJavaScript("var kept = 1")
        #expect(try InlineCode.evaluateJavaScript("typeof kept") == "undefined")
    }

    @Test(.enabled(if: Available.javaScript)) func javaScriptErrorsAreOneLine() {
        // The engine's own words for its own errors: JavaScriptCore's, or QuickJS-ng's (Windows, Linux, Android, and
        // OnQuickJSTests).
        let quickJS = Platform.current.scripts is QuickJSEngine
        func notFound(_ name: String) -> String { quickJS ? "\(name) is not defined" : "Can't find variable: \(name)" }
        let cases: [(code: String, error: String)] = [
            ("x.y", "ReferenceError: \(notFound("x"))"),
            ("throw new Error('first line\\nsecond line')", "Error: first line"),
            ("throw 'oops'", "oops"),
            ("throw {code: 1}", "{code: 1}"),
            ("1 +", quickJS ? "SyntaxError: unexpected token in expression: ''" : "SyntaxError: Unexpected end of script"),
            ("1\n2\nnope", "ReferenceError: \(notFound("nope")) (line 3)"),
            ("({get a() { throw new RangeError('no') }})", "RangeError: no"),  // showing the value failed
        ]
        for (code, error) in cases {
            #expect(throws: InlineCodeError(error), "\(code)") { try InlineCode.evaluateJavaScript(code) }
        }
    }

    @Test(.enabled(if: Available.javaScript)) func javaScriptErrorLinesAreTheCodes() {
        // The line of the call, not one in what JSON.parse or eval parsed (QuickJS-ng numbers those on their own), with
        // either engine: JavaScriptCore's lines.
        let cases: [(code: String, line: Int)] = [
            ("1\n2\nJSON.parse('[1,\\n2,\\n3,\\nx]')", 3),
            ("1\nJSON.parse('{')", 2),
            ("1\neval('2\\n3\\n4 +')", 2),
        ]
        for (code, line) in cases {
            let error = #expect(throws: InlineCodeError.self, "\(code)") { try InlineCode.evaluateJavaScript(code) }
            #expect(error?.message.hasSuffix(" (line \(line))") == true, "\(code): \(error?.message ?? "")")
        }
    }
}
