import Foundation

/// The settings for a settings window in another process (Windows' Settings app, over the wire): the document of what
/// there is to set (`document`), one change at a time (`set`), the actions (`perform`: a key saved, a provider tested, a
/// plugin installed or removed, a command saved or deleted), and a revision that moves with each change, here or in the
/// file (`changed`). Everything goes through a `SettingsStore`: the same rules as the Mac's window.
///
/// Safe from any thread: the store is only touched under a lock. A test, a download or an install runs outside it.
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
    private let library: PluginLibrary

    /// Called after each change (here, or found in the file by `checkForChanges`), with the new revision, on the thread
    /// that made it, outside the lock. Set before the service is used.
    public var changed: @Sendable (UInt64) -> Void = { _ in }
    /// Where a provider's key comes from (`APIKeys.source`: the secret store, else the environment).
    public var keySource: @Sendable (Provider) -> APIKeys.Source = { APIKeys.source($0) }
    /// After a plugin is installed or removed: the shell's command lists pick it up.
    public var pluginsChanged: @Sendable () -> Void = {}
    /// Bedrock's credentials for Test Connection, fetched again through the profile's whole chain.
    public var loadCredentials: Converter.CredentialLoader = { try await AWSCredentialResolver.shared.resolve(profile: $0, forceRefresh: true) }
    /// The Notion link's Test.
    public var notionSession: URLSession = NotionAPI.session

    public init(store: SettingsStore, platform: SettingsPlatform, library: PluginLibrary = PluginLibrary()) {
        self.store = store
        self.platform = platform
        self.library = library
        observation = store.observe { [unowned self] change in
            guard !change.intersection([.config, .keys]).isEmpty else { return }
            revisionValue += 1
        }
    }

    /// Moves with each change of the settings or the keys.
    public var revision: UInt64 { locked { revisionValue } }

    /// The settings now (the file read again if something else changed it), for this platform.
    public func document() -> SettingsDocument {
        changing { store.reloadIfChanged() }
        return locked { build().document }
    }

    /// Reads the file again if something else changed it (another process, an editor): `changed` says so.
    public func checkForChanges() {
        changing { store.reloadIfChanged() }
    }

    /// Changes one setting (`Field.id`) to `value`, checked against what the field takes, and saves it.
    public func set(_ id: String, to value: AIConfig.JSONValue) -> Result<Void, SettingsProblem> {
        changing { () -> Result<Void, SettingsProblem> in
            store.reloadIfChanged()
            let built = build()
            guard let field = built.document.field(id) else { return .failure(Self.unknown(id)) }
            if let problem = built.document.loadError.map({ Self.broken($0, id) }) { return .failure(problem) }
            guard field.readOnly != true, let setter = built.setters[id] else {
                return .failure(SettingsProblem(.notChangeable, field: id, message: Self.notChangeable))
            }
            if let problem = Self.check(value, for: field) { return .failure(problem) }
            do {
                try setter(value)
            } catch let problem as SettingsProblem {
                return .failure(problem)
            } catch {
                return .failure(SettingsProblem(.failed, field: id, message: UIText.describe(error)))
            }
            store.save()
            if let error = store.saveError { return .failure(SettingsProblem(.failed, field: id, message: error)) }
            return .success(())
        }
    }

    /// Runs one of a field's `actions`.
    public func perform(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        let found = changing { () -> Result<SettingsDocument.Field, SettingsProblem> in
            store.reloadIfChanged()
            let document = build().document
            guard let field = document.field(action.field) else { return .failure(Self.unknown(action.field)) }
            guard field.actions?.contains(action.name) == true
                    || (action.item != nil && field.items?.contains { $0.actions?.contains(action.name) == true } == true) else {
                return .failure(SettingsProblem(.notChangeable, field: action.field, message: Self.notChangeable))
            }
            return .success(field)
        }
        guard case .success = found else { return found.map { _ in SettingsActionOutcome() } }
        switch action.name {
        case SettingsAction.setKey, SettingsAction.removeKey: return changing { secret(action) }
        case SettingsAction.test: return await test(action)
        case SettingsAction.browse: return await browse(action)
        case SettingsAction.install: return await install(action)
        case SettingsAction.remove: return changing { remove(action) }
        case SettingsAction.save, SettingsAction.delete: return changing { command(action) }
        default: return .failure(SettingsProblem(.notChangeable, field: action.field, message: Self.notChangeable))
        }
    }

    // MARK: Locking

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
        if after != before { changed(after) }
        return result
    }

    // MARK: Actions

    /// `setKey` and `removeKey` on a secret: a provider's API key, the web search key, the Notion token.
    private func secret(_ action: SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem> {
        let setting = action.name == SettingsAction.setKey
        let key = action.key ?? ""
        if setting, key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(SettingsProblem(.badValue, field: action.field, message: tr("没有 key，什么都没保存", "No key: nothing was saved")))
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
                changing { store.useNotion(target) }
                status = .passed(target.label(language: UIText.language))
            } catch {
                status = .failed(UIText.describe(error))
            }
        default:
            return .failure(Self.unknown(action.field))
        }
        changing {
            tests[action.field] = status
            revisionValue += 1  // the status shown
        }
        switch status {
        case let .passed(text): return .success(SettingsActionOutcome(message: "✓ " + text))
        case let .failed(text): return .failure(SettingsProblem(.failed, field: action.field, message: "✗ " + text))
        case .idle, .running: return .success(SettingsActionOutcome())
        }
    }

    /// The plugin library opened: what it offers this version.
    private func browse(_ action: SettingsAction) async -> Result<SettingsActionOutcome, SettingsProblem> {
        switch await SettingsStore.libraryEntries(library) {
        case let .success(entries):
            changing {
                libraryEntries = entries
                revisionValue += 1
            }
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
        if let error = await SettingsStore.install(entry, from: library) {
            return .failure(SettingsProblem(.failed, field: action.field, message: error))
        }
        changing { revisionValue += 1 }
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
            store.deleteCommand(named: name)
            return store.saveError.map { .failure(SettingsProblem(.failed, field: action.field, message: $0)) } ?? .success(SettingsActionOutcome())
        }
        guard let value = action.value, let data = try? JSONEncoder().encode(value),
              let command = try? JSONDecoder().decode(CustomCommand.self, from: data) else {
            return .failure(SettingsProblem(.badValue, field: action.field, message: Self.badValue))
        }
        let plugins = PluginStore.load(from: library.directory).plugins.map(\.name)
        if let problem = command.problem(among: store.otherCommands(than: action.item), plugins: plugins,
                                         unread: store.config.unreadCustomCommandNames) {
            return .failure(SettingsProblem(.badValue, field: action.field, message: UIText.describe(problem)))
        }
        guard store.saveCommand(command, editing: action.item) else {
            return .failure(SettingsProblem(.badValue, field: action.field, message: UIText.describe(.nameTaken)))
        }
        return store.saveError.map { .failure(SettingsProblem(.failed, field: action.field, message: $0)) } ?? .success(SettingsActionOutcome())
    }

    // MARK: Checks

    static var notChangeable: String { tr("这个设置不能这样改", "This setting isn't changed this way") }
    static var badValue: String { tr("这个设置不接受这个值", "This setting doesn't take that value") }

    static func unknown(_ id: String) -> SettingsProblem {
        SettingsProblem(.unknownField, field: id, message: tr("这里没有这个设置", "There's no such setting here"))
    }

    static func broken(_ error: String, _ id: String?) -> SettingsProblem {
        SettingsProblem(.configBroken, field: id, message: tr("配置文件有误，未做修改：", "The config file has an error and was left as is: ") + error)
    }

    /// Whether `value` is one `field` takes, by its kind, bounds and choices.
    static func check(_ value: AIConfig.JSONValue, for field: SettingsDocument.Field) -> SettingsProblem? {
        func bad(_ message: String = badValue) -> SettingsProblem { SettingsProblem(.badValue, field: field.id, message: message) }
        if value == .null {
            return field.optional == true && [.number, .text, .choice].contains(field.kind) ? nil : bad()
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
        case .choice:
            return field.choices?.contains(where: { $0.value == value && $0.disabled != true }) == true ? nil : bad()
        case .choices:
            guard case let .array(values) = value, Set(values.compactMap(\.string)).count == values.count,
                  values.allSatisfy({ value in field.choices?.contains { $0.value == value && $0.disabled != true } == true }) else {
                return bad()
            }
            let low = field.minCount ?? 0, high = field.maxCount ?? Int.max
            if values.count < low || values.count > high {
                return bad(high == Int.max ? tr("至少选 \(low) 个", "Pick at least \(low)") : tr("选 \(low) 到 \(high) 个", "Pick \(low) to \(high)"))
            }
            return nil
        case .words:
            guard case let .array(values) = value, values.allSatisfy({ $0.string != nil }) else { return bad() }
            return nil
        case .secret, .items, .info, .button:
            return SettingsProblem(.notChangeable, field: field.id, message: notChangeable)
        }
    }

    /// A bound as a person writes it: 200, 0.5.
    static func shown(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(format: "%g", number)
    }

    // MARK: The document

    /// The document, and how each changeable field is set (its value already checked against the field).
    private func build() -> (document: SettingsDocument, setters: [String: (AIConfig.JSONValue) throws -> Void]) {
        var builder = SettingsSchema(store: store, platform: platform, keySource: keySource, tests: tests,
                                     libraryEntries: libraryEntries, library: library)
        let sections = builder.sections()
        var document = SettingsDocument(language: UIText.language, platform: platform, loadError: store.loadError,
                                        saveError: store.saveError, sections: sections)
        if store.loadError != nil {
            for s in document.sections.indices {
                for f in document.sections[s].fields.indices where [.toggle, .integer, .number, .text, .choice, .choices, .words]
                    .contains(document.sections[s].fields[f].kind) {
                    document.sections[s].fields[f].readOnly = true
                }
            }
        }
        return (document, builder.setters)
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

}
