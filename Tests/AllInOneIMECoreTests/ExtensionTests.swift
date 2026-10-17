import Foundation
import Testing
@testable import AllInOneIMECore

struct ExtensionTests {
    let file = URL(fileURLWithPath: "/tmp/scripts/convert-timestamp.sh")

    func command(_ text: String, executable: Bool = true) -> ScriptCommand? {
        guard case let .success(command)? = ScriptCommand.read(text, file: file, executable: executable) else { return nil }
        return command
    }

    func problem(_ text: String, executable: Bool = true) -> ScriptCommand.Problem? {
        guard case let .failure(problem)? = ScriptCommand.read(text, file: file, executable: executable) else { return nil }
        return problem
    }

    // MARK: - The protocol's keys

    @Test func defaults() throws {
        let c = try #require(command(script()))
        #expect(c.name == "converttimestamp" && c.title == "converttimestamp" && c.source == .script)
        // One free-text argument, required; insert; 10 seconds; 150 ms between keys and a list's run.
        #expect(c.arguments == [ScriptCommand.Argument()] && c.input == .required && c.output == .insert)
        #expect(!c.background && c.status == nil && !c.confirm && c.timeout == 10 && c.queryDelay == 0.15)
        #expect(c.directory.path == "/tmp/scripts" && c.extensionDirectory.path == "/tmp/scripts" && c.launch == [file.path])
        #expect(c.icon == nil && c.group == nil && c.keywords.isEmpty && c.alias == nil)
    }

    @Test func everyKey() throws {
        let c = try #require(command(script([
            "name Stamp2", "alias stamp", "title Convert Timestamp", "description Unix time to a date", "group Dev Tools",
            "keywords time, epoch", "icon ⏱", "input optional", #"argument1 {"type": "text", "placeholder": "timestamp"}"#,
            "output show", "background true", "confirm true", "timeout 30", "queryDelay 400", "status ./left.sh --short",
            "statusRefresh 5s", "currentDirectoryPath ~", "authorURL https://example.com", "somethingNew 1",
        ])))
        #expect(c.name == "stamp2" && c.alias == "stamp" && c.names == ["stamp2", "stamp"])
        #expect(c.title == "Convert Timestamp" && c.description == "Unix time to a date" && c.group == "Dev Tools")
        #expect(c.keywords == ["time", "epoch"] && c.icon == .emoji("⏱") && c.emoji == "⏱")
        #expect(c.input == .optional && c.arguments == [ScriptCommand.Argument(placeholder: "timestamp", optional: true)])
        #expect(c.output == .show && c.background && c.confirm && c.timeout == 30 && c.queryDelay == 0.4)
        // A status command line, its program from the script's folder; never more often than every 10 s.
        #expect(c.status == ScriptCommand.Status(launch: ["/tmp/scripts/left.sh", "--short"], refresh: 10, isSelf: false))
        #expect(c.directory.path == NSHomeDirectory())
        #expect(c.searchTerms == ["convert", "timestamp", "time", "epoch"])
    }

    @Test func inputAndArguments() throws {
        #expect(command(script(["input none"]))?.arguments == [])
        #expect(command(script(["input none", #"argument1 {"type": "text"}"#]))?.arguments == [])  // none wins
        let optional = try #require(command(script([#"argument1 {"type": "text", "optional": true}"#])))
        #expect(optional.input == .optional)  // all optional: optional
        let two = try #require(command(script([#"argument1 {"type": "text"}"#, #"argument2 {"type": "text", "optional": true}"#])))
        #expect(two.input == .required && two.arguments.count == 2)
        // Background: ten minutes unless it says.
        #expect(command(script(["background true"]))?.timeout == ScriptCommand.backgroundTimeout)
        // Status: the script itself (`self`), every minute by default; "1h", "2d", plain seconds.
        let status = try #require(command(script(["status self"]))?.status)
        #expect(status.isSelf && status.launch == [file.path] && status.refresh == 60)
        #expect(ScriptCommand.duration("1h") == 3600 && ScriptCommand.duration("2d") == 172_800 && ScriptCommand.duration("90") == 90)
        #expect(ScriptCommand.duration("soon") == nil && ScriptCommand.duration("-5s") == nil)
    }

    @Test func icons() {
        func icon(_ value: String) -> ScriptCommand.Icon? { command(script(["icon \(value)"]))?.icon }
        #expect(icon("♊️") == .emoji("♊️") && icon("👩🏽‍💻") == .emoji("👩🏽‍💻"))
        #expect(icon("battery.75percent") == .symbol("battery.75percent"))
        #expect(icon("images/icon.png") == .image(URL(fileURLWithPath: "/tmp/scripts/images/icon.png")))
        #expect(icon("https://example.com/icon.png") == nil)  // never fetched
    }

    @Test func versionsAndBadValues() {
        #expect(problem("#!/bin/bash\n# @allinoneime.title X\n") == .missing("schemaVersion"))
        #expect(problem(script().replacingOccurrences(of: "schemaVersion 1", with: "schemaVersion 2")) == .newerProtocol(2))
        #expect(problem(script().replacingOccurrences(of: "schemaVersion 1", with: "schemaVersion one")) == .badValue(key: "schemaVersion", value: "one"))
        #expect(problem(script(["output table"])) == .badValue(key: "output", value: "table"))
        #expect(problem(script(["input maybe"])) == .badValue(key: "input", value: "maybe"))
        #expect(problem(script(["background yes"])) == .badValue(key: "background", value: "yes"))
        #expect(problem(script(["timeout 0"])) == .badValue(key: "timeout", value: "0"))
        #expect(problem(script(["queryDelay soon"])) == .badValue(key: "queryDelay", value: "soon"))
        #expect(problem(script(["statusRefresh often", "status self"])) == .badValue(key: "statusRefresh", value: "often"))
        #expect(problem(script(["name 2fast"])) == .badValue(key: "name", value: "2fast"))
        #expect(problem(script(["name my-tool"])) == .badValue(key: "name", value: "my-tool"))
        #expect(problem(script(["argument2 {\"type\": \"text\"}"])) == .badArgument(2))
        #expect(problem(script(["argument1 {\"type\": \"number\"}"])) == .badArgument(1))
        #expect(problem(script(["argument1 {\"type\": \"dropdown\", \"data\": []}"])) == .badArgument(1))
        #expect(problem("# @allinoneime.schemaVersion 1\n", executable: false) == .notRunnable)
        // Unknown keys are ignored: a newer extension still loads.
        #expect(command(script(["shiny new"])) != nil)
        // No metadata at all: not a script (any other file in a folder).
        #expect(ScriptCommand.read("#!/bin/bash\necho hello\n", file: file, executable: true) == nil)
    }

    /// Any language's comments: `//` (JavaScript, Swift), `#` (Python), `--` (AppleScript); `@allinoneime.` keys
    /// win over `@raycast.` ones in the same file.
    @Test func commentStyles() throws {
        let js = "#!/usr/bin/env node\n// @allinoneime.schemaVersion 1\n// @allinoneime.title Word Count\nconsole.log(1)\n"
        let node = try #require(command(js, executable: false))
        #expect(node.title == "Word Count" && node.launch == ["/usr/bin/env", "node", file.path])  // through its "#!" line
        let applescript = "#!/usr/bin/osascript\n-- @allinoneime.schemaVersion 1\n-- @allinoneime.output silent\n"
        #expect(command(applescript)?.output == .silent)
        let both = script(["title Native"]) + "# @raycast.title Raycast\n# @raycast.mode fullOutput\n"
        #expect(command(both)?.title == "Native" && command(both)?.source == .script)
        let py = "#!/usr/bin/env python3\n# @allinoneime.schemaVersion 1\nprint(\"@allinoneime.title not this\")\n"
        #expect(command(py)?.title == "converttimestamp")
    }

    // MARK: - Raycast Script Commands

    @Test func raycastModes() throws {
        func mapped(_ mode: String, _ extra: [String] = []) -> ScriptCommand? { command(raycast(mode: mode, extra)) }
        #expect(mapped("fullOutput")?.output == .show)
        #expect(mapped("compact")?.output == .silent && mapped("silent")?.output == .silent)
        // inline: silent; with refreshTime, a status of the script itself.
        #expect(mapped("inline")?.output == .silent && mapped("inline")?.status == nil)
        let inline = try #require(mapped("inline", ["refreshTime 5m"]))
        #expect(inline.status == ScriptCommand.Status(launch: [file.path], refresh: 300, isSelf: true))
        #expect(problem(raycast(mode: "toast")) == .badValue(key: "mode", value: "toast"))
        let gemini = try #require(command(raycast(title: "Gemini CLI", mode: "silent", ["packageName Gemini", "icon ♊️",
                                                                                    "needsConfirmation true", "currentDirectoryPath /tmp"])))
        #expect(gemini.source == .raycast && gemini.title == "Gemini CLI" && gemini.group == "Gemini" && gemini.emoji == "♊️")
        #expect(gemini.confirm && gemini.directory.path == "/tmp")
        // No arguments: input none; with them, the same keys.
        #expect(gemini.input == ScriptCommand.Input.none && gemini.arguments.isEmpty)
        let flights = try #require(command(raycast([#"argument1 {"type": "text", "placeholder": "from"}"#,
                                                    #"argument2 {"type": "text", "placeholder": "to", "secure": true}"#])))
        #expect(flights.input == .required && flights.arguments.map(\.kind) == [.text, .password])
        #expect(command(raycast())?.group == "scripts")  // no packageName: the folder's name
        for key in ["schemaVersion", "title", "mode"] {
            let without = raycast().split(separator: "\n").filter { !$0.contains("@raycast.\(key)") }.joined(separator: "\n")
            #expect(problem(without + "\n# @raycast.description x\n") == .missing(key))
        }
        #expect(problem(raycast(["platform windows"])) == .notForMac)
    }

    // MARK: - Names

    @Test func names() {
        func name(_ file: String) -> String { ScriptCommand.commandName(for: URL(fileURLWithPath: "/x/" + file)) }
        #expect(name("convert-timestamp.sh") == "converttimestamp" && name("gemini.sh") == "gemini")
        #expect(name("base64.py") == "base64" && name("2fa-codes.sh") == "facodes" && name("Open_In-VSCode.applescript") == "openinvscode")
        #expect(name("翻译.sh") == "" && name(String(repeating: "a", count: 30) + ".sh").count == 24)
        #expect(ScriptCommand.isValidName("base64") && !ScriptCommand.isValidName("64base") && !ScriptCommand.isValidName("Base")
                && !ScriptCommand.isValidName("my-tool") && !ScriptCommand.isValidName(""))
        #expect(ScriptCommand.isTemplate(URL(fileURLWithPath: "/x/github.template.sh")))
        let unnamed = ScriptCommand.read(script(), file: URL(fileURLWithPath: "/tmp/翻译.sh"), executable: true)
        #expect(unnamed == .failure(.noName))
    }

    // MARK: - The text as arguments

    func takes(_ arguments: [ScriptCommand.Argument]) -> ScriptCommand {
        ScriptCommand(file: file, name: "x", arguments: arguments)
    }

    @Test func splittingTheText() {
        #expect(ScriptCommand(file: file, name: "x", input: .none).arguments(from: "ignored") == .success([]))
        #expect(takes([.init(placeholder: "q")]).arguments(from: "  new york, ny  ") == .success(["new york, ny"]))
        let two = takes([.init(placeholder: "from city"), .init(placeholder: "to city")])
        #expect(two.arguments(from: "beijing, new york") == .success(["beijing", "new york"]))
        #expect(two.arguments(from: "北京，纽约") == .success(["北京", "纽约"]))
        #expect(two.arguments(from: "a, b, c,d") == .success(["a", "b, c,d"]))  // the last takes the rest
        #expect(two.arguments(from: "") == .failure(.missing(["from city", "to city"])))
        #expect(two.arguments(from: " , new york") == .failure(.missing(["from city"])))
        let three = takes([.init(placeholder: "a"), .init(placeholder: "b", optional: true), .init(placeholder: "c", optional: true)])
        #expect(three.arguments(from: "x,,z") == .success(["x", "", "z"]) && three.arguments(from: "x") == .success(["x", "", ""]))
        #expect(takes([.init()]).arguments(from: " ") == .failure(.missing(["$1"])))
    }

    @Test func dropdownsPasswordsAndEncoding() {
        let unit = ScriptCommand.Argument(kind: .dropdown, placeholder: "unit",
                                          choices: [.init(title: "Celsius", value: "c"), .init(title: "Fahrenheit", value: "f")])
        let s = takes([.init(placeholder: "degrees"), unit])
        #expect(s.arguments(from: "30, celsius") == .success(["30", "c"]) && s.arguments(from: "30, F") == .success(["30", "f"]))
        #expect(s.arguments(from: "30, kelvin") == .failure(.notAChoice("unit", ["Celsius", "Fahrenheit"])))
        #expect(takes([.init(placeholder: "q", percentEncoded: true)]).arguments(from: "a b&c=d/é") == .success(["a%20b%26c%3Dd%2F%C3%A9"]))
        #expect(takes([.init(kind: .password)]).arguments(from: "s3cr3t!") == .success(["s3cr3t!"]))
    }

    // MARK: - Output

    @Test func textAndSummaries() {
        #expect(ScriptOutput.parse("first\n\nsecond") == .text("first\n\nsecond"))
        #expect(ScriptOutput.parse("first\n\nsecond").lines == ["first", "second"] && ScriptOutput.parse("a\nlast").headline == "last")
        let summary = ScriptOutput.parse(#"{"summary": "3 tests failed", "detail": "see the log"}"#)
        #expect(summary == .summary("3 tests failed", detail: "see the log") && summary.headline == "3 tests failed")
        #expect(summary.copyText == "3 tests failed\nsee the log")
        #expect(ScriptOutput.parse(#"{"summary": 42}"#) == .summary("42", detail: nil))
        #expect(ScriptOutput.parse(#"{"other": 1}"#) == .text(#"{"other": 1}"#))  // JSON, but neither: text
        #expect(ScriptOutput.parse("{not json").isEmpty == false && ScriptOutput.parse("").isEmpty)
    }

    /// The subset of Alfred's Script Filter JSON, and our `action`.
    @Test func scriptFilterLists() throws {
        let json = #"""
            {"rerun": 0.1, "items": [
              {"title": "Jane Doe", "subtitle": "Engineer · Seattle", "arg": "https://example.com/jane", "text": {"copy": "jdoe"}},
              {"title": "Notes", "arg": "~/Documents/notes.txt"},
              {"title": "Plain", "arg": "hello"},
              {"title": "No arg"},
              {"title": "Second step", "arg": "42", "action": "run", "autocomplete": "jane "},
              {"title": "Copy me", "arg": "x", "action": "copy"},
              {"title": "Information", "valid": false},
              {"subtitle": "no title: left out"},
              {"title": "Many args", "arg": ["one", "two"], "uid": "ignored", "icon": {"path": "ignored.png"}}
            ]}
            """#
        guard case let .list(list) = ScriptOutput.parse(json) else { Issue.record("not a list"); return }
        #expect(list.rerun == ScriptList.minimumRerun)
        #expect(list.items.map(\.title) == ["Jane Doe", "Notes", "Plain", "No arg", "Second step", "Copy me", "Information", "Many args"])
        #expect(list.items.map(\.action) == [.open, .open, .insert, .insert, .run, .copy, .insert, .insert])
        let jane = list.items[0]
        #expect(jane.subtitle == "Engineer · Seattle" && jane.copyText == "jdoe" && jane.openTarget == "https://example.com/jane")
        #expect(list.items[1].openTarget == NSHomeDirectory() + "/Documents/notes.txt")
        #expect(list.items[2].insertText == "hello" && list.items[3].insertText == "No arg" && list.items[3].copyText == "No arg")
        #expect(list.items[4].autocomplete == "jane " && !list.items[6].valid && list.items[7].arg == "one")
        let many = ScriptOutput.parse(#"{"items": ["# + (1...80).map { #"{"title": "\#($0)"}"# }.joined(separator: ",") + "]}")
        if case let .list(long) = many { #expect(long.items.count == ScriptList.maxItems && long.rerun == nil) }
    }

    // MARK: - Bundles and preferences

    let manifest = #"""
        {"schemaVersion": 1, "name": "tools", "title": "Team Tools", "version": "1.2.0", "author": "Someone",
         "preferences": [
           {"name": "apiToken", "type": "password", "title": "API token", "required": true},
           {"name": "region", "type": "dropdown", "title": "Region", "default": "eu", "data": [{"title": "Europe", "value": "eu"}]},
           {"name": "verbose", "type": "checkbox", "title": "Verbose", "default": false},
           {"name": "host", "title": "Host"}
         ],
         "commands": [
           {"script": "search.sh", "name": "find", "output": "list", "queryDelay": 300, "alias": "teamfind",
            "argument1": {"type": "text", "placeholder": "who"}},
           {"script": "bin/deploy.py", "title": "Deploy", "background": true, "confirm": true},
           {"script": "missing.sh"},
           {"script": "../outside.sh"},
           {"script": "bad.sh", "output": "table"}
         ]}
        """#

    @Test func bundles() throws {
        let folder = ScriptFolder()
        folder.add("tools/extension.json", manifest)
        folder.add("tools/search.sh", "#!/bin/bash\n# @allinoneime.title Search people\n# @allinoneime.output insert\necho\n")
        folder.add("tools/bin/deploy.py", "#!/usr/bin/env python3\nprint()\n", executable: false)
        folder.add("tools/bad.sh", "#!/bin/bash\n")
        folder.add("tools/lib/shared.sh", "# helpers\n")
        let index = folder.load()
        let bundle = try #require(index.bundles.first)
        #expect(bundle.name == "tools" && bundle.title == "Team Tools" && bundle.version == "1.2.0" && bundle.author == "Someone")
        #expect(bundle.preferences.map(\.kind) == [.password, .dropdown, .checkbox, .textfield])
        #expect(bundle.preferences.map(\.defaultValue) == [nil, "eu", "false", nil] && bundle.preferences[0].required)
        #expect(index.commands.map(\.name) == ["find", "deploy"])
        let find = index.commands[0]
        // The entry's keys over the script's own: the title from the script, the output from the entry.
        #expect(find.title == "Search people" && find.output == .list && find.queryDelay == 0.3 && find.alias == "teamfind")
        #expect(find.id == "tools/find" && find.source == .bundle("tools") && find.group == "Team Tools")
        #expect(find.arguments == [ScriptCommand.Argument(placeholder: "who")] && find.extensionDirectory == folder.url.appendingPathComponent("tools"))
        let deploy = index.commands[1]
        #expect(deploy.background && deploy.confirm && deploy.launch.prefix(2) == ["/usr/bin/env", "python3"])
        #expect(Set(index.skipped.map(\.problem)) == [.notRunnable, .badValue(key: "script", value: "../outside.sh"),
                                                     .badValue(key: "output", value: "table")])
        #expect(index.bundle(of: find) == bundle)
    }

    @Test func preferences() throws {
        let folder = ScriptFolder()
        folder.add("tools/extension.json", manifest)
        folder.add("tools/search.sh", "#!/bin/bash\n")
        folder.add("tools/bin/deploy.py", "#!/usr/bin/env python3\n")
        let bundle = try #require(folder.load().bundles.first)
        #expect(bundle.values([:]) == ["region": "eu", "verbose": "false"])
        #expect(bundle.missing([:]).map(\.name) == ["apiToken"] && bundle.missing(["apiToken": "t"]).isEmpty)
        #expect(bundle.values(["apiToken": "t", "host": "h", "verbose": "true"]) == ["apiToken": "t", "region": "eu", "verbose": "true", "host": "h"])
        #expect(ExtensionBundle.Preference.variable("apiToken") == "ALLINONEIME_PREF_APITOKEN")
        #expect(ExtensionBundle.Preference.variable("my-host.name") == "ALLINONEIME_PREF_MY_HOST_NAME")
        #expect(ExtensionBundle.Preference.keychainAccount(bundle: "tools", name: "apiToken") == "extension.tools.apiToken")
    }

    @Test func bundleProblems() {
        func problem(_ json: String) -> ScriptCommand.Problem? {
            let folder = ScriptFolder()
            folder.add("b/extension.json", json)
            return folder.load().skipped.first?.problem
        }
        #expect(problem("[]") == .badBundle(.notJSON))
        #expect(problem(#"{"name": "b", "commands": [{"script": "x.sh"}]}"#) == .missing("schemaVersion"))
        #expect(problem(#"{"schemaVersion": 3, "name": "b", "commands": []}"#) == .newerProtocol(3))
        #expect(problem(#"{"schemaVersion": 1, "name": "b c", "commands": [{"script": "x.sh"}]}"#) == .badBundle(.badName))
        #expect(problem(#"{"schemaVersion": 1, "name": "b", "commands": []}"#) == .badBundle(.noCommands))
        // Two bundles with one name (their scripts differ): the first is kept.
        let folder = ScriptFolder()
        for name in ["a", "b"] {
            folder.add("\(name)/extension.json", #"{"schemaVersion": 1, "name": "same", "commands": [{"script": "x.sh"}]}"#)
            folder.add("\(name)/x.sh", "#!/bin/bash\necho \(name)\n")
        }
        let index = folder.load()
        #expect(index.bundles.map(\.folder.lastPathComponent) == ["a"] && index.skipped.map(\.problem) == [.bundleTaken])
        #expect(index.identical.isEmpty)
    }

    // MARK: - Environment

    @Test func environment() throws {
        let folder = ScriptFolder()
        folder.add("tools/extension.json", manifest)
        folder.add("tools/search.sh", "#!/bin/bash\n")
        folder.add("tools/bin/deploy.py", "#!/usr/bin/env python3\n")
        let find = try #require(folder.load().commands.first)
        let context = ScriptContext(language: "zh", inputLanguage: "ko", app: "com.apple.TextEdit", query: "jane, seattle")
        let env = context.environment(for: find, base: ["PATH": "/usr/bin", "HOME": "/Users/x"], preferences: ["apiToken": "t", "region": "eu"])
        #expect(env["PATH"] == "/usr/bin" && env["HOME"] == "/Users/x")
        #expect(env["ALLINONEIME_PROTOCOL"] == "1" && env["ALLINONEIME_VERSION"] == AppVersion.string)
        #expect(env["ALLINONEIME_LANGUAGE"] == "zh" && env["ALLINONEIME_INPUT_LANGUAGE"] == "ko" && env["ALLINONEIME_APP"] == "com.apple.TextEdit")
        #expect(env["ALLINONEIME_QUERY"] == "jane, seattle" && env["ALLINONEIME_EXTENSION_DIR"] == folder.url.appendingPathComponent("tools").path)
        #expect(env["ALLINONEIME_PREF_APITOKEN"] == "t" && env["ALLINONEIME_PREF_REGION"] == "eu")
        #expect(env["ALLINONEIME_STATUS"] == nil && env["ALLINONEIME_ACTION"] == nil)
        let flags = context.environment(for: find, base: [:], status: true, action: true)
        #expect(flags["ALLINONEIME_STATUS"] == "1" && flags["ALLINONEIME_ACTION"] == "run")
    }

    // MARK: - Folders, order and names

    @Test func foldersAreReadLikeRaycastDoes() throws {
        let folder = ScriptFolder()
        folder.add("b-second.sh", script(["title Second"]))
        folder.add("a-first.sh", script(["title First"]))
        folder.add("github.template.sh", script(["title Template"]))  // to be filled in first: left out
        folder.add("README.md", "# Scripts\n")  // no metadata: not listed at all
        folder.add("broken.sh", script(["output table"]))
        folder.add(".hidden.sh", script(["title Hidden"]))
        folder.add("sub/nested.sh", script(["title Nested"]))  // a folder without extension.json: not read
        let index = folder.load()
        #expect(index.commands.map(\.title) == ["First", "Second"] && index.commands.first?.id.hasSuffix("/a-first.sh") == true)
        #expect(index.skipped.map(\.file.lastPathComponent) == ["broken.sh"])
        var hidden = folder.folder
        hidden.hidden = true
        #expect(ExtensionStore.load([hidden]).commands.isEmpty)
        #expect(ExtensionStore.load([.init(path: "/no/such/folder", found: false)]).commands.isEmpty)
    }

    // MARK: - Found folders and copies

    /// A folder of everything: a native script, a Raycast script, a bundle, a broken link.
    static func mixed(_ folder: ScriptFolder, raycastTitle: String = "Word Count") {
        folder.add("uuid.sh", script(["title New UUID", "input none"]))
        folder.add("word-count.sh", raycast(title: raycastTitle))
        folder.add("units/extension.json", #"{"schemaVersion": 1, "name": "units", "commands": [{"script": "convert.sh"}]}"#)
        folder.add("units/convert.sh", "#!/bin/bash\necho converted\n")
        try? FileManager.default.createSymbolicLink(atPath: folder.url.appendingPathComponent("gone.sh").path,
                                                    withDestinationPath: "/no/such/file.sh")
    }

    @Test func aFoundFolderGivesOnlyItsRaycastScripts() {
        let folder = ScriptFolder()
        Self.mixed(folder)
        folder.add("bad-raycast.sh", raycast(mode: "table"))  // a Raycast script that can't load: still said
        let found = ExtensionStore.load([.init(path: folder.url.path, found: true)])
        #expect(found.commands.map(\.name) == ["wordcount"] && found.commands.allSatisfy { $0.source == .raycast })
        #expect(found.bundles.isEmpty && found.identical.isEmpty)
        #expect(found.skipped == [.init(file: folder.url.appendingPathComponent("bad-raycast.sh"), problem: .badValue(key: "mode", value: "table"))])
        // The same folder added: all of it.
        let added = ExtensionStore.load([.init(path: folder.url.path, found: false)])
        #expect(added.commands.map(\.name) == ["convert", "uuid", "wordcount"] && added.bundles.map(\.name) == ["units"])
        #expect(Set(added.skipped.map(\.problem)) == [.brokenLink, .badValue(key: "mode", value: "table")])
        // Spotlight only makes a folder of Raycast scripts found: a native script that mentions Raycast's keys doesn't.
        let native = folder.add("both.sh", script(["title Both"], "# @raycast.schemaVersion 1\n# @raycast.title B\n# @raycast.mode compact"))
        #expect(!ExtensionStore.isScript(native) && ExtensionStore.isScript(folder.url.appendingPathComponent("word-count.sh")))
    }

    @Test func identicalCopiesAreLeftOutQuietly() {
        // An added folder, and two checkouts of a repository found by Spotlight; then one more added copy.
        let mine = ScriptFolder(), first = ScriptFolder(), second = ScriptFolder(), copy = ScriptFolder()
        Self.mixed(mine)
        Self.mixed(first)
        Self.mixed(second)
        Self.mixed(copy)
        let folders: [ExtensionStore.Folder] = [.init(path: mine.url.path, found: false), .init(path: copy.url.path, found: false),
                                                .init(path: first.url.path, found: true), .init(path: second.url.path, found: true)]
        let index = ExtensionStore.load(folders)
        // One of each, from the first folder; the copies are noted, not warned about (the broken links are the added
        // folders' own).
        #expect(index.commands.map(\.name) == ["convert", "uuid", "wordcount"] && index.bundles.map(\.folder) == [mine.url.appendingPathComponent("units")])
        #expect(index.commands.allSatisfy { $0.file.path.hasPrefix(mine.url.path) })
        #expect(index.skipped.map(\.problem) == [.brokenLink, .brokenLink])
        #expect(index.identical.map(\.lastPathComponent) == ["extension.json", "uuid.sh", "word-count.sh", "word-count.sh", "word-count.sh"])
        #expect(Command.hiddenScripts(index.commands, custom: []).isEmpty)
        // Turned the other way round, the found folders' first copy is the one kept.
        let reversed = ExtensionStore.load(Array(folders.reversed()))
        #expect(reversed.commands.map(\.file) == [copy.url.appendingPathComponent("units/convert.sh"), copy.url.appendingPathComponent("uuid.sh"),
                                                   second.url.appendingPathComponent("word-count.sh")])
    }

    @Test func copiesThatDifferStillClash() {
        let mine = ScriptFolder(), other = ScriptFolder()
        Self.mixed(mine)
        Self.mixed(other, raycastTitle: "Words")  // word-count.sh changed
        other.add("units/convert.sh", "#!/bin/bash\necho changed\n")  // a bundle's script changed: another bundle
        let index = ExtensionStore.load([.init(path: mine.url.path, found: false), .init(path: other.url.path, found: false)])
        #expect(index.identical.map(\.lastPathComponent) == ["uuid.sh"])
        #expect(index.skipped.map(\.problem) == [.brokenLink, .brokenLink, .bundleTaken])
        let hidden = Command.hiddenScripts(index.commands, custom: [])
        #expect(hidden.map(\.script.file) == [other.url.appendingPathComponent("word-count.sh")])
        #expect(hidden.first?.owner == .command(ExtensionStore.abbreviated(mine.url.appendingPathComponent("word-count.sh").path)))
        // The same content under another file name is another command, not a copy.
        other.add("wc.sh", raycast())
        mine.add("wc2.sh", raycast())
        #expect(ExtensionStore.load([.init(path: mine.url.path, found: false), .init(path: other.url.path, found: true)])
            .commands.map(\.name).sorted() == ["convert", "uuid", "wc", "wc2", "wordcount", "wordcount"])
        // All of a file counts, past the 64 KB read for its metadata.
        let padding = "# " + String(repeating: "x", count: ExtensionCache.maxBytes) + "\n"
        mine.add("big.sh", script(["title Big"], padding + "echo one"))
        other.add("big.sh", script(["title Big"], padding + "echo two"))
        let big = ExtensionStore.load([.init(path: mine.url.path, found: false), .init(path: other.url.path, found: false)])
        #expect(big.commands.filter { $0.name == "big" }.count == 2 && !big.identical.contains { $0.lastPathComponent == "big.sh" })
        // Two copies of a script that can't load are said once.
        mine.add("bad.sh", script(["output table"]))
        other.add("bad.sh", script(["output table"]))
        let bad = ExtensionStore.load([.init(path: mine.url.path, found: false), .init(path: other.url.path, found: false)])
        #expect(bad.skipped.filter { $0.file.lastPathComponent == "bad.sh" }.count == 1 && bad.identical.contains(other.url.appendingPathComponent("bad.sh")))
    }

    @Test func aFolderRemovedIsNoLongerFound() throws {
        let kept = ScriptFolder(), removed = ScriptFolder()
        let file = kept.add("up.sh", raycast())
        let gone = removed.add("up.sh", raycast())
        // Spotlight's index may still list a removed folder's files for a while: they're read, so it's dropped.
        let output = file.path + "\n" + gone.path
        #expect(ExtensionStore.folders(fromSpotlight: output, home: "/nowhere") == [kept.url.path, removed.url.path].sorted())
        try FileManager.default.removeItem(at: removed.url)
        #expect(ExtensionStore.folders(fromSpotlight: output, home: "/nowhere") == [kept.url.path])
        // What's loaded from a found folder that's gone: nothing, and nothing reported.
        let index = ExtensionStore.load([.init(path: removed.url.path, found: true)])
        #expect(index.commands.isEmpty && index.skipped.isEmpty)
    }

    @Test func orderAndCollisions() throws {
        let one = ScriptFolder(), two = ScriptFolder()
        one.add("weather.sh", raycast(title: "Raycast Weather"))
        one.add("weather.py", script(["title Native Weather"]))
        two.add("kit/extension.json", #"{"schemaVersion": 1, "name": "kit", "commands": [{"script": "w.sh", "name": "weather", "alias": "kitweather"}, {"script": "w.sh", "name": "note", "alias": "kitnote"}, {"script": "w.sh", "name": "reply"}]}"#)
        two.add("kit/w.sh", "#!/bin/bash\n")
        let index = ExtensionStore.load([one.folder, two.folder])
        // Bundles first (whatever their folder), then single scripts, then Raycast scripts.
        #expect(index.commands.map(\.source) == [.bundle("kit"), .bundle("kit"), .bundle("kit"), .script, .raycast])
        let custom = [CustomCommand(name: "reply", type: .prompt, prompt: "x")]
        let plugin = InstalledPlugin(manifest: PluginManifest(name: "kitnote", version: "1", type: .prompt, prompt: "x"), directory: one.url, isLocal: true)
        let catalog = Command.catalog(custom, plugins: [plugin], scripts: index.commands)
        let names = catalog.compactMap { command in command.script.map { "\($0.id)=\(command.name)" } }
        // The bundle's weather first; the single script's and Raycast's are hidden by it.
        #expect(names == ["kit/weather=weather"])
        let hidden = Command.hiddenScripts(index.commands, custom: custom, plugins: [plugin])
        #expect(hidden.map(\.owner) == [.builtIn, .custom, .command("kit/weather"), .command("kit/weather")])
        #expect(hidden.map(\.script.name) == ["note", "reply", "weather", "weather"])
        // A name that's taken: the alias, when that's free.
        let withAlias = Command.catalog([CustomCommand(name: "weather", type: .prompt, prompt: "x")], scripts: index.commands)
        #expect(withAlias.first { $0.script?.id == "kit/weather" }?.name == "kitweather")
        let cmd = try #require(withAlias.first { $0.script != nil })
        #expect(cmd.kind == .run && cmd.runsCode && !cmd.typesLatin && cmd.program == nil && !CommandPlan.canBeInner(cmd))
    }

    @Test func turningThingsOff() {
        let folder = ScriptFolder()
        folder.add("one.sh", script())
        folder.add("kit/extension.json", #"{"schemaVersion": 1, "name": "kit", "commands": [{"script": "a.sh"}, {"script": "b.sh"}]}"#)
        folder.add("kit/a.sh", "#!/bin/bash\n")
        folder.add("kit/b.sh", "#!/bin/bash\n")
        let index = folder.load()
        #expect(index.enabled([]).map(\.name) == ["a", "b", "one"])
        #expect(index.enabled(["kit/a"]).map(\.name) == ["b", "one"])
        #expect(index.enabled(["kit"]).map(\.name) == ["one"])
        #expect(index.enabled([ExtensionStore.abbreviated(folder.url.appendingPathComponent("one.sh").path)]).map(\.name) == ["a", "b"])
    }

    @Test func theCacheReadsOnlyWhatChanged() throws {
        let folder = ScriptFolder()
        let file = folder.add("a.sh", script(["title One"]))
        folder.add("b.sh", script(["title Two"]))
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // whole seconds: kept exactly by the file system
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        let cache = ExtensionCache()
        #expect(folder.load(cache: cache).commands.map(\.title) == ["One", "Two"] && cache.count == 2)
        // The same size and date: what was read before (even if the file says otherwise now).
        try Data(script(["title Uno"]).utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        #expect(folder.load(cache: cache).commands.map(\.title) == ["One", "Two"])
        try FileManager.default.setAttributes([.modificationDate: date.addingTimeInterval(5)], ofItemAtPath: file.path)
        #expect(folder.load(cache: cache).commands.map(\.title) == ["Uno", "Two"])
    }

    @Test func foldersAddedFoundAndHidden() {
        var config = Config.default
        #expect(config.extensionFolders == [ExtensionStore.defaultFolder] && config.findRaycastScripts)
        config.extensionFolders = ["~/mine"]
        config.hiddenExtensionFolders = ["~/Documents/old"]
        let folders = ExtensionStore.folders(config, found: ["~/Documents/scripts", "~/mine", "~/Documents/old"])
        #expect(folders == [.init(path: "~/mine", found: false), .init(path: "~/Documents/scripts", found: true),
                            .init(path: "~/Documents/old", found: true, hidden: true)])
        config.findRaycastScripts = false
        #expect(ExtensionStore.folders(config, found: ["~/Documents/scripts"]) == [.init(path: "~/mine", found: false)])
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
        #expect(ExtensionStore.folders(fromSpotlight: output, home: "/Users/me", isScript: { _ in true })
            == ["/opt/scripts", "~/Documents/脚本", "~/code/script-commands/commands/dev"])
        let folder = ScriptFolder()
        let real = folder.add("up.sh", raycast())
        let code = folder.add("Notes.swift", "/// # @raycast.schemaVersion 1\n/// # @raycast.title X\n/// # @raycast.mode compact\n", executable: false)
        #expect(ExtensionStore.folders(fromSpotlight: code.path, home: "/nowhere").isEmpty)
        #expect(ExtensionStore.folders(fromSpotlight: code.path + "\n" + real.path, home: "/nowhere") == [folder.url.path])
        #expect(ExtensionStore.abbreviated("/Users/me", home: "/Users/me") == "~")
    }

    @Test func configKeys() throws {
        let decoded = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(decoded.extensionFolders == [ExtensionStore.defaultFolder] && decoded.findRaycastScripts)
        #expect(decoded.hiddenExtensionFolders.isEmpty && decoded.disabledExtensions.isEmpty && decoded.extensionPreferences.isEmpty)
        var config = Config.default
        config.extensionFolders = []
        config.findRaycastScripts = false
        config.hiddenExtensionFolders = ["~/x"]
        config.disabledExtensions = ["kit", "~/a.sh"]
        config.extensionPreferences = ["kit": ["region": "eu"]]
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(again.extensionFolders.isEmpty && !again.findRaycastScripts && again.hiddenExtensionFolders == ["~/x"])
        #expect(again.disabledExtensions == ["kit", "~/a.sh"] && again.extensionPreferences == ["kit": ["region": "eu"]])
    }

    // MARK: - Running

    func run(_ command: ScriptCommand, _ arguments: [String] = [], environment: [String: String] = ["PATH": "/usr/bin:/bin"],
             status: Bool = false) async -> Result<[CommandRunner.ScriptUpdate], Error> {
        do {
            var updates: [CommandRunner.ScriptUpdate] = []
            for try await update in CommandRunner.run(command, arguments: arguments, environment: environment, status: status) {
                updates.append(update)
            }
            return .success(updates)
        } catch {
            return .failure(error)
        }
    }

    @Test func runsInItsFolderWithItsEnvironment() async throws {
        let folder = ScriptFolder()
        folder.add("args.sh", script([#"argument1 {"type": "text"}"#, #"argument2 {"type": "text"}"#],
                                     #"printf '1=%s\n2=%s\n' "$1" "$2"; pwd; echo "$PATH|$ALLINONEIME_LANGUAGE"; printf '\033[31mred\033[0m\033]0;title\007\n'"#))
        let c = try #require(folder.load().commands.first)
        let env = ScriptContext(language: "en", inputLanguage: "en", app: nil, query: "q").environment(for: c, base: ["PATH": "/usr/bin:/bin"])
        let final = try #require(try await run(c, ["beijing", "new york"], environment: env).get().last)
        #expect(final.isFinal && final.output.lines == ["1=beijing", "2=new york", folder.url.path, "/usr/bin:/bin:/usr/local/bin|en", "red"])
        // Not executable: through its "#!" line.
        folder.add("plain.sh", script(["input none"], "echo from bash"), executable: false)
        let plain = try #require(folder.load().commands.first { $0.name == "plain" })
        let ran = try await run(plain).get().last?.text
        #expect(plain.launch.first == "/bin/bash" && ran == "from bash")
    }

    @Test func whatItPrintsArrivesAsItComes() async throws {
        let folder = ScriptFolder()
        folder.add("progress.sh", script(["output show", "input none"], "for i in 1 2 3; do echo \"step $i\"; sleep 0.25; done; echo done"))
        let c = try #require(folder.load().commands.first)
        let updates = try await run(c).get()
        let partial = updates.filter { !$0.isFinal }.map(\.text)
        #expect(partial.count >= 2 && partial.first?.hasPrefix("step 1") == true)
        #expect(updates.last?.isFinal == true && updates.last?.output.lines == ["step 1", "step 2", "step 3", "done"])
    }

    @Test func aFailureSaysItsLastLine() async throws {
        let folder = ScriptFolder()
        folder.add("fails.sh", script(["input none"], "echo working; echo 'City not found'; exit 2"))
        folder.add("stderr.sh", script(["input none"], "echo out; echo 'the reason' >&2; exit 1"))
        folder.add("slow.sh", script(["input none", "timeout 0.3"], "sleep 5"))
        let commands = folder.load().commands
        func error(_ name: String) async throws -> CommandRunner.RunError? {
            let c = try #require(commands.first { $0.name == name })
            if case let .failure(error) = await run(c) { return error as? CommandRunner.RunError }
            return nil
        }
        let (fails, stderr, slow) = (try await error("fails"), try await error("stderr"), try await error("slow"))
        #expect(fails == .failed(status: 2, message: "City not found"))
        #expect(stderr == .failed(status: 1, message: "the reason"))
        #expect(slow == .timedOut(0.3))
    }

    @Test func statusRunsItsOwnCommand() async throws {
        let folder = ScriptFolder()
        folder.add("timer.sh", script(["status self"], #"if [ -n "$ALLINONEIME_STATUS" ]; then echo "12:04 left"; else echo "full"; fi"#))
        folder.add("left.sh", "#!/bin/bash\necho \"3 left $1\"\n")
        folder.add("other.sh", script(["status left.sh now"], "echo main"))
        let commands = folder.load().commands
        let timer = try #require(commands.first { $0.name == "timer" })
        let env = ScriptContext(language: "en", inputLanguage: "en", app: nil, query: "").environment(for: timer, base: ["PATH": "/usr/bin:/bin"], status: true)
        let timerStatus = try await run(timer, environment: env, status: true).get().last?.output.lines.first
        #expect(timerStatus == "12:04 left")
        let other = try #require(commands.first { $0.name == "other" })
        let otherStatus = try await run(other, status: true).get().last?.text
        #expect(otherStatus == "3 left now")
    }
}
