import AllInOneIMECore
import AppKit

/// Suggestions (plugin completions and Code's rows, the core's `InputSession+Suggestions`) for the whole input method:
/// the store every field shares (each source's list, its queries' answers, failures and pauses), the plugins' runtime
/// (their completion scripts run as script plugins do, `PluginCompletionRuntime`), "Refresh now", the sources' statuses
/// for Settings → Plugins, the rows picked (kept on this Mac only), the coding packs installed (Code's rows are its coding
/// language's pack's). Main thread only.
@MainActor
enum SuggestionsShared {
    /// What the core keeps in memory for every field of this launch (the self-test puts its own in).
    static var store = SuggestionsStore()
    /// Runs plugins' `load` and `query` (the self-test's: in this process, with its stand-in for the network).
    static var runtime: any CompletionRuntime = PluginCompletionRuntime()
    /// Where the lists are cached on disk, readable by this user only: ~/Library/Caches/AllInOneIME/suggestions/ (nil:
    /// none, the self-test's).
    static var cacheFolder: URL? = CorePaths.cacheDir.appendingPathComponent("suggestions", isDirectory: true)
    /// "Refresh now" pressed in Settings → Plugins, the latest for each source.
    private(set) static var refreshes: [CompletionSourceRefresh] = []
    /// The coding packs installed (`CodingPackStore`, the self-test's own folder while it runs).
    static var packs = CodingPackStore() {
        didSet { installedPacks = nil }
    }
    private static var installedPacks: [CodingLanguagePack]?
    /// The coding packs installed, read again only once one is added or removed here.
    static var codingPacks: [CodingLanguagePack] {
        if let installedPacks { return installedPacks }
        let read = packs.installed()
        installedPacks = read
        return read
    }

    /// A pack was added or removed: read again, Settings told, and the field being typed in (Code may have come or gone).
    static func packsChanged() {
        installedPacks = nil
        NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
        AllInOneIMEInputController.activeController?.applySettings()
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
    /// one whose approval no longer holds is marked so, and a script extension's that follows its changes made what it is
    /// now; a refresh asked for starts).
    static func settingsChanged() {
        if let field = AllInOneIMEInputController.activeController {
            field.received(.configChanged)
        } else {
            // No field: what's disabled (or a custom command that was a source, deleted) is still forgotten now, what no
            // longer holds marked and what follows its extension made what it is, with the plugins and extensions as they are.
            let config = LiveConfig.current
            let extensions = LiveExtensions.current(config).commands
            // A script extension's on with no approval (the user's own, a trusted source's) keeps its list too.
            store.prune(keeping: settings(config).sourceKeys(extensions: extensions), folder: cacheFolder)
            // Only those whose changes turn them off are read (their source's repository), off the main thread (Settings
            // calls this); those that follow, never.
            let (root, store) = (ExtensionSourceGate.root, store)
            let follows = { @Sendable (command: ScriptCommand) in config.followsChanges(of: command, root: root) }
            markLapsed(CompletionSourceApproval.lapsed(config.completionSources, plugins: LivePlugins.current(rescan: true)))
            markFollowed(CompletionSourceApproval.followed(config.completionSources, extensions: extensions, follows: follows))
            DispatchQueue.global(qos: .userInitiated).async {
                let lapsed = CompletionSourceApproval.lapsed(config.completionSources, extensions: extensions, follows: follows,
                                                             digest: { ExtensionDigest.of($0, root: root, sha256: store.sha256(of:)) })
                Task { @MainActor in markLapsed(lapsed) }
            }
        }
        NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
    }

    /// Approvals that no longer hold (their plugin or script extension changed since: `CompletionSourceApproval.lapsed`)
    /// marked so in the config file, kept, once the key or focus being handled is done: Settings says the source changed
    /// since it was turned on, and it stays off until turned on again. (Approvals go only with their plugin,
    /// `SettingsStore.uninstall`, or when turned off.)
    static func markLapsed(_ lapsed: [CompletionSourceApproval]) {
        guard !lapsed.isEmpty else { return }
        DispatchQueue.main.async {
            do {
                var marked = false
                try Config.change { marked = $0.markLapsed(lapsed) }
                guard marked else { return }
                log.notice("suggestions: \(lapsed.count, privacy: .public) approval(s) marked lapsed")
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
            } catch {
                log.error("suggestions: approvals couldn't be marked lapsed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The plugins a scan found (`LivePlugins.found`): one this Mac hasn't found before (just installed, put in the
    /// plugins folder, or there before 0.6.7.2) has its completion sources approved as they are now
    /// (`Config.approveNewPlugins`: on by default), in the config file once the key or focus being handled is done; the
    /// field being typed in takes them in. Nothing is read or written when every plugin was found before, nor while the
    /// config file can't be read.
    static func pluginsFound(_ plugins: [InstalledPlugin]) {
        guard let config = LiveConfig.currentIfValid, config.hasNewPlugins(plugins) else { return }
        DispatchQueue.main.async {
            do {
                var changed = false
                try Config.change { changed = $0.approveNewPlugins(plugins) }
                guard changed else { return }
                log.notice("suggestions: plugins found here for the first time, their completion sources on")
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                settingsChanged()
            } catch {
                log.error("suggestions: new plugins' completion sources couldn't be approved: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Script extensions' approvals that follow their extension (the user's own, a trusted source's:
    /// `CompletionSourceApproval.followed`) made what it is now in the config file, once the key or focus being handled is
    /// done; said nowhere, the source on all along.
    static func markFollowed(_ followed: [CompletionSourceApproval]) {
        guard !followed.isEmpty else { return }
        DispatchQueue.main.async {
            do {
                var changed = false
                try Config.change { changed = $0.follow(followed) }
                guard changed else { return }
                log.notice("suggestions: \(followed.count, privacy: .public) approval(s) follow their extension as it is now")
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                NotificationCenter.default.post(name: .allInOneIMESuggestionsChanged, object: nil)
            } catch {
                log.error("suggestions: approvals couldn't follow their extension: \(String(describing: error), privacy: .public)")
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
        services.translateAsYouType = { MainActor.assumeIsolated { TranslateModeShared.state.isOn } }
        services.setTranslateAsYouType = { on in MainActor.assumeIsolated { field.value?.setTranslateMode(on) } }
        // The rows picked: kept with what else is learned on this Mac (`LearnedShared`).
        services.loadPicks = { MainActor.assumeIsolated { LearnedShared.store.picks } }
        services.recordPick = { pick in MainActor.assumeIsolated { LearnedShared.store.recordPick(pick) } }
        services.reportStatus = { reported($0) }
        services.approvalsLapsed = { lapsed in MainActor.assumeIsolated { markLapsed(lapsed) } }
        services.approvalsFollowed = { followed in MainActor.assumeIsolated { markFollowed(followed) } }
        services.extensionSourcesFolder = ExtensionSourceGate.root
        services.pointer = { MainActor.assumeIsolated { TranslateModeShared.pointer() } }
        services.stickyKeys = { MainActor.assumeIsolated { TranslateModeShared.stickyKeys() } }
        services.shiftHeld = { MainActor.assumeIsolated { TranslateModeShared.shiftHeld() } }
        services.shiftDown = { MainActor.assumeIsolated { TranslateModeShared.shiftDown() } }
        services.holdHint = { MainActor.assumeIsolated { field.value?.translateModeHoldHint() } }
        return services
    }

    /// `plugin`'s preferences as the user set them (off the main thread: the passwords come from the keychain): the
    /// texts from the config, the passwords from the keychain, as extensions' are.
    nonisolated static func pluginPreferences(_ plugin: InstalledPlugin) -> [String: String] {
        let read = { MainActor.assumeIsolated { LiveConfig.current.pluginPreferences[plugin.name] ?? [:] } }
        return PluginPreference.stored(for: plugin, texts: Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read))
    }
}

extension Notification.Name {
    /// Suggestions changed something Settings shows: a source's status, the coding packs. Main thread.
    static let allInOneIMESuggestionsChanged = Notification.Name("AllInOneIMESuggestionsChanged")
}

/// Downloading, listing and removing coding packs for the Code input (Settings → Input, the input menu;
/// `CodingPackLibrary`): a coding language picked whose pack isn't installed (`pick`), the library's offer once fetched,
/// each download's progress and error. Main thread.
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
    /// The language picked for Code whose pack is downloading, or didn't download (`pick`): Settings → Input shows how
    /// that goes. Nil once it's in, or cancelled.
    @Published private(set) var picked: String?
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

    /// Code's coding language picked (`language`, decision 22): `then` gets it at once where its pack is installed; else
    /// the pack is downloaded first (the library's newest for this version), as adding an input language downloads its
    /// pack, with its progress and error in `states`, and `then` gets it once the pack is in (not if that fails or is
    /// cancelled: Code stays as it was).
    func pick(_ language: String, then: @escaping @MainActor (String) -> Void) {
        if installed.contains(where: { $0.language == language }) {
            picked = nil
            return then(language)
        }
        guard tasks[language] == nil else { return }
        picked = language
        states[language] = .downloading(0)
        let library = library
        tasks[language] = Task {
            do {
                try await library.install(language: language) { share in
                    Task { @MainActor in
                        if case .downloading = CodingPackManager.shared.states[language] { CodingPackManager.shared.states[language] = .downloading(share) }
                    }
                }
                states[language] = .idle
                tasks[language] = nil
                if picked == language { picked = nil }
                log.notice("coding pack installed for Code")
                SuggestionsShared.packsChanged()
                reload()
                then(language)
            } catch {
                tasks[language] = nil
                let cancelled = Task.isCancelled || (error as? LanguagePackError) == .cancelled
                states[language] = cancelled ? .idle : .failed(UIText.describe(error))
            }
        }
    }

    /// Whether `language`'s pack is on its way.
    func isDownloading(_ language: String) -> Bool {
        if case .downloading = states[language] { return true }
        return false
    }

    func cancel(_ language: String) {
        tasks[language]?.cancel()
        tasks[language] = nil
        states[language] = .idle
        if picked == language { picked = nil }
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
    /// `menu` with Suggestions' switch after autocomplete's: plugin completions and Code's rows, everywhere (an app's own
    /// choice is in Settings → Apps); on unless turned off here or in Settings → General.
    @MainActor
    func addingSuggestions(to menu: NSMenu) -> NSMenu {
        let config = LiveConfig.currentIfValid
        let item = NSMenuItem(title: tr("建议", "Suggestions"), action: #selector(toggleSuggestions(_:)), keyEquivalent: "")
        item.target = self
        item.state = (config ?? .default).suggestions != false ? .on : .off
        item.isEnabled = config != nil  // don't overwrite a config file that failed to parse
        item.toolTip = tr("插件的补全（比如 #12 → GitHub issue）和代码输入的关键字、代码片段，按 Tab 插入",
                          "Plugins' completions (#12 → a GitHub issue, say) and Code's keywords and snippets: Tab inserts")
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
                let config = try Config.change { $0.suggestions = $0.suggestions == false ? nil : false }
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("suggestions: \(config.suggestions == false ? "off" : "on", privacy: .public)")
                SuggestionsShared.settingsChanged()
            } catch {
                log.error("could not switch suggestions: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
