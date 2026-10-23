import AllInOneIMECore
import AppKit

/// Suggestions (plugin completions and coding mode, the core's `InputSession+Suggestions`) for the whole input method:
/// the store every field shares (each source's list, its queries' answers, failures and pauses), the plugins' runtime
/// (their completion scripts run as script plugins do, `PluginCompletionRuntime`), coding mode (on across fields and apps
/// until turned off, as Translate as You Type), "Refresh now", the sources' statuses for Settings → Plugins, the rows
/// picked (kept on this Mac only), the coding packs installed. Main thread only.
@MainActor
enum SuggestionsShared {
    /// What the core keeps in memory for every field of this launch (the self-test puts its own in).
    static var store = SuggestionsStore()
    /// Runs plugins' `load` and `query` (the self-test's: in this process, with its stand-in for the network).
    static var runtime: any CompletionRuntime = PluginCompletionRuntime()
    /// Where the lists are cached on disk, readable by this user only: ~/Library/Caches/AllInOneIME/suggestions/ (nil:
    /// none, the self-test's).
    static var cacheFolder: URL? = CorePaths.cacheDir.appendingPathComponent("suggestions", isDirectory: true)
    /// Coding mode: the session turns it on and off from its chooser (a long press of Shift); the menu bar icon shows it.
    static var codingMode = false {
        didSet {
            guard codingMode != oldValue else { return }
            log.notice("coding mode \(codingMode ? "on" : "off", privacy: .public)")
            MenuBarIcon.shared.setCoding(codingMode)
            NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
        }
    }
    /// "Refresh now" pressed in Settings → Plugins, the latest for each source.
    private(set) static var refreshes: [CompletionSourceRefresh] = []
    /// The coding packs installed (`CodingPackStore`, the self-test's own folder while it runs).
    static var packs = CodingPackStore() {
        didSet { installedPacks = nil }
    }
    private static var installedPacks: [CodingLanguagePack]?
    /// The rows picked (`SuggestionPick`), oldest first, the latest kept (`SuggestionPicks`).
    static var picks = SuggestionPicks()

    /// The coding packs installed, read again only once one is added or removed here.
    static var codingPacks: [CodingLanguagePack] {
        if let installedPacks { return installedPacks }
        let read = packs.installed()
        installedPacks = read
        return read
    }

    /// A pack was added or removed: read again, the fields told.
    static func packsChanged() {
        installedPacks = nil
        NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
    }

    /// The switches as the settings have them now, with "Refresh now".
    static func settings(_ config: Config) -> SuggestionsSettings { config.suggestionsSettings(refreshes: refreshes) }

    /// "Refresh now" for a source: loaded again at once, paused or not (spec 6.17).
    static func refreshNow(plugin: String, source: String) {
        refreshes.removeAll { $0.plugin == plugin && $0.source == source }
        refreshes.append(CompletionSourceRefresh(plugin: plugin, source: source, requested: Date()))
        settingsChanged()
    }

    /// The settings of suggestions changed (a source enabled or disabled, "Refresh now", a plugin removed): the field
    /// being typed in takes them in at once (a source disabled, or its plugin removed, is forgotten, its cache deleted;
    /// one whose approval no longer holds is marked so; a refresh asked for starts).
    static func settingsChanged() {
        if let field = AllInOneIMEInputController.activeController {
            field.received(.configChanged)
        } else {
            // No field: what's disabled is still forgotten now, and what no longer holds marked, with the plugins as they are.
            let enabled = LiveConfig.current.completionSources
            store.prune(keeping: Set(enabled.map { CompletionSourceKey(plugin: $0.plugin, source: $0.source) }), folder: cacheFolder)
            markLapsed(CompletionSourceApproval.lapsed(enabled, plugins: LivePlugins.current(rescan: true)))
        }
        NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
    }

    /// Approvals that no longer hold (their plugin changed since: `CompletionSourceApproval.lapsed`) marked so in the
    /// config file, kept, once the key or focus being handled is done: Settings says the source changed since it was
    /// turned on, and it stays off until turned on again. (Approvals go only with their plugin, `SettingsStore.uninstall`,
    /// or when turned off.)
    static func markLapsed(_ lapsed: [CompletionSourceApproval]) {
        guard !lapsed.isEmpty else { return }
        DispatchQueue.main.async {
            do {
                var config = try Config.load()
                guard config.markLapsed(lapsed) else { return }
                try config.write()
                log.notice("suggestions: \(lapsed.count, privacy: .public) approval(s) marked lapsed")
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
            } catch {
                log.error("suggestions: approvals couldn't be marked lapsed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A source's status changed (from any thread): Settings → Plugins shows it.
    nonisolated static func reported(_ status: CompletionSourceStatus) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
        }
    }

    /// The services suggestions ask of this Mac: this file's, with `field` turning Translate as You Type on and off.
    static func services(field: WeakBox<AllInOneIMEInputController>) -> SuggestionsServices {
        var services = SuggestionsServices()
        services.store = store
        services.runtime = runtime
        services.settings = { MainActor.assumeIsolated { settings(LiveConfig.current) } }
        services.cacheFolder = cacheFolder
        services.preferences = { plugin in pluginPreferences(plugin) }
        services.codingPacks = { MainActor.assumeIsolated { codingPacks } }
        services.codingMode = { MainActor.assumeIsolated { codingMode } }
        services.setCodingMode = { on in MainActor.assumeIsolated { codingMode = on } }
        services.translateAsYouType = { MainActor.assumeIsolated { TranslateModeShared.state.isOn } }
        services.setTranslateAsYouType = { on in MainActor.assumeIsolated { field.value?.setTranslateMode(on) } }
        services.loadPicks = { MainActor.assumeIsolated { picks.all } }
        services.recordPick = { pick in MainActor.assumeIsolated { picks.record(pick) } }
        services.reportStatus = { reported($0) }
        services.approvalsLapsed = { lapsed in MainActor.assumeIsolated { markLapsed(lapsed) } }
        services.pointer = { MainActor.assumeIsolated { TranslateModeShared.pointer() } }
        services.stickyKeys = { MainActor.assumeIsolated { TranslateModeShared.stickyKeys() } }
        services.shiftHeld = { MainActor.assumeIsolated { TranslateModeShared.shiftHeld() } }
        services.shiftDown = { MainActor.assumeIsolated { TranslateModeShared.shiftDown() } }
        services.chooserHint = { MainActor.assumeIsolated { chooserHint } }
        return services
    }

    /// Half way through a long press of Shift, near the caret: what keeping on holding leads to (the chooser opens with
    /// that mode highlighted).
    static var chooserHint: String {
        if TranslateModeShared.state.isOn { return tr("继续按住 → 关闭边打边译", "Keep holding → Translate as You Type off") }
        if codingMode { return tr("继续按住 → 关闭编码模式", "Keep holding → Coding mode off") }
        return tr("继续按住 → 边打边译", "Keep holding → Translate as You Type")
    }

    /// `plugin`'s preferences as the user set them (off the main thread: the passwords come from the keychain): the
    /// texts from the config, the passwords from the keychain, as extensions' are.
    nonisolated static func pluginPreferences(_ plugin: InstalledPlugin) -> [String: String] {
        let read = { MainActor.assumeIsolated { LiveConfig.current.pluginPreferences[plugin.name] ?? [:] } }
        return PluginPreference.stored(for: plugin, texts: Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read))
    }
}

/// The rows picked (inserted), oldest first: rows picked before come first by frecency (`Frecency`). Kept on this Mac
/// only, in the app's data folder (suggestion-picks.json, readable by this user only): the source and the item's
/// `match` (a plugin's, a coding pack's keyword or snippet), never the field's own words. The latest 500.
@MainActor
struct SuggestionPicks {
    static let limit = 500
    /// Where they're kept (the self-test's own while it runs; nil: in memory only).
    var url: URL? = CorePaths.dataDir.appendingPathComponent("suggestion-picks.json")
    private var loaded: [SuggestionPick]?

    var all: [SuggestionPick] {
        mutating get {
            if let loaded { return loaded }
            let read = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([SuggestionPick].self, from: $0) } ?? []
            loaded = read
            return read
        }
    }

    mutating func record(_ pick: SuggestionPick) {
        let picks = Array((all + [pick]).suffix(Self.limit))
        loaded = picks
        guard let url, let data = try? JSONEncoder().encode(picks) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Platform.current.files.writePrivate(data, to: url)
        }
    }

    /// Forgets them all (Settings → General → Suggestions).
    mutating func clear() {
        loaded = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}

extension Notification.Name {
    /// Suggestions changed something Settings shows: a source's status, coding mode, the packs. Main thread.
    static let allInOneIMESuggestionsChanged = Notification.Name("AllInOneIMESuggestionsChanged")
}

/// Downloading, listing and removing coding packs for Settings → Coding languages (`CodingPackLibrary`): the library's
/// offer once fetched, each download's progress and error. Main thread.
@MainActor
final class CodingPackManager: ObservableObject {
    static let shared = CodingPackManager()

    enum State: Equatable {
        case idle
        case downloading(Double)
        case failed(String)
    }

    /// The library's packs (nil: not fetched yet), and why fetching them failed.
    @Published private(set) var offered: [CodingPackIndex.Entry]?
    @Published private(set) var offerError: String?
    @Published private(set) var fetching = false
    @Published private(set) var states: [String: State] = [:]
    /// The packs installed.
    @Published private(set) var installed: [CodingLanguagePack] = []
    /// The library (the self-test's own while it runs).
    var library = CodingPackLibrary()
    private var tasks: [String: Task<Void, Never>] = [:]

    init() { installed = SuggestionsShared.codingPacks }

    func reload() { installed = SuggestionsShared.codingPacks }

    /// The library's offer, fetched (network only now, when Settings asks).
    func fetch() {
        guard !fetching else { return }
        fetching = true
        offerError = nil
        let library = library
        Task {
            do {
                let index = try await library.fetchIndex()
                offered = library.offered(in: index)
            } catch {
                offerError = UIText.describe(error)
            }
            fetching = false
        }
    }

    func download(_ entry: CodingPackIndex.Entry) {
        guard tasks[entry.language] == nil else { return }
        states[entry.language] = .downloading(0)
        let library = library
        let language = entry.language
        tasks[language] = Task {
            do {
                try await library.install(entry) { share in
                    Task { @MainActor in
                        if case .downloading = CodingPackManager.shared.states[language] { CodingPackManager.shared.states[language] = .downloading(share) }
                    }
                }
                states[language] = .idle
                log.notice("coding pack installed")
            } catch {
                states[language] = .failed(UIText.describe(error))
            }
            tasks[language] = nil
            SuggestionsShared.packsChanged()
            reload()
        }
    }

    func cancel(_ language: String) {
        tasks[language]?.cancel()
        tasks[language] = nil
        states[language] = .idle
    }

    func remove(_ language: String) {
        do {
            try SuggestionsShared.packs.remove(language)
            states[language] = .idle
        } catch {
            states[language] = .failed(UIText.describe(error))
        }
        SuggestionsShared.packsChanged()
        reload()
    }
}

extension AllInOneIMEInputController {
    /// `menu` with Suggestions' switch after autocomplete's: plugin completions and coding mode's rows, everywhere (an
    /// app's own choice is in Settings → Apps); on unless turned off here.
    @MainActor
    func addingSuggestions(to menu: NSMenu) -> NSMenu {
        let config = LiveConfig.currentIfValid
        let item = NSMenuItem(title: tr("建议", "Suggestions"), action: #selector(toggleSuggestions(_:)), keyEquivalent: "")
        item.target = self
        item.state = (config ?? .default).suggestions != false ? .on : .off
        item.isEnabled = config != nil  // don't overwrite a config file that failed to parse
        item.toolTip = tr("插件的补全（比如 #12 → GitHub issue）和编码模式的关键字、代码片段，按 Tab 插入",
                          "Plugins' completions (#12 → a GitHub issue, say) and coding mode's keywords and snippets: Tab inserts")
        let after = menu.items.lastIndex {
            $0.action == #selector(toggleAutocomplete(_:)) || $0.tag == Self.autocompleteDestinationTag
                || $0.action == #selector(toggleImproveTranslates(_:))
        }.map { $0 + 1 } ?? menu.items.count
        menu.insertItem(item, at: after)
        return menu
    }

    /// Suggestions on or off everywhere (`Config.suggestions`; on is the default, written as none).
    @objc func toggleSuggestions(_ sender: Any?) {
        MainActor.assumeIsolated {
            do {
                var config = try Config.load()
                config.suggestions = config.suggestions == false ? nil : false
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("suggestions: \(config.suggestions == false ? "off" : "on", privacy: .public)")
                SuggestionsShared.settingsChanged()
            } catch {
                log.error("could not switch suggestions: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
