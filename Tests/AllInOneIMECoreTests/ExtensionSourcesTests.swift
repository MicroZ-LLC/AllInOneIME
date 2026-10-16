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
        #expect(env["GIT_TERMINAL_PROMPT"] == "0" && env["SSH_ASKPASS_REQUIRE"] == "never" && env["GIT_ALLOW_PROTOCOL"] == "ssh:https:file")
        #expect(env["GIT_DIR"] == nil && env["HOME"] == "/Users/me" && env["SSH_AUTH_SOCK"] == "/launchd/agent" && env["PATH"] == "/usr/bin")
        // No ssh command of ours: the user's own stays exactly as it is, or there is none.
        #expect(env["GIT_SSH_COMMAND"] == nil)
        env = ExtensionSources.gitEnvironment(base: base, login: ["SSH_AUTH_SOCK": "/shell/agent"], sshCommand: "ssh -i ~/.ssh/work")
        #expect(env["SSH_AUTH_SOCK"] == "/shell/agent" && env["GIT_SSH_COMMAND"] == nil)
        env = ExtensionSources.gitEnvironment(base: base.merging(["GIT_SSH_COMMAND": "ssh -v"]) { $1 })
        #expect(env["GIT_SSH_COMMAND"] == "ssh -v")
        env = ExtensionSources.gitEnvironment(base: base, login: ["GIT_SSH_COMMAND": "ssh -F ~/.ssh/other"])
        #expect(env["GIT_SSH_COMMAND"] == "ssh -F ~/.ssh/other")
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
                == ["-c", "core.hooksPath=/dev/null", "fetch", "--depth", "100", "--no-tags", "--end-of-options", "origin", "main"])
        #expect(Array(ExtensionSources.logArguments("a..b").suffix(2)) == ["--end-of-options", "a..b"])
    }

    @Test func refs() {
        for ref in ["main", "release/1.2", "v1.2.0", "0123456789abcdef", "feature_x-y", "HEAD"] {
            #expect(ExtensionSources.isPlausibleRef(ref), "\(ref)")
        }
        for ref in ["", "-x", "--upload-pack=touch${IFS}PWNED;false", "a..b", "a b", "a\tb", "a~1", "a^", "a:b", "a?", "a*", "a[b",
                    "a\\b", "@{-1}", "/main", "main/", ".hidden", "a.lock", "a//b", "@", "x\u{7F}"] {
            #expect(!ExtensionSources.isPlausibleRef(ref), "\(ref)")
        }
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
        #expect(ExtensionSources.gitMessage(result) == "git@host: Permission denied (publickey).\nfatal: Could not read from remote repository.")
        // Many lines: the causes stay, the rest is cut to the cap.
        let long = GitResult(status: 128, errors: (1...20).map { "warning: noise \($0)" }.joined(separator: "\n") + "\nfatal: the cause\n")
        let lines = ExtensionSources.gitMessage(long).split(separator: "\n")
        #expect(lines.count == ExtensionSources.maxMessageLines && lines.last == "fatal: the cause")
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
        #expect(Date().timeIntervalSince(start) < 10)
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
        // Enabling an entry the config has keeps its hint and schedule.
        config.extensionSources = [ExtensionSource(url: source.url, autoCheck: false, authHint: "Sign in first.")]
        ExtensionSources.enable(ExtensionSource(url: source.url, path: "ext"), in: &config, root: root)
        #expect(config.extensionSources == [ExtensionSource(url: source.url, path: "ext", autoCheck: false, authHint: "Sign in first.")])
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

// MARK: - Safety (the sign-off review's findings)

@Suite(.serialized) struct ExtensionSourceSafetyTests {
    /// A repository whose default branch is named like an option: the PoC (`--upload-pack=…` ran a command on fetch). Its
    /// name is refused when the clone reads it, before any fetch; nothing runs.
    @Test func optionNamedDefaultBranchRunsNothing() async throws {
        let fixture = try GitFixture()
        try fixture.bundle()
        try fixture.commit("First")
        let marker = fixture.root.appendingPathComponent("PWNED")
        let evil = "--upload-pack=touch${IFS}\(marker.path);false"
        try GitFixture.git(["update-ref", "refs/heads/" + evil, "HEAD"], in: fixture.bare)
        try GitFixture.git(["symbolic-ref", "HEAD", "refs/heads/" + evil], in: fixture.bare)
        // The PoC is real: a fetch that takes the name as an option runs the command.
        let probe = fixture.root.appendingPathComponent("probe")
        try GitFixture.git(["clone", "-q", "--", fixture.url, probe.path], in: fixture.root)
        _ = try? GitFixture.git(["fetch", "origin", evil], in: probe)
        #expect(FileManager.default.fileExists(atPath: marker.path), "the PoC itself works (else this test proves nothing)")
        try FileManager.default.removeItem(at: marker)

        let recorder = GitRecorder()
        let manager = fixture.manager(recorder: recorder)
        do {
            _ = try await manager.stage(ExtensionSource(url: fixture.url))
            Issue.record("a repository with an option-named default branch was accepted")
        } catch {
            #expect(error as? ExtensionSourceError == .invalidRef(evil), "\(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path), "nothing ran")
        #expect(!recorder.calls.contains { $0.contains("fetch") }, "no fetch with it")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: fixture.sources.path))?.filter { !$0.hasPrefix(".") }.isEmpty ?? true)

        // Given as the branch or the pin, or found in sources.json: refused before git sees it.
        for source in [ExtensionSource(url: fixture.url, branch: evil), ExtensionSource(url: fixture.url, pin: evil)] {
            await #expect(throws: ExtensionSourceError.invalidRef(evil)) { _ = try await manager.stage(source) }
        }
        let status = ExtensionSourceStatus(url: fixture.url, trusted: true, branch: evil)
        await #expect(throws: ExtensionSourceError.invalidRef(evil)) { _ = try await manager.check(ExtensionSource(url: fixture.url), status) }
        await #expect(throws: ExtensionSourceError.invalidRef(evil)) {
            _ = try await manager.pin(ExtensionSource(url: fixture.url), to: evil, status)
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path), "nothing ran")
        // git's own rule too: a name that passes the quick check but not git's.
        await #expect(throws: ExtensionSourceError.invalidRef("a.lock/b")) { try await manager.checkRef("a.lock/b") }
    }

    /// The review's clone waits in staging: nothing is in place until Enable, and Cancel never touches what's in place.
    @Test func stagingNeverTouchesWhatIsInPlace() async throws {
        let fixture = try GitFixture()
        try fixture.bundle(text: "first")
        let first = try fixture.commit("First")
        let manager = fixture.manager()
        let source = ExtensionSource(url: fixture.url)
        let place = ExtensionSources.cloneFolder(for: fixture.url, root: fixture.sources)

        let staged = try await manager.stage(source)
        #expect(staged.folder.path.hasPrefix(manager.stagingFolder.path) && !FileManager.default.fileExists(atPath: place.path))
        manager.discard(staged)
        #expect(!FileManager.default.fileExists(atPath: staged.folder.path) && !FileManager.default.fileExists(atPath: manager.stagingFolder.path))

        // In place (enabled), then a new version staged and cancelled: the one in place is as it was.
        _ = try await manager.clone(source)
        try fixture.bundle(text: "second")
        let second = try fixture.commit("Second")
        let again = try await manager.stage(source)
        #expect(again.status.commit == second)
        manager.discard(again)
        #expect(try GitFixture.git(["rev-parse", "HEAD"], in: place) == first)
        #expect(try String(contentsOf: place.appendingPathComponent("hello.sh"), encoding: .utf8).contains("first"))
        // Discarding something that isn't in staging does nothing.
        manager.discard(ExtensionSourceManager.Clone(folder: place, status: ExtensionSourceStatus(url: fixture.url), bundles: []))
        #expect(FileManager.default.fileExists(atPath: place.path))

        // Enable after a review: swapped in, in one step.
        let reviewed = try await manager.stage(source)
        _ = try manager.install(reviewed)
        #expect(try GitFixture.git(["rev-parse", "HEAD"], in: place) == second)
        #expect(!FileManager.default.fileExists(atPath: manager.stagingFolder.path))
    }

    @Test func unreviewedFoldersAreTakenOut() {
        let root = URL(fileURLWithPath: "/Users/me/Library/Application Support/AllInOneIME/Sources")
        let trusted = ExtensionSource(url: "git@github.com:you/a.git")
        let copied = ExtensionSource(url: "git@github.com:you/b.git", path: "ext")
        var config = Config.default
        config.extensionFolders = ["~/my-scripts"]
        ExtensionSources.enable(trusted, in: &config, root: root)
        ExtensionSources.enable(copied, in: &config, root: root)
        config.extensionFolders.append(root.appendingPathComponent("stray/x").path)
        let statuses = [trusted.url: ExtensionSourceStatus(url: trusted.url, trusted: true),
                        copied.url: ExtensionSourceStatus(url: copied.url, trusted: false)]
        let untrusted = ExtensionSources.untrustedFolders(in: config, statuses: statuses, root: root)
        #expect(untrusted == [ExtensionSources.loadPath(for: copied, root: root), root.appendingPathComponent("stray/x").path])
        var quarantined = config
        #expect(ExtensionSources.quarantine(&quarantined, statuses: statuses, root: root) == untrusted)
        #expect(quarantined.extensionFolders == ["~/my-scripts", ExtensionSources.loadPath(for: trusted, root: root)])
        // A lost sources.json: nothing of the sources folder stays.
        var lost = config
        ExtensionSources.quarantine(&lost, statuses: [:], root: root)
        #expect(lost.extensionFolders == ["~/my-scripts"])
    }

    @Test func statusFileRobust() throws {
        let fixture = try GitFixture()
        let file = fixture.root.appendingPathComponent("sources.json")
        // One entry a later version wrote differently: the others still read.
        try Data(#"{"a": {"url": "a", "trusted": true, "updates": [], "fastForward": true}, "b": {"url": 3}}"#.utf8).write(to: file)
        #expect(Array(ExtensionSourceStatus.load(from: file).keys) == ["a"])
        // Not JSON at all: moved aside, never overwritten.
        try Data("{ broken".utf8).write(to: file)
        #expect(ExtensionSourceStatus.load(from: file).isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        let aside = try #require(names.first { $0.hasPrefix("sources.json.bad-") })
        #expect(!names.contains("sources.json"))
        #expect(try String(contentsOf: fixture.root.appendingPathComponent(aside), encoding: .utf8) == "{ broken")
    }

    @Test func unpinGoesBackToTheBranch() async throws {
        let fixture = try GitFixture()
        try fixture.bundle()
        let first = try fixture.commit("One")
        try fixture.bundle(text: "two")
        let second = try fixture.commit("Two")
        let manager = fixture.manager()
        var source = ExtensionSource(url: fixture.url)
        var status = try await manager.clone(source).status
        status.trusted = true
        status = try await manager.pin(source, to: first, status)
        #expect(status.commit == first)
        // A pin that isn't there: an error, the clone where it was.
        await #expect(throws: ExtensionSourceError.self) { _ = try await manager.pin(source, to: "v9", status) }
        #expect(try GitFixture.git(["rev-parse", "HEAD"], in: ExtensionSources.cloneFolder(for: fixture.url, root: fixture.sources)) == first)
        source.pin = nil
        status = try await manager.update(source, status)
        #expect(status.commit == second)
    }

    /// An added folder whose extension.json isn't a bundle's is read as a folder, as before.
    @Test func foreignManifestFallsBack() {
        let folder = ScriptFolder()
        folder.add("extension.json", #"{"name": "Another tool's file", "version": 2}"#)
        folder.add("hello.sh", script(["title Hello"]))
        let index = folder.load()
        #expect(index.bundles.isEmpty && index.commands.map(\.name) == ["hello"])
    }

    @Test func symbolicLinksOutOfTheClone() throws {
        let clone = ScriptFolder(), outside = ScriptFolder()
        outside.add("extension.json", #"{"schemaVersion": 1, "name": "away", "commands": [{"script": "a.sh", "name": "away"}]}"#)
        outside.add("a.sh", script())
        try FileManager.default.createSymbolicLink(at: clone.url.appendingPathComponent("linked"), withDestinationURL: outside.url)
        #expect(throws: ExtensionSourceError.outsideClone("linked")) { try ExtensionSources.resolveBundlePath("linked", in: clone.url) }
        #expect(ExtensionSources.bundleFolders(in: clone.url).isEmpty)

        // A script of the bundle that is a link out of the repository: flagged in the review.
        let elsewhere = outside.add("payload.sh", script())
        clone.add("extension.json", #"{"schemaVersion": 1, "name": "tools", "commands": [{"script": "run.sh", "name": "runner"}]}"#)
        try FileManager.default.createSymbolicLink(at: clone.url.appendingPathComponent("run.sh"), withDestinationURL: elsewhere)
        var config = Config.default
        config.extensionFolders = []
        let review = ExtensionSourceReview.make(bundleFolder: clone.url, path: "", url: "file:///r.git", commit: nil, commitDate: nil,
                                                config: config, repository: clone.url)
        #expect(review.commands.first?.leavesRepository == elsewhere.resolvingSymlinksInPath().path)
        #expect(review.summary.contains { $0.contains("link out of the repository") })
    }

    /// git runs with no controlling terminal: ssh couldn't ask for a host key or a password even from Terminal (run under
    /// `script` to have one), and stdin is closed.
    @Test func noControllingTerminal() async throws {
        let runner = ProcessGitRunner(executable: URL(fileURLWithPath: "/bin/sh"), environment: ["PATH": "/usr/bin:/bin"], timeout: 10)
        let result = try await runner.run(["-c", "if (exec 3</dev/tty) 2>/dev/null; then echo tty; else echo no-tty; fi; ps -o tty= -p $$"], in: nil)
        let lines = result.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.first == "no-tty", "\(result.output)")
        #expect(lines.last == "??", "no terminal: \(result.output)")
        // The exit status comes through, and what it started is in its own group, stopped with it at the timeout.
        #expect(try await runner.run(["-c", "exit 3"], in: nil).status == 3)
        let quick = ProcessGitRunner(executable: URL(fileURLWithPath: "/bin/sh"), environment: ["PATH": "/usr/bin:/bin"], timeout: 0.5)
        let started = Date()
        await #expect(throws: ExtensionSourceError.timedOut(0.5)) { _ = try await quick.run(["-c", "sleep 30 & sleep 30; wait"], in: nil) }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    /// git starts with every signal at its default, whatever this process ignores (the input method ignores SIGTERM and
    /// SIGPIPE): else git, at exit, waits forever for an upload-pack its SIGTERM can't stop (a fetch of a missing ref did).
    @Test func signalsReset() async throws {
        let before = signal(SIGTERM, SIG_IGN)
        defer { signal(SIGTERM, before) }
        let runner = ProcessGitRunner(executable: URL(fileURLWithPath: "/bin/sh"), environment: ["PATH": "/usr/bin:/bin"], timeout: 10)
        let started = Date()
        let result = try await runner.run(["-c", "kill -TERM $$; sleep 5; echo survived"], in: nil)
        #expect(result.status == 128 + SIGTERM && !result.output.contains("survived"), "\(result)")
        #expect(Date().timeIntervalSince(started) < 4)
    }

    @Test func credentialsInAddresses() {
        #expect(throws: ExtensionSourceError.credentialsInURL) { try ExtensionSources.validate("https://me:secret@git.example.com/x.git") }
        #expect(throws: ExtensionSourceError.credentialsInURL) { try ExtensionSources.validate("https://TOKEN@git.example.com/x.git") }
        #expect((try? ExtensionSources.validate("ssh://git@git.example.com/x.git")) == "ssh://git@git.example.com/x.git")
    }

    @Test func leftoversRemoved() throws {
        let fixture = try GitFixture()
        let manager = fixture.manager()
        let old = Date().addingTimeInterval(-2 * 3600)
        for name in [".staging/x-1", ".tmp-x-2", ".old-x-3", "kept-1a2b3c4d", ".staging/in-use-4", ".tmp-in-use-5"] {
            let folder = fixture.sources.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !name.contains("in-use") { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.path) }
        }
        manager.removeLeftovers()
        // Only those an hour old: a younger one may be a review still open, or --add-source at work.
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: fixture.sources.path)) == [".staging", "kept-1a2b3c4d", ".tmp-in-use-5"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: manager.stagingFolder.path) == ["in-use-4"])
    }
}

// MARK: - Follow-ups of the sign-off review

@Suite(.serialized) struct ExtensionSourceFollowUpTests {
    /// A pin further back than a check fetches: Unpin can't fast-forward (Settings then re-clones the branch for a review).
    @Test func unpinFromFarBack() async throws {
        let fixture = try GitFixture()
        try fixture.bundle()
        let first = try fixture.commit("First")
        for index in 1...(ExtensionSources.fetchDepth + 5) {
            try GitFixture.git(["commit", "-q", "--allow-empty", "-m", "Step \(index)"], in: fixture.work)
        }
        try GitFixture.git(["push", "-q", "origin", "main"], in: fixture.work)
        let manager = fixture.manager()
        var source = ExtensionSource(url: fixture.url)
        var status = try await manager.clone(source).status
        status.trusted = true
        status = try await manager.pin(source, to: first, status)
        #expect(status.commit == first)
        source.pin = nil
        await #expect(throws: ExtensionSourceError.notFastForward) { _ = try await manager.update(source, status) }
        #expect(try GitFixture.git(["rev-parse", "HEAD"], in: ExtensionSources.cloneFolder(for: fixture.url, root: fixture.sources)) == first,
                "the clone stays on the pin")
    }

    /// A bundle under review, or a source's folder, whose extension.json is valid JSON but not a bundle: what's wrong is
    /// said, and its loose scripts aren't taken for its commands.
    @Test func invalidManifestOfABundleOnly() throws {
        let folder = ScriptFolder()
        folder.add("extension.json", #"{"schemaVersion": 1, "commands": [{"script": "a.sh"}]}"#)
        folder.add("a.sh", script(["title A"]))
        folder.add("loose.sh", script(["title Loose"]))
        var config = Config.default
        config.extensionFolders = []
        let review = ExtensionSourceReview.make(bundleFolder: folder.url, path: "", url: "file:///r.git", commit: nil, commitDate: nil,
                                                config: config)
        #expect(review.bundle == nil && review.problem == .badBundle(.badName) && review.commands.isEmpty)
        #expect(review.summary(describe: { problem, _ in "described \(problem)" }).contains("bundle:      can't be loaded: described badBundle(AllInOneIMECore.ScriptCommand.BundleProblem.badName)"))
        // The same folder added by hand still falls back to a plain folder.
        #expect(ExtensionStore.load([ExtensionStore.Folder(path: folder.url.path, found: false)]).commands.map(\.name).sorted() == ["a", "loose"])
        let only = ExtensionStore.load([ExtensionStore.Folder(path: folder.url.path, found: false, bundleOnly: true)])
        #expect(only.commands.isEmpty && only.skipped.map(\.problem) == [.badBundle(.badName)])
        // No extension.json at all: said too.
        let empty = ScriptFolder()
        empty.add("loose.sh", script())
        let none = ExtensionStore.load([ExtensionStore.Folder(path: empty.url.path, found: false, bundleOnly: true)])
        #expect(none.commands.isEmpty && none.skipped.map(\.problem) == [.missing("extension.json")])
    }

    /// Folders of the sources folder load only as their bundle, and only when trusted.
    @Test func loadFoldersMarksSourceFolders() {
        let root = URL(fileURLWithPath: "/tmp/Sources-\(UUID().uuidString)")
        let source = ExtensionSource(url: "file:///r.git", path: "ext")
        var config = Config.default
        config.extensionFolders = ["/tmp/mine"]
        ExtensionSources.enable(source, in: &config, root: root)
        let trusted = [source.url: ExtensionSourceStatus(url: source.url, trusted: true)]
        let folders = ExtensionSources.loadFolders(config, found: [], statuses: trusted, root: root)
        #expect(folders.map(\.bundleOnly) == [false, true])
        #expect(ExtensionSources.loadFolders(config, found: [], statuses: [:], root: root).map(\.path) == ["/tmp/mine"])
    }

    /// The gate compares where folders really are: links resolved, and case as the volume treats it.
    @Test func comparablePaths() {
        #expect(ExtensionSources.comparable("/tmp/x-\(UUID().uuidString)/a/../b/") .hasPrefix("/private/tmp/"))
        let id = UUID().uuidString
        let caseSensitive = (try? URL(fileURLWithPath: "/tmp").resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? true
        #expect((ExtensionSources.comparable("/private/tmp/Sources-\(id)/X") == ExtensionSources.comparable("/tmp/sources-\(id)/x")) == !caseSensitive)
        // A trusted source's folder written another way is still that folder; a path out of the clone names none.
        let root = URL(fileURLWithPath: "/tmp/Sources-\(id)")
        let source = ExtensionSource(url: "file:///r.git", path: "ext")
        var config = Config.default
        config.extensionFolders = ["/private/tmp/Sources-\(id)/" + ExtensionSources.folderName(for: source.url) + "/./ext/"]
        config.extensionSources = [source]
        #expect(ExtensionSources.isEnabled(source, in: config, root: root))
        #expect(ExtensionSources.untrustedFolders(in: config, statuses: [source.url: ExtensionSourceStatus(url: source.url, trusted: true)], root: root).isEmpty)
        let climbing = ExtensionSource(url: "file:///r.git", path: "ext/../../elsewhere")
        #expect(ExtensionSources.bundleFolder(for: climbing, root: root).lastPathComponent == ".invalid-bundle-path")
    }
}
