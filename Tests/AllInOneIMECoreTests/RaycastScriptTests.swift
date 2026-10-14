import Foundation
import Testing
@testable import AllInOneIMECore

/// A folder of scripts made for one test, removed after it.
final class ScriptFolder {
    let url: URL

    init() {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("raycast-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        // /private/var/…, as the folder's listing names its files (`resolvingSymlinksInPath` gives /var/… back).
        url = URL(fileURLWithPath: realpath(made.path, nil).map { defer { free($0) }; return String(cString: $0) } ?? made.path,
                  isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Writes `name` with `text`, executable unless `executable` is false.
    @discardableResult
    func add(_ name: String, _ text: String, executable: Bool = true) -> URL {
        let file = url.appendingPathComponent(name)
        try? Data(text.utf8).write(to: file)
        try? FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
        return file
    }

    var folder: RaycastScriptStore.Folder { RaycastScriptStore.Folder(path: url.path, found: false) }

    func load() -> (scripts: [RaycastScript], skipped: [RaycastScriptStore.Skipped]) { RaycastScriptStore.load([folder]) }
}

/// A bash script with Raycast metadata: `body` after it, `extra` metadata lines ("argument1 {…}").
func bash(title: String = "Test", mode: String = "compact", _ extra: [String] = [], _ body: String = "echo hi") -> String {
    (["#!/bin/bash", "# @raycast.schemaVersion 1", "# @raycast.title \(title)", "# @raycast.mode \(mode)"]
        + extra.map { "# @raycast.\($0)" } + [body]).joined(separator: "\n") + "\n"
}

struct RaycastScriptTests {
    let file = URL(fileURLWithPath: "/tmp/scripts/convert-timestamp.sh")

    func script(_ text: String, executable: Bool = true) -> RaycastScript? {
        guard case let .success(script)? = RaycastScript.read(text, file: file, executable: executable) else { return nil }
        return script
    }

    func problem(_ text: String, executable: Bool = true) -> RaycastScript.Problem? {
        guard case let .failure(problem)? = RaycastScript.read(text, file: file, executable: executable) else { return nil }
        return problem
    }

    // MARK: - Metadata

    @Test func readsBashMetadata() throws {
        let s = try #require(script(bash(title: "Convert Timestamp", [
            "packageName Dev Tools", "icon ⏱", "description Unix time to a date", "author Jane", "needsConfirmation true",
            #"argument1 { "type": "text", "placeholder": "timestamp", "percentEncoded": true }"#,
        ])))
        #expect(s.name == "converttimestamp" && s.title == "Convert Timestamp" && s.mode == .compact)
        #expect(s.packageName == "Dev Tools" && s.icon == "⏱" && s.emoji == "⏱" && s.description == "Unix time to a date")
        #expect(s.author == "Jane" && s.needsConfirmation)
        #expect(s.arguments == [RaycastScript.Argument(placeholder: "timestamp", percentEncoded: true)])
        #expect(s.directory.path == "/tmp/scripts" && s.launch == ["/tmp/scripts/convert-timestamp.sh"])
        #expect(s.timeout == CustomCommand.defaultTimeout)
    }

    /// Any language's comments: `//` (JavaScript, Swift), `#` (Python), `--` (AppleScript).
    @Test func readsOtherLanguagesComments() throws {
        let js = """
            #!/usr/bin/env node
            // @raycast.schemaVersion 1
            // @raycast.title Word Count
            // @raycast.mode fullOutput
            console.log(process.argv[2])
            """
        let node = try #require(script(js, executable: false))
        #expect(node.title == "Word Count" && node.mode == .fullOutput && node.timeout == RaycastScript.fullOutputTimeout)
        // Not executable: run through its "#!" line.
        #expect(node.launch == ["/usr/bin/env", "node", file.path])
        let py = """
            #!/usr/bin/env python3

            # Required parameters:
            # @raycast.schemaVersion 1
            # @raycast.title  Python Thing
            # @raycast.mode silent
            # @raycast.packageName Py
            # @raycast.currentDirectoryPath ~
            import sys
            print("@raycast.title not this one")
            """
        let python = try #require(script(py))
        #expect(python.title == "Python Thing" && python.mode == .silent && python.packageName == "Py")
        #expect(python.directory.path == NSHomeDirectory())
        let applescript = "#!/usr/bin/osascript\n-- @raycast.schemaVersion 1\n-- @raycast.title Mute\n-- @raycast.mode inline\n"
        #expect(script(applescript)?.mode == .inline)
        // No package: the folder's name.
        #expect(script(bash())?.packageName == "scripts")
        // A relative currentDirectoryPath is from the script's folder.
        #expect(script(bash(["currentDirectoryPath data"]))?.directory.path == "/tmp/scripts/data")
    }

    @Test func requiredKeysAndWhatIsWrong() {
        #expect(RaycastScript.read("#!/bin/bash\necho hello\n", file: file, executable: true) == nil)  // not a script at all
        #expect(problem("#!/bin/bash\n# @raycast.title X\n# @raycast.mode compact\n") == .missing("schemaVersion"))
        #expect(problem("#!/bin/bash\n# @raycast.schemaVersion 1\n# @raycast.mode compact\n") == .missing("title"))
        #expect(problem("#!/bin/bash\n# @raycast.schemaVersion 1\n# @raycast.title X\n") == .missing("mode"))
        #expect(problem(bash().replacingOccurrences(of: "schemaVersion 1", with: "schemaVersion 2")) == .schemaVersion("2"))
        #expect(problem(bash(mode: "toast")) == .unknownMode("toast"))
        #expect(problem(bash(["argument1 { not json"])) == .badArgument(1))
        #expect(problem(bash([#"argument1 {"type": "number"}"#])) == .badArgument(1))
        #expect(problem(bash([#"argument2 {"type": "text"}"#])) == .badArgument(2))  // without argument1
        #expect(problem(bash([#"argument1 {"type": "dropdown", "data": []}"#])) == .badArgument(1))
        #expect(problem(bash(["platform windows"])) == .notForMac)
        #expect(script(bash(["platform macOS"])) != nil)
        // Neither executable nor with a "#!" line: nothing to run it with.
        #expect(problem("# @raycast.schemaVersion 1\n# @raycast.title X\n# @raycast.mode compact\n", executable: false) == .notRunnable)
        let unnamed = RaycastScript.read(bash(), file: URL(fileURLWithPath: "/tmp/scripts/翻译-2.sh"), executable: true)
        #expect(unnamed == .failure(.noName))
    }

    @Test func argumentsAndTheirKinds() throws {
        let s = try #require(script(bash([
            #"argument1 { "type": "text", "placeholder": "query" }"#,
            #"argument2 { "type": "text", "placeholder": "token", "secure": true, "optional": true }"#,
            #"argument3 { "type": "dropdown", "placeholder": "unit", "data": [{"title": "Celsius", "value": "c"}, {"title": "Fahrenheit", "value": "f"}] }"#,
        ])))
        #expect(s.arguments.map(\.kind) == [.text, .password, .dropdown])
        #expect(s.arguments.map(\.optional) == [false, true, false])
        #expect(s.arguments[2].choices == [.init(title: "Celsius", value: "c"), .init(title: "Fahrenheit", value: "f")])
        #expect(!s.runsWhenPicked && script(bash())?.runsWhenPicked == true)
    }

    @Test func commandNames() {
        func name(_ file: String) -> String { RaycastScript.commandName(for: URL(fileURLWithPath: "/x/" + file)) }
        #expect(name("convert-timestamp.sh") == "converttimestamp")
        #expect(name("gemini.sh") == "gemini")
        #expect(name("Open_In-VSCode.applescript") == "openinvscode")
        #expect(name("base64.py") == "base")
        #expect(name("noextension") == "noextension")
        #expect(name("翻译.sh") == "")
        #expect(name(String(repeating: "a", count: 30) + ".sh").count == 24)
        #expect(RaycastScript.isTemplate(URL(fileURLWithPath: "/x/github.template.sh")))
    }

    @Test func emojiIcons() {
        func emoji(_ icon: String?) -> String? {
            var s = RaycastScript(file: file, name: "x", title: "X", mode: .compact, packageName: "P")
            s.icon = icon
            return s.emoji
        }
        #expect(emoji("♊️") == "♊️" && emoji("🤖") == "🤖" && emoji("👩🏽‍💻") == "👩🏽‍💻")
        #expect(emoji("images/icon.png") == nil && emoji("https://example.com/i.png") == nil && emoji("A") == nil)
        #expect(emoji("1") == nil && emoji(nil) == nil)
    }

    // MARK: - The text as arguments

    func takes(_ arguments: [RaycastScript.Argument]) -> RaycastScript {
        RaycastScript(file: file, name: "x", title: "X", mode: .compact, packageName: "P", arguments: arguments)
    }

    @Test func splittingTheText() {
        let none = takes([])
        #expect(none.arguments(from: "ignored text") == .success([]))
        let one = takes([.init(placeholder: "query")])
        #expect(one.arguments(from: "  new york, ny  ") == .success(["new york, ny"]))  // all of it: commas too
        let two = takes([.init(placeholder: "from city"), .init(placeholder: "to city")])
        #expect(two.arguments(from: "beijing, new york") == .success(["beijing", "new york"]))
        #expect(two.arguments(from: "北京，纽约") == .success(["北京", "纽约"]))  // a full-width comma
        #expect(two.arguments(from: "a, b, c,d") == .success(["a", "b, c,d"]))  // the rest stays in the last one
        let three = takes([.init(placeholder: "a"), .init(placeholder: "b", optional: true), .init(placeholder: "c", optional: true)])
        #expect(three.arguments(from: "x,,z") == .success(["x", "", "z"]))
        #expect(three.arguments(from: "x") == .success(["x", "", ""]))  // optional ones left out
    }

    @Test func missingRequiredArguments() {
        let two = takes([.init(placeholder: "from city"), .init(placeholder: "to city")])
        #expect(two.arguments(from: "") == .failure(.missing(["from city", "to city"])))
        #expect(two.arguments(from: "beijing") == .failure(.missing(["to city"])))
        #expect(two.arguments(from: " , new york") == .failure(.missing(["from city"])))
        #expect(takes([.init()]).arguments(from: " ") == .failure(.missing(["$1"])))  // no placeholder: its number
        #expect(takes([.init(optional: true)]).arguments(from: "") == .success([""]))
    }

    @Test func dropdownsAndEncoding() {
        let unit = RaycastScript.Argument(kind: .dropdown, placeholder: "unit",
                                          choices: [.init(title: "Celsius", value: "c"), .init(title: "Fahrenheit", value: "f")])
        let s = takes([.init(placeholder: "degrees"), unit])
        #expect(s.arguments(from: "30, celsius") == .success(["30", "c"]))  // by title, any case
        #expect(s.arguments(from: "30, F") == .success(["30", "f"]))  // by value
        #expect(s.arguments(from: "30, kelvin") == .failure(.notAChoice("unit", ["Celsius", "Fahrenheit"])))
        let encoded = takes([.init(placeholder: "q", percentEncoded: true)])
        #expect(encoded.arguments(from: "a b&c=d/é") == .success(["a%20b%26c%3Dd%2F%C3%A9"]))
        // A password goes to the script as typed.
        #expect(takes([.init(kind: .password, placeholder: "token")]).arguments(from: "s3cr3t!") == .success(["s3cr3t!"]))
    }

    // MARK: - Output

    @Test func outputByMode() {
        func result(_ mode: RaycastScript.Mode, _ output: String) -> [String] {
            RaycastScript(file: file, name: "x", title: "X", mode: mode, packageName: "P").result(for: output).versions.map(\.text)
        }
        let output = "first\n\nsecond\nlast"
        #expect(result(.fullOutput, output) == [output, "first", "second", "last"])  // all, then each line
        #expect(result(.fullOutput, "one line") == ["one line"])
        #expect(result(.fullOutput, (1...20).map(String.init).joined(separator: "\n")).count == 9)  // as many as digits pick
        #expect(result(.compact, output) == ["last"])
        #expect(result(.inline, output) == ["last"])
        #expect(result(.silent, output) == ["last"])
        #expect(result(.compact, "").isEmpty && result(.fullOutput, "").isEmpty)
    }

    func run(_ script: RaycastScript, _ arguments: [String] = []) async -> Result<[String], Error> {
        do {
            var versions: [String] = []
            for try await update in CommandRunner.run(script, arguments: arguments, environment: ["PATH": "/usr/bin:/bin"])
            where update.isFinal {
                versions = update.result.versions.map(\.text)
            }
            return .success(versions)
        } catch {
            return .failure(error)
        }
    }

    @Test func runsWithItsArgumentsInItsFolder() async throws {
        let folder = ScriptFolder()
        folder.add("args.sh", bash(mode: "fullOutput", [#"argument1 {"type": "text"}"#, #"argument2 {"type": "text"}"#],
                                   #"printf '1=%s\n2=%s\n' "$1" "$2"; pwd; echo "$PATH"; printf '\033[31mred\033[0m\n'"#))
        let s = try #require(folder.load().scripts.first)
        let lines = try await run(s, ["beijing", "new york"]).get()
        #expect(lines.dropFirst() == ["1=beijing", "2=new york", folder.url.path, "/usr/bin:/bin:/usr/local/bin", "red"])
        // Not executable: through its "#!" line.
        folder.add("plain.sh", bash(mode: "compact", [], "echo from bash"), executable: false)
        let plain = try #require(folder.load().scripts.first { $0.name == "plain" })
        #expect(plain.launch.first == "/bin/bash")
        #expect(try await run(plain).get() == ["from bash"])
    }

    @Test func aFailureSaysItsLastLine() async throws {
        let folder = ScriptFolder()
        folder.add("fails.sh", bash([], "echo working; echo 'City not found'; exit 2"))
        folder.add("stderr.sh", bash([], "echo out; echo 'the reason' >&2; exit 1"))
        let scripts = folder.load().scripts
        let fails = await run(try #require(scripts.first { $0.name == "fails" }))
        #expect((fails.error as? CommandRunner.RunError) == .failed(status: 2, message: "City not found"))
        let stderr = await run(try #require(scripts.first { $0.name == "stderr" }))
        #expect((stderr.error as? CommandRunner.RunError) == .failed(status: 1, message: "the reason"))
    }

    // MARK: - Folders

    @Test func foldersAreScannedLikeRaycast() throws {
        let folder = ScriptFolder()
        folder.add("b-second.sh", bash(title: "Second"))
        folder.add("a-first.sh", bash(title: "First"))
        folder.add("github.template.sh", bash(title: "Template"))  // to be filled in first: left out
        folder.add("README.md", "# Scripts\n")  // no metadata: not listed at all
        folder.add("broken.sh", bash(mode: "loud"))
        folder.add(".hidden.sh", bash(title: "Hidden"))
        try FileManager.default.createDirectory(at: folder.url.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(bash(title: "Nested").utf8).write(to: folder.url.appendingPathComponent("sub/nested.sh"))  // not recursive
        let (scripts, skipped) = folder.load()
        #expect(scripts.map(\.title) == ["First", "Second"])
        #expect(skipped.map(\.file.lastPathComponent) == ["broken.sh"] && skipped.first?.problem == .unknownMode("loud"))
        // A hidden folder is not read; one that doesn't exist is nothing.
        var hidden = folder.folder
        hidden.hidden = true
        #expect(RaycastScriptStore.load([hidden]).scripts.isEmpty)
        #expect(RaycastScriptStore.load([.init(path: "/no/such/folder", found: false)]).scripts.isEmpty)
    }

    @Test func theFirstScriptWithANameWins() throws {
        let one = ScriptFolder(), two = ScriptFolder()
        one.add("weather.sh", bash(title: "Weather One"))
        two.add("weather.py", bash(title: "Weather Two"))
        two.add("note.sh", bash(title: "Note"))
        let (scripts, skipped) = RaycastScriptStore.load([one.folder, two.folder])
        #expect(scripts.map(\.title) == ["Weather One", "Note"])
        #expect(skipped == [.init(file: two.url.appendingPathComponent("weather.py"), problem: .nameTaken(by: .script(one.url.appendingPathComponent("weather.sh"))))])
        // In the list after the built-in, plugin and custom commands; a name one of them has is theirs.
        let custom = [CustomCommand(name: "Weather", type: .prompt, prompt: "x")]
        let catalog = Command.catalog(custom, scripts: scripts)
        #expect(catalog.filter { $0.script != nil }.isEmpty)  // @note is built in, @weather custom
        #expect(catalog.first { $0.name == "weather" }?.custom != nil)
        let hidden = Command.hiddenScripts(scripts, custom: custom)
        #expect(hidden.map(\.script.title) == ["Weather One", "Note"] && hidden.map(\.owner) == [.custom, .builtIn])
        let free = Command.catalog([], scripts: scripts)
        let weather = try #require(free.first { $0.name == "weather" })
        #expect(weather.kind == .run && weather.script?.title == "Weather One" && free.last == weather)
        #expect(weather.runsCode && !weather.typesLatin && weather.program == nil)
        #expect(!CommandPlan.canBeInner(weather))  // not inside another command's text
        let plugin = InstalledPlugin(manifest: PluginManifest(name: "weather", version: "1", type: .prompt, prompt: "x"),
                                     directory: one.url, isLocal: true)
        #expect(Command.hiddenScripts(scripts, custom: [], plugins: [plugin]).map(\.owner) == [.plugin, .builtIn])
    }

    @Test func foldersAddedFoundAndHidden() {
        var config = Config.default
        #expect(config.scriptFolders == [RaycastScriptStore.defaultFolder] && config.findRaycastScripts)
        config.scriptFolders = ["~/mine"]
        config.hiddenScriptFolders = ["~/Documents/old"]
        let folders = RaycastScriptStore.folders(config, found: ["~/Documents/scripts", "~/mine", "~/Documents/old"])
        #expect(folders == [.init(path: "~/mine", found: false), .init(path: "~/Documents/scripts", found: true),
                            .init(path: "~/Documents/old", found: true, hidden: true)])
        config.findRaycastScripts = false
        #expect(RaycastScriptStore.folders(config, found: ["~/Documents/scripts"]) == [.init(path: "~/mine", found: false)])
    }

    @Test func spotlightResultsBecomeFolders() {
        let output = """
            /Users/me/Documents/脚本/gemini.sh
            /Users/me/Documents/脚本/other.sh
            /Users/me/code/script-commands/commands/dev/uuid.sh
            /Users/me/code/script-commands/templates/script-command.template.sh
            /Users/me/.Trash/old.sh
            /Users/me/Library/Caches/com.raycast.macos/copy.sh
            /Users/me/app/node_modules/pkg/x.js
            /opt/scripts/up.sh
            """
        #expect(RaycastScriptStore.folders(fromSpotlight: output, home: "/Users/me", isScript: { _ in true })
            == ["/opt/scripts", "~/Documents/脚本", "~/code/script-commands/commands/dev"])
        // Only files that are scripts: code or notes that mention the metadata (this test's own file) aren't.
        let folder = ScriptFolder()
        let script = folder.add("up.sh", bash())
        let code = folder.add("Notes.swift", "/// # @raycast.schemaVersion 1\n/// # @raycast.title X\n/// # @raycast.mode compact\n",
                              executable: false)
        #expect(RaycastScriptStore.folders(fromSpotlight: code.path, home: "/nowhere").isEmpty)
        #expect(RaycastScriptStore.folders(fromSpotlight: code.path + "\n" + script.path, home: "/nowhere") == [folder.url.path])
        #expect(RaycastScriptStore.abbreviated("/Users/me", home: "/Users/me") == "~")
        #expect(RaycastScriptStore.abbreviated("/Users/meme/x", home: "/Users/me") == "/Users/meme/x")
    }

    @Test func aChangedFolderIsSeen() throws {
        let folder = ScriptFolder()
        folder.add("a.sh", bash())
        let before = RaycastScriptStore.signature([folder.folder])
        #expect(before == RaycastScriptStore.signature([folder.folder]))
        folder.add("b.sh", bash())
        #expect(before != RaycastScriptStore.signature([folder.folder]))
    }

    @Test func configKeys() throws {
        let decoded = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(decoded.scriptFolders == [RaycastScriptStore.defaultFolder] && decoded.findRaycastScripts && decoded.hiddenScriptFolders.isEmpty)
        var config = Config.default
        config.scriptFolders = []
        config.findRaycastScripts = false
        config.hiddenScriptFolders = ["~/x"]
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(again.scriptFolders.isEmpty && !again.findRaycastScripts && again.hiddenScriptFolders == ["~/x"])
    }
}

/// Raycast scripts typed as @ commands: the action key runs them with their arguments, and what they print
/// is used as their mode says. The scripts are made in a temporary folder and really run.
struct RaycastScriptComposerTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    func typeKeys(_ text: String, _ composer: Composer) {
        for ch in text { _ = composer.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    /// A composer in English mode offering the scripts of `folder`.
    func composer(_ folder: ScriptFolder) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = Command.catalog([], scripts: folder.load().scripts)
        return c
    }

    /// The script `effects` start, and the arguments it gets.
    func started(_ effects: [Composer.Effect]) -> (command: Command, arguments: [String], id: Int)? {
        for effect in effects { if case let .startScript(command, arguments, id) = effect { return (command, arguments, id) } }
        return nil
    }

    /// Runs what `effects` start and gives the composer what it printed (or its failure); the effects of that.
    func finish(_ effects: [Composer.Effect], in c: Composer) async -> [Composer.Effect] {
        guard let (command, arguments, id) = started(effects), let script = command.script else { return [] }
        var out: [Composer.Effect] = []
        do {
            for try await update in CommandRunner.run(script, arguments: arguments, environment: ["PATH": "/usr/bin:/bin"]) {
                out += c.receive(update.result, isFinal: update.isFinal, id: id)
            }
        } catch {
            out += c.fail(error.localizedDescription, id: id)
        }
        return out
    }

    @Test func argumentsComeFromTheText() async throws {
        let folder = ScriptFolder()
        folder.add("flights.sh", bash(title: "Flights", mode: "compact",
                                      [#"argument1 {"type": "text", "placeholder": "from city"}"#,
                                       #"argument2 {"type": "text", "placeholder": "to city"}"#],
                                      #"echo "searching"; echo "$1 → $2""#))
        let c = composer(folder)
        typeKeys("@fl", c)
        #expect(c.paletteMatches.map(\.name) == ["flights"])
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@flights ")
        // Missing ones: a notice with their placeholders, nothing runs.
        #expect(c.handleKeyDown(enterKey).effects == [.notice("还要写：from city, to city")])
        typeKeys("beijing, new york", c)
        #expect(c.markedText == "flights › beijing, new york")
        let effects = c.handleKeyDown(enterKey).effects
        let start = try #require(started(effects))
        #expect(start.command.name == "flights" && start.arguments == ["beijing", "new york"] && start.id == 1)
        #expect(effects.contains(.commandUsed("flights")) && c.activeCommand?.script?.title == "Flights")
        // compact: the last line, to insert.
        #expect(await finish(effects, in: c) == [.showPanel])
        #expect(c.choices.map(\.text) == ["beijing, new york", "beijing → new york"] && c.highlighted == 1)
        #expect(commits(c.handleKeyDown(enterKey)) == ["beijing → new york"] && !c.isComposing)
        // A dropdown value that isn't a choice: the choices.
        folder.add("temp.sh", bash(title: "Temperature", [#"argument1 {"type": "dropdown", "placeholder": "unit", "data": [{"title": "Celsius", "value": "c"}]}"#]))
        let d = composer(folder)
        typeKeys("@temp kelvin", d)
        #expect(d.handleKeyDown(enterKey).effects == [.notice("只能是这几个之一：Celsius")])
        // An "@" in a script's text is just text (no list of commands inside it).
        let e = composer(folder)
        typeKeys("@flights me@", e)
        #expect(e.paletteQuery == nil)
    }

    @Test func eachModeDoesItsThing() async throws {
        let folder = ScriptFolder()
        folder.add("report.sh", bash(title: "Report", mode: "fullOutput", [], "echo one; echo two"))
        folder.add("toggle.sh", bash(title: "Toggle", mode: "silent", [], "echo working; echo 'Dark mode on'"))
        folder.add("quiet.sh", bash(title: "Quiet", mode: "compact", [], "true"))
        folder.add("status.sh", bash(title: "Status", mode: "inline", [#"argument1 {"type": "text", "optional": true}"#], "echo old; echo new"))
        folder.add("broken.sh", bash(title: "Broken", mode: "compact", [], "echo 'Not signed in'; exit 1"))

        // fullOutput: all of it, then each line; no row for the text (there is none).
        let full = composer(folder)
        typeKeys("@report", full)
        let picked = full.handleKeyDown(tab).effects  // no arguments: picked, it runs
        #expect(started(picked)?.arguments == [] && full.draft == "@report ")
        _ = await finish(picked, in: full)
        #expect(full.choices.map(\.text) == ["one\ntwo", "one", "two"] && full.choices.map(\.label) == ["1", "2", "3"])
        #expect(commits(full.handleKeyDown(k("3"))) == ["two"])

        // silent: what it said last, as a notice; nothing inserted.
        let silent = composer(folder)
        typeKeys("@toggle", silent)
        let done = await finish(silent.handleKeyDown(tab).effects, in: silent)
        #expect(done.contains(.notice("Dark mode on")) && commits(done) == [] && !silent.isComposing)

        // Nothing printed: that it ran.
        let quiet = composer(folder)
        typeKeys("@quiet", quiet)
        let ran = await finish(quiet.handleKeyDown(enterKey).effects, in: quiet)  // ⏎ picks and runs it too
        #expect(ran.contains(.notice("已运行：Quiet")) && !quiet.isComposing)

        // inline: like compact (no refreshing); typed text with the optional argument.
        let inline = composer(folder)
        typeKeys("@status x", inline)
        let effects = inline.handleKeyDown(enterKey).effects
        #expect(started(effects)?.arguments == ["x"])
        _ = await finish(effects, in: inline)
        #expect(inline.choices.last?.text == "new")

        // A failure: its last line, and ⏎ tries again.
        let broken = composer(folder)
        typeKeys("@broken", broken)
        _ = await finish(broken.handleKeyDown(tab).effects, in: broken)
        #expect(broken.phase == .failed("Not signed in"))
        #expect(started(broken.handleKeyDown(enterKey).effects) != nil)
    }

    @Test func confirmationFirst() async throws {
        let folder = ScriptFolder()
        folder.add("empty-trash.sh", bash(title: "Empty Trash", mode: "silent", ["needsConfirmation true"], "echo emptied"))
        let c = composer(folder)
        c.messages = .english
        typeKeys("@empty", c)
        // Picked: it asks first, and the draft stays.
        let asked = c.handleKeyDown(tab).effects
        #expect(asked.contains(.notice("Run Empty Trash? ⏎ again")) && started(asked) == nil && c.draft == "@emptytrash ")
        // Again: it runs.
        let effects = c.handleKeyDown(enterKey).effects
        #expect(started(effects) != nil)
        #expect(await finish(effects, in: c).contains(.notice("emptied")))
        // Changing the text asks again.
        let d = composer(folder)
        d.messages.actionKeyName = "⌥Space"
        d.messages.confirmScript = Composer.Messages.english.confirmScript
        typeKeys("@emptytrash", d)
        #expect(d.handleKeyDown(spaceKey).effects.contains(.notice("Run Empty Trash? ⌥Space again")))  // Space picks it too
        typeKeys("x", d)
        #expect(started(d.handleKeyDown(enterKey).effects) == nil)
        #expect(started(d.handleKeyDown(enterKey).effects) != nil)
    }

    @Test func escStopsIt() {
        // Like a run command's: Esc cancels the run (`cancelConversion`) and goes back to the draft. (The
        // controller refuses to start it while secure input is on, `refusedForSecureInput`.)
        let folder = ScriptFolder()
        folder.add("slow.sh", bash(title: "Slow", [], "sleep 5"))
        let c = composer(folder)
        typeKeys("@slow", c)
        #expect(started(c.handleKeyDown(tab).effects) != nil)
        #expect(c.handleKeyDown(escKey).effects.first == .cancelConversion)
    }
}

private extension Result where Failure == Error {
    var error: Error? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
