import AllInOneIMECore
import AllInOneIMERime
import Foundation

/// The language packs on this Mac (`LanguagePackStore`) and their downloads, for the settings and the
/// input controllers. Starts librime once the Chinese pack is there (at launch, or when a download
/// finishes); until then Chinese isn't an input mode and controllers type English (`LatinEngine`).
@MainActor
final class LanguagePackManager: ObservableObject {
    static let shared = LanguagePackManager()

    enum State: Equatable {
        case notInstalled
        /// The share downloaded so far (0…1); nil while asking the library for its index.
        case downloading(Double?)
        case installed(LanguagePackRecord)
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    var store = LanguagePackStore()
    var library = LanguagePackLibrary()
    private var downloads: [String: Task<Void, Never>] = [:]

    private init() {}

    func state(_ pack: LanguagePack) -> State {
        if let state = states[pack.id] { return state }
        return store.installed(pack).map(State.installed) ?? .notInstalled
    }

    func isInstalled(_ pack: LanguagePack) -> Bool {
        // The self-test's own data (`--rime-data`) stands in for the Chinese pack.
        if pack == .chinesePinyin, RimeDirectories.override != nil { return true }
        if case .installed = state(pack) { return true }
        return false
    }

    /// Whether `language` can be typed now: English always, others once their pack is installed.
    func isUsable(_ language: Language) -> Bool {
        LanguagePack.for(language).map(isInstalled) ?? true
    }

    /// `languages` without those whose pack isn't installed (yet); English when none is left.
    func usable(_ languages: [Language]) -> [Language] {
        let usable = languages.filter(isUsable)
        return usable.isEmpty ? [.english] : usable
    }

    /// Reads the packs folder again (a pack may have been installed by the installer or another process).
    func refresh() {
        for pack in LanguagePack.catalog where downloads[pack.id] == nil { states[pack.id] = nil }
        objectWillChange.send()
    }

    // MARK: Launch

    /// At launch: starts the engines of the installed packs. An upgrade from a version that bundled the
    /// Chinese data, whose user typed Chinese, without the pack (the installer takes the old app's copy
    /// over; `make install` and a missing copy end up here): downloads it once, unasked, so pinyin comes back.
    func launch() {
        if isInstalled(.chinesePinyin) {
            RimeStartup.start()
            return
        }
        guard LanguagePackMigration.wantsChinese(rimeUserFolder: RimeDirectories.user) else { return }
        keepChineseInSettings()
        log.notice("Chinese pack missing for a user who had Chinese: downloading it")
        download(.chinesePinyin)
    }

    /// A user from before packs with no settings file typed Chinese by default; a new install now starts
    /// in English, so their settings are written with Chinese as it was.
    private func keepChineseInSettings() {
        guard !FileManager.default.fileExists(atPath: Config.defaultURL.path) else { return }
        var config = Config.fresh
        config.setOrder([Language.chinese, .english])
        do { try config.write() } catch {
            log.error("could not write the settings: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Download and remove

    /// Starts downloading `pack` (nothing if it's already on its way); `done` runs once it's installed
    /// and its engine is starting.
    func download(_ pack: LanguagePack, done: (@MainActor () -> Void)? = nil) {
        guard downloads[pack.id] == nil else { return }
        states[pack.id] = .downloading(nil)
        let library = library
        downloads[pack.id] = Task { [weak self] in
            do {
                let record = try await library.install(pack) { share in
                    Task { @MainActor in
                        guard let self, case .downloading = self.states[pack.id] else { return }
                        self.states[pack.id] = .downloading(share)
                    }
                }
                guard let self else { return }
                self.downloads[pack.id] = nil
                self.states[pack.id] = .installed(record)
                log.notice("language pack \(pack.id, privacy: .public) \(record.version, privacy: .public) installed")
                self.startEngine(pack)
                done?()
            } catch {
                guard let self else { return }
                self.downloads[pack.id] = nil
                let cancelled = Task.isCancelled || (error as? LanguagePackError) == .cancelled
                self.states[pack.id] = cancelled ? nil : .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
                log.error("language pack \(pack.id, privacy: .public) not installed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func cancel(_ pack: LanguagePack) {
        downloads[pack.id]?.cancel()
    }

    /// Deletes an installed pack. librime keeps what it has loaded until the input method restarts, but
    /// nothing uses it any more: its language is no longer usable.
    func remove(_ pack: LanguagePack) {
        do {
            try store.remove(pack)
            states[pack.id] = nil
            log.notice("language pack \(pack.id, privacy: .public) removed")
        } catch {
            states[pack.id] = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
    }

    private func startEngine(_ pack: LanguagePack) {
        if pack == .chinesePinyin { RimeStartup.start() }
        NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
    }
}

/// Starts librime on the Chinese pack: its Lua linked to the app's, the fuzzy pinyin patch written, and a
/// full check when the pack changed since the last deployment. Deploys again if it was running already
/// (the pack was installed anew in the same folder).
enum RimeStartup {
    private static let deployedKey = "rimeDeployedPack"

    @MainActor
    static func start() {
        guard let shared = RimeDirectories.shared else {
            log.fault("Chinese pack missing; pinyin input disabled")
            return
        }
        let store = LanguagePackStore()
        do {
            try store.linkCode(.chinesePinyin, from: RimeDirectories.code)
        } catch {
            log.error("could not link the Rime scripts: \(String(describing: error), privacy: .public)")
        }
        let fuzzy = RimeFuzzy.write(LiveConfig.current.fuzzyPinyin)
        let record = store.installed(.chinesePinyin)
        let deployed = "\(record?.version ?? "?")|\(record?.sha256 ?? record?.source.rawValue ?? "")|\(shared.path)"
        let packChanged = UserDefaults.standard.string(forKey: deployedKey) != deployed
        if RimeService.shared.isStarted {
            RimeService.shared.redeploy()
        } else {
            do {
                try RimeService.shared.start(
                    sharedDataDir: shared, userDataDir: RimeDirectories.user, logDir: RimeDirectories.logs,
                    fullCheck: fuzzy == .written || fuzzy == .removed || packChanged)
                RimeReadinessLogger.shared.start()
            } catch {
                log.fault("could not start Rime: \(String(describing: error), privacy: .public)")
                return
            }
        }
        UserDefaults.standard.set(deployed, forKey: deployedKey)
    }
}
