import Foundation
import Testing
@testable import AllInOneIMECore

struct CommandTests {
    @Test func parse() {
        #expect(Command.parse("@question 量子计算是什么")! == (.question, "量子计算是什么"))
        #expect(Command.parse("@Open calc")! == (.open, "calc"))
        #expect(Command.parse("@agent ")! == (.agent, ""))
        #expect(Command.parse("@question") == nil)  // name not finished
        #expect(Command.parse("@john hi") == nil)  // not a command
        #expect(Command.parse("hi @question x") == nil)
        #expect(Command.parse("") == nil)
    }

    @Test func matching() {
        #expect(Command.matching("") == Command.builtins)
        #expect(Command.matching("Q") == [.question])
        #expect(Command.matching("ag") == [.agent])
        #expect(Command.matching("x").isEmpty)
        #expect(Command.builtins.map(\.kind) == [.convert, .convert, .generate, .terminal, .search, .generate, .run, .note, .reminder, .run, .run, .run,
                                                      .agents, .settings, .message, .report])
    }

    @Test func notesAndRemindersAreBuiltIn() {
        #expect(Command.parse("@note 买牛奶")! == (.note, "买牛奶"))
        #expect(Command.parse("@Reminder 明天下午3点开会")! == (.reminder, "明天下午3点开会"))
        // Typed in Chinese, need no program, and don't run inside another command's text.
        #expect(!Command.note.typesLatin && !Command.reminder.typesLatin)
        #expect(Command.note.program == nil && Command.reminder.program == nil)
        #expect(!CommandPlan.canBeInner(.note) && !CommandPlan.canBeInner(.reminder))
        #expect(CustomCommand(name: "Note", type: .prompt, prompt: "x").problem(among: []) == .nameTaken)
        #expect(CustomCommand(name: "reminder", type: .run, argv: ["x"]).problem(among: []) == .nameTaken)
    }

    let python = CustomCommand(name: "python", type: .run, argv: ["python3", "-c", "{input}"])
    let respond = CustomCommand(name: "respond", type: .prompt, summary: "Write a reply", prompt: "Write a short, polite reply.")
    let sh = CustomCommand(name: "sh", type: .terminal, argv: ["zsh", "-c", "{input}"])

    @Test func catalogAddsValidCustomCommandsAfterTheBuiltIns() {
        let catalog = Command.catalog([
            python, respond, sh,
            CustomCommand(name: "open", type: .run, argv: ["x"]),           // taken by a built-in
            CustomCommand(name: "Python", type: .run, argv: ["python2"]),  // taken (names are case-insensitive)
            CustomCommand(name: "py3", type: .run, argv: ["python3"]),     // digits pick from the list
            CustomCommand(name: "empty", type: .prompt, prompt: "  "),     // nothing to tell the model
            CustomCommand(name: "noargv", type: .run),
        ])
        #expect(catalog.map(\.name) == ["improve", "translate", "question", "agent", "open", "reply", "note", "reminder", "py", "js",
                                        "tasks", "settings", "imessage", "reportissue", "python", "respond", "sh"])
        #expect(catalog.suffix(3).map(\.kind) == [.run, .generate, .terminal])
        #expect(Command.matching("p", in: catalog).map(\.name) == ["py", "python"])
        #expect(Command.parse("@python print(1)", in: catalog)?.command.custom == python)
        #expect(Command.parse("@python print(1)") == nil)  // without the catalog it's not a command
    }

    @Test func inputStaysOneArgument() {
        // Quotes and shell syntax in the text never leave its argument.
        #expect(python.arguments(for: "print('a'); import os") == ["python3", "-c", "print('a'); import os"])
        #expect(sh.arguments(for: "echo hi; rm -rf ~") == ["zsh", "-c", "echo hi; rm -rf ~"])
        let wrapped = CustomCommand(name: "say", type: .run, argv: ["say", "--", "Hi {input}!"], ascii: false)
        #expect(wrapped.arguments(for: "a b") == ["say", "--", "Hi a b!"])
        let calc = CustomCommand(name: "calculate", type: .run, argv: ["bc", "-l"], stdin: "{input}\n")
        #expect(calc.standardInput(for: "1+1") == "1+1\n" && python.standardInput(for: "x") == nil)
    }

    @Test func latinCommandsTakeHalfWidthPunctuation() {
        #expect(python.typesLatin && sh.typesLatin && !respond.typesLatin)
        #expect(python.arguments(for: "if True: print（“牛逼”）")[2] == "if True: print(\"牛逼\")")
        #expect(CustomCommand.halfWidth("a，b：c；【1】") == "a,b:c;[1]")
        // A prompt command keeps the text as typed.
        let typed = CustomCommand(name: "t", type: .terminal, argv: ["echo", "{input}"], ascii: false)
        #expect(typed.arguments(for: "你好，世界")[1] == "你好，世界")
    }

    @Test func customPromptGoesToTheModel() throws {
        let command = try #require(Command.catalog([respond]).last)
        let system = Prompt.commandSystem(command)
        #expect(system.contains("inserted at their cursor") && system.hasSuffix("Write a short, polite reply."))
        #expect(!Prompt.commandSystem(.question).contains("polite reply"))
    }

    @Test func configReadsCustomCommands() throws {
        let json = """
            {"customCommands": [{"name": "python", "type": "run", "argv": ["python3", "-c", "{input}"]},
                                {"name": "respond", "type": "prompt", "summary": "Write a reply", "prompt": "Write a short, polite reply."}]}
            """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.customCommands == [python, respond])
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).customCommands.isEmpty)
        // Written back as they were (unset fields stay out of the file).
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(again.customCommands == config.customCommands)
        #expect(!String(decoding: try JSONEncoder().encode(python), as: UTF8.self).contains("prompt"))
    }

    @Test func commandRequestShape() throws {
        var config = Config.default
        config.temperature = nil
        let request = Prompt.commandRequest(.question, input: "量子计算是什么", config: config)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)  // no few-shot examples: the text goes as typed
        #expect((messages[0]["content"] as? [[String: Any]])?.first?["text"] as? String == "量子计算是什么")
        let system = try #require((json["system"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(system.contains("inserted at their cursor") && system.contains("Answer the user's question"))
        #expect((json["inferenceConfig"] as? [String: Any])?["temperature"] == nil)
    }

    @Test func answersBecomeOneSafeLine() {
        #expect(Converter.oneLine("  First line.\nSecond\tline.\u{1B}[31m  ") == "First line. Second line. [31m")
        // An answer keeps its lines (code): indentation stays, tabs are 4 spaces, fences and controls go,
        // blank lines collapse.
        let code = "Here:\n```swift\nfunc f() {\n\treturn 1   \n}\n```\n\n\n\nDone.\u{1B}[0m\n"
        #expect(Converter.lines(code) == "Here:\nfunc f() {\n    return 1\n}\n\nDone. [0m")
    }

    @Test func commandLines() {
        typealias C = CustomCommand
        #expect(C.arguments(fromCommandLine: "python3 -c {input}") == ["python3", "-c", "{input}"])
        #expect(C.arguments(fromCommandLine: #"say -v "Ting-Ting" '{input}'  "#) == ["say", "-v", "Ting-Ting", "{input}"])
        #expect(C.arguments(fromCommandLine: #"zsh -c "{input}; exec zsh""#) == ["zsh", "-c", "{input}; exec zsh"])
        #expect(C.arguments(fromCommandLine: #"echo a\ b "" x"#) == ["echo", "a b", "", "x"])
        #expect(C.arguments(fromCommandLine: #"echo "open"#) == nil)
        #expect(C.arguments(fromCommandLine: "   ") == [])
        // One line and back gives the same arguments.
        for argv in [["python3", "-c", "{input}"], ["zsh", "-c", "{input}; exec zsh"], ["echo", #"say "hi" \ there"#, ""]] {
            #expect(C.arguments(fromCommandLine: C.commandLine(argv)) == argv)
        }
        #expect(C.commandLine(["python3", "-c", "{input}"]) == "python3 -c {input}")
    }

    @Test func editorProblems() {
        let ok = CustomCommand(name: "respond", type: .prompt, prompt: "Reply politely.")
        #expect(ok.problem(among: []) == nil)
        #expect(CustomCommand(name: "", type: .prompt, prompt: "x").problem(among: []) == .emptyName)
        #expect(CustomCommand(name: "py3", type: .run, argv: ["python3"]).problem(among: []) == .nameNotLetters)
        #expect(CustomCommand(name: "Open", type: .run, argv: ["x"]).problem(among: []) == .nameTaken)  // built-in
        #expect(CustomCommand(name: "calculate", type: .run, argv: ["bc", "-l"]).problem(among: []) == nil)  // no longer one
        #expect(ok.problem(among: [CustomCommand(name: "Respond", type: .prompt, prompt: "y")]) == .nameTaken)
        #expect(CustomCommand(name: "x", type: .prompt, prompt: "  ").problem(among: []) == .emptyPrompt)
        #expect(CustomCommand(name: "x", type: .terminal, argv: []).problem(among: []) == .emptyCommand)
    }

    @Test func usageCountsOftenAndLately() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = CommandUsage()
        usage.record("calculate", now: now)
        usage.record("calculate", now: now)
        #expect(usage.score("calculate", now: now) == 2)
        #expect(abs(usage.score("calculate", now: now + CommandUsage.halfLife) - 1) < 1e-9)  // halves in a week
        #expect(usage.score("never", now: now) == 0)
        // Long unused commands are forgotten when another is used.
        usage.record("py", now: now + 60 * 86400)
        #expect(usage.score("calculate", now: now + 60 * 86400) == 0)
        // Kept as JSON between launches.
        let again = try? JSONDecoder().decode(CommandUsage.self, from: JSONEncoder().encode(usage))
        #expect(again == usage)
    }

    @Test func paletteShowsFiveByUse() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let custom = ["calculate", "sh", "respond", "python", "japanese"].map {
            CustomCommand(name: $0, type: .run, argv: ["x"])
        }
        let catalog = Command.catalog(custom)  // 16 built-in + 5 ("calculate" is no built-in's name)
        // Nothing used yet: the first five in catalog order.
        #expect(Command.palette("", in: catalog, usage: CommandUsage(), now: now).map(\.name)
            == ["improve", "translate", "question", "agent", "open"])
        // The most used first, the rest in catalog order.
        var usage = CommandUsage()
        for _ in 0..<3 { usage.record("python", now: now) }
        usage.record("sh", now: now)
        usage.record("japanese", now: now - 30 * 86400)  // long ago: less than sh today
        #expect(Command.palette("", in: catalog, usage: usage, now: now).map(\.name)
            == ["python", "sh", "japanese", "improve", "translate"])
        // Letters: the name typed in full first, then names starting with them, then names containing them; by use
        // within each.
        #expect(Command.palette("py", in: catalog, usage: usage, now: now).map(\.name) == ["py", "python"])
        #expect(Command.palette("pyt", in: catalog, usage: usage, now: now).map(\.name) == ["python"])
        #expect(Command.palette("p", in: catalog, usage: usage, now: now).map(\.name) == ["python", "py", "japanese", "improve", "open"])
        #expect(Command.palette("a", in: catalog, usage: usage, now: now).map(\.name) == ["agent", "japanese", "translate", "tasks", "imessage"])
        #expect(Command.palette("calc", in: catalog, usage: usage, now: now).map(\.custom) == [custom[0]])  // the user's own
        #expect(Command.palette("o", in: catalog, usage: usage, now: now).map(\.name) == ["open", "python", "improve", "question", "note"])
        #expect(Command.palette("zz", in: catalog, usage: usage, now: now).isEmpty)
    }

    @Test func theNameTypedInFullComesFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let catalog = Command.catalog(["reply", "rep", "prep"].map { CustomCommand(name: $0, type: .prompt, prompt: "x") })
        var usage = CommandUsage()
        for _ in 0..<5 { usage.record("reply", now: now) }
        usage.record("reportissue", now: now)
        // "rep" exactly first, though used least; then the names starting with it by use, then those containing it.
        #expect(Command.palette("rep", in: catalog, usage: usage, now: now).map(\.name) == ["rep", "reply", "reportissue", "prep"])
        #expect(Command.palette("REP", in: catalog, usage: usage, now: now).first?.name == "rep")
        // Without one of that name, the groups as before.
        #expect(Command.palette("repo", in: catalog, usage: usage, now: now).map(\.name) == ["reportissue"])
        #expect(Command.palette("re", in: catalog, usage: usage, now: now).map(\.name).prefix(3) == ["reply", "reportissue", "reminder"])
        // The list as typed: "@rep" Tab picks it.
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = catalog
        c.commandUsage = usage
        for key in [KeyEvent(keyCode: 0x13, characters: "@", modifiers: .shift), k("r"), k("e"), k("p"),
                    KeyEvent(keyCode: VirtualKey.tab, characters: "\t")] { _ = c.handleKeyDown(key) }
        #expect(c.draft == "@rep ")
    }

    @Test func openWebAddresses() {
        #expect(SearchResult.web("github.com")?.path == "https://github.com")
        #expect(SearchResult.web("github.com/weijianz-opc/AllInOneIME")?.name == "github.com/weijianz-opc/AllInOneIME")
        #expect(SearchResult.web("www.example.app")?.path == "https://www.example.app")
        #expect(SearchResult.web("http://localhost:8080/a")?.webURL?.port == 8080)
        #expect(SearchResult(name: "", path: "HTTPS://example.com").webURL != nil)  // opened in the browser, not as a file
        #expect(SearchResult.web("baidu.cn")?.webURL?.host == "baidu.cn")
        // localhost and IP addresses, with a port or not: a server here or on the network, over http (it listed nothing).
        #expect(SearchResult.web("localhost:3000") == SearchResult(name: "localhost:3000", path: "http://localhost:3000"))
        #expect(SearchResult.web("localhost")?.path == "http://localhost")
        #expect(SearchResult.web("localhost:3000/api/v1")?.name == "localhost:3000/api/v1")
        #expect(SearchResult.web("127.0.0.1:8080")?.path == "http://127.0.0.1:8080")
        #expect(SearchResult.web("192.168.1.1")?.webURL?.host == "192.168.1.1")
        #expect(SearchResult.web("https://localhost:3000")?.path == "https://localhost:3000")  // as written
        #expect(SearchResult.web("http://localhost:8080/a")?.name == "localhost:8080/a")
        #expect(SearchResult.isIPv4("10.0.0.255") && !SearchResult.isIPv4("1.2.3") && !SearchResult.isIPv4("256.1.1.1")
                && !SearchResult.isIPv4("1.2.3.4.5") && !SearchResult.isIPv4("1..2.3"))
        // File names, paths and words stay a file search.
        for query in ["report.pdf", "Safari.app", "notes.md", "~/Downloads", "/Applications/", "微信", "hello world.com", "file:///etc",
                      "1.2.3", "999.1.1.1", "localhost.pem", "v1.2.3.4", "me@localhost"] {
            #expect(SearchResult.web(query) == nil, "\(query)")
        }
        #expect(SearchResult(name: "", path: "/Users/me/a.txt").webURL == nil)
    }
}
