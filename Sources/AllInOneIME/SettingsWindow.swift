import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import AuthenticationServices
import Carbon
import SwiftUI
import UniformTypeIdentifiers

/// State of the settings window, around the core's `SettingsStore` (the config file, the rules each change follows, the
/// keys: what Windows' Settings app has too), with what only the Mac has: its open panels, the menu bar icon, iCloud,
/// Apple Notes, the voice models, the AllInOneIME Cloud sign-in. Every change is written to the config file right away;
/// the input method re-reads it for each translation, so nothing needs a restart.
@MainActor
final class SettingsModel: ObservableObject {
    /// The settings, and the rules each change follows.
    let store: SettingsStore
    private var observation: SettingsStore.Observation?

    var config: Config {
        get { store.config }
        set { store.config = newValue }
    }
    var loadError: String? { store.loadError }
    var saveError: String? { store.saveError }

    /// Interface text that names commands ("@agent", "@ commands") with the command trigger these settings have
    /// (`UIText.triggered`): drawn again as it changes.
    func triggered(_ text: String) -> String { UIText.triggered(text, trigger: config.commandTrigger) }
    @Published private(set) var profiles: [String] = []
    @Published private(set) var testStatus: TestStatus = .idle
    /// Where the API key of each provider comes from (refreshed when one is saved), and the last 4 characters kept
    /// with a saved one (`APIKeys.keyEnding`: the key isn't read).
    @Published private(set) var keySources: [Provider: APIKeys.Source] = [:]
    @Published private(set) var keyEndings: [Provider: String] = [:]
    @Published private(set) var keyError: String?
    /// What this Mac learned (`LearnedShared`: Privacy → Learned…), its apps by name, as when the Privacy page or the list
    /// was last shown or something was forgotten.
    @Published private(set) var learned: [LearnedItem] = []

    func refreshLearned() {
        learned = LearnedShared.store.items(appName: { AppNames.name(for: $0) })
    }

    /// Forget: `item` forgotten where it is kept (an app's starting input with its streak, autocomplete's learning in an
    /// app, a model's temperature …).
    func forget(_ item: LearnedItem) {
        LearnedShared.store.forget(item)
        refreshLearned()
    }

    /// Forget All: everything learned on this Mac.
    func forgetAllLearned() {
        LearnedShared.store.forgetAll()
        refreshLearned()
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
        store.setRememberQuestions(on)
    }

    /// The questions kept, deleted (the store's `questionsForgotten`, when the switch goes off).
    private func forgetQuestions() {
        // Marked first, so that a sync running meanwhile never takes the deletion for a Clear.
        if persists { ICloudSyncController.shared.questionsForgotten() }
        QuestionHistoryStore.clear()
        recentQuestions = 0
    }

    /// Questions asked since the window opened.
    func refreshRecentQuestions() {
        recentQuestions = QuestionHistoryStore.history.entries.count
    }

    typealias TestStatus = SettingsStore.TestStatus

    var configURL: URL { store.configURL }
    /// The control the window was opened to point at (`SettingsWindow.show(page:spot:)`), outlined on its page until it's
    /// used or another page is shown.
    @Published var spot: SettingsSpot?
    /// False for previews/screenshots: nothing is ever written.
    private var persists: Bool { store.persists }
    private var testTask: Task<Void, Never>?
    /// Screenshots only: the name shown for the selected AWS profile. README images are public and a
    /// profile is often named after its owner; the keys, region and Test Connection (测试连接) still use the real one.
    var profileShownAs: String?
    /// The AWS profiles' kinds and the chosen one's status line (`AWSProfileSettings`).
    let aws = AWSProfileModel()

    init(configURL: URL = Config.defaultURL, persists: Bool = true) {
        store = SettingsStore(configURL: configURL, persists: persists)
        profiles = AWSSharedConfig.profileNames()
        if !profiles.contains(config.awsProfile) { profiles.insert(config.awsProfile, at: 0) }
        observation = store.observe { [weak self] _ in self?.objectWillChange.send() }
        store.questionsForgotten = { [weak self] in self?.forgetQuestions() }
    }

    var canSave: Bool { store.canSave }

    /// Writes the settings changed in the window since the file was read or last written here, and only those
    /// (`SettingsStore.save`). Nothing is written when nothing changed. The window then shows the file as it now is.
    func save() { store.save() }

    /// Reads the config file again if something else changed it, so the window shows it and its next save
    /// doesn't put back what was there before.
    func reloadIfChanged() { store.reloadIfChanged() }

    // MARK: Lists edited while sync may change them

    // The window may not have read the file again yet when one of these saves (its reload waits while a slider is dragged
    // or a menu is open), and sync through iCloud may have changed the list in it: each reads it again first, and edits
    // the list by name, never by an index the page showed (`SettingsStore`).

    /// The hidden-words field saved (Return, or leaving the page). The list to show.
    @discardableResult
    func saveWords(field text: String, shown: [String]) -> [String] { store.saveWords(field: text, shown: shown) }

    /// Settings → Input → English Words' Add (`SettingsStore.addEnglishWords`): those added, and those refused as what
    /// hiding sensitive information hides.
    @discardableResult
    func addEnglishWords(_ text: String) -> EnglishWords.Added { store.addEnglishWords(text) }

    /// A word's ✕ (`SettingsStore.removeEnglishWord`).
    func removeEnglishWord(_ word: String) { store.removeEnglishWord(word) }

    /// The custom commands an edit of the one named `original` (nil: one being added) is checked against.
    func otherCommands(than original: String?) -> [CustomCommand] { store.otherCommands(than: original) }

    /// The command editor's Save (`SettingsStore.saveCommand`): false when another command has its name by now, and the
    /// editor stays open saying so.
    @discardableResult
    func saveCommand(_ command: CustomCommand, editing original: String?, shown: CustomCommand? = nil) -> Bool {
        guard store.saveCommand(command, editing: original, shown: shown) else { return false }
        commandSourceChanged(saved: command, was: shown)
        return true
    }

    /// The Delete dialog's Delete (`SettingsStore.deleteCommand`).
    func deleteCommand(named name: String, shown: CustomCommand? = nil) {
        store.deleteCommand(named: name, shown: shown)
        commandSourceChanged(saved: nil, was: shown)
    }

    /// The Delete dialog's Delete of a command config.json has that can't be read (`SettingsStore.deleteRefusedCommand`).
    func deleteRefusedCommand(_ refused: CustomCommand.Refused) { store.deleteRefusedCommand(refused) }

    /// Allow of a suggestions command from another Mac, as the page showed it (`SettingsStore.allowCommand`): its program
    /// runs on this Mac from now on, its list at once.
    func allowCommand(_ command: CustomCommand) {
        store.allowCommand(command)
        commandSourceChanged(saved: command, was: command)
    }

    /// Switches the window's language at once (a config value, `Config.uiLanguage`; nil: follow the system) and saves
    /// the choice.
    func setUILanguage(_ language: String?) {
        store.setUILanguage(language)
        SettingsWindow.shared.updateTitle()
    }

    /// Shows or removes the menu bar icon (the self-test passes its own).
    var applyMenuBarIcon: @MainActor (Bool) -> Void = { MenuBarIcon.shared.apply($0) }

    /// The menu bar icon's switch: saved, and the icon shown or removed at once (not by a preview).
    func setMenuBarIcon(_ on: Bool) {
        store.setMenuBarIcon(on)
        if persists { applyMenuBarIcon(on) }
    }

    /// Autocomplete's switch for every app (the input menu's, `AutocompleteSwitch`): saved, and counted as the menu's is.
    func setAutocomplete(_ on: Bool) {
        config.autocomplete = on
        save()
        if persists { AutocompleteSwitch.store.switched(on: on) }
    }

    // MARK: Fuzzy pinyin

    /// Fuzzy pinyin couldn't be applied: the Rime folder has the user's own `rime_ice.custom.yaml`.
    @Published private(set) var fuzzyBlocked = false
    /// Writes the patch and deploys Rime again (the self-test's preview model doesn't).
    var applyFuzzyPinyin: @MainActor ([String]) -> FuzzyPinyin.Outcome? = { RimeFuzzy.apply($0) }
    /// What turning it on picks: the pairs most often mixed up.
    static let fuzzyDefaults = SettingsStore.fuzzyDefaults

    func setFuzzyPinyin(_ ids: [String]) {
        store.setFuzzyPinyin(ids)
        guard persists else { return }
        fuzzyBlocked = applyFuzzyPinyin(config.fuzzyPinyin) == .userFile
    }

    func setFuzzy(_ id: String, on: Bool) {
        setFuzzyPinyin(on ? config.fuzzyPinyin + [id] : config.fuzzyPinyin.filter { $0 != id })
    }

    // MARK: Styles

    func isStyleOn(_ style: RewriteStyle) -> Bool { store.isStyleOn(style) }

    func setStyle(_ style: RewriteStyle, on: Bool) { store.setStyle(style, on: on) }

    /// The styles in this order (dragged in the window): the candidates follow it.
    func setStyleOrder(_ names: [String]) { store.setStyleOrder(names) }

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
            let (sources, endings) = SettingsStore.keyStates(providers, lookup: lookup)
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
        keyError = store.saveKey(key, for: provider)
        refreshKeys()
    }

    /// Removes the provider's API key from the keychain: Remove Key…, confirmed.
    func removeKey(_ provider: Provider) {
        guard persists else { return }
        keyError = store.removeKey(provider)
        refreshKeys()
    }

    /// "✓ Saved · ends in a1b2", "✓ From $OPENAI_API_KEY", "No API key yet".
    func keyStatus(_ provider: Provider) -> String {
        keyState(provider).text(missing: tr("还没有 API key", "No API key yet"))
    }

    /// The settings of an API-key provider as stored (unset fields use the defaults).
    func providerSettings(_ provider: Provider) -> ProviderSettings { store.providerSettings(provider) }

    func setProviderSettings(_ settings: ProviderSettings, for provider: Provider) {
        store.setProviderSettings(settings, for: provider)
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
        searchKeyError = store.saveSearchKey(key)
        searchTestStatus = .idle
        refreshSearchKey()
    }

    /// Removes the web search key: Remove Key…, confirmed.
    func removeSearchKey() {
        guard persists else { return }
        searchKeyError = store.removeSearchKey()
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
            let status = await SettingsStore.testSearch(query)
            self?.searchTestStatus = status
        }
    }

    // MARK: Notes (@note)

    /// Where the Notion token comes from (nil until looked up), the last save's error, and Test.
    @Published private(set) var notionTokenSource: APIKeys.Source?
    @Published private(set) var notionTokenEnding: String?
    @Published private(set) var notionTokenError: String?
    @Published private(set) var notesTestStatus: TestStatus = .idle
    /// The page or database link pasted in the section, which Test resolves (`NotionLink`, `NotionAPI.resolve`).
    @Published var notionLink = ""
    private var notesTestTask: Task<Void, Never>?
    /// Asks for the folder notes go to, starting at the one there is (an open panel; the self-test answers instead).
    var pickNotesFolder: @MainActor (URL?) -> URL? = { SettingsModel.askForNotesFolder($0) }

    func refreshNotionToken() {
        // A preview (the self-test's images) shows no token and never asks the user's keychain.
        guard persists, Self.looksUpKeys else {
            notionTokenSource = APIKeys.Source.none
            return
        }
        // From the item's attributes: the token isn't read, so nothing asks for the login password.
        notionTokenSource = APIKeys.source(account: NotionAPI.keyAccount, variables: [])
        notionTokenEnding = APIKeys.keyEnding(account: NotionAPI.keyAccount)
    }

    var notionTokenState: KeyState { KeyState(notionTokenSource, ending: notionTokenEnding) }

    /// Stores the Notion token in the keychain, sent to api.notion.com only, never in the config; an empty one does
    /// nothing (`removeNotionToken`).
    func saveNotionToken(_ token: String) {
        guard persists, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notionTokenError = store.saveNotionToken(token)
        notesTestStatus = .idle
        refreshNotionToken()
    }

    /// Removes the Notion token: Remove…, confirmed.
    func removeNotionToken() {
        guard persists else { return }
        notionTokenError = store.removeNotionToken()
        notesTestStatus = .idle
        refreshNotionToken()
    }

    /// The "Save to" picker. A folder without one chosen yet asks for it first (cancelled: as it was).
    func setNotesDestination(_ destination: NoteSettings.Destination) {
        let changed = store.setNotesDestination(destination) { pickNotesFolder(nil).map(Self.notesPath) }
        if changed { notesTestStatus = .idle }
    }

    /// Choose Folder…: kept as "~/…" when it is in the home folder, and saved to from now on.
    func chooseNotesFolder() {
        guard let url = pickNotesFolder(config.notes.folderURL) else { return }
        store.setNotesFolder(Self.notesPath(url))
    }

    static func notesPath(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    /// The folder chosen isn't there (an unmounted volume, a moved vault): a save would fail. Looked at off the main
    /// thread (`refreshNotesFolder`: a network volume that went away can hang a `stat`), never while rendering.
    @Published private(set) var notesFolderMissing = false
    private var notesFolderLook = 0

    /// Looks at the folder notes go to, in the background, and says whether it is missing (`notesFolderMissing`).
    func refreshNotesFolder() {
        notesFolderLook += 1
        let look = notesFolderLook
        guard config.notes.destination == .folder, let folder = config.notes.folderURL else {
            notesFolderMissing = false
            return
        }
        Task { [weak self] in
            let missing = await Task.detached(priority: .utility) { () -> Bool in
                var isDirectory: ObjCBool = false
                return !(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
            }.value
            guard let self, look == self.notesFolderLook else { return }
            self.notesFolderMissing = missing
        }
    }

    static func askForNotesFolder(_ current: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = current
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Test: the link pasted (else the page or database kept) resolved with the token kept, within 10 s; what it is goes
    /// into the config, and @note saves there from now on: "✓ “Inbox” (database)".
    func testNotes() {
        notesTestTask?.cancel()
        notesTestStatus = .running
        let link = notionLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let (kept, session) = (config.notes.notion, NoteSaving.notionSession)
        notesTestTask = Task { [weak self] in
            do {
                let target = try await SettingsStore.resolveNotion(link: link, kept: kept, session: session)
                guard let self, !Task.isCancelled else { return }
                self.store.useNotion(target)
                self.notionLink = ""
                self.notesTestStatus = .passed(target.label(language: UIText.language))
            } catch {
                guard !Task.isCancelled else { return }
                self?.notesTestStatus = .failed(UIText.describe(error))
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
        pluginError = store.uninstall(plugin)
        refreshPlugins()
        _ = LivePlugins.current(rescan: true)  // the command list drops it right away
        SuggestionsShared.settingsChanged()  // what was enabled of it forgotten, its cached lists deleted
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
    /// The bundles' snippets ("<bundle>/<name>"): the name each got, and the ones on but left out (and why).
    @Published private(set) var snippetNames: [String: String] = [:]
    @Published private(set) var hiddenSnippets: [String: ScriptCommand.Problem] = [:]
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
        let enabledSnippets = index.enabledSnippets(config.disabledExtensions)
        let hidden = Command.hiddenScripts(enabled, custom: config.customCommands, plugins: plugins, snippets: enabledSnippets)
        let catalog = Command.catalog(config.customCommands, plugins: plugins, scripts: enabled, snippets: enabledSnippets)
        extensionNames = Dictionary(catalog.compactMap { command in command.script.map { ($0.id, command.name) } },
                                    uniquingKeysWith: { first, _ in first })
        snippetNames = Dictionary(catalog.compactMap { command -> (String, String)? in
            guard command.kind == .snippet, let bundle = command.bundle, let custom = command.custom else { return nil }
            return (bundle + "/" + custom.name, command.name)
        }, uniquingKeysWith: { first, _ in first })
        hiddenSnippets = Dictionary(Command.hiddenSnippets(enabledSnippets, scripts: enabled, custom: config.customCommands, plugins: plugins)
            .map { ($0.snippet.id, .nameTaken($0.snippet.name, by: $0.owner)) }, uniquingKeysWith: { first, _ in first })
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
        store.addExtensionFolder(ExtensionStore.abbreviated(url.path))
        refreshExtensions()
    }

    /// An added folder is removed from the list; a found one is hidden (or shown again).
    func removeExtensionFolder(_ folder: ExtensionStore.Folder) {
        store.removeExtensionFolder(folder)
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
    func isEnabled(_ id: String) -> Bool { store.isEnabled(id) }

    func setEnabled(_ id: String, _ on: Bool) {
        store.setEnabled(id, on)
        refreshExtensions()
    }

    /// A preference's value as saved (not a password's), else its default.
    func preference(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference) -> String {
        store.preference(bundle, preference)
    }

    /// Saves a preference: a password in the keychain (an empty one does nothing: `removePassword` removes it),
    /// anything else in the config file.
    func setPreference(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference, _ value: String) {
        guard persists else { return }
        if preference.kind == .password {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            extensionError = store.setPreference(bundle, preference, value)
        } else {
            _ = store.setPreference(bundle, preference, value)
        }
        refreshExtensions()
    }

    /// Removes a password preference from the keychain: Remove…, confirmed.
    func removePassword(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference) {
        guard persists, preference.kind == .password else { return }
        extensionError = store.removePassword(bundle, preference)
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
            switch await SettingsStore.libraryEntries(library) {
            case let .success(entries):
                self?.libraryEntries = entries
                self?.updateLibraryStatus()
            case let .failure(error):
                self?.libraryError = error.message
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
            if let error = await SettingsStore.install(entry, from: library) { self?.libraryError = error }
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
        guard Features.voiceInput else { return }  // off for now: its page isn't shown
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
                store.showSaveError(tr("无法创建黑话库：", "Couldn't create the jargon list: ") + error.localizedDescription)
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
            let status = await SettingsStore.testConnection(snapshot) { try await resolver.resolve(profile: $0, forceRefresh: true) }
            self?.testStatus = status
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var personalDictionaries = PersonalDictionariesModel()
    @State private var customModel = false
    @State private var customProviderModel = false
    @State private var pluginToRemove: InstalledPlugin?
    /// The library plugin about to be installed or updated (the confirmation shows what it contacts).
    @State private var pluginToInstall: PluginIndex.Entry?
    /// The custom command being added or edited (the editor sheet), and the one about to be deleted.
    @State private var commandEdit: CommandEdit?
    /// The name of the command the Delete dialog asks about (by name: sync may change the list while it is open).
    @State private var commandToDelete: CustomCommand?
    @State private var refusedToDelete: CustomCommand.Refused?
    /// The provider whose key row shows its paste field (Replace…, or the Assistant opening Settings at the key).
    @State private var editingKey: Provider?
    /// The key sheet: a provider other than the one in use whose key the Assistant asked for.
    @State private var keySheet: KeySheetRequest?
    /// The web search key row's paste field.
    @State private var editingSearchKey = false
    @State private var editingNotionToken = false
    /// The page shown (General when none is asked for) and what's typed in the sidebar's search field.
    @State private var page: SettingsPage
    @State private var query = ""
    /// The search's row chosen (↑↓ move it; the last one is "Change: …").
    @State private var chosen = 0
    @FocusState private var searchFocused: Bool
    /// The input whose chip's popover is open.
    @State private var openChip: Input?
    /// The README images: the options of this input drawn under the chips (a popover isn't in a page's image).
    private let chipShown: Input?
    /// The AI page's More… opened.
    @State private var showsMore = false
    /// About's Troubleshoot… sheet.
    @State private var troubleshooting = false
    /// Script Extensions' folders with no new commands, opened.
    @State private var showsOtherFolders = false
    /// The language packs and their downloads (Chinese is a download: the app ships English only).
    @ObservedObject private var packs = LanguagePackManager.shared
    /// Code's coding packs and their downloads (Code's menu, the + menu's Code).
    @ObservedObject private var codingPacks = CodingPackManager.shared
    /// The extension sources' new commits: a badge on the Custom Commands page.
    @ObservedObject private var extensionSources = ExtensionSourceController.shared
    /// The pack of an input language just removed: the dialog offers to remove it too.
    @State private var packToRemove: LanguagePack?
    /// A pack the user asked to remove from its language's chip (asked first, with its size).
    @State private var packToDelete: LanguagePack?
    /// The search's "Change: …" (a request to change settings in a sentence, its preview, Apply and Undo) and the checks
    /// behind the pages' banners and Troubleshoot: the process's own (`AssistantModel.shared`), so they stay while other
    /// pages are shown and the window is closed. Observed: the sidebar's dots follow the checks.
    @ObservedObject private var assistant: AssistantModel

    /// The README images: the key sheet drawn over the page, for this provider (a real sheet isn't in a page's image).
    private let keySheetShown: Provider?
    /// The README images: Troubleshoot drawn over the page (About's sheet).
    private let troubleshootShown: Bool
    /// The README images: the Learned list drawn over the page (Privacy's sheet).
    private let learnedShown: Bool

    /// `page`: the one shown first; nil: General (the last one isn't remembered). `query`: the search typed (images).
    @MainActor
    init(model: SettingsModel, page: SettingsPage? = nil, inputTab: Input? = nil, keySheetShown: Provider? = nil,
         assistant: AssistantModel? = nil, query: String = "", troubleshootShown: Bool = false, learnedShown: Bool = false) {
        self.model = model
        self.keySheetShown = keySheetShown
        self.troubleshootShown = troubleshootShown
        self.learnedShown = learnedShown
        _assistant = ObservedObject(wrappedValue: assistant ?? .shared)
        chipShown = inputTab
        _page = State(initialValue: page ?? Self.firstPage)
        _query = State(initialValue: query)
    }

    /// The page Settings opens on when none is asked for.
    static let firstPage = SettingsPage.general

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

    /// The magic key and the action key.
    @ViewBuilder private var keysSection: some View {
        Section {
            // One of the symbols that type as themselves in every mode (`Config.commandTriggers`): picked, never typed,
            // so there is nothing to refuse.
            LabeledContent {
                // Shown like the action key: the symbol as text, and a click opens the symbols to pick from, the one in
                // use checked (a toggle each: the menu's own checkmark). Drawn by SwiftUI as a plain button: AppKit's
                // borderless pop-up gives its title the controls' color, not the text's, and an inset on the right.
                Menu {
                    ForEach(Config.commandTriggers, id: \.self) { symbol in
                        Toggle(symbol == "@" ? tr("@（默认）", "@ (default)") : symbol,
                               isOn: Binding(get: { model.config.commandTrigger == symbol },
                                             set: { if $0 { model.config.commandTrigger = symbol } }))
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(model.config.commandTrigger).foregroundStyle(.primary)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(tr("魔法键：", "Magic key: ") + model.config.commandTrigger)
            } label: {
                titled(.magicKey)
            }
            .settingsRow(.magicKey, shown: model.spot)
            // Return by default; a click on it takes the next key pressed (or a tap of ⌥).
            LabeledContent {
                KeyRecorder(key: $model.config.actionKey)
            } label: {
                titled(SettingsSpot.actionKey.title, Self.actionKeyNote(model.config.actionKey, trigger: model.config.commandTrigger))
            }
            .settingsRow(.actionKey, shown: model.spot)
        }
        .disabled(!model.canSave)
    }

    /// Advanced → typing results out, as a person types: its speed, its ups and downs, its typos (the apps where they
    /// couldn't be fixed are in Privacy → Learned…).
    @ViewBuilder private var typeOutSection: some View {
        Section {
            // Results typed in character by character, like a person typing.
            Toggle(isOn: $model.config.typeOut) {
                titled(.typeOut)
            }
            .settingsRow(.typeOut, shown: model.spot)
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
                    titled(tr("偶尔打错再改", "Make occasional typos and fix them"), Self.typoNote)
                }
            }
        }
        .disabled(!model.canSave)
    }

    /// The typos' row: one sentence, as the core's settings document says it too.
    static var typoNote: String {
        tr("偶尔按到旁边的键或多打一个字母，马上改回来，终端里不打错；打完的文字一字不差。",
           "Now and then a neighboring key or a doubled letter, fixed at once and never in a terminal: the text ends up exactly the result.")
    }

    /// Advanced → how the candidates of a word are laid out, and commands on the selected text.
    @ViewBuilder private var typingSection: some View {
        Section {
            // The candidates of a word being typed (pinyin, Hindi) in a column, or in a row like macOS's own panel.
            LabeledContent {
                Picker("", selection: $model.config.candidateLayout) {
                    Text(tr("竖排", "Vertical")).tag(CandidateArrangement.vertical)
                    Text(tr("横排", "Horizontal")).tag(CandidateArrangement.horizontal)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            } label: {
                titled(SettingsSpot.candidateLayout.title, Self.layoutNote(model.config.candidateLayout))
            }
            .settingsRow(.candidateLayout, shown: model.spot)
            // Commands on the selected text (`Composer.selection`): on by default, off for an app where it misbehaves.
            Toggle(isOn: $model.config.useSelection) {
                titled(.useSelection)
            }
            .settingsRow(.useSelection, shown: model.spot)
        }
        .disabled(!model.canSave)
    }

    /// What the candidate layout's row says for `layout`, as the core's settings document says it too.
    static func layoutNote(_ layout: CandidateArrangement) -> String {
        layout == .horizontal
            ? tr("选词（拼音、印地语）的候选并排，像系统自带的输入法：← → 选词，↑↓ 或 - = 翻页。",
                 "Word candidates (pinyin, Hindi) side by side, like the system's own input methods: ← → choose, ↑↓ or - = turn the page.")
            : tr("选词（拼音、印地语）的候选一个一个往下排：↑↓ 选词，- = 翻页。",
                 "Word candidates (pinyin, Hindi) one under the other: ↑↓ choose, - = turn the page.")
    }

    /// Commands → `@question`: where its conversation goes on (`ChatHandoff`; QuestionChatSettings.swift): the chips, the
    /// card's width for them (every agent installed, the web, Copy), scrolled sideways when there are more.
    @ViewBuilder private var questionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    titled(SettingsSpot.questionContinueIn.title,
                           model.triggered(tr("@question 聊满 \(QuestionChat.rounds(model.config.questionRounds)) 轮（或随时按 ⌘⏎）后，⌘1、⌘2… 把对话带到这些地方接着聊，第一个是默认。",
                              "After \(QuestionChat.rounds(model.config.questionRounds)) rounds of @question (or ⌘⏎ any time), ⌘1, ⌘2 … take the conversation there, the first by default.")))
                    Spacer()
                    let missing = model.missingContinueChoices
                    if !missing.isEmpty {
                        Menu(tr("添加…", "Add…")) {
                            ForEach(missing, id: \.self) { destination in
                                Button(SessionText.name(destination, picked: model.config.agent,
                                                        custom: model.config.agentCommand, language: UIText.language)) {
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
                                  name: {
                                      SessionText.shortName($0, picked: model.config.agent, custom: model.config.agentCommand,
                                                            language: UIText.language)
                                  },
                                  firstNote: tr("默认", "default"),
                                  reorder: { model.setContinueIn($0) }, remove: { model.removeContinueIn($0) })
                        .fixedSize()
                }
            }
            .settingsRow(.questionContinueIn, shown: model.spot)
        } header: {
            SectionTitle(model.triggered(tr("提问（@question）", "Questions (@question)")), icon: CommandIcons.icon(for: .question))
        }
        .disabled(!model.canSave)
    }

    /// The menu bar icon and the interface language.
    @ViewBuilder private var appearanceSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.menuBarIcon }, set: { model.setMenuBarIcon($0) })) {
                titled(.menuBarIcon)
            }
            .settingsRow(.menuBarIcon, shown: model.spot)
            .disabled(!model.canSave)
            // Following the system by default; the languages the app ships are written in their own language, so
            // they can be found whatever the window is in. Saved as "zh" / "en" for those two (older versions read them).
            Picker(SettingsSpot.interfaceLanguage.title,
                   selection: Binding(get: { InterfaceLanguage.code(forSetting: model.config.uiLanguage, shipped: UIText.shipped) },
                                      set: { model.setUILanguage($0.map(InterfaceLanguage.setting(for:))) })) {
                Text(tr("跟随系统", "Follow the system")).tag(String?.none)
                Divider()
                ForEach(UIText.shipped, id: \.self) { code in
                    Text(InterfaceLanguage.name(code)).tag(String?.some(code))
                }
            }
            .pickerStyle(.menu)
            .settingsRow(.interfaceLanguage, shown: model.spot)
        }
    }

    /// The input languages as chips, in their order (the first is the default: new text fields start in it; with two,
    /// Shift switches), Code after them with its coding language; ⊗ removes one, dragging reorders the languages, and
    /// "Add…" adds one. The packs on their way under them; each input's options follow in sections of their own.
    @ViewBuilder private var inputSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    titled(SettingsSpot.inputLanguages.title,
                           model.config.inputs.count > 1
                           ? tr("单按 Shift 切换；新的输入框从第一个开始。", "Tap Shift to switch; new text fields start in the first.")
                           : tr("只有一种时 Shift 不切换", "With one, Shift doesn't switch"))
                    Spacer()
                }
                HStack(spacing: 6) {
                    LanguageChips(items: model.config.inputLanguages,
                                  name: { SessionText.inputName($0, language: UIText.language) },
                                  firstNote: tr("默认", "default"),
                                  keepsOne: !(model.config.inputLanguages.count == 1 && model.config.inputLanguages.first != .english),
                                  reorder: { model.config.setOrder($0) }, remove: removeInputLanguage,
                                  move: { language, step in model.store.moveInputLanguage(language, by: step) })
                    if let coding = model.config.codingLanguage { codeChip(coding) }
                    addInputMenu
                }
            }
            .settingsRow(.inputLanguages, shown: model.spot)
            ForEach(LanguagePack.catalog) { pack in packRow(pack) }
            CodeInputRow(model: model)
            if Features.voiceInput { voiceRows }  // off for now: the setting kept as it is

        } header: {
            SectionTitle(tr("输入语言", "Input Languages"), icon: CommandIcons.input)
        }
        .disabled(!model.canSave)
        // Pointed at something in a chip (the search found fuzzy pinyin): that chip opened.
        .onChange(of: model.spot) { openChipOfSpot() }
        .onAppear { openChipOfSpot() }
    }

    /// Voice input (`Features.voiceInput`, off for now): its switch, the speech models, the microphone.
    @ViewBuilder private var voiceRows: some View {
        Toggle(isOn: $model.config.voiceInput) {
            titled(tr("按住右 ⌥ 说话，松开结束", "Hold right ⌥ to talk, release to stop"),
                   tr("在这台 Mac 上识别，不上传", "Recognized on this Mac, never uploaded"))
        }
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
    }

    private func openChipOfSpot() {
        guard let chip = model.spot?.chip, model.config.inputs.contains(chip) else { return }
        DispatchQueue.main.async { openChip = chip }
    }

    /// Code's chip, after the languages and apart from them (decision 22): "Code · Python"; a click opens its options,
    /// ⊗ removes Code.
    private func codeChip(_ coding: String) -> some View {
        let open = openChip == .code
        let name = tr("代码", "Code") + " · " + CodingLanguagePack.title(of: coding, installed: codingPacks.installed)
        return HStack(spacing: 2) {
            Text(name).foregroundStyle(open ? .primary : .secondary)
            Button { model.config.codingLanguage = nil } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .help(tr("移除\(name)", "Remove \(name)")).accessibilityLabel(tr("移除\(name)", "Remove \(name)"))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(open ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(open ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1))
    }

    /// "Add…": the languages not added (one whose pack isn't here says it downloads first), then Code with each
    /// coding language until it's added.
    private var addInputMenu: some View {
        let languages = model.config.inputLanguages
        let missing = Language.allCases.filter { !languages.contains($0) }
        let full = languages.count >= Config.maxInputLanguages
        let codeAdded = model.config.codingLanguage != nil
        return Menu(tr("添加…", "Add…")) {
            ForEach(missing, id: \.self) { language in
                let download = !packs.isUsable(language)
                Button(SessionText.inputName(language, language: UIText.language)
                       + (download ? tr("（下载语言包）", " (downloads a language pack)") : "")) {
                    addInputLanguage(language)
                }
                .disabled(full || LanguagePack.for(language).map(isDownloading) ?? false)
            }
            if !missing.isEmpty { Divider() }
            Text(tr("更多输入语言即将支持", "More input languages are coming"))
            if !codeAdded {
                Divider()
                Section(tr("代码", "Code")) {
                    ForEach(CodingLanguagePack.offered, id: \.language) { offered in
                        let download = !codingPacks.installed.contains { $0.language == offered.language }
                        Button(offered.title + (download ? tr("（下载语言包）", " (downloads a language pack)") : "")) {
                            CodeInputSettings.pick(offered.language, model: model)
                        }
                        .disabled(codingPacks.isDownloading(offered.language))
                    }
                }
            }
        }
        .fixedSize()
        .disabled(full && codeAdded)
        .help(full ? tr("最多 \(Config.maxInputLanguages) 种输入语言", "Up to \(Config.maxInputLanguages) input languages")
                   : tr("添加输入语言", "Add an input language"))
    }

    /// What @translate writes in, and what @improve offers: the languages, in order (a line in each); the rewrite styles,
    /// in order; whether @improve also translates; and the jargon list, with the Jargon style (or one already chosen).
    @ViewBuilder private var writingSection: some View {
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
                if model.config.hasLanguageToTranslateInto {
                    titled(SettingsSpot.outputLanguages.title, tr("每种一行，拖动排序", "A line in each; drag to reorder"))
                } else {
                    // Only the languages typed (a new user whose Mac has English alone): @translate has nothing to do yet.
                    let typed = model.config.inputLanguages.map { UIText.name(OutputLanguage($0)) }.joined(separator: tr("、", ", "))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SettingsSpot.outputLanguages.title)
                        Text(tr("再加一种\(typed)以外的语言：句子不会翻译成它本来的语言",
                                "Add one besides \(typed): a sentence isn't translated into its own language"))
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // Opened from @translate's notice (nothing to translate into): this is where.
            .settingsRow(.outputLanguages, shown: model.spot)
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
                titled(SettingsSpot.rewriteStyles.title, model.config.rewriteStyles.isEmpty
                       ? tr("没有风格时只出 1–3 行", "With none, lines 1–3 only")
                       : tr("用你写的语言改写，拖动排序", "In the language you wrote; drag to reorder"))
            }
            .settingsRow(.rewriteStyles, shown: model.spot)
            Toggle(isOn: $model.config.improveTranslates) {
                titled(model.triggered(tr("@improve 同时翻译", "@improve also translates")), inputSummary)
            }
            .settingsRow(.improveTranslates, shown: model.spot)
            if Self.showsJargon(model.config) || model.jargonExists {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(model.jargonExists ? tr("\(model.jargonCount) 个词", "\(model.jargonCount) terms") : tr("未设置", "Not set"))
                            .foregroundStyle(.secondary)
                        Button(tr("选择文件…", "Choose File…")) { model.chooseJargonFile() }
                        Button(model.jargonExists ? tr("打开", "Open") : tr("新建", "New")) { model.openJargonFile() }
                    }
                } label: {
                    titled(SettingsSpot.jargonList.title, model.jargonExists ? model.jargonPath
                           : tr("「黑话」风格用的词表：文本文件，每行一个词，可以加解释。",
                                "The Jargon style's terms: a text file, one term per line, optionally with its meaning."))
                }
                .settingsRow(.jargonList, shown: model.spot)
            }
        } header: {
            SectionTitle(tr("翻译和改写", "Translate and Rewrite"), icon: CommandIcons.translate)
        }
        .disabled(!model.canSave)
    }

    /// The jargon list's row shows with the Jargon style on, or a list chosen already.
    static func showsJargon(_ config: Config) -> Bool {
        config.jargonFile != nil || RewriteStyle.resolve(config.rewriteStyles).contains { $0.tag == "JARGON" }
    }

    /// Autocomplete's switch (the input menu's), where its text goes under it; then Suggestions.
    @ViewBuilder private var autocompleteSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.autocomplete }, set: { model.setAutocomplete($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSpot.autocomplete.title)
                    Text(SettingsSpot.autocomplete.note ?? "").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Where the text goes, whether it's on or not: turning it on is the choice to send it there.
                    if let destination = AutocompleteSwitch.destination(model.config) {
                        Text(destination).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .settingsRow(.autocomplete, shown: model.spot)
        }
        .disabled(!model.canSave)
    }

    @ViewBuilder private var commandsSection: some View {
        Section {
            // By place: two of one name (a config edited by hand) are two rows. Edit and Delete still go by the name.
            ForEach(Array(model.config.customCommands.enumerated()), id: \.offset) { index, command in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        IconTile(icon: CommandIcons.icon(for: command))
                        Text(model.config.commandTrigger + command.name).font(.body.monospaced())
                        Text(UIText.customKind(command)).foregroundStyle(.secondary)
                        if let summary = command.summary {
                            Text(summary).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(tr("编辑", "Edit")) { commandEdit = CommandEdit(index: index, command: command) }
                        Button(tr("移除", "Remove")) { commandToDelete = command }
                    }
                    if Self.hiddenByBuiltIn(command) {
                        Label(tr("和内置命令重名，不会生效，请改名", "Same name as a built-in command: rename it to use it"),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    // From another Mac, not allowed here yet (decision 26): the program it would run, Allow or Remove.
                    if model.config.awaitsConfirmation(command) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(UIText.fromAnotherMac(command), systemImage: "desktopcomputer").foregroundStyle(.orange)
                                Text(UIText.runsNothingUntilAllowed()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(tr("允许", "Allow")) { model.allowCommand(command) }
                            Button(tr("移除", "Remove")) { commandToDelete = command }
                        }
                        .font(.caption).fixedSize(horizontal: false, vertical: true).padding(.leading, 36)
                    } else if command.type == .suggestions {
                        // A suggestion source: how it is doing (its items, last update, last error), or why it isn't used.
                        CommandSourceStatus(command: command, config: model.config).padding(.leading, 36)
                    }
                }
            }
            // Those config.json has that can't be read (a value of the wrong kind): never run, kept, said why; Delete only.
            ForEach(Array(model.config.refusedCustomCommands.enumerated()), id: \.offset) { _, refused in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).frame(width: 20)
                        Text(model.config.commandTrigger + (refused.name ?? "?")).font(.body.monospaced())
                        Spacer()
                        Button(tr("移除", "Remove")) { refusedToDelete = refused }
                    }
                    Text(UIText.describe(refused)).font(.caption).foregroundStyle(.orange).padding(.leading, 36)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(tr("添加命令…", "Add Command…")) {
                commandEdit = CommandEdit(index: nil, command: CustomCommand(name: "", type: .prompt))
            }
        } header: {
            SectionTitle(SettingsSpot.customCommands.title, icon: CommandIcons.commands)
                .settingsRow(.customCommands, shown: model.spot)
        } footer: {
            Text(tr("保存后，在任意输入框开头打 @ 加名字就能用，和 @improve 一样。",
                    "Once saved, type @ and its name at the start of any text field, like @improve.")
                    .replacingOccurrences(of: "@", with: model.config.commandTrigger))
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
            // The folders that bring commands, each on its row; the others (empty, hidden, only copies of what loads from
            // elsewhere) folded into one.
            let (bringing, others) = foldedFolders
            ForEach(bringing, id: \.path) { folder in folderRow(folder) }
            if !others.isEmpty {
                DisclosureGroup(isExpanded: $showsOtherFolders) {
                    ForEach(others, id: \.path) { folder in folderRow(folder) }
                } label: {
                    Label(others.count == 1 ? tr("另外 1 个文件夹没有新命令", "1 more folder with no new commands")
                              : tr("另外 \(others.count) 个文件夹没有新命令", "\(others.count) more folders with no new commands"),
                          systemImage: "folder").foregroundStyle(.secondary)
                }
                .disclosureGroupStyle(RowDisclosureStyle())
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
            SectionTitle(SettingsSpot.scriptExtensions.title, icon: CommandIcons.scripts)
                .settingsRow(.scriptExtensions, shown: model.spot)
        } footer: {
            Text(tr("每个脚本是一个 @ 命令，名字取自文件名（convert-timestamp.sh → @converttimestamp）。参数写在命令后面，多个用逗号隔开：@flights beijing, new york。脚本可以上屏结果、显示进度、给出列表来选，或在后台运行，完成后通知你。写法见 docs/extensions.md。",
                    "Each script is an @ command named after its file (convert-timestamp.sh → @converttimestamp). Write its arguments after it, with commas between: @flights beijing, new york. A script can insert its result, show progress, offer a list to pick from, or run in the background and notify you. See docs/extensions.md for how to write one.")
                    .replacingOccurrences(of: "@", with: model.config.commandTrigger))
                .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
    }

    /// The extension folders that bring commands (one of theirs loads), and the others.
    private var foldedFolders: (bringing: [ExtensionStore.Folder], others: [ExtensionStore.Folder]) {
        let files = model.extensionIndex.commands.map { $0.file.resolvingSymlinksInPath().path }
            + model.extensionIndex.bundles.map { $0.folder.resolvingSymlinksInPath().path + "/" }
        func brings(_ folder: ExtensionStore.Folder) -> Bool {
            let root = folder.url.resolvingSymlinksInPath().path + "/"
            return !folder.hidden && files.contains { $0.hasPrefix(root) }
        }
        return (model.extensionFolders.filter(brings), model.extensionFolders.filter { !brings($0) })
    }

    /// An extension folder: where it is, whether it was added or found (and hidden), Show in Finder, and Remove (added)
    /// or Hide / Show (found).
    private func folderRow(_ folder: ExtensionStore.Folder) -> some View {
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
                Text(model.config.commandTrigger + name).font(.body.monospaced()).foregroundStyle(on ? .primary : .secondary)
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
                        Text(model.config.commandTrigger + plugin.name).font(.body.monospaced())
                        Text(plugin.manifest.summary?.text(chinese: UIText.chinese) ?? "").foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if let update = model.libraryUpdate(for: plugin) {
                            Button(tr("更新到 \(update.version)", "Update to \(update.version)")) { pluginToInstall = update }
                        }
                        Button(tr("移除", "Remove")) { pluginToRemove = plugin }
                    }
                    Text(pluginDetail(plugin)).font(.caption).foregroundStyle(.secondary)
                    // Its completion sources (suggestions) and preferences, under it.
                    PluginCompletionsView(model: model, plugin: plugin).padding(.top, 4)
                }
            }
            ForEach(model.skippedPlugins, id: \.folder) { skipped in
                Label(tr("没有加载 \(skipped.folder)：", "Not loaded, \(skipped.folder): ") + skipped.reason,
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if model.plugins.isEmpty, model.skippedPlugins.isEmpty {
                Text(tr("还没有插件。插件是别人写好的 @ 命令，比如 @stock 查股价；装好后和其他命令一样用。",
                        "No plugins yet. Plugins are ready-made @ commands, like @stock for stock quotes; once installed they work like any command.")
                        .replacingOccurrences(of: "@", with: model.config.commandTrigger))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(tr("打开插件文件夹", "Open Plugins Folder")) { model.openPluginsFolder() }
                Button(tr("刷新", "Refresh")) { model.refreshPlugins() }
            }
            if let error = model.pluginError { Text(error).foregroundStyle(.red) }
            pluginLibrary
        } header: {
            SectionTitle(SettingsSpot.plugins.title, icon: CommandIcons.plugins)
                .settingsRow(.plugins, shown: model.spot)
        }
        .disabled(!model.canSave)
    }

    @ViewBuilder private var providerSection: some View {
        Section {
            Picker(SettingsSpot.provider.title, selection: $model.config.provider) {
                ForEach(Provider.offered, id: \.self) { provider in
                    providerItem(provider)
                }
            }
            .settingsRow(.provider, shown: model.spot)
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
                Button(SettingsSpot.testConnection.title) { model.runTest() }
                    .disabled(model.testStatus == .running)
                switch model.testStatus {
                case .idle: EmptyView()
                case .running: ProgressView().controlSize(.small)
                case let .passed(text): Text("✓ \(text)").foregroundStyle(.green).textSelection(.enabled)
                case let .failed(text): Text("✗ \(text)").foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .settingsRow(.testConnection, shown: model.spot)
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
                                  removeTitle: { everywhere in
                                      everywhere ? tr("从你所有的 Mac 上删除搜索 API key？", "Remove the search API key from all your Macs?")
                                          : tr("从这台 Mac 上删除搜索 API key？", "Remove the search API key from this Mac?")
                                  },
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
                Text(model.triggered(tr("@search 用 Brave Search 搜网页，用你自己的 API key：Brave 每月送一些免费额度（目前约 1000 次搜索），注册时要绑信用卡。"
                            + "要搜的内容会发给 Brave。key 存在钥匙串里；也可以在 shell 里设置 BRAVE_API_KEY。",
                        "@search searches the web with Brave Search, using your own API key: Brave gives some free credit each month "
                            + "(about 1,000 searches for now); signing up needs a credit card. What you search for is sent to Brave. "
                            + "The key is kept in the keychain; you can also set BRAVE_API_KEY in your shell.")))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                SectionTitle(model.triggered(tr("网页搜索（@search）", "Web Search (@search)")), icon: CommandIcons.webSearch)
            }
        }
    }

    /// Where `@note` saves (`Config.notes`): Notes, Notion (its token in the keychain, never in the config; the link of a
    /// page or database, which Test resolves) or a folder of Markdown files (an Obsidian vault or any folder).
    @ViewBuilder private var notesSection: some View {
        Section {
            Picker(tr("存到", "Save to"), selection: Binding(get: { model.config.notes.destination }, set: { destination in
                // After the picker's own update: a folder may ask for one first, in an open panel.
                DispatchQueue.main.async { model.setNotesDestination(destination) }
            })) {
                Text(tr("备忘录", "Notes")).tag(NoteSettings.Destination.notes)
                Text("Notion").tag(NoteSettings.Destination.notion)
                Text(tr("文件夹（Obsidian 等）", "Folder (Obsidian or any)")).tag(NoteSettings.Destination.folder)
            }
            switch model.config.notes.destination {
            case .notes:
                EmptyView()
            case .folder:
                HStack {
                    Text(model.config.notes.folder ?? "").font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(tr("选择文件夹…", "Choose Folder…")) { model.chooseNotesFolder() }
                }
                if model.config.notes.folderURL == nil {
                    // Only a config edited by hand gets here (the picker asks for a folder first): saved to Notes meanwhile.
                    Text(tr("还没选文件夹：笔记先存到备忘录", "No folder chosen: notes go to Notes until you choose one"))
                        .foregroundStyle(.orange)
                } else if model.notesFolderMissing {
                    Text(NoteError.folderMissing(path: "").message(language: UIText.language)).foregroundStyle(.red)
                }
            case .notion:
                HStack {
                    Button(tr("创建集成…", "Create Integration…")) { NSWorkspace.shared.open(NotionAPI.integrationsPage) }
                    Text(tr("新建集成 → 内部 → 复制令牌", "New integration → Internal → copy the token"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent(tr("令牌", "Token")) {
                    KeyRowContent(state: model.notionTokenState, missing: tr("还没有设置", "Not set yet"),
                                  prompt: tr("粘贴 Notion 集成的令牌", "Paste a Notion integration token"),
                                  removeTitle: { everywhere in
                                      everywhere ? tr("从你所有的 Mac 上删除 Notion 令牌？", "Remove the Notion token from all your Macs?")
                                          : tr("从这台 Mac 上删除 Notion 令牌？", "Remove the Notion token from this Mac?")
                                  },
                                  save: { model.saveNotionToken($0) },
                                  remove: model.notionTokenSource == .keychain ? { model.removeNotionToken() } : nil,
                                  editing: $editingNotionToken)
                }
                if let error = model.notionTokenError { Text(error).foregroundStyle(.red) }
                Text(tr("在 Notion 里打开那个页面 → ··· → 连接 → 加上你的集成", "In Notion, open the page → ··· → Connections → add your integration"))
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent(tr("页面或数据库链接", "Page or database link")) {
                    TextField("", text: $model.notionLink, prompt: Text(verbatim: "https://www.notion.so/…"))
                        .onSubmit { model.testNotes() }
                }
                HStack {
                    Button(tr("测试", "Test")) { model.testNotes() }
                        .disabled(model.notesTestStatus == .running
                                  || (model.notionLink.trimmingCharacters(in: .whitespaces).isEmpty && model.config.notes.notion == nil))
                    switch model.notesTestStatus {
                    case .idle:
                        // What it saves under now, as Test found it.
                        if let target = model.config.notes.notion {
                            Text(target.label(language: UIText.language)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    case .running: ProgressView().controlSize(.small)
                    case let .passed(text): Text("✓ \(text)").foregroundStyle(.green).textSelection(.enabled)
                    case let .failed(text): Text("✗ \(text)").foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
        } header: {
            SectionTitle(model.triggered(tr("笔记（@note）", "Notes (@note)")), icon: CommandIcons.icon(for: .note))
        }
        .disabled(!model.canSave)
    }

    /// How each request is made: output tokens, temperature (Bedrock, Apple's model), timeout, a provider's Thinking. Not
    /// shown, still read from the config: one set to something else than its default (by hand, an earlier version, the
    /// search's Change) shows its row with Restore Default. The models remembered as refusing a temperature are in Privacy
    /// → Learned….
    @ViewBuilder private var requestSection: some View {
        let defaults = Config.default
        let usesTemperature = model.config.provider == .bedrock || model.config.provider == .apple
        let effort = model.config.provider.needsKey ? model.providerSettings(model.config.provider).effort : nil
        let defaultEffort = ProviderSettings.defaults(for: model.config.provider).effort
        let shows = model.config.maxTokens != defaults.maxTokens || model.config.timeoutSeconds != defaults.timeoutSeconds
            || (usesTemperature && model.config.temperature != defaults.temperature) || (effort != nil && effort != defaultEffort)
        if shows {
            Section {
                if model.config.maxTokens != defaults.maxTokens {
                    RestoreDefaultRow(title: tr("最多输出 \(model.config.maxTokens) tokens", "Up to \(model.config.maxTokens) output tokens"),
                                      note: RestoreDefaultRow.defaultIs("\(defaults.maxTokens)")) { model.config.maxTokens = defaults.maxTokens }
                }
                if usesTemperature, model.config.temperature != defaults.temperature {
                    RestoreDefaultRow(title: model.config.temperature.map { "temperature " + String(format: "%.1f", $0) }
                                          ?? tr("不发 temperature", "No temperature sent"),
                                      note: RestoreDefaultRow.defaultIs(defaults.temperature.map { String(format: "%.1f", $0) } ?? "-")) {
                        model.config.temperature = defaults.temperature
                    }
                }
                if model.config.timeoutSeconds != defaults.timeoutSeconds {
                    RestoreDefaultRow(title: tr("超时 \(Int(model.config.timeoutSeconds)) 秒", "Timeout \(Int(model.config.timeoutSeconds)) s"),
                                      note: RestoreDefaultRow.defaultIs(tr("\(Int(defaults.timeoutSeconds)) 秒", "\(Int(defaults.timeoutSeconds)) s"))) {
                        model.config.timeoutSeconds = defaults.timeoutSeconds
                    }
                }
                if let effort, effort != defaultEffort {
                    RestoreDefaultRow(title: tr("思考", "Thinking") + tr("：", ": ") + (effort.isEmpty ? tr("未设置", "Not set") : effort),
                                      note: RestoreDefaultRow.defaultIs(defaultEffort.map { $0.isEmpty ? tr("未设置", "Not set") : $0 } ?? tr("未设置", "Not set"))) {
                        model.store.setProviderField(model.config.provider, \.effort, to: "", empty: nil)
                    }
                }
            } header: {
                SectionTitle(tr("模型参数", "Model Settings"), icon: CommandIcons.provider)
            }
            .disabled(!model.canSave)
        }
    }

    @ViewBuilder private var filesSection: some View {
        Section {
            let path = (model.configURL.path as NSString).abbreviatingWithTildeInPath
            LabeledContent {
                Button(tr("打开", "Open")) { NSWorkspace.shared.open(model.configURL) }
            } label: {
                titled(SettingsSpot.configFile.title, path)
            }
            .settingsRow(.configFile, shown: model.spot)
            LabeledContent {
                Button(tr("打开", "Open")) { NSWorkspace.shared.open(RimeDirectories.user) }
            } label: {
                titled(.rimeFolder)
            }
            .settingsRow(.rimeFolder, shown: model.spot)
            if let saveError = model.saveError {
                Text(saveError).foregroundStyle(.red)
            }
        } header: {
            SectionTitle(tr("文件", "Files"), icon: CommandIcons.advanced)
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

    /// A row's title and what it says, as the search finds them (`SettingsSpot`).
    @ViewBuilder private func titled(_ spot: SettingsSpot) -> some View {
        if let note = spot.note { titled(spot.title, note) } else { Text(spot.title) }
    }

    // MARK: Pages

    /// Like System Settings: a search field, then the pages, each with its icon (and a dot while the checks find
    /// something wrong there). Typed into, the field lists the rows it finds instead, at once and on this Mac only; the
    /// chosen one is shown on its page, outlined; the last row, "Change: …", asks the AI to change the settings as typed
    /// (only it sends anything).
    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("搜索设置…", "Search settings…"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    // As in every list of the input method: the first row chosen, ↑↓ move, Return picks, Esc clears.
                    .onSubmit { pick(chosen) }
                    .onKeyPress(.upArrow) { moveChoice(-1) }
                    .onKeyPress(.downArrow) { moveChoice(1) }
                    .onKeyPress(.escape) {
                        guard !query.isEmpty else { return .ignored }
                        query = ""
                        return .handled
                    }
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
            if typed.isEmpty { pageList } else { resultList }
        }
        .padding(.top, 8)
        .onChange(of: query) {
            chosen = 0
            follow()
            // The on-device model and the apps, before a request.
            if !typed.isEmpty { AIConfigSession.prewarmIfDue() }
        }
    }

    /// What's typed in the search field, trimmed.
    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The rows the search finds, in order; the row after them is "Change: …".
    private var results: [SettingsSpot] {
        typed.isEmpty ? [] : SettingsSpot.search(typed, trigger: model.config.commandTrigger, config: model.config)
    }

    /// The pages: a thin line before Advanced, as in System Settings.
    private var pageList: some View {
        List(selection: Binding(get: { page }, set: { if let new = $0 { page = new } })) {
            ForEach(SettingsPage.allCases) { item in
                if item == .advanced {
                    Divider().padding(.horizontal, 6).padding(.vertical, 2)
                        .selectionDisabled()
                }
                // Something the checks found wrong on the page: a dot, red for a problem (its banner says what), which
                // VoiceOver reads after the page's name.
                let worst = assistant.issues.map(\.element).filter { SettingsPage.of($0.area) == item }.map(\.status).min()
                Label {
                    HStack {
                        Text(item.title).font(.system(size: 13.5)).padding(.leading, 4)
                        Spacer(minLength: 4)
                        if let worst {
                            Circle().fill(TroubleshootSheet.color(worst)).frame(width: 8, height: 8).accessibilityHidden(true)
                        }
                    }
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
                .accessibilityLabel(item.title + (worst.map { tr("：", ": ") + ($0 == .problem ? tr("有问题", "Has a problem") : tr("有提醒", "Has a warning")) } ?? ""))
                .badge(item == .commands ? extensionSources.updateCount(for: model.config.extensionSources) : 0)
                .tag(item)
            }
        }
        .listStyle(.sidebar)
    }

    /// The rows found, each with its page, the chosen one highlighted; "Change: …" last.
    private var resultList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, spot in
                    resultRow(index) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(spot.title).lineLimit(1)
                            Text(spot.page.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if results.isEmpty {
                    Text(tr("没有匹配的设置", "No matching settings")).font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                resultRow(results.count) {
                    Label(tr("修改：\(typed)", "Change: \(typed)"), systemImage: "wand.and.stars").lineLimit(2)
                }
                .help(tr("让 AI 按你写的改设置，先预览再应用", "Asks the AI to change the settings as you wrote, with a preview before anything is applied"))
            }
            .padding(.horizontal, 10)
        }
    }

    private func resultRow(_ index: Int, @ViewBuilder _ label: () -> some View) -> some View {
        Button {
            chosen = index
            pick(index)
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(index == chosen ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(index == chosen ? .isSelected : [])
    }

    /// ↑↓ in the search field: the chosen row moves (stays in the list), and is shown.
    private func moveChoice(_ step: Int) -> KeyPress.Result {
        guard !typed.isEmpty else { return .ignored }
        chosen = min(max(chosen + step, 0), results.count)
        follow()
        return .handled
    }

    /// The chosen row shown on its page, outlined; "Change: …" shows nothing until it is picked.
    private func follow() {
        guard results.indices.contains(chosen) else { return }
        show(results[chosen])
    }

    /// Return on a row, or a click: a setting is shown; "Change: …" asks the AI, as typed (the preview comes at the top of
    /// the page, with Apply and Undo).
    private func pick(_ index: Int) {
        if results.indices.contains(index) {
            show(results[index])
        } else if index == results.count, !typed.isEmpty {
            assistant.request = typed
            assistant.sendRequest()
        }
    }

    private func show(_ spot: SettingsSpot) {
        page = spot.page
        model.spot = spot
    }

    /// What an input's chip opens: a language's pack, its own settings (Chinese's fuzzy pinyin and personal dictionaries,
    /// French's keyboard layout), the English words pinyin offers (English's, or Chinese's without English), and its
    /// place among the languages; Code's coding language and packs.
    @ViewBuilder private func inputOptions(_ input: Input) -> some View {
        switch input {
        case .code:
            CodeOptions(model: model)
        case let .language(language):
            languageOptions(language).disabled(personalDictionaries.isWorking)
            if language == .chinese {
                PersonalDictionariesSection(model: model, dictionaries: personalDictionaries)
            }
            if language == .english || (language == .chinese && !model.config.inputLanguages.contains(.english)) {
                EnglishWordsSection(model: model)
            }
        }
    }

    @ViewBuilder private func languageOptions(_ language: Language) -> some View {
        Section {
            // The language's pack: still on its way (its progress is shown under the chips), or what's installed.
            if let pack = LanguagePack.for(language) {
                if !packs.isInstalled(pack) {
                    Label(tr("语言包下载完以后才能打\(pack.name.text(chinese: true))。", "\(pack.name.en) can be typed once its language pack has downloaded."),
                          systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
                packInfo(pack)
            }
            switch language {
            case .chinese:
                Toggle(isOn: Binding(get: { !model.config.fuzzyPinyin.isEmpty },
                                     set: { model.setFuzzyPinyin($0 ? SettingsModel.fuzzyDefaults : []) })) {
                    titled(.fuzzyPinyin)
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
                EmptyView()
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
            // Its place in the order (the chips follow it); the first is the default. Dragging a chip does the same.
            let languages = model.config.inputLanguages
            if languages.count > 1, let index = languages.firstIndex(of: language) {
                LabeledContent {
                    HStack(spacing: 4) {
                        Button(tr("左移", "Move Left")) { model.store.moveInputLanguage(language, by: -1) }
                            .disabled(index == 0)
                        Button(tr("右移", "Move Right")) { model.store.moveInputLanguage(language, by: 1) }
                            .disabled(index == languages.count - 1)
                    }
                } label: {
                    titled(tr("位置", "Position"),
                           tr("第 \(index + 1) 个，共 \(languages.count) 个；第一个是默认", "\(index + 1) of \(languages.count); the first is the default"))
                }
            }
        } header: {
            SectionTitle(SessionText.inputName(language, language: UIText.language), icon: CommandIcons.input)
        } footer: {
            if language == .chinese {
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
            .settingsRow(.updates, shown: model.spot)
        Section {
            // Today's checks (`AssistantModel`'s), in a sheet: what's wrong on a row each, what's fine folded under one line.
            LabeledContent {
                Button(tr("排查问题…", "Troubleshoot…")) { troubleshooting = true }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSpot.troubleshoot.title)
                    Text(SettingsSpot.troubleshoot.note ?? "").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TroubleshootSummary(assistant: assistant)
                }
            }
            .settingsRow(.troubleshoot, shown: model.spot)
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
            .settingsRow(.reportIssue, shown: model.spot)
        }
    }

    /// The input languages' pack dialogs, on the page rather than on the Input section (a Form section's own
    /// dialog is not shown), and apart from `body`'s chain of modifiers (too long to type-check otherwise).
    private func packDialogs(_ content: some View) -> some View {
        content
        .confirmationDialog(packToRemove.map { tr("也移除\($0.name.text(chinese: true))语言包？", "Also remove the \($0.name.en) language pack?") } ?? "",
                            isPresented: Binding(get: { packToRemove != nil }, set: { if !$0 { packToRemove = nil } })) {
            Button(tr("移除语言包", "Remove Pack"), role: .destructive) {
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
        .confirmationDialog(packToDelete.map { tr("移除\($0.name.text(chinese: true))语言包？", "Remove the \($0.name.en) language pack?") } ?? "",
                            isPresented: Binding(get: { packToDelete != nil }, set: { if !$0 { packToDelete = nil } })) {
            Button(tr("移除语言包", "Remove Pack"), role: .destructive) {
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
            } else if troubleshootShown {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    TroubleshootSheet(assistant: assistant) {}
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                        .padding(.top, 50)
                }
            } else if learnedShown {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    LearnedSheet(model: model) {}
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
            ScrollViewReader { proxy in
                packDialogs(Form {
                    loadErrorSection
                    // What the checks found wrong on this page, and the search's "Change: …" with its preview.
                    ProblemBanners(assistant: assistant, page: page)
                    ChangeCard(assistant: assistant)
                    switch page {
                    case .general:
                        // The keys first, then the menu bar and the interface language (the owner, 0.6.7).
                        keysSection
                        appearanceSection
                        writingSection
                        autocompleteSection
                        SuggestionsSection(model: model)
                        ICloudSyncSection(model: model)
                        PreviousAppSettingsSection(model: model)
                    case .input:
                        // The input languages, then each one's options under its name (owner, 0.6.7: a page of its own,
                        // as before, not a popover on General).
                        inputSection
                        ForEach(model.config.inputs, id: \.self) { input in inputOptions(input) }
                    case .ai:
                        providerSection
                        requestSection
                    case .privacy:
                        PrivacySection(model: model)
                    case .commands:
                        commandsSection
                        AgentSettingsPage(model: model)
                        questionSection
                        notesSection
                        webSearchSection
                        pluginsSection
                        extensionsSection
                        ExtensionSourcesSection(model: model)
                    case .advanced:
                        typeOutSection
                        typingSection
                        filesSection
                    case .about: aboutSection
                    }
                }
                .formStyle(.grouped)
                // A white page under light gray cards, as in Raycast and System Settings (dark in dark mode).
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                // The row pointed at (the search's, `SettingsWindow.show(page:spot:)`), scrolled to.
                .onAppear { scroll(proxy) }
                .onChange(of: model.spot) { scroll(proxy) }
                // A page starts at its top, and is drawn anew in the other interface language: controls of their
                // own (the action key's recorder, the language chips) don't redraw by themselves when it changes.
                .id("\(page.rawValue)-\(UIText.language)"))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 480, idealHeight: 720)
        // Text fields save on Return; everything else (pickers, steppers, toggles) saves on change.
        .sheet(item: $commandEdit) { edit in
            CommandEditor(edit: edit, others: model.otherCommands(than: edit.original),
                          plugins: model.plugins.map(\.name), unread: model.config.unreadCustomCommandNames, config: model.config,
                          refreshNow: { model.refreshNow(command: $0) }) { command in
                model.saveCommand(command, editing: edit.original, shown: edit.original == nil ? nil : edit.command)
            }
        }
        .confirmationDialog(tr("移除这个命令？", "Remove this command?"),
                            isPresented: Binding(get: { commandToDelete != nil }, set: { if !$0 { commandToDelete = nil } })) {
            Button(tr("移除", "Remove"), role: .destructive) {
                if let command = commandToDelete { model.deleteCommand(named: command.name, shown: command) }
                commandToDelete = nil
            }
        } message: {
            if let command = commandToDelete { Text(model.config.commandTrigger + command.name) }
        }
        .confirmationDialog(tr("移除这个命令？", "Remove this command?"),
                            isPresented: Binding(get: { refusedToDelete != nil }, set: { if !$0 { refusedToDelete = nil } })) {
            Button(tr("移除", "Remove"), role: .destructive) {
                if let refused = refusedToDelete { model.deleteRefusedCommand(refused) }
                refusedToDelete = nil
            }
        } message: {
            if let refused = refusedToDelete { Text(model.config.commandTrigger + (refused.name ?? "?")) }
        }
        .confirmationDialog(tr("移除这个插件？", "Remove this plugin?"),
                            isPresented: Binding(get: { pluginToRemove != nil }, set: { if !$0 { pluginToRemove = nil } })) {
            Button(tr("移除", "Remove"), role: .destructive) {
                if let plugin = pluginToRemove { model.uninstall(plugin) }
                pluginToRemove = nil
            }
        } message: {
            if let plugin = pluginToRemove { Text(model.config.commandTrigger + plugin.name) }
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
        .onChange(of: model.config.codingLanguage) { model.save() }
        .onChange(of: model.config.improveTranslates) { model.save() }
        .onChange(of: model.config.voiceInput) { model.save() }
        .onChange(of: model.config.useSelection) { model.save() }
        .onChange(of: model.config.actionKey) { model.save() }
        .onChange(of: model.config.commandTrigger) {
            UIText.commandTrigger = model.config.commandTrigger  // the core's text the window shows
            model.save()
        }
        .onChange(of: model.config.claudeInBackground) { model.save() }
        .onChange(of: model.config.agent) { model.save() }
        .onChange(of: model.config.agentCommand) { model.save() }
        .onChange(of: model.config.agentPageContext) { model.save() }
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
        .onChange(of: page) {
            if page == .commands { model.refreshExtensions(discover: true) }
            if let spot = model.spot, spot.page != page { model.spot = nil }  // pointed at on a page no longer shown
        }
        .onChange(of: model.config.customCommands) { model.refreshExtensions() }  // a name an extension had may be taken now
        .onChange(of: model.config.notes) { model.refreshNotesFolder() }
        .onAppear {
            UIText.commandTrigger = model.config.commandTrigger
            // The checks behind the banners: quick, local (never a permission asked, a key read or the AI called).
            assistant.expireUndo()
            assistant.dropStalePreview()
            assistant.probe()
            model.refreshPlugins()
            model.refreshExtensions(discover: page == .commands)
            model.refreshKeys()
            model.refreshSearchKey()
            model.refreshNotionToken()
            model.refreshNotesFolder()
            model.refreshAccount()
            model.refreshVoice()
            model.refreshJargon()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshJargon()  // the list may have been edited in the text editor
            model.reloadIfChanged()  // so may the settings, or the input method's menu changed one
            model.refreshNotesFolder()  // a volume mounted or unmounted meanwhile
            model.refreshRecentQuestions()
            // Back from Terminal after `aws sso login`, say: the AWS profile's line read again.
            if model.config.provider == .bedrock { model.aws.refresh(profile: model.config.awsProfile) }
        }
        // Settings back in front (the input method's process active again), not any window of it becoming key.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            assistant.dropStalePreview()
            assistant.probe()
        }
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMEShowSettingsPage)) { note in
            if let raw = note.userInfo?["page"] as? String, let shown = SettingsPage(rawValue: raw) { page = shown }
        }
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMEConfigChanged).receive(on: RunLoop.main)) { _ in
            model.reloadIfChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMEFocusAPIKey)) { note in
            page = .ai
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
        .sheet(isPresented: $troubleshooting) {
            TroubleshootSheet(assistant: assistant) { troubleshooting = false }
        }
        .onDisappear { model.save() }
    }

    /// The row pointed at, in the middle of the page (once it is laid out).
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let spot = model.spot, spot.page == page else { return }
        DispatchQueue.main.async { withAnimation { proxy.scrollTo(spot.row, anchor: .center) } }
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
        let languages = model.config.inputLanguages.map { SessionText.inputName($0, language: UIText.language) }
            .joined(separator: tr("、", ", "))
        return tr("平时就是普通输入法：\(languages)。开头打 @ 用命令：@improve 润色、改写，@translate 翻译，@question 提问，"
                      + "@agent 交给 Claude Code 等 agent，@open 找文件，@note 存到备忘录，@reminder 加提醒事项。写完\(key)执行。",
                  "A regular input method: \(languages). "
                      + "Type @ first for commands: @improve polishes and rewrites, @translate "
                      + "translates, @question asks, @agent hands it to a coding agent (Claude Code …), @open finds files, @note saves to Notes, "
                      + "@reminder adds a reminder. When done, \(key).")
            .replacingOccurrences(of: "@", with: model.config.commandTrigger)
    }

    /// What @improve does for each input language: "@improve: Chinese → polish / rewrite; Korean → …".
    private var inputSummary: String {
        let each = model.config.inputLanguages.map { "\(UIText.name($0)) → \(UIText.action(input: $0, config: model.config))" }
        return tr("@improve：打", "@improve: ").replacingOccurrences(of: "@", with: model.config.commandTrigger)
            + each.joined(separator: tr("；打", "; ", key: "improve.separator")) + tr("。", ".")
    }

    /// Adds an input language; one whose pack isn't installed is added once the pack has downloaded
    /// (until then it isn't an input mode; its progress shows under the chips).
    private func addInputLanguage(_ language: Language) {
        guard let pack = LanguagePack.for(language), !packs.isInstalled(pack) else {
            model.store.addInputLanguage(language)
            return
        }
        let model = model
        packs.download(pack) {
            guard !model.config.inputLanguages.contains(language) else { return }
            model.store.addInputLanguage(language)
            model.save()  // the window may be closed by now
        }
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

    /// What a language's chip says about its pack: the version, its size, where it came from, and Remove….
    @ViewBuilder private func packInfo(_ pack: LanguagePack) -> some View {
        if case let .installed(record) = packs.state(pack) {
            let size = ByteCountFormatter.string(fromByteCount: packs.store.size(pack), countStyle: .file)
            LabeledContent {
                Button(tr("移除…", "Remove…")) { packToDelete = pack }
            } label: {
                titled(tr("语言包", "Language pack"),
                       record.source == .library
                       ? tr("\(record.version) · \(size) · 从语言包库下载", "\(record.version) · \(size) · downloaded from the language library")
                       : tr("\(record.version) · \(size) · 更新时从旧版本留下，没有重新下载",
                            "\(record.version) · \(size) · kept from the earlier version when updating, not downloaded"))
            }
        }
    }

    /// Removes a pack from its chip: its language is removed from the input languages first.
    private func deletePack(_ pack: LanguagePack) {
        model.store.removePackLanguage(pack.language)
        packs.remove(pack)
    }

    /// Removes an input language; the next one becomes the default, or English when it was the only one.
    private func removeInputLanguage(_ language: Language) {
        model.store.removeInputLanguage(language)
        // Its pack stays unless the user deletes it too (asked, with its size).
        if !model.config.inputLanguages.contains(language), let pack = LanguagePack.for(language), packs.isInstalled(pack) {
            packToRemove = pack
        }
    }

    private func addOutputLanguage(_ language: OutputLanguage) {
        model.store.addOutputLanguage(language)
        if model.spot == .outputLanguages { model.spot = nil }
    }

    /// Removes an added output language (one always stays); the next one is then in use.
    private func removeOutputLanguage(_ language: OutputLanguage) {
        model.store.removeOutputLanguage(language)
    }

    /// The typing speed as shown (`TypeOut.label`).
    static func rateLabel(_ rate: Double) -> String { TypeOut.label(rate: rate) }

    /// Slider values rounded to what the label shows (`TypeOut.rounded`).
    static func roundedRate(_ rate: Double) -> Double { TypeOut.rounded(rate: rate) }

    /// How the chosen action key works (`UIText.actionKeyNote`).
    /// With the trigger the window's config has (passed, so the note is drawn again when it changes), whatever the
    /// process's is while it draws (set after a change, by `onChange`: ~ still when ~ was just changed to #).
    static func actionKeyNote(_ key: ActionKey, trigger: String) -> String {
        UIText.$scopedCommandTrigger.withValue(trigger) { UIText.actionKeyNote(key) }
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
                          removeTitle: { everywhere in
                              everywhere ? tr("从你所有的 Mac 上删除 \(UIText.name(provider)) 的 API key？",
                                              "Remove the key for \(UIText.name(provider)) from all your Macs?")
                                  : tr("从这台 Mac 上删除 \(UIText.name(provider)) 的 API key？",
                                       "Remove the key for \(UIText.name(provider)) from this Mac?")
                          },
                          removeMessage: tr("删除后，要再粘贴一次 key 才能用 \(UIText.name(provider))。",
                                            "To use \(UIText.name(provider)) again, you'll have to paste the key again."),
                          save: { model.saveKey($0, for: provider) },
                          remove: model.keySources[provider] == .keychain ? { model.removeKey(provider) } : nil,
                          editing: Binding(get: { editingKey == provider }, set: { editingKey = $0 ? provider : nil }))
        }
        if let error = model.keyError { Text(error).foregroundStyle(.red) }
        // More…: the base URL (and, for OpenAI's, the services that take its API); open whenever one is set.
        let baseURLSet = model.providerSettings(provider).baseURL != nil
        DisclosureGroup(isExpanded: Binding(get: { showsMore || baseURLSet }, set: { showsMore = $0 })) {
            TextField(SettingsSpot.baseURL.title, text: providerBinding(provider, \.baseURL),
                      prompt: Text(ProviderSettings.defaults(for: provider).baseURL ?? ""))
                .onSubmit { model.save() }
                .settingsRow(.baseURL, shown: model.spot)
            if provider == .openai {
                LabeledContent {
                    Menu(tr("常用服务…", "Common Services…")) {
                        ForEach(CompatibleService.all) { service in
                            Button(service.name) { useService(service) }
                        }
                    }
                    .fixedSize()
                } label: {
                    titled(tr("兼容 OpenAI 的服务", "OpenAI-compatible services"),
                           tr("选一个会填好它的 Base URL，再在「自定义…」里填它的模型。", "Picking one fills in its base URL; then enter its model under Custom…."))
                }
            }
        } label: {
            Text(tr("更多…", "More…", key: "settings.more"))
        }
        .disclosureGroupStyle(RowDisclosureStyle())
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
            set: { model.store.setProviderField(provider, key, to: $0, empty: empty) })
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
            .confirmationDialog(pluginToInstall.map { entry in
                                    let (name, version) = (UIText.verbatim(entry.name), UIText.verbatim(entry.version))
                                    return model.triggered(tr("安装 @\(name) \(version)？", "Install @\(name) \(version)?"))
                                } ?? "",
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
                            Text(model.config.commandTrigger + entry.name).font(.body.monospaced())
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
        // The plugin's own words, as they are (`UIText.verbatim`): an "@" in them is no command.
        let hosts = UIText.verbatim(entry.hosts.joined(separator: ", ")), name = UIText.verbatim(entry.name)
        switch entry.type {
        case "prompt": return tr("AI 指令，发给你选的 AI 服务", "An AI instruction, sent to your AI provider")
        case "link":
            let target = entry.url.flatMap { URL(string: $0)?.host }.map(UIText.verbatim) ?? hosts
            return model.triggered(tr("@\(name) 后面的内容会在浏览器里打开 \(target)", "Opens what you type after @\(name) at \(target) in the browser"))
        default:
            return hosts.isEmpty ? tr("不联网", "No network")
                : model.triggered(tr("@\(name) 后面输入的内容会发到 \(hosts)", "What you type after @\(name) goes to \(hosts)"))
        }
    }

    /// "1.0.0 · sends what you type after @stock to query1.finance.yahoo.com · local".
    private func pluginDetail(_ plugin: InstalledPlugin) -> String {
        var parts = [plugin.manifest.version]
        // The plugin's own words, as they are (`UIText.verbatim`): an "@" in them is no command.
        let name = UIText.verbatim(plugin.name)
        switch plugin.manifest.type {
        case .script:
            let hosts = UIText.verbatim(plugin.manifest.hosts.joined(separator: ", "))
            parts.append(hosts.isEmpty ? tr("不联网", "no network")
                         : model.triggered(tr("@\(name) 后面的内容会发到 \(hosts)", "sends the text after @\(name) to \(hosts)")))
        case .prompt:
            parts.append(tr("AI 指令，发给你选的 AI 服务", "an AI instruction, sent to your AI provider"))
        case .link:
            let host = UIText.verbatim(plugin.manifest.destinationHosts.joined(separator: ", "))
            parts.append(model.triggered(tr("@\(name) 后面的内容会在浏览器里打开 \(host)", "opens \(host) in the browser with the text after @\(name)")))
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
    /// The open window's settings.
    private var model: SettingsModel?
    private var closing: NSObjectProtocol?

    static var title: String { tr("AllInOneIME 设置", "AllInOneIME Settings") }

    /// After the window's language changed.
    func updateTitle() { window?.title = Self.title }

    /// Whether the window is open (an update opens it again once the input method restarts).
    var isVisible: Bool { window?.isVisible == true }

    /// Shows the window on `page` (already open: it turns to it), and outlines `spot` there if given (`SettingsModel.spot`).
    func show(page: SettingsPage, spot: SettingsSpot? = nil) {
        show(opening: page)
        model?.spot = spot
        NotificationCenter.default.post(name: .allInOneIMEShowSettingsPage, object: nil, userInfo: ["page": page.rawValue])
    }

    /// What the window outlines (`show(page:spot:)`), while it does.
    var spot: SettingsSpot? { model?.spot }

    /// Shows the window; opened now, it starts on General.
    func show() { show(opening: nil) }

    private func show(opening page: SettingsPage?) {
        AgentAvailability.forget()  // an agent may have been installed meanwhile
        if window?.isVisible != true {
            // (Re)build so the window reflects the config file as it is now.
            window?.close()
            let model = SettingsModel()
            self.model = model
            UIText.choice = model.config.uiLanguage
            AssistantModel.shared.showsFine = false  // Check for problems: what is fine folded again
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
        EditMenu.install()  // ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z in the window's fields
        // The input method is an agent app: activate it so the window can take keyboard focus. If macOS
        // doesn't grant activation (another app is active), still put the window in front; a click
        // into it then activates it.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// The keys every text field answers in an app with a menu bar: an agent app (the input method, `LSUIElement`) has no
/// main menu, so ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z did nothing in Settings' fields (an API key could only be pasted from the context
/// menu). A main menu that is never shown, with an Edit menu of the standard actions sent to the first responder, gives
/// them their keys in every window of ours. Installed once, the first time Settings opens.
enum EditMenu {
    @MainActor
    static func install() {
        guard NSApp.mainMenu?.item(withTitle: "Edit") == nil else { return }
        let edit = NSMenu(title: "Edit")
        // Titles nobody sees (the menu bar of an agent app isn't shown): not translated.
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", .command),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (title, action, key, modifiers) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)  // no target: the first responder (the field being edited) takes it
        }
        let main = NSApp.mainMenu ?? NSMenu(title: "Main")
        let holder = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        holder.submenu = edit
        main.addItem(holder)
        NSApp.mainMenu = main
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
    /// Chips that open: the one open (highlighted), and a click opens another.
    var selected: Item? = nil
    var select: ((Item) -> Void)? = nil
    /// What an open chip shows, in a popover under it, and which is open.
    var options: ((Item) -> AnyView)? = nil
    var open: Binding<Item?>? = nil
    /// Moving a chip one place left (-1) or right (1), from its context menu and for VoiceOver, as dragging does.
    var move: ((Item, Int) -> Void)? = nil
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
        .popover(isPresented: Binding(get: { open?.wrappedValue == item && options != nil },
                                      set: { if !$0, open?.wrappedValue == item { open?.wrappedValue = nil } }),
                 arrowEdge: .bottom) {
            options?(item)
        }
        .contextMenu {
            if let move, items.count > 1 {
                Button(tr("左移", "Move Left")) { move(item, -1) }.disabled(item == items.first)
                Button(tr("右移", "Move Right")) { move(item, 1) }.disabled(item == items.last)
            }
        }
        .accessibilityActions {
            if let move, items.count > 1 {
                if item != items.first { Button(tr("左移", "Move Left")) { move(item, -1) } }
                if item != items.last { Button(tr("右移", "Move Right")) { move(item, 1) } }
            }
        }
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

/// The action key as System Settings shows a shortcut: its name as plain text; a click records another (the next key
/// pressed with ⌃, ⌥ or ⌘, or Return, Space, ⌥Space, a function key, or a tap of ⌥ on its own), outlined while it
/// listens. Esc or another click cancels; a plain letter is refused (it couldn't be typed any more). Return again is in
/// its context menu.
private struct KeyRecorder: View {
    @Binding var key: ActionKey
    @State private var recording = false
    @State private var refused = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? (refused ? tr("要带 ⌃、⌥ 或 ⌘", "Add ⌃, ⌥ or ⌘") : tr("按下新的键", "Type the key")) : UIText.pickerName(key))
                .foregroundStyle(recording ? Color.accentColor : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(recording ? Color.accentColor.opacity(0.12) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The name flush with the row's end, as the other rows' controls are; the outline reaches past it.
        .padding(.horizontal, -6)
        .help(tr("点一下，再按新的键", "Click, then press the new key"))
        .accessibilityLabel(tr("执行键：", "Action key: ") + UIText.pickerName(key))
        .accessibilityHint(tr("点一下录制新的键", "Click to record another key"))
        .contextMenu {
            if key != .enter { Button(tr("恢复 ⏎", "Use ⏎")) { key = .enter } }
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

/// A setting the window no longer shows, set to something other than its default (by hand, by an earlier version, by the
/// Assistant): its row, with what it is and Restore Default, so that nothing set is out of sight.
struct RestoreDefaultRow: View {
    let title: String
    var note: String? = nil
    let restore: () -> Void

    /// "The default is 1000."
    static func defaultIs(_ value: String) -> String { tr("默认是 \(value)。", "The default is \(value).") }

    var body: some View {
        LabeledContent {
            Button(tr("恢复默认", "Restore Default"), action: restore)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note {
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
    case general, input, ai, privacy, commands, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return tr("通用", "General")
        case .input: return tr("输入", "Input")
        case .ai: return tr("AI", "AI")
        case .privacy: return tr("隐私", "Privacy")
        case .commands: return tr("命令", "Commands")
        case .advanced: return tr("高级", "Advanced")
        case .about: return tr("关于", "About")
        }
    }

    var icon: CandidateView.Icon {
        switch self {
        case .general: return CandidateView.Icon(symbol: "gearshape.fill", color: .systemGray)
        case .input: return CandidateView.Icon(symbol: "keyboard.fill", color: .systemBlue)
        case .ai: return CommandIcons.provider
        case .privacy: return CandidateView.Icon(symbol: "hand.raised.fill", color: .systemBlue)
        case .commands: return CommandIcons.commands
        case .advanced: return CommandIcons.advanced
        case .about: return CandidateView.Icon(symbol: "info", color: .systemBlue)
        }
    }

    /// Its rows (`SettingsSpot`), in order.
    var spots: [SettingsSpot] { SettingsSpot.allCases.filter { $0.page == self } }

    /// Whether the page has a row `query` finds (its title counts too), with commands named with the command trigger
    /// (`trigger`: "~agent") as its rows name them ("@agent").
    func matches(_ query: String, trigger: String = "@") -> Bool {
        let words = query.lowercased().replacingOccurrences(of: trigger, with: "@").split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { title.lowercased().contains($0) } || spots.contains { $0.matches(query, trigger: trigger) }
    }

    /// The page a Doctor finding of `area` shows on, as a banner at its top (and a dot on its sidebar row); what has no
    /// page of its own (secure input, the logs' errors) is About's, with Troubleshoot.
    static func of(_ area: Doctor.Area) -> SettingsPage {
        switch area {
        case .inputMethod, .iCloudSync: return .general
        case .languagePacks: return .input
        case .provider, .connection, .appleIntelligence: return .ai
        case .permissions: return .privacy
        case .extensions: return .commands
        case .config: return .advanced
        case .updates, .secureInput, .recentErrors: return .about
        }
    }
}


/// The settings window drawn offscreen, for the README and the wiki: `page`, as tall as its content.
enum SettingsImage {
    @MainActor
    static func render(_ model: SettingsModel, page: SettingsPage, inputTab: Input? = nil, keySheet: Provider? = nil,
                       assistant: AssistantModel? = nil, query: String = "", troubleshoot: Bool = false, learned: Bool = false,
                       to url: URL, appearance: NSAppearance.Name = .aqua, settle: (TimeInterval) -> Void) {
        let host = NSHostingView(rootView: SettingsView(model: model, page: page, inputTab: inputTab, keySheetShown: keySheet,
                                                        assistant: assistant, query: query, troubleshootShown: troubleshoot,
                                                        learnedShown: learned))
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
                              removeTitle: { everywhere in
                                  everywhere ? tr("从你所有的 Mac 上删除「\(preference.title)」？", "Remove “\(preference.title)” from all your Macs?")
                                      : tr("从这台 Mac 上删除「\(preference.title)」？", "Remove “\(preference.title)” from this Mac?")
                              },
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
