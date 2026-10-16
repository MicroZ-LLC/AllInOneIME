import Foundation
import Testing
@testable import AllInOneIMECore

// Extension sources (`ExtensionSources`, `ExtensionSourceManager`): the pure parts, then the real git against local bare
// repositories in temporary folders (file:// addresses, never the network).

/// A bare repository and a working copy that pushes to it, in a temporary folder removed after the test.
final class GitFixture: @unchecked Sendable {
    let root: URL
    let bare: URL
    let work: URL
    /// Where the sources' clones go.
    let sources: URL

    init() throws {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("sources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: realpath(made.path, nil).map { defer { free($0) }; return String(cString: $0) } ?? made.path,
                   isDirectory: true)
        bare = root.appendingPathComponent("remote.git", isDirectory: true)
        work = root.appendingPathComponent("work", isDirectory: true)
        sources = root.appendingPathComponent("Sources", isDirectory: true)
        try Self.git(["init", "-q", "--bare", "-b", "main", bare.path], in: root)
        try Self.git(["init", "-q", "-b", "main", work.path], in: root)
        try Self.git(["remote", "add", "origin", bare.path], in: work)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var url: String { "file://" + bare.path }

    /// git for the fixture itself (the test's commits): no user config, no signing.
    @discardableResult
    static func git(_ arguments: [String], in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
                             "-c", "tag.gpgsign=false"] + arguments
        process.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExtensionSourceError.git("fixture: git \(arguments.joined(separator: " "))") }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func write(_ path: String, _ text: String, executable: Bool = false) throws {
        let file = work.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
    }

    /// Commits everything and pushes it (`force`: a rewritten history); returns the commit.
    @discardableResult
    func commit(_ message: String, amend: Bool = false, force: Bool = false) throws -> String {
        try Self.git(["add", "-A"], in: work)
        try Self.git(["commit", "-q", "-m", message] + (amend ? ["--amend"] : []), in: work)
        try Self.git(["push", "-q"] + (force ? ["-f"] : []) + ["origin", "main"], in: work)
        return try Self.git(["rev-parse", "HEAD"], in: work)
    }

    /// A bundle at `path` ("" for the root) with one command, `name`, printing `text`.
    func bundle(_ path: String = "", name: String = "hello", bundle: String = "greetings", text: String = "hi") throws {
        let prefix = path.isEmpty ? "" : path + "/"
        try write(prefix + "extension.json", """
            { "schemaVersion": 1, "name": "\(bundle)", "title": "Greetings", "version": "1.0.0", "author": "Test",
              "description": "Says hello.",
              "preferences": [{ "name": "greeting", "type": "textfield", "title": "Greeting", "default": "hi" }],
              "commands": [{ "script": "\(name).sh", "name": "\(name)", "title": "Say Hello", "description": "Prints a greeting.",
                             "output": "show", "input": "none" }] }
            """)
        try write(prefix + "\(name).sh", "#!/bin/sh\necho \(text)\n", executable: true)
    }

    /// The real git, as the input method runs it (no prompts, batch ssh), recording each call.
    func manager(recorder: GitRecorder? = nil) -> ExtensionSourceManager {
        let real = ProcessGitRunner(environment: ExtensionSources.gitEnvironment(base: ProcessInfo.processInfo.environment))
        return ExtensionSourceManager(root: sources, git: recorder.map { $0.wrapping(real) } ?? real,
                                      trashItem: { try FileManager.default.removeItem(at: $0) })
    }
}

/// Records the arguments of each git call, then runs it with `runner`.
final class GitRecorder: GitRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var runner: (any GitRunning)?
    private(set) var calls: [[String]] = []

    func wrapping(_ runner: any GitRunning) -> GitRecorder {
        self.runner = runner
        return self
    }

    func run(_ arguments: [String], in directory: URL?) async throws -> GitResult {
        lock.withLock { calls.append(arguments) }
        return try await runner?.run(arguments, in: directory) ?? GitResult(status: 0)
    }
}

@Suite struct ExtensionSourceAddressTests {
    @Test func acceptsGitAddresses() throws {
        for url in ["ssh://git.example.com/team/MyExtensions", "git@github.com:you/my-extensions.git", "https://example.com/you/x.git",
                    "https://example.com/you/x", "file:///tmp/remote.git", "ssh://git@example.com:2222/x/y.git"] {
            #expect(try ExtensionSources.validate("  \(url)\n") == url)
        }
    }

    @Test func refusesOthers() {
        #expect(throws: ExtensionSourceError.notHTTPS) { try ExtensionSources.validate("http://example.com/x.git") }
        for url in ["", "ftp://example.com/x", "--upload-pack=touch /tmp/x", "example.com/x", "/tmp/repo", "git@host:", "@host:x",
                    "https://example.com", "https://exa mple.com/x", "ssh://", "git@host://x"] {
            #expect(throws: ExtensionSourceError.self) { try ExtensionSources.validate(url) }
        }
    }

    @Test func folderNames() {
        let a = ExtensionSources.folderName(for: "git@github.com:you/my-extensions.git")
        #expect(a.hasPrefix("my-extensions-") && a.count == "my-extensions-".count + 8)
        // Same name elsewhere: another folder; the same address: the same folder.
        #expect(ExtensionSources.folderName(for: "ssh://other.example.com/me/my-extensions") != a)
        #expect(ExtensionSources.folderName(for: " git@github.com:you/my-extensions.git ") == a)
        #expect(ExtensionSources.folderName(for: "ssh://git.example.com/team/MyExtensions").hasPrefix("MyExtensions-"))
        #expect(ExtensionSources.folderName(for: "https://example.com/a/../..git").hasPrefix("source-"))
        #expect(!ExtensionSources.folderName(for: "https://example.com/x/.hidden.git").hasPrefix("."))
        #expect(ExtensionSources.repositoryName("https://example.com/you/tools.git/") == "tools")
    }

    @Test func bundleFolderAndLoadPath() {
        let root = URL(fileURLWithPath: "/Users/me/Library/Application Support/AllInOneIME/Sources")
        let source = ExtensionSource(url: "git@github.com:you/my-extensions.git", path: "extensions/team")
        let folder = ExtensionSources.bundleFolder(for: source, root: root)
        #expect(folder.path == root.path + "/" + ExtensionSources.folderName(for: source.url) + "/extensions/team")
        #expect(ExtensionSources.bundleFolder(for: ExtensionSource(url: source.url), root: root).lastPathComponent
                == ExtensionSources.folderName(for: source.url))
    }
}

@Suite struct ExtensionSourceGitCommandTests {
    @Test func environment() {
        let base = ["PATH": "/usr/bin", "HOME": "/Users/me", "GIT_DIR": "/elsewhere", "SSH_AUTH_SOCK": "/launchd/agent"]
        var env = ExtensionSources.gitEnvironment(base: base)
        #expect(env["GIT_TERMINAL_PROMPT"] == "0" && env["GIT_SSH_COMMAND"] == "ssh -o BatchMode=yes")
        #expect(env["GIT_DIR"] == nil && env["HOME"] == "/Users/me" && env["SSH_AUTH_SOCK"] == "/launchd/agent" && env["PATH"] == "/usr/bin")
        // The login shell's agent wins; the user's own ssh command keeps its options, batch mode added.
        env = ExtensionSources.gitEnvironment(base: base, login: ["SSH_AUTH_SOCK": "/shell/agent"], sshCommand: "ssh -i ~/.ssh/work")
        #expect(env["SSH_AUTH_SOCK"] == "/shell/agent" && env["GIT_SSH_COMMAND"] == "ssh -i ~/.ssh/work -o BatchMode=yes")
        env = ExtensionSources.gitEnvironment(base: base.merging(["GIT_SSH_COMMAND": "ssh -v"]) { $1 }, sshCommand: "ignored")
        #expect(env["GIT_SSH_COMMAND"] == "ssh -v -o BatchMode=yes")
        env = ExtensionSources.gitEnvironment(base: base, login: ["GIT_SSH_COMMAND": "ssh -F ~/.ssh/other"])
        #expect(env["GIT_SSH_COMMAND"] == "ssh -F ~/.ssh/other -o BatchMode=yes")
        // GIT_SSH (a program) is left alone.
        env = ExtensionSources.gitEnvironment(base: base.merging(["GIT_SSH": "/usr/local/bin/myssh"]) { $1 })
        #expect(env["GIT_SSH_COMMAND"] == nil && env["GIT_SSH"] == "/usr/local/bin/myssh")
        #expect(ExtensionSources.gitEnvironment(base: [:])["HOME"] == NSHomeDirectory())
    }

    @Test func arguments() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        #expect(ExtensionSources.cloneArguments(url: "git@h:a/b.git", branch: nil, into: folder)
                == ["-c", "core.hooksPath=/dev/null", "clone", "--depth", "1", "--single-branch", "--no-tags", "--", "git@h:a/b.git", "/tmp/x"])
        #expect(ExtensionSources.cloneArguments(url: "git@h:a/b.git", branch: "dev", into: folder).contains("--branch"))
        #expect(ExtensionSources.fetchArguments("main", depth: 100)
                == ["-c", "core.hooksPath=/dev/null", "fetch", "--depth", "100", "--no-tags", "origin", "main"])
        #expect(ExtensionSources.logArguments("a..b").last == "a..b")
    }

    @Test func log() {
        let output = "0123456789abcdef0123456789abcdef01234567\u{1F}Ann Lee\u{1F}2026-10-15T19:30:00-07:00\u{1F}Add @weather\n"
            + "fedcba9876543210fedcba9876543210fedcba98\u{1F}Bo\u{1F}not a date\u{1F}Fix: a\u{1F}b\n"
            + "garbage line\n"
        let commits = ExtensionSources.parseLog(output)
        #expect(commits.count == 2)
        #expect(commits[0].subject == "Add @weather" && commits[0].author == "Ann Lee" && commits[0].shortSHA == "0123456")
        #expect(commits[0].date == ISO8601DateFormatter().date(from: "2026-10-16T02:30:00Z"))
        #expect(commits[1].date == nil && commits[1].subject == "Fix: a\u{1F}b")
    }

    @Test func messages() {
        let result = GitResult(status: 128, errors: "Cloning into 'x'...\ngit@host: Permission denied (publickey).\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\nhint: something\n")
        #expect(ExtensionSources.gitMessage(result)
                == "fatal: Could not read from remote repository.\nPlease make sure you have the correct access rights\nand the repository exists.")
        #expect(ExtensionSources.gitMessage(GitResult(status: 1)) == "git failed (exit status 1)")
    }

    @Test func schedule() {
        let source = ExtensionSource(url: "file:///r.git")
        let trusted = ExtensionSourceStatus(url: source.url, trusted: true)
        #expect(ExtensionSources.shouldCheck(source, status: trusted, automatic: true))
        #expect(!ExtensionSources.shouldCheck(source, status: nil, automatic: false))
        #expect(!ExtensionSources.shouldCheck(source, status: ExtensionSourceStatus(url: source.url), automatic: false))
        var pinned = source
        pinned.pin = "v1"
        #expect(!ExtensionSources.shouldCheck(pinned, status: trusted, automatic: false))
        var manual = source
        manual.autoCheck = false
        #expect(!ExtensionSources.shouldCheck(manual, status: trusted, automatic: true))
        #expect(ExtensionSources.shouldCheck(manual, status: trusted, automatic: false))
        // Trust goes with the address it was given for.
        var moved = trusted
        moved.url = "file:///other.git"
        #expect(!ExtensionSources.shouldCheck(source, status: moved, automatic: false) && !ExtensionSources.isTrusted(source, moved))
    }

    @Test func gitMissing() async {
        let runner = ProcessGitRunner(environment: [:], developerFolders: ["/nonexistent-\(UUID().uuidString)"])
        await #expect(throws: ExtensionSourceError.gitNotInstalled) { try await runner.run(["--version"], in: nil) }
    }

    @Test func timeout() async {
        let runner = ProcessGitRunner(executable: URL(fileURLWithPath: "/bin/sleep"), environment: [:], timeout: 0.3)
        let start = Date()
        await #expect(throws: ExtensionSourceError.timedOut(0.3)) { try await runner.run(["5"], in: nil) }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func stdinClosed() async throws {
        let runner = ProcessGitRunner(executable: URL(fileURLWithPath: "/bin/cat"), environment: [:], timeout: 5)
        let result = try await runner.run([], in: nil)
        #expect(result.status == 0 && result.output.isEmpty)
    }
}

@Suite struct ExtensionSourceConfigTests {
    @Test func decodesOldAndNew() throws {
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"customCommands": []}"#.utf8))
        #expect(old.extensionSources.isEmpty)
        let json = #"""
        {"extensionSources": [
            {"url": "ssh://git.example.com/team/MyExtensions", "path": "extensions/team", "branch": "main", "pin": null,
             "autoCheck": false, "authHint": "Sign in first", "later": 1},
            {"url": "git@github.com:you/my-extensions.git"},
            {"path": "no address"},
            {"url": "git@github.com:you/my-extensions.git", "pin": "v2"}
        ]}
        """#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.extensionSources == [
            ExtensionSource(url: "ssh://git.example.com/team/MyExtensions", path: "extensions/team", branch: "main", autoCheck: false,
                            authHint: "Sign in first"),
            ExtensionSource(url: "git@github.com:you/my-extensions.git"),
        ])
        // Written back as read; a config without sources gains no key.
        let encoder = JSONEncoder()
        let again = try JSONDecoder().decode(Config.self, from: try encoder.encode(config))
        #expect(again.extensionSources == config.extensionSources)
        let plain = String(decoding: try encoder.encode(Config.default), as: UTF8.self)
        #expect(!plain.contains("extensionSources"))
        let one = String(decoding: try encoder.encode(ExtensionSource(url: "file:///r.git")), as: UTF8.self)
        #expect(one.contains("\"pin\":null") && one.contains("\"autoCheck\":true"))
    }

    @Test func enableAndRemove() {
        let root = URL(fileURLWithPath: "/tmp/Sources")
        var config = Config.default
        config.extensionPreferences = ["greetings": ["greeting": "yo"]]
        let source = ExtensionSource(url: "file:///r.git", path: "ext")
        ExtensionSources.enable(source, in: &config, root: root)
        ExtensionSources.enable(source, in: &config, root: root)
        let path = ExtensionSources.loadPath(for: source, root: root)
        #expect(config.extensionSources == [source] && config.extensionFolders.filter { $0 == path }.count == 1)
        #expect(ExtensionSources.isEnabled(source, in: config, root: root))
        ExtensionSources.remove(source, from: &config, root: root)
        #expect(config.extensionSources.isEmpty && !config.extensionFolders.contains(path) && !ExtensionSources.isEnabled(source, in: config, root: root))
        #expect(config.extensionPreferences["greetings"]?["greeting"] == "yo")
        #expect(config.extensionFolders == [ExtensionStore.defaultFolder])
    }

    @Test func statusFile() throws {
        let fixture = try GitFixture()
        let file = fixture.root.appendingPathComponent("sources.json")
        #expect(ExtensionSourceStatus.load(from: file).isEmpty)
        let status = ExtensionSourceStatus(url: "file:///r.git", trusted: true, branch: "main", commit: "abc", commitDate: Date(timeIntervalSince1970: 1_800_000_000),
                                           checked: Date(timeIntervalSince1970: 1_800_000_100), error: "nope",
                                           updates: [ExtensionSourceCommit(sha: "def", author: "A", date: nil, subject: "s")], remote: "def",
                                           fastForward: false)
        try ExtensionSourceStatus.save([status.url: status], to: file)
        #expect(ExtensionSourceStatus.load(from: file) == [status.url: status])
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("2027-01-15T08:00:00Z"))
    }
}

@Suite struct ExtensionSourceBundleTests {
    @Test func findsBundles() throws {
        let folder = ScriptFolder()
        folder.add("README.md", "x")
        #expect(ExtensionSources.bundleFolders(in: folder.url).isEmpty)
        #expect(throws: ExtensionSourceError.noBundle(nil)) { try ExtensionSources.resolveBundlePath(nil, in: folder.url) }
        folder.add("extensions/team/extension.json", "{}")
        folder.add(".git/x/extension.json", "{}")
        folder.add("node_modules/y/extension.json", "{}")
        folder.add("a/b/c/d/e/extension.json", "{}")  // too deep
        #expect(ExtensionSources.bundleFolders(in: folder.url) == ["extensions/team"])
        #expect(try ExtensionSources.resolveBundlePath(nil, in: folder.url) == "extensions/team")
        folder.add("extension.json", "{}")
        folder.add("more/extension.json", "{}")
        #expect(ExtensionSources.bundleFolders(in: folder.url) == ["", "extensions/team", "more"])
        #expect(throws: ExtensionSourceError.severalBundles(["", "extensions/team", "more"])) {
            try ExtensionSources.resolveBundlePath("", in: folder.url)
        }
        #expect(try ExtensionSources.resolveBundlePath("/more/", in: folder.url) == "more")
        #expect(throws: ExtensionSourceError.noBundle("../x")) { try ExtensionSources.resolveBundlePath("../x", in: folder.url) }
        #expect(throws: ExtensionSourceError.noBundle("a")) { try ExtensionSources.resolveBundlePath("a", in: folder.url) }
    }

    /// A folder added to the load list that is a bundle itself loads as that bundle (a source's folder).
    @Test func folderThatIsABundle() {
        let folder = ScriptFolder()
        folder.add("extension.json", #"{"schemaVersion": 1, "name": "tools", "commands": [{"script": "a.sh", "name": "alpha"}]}"#)
        folder.add("a.sh", script(["title A"]))
        folder.add("b.sh", script(["title B"]))
        let index = folder.load()
        #expect(index.bundles.map(\.name) == ["tools"])
        #expect(index.commands.map(\.name) == ["alpha"])
    }
}

@Suite(.serialized) struct ExtensionSourceGitTests {
    @Test func addReviewEnableUpdate() async throws {
        let fixture = try GitFixture()
        try fixture.bundle("ext")
        try fixture.write("README.md", "my extensions")
        let first = try fixture.commit("First")
        let recorder = GitRecorder()
        let manager = fixture.manager(recorder: recorder)
        var source = ExtensionSource(url: fixture.url)

        // Add: cloned into place (nothing left in a temporary folder), the one bundle found.
        let clone = try await manager.clone(source)
        #expect(clone.folder == ExtensionSources.cloneFolder(for: fixture.url, root: fixture.sources))
        #expect(clone.status.commit == first && clone.status.branch == "main" && !clone.status.trusted && clone.status.commitDate != nil)
        #expect(clone.bundles == ["ext"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.sources.path).filter { $0.hasPrefix(".") }.isEmpty)
        source.path = try ExtensionSources.resolveBundlePath(source.path, in: clone.folder)
        #expect(source.path == "ext")
        // Shallow.
        #expect(FileManager.default.fileExists(atPath: clone.folder.appendingPathComponent(".git/shallow").path))

        // Review: what it is and runs, before anything loads.
        var config = Config.default
        config.extensionFolders = []
        config.customCommands = [CustomCommand(name: "hello", type: .prompt, prompt: "x")]
        let review = ExtensionSourceReview.make(bundleFolder: ExtensionSources.bundleFolder(for: source, root: fixture.sources), path: "ext",
                                                url: fixture.url, commit: clone.status.commit, commitDate: clone.status.commitDate,
                                                config: config)
        #expect(review.bundle?.name == "greetings" && review.bundle?.title == "Greetings" && review.problem == nil)
        #expect(review.commands.map(\.name) == ["hello"] && review.commands[0].title == "Say Hello" && review.commands[0].output == .show)
        #expect(review.commands[0].description == "Prints a greeting." && review.programs == ["hello.sh"])
        #expect(review.commands[0].hidden == .nameTaken("hello", by: .custom))
        #expect(review.preferences.map(\.name) == ["greeting"])
        #expect(review.summary.contains("WARNING:     This source isn't signed: it will run programs from \(fixture.url)."))
        #expect(review.summary.contains("commit:      \(first.prefix(7)) " + ISO8601DateFormatter().string(from: clone.status.commitDate!)))

        // Enable: the bundle's folder in the load list, and it loads.
        config.customCommands = []
        ExtensionSources.enable(source, in: &config, root: fixture.sources)
        var index = ExtensionStore.load(ExtensionStore.folders(config, found: []))
        #expect(index.commands.map(\.name) == ["hello"])

        // Up to date.
        var status = clone.status
        status.trusted = true
        status = try await manager.check(source, status)
        #expect(status.updates.isEmpty && status.remote == nil && status.checked != nil)

        // A new commit upstream: listed, not applied.
        try fixture.bundle("ext", text: "hello there")
        let second = try fixture.commit("Say more")
        status = try await manager.check(source, status)
        #expect(status.updates.map(\.subject) == ["Say more"] && status.updates[0].author == "Test" && status.fastForward)
        #expect(status.remote == second && status.commit == first)
        let script = clone.folder.appendingPathComponent("ext/hello.sh")
        #expect(try String(contentsOf: script, encoding: .utf8).contains("echo hi"))

        // Update: fast-forwarded; the loader sees the new file.
        status = try await manager.update(source, status)
        #expect(status.commit == second && status.updates.isEmpty)
        #expect(try String(contentsOf: script, encoding: .utf8).contains("hello there"))
        index = ExtensionStore.load(ExtensionStore.folders(config, found: []))
        #expect(index.commands.map(\.name) == ["hello"])

        // No hooks, ever; never a merge or a pull.
        #expect(!recorder.calls.isEmpty && recorder.calls.allSatisfy { Array($0.prefix(2)) == ["-c", "core.hooksPath=/dev/null"] })
        #expect(!recorder.calls.contains { $0.contains("merge") && !$0.contains("merge-base") || $0.contains("pull") })

        // A force push: can't fast-forward; Re-clone gets the new history.
        try fixture.bundle("ext", text: "rewritten")
        let rewritten = try fixture.commit("Rewritten", amend: true, force: true)
        status = try await manager.check(source, status)
        #expect(!status.fastForward && status.updates.first?.subject == "Rewritten")
        await #expect(throws: ExtensionSourceError.notFastForward) { try await manager.update(source, status) }
        status = try await manager.reclone(source, status)
        #expect(status.commit == rewritten && status.trusted)
        #expect(try String(contentsOf: script, encoding: .utf8).contains("rewritten"))

        // Remove: the clone goes, the config forgets the source and its folder.
        try manager.trash(source)
        ExtensionSources.remove(source, from: &config, root: fixture.sources)
        #expect(!FileManager.default.fileExists(atPath: clone.folder.path) && config.extensionFolders.isEmpty, "\(config.extensionFolders)")
    }

    @Test func pins() async throws {
        let fixture = try GitFixture()
        try fixture.bundle()
        let first = try fixture.commit("One")
        try GitFixture.git(["tag", "-a", "v1", "-m", "v1"], in: fixture.work)
        try GitFixture.git(["push", "-q", "origin", "v1"], in: fixture.work)
        try fixture.bundle(text: "two")
        let second = try fixture.commit("Two")
        try fixture.bundle(text: "three")
        let third = try fixture.commit("Three")
        let manager = fixture.manager()

        // Added pinned to a tag: the clone is at it.
        var source = ExtensionSource(url: fixture.url, pin: "v1")
        let clone = try await manager.clone(source)
        #expect(clone.status.commit == first && clone.bundles == [""])
        #expect(!ExtensionSources.shouldCheck(source, status: ExtensionSourceStatus(url: source.url, trusted: true), automatic: false))

        // The pin changed to a commit (not a branch tip): checked out.
        var status = clone.status
        status.trusted = true
        status = try await manager.pin(source, to: second, status)
        #expect(status.commit == second)
        source.pin = second

        // Unpinned: it follows the branch again, through Update.
        source.pin = nil
        status = try await manager.check(source, status)
        #expect(status.updates.map(\.subject) == ["Three"] && status.fastForward)
        status = try await manager.update(source, status)
        #expect(status.commit == third)
    }

    @Test func branchAndErrors() async throws {
        let fixture = try GitFixture()
        try fixture.bundle()
        try fixture.commit("Main")
        try GitFixture.git(["checkout", "-q", "-b", "dev"], in: fixture.work)
        try fixture.bundle(text: "dev")
        try fixture.write("other/extension.json", "{}")
        try GitFixture.git(["add", "-A"], in: fixture.work)
        try GitFixture.git(["commit", "-q", "-m", "Dev"], in: fixture.work)
        try GitFixture.git(["push", "-q", "origin", "dev"], in: fixture.work)
        let manager = fixture.manager()

        let clone = try await manager.clone(ExtensionSource(url: fixture.url, branch: "dev"))
        #expect(clone.status.branch == "dev" && clone.bundles == ["", "other"])

        // A repository that isn't there: git's own words, and nothing left behind.
        let missing = ExtensionSource(url: "file://" + fixture.root.appendingPathComponent("missing.git").path)
        do {
            _ = try await manager.clone(missing)
            Issue.record("cloned a repository that isn't there")
        } catch let ExtensionSourceError.git(message) {
            #expect(message.contains("does not appear to be a git repository") || message.contains("not found") || message.contains("fatal"))
        }
        #expect(!FileManager.default.fileExists(atPath: ExtensionSources.cloneFolder(for: missing.url, root: fixture.sources).path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.sources.path).filter { $0.hasPrefix(".tmp") }.isEmpty)
        await #expect(throws: ExtensionSourceError.notHTTPS) { try await manager.clone(ExtensionSource(url: "http://example.com/x.git")) }
    }
}
