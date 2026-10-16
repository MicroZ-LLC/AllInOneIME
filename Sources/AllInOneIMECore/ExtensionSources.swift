import CryptoKit
import Foundation

// Extension sources: script-extension bundles (docs/extensions.md §6) installed from a Git repository and updated from
// there (docs/extensions.md §10, README "Extension sources").
//
// - Adding (`ExtensionSourceManager.clone`): a shallow clone with the user's own git (/usr/bin/git, in the login shell's
//   environment: their SSH keys, agent, ~/.ssh/config and credential helpers do any signing in; the app knows nothing of
//   it), into a temporary folder under `ExtensionSources.directory`, moved into place when it's done. Nothing in it is
//   loaded or run until the user has seen what it holds (`ExtensionSourceReview`) and clicked Enable (`enable`): then the
//   bundle's folder joins `Config.extensionFolders`, and the source is trusted (`ExtensionSourceStatus.trusted`, with its
//   address).
// - Updates (`check`, `update`): `git fetch`, and what's new listed; only Update moves the clone, by a fast-forward
//   (never a merge), with hooks off. A pinned source stays where it is.
// - Removing: the clone goes to the Trash, the source and its folder leave the config; the bundle's preferences stay.
//
// Where things are: the sources the user added are in the config (`Config.extensionSources`); what is known of each
// clone (trusted or not, its commit, the last check and error, what's new) is in `sources.json` next to the clones
// (`ExtensionSourceStatus.load`). A clone's folder is named from the address (`folderName`).

/// A Git repository extension bundles come from (`Config.extensionSources`).
///
///     { "url": "git@github.com:you/my-extensions.git", "path": "extensions/team", "branch": "main", "pin": null,
///       "autoCheck": true }
public struct ExtensionSource: Codable, Hashable, Sendable {
    /// `ssh://…`, `git@host:…`, `https://…`, or `file://…` (`ExtensionSources.validate`).
    public var url: String
    /// The bundle's folder in the repository ("" or nil: the root, or the one folder with an `extension.json`).
    public var path: String?
    /// The branch followed (nil: the repository's default).
    public var branch: String?
    /// A tag or commit the clone stays on (nil: follow the branch). A pinned source isn't checked for updates.
    public var pin: String?
    /// Checked for updates by itself (once a day, and soon after the input method starts); it only ever notes them.
    public var autoCheck: Bool
    /// Shown under a git error: the user's own reminder of how this host is signed in to.
    public var authHint: String?

    public init(url: String, path: String? = nil, branch: String? = nil, pin: String? = nil, autoCheck: Bool = true,
                authHint: String? = nil) {
        self.url = url
        self.path = path
        self.branch = branch
        self.pin = pin
        self.autoCheck = autoCheck
        self.authHint = authHint
    }

    private enum CodingKeys: String, CodingKey { case url, path, branch, pin, autoCheck, authHint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        func text(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
        }
        path = text(.path)
        branch = text(.branch)
        pin = text(.pin)
        autoCheck = (try? c.decodeIfPresent(Bool.self, forKey: .autoCheck)).flatMap { $0 } ?? true
        authHint = text(.authHint)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(branch, forKey: .branch)
        try c.encode(pin, forKey: .pin)  // null: following the branch (the key stays discoverable)
        try c.encode(autoCheck, forKey: .autoCheck)
        try c.encodeIfPresent(authHint, forKey: .authHint)
    }

    /// `Config.extensionSources` as read: an entry without an address is left out, not the whole file; an address twice,
    /// once.
    static func decodeAll<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, forKey key: Key) -> [ExtensionSource] {
        let sources = (try? c.decodeIfPresent([Lenient].self, forKey: key)).flatMap { $0 }?.compactMap(\.source) ?? []
        var seen = Set<String>()
        return sources.filter { seen.insert($0.url).inserted }
    }

    private struct Lenient: Decodable {
        var source: ExtensionSource?
        init(from decoder: Decoder) throws { source = try? ExtensionSource(from: decoder) }
    }

    /// The repository's name: "my-extensions" for "git@github.com:you/my-extensions.git".
    public var repositoryName: String { ExtensionSources.repositoryName(url) }
}

/// A commit of what's new upstream (`git log`).
public struct ExtensionSourceCommit: Codable, Equatable, Hashable, Sendable {
    public var sha: String
    public var author: String
    public var date: Date?
    public var subject: String

    public init(sha: String, author: String, date: Date?, subject: String) {
        self.sha = sha
        self.author = author
        self.date = date
        self.subject = subject
    }

    public var shortSHA: String { String(sha.prefix(7)) }
}

/// What is known of a source's clone (`sources.json` next to the clones, by address).
public struct ExtensionSourceStatus: Codable, Equatable, Sendable {
    /// The address the clone was made from, and trusted for when Enable was clicked.
    public var url: String
    /// Reviewed and enabled once: its updates don't need another review.
    public var trusted: Bool
    /// The branch followed, as the clone found it (the default one when none was asked for).
    public var branch: String?
    /// The commit the clone is at, and its date.
    public var commit: String?
    public var commitDate: Date?
    /// When a check last worked, and why the last git call didn't (git's own words; nil: it did).
    public var checked: Date?
    public var error: String?
    /// What's new upstream since `commit`, newest first (empty: up to date), and its newest commit.
    public var updates: [ExtensionSourceCommit]
    public var remote: String?
    /// `remote` is a descendant of `commit`: Update can fast-forward. False after a force push: Re-clone instead.
    public var fastForward: Bool

    public init(url: String, trusted: Bool = false, branch: String? = nil, commit: String? = nil, commitDate: Date? = nil,
                checked: Date? = nil, error: String? = nil, updates: [ExtensionSourceCommit] = [], remote: String? = nil,
                fastForward: Bool = true) {
        self.url = url
        self.trusted = trusted
        self.branch = branch
        self.commit = commit
        self.commitDate = commitDate
        self.checked = checked
        self.error = error
        self.updates = updates
        self.remote = remote
        self.fastForward = fastForward
    }

    public var shortCommit: String? { commit.map { String($0.prefix(7)) } }

    /// The statuses in `file` (none when it's missing or can't be read), by address.
    public static func load(from file: URL) -> [String: ExtensionSourceStatus] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: ExtensionSourceStatus].self, from: data)) ?? [:]
    }

    public static func save(_ statuses: [String: ExtensionSourceStatus], to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(statuses).write(to: file, options: .atomic)
    }
}

public enum ExtensionSourceError: Error, LocalizedError, Equatable, Sendable {
    /// Not an `ssh://`, `git@host:`, `https://` or `file://` address.
    case invalidURL(String)
    /// `http://`: the code would travel in the clear.
    case notHTTPS
    /// /usr/bin/git without Xcode or the command line tools (it would only offer to install them).
    case gitNotInstalled
    /// A git command failed: its last meaningful lines.
    case git(String)
    case timedOut(TimeInterval)
    /// The repository (or the folder named) has no `extension.json`.
    case noBundle(String?)
    /// Several folders have an `extension.json`: which one is meant has to be picked (`path`).
    case severalBundles([String])
    case alreadyAdded
    case notAdded
    /// Not reviewed and enabled yet: `--add-source` or Settings first.
    case notTrusted
    /// The new commits don't follow the clone's (a force push): Re-clone.
    case notFastForward

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url): return "Not a Git address (ssh://, git@host:, https:// or file://): \(url)"
        case .notHTTPS: return "Plain http:// isn't used: use https:// or ssh"
        case .gitNotInstalled: return "git needs the Command Line Tools: run xcode-select --install in Terminal"
        case let .git(message): return message
        case let .timedOut(seconds): return "git didn't finish within \(Int(seconds)) seconds"
        case let .noBundle(path): return path.map { "\($0) has no extension.json" } ?? "The repository has no extension.json"
        case let .severalBundles(paths): return "Several bundles: pick one of " + paths.map { $0.isEmpty ? "(root)" : $0 }.joined(separator: ", ")
        case .alreadyAdded: return "This source is already added"
        case .notAdded: return "No such source is added"
        case .notTrusted: return "Not reviewed and enabled yet"
        case .notFastForward: return "The repository's history changed (a force push): re-clone it"
        }
    }
}

/// What a git command printed.
public struct GitResult: Equatable, Sendable {
    public var status: Int32
    public var output: String
    public var errors: String

    public init(status: Int32, output: String = "", errors: String = "") {
        self.status = status
        self.output = output
        self.errors = errors
    }
}

/// Runs git (tests pass their own, or the real one against local bare repositories).
public protocol GitRunning: Sendable {
    /// `git <arguments>` in `directory` (nil: the sources folder's parent is fine; nothing depends on it).
    func run(_ arguments: [String], in directory: URL?) async throws -> GitResult
}

/// The pure parts: addresses, folder names, git's arguments and environment, finding bundles, the log, the schedule.
public enum ExtensionSources {
    /// Where the clones are: ~/Library/Application Support/AllInOneIME/Sources/<folderName>/.
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AllInOneIME/Sources",
                                                                              isDirectory: true)
    }
    public static let statusFileName = "sources.json"
    /// Seconds a git call may take.
    public static let timeout: TimeInterval = 60
    /// When the input method checks by itself: a while after it starts, then once a day while it runs.
    public static let firstCheckDelay: TimeInterval = 30
    public static let checkInterval: TimeInterval = 24 * 3600
    /// How much history a check fetches: more new commits than this can't be told from a force push (Re-clone).
    public static let fetchDepth = 100
    /// Every git call: no hooks run, whatever the repository or the user's config says.
    public static let noHooks = ["-c", "core.hooksPath=/dev/null"]

    // MARK: Addresses

    /// `text` trimmed, if it's an address git is used with here: `ssh://host/…`, `user@host:path`, `https://host/…`,
    /// `file:///…`. `http://` is refused; so is anything git would read as an option or that has spaces.
    public static func validate(_ text: String) throws -> String {
        let url = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = url.lowercased()
        if lower.hasPrefix("http://") { throw ExtensionSourceError.notHTTPS }
        guard !url.isEmpty, !url.hasPrefix("-"), !url.contains(where: { $0.isWhitespace || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }) else {
            throw ExtensionSourceError.invalidURL(url)
        }
        if lower.hasPrefix("ssh://") || lower.hasPrefix("https://") {
            guard let parsed = URL(string: url), let host = parsed.host, !host.isEmpty, parsed.path.count > 1 else {
                throw ExtensionSourceError.invalidURL(url)
            }
            return url
        }
        if lower.hasPrefix("file://") {
            guard let parsed = URL(string: url), parsed.isFileURL, parsed.path.count > 1 else { throw ExtensionSourceError.invalidURL(url) }
            return url
        }
        // scp-like: user@host:path (no "://", no "//" right after the colon).
        if !lower.contains("://"), let at = url.firstIndex(of: "@"), at > url.startIndex,
           let colon = url[at...].firstIndex(of: ":"), url.index(after: at) < colon, url.index(after: colon) < url.endIndex,
           !url[url.index(after: colon)...].hasPrefix("/"),
           url[..<colon].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-@".contains($0)) }) {
            return url
        }
        throw ExtensionSourceError.invalidURL(url)
    }

    /// The repository's name in an address: its last part, without ".git" ("my-extensions").
    public static func repositoryName(_ url: String) -> String {
        var path = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = path.lastIndex(of: ":"), !path.contains("://") { path = String(path[path.index(after: colon)...]) }
        while path.hasSuffix("/") { path.removeLast() }
        var name = path.split(separator: "/").last.map(String.init) ?? path
        if name.lowercased().hasSuffix(".git") { name.removeLast(4) }
        return name
    }

    /// The clone's folder: the repository's name (letters, digits, "-", "_", "."; at most 40) and a short hash of the
    /// address, so two repositories of one name don't meet: "my-extensions-1a2b3c4d".
    public static func folderName(for url: String) -> String {
        let cleaned = String(repositoryName(url).map { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) ? $0 : "-" }
            .drop { $0 == "." || $0 == "-" }.prefix(40))
        let hash = SHA256.hash(data: Data(url.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).prefix(4)
            .map { String(format: "%02x", $0) }.joined()
        return (cleaned.isEmpty ? "source" : cleaned) + "-" + hash
    }

    /// The clone of `url` under `root`.
    public static func cloneFolder(for url: String, root: URL = directory) -> URL {
        root.appendingPathComponent(folderName(for: url), isDirectory: true)
    }

    /// The bundle's folder: the clone's, then `path` in it.
    public static func bundleFolder(for source: ExtensionSource, root: URL = directory) -> URL {
        let clone = cloneFolder(for: source.url, root: root)
        let parts = (source.path ?? "").split(separator: "/").filter { $0 != "." }
        return parts.isEmpty ? clone : clone.appendingPathComponent(parts.joined(separator: "/"), isDirectory: true)
    }

    /// A folder's path as the load list is compared: "~" expanded, no trailing "/" (not resolved on disk: a folder
    /// gone compares the same).
    public static func comparable(_ path: String) -> String {
        var path = (path as NSString).expandingTildeInPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// The bundle's folder as `Config.extensionFolders` has it ("~/…").
    public static func loadPath(for source: ExtensionSource, root: URL = directory) -> String {
        ExtensionStore.abbreviated(bundleFolder(for: source, root: root).path)
    }

    // MARK: Git

    /// The environment git runs in: the input method's own with the login shell's PATH (`base`: `ShellEnvironment
    /// .current`), the login shell's SSH agent if it has one (`login`), no prompts (`GIT_TERMINAL_PROMPT=0`), and ssh in
    /// batch mode added to the user's own ssh command (their `GIT_SSH_COMMAND`, else `core.sshCommand`, else ssh), so a
    /// key that needs a passphrase fails instead of asking. Variables that would point git at another repository are
    /// dropped.
    public static func gitEnvironment(base: [String: String], login: [String: String] = [:],
                                      sshCommand: String? = nil) -> [String: String] {
        var env = base
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"] {
            env[key] = nil
        }
        if let agent = login["SSH_AUTH_SOCK"], !agent.isEmpty { env["SSH_AUTH_SOCK"] = agent }
        if env["HOME"]?.isEmpty != false { env["HOME"] = NSHomeDirectory() }
        env["GIT_TERMINAL_PROMPT"] = "0"
        let own = [env["GIT_SSH_COMMAND"], login["GIT_SSH_COMMAND"], sshCommand].compactMap { $0 }.first { !$0.isEmpty }
        // GIT_SSH names a program, to which no option can be added: left as the user has it.
        if own != nil || env["GIT_SSH"]?.isEmpty != false {
            env["GIT_SSH_COMMAND"] = (own ?? "ssh") + " -o BatchMode=yes"
        }
        return env
    }

    /// `git clone`: shallow, the one branch (`branch`, else the default), no tags, into `folder`.
    public static func cloneArguments(url: String, branch: String?, into folder: URL) -> [String] {
        noHooks + ["clone", "--depth", "1", "--single-branch", "--no-tags"] + (branch.map { ["--branch", $0] } ?? [])
            + ["--", url, folder.path]
    }

    /// `git fetch` of `ref` (a branch, a tag or a commit; "HEAD": the default branch) from origin, `depth` deep.
    public static func fetchArguments(_ ref: String, depth: Int) -> [String] {
        noHooks + ["fetch", "--depth", String(depth), "--no-tags", "origin", ref]
    }

    /// `git log` of `range`, one line a commit: sha, author, date, subject, split by a unit separator.
    public static func logArguments(_ range: String, limit: Int = 100) -> [String] {
        noHooks + ["log", "-n", String(limit), "--format=%H%x1f%an%x1f%aI%x1f%s", range]
    }

    /// The commits `logArguments` printed (lines that don't parse are left out).
    public static func parseLog(_ output: String) -> [ExtensionSourceCommit] {
        let iso = ISO8601DateFormatter()
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, fields[0].count >= 7, fields[0].allSatisfy(\.isHexDigit) else { return nil }
            return ExtensionSourceCommit(sha: fields[0], author: fields[1], date: iso.date(from: fields[2]),
                                         subject: fields[3...].joined(separator: "\u{1F}"))
        }
    }

    /// What a failed git call says: its last lines with words (at most three), "hint:" lines left out.
    public static func gitMessage(_ result: GitResult) -> String {
        let text = result.errors.isEmpty ? result.output : result.errors
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains(where: \.isLetter) && !$0.lowercased().hasPrefix("hint:") }
        let message = lines.suffix(3).joined(separator: "\n")
        return message.isEmpty ? "git failed (exit status \(result.status))" : message
    }

    // MARK: Bundles

    /// The folders in `clone` holding an `extension.json`, relative to it ("" for the root), sorted; not inside hidden
    /// folders (.git) or node_modules, at most `depth` levels down.
    public static func bundleFolders(in clone: URL, depth: Int = 4) -> [String] {
        let fm = FileManager.default
        var found: [String] = []
        func visit(_ folder: URL, _ relative: String, _ level: Int) {
            if fm.fileExists(atPath: folder.appendingPathComponent(ExtensionBundle.manifestName).path) { found.append(relative) }
            guard level < depth, let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names.sorted() where !name.hasPrefix(".") && name != "node_modules" {
                let child = folder.appendingPathComponent(name)
                var isFolder: ObjCBool = false
                // Real folders only: a link could lead out of the clone.
                guard (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
                      fm.fileExists(atPath: child.path, isDirectory: &isFolder), isFolder.boolValue else { continue }
                visit(child, relative.isEmpty ? name : relative + "/" + name, level + 1)
            }
        }
        visit(clone, "", 0)
        return found
    }

    /// The bundle path to use in `clone`: `path` if it has an `extension.json`, else the only folder that has one.
    public static func resolveBundlePath(_ path: String?, in clone: URL) throws -> String {
        if let path, !path.isEmpty {
            let cleaned = path.split(separator: "/").joined(separator: "/")
            guard !cleaned.split(separator: "/").contains(".."),
                  FileManager.default.fileExists(atPath: clone.appendingPathComponent(cleaned).appendingPathComponent(ExtensionBundle.manifestName).path)
            else { throw ExtensionSourceError.noBundle(path) }
            return cleaned
        }
        let found = bundleFolders(in: clone)
        switch found.count {
        case 0: throw ExtensionSourceError.noBundle(nil)
        case 1: return found[0]
        default: throw ExtensionSourceError.severalBundles(found)
        }
    }

    // MARK: Schedule

    /// Whether `source` is checked now: never when pinned; by itself (`automatic`) only with `autoCheck`; and only once
    /// it's cloned and trusted.
    public static func shouldCheck(_ source: ExtensionSource, status: ExtensionSourceStatus?, automatic: Bool) -> Bool {
        guard source.pin == nil, let status, status.trusted, status.url == source.url else { return false }
        return !automatic || source.autoCheck
    }

    /// Whether `status` is the trusted clone of `source` (reviewed and enabled from this very address).
    public static func isTrusted(_ source: ExtensionSource, _ status: ExtensionSourceStatus?) -> Bool {
        status?.trusted == true && status?.url == source.url
    }

    // MARK: Config

    /// Enable: the source is in the config (replacing one of the same address), and its bundle's folder in the load list.
    public static func enable(_ source: ExtensionSource, in config: inout Config, root: URL = directory) {
        if let index = config.extensionSources.firstIndex(where: { $0.url == source.url }) {
            config.extensionSources[index] = source
        } else {
            config.extensionSources.append(source)
        }
        if !isEnabled(source, in: config, root: root) { config.extensionFolders.append(loadPath(for: source, root: root)) }
    }

    /// Remove: the source and its bundle's folder leave the config; its bundle's preferences stay (adding it back finds them).
    public static func remove(_ source: ExtensionSource, from config: inout Config, root: URL = directory) {
        config.extensionSources.removeAll { $0.url == source.url }
        let full = comparable(bundleFolder(for: source, root: root).path)
        config.extensionFolders.removeAll { comparable($0) == full }
    }

    /// Whether the source's bundle is in the load list.
    public static func isEnabled(_ source: ExtensionSource, in config: Config, root: URL = directory) -> Bool {
        let full = comparable(bundleFolder(for: source, root: root).path)
        return config.extensionFolders.contains { comparable($0) == full }
    }
}

/// What the user sees before Enable: the bundle, every command (what it's called, what it does, how it answers, what
/// it runs), its preferences, where it's from and at which commit, and what wouldn't load or is hidden by a command
/// that has the name already (the extension rules: built-in, plugin, custom, then extensions in order).
public struct ExtensionSourceReview: Equatable, Sendable {
    public struct Command: Equatable, Sendable {
        public var name: String
        public var title: String
        public var description: String?
        public var output: ScriptCommand.Output
        public var background: Bool
        /// What it runs: the interpreter, if any, and the script, as a path in the bundle ("/usr/bin/env python3 bin/x.py").
        public var program: String
        /// Why it won't be offered (another command has its name), nil when it will.
        public var hidden: ScriptCommand.Problem?
    }

    public var url: String
    public var commit: String?
    public var commitDate: Date?
    /// The bundle's folder in the repository ("" for the root).
    public var path: String
    public var bundle: ExtensionBundle?
    /// Why the bundle as a whole can't be loaded (no or bad `extension.json`, another bundle has its name).
    public var problem: ScriptCommand.Problem?
    public var commands: [Command]
    /// Its entries that can't be loaded, and why (a script missing or not runnable, a name twice).
    public var skipped: [ExtensionStore.Skipped]

    public var preferences: [ExtensionBundle.Preference] { bundle?.preferences ?? [] }
    /// Every program it runs, once each.
    public var programs: [String] {
        var seen = Set<String>()
        return commands.map(\.program).filter { seen.insert($0).inserted }
    }

    /// The bundle in `bundleFolder` as it would load next to what `config` loads now (`found`: the Raycast folders
    /// Spotlight found; `plugins`: the installed plugins).
    public static func make(bundleFolder: URL, path: String, url: String, commit: String?, commitDate: Date?, config: Config,
                            plugins: [InstalledPlugin] = [], found: [String] = []) -> ExtensionSourceReview {
        let folder = bundleFolder.standardizedFileURL
        let prefix = folder.path + "/"
        var folders = ExtensionStore.folders(config, found: found).filter { $0.url.standardizedFileURL.path != folder.path }
        folders.append(ExtensionStore.Folder(path: folder.path, found: false))
        let index = ExtensionStore.load(folders, cache: ExtensionCache())
        let bundle = index.bundles.first { $0.folder.standardizedFileURL.path == folder.path }
        let mine = index.skipped.filter { $0.file.standardizedFileURL.path.hasPrefix(prefix) }
        let manifest = folder.appendingPathComponent(ExtensionBundle.manifestName).path
        let problem = bundle == nil ? mine.first { $0.file.standardizedFileURL.path == manifest }?.problem ?? .badBundle(.notJSON) : nil
        let enabled = index.enabled(config.disabledExtensions)
        let hidden = Dictionary(AllInOneIMECore.Command.hiddenScripts(enabled, custom: config.customCommands, plugins: plugins)
            .map { ($0.script.id, ScriptCommand.Problem.nameTaken($0.script.name, by: $0.owner)) }, uniquingKeysWith: { (a: ScriptCommand.Problem, _: ScriptCommand.Problem) in a })
        let commands = index.commands.filter { $0.file.standardizedFileURL.path.hasPrefix(prefix) }.map { command in
            let program = command.launch.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }.joined(separator: " ")
            let off = bundle.map { config.disabledExtensions.contains($0.name) } == true || config.disabledExtensions.contains(command.id)
            return Command(name: command.name, title: command.title, description: command.description, output: command.output,
                           background: command.background, program: program, hidden: off ? nil : hidden[command.id])
        }
        return ExtensionSourceReview(url: url, commit: commit, commitDate: commitDate, path: path, bundle: bundle, problem: problem,
                                     commands: commands, skipped: bundle == nil ? [] : mine)
    }

    /// The review as text, for `--add-source`.
    public var summary: [String] {
        var lines: [String] = []
        lines.append("source:      \(url)" + (path.isEmpty ? "" : " (\(path))"))
        if let commit {
            let date = commitDate.map { " " + ISO8601DateFormatter().string(from: $0) } ?? ""
            lines.append("commit:      \(commit.prefix(7))\(date)")
        }
        lines.append("WARNING:     This source isn't signed: it will run programs from \(url).")
        if let problem { lines.append("bundle:      can't be loaded: \(problem)") }
        if let bundle {
            lines.append("bundle:      \(bundle.name) — \(bundle.title)" + (bundle.version.map { " \($0)" } ?? "") + (bundle.author.map { " by \($0)" } ?? ""))
            if let description = bundle.description { lines.append("             \(description)") }
        }
        for command in commands {
            let hidden = command.hidden.map { "  [hidden: \($0)]" } ?? ""
            lines.append("command:     @\(command.name) — \(command.title) (\(command.output.rawValue)\(command.background ? ", background" : ""))\(hidden)")
            if let description = command.description { lines.append("             \(description)") }
            lines.append("  runs:      \(command.program)")
        }
        for preference in preferences {
            lines.append("preference:  \(preference.name) (\(preference.kind.rawValue)\(preference.required ? ", required" : ""))")
        }
        for skipped in skipped { lines.append("skipped:     \(skipped.file.lastPathComponent): \(skipped.problem)") }
        return lines
    }
}

/// The git work on the clones: cloning, checking, updating, pinning, re-cloning, removing. Every call goes through
/// `git` (the real one, or a test's).
public struct ExtensionSourceManager: Sendable {
    public var root: URL
    public var git: any GitRunning
    public var now: @Sendable () -> Date
    /// Moves a removed source's clone away: to the Trash (tests delete it instead).
    public var trashItem: @Sendable (URL) throws -> Void

    public init(root: URL = ExtensionSources.directory, git: any GitRunning, now: @escaping @Sendable () -> Date = { Date() },
                trashItem: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.root = root
        self.git = git
        self.now = now
        self.trashItem = trashItem
    }

    public var statusFile: URL { root.appendingPathComponent(ExtensionSources.statusFileName) }

    /// The statuses as kept, and keeping them.
    public func statuses() -> [String: ExtensionSourceStatus] { ExtensionSourceStatus.load(from: statusFile) }
    public func save(_ statuses: [String: ExtensionSourceStatus]) throws { try ExtensionSourceStatus.save(statuses, to: statusFile) }

    /// A clone made for adding: where it is, what it found, and the bundle paths in it.
    public struct Clone: Equatable, Sendable {
        public var folder: URL
        public var status: ExtensionSourceStatus
        public var bundles: [String]
    }

    /// Clones `source` (shallow; its pin checked out) into a temporary folder, then moves it into place as the source's
    /// folder (one left from before, never enabled, is replaced). Not trusted, not enabled: nothing in it is loaded.
    public func clone(_ source: ExtensionSource) async throws -> Clone {
        let url = try ExtensionSources.validate(source.url)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = ExtensionSources.cloneFolder(for: url, root: root)
        let temporary = root.appendingPathComponent(".tmp-\(destination.lastPathComponent)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try await call(ExtensionSources.cloneArguments(url: url, branch: source.branch, into: temporary), in: root)
            if let pin = source.pin { try await checkout(pin, in: temporary) }
            var status = ExtensionSourceStatus(url: url, checked: now())
            let branch = try await call(ExtensionSources.noHooks + ["rev-parse", "--abbrev-ref", "HEAD"], in: temporary).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            status.branch = branch == "HEAD" || branch.isEmpty ? source.branch : branch
            (status.commit, status.commitDate) = try await currentCommit(of: temporary)
            let bundles = ExtensionSources.bundleFolders(in: temporary)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: temporary, to: destination)
            return Clone(folder: destination, status: status, bundles: bundles)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    /// Looks for what's new: fetches the branch, and lists the commits after the clone's (`updates`); whether Update can
    /// fast-forward to them. The clone itself doesn't move.
    public func check(_ source: ExtensionSource, _ status: ExtensionSourceStatus) async throws -> ExtensionSourceStatus {
        var status = status
        let folder = ExtensionSources.cloneFolder(for: source.url, root: root)
        let (remote, head) = try await fetch(source, status, in: folder)
        status.remote = remote == head ? nil : remote
        if remote == head {
            status.updates = []
            status.fastForward = true
        } else {
            status.fastForward = try await isAncestor(head, of: remote, in: folder)
            let range = status.fastForward ? "\(head)..\(remote)" : remote
            status.updates = ExtensionSources.parseLog(try await call(ExtensionSources.logArguments(range, limit: status.fastForward ? 100 : 20),
                                                                      in: folder).output)
        }
        status.checked = now()
        status.error = nil
        return status
    }

    /// Update: fetches again and fast-forwards the clone to the branch (a reset to it, once it's known to follow the
    /// clone's commit; no merge, no hooks). Throws `.notFastForward` after a force push.
    public func update(_ source: ExtensionSource, _ status: ExtensionSourceStatus) async throws -> ExtensionSourceStatus {
        var status = status
        let folder = ExtensionSources.cloneFolder(for: source.url, root: root)
        let (remote, head) = try await fetch(source, status, in: folder)
        if remote != head {
            guard try await isAncestor(head, of: remote, in: folder) else {
                status.fastForward = false
                throw ExtensionSourceError.notFastForward
            }
            try await call(ExtensionSources.noHooks + ["reset", "-q", "--hard", remote], in: folder)
        }
        (status.commit, status.commitDate) = try await currentCommit(of: folder)
        status.updates = []
        status.remote = nil
        status.fastForward = true
        status.checked = now()
        status.error = nil
        return status
    }

    /// Re-clone (after a force push): a new clone replaces the old one, which goes only once the new one is in place.
    /// The source stays trusted.
    public func reclone(_ source: ExtensionSource, _ status: ExtensionSourceStatus) async throws -> ExtensionSourceStatus {
        let fm = FileManager.default
        let destination = ExtensionSources.cloneFolder(for: source.url, root: root)
        let old = root.appendingPathComponent(".old-\(destination.lastPathComponent)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        if fm.fileExists(atPath: destination.path) { try fm.moveItem(at: destination, to: old) }
        do {
            let clone = try await clone(source)
            _ = try ExtensionSources.resolveBundlePath(source.path, in: clone.folder)
            try? fm.removeItem(at: old)
            var fresh = clone.status
            fresh.trusted = status.trusted
            return fresh
        } catch {
            if fm.fileExists(atPath: old.path) {
                try? fm.removeItem(at: destination)
                try? fm.moveItem(at: old, to: destination)
            }
            throw error
        }
    }

    /// Pins the clone to `pin` (a tag or a commit): fetched and checked out. Changing the pin is the user's own act.
    public func pin(_ source: ExtensionSource, to pin: String, _ status: ExtensionSourceStatus) async throws -> ExtensionSourceStatus {
        var status = status
        let folder = ExtensionSources.cloneFolder(for: source.url, root: root)
        try await checkout(pin, in: folder)
        (status.commit, status.commitDate) = try await currentCommit(of: folder)
        status.updates = []
        status.remote = nil
        status.fastForward = true
        status.error = nil
        return status
    }

    /// Moves the clone to the Trash (nothing there: fine).
    public func trash(_ source: ExtensionSource) throws {
        let folder = ExtensionSources.cloneFolder(for: source.url, root: root)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try trashItem(folder)
    }

    /// Deletes a clone that was never enabled (Cancel in the review).
    public func discard(_ source: ExtensionSource) {
        try? FileManager.default.removeItem(at: ExtensionSources.cloneFolder(for: source.url, root: root))
    }

    // MARK: Git calls

    /// The branch's newest commit, fetched, and the clone's.
    private func fetch(_ source: ExtensionSource, _ status: ExtensionSourceStatus, in folder: URL) async throws -> (remote: String, head: String) {
        let ref = source.branch ?? status.branch ?? "HEAD"
        try await call(ExtensionSources.fetchArguments(ref, depth: ExtensionSources.fetchDepth), in: folder)
        let remote = try await revision("FETCH_HEAD^{commit}", in: folder)
        let head = try await revision("HEAD", in: folder)
        return (remote, head)
    }

    /// Checks out `ref` (a tag, a branch or a commit), fetched first; a commit the server won't send on its own is
    /// fetched with the whole history.
    private func checkout(_ ref: String, in folder: URL) async throws {
        guard !ref.hasPrefix("-"), !ref.contains(where: \.isWhitespace) else { throw ExtensionSourceError.git("Not a tag or commit: \(ref)") }
        do {
            try await call(ExtensionSources.fetchArguments(ref, depth: 1), in: folder)
            try await call(ExtensionSources.noHooks + ["checkout", "-q", "--detach", "FETCH_HEAD^{commit}"], in: folder)
        } catch let error as ExtensionSourceError where ref.count >= 7 && ref.allSatisfy(\.isHexDigit) {
            guard case .git = error else { throw error }
            try await call(ExtensionSources.noHooks + ["fetch", "--unshallow", "--no-tags", "origin"], in: folder)
            try await call(ExtensionSources.noHooks + ["checkout", "-q", "--detach", ref + "^{commit}"], in: folder)
        }
    }

    private func currentCommit(of folder: URL) async throws -> (String, Date?) {
        let line = try await call(ExtensionSources.noHooks + ["show", "-s", "--format=%H%x1f%cI", "HEAD"], in: folder).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = line.split(separator: "\u{1F}").map(String.init)
        return (fields.first ?? line, fields.count > 1 ? ISO8601DateFormatter().date(from: fields[1]) : nil)
    }

    private func revision(_ ref: String, in folder: URL) async throws -> String {
        try await call(ExtensionSources.noHooks + ["rev-parse", "--verify", "-q", ref], in: folder).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAncestor(_ commit: String, of descendant: String, in folder: URL) async throws -> Bool {
        let result = try await git.run(ExtensionSources.noHooks + ["merge-base", "--is-ancestor", commit, descendant], in: folder)
        return result.status == 0
    }

    /// Runs git; a non-zero exit throws its message.
    @discardableResult
    private func call(_ arguments: [String], in folder: URL) async throws -> GitResult {
        let result = try await git.run(arguments, in: folder)
        guard result.status == 0 else { throw ExtensionSourceError.git(ExtensionSources.gitMessage(result)) }
        return result
    }
}

/// The real git: /usr/bin/git (which runs the one of Xcode or the command line tools), with stdin closed, in
/// `environment` (`ExtensionSources.gitEnvironment`), stopped after `timeout` with what it started.
public struct ProcessGitRunner: GitRunning {
    public var executable: URL
    public var environment: [String: String]
    public var timeout: TimeInterval
    /// Where Xcode or the command line tools may be (`DeveloperTools.folders`): without them, /usr/bin/git only offers
    /// to install them, so it isn't run.
    public var developerFolders: [String]

    public init(executable: URL = URL(fileURLWithPath: "/usr/bin/git"), environment: [String: String],
                timeout: TimeInterval = ExtensionSources.timeout, developerFolders: [String] = DeveloperTools.folders) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
        self.developerFolders = developerFolders
    }

    /// The user's git: the login shell's environment, their agent, and their own ssh command (`core.sshCommand`) with
    /// batch mode. Slow the first time (the login shell is read): off the main thread.
    public static func user() async -> ProcessGitRunner {
        let base = ShellEnvironment.current
        let plain = ProcessGitRunner(environment: ExtensionSources.gitEnvironment(base: base, login: ShellEnvironment.login))
        let configured = try? await plain.run(["config", "--get", "core.sshCommand"], in: nil)
        let ssh = configured.flatMap { $0.status == 0 ? $0.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
        var runner = plain
        runner.environment = ExtensionSources.gitEnvironment(base: base, login: ShellEnvironment.login, sshCommand: ssh.flatMap { $0.isEmpty ? nil : $0 })
        return runner
    }

    public func run(_ arguments: [String], in directory: URL?) async throws -> GitResult {
        if executable.path == "/usr/bin/git", !DeveloperTools.installed(in: developerFolders) {
            throw ExtensionSourceError.gitNotInstalled
        }
        let (executable, environment, timeout) = (self.executable, self.environment, self.timeout)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try Self.runNow(executable, arguments, directory: directory, environment: environment, timeout: timeout)
                })
            }
        }
    }

    private static func runNow(_ executable: URL, _ arguments: [String], directory: URL?, environment: [String: String],
                               timeout: TimeInterval) throws -> GitResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let reading = DispatchGroup()
        let captured = Captured()
        for (pipe, isError) in [(out, false), (err, true)] {
            reading.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                captured.set(data, error: isError)
                reading.leave()
            }
        }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw ExtensionSourceError.git("Can't start \(executable.path): \(error.localizedDescription)")
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            // Its whole group (ssh it started too).
            let group = process.processIdentifier
            kill(-group, SIGTERM)
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut { kill(-group, SIGKILL); kill(group, SIGKILL) }
            _ = reading.wait(timeout: .now() + 1)
            throw ExtensionSourceError.timedOut(timeout)
        }
        _ = reading.wait(timeout: .now() + 5)
        let (output, errors) = captured.get()
        return GitResult(status: process.terminationStatus, output: String(decoding: output, as: UTF8.self),
                         errors: String(decoding: errors, as: UTF8.self))
    }

    /// What the two pipes held, read on two threads.
    private final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var output = Data(), errors = Data()
        func set(_ data: Data, error: Bool) { lock.withLock { if error { errors = data } else { output = data } } }
        func get() -> (Data, Data) { lock.withLock { (output, errors) } }
    }
}
