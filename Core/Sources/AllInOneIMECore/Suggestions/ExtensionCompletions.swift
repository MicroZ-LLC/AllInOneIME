import Crypto
import Foundation

// Script extensions as completion sources (0.6.7.1 §2): a command of a script extension may declare one completion
// source, with a plugin's `completions` entry's keys and meaning (docs/plugins.md), its name and title the command's. One
// kind of source: the session takes it with the plugins' and the custom commands' (`InputSession.ActiveSource`), the
// store keeps it as theirs under `CompletionSourceKey(extension:)` (its list, the disk cache, back-off and pause, statuses,
// "Refresh now", the picks), its approval is a `CompletionSourceApproval` in `Config.completionSources` (off until turned
// on in Settings → Commands), its rows, keys and insertions are theirs. Turning it on pins its whole extension (a digest
// of every file of its bundle, `ExtensionDigest`) and its terms (query, prefix, queryMinChars, compare); what a change
// does then depends on where the extension comes from (`ExtensionOrigin`, owner 2026-10-24): the user's own, or one from
// an extension source whose updates they trust, keeps it on (the approval follows it, said nowhere); one from any other
// source turns it off again, said once. What differs is where its items come from: its script, run as its commands run
// (`CommandRunner`) with `ALLINONEIME_COMPLETION` set (`ExtensionCompletionRunner`), a bundle's programs one at a time.

extension CompletionDeclaration {
    /// A script extension's declaration (`completion`: the JSON text of a script's `@allinoneime.completion` line, or of
    /// its bundle entry's `"completion"`) read as a plugin's `completions` entry is (the same keys, limits, defaults and
    /// reasons), its name and title the command's (`name`, `title`: any it gives are the command's anyway). A list loads
    /// within 20 seconds whatever the command's `timeout` (`ExtensionCompletionRunner.loadTimeout`).
    static func extensionSource(_ json: String, name: String, title: String) -> Result<CompletionSource, CompletionRefusal> {
        func refuse(_ reason: String) -> Result<CompletionSource, CompletionRefusal> {
            .failure(CompletionRefusal(name: name, reason: reason))
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]),
              case var .object(fields)? = JSON(object) else { return refuse(tr("completion 必须是 JSON 对象", "completion must be a JSON object")) }
        fields["name"] = .string(name)
        fields["title"] = .string(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : title)
        let read = read(.array([.object(fields)]), type: .script, timeoutSeconds: nil)
        if let source = read.sources.first { return .success(source) }
        return .failure(read.refused.first ?? CompletionRefusal(name: name, reason: tr("不是补全来源", "not a completion source")))
    }
}

extension CompletionSourceKey {
    /// What script extensions' sources are kept under (their `plugin`): a name no plugin can have.
    public static let scriptExtensions = "script-extensions"

    /// The completion source of the script extension command `command`: by its id ("units/convert", a single script's
    /// file "~/…"), which stays while it is the same command in the same place.
    public init(extension command: ScriptCommand) {
        self.init(extensionCommand: command.id)
    }

    /// The completion source of the script extension command whose id is `id` (`ScriptCommand.id`).
    public init(extensionCommand id: String) {
        self.init(plugin: Self.scriptExtensions, source: id)
    }

    /// It is a script extension's source.
    public var isScriptExtension: Bool { plugin == Self.scriptExtensions }
}

// MARK: - What turning it on pins

/// What a script extension is, as turning its completion source on pins it (0.6.7.1 §2): every file of its bundle
/// (`extension.json`, every script, `lib/`…), or a single script's file.
public enum ExtensionDigest {
    /// `command`'s, lowercase hex: a bundle's command, its bundle folder's (`folder(_:sha256:)`); a single script, its
    /// file's SHA-256 (as a plugin's script is pinned). Nil: nothing to read. `sha256`: a file's SHA-256 (nil: none).
    public static func of(_ command: ScriptCommand, sha256: (URL) -> String? = PluginStore.sha256(of:)) -> String? {
        guard command.source.bundleName != nil else { return sha256(command.file) }
        return folder(command.extensionDirectory, sha256: sha256)
    }

    /// The SHA-256 (lowercase hex) of every file under `folder`: each one's path in it with its own SHA-256, in the order
    /// of their paths, so a file added, removed, renamed or changed anywhere in it (a hidden one too) changes it. A link is
    /// read as the file it leads to; one to a folder, or to nothing, as where it leads (that folder isn't walked: it may be
    /// anywhere). What is no file of an extension is left out (`isIgnored`). Nil: `folder` can't be read.
    public static func folder(_ folder: URL, sha256: (URL) -> String?) -> String? {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: folder.path)) != nil else { return nil }
        var entries: [(path: String, content: String)] = []
        func visit(_ url: URL, _ relative: String) {
            guard let names = try? fm.contentsOfDirectory(atPath: url.path) else {
                entries.append((relative + "/", "unreadable"))
                return
            }
            for name in names where !isIgnored(name) {
                let child = url.appendingPathComponent(name)
                let path = relative.isEmpty ? name : relative + "/" + name
                let kind = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                if kind?.isSymbolicLink == true {
                    // The file it leads to, hashed by its own path (a hash kept by size and date then sees it change).
                    let target = child.resolvingSymlinksInPath()
                    if (try? target.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        entries.append((path, sha256(target) ?? "unreadable"))
                    } else {
                        entries.append((path, "link " + ((try? fm.destinationOfSymbolicLink(atPath: child.path)) ?? "")))
                    }
                } else if kind?.isDirectory == true {
                    visit(child, path)
                } else if kind?.isRegularFile == true {
                    entries.append((path, sha256(child) ?? "unreadable"))
                }
            }
        }
        visit(folder, "")
        var hasher = SHA256()
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data((entry.path + "\u{0}" + entry.content + "\n").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Names that are no file of an extension, wherever they are in its folder: the Finder's (`.DS_Store`, AppleDouble
    /// `._` files, a folder's own icon `Icon\r`), Windows Explorer's (`Thumbs.db`, `desktop.ini`), and git's own folder
    /// (`.git`: a check for updates changes it, never the bundle).
    static func isIgnored(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._") || name == "Icon\r" || name == ".git"
            || ["thumbs.db", "desktop.ini"].contains(name.lowercased())
    }
}

/// Where a script extension comes from, as its completion source's approval goes (0.6.7.1 §2, owner 2026-10-24).
public enum ExtensionOrigin: Equatable, Sendable {
    /// The user's own: a folder of theirs (their extensions folder, one they added), not installed from an extension
    /// source. Trusted: its changes never turn its source off.
    case own
    /// Installed from this extension source (`Config.extensionSources`): its updates keep its source on when the user
    /// trusts them (`ExtensionSource.trustUpdates`); else any change turns it off.
    case source(ExtensionSource)
    /// In the extension sources' folder but no source's bundle (a config copied from another Mac): as a source's not
    /// trusted.
    case unknownSource

    /// Whether a change keeps its source on, the approval following it (`CompletionSourceApproval.followed`).
    public var followsChanges: Bool {
        switch self {
        case .own: return true
        case let .source(source): return source.trustUpdates
        case .unknownSource: return false
        }
    }
}

extension Config {
    /// Where the script extension `command` comes from (`ExtensionOrigin`): its folder (`ScriptCommand.extensionDirectory`)
    /// a source's bundle folder in `root`, the extension sources' folder (`ExtensionSources.bundleFolder`), or in it as
    /// no source's; anywhere else, the user's own.
    public func extensionOrigin(of command: ScriptCommand, root: URL = ExtensionSources.directory) -> ExtensionOrigin {
        let folder = ExtensionSources.comparable(command.extensionDirectory.path)
        let base = ExtensionSources.comparable(root.path)
        guard folder == base || folder.hasPrefix(base + "/") else { return .own }
        let source = extensionSources.first { ExtensionSources.comparable(ExtensionSources.bundleFolder(for: $0, root: root).path) == folder }
        return source.map(ExtensionOrigin.source) ?? .unknownSource
    }

    /// Whether a change to the script extension `command` keeps its completion source on (`ExtensionOrigin.followsChanges`).
    public func followsChanges(of command: ScriptCommand, root: URL = ExtensionSources.directory) -> Bool {
        extensionOrigin(of: command, root: root).followsChanges
    }

    /// The extension source of `url`'s "Trust its updates" switched `on`. Turned off, its extensions' approvals that hold
    /// are first made what they are now (`follow`), so turning it off turns nothing off by itself: only a change after
    /// it does. `commands`: the script extensions as loaded; `root`: the extension sources' folder. Whether it changed.
    @discardableResult
    public mutating func setTrustUpdates(_ on: Bool, of url: String, extensions commands: [ScriptCommand],
                                         root: URL = ExtensionSources.directory) -> Bool {
        guard let index = extensionSources.firstIndex(where: { $0.url == url }), extensionSources[index].trustUpdates != on
        else { return false }
        if !on {
            let config = self
            let own = commands.filter { if case let .source(source) = config.extensionOrigin(of: $0, root: root) { return source.url == url } else { return false } }
            follow(CompletionSourceApproval.followed(completionSources, extensions: own, follows: { _ in true }))
        }
        extensionSources[index].trustUpdates = on
        return true
    }
}

extension CompletionSourceApproval {
    /// What turning on `source`, `command`'s, approves now (0.6.7.1 §2): its extension's digest (`ExtensionDigest`: every
    /// file of its bundle, a single script's file), whether it queries, and its terms as a plugin's (`Terms`: its prefix,
    /// from which character it queries, how it compares). No hosts: what its script reaches is its own. Nil: nothing of it
    /// can be read.
    public init?(enabling source: CompletionSource, of command: ScriptCommand) {
        guard let digest = ExtensionDigest.of(command) else { return nil }
        self.init(source, of: command, digest: digest)
    }

    /// What turning on the source `command` declares approves now (`init(enabling:of:)`). Nil: it declares none, or one
    /// refused, or nothing of it can be read.
    public init?(enabling command: ScriptCommand) {
        guard case let .success(source)? = command.completion else { return nil }
        self.init(enabling: source, of: command)
    }

    /// `source` of `command` as it is, `digest` its extension's.
    init(_ source: CompletionSource, of command: ScriptCommand, digest: String) {
        let key = CompletionSourceKey(extension: command)
        self.init(plugin: key.plugin, source: key.source, hosts: [], query: source.query, scriptSHA256: digest, terms: Terms(source))
    }

    /// Whether it still pins `source` of `command` as they are now: the same extension (its digest: any file of its
    /// bundle, a single script's file), query and terms (prefix, queryMinChars and compare), compared as a plugin's are.
    /// One without terms never holds; nor one once marked lapsed.
    public func holds(for source: CompletionSource, of command: ScriptCommand) -> Bool {
        guard let digest = ExtensionDigest.of(command) else { return false }
        return holds(forScript: source, of: command, digest: digest, follows: false)
    }

    /// Whether it holds for `source` of `command`, `follows` whether a change keeps it on (`Config.followsChanges`): one
    /// that follows holds whatever changed since (it is made what it is now, `followed`), one pinned only for what it
    /// was turned on with (`holds(for:of:)`). Never once marked lapsed: that one stays off until turned on again.
    public func holds(for source: CompletionSource, of command: ScriptCommand, follows: Bool) -> Bool {
        follows ? holds(forScript: source, of: command, digest: nil, follows: true) : holds(for: source, of: command)
    }

    /// `holds(for:of:follows:)` with its extension's digest as it is now (nil: none read; one pinned doesn't hold then).
    func holds(forScript source: CompletionSource, of command: ScriptCommand, digest: String?, follows: Bool) -> Bool {
        guard !lapsed, let terms, CompletionSourceKey(plugin: plugin, source: self.source) == CompletionSourceKey(extension: command)
        else { return false }
        if follows { return true }
        return query == source.query && scriptSHA256 == digest && terms == Terms(source)
    }

    /// The approvals of `enabled` not marked lapsed yet that no longer hold for the script extensions' `commands` as they
    /// are now: those pinned (`follows` false: from an extension source whose updates aren't trusted) whose extension,
    /// query or terms changed since. One that follows its changes never lapses (`followed`). One whose command isn't
    /// there, declares none or one refused, or can't be read, has nothing to compare with: it doesn't lapse (it isn't on
    /// meanwhile). `digest`: an extension's as it is now (`ExtensionDigest.of`; nil: none to read).
    public static func lapsed(_ enabled: [CompletionSourceApproval], extensions commands: [ScriptCommand],
                              follows: (ScriptCommand) -> Bool = { _ in false },
                              digest: (ScriptCommand) -> String? = { ExtensionDigest.of($0) }) -> [CompletionSourceApproval] {
        let extensionApprovals = enabled.filter { !$0.lapsed && $0.plugin == CompletionSourceKey.scriptExtensions }
        guard !extensionApprovals.isEmpty else { return [] }
        return extensionApprovals.filter { approval in
            guard let command = commands.first(where: { $0.id == approval.source }), case let .success(source)? = command.completion,
                  !follows(command), let digest = digest(command) else { return false }
            return !approval.holds(forScript: source, of: command, digest: digest, follows: false)
        }
    }

    /// The approvals of `enabled` not marked lapsed that follow their extension (`follows`: the user's own, or from an
    /// extension source whose updates are trusted) and differ from what it is now (its digest, query or terms), each made
    /// what it is now: kept in its place (`Config.follow`), said nowhere. `digest` as for `lapsed`.
    public static func followed(_ enabled: [CompletionSourceApproval], extensions commands: [ScriptCommand],
                                follows: (ScriptCommand) -> Bool,
                                digest: (ScriptCommand) -> String? = { ExtensionDigest.of($0) }) -> [CompletionSourceApproval] {
        enabled.compactMap { approval in
            guard !approval.lapsed, approval.plugin == CompletionSourceKey.scriptExtensions,
                  let command = commands.first(where: { $0.id == approval.source }), case let .success(source)? = command.completion,
                  follows(command), let digest = digest(command) else { return nil }
            let now = CompletionSourceApproval(source, of: command, digest: digest)
            return now == approval ? nil : now
        }
    }
}

extension Config {
    /// The approval `source` of the script extension `command` was turned on with (nil: not turned on).
    public func approval(of source: CompletionSource, in command: ScriptCommand) -> CompletionSourceApproval? {
        let key = CompletionSourceKey(extension: command)
        return completionSources.first { $0.plugin == key.plugin && $0.source == key.source }
    }

    /// `source` of the script extension `command` turned on with what it is now (`CompletionSourceApproval(enabling:of:)`),
    /// or off.
    public mutating func setCompletionSource(_ source: CompletionSource, of command: ScriptCommand, enabled: Bool) {
        let key = CompletionSourceKey(extension: command)
        completionSources.removeAll { $0.plugin == key.plugin && $0.source == key.source }
        if enabled, let approval = CompletionSourceApproval(enabling: source, of: command) { completionSources.append(approval) }
    }

    /// The approvals `followed` found (`CompletionSourceApproval.followed`) in place of those of their sources: unless one
    /// was turned off or marked lapsed meanwhile. Whether any changed.
    @discardableResult
    public mutating func follow(_ followed: [CompletionSourceApproval]) -> Bool {
        var changed = false
        for approval in followed {
            guard let index = completionSources.firstIndex(where: { $0.plugin == approval.plugin && $0.source == approval.source }),
                  !completionSources[index].lapsed, completionSources[index] != approval else { continue }
            completionSources[index] = approval
            changed = true
        }
        return changed
    }
}

extension CompletionSource {
    /// What a script extension's source switch says it does (0.6.7.1 §2), in the interface language: it runs the script in
    /// the background for its rows (its list refreshed while you use it), and one that queries gives it what you type
    /// after the prefix.
    public func scriptSummary(in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> String {
        let start = prefix.map { t.tr("在 \($0) 后面", "after \($0)") } ?? t.tr("打完整个号码后", "once the whole number is typed")
        var text = t.tr("在后台运行这个脚本，\(start)显示它给的行", "Runs this script in the background for rows \(start)")
        if list {
            let every = Self.interval(refresh, in: t)
            text += t.tr("（列表每 \(every)更新一次，只在你用到时）", " (its list refreshed every \(every), while you use it)")
        }
        if query, let prefix {
            text += t.tr("；它还会收到你在 \(prefix) 后面打的字", "; it also gets what you type after \(prefix)")
        }
        return text
    }

    /// What a script extension's source turned on before it changed says (Settings → Commands, the Mac's and the
    /// settings document's): an update from an extension source whose updates aren't trusted changed a file of its bundle,
    /// its prefix, query or terms; it is off until turned on again.
    public static var scriptChanged: String {
        tr("打开以后它改过（扩展包里的文件、前缀、实时查询或比较方式），已经关掉：要用的话再打开一次。",
           "It changed since you turned it on (a file of its bundle, its prefix, live query or how it compares), so it's off: turn it on again to use it.")
    }
}

// MARK: - Running it

extension ScriptCommand {
    /// The environment its completion program runs with (0.6.7.1 §2): `base` (as its commands': the login shell's PATH and
    /// the rest) without anything of the protocol's it may hold, then the protocol's version, `ALLINONEIME_COMPLETION`
    /// (`load` or `query`), `ALLINONEIME_LANGUAGE` (the interface's: "en" or "zh"), `ALLINONEIME_EXTENSION_DIR`, and its
    /// bundle's preferences as `ALLINONEIME_PREF_<NAME>` (passwords from the secret store). Nothing of the field: not the
    /// app in front, not the input language, not the token (a query's text is its one argument).
    public func completionEnvironment(_ function: PluginScript.CompletionFunction, base: [String: String], language: String,
                                      preferences: [String: String] = [:]) -> [String: String] {
        var environment = base.filter { !$0.key.uppercased().hasPrefix("ALLINONEIME_") }
        environment["ALLINONEIME_PROTOCOL"] = String(Self.protocolVersion)
        environment["ALLINONEIME_VERSION"] = AppVersion.string
        environment["ALLINONEIME_COMPLETION"] = function.rawValue
        environment["ALLINONEIME_LANGUAGE"] = language
        environment["ALLINONEIME_EXTENSION_DIR"] = extensionDirectory.path
        for (name, value) in preferences { environment[ExtensionBundle.Preference.variable(name)] = value }
        return environment
    }

    /// What its programs share one run at a time (`ExtensionCompletionRunner`): its bundle's name ("bundle:units"), a
    /// single script its own id.
    public var completionTurn: String { source.bundleName.map { "bundle:" + $0 } ?? "script:" + id }
}

/// A call to a script extension's completion program: the command, the environment it runs with
/// (`ScriptCommand.completionEnvironment`), how long it may take (a list 20 seconds, a query 3), and the digest of the
/// extension the user turned its source on with (`ExtensionDigest`: only that one runs; nil: none does), unless it
/// `followsChanges` (the user's own, or from an extension source whose updates are trusted: it runs as it is now).
public struct ExtensionCompletionCall: Sendable {
    public var command: ScriptCommand
    public var environment: [String: String]
    public var timeout: TimeInterval
    public var scriptSHA256: String?
    public var followsChanges: Bool

    public init(command: ScriptCommand, environment: [String: String], timeout: TimeInterval, scriptSHA256: String?,
                followsChanges: Bool = false) {
        self.command = command
        self.environment = environment
        self.timeout = timeout
        self.scriptSHA256 = scriptSHA256
        self.followsChanges = followsChanges
    }
}

/// What runs script extensions' completion programs (0.6.7.1 §2): `load` with no arguments, `query` with what follows the
/// prefix as its one argument; what it printed, as it is (the core reads it as a plugin's script's output,
/// `CompletionOutput.read`). Called off the session's thread; a call the core no longer wants (a newer query) is cancelled
/// as a task is, which stops the program.
public protocol ExtensionCompletionRuntime: Sendable {
    func load(_ call: ExtensionCompletionCall) async throws -> Data
    func query(_ text: String, _ call: ExtensionCompletionCall) async throws -> Data
}

/// Runs script extensions' completion programs as their commands run (`CommandRunner`: its launch, in its folder or its
/// `currentDirectoryPath`, /usr/local/bin on the PATH, its last line on standard error saying why it failed), with the
/// call's environment and limits of its own: a list within 20 seconds, a query within 3, 4 MB of output (a command's
/// 64 KB doesn't apply), nothing on standard input. Only the extension the user turned the source on with runs (its
/// digest, every file of its bundle read again as it starts: an update may have come since), unless it follows its
/// changes (`ExtensionCompletionCall.followsChanges`). One program of a bundle at a time (`completionTurn`: they may
/// share state, a cookie file or a cache), the others waiting their turn; cancelling the task, waiting or running, stops
/// it, and one running passes its turn on once its process has exited (SIGTERM, then SIGKILL after half a second).
public struct ExtensionCompletionRunner: ExtensionCompletionRuntime {
    /// How long a list may take to load, whatever the command's own `timeout`.
    public static let loadTimeout: TimeInterval = PluginManifest.maxTimeout
    /// The most a program may print: a list's 4 MiB, with room for its JSON (as a plugin's script).
    static let maxOutput = PluginCompletionRuntime.maxOutput
    /// The turns every runner shares: one program of a bundle at a time in this process.
    static let turns = ProgramTurns()

    public init() {}

    public func load(_ call: ExtensionCompletionCall) async throws -> Data {
        try await run(call, arguments: [])
    }

    public func query(_ text: String, _ call: ExtensionCompletionCall) async throws -> Data {
        try await run(call, arguments: [text])
    }

    private func run(_ call: ExtensionCompletionCall, arguments: [String]) async throws -> Data {
        let command = call.command
        return try await Self.turns.run(command.completionTurn) {
            try Task.checkCancellation()
            if !call.followsChanges {
                guard let sha = call.scriptSHA256, ExtensionDigest.of(command) == sha.lowercased() else {
                    throw ExtensionCompletionError.scriptChanged
                }
            }
            let output = try await CommandRunner.completionOutput(command, arguments: arguments, environment: call.environment,
                                                                  timeout: call.timeout, maxOutput: Self.maxOutput)
            return Data(output.utf8)
        }
    }
}

/// Why a script extension's completion program didn't run, as Settings says it.
public enum ExtensionCompletionError: Error, LocalizedError, Equatable {
    /// Its extension isn't the one its source was turned on with (a file of its bundle, a single script's file).
    case scriptChanged
    /// A required preference of its bundle isn't set: its title.
    case missingPreference(String)

    public var errorDescription: String? {
        switch self {
        case .scriptChanged:
            return tr("扩展在打开补全以后改过，没有运行", "The extension changed since its suggestions were turned on: not run")
        case let .missingPreference(title):
            return tr("先在设置里填好「\(title)」", "Set “\(title)” in the settings first")
        }
    }
}

/// One program at a time for each turn (`ScriptCommand.completionTurn`): the others wait, in the order they came; one
/// cancelled while it waits leaves the line.
actor ProgramTurns {
    private var running: Set<String> = []
    private var waiting: [String: [(id: Int, resume: CheckedContinuation<Void, Error>)]] = [:]
    private var serial = 0

    /// `operation` run once it is `turn`'s turn, the next one's after it.
    func run<T: Sendable>(_ turn: String, _ operation: @Sendable () async throws -> T) async throws -> T {
        try await take(turn)
        defer { pass(turn) }
        return try await operation()
    }

    /// Whether a program of `turn` runs now, and how many wait (for the tests).
    func state(_ turn: String) -> (running: Bool, waiting: Int) { (running.contains(turn), waiting[turn]?.count ?? 0) }

    private func take(_ turn: String) async throws {
        guard running.contains(turn) else {
            running.insert(turn)
            return
        }
        serial += 1
        let id = serial
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiting[turn, default: []].append((id, continuation))
            }
        } onCancel: {
            Task { await self.leave(id, turn) }
        }
    }

    /// The turn passes to the first waiting, else it's free.
    private func pass(_ turn: String) {
        guard var line = waiting[turn], !line.isEmpty else {
            running.remove(turn)
            return
        }
        let next = line.removeFirst()
        waiting[turn] = line.isEmpty ? nil : line
        next.resume.resume()
    }

    /// The call `id` was cancelled: out of the line, if it still waits.
    private func leave(_ id: Int, _ turn: String) {
        guard let index = waiting[turn]?.firstIndex(where: { $0.id == id }) else { return }
        let left = waiting[turn]!.remove(at: index)
        if waiting[turn]?.isEmpty == true { waiting[turn] = nil }
        left.resume.resume(throwing: CancellationError())
    }
}
