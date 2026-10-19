import Foundation

/// The settings as a settings window shows and changes them, whatever draws it (the Mac's SwiftUI window, Windows'
/// Settings app over the wire): the config file read, changed and written back key by key, the rules each change follows,
/// and the keys, through the platform's secret store (`APIKeys`). What only one platform has (the Mac's open panels, its
/// menu bar icon, iCloud, Apple Notes) stays in its shell, around this.
///
/// Not tied to a thread or an actor: its owner uses it from one at a time (the Mac's window: the main thread; the Windows
/// engine: one queue), and hears of its changes through `observe`, on the thread that made them.
public final class SettingsStore {
    /// What changed (`observe`).
    public struct Change: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// `config`: changed here, or read again.
        public static let config = Change(rawValue: 1)
        /// `loadError` or `saveError`.
        public static let status = Change(rawValue: 2)
        /// A key, token or password saved or removed (`saveKey`, …): what `KeyState` shows.
        public static let keys = Change(rawValue: 4)
    }

    /// A Test button's state: Test Connection, the web search's, the Notion link's.
    public enum TestStatus: Equatable, Sendable {
        case idle
        case running
        case passed(String)
        case failed(String)
    }

    /// The settings as shown and changed. A change is only kept in memory until `save` (a settings window saves on each
    /// change, its text fields on Return).
    public var config: Config {
        didSet { if config != oldValue { notify(.config) } }
    }

    /// Why the file couldn't be read: nothing is saved then (`canSave`), and the file stays as it is.
    public private(set) var loadError: String? {
        didSet { if loadError != oldValue { notify(.status) } }
    }

    /// Why the last save failed; nil once one works.
    public private(set) var saveError: String? {
        didSet { if saveError != oldValue { notify(.status) } }
    }

    public let configURL: URL
    /// False for previews and screenshots: nothing is ever written, no key saved or removed.
    public let persists: Bool

    /// Called when "Remember recent questions" is switched off (`setRememberQuestions`), after the config changed: the
    /// shell deletes the questions it keeps.
    public var questionsForgotten: () -> Void = {}

    /// The config as the file has it (read or last written here): a save writes only what differs from it.
    private var written: Config?
    /// When the config file was last read or written here: changed since (an input method's menu, an editor, sync), it
    /// is read again (`reloadIfChanged`).
    private var fileDate: Date?
    private var observers: [Int: (Change) -> Void] = [:]
    private var lastObserver = 0

    /// The settings in the file at `configURL`. A file that can't be read is kept as it is: `loadError` says why, and
    /// nothing is saved over it. `fresh`: a new user's settings, when there is no file yet (`Config.fresh` on the Mac).
    public init(configURL: URL = Config.defaultURL, persists: Bool = true, fresh: (() -> Config)? = nil) {
        self.configURL = configURL
        self.persists = persists
        fileDate = Self.modificationDate(configURL)
        do {
            if let fresh, !FileManager.default.fileExists(atPath: configURL.path) {
                config = fresh()
            } else {
                config = try Config.load(from: configURL)
            }
            written = config
        } catch {
            // Keep the broken file untouched: the window shows the error instead of overwriting it.
            config = .default
            loadError = UIText.describe(error)
        }
    }

    public var canSave: Bool { loadError == nil }

    // MARK: Observing

    /// Calls `handler` after each change, on the thread that made it, until the token is cancelled or released.
    public func observe(_ handler: @escaping (Change) -> Void) -> Observation {
        lastObserver += 1
        observers[lastObserver] = handler
        return Observation(store: self, id: lastObserver)
    }

    /// A handler `observe` calls, until `cancel` (or the token's release).
    public final class Observation {
        private weak var store: SettingsStore?
        private let id: Int

        init(store: SettingsStore, id: Int) {
            self.store = store
            self.id = id
        }

        public func cancel() { store?.observers[id] = nil }

        deinit { cancel() }
    }

    private func notify(_ change: Change) {
        for handler in observers.sorted(by: { $0.key < $1.key }).map(\.value) { handler(change) }
    }

    // MARK: The file

    /// Writes the settings changed since the file was read or last written here, and only those (`AIConfig.writing`),
    /// down to an app's profile and each switch of hiding sensitive information: a value written meanwhile by sync
    /// through iCloud, the Assistant or by hand that hasn't been read yet stays as it is, and so do keys this version
    /// doesn't know. Nothing is written when nothing changed (a window opened, moved through, ⏎ on a field left as it
    /// was, closed). `config` is then the file as it now is.
    public func save() {
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

    /// Something else about saving went wrong (a file the settings make, a jargon list): shown where a save's error is,
    /// until the next save that works.
    public func showSaveError(_ message: String) {
        saveError = message
    }

    /// Reads the config file again if something else changed it, so that it is shown and the next save doesn't put back
    /// what was there before.
    public func reloadIfChanged() {
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

    /// The file as it is now: what was changed and not saved yet saved (a save reads the file back), else the file read
    /// again if something else changed it. Lists that sync through iCloud may change (the commands, the hidden words)
    /// are read this way before an edit, and edited by name, never by an index shown earlier.
    public func refresh() {
        save()
        reloadIfChanged()
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: Lists edited while sync may change them

    /// The hidden-words field saved (Return, or leaving the page): its edit since it showed `shown`
    /// (`RedactionSettings.edited`) on the words as the file has them now. The list to show.
    @discardableResult
    public func saveWords(field text: String, shown: [String]) -> [String] {
        refresh()
        let list = RedactionSettings.edited(config.redaction.customWords, field: text, shown: shown)
        guard list != config.redaction.customWords else { return list }
        config.redaction.customWords = list
        save()
        return config.redaction.customWords
    }

    /// The custom commands an edit of the one named `original` (nil: one being added) is checked against.
    public func otherCommands(than original: String?) -> [CustomCommand] {
        CustomCommand.others(than: original, in: config.customCommands)
    }

    /// A command editor's Save: `command` in place of the one named `original` wherever it is now (of two of that name,
    /// the one the editor opened on, `shown`), else added (it was deleted elsewhere meanwhile). Not saved when another
    /// command has its name by now: false, and the editor stays open saying so.
    @discardableResult
    public func saveCommand(_ command: CustomCommand, editing original: String?, shown: CustomCommand? = nil) -> Bool {
        refresh()
        guard let list = CustomCommand.saving(command, as: original, in: config.customCommands, shown: shown) else { return false }
        config.customCommands = list
        save()
        return true
    }

    /// A Delete dialog's Delete: the command named `name`, wherever it is now; one only (of two of that name, the one the
    /// dialog was opened on, `shown`).
    public func deleteCommand(named name: String, shown: CustomCommand? = nil) {
        refresh()
        let list = CustomCommand.removing(name, from: config.customCommands, shown: shown)
        guard list != config.customCommands else { return }
        config.customCommands = list
        save()
    }

    // MARK: Switches with more to them

    /// The interface language (`Config.uiLanguage`; nil: follow the system), switched at once and saved.
    public func setUILanguage(_ language: String?) {
        UIText.choice = language  // before the change is published, so that what shows it redraws in it
        config.uiLanguage = language
        save()
    }

    /// The menu bar icon's switch, saved (the Mac shows or removes the icon).
    public func setMenuBarIcon(_ on: Bool) {
        config.menuBarIcon = on
        save()
    }

    /// "Remember recent questions" switched: off deletes the ones kept (`questionsForgotten`). Only from the switch: a
    /// config read again with it off (the Assistant turned it off, and may still undo that) keeps them. Not saved here:
    /// the caller saves, as for any switch.
    public func setRememberQuestions(_ on: Bool) {
        config.rememberQuestions = on
        guard !on else { return }
        questionsForgotten()
    }

    /// Fuzzy pinyin's pairs (`FuzzyPinyin.pairs` ids; the ones this version doesn't know are left out), saved. The shell
    /// applies them to its Rime.
    public func setFuzzyPinyin(_ ids: [String]) {
        config.fuzzyPinyin = FuzzyPinyin.known(ids)
        save()
    }

    /// What turning fuzzy pinyin on picks: the pairs most often mixed up.
    public static let fuzzyDefaults = ["z-zh", "c-ch", "s-sh", "en-eng", "in-ing"]

    // MARK: Rewrite styles

    public func isStyleOn(_ style: RewriteStyle) -> Bool {
        RewriteStyle.resolve(config.rewriteStyles).contains(style)
    }

    public func setStyle(_ style: RewriteStyle, on: Bool) {
        guard on != isStyleOn(style) else { return }
        config.rewriteStyles = SessionText.toggled(style.name, in: config.rewriteStyles)
        save()
    }

    /// The styles in this order (dragged in a window): the candidates follow it.
    public func setStyleOrder(_ names: [String]) {
        config.rewriteStyles = names
        save()
    }

    // MARK: Languages

    // Not saved here: a window saves on each change of the lists, as for any switch.

    /// Adds an input language (its pack, if it needs one, is the shell's to download first).
    public func addInputLanguage(_ language: Language) {
        config.inputLanguages.append(language)
        config.normalizeLanguages()
    }

    /// Removes an input language; the next one becomes the default, or English when it was the only one.
    public func removeInputLanguage(_ language: Language) {
        let languages = config.inputLanguages
        config.setOrder(languages == [language] ? [Language.english] : SessionText.toggled(language, in: languages))
    }

    /// A language whose pack is deleted: out of the input languages first (English when it was the only one).
    public func removePackLanguage(_ language: Language) {
        let languages = config.inputLanguages
        if languages.contains(language) {
            config.setOrder(languages == [language] ? [Language.english] : languages.filter { $0 != language })
        }
    }

    /// Moves an input language one place earlier (-1) or later (1); the first is the default.
    public func moveInputLanguage(_ language: Language, by step: Int) {
        var languages = config.inputLanguages
        guard let index = languages.firstIndex(of: language), languages.indices.contains(index + step) else { return }
        languages.swapAt(index, index + step)
        config.setOrder(languages)
    }

    /// The input language new text fields start in: first in the list.
    public func makeDefaultInput(_ language: Language) {
        config.setOrder([language] + config.inputLanguages.filter { $0 != language })
    }

    public func addOutputLanguage(_ language: OutputLanguage) {
        config.outputLanguages.append(language)
    }

    /// Removes an added output language (one always stays); the next one is then in use.
    public func removeOutputLanguage(_ language: OutputLanguage) {
        guard config.outputLanguages.count > 1 else { return }
        config.setOrder(config.outputLanguages.filter { $0 != language })
    }

    // MARK: Providers

    /// The settings of an API-key provider as stored (unset fields use the defaults).
    public func providerSettings(_ provider: Provider) -> ProviderSettings {
        switch provider {
        case .anthropic: return config.anthropic
        case .gemini: return config.gemini
        case .openai: return config.openai
        case .bedrock, .hosted, .apple: return ProviderSettings()
        }
    }

    public func setProviderSettings(_ settings: ProviderSettings, for provider: Provider) {
        switch provider {
        case .anthropic: config.anthropic = settings
        case .gemini: config.gemini = settings
        case .openai: config.openai = settings
        case .bedrock, .hosted, .apple: return
        }
        save()
    }

    /// One string setting of a provider, as typed: trimmed, and an empty one stored as `empty` (nil: unset, so that the
    /// default applies and is never written as if typed). Nothing is written unless the value changes.
    public func setProviderField(_ provider: Provider, _ key: WritableKeyPath<ProviderSettings, String?>, to value: String,
                                 empty: String? = nil) {
        var settings = providerSettings(provider)
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let new = trimmed.isEmpty ? empty : trimmed
        guard settings[keyPath: key] != new else { return }
        settings[keyPath: key] = new
        setProviderSettings(settings, for: provider)
    }

    // MARK: Keys

    // Each saves to or removes from the platform's secret store (`APIKeys`), never the config file: a key works even
    // when the file is broken. An empty or blank key does nothing: it never removes the one saved (that's Remove…,
    // confirmed). Each returns what went wrong, as the window shows it (nil: done, or nothing to do).

    /// Saves the provider's API key, tied to the base URL it is saved with: it isn't sent to another one set later.
    public func saveKey(_ key: String, for provider: Provider) -> String? {
        guard persists, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        defer { notify(.keys) }
        do {
            try APIKeys.save(key, for: provider, host: HTTPProviders.host(of: config.settings(for: provider)))
            return nil
        } catch {
            return tr("无法保存到钥匙串：", "Couldn't save to the keychain: ") + UIText.describe(error)
        }
    }

    /// Removes the provider's API key: Remove Key…, confirmed.
    public func removeKey(_ provider: Provider) -> String? {
        guard persists else { return nil }
        defer { notify(.keys) }
        do {
            try APIKeys.remove(provider)
            Self.log.notice("Settings: the \(provider.rawValue) key removed (Remove Key…, confirmed)")
            return nil
        } catch {
            return tr("无法从钥匙串里删除：", "Couldn't remove it from the keychain: ") + UIText.describe(error)
        }
    }

    /// Saves the web search key (`WebSearch`).
    public func saveSearchKey(_ key: String) -> String? {
        guard persists, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        defer { notify(.keys) }
        do {
            try WebSearch.saveKey(key)
            return nil
        } catch {
            return tr("无法保存到钥匙串：", "Couldn't save to the keychain: ") + UIText.describe(error)
        }
    }

    public func removeSearchKey() -> String? {
        guard persists else { return nil }
        defer { notify(.keys) }
        do {
            try WebSearch.removeKey()
            return nil
        } catch {
            return tr("无法从钥匙串里删除：", "Couldn't remove it from the keychain: ") + UIText.describe(error)
        }
    }

    /// Saves the Notion token, sent to api.notion.com only.
    public func saveNotionToken(_ token: String) -> String? {
        guard persists, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        defer { notify(.keys) }
        do {
            try NotionAPI.saveToken(token)
            return nil
        } catch {
            return tr("无法保存到钥匙串：", "Couldn't save to the keychain: ") + UIText.describe(error)
        }
    }

    public func removeNotionToken() -> String? {
        guard persists else { return nil }
        defer { notify(.keys) }
        do {
            try NotionAPI.removeToken()
            return nil
        } catch {
            return tr("无法从钥匙串里删除：", "Couldn't remove it from the keychain: ") + UIText.describe(error)
        }
    }

    /// Where each provider's key comes from and the last 4 characters kept with a saved one (`APIKeys.keyEnding`: the
    /// key itself isn't read). The first look may ask the user's shell for its variables: not on a thread that draws.
    public static func keyStates(_ providers: [Provider] = Provider.allCases.filter { $0 != .bedrock },
                                 lookup: (Provider) -> APIKeys.Source = { APIKeys.source($0) })
        -> (sources: [Provider: APIKeys.Source], endings: [Provider: String]) {
        let sources = Dictionary(uniqueKeysWithValues: providers.map { ($0, lookup($0)) })
        let endings = Dictionary(uniqueKeysWithValues: providers.compactMap { provider in
            APIKeys.keyEnding(account: provider.rawValue).map { (provider, $0) }
        })
        return (sources, endings)
    }

    // MARK: Notes (@note)

    /// The "Save to" picker. A folder without one chosen yet asks for it first (`chooseFolder`; nil, cancelled: as it
    /// was). False when nothing changed.
    @discardableResult
    public func setNotesDestination(_ destination: NoteSettings.Destination, chooseFolder: () -> String?) -> Bool {
        guard destination != config.notes.destination else { return false }
        if destination == .folder, config.notes.folderURL == nil {
            guard let path = chooseFolder() else { return false }
            config.notes.folder = path
        }
        config.notes.destination = destination
        save()
        return true
    }

    /// The folder notes go to (as "~/…" when it is in the home folder), and saved to from now on.
    public func setNotesFolder(_ path: String) {
        config.notes.folder = path
        config.notes.destination = .folder
        save()
    }

    // MARK: Script extensions

    /// Whether a command (its id) or a bundle (its name) is on.
    public func isEnabled(_ id: String) -> Bool { !config.disabledExtensions.contains(id) }

    public func setEnabled(_ id: String, _ on: Bool) {
        config.disabledExtensions.removeAll { $0 == id }
        if !on { config.disabledExtensions.append(id) }
        save()
    }

    /// A preference's value as saved (not a password's), else its default.
    public func preference(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference) -> String {
        config.extensionPreferences[bundle.name]?[preference.name] ?? preference.defaultValue ?? ""
    }

    /// Saves a preference: a password in the secret store (an empty one does nothing: `removePassword` removes it),
    /// anything else in the config file. What went wrong (nil: nothing).
    public func setPreference(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference, _ value: String) -> String? {
        guard persists else { return nil }
        guard preference.kind == .password else {
            config.extensionPreferences[bundle.name, default: [:]][preference.name] = value
            save()
            return nil
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        defer { notify(.keys) }
        do {
            try APIKeys.save(value, account: ExtensionBundle.Preference.keychainAccount(bundle: bundle.name, name: preference.name),
                             label: "AllInOneIME: \(bundle.title) – \(preference.title)")
            return nil
        } catch {
            return tr("没有存进钥匙串：", "Couldn't save it in the keychain: ") + error.localizedDescription
        }
    }

    /// Removes a password preference from the secret store: Remove…, confirmed.
    public func removePassword(_ bundle: ExtensionBundle, _ preference: ExtensionBundle.Preference) -> String? {
        guard persists, preference.kind == .password else { return nil }
        defer { notify(.keys) }
        do {
            try APIKeys.remove(account: ExtensionBundle.Preference.keychainAccount(bundle: bundle.name, name: preference.name))
            return nil
        } catch {
            return tr("没能从钥匙串里删除：", "Couldn't remove it from the keychain: ", key: "extensionKey.removeFailed")
                + error.localizedDescription
        }
    }

    /// Adds a folder of extensions (as "~/…": `ExtensionStore.abbreviated`); one found and hidden is shown again.
    public func addExtensionFolder(_ path: String) {
        if !config.extensionFolders.contains(path) { config.extensionFolders.append(path) }
        config.hiddenExtensionFolders.removeAll { $0 == path }
        save()
    }

    /// An added folder is removed from the list; a found one is hidden (or shown again).
    public func removeExtensionFolder(_ folder: ExtensionStore.Folder) {
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
    }

    // MARK: Plugins

    /// Removes an installed plugin (its folder). What went wrong (nil: done).
    public func uninstall(_ plugin: InstalledPlugin) -> String? {
        guard persists else { return nil }
        do {
            try PluginStore.uninstall(plugin)
            return nil
        } catch {
            return tr("无法删除插件：", "Couldn't remove the plugin: ") + error.localizedDescription
        }
    }

    /// What the plugin library offers this version (its index downloaded and checked), or why it couldn't be opened.
    public static func libraryEntries(_ library: PluginLibrary) async -> Result<[PluginIndex.Entry], LibraryError> {
        do {
            return .success(library.available(try await library.fetchIndex()))
        } catch {
            return .failure(LibraryError(message: tr("无法打开插件库：", "Couldn't open the plugin library: ") + UIText.describe(error)))
        }
    }

    /// Installs or updates a plugin from the library (downloaded and checked against the signed index). What went wrong
    /// (nil: done); the shell then has its command list pick it up.
    public static func install(_ entry: PluginIndex.Entry, from library: PluginLibrary) async -> String? {
        do {
            try await library.install(entry)
            return nil
        } catch {
            return tr("无法安装 @\(entry.name)：", "Couldn't install @\(entry.name): ") + UIText.describe(error)
        }
    }

    /// Why the plugin library couldn't be opened, as shown.
    public struct LibraryError: Error, Equatable, Sendable {
        public var message: String
    }

    // MARK: Apps

    /// Changes the profile of `app` (added if it has none, under the key it has in another case if so) and saves. One
    /// that sets nothing stays in the list while it is shown, and isn't saved.
    public func changeProfile(_ app: String, _ change: (inout AppProfile) -> Void) {
        config.changeProfile(for: app, change)
        save()
    }

    public func removeProfile(_ app: String) {
        config.removeProfile(for: app)
        save()
    }

    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "settings")
}
