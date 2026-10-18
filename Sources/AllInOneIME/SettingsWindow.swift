import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import AuthenticationServices
import Carbon
import SwiftUI
import UniformTypeIdentifiers

/// Models offered in the settings window (any Bedrock model / inference-profile ID can be typed in).
/// Measured on 10 everyday sentences with the default presets (2026-10).
struct SuggestedModel: Identifiable, Hashable {
    let id: String
    let title: String
    let note: String

    /// The models offered for `provider` (any other ID can be typed in).
    static func suggested(for provider: Provider) -> [SuggestedModel] {
        switch provider {
        case .bedrock: return all
        case .anthropic:
            return [
                SuggestedModel(id: "claude-haiku-5-5", title: "Claude Haiku 5.5", note: tr("默认：最快、最便宜", "Default: fastest, cheapest")),
                SuggestedModel(id: "claude-sonnet-5-5", title: "Claude Sonnet 5.5", note: tr("更用心，慢一些", "More careful, slower")),
                SuggestedModel(id: "claude-opus-5-5", title: "Claude Opus 5.5", note: tr("最强，最慢最贵", "Most capable, slowest, priciest")),
            ]
        case .gemini:
            return [SuggestedModel(id: "gemini-3.8-flash", title: "Gemini 3.8 Flash", note: tr("默认", "Default"))]
        case .hosted, .apple:
            return []  // the service (the system) picks the model
        case .openai:
            // OpenAI's own; for another service (DeepSeek, Qwen, Ollama, …), "Custom…" and its base URL.
            return [
                SuggestedModel(id: "gpt-6-luna", title: "GPT-6 Luna", note: tr("默认：最快、最省", "Default: fastest, cheapest", key: "models.openaiDefault")),
                SuggestedModel(id: "gpt-5.4-mini", title: "GPT-5.4 mini", note: tr("上一代 mini", "The previous mini")),
            ]
        }
    }

    static var all: [SuggestedModel] {
        [
            SuggestedModel(id: "us.anthropic.claude-haiku-4-5-20251001-v1:0", title: "Claude Haiku 4.5",
                           note: tr("推荐：约 1.3 秒，质量好", "Recommended: about 1.3 s, good quality")),
            SuggestedModel(id: "us.anthropic.claude-sonnet-4-6", title: "Claude Sonnet 4.6",
                           note: tr("约 2.2 秒，改写最用心", "About 2.2 s, the most careful rewrites")),
            SuggestedModel(id: "us.amazon.nova-2-lite-v1:0", title: "Amazon Nova 2 Lite",
                           note: tr("约 1 秒，最便宜，润色偏弱", "About 1 s, cheapest, weaker polish")),
        ]
    }
}

/// State of the settings window. Every change is written to the config file right away;
/// the input method re-reads it for each translation, so nothing needs a restart.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config
    @Published private(set) var loadError: String?
    @Published private(set) var saveError: String?
    @Published private(set) var profiles: [String] = []
    @Published private(set) var testStatus: TestStatus = .idle
    /// Where the API key of each provider comes from (refreshed when one is saved), and the last 4 characters kept
    /// with a saved one (`APIKeys.keyEnding`: the key isn't read).
    @Published private(set) var keySources: [Provider: APIKeys.Source] = [:]
    @Published private(set) var keyEndings: [Provider: String] = [:]
    @Published private(set) var keyError: String?
    /// The apps that get no typos (`TypoMemory`), as when the window opened or they were forgotten.
    @Published private(set) var typoApps: [String] = TypoMemory.apps

    func forgetTypoApps() {
        TypoMemory.forget()
        typoApps = TypoMemory.apps
    }

    /// How many recent `@question`s are kept (`QuestionHistoryStore`), as when the window opened or they were cleared.
    @Published private(set) var recentQuestions = QuestionHistoryStore.history.entries.count

    /// "Clear": a Clear for every Mac syncing the recent questions through iCloud too (`ICloudSyncController`).
    func clearRecentQuestions() {
        QuestionHistoryStore.clear()
        recentQuestions = 0
        if persists { ICloudSyncController.shared.questionsCleared() }
    }

    /// "Remember recent questions" switched in the window: off deletes the ones kept (on this Mac only: no Clear for the
    /// other Macs). Only from the switch: a config read again with it off (the Assistant turned it off, and may still
    /// undo that) keeps them.
    func setRememberQuestions(_ on: Bool) {
        config.rememberQuestions = on
        guard !on else { return }
        // Marked first, so that a sync running meanwhile never takes the deletion for a Clear.
        if persists { ICloudSyncController.shared.questionsForgotten() }
        QuestionHistoryStore.clear()
        recentQuestions = 0
    }

    /// Questions asked since the window opened.
    func refreshRecentQuestions() {
        recentQuestions = QuestionHistoryStore.history.entries.count
    }

    enum TestStatus: Equatable {
        case idle
        case running
        case passed(String)
        case failed(String)
    }

    let configURL: URL
    /// False for previews/screenshots: nothing is ever written.
    private let persists: Bool
    private var testTask: Task<Void, Never>?
    /// Screenshots only: the name shown for the selected AWS profile. README images are public and a
    /// profile is often named after its owner; the keys, region and Test Connection (测试连接) still use the real one.
    var profileShownAs: String?
    /// The AWS profiles' kinds and the chosen one's status line (`AWSProfileSettings`).
    let aws = AWSProfileModel()

    /// When the config file was last read or written here: changed since (the input method's menu, an
    /// editor), it is read again before the window shows it (`reloadIfChanged`).
    private var fileDate: Date?

    init(configURL: URL = Config.defaultURL, persists: Bool = true) {
        self.configURL = configURL
        self.persists = persists
        fileDate = Self.modificationDate(configURL)
        do {
            config = try Config.load(from: configURL)
            written = config
        } catch {
            // Keep the broken file untouched: the window shows the error instead of overwriting it.
            config = .default
            loadError = UIText.describe(error)
        }
        profiles = AWSSharedConfig.profileNames()
        if !profiles.contains(config.awsProfile) { profiles.insert(config.awsProfile, at: 0) }
    }

    var canSave: Bool { loadError == nil }

    /// The config as the file has it (read or last written here): a save writes only what differs from it.
    private var written: Config?

    /// Writes the settings changed in the window since the file was read or last written here, and only those
    /// (`AIConfig.writing`), down to an app's profile and each switch of hiding sensitive information: a value written
    /// meanwhile by sync through iCloud, Settings → Assistant or by hand that the window hasn't read yet stays as it is, and so do keys this version
    /// doesn't know. Nothing is written when nothing changed (opening the window, moving through its fields, ⏎ on one
    /// left as it was, closing it). The window then shows the file as it now is.
    func save() {
        guard canSave, persists, config != written else { return }
        do {
            if let written {
                try AIConfig.writing(config, from: written, keys: AIConfig.changedKeys(written, config), at: configURL)
            } else {
                try config.write(to: configURL)
            }
            let now = (try? Config.load(from: configURL)) ?? config
            written = now
            if now != config { config = now }  // what was written elsewhere meanwhile, now shown
            fileDate = Self.modificationDate(configURL)
            saveError = nil
        } catch {
            saveError = tr("保存失败：", "Couldn't save: ") + error.localizedDescription
        }
    }

    /// Reads the config file again if something else changed it, so the window shows it and its next save
    /// doesn't put back what was there before.
    func reloadIfChanged() {
        guard persists, case let date = Self.modificationDate(configURL), date != fileDate else { return }
        fileDate = date
        do {
            config = try Config.load(from: configURL)
            written = config
            loadError = nil
        } catch {
            loadError = UIText.describe(error)
        }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Switches the window's language at once (a config value, `Config.uiLanguage`; nil: follow the system) and saves
    /// the choice.
    func setUILanguage(_ language: String?) {
        UIText.choice = language  // before the change is published, so the window redraws in it
        config.uiLanguage = language
        save()
        SettingsWindow.shared.updateTitle()
    }

    /// Shows or removes the menu bar icon (the self-test passes its own).
    var applyMenuBarIcon: @MainActor (Bool) -> Void = { MenuBarIcon.shared.apply($0) }

    /// The menu bar icon's switch: saved, and the icon shown or removed at once (not by a preview).
    func setMenuBarIcon(_ on: Bool) {
        config.menuBarIcon = on
        save()
        if persists { applyMenuBarIcon(on) }
    }

    // MARK: Fuzzy pinyin

    /// Fuzzy pinyin couldn't be applied: the Rime folder has the user's own `rime_ice.custom.yaml`.
    @Published private(set) var fuzzyBlocked = false
    /// Writes the patch and deploys Rime again (the self-test's preview model doesn't).
    var applyFuzzyPinyin: @MainActor ([String]) -> FuzzyPinyin.Outcome? = { RimeFuzzy.apply($0) }
    /// What turning it on picks: the pairs most often mixed up.
    static let fuzzyDefaults = ["z-zh", "c-ch", "s-sh", "en-eng", "in-ing"]

    func setFuzzyPinyin(_ ids: [String]) {
        config.fuzzyPinyin = FuzzyPinyin.known(ids)
        save()
        guard persists else { return }
        fuzzyBlocked = applyFuzzyPinyin(config.fuzzyPinyin) == .userFile
    }

    func setFuzzy(_ id: String, on: Bool) {
        setFuzzyPinyin(on ? config.fuzzyPinyin + [id] : config.fuzzyPinyin.filter { $0 != id })
    }

    // MARK: Styles

    func isStyleOn(_ style: RewriteStyle) -> Bool {
        RewriteStyle.resolve(config.rewriteStyles).contains(style)
    }

    func setStyle(_ style: RewriteStyle, on: Bool) {
        guard on != isStyleOn(style) else { return }
        config.rewriteStyles = AllInOneIMEInputController.toggled(style.name, in: config.rewriteStyles)
        save()
    }

    /// The styles in this order (dragged in the window): the candidates follow it.
    func setStyleOrder(_ names: [String]) {
        config.rewriteStyles = names
        save()
    }

    // MARK: Provider

    /// False in the self-test: none of its windows asks the user's keychain or shell which keys there are.
    static var looksUpKeys = true
    /// Bumped by each look: only the latest one's answer is shown.
    private var keyLookups = 0

    func refreshKeys() {
        let providers = Provider.allCases.filter { $0 != .bedrock }
        // A preview (the self-test's README images) shows no keys, or the sample ones given (`showKeys`), and never asks
        // the user's keychain.
        guard persists, Self.looksUpKeys else {
            if !keysShown { keySources = Dictionary(uniqueKeysWithValues: providers.map { ($0, APIKeys.Source.none) }) }
            return
        }
        keyLookups += 1
        // As the Assistant's requests and checks look (`AIConfigSession.keySource`).
        let lookup = AIConfigSession.keySource, generation = keyLookups
        Task.detached {
            // The first look asks the user's shell for its variables (ANTHROPIC_API_KEY, …): not on the main thread.
            let sources = Dictionary(uniqueKeysWithValues: providers.map { ($0, lookup($0)) })
            let endings = Dictionary(uniqueKeysWithValues: providers.compactMap { provider in
                APIKeys.keyEnding(account: provider.rawValue).map { (provider, $0) }
            })
            await MainActor.run { [weak self] in
                // One that started earlier (the window opening) never overwrites a later one's (a key just saved).
                guard let self, self.keyLookups == generation else { return }
                self.keySources = sources
                self.keyEndings = endings
            }
        }
    }

    /// The README images: keys as given (`persists` false: nothing is looked up or saved).
    func showKeys(_ sources: [Provider: APIKeys.Source], endings: [Provider: String] = [:]) {
        keySources = sources
        keyEndings = endings
        keysShown = true
    }
    private var keysShown = false

    /// Whether the provider's key is set, as its row shows it.
    func keyState(_ provider: Provider) -> KeyState {
        KeyState(keySources[provider], ending: keyEndings[provider])
    }

    /// The key sheet's Save and Use: the key saved, then the provider switched to and Test Connection run.
    func saveKeyAndUse(_ key: String, for provider: Provider) {
        guard persists, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveKey(key, for: provider)
        guard keyError == nil else { return }
        config.provider = provider
        save()
        if let testRunner { testRunner() } else { runTest() }
    }

    /// The self-test's stand-in for Test Connection after Save and Use (nil: the real one).
    var testRunner: (() -> Void)?

    /// Stores the provider's API key in the keychain. An empty or blank one does nothing: it never removes the key
    /// saved (that's `removeKey`, after the user confirmed).
    func saveKey(_ key: String, for provider: Provider) {
        guard persists, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            // Tied to the base URL it is saved with: it isn't sent to another one set later.
            try APIKeys.save(key, for: provider, host: HTTPProviders.host(of: config.settings(for: provider)))
            keyError = nil
        } catch {
            keyError = tr("无法保存到钥匙串：", "Couldn't save to the keychain: ") + UIText.describe(error)
        }
        refreshKeys()
    }

    /// Removes the provider's API key from the keychain: Remove Key…, confirmed.
    func removeKey(_ provider: Provider) {
        guard persists else { return }
        do {
            try APIKeys.remove(provider)
            log.notice("Settings: the \(provider.rawValue, privacy: .public) key removed (Remove Key…, confirmed)")
            keyError = nil
        } catch {
            keyError = tr("无法从钥匙串里删除：", "Couldn't remove it from the keychain: ") + UIText.describe(error)
        }
        refreshKeys()
    }

    /// "✓ Saved · ends in a1b2", "✓ From $OPENAI_API_KEY", "No API key yet".
    func keyStatus(_ provider: Provider) -> String {
        keyState(provider).text(missing: tr("还没有 API key", "No API key yet"))
    }

    /// The settings of an API-key provider as stored (unset fields use the defaults).
    func providerSettings(_ provider: Provider) -> ProviderSettings {
        switch provider {
        case .anthropic: return config.anthropic
        case .gemini: return config.gemini
        case .openai: return config.openai
        case .bedrock, .hosted, .apple: return ProviderSettings()
        }
    }

    func setProviderSettings(_ settings: ProviderSettings, for provider: Provider) {
        switch provider {
        case .anthropic: config.anthropic = settings
        case .gemini: config.gemini = settings
        case .openai: config.openai = settings
        case .bedrock, .hosted, .apple: return
        }
        save()
    }

    // MARK: Web search (@search)

    /// Where the web search key comes from (nil until looked up), the last save's error, and the test.
    @Published private(set) var searchKeySource: APIKeys.Source?
    @Published private(set) var searchKeyEnding: String?
    @Published private(set) var searchKeyError: String?
    @Published private(set) var searchTestStatus: TestStatus = .idle
    private var searchTestTask: Task<Void, Never>?

    func refreshSearchKey() {
        // A preview (the self-test's README images) shows no key and never asks the user's keychain.
        guard persists, Self.looksUpKeys else {
            searchKeySource = APIKeys.Source.none
            return
        }
        Task.detached {
            // The first look asks the user's shell for its variables (BRAVE_API_KEY): not on the main thread.
            let source = WebSearch.keySource()
            let ending = APIKeys.keyEnding(account: WebSearch.backend.keyAccount)
            await MainActor.run { [weak self] in
                self?.searchKeySource = source
                self?.searchKeyEnding = ending
            }
        }
    }

    /// Stores the web search key in the keychain, never in the config; an empty one does nothing (`removeSearchKey`).
    func saveSearchKey(_ key: String) {
        guard persists, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try WebSearch.saveKey(key)
            searchKeyError = nil
        } catch {
            searchKeyError = tr("无法保存到钥匙串：", "Couldn't save to the keychain: ") + UIText.describe(error)
        }
        searchTestStatus = .idle
        refreshSearchKey()
    }

    /// Removes the web search key: Remove Key…, confirmed.
    func removeSearchKey() {
        guard persists else { return }
        do {
            try WebSearch.removeKey()
            searchKeyError = nil
        } catch {
            searchKeyError = tr("无法从钥匙串里删除：", "Couldn't remove it from the keychain: ") + UIText.describe(error)
        }
        searchTestStatus = .idle
        refreshSearchKey()
    }

    var searchKeyState: KeyState { KeyState(searchKeySource, ending: searchKeyEnding) }

    /// One search with the key as it is kept, to see that it works.
    func testSearch() {
        searchTestTask?.cancel()
        searchTestStatus = .running
        let query = tr("输入法", "input method")
        searchTestTask = Task { [weak self] in
            let started = Date()
            do {
                let key = await Task.detached { WebSearch.loadKey() }.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !key.isEmpty else {
                    throw WebSearch.SearchError.missingKey(variable: WebSearch.backend.keyVariables.first ?? "")
                }
                let first = try await WebSearch.search(query, key: key).first
                let shown = first.map { $0.title.isEmpty ? $0.url : $0.title } ?? ""
                self?.searchTestStatus = .passed(String(format: tr("%.1f 秒：%@", "%.1f s: %@"), Date().timeIntervalSince(started), shown))
            } catch {
                self?.searchTestStatus = .failed(UIText.describe(error))
            }
        }
    }

    // MARK: AllInOneIME Cloud (the hosted provider)

    @Published private(set) var account: HostedAccount?
    @Published private(set) var accountBusy = false
    @Published private(set) var accountError: String?
    private var authSession: ASWebAuthenticationSession?
    private let presenter = AuthPresenter()

    func refreshAccount() {
        // A preview shows no account: the user's session token stays in the keychain.
        guard persists, HostedService.isConfigured else { return }
        Task { [weak self] in
            do {
                let account = try await HostedAccount.current()
                self?.account = account
                self?.accountError = nil
            } catch {
                self?.accountError = UIText.describe(error)
            }
        }
    }

    /// Signing in (or up) on the user pool's page in the system's authentication sheet, then the service's session.
    func signIn(_ method: HostedSignIn.Method) {
        let signIn = HostedSignIn()
        accountBusy = true
        accountError = nil
        let session = ASWebAuthenticationSession(url: signIn.authorizationURL(method),
                                                 callbackURLScheme: HostedService.callbackScheme) { [weak self] url, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.accountBusy = false }
                if let error {
                    // Closing the sheet is not an error worth showing.
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.accountError = error.localizedDescription
                    }
                    return
                }
                guard let url, let code = signIn.code(from: url) else {
                    self.accountError = tr("没有拿到登录结果", "The sign-in didn't come back")
                    return
                }
                do {
                    let idToken = try await signIn.idToken(for: code)
                    self.account = try await HostedAccount.signIn(idToken: idToken)
                    self.config.provider = .hosted
                    self.save()
                } catch {
                    self.accountError = UIText.describe(error)
                }
            }
        }
        session.presentationContextProvider = presenter
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        if !session.start() {
            accountBusy = false
            accountError = tr("无法打开登录页面", "Couldn't open the sign-in page")
        }
    }

    func signOut() {
        try? HostedAccount.signOut()
        account = nil
    }

    func subscribe() {
        guard let account, let sub = account.sub, let url = HostedService.checkoutURL(sub: sub, email: account.email) else { return }
        NSWorkspace.shared.open(url)
    }

    func manageSubscription() {
        guard let url = URL(string: HostedService.portalLink), !HostedService.portalLink.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Plugins

    @Published private(set) var plugins: [InstalledPlugin] = []
    @Published private(set) var skippedPlugins: [PluginStore.Skipped] = []
    @Published private(set) var pluginError: String?

    func refreshPlugins() {
        (plugins, skippedPlugins) = PluginStore.load()
        updateLibraryStatus()
    }

    func uninstall(_ plugin: InstalledPlugin) {
        guard persists else { return }
        do {
            try PluginStore.uninstall(plugin)
            pluginError = nil
        } catch {
            pluginError = tr("无法删除插件：", "Couldn't remove the plugin: ") + error.localizedDescription
        }
        refreshPlugins()
        _ = LivePlugins.current(rescan: true)  // the command list drops it right away
    }

    /// Opens the plugins folder (made first), where a plugin folder can be put by hand.
    func openPluginsFolder() {
        try? FileManager.default.createDirectory(at: PluginStore.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(PluginStore.directory)
    }

    // MARK: Script extensions

    /// The folders looked in, what's in them (`ExtensionIndex`), the names each command got, and what was left
    /// out (with the names another command has: `Command.hiddenScripts`).
    @Published private(set) var extensionFolders: [ExtensionStore.Folder] = []
    @Published private(set) var extensionIndex = ExtensionIndex.empty
    @Published private(set) var extensionNames: [String: String] = [:]
    @Published private(set) var skippedExtensions: [ExtensionStore.Skipped] = []
    /// The commands on but left out of the list because another command has their name: id → why.
    @Published private(set) var hiddenExtensions: [String: ScriptCommand.Problem] = [:]
    /// The password preferences saved in the keychain ("bundle/name"): only whether they are, never their value.
    @Published private(set) var passwordsSaved: Set<String> = []
    /// Their last 4 characters, where kept ("bundle/name" → "a1b2").
    @Published private(set) var passwordEndings: [String: String] = [:]
    @Published private(set) var extensionError: String?

    /// Reads the folders again; `discover`: Spotlight looks for Raycast script folders first, in the background
    /// (not for a preview), and the list follows when it's done.
    func refreshExtensions(discover: Bool = false) {
        extensionFolders = ExtensionStore.folders(config, found: LiveExtensions.found)
        let index = LiveExtensions.load(config)
        extensionIndex = index
        let enabled = index.enabled(config.disabledExtensions)
        let hidden = Command.hiddenScripts(enabled, custom: config.customCommands, plugins: plugins)
        extensionNames = Dictionary(Command.catalog(config.customCommands, plugins: plugins, scripts: enabled)
            .compactMap { command in command.script.map { ($0.id, command.name) } }, uniquingKeysWith: { first, _ in first })
        skippedExtensions = index.skipped
        hiddenExtensions = Dictionary(hidden.map { ($0.script.id, .nameTaken($0.script.name, by: $0.owner)) }, uniquingKeysWith: { first, _ in first })
        // Whether each is saved, not its value (that could ask for the keychain); none in a preview.
        passwordsSaved = persists ? Set(index.bundles.flatMap { bundle in
            bundle.preferences.filter { $0.kind == .password }.compactMap { preference in
                APIKeys.hasKeychainKey(account: ExtensionBundle.Preference.keychainAccount(bundle: bundle.name, name: preference.name))
                    ? bundle.name + "/" + preference.name : nil
            }
        }) : []
        passwordEndings = persists ? Dictionary(index.bundles.flatMap { bundle in
            bundle.preferences.filter { $0.kind == .password }.compactMap { preference in
                APIKeys.keyEnding(account: ExtensionBundle.Preference.keychainAccount(bundle: bundle.name, name: preference.name))
                    .map { (bundle.name + "/" + preference.name, $0) }
            }
        }, uniquingKeysWith: { first, _ in first }) : [:]
        if discover, persists { LiveExtensions.discoverIfDue(config, force: true) { [weak self] in self?.refreshExtensions() } }
    }

    /// Adds a folder of extensions (asked with an open panel); one Spotlight found and was hidden is shown again.
    func addExtensionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = tr("添加", "Add")
        panel.message = tr("选择放脚本或扩展包的文件夹", "Choose a folder of scripts or extension bundles")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = ExtensionStore.abbreviated(url.path)
        if !config.extensionFolders.contains(path) { config.extensionFolders.append(path) }
        config.hiddenExtensionFolders.removeAll { $0 == path }
        save()
        refreshExtensions()
    }

    /// An added folder is removed from the list; a found one is hidden (or shown again).
    func removeExtensionFolder(_ folder: ExtensionStore.Folder) {
        if folder.found {
            if folder.hidden {
                config.hiddenExtensionFolders.removeAll { $0 == folder.path }
            } else {
                config.hiddenExtensionFolders.append(folder.path)
            }
        } else {
            config.extensionFolders.removeAll { $0 == folder.path }
        }
        save()
        refreshExtensions()
    }

    /// Shows a folder in Finder (the suggested one is made first).
    func revealExtensionFolder(_ folder: ExtensionStore.Folder) {
        if folder.path == ExtensionStore.defaultFolder, persists {
            try? FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(folder.url)
    }

    /// Whether a command (its id) or a bundle (its name) is on.
    func isEnabled(_ id: String) -> Bool { !config.disabledExtensions.contains(id) }

    func setEnabled(_ id: String, _ on: Bool) {
        config.disabledExtensions.removeAll { $0 == id }
        if !on { config.disabledExtensions.append(id) }
        save()
        refreshExtensions()
    }

    /// A preference's value as saved (not a password's), else its default.
    func preference(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference) -> String {
        config.extensionPreferences[bundle.name]?[preference.name] ?? preference.defaultValue ?? ""
    }

    /// Saves a preference: a password in the keychain (an empty one does nothing: `removePassword` removes it),
    /// anything else in the config file.
    func setPreference(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference, _ value: String) {
        guard persists else { return }
        if preference.kind == .password {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do {
                try APIKeys.save(value, account: ExtensionBundle.Preference.keychainAccount(bundle: bundle.name, name: preference.name),
                                 label: "AllInOneIME: \(bundle.title) – \(preference.title)")
                extensionError = nil
            } catch {
                extensionError = tr("没有存进钥匙串：", "Couldn't save it in the keychain: ") + error.localizedDescription
            }
        } else {
            config.extensionPreferences[bundle.name, default: [:]][preference.name] = value
            save()
        }
        refreshExtensions()
    }

    /// Removes a password preference from the keychain: Remove…, confirmed.
    func removePassword(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference) {
        guard persists, preference.kind == .password else { return }
        do {
            try APIKeys.remove(account: ExtensionBundle.Preference.keychainAccount(bundle: bundle.name, name: preference.name))
            extensionError = nil
        } catch {
            extensionError = tr("没能从钥匙串里删除：", "Couldn't remove it from the keychain: ", key: "extensionKey.removeFailed") + error.localizedDescription
        }
        refreshExtensions()
    }

    // MARK: Plugin library

    private let library = PluginLibrary()
    /// What the library offers this app; nil until the user opens it (no network before that).
    @Published private(set) var libraryEntries: [PluginIndex.Entry]?
    @Published private(set) var libraryStatus: [String: PluginLibrary.Status] = [:]
    @Published private(set) var libraryBusy = false
    /// The plugin being installed or updated.
    @Published private(set) var installingPlugin: String?
    @Published private(set) var libraryError: String?

    var libraryHost: String { library.host }

    /// Downloads the index (Browse / Refresh). Off the main thread; only when asked.
    func refreshLibrary() {
        guard !libraryBusy else { return }
        libraryBusy = true
        libraryError = nil
        let library = self.library
        Task { [weak self] in
            do {
                let entries = library.available(try await library.fetchIndex())
                self?.libraryEntries = entries
                self?.updateLibraryStatus()
            } catch {
                self?.libraryError = tr("无法打开插件库：", "Couldn't open the plugin library: ") + UIText.describe(error)
            }
            self?.libraryBusy = false
        }
    }

    /// Install / Update / Installed / local, for each plugin the library offers.
    func updateLibraryStatus() {
        guard let entries = libraryEntries else { return }
        libraryStatus = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, library.status(of: $0)) })
    }

    /// The library's newer version of an installed library plugin (known once the library was opened).
    func libraryUpdate(for plugin: InstalledPlugin) -> PluginIndex.Entry? {
        guard case .update = libraryStatus[plugin.name] else { return nil }
        return libraryEntries?.first { $0.name == plugin.name }
    }

    /// Installs or updates `entry` (downloads and checks off the main thread), then has the command
    /// list pick it up.
    func install(_ entry: PluginIndex.Entry) {
        guard persists, installingPlugin == nil else { return }
        installingPlugin = entry.name
        libraryError = nil
        let library = self.library
        Task { [weak self] in
            do {
                try await library.install(entry)
            } catch {
                self?.libraryError = tr("无法安装 @\(entry.name)：", "Couldn't install @\(entry.name): ") + UIText.describe(error)
            }
            self?.installingPlugin = nil
            self?.refreshPlugins()
            _ = LivePlugins.current(rescan: true)
        }
    }

    // MARK: Account

    /// Region shown when the field is empty: the profile's own region.
    var profileRegion: String {
        aws.status(for: config.awsProfile)?.region ?? AWSSharedConfig.region(profile: config.awsProfile) ?? "us-east-1"
    }

    /// The profile's kind and when its credentials expire, or what's wrong ("Role via base: credentials expire at 15:30").
    var credentialStatus: String { aws.line(profile: config.awsProfile) }

    /// Whether the profile's credentials can be had, as far as the files tell (`AWSProfileStatus.isReady`).
    var credentialsReady: Bool { aws.status(for: config.awsProfile)?.isReady == true }

    // MARK: Voice

    @Published private(set) var installedModels: [Language: Bool] = [:]
    @Published private(set) var modelProgress: [Language: Double] = [:]
    @Published private(set) var microphone = VoiceInput.microphoneAccess
    @Published private(set) var voiceError: String?

    func refreshVoice() {
        microphone = VoiceInput.microphoneAccess
        // A download started by the input method (first dictation) shows its progress here too.
        for language in VoiceInput.downloads.keys where modelProgress[language] == nil { downloadModel(language) }
        Task { [weak self] in
            for language in [Language.chinese, .english] {
                let installed = await VoiceInput.isModelInstalled(language)
                self?.installedModels[language] = installed
            }
        }
    }

    func downloadModel(_ language: Language) {
        voiceError = nil
        modelProgress[language] = 0
        VoiceInput.startDownload(language, progress: { [weak self] in self?.modelProgress[language] = $0 }) { [weak self] error in
            self?.modelProgress[language] = nil
            if let error { self?.voiceError = tr("下载失败：", "Download failed: ") + UIText.describe(error) }
            self?.refreshVoice()
        }
    }

    /// Asks for microphone access (system prompt), or opens the privacy settings once it was denied.
    func microphoneAction() {
        switch microphone {
        case .notDetermined:
            Task { [weak self] in
                _ = await VoiceInput.requestMicrophoneAccess()
                self?.microphone = VoiceInput.microphoneAccess
            }
        case .denied:
            NSWorkspace.shared.open(VoiceInput.microphoneSettingsURL)
        case .granted:
            break
        }
    }

    // MARK: Jargon list (the user's own; nothing is built in)

    @Published private(set) var jargonCount = 0
    @Published private(set) var jargonExists = false

    var jargonPath: String { (config.jargonURL.path as NSString).abbreviatingWithTildeInPath }

    func refreshJargon() {
        let url = config.jargonURL
        jargonExists = FileManager.default.fileExists(atPath: url.path)
        jargonCount = jargonExists ? JargonLibrary.load(from: url).count : 0
    }

    /// Uses a text file the user already has (e.g. the team's list) where it is.
    func chooseJargonFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .tabSeparatedText] + [UTType(filenameExtension: "md")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = config.jargonURL.deletingLastPathComponent()
        panel.message = tr("选择你的黑话库：文本文件，每行一个词，可以加解释",
                           "Choose your jargon list: a text file, one term per line, optionally with its meaning")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        config.jargonFile = (url.path as NSString).abbreviatingWithTildeInPath
        save()
        refreshJargon()
    }

    /// Opens the list in the text editor, first creating it (comments only) if it doesn't exist.
    func openJargonFile() {
        let url = config.jargonURL
        if !FileManager.default.fileExists(atPath: url.path) {
            guard persists else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(JargonLibrary.template.utf8).write(to: url, options: .withoutOverwriting)
            } catch {
                saveError = tr("无法创建黑话库：", "Couldn't create the jargon list: ") + error.localizedDescription
                return
            }
        }
        NSWorkspace.shared.open(url)
        refreshJargon()
    }

    // MARK: Test

    func runTest() {
        testTask?.cancel()
        testStatus = .running
        let snapshot = config
        // Bedrock: the profile's credentials fetched again through its whole chain (a program, STS, SSO), not the cached ones.
        let resolver = aws.resolver
        testTask = Task { [weak self] in
            defer { self?.aws.refresh(profile: snapshot.awsProfile) }
            let converter = Converter(loadConfig: { snapshot },
                                      loadCredentials: { try await resolver.resolve(profile: $0, forceRefresh: true) })
            // In the first input language: an English-only user sees an English test.
            let sample = switch snapshot.inputLanguages.first ?? .english {
            case .chinese: "我今天有点不舒服"
            case .english: "i dont feel so good today"
            case .french: "je me sens pas tres bien aujourdhui"
            case .korean: "오늘 몸이 좀 안 좋아요"
            case .hindi: "आज मेरी तबीयत ठीक नहीं है"
            }
            do {
                var final = ConversionResult.empty
                var elapsed: TimeInterval = 0
                for try await update in converter.convert(sample) where update.isFinal {
                    final = update.result
                    elapsed = update.elapsed
                }
                // Three versions with one translation language, a line each with several.
                guard let first = final.versions.first?.text ?? final.translations.first?.line.text else {
                    throw BedrockError.invalidResponse(tr("没有返回结果", "no result"))
                }
                // Like the candidate panel: a rewrite that only changes punctuation or repeats a row isn't shown.
                let shown = Set(([sample] + final.versions.map(\.text) + final.translations.map(\.line.text)).map(\.wordingKey))
                let rewrite = final.rewrites.first { !shown.contains($0.line.text.wordingKey) }
                    .map { "\n" + (RewriteStyle.named($0.style).map(UIText.name) ?? $0.style) + tr("：", ": ") + $0.line.text } ?? ""
                self?.testStatus = .passed(String(format: tr("%.1f 秒：%@%@", "%.1f s: %@%@"), elapsed, first, rewrite))
            } catch {
                self?.testStatus = .failed(UIText.describe(error))
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var customModel = false
    @State private var customProviderModel = false
    @State private var pluginToRemove: InstalledPlugin?
    /// The library plugin about to be installed or updated (the confirmation shows what it contacts).
    @State private var pluginToInstall: PluginIndex.Entry?
    /// The custom command being added or edited (the editor sheet), and the one about to be deleted.
    @State private var commandEdit: CommandEdit?
    @State private var commandToDelete: Int?
    /// The provider whose key row shows its paste field (Replace…, or the Assistant opening Settings at the key).
    @State private var editingKey: Provider?
    /// The key sheet: a provider other than the one in use whose key the Assistant asked for.
    @State private var keySheet: KeySheetRequest?
    /// The web search key row's paste field.
    @State private var editingSearchKey = false
    /// The page shown (Assistant when none is asked for) and what's typed in the sidebar's search field.
    @State private var page: SettingsPage
    @State private var query = ""
    /// The input language whose settings the Input page shows.
    @State private var inputTab: Language = .chinese
    /// The language packs and their downloads (Chinese is a download: the app ships English only).
    @ObservedObject private var packs = LanguagePackManager.shared
    /// The extension sources' new commits: a badge on the Custom Commands page.
    @ObservedObject private var extensionSources = ExtensionSourceController.shared
    /// The pack of an input language just removed: the dialog offers to delete it too.
    @State private var packToRemove: LanguagePack?
    /// A pack the user asked to delete from its language's card (asked first, with its size).
    @State private var packToDelete: LanguagePack?
    /// Settings → Assistant's request, preview and checks: the process's own (`AssistantModel.shared`), so they stay while
    /// other pages are shown and the window is closed.
    private let assistant: AssistantModel

    /// The README images: the key sheet drawn over the page, for this provider (a real sheet isn't in a page's image).
    private let keySheetShown: Provider?

    /// `page`: the one shown first; nil: Assistant (the last one isn't remembered).
    @MainActor
    init(model: SettingsModel, page: SettingsPage? = nil, inputTab: Language? = nil, keySheetShown: Provider? = nil,
         assistant: AssistantModel? = nil) {
        self.model = model
        self.keySheetShown = keySheetShown
        self.assistant = assistant ?? .shared
        if let inputTab { _inputTab = State(initialValue: inputTab) }
        _page = State(initialValue: page ?? Self.firstPage)
    }

    /// The page Settings opens on when none is asked for.
    static let firstPage = SettingsPage.assistant

    @ViewBuilder private var loadErrorSection: some View {
        if let loadError = model.loadError {
            Section {
                Label(tr("配置文件有误，未做修改：", "The config file has an error and was left as is: ") + loadError,
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button(tr("打开配置文件", "Open Config File")) { NSWorkspace.shared.open(model.configURL) }
            }
        }
    }

    @ViewBuilder private var generalSection: some View {
        Section {
            // Return by default; "Record…" takes the next key pressed (or a tap of ⌥).
            LabeledContent {
                HStack(spacing: 8) {
                    KeyRecorder(key: $model.config.actionKey)
                    if model.config.actionKey != .enter {
                        Button(tr("恢复 ⏎", "Use ⏎")) { model.config.actionKey = .enter }
                    }
                }
            } label: {
                titled(tr("执行键", "Action key"), Self.actionKeyNote(model.config.actionKey))
            }
            .disabled(!model.canSave)
            // Results typed in character by character, like a person typing.
            Toggle(isOn: $model.config.typeOut) {
                titled(tr("逐字上屏", "Type results out"),
                       tr("命令的结果（翻译、润色、回答…）像人打字一样一个字一个字打进去；打拼音选词还是马上上屏。按 Esc 停下，按别的键把剩下的一次打完。",
                          "A command's result is typed in character by character, like a person typing; pinyin picks still go in at once. Esc stops it; any other key types the rest at once."))
            }
            if model.config.typeOut {
                // A log scale: from 6 s a character to 40 a second, the slow end as easy to set.
                LabeledContent(tr("打字速度", "Typing speed")) {
                    HStack(spacing: 8) {
                        Text(tr("慢", "Slow")).font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { TypeOut.position(of: model.config.typeOutRate) },
                                              set: { model.config.typeOutRate = Self.roundedRate(TypeOut.rate(at: $0)) }))
                            .frame(width: 180)
                        Text(tr("快", "Fast")).font(.caption).foregroundStyle(.secondary)
                        Text(Self.rateLabel(model.config.typeOutRate)).monospacedDigit().frame(minWidth: 92, alignment: .trailing)
                    }
                }
                Toggle(tr("忽快忽慢（像真人打字）", "Speed up and slow down (like a person)"), isOn: $model.config.typeOutVaries)
                // Typos fixed at once (`TypeOut.plan`): the text still ends up exactly the result.
                Toggle(isOn: $model.config.typeOutMistakes) {
                    titled(tr("偶尔打错再改", "Make occasional typos and fix them"),
                           tr("偶尔按到旁边的键、多打一个字母或空格，或者一个词打了又删掉重打，马上就改回来，打完的文字一字不差。代码、网址和数字里打错马上就改；终端里不打错。",
                              "Now and then a neighboring key, a doubled letter or space, or a word typed again, fixed on the way: typed to the end, the text is exactly the result. In code, addresses and numbers fixed at once; never in a terminal."))
                }
                // Apps whose fields didn't take a typo back get none again; forgotten, they're tried once more.
                HStack {
                    Text(model.typoApps.isEmpty ? tr("每个 App 都能打错再改。", "Every app can make typos and fix them.")
                         : tr("这些 App 里不再打错：", "No typos in: ") + model.typoApps.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button(tr("忘掉改不回来的 App（\(model.typoApps.count)）", "Forget apps where typos couldn't be fixed (\(model.typoApps.count))")) {
                        model.forgetTypoApps()
                    }
                    .disabled(model.typoApps.isEmpty)
                }
            }
            // Commands on the selected text (`Composer.selection`): on by default, off for an app where it misbehaves.
            Toggle(isOn: $model.config.useSelection) {
                titled(tr("使用选中的文字", "Use the selected text"),
                       tr("先选中一段文字，再打 @improve、@translate、@question 等命令按 ⏎：命令处理选中的文字（打字时它一直选中、不变），选好的结果替换它；Esc 什么都不改。哪个 App 里不正常就关掉。",
                          "Select some text, then type @improve, @translate, @question … and ⏎: the command works on the selection (it stays selected and as it is while you type), and the result you pick replaces it; Esc changes nothing. Turn it off if it misbehaves in an app."))
            }
            // The recent @questions (`QuestionHistory`): kept only on this Mac; off forgets them too.
            Toggle(isOn: Binding(get: { model.config.rememberQuestions }, set: { model.setRememberQuestions($0) })) {
                titled(tr("记住最近的问题", "Remember recent questions"),
                       tr("@question 后面不打字就列出最近 \(QuestionHistory.limit) 个问题，选一个马上看到当时的答案（不联网），按 ⌘R 重新问。问题和答案只存在这台 Mac 上（除非在下面选了通过 iCloud 同步）；安全输入时和对选中文字的提问不存。关掉会删掉已存的。",
                          "@question with nothing after it lists your last \(QuestionHistory.limit) questions; pick one to see its answer again at once (offline), ⌘R asks it again. Questions and answers stay on this Mac (unless you sync them through iCloud, below); nothing is kept during secure input or for questions on selected text. Turning it off deletes them."))
            }
            .disabled(!model.canSave)
            HStack {
                Text(model.recentQuestions == 0 ? tr("没有保存的问题。", "No questions saved.")
                     : model.recentQuestions == 1 ? tr("保存了 1 个问题。", "1 saved question.")
                     : tr("保存了 \(model.recentQuestions) 个问题。", "\(model.recentQuestions) saved questions."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(tr("清除（\(model.recentQuestions)）", "Clear (\(model.recentQuestions))")) { model.clearRecentQuestions() }
                    .disabled(model.recentQuestions == 0)
            }
            // Where an @question conversation goes on (`ChatHandoff`; QuestionChatSettings.swift): the chips under the title,
            // the card's width for them (every agent installed, the web, Copy), scrolled sideways when there are more.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    titled(tr("对话接着在哪里聊", "Continue a conversation in"),
                           tr("@question 聊满 \(QuestionChat.rounds(model.config.questionRounds)) 轮（或随时按 ⌘⏎）后，⌘1、⌘2… 把对话带到这些地方接着聊，拖动排序，第一个是默认。对话会发给你选的服务。",
                              "After \(QuestionChat.rounds(model.config.questionRounds)) rounds of @question (or ⌘⏎ any time), ⌘1, ⌘2 … take the conversation there; drag to reorder, the first is the default. The conversation goes to the service you pick."))
                    Spacer()
                    let missing = model.missingContinueChoices
                    if !missing.isEmpty {
                        Menu(tr("添加…", "Add…")) {
                            ForEach(missing, id: \.self) { destination in
                                Button(AllInOneIMEInputController.name(destination, picked: model.config.agent,
                                                                       custom: model.config.agentCommand)) {
                                    model.addContinueIn(destination)
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    // The agents by name (a custom one's from its command), `.atAgent` by @agent's.
                    LanguageChips(items: model.continueChoices,
                                  name: { AllInOneIMEInputController.shortName($0, picked: model.config.agent, custom: model.config.agentCommand) },
                                  firstNote: tr("默认", "default"),
                                  reorder: { model.setContinueIn($0) }, remove: { model.removeContinueIn($0) })
                        .fixedSize()
                }
            }
            .disabled(!model.canSave)
        }
    }

    @ViewBuilder private var menuBarSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.menuBarIcon }, set: { model.setMenuBarIcon($0) })) {
                titled(tr("在菜单栏显示图标", "Show in Menu Bar"),
                       tr("笔记、提醒和后台的 Claude 任务，点一下就下拉出来", "Your notes, reminders and Claude tasks, a click away"))
            }
            .disabled(!model.canSave)
        } header: {
            SectionTitle(tr("菜单栏面板", "Menu Bar Panel"), icon: CommandIcons.panel)
        }
    }

    @ViewBuilder private var inputSection: some View {
        Section {
            // The input languages added, as tabs: the one picked shows its settings in the card below. The
            // first is the default (new text fields start in it); with two, Shift switches between them.
            LabeledContent {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(get: { shownInput }, set: { inputTab = $0 })) {
                        ForEach(model.config.inputLanguages, id: \.self) { language in
                            Text(AllInOneIMEInputController.inputName(language)
                                 + (language == model.config.inputLanguages.first && model.config.inputLanguages.count > 1
                                    ? tr(" · 默认", " · default") : ""))
                                .tag(language)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    // Always there, so it's clear where languages are added: one to five of them.
                    let languages = model.config.inputLanguages
                    let missing = Language.allCases.filter { !languages.contains($0) }
                    let full = languages.count >= Config.maxInputLanguages
                    Menu {
                        ForEach(missing, id: \.self) { language in
                            // A language whose pack isn't here says it downloads first.
                            let download = !packs.isUsable(language)
                            Button(AllInOneIMEInputController.inputName(language)
                                   + (download ? tr("（下载语言包）", " (downloads a language pack)") : "")) {
                                addInputLanguage(language)
                            }
                            .disabled(LanguagePack.for(language).map(isDownloading) ?? false)
                        }
                        if !missing.isEmpty { Divider() }
                        Text(tr("更多输入语言即将支持", "More input languages are coming"))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuIndicator(.hidden).fixedSize()
                    .disabled(full)
                    .help(full ? tr("最多 \(Config.maxInputLanguages) 种输入语言", "Up to \(Config.maxInputLanguages) input languages")
                               : tr("添加输入语言", "Add an input language"))
                    .accessibilityLabel(tr("添加输入语言", "Add an input language"))
                }
            } label: {
                titled(tr("输入语言", "Input languages"),
                       model.config.inputLanguages.count > 1
                       ? tr("单按 Shift 切换；点一个看它的设置", "Tap Shift to switch; click one for its settings")
                       : tr("只有一种时 Shift 不切换", "With one, Shift doesn't switch"))
            }
            // The candidates of a word being typed (pinyin, Hindi) in a column, or in a row like macOS's own panel.
            LabeledContent {
                Picker("", selection: $model.config.candidateLayout) {
                    Text(tr("竖排", "Vertical")).tag(CandidateArrangement.vertical)
                    Text(tr("横排", "Horizontal")).tag(CandidateArrangement.horizontal)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .disabled(!model.canSave)
            } label: {
                titled(tr("候选排列", "Candidate layout"),
                       model.config.candidateLayout == .horizontal
                       ? tr("选词（拼音、印地语）的候选并排（默认），像系统自带的输入法：← → 选词，↑↓ 或 - = 翻页。@ 命令列表和结果还是竖排。在下一个输入框生效。",
                            "For picking words (pinyin, Hindi): side by side (the default), like the system's own input methods; ← → choose, ↑↓ or - = turn the page. The @ list and results stay vertical. From the next text field.")
                       : tr("选词（拼音、印地语）的候选一个一个往下排：↑↓ 选词，- = 翻页。@ 命令列表和结果总是竖排。在下一个输入框生效。",
                            "For picking words (pinyin, Hindi): one under the other; ↑↓ choose, - = turn the page. The @ list and results are always vertical. From the next text field."))
            }
            ForEach(LanguagePack.catalog) { pack in packRow(pack) }
        } header: {
            SectionTitle(tr("输入", "Input"), icon: CommandIcons.input)
        }
        .disabled(!model.canSave)
    }

    @ViewBuilder private var translateSection: some View {
        Section {
            // @translate writes a line in each, in this order (three versions with only one).
            LabeledContent {
                HStack(spacing: 6) {
                    LanguageChips(items: model.config.outputLanguages, name: UIText.name,
                                  firstNote: nil,
                                  reorder: { model.config.setOrder($0) }, remove: removeOutputLanguage)
                    Menu(tr("添加…", "Add…")) {
                        ForEach(OutputLanguage.catalog.filter { !model.config.outputLanguages.contains($0) }) { language in
                            Button(UIText.name(language)) { addOutputLanguage(language) }
                        }
                    }
                    .fixedSize()
                }
            } label: {
                titled(tr("翻译语言", "Languages"), tr("每种一行，拖动排序", "A line in each; drag to reorder"))
            }
        } header: {
            SectionTitle(tr("翻译（@translate）", "Translate (@translate)"), icon: CommandIcons.translate)
        }
        .disabled(!model.canSave)
    }

    @ViewBuilder private var rewriteSection: some View {
        Section {
            // Like the languages: the styles added, in the order they're shown; drag to reorder.
            LabeledContent {
                HStack(spacing: 6) {
                    let on = RewriteStyle.resolve(model.config.rewriteStyles)
                    LanguageChips(items: on.map(\.name), name: { RewriteStyle.named($0).map(UIText.name) ?? $0 },
                                  firstNote: nil, keepsOne: false,
                                  reorder: { model.setStyleOrder($0) },
                                  remove: { name in RewriteStyle.named(name).map { model.setStyle($0, on: false) } })
                    let missing = RewriteStyle.catalog.filter { !on.contains($0) }
                    if !missing.isEmpty {
                        Menu(tr("添加…", "Add…")) {
                            ForEach(missing, id: \.name) { style in
                                Button(UIText.name(style) + " — " + UIText.summary(style)) { model.setStyle(style, on: true) }
                            }
                        }
                        .fixedSize()
                    }
                }
            } label: {
                titled(tr("风格", "Styles"), model.config.rewriteStyles.isEmpty
                       ? tr("没有风格时只出 1–3 行", "With none, lines 1–3 only")
                       : tr("用你写的语言改写，拖动排序", "In the language you wrote; drag to reorder"))
            }
            .disabled(!model.canSave)
            Toggle(isOn: $model.config.improveTranslates) {
                titled(tr("@improve 同时翻译", "@improve also translates"), inputSummary)
            }
            .disabled(!model.canSave)
        } header: {
            SectionTitle(tr("改写风格（@improve）", "Rewrite Styles (@improve)"), icon: CommandIcons.improve)
        }
    }

    @ViewBuilder private var jargonSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(model.jargonExists ? tr("\(model.jargonCount) 个词", "\(model.jargonCount) terms") : tr("未设置", "Not set"))
                        .foregroundStyle(.secondary)
                    Button(tr("选择文件…", "Choose File…")) { model.chooseJargonFile() }
                    Button(model.jargonExists ? tr("打开", "Open") : tr("新建", "New")) { model.openJargonFile() }
                }
            } label: {
                titled(tr("黑话库", "Jargon list"), model.jargonExists ? model.jargonPath : tr("你团队自己的说法", "Your team's own terms"))
            }
            .disabled(!model.canSave)
        } header: {
            SectionTitle(tr("黑话库", "Jargon List"), icon: CommandIcons.jargon)
        } footer: {
            Text(tr("用你自己的词表：文本文件，每行一个词，可以加解释（如 bandwidth：精力、时间）。加了「黑话」风格后模型优先用这些词，候选里会注明意思。",
                    "Your own term list: a text file, one term per line, optionally with its meaning (e.g. bandwidth: time and energy). With the Jargon style added, the model prefers these terms and the candidates explain them.")
                 )
                .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
    }

    @ViewBuilder private var commandsSection: some View {
        Section {
            ForEach(Array(model.config.customCommands.enumerated()), id: \.offset) { index, command in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        IconTile(icon: CommandIcons.icon(for: command))
                        Text("@" + command.name).font(.body.monospaced())
                        Text(UIText.customKind(command)).foregroundStyle(.secondary)
                        if let summary = command.summary {
                            Text(summary).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(tr("编辑", "Edit")) { commandEdit = CommandEdit(index: index, command: command) }
                        Button(tr("删除", "Delete")) { commandToDelete = index }
                    }
                    if Self.hiddenByBuiltIn(command) {
                        Label(tr("和内置命令重名，不会生效，请改名", "Same name as a built-in command: rename it to use it"),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Button(tr("添加命令…", "Add Command…")) {
                commandEdit = CommandEdit(index: nil, command: CustomCommand(name: "", type: .prompt))
            }
        } header: {
            SectionTitle(tr("自定义 @ 命令", "Custom @ Commands"), icon: CommandIcons.commands)
        } footer: {
            Text(tr("保存后，在任意输入框开头打 @ 加名字就能用，和 @improve 一样。",
                    "Once saved, type @ and its name at the start of any text field, like @improve."))
                .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
    }

    /// Script extensions (docs/extensions.md): where they're looked for, the bundles and their preferences, the
    /// commands (each turned on or off), and what was left out, with why.
    @ViewBuilder private var extensionsSection: some View {
        Section {
            Toggle(isOn: $model.config.findRaycastScripts) {
                titled(tr("自动查找 Raycast 脚本", "Find Raycast scripts automatically"),
                       tr("用聚焦（Spotlight）找带 @raycast 元数据的脚本，它们所在的文件夹会列在下面，用不着的可以隐藏。",
                          "Spotlight finds scripts with @raycast metadata; their folders are listed below, and you can hide the ones you don't want."))
            }
            ForEach(model.extensionFolders, id: \.path) { folder in
                HStack {
                    Image(systemName: folder.found ? "sparkle.magnifyingglass" : "folder").foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(folder.path).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(folder.hidden ? .secondary : .primary)
                    Text(folder.hidden ? tr("自动找到 · 已隐藏", "found · hidden") : folder.found ? tr("自动找到", "found") : tr("添加的", "added"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("在访达中显示", "Show in Finder")) { model.revealExtensionFolder(folder) }
                    Button(folder.found ? (folder.hidden ? tr("显示", "Show") : tr("隐藏", "Hide")) : tr("移除", "Remove")) {
                        model.removeExtensionFolder(folder)
                    }
                }
            }
            Button(tr("添加文件夹…", "Add Folder…")) { model.addExtensionFolder() }
            ForEach(model.extensionIndex.bundles, id: \.name) { bundle in bundleRow(bundle) }
            ForEach(model.extensionIndex.commands.filter { $0.source.bundleName == nil }, id: \.id) { command in extensionRow(command) }
            ForEach(model.skippedExtensions, id: \.self) { skipped in
                // A bundle's extension.json is named with its folder ("units/extension.json").
                let file = skipped.file.lastPathComponent == ExtensionBundle.manifestName
                    ? skipped.file.deletingLastPathComponent().lastPathComponent + "/" + skipped.file.lastPathComponent
                    : skipped.file.lastPathComponent
                Label(tr("没有加载 \(file)：", "Not loaded, \(file): ") + UIText.describe(skipped.problem, file: skipped.file),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            // Copies of what is loaded (another checkout of a repository, a copied folder): one quiet line.
            if !model.extensionIndex.identical.isEmpty {
                let identical = model.extensionIndex.identical
                Label(identical.count == 1 ? tr("跳过了 1 个完全相同的副本", "Skipped 1 identical copy")
                          : tr("跳过了 \(identical.count) 个完全相同的副本", "Skipped \(identical.count) identical copies"),
                      systemImage: "doc.on.doc")
                    .font(.caption).foregroundStyle(.secondary)
                    .help(identical.map { ExtensionStore.abbreviated($0.path) }.joined(separator: "\n"))
            }
            if model.extensionIndex.commands.isEmpty, model.skippedExtensions.isEmpty {
                Text(tr("还没有扩展。把脚本、扩展包或 Raycast 的脚本命令放进上面的文件夹就行。",
                        "No extensions yet. Put scripts, extension bundles or Raycast Script Commands in a folder above."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.extensionError { Text(error).foregroundStyle(.red) }
        } header: {
            SectionTitle(tr("脚本扩展", "Script Extensions"), icon: CommandIcons.scripts)
        } footer: {
            Text(tr("每个脚本是一个 @ 命令，名字取自文件名（convert-timestamp.sh → @converttimestamp）。参数写在命令后面，多个用逗号隔开：@flights beijing, new york。脚本可以上屏结果、显示进度、给出列表来选，或在后台运行，完成后通知你。写法见 docs/extensions.md。",
                    "Each script is an @ command named after its file (convert-timestamp.sh → @converttimestamp). Write its arguments after it, with commas between: @flights beijing, new york. A script can insert its result, show progress, offer a list to pick from, or run in the background and notify you. See docs/extensions.md for how to write one."))
                .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
    }

    /// A bundle: its switch, title, version and author, its preferences, and its commands.
    @ViewBuilder private func bundleRow(_ bundle: ExtensionBundle) -> some View {
        let on = model.isEnabled(bundle.name)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shippingbox.fill").foregroundStyle(.secondary).frame(width: 20)
                Text(bundle.title).fontWeight(.medium)
                Text([bundle.version, bundle.author].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { model.setEnabled(bundle.name, $0) })).labelsHidden().toggleStyle(.switch)
                    .controlSize(.small)
            }
            ForEach(bundle.preferences, id: \.name) { preference in
                PreferenceField(preference: preference, value: model.preference(bundle, preference),
                                saved: model.passwordsSaved.contains(bundle.name + "/" + preference.name),
                                save: { model.setPreference(bundle, preference, $0) },
                                ending: model.passwordEndings[bundle.name + "/" + preference.name],
                                remove: { model.removePassword(bundle, preference) })
                .padding(.leading, 28)
            }
            if on {
                ForEach(model.extensionIndex.commands.filter { $0.source.bundleName == bundle.name }, id: \.id) { command in
                    extensionRow(command).padding(.leading, 28)
                }
            }
        }
    }

    /// A command: its icon, the name it got, its title and description, what it does, and its switch; one
    /// left out because another command has its name says so.
    private func extensionRow(_ command: ScriptCommand) -> some View {
        let hidden = model.hiddenExtensions[command.id]
        let on = model.isEnabled(command.id) && hidden == nil
        let name = model.extensionNames[command.id] ?? command.name
        let input = command.input == .none ? tr("不用输入", "no input")
            : command.arguments.count == 1 ? tr("1 个参数", "1 argument") : tr("\(command.arguments.count) 个参数", "\(command.arguments.count) arguments")
        let traits = [command.background ? tr("后台", "background") : UIText.name(command.output), input,
                      command.status != nil ? tr("状态", "status") : nil].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                IconTile(icon: CommandIcons.icon(for: command))
                Text("@" + name).font(.body.monospaced()).foregroundStyle(on ? .primary : .secondary)
                Text(command.title).lineLimit(1).foregroundStyle(on ? .primary : .secondary)
                if command.source == .raycast { Text("Raycast").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text(traits).font(.caption).foregroundStyle(.secondary)
                Toggle("", isOn: Binding(get: { model.isEnabled(command.id) }, set: { model.setEnabled(command.id, $0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if let description = command.description {
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(.leading, 28)
            }
            if let hidden {
                Label(tr("没有加载：", "Not loaded: ") + UIText.describe(hidden, file: command.file), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.leading, 28)
            }
        }
        .help(ExtensionStore.abbreviated(command.file.path))
    }

    @ViewBuilder private var pluginsSection: some View {
        Section {
            ForEach(model.plugins, id: \.name) { plugin in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        IconTile(icon: CommandIcons.icon(for: plugin))
                        Text("@" + plugin.name).font(.body.monospaced())
                        Text(plugin.manifest.summary?.text(chinese: UIText.chinese) ?? "").foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if let update = model.libraryUpdate(for: plugin) {
                            Button(tr("更新到 \(update.version)", "Update to \(update.version)")) { pluginToInstall = update }
                        }
                        Button(tr("删除", "Remove", key: "remove.delete")) { pluginToRemove = plugin }
                    }
                    Text(pluginDetail(plugin)).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(model.skippedPlugins, id: \.folder) { skipped in
                Label(tr("没有加载 \(skipped.folder)：", "Not loaded, \(skipped.folder): ") + skipped.reason,
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if model.plugins.isEmpty, model.skippedPlugins.isEmpty {
                Text(tr("还没有插件。插件是别人写好的 @ 命令，比如 @stock 查股价；装好后和其他命令一样用。",
                        "No plugins yet. Plugins are ready-made @ commands, like @stock for stock quotes; once installed they work like any command."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(tr("打开插件文件夹", "Open Plugins Folder")) { model.openPluginsFolder() }
                Button(tr("刷新", "Refresh")) { model.refreshPlugins() }
            }
            if let error = model.pluginError { Text(error).foregroundStyle(.red) }
            pluginLibrary
        } header: {
            SectionTitle(tr("插件", "Plugins"), icon: CommandIcons.plugins)
        }
        .disabled(!model.canSave)
    }

    @ViewBuilder private var voiceSection: some View {
        Section {
            Toggle(isOn: $model.config.voiceInput) {
                titled(tr("按住右 ⌥ 说话，松开结束", "Hold right ⌥ to talk, release to stop"),
                       tr("在这台 Mac 上识别，不上传", "Recognized on this Mac, never uploaded"))
            }
            .disabled(!model.canSave)
            if VoiceInput.isSupported {
                ForEach([Language.chinese, .english], id: \.self) { language in
                    LabeledContent(tr("\(language.displayName)语音模型", "\(UIText.name(language)) speech model")) {
                        modelStatus(language)
                    }
                }
                LabeledContent(tr("麦克风", "Microphone")) {
                    switch model.microphone {
                    case .granted: Text(tr("已允许", "Allowed")).foregroundStyle(.secondary)
                    case .notDetermined: Button(tr("允许使用麦克风", "Allow Microphone")) { model.microphoneAction() }
                    case .denied: Button(tr("已拒绝，去系统设置打开", "Denied: Open System Settings")) { model.microphoneAction() }
                    }
                }
                if let error = model.voiceError { Text(error).foregroundStyle(.red) }
            } else {
                Text(tr("需要 macOS 26 或更新版本。", "Needs macOS 26 or later.")).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            SectionTitle(tr("语音输入", "Voice Input"), icon: CommandIcons.voice)
        } footer: {
            if VoiceInput.isSupported {
                Text(tr("中文模式说中文，英文模式说英文。识别出的文字直接上屏，在 @ 命令里就接在命令后面。",
                        "Speak English in English mode and Chinese in Chinese mode. The text is typed in, or after the @ command you are writing."))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
            }
        }
    }

    @ViewBuilder private var providerSection: some View {
        Section {
            Picker(tr("服务", "Provider"), selection: $model.config.provider) {
                ForEach(Provider.offered, id: \.self) { provider in
                    providerItem(provider)
                }
            }
            if model.config.provider == .bedrock {
                bedrockSettings
            } else if model.config.provider == .hosted {
                hostedSettings
            } else if model.config.provider == .apple {
                appleSettings
            } else {
                apiKeySettings(model.config.provider)
            }
            HStack {
                Button(tr("测试连接", "Test Connection")) { model.runTest() }
                    .disabled(model.testStatus == .running)
                switch model.testStatus {
                case .idle: EmptyView()
                case .running: ProgressView().controlSize(.small)
                case let .passed(text): Text("✓ \(text)").foregroundStyle(.green).textSelection(.enabled)
                case let .failed(text): Text("✗ \(text)").foregroundStyle(.red).textSelection(.enabled)
                }
            }
        } header: {
            SectionTitle(tr("AI 服务", "AI Provider"), icon: CommandIcons.provider)
        }
        .disabled(!model.canSave)
    }

    @ViewBuilder private var webSearchSection: some View {
        if Command.webSearchOffered {
            // The key lives in the keychain, not in the config file: this works even when the file is broken.
            Section {
                LabeledContent("API key") {
                    KeyRowContent(state: model.searchKeyState, missing: tr("还没有 API key", "No API key yet"),
                                  prompt: tr("粘贴 Brave Search 的 API key", "Paste a Brave Search API key"),
                                  removeTitle: tr("删除钥匙串里的搜索 API key？", "Remove the search API key from the keychain?"),
                                  save: { model.saveSearchKey($0) },
                                  remove: model.searchKeySource == .keychain ? { model.removeSearchKey() } : nil,
                                  editing: $editingSearchKey)
                }
                if let error = model.searchKeyError { Text(error).foregroundStyle(.red) }
                HStack {
                    Button(tr("测试", "Test")) { model.testSearch() }
                        .disabled(model.searchTestStatus == .running || model.searchKeySource == APIKeys.Source.none)
                    Button(tr("获取 API key…", "Get an API Key…")) { NSWorkspace.shared.open(WebSearch.backend.keyPage) }
                    switch model.searchTestStatus {
                    case .idle: EmptyView()
                    case .running: ProgressView().controlSize(.small)
                    case let .passed(text): Text("✓ \(text)").foregroundStyle(.green).textSelection(.enabled)
                    case let .failed(text): Text("✗ \(text)").foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Text(tr("@search 用 Brave Search 搜网页，用你自己的 API key：Brave 每月送一些免费额度（目前约 1000 次搜索），注册时要绑信用卡。"
                            + "要搜的内容会发给 Brave。key 存在钥匙串里；也可以在 shell 里设置 BRAVE_API_KEY。",
                        "@search searches the web with Brave Search, using your own API key: Brave gives some free credit each month "
                            + "(about 1,000 searches for now); signing up needs a credit card. What you search for is sent to Brave. "
                            + "The key is kept in the keychain; you can also set BRAVE_API_KEY in your shell."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                SectionTitle(tr("网页搜索（@search）", "Web Search (@search)"), icon: CommandIcons.webSearch)
            }
        }
    }

    /// How each request is made, under the AI provider: output tokens, temperature (Bedrock), timeout.
    @ViewBuilder private var requestSection: some View {
        Section {
            Stepper(value: $model.config.maxTokens, in: 200...4000, step: 100) {
                Text(tr("最多输出 \(model.config.maxTokens) tokens", "Up to \(model.config.maxTokens) output tokens"))
            }
            if model.config.provider == .bedrock || model.config.provider == .apple {
                Toggle(tr("发送 temperature（有的模型不支持，报错时关掉）",
                          "Send temperature (some models don't support it; turn it off if requests fail)"),
                       isOn: temperatureOn)
                if let t = model.config.temperature {
                    Slider(value: Binding(get: { t }, set: { model.config.temperature = ($0 * 10).rounded() / 10 }),
                           in: 0...1) { Text("temperature \(String(format: "%.1f", t))") }
                }
            }
            Stepper(value: $model.config.timeoutSeconds, in: 5...60, step: 5) {
                Text(tr("超时 \(Int(model.config.timeoutSeconds)) 秒", "Timeout \(Int(model.config.timeoutSeconds)) s"))
            }
        } header: {
            SectionTitle(tr("模型参数", "Model Settings"), icon: CommandIcons.provider)
        }
        .disabled(!model.canSave)
    }

    @ViewBuilder private var interfaceSection: some View {
        Section {
            // Following the system by default; the languages the app ships are written in their own language, so
            // they can be found whatever the window is in. Saved as "zh" / "en" for those two (older versions read them).
            Picker(tr("界面语言", "Interface language"),
                   selection: Binding(get: { InterfaceLanguage.code(forSetting: model.config.uiLanguage, shipped: UIText.shipped) },
                                      set: { model.setUILanguage($0.map(InterfaceLanguage.setting(for:))) })) {
                Text(tr("跟随系统", "Follow the system")).tag(String?.none)
                Divider()
                ForEach(UIText.shipped, id: \.self) { code in
                    Text(InterfaceLanguage.name(code)).tag(String?.some(code))
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder private var filesSection: some View {
        Section {
            let path = (model.configURL.path as NSString).abbreviatingWithTildeInPath
            LabeledContent {
                Button(tr("打开", "Open")) { NSWorkspace.shared.open(model.configURL) }
            } label: {
                titled(tr("配置文件", "Config file"), path)
            }
            LabeledContent {
                Button(tr("打开", "Open")) { NSWorkspace.shared.open(RimeDirectories.user) }
            } label: {
                titled(tr("Rime 用户目录", "Rime user folder"), tr("学到的词和你自己的 Rime 设置", "Learned words and your own Rime settings"))
            }
            if let saveError = model.saveError {
                Text(saveError).foregroundStyle(.red)
            }
        } header: {
            SectionTitle(tr("高级", "Advanced"), icon: CommandIcons.advanced)
        } footer: {
            Text(tr("改完立即生效，不用重启。", "Changes apply right away, with no restart."))
                .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
    }

    /// A row's title with a short explanation under it, as System Settings shows them.
    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pages

    /// Like System Settings: a search field, then the pages, each with its icon.
    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("搜索设置…", "Search settings…"), text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(tr("清除搜索", "Clear the search"))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.75)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .padding(.horizontal, 12)
            let shown = SettingsPage.allCases.filter { $0.matches(query) }
            List(selection: Binding(get: { page }, set: { if let new = $0 { page = new } })) {
                // In groups, like System Settings: what you type with, what it runs, the rest.
                let groups = SettingsPage.groups.map { $0.filter(shown.contains) }.filter { !$0.isEmpty }
                ForEach(groups.indices, id: \.self) { index in
                    // A thin line between the groups.
                    if index > 0 {
                        Divider().padding(.horizontal, 6).padding(.vertical, 2)
                            .selectionDisabled()
                    }
                    ForEach(groups[index]) { item in
                        Label {
                            Text(item.title).font(.system(size: 13.5)).padding(.leading, 4)
                        } icon: {
                            if item == .about {
                                // The app's own icon, as Raycast's About has.
                                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                                    .accessibilityHidden(true)
                            } else {
                                IconTile(icon: item.icon, size: 24)
                            }
                        }
                        .padding(.vertical, 3)
                        .badge(item == .commands ? extensionSources.updateCount(for: model.config.extensionSources) : 0)
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: query) {
                // The first page that matches comes up as you type.
                if let first = shown.first, !shown.contains(page) { page = first }
            }
            if shown.isEmpty {
                Text(tr("没有匹配的设置", "No matching settings")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    /// 模糊音: shown with Chinese (pinyin) input.
    /// The input language whose settings show below the languages (the first, until another is picked).
    private var shownInput: Language {
        model.config.inputLanguages.contains(inputTab) ? inputTab : model.config.inputLanguages.first ?? .chinese
    }

    /// The settings of the input language picked above: pinyin's fuzzy sounds; none for English yet.
    @ViewBuilder private var inputLanguageSection: some View {
        Section {
            // The language's pack: still on its way (its progress is shown above), or what's installed.
            if let pack = LanguagePack.for(shownInput) {
                if !packs.isInstalled(pack) {
                    Label(tr("语言包下载完以后才能打\(pack.name.text(chinese: true))。", "\(pack.name.en) can be typed once its language pack has downloaded."),
                          systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
                packInfo(pack)
            }
            switch shownInput {
            case .chinese:
                Toggle(isOn: Binding(get: { !model.config.fuzzyPinyin.isEmpty },
                                     set: { model.setFuzzyPinyin($0 ? SettingsModel.fuzzyDefaults : []) })) {
                    titled(tr("模糊音", "Fuzzy pinyin"),
                           tr("分不清的音两种拼法都能打出来，比如 zh 和 z：打 zi 也有「之」", "Sounds you don't tell apart typed either way, e.g. zh and z: zi also offers 之"))
                }
                if !model.config.fuzzyPinyin.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(FuzzyPinyin.pairs) { pair in
                            Toggle(pair.label, isOn: Binding(get: { model.config.fuzzyPinyin.contains(pair.id) },
                                                             set: { model.setFuzzy(pair.id, on: $0) }))
                                .toggleStyle(.checkbox)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                if model.fuzzyBlocked {
                    Label(tr("Rime 用户目录里有你自己的 \(FuzzyPinyin.fileName)，没有改动它，模糊音没有生效。",
                             "The Rime user folder has your own \(FuzzyPinyin.fileName): it was left as is, so fuzzy pinyin isn't on."),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            case .english:
                Text(tr("英文模式直接打字母，暂时没有要设置的。", "In English, letters are typed as they are: nothing to set yet."))
                    .foregroundStyle(.secondary)
            case .french:
                // The layout French types with (AZERTY unless picked); Shift to French switches to it.
                Picker(selection: Binding(get: { model.config.keyboardLayout(for: .french) ?? "" },
                                          set: { model.config.keyboardLayouts[Language.french.rawValue] = $0 })) {
                    ForEach(KeyboardLayouts.latin, id: \.id) { layout in Text(layout.name).tag(layout.id) }
                } label: {
                    titled(tr("键盘布局", "Keyboard layout"),
                           tr("切到法语时按这个布局打字；死键（^、¨、´）也按它组合", "French types with this layout, its dead keys (^, ¨, ´) too"))
                }
                .pickerStyle(.menu)
            case .korean:
                Text(tr("두벌식（两套式）：按键位打字母，自动组成音节，比如 g k s → 한。Shift 打紧音（ㄲ ㄸ ㅃ ㅆ ㅉ）和 ㅒ ㅖ。",
                        "Dubeolsik (2-set): keys give jamo, composed into syllables as you type, e.g. g k s → 한. Shift for ㄲ ㄸ ㅃ ㅆ ㅉ and ㅒ ㅖ."))
                    .foregroundStyle(.secondary)
            case .hindi:
                Text(tr("用拉丁字母按发音打，出天城文：namaste → नमस्ते。常用词按词表拼写，其他词可以从几种写法里选：空格上屏第一个，数字选别的，⏎ 上屏原样的字母，. 打出 ।",
                        "Type it as it sounds in Latin letters, get Devanagari: namaste → नमस्ते. Common words are spelled from a list; for others pick a spelling: Space inserts the first, a digit another, ⏎ the letters as typed, . the danda (।)."))
                    .foregroundStyle(.secondary)
            }
            // Its place among the input languages: the default, or not added at all.
            let languages = model.config.inputLanguages
            if languages.count > 1, let index = languages.firstIndex(of: shownInput) {
                // Its place in the order (the tabs above follow it); the first is the default.
                LabeledContent {
                    HStack(spacing: 4) {
                        Button { moveInput(shownInput, by: -1) } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0)
                            .help(tr("往前移", "Move earlier")).accessibilityLabel(tr("往前移", "Move earlier"))
                        Button { moveInput(shownInput, by: 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(index == languages.count - 1)
                            .help(tr("往后移", "Move later")).accessibilityLabel(tr("往后移", "Move later"))
                    }
                } label: {
                    titled(tr("位置", "Position"),
                           tr("第 \(index + 1) 个，共 \(languages.count) 个；第一个是默认", "\(index + 1) of \(languages.count); the first is the default"))
                }
                if shownInput != languages.first {
                    LabeledContent {
                        Button(tr("设为默认", "Make Default")) {
                            model.config.setOrder([shownInput] + languages.filter { $0 != shownInput })
                        }
                    } label: {
                        titled(tr("默认输入语言", "Default input language"), tr("新输入框从这种语言开始", "New text fields start in this one"))
                    }
                }
            }
            if languages.contains(shownInput), languages.count > 1 || shownInput != .english {
                LabeledContent {
                    Button(tr("移除", "Remove"), role: .destructive) { removeInputLanguage(shownInput) }
                } label: {
                    titled(tr("移除这种输入语言", "Remove this input language"),
                           languages.count > 1 ? tr("以后可以再用 ＋ 加回来", "You can add it back with +")
                                               : tr("只剩英文；以后可以再用 ＋ 加回来", "English stays; you can add it back with +"))
                }
            }
        } header: {
            SectionTitle(AllInOneIMEInputController.inputName(shownInput), icon: CommandIcons.input)
        } footer: {
            if shownInput == .chinese {
                Text(tr("改完词库会重新部署，一两秒生效。", "Applied in a second or two: the dictionaries are deployed again."))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
            }
        }
        .disabled(!model.canSave)
    }

    /// The version, its updates, who makes it, where to read more.
    @ViewBuilder private var aboutSection: some View {
        Section {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                Text("AllInOneIME").font(.title2).bold()
                if let version = Self.version {
                    Text(tr("版本 \(version)", "Version \(version)")).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("© 2026 MicroZ LLC · FSL-1.1-ALv2").font(.caption).foregroundStyle(.secondary)
                Text(commandsSummary).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        UpdateSection(updates: .shared, model: model)
        Section {
            LabeledContent(tr("网站", "Website")) { Link("allinoneime.com", destination: URL(string: "https://allinoneime.com")!) }
            LabeledContent(tr("使用说明", "Documentation")) { Link("Wiki", destination: URL(string: "https://allinoneime.com/docs")!) }
            LabeledContent(tr("更新日志", "What's new")) {
                Link(tr("更新日志", "Changelog"), destination: URL(string: "https://github.com/MicroZ-LLC/AllInOneIME/releases")!)
            }
            LabeledContent(tr("源代码", "Source code")) {
                Link("GitHub", destination: URL(string: "https://github.com/MicroZ-LLC/AllInOneIME")!)
            }
            // GitHub's page for a new issue, with the versions and settings that help; `@reportissue` does the same.
            LabeledContent {
                Button(tr("报告问题…", "Report an Issue…")) { IssueReporting.open(config: model.config) }
            } label: {
                titled(tr("反馈", "Feedback"),
                       tr("在浏览器里打开 GitHub 的新问题页，附上版本、语言和设置的种类，不含你打的字、路径、密钥和命令名；你看过再提交。",
                          "Opens a new GitHub issue in the browser with the versions, languages and kinds of settings, never your text, paths, keys or command names; you submit it."))
            }
        }
    }

    /// The input languages' pack dialogs, on the page rather than on the Input section (a Form section's own
    /// dialog is not shown), and apart from `body`'s chain of modifiers (too long to type-check otherwise).
    private func packDialogs(_ content: some View) -> some View {
        content
        .confirmationDialog(packToRemove.map { tr("也删除\($0.name.text(chinese: true))语言包？", "Also delete the \($0.name.en) language pack?") } ?? "",
                            isPresented: Binding(get: { packToRemove != nil }, set: { if !$0 { packToRemove = nil } })) {
            Button(tr("删除语言包", "Delete Pack"), role: .destructive) {
                if let pack = packToRemove { packs.remove(pack) }
                packToRemove = nil
            }
            Button(tr("保留", "Keep"), role: .cancel) { packToRemove = nil }
        } message: {
            if let pack = packToRemove {
                Text(tr("占用 \(ByteCountFormatter.string(fromByteCount: packs.store.size(pack), countStyle: .file))；以后用 ＋ 加回来时要重新下载。",
                        "It takes \(ByteCountFormatter.string(fromByteCount: packs.store.size(pack), countStyle: .file)); adding the language back with + downloads it again."))
            }
        }
        .confirmationDialog(packToDelete.map { tr("删除\($0.name.text(chinese: true))语言包？", "Delete the \($0.name.en) language pack?") } ?? "",
                            isPresented: Binding(get: { packToDelete != nil }, set: { if !$0 { packToDelete = nil } })) {
            Button(tr("删除语言包", "Delete Pack"), role: .destructive) {
                if let pack = packToDelete { deletePack(pack) }
                packToDelete = nil
            }
            Button(tr("取消", "Cancel"), role: .cancel) { packToDelete = nil }
        } message: {
            if let pack = packToDelete {
                Text(tr("\(pack.name.text(chinese: true))也会从输入语言里移除。占用 \(ByteCountFormatter.string(fromByteCount: packs.store.size(pack), countStyle: .file))；以后用 ＋ 加回来时要重新下载。",
                        "\(pack.name.en) is removed from your input languages too. It takes \(ByteCountFormatter.string(fromByteCount: packs.store.size(pack), countStyle: .file)); adding it back with + downloads it again."))
            }
        }
    }

    var body: some View {
        settings.overlay {
            if let keySheetShown {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    KeySheet(model: model, provider: keySheetShown) {}
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                        .padding(.top, 70)
                }
            }
        }
    }

    private var settings: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            packDialogs(Form {
                loadErrorSection
                switch page {
                case .assistant: AssistantPage(assistant: assistant)
                case .general:
                    generalSection
                    menuBarSection
                    interfaceSection
                    ICloudSyncSection(model: model)
                case .input:
                    inputSection
                    inputLanguageSection
                case .writing:
                    translateSection
                    rewriteSection
                    jargonSection
                case .commands:
                    commandsSection
                    ExtensionSourcesSection(model: model)
                    extensionsSection
                case .plugins:
                    pluginsSection
                    webSearchSection
                case .voice: voiceSection
                case .agent: AgentSettingsPage(model: model)
                case .provider:
                    providerSection
                    requestSection
                    PrivacySection(model: model)
                case .advanced: filesSection
                case .about: aboutSection
                case .apps: AppProfilesSection(model: model)
                }
            }
            .formStyle(.grouped)
            // A white page under light gray cards, as in Raycast and System Settings (dark in dark mode).
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            // A page starts at its top, and is drawn anew in the other interface language: controls of their
            // own (the action key's recorder, the language chips) don't redraw by themselves when it changes.
            .id("\(page.rawValue)-\(UIText.language)"))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 480, idealHeight: 720)
        // Text fields save on Return; everything else (pickers, steppers, toggles) saves on change.
        .sheet(item: $commandEdit) { edit in
            CommandEditor(edit: edit, others: model.config.customCommands.enumerated()
                            .filter { $0.offset != edit.index }.map(\.element),
                          plugins: model.plugins.map(\.name)) { command in
                if let index = edit.index {
                    model.config.customCommands[index] = command
                } else {
                    model.config.customCommands.append(command)
                }
                model.save()
            }
        }
        .confirmationDialog(tr("删除这个命令？", "Delete this command?"),
                            isPresented: Binding(get: { commandToDelete != nil }, set: { if !$0 { commandToDelete = nil } })) {
            Button(tr("删除", "Delete"), role: .destructive) {
                if let index = commandToDelete, model.config.customCommands.indices.contains(index) {
                    model.config.customCommands.remove(at: index)
                    model.save()
                }
                commandToDelete = nil
            }
        } message: {
            if let index = commandToDelete, model.config.customCommands.indices.contains(index) {
                Text("@" + model.config.customCommands[index].name)
            }
        }
        .confirmationDialog(tr("删除这个插件？", "Remove this plugin?"),
                            isPresented: Binding(get: { pluginToRemove != nil }, set: { if !$0 { pluginToRemove = nil } })) {
            Button(tr("删除", "Remove", key: "remove.delete"), role: .destructive) {
                if let plugin = pluginToRemove { model.uninstall(plugin) }
                pluginToRemove = nil
            }
        } message: {
            if let plugin = pluginToRemove { Text("@" + plugin.name) }
        }
        .onChange(of: model.config.awsProfile) { model.save() }
        .onChange(of: model.config.provider) {
            customProviderModel = false
            editingKey = nil
            model.save()
        }
        .onChange(of: model.config.maxTokens) { model.save() }
        .onChange(of: model.config.temperature) { model.save() }
        .onChange(of: model.config.timeoutSeconds) { model.save() }
        .onChange(of: model.config.defaultInput) { model.save() }
        .onChange(of: model.config.outputLanguage) { model.save() }
        .onChange(of: model.config.outputLanguages) { model.save() }
        .onChange(of: model.config.inputLanguages) { model.save() }
        .onChange(of: model.config.improveTranslates) { model.save() }
        .onChange(of: model.config.voiceInput) { model.save() }
        .onChange(of: model.config.actionKey) { model.save() }
        .onChange(of: model.config.claudeInBackground) { model.save() }
        .onChange(of: model.config.agent) { model.save() }
        .onChange(of: model.config.agentCommand) { model.save() }
        .onChange(of: model.config.agentPageContext) { model.save() }
        .onChange(of: model.config.useSelection) { model.save() }
        .onChange(of: model.config.rememberQuestions) { model.save() }
        .onChange(of: model.config.typeOut) { model.save() }
        .onChange(of: model.config.typeOutRate) { model.save() }
        .onChange(of: model.config.typeOutVaries) { model.save() }
        .onChange(of: model.config.typeOutMistakes) { model.save() }
        .onChange(of: model.config.candidateLayout) { model.save() }
        .onChange(of: model.config.findRaycastScripts) {
            model.save()
            model.refreshExtensions(discover: model.config.findRaycastScripts)
        }
        .onChange(of: page) { if page == .commands { model.refreshExtensions(discover: true) } }
        .onChange(of: model.config.customCommands) { model.refreshExtensions() }  // a name an extension had may be taken now
        .onAppear {
            model.refreshPlugins()
            model.refreshExtensions(discover: page == .commands)
            model.refreshKeys()
            model.refreshSearchKey()
            model.refreshAccount()
            model.refreshVoice()
            model.refreshJargon()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshJargon()  // the list may have been edited in the text editor
            model.reloadIfChanged()  // so may the settings, or the input method's menu changed one
            model.refreshRecentQuestions()
            // Back from Terminal after `aws sso login`, say: the AWS profile's line read again.
            if model.config.provider == .bedrock { model.aws.refresh(profile: model.config.awsProfile) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMEShowSettingsPage)) { note in
            if let raw = note.userInfo?["page"] as? String, let shown = SettingsPage(rawValue: raw) { page = shown }
        }
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMEConfigChanged).receive(on: RunLoop.main)) { _ in
            model.reloadIfChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMEFocusAPIKey)) { note in
            page = .provider
            model.reloadIfChanged()  // what the Assistant just set
            guard let provider = (note.userInfo?["provider"] as? String).flatMap(Provider.init(rawValue:)) else { return }
            // The provider in use: its own row, ready to paste. Another one: the key sheet (nothing of it on this page).
            if provider == model.config.provider {
                DispatchQueue.main.async { editingKey = provider }
            } else if provider.needsKey {
                keySheet = KeySheetRequest(provider: provider)
            }
        }
        .sheet(item: $keySheet) { request in
            KeySheet(model: model, provider: request.provider) { keySheet = nil }
        }
        .onDisappear { model.save() }
    }

    /// The input method's version (Info.plist), shown at the bottom of the window.
    static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// A custom command with a built-in's name (say a `note` added before @note was built in): the built-in hides
    /// it (`Command.catalog`), so the list says so. The editor won't save such a name (`.nameTaken`).
    static func hiddenByBuiltIn(_ command: CustomCommand) -> Bool {
        Command.builtins.contains { $0.name == command.name.lowercased() }
    }

    /// The commands, at the top: what this input method does beyond typing the user's input languages.
    private var commandsSummary: String {
        let key = UIText.howToPress(model.config.actionKey)
        let languages = model.config.inputLanguages.map(AllInOneIMEInputController.inputName).joined(separator: tr("、", ", "))
        return tr("平时就是普通输入法：\(languages)。开头打 @ 用命令：@improve 润色、改写，@translate 翻译，@question 提问，"
                      + "@agent 交给 Claude Code 等 agent，@open 找文件，@note 存到备忘录，@reminder 加提醒事项。写完\(key)执行。",
                  "A regular input method: \(languages). "
                      + "Type @ first for commands: @improve polishes and rewrites, @translate "
                      + "translates, @question asks, @agent hands it to a coding agent (Claude Code …), @open finds files, @note saves to Notes, "
                      + "@reminder adds a reminder. When done, \(key).")
    }

    /// What @improve does for each input language: "@improve: Chinese → polish / rewrite; Korean → …".
    private var inputSummary: String {
        let each = model.config.inputLanguages.map { "\(UIText.name($0)) → \(UIText.action(input: $0, config: model.config))" }
        return tr("@improve：打", "@improve: ") + each.joined(separator: tr("；打", "; ", key: "improve.separator")) + tr("。", ".")
    }

    /// Adds an input language; one whose pack isn't installed is added once the pack has downloaded
    /// (until then it isn't an input mode), and its tab is then shown.
    private func addInputLanguage(_ language: Language) {
        guard let pack = LanguagePack.for(language), !packs.isInstalled(pack) else {
            model.config.inputLanguages.append(language)
            model.config.normalizeLanguages()
            inputTab = language
            return
        }
        let model = model
        packs.download(pack) {
            guard !model.config.inputLanguages.contains(language) else { return }
            model.config.inputLanguages.append(language)
            model.config.normalizeLanguages()
            model.save()  // the window may be closed by now
        }
        inputTab = language
    }

    private func isDownloading(_ pack: LanguagePack) -> Bool {
        if case .downloading = packs.state(pack) { return true }
        return false
    }

    /// A pack's download in progress (with Cancel) or its failure (with Retry); nothing otherwise.
    @ViewBuilder private func packRow(_ pack: LanguagePack) -> some View {
        switch packs.state(pack) {
        case let .downloading(share):
            LabeledContent {
                HStack(spacing: 8) {
                    if let share {
                        ProgressView(value: share).frame(width: 140)
                        Text("\(Int(share * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button(tr("取消", "Cancel")) { packs.cancel(pack) }
                }
            } label: {
                titled(tr("正在下载\(pack.name.text(chinese: true))语言包", "Downloading the \(pack.name.en) language pack"),
                       tr("下载完就能用，不用重启", "Ready when it's done, no restart"))
            }
        case let .failed(message):
            LabeledContent {
                Button(tr("重试", "Retry")) { addInputLanguage(pack.language) }
            } label: {
                titled(tr("\(pack.name.text(chinese: true))语言包没有下载成功", "The \(pack.name.en) language pack didn't download"), message)
            }
        case .notInstalled, .installed:
            EmptyView()
        }
    }

    /// What a language's card says about its pack: the version, its size, where it came from, and Delete.
    @ViewBuilder private func packInfo(_ pack: LanguagePack) -> some View {
        if case let .installed(record) = packs.state(pack) {
            let size = ByteCountFormatter.string(fromByteCount: packs.store.size(pack), countStyle: .file)
            LabeledContent {
                Button(tr("删除…", "Delete…")) { packToDelete = pack }
            } label: {
                titled(tr("语言包", "Language pack"),
                       record.source == .library
                       ? tr("\(record.version) · \(size) · 从语言包库下载", "\(record.version) · \(size) · downloaded from the language library")
                       : tr("\(record.version) · \(size) · 更新时从旧版本留下，没有重新下载",
                            "\(record.version) · \(size) · kept from the earlier version when updating, not downloaded"))
            }
        }
    }

    /// Deletes a pack from its card: its language is removed from the input languages first.
    private func deletePack(_ pack: LanguagePack) {
        let languages = model.config.inputLanguages
        if languages.contains(pack.language) {
            model.config.setOrder(languages == [pack.language] ? [Language.english] : languages.filter { $0 != pack.language })
        }
        packs.remove(pack)
    }

    /// Moves an input language one place earlier (-1) or later (1); the first is the default.
    private func moveInput(_ language: Language, by step: Int) {
        var languages = model.config.inputLanguages
        guard let index = languages.firstIndex(of: language), languages.indices.contains(index + step) else { return }
        languages.swapAt(index, index + step)
        model.config.setOrder(languages)
    }

    /// Removes an input language; the next one becomes the default, or English when it was the only one.
    private func removeInputLanguage(_ language: Language) {
        let languages = model.config.inputLanguages
        model.config.setOrder(languages == [language] ? [Language.english] : AllInOneIMEInputController.toggled(language, in: languages))
        // Its pack stays unless the user deletes it too (asked, with its size).
        if !model.config.inputLanguages.contains(language), let pack = LanguagePack.for(language), packs.isInstalled(pack) {
            packToRemove = pack
        }
    }

    private func addOutputLanguage(_ language: OutputLanguage) {
        model.config.outputLanguages.append(language)
    }

    /// Removes an added output language (one always stays); the next one is then in use.
    private func removeOutputLanguage(_ language: OutputLanguage) {
        guard model.config.outputLanguages.count > 1 else { return }
        model.config.setOrder(model.config.outputLanguages.filter { $0 != language })
    }

    /// The typing speed as shown: "每秒 16 个字" / "16 a second", or slower than one a second "6 秒一个字" / "6 s each".
    static func rateLabel(_ rate: Double) -> String {
        if rate >= 1 { return tr("每秒 \(Int(rate.rounded())) 个字", "\(Int(rate.rounded())) a second") }
        let seconds = 1 / rate
        let shown = seconds < 2 ? String(format: "%.1f", seconds) : String(Int(seconds.rounded()))
        return tr("\(shown) 秒一个字", "\(shown) s each")
    }

    /// Slider values rounded to what the label shows (whole characters a second, or whole / tenth seconds each).
    static func roundedRate(_ rate: Double) -> Double {
        if rate >= 1 { return rate.rounded() }
        let seconds = 1 / rate
        return 1 / (seconds < 2 ? (seconds * 10).rounded() / 10 : seconds.rounded())
    }

    /// How the chosen action key works, and what Space does with it.
    static func actionKeyNote(_ key: ActionKey) -> String {
        switch key {
        case .enter:
            return tr("@ 命令写完按 ⏎ 执行，拼音没选完也能直接按。没有 @ 时 ⏎ 就是普通回车。",
                      "Return runs an @ command, also on pinyin not yet picked. Without @, Return is a normal Return.")
        case .optionTap:
            return tr("按一下 ⌥ 马上松开，左右都行；按住右 ⌥ 仍然是说话。@ 命令按 ⏎ 也执行。",
                      "Press either ⌥ and let go right away; holding right ⌥ still dictates. @ commands also run on Return.")
        case .optionSpace:
            return tr("拼音没选完也可以直接按 ⌥空格。⌥空格被 Alfred、Raycast 等占用时，改用「单按 ⌥」。@ 命令按 ⏎ 也执行。",
                      "⌥Space also works before the pinyin is picked. If Alfred, Raycast or another app uses ⌥Space, "
                          + "choose Tap ⌥. @ commands also run on Return.")
        case .space:
            return tr("空格先选词，没有要选的了再按一次空格执行；英文模式下连按两次空格。@ 命令按 ⏎ 也执行。",
                      "Space picks words; once nothing is left to pick, Space again runs it. In English mode, press Space twice. "
                          + "@ commands also run on Return.")
        case let .shortcut(key):
            return tr("@ 命令写完按 \(key.name) 执行；⏎ 也执行，没有 @ 时 ⏎ 是普通回车。",
                      "\(key.name) runs an @ command; Return does too, and without @ Return is a normal Return.")
        }
    }

    @ViewBuilder
    private func modelStatus(_ language: Language) -> some View {
        if let progress = model.modelProgress[language] {
            HStack {
                ProgressView(value: progress).frame(width: 120)
                Text(String(format: "%.0f%%", progress * 100)).foregroundStyle(.secondary).monospacedDigit()
            }
        } else {
            switch model.installedModels[language] {
            case true?: Text(tr("已安装", "Installed")).foregroundStyle(.secondary)
            case false?: Button(tr("下载（只需一次）", "Download (once)")) { model.downloadModel(language) }
            case nil: ProgressView().controlSize(.small)
            }
        }
    }

    /// Amazon Bedrock: the model, the AWS profile with its keys, and the region.
    @ViewBuilder
    private var bedrockSettings: some View {
        Picker(tr("模型", "Model"), selection: modelSelection) {
            ForEach(SuggestedModel.all) { m in
                Text(m.title + tr("　", "  ") + m.note).tag(m.id)
            }
            Text(tr("自定义…", "Custom…")).tag("custom")
        }
        if customModel || !SuggestedModel.all.contains(where: { $0.id == model.config.modelId }) {
            TextField(tr("模型 ID", "Model ID"), text: $model.config.modelId,
                      prompt: Text(tr("例如 ", "e.g. ") + "us.anthropic.claude-haiku-4-5-20251001-v1:0"))
                .onSubmit { model.save() }
        }
        AWSProfilePicker(selection: $model.config.awsProfile, names: model.profiles, shownAs: model.profileShownAs, aws: model.aws)
        TextField(tr("区域", "Region"), text: regionBinding,
                  prompt: Text(tr("留空用 profile 的区域（\(model.profileRegion)）",
                                  "Empty: the profile's region (\(model.profileRegion))")))
            .onSubmit { model.save() }
        AWSProfileStatusRow(profile: model.config.awsProfile, aws: model.aws, shownAs: model.profileShownAs)
    }

    /// AllInOneIME Cloud: the Google account, today's free requests, the subscription.
    @ViewBuilder
    private var hostedSettings: some View {
        if let account = model.account {
            LabeledContent(tr("账号", "Account")) {
                HStack {
                    Text(account.email ?? "").textSelection(.enabled)
                    Button(tr("退出", "Sign Out")) { model.signOut() }
                }
            }
            LabeledContent(tr("今天免费", "Free today")) {
                Text("\(account.freeRemaining) / \(account.freeLimit)").monospacedDigit()
            }
            LabeledContent(tr("订阅剩余", "Subscription")) {
                Text(account.isSubscribed || account.credits > 0 ? "\(account.credits)" : tr("未订阅", "None", key: "account.notSubscribed")).monospacedDigit()
            }
            HStack {
                // Until Stripe is set up (no payment link), there is nothing to subscribe to.
                if account.isSubscribed, !HostedService.portalLink.isEmpty {
                    Button(tr("管理订阅", "Manage Subscription")) { model.manageSubscription() }
                } else if !account.isSubscribed, !HostedService.paymentLink.isEmpty {
                    Button(tr("订阅：$3/月 3000 次", "Subscribe: $3/month for 3000")) { model.subscribe() }
                }
                Button(tr("刷新", "Refresh")) { model.refreshAccount() }
            }
            Text(tr("先用每天的免费次数，用完再用订阅的次数。付款在浏览器里完成，完成后点「刷新」。",
                    "The day's free requests are used first, then the subscription's. Payment happens in the browser; click Refresh afterwards."))
                .font(.caption).foregroundStyle(.secondary)
        } else {
            HStack {
                if HostedService.googleEnabled {
                    Button(tr("用 Google 登录", "Sign in with Google")) { model.signIn(.google) }.disabled(model.accountBusy)
                }
                Button(tr("用邮箱登录 / 注册", "Sign in / Sign up with Email")) { model.signIn(.email) }.disabled(model.accountBusy)
                if model.accountBusy { ProgressView().controlSize(.small) }
            }
            Text(tr("登录后每天免费 20 次，不用自己的 AWS 或 API key。",
                    "Signed in, you get 20 free requests a day, without an AWS account or API key of your own."))
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error = model.accountError { Text(error).foregroundStyle(.red) }
    }

    /// A provider in the picker: Apple Intelligence greyed out, with the reason, on a Mac where it can't be used.
    @ViewBuilder
    private func providerItem(_ provider: Provider) -> some View {
        let apple = provider == .apple ? AppleModel.system.availability : .available
        Text(UIText.name(provider) + (apple == .available ? "" : tr("（", " (") + UIText.reason(apple) + tr("）", ")")))
            .tag(provider)
            .disabled(apple != .available)
    }

    /// Apple Intelligence on this Mac: whether it can be used, and where to turn it on.
    @ViewBuilder
    private var appleSettings: some View {
        let availability = AppleModel.system.availability
        if availability == .available {
            Text(tr("✓ 这台 Mac 上可以使用", "✓ Ready on this Mac")).foregroundStyle(.green)
        } else {
            Text(UIText.describe(AppleModelError.unavailable(availability))).foregroundStyle(.orange)
            if availability != .deviceNotEligible, availability != .unsupportedSystem {
                Button(tr("打开「Apple 智能与 Siri」设置…", "Open Apple Intelligence & Siri Settings…")) {
                    NSWorkspace.shared.open(AppleModel.settingsURL)
                }
            }
        }
        let context = "\(AppleModel.system.contextSize / 1024)K"
        Text(tr("用这台 Mac 自带的模型（macOS 26 起）：不用 API key，不花钱，文字不离开这台 Mac。模型较小：上下文约 \(context) tokens，"
                    + "支持的语言少一些，效果不如云端的模型。",
                "Uses the model built into this Mac (macOS 26 and later): no API key, no cost, and nothing leaves the Mac. "
                    + "It is a small model: about \(context) tokens of context, fewer languages, and results below the cloud models'."))
            .font(.caption).foregroundStyle(.secondary)
    }

    /// An API-key provider: the model, the key (kept in the keychain), the base URL and the effort.
    @ViewBuilder
    private func apiKeySettings(_ provider: Provider) -> some View {
        let settings = model.config.settings(for: provider)
        let suggested = SuggestedModel.suggested(for: provider)
        if !suggested.isEmpty {
            Picker(tr("模型", "Model"), selection: providerModelSelection(provider)) {
                ForEach(suggested) { m in
                    Text(m.title + tr("　", "  ") + m.note).tag(m.id)
                }
                Text(tr("自定义…", "Custom…")).tag("custom")
            }
        }
        if suggested.isEmpty || customProviderModel || !suggested.contains(where: { $0.id == settings.model }) {
            // The default model, when there is one, is the placeholder: an empty field uses it, and is never saved as it.
            TextField(tr("模型 ID", "Model ID"), text: providerBinding(provider, \.model),
                      prompt: Text(ProviderSettings.defaults(for: provider).model ?? tr("例如 ", "e.g. ") + Self.modelExample(provider)))
                .onSubmit { model.save() }
        }
        // Whether a key is set, in the row itself: with one, the paste field shows only after Replace….
        LabeledContent("API key") {
            KeyRowContent(state: model.keyState(provider), missing: tr("还没有 API key", "No API key yet"),
                          prompt: tr("粘贴新的 API key", "Paste a new API key"),
                          removeTitle: tr("从钥匙串里删除 \(UIText.name(provider)) 的 API key？",
                                          "Remove the key for \(UIText.name(provider)) from the keychain?"),
                          removeMessage: tr("删除后，要再粘贴一次 key 才能用 \(UIText.name(provider))。",
                                            "To use \(UIText.name(provider)) again, you'll have to paste the key again."),
                          save: { model.saveKey($0, for: provider) },
                          remove: model.keySources[provider] == .keychain ? { model.removeKey(provider) } : nil,
                          editing: Binding(get: { editingKey == provider }, set: { editingKey = $0 ? provider : nil }))
        }
        if let error = model.keyError { Text(error).foregroundStyle(.red) }
        TextField(tr("Base URL", "Base URL"), text: providerBinding(provider, \.baseURL),
                  prompt: Text(ProviderSettings.defaults(for: provider).baseURL ?? ""))
            .onSubmit { model.save() }
        if provider == .openai {
            Menu(tr("常用服务…", "Common Services…")) {
                ForEach(CompatibleService.all) { service in
                    Button(service.name) { useService(service) }
                }
            }
            .fixedSize()
            Text(tr("选一个服务会填好它的 Base URL，再在「自定义…」里填它的模型。也可以填任何其他兼容 OpenAI 的地址。",
                    "Picking a service fills in its base URL; then enter its model under Custom…. Any other OpenAI-compatible address works too."))
                .font(.caption).foregroundStyle(.secondary)
        }
        Picker(tr("思考", "Thinking"), selection: providerBinding(provider, \.effort, empty: "", showsDefault: true)) {
            Text(tr("少（low，最快）", "Little (low, fastest)")).tag("low")
            Text("medium").tag("medium")
            Text("high").tag("high")
            Text(tr("不设置（模型不支持时选）", "Not set (for models without it)")).tag("")
        }
    }

    /// A common OpenAI-compatible service: its base URL, and its model to type in (the model of
    /// another service wouldn't exist there).
    private func useService(_ service: CompatibleService) {
        var settings = model.providerSettings(.openai)
        settings.baseURL = service.baseURL
        settings.model = service.model
        model.setProviderSettings(settings, for: .openai)
        customProviderModel = true
    }

    static func modelExample(_ provider: Provider) -> String {
        switch provider {
        case .anthropic: return "claude-sonnet-5-5"
        case .gemini: return "gemini-3.8-flash"
        case .openai: return "deepseek-chat"
        case .hosted, .apple: return ""
        case .bedrock: return "us.anthropic.claude-haiku-4-5-20251001-v1:0"
        }
    }

    /// One string setting of a provider, as set: a text field shows only what was set, the default being its placeholder
    /// (an empty field falls back to it), so leaving the field, or ⏎ on it, never writes the default as if the user had
    /// typed it. `showsDefault`: a picker, which shows the default as its selection. Nothing is written unless the value
    /// changes.
    private func providerBinding(_ provider: Provider, _ key: WritableKeyPath<ProviderSettings, String?>,
                                 empty: String? = nil, showsDefault: Bool = false) -> Binding<String> {
        Binding(
            get: {
                model.providerSettings(provider)[keyPath: key]
                    ?? (showsDefault ? model.config.settings(for: provider)[keyPath: key] : nil) ?? ""
            },
            set: { value in
                var settings = model.providerSettings(provider)
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                let new = trimmed.isEmpty ? empty : trimmed
                guard settings[keyPath: key] != new else { return }
                settings[keyPath: key] = new
                model.setProviderSettings(settings, for: provider)
            })
    }

    private func providerModelSelection(_ provider: Provider) -> Binding<String> {
        let suggested = SuggestedModel.suggested(for: provider)
        return Binding(
            get: {
                let current = model.config.settings(for: provider).model ?? ""
                return customProviderModel || !suggested.contains(where: { $0.id == current }) ? "custom" : current
            },
            set: { choice in
                customProviderModel = choice == "custom"
                guard choice != "custom" else { return }
                var settings = model.providerSettings(provider)
                settings.model = choice
                model.setProviderSettings(settings, for: provider)
            })
    }

    /// The plugin library: a "Browse" button until opened (no network before), then what it offers with
    /// Install / Update / Installed, and a confirmation naming what a plugin contacts.
    @ViewBuilder private var pluginLibrary: some View {
        if let entries = model.libraryEntries {
            HStack {
                Text(tr("插件库", "Plugin Library")).font(.headline)
                Spacer()
                if model.libraryBusy { ProgressView().controlSize(.small) }
                Button(tr("刷新插件库", "Refresh Library")) { model.refreshLibrary() }.disabled(model.libraryBusy)
            }
            // On the header, which is there whenever an Install or Update button is.
            .confirmationDialog(pluginToInstall.map { tr("安装 @\($0.name) \($0.version)？", "Install @\($0.name) \($0.version)?") } ?? "",
                                isPresented: Binding(get: { pluginToInstall != nil }, set: { if !$0 { pluginToInstall = nil } })) {
                Button(tr("安装", "Install")) {
                    if let entry = pluginToInstall { model.install(entry) }
                    pluginToInstall = nil
                }
            } message: {
                if let entry = pluginToInstall {
                    Text(libraryContacts(entry) + "\n" + tr("从 \(model.libraryHost) 下载，逐个文件核对签名的索引。",
                                                            "Downloaded from \(model.libraryHost), every file checked against the signed index."))
                }
            }
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.icon ?? "puzzlepiece.extension.fill")
                        .foregroundStyle(.white).frame(width: 22, height: 22)
                        .background(Color(nsColor: CommandIcons.color(entry.color) ?? .systemPink), in: RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("@" + entry.name).font(.body.monospaced())
                            Text(entry.version).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.summary?.text(chinese: UIText.chinese) ?? "").foregroundStyle(.secondary).lineLimit(2)
                        Text(libraryContacts(entry)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    libraryButton(entry)
                }
            }
            if entries.isEmpty {
                Text(tr("插件库里暂时没有这个版本能用的插件。", "The library has no plugins for this version yet."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Button(tr("浏览插件库…", "Browse Library…")) { model.refreshLibrary() }.disabled(model.libraryBusy)
                if model.libraryBusy { ProgressView().controlSize(.small) }
            }
            Text(tr("插件库里的插件都经过审核和签名；打开时才会联网（\(model.libraryHost)）。",
                    "Library plugins are reviewed and signed; the library is fetched only when you open it (\(model.libraryHost))."))
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error = model.libraryError { Text(error).foregroundStyle(.red) }
    }

    @ViewBuilder private func libraryButton(_ entry: PluginIndex.Entry) -> some View {
        if model.installingPlugin == entry.name {
            ProgressView().controlSize(.small)
        } else {
            switch model.libraryStatus[entry.name] ?? .notInstalled {
            case .notInstalled:
                Button(tr("安装", "Install")) { pluginToInstall = entry }.disabled(model.installingPlugin != nil)
            case let .update(from):
                Button(tr("更新（当前 \(from)）", "Update (from \(from))")) { pluginToInstall = entry }.disabled(model.installingPlugin != nil)
            case .installed:
                Text(tr("已安装", "Installed")).foregroundStyle(.secondary)
            case .local:
                Text(tr("已有同名本地插件", "Local plugin installed")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// What a library plugin contacts: "what you type after @stock goes to query1.finance.yahoo.com".
    private func libraryContacts(_ entry: PluginIndex.Entry) -> String {
        let hosts = entry.hosts.joined(separator: ", ")
        switch entry.type {
        case "prompt": return tr("AI 指令，发给你选的 AI 服务", "An AI instruction, sent to your AI provider")
        case "link":
            let target = entry.url.flatMap { URL(string: $0)?.host } ?? hosts
            return tr("@\(entry.name) 后面的内容会在浏览器里打开 \(target)", "Opens what you type after @\(entry.name) at \(target) in the browser")
        default:
            return hosts.isEmpty ? tr("不联网", "No network")
                : tr("@\(entry.name) 后面输入的内容会发到 \(hosts)", "What you type after @\(entry.name) goes to \(hosts)")
        }
    }

    /// "1.0.0 · sends what you type after @stock to query1.finance.yahoo.com · local".
    private func pluginDetail(_ plugin: InstalledPlugin) -> String {
        var parts = [plugin.manifest.version]
        switch plugin.manifest.type {
        case .script:
            let hosts = plugin.manifest.hosts.joined(separator: ", ")
            parts.append(hosts.isEmpty ? tr("不联网", "no network")
                         : tr("@\(plugin.name) 后面的内容会发到 \(hosts)", "sends the text after @\(plugin.name) to \(hosts)"))
        case .prompt:
            parts.append(tr("AI 指令，发给你选的 AI 服务", "an AI instruction, sent to your AI provider"))
        case .link:
            let host = plugin.manifest.destinationHosts.joined(separator: ", ")
            parts.append(tr("@\(plugin.name) 后面的内容会在浏览器里打开 \(host)", "opens \(host) in the browser with the text after @\(plugin.name)"))
        }
        if plugin.isLocal { parts.append(tr("本地插件（未经审核）", "local (not reviewed)")) }
        return parts.joined(separator: " · ")
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: {
                customModel || !SuggestedModel.all.contains(where: { $0.id == model.config.modelId })
                    ? "custom" : model.config.modelId
            },
            set: { choice in
                if choice == "custom" {
                    customModel = true
                } else {
                    customModel = false
                    model.config.modelId = choice
                    model.save()
                }
            })
    }

    private var regionBinding: Binding<String> {
        Binding(get: { model.config.region ?? "" },
                set: { model.config.region = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }

    private var temperatureOn: Binding<Bool> {
        Binding(get: { model.config.temperature != nil },
                set: { model.config.temperature = $0 ? (model.config.temperature ?? 0.3) : nil })
    }
}

/// The single settings window of the input method process.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private var closing: NSObjectProtocol?

    static var title: String { tr("AllInOneIME 设置", "AllInOneIME Settings") }

    /// After the window's language changed.
    func updateTitle() { window?.title = Self.title }

    /// Whether the window is open (an update opens it again once the input method restarts).
    var isVisible: Bool { window?.isVisible == true }

    /// Shows the window on `page` (already open: it turns to it).
    func show(page: SettingsPage) {
        show(opening: page)
        NotificationCenter.default.post(name: .allInOneIMEShowSettingsPage, object: nil, userInfo: ["page": page.rawValue])
    }

    /// Shows the window; opened now, it starts on Assistant.
    func show() { show(opening: nil) }

    private func show(opening page: SettingsPage?) {
        AgentAvailability.forget()  // an agent may have been installed meanwhile
        if window?.isVisible != true {
            // (Re)build so the window reflects the config file as it is now.
            window?.close()
            let model = SettingsModel()
            UIText.choice = model.config.uiLanguage
            let host = NSHostingController(rootView: SettingsView(model: model, page: page))
            let window = NSWindow(contentViewController: host)
            // Fields saved on ⏎ (a model ID, the base URL) are saved when the window closes too.
            if let closing { NotificationCenter.default.removeObserver(closing) }
            closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                             queue: .main) { _ in
                MainActor.assumeIsolated { model.save() }
            }
            window.title = Self.title
            // The sidebar runs up under the traffic lights, as in System Settings.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 900
            window.setContentSize(NSSize(width: 880, height: min(760, visible - 60)))
            window.center()
            self.window = window
        }
        // The input method is an agent app: activate it so the window can take keyboard focus. If macOS
        // doesn't grant activation (another app is active), still put the window in front; a click
        // into it then activates it.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Where the Google sign-in sheet is shown: the settings window.
final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}

/// OpenAI-compatible services offered under "Common Services…": their base URLs (a model to start
/// with only where its ID is long-standing; otherwise the model is typed in).
struct CompatibleService: Identifiable {
    let name: String
    let baseURL: String
    let model: String?
    var id: String { baseURL }

    static var all: [CompatibleService] {
        [
            CompatibleService(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-6-luna"),
            CompatibleService(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
            CompatibleService(name: tr("通义千问（阿里云百炼）", "Qwen (Alibaba Cloud Model Studio)"),
                              baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: nil),
            CompatibleService(name: tr("通义千问（海外）", "Qwen (international)"),
                              baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", model: nil),
            CompatibleService(name: tr("Kimi（月之暗面）", "Kimi (Moonshot)"), baseURL: "https://api.moonshot.cn/v1", model: nil),
            CompatibleService(name: tr("智谱 GLM", "Zhipu GLM"), baseURL: "https://open.bigmodel.cn/api/paas/v4", model: nil),
            CompatibleService(name: tr("硅基流动", "SiliconFlow"), baseURL: "https://api.siliconflow.cn/v1", model: nil),
            CompatibleService(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: nil),
            CompatibleService(name: tr("本机 Ollama", "Ollama on this Mac"), baseURL: "http://localhost:11434/v1", model: nil),
        ]
    }
}

/// Added languages as chips in the user's order, dragged to reorder: the first is marked
/// ("中文（拼音）· 默认"), ⓧ removes one (not the last). The chip follows the pointer and the order
/// changes where it's let go. The drag is tracked in AppKit (`DragHandle`): a grouped Form sits on a
/// table view that takes mouse drags for itself, so neither SwiftUI's drag gesture nor its drag and
/// drop ever start there.
private struct LanguageChips<Item: Hashable>: View {
    let items: [Item]
    let name: (Item) -> String
    /// What the first is ("默认"); nil: the order matters, no one is special.
    let firstNote: String?
    /// The last one can't be removed (a language); styles can all go.
    var keepsOne = true
    let reorder: ([Item]) -> Void
    let remove: (Item) -> Void
    /// Chips that are also tabs: the one whose settings show (highlighted), and a click picks another.
    var selected: Item? = nil
    var select: ((Item) -> Void)? = nil
    @State private var frames: [Item: CGRect] = [:]
    @State private var dragging: Item?
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                chip(item)
                    .background(GeometryReader { geometry in
                        // Window coordinates: the pointer's x comes from AppKit in the window too.
                        Color.clear.preference(key: ChipFrames.self, value: [AnyHashable(item): geometry.frame(in: .global)])
                    })
                    .offset(x: dragging == item ? offset : 0)
                    .zIndex(dragging == item ? 1 : 0)
                    .opacity(dragging == item ? 0.8 : 1)
            }
        }
        .padding(1)  // room for the picked chip's outline
        .onPreferenceChange(ChipFrames.self) { all in
            frames = Dictionary(uniqueKeysWithValues: all.compactMap { key, frame in (key.base as? Item).map { ($0, frame) } })
        }
        .animation(.easeOut(duration: 0.15), value: items)
    }

    private func chip(_ item: Item) -> some View {
        let first = item == items.first && firstNote != nil
        let label = first && items.count > 1 ? name(item) + " · " + (firstNote ?? "") : name(item)
        let picked = select != nil && item == selected
        return HStack(spacing: 2) {
            Text(label).foregroundStyle(picked || first ? .primary : .secondary)
                .overlay {
                    if items.count > 1 || select != nil {
                        DragHandle(onTap: { select?(item) }, onChanged: { dx in
                            guard items.count > 1 else { return }
                            dragging = item
                            offset = dx
                        }, onEnded: { x in
                            guard items.count > 1 else { return }
                            let moved = ChipOrder.moved(item, in: items, to: x, midX: { frames[$0]?.midX })
                            dragging = nil
                            offset = 0
                            if moved != items { reorder(moved) }
                        })
                    }
                }
            if items.count > 1 || !keepsOne {
                Button { remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help(tr("移除\(name(item))", "Remove \(name(item))"))
                    .accessibilityLabel(tr("移除\(name(item))", "Remove \(name(item))"))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(picked ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(first ? 0.22 : 0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(picked ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .help(firstNote.map { tr("拖动排序，第一个是\($0)", "Drag to reorder; the first is \($0)") } ?? tr("拖动排序", "Drag to reorder"))
    }
}

/// Tracks a mouse drag itself (its own event loop from mouseDown to mouseUp), so the table view under
/// the Form never sees it: reports the horizontal distance while dragging and the pointer's x in the
/// window where it's let go. A click without moving is a tap.
private struct DragHandle: NSViewRepresentable {
    /// A click without moving.
    var onTap: () -> Void = {}
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> HandleView { HandleView() }

    func updateNSView(_ view: HandleView, context: Context) {
        view.onTap = onTap
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    final class HandleView: NSView {
        var onTap: (() -> Void)?
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            let start = event.locationInWindow.x
            var moved = false
            while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                let dx = next.locationInWindow.x - start
                if next.type == .leftMouseUp {
                    if moved { onEnded?(next.locationInWindow.x) } else { onTap?() }
                    break
                }
                if abs(dx) > 3 { moved = true }
                if moved {
                    NSCursor.closedHand.set()
                    onChanged?(dx)
                }
            }
            window?.invalidateCursorRects(for: self)
        }
    }
}

private struct ChipFrames: PreferenceKey {
    static let defaultValue: [AnyHashable: CGRect] = [:]
    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where a dragged chip lands: before every other chip whose middle is right of where it was let go.
enum ChipOrder {
    static func moved<Item: Equatable>(_ item: Item, in items: [Item], to x: CGFloat, midX: (Item) -> CGFloat?) -> [Item] {
        let others = items.filter { $0 != item }
        let index = others.filter { (midX($0) ?? .infinity) < x }.count
        var result = others
        result.insert(item, at: index)
        return result
    }
}

/// The action key and a button to record another: the next key pressed with ⌃, ⌥ or ⌘ (or Return,
/// Space, ⌥Space, a function key), or a tap of ⌥ on its own. Esc cancels; a plain letter is refused
/// (it couldn't be typed any more).
private struct KeyRecorder: View {
    @Binding var key: ActionKey
    @State private var recording = false
    @State private var refused = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(recording ? (refused ? tr("要带 ⌃、⌥ 或 ⌘", "Add ⌃, ⌥ or ⌘") : tr("按下新的键…", "Press a key…")) : UIText.pickerName(key))
                .foregroundStyle(recording ? .secondary : .primary)
                .frame(minWidth: 90, alignment: .trailing)
            Button(recording ? tr("取消", "Cancel") : tr("录制…", "Record…")) { recording ? stop() : start() }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        refused = false
        var optionDown = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
                if flags == .option { optionDown = true } else if flags.isEmpty, optionDown { finish(.optionTap) } else { optionDown = false }
                return event
            }
            optionDown = false
            if event.keyCode == VirtualKey.escape, event.modifierFlags.intersection([.control, .option, .command]).isEmpty {
                stop()
                return nil
            }
            let modifiers = AllInOneIMEInputController.modifiers(event.modifierFlags)
            if let recorded = ActionKey.recorded(keyCode: event.keyCode, usage: MacKeyboard.usage(event.keyCode), modifiers: modifiers,
                                                 name: Self.name(event)) {
                finish(recorded)
            } else {
                refused = true
            }
            return nil
        }
    }

    private func finish(_ recorded: ActionKey) {
        key = recorded
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    /// "⌃⏎", "⌘J", "⌥F5": the modifiers in the system's order, then the key.
    static func name(_ event: NSEvent) -> String {
        let flags = event.modifierFlags
        var name = ""
        if flags.contains(.control) { name += "⌃" }
        if flags.contains(.option) { name += "⌥" }
        if flags.contains(.shift) { name += "⇧" }
        if flags.contains(.command) { name += "⌘" }
        let keys: [UInt16: String] = [
            VirtualKey.returnKey: "⏎", VirtualKey.keypadEnter: "⌤", VirtualKey.tab: "⇥", VirtualKey.space: tr("空格", "Space"),
            VirtualKey.delete: "⌫", VirtualKey.forwardDelete: "⌦", 0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        return name + (keys[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "?").uppercased())
    }
}

/// A colored rounded square with a white symbol, as in System Settings and the command list.
struct IconTile: View {
    let icon: CandidateView.Icon
    var size: CGFloat = 20

    var body: some View {
        if let path = icon.image, let image = CommandIcons.image(path) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
        } else if let emoji = icon.emoji {
            Text(emoji).font(.system(size: size * 0.8)).frame(width: size, height: size).accessibilityHidden(true)
        } else {
            tile
        }
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        // Fitted into the same box whatever its shape: a wide symbol (translate) stays inside the tile.
        return Image(systemName: icon.symbol)
            .resizable()
            .symbolRenderingMode(.monochrome)
            .fontWeight(.semibold)
            .scaledToFit()
            .foregroundStyle(.white)
            .frame(width: size * 0.7, height: size * 0.58)  // wider than tall: a wide symbol gets the room
            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            .frame(width: size, height: size)
            .background {
                // A little depth, like the icons of System Settings: lighter at the top, a fine edge.
                ZStack {
                    shape.fill(Color(nsColor: icon.color))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0), .black.opacity(0.08)],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// A section heading with its icon.
struct SectionTitle: View {
    let title: String
    let icon: CandidateView.Icon

    init(_ title: String, icon: CandidateView.Icon) {
        self.title = title
        self.icon = icon
    }

    // Plain, like System Settings: the page's icon is in the sidebar.
    var body: some View {
        Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).padding(.top, 6)
    }
}


/// The settings window's pages, in the sidebar's order.
enum SettingsPage: String, CaseIterable, Identifiable {
    case assistant, general, input, writing, commands, plugins, voice, agent, provider, advanced, about, apps

    var id: String { rawValue }

    static let groups: [[SettingsPage]] = [[.assistant], [.general, .input, .writing, .voice, .apps], [.commands, .plugins, .agent, .provider],
                                           [.advanced, .about]]

    var title: String {
        switch self {
        case .assistant: return tr("助手", "Assistant")
        case .general: return tr("通用", "General")
        case .input: return tr("输入", "Input")
        case .writing: return tr("翻译与改写", "Translate & Rewrite")
        case .commands: return tr("自定义命令", "Custom Commands")
        case .plugins: return tr("插件", "Plugins")
        case .voice: return tr("语音输入", "Voice Input")
        case .agent: return tr("Agent", "Agent")
        case .provider: return tr("AI 服务", "AI Provider")
        case .advanced: return tr("高级", "Advanced")
        case .about: return tr("关于", "About")
        case .apps: return tr("按 App 设置", "Apps")
        }
    }

    var icon: CandidateView.Icon {
        switch self {
        case .assistant: return CandidateView.Icon(symbol: "wand.and.stars", color: .systemPurple)
        case .general: return CandidateView.Icon(symbol: "gearshape.fill", color: .systemGray)
        case .input: return CommandIcons.input
        case .writing: return CommandIcons.translate
        case .commands: return CommandIcons.commands
        case .plugins: return CommandIcons.plugins
        case .voice: return CommandIcons.voice
        case .agent: return CommandIcons.agent
        case .provider: return CommandIcons.provider
        case .advanced: return CommandIcons.advanced
        case .about: return CandidateView.Icon(symbol: "info", color: .systemBlue)
        case .apps: return CandidateView.Icon(symbol: "square.grid.2x2.fill", color: .systemIndigo)
        }
    }

    /// Words its settings go by, in both languages, for the search field.
    private var keywords: String {
        switch self {
        case .assistant: return "assistant config change settings describe sentence doctor check problems fix diagnose 助手 设置 改设置 描述 一句话 检查 问题 修复 诊断"
        case .general: return "action key return 执行键 回车 type out typing speed typos mistakes forget 逐字上屏 打字速度 打错 忘掉 menu bar panel 菜单栏 面板 interface language 界面语言 中文 english recent questions history @question clear 最近的问题 提问 记录 历史 清除 continue conversation claude code chatgpt gemini copy 接着聊 对话 追问 复制 icloud drive sync macs learned words hidden words remove 同步 云盘 多台 学到的词 隐藏的词 移除"
        case .input: return "input languages pinyin english chinese shift 输入语言 拼音 中文 英文 fuzzy 模糊音 zh ch sh candidate layout horizontal vertical 候选 排列 横排 竖排"
        case .writing: return "translate languages 翻译 语言 rewrite styles polish concise formal casual tactful jargon 改写 润色 简洁 正式 口语 委婉 黑话 jargon list 黑话库 improve"
        case .commands: return "custom commands 自定义 命令 prompt program terminal link 程序 终端 网页 raycast script commands scripts extensions bundles preferences 脚本 扩展 扩展包 偏好 文件夹 folder spotlight 聚焦 extension sources git repository link clone update pin ssh 扩展来源 仓库 链接 从链接添加 克隆 更新 固定"
        case .plugins: return "plugins library 插件 插件库 stock xe search 搜索 brave"
        case .voice: return "voice speech microphone dictation 语音 说话 麦克风 right option 右 ⌥"
        case .agent: return "@agent coding agent claude code gemini cli kiro custom command terminal installed not installed background notify tasks @tasks claude tasks 编程 交给 自定义 命令 终端 已安装 未安装 后台 通知 任务"
        case .provider: return "ai provider model bedrock aws profile region claude gemini openai deepseek ollama api key test connection tokens temperature timeout apple intelligence on-device local 服务 模型 密钥 测试连接 模型参数 超时 温度 本机 苹果 sso role assume credential_process sts mfa 角色 登录 privacy hide sensitive information redact placeholder email phone card key token ip address words 隐私 隐藏 敏感信息 脱敏 占位符 邮箱 电话 卡号 密钥 地址"
        case .advanced: return "config file rime folder 高级 配置文件 目录"
        case .about: return "about version website github license report issue bug feedback 关于 版本 网站 报告 问题 反馈"
        case .apps: return "apps per-app app profiles each app bundle id starting input language rewrite styles tone type out no ai off slack mail wechat 每个 应用 按 App 设置 开始 输入语言 改写 风格 语气 逐字上屏 不用 AI 关掉"
        }
    }

    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = (title + " " + keywords).lowercased()
        return words.allSatisfy { text.contains($0) }
    }
}


/// The settings window drawn offscreen, for the README and the wiki: `page`, as tall as its content.
enum SettingsImage {
    @MainActor
    static func render(_ model: SettingsModel, page: SettingsPage, inputTab: Language? = nil, keySheet: Provider? = nil,
                       assistant: AssistantModel? = nil, to url: URL, appearance: NSAppearance.Name = .aqua,
                       settle: (TimeInterval) -> Void) {
        let host = NSHostingView(rootView: SettingsView(model: model, page: page, inputTab: inputTab, keySheetShown: keySheet,
                                                        assistant: assistant))
        // Taller than any page; the empty space below it is cut off after drawing (a form's scroll view
        // doesn't tell how tall its content is).
        let size = NSSize(width: 880, height: 2600)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.alphaValue = 0
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        settle(0.8)
        defer { window.close() }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let cropped = trimmed(rep, sidebar: 300) else { return }
        try? cropped.representation(using: .png, properties: [:])?.write(to: url)
        print("  \(url.path) (\(Int(cropped.size.width))×\(Int(cropped.size.height)))")
    }

    /// `rep` without the rows below the page's last content (right of the sidebar), 24 pt kept, at least 560 pt tall.
    private static func trimmed(_ rep: NSBitmapImageRep, sidebar: CGFloat) -> NSBitmapImageRep? {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        let (w, h) = (rep.pixelsWide, rep.pixelsHigh)
        let x0 = Int(sidebar * scale)
        guard let background = rep.colorAt(x: w - 4, y: h - 4) else { return nil }
        func differs(_ c: NSColor?) -> Bool {
            guard let c = c?.usingColorSpace(.deviceRGB), let b = background.usingColorSpace(.deviceRGB) else { return false }
            return abs(c.redComponent - b.redComponent) + abs(c.greenComponent - b.greenComponent) + abs(c.blueComponent - b.blueComponent) > 0.03
        }
        var last = 0
        for y in stride(from: h - 1, through: 0, by: -1) {
            if stride(from: x0, to: w - 30, by: 3).contains(where: { differs(rep.colorAt(x: $0, y: y)) }) { last = y; break }
        }
        let height = min(h, max(Int(560 * scale), last + Int(24 * scale)))
        guard let cg = rep.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: w, height: height)) else { return nil }
        let out = NSBitmapImageRep(cgImage: cg)
        out.size = NSSize(width: rep.size.width, height: CGFloat(height) / scale)
        return out
    }
}

/// The keyboard layouts installed on this Mac that type Latin letters (U.S., ABC, French, French – PC, Swiss
/// French …), by name, for picking the one an input language types with.
enum KeyboardLayouts {
    struct Layout: Hashable { let id: String; let name: String }

    static let latin: [Layout] = {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
                      kTISPropertyInputSourceIsASCIICapable as String: true] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        let layouts = sources.compactMap { source -> Layout? in
            guard let id = InputSourceRegistrar.string(source, kTISPropertyInputSourceID),
                  let name = InputSourceRegistrar.string(source, kTISPropertyLocalizedName) else { return nil }
            return Layout(id: id, name: name)
        }
        return Array(Set(layouts)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()
}

/// A bundle's preference (`ExtensionBundle.Preference`): a text field, a password (saved in the keychain, never
/// shown again), a checkbox or a menu. Text is saved on Return and when the field loses focus.
private struct PreferenceField: View {
    let preference: ExtensionBundle.Preference
    let value: String
    /// A password: one is in the keychain.
    let saved: Bool
    let save: (String) -> Void
    /// A saved password's last 4 characters, where kept.
    var ending: String? = nil
    /// A password's Remove…, once confirmed.
    let remove: () -> Void
    @State private var text = ""
    /// The text field was edited since it last showed `value`.
    @State private var edited = false
    @State private var editingPassword = false
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            switch preference.kind {
            case .checkbox:
                Toggle("", isOn: Binding(get: { value == "true" }, set: { save($0 ? "true" : "false") })).labelsHidden()
            case .dropdown:
                Picker("", selection: Binding(get: { value }, set: { save($0) })) {
                    ForEach(preference.choices, id: \.value) { Text($0.title).tag($0.value) }
                }
                .labelsHidden().frame(maxWidth: 220)
            case .password:
                // As an API key's row: whether it is saved, in the row; the field only after Replace… (or when not set).
                KeyRowContent(state: saved ? .saved(ending: ending) : .missing, missing: tr("还没有设置", "Not set yet"),
                              prompt: tr("粘贴", "Paste it"),
                              removeTitle: tr("从钥匙串里删除「\(preference.title)」？", "Remove “\(preference.title)” from the keychain?"),
                              save: save, remove: remove, editing: $editingPassword)
                    .frame(maxWidth: 360)
            case .textfield:
                // Saved only when edited here; not being edited, it follows the value (read again after a write elsewhere).
                TextField("", text: Binding(get: { text }, set: { if $0 != text { text = $0; edited = true } }),
                          prompt: preference.defaultValue.map { Text($0) })
                    .labelsHidden().focused($focused)
                    .onSubmit(commitText)
                    .onChange(of: focused) { if !focused { commitText() } }
                    .onAppear { text = value }
                    .onChange(of: value) { if !edited { text = value } }
                    .frame(maxWidth: 220)
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(preference.title + (preference.required ? " *" : ""))
                if let description = preference.description {
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The text field's edit, if there was one and it changed the value: saved.
    private func commitText() {
        guard edited else { return }
        edited = false
        if text != value { save(text) }
    }
}
