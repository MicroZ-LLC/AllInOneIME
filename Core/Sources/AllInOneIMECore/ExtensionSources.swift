import Crypto
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
    /// Entry by entry: one that can't be read (a field a later version changed) is left out, not the others. A file that
    /// isn't a JSON object at all is moved aside (`sources.json.bad-<date>`), never overwritten, and reads as empty.
    public static func load(from file: URL) -> [String: ExtensionSourceStatus] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let aside = file.deletingLastPathComponent()
                .appendingPathComponent(file.lastPathComponent + ".bad-" + formatter.string(from: Platform.current.clock.now))
            try? FileManager.default.moveItem(at: file, to: aside)
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var statuses: [String: ExtensionSourceStatus] = [:]
        for (url, entry) in object {
            // An entry that isn't an object (a `null`) makes JSONSerialization raise, not throw: skipped.
            guard JSONSerialization.isValidJSONObject(entry), let entryData = try? JSONSerialization.data(withJSONObject: entry),
                  let status = try? decoder.decode(ExtensionSourceStatus.self, from: entryData) else { continue }
            statuses[url] = status
        }
        return statuses
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
    /// The new commits don't follow the clone's (a force push): Re-clone, which shows the review again.
    case notFastForward
    /// A branch, tag or commit that isn't one (or could be read as an option).
    case invalidRef(String)
    /// A user name or token in an https address.
    case credentialsInURL
    /// The bundle folder leads out of the repository (a symbolic link).
    case outsideClone(String)

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
        case .notFastForward: return "The repository's history changed (a force push): re-clone it, and review it again"
        case let .invalidRef(ref): return "Not a branch, tag or commit name: \(ref)"
        case .credentialsInURL:
            return "Don't put a user name, password or token in the address: git's credential helper keeps them (git help credential)"
        case let .outsideClone(path): return "\(path) leads out of the repository"
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
        CorePaths.dataDir.appendingPathComponent("Sources", isDirectory: true)
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
            // A name or token in an https address would be kept in the config in the clear: git's credential helper keeps it.
            if lower.hasPrefix("https://"), parsed.user != nil || parsed.password != nil { throw ExtensionSourceError.credentialsInURL }
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
        let path = source.path ?? ""
        let parts = CorePaths.components(path).filter { $0 != "." }
        // A path that climbs out ("..", and on Windows "..\", "C:") or has a NUL in it (a URL with one names "/") names no
        // folder of the clone: a hidden name that never exists, so nothing loads.
        if path.contains("\0") || parts.contains(where: CorePaths.climbs) {
            return clone.appendingPathComponent(".invalid-bundle-path", isDirectory: true)
        }
        return parts.isEmpty ? clone : clone.appendingPathComponent(parts.joined(separator: "/"), isDirectory: true)
    }

    /// A folder's path as the load list is compared: "~" expanded, standardized, its existing part's links resolved,
    /// no trailing "/", in lower case on a volume that doesn't tell case apart (a folder gone compares the same as before).
    public static func comparable(_ path: String) -> String {
        var path = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        // Its existing part with links resolved (/var → /private/var), the rest as written; on a volume that doesn't tell
        // case apart, in lower case.
        var existing = path, rest: [String] = []
        while existing.count > 1, !FileManager.default.fileExists(atPath: existing) {
            // Up to the first part there; not past a top that isn't (a missing drive, "C:/", is its own parent).
            let parent = (existing as NSString).deletingLastPathComponent
            guard parent != existing else { break }
            rest.insert((existing as NSString).lastPathComponent, at: 0)
            existing = parent
        }
        #if os(Windows)
        // No realpath there: Foundation resolves the links. It doesn't say how the volume compares names: NTFS's way.
        existing = URL(fileURLWithPath: existing).resolvingSymlinksInPath().path
        let unsaid = false
        #else
        if let real = realpath(existing, nil) {
            existing = String(cString: real)
            free(real)
        }
        let unsaid = true
        #endif
        let resolved = rest.reduce(existing) { ($0 as NSString).appendingPathComponent($1) }
        let caseSensitive = (try? URL(fileURLWithPath: existing).resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? unsaid
        return caseSensitive ? resolved : resolved.lowercased()
    }

    /// The bundle's folder as `Config.extensionFolders` has it ("~/…").
    public static func loadPath(for source: ExtensionSource, root: URL = directory) -> String {
        ExtensionStore.abbreviated(bundleFolder(for: source, root: root).path)
    }

    // MARK: Git

    /// The environment git runs in: the input method's own with the login shell's PATH (`base`: on the Mac `ShellEnvironment
    /// .current`), the login shell's SSH agent and ssh command if it sets them (`login`), and nothing that could wait for
    /// an answer: no terminal prompts (`GIT_TERMINAL_PROMPT=0`), no askpass program (`SSH_ASKPASS_REQUIRE=never`). git
    /// runs without a controlling terminal and with stdin closed (`ProcessGitRunner`), so ssh can't ask for a host key or a
    /// password either; it fails, and the timeout ends anything else. The user's own ssh command (`GIT_SSH_COMMAND`,
    /// `core.sshCommand`, `GIT_SSH`) is left exactly as it is (`sshCommand` is no longer used). Only ssh, https and file
    /// transports are allowed (`GIT_ALLOW_PROTOCOL`), and variables that would point git at another repository are dropped.
    public static func gitEnvironment(base: [String: String], login: [String: String] = [:],
                                      sshCommand: String? = nil) -> [String: String] {
        var env = base
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"] {
            env[key] = nil
        }
        if let agent = login["SSH_AUTH_SOCK"], !agent.isEmpty { env["SSH_AUTH_SOCK"] = agent }
        if env["GIT_SSH_COMMAND"]?.isEmpty != false, let own = login["GIT_SSH_COMMAND"], !own.isEmpty { env["GIT_SSH_COMMAND"] = own }
        if env["HOME"]?.isEmpty != false { env["HOME"] = NSHomeDirectory() }
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["SSH_ASKPASS_REQUIRE"] = "never"
        env["GIT_ALLOW_PROTOCOL"] = "ssh:https:file"
        return env
    }

    /// A branch, tag or commit as given (config, Settings, a pin, the repository's own default branch): what git itself
    /// takes for a branch name (`git check-ref-format --branch`, `ExtensionSourceManager.checkRef`), and never anything
    /// git could read as an option. This part needs no git: not empty, no leading "-", no spaces or control characters,
    /// none of `~^:?*[\`, no "..", "@{", "//", a leading or trailing "/" or "." or a ".lock" ending.
    public static func isPlausibleRef(_ ref: String) -> Bool {
        guard !ref.isEmpty, ref.count <= 255, !ref.hasPrefix("-"), !ref.hasPrefix("/"), !ref.hasSuffix("/"), !ref.hasPrefix("."),
              !ref.hasSuffix("."), !ref.hasSuffix(".lock"), !ref.contains(".."), !ref.contains("@{"), !ref.contains("//"), ref != "@"
        else { return false }
        return ref.unicodeScalars.allSatisfy { scalar in
            scalar.value > 32 && scalar.value != 127 && !"~^:?*[\\".unicodeScalars.contains(scalar)
        }
    }

    /// `git clone`: shallow, the one branch (`branch`, else the default; checked first, and git takes the word after
    /// `--branch` as its value whatever it is), no tags, the address after `--`, into `folder`.
    public static func cloneArguments(url: String, branch: String?, into folder: URL) -> [String] {
        noHooks + ["clone", "--depth", "1", "--single-branch", "--no-tags"] + (branch.map { ["--branch", $0] } ?? [])
            + ["--", url, folder.path]
    }

    /// `git fetch` of `ref` (a branch, a tag or a commit; "HEAD": the default branch) from origin, `depth` deep.
    public static func fetchArguments(_ ref: String, depth: Int) -> [String] {
        noHooks + ["fetch", "--depth", String(depth), "--no-tags", "--end-of-options", "origin", ref]
    }

    /// `git log` of `range`, one line a commit: sha, author, date, subject, split by a unit separator.
    public static func logArguments(_ range: String, limit: Int = 100) -> [String] {
        noHooks + ["log", "-n", String(limit), "--format=%H%x1f%an%x1f%aI%x1f%s", "--end-of-options", range]
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

    /// What a failed git call says, for Settings and the command line: every line that states a cause (ssh's or the
    /// server's refusal, `remote:` lines, each `fatal:` and `error:`), without git's progress, its "hint:" lines and its
    /// closing boilerplate ("Please make sure you have the correct access rights / and the repository exists."). At most
    /// `maxMessageLines` lines of at most 300 characters; the causes are kept first when there are more.
    public static func gitMessage(_ result: GitResult) -> String {
        let text = result.errors.isEmpty ? result.output : result.errors
        let boilerplate: Set<String> = ["please make sure you have the correct access rights", "and the repository exists."]
        let progress = ["cloning into", "remote: enumerating", "remote: counting", "remote: compressing", "remote: total",
                        "receiving objects", "resolving deltas", "unpacking objects"]
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            let lower = line.lowercased()
            return line.contains(where: \.isLetter) && !lower.hasPrefix("hint:") && !boilerplate.contains(lower)
                && !progress.contains { lower.hasPrefix($0) }
        }
        func isCause(_ line: String) -> Bool {
            let lower = line.lowercased()
            return lower.hasPrefix("fatal:") || lower.hasPrefix("error:") || lower.hasPrefix("remote:") || lower.contains("denied")
                || lower.contains("failed") || lower.contains("could not") || lower.contains("not found")
        }
        var kept = lines
        if kept.count > maxMessageLines {
            // The causes first, in order; then the latest other lines, up to the cap.
            let causes = Array(lines.enumerated().filter { isCause($0.element) }.suffix(maxMessageLines))
            let room = maxMessageLines - causes.count
            let others = room > 0 ? Array(lines.enumerated().filter { !isCause($0.element) }.suffix(room)) : []
            kept = (causes + others).sorted { $0.offset < $1.offset }.map(\.element)
        }
        let message = kept.map { $0.count > 300 ? String($0.prefix(299)) + "…" : $0 }.joined(separator: "\n")
        return message.isEmpty ? "git failed (exit status \(result.status))" : message
    }

    /// The most lines of git's own words shown for a failure.
    public static let maxMessageLines = 8

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
            let parts = CorePaths.components(path).filter { $0 != "." }
            let cleaned = parts.joined(separator: "/")
            guard !path.contains("\0"), !parts.contains(where: CorePaths.climbs),
                  FileManager.default.fileExists(atPath: clone.appendingPathComponent(cleaned).appendingPathComponent(ExtensionBundle.manifestName).path)
            else { throw ExtensionSourceError.noBundle(path) }
            // A folder that is (or goes through) a link out of the repository isn't the repository's.
            guard isInside(clone.appendingPathComponent(cleaned), clone) else { throw ExtensionSourceError.outsideClone(cleaned) }
            return cleaned
        }
        let found = bundleFolders(in: clone)
        switch found.count {
        case 0: throw ExtensionSourceError.noBundle(nil)
        case 1: return found[0]
        default: throw ExtensionSourceError.severalBundles(found)
        }
    }

    /// Whether `url`, its links followed, is `folder` or inside it (its links followed too).
    public static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
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
            // An entry the config had (one handed out with its sign-in hint, say) keeps its hint and its schedule.
            var source = source
            let had = config.extensionSources[index]
            source.authHint = source.authHint ?? had.authHint
            source.autoCheck = had.autoCheck
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

    /// The load list's folders inside the sources folder (`root`) that aren't a trusted source's bundle: a config copied
    /// from another Mac, a lost sources.json, a folder added by hand. Their code was never reviewed here: they aren't
    /// loaded (`quarantine`, and the input method's own check before it loads extensions).
    public static func untrustedFolders(in config: Config, statuses: [String: ExtensionSourceStatus], root: URL = directory) -> [String] {
        let base = comparable(root.path)
        let trusted = Set(config.extensionSources.filter { isTrusted($0, statuses[$0.url]) }
            .map { comparable(bundleFolder(for: $0, root: root).path) })
        return config.extensionFolders.filter { path in
            let full = comparable(path)
            return (full == base || full.hasPrefix(base + "/")) && !trusted.contains(full)
        }
    }

    /// The folders extensions are loaded from (`ExtensionStore.folders`) as the input method loads them: less
    /// `untrustedFolders`, and those of the sources folder read only as the one bundle each is (`Folder.bundleOnly`).
    /// What an interrupted Enable or Re-clone left aside in the sources folder is put right first
    /// (`FileOps.recoverInterruptedSwaps`).
    public static func loadFolders(_ config: Config, found: [String], statuses: [String: ExtensionSourceStatus],
                                   root: URL = directory) -> [ExtensionStore.Folder] {
        Platform.current.files.recoverInterruptedSwaps(in: root)
        let base = comparable(root.path)
        let untrusted = Set(untrustedFolders(in: config, statuses: statuses, root: root).map(comparable))
        return ExtensionStore.folders(config, found: found).compactMap { folder in
            let path = comparable(folder.path)
            guard !untrusted.contains(path) else { return nil }
            var folder = folder
            if path.hasPrefix(base + "/") { folder.bundleOnly = true }
            return folder
        }
    }

    /// Takes `untrustedFolders` out of the load list; returns them.
    @discardableResult
    public static func quarantine(_ config: inout Config, statuses: [String: ExtensionSourceStatus], root: URL = directory) -> [String] {
        let untrusted = untrustedFolders(in: config, statuses: statuses, root: root)
        if !untrusted.isEmpty { config.extensionFolders.removeAll { untrusted.contains($0) } }
        return untrusted
    }

    /// `quarantine` in the config file at `url`: written only if a folder was taken out, and then only the keys that
    /// changed (`AIConfig.writing`), so a file without a key this version always writes doesn't gain it with its
    /// default. The folders taken out.
    @discardableResult
    public static func quarantineConfigFile(at url: URL, statuses: [String: ExtensionSourceStatus],
                                            root: URL = directory) throws -> [String] {
        let before = try Config.load(from: url)
        var config = before
        let removed = quarantine(&config, statuses: statuses, root: root)
        guard !removed.isEmpty else { return [] }
        try AIConfig.writing(config, from: before, keys: AIConfig.changedKeys(before, config), at: url)
        return removed
    }

    /// Enable in the config file at `url`, read as it is now: the unreviewed folders of the sources folder out of its
    /// load list first (`quarantine`, by `statuses`), then `source` in (`enable`). Only the keys that changed are written
    /// (`AIConfig.writing`); every other key of the file stays as it was. A missing file is written whole.
    public static func enableInConfigFile(_ source: ExtensionSource, at url: URL,
                                          quarantining statuses: [String: ExtensionSourceStatus], root: URL = directory) throws {
        let before = try Config.load(from: url)
        var config = before
        quarantine(&config, statuses: statuses, root: root)
        enable(source, in: &config, root: root)
        try AIConfig.writing(config, from: before, keys: AIConfig.changedKeys(before, config), at: url)
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
        /// Its script is a symbolic link out of the repository (to where it leads): it would run a file the review
        /// can't vouch for.
        public var leavesRepository: String? = nil
        /// What its status line runs (`status`), written as `program` is; nil when it has none.
        public var status: String? = nil
    }

    /// A text the bundle ships to insert (`BundleSnippet`): it runs nothing.
    public struct Snippet: Equatable, Sendable {
        public var name: String
        /// Its row in the command list: its summary, or the start of its text (`Command.snippetRowText`).
        public var text: String
        /// Why it won't be offered (other commands have its name and alias), nil when it will.
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
    public var snippets: [Snippet] = []
    /// Its entries that can't be loaded, and why (a script missing or not runnable, a name twice).
    public var skipped: [ExtensionStore.Skipped]

    public var preferences: [ExtensionBundle.Preference] { bundle?.preferences ?? [] }
    /// Every program it runs, once each: its commands' and their status lines'.
    public var programs: [String] {
        var seen = Set<String>()
        return commands.flatMap { [$0.program] + ($0.status.map { [$0] } ?? []) }.filter { seen.insert($0).inserted }
    }

    /// The bundle in `bundleFolder` as it would load next to what `config` loads now (`found`: the Raycast folders
    /// Spotlight found; `plugins`: the installed plugins). `repository`: the clone, to flag a script that is a link out of
    /// it (nil: out of the bundle's folder).
    public static func make(bundleFolder: URL, path: String, url: String, commit: String?, commitDate: Date?, config: Config,
                            plugins: [InstalledPlugin] = [], found: [String] = [], repository: URL? = nil) -> ExtensionSourceReview {
        let folder = bundleFolder.standardizedFileURL
        let prefix = folder.path + "/"
        var folders = ExtensionStore.folders(config, found: found).filter { $0.url.standardizedFileURL.path != folder.path }
        // Only ever the bundle it is: a manifest that isn't valid says why, and its scripts aren't listed as commands.
        folders.append(ExtensionStore.Folder(path: folder.path, found: false, bundleOnly: true))
        let index = ExtensionStore.load(folders, cache: ExtensionCache())
        let bundle = index.bundles.first { $0.folder.standardizedFileURL.path == folder.path }
        let mine = index.skipped.filter { $0.file.standardizedFileURL.path.hasPrefix(prefix) }
        let manifest = folder.appendingPathComponent(ExtensionBundle.manifestName).path
        let problem = bundle == nil ? mine.first { $0.file.standardizedFileURL.path == manifest }?.problem ?? .badBundle(.notJSON) : nil
        let enabled = index.enabled(config.disabledExtensions)
        let enabledSnippets = index.enabledSnippets(config.disabledExtensions)
        let hidden = Dictionary(AllInOneIMECore.Command.hiddenScripts(enabled, custom: config.customCommands, plugins: plugins,
                                                                      snippets: enabledSnippets)
            .map { ($0.script.id, ScriptCommand.Problem.nameTaken($0.script.name, by: $0.owner)) }, uniquingKeysWith: { (a: ScriptCommand.Problem, _: ScriptCommand.Problem) in a })
        let hiddenSnippets = Dictionary(AllInOneIMECore.Command.hiddenSnippets(enabledSnippets, scripts: enabled, custom: config.customCommands,
                                                                               plugins: plugins)
            .map { ($0.snippet.id, ScriptCommand.Problem.nameTaken($0.snippet.name, by: $0.owner)) }, uniquingKeysWith: { (a: ScriptCommand.Problem, _: ScriptCommand.Problem) in a })
        let snippets: [Snippet] = bundle.map { bundle in
            index.snippets.filter { $0.bundle == bundle.name }.map { snippet in
                let off = config.disabledExtensions.contains(bundle.name) || config.disabledExtensions.contains(snippet.id)
                let row = AllInOneIMECore.Command(name: snippet.name, kind: .snippet, custom: snippet.definition).snippetRowText ?? ""
                return Snippet(name: snippet.name, text: row, hidden: off ? nil : hiddenSnippets[snippet.id])
            }
        } ?? []
        let commands = index.commands.filter { $0.file.standardizedFileURL.path.hasPrefix(prefix) }.map { command in
            func shown(_ launch: [String]) -> String { launch.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }.joined(separator: " ") }
            let program = shown(command.launch)
            let off = bundle.map { config.disabledExtensions.contains($0.name) } == true || config.disabledExtensions.contains(command.id)
            let outside = ExtensionSources.isInside(command.file, repository ?? folder) ? nil : command.file.resolvingSymlinksInPath().path
            return Command(name: command.name, title: command.title, description: command.description, output: command.output,
                           background: command.background, program: program, hidden: off ? nil : hidden[command.id],
                           leavesRepository: outside, status: command.status.map { shown($0.launch) })
        }
        return ExtensionSourceReview(url: url, commit: commit, commitDate: commitDate, path: path, bundle: bundle, problem: problem,
                                     commands: commands, snippets: snippets, skipped: bundle == nil ? [] : mine)
    }

    /// The review as text, for `--add-source`, a problem in Swift's own words (`summary(describe:)` says it in a person's).
    public var summary: [String] { summary(describe: { problem, _ in "\(problem)" }) }

    /// The review as text, each problem as `describe` says it.
    public func summary(describe: (ScriptCommand.Problem, URL) -> String) -> [String] {
        var lines: [String] = []
        lines.append("source:      \(url)" + (path.isEmpty ? "" : " (\(path))"))
        if let commit {
            let date = commitDate.map { " " + ISO8601DateFormatter().string(from: $0) } ?? ""
            lines.append("commit:      \(commit.prefix(7))\(date)")
        }
        lines.append("WARNING:     This source isn't signed: it will run programs from \(url).")
        if let problem {
            let manifest = URL(fileURLWithPath: path.isEmpty ? ExtensionBundle.manifestName : path + "/" + ExtensionBundle.manifestName)
            lines.append("bundle:      can't be loaded: " + describe(problem, manifest))
        }
        if let bundle {
            lines.append("bundle:      \(bundle.name) — \(bundle.title)" + (bundle.version.map { " \($0)" } ?? "") + (bundle.author.map { " by \($0)" } ?? ""))
            if let description = bundle.description { lines.append("             \(description)") }
        }
        for command in commands {
            let hidden = command.hidden.map { "  [hidden: " + describe($0, URL(fileURLWithPath: command.program)) + "]" } ?? ""
            lines.append("command:     @\(command.name) — \(command.title) (\(command.output.rawValue)\(command.background ? ", background" : ""))\(hidden)")
            if let description = command.description { lines.append("             \(description)") }
            lines.append("  runs:      \(command.program)")
            if let status = command.status { lines.append("  status:    \(status)") }
            if let target = command.leavesRepository { lines.append("  WARNING:   its script is a link out of the repository, to \(target)") }
        }
        for snippet in snippets {
            let hidden = snippet.hidden.map { "  [hidden: " + describe($0, URL(fileURLWithPath: ExtensionBundle.manifestName)) + "]" } ?? ""
            lines.append("snippet:     @\(snippet.name) — \(snippet.text) (inserts text, runs nothing)\(hidden)")
        }
        for preference in preferences {
            lines.append("preference:  \(preference.name) (\(preference.kind.rawValue)\(preference.required ? ", required" : ""))")
        }
        for skipped in skipped { lines.append("skipped:     \(skipped.file.lastPathComponent): " + describe(skipped.problem, skipped.file)) }
        return lines
    }
}

/// The git work on the clones: cloning (into staging, then into place), checking, updating, pinning, re-cloning,
/// removing. Every call goes through `git` (the real one, or a test's). Every branch, tag or commit is checked before git
/// sees it (`checkRef`), and passed after `--end-of-options` (or as an option's own value): a name like
/// `--upload-pack=…`, in the config or as a repository's default branch, is refused, never run.
public struct ExtensionSourceManager: Sendable {
    public var root: URL
    public var git: any GitRunning
    public var now: @Sendable () -> Date
    /// Moves a removed source's clone away: to the Trash where there is one (`FileOps.trash`; tests delete it instead).
    public var trashItem: @Sendable (URL) throws -> Void

    /// `now` and `trashItem` by default are the clock and the files of the platform in use where it's made
    /// (`Platform.current`, read then: work on another queue doesn't see a test's `Platform.$override`).
    public init(root: URL = ExtensionSources.directory, git: any GitRunning,
                now: @escaping @Sendable () -> Date = { [clock = Platform.current.clock] in clock.now },
                trashItem: @escaping @Sendable (URL) throws -> Void = { [files = Platform.current.files] in try files.trash($0) }) {
        self.root = root
        self.git = git
        self.now = now
        self.trashItem = trashItem
    }

    public var statusFile: URL { root.appendingPathComponent(ExtensionSources.statusFileName) }
    /// Where clones wait for their review: hidden, never in the load list.
    public var stagingFolder: URL { root.appendingPathComponent(".staging", isDirectory: true) }

    /// The statuses as kept, and keeping them.
    public func statuses() -> [String: ExtensionSourceStatus] { ExtensionSourceStatus.load(from: statusFile) }
    public func save(_ statuses: [String: ExtensionSourceStatus]) throws { try ExtensionSourceStatus.save(statuses, to: statusFile) }

    /// A clone: where it is (in staging, waiting for the review, or in place), what it found, and the bundle paths in it.
    public struct Clone: Equatable, Sendable {
        public var folder: URL
        public var status: ExtensionSourceStatus
        public var bundles: [String]
    }

    /// Clones `source` (shallow; its pin checked out) into a folder of its own in staging (`stagingFolder`), for the
    /// review: nothing there is in the load list, and nothing in place is touched. `install` puts it in place (Enable);
    /// `discard` deletes it (Cancel).
    public func stage(_ source: ExtensionSource) async throws -> Clone {
        let url = try ExtensionSources.validate(source.url)
        if let branch = source.branch { try await checkRef(branch) }
        if let pin = source.pin { try await checkRef(pin) }
        let fm = FileManager.default
        try fm.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        let folder = stagingFolder.appendingPathComponent("\(ExtensionSources.folderName(for: url))-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try await call(ExtensionSources.cloneArguments(url: url, branch: source.branch, into: folder), in: root)
            if let pin = source.pin { try await checkout(pin, in: folder) }
            var status = ExtensionSourceStatus(url: url, checked: now())
            let branch = try await call(ExtensionSources.noHooks + ["rev-parse", "--abbrev-ref", "HEAD"], in: folder).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if branch == "HEAD" || branch.isEmpty {
                status.branch = source.branch
            } else {
                // The repository's own default branch is a name its owner chose: checked like any other.
                try await checkRef(branch)
                status.branch = branch
            }
            (status.commit, status.commitDate) = try await currentCommit(of: folder)
            return Clone(folder: folder, status: status, bundles: ExtensionSources.bundleFolders(in: folder))
        } catch {
            try? fm.removeItem(at: folder)
            removeStagingIfEmpty()
            throw error
        }
    }

    /// Enable: the staged clone takes the source's place, in one step (an atomic swap with the one there, which is then
    /// deleted; a crash between leaves either the old or the new folder in place, never none).
    public func install(_ staged: Clone) throws -> Clone {
        let destination = ExtensionSources.cloneFolder(for: staged.status.url, root: root)
        try PluginLibrary.moveIntoPlace(staged.folder, destination)
        removeStagingIfEmpty()
        return Clone(folder: destination, status: staged.status, bundles: staged.bundles)
    }

    /// Cancel: a staged clone is deleted. Only ever a folder in staging; the one in place is never touched.
    public func discard(_ staged: Clone) {
        guard ExtensionSources.isInside(staged.folder, stagingFolder), staged.folder.standardizedFileURL != stagingFolder.standardizedFileURL
        else { return }
        try? FileManager.default.removeItem(at: staged.folder)
        removeStagingIfEmpty()
    }

    /// Clones `source` and puts it in place at once (`stage`, then `install`): for a source already reviewed, and tests.
    /// Settings and `--add-source` stage, review, and install only on Enable.
    public func clone(_ source: ExtensionSource) async throws -> Clone {
        try install(try await stage(source))
    }

    /// Leftovers of an interrupted add, update or re-clone (staged clones, ".tmp-", ".old-" folders) at least `age`
    /// old: removed. A younger one may be in use (a review open, `--add-source` running).
    public func removeLeftovers(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        func old(_ url: URL) -> Bool {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return date.map { now().timeIntervalSince($0) >= age } ?? true
        }
        for name in (try? fm.contentsOfDirectory(atPath: stagingFolder.path)) ?? [] {
            let staged = stagingFolder.appendingPathComponent(name)
            if old(staged) { try? fm.removeItem(at: staged) }
        }
        removeStagingIfEmpty()
        // Never a swap's aside (".tmp-x.swap-<UUID>" for a clone named "tmp-x"): `recoverInterruptedSwaps` puts it back.
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        where (name.hasPrefix(".tmp-") || name.hasPrefix(".old-")) && SystemFileOps.swappedName(name) == nil {
            let leftover = root.appendingPathComponent(name)
            if old(leftover) { try? fm.removeItem(at: leftover) }
        }
    }

    private func removeStagingIfEmpty() {
        if (try? FileManager.default.contentsOfDirectory(atPath: stagingFolder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: stagingFolder)
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
    /// clone's commit; no merge, no hooks). Throws `.notFastForward` after a force push. Also how a pinned clone goes
    /// back to the branch when the pin is taken off.
    public func update(_ source: ExtensionSource, _ status: ExtensionSourceStatus) async throws -> ExtensionSourceStatus {
        var status = status
        let folder = ExtensionSources.cloneFolder(for: source.url, root: root)
        let (remote, head) = try await fetch(source, status, in: folder)
        if remote != head {
            guard try await isAncestor(head, of: remote, in: folder) else {
                status.fastForward = false
                throw ExtensionSourceError.notFastForward
            }
            try await call(ExtensionSources.noHooks + ["reset", "-q", "--hard", "--end-of-options", remote], in: folder)
        }
        (status.commit, status.commitDate) = try await currentCommit(of: folder)
        status.updates = []
        status.remote = nil
        status.fastForward = true
        status.checked = now()
        status.error = nil
        return status
    }

    /// Re-clone: a new clone (staged) replaces the one in place in one step, once it's complete and has the bundle; a
    /// failure leaves the old one as it was. The status keeps its trust as given: the app shows the review first (after a
    /// force push the new history needs one) and only then calls this, or stages and installs itself.
    public func reclone(_ source: ExtensionSource, _ status: ExtensionSourceStatus) async throws -> ExtensionSourceStatus {
        let staged = try await stage(source)
        do {
            _ = try ExtensionSources.resolveBundlePath(source.path, in: staged.folder)
            let installed = try install(staged)
            var fresh = installed.status
            fresh.trusted = status.trusted
            return fresh
        } catch {
            discard(staged)
            throw error
        }
    }

    /// Pins the clone to `pin` (a tag or a commit): fetched and checked out. Changing the pin is the user's own act.
    public func pin(_ source: ExtensionSource, to pin: String, _ status: ExtensionSourceStatus) async throws -> ExtensionSourceStatus {
        var status = status
        let folder = ExtensionSources.cloneFolder(for: source.url, root: root)
        try await checkRef(pin)
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

    /// Deletes the source's clone in place. For a clone that was never enabled; the app itself only ever discards staged
    /// clones (`discard(_: Clone)`), never a folder in the load list.
    public func discard(_ source: ExtensionSource) {
        try? FileManager.default.removeItem(at: ExtensionSources.cloneFolder(for: source.url, root: root))
    }

    /// Throws `.invalidRef` unless `ref` is a name git takes for a branch (`git check-ref-format --branch`), after the
    /// checks that need no git (`ExtensionSources.isPlausibleRef`: never one starting with "-").
    public func checkRef(_ ref: String) async throws {
        guard ExtensionSources.isPlausibleRef(ref) else { throw ExtensionSourceError.invalidRef(ref) }
        let result = try await git.run(ExtensionSources.noHooks + ["check-ref-format", "--branch", ref], in: nil)
        guard result.status == 0 else { throw ExtensionSourceError.invalidRef(ref) }
    }

    // MARK: Git calls

    /// The branch's newest commit, fetched, and the clone's.
    private func fetch(_ source: ExtensionSource, _ status: ExtensionSourceStatus, in folder: URL) async throws -> (remote: String, head: String) {
        let ref = source.branch ?? status.branch ?? "HEAD"
        if ref != "HEAD" { try await checkRef(ref) }
        try await call(ExtensionSources.fetchArguments(ref, depth: ExtensionSources.fetchDepth), in: folder)
        let remote = try await revision("FETCH_HEAD^{commit}", in: folder)
        let head = try await revision("HEAD", in: folder)
        return (remote, head)
    }

    /// Checks out `ref` (a tag, a branch or a commit), fetched first; a commit the server won't send on its own is
    /// fetched with the whole history.
    private func checkout(_ ref: String, in folder: URL) async throws {
        try await checkRef(ref)
        do {
            try await call(ExtensionSources.fetchArguments(ref, depth: 1), in: folder)
            try await call(ExtensionSources.noHooks + ["checkout", "-q", "--detach", "--end-of-options", "FETCH_HEAD^{commit}"], in: folder)
        } catch let error as ExtensionSourceError where ref.count >= 7 && ref.allSatisfy(\.isHexDigit) {
            guard case .git = error else { throw error }
            try await call(ExtensionSources.noHooks + ["fetch", "--unshallow", "--no-tags", "--end-of-options", "origin"], in: folder)
            try await call(ExtensionSources.noHooks + ["checkout", "-q", "--detach", "--end-of-options", ref + "^{commit}"], in: folder)
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
        let result = try await git.run(ExtensionSources.noHooks + ["merge-base", "--is-ancestor", "--end-of-options", commit, descendant], in: folder)
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
