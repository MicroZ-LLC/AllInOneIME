import Foundation
import Testing
@testable import AllInOneIMECore

/// Script extensions where things are unusual: links, permissions changing, processes that don't stop, names that
/// clash inside a bundle, what a list row may open, and the rules for status lines and background runs.
struct ExtensionRobustnessTests {
    // MARK: - Folders and files

    @Test func linksAreFollowed() throws {
        let real = ScriptFolder(), other = ScriptFolder(), folder = ScriptFolder()
        real.add("hello.sh", script(["title Hello"]))
        other.add("linked.sh", script(["title Linked"]))
        other.add("kit/extension.json", #"{"schemaVersion": 1, "name": "kit", "commands": [{"script": "k.sh"}]}"#)
        other.add("kit/k.sh", "#!/bin/bash\n")
        let fm = FileManager.default
        // A folder that is a link, a script and a bundle that are links, and a link to nothing.
        let linkedFolder = folder.url.appendingPathComponent("scripts")
        try fm.createSymbolicLink(at: linkedFolder, withDestinationURL: real.url)
        try fm.createSymbolicLink(at: folder.url.appendingPathComponent("linked.sh"), withDestinationURL: other.url.appendingPathComponent("linked.sh"))
        try fm.createSymbolicLink(at: folder.url.appendingPathComponent("kit"), withDestinationURL: other.url.appendingPathComponent("kit"))
        try fm.createSymbolicLink(at: folder.url.appendingPathComponent("gone.sh"), withDestinationURL: other.url.appendingPathComponent("nothing.sh"))
        let viaLink = ExtensionStore.load([.init(path: linkedFolder.path, found: false)])
        #expect(viaLink.commands.map(\.title) == ["Hello"])
        let index = folder.load()
        #expect(index.commands.map(\.name) == ["k", "linked"] && index.bundles.map(\.name) == ["kit"])
        #expect(index.skipped == [.init(file: folder.url.appendingPathComponent("gone.sh"), problem: .brokenLink)])
    }

    @Test func permissionsArePartOfWhatChanged() throws {
        let folder = ScriptFolder()
        let file = folder.add("plain.sh", "# @allinoneime.schemaVersion 1\necho plain\n", executable: false)
        let cache = ExtensionCache()
        #expect(folder.load(cache: cache).skipped.map(\.problem) == [.notRunnable])
        // chmod +x changes neither the size nor the date: it's seen all the same.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let index = folder.load(cache: cache)
        #expect(index.skipped.isEmpty && index.commands.first?.launch == ["/bin/sh", file.path])
    }

    @Test func theCacheKeepsOnlyWhatsThere() throws {
        let folder = ScriptFolder()
        folder.add("a.sh", script())
        let gone = folder.add("b.sh", script())
        folder.add("notes.txt", String(repeating: "x", count: 100_000))
        let cache = ExtensionCache()
        _ = folder.load(cache: cache)
        #expect(cache.count == 3)
        try FileManager.default.removeItem(at: gone)
        _ = folder.load(cache: cache)
        #expect(cache.count == 2)
        _ = ExtensionStore.load([], cache: cache)
        #expect(cache.count == 0)
    }

    @Test func anExecutableWithoutAShebangLineRunsWithSh() async throws {
        let folder = ScriptFolder()
        folder.add("nobang.sh", "# @allinoneime.schemaVersion 1\n# @allinoneime.input none\necho \"from sh\"\n")
        let command = try #require(folder.load().commands.first)
        #expect(command.launch.first == "/bin/sh")
        var text = ""
        for try await update in CommandRunner.run(command, arguments: [], environment: ["PATH": "/usr/bin:/bin"]) where update.isFinal {
            text = update.text
        }
        #expect(text == "from sh")
    }

    @Test func twoCommandsWithOneNameInABundle() {
        let folder = ScriptFolder()
        folder.add("b/extension.json", #"{"schemaVersion": 1, "name": "b", "commands": [{"script": "one.sh", "name": "x"}, {"script": "two.sh", "name": "x"}]}"#)
        folder.add("b/one.sh", "#!/bin/bash\n")
        folder.add("b/two.sh", "#!/bin/bash\n")
        let index = folder.load()
        #expect(index.commands.map(\.id) == ["b/x"] && index.commands.first?.file.lastPathComponent == "one.sh")
        #expect(index.skipped.map(\.problem) == [.nameTaken("x", by: .command("b/x"))])
    }

    @Test func metadataNeedsACommentMark() {
        let file = URL(fileURLWithPath: "/tmp/notes.md")
        #expect(ScriptCommand.metadata(in: "@allinoneime.schemaVersion 1\n@allinoneime.title X\n") == nil)
        #expect(ScriptCommand.metadata(in: "  # @allinoneime.schemaVersion 1\n")?.keys == ["schemaVersion": "1"])
        #expect(ScriptCommand.read("@raycast.schemaVersion 1\n@raycast.title X\n@raycast.mode compact\n", file: file, executable: true) == nil)
    }

    @Test func raycastsOwnSchemaVersion() {
        let file = URL(fileURLWithPath: "/tmp/r.sh")
        let two = ScriptCommand.read(raycast().replacingOccurrences(of: "schemaVersion 1", with: "schemaVersion 2"), file: file, executable: true)
        #expect(two == .failure(.badValue(key: "schemaVersion", value: "2")))
    }

    @Test func requiredInputIsRequired() throws {
        let file = URL(fileURLWithPath: "/tmp/r.sh")
        guard case let .success(c)? = ScriptCommand.read(script(["input required", #"argument1 {"type": "text", "optional": true}"#]),
                                                         file: file, executable: true) else { Issue.record("not read"); return }
        #expect(c.input == .required && c.arguments.first?.optional == false && c.arguments(from: "") == .failure(.missing(["$1"])))
    }

    @Test func aPasswordIsntRepeatedInTheQuery() {
        let file = URL(fileURLWithPath: "/tmp/login.sh")
        let secret = ScriptCommand(file: file, name: "login", arguments: [.init(placeholder: "user"), .init(kind: .password, placeholder: "token")])
        let plain = ScriptCommand(file: file, name: "find", arguments: [.init(placeholder: "who")])
        let context = ScriptContext(language: "en", inputLanguage: "en", app: nil, query: "me, s3cr3t")
        #expect(context.environment(for: secret, base: [:])["ALLINONEIME_QUERY"] == "")
        #expect(context.environment(for: plain, base: [:])["ALLINONEIME_QUERY"] == "me, s3cr3t")
    }

    // MARK: - Processes

    /// A script that ignores SIGTERM, and what it started, are killed soon after its timeout.
    @Test func aStoppedScriptsChildrenGoToo() async throws {
        let folder = ScriptFolder()
        let pids = folder.url.appendingPathComponent("pids")
        folder.add("stubborn.sh", script(["input none", "timeout 1"],
                                         "trap '' TERM; sleep \(Timing.longSleep) & echo $! > \(pids.path); wait"))
        let command = try #require(folder.load().commands.first)
        let started = Date()
        var failure: CommandRunner.RunError?
        do {
            for try await _ in CommandRunner.run(command, arguments: [], environment: ["PATH": "/usr/bin:/bin"]) {}
        } catch {
            failure = error as? CommandRunner.RunError
        }
        // 1 s, then 0.5 s to SIGKILL (about 1.6 s). A busy test run can take ten times that or more (`Timing`): the
        // bound is against the script's child, which would hold it up for a minute if it weren't killed.
        #expect(failure == .timedOut(1))
        #expect(Date().timeIntervalSince(started) < Timing.wellBeforeLongSleep)
        let child = try #require(pid_t(String(decoding: try Data(contentsOf: pids), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        // Gone once it's reaped, which a busy test run can hold up (`Timing`).
        #expect(await Timing.eventually { kill(child, 0) != 0 }, "the script's child \(child) is still running")
    }

    /// When the input method quits (`CommandRunner.stopAll`), a running program's group goes, children and all.
    @Test func quittingStopsWhatsRunning() async throws {
        let folder = ScriptFolder()
        let pids = folder.url.appendingPathComponent("pids")
        folder.add("long.sh", script(["input none", "timeout 60"], "sleep 30 & echo $! > \(pids.path); wait"))
        let command = try #require(folder.load().commands.first)
        let task = Task {
            for try await _ in CommandRunner.run(command, arguments: [], environment: ["PATH": "/usr/bin:/bin"]) {}
        }
        // Started and its child's pid written, which a busy test run can take seconds to get to (`Timing`).
        var found: pid_t?
        _ = await Timing.eventually {
            found = (try? Data(contentsOf: pids)).flatMap { pid_t(String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
            return found != nil
        }
        let started = try #require(found)
        // Its group is the script's own (Foundation starts it in one), kept while it runs.
        let leader = getpgid(started)
        #expect(leader > 0 && leader != getpgrp() && CommandRunner.runningGroups.contains(leader))
        let child = started
        // `stopAll` with only this test's program.
        CommandRunner.stop(CommandRunner.runningPrograms.filter { $0.processIdentifier == leader }, grace: 0.3)
        #expect(await Timing.eventually { kill(child, 0) != 0 && kill(leader, 0) != 0 })
        _ = try? await task.value
    }

    // MARK: - Status lines and background runs

    @Test func statusLinesTakeTurns() {
        func command(_ name: String) -> ScriptCommand {
            ScriptCommand(id: name, file: URL(fileURLWithPath: "/x/\(name).sh"), name: name,
                          status: ScriptCommand.Status(launch: ["/x/\(name).sh"], refresh: 60, isSelf: true))
        }
        let shown = ["a", "b", "c"].map(command)
        var schedule = StatusSchedule()
        let now = Date()
        let first = schedule.due(shown, now: now).map(\.id)
        let none = schedule.due(shown, now: now)
        #expect(first == ["a", "b"] && none.isEmpty)  // two at once
        // One that fails frees its place: the next due one runs without waiting for another key.
        let failed = schedule.finished("a", line: nil, now: now)
        let next = schedule.due(shown, now: now).map(\.id)
        #expect(!failed && next == ["c"])
        let changed = schedule.finished("b", line: "12:04", now: now)
        let cFailed = schedule.finished("c", line: nil, now: now)
        #expect(changed && schedule.text(for: "b") == "12:04" && !cFailed && schedule.text(for: "c") == nil)
        // Due again after their refresh time, not before.
        let early = schedule.due(shown, now: now.addingTimeInterval(30))
        let later = schedule.due(shown, now: now.addingTimeInterval(61)).map(\.id)
        #expect(early.isEmpty && later == ["a", "b"])
        // A failure keeps the value before.
        let kept = schedule.finished("b", line: nil, now: now.addingTimeInterval(61))
        #expect(!kept && schedule.text(for: "b") == "12:04")
    }

    @Test func roomInTheBackground() {
        #expect(BackgroundRuns.admits("a", running: []))
        #expect(!BackgroundRuns.admits("a", running: ["a"]))  // not twice
        #expect(BackgroundRuns.admits("e", running: ["a", "b", "c"]))
        #expect(!BackgroundRuns.admits("e", running: ["a", "b", "c", "d"]))  // four at most
    }

    @Test func aNotificationSaysTheDetailToo() {
        #expect(ScriptOutput.summary("Deployed", detail: "3 services, 12 s").notificationBody == "Deployed\n3 services, 12 s")
        #expect(ScriptOutput.summary("Deployed", detail: nil).notificationBody == "Deployed")
        #expect(ScriptOutput.text("step 1\ndone").notificationBody == "done")
    }

    // MARK: - What a list row may open

    @Test func whatOpenOpens() throws {
        let folder = ScriptFolder()
        let file = folder.add("report.txt", "x", executable: false)
        let runnable = folder.add("evil.command", "#!/bin/bash\n")
        func url(_ arg: String) -> URL? { ScriptItem(title: "x", arg: arg, action: .open).openURL }
        #expect(url("https://example.com/a?b=c") == URL(string: "https://example.com/a?b=c"))
        #expect(url("HTTP://example.com") != nil && url("https:") == nil)
        #expect(url(file.path) == file && url("file://" + file.path) == file && url("~/")?.path == NSHomeDirectory())
        for refused in ["smb://server/share", "javascript:alert(1)", "claude-agent:abc", "myapp://do", "docs/report.txt",
                        folder.url.appendingPathComponent("missing.txt").path, runnable.path] {
            #expect(url(refused) == nil, "\(refused)")
        }
    }

    @Test func theComposerOpensOnlyThat() async throws {
        let folder = ScriptFolder()
        let file = folder.add("report.txt", "x", executable: false)
        folder.add("rows.sh", script(["output list", "input optional"], """
            printf '{"items": [{"title": "Share", "arg": "smb://server/share", "action": "open"}, {"title": "Report", "arg": "file://\(file.path)"}]}'
            """))
        let helpers = ExtensionComposerTests()
        let c = helpers.composer(folder)
        helpers.typeKeys("@rows ", c)
        _ = try await helpers.runList(c)
        // Something it can't open: said, and the list stays.
        let refused = c.handleKeyDown(enterKey).effects
        #expect(refused == [.notice("打不开：smb://server/share")] && c.isComposing)
        _ = c.handleKeyDown(downKey)
        #expect(c.handleKeyDown(enterKey).effects.contains(.openLink(file)) && !c.isComposing)
    }

    // MARK: - Lists as you type

    @Test func aListSaysWhatsMissing() {
        let folder = ScriptFolder()
        folder.add("cities.sh", script(["output list", #"argument1 {"type": "text", "placeholder": "city"}"#], "echo '{\"items\": []}'"))
        let helpers = ExtensionComposerTests()
        let c = helpers.composer(folder)
        helpers.typeKeys("@cities ", c)
        #expect(c.listQuery == "" && c.handleKeyDown(enterKey).effects == [.notice("还要写：city")])
    }

    @Test func rowsAsYouTypeAreNotNumbered() {
        let items = [ScriptItem(title: "a"), ScriptItem(title: "info", valid: false), ScriptItem(title: "b")]
        #expect(Composer.itemChoicesForPanel(items).map(\.label) == ["", "", ""])
        #expect(Composer.itemChoices(items).map(\.label) == ["1", "", "2"])  // in level two, where digits pick
    }

    // MARK: - How a file is started

    /// A compiled program in a bundle runs as itself, as a shell would run it. (Compiled here: macOS kills a copy
    /// of one of its own programs, like /bin/echo, run from elsewhere.)
    @Test func aCompiledProgramRunsAsItself() async throws {
        let folder = ScriptFolder()
        folder.add("tools/extension.json", #"{"schemaVersion": 1, "name": "tools", "commands": [{"script": "bin/hello", "name": "hello"}]}"#)
        let binary = folder.url.appendingPathComponent("tools/bin/hello")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = folder.add("hello.c", "#include <stdio.h>\nint main(int c, char **v) { printf(\"%s\\n\", c > 1 ? v[1] : \"\"); return 0; }\n",
                                executable: false)
        let cc = Process()
        cc.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        cc.arguments = [source.path, "-o", binary.path]
        try cc.run()
        cc.waitUntilExit()
        try #require(cc.terminationStatus == 0)
        let hello = try #require(folder.load().commands.first)
        #expect(hello.launch == [binary.path])
        var text = ""
        for try await update in CommandRunner.run(hello, arguments: ["from echo"], environment: ["PATH": "/usr/bin:/bin"]) where update.isFinal {
            text = update.text
        }
        #expect(text == "from echo")
    }

    /// A text script: without "#!", /bin/sh runs it (as a shell does when the system can't); with a byte order mark
    /// before its "#!" (which the system then doesn't read), the program on that line does.
    @Test func textScriptsWithoutAReadableShebangLine() async throws {
        let folder = ScriptFolder()
        let plain = folder.add("plain.sh", "# @allinoneime.schemaVersion 1\n# @allinoneime.input none\necho plain\n")
        let bom = folder.add("bom.sh", "\u{FEFF}#!/bin/bash\n# @allinoneime.schemaVersion 1\n# @allinoneime.input none\n[[ 1 == 1 ]] && echo bash\n")
        let commands = folder.load().commands
        let (p, b) = (try #require(commands.first { $0.name == "plain" }), try #require(commands.first { $0.name == "bom" }))
        #expect(p.launch == ["/bin/sh", plain.path] && b.launch == ["/bin/bash", bom.path])
        var outputs: [String] = []
        for command in [p, b] {
            for try await update in CommandRunner.run(command, arguments: [], environment: ["PATH": "/usr/bin:/bin"]) where update.isFinal {
                outputs.append(update.text)
            }
        }
        #expect(outputs == ["plain", "bash"])
        // Neither executable nor with a "#!" line: nothing to run it with.
        #expect(ScriptCommand.launch(for: plain, firstLine: "echo", executable: false) == nil)
        #expect(ScriptCommand.launch(for: plain, firstLine: "", executable: true, binary: true) == [plain.path])
    }

    /// Quick programs are never left among the running ones, whichever ends first: the program or its start.
    @Test func quickProgramsArentLeftRunning() async throws {
        let folder = ScriptFolder()
        folder.add("quick.sh", script(["input none"], "echo $$"))
        let command = try #require(folder.load().commands.first)
        let groups = try await withThrowingTaskGroup(of: String.self) { tasks in
            for _ in 0..<30 {
                tasks.addTask {
                    var text = ""
                    for try await update in CommandRunner.run(command, arguments: [], environment: ["PATH": "/usr/bin:/bin"]) where update.isFinal {
                        text = update.text
                    }
                    return text
                }
            }
            return try await tasks.reduce(into: [pid_t]()) { $0.append(pid_t($1) ?? 0) }
        }
        #expect(groups.count == 30 && !groups.contains(0))
        #expect(CommandRunner.runningGroups.isDisjoint(with: groups))
    }

    /// What `open` refuses: anything opening would run.
    @Test func openDoesntRunAnything() throws {
        let folder = ScriptFolder()
        func url(_ path: String) -> URL? { ScriptItem(title: "x", arg: path, action: .open).openURL }
        let script = folder.add("tool.sh", "echo\n", executable: false)
        let python = folder.add("tool.py", "print()\n", executable: false)
        let runme = folder.add("runme", "echo\n")  // executable, no extension
        let notes = folder.add("notes.txt", "x", executable: false)
        let app = folder.url.appendingPathComponent("Tool.app"), workflow = folder.url.appendingPathComponent("Do.workflow")
        for bundle in [app, workflow] { try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true) }
        #expect(url(script.path) == nil && url(python.path) == nil && url(runme.path) == nil && url("/usr/bin/say") == nil)
        #expect(url(workflow.path) == nil)
        #expect(url(notes.path) == notes && url(app.path)?.path == app.path && url(folder.url.path)?.path == folder.url.path)
    }
}
