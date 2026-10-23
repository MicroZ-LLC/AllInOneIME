import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The settings for a settings window in another process (Windows' Settings app, over the wire): the document of what
/// there is to set (`document`), one change at a time (`set`), the actions (`perform`: a key saved, a provider tested, a
/// plugin installed or removed, a command saved or deleted; one that takes a while shown `running` until it is done,
/// and stopped by `cancel`), and a revision that moves with each change, here or in the file (`changed`). Everything goes
/// through a `SettingsStore`: the same rules as the Mac's window.
///
/// Safe from any thread: the store is only touched under a lock, and so are the hooks (`changed`, …), which may be set
/// while it is in use. A test, a download or an install runs outside it.
public final class SettingsService: @unchecked Sendable {
    public let platform: SettingsPlatform
    private let store: SettingsStore
    private let lock = NSRecursiveLock()
    private var observation: SettingsStore.Observation?
    private var revisionValue: UInt64 = 1
    /// The Test buttons' last outcomes, by field.
    private var tests: [String: SettingsStore.TestStatus] = [:]
    /// What the plugin library offers, once browsed (`browse`).
    private var libraryEntries: [PluginIndex.Entry]?
    /// The actions that take a while running now, by field and item (an install's plugin): shown `running`, with
    /// `cancel` among the actions.
    private var runs: [Run: Running] = [:]

    struct Run: Hashable {
        var field: String
        var item: String?
    }

    /// An action running: its task, and its request's answer, which comes from the task or, stopped, at once (a test
    /// whose request doesn't stop when asked is left to end on its own, and what it finds isn't shown).
    final class Running: @unchecked Sendable {
        typealias Outcome = Result<SettingsActionOutcome, SettingsProblem>
        private let lock = NSLock()
        private var answer: Outcome?
        private var waiting: CheckedContinuation<Outcome, Never>?
        private var running: Task<Void, Never>?

        /// The task it runs in: stopped by `stop`, also one set after it.
        var task: Task<Void, Never>? {
            get { lock.lock(); defer { lock.unlock() }; return running }
            set {
                lock.lock()
                running = newValue
                let stopped = answer != nil
                lock.unlock()
                if stopped { newValue?.cancel() }
            }
        }

        /// The answer, once: later ones are left out.
        func answer(_ outcome: Outcome) {
            lock.lock()
            guard answer == nil else { lock.unlock(); return }
            answer = outcome
            let waiting = waiting
            self.waiting = nil
            lock.unlock()
            waiting?.resume(returning: outcome)
        }

        func stop(_ problem: SettingsProblem) {
            task?.cancel()
            answer(.failure(problem))
        }

        var outcome: Outcome {
            get async {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if let answer {
                        lock.unlock()
                        continuation.resume(returning: answer)
                    } else {
                        waiting = continuation
                        lock.unlock()
                    }
                }
            }
        }
    }
    private let library: PluginLibrary
    /// The secret store its keys go to, when not the platform's (`Platform.secrets`): an engine's test mode keeps them
    /// in memory, never in the user's.
    private let secrets: APIKeys.Keychain?
    /// Apps added in the window that have no setting of their own yet: listed until one is set, or they are removed
    /// (a profile that sets nothing isn't saved).
    private let addedApps = SettingsSchema.AddedApps()
    /// The script extensions' files as last read: read again only when they changed.
    private let extensionCache = ExtensionCache()

    /// Called after each change (here, or found in the file by `checkForChanges`), with the new revision, on the thread
    /// that made it, outside the lock; one at a time, the revisions in order (one passed by a later one is left out).
    public var changed: @Sendable (UInt64) -> Void {
        get { hooks.withLock { $0.changed } }
        set { hooks.withLock { $0.changed = newValue } }
    }
    /// Where a provider's key comes from (`APIKeys.source`: the secret store, else the environment).
    public var keySource: @Sendable (Provider) -> APIKeys.Source {
        get { hooks.withLock { $0.keySource } }
        set { hooks.withLock { $0.keySource = newValue } }
    }
    /// After a plugin is installed or removed: the shell's command lists pick it up.
    public var pluginsChanged: @Sendable () -> Void {
        get { hooks.withLock { $0.pluginsChanged } }
        set { hooks.withLock { $0.pluginsChanged = newValue } }
    }
    /// The apps typed in lately (`win:notepad.exe`, a bundle id), latest first: offered when an app is added.
    public var recentApps: @Sendable () -> [String] {
        get { hooks.withLock { $0.recentApps } }
        set { hooks.withLock { $0.recentApps = newValue } }
    }
    /// Bedrock's credentials for Test Connection, fetched again through the profile's whole chain.
    public var loadCredentials: Converter.CredentialLoader {
        get { hooks.withLock { $0.loadCredentials } }
        set { hooks.withLock { $0.loadCredentials = newValue } }
    }
    /// The Notion link's Test.
    public var notionSession: URLSession {
        get { hooks.withLock { $0.notionSession } }
        set { hooks.withLock { $0.notionSession = newValue } }
    }
    /// The interface language the settings say (their `uiLanguage`, else the system's): what the document, the problems
    /// and the outcomes are in, whatever the process's own is (`UIText.scopedLanguage`). Windows' engine picks it as its
    /// panel does (Windows' own list of languages).
    public var interfaceLanguage: @Sendable (Config) -> String {
        get { hooks.withLock { $0.interfaceLanguage } }
        set { hooks.withLock { $0.interfaceLanguage = newValue } }
    }

    /// What the owner hooks in, and the last revision `changed` was called with.
    private struct Hooks {
        var changed: @Sendable (UInt64) -> Void = { _ in }
        var keySource: @Sendable (Provider) -> APIKeys.Source = { APIKeys.source($0) }
        var pluginsChanged: @Sendable () -> Void = {}
        var recentApps: @Sendable () -> [String] = { [] }
        var loadCredentials: Converter.CredentialLoader = { try await AWSCredentialResolver.shared.resolve(profile: $0, forceRefresh: true) }
        var notionSession: URLSession = NotionAPI.session
        var interfaceLanguage: @Sendable (Config) -> String = { config in
            InterfaceLanguage.code(forSetting: config.uiLanguage, shipped: UIText.shipped) ?? UIText.systemLanguage
        }
        var notified: UInt64 = 1
    }

    private let hooks = Locked(initialState: Hooks())
    /// Held while `changed` is called: one call at a time, in the order of the revisions.
    private let notifying = NSLock()

    public init(store: SettingsStore, platform: SettingsPlatform, library: PluginLibrary = PluginLibrary(),
                secrets: APIKeys.Keychain? = nil) {
        self.store = store
        self.platform = platform
        self.library = library
        self.secrets = secrets
        // Any change: the config, a key, the file turned unreadable or a save that failed (the document says so).
        observation = store.observe { [unowned self] _ in revisionValue += 1 }
    }

    /// Moves with each change of the settings or the keys.
    public var revision: UInt64 { locked { revisionValue } }

    /// The settings now (the file read again if something else changed it), for this platform.
    public func document() -> SettingsDocument {
        current().document
    }

    /// The settings now and their revision, together (`document`'s, read again first if the file changed), in the
    /// interface language they say: one just changed shows at once.
    public func current() -> (revision: UInt64, document: SettingsDocument) {
        changing { store.reloadIfChanged() }
        return scoped { locked { (revisionValue, build().document) } }
    }

    /// Reads the file again if something else changed it (another process, an editor): `changed` says so.
    public func checkForChanges() {
        changing { store.reloadIfChanged() }
    }

    /// Changes one setting (`Field.id`) to `value`, checked against what the field takes, and saves it.
    ///
    /// Made on the settings as a window showed them, it may say which: `revision` (the document's), and the change is
    /// refused (`stale`) when the settings changed since; or, for a list, `shown` (the list the window showed), and
    /// `value` is taken as the window's edit of it, made on the list as it is now (`edited`): what was added elsewhere
    /// meanwhile stays. With neither, `value` is the field's new value, whatever happened since.
    public func set(_ id: String, to value: AIConfig.JSONValue, revision: UInt64? = nil,
                    shown: AIConfig.JSONValue? = nil) -> Result<Void, SettingsProblem> {
        scoped { setting(id, to: value, revision: revision, shown: shown) }
    }

    private func setting(_ id: String, to value: AIConfig.JSONValue, revision: UInt64?,
                         shown: AIConfig.JSONValue?) -> Result<Void, SettingsProblem> {
        changing { () -> Result<Void, SettingsProblem> in
            store.reloadIfChanged()
            if let revision, revision != revisionValue { return .failure(Self.stale(id)) }
            let built = build()
            guard let field = built.document.field(id) else { return .failure(Self.unknown(id)) }
            if let problem = built.document.loadError.map({ Self.broken($0, id) }) { return .failure(problem) }
            guard field.readOnly != true, let setter = built.setters[id] else {
                return .failure(SettingsProblem(.notChangeable, field: id, message: Self.notChangeable))
            }
            var value = value
            if let shown {
                switch Self.edited(value, shown: shown, of: field, rules: .init(platform)) {
                case let .success(edited): value = edited
                case let .failure(problem): return .failure(problem)
                }
            }
            if let problem = Self.check(value, for: field) { return .failure(problem) }
            return saving(id) {
                do {
                    try setter(value)
                } catch let problem as SettingsProblem {
                    return problem
                } catch {
                    return SettingsProblem(.failed, field: id, message: UIText.describe(error))
                }
                return nil
            }
        }
    }

    /// `change` (a problem: refused), then saved: `failed` when a save it made, or the one after it, failed (the store
    /// went back to the file as it was, and its `saveError` says why). A change that saves nothing clears an earlier
    /// failure: the file has what is shown.
    private func saving(_ id: String?, _ change: () -> SettingsProblem?) -> Result<Void, SettingsProblem> {
        let failures = store.failedSaves
        if let problem = change() { return .failure(problem) }
        // A rule that saved and failed has nothing left to save: saving again would clear its error.
        if store.failedSaves == failures { store.save() }
        guard store.failedSaves == failures else {
            return .failure(SettingsProblem(.failed, field: id, message: store.saveError ?? ""))
        }
        return .success(())
    }

    /// The actions that run a while (a test, a download): `perform` them; any other is done at once (`performNow`).
    public static let longActions = [SettingsAction.test, SettingsAction.browse, SettingsAction.install]

    /// Whether an action runs a while (a test, a download): `perform` it; any other is done at once (`performNow`).
    public static func takesAWhile(_ action: SettingsAction) -> Bool {
        longActions.contains(action.name)
    }

    /// Runs one of a field's `actions`.
    public func perform(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        await UIText.$scopedLanguage.withValue(language) {
            guard let secrets else { return await performing(action) }
            var platform = Platform.current
            platform.secrets = secrets
            return await Platform.$override.withValue(platform) { await performing(action) }
        }
    }

    /// Runs an action that is done at once (`takesAWhile` false), on the caller's thread; one that takes a while is
    /// refused (`perform` it).
    public func performNow(_ action: SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem> {
        scoped { () -> Result<SettingsActionOutcome, SettingsProblem> in
            if let problem = check(action) { return .failure(problem) }
            return now(action)
        }
    }

    private func performing(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        if let problem = check(action) { return .failure(problem) }
        guard Self.takesAWhile(action) else { return now(action) }
        return await running(action)
    }

    /// An action that takes a while, in a task of its own: shown `running` (the document's revision moves when it starts
    /// and when it is done). Another of the same field and item replaces it, as the Mac's Test does, and `cancel` stops
    /// it: its request is then answered `cancelled`, and what it would have shown isn't.
    private func running(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        let run = Run(field: action.field, item: action.item)
        let running = Running()
        changing {
            runs[run]?.stop(Self.cancelled(action.field))
            runs[run] = running
            if action.name == SettingsAction.test { tests[action.field] = nil }  // the last outcome, gone while it runs
            revisionValue += 1
            // Started under the lock: a `cancel` finds it.
            running.task = Task { running.answer(await longAction(action)) }
        }
        let result = await withTaskCancellationHandler { await running.outcome } onCancel: {
            running.stop(Self.cancelled(action.field))
        }
        changing {
            guard runs[run] === running else { return }  // stopped or replaced: shown already
            runs[run] = nil
            revisionValue += 1  // done, and what it found
        }
        return result
    }

    private func longAction(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        switch action.name {
        case SettingsAction.test: return await test(action)
        case SettingsAction.browse: return await browse(action)
        default: return await install(action)
        }
    }

    /// `cancel`: what runs for the field (and the item, if one is named) stopped. Nothing running (done already):
    /// nothing to do.
    private func cancel(_ action: SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem> {
        let stopped = runs.keys.filter { $0.field == action.field && (action.item == nil || $0.item == action.item) }
        guard !stopped.isEmpty else { return .success(SettingsActionOutcome()) }
        for run in stopped { runs.removeValue(forKey: run)?.stop(Self.cancelled(run.field)) }
        revisionValue += 1
        return .success(SettingsActionOutcome())
    }

    /// The actions done at once.
    private func now(_ action: SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem> {
        // The schema's own (an app added or removed, a folder, an extension's password), else the service's: saved as
        // the service's are, and, but for a password, nothing changed while the file can't be read.
        if let done = changing({ () -> Result<SettingsActionOutcome, SettingsProblem>? in
            guard let handler = build().handlers[action.field] else { return nil }
            if let error = store.loadError, ![SettingsAction.setKey, SettingsAction.removeKey].contains(action.name) {
                return .failure(Self.broken(error, action.field))
            }
            var outcome = SettingsActionOutcome()
            let done = saving(action.field) { () -> SettingsProblem? in
                switch handler(action) {
                case let .success(done): outcome = done
                case let .failure(problem): return problem
                }
                return nil
            }
            if case .success = done { revisionValue += 1 }  // the document changed (an app added: the store didn't)
            return done.map { outcome }
        }) {
            return done
        }
        switch action.name {
        case SettingsAction.setKey, SettingsAction.removeKey: return changing { secret(action) }
        case SettingsAction.remove: return changing { remove(action) }
        case SettingsAction.save, SettingsAction.delete: return changing { command(action) }
        case SettingsAction.cancel: return changing { cancel(action) }
        default: return .failure(SettingsProblem(.notChangeable, field: action.field, message: Self.notChangeable))
        }
    }

    /// Whether the field is there and has the action (or an item of it does). `cancel` is for a field with an action
    /// that takes a while, running or not (done meanwhile: nothing to stop).
    private func check(_ action: SettingsAction) -> SettingsProblem? {
        let found = changing { () -> Result<SettingsDocument.Field, SettingsProblem> in
            store.reloadIfChanged()
            let document = build().document
            guard let field = document.field(action.field) else { return .failure(Self.unknown(action.field)) }
            let actions = (field.actions ?? []) + (field.items ?? []).flatMap { $0.actions ?? [] }
            if action.name == SettingsAction.cancel, actions.contains(where: Self.longActions.contains) { return .success(field) }
            guard field.actions?.contains(action.name) == true
                    || (action.item != nil && field.items?.contains { $0.actions?.contains(action.name) == true } == true) else {
                return .failure(SettingsProblem(.notChangeable, field: action.field, message: Self.notChangeable))
            }
            return .success(field)
        }
        if case let .failure(problem) = found { return problem }
        return nil
    }

    // MARK: Locking

    /// `body` in the settings' interface language, and with the keys in `secrets` when the service has its own.
    private func scoped<T>(_ body: () -> T) -> T {
        UIText.$scopedLanguage.withValue(language) {
            guard let secrets else { return body() }
            var platform = Platform.current
            platform.secrets = secrets
            return Platform.$override.withValue(platform, operation: body)
        }
    }

    /// The interface language the settings say now (`interfaceLanguage`).
    private var language: String { interfaceLanguage(locked { store.config }) }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// `body` under the lock, then `changed` with the new revision if it moved.
    private func changing<T>(_ body: () -> T) -> T {
        let (result, before, after) = locked { () -> (T, UInt64, UInt64) in
            let before = revisionValue
            let result = body()
            return (result, before, revisionValue)
        }
        if after != before { notify(after) }
        return result
    }

    /// `changed(revision)`, unless a later revision was told already (two threads' changes: the later one's covers both).
    private func notify(_ revision: UInt64) {
        notifying.lock()
        defer { notifying.unlock() }
        let changed = hooks.withLock { hooks -> (@Sendable (UInt64) -> Void)? in
            guard revision > hooks.notified else { return nil }
            hooks.notified = revision
            return hooks.changed
        }
        changed?(revision)
    }

    // MARK: Actions

    /// `setKey` and `removeKey` on a secret: a provider's API key, the web search key, the Notion token.
    private func secret(_ action: SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem> {
        let setting = action.name == SettingsAction.setKey
        let key = action.key ?? ""
        if setting, key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(SettingsProblem(.badValue, field: action.field, message: Self.noKey))
        }
        let error: String?
        switch action.field {
        case "search.key": error = setting ? store.saveSearchKey(key) : store.removeSearchKey()
        case "notes.notionToken": error = setting ? store.saveNotionToken(key) : store.removeNotionToken()
        default:
            guard let provider = Self.keyProvider(action.field) else { return .failure(Self.unknown(action.field)) }
            error = setting ? store.saveKey(key, for: provider) : store.removeKey(provider)
        }
        if action.field == "search.key" { tests[action.field] = nil }
        if let error { return .failure(SettingsProblem(.failed, field: action.field, message: error)) }
        return .success(SettingsActionOutcome())
    }

    /// The provider a key field is for: "anthropic.key".
    private static func keyProvider(_ field: String) -> Provider? {
        guard field.hasSuffix(".key"), let provider = Provider(rawValue: String(field.dropLast(4))),
              [.anthropic, .gemini, .openai].contains(provider) else { return nil }
        return provider
    }

    /// Test Connection, the web search's Test, the Notion link's (its `value`: the link; none, the page kept).
    private func test(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        let status: SettingsStore.TestStatus
        switch action.field {
        case "provider.test":
            let config = locked { store.config }
            status = await SettingsStore.testConnection(config, loadCredentials: loadCredentials)
        case "search.key":
            status = await SettingsStore.testSearch()
        case "notes.notion":
            guard action.value == nil || action.value?.string != nil else {
                return .failure(SettingsProblem(.badValue, field: action.field, message: Self.badValue))
            }
            let kept = locked { store.config.notes.notion }
            do {
                let target = try await SettingsStore.resolveNotion(link: action.value?.string ?? "", kept: kept, session: notionSession)
                guard !Task.isCancelled else { return .failure(Self.cancelled(action.field)) }
                changing { store.useNotion(target) }
                status = .passed(target.label(language: UIText.language))
            } catch {
                status = .failed(UIText.describe(error))
            }
        default:
            return .failure(Self.unknown(action.field))
        }
        // Stopped (`cancel`, or another run of it): what it found isn't shown.
        guard !Task.isCancelled else { return .failure(Self.cancelled(action.field)) }
        locked { tests[action.field] = status }  // shown with the revision `running` moves when it is done
        switch status {
        case let .passed(text): return .success(SettingsActionOutcome(message: "✓ " + text))
        case let .failed(text): return .failure(SettingsProblem(.failed, field: action.field, message: "✗ " + text))
        case .idle, .running: return .success(SettingsActionOutcome())
        }
    }

    /// The plugin library opened: what it offers this version.
    private func browse(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        let found = await SettingsStore.libraryEntries(library)
        guard !Task.isCancelled else { return .failure(Self.cancelled(action.field)) }
        switch found {
        case let .success(entries):
            locked { libraryEntries = entries }  // shown with the revision `running` moves when it is done
            return .success(SettingsActionOutcome())
        case let .failure(error):
            return .failure(SettingsProblem(.failed, field: action.field, message: error.message))
        }
    }

    /// A library plugin installed or updated.
    private func install(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        guard store.persists else { return .success(SettingsActionOutcome()) }
        guard let entry = locked({ libraryEntries?.first { $0.name == action.item } }) else {
            return .failure(SettingsProblem(.badValue, field: action.field, message: Self.badValue))
        }
        // Installed, though cancelled meanwhile: done, and shown. Not installed: cancelled, or why.
        if let error = await SettingsStore.install(entry, from: library) {
            return .failure(Task.isCancelled ? Self.cancelled(action.field) : SettingsProblem(.failed, field: action.field, message: error))
        }
        if Task.isCancelled { changing { revisionValue += 1 } }  // its request answered already: the change is told
        pluginsChanged()
        return .success(SettingsActionOutcome())
    }

    /// An installed plugin removed.
    private func remove(_ action: SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem> {
        guard let plugin = PluginStore.load(from: library.directory).plugins.first(where: { $0.name == action.item }) else {
            return .failure(SettingsProblem(.badValue, field: action.field, message: Self.badValue))
        }
        if let error = store.uninstall(plugin) { return .failure(SettingsProblem(.failed, field: action.field, message: error)) }
        revisionValue += 1
        pluginsChanged()
        return .success(SettingsActionOutcome())
    }

    /// A custom command saved (`value`: its definition; `item`: the name it had, none for a new one) or deleted
    /// (`item`), by name, with the editor's rules.
    private func command(_ action: SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem> {
        guard store.canSave else { return .failure(Self.broken(store.loadError ?? "", action.field)) }
        if action.name == SettingsAction.delete {
            guard let name = action.item, store.config.customCommands.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
                return .failure(SettingsProblem(.badValue, field: action.field, message: Self.badValue))
            }
            return saving(action.field) {
                store.deleteCommand(named: name)
                return nil
            }.map { SettingsActionOutcome() }
        }
        // The form's command (`argv`) as typed, a command line: split as the Mac's editor splits it.
        var definition = action.value
        if case var .object(keys)? = definition, case let .string(line)? = keys["argv"] {
            guard let argv = CustomCommand.arguments(fromCommandLine: line, rules: .init(platform)) else {
                return .failure(SettingsProblem(.badValue, field: action.field, message: UIText.describe(.unbalancedQuote)))
            }
            keys["argv"] = argv.isEmpty ? nil : .array(argv.map(AIConfig.JSONValue.string))
            definition = .object(keys)
        }
        guard let value = definition, let data = try? JSONEncoder().encode(value),
              let command = try? JSONDecoder().decode(CustomCommand.self, from: data) else {
            return .failure(SettingsProblem(.badValue, field: action.field, message: Self.badValue))
        }
        let plugins = PluginStore.load(from: library.directory).plugins.map(\.name)
        if let problem = command.problem(among: store.otherCommands(than: action.item), plugins: plugins,
                                         unread: store.config.unreadCustomCommandNames) {
            return .failure(SettingsProblem(.badValue, field: action.field, message: UIText.describe(problem)))
        }
        return saving(action.field) {
            store.saveCommand(command, editing: action.item)
                ? nil : SettingsProblem(.badValue, field: action.field, message: UIText.describe(.nameTaken))
        }.map { SettingsActionOutcome() }
    }

    // MARK: Checks

    static var notChangeable: String { tr("这个设置不能这样改", "This setting isn't changed this way") }
    static var noKey: String { tr("没有 key，什么都没保存", "No key: nothing was saved") }
    static var badValue: String { tr("这个设置不接受这个值", "This setting doesn't take that value") }

    static func cancelled(_ id: String?) -> SettingsProblem {
        SettingsProblem(.cancelled, field: id, message: tr("已取消", "Cancelled"))
    }

    static func stale(_ id: String?) -> SettingsProblem {
        SettingsProblem(.stale, field: id, message: tr("设置刚在别处改过，没有改动；这里是现在的设置",
                                                       "The settings changed meanwhile: nothing was changed, and here they are now"))
    }

    static func unknown(_ id: String) -> SettingsProblem {
        SettingsProblem(.unknownField, field: id, message: tr("这里没有这个设置", "There's no such setting here"))
    }

    static func broken(_ error: String, _ id: String?) -> SettingsProblem {
        SettingsProblem(.configBroken, field: id, message: tr("配置文件有误，未做修改：", "The config file has an error and was left as is: ") + error)
    }

    /// Whether `value` is one `field` takes, by its kind, bounds and choices.
    static func check(_ value: AIConfig.JSONValue, for field: SettingsDocument.Field) -> SettingsProblem? {
        func bad(_ message: String = badValue) -> SettingsProblem { SettingsProblem(.badValue, field: field.id, message: message) }
        if value == .null, field.kind != .choice {
            return field.optional == true && [.number, .text].contains(field.kind) ? nil : bad()
        }
        switch field.kind {
        case .toggle:
            return value.bool == nil ? bad() : nil
        case .integer, .number:
            guard case let .number(number) = value, number.isFinite else { return bad() }
            if field.kind == .integer, number.rounded() != number { return bad() }
            let low = field.min ?? -.infinity, high = field.max ?? .infinity
            if number < low || number > high {
                return bad(tr("要在 \(shown(low)) 到 \(shown(high)) 之间", "Between \(shown(low)) and \(shown(high))"))
            }
            if field.kind == .integer, let step = field.step, let min = field.min,
               (number - min).truncatingRemainder(dividingBy: step) != 0 {
                return bad()
            }
            return nil
        case .text:
            return value.string == nil ? bad() : nil
        // A `disabled` choice (another platform's, one this version doesn't offer) may be kept, not picked: only as
        // the value now, or among it.
        case .choice:
            return field.choices?.contains(where: { $0.value == value && ($0.disabled != true || value == field.value ?? .null) }) == true
                ? nil : bad()
        case .choices:
            let now = field.value?.array ?? []
            guard case let .array(values) = value, Set(values.compactMap(\.string)).count == values.count,
                  values.allSatisfy({ value in
                      field.choices?.contains { $0.value == value && ($0.disabled != true || now.contains(value)) } == true
                  }) else {
                return bad()
            }
            let low = field.minCount ?? 0, high = field.maxCount ?? Int.max
            if values.count < low || values.count > high {
                return bad(high == Int.max ? tr("至少选 \(low) 个", "Pick at least \(low)") : tr("选 \(low) 到 \(high) 个", "Pick \(low) to \(high)"))
            }
            return nil
        case .words:
            // The list, or the line its `text` shows (split by the field's setter).
            if field.text != nil, value.string != nil { return nil }
            guard case let .array(values) = value, values.allSatisfy({ $0.string != nil }) else { return bad() }
            return nil
        case .secret, .items, .info, .button:
            return SettingsProblem(.notChangeable, field: field.id, message: notChangeable)
        }
    }

    // MARK: Lists edited elsewhere meanwhile

    /// A list field's new value, `value`, as a window edited it from `shown` (the list it showed), made an edit of the
    /// list as it is now (`field.value`): what the window took out goes, what it added is added, and what was added
    /// elsewhere meanwhile stays (taken out elsewhere, it stays out). Words (`redaction.customWords`) by the Mac's rule
    /// (`RedactionSettings.edited`); a list of choices keeps the window's order of what it showed (`merged`). A list
    /// whose order is its meaning (`agentCommand`, a command's arguments) isn't merged: changed since, it is `stale`.
    /// A `words` field with a line (`text`) may be sent as lines: the one it showed, and the one edited (a command line
    /// split by `rules`, the system's).
    static func edited(_ value: AIConfig.JSONValue, shown: AIConfig.JSONValue, of field: SettingsDocument.Field,
                       rules: CustomCommand.LineRules = .shell) -> Result<AIConfig.JSONValue, SettingsProblem> {
        let now = field.value?.strings ?? []
        /// The list a value stands for: a line split as the field's setter splits it.
        func list(_ value: AIConfig.JSONValue) -> [String]? {
            guard field.kind == .words, field.text != nil, let line = value.string else { return value.strings }
            return field.ordered == true ? CustomCommand.arguments(fromCommandLine: line, rules: rules) : RedactionSettings.words(from: line)
        }
        guard [.words, .choices].contains(field.kind), let shown = list(shown) else {
            return .failure(SettingsProblem(.badValue, field: field.id, message: badValue))
        }
        // Not merged: the value as it came (a line too, which the setter splits), if nothing changed since.
        if field.kind == .words, field.ordered == true {
            return now == shown ? .success(value) : .failure(stale(field.id))
        }
        guard let list = list(value) else { return .failure(SettingsProblem(.badValue, field: field.id, message: badValue)) }
        switch field.kind {
        case .words:
            return .success(.array(RedactionSettings.edited(now, to: list, shown: shown).map(AIConfig.JSONValue.string)))
        default:
            return .success(.array(merged(now, shown: shown, edited: list).map(AIConfig.JSONValue.string)))
        }
    }

    /// `now` after a window's edit of the list from `shown` to `edited`, in the window's order: what it shows that was
    /// taken out elsewhere meanwhile stays out, and what was added elsewhere (in `now`, never shown) goes back in after
    /// the item it came after in `now` (first, when none did).
    static func merged(_ now: [String], shown: [String], edited: [String]) -> [String] {
        var result = edited.filter { !shown.contains($0) || now.contains($0) }
        for (index, item) in now.enumerated() where !shown.contains(item) && !result.contains(item) {
            let after = now[..<index].last(where: result.contains).flatMap { result.firstIndex(of: $0) }
            result.insert(item, at: after.map { $0 + 1 } ?? 0)
        }
        return result
    }

    /// A bound as a person writes it: 200, 0.5.
    static func shown(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(format: "%g", number)
    }

    // MARK: The document

    /// The document, how each changeable field is set (its value already checked against the field), and the schema's
    /// own actions.
    private func build() -> (document: SettingsDocument, setters: [String: (AIConfig.JSONValue) throws -> Void],
                             handlers: [String: SettingsSchema.Handler]) {
        var builder = SettingsSchema(store: store, platform: platform, keySource: keySource, tests: tests,
                                     libraryEntries: libraryEntries, library: library)
        builder.recentApps = recentApps()
        builder.addedApps = addedApps
        builder.extensions = ExtensionStore.load(ExtensionStore.folders(store.config, found: []), cache: extensionCache)
        // Its text names commands with the trigger its settings have, whatever the process's own is.
        let sections = UIText.$scopedCommandTrigger.withValue(store.config.commandTrigger) { builder.sections() }
        var document = SettingsDocument(language: UIText.language, platform: platform, loadError: store.loadError,
                                        saveError: store.saveError, sections: sections, strings: UIText.settingsWindowStrings)
        // What runs now: `running`, and `cancel` to stop it.
        for s in document.sections.indices {
            for f in document.sections[s].fields.indices {
                let id = document.sections[s].fields[f].id
                if runs[Run(field: id, item: nil)] != nil {
                    document.sections[s].fields[f].running = true
                    document.sections[s].fields[f].actions = (document.sections[s].fields[f].actions ?? []) + [SettingsAction.cancel]
                }
                for i in (document.sections[s].fields[f].items ?? []).indices {
                    guard let item = document.sections[s].fields[f].items?[i], runs[Run(field: id, item: item.id)] != nil else { continue }
                    document.sections[s].fields[f].items?[i].running = true
                    document.sections[s].fields[f].items?[i].actions = (item.actions ?? []) + [SettingsAction.cancel]
                }
            }
        }
        if store.loadError != nil {
            for s in document.sections.indices {
                document.sections[s].fields = document.sections[s].fields.map(Self.readOnly)
            }
        }
        return (document, builder.setters, builder.handlers)
    }

    /// A field shown, not changed (the file can't be read), and so are an item's own fields.
    static func readOnly(_ field: SettingsDocument.Field) -> SettingsDocument.Field {
        var field = field
        if [.toggle, .integer, .number, .text, .choice, .choices, .words].contains(field.kind) { field.readOnly = true }
        field.items = field.items?.map { item in
            var item = item
            item.fields = item.fields?.map(readOnly)
            return item
        }
        return field
    }
}

extension AIConfig.JSONValue {
    var string: String? {
        if case let .string(text) = self { return text }
        return nil
    }

    var bool: Bool? {
        if case let .bool(on) = self { return on }
        return nil
    }

    var number: Double? {
        if case let .number(number) = self { return number }
        return nil
    }

    var array: [AIConfig.JSONValue]? {
        if case let .array(values) = self { return values }
        return nil
    }
}
