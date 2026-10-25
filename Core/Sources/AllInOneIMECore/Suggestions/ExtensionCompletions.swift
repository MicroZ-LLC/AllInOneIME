import Foundation

// Script extensions as completion sources (0.6.7.1 §2): a command of a script extension may declare one completion
// source, with a plugin's `completions` entry's keys and meaning (docs/plugins.md), its name and title the command's. One
// kind of source: the session takes it with the plugins' and the custom commands' (`InputSession.ActiveSource`), the
// store keeps it as theirs under `CompletionSourceKey(extension:)` (its list, the disk cache, back-off and pause, statuses,
// "Refresh now", the picks), its approval is a `CompletionSourceApproval` in `Config.completionSources` (off until turned
// on in Settings → Commands; a change to its script, prefix, query, queryMinChars or compare turns it off again), its
// rows, keys and insertions are theirs. What differs is where its items come from: its script, run as its commands run
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

extension CompletionSourceApproval {
    /// What turning on `source`, `command`'s, approves now (0.6.7.1 §2): its script's SHA-256, whether it queries, and its
    /// terms as a plugin's (`Terms`: its prefix, from which character it queries, how it compares). No hosts: what its
    /// script reaches is its own. Nil: its script can't be read.
    public init?(enabling source: CompletionSource, of command: ScriptCommand) {
        guard let sha = PluginStore.sha256(of: command.file) else { return nil }
        let key = CompletionSourceKey(extension: command)
        self.init(plugin: key.plugin, source: key.source, hosts: [], query: source.query, scriptSHA256: sha, terms: Terms(source))
    }

    /// What turning on the source `command` declares approves now (`init(enabling:of:)`). Nil: it declares none, or one
    /// refused, or its script can't be read.
    public init?(enabling command: ScriptCommand) {
        guard case let .success(source)? = command.completion else { return nil }
        self.init(enabling: source, of: command)
    }

    /// Whether it still holds for `source` of `command` as they are now: the same script, query and terms (prefix,
    /// queryMinChars and compare), compared as a plugin's are: a change to its script file, `prefix`, `query`,
    /// `queryMinChars` or `compare` turns the source off again; one without terms never holds. Never once marked lapsed.
    public func holds(for source: CompletionSource, of command: ScriptCommand) -> Bool {
        guard let sha = PluginStore.sha256(of: command.file) else { return false }
        return holds(forScript: source, of: command, scriptSHA256: sha)
    }

    /// `holds(for:of:)` with its script's SHA-256 as it is now.
    func holds(forScript source: CompletionSource, of command: ScriptCommand, scriptSHA256 sha: String) -> Bool {
        guard !lapsed, let terms, CompletionSourceKey(plugin: plugin, source: self.source) == CompletionSourceKey(extension: command)
        else { return false }
        return query == source.query && scriptSHA256 == sha && terms == Terms(source)
    }

    /// The approvals of `enabled` not marked lapsed yet that no longer hold for the script extensions' `commands` as they
    /// are now (`holds(for:of:)`): their command declares a source that reads, and its script is there, changed since. One
    /// whose command isn't there, declares none or one refused has nothing to compare with: it doesn't lapse (it isn't on
    /// meanwhile). `sha256`: a script's SHA-256 (nil: none to read).
    public static func lapsed(_ enabled: [CompletionSourceApproval], extensions commands: [ScriptCommand],
                              sha256: (URL) -> String? = PluginStore.sha256(of:)) -> [CompletionSourceApproval] {
        let extensionApprovals = enabled.filter { !$0.lapsed && $0.plugin == CompletionSourceKey.scriptExtensions }
        guard !extensionApprovals.isEmpty else { return [] }
        return extensionApprovals.filter { approval in
            guard let command = commands.first(where: { $0.id == approval.source }), case let .success(source)? = command.completion,
                  let sha = sha256(command.file) else { return false }
            return !approval.holds(forScript: source, of: command, scriptSHA256: sha)
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

    /// What a script extension's source turned on before its script, prefix, query or terms changed says (Settings →
    /// Commands, the Mac's and the settings document's): it is off until turned on again.
    public static var scriptChanged: String {
        tr("脚本、前缀、实时查询或比较方式改过了，已经关掉：要用的话再打开一次。",
           "Its script, prefix, live query or how it compares changed since you turned it on, so it's off: turn it on again to use it.")
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
/// (`ScriptCommand.completionEnvironment`), how long it may take (a list 20 seconds, a query 3), and the SHA-256 of the
/// script the user turned its source on with (only that one runs; nil: none does).
public struct ExtensionCompletionCall: Sendable {
    public var command: ScriptCommand
    public var environment: [String: String]
    public var timeout: TimeInterval
    public var scriptSHA256: String?

    public init(command: ScriptCommand, environment: [String: String], timeout: TimeInterval, scriptSHA256: String?) {
        self.command = command
        self.environment = environment
        self.timeout = timeout
        self.scriptSHA256 = scriptSHA256
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
/// 64 KB doesn't apply), nothing on standard input. Only the script the user turned the source on with runs (its SHA-256,
/// checked as it starts: an update may have come since). One program of a bundle at a time (`completionTurn`: they may
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
            guard let sha = call.scriptSHA256, PluginStore.sha256(of: command.file) == sha.lowercased() else {
                throw ExtensionCompletionError.scriptChanged
            }
            let output = try await CommandRunner.completionOutput(command, arguments: arguments, environment: call.environment,
                                                                  timeout: call.timeout, maxOutput: Self.maxOutput)
            return Data(output.utf8)
        }
    }
}

/// Why a script extension's completion program didn't run, as Settings says it.
public enum ExtensionCompletionError: Error, LocalizedError, Equatable {
    /// Its script isn't the one its source was turned on with.
    case scriptChanged
    /// A required preference of its bundle isn't set: its title.
    case missingPreference(String)

    public var errorDescription: String? {
        switch self {
        case .scriptChanged:
            return tr("脚本在打开补全以后改过，没有运行", "The script changed since its suggestions were turned on: not run")
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
