import Foundation
import Testing
@testable import AllInOneIMECore

// Independent acceptance tests for "extension sources" (spec v2, 0.6.4), written from the spec: install and update a
// script-extension bundle from a Git link. They use only the public API named for the feature (`ExtensionSources`,
// `ExtensionSourceManager`, `ExtensionSourceReview`, `ProcessGitRunner`) and the app binary's command-line flags.
//
// Never the network, never the user's data: repositories are local bare ones in temporary folders, reached through
// file:// addresses; clones go to a temporary sources folder; configs are temporary files. The command-line tests run
// the built binary (.build/debug/AllInOneIME, or $ALLINONEIME_TEST_BINARY) with `--config` and `--sources-dir`, with
// SHELL=/usr/bin/false so the user's shell startup files aren't run, and check that the user's real config and
// sources folder are byte for byte / name for name what they were. When no binary is built they're skipped.
//
// Spec clauses are cited as §N.

// MARK: - Fixtures

enum ExtSrcAcc {
    /// A new temporary folder, its real path (/private/var/…: git prints real paths).
    static func temporaryFolder(_ label: String = "extsrc-acc") throws -> URL {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        guard let real = realpath(made.path, nil) else { return made }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    /// The environment the fixtures' own git runs in: no user or system config.
    static var isolatedEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"] { env[key] = nil }
        return env
    }

    /// The real git as the feature runs it (its own environment builder), but with no user config.
    static func realGit() -> ProcessGitRunner {
        ProcessGitRunner(environment: ExtensionSources.gitEnvironment(base: isolatedEnvironment))
    }

    struct Ran {
        var status: Int32
        var output: String
        var errors: String
    }

    /// Runs `executable` with `arguments`; stdin from /dev/null, its output through files, stopped after `timeout`.
    /// posix_spawn and waitpid, not Process and pipes: with many tests at once, nothing here waits on a dispatch
    /// thread that the blocked test threads could starve.
    static func run(_ executable: String, _ arguments: [String], in folder: URL? = nil, environment: [String: String]? = nil,
                    timeout: TimeInterval = 120) throws -> Ran {
        let io = FileManager.default.temporaryDirectory.appendingPathComponent("extsrc-acc-io-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: io, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: io) }
        let outFile = io.appendingPathComponent("out").path, errFile = io.appendingPathComponent("err").path

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, outFile, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_addopen(&actions, 2, errFile, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if let folder { posix_spawn_file_actions_addchdir_np(&actions, folder.path) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = (environment ?? isolatedEnvironment).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        guard spawned == 0 else { throw ExtensionSourceError.git("test harness: can't start \(executable): \(spawned)") }

        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while true {
            let done = waitpid(pid, &status, WNOHANG)
            if done == pid { break }
            if done == -1 && errno != EINTR { throw ExtensionSourceError.git("test harness: waitpid \(errno)") }
            if Date() > deadline {
                kill(pid, SIGKILL)
                _ = waitpid(pid, &status, 0)
                throw ExtensionSourceError.git("test harness: \(executable) \(arguments.joined(separator: " ")) didn't finish")
            }
            usleep(5_000)
        }
        // Exited normally: its exit status; killed by a signal: 128 + the signal.
        let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        let read = { (path: String) in (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        return Ran(status: code, output: read(outFile), errors: read(errFile))
    }

    /// git for the fixtures (the test's own commits): no user config, no signing.
    @discardableResult
    static func git(_ arguments: [String], in folder: URL, environment extra: [String: String] = [:]) throws -> String {
        var env = isolatedEnvironment
        for (key, value) in extra { env[key] = value }
        let ran = try run("/usr/bin/git", ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.com",
                                           "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false"] + arguments,
                          in: folder, environment: env)
        guard ran.status == 0 else {
            throw ExtensionSourceError.git("fixture: git \(arguments.joined(separator: " ")): \(ran.errors)")
        }
        return ran.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ text: String, to file: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
    }

    /// An `extension.json` (docs/extensions.md §6) with `commands`, each run by `<name>.sh` unless given a script.
    static func manifest(bundle: String, commands: [(name: String, title: String, description: String, output: String)],
                         preferences: String = #"[{ "name": "greeting", "type": "textfield", "title": "Greeting", "default": "hi" }]"#)
        -> String {
        let list = commands.map {
            #"{ "script": "\#($0.name).sh", "name": "\#($0.name)", "title": "\#($0.title)", "description": "\#($0.description)", "output": "\#($0.output)", "input": "none" }"#
        }.joined(separator: ",\n    ")
        return """
            { "schemaVersion": 1, "name": "\(bundle)", "title": "Accept Bundle", "version": "1.0.0", "author": "Fixture",
              "description": "A bundle for the acceptance tests.",
              "preferences": \(preferences),
              "commands": [
                \(list)
              ] }
            """
    }

    /// A bundle in `folder`: the manifest and an executable script for each command.
    static func makeBundle(in folder: URL, bundle: String = "xsrcgreet",
                           commands: [(name: String, title: String, description: String, output: String)]) throws {
        try write(manifest(bundle: bundle, commands: commands), to: folder.appendingPathComponent("extension.json"))
        for command in commands {
            try write("#!/bin/sh\necho \(command.name)\n", to: folder.appendingPathComponent("\(command.name).sh"), executable: true)
        }
    }

    /// The commands the extension loader would offer for `config` (no Spotlight folders).
    static func loadedNames(_ config: Config) -> Set<String> {
        Set(ExtensionStore.load(ExtensionStore.folders(config, found: []), cache: ExtensionCache()).commands.map(\.name))
    }

    /// A config that loads nothing of the user's: no default extensions folder, no Spotlight folders.
    static func emptyConfig() -> Config {
        var config = Config.default
        config.extensionFolders = []
        config.findRaycastScripts = false
        return config
    }

    static let hookNames = ["post-checkout", "post-merge", "post-rewrite", "reference-transaction", "pre-auto-gc"]
}

/// A bare repository on this Mac, and a working copy that pushes to it.
final class ExtSrcAccRepo: @unchecked Sendable {
    let root: URL
    let bare: URL
    let work: URL
    /// Where the clones go (the manager's `root`).
    let sources: URL

    init() throws {
        root = try ExtSrcAcc.temporaryFolder()
        bare = root.appendingPathComponent("upstream/my-extensions.git", isDirectory: true)
        work = root.appendingPathComponent("work", isDirectory: true)
        sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: bare.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ExtSrcAcc.git(["init", "-q", "--bare", "-b", "main", bare.path], in: root)
        try ExtSrcAcc.git(["init", "-q", "-b", "main", work.path], in: root)
        try ExtSrcAcc.git(["remote", "add", "origin", bare.path], in: work)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var url: String { "file://" + bare.path }

    func write(_ path: String, _ text: String, executable: Bool = false) throws {
        try ExtSrcAcc.write(text, to: work.appendingPathComponent(path), executable: executable)
    }

    func bundle(at path: String = "", bundle: String = "xsrcgreet",
                commands: [(name: String, title: String, description: String, output: String)] =
                    [("xsrchello", "Say Hello", "Prints a greeting.", "show")]) throws {
        try ExtSrcAcc.makeBundle(in: path.isEmpty ? work : work.appendingPathComponent(path), bundle: bundle, commands: commands)
    }

    /// Commits everything as `author` at `date` and pushes; returns the commit.
    @discardableResult
    func commit(_ subject: String, author: String = "Fixture <fixture@example.com>", date: String = "2026-10-01T09:30:00-07:00",
                amend: Bool = false, force: Bool = false) throws -> String {
        let env = ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date]
        try ExtSrcAcc.git(["add", "-A"], in: work)
        try ExtSrcAcc.git(["commit", "-q", "--allow-empty", "--author", author, "-m", subject] + (amend ? ["--amend"] : []),
                          in: work, environment: env)
        try ExtSrcAcc.git(["push", "-q"] + (force ? ["-f"] : []) + ["origin", "main"], in: work)
        return try ExtSrcAcc.git(["rev-parse", "HEAD"], in: work)
    }

    func tag(_ name: String) throws {
        try ExtSrcAcc.git(["tag", name], in: work)
        try ExtSrcAcc.git(["push", "-q", "origin", name], in: work)
    }

    /// The commit the clone of `url` under `sources` is at.
    func cloneHead(root: URL? = nil) throws -> String {
        try ExtSrcAcc.git(["rev-parse", "HEAD"], in: ExtensionSources.cloneFolder(for: url, root: root ?? sources))
    }

    func manager(git: (any GitRunning)? = nil, trash: (@Sendable (URL) throws -> Void)? = nil) -> ExtensionSourceManager {
        ExtensionSourceManager(root: sources, git: git ?? ExtSrcAcc.realGit(), now: { Date(timeIntervalSince1970: 1_791_000_000) },
                               trashItem: trash ?? { try FileManager.default.removeItem(at: $0) })
    }

    /// Added the way Settings or `--add-source` adds it: cloned, then trusted and enabled.
    func addTrusted(_ source: ExtensionSource, config: inout Config) async throws -> ExtensionSourceStatus {
        let clone = try await manager().clone(source)
        var status = clone.status
        status.trusted = true
        ExtensionSources.enable(source, in: &config, root: sources)
        return status
    }
}

/// A git that records every call, then answers from `answer` (or passes it on to `inner`).
final class ExtSrcAccRecordingGit: GitRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(arguments: [String], directory: URL?)] = []
    let inner: (any GitRunning)?
    let answer: (@Sendable ([String], URL?) throws -> GitResult)?

    init(inner: any GitRunning) {
        self.inner = inner
        self.answer = nil
    }

    init(answer: @escaping @Sendable ([String], URL?) throws -> GitResult) {
        self.inner = nil
        self.answer = answer
    }

    var calls: [[String]] { lock.withLock { recorded.map(\.arguments) } }

    func run(_ arguments: [String], in directory: URL?) async throws -> GitResult {
        lock.withLock { recorded.append((arguments, directory)) }
        if let answer { return try answer(arguments, directory) }
        return try await inner!.run(arguments, in: directory)
    }
}

/// The URLs an injected trash was given.
final class ExtSrcAccTrash: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URL] = []
    var trashed: [URL] { lock.withLock { items } }
    var closure: @Sendable (URL) throws -> Void { { [self] url in lock.withLock { items.append(url) } } }
}

/// Whether `arguments` turn hooks off (`-c core.hooksPath=/dev/null`), before the git command.
func extSrcAccNoHooks(_ arguments: [String]) -> Bool {
    zip(arguments, arguments.dropFirst()).contains { $0 == "-c" && $1 == "core.hooksPath=/dev/null" }
}

// MARK: - §1/§2 Addresses

@Suite("ExtensionSourcesAcceptance: addresses")
struct ExtensionSourcesAcceptanceURLTests {
    @Test("ssh://, scp-like git@host:, https:// and file:// are accepted (§1)", arguments: [
        "ssh://git.example.com/team/MyExtensions",
        "ssh://git@git.example.com:2222/team/my-extensions.git",
        "git@github.com:you/my-extensions.git",
        "https://github.com/you/my-extensions.git",
        "file:///tmp/repos/my-extensions.git",
    ])
    func accepted(_ url: String) throws {
        #expect(try ExtensionSources.validate(url) == url)
        #expect(try ExtensionSources.validate("  \(url)\n") == url, "surrounding blanks from a paste are trimmed")
    }

    @Test("plain http:// is refused (§1)", arguments: ["http://github.com/you/my-extensions.git", "HTTP://git.example.com/team/x.git"])
    func httpRefused(_ url: String) {
        #expect(throws: (any Error).self) { try ExtensionSources.validate(url) }
    }

    @Test("what isn't one of the accepted forms is refused", arguments: [
        "", "   ", "my-extensions", "ftp://example.com/x.git", "-uhttps://example.com/x.git", "--upload-pack=touch /tmp/x",
    ])
    func otherRefused(_ url: String) {
        #expect(throws: (any Error).self) { try ExtensionSources.validate(url) }
    }

    @Test("adding an http:// link never runs git and leaves nothing behind (§1)")
    func httpNeverCloned() async throws {
        let root = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let git = ExtSrcAccRecordingGit { _, _ in GitResult(status: 0) }
        let manager = ExtensionSourceManager(root: root.appendingPathComponent("Sources"), git: git)
        await #expect(throws: (any Error).self) { _ = try await manager.clone(ExtensionSource(url: "http://example.com/x.git")) }
        #expect(git.calls.isEmpty)
        #expect(ExtensionSources.bundleFolders(in: root).isEmpty)
    }
}

// MARK: - §2 Where the clone goes

@Suite("ExtensionSourcesAcceptance: the clone's folder")
struct ExtensionSourcesAcceptanceCloneFolderTests {
    @Test("the folder is the repository's name plus a short hash of the URL (§2)")
    func folderName() throws {
        let url = "git@github.com:you/my-extensions.git"
        let name = ExtensionSources.folderName(for: url)
        #expect(name.hasPrefix("my-extensions-"))
        let hash = name.dropFirst("my-extensions-".count)
        #expect(!hash.isEmpty && hash.count <= 16 && hash.allSatisfy(\.isHexDigit), "a short hash: \(name)")
        #expect(ExtensionSources.folderName(for: url) == name, "the same URL, the same folder")
        #expect(ExtensionSources.folderName(for: "git@github.com:someone-else/my-extensions.git") != name,
                "two repositories of one name don't share a folder")
        #expect(ExtensionSources.folderName(for: "ssh://git.example.com/team/MyExtensions").hasPrefix("MyExtensions-"))
    }

    @Test("clones live under ~/Library/Application Support/AllInOneIME/Sources, never in an extensions folder (§2)")
    func directory() {
        let directory = ExtensionSources.directory.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        #expect(directory == home + "/Library/Application Support/AllInOneIME/Sources")
        for folder in Config.default.extensionFolders {
            let path = ExtensionSources.comparable(folder)
            #expect(!directory.hasPrefix(path + "/") && directory != path, "\(folder) is an extensions folder")
        }
        let url = "git@github.com:you/my-extensions.git"
        #expect(ExtensionSources.cloneFolder(for: url).deletingLastPathComponent().standardizedFileURL.path == directory)
    }

    @Test("git clones into a temporary folder, not the final one, and the result is moved into place (§2)")
    func clonedElsewhereThenMoved() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        try repo.commit("First")
        let recording = ExtSrcAccRecordingGit(inner: ExtSrcAcc.realGit())
        let source = ExtensionSource(url: repo.url)
        let clone = try await repo.manager(git: recording).clone(source)
        let destination = ExtensionSources.cloneFolder(for: repo.url, root: repo.sources)
        #expect(clone.folder.standardizedFileURL.path == destination.standardizedFileURL.path)
        let cloneCall = try #require(recording.calls.first { $0.contains("clone") })
        let target = try #require(cloneCall.last)
        #expect(URL(fileURLWithPath: target).standardizedFileURL.path != destination.standardizedFileURL.path,
                "git must not write straight into the final folder: \(cloneCall)")
        #expect(cloneCall.contains("--depth") && cloneCall.contains("1"), "a shallow clone: \(cloneCall)")
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("extension.json").path))
        #expect(!FileManager.default.fileExists(atPath: target), "the temporary folder is gone once moved")
        let left = try FileManager.default.contentsOfDirectory(atPath: repo.sources.path)
            .filter { $0 != destination.lastPathComponent && $0 != ExtensionSources.statusFileName }
        #expect(left.isEmpty, "nothing else left in the sources folder: \(left)")
    }

    @Test("a clone that fails half-way leaves no tree behind, in place or anywhere under the sources folder (§2)")
    func noHalfFetchedTree() async throws {
        let root = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let url = "ssh://git.example.com/team/MyExtensions"
        let destination = ExtensionSources.cloneFolder(for: url, root: sources)
        final class Seen: @unchecked Sendable { var destinationExisted = false }
        let seen = Seen()
        let git = ExtSrcAccRecordingGit { arguments, _ in
            guard arguments.contains("clone"), let target = arguments.last else { return GitResult(status: 0) }
            seen.destinationExisted = FileManager.default.fileExists(atPath: destination.path)
            // Half a tree: the manifest arrived, the script didn't.
            let folder = URL(fileURLWithPath: target)
            try ExtSrcAcc.makeBundle(in: folder, commands: [("xsrchalf", "Half", "Half-fetched.", "show")])
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("xsrchalf.sh"))
            return GitResult(status: 128, errors: "Cloning into '\(target)'...\nfatal: early EOF\nfatal: fetch-pack: invalid index-pack output\n")
        }
        let manager = ExtensionSourceManager(root: sources, git: git)
        await #expect(throws: (any Error).self) { _ = try await manager.clone(ExtensionSource(url: url)) }
        #expect(!seen.destinationExisted)
        #expect(!FileManager.default.fileExists(atPath: destination.path), "no clone in place")
        #expect(ExtensionSources.bundleFolders(in: sources).isEmpty, "no half-fetched bundle anywhere under Sources")
    }

    @Test("a failed re-clone keeps the clone that was there (nothing half-fetched replaces it) (§2, §4)")
    func failedRecloneKeepsOld() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        let first = try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        let source = ExtensionSource(url: repo.url)
        let status = try await repo.addTrusted(source, config: &config)
        try FileManager.default.moveItem(at: repo.bare, to: repo.bare.deletingLastPathComponent().appendingPathComponent("gone.git"))
        await #expect(throws: (any Error).self) { _ = try await repo.manager().reclone(source, status) }
        #expect(try repo.cloneHead() == first)
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrchello"), "the enabled bundle still loads")
    }
}

// MARK: - §1 Finding the bundle

@Suite("ExtensionSourcesAcceptance: finding the bundle path")
struct ExtensionSourcesAcceptancePathTests {
    @Test("one folder with an extension.json: it's used (§1)")
    func one() throws {
        let clone = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: clone) }
        try ExtSrcAcc.write("# Team tools\n", to: clone.appendingPathComponent("README.md"))
        try ExtSrcAcc.makeBundle(in: clone.appendingPathComponent("extensions/team"), commands: [("xsrcstandup", "Standup", "d", "show")])
        #expect(try ExtensionSources.resolveBundlePath(nil, in: clone) == "extensions/team")
        #expect(try ExtensionSources.resolveBundlePath("", in: clone) == "extensions/team", "an empty path is auto-detected too")
        #expect(try ExtensionSources.resolveBundlePath("extensions/team", in: clone) == "extensions/team")
    }

    @Test("the bundle at the repository's root (§1)")
    func root() throws {
        let clone = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: clone) }
        try ExtSrcAcc.makeBundle(in: clone, commands: [("xsrcroot", "Root", "d", "insert")])
        #expect(try ExtensionSources.resolveBundlePath(nil, in: clone) == "")
    }

    @Test("several: all are listed to pick from, none is chosen silently (§1)")
    func several() throws {
        let clone = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: clone) }
        try ExtSrcAcc.makeBundle(in: clone.appendingPathComponent("tools/alpha"), bundle: "xsrca", commands: [("xsrcalpha", "A", "d", "show")])
        try ExtSrcAcc.makeBundle(in: clone.appendingPathComponent("tools/beta"), bundle: "xsrcb", commands: [("xsrcbeta", "B", "d", "show")])
        #expect(Set(ExtensionSources.bundleFolders(in: clone)) == ["tools/alpha", "tools/beta"])
        do {
            let picked = try ExtensionSources.resolveBundlePath(nil, in: clone)
            Issue.record("picked \(picked) without asking")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            #expect(text.contains("tools/alpha") && text.contains("tools/beta"), "the choices are shown: \(text)")
        }
        #expect(try ExtensionSources.resolveBundlePath("tools/beta", in: clone) == "tools/beta", "a path picks one")
    }

    @Test("none: an error, not an empty bundle (§1)")
    func none() throws {
        let clone = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: clone) }
        try ExtSrcAcc.write("# nothing here\n", to: clone.appendingPathComponent("README.md"))
        #expect(ExtensionSources.bundleFolders(in: clone).isEmpty)
        #expect(throws: (any Error).self) { try ExtensionSources.resolveBundlePath(nil, in: clone) }
        #expect(throws: (any Error).self) { try ExtensionSources.resolveBundlePath("extensions/team", in: clone) }
    }

    @Test("a clone with several bundles reports them all for the preview (§1)")
    func cloneListsBundles() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle(at: "a", bundle: "xsrcbunda", commands: [("xsrcaa", "A", "d", "show")])
        try repo.bundle(at: "b", bundle: "xsrcbundb", commands: [("xsrcbb", "B", "d", "show")])
        try repo.commit("Two bundles")
        let clone = try await repo.manager().clone(ExtensionSource(url: repo.url))
        #expect(Set(clone.bundles) == ["a", "b"])
    }
}

// MARK: - §2 Git's environment and calls

@Suite("ExtensionSourcesAcceptance: how git runs")
struct ExtensionSourcesAcceptanceGitEnvironmentTests {
    @Test("no prompts, ssh in batch mode, the login PATH, the SSH agent and HOME (§2)")
    func environment() {
        let env = ExtensionSources.gitEnvironment(
            base: ["PATH": "/opt/homebrew/bin:/usr/bin:/bin", "HOME": "/Users/someone", "GIT_TERMINAL_PROMPT": "1", "LANG": "en_US.UTF-8"],
            login: ["SSH_AUTH_SOCK": "/private/tmp/com.apple.launchd.x/Listeners"])
        #expect(env["GIT_TERMINAL_PROMPT"] == "0", "a prompt would hang the IME: always 0, whatever was set")
        #expect(env["GIT_SSH_COMMAND"]?.contains("BatchMode=yes") == true, "\(env["GIT_SSH_COMMAND"] ?? "nil")")
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin")
        #expect(env["HOME"] == "/Users/someone")
        #expect(env["SSH_AUTH_SOCK"] == "/private/tmp/com.apple.launchd.x/Listeners")
        #expect(env["LANG"] == "en_US.UTF-8", "the rest of the environment is kept")
    }

    @Test("the agent already in the environment is kept when the login shell has none (§2)")
    func agentKept() {
        let env = ExtensionSources.gitEnvironment(base: ["PATH": "/usr/bin", "HOME": "/Users/u", "SSH_AUTH_SOCK": "/tmp/agent"], login: [:])
        #expect(env["SSH_AUTH_SOCK"] == "/tmp/agent")
    }

    @Test("BatchMode is added to the user's own ssh command, not instead of it (§2)")
    func ownSSHCommandKept() {
        let own = "ssh -i ~/.ssh/work_key -F ~/.ssh/config.work"
        for env in [ExtensionSources.gitEnvironment(base: ["PATH": "/usr/bin", "GIT_SSH_COMMAND": own]),
                    ExtensionSources.gitEnvironment(base: ["PATH": "/usr/bin"], login: ["GIT_SSH_COMMAND": own]),
                    ExtensionSources.gitEnvironment(base: ["PATH": "/usr/bin"], sshCommand: own)] {
            let command = env["GIT_SSH_COMMAND"] ?? ""
            #expect(command.hasPrefix(own), "the user's command and options stay: \(command)")
            #expect(command.contains("BatchMode=yes"), "\(command)")
        }
    }

    @Test("the user's git: /usr/bin/git, 60 s a call, in the login shell's environment, no prompts (§2)")
    func userRunner() async {
        let runner = await ProcessGitRunner.user()
        #expect(runner.executable.path == "/usr/bin/git")
        #expect(runner.timeout == 60)
        #expect(ExtensionSources.timeout == 60)
        #expect(runner.environment["GIT_TERMINAL_PROMPT"] == "0")
        if runner.environment["GIT_SSH"]?.isEmpty != false {
            #expect(runner.environment["GIT_SSH_COMMAND"]?.contains("BatchMode=yes") == true)
        }
        #expect(runner.environment["PATH"] == ShellEnvironment.current["PATH"], "the login shell's PATH (the user's tools)")
        if let agent = ShellEnvironment.login["SSH_AUTH_SOCK"], !agent.isEmpty {
            #expect(runner.environment["SSH_AUTH_SOCK"] == agent, "the login shell's SSH agent")
        }
        #expect(runner.environment["HOME"]?.isEmpty == false)
    }

    @Test("hooks are off and fetches are shallow in the git commands built (§2, §4)")
    func arguments() {
        let clone = ExtensionSources.cloneArguments(url: "git@github.com:you/my-extensions.git", branch: "main",
                                                    into: URL(fileURLWithPath: "/tmp/x"))
        #expect(extSrcAccNoHooks(clone))
        #expect(clone.contains("clone") && clone.contains("--depth"))
        #expect(clone.contains("main"), "the branch asked for")
        #expect(clone.contains("git@github.com:you/my-extensions.git"))
        let fetch = ExtensionSources.fetchArguments("main", depth: 50)
        #expect(extSrcAccNoHooks(fetch))
        #expect(fetch.contains("fetch") && fetch.contains("--depth"))
    }

    @Test("every git call of add, check, update, pin and re-clone has hooks off (§4)")
    func everyCallNoHooks() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        let first = try repo.commit("First")
        try repo.tag("v1")
        try repo.write("notes.txt", "two\n")
        try repo.commit("Second")
        let recording = ExtSrcAccRecordingGit(inner: ExtSrcAcc.realGit())
        let manager = repo.manager(git: recording)
        let source = ExtensionSource(url: repo.url)
        var status = try await manager.clone(source).status
        status.trusted = true
        try repo.write("notes.txt", "three\n")
        try repo.commit("Third")
        status = try await manager.check(source, status)
        status = try await manager.update(source, status)
        status = try await manager.pin(source, to: "v1", status)
        #expect(try repo.cloneHead() == first)
        _ = try await manager.reclone(source, status)
        #expect(!recording.calls.isEmpty)
        for call in recording.calls { #expect(extSrcAccNoHooks(call), "hooks not off: git \(call.joined(separator: " "))") }
    }

    @Test("a git call that hangs is stopped at the timeout (§2)")
    func timeout() async throws {
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("slow-git")
        try ExtSrcAcc.write("#!/bin/sh\nsleep 30\necho finished\n", to: fake, executable: true)
        let runner = ProcessGitRunner(executable: fake, environment: ["PATH": "/usr/bin:/bin"], timeout: 1)
        let started = Date()
        await #expect(throws: (any Error).self) { _ = try await runner.run(["fetch"], in: folder) }
        #expect(Date().timeIntervalSince(started) < 10, "stopped after about a second, not 30")
    }

    @Test("stdin is closed: git can't wait for an answer (§2)")
    func stdinClosed() async throws {
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("reading-git")
        try ExtSrcAcc.write("#!/bin/sh\nif read line; then echo \"read:$line\"; else echo stdin-closed; fi\n", to: fake, executable: true)
        let runner = ProcessGitRunner(executable: fake, environment: ["PATH": "/usr/bin:/bin"], timeout: 10)
        let result = try await runner.run([], in: folder)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "stdin-closed")
    }

    @Test("git runs in exactly the environment built for it (§2)")
    func environmentPassed() async throws {
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("env-git")
        try ExtSrcAcc.write("#!/bin/sh\n/usr/bin/env\n", to: fake, executable: true)
        let env = ExtensionSources.gitEnvironment(base: ["PATH": "/usr/bin:/bin", "HOME": folder.path], login: ["SSH_AUTH_SOCK": "/tmp/acc-agent"])
        let result = try await ProcessGitRunner(executable: fake, environment: env, timeout: 10).run([], in: folder)
        let lines = Set(result.output.split(separator: "\n").map(String.init))
        #expect(lines.contains("GIT_TERMINAL_PROMPT=0"))
        #expect(lines.contains("SSH_AUTH_SOCK=/tmp/acc-agent"))
        #expect(lines.contains { $0.hasPrefix("GIT_SSH_COMMAND=") && $0.contains("BatchMode=yes") })
    }

    @Test("without the Command Line Tools, a clear error instead of /usr/bin/git's installer (§2)")
    func noDeveloperTools() async {
        let runner = ProcessGitRunner(environment: ["PATH": "/usr/bin:/bin"], developerFolders: ["/nonexistent/Developer"])
        do {
            _ = try await runner.run(["--version"], in: nil)
            Issue.record("ran /usr/bin/git without the developer tools")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            #expect(text.contains("Command Line Tools") || text.contains("xcode-select"), "\(text)")
        }
    }
}

// MARK: - §2 Failures

@Suite("ExtensionSourcesAcceptance: git's errors")
struct ExtensionSourcesAcceptanceErrorTests {
    @Test("git's own error lines are shown as they are (§2)")
    func verbatim() async throws {
        let stderr = "Cloning into '/x/.tmp'...\nfatal: repository 'https://git.example.com/team/Missing.git/' not found\n"
        let git = ExtSrcAccRecordingGit { arguments, _ in
            arguments.contains("clone") ? GitResult(status: 128, errors: stderr) : GitResult(status: 0)
        }
        let root = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ExtensionSourceManager(root: root, git: git)
        do {
            _ = try await manager.clone(ExtensionSource(url: "https://git.example.com/team/Missing.git"))
            Issue.record("the clone didn't fail")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            #expect(text.contains("fatal: repository 'https://git.example.com/team/Missing.git/' not found"), "\(text)")
        }
    }

    /// The case the spec was written for: a company host refuses the key. The line that says why is ssh's (or the
    /// server's) and comes before git's generic closing lines; it must reach the user (§2: "show git's error text as
    /// it is (its last meaningful lines)").
    @Test("an ssh or server refusal line is kept, not cut off by git's closing boilerplate (§2)")
    func authenticationLineKept() {
        let stderr = """
            Cloning into '/Users/u/Library/Application Support/AllInOneIME/Sources/.tmp-x'...
            git@git.example.com: Permission denied (publickey).
            fatal: Could not read from remote repository.

            Please make sure you have the correct access rights
            and the repository exists.

            """
        let message = ExtensionSources.gitMessage(GitResult(status: 128, errors: stderr))
        #expect(message.contains("git@git.example.com: Permission denied (publickey)."), "shown: \(message)")
        #expect(message.contains("fatal: Could not read from remote repository."), "shown: \(message)")
    }

    @Test("a server's own message before git's is kept (§2)")
    func serverMessageKept() {
        let stderr = """
            Cloning into '.tmp-x'...
            remote: ERROR: Your sign-in has expired. Sign in again and retry.
            fatal: Could not read from remote repository.

            Please make sure you have the correct access rights
            and the repository exists.
            """
        let message = ExtensionSources.gitMessage(GitResult(status: 128, errors: stderr))
        #expect(message.contains("remote: ERROR: Your sign-in has expired. Sign in again and retry."), "shown: \(message)")
    }

    @Test("a real git failure: the error carries every fatal line git printed, the cause included (§2)")
    func realGitFailure() async throws {
        let root = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = "file://" + root.appendingPathComponent("no-such-repo.git").path
        // What git itself says for this address.
        let own = try ExtSrcAcc.run("/usr/bin/git", ["clone", "--depth", "1", url, root.appendingPathComponent("probe").path], in: root)
        let fatal = own.errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("fatal:") }
        try #require(!fatal.isEmpty, "git printed: \(own.errors)")
        let manager = ExtensionSourceManager(root: root.appendingPathComponent("Sources"), git: ExtSrcAcc.realGit())
        do {
            _ = try await manager.clone(ExtensionSource(url: url))
            Issue.record("cloned a repository that isn't there")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            for line in fatal { #expect(text.contains(line), "git said \(line); shown: \(text)") }
        }
    }

    @Test("authHint is kept from the config (§2)")
    func authHintDecodes() throws {
        let json = #"{ "url": "ssh://git.example.com/team/MyExtensions", "authHint": "Sign in to the network first." }"#
        let source = try JSONDecoder().decode(ExtensionSource.self, from: Data(json.utf8))
        #expect(source.authHint == "Sign in to the network first.")
        let again = try JSONDecoder().decode(ExtensionSource.self, from: JSONEncoder().encode(source))
        #expect(again.authHint == "Sign in to the network first.")
    }
}

// MARK: - §3 The review

@Suite("ExtensionSourcesAcceptance: the review before enabling")
struct ExtensionSourcesAcceptanceReviewTests {
    static let url = "git@github.com:you/my-extensions.git"
    static let sha = "0123456789abcdef0123456789abcdef01234567"
    static let date = ISO8601DateFormatter().date(from: "2026-10-01T16:30:00Z")!

    /// A bundle with a shell script, a Python script that isn't executable, and two preferences.
    static func bundle() throws -> URL {
        let folder = try ExtSrcAcc.temporaryFolder()
        try ExtSrcAcc.write("""
            { "schemaVersion": 1, "name": "xsrcteam", "title": "Team Tools", "version": "2.1.0", "author": "Team",
              "description": "Our tools.",
              "preferences": [
                { "name": "channel", "type": "textfield", "title": "Channel", "default": "general" },
                { "name": "apiToken", "type": "password", "title": "API token", "required": true }
              ],
              "commands": [
                { "script": "standup.sh", "name": "xsrcstandup", "title": "Standup Notes", "description": "Writes the standup.",
                  "output": "show", "input": "none" },
                { "script": "bin/format.py", "name": "xsrcformat", "title": "Format Text", "description": "Formats the text.",
                  "output": "insert" }
              ] }
            """, to: folder.appendingPathComponent("extension.json"))
        try ExtSrcAcc.write("#!/bin/sh\necho standup\n", to: folder.appendingPathComponent("standup.sh"), executable: true)
        try ExtSrcAcc.write("#!/usr/bin/env python3\nprint('x')\n", to: folder.appendingPathComponent("bin/format.py"))
        return folder
    }

    @Test("the review lists the bundle, each command, the programs, the preferences, the link and the commit (§3)")
    func contents() throws {
        let folder = try Self.bundle()
        defer { try? FileManager.default.removeItem(at: folder) }
        let review = ExtensionSourceReview.make(bundleFolder: folder, path: "", url: Self.url, commit: Self.sha, commitDate: Self.date,
                                                config: ExtSrcAcc.emptyConfig())
        #expect(review.bundle?.name == "xsrcteam")
        #expect(review.url == Self.url)
        #expect(review.commit == Self.sha)
        let byName = Dictionary(uniqueKeysWithValues: review.commands.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["xsrcstandup", "xsrcformat"])
        #expect(byName["xsrcstandup"]?.title == "Standup Notes")
        #expect(byName["xsrcstandup"]?.description == "Writes the standup.")
        #expect(byName["xsrcstandup"]?.output == .show)
        #expect(byName["xsrcformat"]?.title == "Format Text")
        #expect(byName["xsrcformat"]?.description == "Formats the text.")
        #expect(byName["xsrcformat"]?.output == .insert)
        #expect(review.programs.contains { $0.contains("standup.sh") }, "\(review.programs)")
        #expect(review.programs.contains { $0.contains("python3") && $0.contains("bin/format.py") },
                "the interpreter and the script: \(review.programs)")
        #expect(review.preferences.map(\.name) == ["channel", "apiToken"])
        #expect(review.commands.allSatisfy { $0.hidden == nil })
    }

    @Test("the review as text has all of it, and the unsigned warning (§3, §6)")
    func summary() throws {
        let folder = try Self.bundle()
        defer { try? FileManager.default.removeItem(at: folder) }
        let review = ExtensionSourceReview.make(bundleFolder: folder, path: "", url: Self.url, commit: Self.sha, commitDate: Self.date,
                                                config: ExtSrcAcc.emptyConfig())
        let text = review.summary.joined(separator: "\n")
        #expect(text.contains("This source isn't signed: it will run programs from \(Self.url)"), "\(text)")
        #expect(text.contains(Self.url))
        #expect(text.contains("0123456"), "the short sha")
        #expect(text.contains("2026-10-01"), "the commit's date")
        #expect(text.contains("xsrcteam"))
        for word in ["xsrcstandup", "Standup Notes", "Writes the standup.", "show",
                     "xsrcformat", "Format Text", "Formats the text.", "insert",
                     "standup.sh", "python3", "bin/format.py", "channel", "apiToken"] {
            #expect(text.contains(word), "missing \(word) in:\n\(text)")
        }
    }

    @Test("commands that clash with a built-in or an existing command are shown as skipped, with why (§3)")
    func clashes() throws {
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try ExtSrcAcc.makeBundle(in: folder, bundle: "xsrcclash", commands: [
            ("translate", "My Translate", "Clashes with a built-in.", "show"),
            ("xsrcmine", "Mine", "Clashes with a custom command.", "show"),
            ("xsrcfree", "Free", "Clashes with nothing.", "show"),
        ])
        var config = ExtSrcAcc.emptyConfig()
        config.customCommands.append(CustomCommand(name: "xsrcmine", type: .prompt, prompt: "Say {input}"))
        let review = ExtensionSourceReview.make(bundleFolder: folder, path: "", url: Self.url, commit: Self.sha, commitDate: Self.date,
                                                config: config)
        let byName = Dictionary(uniqueKeysWithValues: review.commands.map { ($0.name, $0) })
        #expect(byName["translate"]?.hidden != nil, "a built-in has the name")
        #expect(byName["xsrcmine"]?.hidden != nil, "a custom command has the name")
        #expect(byName["xsrcfree"]?.hidden == nil)
        let text = review.summary.joined(separator: "\n")
        let lines = text.split(separator: "\n").filter { $0.contains("translate") || $0.contains("xsrcmine") }
        #expect(!lines.isEmpty && lines.allSatisfy { !$0.contains("@xsrcfree") }, "\(text)")
        let translateLine = text.split(separator: "\n").first { $0.contains("translate") }.map { $0.lowercased() } ?? ""
        #expect(translateLine.contains("hidden") || translateLine.contains("taken") || translateLine.contains("skipped"),
                "the reason is shown: \(text)")
    }

    @Test("nothing is loaded before Enable; Enable adds the bundle's folder; Cancel deletes the clone (§3)")
    func enableOnlyOnEnable() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle(at: "extensions/team")
        let sha = try repo.commit("First", date: "2026-10-01T09:30:00-07:00")
        let manager = repo.manager()
        var source = ExtensionSource(url: repo.url)
        var config = ExtSrcAcc.emptyConfig()
        let before = config
        let clone = try await manager.clone(source)
        #expect(clone.status.trusted == false, "a fresh clone isn't trusted")
        #expect(clone.status.commit == sha)
        source.path = try ExtensionSources.resolveBundlePath(source.path, in: clone.folder)
        #expect(source.path == "extensions/team")
        let review = ExtensionSourceReview.make(bundleFolder: ExtensionSources.bundleFolder(for: source, root: repo.sources),
                                                path: source.path ?? "", url: source.url, commit: clone.status.commit,
                                                commitDate: clone.status.commitDate, config: config)
        #expect(review.commands.map(\.name) == ["xsrchello"])
        #expect(review.commit == sha)
        #expect(config == before, "neither the clone nor the review changes the config")
        #expect(!ExtensionSources.isEnabled(source, in: config, root: repo.sources))
        #expect(!ExtSrcAcc.loadedNames(config).contains("xsrchello"), "not loaded before Enable")

        ExtensionSources.enable(source, in: &config, root: repo.sources)
        #expect(ExtensionSources.isEnabled(source, in: config, root: repo.sources))
        #expect(config.extensionSources.map(\.url) == [repo.url])
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrchello"), "loaded once enabled")

        // Cancel, for a second source: its clone is deleted.
        let other = try ExtSrcAccRepo()
        try other.bundle(bundle: "xsrcother", commands: [("xsrcother", "Other", "d", "show")])
        try other.commit("Other")
        let otherSource = ExtensionSource(url: other.url)
        let otherManager = other.manager()
        let otherClone = try await otherManager.clone(otherSource)
        #expect(FileManager.default.fileExists(atPath: otherClone.folder.path))
        otherManager.discard(otherSource)
        #expect(!FileManager.default.fileExists(atPath: otherClone.folder.path))
    }
}

// MARK: - §3 Trust

@Suite("ExtensionSourcesAcceptance: trust")
struct ExtensionSourcesAcceptanceTrustTests {
    @Test("trust is recorded with the URL: another URL isn't trusted (§3)")
    func perURL() {
        let source = ExtensionSource(url: "git@github.com:you/my-extensions.git")
        #expect(ExtensionSources.isTrusted(source, ExtensionSourceStatus(url: source.url, trusted: true)))
        #expect(!ExtensionSources.isTrusted(source, ExtensionSourceStatus(url: source.url, trusted: false)))
        #expect(!ExtensionSources.isTrusted(source, nil))
        #expect(!ExtensionSources.isTrusted(source, ExtensionSourceStatus(url: "git@github.com:someone-else/my-extensions.git", trusted: true)),
                "trust for one address doesn't carry over to another")
    }

    @Test("once trusted, update and re-clone need no new review: the trust stays (§3, §4)")
    func trustSurvivesUpdates() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        let source = ExtensionSource(url: repo.url)
        var status = try await repo.addTrusted(source, config: &config)
        let enabled = config
        try repo.write("notes.txt", "more\n")
        let second = try repo.commit("Second")
        status = try await repo.manager().check(source, status)
        status = try await repo.manager().update(source, status)
        #expect(status.trusted)
        #expect(try repo.cloneHead() == second)
        #expect(config == enabled, "no new review or Enable")
        status = try await repo.manager().reclone(source, status)
        #expect(status.trusted)
    }

    @Test("the status survives being saved next to the clones (§1: per-source state)")
    func statusKept() throws {
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(ExtensionSources.statusFileName)
        #expect(ExtensionSourceStatus.load(from: file).isEmpty)
        let status = ExtensionSourceStatus(url: "git@github.com:you/my-extensions.git", trusted: true, branch: "main",
                                           commit: "0123456789abcdef0123456789abcdef01234567",
                                           commitDate: Date(timeIntervalSince1970: 1_790_000_000),
                                           checked: Date(timeIntervalSince1970: 1_790_100_000), error: "fatal: x")
        try ExtensionSourceStatus.save([status.url: status], to: file)
        #expect(ExtensionSourceStatus.load(from: file)[status.url] == status)
    }
}

// MARK: - §4 Updates

@Suite("ExtensionSourcesAcceptance: updates")
struct ExtensionSourcesAcceptanceUpdateTests {
    @Test("check lists N new commits with subject, author and date, and changes nothing (§4)")
    func check() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        let first = try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        let source = ExtensionSource(url: repo.url)
        let status = try await repo.addTrusted(source, config: &config)
        try repo.write("a.txt", "a\n")
        try repo.commit("Add a", author: "Alice Example <alice@example.com>", date: "2026-10-02T10:00:00-07:00")
        try repo.write("b.txt", "b\n")
        try repo.commit("Add b", author: "Bob Example <bob@example.com>", date: "2026-10-03T11:00:00-07:00")
        try repo.write("c.txt", "c\n")
        let newest = try repo.commit("Add c", author: "Carol Example <carol@example.com>", date: "2026-10-04T12:00:00-07:00")

        let checked = try await repo.manager().check(source, status)
        #expect(checked.updates.count == 3)
        #expect(checked.updates.map(\.subject) == ["Add c", "Add b", "Add a"], "newest first")
        #expect(checked.updates.map(\.author) == ["Carol Example", "Bob Example", "Alice Example"])
        let iso = ISO8601DateFormatter()
        #expect(checked.updates.map(\.date) == ["2026-10-04T19:00:00Z", "2026-10-03T18:00:00Z", "2026-10-02T17:00:00Z"].map { iso.date(from: $0) })
        #expect(checked.updates.first?.sha == newest)
        #expect(checked.fastForward)
        #expect(try repo.cloneHead() == first, "a check doesn't move the clone")
        let clone = ExtensionSources.cloneFolder(for: repo.url, root: repo.sources)
        #expect(!FileManager.default.fileExists(atPath: clone.appendingPathComponent("a.txt").path))
    }

    @Test("parsing git's log gives subject, author and date (§4)")
    func parseLog() {
        let line = ["9fceb02d0ae598e95dc970b74767f19372d61af8", "Alice Example", "2026-10-02T10:00:00-07:00", "Fix: handle a | in names"]
            .joined(separator: "\u{1F}")
        let commits = ExtensionSources.parseLog(line + "\n")
        #expect(commits.count == 1)
        #expect(commits.first?.subject == "Fix: handle a | in names")
        #expect(commits.first?.author == "Alice Example")
        #expect(commits.first?.date == ISO8601DateFormatter().date(from: "2026-10-02T17:00:00Z"))
        #expect(commits.first?.shortSHA == "9fceb02")
        #expect(ExtensionSources.parseLog("").isEmpty)
    }

    @Test("check when up to date: no updates (§4)")
    func upToDate() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        let source = ExtensionSource(url: repo.url)
        let status = try await repo.addTrusted(source, config: &config)
        let checked = try await repo.manager().check(source, status)
        #expect(checked.updates.isEmpty)
    }

    @Test("Update fast-forwards to upstream: no merge commit, the new files are there, the loader sees them (§4)")
    func update() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        let source = ExtensionSource(url: repo.url)
        var status = try await repo.addTrusted(source, config: &config)
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrchello"))
        try repo.bundle(commands: [("xsrchello", "Say Hello", "Prints a greeting.", "show"), ("xsrcbye", "Say Bye", "Prints bye.", "show")])
        let second = try repo.commit("Add bye")
        status = try await repo.manager().check(source, status)
        status = try await repo.manager().update(source, status)
        #expect(try repo.cloneHead() == second, "exactly upstream's commit (a merge would make a new one)")
        #expect(status.commit == second)
        #expect(status.updates.isEmpty)
        #expect(ExtSrcAcc.loadedNames(config).isSuperset(of: ["xsrchello", "xsrcbye"]), "the loader picks up the new command")
    }

    @Test("Update runs no hooks: post-checkout, post-merge and the rest never fire (§4)")
    func noHooks() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        let first = try repo.commit("First")
        try repo.tag("v1")
        var config = ExtSrcAcc.emptyConfig()
        let source = ExtensionSource(url: repo.url)
        var status = try await repo.addTrusted(source, config: &config)
        let clone = ExtensionSources.cloneFolder(for: repo.url, root: repo.sources)
        let markers = repo.root.appendingPathComponent("markers", isDirectory: true)
        try FileManager.default.createDirectory(at: markers, withIntermediateDirectories: true)
        for hook in ExtSrcAcc.hookNames {
            try ExtSrcAcc.write("#!/bin/sh\ntouch '\(markers.path)/\(hook)'\nexit 0\n",
                                to: clone.appendingPathComponent(".git/hooks/\(hook)"), executable: true)
        }
        // Control: the hooks are live for a plain git.
        try ExtSrcAcc.git(["checkout", "-q", "--detach", "HEAD"], in: clone)
        #expect(FileManager.default.fileExists(atPath: markers.appendingPathComponent("post-checkout").path), "control: the hook would run")
        for name in try FileManager.default.contentsOfDirectory(atPath: markers.path) {
            try FileManager.default.removeItem(at: markers.appendingPathComponent(name))
        }

        try repo.write("a.txt", "a\n")
        let second = try repo.commit("Second")
        status = try await repo.manager().check(source, status)
        status = try await repo.manager().update(source, status)
        #expect(try repo.cloneHead() == second)
        status = try await repo.manager().pin(source, to: "v1", status)
        #expect(try repo.cloneHead() == first)
        let fired = try FileManager.default.contentsOfDirectory(atPath: markers.path)
        #expect(fired.isEmpty, "hooks ran: \(fired)")
    }

    @Test("after a force push: not a fast-forward, the clone stays, and Re-clone fixes it (§4)")
    func forcePush() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        let first = try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        let source = ExtensionSource(url: repo.url)
        var status = try await repo.addTrusted(source, config: &config)
        try repo.write("rewritten.txt", "new history\n")
        let rewritten = try repo.commit("First, rewritten", amend: true, force: true)
        #expect(rewritten != first)

        status = try await repo.manager().check(source, status)
        #expect(status.fastForward == false, "the check says Update can't fast-forward")
        do {
            _ = try await repo.manager().update(source, status)
            Issue.record("updated across a force push")
        } catch {
            #expect(error as? ExtensionSourceError == .notFastForward, "\(error)")
        }
        #expect(try repo.cloneHead() == first, "the clone isn't touched")
        status = try await repo.manager().reclone(source, status)
        #expect(try repo.cloneHead() == rewritten)
        #expect(status.trusted)
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrchello"))
    }

    @Test("autoCheck only decides automatic checks; a check never updates (§4)")
    func autoCheck() {
        let url = "git@github.com:you/my-extensions.git"
        let trusted = ExtensionSourceStatus(url: url, trusted: true)
        #expect(ExtensionSource(url: url).autoCheck, "on by default")
        #expect(ExtensionSources.shouldCheck(ExtensionSource(url: url, autoCheck: true), status: trusted, automatic: true))
        #expect(!ExtensionSources.shouldCheck(ExtensionSource(url: url, autoCheck: false), status: trusted, automatic: true))
        #expect(ExtensionSources.shouldCheck(ExtensionSource(url: url, autoCheck: false), status: trusted, automatic: false),
                "Check Now still works")
        #expect(!ExtensionSources.shouldCheck(ExtensionSource(url: url), status: ExtensionSourceStatus(url: url), automatic: true),
                "not before it's reviewed and enabled")
        #expect(ExtensionSources.firstCheckDelay >= 20 && ExtensionSources.firstCheckDelay <= 60, "about 30 s after start")
        #expect(ExtensionSources.checkInterval == 24 * 3600, "once a day")
    }

    @Test("a pinned source isn't checked, automatically or not (§4)")
    func pinnedNotChecked() {
        let url = "git@github.com:you/my-extensions.git"
        let trusted = ExtensionSourceStatus(url: url, trusted: true)
        #expect(!ExtensionSources.shouldCheck(ExtensionSource(url: url, pin: "v1.2.0"), status: trusted, automatic: true))
        #expect(!ExtensionSources.shouldCheck(ExtensionSource(url: url, pin: "v1.2.0"), status: trusted, automatic: false))
    }

    @Test("a pin to a tag is honoured when adding, and changing the pin checks out a commit or a tag (§1, §4)")
    func pins() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        let c1 = try repo.commit("One")
        try repo.tag("v1")
        try repo.write("two.txt", "2\n")
        let c2 = try repo.commit("Two")
        try repo.write("three.txt", "3\n")
        let c3 = try repo.commit("Three")
        try repo.write("four.txt", "4\n")
        let c4 = try repo.commit("Four")

        // Added pinned to a tag.
        let pinned = ExtensionSource(url: repo.url, pin: "v1")
        let clone = try await repo.manager().clone(pinned)
        #expect(try repo.cloneHead() == c1)
        #expect(clone.status.commit == c1)
        #expect(!FileManager.default.fileExists(atPath: clone.folder.appendingPathComponent("two.txt").path))

        // Following the branch, then pinned to an older commit (not in the shallow clone), then to the tag.
        repo.manager().discard(pinned)
        let following = ExtensionSource(url: repo.url)
        var status = try await repo.manager().clone(following).status
        #expect(try repo.cloneHead() == c4)
        status = try await repo.manager().pin(following, to: c2, status)
        #expect(try repo.cloneHead() == c2)
        #expect(status.commit == c2)
        status = try await repo.manager().pin(following, to: "v1", status)
        #expect(try repo.cloneHead() == c1)
        status = try await repo.manager().pin(following, to: c3, status)
        #expect(try repo.cloneHead() == c3)
    }
}

// MARK: - §5 Removing

@Suite("ExtensionSourcesAcceptance: removing")
struct ExtensionSourcesAcceptanceRemoveTests {
    @Test("the clone goes to the Trash; the source and its folder leave the config; its preferences stay (§5)")
    func remove() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.bundle(at: "extensions/team")
        try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        config.extensionFolders = ["/Users/someone/my-own-extensions"]
        let source = ExtensionSource(url: repo.url, path: "extensions/team")
        _ = try await repo.addTrusted(source, config: &config)
        config.extensionPreferences["xsrcgreet"] = ["greeting": "hello there"]
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrchello"))

        let trash = ExtSrcAccTrash()
        try repo.manager(trash: trash.closure).trash(source)
        #expect(trash.trashed.map { $0.standardizedFileURL.path }
                == [ExtensionSources.cloneFolder(for: repo.url, root: repo.sources).standardizedFileURL.path],
                "the whole clone, through FileManager.trashItem (injected here)")

        ExtensionSources.remove(source, from: &config, root: repo.sources)
        #expect(config.extensionSources.isEmpty)
        #expect(config.extensionFolders == ["/Users/someone/my-own-extensions"], "only its folder left the load list")
        #expect(!ExtensionSources.isEnabled(source, in: config, root: repo.sources))
        #expect(config.extensionPreferences["xsrcgreet"] == ["greeting": "hello there"], "kept for a reinstall")

        // Adding it back finds them.
        ExtensionSources.enable(source, in: &config, root: repo.sources)
        #expect(config.extensionPreferences["xsrcgreet"] == ["greeting": "hello there"])
    }
}

// MARK: - §1 The config file

@Suite("ExtensionSourcesAcceptance: the config file")
struct ExtensionSourcesAcceptanceConfigTests {
    @Test("an old config without extensionSources decodes (§1)")
    func oldConfig() throws {
        let old = #"{ "extensionFolders": ["~/.config/allinoneime/extensions", "~/scripts"], "findRaycastScripts": false }"#
        let config = try JSONDecoder().decode(Config.self, from: Data(old.utf8))
        #expect(config.extensionSources.isEmpty)
        #expect(config.extensionFolders == ["~/.config/allinoneime/extensions", "~/scripts"])
        let empty = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(empty.extensionSources.isEmpty)
    }

    @Test("written back without the key while there are no sources (§1)")
    func noEmptyKey() throws {
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.json")
        try Config.default.write(to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("extensionSources"))

        var config = try Config.load(from: file)
        config.extensionSources = [ExtensionSource(url: "git@github.com:you/my-extensions.git")]
        try config.write(to: file)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("extensionSources"))
        config.extensionSources = []
        try config.write(to: file)
        #expect(!(try String(contentsOf: file, encoding: .utf8).contains("extensionSources")), "gone again once the last is removed")
    }

    @Test("a source's fields and defaults: branch and pin optional, pin null follows the branch, autoCheck on (§1)")
    func sourceFields() throws {
        let json = """
            { "extensionSources": [
                { "url": "ssh://git.example.com/team/MyExtensions", "path": "extensions/team", "branch": "main", "pin": null, "autoCheck": true },
                { "url": "git@github.com:you/my-extensions.git" },
                { "url": "https://github.com/you/pinned.git", "pin": "v1.2.0", "autoCheck": false }
            ] }
            """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.extensionSources.count == 3)
        let first = config.extensionSources[0], second = config.extensionSources[1], third = config.extensionSources[2]
        #expect(first.path == "extensions/team" && first.branch == "main" && first.pin == nil && first.autoCheck)
        #expect(second.path == nil || second.path == "")
        #expect(second.branch == nil && second.pin == nil && second.autoCheck)
        #expect(third.pin == "v1.2.0" && third.autoCheck == false)
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(again.extensionSources == config.extensionSources)
    }
}

// MARK: - §6 The command line

/// The app binary, run with a temporary config and sources folder.
enum ExtSrcAccCLI {
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let binary: String? = {
        if let given = ProcessInfo.processInfo.environment["ALLINONEIME_TEST_BINARY"], FileManager.default.isExecutableFile(atPath: given) {
            return given
        }
        let built = package.appendingPathComponent(".build/debug/AllInOneIME").path
        return FileManager.default.isExecutableFile(atPath: built) ? built : nil
    }()

    static var available: Bool { binary != nil }

    /// `AllInOneIME <arguments> --config <config> --sources-dir <sources>`.
    static func run(_ arguments: [String], config: URL, sources: URL) throws -> ExtSrcAcc.Ran {
        var env = ExtSrcAcc.isolatedEnvironment
        env["DYLD_LIBRARY_PATH"] = package.appendingPathComponent("ThirdParty/librime/dist/lib").path
        env["SHELL"] = "/usr/bin/false"  // the login shell isn't read: the user's startup files aren't run
        guard let binary else { throw ExtensionSourceError.git("test harness: no app binary built") }
        return try ExtSrcAcc.run(binary, arguments + ["--config", config.path, "--sources-dir", sources.path],
                                 environment: env, timeout: 180)
    }

    /// What of the user's own state these tests must never change.
    struct UserState: Equatable {
        var config: Data?
        var sources: [String]?

        static func now() -> UserState {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return UserState(config: try? Data(contentsOf: home.appendingPathComponent(".config/allinoneime/config.json")),
                             sources: try? FileManager.default.contentsOfDirectory(atPath: ExtensionSources.directory.path).sorted())
        }
    }

    static func writeConfig(_ config: Config, to file: URL) throws { try config.write(to: file) }
}

@Suite("ExtensionSourcesAcceptance: command line", .enabled(if: ExtSrcAccCLI.available, "needs the built app binary (swift build)"),
       .serialized)
struct ExtensionSourcesAcceptanceCLITests {
    @Test("--add-source clones, prints the review, enables it; --list-extensions lists it; --update-sources updates it (§6)")
    func addListUpdate() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user, "the user's config and sources are untouched") }
        let repo = try ExtSrcAccRepo()
        try repo.bundle(at: "extensions/team")
        let first = try repo.commit("First")
        let configFile = repo.root.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(ExtSrcAcc.emptyConfig(), to: configFile)

        let added = try ExtSrcAccCLI.run(["--add-source", repo.url], config: configFile, sources: repo.sources)
        #expect(added.status == 0, "\(added.output)\n\(added.errors)")
        for word in ["This source isn't signed: it will run programs from \(repo.url)", "xsrchello", "Say Hello", "Prints a greeting.",
                     "show", "xsrchello.sh", "greeting", String(first.prefix(7))] {
            #expect(added.output.contains(word), "the review lacks \(word):\n\(added.output)")
        }
        var config = try Config.load(from: configFile)
        #expect(config.extensionSources.map(\.url) == [repo.url])
        let source = try #require(config.extensionSources.first)
        #expect(ExtensionSources.isEnabled(source, in: config, root: repo.sources), "\(config.extensionFolders)")
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrchello"))
        let statuses = ExtensionSourceStatus.load(from: repo.sources.appendingPathComponent(ExtensionSources.statusFileName))
        #expect(ExtensionSources.isTrusted(source, statuses[repo.url]), "running --add-source is the consent")
        #expect(try repo.cloneHead() == first)

        let listed = try ExtSrcAccCLI.run(["--list-extensions"], config: configFile, sources: repo.sources)
        #expect(listed.status == 0)
        let line = listed.output.split(separator: "\n").first { $0.contains("xsrchello") }.map(String.init) ?? ""
        #expect(line.contains("show") && line.contains(repo.url), "name, output and source: \(listed.output)")

        let same = try ExtSrcAccCLI.run(["--update-sources"], config: configFile, sources: repo.sources)
        #expect(same.status == 0, "\(same.output)\n\(same.errors)")
        #expect(try repo.cloneHead() == first)

        try repo.bundle(at: "extensions/team", commands: [("xsrchello", "Say Hello", "Prints a greeting.", "show"),
                                                          ("xsrcbye", "Say Bye", "Prints bye.", "show")])
        let second = try repo.commit("Add the bye command")
        let updated = try ExtSrcAccCLI.run(["--update-sources"], config: configFile, sources: repo.sources)
        #expect(updated.status == 0, "\(updated.output)\n\(updated.errors)")
        #expect(updated.output.contains("Add the bye command"), "what changed is printed: \(updated.output)")
        #expect(try repo.cloneHead() == second)
        config = try Config.load(from: configFile)
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrcbye"))
        let relisted = try ExtSrcAccCLI.run(["--list-extensions"], config: configFile, sources: repo.sources)
        #expect(relisted.output.contains("xsrcbye"))
    }

    @Test("--list-extensions shows what's left out, with the reason (§6)")
    func listSkipped() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let extensions = folder.appendingPathComponent("extensions", isDirectory: true)
        try ExtSrcAcc.makeBundle(in: extensions.appendingPathComponent("good"), bundle: "xsrcgood", commands: [("xsrcgood", "Good", "d", "insert")])
        try ExtSrcAcc.write("{ not json", to: extensions.appendingPathComponent("broken/extension.json"))
        var config = ExtSrcAcc.emptyConfig()
        config.extensionFolders = [extensions.path]
        let configFile = folder.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(config, to: configFile)
        let listed = try ExtSrcAccCLI.run(["--list-extensions"], config: configFile, sources: folder.appendingPathComponent("Sources"))
        #expect(listed.status == 0)
        let good = listed.output.split(separator: "\n").first { $0.contains("xsrcgood") }.map(String.init) ?? ""
        #expect(good.contains("insert") && good.contains("extensions"), "name, output and folder: \(listed.output)")
        let broken = listed.output.split(separator: "\n").first { $0.contains("broken") }.map(String.init) ?? ""
        #expect(!broken.isEmpty && broken.count > "broken/extension.json".count + 10, "listed with a reason: \(listed.output)")
    }

    @Test("--add-source refuses http:// with a non-zero exit, and changes nothing (§1, §6)")
    func http() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let configFile = folder.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(ExtSrcAcc.emptyConfig(), to: configFile)
        let before = try Data(contentsOf: configFile)
        let sources = folder.appendingPathComponent("Sources")
        let ran = try ExtSrcAccCLI.run(["--add-source", "http://git.example.com/team/MyExtensions.git"], config: configFile, sources: sources)
        #expect(ran.status != 0)
        #expect(try Data(contentsOf: configFile) == before)
        #expect(ExtensionSources.bundleFolders(in: folder).isEmpty)
    }

    @Test("a git failure: non-zero, git's message, and the generic hint naming git ls-remote <url> (§2, §6)")
    func gitFailureHint() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let configFile = folder.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(ExtSrcAcc.emptyConfig(), to: configFile)
        let before = try Data(contentsOf: configFile)
        let url = "file://" + folder.appendingPathComponent("missing.git").path
        let sources = folder.appendingPathComponent("Sources")
        let own = try ExtSrcAcc.run("/usr/bin/git", ["clone", "--depth", "1", url, folder.appendingPathComponent("probe").path], in: folder)
        let fatal = own.errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("fatal:") }
        try #require(!fatal.isEmpty, "git printed: \(own.errors)")
        let ran = try ExtSrcAccCLI.run(["--add-source", url], config: configFile, sources: sources)
        #expect(ran.status != 0)
        let all = ran.output + ran.errors
        for line in fatal { #expect(all.contains(line), "git's own words, the cause included: \(line)\nshown: \(all)") }
        #expect(all.contains("This uses your own git and SSH setup"), "\(all)")
        #expect(all.contains("git ls-remote \(url)") && all.contains("works in Terminal"), "\(all)")
        #expect(try Data(contentsOf: configFile) == before)
        #expect(!FileManager.default.fileExists(atPath: ExtensionSources.cloneFolder(for: url, root: sources).path))
    }

    @Test("--update-sources failing: the generic hint and the source's authHint under the error (§2, §6)")
    func updateFailureAuthHint() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        try repo.commit("First")
        let configFile = repo.root.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(ExtSrcAcc.emptyConfig(), to: configFile)
        let added = try ExtSrcAccCLI.run(["--add-source", repo.url], config: configFile, sources: repo.sources)
        try #require(added.status == 0, "\(added.errors)")
        var config = try Config.load(from: configFile)
        config.extensionSources[0].authHint = "Sign in to the team network first, then retry."
        try config.write(to: configFile)
        try FileManager.default.moveItem(at: repo.bare, to: repo.bare.deletingLastPathComponent().appendingPathComponent("moved.git"))

        let ran = try ExtSrcAccCLI.run(["--update-sources"], config: configFile, sources: repo.sources)
        #expect(ran.status != 0)
        let all = ran.output + ran.errors
        #expect(all.contains("This uses your own git and SSH setup") && all.contains("git ls-remote \(repo.url)"), "\(all)")
        #expect(all.contains("Sign in to the team network first, then retry."), "\(all)")
        #expect(ExtSrcAcc.loadedNames(try Config.load(from: configFile)).contains("xsrchello"), "the old clone still loads")
    }

    /// A team hands out a config entry with its sign-in hint; the user runs `--add-source` for it, and the clone fails.
    @Test("--add-source failing for a source already in the config shows its authHint (§2)")
    func addFailureAuthHint() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let folder = try ExtSrcAcc.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = "file://" + folder.appendingPathComponent("missing.git").path
        var config = ExtSrcAcc.emptyConfig()
        config.extensionSources = [ExtensionSource(url: url, authHint: "Sign in to the team network first, then retry.")]
        let configFile = folder.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(config, to: configFile)
        let ran = try ExtSrcAccCLI.run(["--add-source", url], config: configFile, sources: folder.appendingPathComponent("Sources"))
        #expect(ran.status != 0)
        #expect((ran.output + ran.errors).contains("Sign in to the team network first, then retry."), "\(ran.errors)")
    }

    @Test("several bundles: --add-source asks for --path and changes nothing; with --path it adds that one (§1, §6)")
    func severalBundles() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let repo = try ExtSrcAccRepo()
        try repo.bundle(at: "alpha-tools", bundle: "xsrcbunda", commands: [("xsrcaa", "A", "d", "show")])
        try repo.bundle(at: "beta-tools", bundle: "xsrcbundb", commands: [("xsrcbb", "B", "d", "show")])
        try repo.commit("Two bundles")
        let configFile = repo.root.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(ExtSrcAcc.emptyConfig(), to: configFile)
        let before = try Data(contentsOf: configFile)

        let ambiguous = try ExtSrcAccCLI.run(["--add-source", repo.url], config: configFile, sources: repo.sources)
        #expect(ambiguous.status != 0)
        let all = ambiguous.output + ambiguous.errors
        #expect(all.contains("alpha-tools") && all.contains("beta-tools"), "the choices are listed: \(all)")
        #expect(try Data(contentsOf: configFile) == before)
        #expect(ExtensionSources.bundleFolders(in: repo.sources).isEmpty, "no clone left behind")

        let picked = try ExtSrcAccCLI.run(["--add-source", repo.url, "--path", "beta-tools"], config: configFile, sources: repo.sources)
        #expect(picked.status == 0, "\(picked.errors)")
        let config = try Config.load(from: configFile)
        #expect(ExtSrcAcc.loadedNames(config) == ["xsrcbb"])
    }

    @Test("--add-source --pin stays on the tag; --update-sources leaves a pinned source alone (§4, §6)")
    func pinned() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        let c1 = try repo.commit("One")
        try repo.tag("v1")
        try repo.write("two.txt", "2\n")
        try repo.commit("Two")
        let configFile = repo.root.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(ExtSrcAcc.emptyConfig(), to: configFile)
        let added = try ExtSrcAccCLI.run(["--add-source", repo.url, "--pin", "v1"], config: configFile, sources: repo.sources)
        #expect(added.status == 0, "\(added.errors)")
        #expect(try repo.cloneHead() == c1)
        #expect(try Config.load(from: configFile).extensionSources.first?.pin == "v1")
        try repo.write("three.txt", "3\n")
        try repo.commit("Three")
        let updated = try ExtSrcAccCLI.run(["--update-sources"], config: configFile, sources: repo.sources)
        #expect(updated.status == 0)
        #expect(try repo.cloneHead() == c1, "pinned: not updated")
    }

    @Test("--update-sources doesn't fetch a source that was never reviewed and enabled (§3)")
    func untrustedSkipped() throws {
        let user = ExtSrcAccCLI.UserState.now()
        defer { #expect(ExtSrcAccCLI.UserState.now() == user) }
        let repo = try ExtSrcAccRepo()
        try repo.bundle()
        try repo.commit("First")
        var config = ExtSrcAcc.emptyConfig()
        config.extensionSources = [ExtensionSource(url: repo.url)]  // written by hand: never reviewed
        let configFile = repo.root.appendingPathComponent("config.json")
        try ExtSrcAccCLI.writeConfig(config, to: configFile)
        let before = try Data(contentsOf: configFile)
        _ = try ExtSrcAccCLI.run(["--update-sources"], config: configFile, sources: repo.sources)
        #expect(!FileManager.default.fileExists(atPath: ExtensionSources.cloneFolder(for: repo.url, root: repo.sources).path))
        #expect(try Data(contentsOf: configFile) == before, "not enabled behind the user's back")
    }
}

// MARK: - Integration: the whole life of a source with the real git

@Suite("ExtensionSourcesAcceptance: integration")
struct ExtensionSourcesAcceptanceIntegrationTests {
    @Test("add, review, enable, new commit, check, update, force push, re-clone, pin, remove")
    func lifecycle() async throws {
        let repo = try ExtSrcAccRepo()
        try repo.write("README.md", "# My extensions\n")
        try repo.bundle(at: "extensions/team")
        let c1 = try repo.commit("First", date: "2026-10-01T09:30:00-07:00")
        try repo.tag("v1")
        let trash = ExtSrcAccTrash()
        let manager = repo.manager(trash: trash.closure)
        var config = ExtSrcAcc.emptyConfig()

        // Add: auto-detected path, review, nothing loaded until Enable.
        var source = ExtensionSource(url: try ExtensionSources.validate(repo.url))
        let clone = try await manager.clone(source)
        source.path = try ExtensionSources.resolveBundlePath(nil, in: clone.folder)
        let review = ExtensionSourceReview.make(bundleFolder: ExtensionSources.bundleFolder(for: source, root: repo.sources),
                                                path: source.path ?? "", url: source.url, commit: clone.status.commit,
                                                commitDate: clone.status.commitDate, config: config)
        #expect(review.commands.map(\.name) == ["xsrchello"])
        #expect(review.summary.joined().contains(String(c1.prefix(7))))
        #expect(!ExtSrcAcc.loadedNames(config).contains("xsrchello"))
        ExtensionSources.enable(source, in: &config, root: repo.sources)
        var status = clone.status
        status.trusted = true
        #expect(ExtSrcAcc.loadedNames(config).contains("xsrchello"))

        // A new commit upstream: check, then update.
        try repo.bundle(at: "extensions/team", commands: [("xsrchello", "Say Hello Again", "Prints a greeting.", "show")])
        let c2 = try repo.commit("Retitle hello", author: "Dana Example <dana@example.com>", date: "2026-10-05T08:00:00-07:00")
        #expect(ExtensionSources.shouldCheck(source, status: status, automatic: true))
        status = try await manager.check(source, status)
        #expect(status.updates.map(\.subject) == ["Retitle hello"])
        #expect(status.updates.first?.author == "Dana Example")
        #expect(try repo.cloneHead() == c1)
        status = try await manager.update(source, status)
        #expect(try repo.cloneHead() == c2)
        let titles = ExtensionStore.load(ExtensionStore.folders(config, found: []), cache: ExtensionCache()).commands.map(\.title)
        #expect(titles.contains("Say Hello Again"), "the loader reads the updated files: \(titles)")

        // A force push: not a fast-forward; re-clone.
        try repo.write("extensions/team/extra.txt", "x\n")
        let rewritten = try repo.commit("Retitle hello (rewritten)", amend: true, force: true)
        status = try await manager.check(source, status)
        #expect(!status.fastForward)
        await #expect(throws: ExtensionSourceError.notFastForward) { _ = try await manager.update(source, status) }
        status = try await manager.reclone(source, status)
        #expect(try repo.cloneHead() == rewritten)
        #expect(status.trusted)

        // Pin to the tag: no longer checked.
        source.pin = "v1"
        status = try await manager.pin(source, to: "v1", status)
        #expect(try repo.cloneHead() == c1)
        #expect(!ExtensionSources.shouldCheck(source, status: status, automatic: false))

        // Remove: trashed, out of the config, preferences kept.
        config.extensionPreferences["xsrcgreet"] = ["greeting": "hey"]
        try manager.trash(source)
        ExtensionSources.remove(source, from: &config, root: repo.sources)
        #expect(trash.trashed.count == 1)
        #expect(config.extensionSources.isEmpty && config.extensionFolders.isEmpty)
        #expect(config.extensionPreferences["xsrcgreet"] == ["greeting": "hey"])
    }
}
